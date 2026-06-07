"""Progress bar + stage label + collapsible raw log."""

from __future__ import annotations

from PySide6.QtCore import QTimer
from PySide6.QtWidgets import (
    QLabel, QPlainTextEdit, QProgressBar, QPushButton, QVBoxLayout, QWidget,
)

_LOG_MAX_BLOCKS = 2000
# Flush buffered log lines at most this often. A multi-minute render emits many
# tqdm frames; appending each one separately forces a QPlainTextEdit re-layout
# per line and janks the UI. Buffering + a single appendPlainText per tick keeps
# the panel responsive without losing any output.
_LOG_FLUSH_MS = 100


class ProgressPanel(QWidget):
    """Shows coarse progress, the current stage, and a toggleable raw log.

    The progress bar is monotonic — set_fraction never moves it backwards.
    """

    def __init__(self, parent=None) -> None:
        super().__init__(parent)
        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)

        self.stage_label = QLabel("Idle")
        layout.addWidget(self.stage_label)

        self.bar = QProgressBar()
        self.bar.setRange(0, 1000)
        self.bar.setValue(0)
        self.bar.setTextVisible(False)
        layout.addWidget(self.bar)

        self.log_toggle = QPushButton("Show log ▸")
        self.log_toggle.setCheckable(True)
        self.log_toggle.toggled.connect(self._on_toggle_log)
        layout.addWidget(self.log_toggle)

        self.log = QPlainTextEdit()
        self.log.setReadOnly(True)
        self.log.setMaximumBlockCount(_LOG_MAX_BLOCKS)
        self.log.setVisible(False)
        self.log.setMinimumHeight(160)
        layout.addWidget(self.log)

        self._max_value = 0

        # Buffered log: lines accumulate and flush on a timer (see append_log).
        self._log_buffer: list[str] = []
        self._log_timer = QTimer(self)
        self._log_timer.setInterval(_LOG_FLUSH_MS)
        self._log_timer.timeout.connect(self._flush_log)

    # ----------------------------------------------------------------- state

    def reset(self) -> None:
        self.bar.setValue(0)
        self._max_value = 0
        self.set_stage("Starting…")
        self._log_buffer.clear()
        self.log.clear()

    def set_stage(self, text: str) -> None:
        self.stage_label.setText(text)

    def set_fraction(self, fraction: float) -> None:
        value = max(0, min(1000, int(fraction * 1000)))
        if value > self._max_value:        # monotonic
            self._max_value = value
            self.bar.setValue(value)

    def complete(self) -> None:
        self._max_value = 1000
        self.bar.setValue(1000)
        self._flush_log()

    def append_log(self, line: str) -> None:
        """Queue a log line; the buffer is flushed on a timer (coalesced)."""
        self._log_buffer.append(line)
        if not self._log_timer.isActive():
            self._log_timer.start()

    def flush_log(self) -> None:
        """Flush any buffered log lines immediately (e.g. on run completion)."""
        self._flush_log()

    def _flush_log(self) -> None:
        if self._log_buffer:
            self.log.appendPlainText("\n".join(self._log_buffer))
            self._log_buffer.clear()
        self._log_timer.stop()

    # ---------------------------------------------------------------- toggle

    def _on_toggle_log(self, checked: bool) -> None:
        self.log.setVisible(checked)
        self.log_toggle.setText("Hide log ▾" if checked else "Show log ▸")
