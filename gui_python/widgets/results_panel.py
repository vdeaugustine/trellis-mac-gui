"""Shows the resolved output files with Reveal-in-Finder / Open actions."""

from __future__ import annotations

import os
import subprocess

from PySide6.QtWidgets import (
    QGroupBox, QHBoxLayout, QLabel, QPushButton, QVBoxLayout, QWidget,
)

_KIND_LABELS = {
    "glb": "3D model (.glb)",
    "obj": "Mesh (.obj)",
    "basecolor": "Base color texture (.png)",
}


def _reveal_in_finder(path: str) -> None:
    subprocess.run(["open", "-R", path], check=False)


def _open_path(path: str) -> None:
    subprocess.run(["open", path], check=False)


class ResultsPanel(QWidget):
    """Hidden until a run completes; lists each output file with actions."""

    def __init__(self, parent=None) -> None:
        super().__init__(parent)
        self._output_dir: str | None = None

        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)

        self.group = QGroupBox("Output")
        self._rows = QVBoxLayout(self.group)
        layout.addWidget(self.group)

        self.open_folder_btn = QPushButton("Open output folder")
        self.open_folder_btn.clicked.connect(self._open_folder)
        layout.addWidget(self.open_folder_btn)

        self.setVisible(False)

    def show_results(self, output_dir: str, outputs: dict[str, str]) -> None:
        self._output_dir = output_dir
        self._clear_rows()

        if not outputs:
            self._rows.addWidget(QLabel("No output files were found."))
        else:
            for kind, path in outputs.items():
                self._rows.addWidget(self._make_row(kind, path))

        self.setVisible(True)

    # --------------------------------------------------------------- helpers

    def _make_row(self, kind: str, path: str) -> QWidget:
        row = QWidget()
        hbox = QHBoxLayout(row)
        hbox.setContentsMargins(0, 0, 0, 0)

        label = QLabel(_KIND_LABELS.get(kind, kind))
        label.setToolTip(path)
        hbox.addWidget(label, 1)

        reveal = QPushButton("Reveal in Finder")
        reveal.clicked.connect(lambda _=False, p=path: _reveal_in_finder(p))
        hbox.addWidget(reveal)

        open_btn = QPushButton("Open")
        open_btn.clicked.connect(lambda _=False, p=path: _open_path(p))
        hbox.addWidget(open_btn)

        return row

    def _open_folder(self) -> None:
        if self._output_dir and os.path.isdir(self._output_dir):
            _open_path(self._output_dir)

    def _clear_rows(self) -> None:
        while self._rows.count():
            item = self._rows.takeAt(0)
            w = item.widget()
            if w is not None:
                w.deleteLater()

    def hide_results(self) -> None:
        self.setVisible(False)
