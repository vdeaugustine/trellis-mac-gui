"""Small QSettings-backed configuration store for the GUI.

Exposes exactly three knobs (per the hardening plan):
  - hf_token            : used as HF_TOKEN for the subprocess (falls back to env)
  - output_base         : where per-run output folders are created
  - watchdog_safe_mode  : when True, the worker sets MTL_CAPTURE_ENABLED=1
"""

from __future__ import annotations

import os
from typing import Optional

from PySide6.QtCore import QSettings

from . import cli_args

_ORG = "VinWare"
_APP = "TrellisStudioPython"

_KEY_HF_TOKEN = "hf_token"
_KEY_OUTPUT_BASE = "output_base"
_KEY_WATCHDOG_SAFE = "watchdog_safe_mode"   # legacy bool key (migrated)
_KEY_WATCHDOG_MODE = "watchdog_mode"        # "auto" | "on" | "off"
_KEY_SPARSE_CONV_NONE = "sparse_conv_none"
_KEY_FAST_MODE = "fast_mode"

WATCHDOG_MODES = ("auto", "on", "off")


class AppSettings:
    """Thin typed wrapper over QSettings with sensible fallbacks."""

    def __init__(self) -> None:
        self._s = QSettings(_ORG, _APP)

    # ---- Hugging Face token ------------------------------------------------

    @property
    def hf_token(self) -> str:
        return str(self._s.value(_KEY_HF_TOKEN, "") or "")

    @hf_token.setter
    def hf_token(self, value: str) -> None:
        self._s.setValue(_KEY_HF_TOKEN, value or "")

    def effective_hf_token(self) -> Optional[str]:
        """Token to use for a run: the saved one, else the environment, else None."""
        return self.hf_token or os.environ.get("HF_TOKEN") or None

    # ---- Output base -------------------------------------------------------

    @property
    def output_base(self) -> str:
        return str(self._s.value(_KEY_OUTPUT_BASE, "") or "") \
            or cli_args.default_output_base()

    @output_base.setter
    def output_base(self, value: str) -> None:
        self._s.setValue(_KEY_OUTPUT_BASE, value or "")

    # ---- Watchdog protection mode (auto / on / off) ------------------------

    @property
    def watchdog_mode(self) -> str:
        """One of WATCHDOG_MODES; default 'auto'. Migrates the legacy bool key."""
        val = str(self._s.value(_KEY_WATCHDOG_MODE, "") or "").lower()
        if val in WATCHDOG_MODES:
            return val
        legacy = self._s.value(_KEY_WATCHDOG_SAFE, None)
        if legacy is not None and str(legacy).lower() in ("1", "true", "yes"):
            return "on"
        return "auto"

    @watchdog_mode.setter
    def watchdog_mode(self, value: str) -> None:
        self._s.setValue(
            _KEY_WATCHDOG_MODE, value if value in WATCHDOG_MODES else "auto")

    # ---- Fallback sparse-conv backend (slow path, opt-in) ------------------

    @property
    def sparse_conv_none(self) -> bool:
        val = self._s.value(_KEY_SPARSE_CONV_NONE, False)
        if isinstance(val, str):
            return val.lower() in ("1", "true", "yes")
        return bool(val)

    @sparse_conv_none.setter
    def sparse_conv_none(self, value: bool) -> None:
        self._s.setValue(_KEY_SPARSE_CONV_NONE, bool(value))

    # ---- Experimental fp16 fast mode (TRELLIS_FAST=1) ----------------------

    @property
    def fast_mode(self) -> bool:
        val = self._s.value(_KEY_FAST_MODE, False)
        if isinstance(val, str):
            return val.lower() in ("1", "true", "yes")
        return bool(val)

    @fast_mode.setter
    def fast_mode(self, value: bool) -> None:
        self._s.setValue(_KEY_FAST_MODE, bool(value))
