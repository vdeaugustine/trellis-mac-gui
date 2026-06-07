"""Pure helpers: turn GUI parameters into a `generate.py` argv, manage the
per-run output directory, and resolve the files produced by a run.

No Qt and no GPU imports here so this module is trivially unit-testable.
"""

from __future__ import annotations

import datetime
import os
import uuid
from typing import Optional, TypedDict

# Repo root is the parent of the gui_python package directory.
REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# The CLI writes <output>.glb / <output>.obj / <output>_basecolor.png. We reuse
# the daemon's "output_3d" prefix convention (trellis_daemon.py:133) so output
# naming matches the rest of the project.
OUTPUT_PREFIX = "output_3d"


class GenerationParams(TypedDict, total=False):
    seed: int
    pipeline_type: str          # "512" | "1024" | "1024_cascade"
    texture_size: int           # 512 | 1024 | 2048
    no_texture: bool
    steps: Optional[int]        # None => omit --steps (use pipeline default)


def default_output_base() -> str:
    """Base directory under which per-run output folders are created."""
    return os.path.join(REPO_ROOT, "gui_output")


def make_output_dir(base: Optional[str] = None,
                    timestamp: Optional[str] = None,
                    token: Optional[str] = None) -> str:
    """Return a unique per-run output directory path (NOT yet created).

    `timestamp` / `token` are injectable for deterministic tests. When omitted,
    a wall-clock stamp and a short uuid are used.
    """
    base = base or default_output_base()
    if timestamp is None:
        timestamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    if token is None:
        token = uuid.uuid4().hex[:6]
    return os.path.join(base, f"{timestamp}-{token}")


def build_argv(image_path: str,
               params: GenerationParams,
               output_dir: str) -> list[str]:
    """Build the argument list passed to `generate.py` (excluding the script).

    Mirrors the CLI contract in generate.py:44-66. `--texture-size` is omitted
    when `no_texture` is set, and `--steps` is omitted unless explicitly set
    (passing it always overrides the pipeline JSON default).
    """
    output_prefix = os.path.join(output_dir, OUTPUT_PREFIX)
    argv: list[str] = [
        image_path,
        "--seed", str(params["seed"]),
        "--output", output_prefix,
        "--pipeline-type", str(params["pipeline_type"]),
    ]
    if params.get("no_texture"):
        argv.append("--no-texture")
    else:
        argv += ["--texture-size", str(params["texture_size"])]

    steps = params.get("steps")
    if steps is not None:
        argv += ["--steps", str(steps)]

    return argv


def resolve_outputs(output_dir: str) -> dict[str, str]:
    """Return a mapping of {kind: path} for output files that actually exist."""
    prefix = os.path.join(output_dir, OUTPUT_PREFIX)
    candidates = {
        "glb": prefix + ".glb",
        "obj": prefix + ".obj",
        "basecolor": prefix + "_basecolor.png",
    }
    return {kind: path for kind, path in candidates.items() if os.path.exists(path)}
