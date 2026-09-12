"""Periodic progress messages for long TRELLIS pipeline load steps."""

import threading
import time

from daemon_transport import send_response


class PipelineLoadHeartbeat:
    """Emit elapsed-time progress while a blocking load step runs."""

    def __init__(self, message, current, total, phase, detail=None, interval=5):
        self.message = message
        self.current = current
        self.total = total
        self.phase = phase
        self.detail = detail
        self.interval = interval
        self._started_at = None
        self._stop_event = threading.Event()
        self._thread = None

    def __enter__(self):
        self._started_at = time.monotonic()
        self._thread = threading.Thread(target=self._run, daemon=True)
        self._thread.start()
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        self._stop_event.set()
        if self._thread is not None:
            self._thread.join(timeout=1)

    def _run(self):
        while not self._stop_event.wait(self.interval):
            elapsed = int(time.monotonic() - self._started_at)
            send_response({
                "stage": "loadingPipeline",
                "status": "step",
                "current": self.current,
                "total": self.total,
                "phase": self.phase,
                "detail": self.detail,
                "step_elapsed_s": elapsed,
                "message": f"{self.message} ({elapsed}s elapsed)",
            })
