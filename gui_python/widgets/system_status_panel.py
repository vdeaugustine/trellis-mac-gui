"""Always-visible hardware + headroom readout.

Shows: chip · total RAM · estimated peak for the CURRENT settings · verdict ·
display count. Chip/RAM are cached once; only the cheap estimate recomputes when
parameters change. Display count is probed lazily (a ~1s system call) and only
on the explicit 'Refresh displays' click, never on the parameter hot path.
"""

from __future__ import annotations

from PySide6.QtWidgets import (
    QGroupBox, QHBoxLayout, QLabel, QPushButton, QVBoxLayout, QWidget,
)

from .. import output_store
from .. import system_info
from ..cli_args import GenerationParams

_VERDICT_MARK = {
    "comfortable": "✓ comfortable",
    "tight": "tight",
    "risky": "⚠ risky",
    "unknown": "—",
}


class SystemStatusPanel(QWidget):
    def __init__(self, initial_params: GenerationParams, parent=None) -> None:
        super().__init__(parent)
        # Invariant facts — read once.
        self._chip = system_info.chip_name()
        self._ram = system_info.total_ram_bytes()
        self._displays: int | None = None  # probed lazily

        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        group = QGroupBox("System")
        box = QVBoxLayout(group)

        self.summary = QLabel()
        self.summary.setWordWrap(True)
        self.summary.setTextFormat(self.summary.textFormat())  # rich auto-detect
        box.addWidget(self.summary)

        row = QHBoxLayout()
        self.refresh_btn = QPushButton("Refresh displays")
        self.refresh_btn.clicked.connect(self._refresh_displays)
        row.addWidget(self.refresh_btn)
        row.addStretch(1)
        box.addLayout(row)

        layout.addWidget(group)

        self._last_params = initial_params
        self.update_for_params(initial_params)

    def update_for_params(self, params: GenerationParams) -> None:
        """Recompute only the estimate/verdict (cheap) and re-render."""
        self._last_params = params
        a = system_info.assess_memory(params, total_ram=self._ram)
        mark = _VERDICT_MARK.get(a.verdict, "—")
        ram_txt = (output_store.human_size(self._ram) if self._ram > 0
                   else "unknown")
        peak_txt = output_store.human_size(a.estimated_peak)
        disp = ""
        if self._displays is not None:
            disp = f" · Displays: {self._displays}"
            if self._displays > 1:
                disp += " (external)"
        self.summary.setText(
            f"{self._chip} · {ram_txt} unified · "
            f"est. peak ~{peak_txt} {mark}{disp}")

    def _refresh_displays(self) -> None:
        self._displays = system_info.display_count(refresh=True)
        self.update_for_params(self._last_params)
