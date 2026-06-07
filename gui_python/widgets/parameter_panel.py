"""Generation parameter controls, mirroring the Swift ParameterPanel."""

from __future__ import annotations

import random

from PySide6.QtCore import Signal
from PySide6.QtWidgets import (
    QCheckBox, QComboBox, QFormLayout, QGroupBox, QHBoxLayout, QPushButton,
    QSpinBox, QVBoxLayout, QWidget,
)

from ..cli_args import GenerationParams

# Display label -> CLI value for the pipeline type combo.
_PIPELINE_CHOICES = [
    ("512", "512"),
    ("1024", "1024"),
    ("1024 Cascade", "1024_cascade"),
]
_TEXTURE_CHOICES = [512, 1024, 2048]

_SEED_MIN, _SEED_MAX = 0, 999_999


class ParameterPanel(QWidget):
    """Collects seed, pipeline type, texture options, and step override."""

    # Emitted whenever any control that affects params() changes, so the
    # hardware/headroom readout can update live.
    params_changed = Signal()

    def __init__(self, parent=None) -> None:
        super().__init__(parent)
        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)

        # --- Presets -------------------------------------------------------
        presets = QHBoxLayout()
        for name, handler in (
            ("Fast Draft", self._preset_fast),
            ("Balanced", self._preset_balanced),
            ("Max Quality", self._preset_max),
        ):
            btn = QPushButton(name)
            btn.clicked.connect(handler)
            presets.addWidget(btn)
        layout.addLayout(presets)

        # --- Parameters ----------------------------------------------------
        group = QGroupBox("Generation Settings")
        form = QFormLayout(group)

        seed_row = QHBoxLayout()
        self.seed_spin = QSpinBox()
        self.seed_spin.setRange(_SEED_MIN, _SEED_MAX)
        self.seed_spin.setValue(42)
        randomize = QPushButton("🎲")
        randomize.setToolTip("Randomize seed")
        randomize.setFixedWidth(40)
        randomize.clicked.connect(self.randomize_seed)
        seed_row.addWidget(self.seed_spin, 1)
        seed_row.addWidget(randomize)
        form.addRow("Seed", _wrap(seed_row))

        self.pipeline_combo = QComboBox()
        for label, value in _PIPELINE_CHOICES:
            self.pipeline_combo.addItem(label, value)
        form.addRow("Pipeline", self.pipeline_combo)

        self.no_texture_check = QCheckBox("Geometry only (no texture)")
        self.no_texture_check.toggled.connect(self._on_no_texture_toggled)
        form.addRow("", self.no_texture_check)

        self.texture_combo = QComboBox()
        for size in _TEXTURE_CHOICES:
            self.texture_combo.addItem(f"{size} px", size)
        self.texture_combo.setCurrentIndex(_TEXTURE_CHOICES.index(1024))
        form.addRow("Texture size", self.texture_combo)

        steps_row = QHBoxLayout()
        self.steps_check = QCheckBox("Override steps")
        self.steps_check.toggled.connect(self._on_steps_toggled)
        self.steps_spin = QSpinBox()
        self.steps_spin.setRange(1, 50)
        self.steps_spin.setValue(12)
        self.steps_spin.setEnabled(False)
        steps_row.addWidget(self.steps_check)
        steps_row.addWidget(self.steps_spin, 1)
        form.addRow("Steps", _wrap(steps_row))

        layout.addWidget(group)

        # Emit params_changed when any param-affecting control changes.
        self.pipeline_combo.currentIndexChanged.connect(self._emit_changed)
        self.texture_combo.currentIndexChanged.connect(self._emit_changed)
        self.no_texture_check.toggled.connect(self._emit_changed)
        self.steps_check.toggled.connect(self._emit_changed)
        self.steps_spin.valueChanged.connect(self._emit_changed)
        self.seed_spin.valueChanged.connect(self._emit_changed)

    # --------------------------------------------------------------- actions

    def _emit_changed(self, *_args) -> None:
        self.params_changed.emit()

    def randomize_seed(self) -> None:
        self.seed_spin.setValue(random.randint(1, _SEED_MAX))

    def _on_no_texture_toggled(self, checked: bool) -> None:
        self.texture_combo.setEnabled(not checked)

    def _on_steps_toggled(self, checked: bool) -> None:
        self.steps_spin.setEnabled(checked)

    def _preset_fast(self) -> None:
        self._apply_preset("512", 512, no_texture=False)

    def _preset_balanced(self) -> None:
        self._apply_preset("1024", 1024, no_texture=False)

    def _preset_max(self) -> None:
        self._apply_preset("1024_cascade", 2048, no_texture=False)

    def _apply_preset(self, pipeline_value: str, texture_size: int,
                      no_texture: bool) -> None:
        idx = self.pipeline_combo.findData(pipeline_value)
        if idx >= 0:
            self.pipeline_combo.setCurrentIndex(idx)
        self.no_texture_check.setChecked(no_texture)
        tex_idx = self.texture_combo.findData(texture_size)
        if tex_idx >= 0:
            self.texture_combo.setCurrentIndex(tex_idx)

    # ----------------------------------------------------------------- model

    def params(self) -> GenerationParams:
        return GenerationParams(
            seed=self.seed_spin.value(),
            pipeline_type=self.pipeline_combo.currentData(),
            texture_size=self.texture_combo.currentData(),
            no_texture=self.no_texture_check.isChecked(),
            steps=self.steps_spin.value() if self.steps_check.isChecked() else None,
        )

    def set_enabled(self, enabled: bool) -> None:
        self.setEnabled(enabled)


def _wrap(layout) -> QWidget:
    """Wrap a layout in a QWidget so it can be used as a QFormLayout row field."""
    w = QWidget()
    w.setLayout(layout)
    layout.setContentsMargins(0, 0, 0, 0)
    return w
