"""QProcess wrapper that runs `generate.py` as a subprocess and streams its
output back to the GUI thread via signals.

We use QProcess (not QThread + subprocess) because it is Qt-native: its
readyRead* signals fire on the GUI thread, so widget updates need no locking,
and finished()/errorOccurred() cover success, non-zero exits, and
failed-to-start cleanly. stdout and stderr are kept on Separate channels so the
stdout milestone parser is not corrupted by tqdm carriage-return frames on
stderr.

Set TRELLIS_GUI_MOCK=1 in the environment to run gui_python/mock_generate.py
instead of generate.py — useful for exercising the UI without a GPU run.
"""

from __future__ import annotations

import os
from typing import Optional

from PySide6.QtCore import QObject, QProcess, QProcessEnvironment, Signal

from .cli_args import REPO_ROOT

VENV_PYTHON = os.path.join(REPO_ROOT, ".venv", "bin", "python")
GENERATE_PY = os.path.join(REPO_ROOT, "generate.py")
MOCK_GENERATE_PY = os.path.join(os.path.dirname(os.path.abspath(__file__)), "mock_generate.py")

_TAIL_LINES = 50
# Force-flush a buffer that has grown this large without a line delimiter, so a
# misbehaving child emitting an unbounded line can't grow GUI memory.
_MAX_BUFFER_BYTES = 1 * 1024 * 1024  # 1 MB


def _use_mock() -> bool:
    return os.environ.get("TRELLIS_GUI_MOCK") == "1"


def target_script() -> str:
    """The script the worker will launch (real CLI or the mock test double)."""
    return MOCK_GENERATE_PY if _use_mock() else GENERATE_PY


class GenerationWorker(QObject):
    """Runs one generation subprocess. Reusable: call start() again after a run."""

    stdout_line = Signal(str)        # one logical stdout line
    stderr_line = Signal(str)        # one logical stderr line (tqdm-aware)
    finished_ok = Signal(int)        # exit code 0
    # non-zero exit code + combined tail + stdout-only tail + stderr-only tail
    finished_err = Signal(int, str, str, str)
    cancelled = Signal()             # user-initiated cancel completed
    failed_to_start = Signal(str)    # executable / script missing, etc.

    def __init__(self, parent: Optional[QObject] = None) -> None:
        super().__init__(parent)
        self._proc: Optional[QProcess] = None
        self._stdout_buf = ""
        self._stderr_buf = ""
        self._tail: list[str] = []          # combined, most-recent-last
        self._stdout_tail: list[str] = []   # stdout only
        self._stderr_tail: list[str] = []   # stderr only
        self._cancelling = False

    @staticmethod
    def preflight() -> Optional[str]:
        """Return None if the worker can run, else a human-readable problem."""
        if not os.path.exists(VENV_PYTHON):
            return (f"Python virtual environment not found at:\n{VENV_PYTHON}\n\n"
                    f"Run ./setup.sh in the repo root first.")
        script = target_script()
        if not os.path.exists(script):
            return f"Required script not found:\n{script}"
        return None

    def is_running(self) -> bool:
        return self._proc is not None and self._proc.state() != QProcess.NotRunning

    # ------------------------------------------------------------------ start

    def start(self, argv: list[str], hf_token: Optional[str] = None,
              watchdog_safe: bool = False, sparse_conv_none: bool = False,
              fast_mode: bool = False) -> None:
        # Re-entrancy guard: never spawn a second generation while one runs —
        # two GPU processes contend for MPS memory and are unsafe (README).
        if self.is_running():
            return

        # Free any previous QProcess so they don't accumulate across runs.
        self._dispose_proc()

        self._stdout_buf = ""
        self._stderr_buf = ""
        self._tail = []
        self._stdout_tail = []
        self._stderr_tail = []
        self._cancelling = False

        proc = QProcess(self)
        proc.setProgram(VENV_PYTHON)
        proc.setArguments([target_script(), *argv])
        proc.setWorkingDirectory(REPO_ROOT)
        proc.setProcessEnvironment(
            self._build_env(hf_token, watchdog_safe, sparse_conv_none, fast_mode))
        proc.setProcessChannelMode(QProcess.SeparateChannels)

        proc.readyReadStandardOutput.connect(self._on_stdout)
        proc.readyReadStandardError.connect(self._on_stderr)
        proc.finished.connect(self._on_finished)
        proc.errorOccurred.connect(self._on_error)

        self._proc = proc
        proc.start()

    def _dispose_proc(self) -> None:
        """Disconnect and schedule deletion of the current QProcess, if any."""
        if self._proc is None:
            return
        try:
            self._proc.readyReadStandardOutput.disconnect(self._on_stdout)
            self._proc.readyReadStandardError.disconnect(self._on_stderr)
            self._proc.finished.disconnect(self._on_finished)
            self._proc.errorOccurred.disconnect(self._on_error)
        except (RuntimeError, TypeError):
            pass
        self._proc.deleteLater()
        self._proc = None

    def cancel(self) -> None:
        if self._proc is None or self._proc.state() == QProcess.NotRunning:
            return
        self._cancelling = True
        self._proc.terminate()          # SIGTERM
        if not self._proc.waitForFinished(2000):
            self._proc.kill()           # SIGKILL fallback

    # ------------------------------------------------------------- env / read

    def _build_env(self, hf_token: Optional[str], watchdog_safe: bool = False,
                   sparse_conv_none: bool = False,
                   fast_mode: bool = False) -> QProcessEnvironment:
        """Mirror DaemonRuntimeEnvironment.make() from the Swift app."""
        env = QProcessEnvironment.systemEnvironment()
        env.insert("PYTHONUNBUFFERED", "1")
        env.insert("PYTORCH_ENABLE_MPS_FALLBACK", "1")
        # Metal validation can abort PyTorch/MPS kernels; disable it.
        env.insert("MTL_DEBUG_LAYER", "0")
        env.insert("MTL_SHADER_VALIDATION", "0")
        env.insert("METAL_DEVICE_WRAPPER_TYPE", "0")
        # Cap CPU thread pools for the parallel CPU phases (xatlas UV unwrap,
        # fast_simplification, numpy/scipy in the texture bake). Left uncapped,
        # these libraries each spawn one thread per core and oversubscribe while
        # the GPU work and main thread also need cycles. We respect any value the
        # user already exported. Default = physical cores - 2 (min 4), which
        # keeps headroom without starving the parallel work.
        thread_cap = str(max(4, (os.cpu_count() or 8) - 2))
        for var in ("OMP_NUM_THREADS", "VECLIB_MAXIMUM_THREADS",
                    "MKL_NUM_THREADS", "NUMEXPR_NUM_THREADS"):
            if var not in os.environ:
                env.insert(var, thread_cap)
        if hf_token:
            env.insert("HF_TOKEN", hf_token)
        if watchdog_safe:
            # Metal-debugger mode extends the GPU watchdog timeout (generate.py:111).
            env.insert("MTL_CAPTURE_ENABLED", "1")
        if sparse_conv_none:
            # Slow fallback path — explicit opt-in only. Otherwise generate.py
            # auto-detects (flex_gemm when available).
            env.insert("SPARSE_CONV_BACKEND", "none")
        if fast_mode:
            # Experimental fp16 fast mode (changes GPU numerics; opt-in).
            env.insert("TRELLIS_FAST", "1")
        return env

    def _on_stdout(self) -> None:
        if self._proc is None:
            return
        chunk = bytes(self._proc.readAllStandardOutput()).decode("utf-8", "replace")
        self._stdout_buf += chunk
        while "\n" in self._stdout_buf:
            line, self._stdout_buf = self._stdout_buf.split("\n", 1)
            self._emit_stdout(line)
        self._stdout_buf = self._cap_buffer(self._stdout_buf, self._emit_stdout)

    def _on_stderr(self) -> None:
        if self._proc is None:
            return
        chunk = bytes(self._proc.readAllStandardError()).decode("utf-8", "replace")
        self._stderr_buf += chunk
        # tqdm redraws with '\r'; split on either delimiter to surface each frame.
        while True:
            positions = [p for p in (self._stderr_buf.find("\n"),
                                     self._stderr_buf.find("\r")) if p != -1]
            if not positions:
                break
            idx = min(positions)
            line = self._stderr_buf[:idx]
            self._stderr_buf = self._stderr_buf[idx + 1:]
            if line.strip():
                self._emit_stderr(line)
        self._stderr_buf = self._cap_buffer(self._stderr_buf, self._emit_stderr)

    def _cap_buffer(self, buf: str, emit) -> str:
        """If a line has no delimiter but exceeds the cap, flush it and reset."""
        if len(buf) > _MAX_BUFFER_BYTES:
            emit(buf)
            return ""
        return buf

    def _emit_stdout(self, line: str) -> None:
        self._record_tail(self._stdout_tail, line)
        self._record_tail(self._tail, line)
        self.stdout_line.emit(line)

    def _emit_stderr(self, line: str) -> None:
        self._record_tail(self._stderr_tail, line)
        self._record_tail(self._tail, line)
        self.stderr_line.emit(line)

    @staticmethod
    def _record_tail(tail: list[str], line: str) -> None:
        tail.append(line)
        if len(tail) > _TAIL_LINES:
            del tail[:-_TAIL_LINES]

    # --------------------------------------------------------------- finished

    def _on_finished(self, code: int, _status) -> None:
        # Flush any trailing partial line from each buffer.
        if self._stdout_buf.strip():
            self._emit_stdout(self._stdout_buf)
        if self._stderr_buf.strip():
            self._emit_stderr(self._stderr_buf)
        self._stdout_buf = ""
        self._stderr_buf = ""

        if self._cancelling:
            self.cancelled.emit()
        elif code == 0:
            self.finished_ok.emit(code)
        else:
            self.finished_err.emit(
                code,
                "\n".join(self._tail),
                "\n".join(self._stdout_tail),
                "\n".join(self._stderr_tail),
            )

    def _on_error(self, err) -> None:
        if err == QProcess.FailedToStart:
            self.failed_to_start.emit(
                f"Could not launch:\n{VENV_PYTHON}\n\nRun ./setup.sh in the repo root.")
