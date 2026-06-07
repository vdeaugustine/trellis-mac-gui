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
    finished_err = Signal(int, str)  # non-zero exit code + recent-log tail
    cancelled = Signal()             # user-initiated cancel completed
    failed_to_start = Signal(str)    # executable / script missing, etc.

    def __init__(self, parent: Optional[QObject] = None) -> None:
        super().__init__(parent)
        self._proc: Optional[QProcess] = None
        self._stdout_buf = ""
        self._stderr_buf = ""
        self._tail: list[str] = []
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

    def start(self, argv: list[str], hf_token: Optional[str] = None) -> None:
        self._stdout_buf = ""
        self._stderr_buf = ""
        self._tail = []
        self._cancelling = False

        proc = QProcess(self)
        proc.setProgram(VENV_PYTHON)
        proc.setArguments([target_script(), *argv])
        proc.setWorkingDirectory(REPO_ROOT)
        proc.setProcessEnvironment(self._build_env(hf_token))
        proc.setProcessChannelMode(QProcess.SeparateChannels)

        proc.readyReadStandardOutput.connect(self._on_stdout)
        proc.readyReadStandardError.connect(self._on_stderr)
        proc.finished.connect(self._on_finished)
        proc.errorOccurred.connect(self._on_error)

        self._proc = proc
        proc.start()

    def cancel(self) -> None:
        if self._proc is None or self._proc.state() == QProcess.NotRunning:
            return
        self._cancelling = True
        self._proc.terminate()          # SIGTERM
        if not self._proc.waitForFinished(2000):
            self._proc.kill()           # SIGKILL fallback

    # ------------------------------------------------------------- env / read

    def _build_env(self, hf_token: Optional[str]) -> QProcessEnvironment:
        """Mirror DaemonRuntimeEnvironment.make() from the Swift app."""
        env = QProcessEnvironment.systemEnvironment()
        env.insert("PYTHONUNBUFFERED", "1")
        env.insert("PYTORCH_ENABLE_MPS_FALLBACK", "1")
        # Metal validation can abort PyTorch/MPS kernels; disable it.
        env.insert("MTL_DEBUG_LAYER", "0")
        env.insert("MTL_SHADER_VALIDATION", "0")
        env.insert("METAL_DEVICE_WRAPPER_TYPE", "0")
        if hf_token:
            env.insert("HF_TOKEN", hf_token)
        # Intentionally do NOT set SPARSE_CONV_BACKEND — generate.py auto-detects.
        return env

    def _on_stdout(self) -> None:
        assert self._proc is not None
        chunk = bytes(self._proc.readAllStandardOutput()).decode("utf-8", "replace")
        self._stdout_buf += chunk
        while "\n" in self._stdout_buf:
            line, self._stdout_buf = self._stdout_buf.split("\n", 1)
            self._record_tail(line)
            self.stdout_line.emit(line)

    def _on_stderr(self) -> None:
        assert self._proc is not None
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
                self._record_tail(line)
                self.stderr_line.emit(line)

    def _record_tail(self, line: str) -> None:
        self._tail.append(line)
        if len(self._tail) > _TAIL_LINES:
            del self._tail[:-_TAIL_LINES]

    # --------------------------------------------------------------- finished

    def _on_finished(self, code: int, _status) -> None:
        # Flush any trailing partial line from each buffer.
        for buf_name in ("_stdout_buf", "_stderr_buf"):
            buf = getattr(self, buf_name)
            if buf.strip():
                self._record_tail(buf)
                (self.stdout_line if buf_name == "_stdout_buf"
                 else self.stderr_line).emit(buf)
            setattr(self, buf_name, "")

        if self._cancelling:
            self.cancelled.emit()
        elif code == 0:
            self.finished_ok.emit(code)
        else:
            self.finished_err.emit(code, "\n".join(self._tail))

    def _on_error(self, err) -> None:
        if err == QProcess.FailedToStart:
            self.failed_to_start.emit(
                f"Could not launch:\n{VENV_PYTHON}\n\nRun ./setup.sh in the repo root.")
