"""Main window: assembles the widgets, owns the GenerationWorker, and maps its
signals into UI state for the core image-to-3D generation flow."""

from __future__ import annotations

import os

from PySide6.QtWidgets import (
    QHBoxLayout, QMainWindow, QMessageBox, QPushButton, QScrollArea, QSplitter,
    QVBoxLayout, QWidget,
)
from PySide6.QtCore import Qt

from . import cli_args
from .generation_worker import GenerationWorker
from . import progress_parser
from .widgets.image_drop_area import ImageDropArea
from .widgets.parameter_panel import ParameterPanel
from .widgets.progress_panel import ProgressPanel
from .widgets.results_panel import ResultsPanel


class MainWindow(QMainWindow):
    def __init__(self) -> None:
        super().__init__()
        self.setWindowTitle("Trellis Studio (Python)")
        self.resize(960, 680)

        self._worker = GenerationWorker(self)
        self._connect_worker()
        self._output_dir: str | None = None
        self._running = False

        self._build_ui()
        self._update_generate_enabled()

    # ------------------------------------------------------------------- UI

    def _build_ui(self) -> None:
        splitter = QSplitter(Qt.Horizontal)

        # Left column: image + parameters + generate button.
        left = QWidget()
        left_layout = QVBoxLayout(left)
        self.image_area = ImageDropArea()
        self.image_area.image_selected.connect(self._on_image_selected)
        left_layout.addWidget(self.image_area, 1)

        self.params = ParameterPanel()
        left_layout.addWidget(self.params)

        self.generate_btn = QPushButton("Generate")
        self.generate_btn.clicked.connect(self._on_generate_clicked)
        left_layout.addWidget(self.generate_btn)

        # Right column: progress + results (scrollable).
        right = QWidget()
        right_layout = QVBoxLayout(right)
        self.progress = ProgressPanel()
        right_layout.addWidget(self.progress)
        self.results = ResultsPanel()
        right_layout.addWidget(self.results)
        right_layout.addStretch(1)

        right_scroll = QScrollArea()
        right_scroll.setWidgetResizable(True)
        right_scroll.setWidget(right)

        splitter.addWidget(left)
        splitter.addWidget(right_scroll)
        splitter.setStretchFactor(0, 1)
        splitter.setStretchFactor(1, 1)

        container = QWidget()
        layout = QHBoxLayout(container)
        layout.addWidget(splitter)
        self.setCentralWidget(container)

    # -------------------------------------------------------------- worker

    def _connect_worker(self) -> None:
        self._worker.stdout_line.connect(self._on_stdout)
        self._worker.stderr_line.connect(self._on_stderr)
        self._worker.finished_ok.connect(self._on_finished_ok)
        self._worker.finished_err.connect(self._on_finished_err)
        self._worker.cancelled.connect(self._on_cancelled)
        self._worker.failed_to_start.connect(self._on_failed_to_start)

    # --------------------------------------------------------------- events

    def _on_image_selected(self, _path: str) -> None:
        self._update_generate_enabled()

    def _update_generate_enabled(self) -> None:
        if self._running:
            self.generate_btn.setEnabled(True)   # acts as Cancel
            return
        self.generate_btn.setEnabled(bool(self.image_area.path))

    def _on_generate_clicked(self) -> None:
        if self._running:
            self._worker.cancel()
            return

        problem = GenerationWorker.preflight()
        if problem:
            QMessageBox.critical(self, "Setup required", problem)
            return

        image_path = self.image_area.path
        if not image_path:
            return

        self._output_dir = cli_args.make_output_dir()
        os.makedirs(self._output_dir, exist_ok=True)
        argv = cli_args.build_argv(image_path, self.params.params(), self._output_dir)

        hf_token = os.environ.get("HF_TOKEN") or None

        self._enter_running_state()
        self._worker.start(argv, hf_token=hf_token)

    # --------------------------------------------------- stream → progress

    def _on_stdout(self, line: str) -> None:
        self.progress.append_log(line)
        milestone = progress_parser.parse_line(line)
        if milestone:
            self.progress.set_stage(milestone.label)
            self.progress.set_fraction(milestone.fraction)

    def _on_stderr(self, line: str) -> None:
        self.progress.append_log(line)
        tqdm = progress_parser.parse_tqdm(line)
        if tqdm:
            current, total = tqdm
            # Layer an in-phase hint onto the current stage label.
            base = self.progress.stage_label.text().split("  (")[0]
            self.progress.set_stage(f"{base}  ({current}/{total})")

    # ------------------------------------------------------- worker results

    def _on_finished_ok(self, _code: int) -> None:
        self.progress.complete()
        self.progress.set_stage("Done")
        outputs = cli_args.resolve_outputs(self._output_dir or "")
        self.results.show_results(self._output_dir or "", outputs)
        self._exit_running_state()

    def _on_finished_err(self, code: int, tail: str) -> None:
        if code == 1:
            title, msg = "Image not found", \
                "generate.py could not find the input image."
        elif code == 2:
            title = "GPU watchdog"
            msg = ("The macOS GPU watchdog killed the generation.\n\n" + tail)
        else:
            title = f"Generation failed (exit code {code})"
            msg = tail or "See the log for details."
        self.progress.set_stage(f"Failed (exit {code})")
        QMessageBox.critical(self, title, msg)
        self._exit_running_state()

    def _on_cancelled(self) -> None:
        self.progress.set_stage("Cancelled")
        self._exit_running_state()

    def _on_failed_to_start(self, message: str) -> None:
        self.progress.set_stage("Failed to start")
        QMessageBox.critical(self, "Could not start generation", message)
        self._exit_running_state()

    # ----------------------------------------------------------- run state

    def _enter_running_state(self) -> None:
        self._running = True
        self.params.set_enabled(False)
        self.image_area.setEnabled(False)
        self.results.hide_results()
        self.progress.reset()
        self.generate_btn.setText("Cancel")
        self._update_generate_enabled()

    def _exit_running_state(self) -> None:
        self._running = False
        self.params.set_enabled(True)
        self.image_area.setEnabled(True)
        self.generate_btn.setText("Generate")
        self._update_generate_enabled()

    def closeEvent(self, event) -> None:  # noqa: N802
        if self._worker.is_running():
            self._worker.cancel()
        super().closeEvent(event)
