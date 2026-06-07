"""Progress bar + stage label + collapsible raw log."""

from __future__ import annotations

from PySide6.QtWidgets import (
    QLabel, QPlainTextEdit, QProgressBar, QPushButton, QVBoxLayout, QWidget,
)

_LOG_MAX_BLOCKS = 2000


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

    # ----------------------------------------------------------------- state

    def reset(self) -> None:
        self.bar.setValue(0)
        self._max_value = 0
        self.set_stage("Starting…")
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

    def append_log(self, line: str) -> None:
        self.log.appendPlainText(line)

    # ---------------------------------------------------------------- toggle

    def _on_toggle_log(self, checked: bool) -> None:
        self.log.setVisible(checked)
        self.log_toggle.setText("Hide log ▾" if checked else "Show log ▸")
