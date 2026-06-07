"""Manage the per-run output directories under the GUI output base.

Per-run dirs are created by `cli_args.make_output_dir` with the name
`<YYYYMMDD-HHMMSS>-<6 hex>`. This module reports cumulative size and can prune
old runs — but it ONLY ever touches directories that match that exact naming
pattern, so it can never delete something we didn't create.

Pure module — no Qt — so it is unit-testable against a temp tree.
"""

from __future__ import annotations

import os
import re
import shutil
from typing import NamedTuple

# Matches the directory names make_output_dir() produces: 8-6-6 with hex token.
RUN_DIR_RE = re.compile(r"^\d{8}-\d{6}-[0-9a-f]{6}$")


class RunInfo(NamedTuple):
    path: str
    size: int     # bytes
    mtime: float  # seconds since epoch


def _is_run_dir(name: str) -> bool:
    return bool(RUN_DIR_RE.match(name))


def _dir_size(path: str) -> int:
    total = 0
    for root, _dirs, files in os.walk(path):
        for f in files:
            fp = os.path.join(root, f)
            try:
                total += os.path.getsize(fp)
            except OSError:
                pass
    return total


def list_runs(base: str) -> list[RunInfo]:
    """Return our run directories under `base`, newest first. [] if no base."""
    if not os.path.isdir(base):
        return []
    runs: list[RunInfo] = []
    with os.scandir(base) as it:
        for entry in it:
            if entry.is_dir() and _is_run_dir(entry.name):
                try:
                    mtime = entry.stat().st_mtime
                except OSError:
                    mtime = 0.0
                runs.append(RunInfo(entry.path, _dir_size(entry.path), mtime))
    runs.sort(key=lambda r: r.mtime, reverse=True)
    return runs


def total_size(base: str) -> int:
    """Total bytes used by our run directories under `base`."""
    return sum(r.size for r in list_runs(base))


def prune(base: str, keep_last_n: int) -> list[str]:
    """Delete run dirs beyond the `keep_last_n` newest. Returns deleted paths.

    Only deletes directories whose names match RUN_DIR_RE — anything else under
    `base` is left untouched. `keep_last_n` < 0 is treated as 0.
    """
    keep = max(0, keep_last_n)
    runs = list_runs(base)
    to_delete = runs[keep:]
    deleted: list[str] = []
    for run in to_delete:
        # Re-check the basename right before removal as a final safety guard.
        if not _is_run_dir(os.path.basename(run.path)):
            continue
        try:
            shutil.rmtree(run.path)
            deleted.append(run.path)
        except OSError:
            pass
    return deleted


def human_size(num_bytes: int) -> str:
    """Format a byte count as a short human-readable string."""
    value = float(num_bytes)
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if value < 1024 or unit == "TB":
            return f"{value:.0f} {unit}" if unit == "B" else f"{value:.1f} {unit}"
        value /= 1024
    return f"{value:.1f} TB"
