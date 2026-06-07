"""Entry point for the Trellis Studio Python GUI.

Run from the repo root with the project's venv:
    .venv/bin/python -m gui_python.main

Set TRELLIS_GUI_MOCK=1 to exercise the UI against a mock generator (no GPU).
"""

from __future__ import annotations

import sys

from PySide6.QtWidgets import QApplication

from .main_window import MainWindow


def main() -> int:
    app = QApplication(sys.argv)
    app.setApplicationName("Trellis Studio (Python)")
    window = MainWindow()
    window.show()
    return app.exec()


if __name__ == "__main__":
    sys.exit(main())
