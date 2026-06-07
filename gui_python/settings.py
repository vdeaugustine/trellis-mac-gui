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
_KEY_WATCHDOG_SAFE = "watchdog_safe_mode"


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

    # ---- Watchdog-safe mode ------------------------------------------------

    @property
    def watchdog_safe_mode(self) -> bool:
        # QSettings stores bools as strings on some platforms.
        val = self._s.value(_KEY_WATCHDOG_SAFE, False)
        if isinstance(val, str):
            return val.lower() in ("1", "true", "yes")
        return bool(val)

    @watchdog_safe_mode.setter
    def watchdog_safe_mode(self, value: bool) -> None:
        self._s.setValue(_KEY_WATCHDOG_SAFE, bool(value))
