"""Opt-in Apple Silicon performance tweaks for the TRELLIS.2 pipeline.

Everything here is gated behind the TRELLIS_FAST=1 environment variable and is
OFF by default, because it changes GPU numerics and needs validation on real
renders (compare meshes for NaNs / quality across several images). The GUI
exposes this as a "Fast mode (experimental)" setting.

Currently applies:
  - fp16 cast of the flow/DiT torso blocks. The decoders already ship fp16
    (`*_fp16` checkpoints); the flow models ship bf16, and on Apple GPUs fp16 is
    the natively-accelerated type. Each flow model exposes `convert_to(dtype)`,
    which converts only the transformer torso and leaves the numerically
    sensitive norms/embeddings alone. README/audit note the velocity field can
    occasionally exceed fp16 range — if you see NaNs / empty meshes with fast
    mode on, turn it off.

Kept intentionally small and isolated so it's easy to A/B and easy to revert.
"""

from __future__ import annotations

import os

# Flow/DiT model keys in pipeline.models (see trellis2_image_to_3d.py:31-39).
_FLOW_MODEL_KEYS = (
    "sparse_structure_flow_model",
    "shape_slat_flow_model_512",
    "shape_slat_flow_model_1024",
    "tex_slat_flow_model_512",
    "tex_slat_flow_model_1024",
)


def fast_mode_enabled() -> bool:
    return os.environ.get("TRELLIS_FAST") == "1"


def apply_fast_mode(pipeline, log=print) -> None:
    """Cast the flow/DiT torsos to fp16 when TRELLIS_FAST=1. No-op otherwise.

    Safe to call unconditionally right after the pipeline loads; it only acts
    when the env flag is set and silently skips models that aren't present or
    don't expose `convert_to`.
    """
    if not fast_mode_enabled():
        return
    try:
        import torch
    except Exception:
        return

    models = getattr(pipeline, "models", {}) or {}
    converted = []
    for key in _FLOW_MODEL_KEYS:
        model = models.get(key)
        convert = getattr(model, "convert_to", None)
        if model is None or convert is None:
            continue
        try:
            convert(torch.float16)
            converted.append(key)
        except Exception as exc:  # never let a perf tweak break a real run
            log(f"[fast] skipped {key}: {exc}")
    if converted:
        log(f"[fast] TRELLIS_FAST=1 — flow models cast to fp16: "
            f"{', '.join(converted)}")
