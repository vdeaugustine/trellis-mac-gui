"""Main window: assembles the widgets, owns the GenerationWorker, and maps its
signals into UI state for the core image-to-3D generation flow."""

from __future__ import annotations

import os

from PySide6.QtGui import QAction, QKeySequence
from PySide6.QtWidgets import (
    QHBoxLayout, QMainWindow, QMessageBox, QPushButton, QScrollArea, QSplitter,
    QVBoxLayout, QWidget,
)
from PySide6.QtCore import Qt

from . import cli_args
from . import error_classifier
from . import output_store
from . import progress_parser
from .generation_worker import GenerationWorker
from .settings import AppSettings
from .widgets.error_panel import ErrorPanel
from .widgets.image_drop_area import ImageDropArea
from .widgets.parameter_panel import ParameterPanel
from .widgets.progress_panel import ProgressPanel
from .widgets.results_panel import ResultsPanel
from .widgets.settings_dialog import SettingsDialog
from .widgets.storage_panel import StoragePanel


class MainWindow(QMainWindow):
    def __init__(self) -> None:
        super().__init__()
        self.setWindowTitle("Trellis Studio (Python)")
        self.resize(980, 720)

        self._settings = AppSettings()
        self._worker = GenerationWorker(self)
        self._connect_worker()
        self._output_dir: str | None = None
        self._running = False
        # One-time advisory hints we don't want to repeat every run.
        self._heavy_combo_ack = False
        self._first_run_hint_shown = False

        self._build_ui()
        self._build_menu()
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

        # Right column: progress + error + results + storage (scrollable).
        right = QWidget()
        right_layout = QVBoxLayout(right)
        self.progress = ProgressPanel()
        right_layout.addWidget(self.progress)
        self.error_panel = ErrorPanel()
        right_layout.addWidget(self.error_panel)
        self.results = ResultsPanel()
        right_layout.addWidget(self.results)
        self.storage = StoragePanel(self._settings_output_base)
        right_layout.addWidget(self.storage)
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

    def _build_menu(self) -> None:
        settings_action = QAction("Settings…", self)
        settings_action.setShortcut(QKeySequence("Ctrl+,"))
        settings_action.triggered.connect(self._open_settings)
        # On macOS this lands under the app menu automatically (role-based).
        menu = self.menuBar().addMenu("Trellis")
        menu.addAction(settings_action)

    def _settings_output_base(self) -> str:
        return self._settings.output_base

    # -------------------------------------------------------------- worker

    def _connect_worker(self) -> None:
        self._worker.stdout_line.connect(self._on_stdout)
        self._worker.stderr_line.connect(self._on_stderr)
        self._worker.finished_ok.connect(self._on_finished_ok)
        self._worker.finished_err.connect(self._on_finished_err)
        self._worker.cancelled.connect(self._on_cancelled)
        self._worker.failed_to_start.connect(self._on_failed_to_start)

    # --------------------------------------------------------------- events

    def _open_settings(self) -> None:
        dialog = SettingsDialog(self._settings, self)
        if dialog.exec():
            self.storage.refresh()

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

        if not self._run_preflight(image_path):
            return

        output_base = self._settings.output_base
        self._output_dir = cli_args.make_output_dir(base=output_base)
        os.makedirs(self._output_dir, exist_ok=True)
        argv = cli_args.build_argv(image_path, self.params.params(), self._output_dir)

        self._enter_running_state()
        self._worker.start(
            argv,
            hf_token=self._settings.effective_hf_token(),
            watchdog_safe=self._settings.watchdog_safe_mode,
        )

    def _run_preflight(self, image_path: str) -> bool:
        """Cheap up-front checks. Returns False to abort the run."""
        # Hard block: corrupt / unreadable image (catches it before ~100s load).
        image_problem = cli_args.validate_image(image_path)
        if image_problem:
            QMessageBox.critical(self, "Invalid image", image_problem)
            return False

        params = self.params.params()

        # Advisory: free disk space.
        disk = cli_args.check_disk_space(self._settings.output_base)
        if not disk.ok:
            free_txt = (output_store.human_size(disk.free_bytes)
                        if disk.free_bytes >= 0 else "unknown")
            extra = (" The first run also downloads ~15 GB of model weights."
                     if disk.needs_weights else "")
            if not self._confirm(
                    "Low disk space",
                    f"Only {free_txt} free on the output volume.{extra}\n\n"
                    "Continue anyway?"):
                return False

        # Advisory: heaviest combo is most likely to OOM / hit the watchdog.
        if cli_args.is_heavy_combo(params) and not self._heavy_combo_ack:
            if not self._confirm(
                    "Heavy settings",
                    "1024 Cascade + 2048 texture is the heaviest setting "
                    "(~18 GB peak memory) and may run out of memory or hit the "
                    "GPU watchdog on machines with under 24 GB.\n\n"
                    "Continue with these settings?"):
                return False
            self._heavy_combo_ack = True

        # Advisory: first-run gated weights need a token.
        if (not self._first_run_hint_shown
                and not self._settings.effective_hf_token()
                and cli_args.hf_cache_looks_empty()):
            self._first_run_hint_shown = True
            QMessageBox.information(
                self, "Hugging Face token",
                "No Hugging Face token is set and the model weights aren't "
                "cached yet. The gated weights (TRELLIS.2-4B, DINOv3, RMBG-2.0) "
                "need a token — add one in Settings (Cmd+,) if the download "
                "fails with an access error.")
        return True

    def _confirm(self, title: str, text: str) -> bool:
        return QMessageBox.question(
            self, title, text,
            QMessageBox.Yes | QMessageBox.No, QMessageBox.No) == QMessageBox.Yes

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
            base = self.progress.stage_label.text().split("  (")[0]
            self.progress.set_stage(f"{base}  ({current}/{total})")

    # ------------------------------------------------------- worker results

    def _on_finished_ok(self, _code: int) -> None:
        self.progress.complete()
        self.progress.set_stage("Done")
        outputs = cli_args.resolve_outputs(self._output_dir or "")
        self.results.show_results(self._output_dir or "", outputs)
        self.storage.refresh()
        self._exit_running_state()

    def _on_finished_err(self, code: int, tail: str,
                         stdout_tail: str, stderr_tail: str) -> None:
        info = error_classifier.classify(code, stdout_tail, stderr_tail)
        self.progress.set_stage(f"Failed: {info.title}")
        self.error_panel.show_error(info, tail)
        self.storage.refresh()
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
        self.error_panel.hide_error()
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
