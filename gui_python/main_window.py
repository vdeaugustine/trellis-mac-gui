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
from . import system_info
from .generation_worker import GenerationWorker
from .settings import AppSettings
from .widgets.error_panel import ErrorPanel
from .widgets.image_drop_area import ImageDropArea
from .widgets.parameter_panel import ParameterPanel
from .widgets.progress_panel import ProgressPanel
from .widgets.results_panel import ResultsPanel
from .widgets.settings_dialog import SettingsDialog
from .widgets.storage_panel import StoragePanel
from .widgets.system_status_panel import SystemStatusPanel


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
        self._last_run_params: dict | None = None  # what actually ran last
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
        self.params.params_changed.connect(self._on_params_changed)
        left_layout.addWidget(self.params)

        self.generate_btn = QPushButton("Generate")
        self.generate_btn.clicked.connect(self._on_generate_clicked)
        left_layout.addWidget(self.generate_btn)

        # Right column: system readout + progress + error + results + storage.
        right = QWidget()
        right_layout = QVBoxLayout(right)
        self.system_status = SystemStatusPanel(self.params.params())
        right_layout.addWidget(self.system_status)
        self.progress = ProgressPanel()
        right_layout.addWidget(self.progress)
        self.error_panel = ErrorPanel()
        self.error_panel.retry_with_protection.connect(self._retry_with_protection)
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

    def _on_params_changed(self) -> None:
        self.system_status.update_for_params(self.params.params())

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

        params = self.params.params()
        self._launch(image_path, params,
                     watchdog_safe=self._effective_watchdog_safe(params))

    def _launch(self, image_path: str, params: dict, watchdog_safe: bool) -> None:
        """Build the output dir + argv and start the worker for `params`."""
        self._last_run_params = dict(params)
        self._output_dir = cli_args.make_output_dir(base=self._settings.output_base)
        os.makedirs(self._output_dir, exist_ok=True)
        argv = cli_args.build_argv(image_path, params, self._output_dir)

        self._enter_running_state()
        self._worker.start(
            argv,
            hf_token=self._settings.effective_hf_token(),
            watchdog_safe=watchdog_safe,
            sparse_conv_none=self._settings.sparse_conv_none,
        )

    def _effective_watchdog_safe(self, params: dict) -> bool:
        """Decide whether to set MTL_CAPTURE_ENABLED=1 for this run.

        `auto` (default) protects long/heavy renders or runs under display load;
        `on`/`off` are hard overrides. Auto-protecting is what makes high-res
        "just work" without the user touching anything.
        """
        mode = self._settings.watchdog_mode
        if mode == "on":
            return True
        if mode == "off":
            return False
        assessment = system_info.assess_memory(params)
        heavy = (params.get("pipeline_type") in ("1024", "1024_cascade")
                 or assessment.verdict in ("tight", "risky"))
        return heavy or system_info.has_external_display()

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

        # Advisory: real memory headroom for THESE params vs. this machine's
        # actual RAM (psutil-driven) — NOT a hardcoded 24 GB threshold.
        assessment = system_info.assess_memory(params)
        peak_txt = output_store.human_size(assessment.estimated_peak)
        ram_txt = output_store.human_size(assessment.total_ram)

        if assessment.verdict == "risky" and not self._heavy_combo_ack:
            if not self._confirm(
                    "Memory may be insufficient",
                    f"These settings are estimated to peak around {peak_txt} of "
                    f"unified memory, but this Mac has {ram_txt} total — the run "
                    f"may run out of memory.\n\nTo make it fit you can lower the "
                    f"texture size, switch to pipeline 1024 or 512, or use "
                    f"Geometry only. You can also proceed and see how it goes.\n\n"
                    f"Proceed anyway?"):
                return False
            self._heavy_combo_ack = True
        elif assessment.verdict == "tight" and not self._heavy_combo_ack:
            if not self._confirm(
                    "Heavy settings",
                    f"Estimated peak ~{peak_txt} of {ram_txt} unified memory — it "
                    f"should fit, but close memory-heavy apps for headroom. "
                    f"Watchdog protection will be enabled automatically.\n\n"
                    f"Continue?"):
                return False
            self._heavy_combo_ack = True
        # comfortable / unknown: no blocking dialog. (Plenty of headroom — the
        # persistent System panel already shows the verdict + display count.)

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
        info = self._refine_error(info)
        self.progress.set_stage(f"Failed: {info.title}")
        self.error_panel.show_error(info, tail)
        self.storage.refresh()
        self._exit_running_state()

    def _refine_error(self, info):
        """Make memory errors hardware-aware: if the GPU reported OOM but this
        machine had ample RAM for the run, the real culprit is almost certainly
        the watchdog — relabel rather than tell the user to reduce quality."""
        if info.kind == "mps_oom" and self._last_run_params:
            a = system_info.assess_memory(self._last_run_params)
            if a.verdict == "comfortable":
                ram = output_store.human_size(a.total_ram)
                peak = output_store.human_size(a.estimated_peak)
                new_message = (
                    info.message + f" But this Mac has {ram} unified memory and "
                    f"the estimated peak was only ~{peak}, so RAM is unlikely to "
                    f"be the real cause — this is more likely the GPU watchdog "
                    f"under display load.")
                new_suggestions = (error_classifier._WATCHDOG_LEVERS
                                   + list(info.suggestions))
                info = info._replace(message=new_message,
                                     suggestions=new_suggestions)
        return info

    def _retry_with_protection(self) -> None:
        """Re-run the SAME settings with watchdog protection forced on."""
        if self._running or not self._last_run_params:
            return
        image_path = self.image_area.path
        if not image_path:
            return
        self.error_panel.hide_error()
        self._launch(image_path, self._last_run_params, watchdog_safe=True)

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
