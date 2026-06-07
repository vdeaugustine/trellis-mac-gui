"""Shows cumulative output-folder size and offers cleanup of old runs."""

from __future__ import annotations

import subprocess

from PySide6.QtWidgets import (
    QGroupBox, QHBoxLayout, QLabel, QMessageBox, QPushButton, QVBoxLayout,
    QWidget,
)

from .. import output_store

# How many most-recent runs "Clean old runs" keeps.
KEEP_LAST_N = 5


class StoragePanel(QWidget):
    """Displays gui_output size and a guarded 'Clean old runs' action."""

    def __init__(self, output_base_getter, parent=None) -> None:
        super().__init__(parent)
        self._output_base_getter = output_base_getter

        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)

        group = QGroupBox("Output storage")
        box = QVBoxLayout(group)

        self.size_label = QLabel("…")
        box.addWidget(self.size_label)

        row = QHBoxLayout()
        self.open_btn = QPushButton("Open output folder")
        self.open_btn.clicked.connect(self._open_folder)
        self.clean_btn = QPushButton(f"Clean old runs (keep last {KEEP_LAST_N})")
        self.clean_btn.clicked.connect(self._clean)
        row.addWidget(self.open_btn)
        row.addWidget(self.clean_btn)
        box.addLayout(row)

        layout.addWidget(group)
        self.refresh()

    def refresh(self) -> None:
        base = self._output_base_getter()
        runs = output_store.list_runs(base)
        total = sum(r.size for r in runs)
        self.size_label.setText(
            f"{len(runs)} run(s), {output_store.human_size(total)} in\n{base}")
        self.clean_btn.setEnabled(len(runs) > KEEP_LAST_N)

    def _open_folder(self) -> None:
        subprocess.run(["open", self._output_base_getter()], check=False)

    def _clean(self) -> None:
        base = self._output_base_getter()
        runs = output_store.list_runs(base)
        to_remove = max(0, len(runs) - KEEP_LAST_N)
        if to_remove == 0:
            return
        reply = QMessageBox.question(
            self, "Clean old runs",
            f"Delete the {to_remove} oldest run folder(s), keeping the "
            f"{KEEP_LAST_N} most recent?\nThis cannot be undone.",
            QMessageBox.Yes | QMessageBox.No, QMessageBox.No)
        if reply != QMessageBox.Yes:
            return
        deleted = output_store.prune(base, KEEP_LAST_N)
        self.refresh()
        QMessageBox.information(
            self, "Clean old runs", f"Removed {len(deleted)} run folder(s).")
