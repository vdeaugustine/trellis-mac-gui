"""Hardware facts and a memory-headroom assessment for the current settings.

Pure (no Qt, no GPU). Used to make warnings hardware-aware: instead of a
hardcoded "under 24 GB" nag, we compare an estimated peak for the chosen
settings against the machine's *actual* unified memory.

Caching contract:
  - chip_name() is constant per process (@lru_cache).
  - display_count() is a ~1s `system_profiler` call, so it is probed lazily at
    most once and cached; pass refresh=True to re-probe. NEVER call it on a hot
    path (e.g. a parameter-change handler) — read the cached value instead.
"""

from __future__ import annotations

import functools
import os
import subprocess
from typing import NamedTuple, Optional

from .cli_args import GenerationParams

_GB = 1024 ** 3


# --------------------------------------------------------------------- memory

def total_ram_bytes() -> int:
    """Total physical (unified) memory in bytes. 0 means 'unknown'."""
    try:
        import psutil  # lazy import: a missing psutil must not be fatal
        return int(psutil.virtual_memory().total)
    except Exception:
        try:
            return os.sysconf("SC_PHYS_PAGES") * os.sysconf("SC_PAGE_SIZE")
        except (ValueError, OSError, AttributeError):
            return 0


# ----------------------------------------------------------------------- chip

@functools.lru_cache(maxsize=1)
def chip_name() -> str:
    """e.g. 'Apple M4 Max'. Cached; falls back to 'Apple Silicon'."""
    try:
        out = subprocess.run(
            ["sysctl", "-n", "machdep.cpu.brand_string"],
            capture_output=True, text=True, timeout=2, check=True)
        return out.stdout.strip() or "Apple Silicon"
    except Exception:
        return "Apple Silicon"


# -------------------------------------------------------------------- displays

_display_count_cache: Optional[int] = None  # None => not probed yet


def _probe_display_count() -> int:
    try:
        out = subprocess.run(
            ["system_profiler", "SPDisplaysDataType"],
            capture_output=True, text=True, timeout=5, check=True)
        # Each attached display reports a "Resolution:" line.
        count = sum(1 for ln in out.stdout.splitlines() if "Resolution:" in ln)
        return count if count > 0 else 1
    except Exception:
        return 1  # assume the built-in display; never over-warn


def display_count(refresh: bool = False) -> int:
    """Number of attached displays. Cached; ~1s on first probe / refresh."""
    global _display_count_cache
    if refresh or _display_count_cache is None:
        _display_count_cache = _probe_display_count()
    return _display_count_cache


def has_external_display(refresh: bool = False) -> bool:
    return display_count(refresh=refresh) > 1


# ------------------------------------------------------------- peak estimate

# Estimated PEAK unified-memory by pipeline tier (texture bake excluded). The
# only hard anchor is README:142 — the heaviest setting (1024_cascade + 2048)
# peaks ~18 GB. We split that as a 15 GB geometry base + 3 GB texture extra and
# scale lighter tiers down monotonically. These are deliberately rough estimates
# for comfortable/tight/risky triage, NOT exact accounting — tune here as real
# measurements land.
_PIPELINE_BASE_BYTES = {
    "512":           7 * _GB,
    "1024":         12 * _GB,
    "1024_cascade": 15 * _GB,
}
_TEXTURE_EXTRA_BYTES = {
    512:  1 * _GB,
    1024: 2 * _GB,
    2048: 3 * _GB,   # 15 + 3 = 18 GB at cascade+2048 -> matches README:142
}


def estimate_peak_bytes(params: GenerationParams) -> int:
    """Rough peak unified-memory estimate for the given settings."""
    base = _PIPELINE_BASE_BYTES.get(params.get("pipeline_type"), 12 * _GB)
    if params.get("no_texture"):
        return base
    extra = _TEXTURE_EXTRA_BYTES.get(params.get("texture_size"), 2 * _GB)
    return base + extra


# ------------------------------------------------------------- assessment

class MemoryAssessment(NamedTuple):
    estimated_peak: int
    total_ram: int
    headroom_ratio: float   # estimated_peak / total_ram (0.0 if RAM unknown)
    verdict: str            # "comfortable" | "tight" | "risky" | "unknown"


def assess_memory(params: GenerationParams,
                  total_ram: Optional[int] = None) -> MemoryAssessment:
    """Compare the estimated peak against real RAM.

    Thresholds (ratio = peak / total_ram):
      comfortable < 0.5  — ample headroom for the OS, WindowServer, other apps.
      tight  0.5–0.8     — fits, but other apps could push it; worth a heads-up.
      risky  >= 0.8      — estimate approaches total RAM; genuine OOM plausible.
    `total_ram` is injectable so tests don't depend on the host.
    """
    peak = estimate_peak_bytes(params)
    ram = total_ram if total_ram is not None else total_ram_bytes()
    if ram <= 0:
        return MemoryAssessment(peak, 0, 0.0, "unknown")
    ratio = peak / ram
    if ratio < 0.5:
        verdict = "comfortable"
    elif ratio < 0.8:
        verdict = "tight"
    else:
        verdict = "risky"
    return MemoryAssessment(peak, ram, ratio, verdict)
