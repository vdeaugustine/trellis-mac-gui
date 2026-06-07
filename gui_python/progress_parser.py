"""Best-effort parsing of `generate.py` text output into UI progress.

`generate.py` prints unstructured milestones to stdout and tqdm bars to stderr;
there is no structured protocol. We map known lines to a coarse, monotonic
progress fraction plus a friendly stage label, and pull "x/y" out of tqdm frames
for an in-phase hint. The raw log remains the source of truth.

Pure module — no Qt, no GPU — so it is trivially unit-testable.
"""

from __future__ import annotations

import re
from typing import NamedTuple, Optional, Union


class Milestone(NamedTuple):
    label: str
    fraction: float


# Ordered milestones. Each entry is (matcher, label, fraction); matcher is either
# a substring (case-sensitive `in` test) or a compiled regex (`.search`).
_MILESTONES: list[tuple[Union[str, re.Pattern[str]], str, float]] = [
    ("Loading pipeline",                  "Loading pipeline…",   0.02),
    (re.compile(r"^Loaded in"),           "Pipeline loaded",     0.10),
    ("Device: MPS",                       "Moved to MPS",        0.12),
    (re.compile(r"^Input:"),              "Image loaded",        0.14),
    ("Generating 3D model",               "Sampling…",           0.16),
    (re.compile(r"^Mesh:"),               "Mesh extracted",      0.70),
    ("Baking PBR textures",               "Baking textures…",    0.75),
    ("UV unwrapping",                     "UV unwrapping…",      0.80),
    (re.compile(r"Saved:.*\.glb"),        "Saved GLB",           0.90),
    (re.compile(r"Saved:.*\.obj"),        "Saved OBJ",           0.95),
    (re.compile(r"^Total time"),          "Done",                1.00),
]

_TQDM_RE = re.compile(r"(\d+)\s*/\s*(\d+)")


def parse_line(line: str) -> Optional[Milestone]:
    """Map a stdout line to a coarse milestone, or None if it matches nothing."""
    for matcher, label, fraction in _MILESTONES:
        if isinstance(matcher, str):
            if matcher in line:
                return Milestone(label, fraction)
        elif matcher.search(line):
            return Milestone(label, fraction)
    return None


def parse_tqdm(line: str) -> Optional[tuple[int, int]]:
    """Pull (current, total) out of a tqdm frame on stderr, if present."""
    m = _TQDM_RE.search(line)
    if not m:
        return None
    current, total = int(m.group(1)), int(m.group(2))
    if total <= 0:
        return None
    return current, total
