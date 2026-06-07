"""Shows cumulative output-folder size and offers cleanup of old runs."""

from __future__ import annotations

import subprocess

from PySide6.QtCore import QObject, QThread, Signal
from PySide6.QtWidgets import (
    QGroupBox, QHBoxLayout, QLabel, QMessageBox, QPushButton, QVBoxLayout,
    QWidget,
)

from .. import output_store

# How many most-recent runs "Clean old runs" keeps.
KEEP_LAST_N = 5


class _SizeScanWorker(QObject):
    """Runs the (potentially slow) os.walk size scan off the UI thread."""

    done = Signal(int, int)  # (run_count, total_bytes)

    def __init__(self, base: str) -> None:
        super().__init__()
        self._base = base

    def run(self) -> None:
        runs = output_store.list_runs(self._base)
        self.done.emit(len(runs), sum(r.size for r in runs))


class StoragePanel(QWidget):
    """Displays gui_output size and a guarded 'Clean old runs' action.

    The size scan walks every output file, which can be slow with many large
    runs, so it runs on a background thread and the label updates when it lands.
    """

    def __init__(self, output_base_getter, parent=None) -> None:
        super().__init__(parent)
        self._output_base_getter = output_base_getter
        self._thread: QThread | None = None
        self._scan: _SizeScanWorker | None = None

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
        """Kick off a background size scan; the label updates when it finishes."""
        if self._thread is not None:   # a scan is already running; skip
            return
        base = self._output_base_getter()
        self.size_label.setText("Calculating output size…")

        thread = QThread(self)
        scan = _SizeScanWorker(base)
        scan.moveToThread(thread)
        thread.started.connect(scan.run)
        # Update the UI on the worker's signal (delivered to the UI thread since
        # this QObject lives there). Then tear the thread down safely via its own
        # finished signal — never call wait() from inside the slot.
        scan.done.connect(lambda n, t: self._on_scan_done(base, n, t))
        scan.done.connect(thread.quit)
        thread.finished.connect(scan.deleteLater)
        thread.finished.connect(thread.deleteLater)
        thread.finished.connect(self._on_thread_finished)
        self._thread = thread
        self._scan = scan
        thread.start()

    def _on_scan_done(self, base: str, count: int, total: int) -> None:
        self.size_label.setText(
            f"{count} run(s), {output_store.human_size(total)} in\n{base}")
        self.clean_btn.setEnabled(count > KEEP_LAST_N)

    def _on_thread_finished(self) -> None:
        self._thread = None
        self._scan = None

    def shutdown(self) -> None:
        """Block until any in-flight size scan finishes (call on window close)."""
        if self._thread is not None:
            self._thread.quit()
            self._thread.wait(2000)

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
