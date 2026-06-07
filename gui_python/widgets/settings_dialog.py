"""Small curated settings dialog: HF token, output folder, watchdog-safe mode."""

from __future__ import annotations

from PySide6.QtWidgets import (
    QCheckBox, QComboBox, QDialog, QDialogButtonBox, QFileDialog, QFormLayout,
    QHBoxLayout, QLabel, QLineEdit, QPushButton, QVBoxLayout, QWidget,
)

from ..settings import AppSettings

_WATCHDOG_LABELS = [
    ("Auto (recommended)", "auto"),
    ("Always on", "on"),
    ("Off", "off"),
]


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

        # Watchdog protection mode (Auto / On / Off).
        self.watchdog_combo = QComboBox()
        for label, value in _WATCHDOG_LABELS:
            self.watchdog_combo.addItem(label, value)
        idx = self.watchdog_combo.findData(settings.watchdog_mode)
        self.watchdog_combo.setCurrentIndex(idx if idx >= 0 else 0)
        form.addRow("Watchdog protection", self.watchdog_combo)

        # Fallback sparse-conv backend (slow path, opt-in).
        self.sparse_check = QCheckBox(
            "Use slower fallback backend (SPARSE_CONV_BACKEND=none)")
        self.sparse_check.setChecked(settings.sparse_conv_none)
        form.addRow("", self.sparse_check)

        # Experimental fp16 fast mode.
        self.fast_check = QCheckBox(
            "Fast mode (experimental fp16 — faster, validate output quality)")
        self.fast_check.setChecked(settings.fast_mode)
        form.addRow("", self.fast_check)

        layout.addLayout(form)

        hint = QLabel(
            "Watchdog protection sets MTL_CAPTURE_ENABLED=1, which extends the "
            "macOS GPU watchdog timeout. Auto enables it for heavy renders or "
            "when an external display is attached. The token falls back to the "
            "HF_TOKEN environment variable if blank.")
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
        self._settings.watchdog_mode = self.watchdog_combo.currentData()
        self._settings.sparse_conv_none = self.sparse_check.isChecked()
        self._settings.fast_mode = self.fast_check.isChecked()
        self.accept()


def _wrap(layout) -> QWidget:
    w = QWidget()
    w.setLayout(layout)
    layout.setContentsMargins(0, 0, 0, 0)
    return w
