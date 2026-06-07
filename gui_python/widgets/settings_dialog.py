"""Small curated settings dialog: HF token, output folder, watchdog-safe mode."""

from __future__ import annotations

from PySide6.QtWidgets import (
    QCheckBox, QDialog, QDialogButtonBox, QFileDialog, QFormLayout, QHBoxLayout,
    QLabel, QLineEdit, QPushButton, QVBoxLayout, QWidget,
)

from ..settings import AppSettings


class SettingsDialog(QDialog):
    """Edits the three AppSettings knobs. Persists on Save."""

    def __init__(self, settings: AppSettings, parent=None) -> None:
        super().__init__(parent)
        self._settings = settings
        self.setWindowTitle("Settings")
        self.setMinimumWidth(520)

        layout = QVBoxLayout(self)
        form = QFormLayout()

        # Hugging Face token (password echo).
        self.token_edit = QLineEdit(settings.hf_token)
        self.token_edit.setEchoMode(QLineEdit.Password)
        self.token_edit.setPlaceholderText("hf_… (needed for first-run gated weights)")
        form.addRow("Hugging Face token", self.token_edit)

        # Output folder picker.
        folder_row = QHBoxLayout()
        self.output_edit = QLineEdit(settings.output_base)
        browse = QPushButton("Choose…")
        browse.clicked.connect(self._choose_folder)
        folder_row.addWidget(self.output_edit, 1)
        folder_row.addWidget(browse)
        form.addRow("Output folder", _wrap(folder_row))

        # Watchdog-safe mode.
        self.watchdog_check = QCheckBox(
            "Watchdog-safe mode (sets MTL_CAPTURE_ENABLED=1 to extend the GPU "
            "watchdog timeout)")
        self.watchdog_check.setChecked(settings.watchdog_safe_mode)
        form.addRow("", self.watchdog_check)

        layout.addLayout(form)

        hint = QLabel(
            "The token falls back to the HF_TOKEN environment variable if left "
            "blank. Output folder is where each run's files are written.")
        hint.setWordWrap(True)
        hint.setStyleSheet("color: #888;")
        layout.addWidget(hint)

        buttons = QDialogButtonBox(QDialogButtonBox.Save | QDialogButtonBox.Cancel)
        buttons.accepted.connect(self._save)
        buttons.rejected.connect(self.reject)
        layout.addWidget(buttons)

    def _choose_folder(self) -> None:
        path = QFileDialog.getExistingDirectory(
            self, "Choose output folder", self.output_edit.text())
        if path:
            self.output_edit.setText(path)

    def _save(self) -> None:
        self._settings.hf_token = self.token_edit.text().strip()
        base = self.output_edit.text().strip()
        if base:
            self._settings.output_base = base
        self._settings.watchdog_safe_mode = self.watchdog_check.isChecked()
        self.accept()


def _wrap(layout) -> QWidget:
    w = QWidget()
    w.setLayout(layout)
    layout.setContentsMargins(0, 0, 0, 0)
    return w
