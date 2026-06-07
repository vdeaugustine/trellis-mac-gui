"""Pure helpers: turn GUI parameters into a `generate.py` argv, manage the
per-run output directory, and resolve the files produced by a run.

No Qt and no GPU imports here so this module is trivially unit-testable.
"""

from __future__ import annotations

import datetime
import os
import shutil
import uuid
from typing import NamedTuple, Optional, TypedDict

# Repo root is the parent of the gui_python package directory.
REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Default free-space floor for the output volume, and the heaviest combo's
# documented peak (~18 GB unified memory, README:142).
MIN_FREE_BYTES = 1 * 1024 * 1024 * 1024          # 1 GB for per-run outputs
FIRST_RUN_WEIGHTS_BYTES = 15 * 1024 * 1024 * 1024  # ~15 GB weight download

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
    output_obj: bool            # False => pass --no-obj (skip the .obj file)


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

    # output_obj defaults to True (keep the .obj). Only emit the flag to skip.
    if params.get("output_obj", True) is False:
        argv.append("--no-obj")

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


# ----------------------------------------------------------- preflight checks


def is_heavy_combo(params: GenerationParams) -> bool:
    """True for the heaviest settings (most likely to OOM / hit the watchdog).

    1024_cascade + 2048 texture peaks around 18 GB unified memory (README:142).
    """
    return (params.get("pipeline_type") == "1024_cascade"
            and not params.get("no_texture")
            and params.get("texture_size") == 2048)


class DiskStatus(NamedTuple):
    ok: bool          # True if free space is comfortably above the floor
    free_bytes: int
    needs_weights: bool  # True if the HF cache looks empty (first run, ~15 GB)


def hf_cache_dir() -> str:
    """Best-effort path to the Hugging Face hub cache."""
    base = os.environ.get("HF_HOME") or os.path.join(
        os.path.expanduser("~"), ".cache", "huggingface")
    return os.path.join(base, "hub")


def hf_cache_looks_empty() -> bool:
    """True if the HF hub cache is missing/empty (first-run weight download)."""
    cache = hf_cache_dir()
    try:
        return not any(os.scandir(cache))
    except (FileNotFoundError, NotADirectoryError, OSError):
        return True


def check_disk_space(output_base: str,
                     min_bytes: int = MIN_FREE_BYTES) -> DiskStatus:
    """Inspect free space on the volume that will hold outputs.

    Walks up to the nearest existing parent of `output_base` (it may not exist
    yet) so `shutil.disk_usage` succeeds. If weights still need downloading,
    the effective floor includes the ~15 GB first-run download.
    """
    probe = output_base
    while probe and not os.path.exists(probe):
        parent = os.path.dirname(probe)
        if parent == probe:
            break
        probe = parent
    needs_weights = hf_cache_looks_empty()
    try:
        free = shutil.disk_usage(probe or os.path.sep).free
    except OSError:
        # If we can't measure, don't block the user.
        return DiskStatus(True, -1, needs_weights)

    floor = min_bytes + (FIRST_RUN_WEIGHTS_BYTES if needs_weights else 0)
    return DiskStatus(free >= floor, free, needs_weights)


def validate_image(path: str) -> Optional[str]:
    """Return None if `path` is a readable image, else a short problem string.

    Uses Pillow's verify() to catch corrupt/truncated/unsupported files before
    paying the ~100s pipeline load. Pillow is available in the project venv; if
    it somehow isn't, fall back to an existence check rather than blocking.
    """
    if not path or not os.path.exists(path):
        return "The selected image no longer exists."
    if os.path.getsize(path) == 0:
        return "The selected image file is empty."
    try:
        from PIL import Image  # noqa: PLC0415 (lazy: keep module Qt/GPU-free)
    except ImportError:
        return None
    try:
        with Image.open(path) as img:
            img.verify()  # decodes headers / checks integrity without full load
    except Exception as exc:  # PIL raises a variety of types
        return f"The selected file is not a valid image: {exc}"
    return None
