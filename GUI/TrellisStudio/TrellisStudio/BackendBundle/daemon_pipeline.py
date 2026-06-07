"""Pipeline loading, model hot-loading, and model pruning."""

import json
import os
import sys
import time

from daemon_memory import (
    aggressive_mps_cleanup,
    install_mps_cpu_cleanup_hook,
    prune_pipeline_models,
    release_pipeline_memory,
)
from daemon_transport import send_response


_torch = None
_pil_image = None

IDLE_TIMEOUT_SECONDS = 30 * 60
APP_SUPPORT_DIR = os.path.expanduser(
    "~/Library/Application Support/com.vinware.trellis-studio"
)
PORT_FILE = os.path.join(APP_SUPPORT_DIR, "daemon.port")
PID_FILE = os.path.join(APP_SUPPORT_DIR, "daemon.pid")


def get_torch():
    """Lazy-import torch and install MPS cleanup hooks once."""
    global _torch
    if _torch is None:
        _torch = __import__("torch")
        install_mps_cpu_cleanup_hook(_torch)
    return _torch


def get_pil_image():
    """Lazy-import PIL.Image."""
    global _pil_image
    if _pil_image is None:
        from PIL import Image
        _pil_image = Image
    return _pil_image


def load_pipeline(args, pipeline_type="512"):
    """Load a TRELLIS pipeline with only models required by pipeline_type."""
    send_response({
        "stage": "loadingPipeline",
        "status": "started",
        "backend": os.environ.get("SPARSE_CONV_BACKEND", "unknown"),
        "message": "Preparing pipeline loader",
    })
    t0 = time.time()

    if args.dry_run:
        time.sleep(0.5)
        send_response({
            "stage": "loadingPipeline",
            "status": "done",
            "elapsed_s": round(time.time() - t0, 2),
            "message": "Pipeline ready (dry-run)",
        })
        return None

    try:
        torch = _import_torch_for_loading()
        pipeline = _load_filtered_pipeline(pipeline_type)
        _move_pipeline_to_mps(pipeline, torch)
        release_pipeline_memory(pipeline, torch)
        elapsed = round(time.time() - t0, 2)
        send_response({
            "stage": "loadingPipeline",
            "status": "done",
            "elapsed_s": elapsed,
            "message": f"Pipeline ready ({elapsed}s)",
        })
        sys.stderr.write(f"[daemon] Pipeline ready in {elapsed}s\n")
        sys.stderr.flush()
        return pipeline
    except Exception as error:
        import traceback
        sys.stderr.write(f"[daemon] PIPELINE LOAD FAILED:\n{traceback.format_exc()}\n")
        sys.stderr.flush()
        send_response({
            "stage": "failed",
            "reason": "load_error",
            "message": f"{type(error).__name__}: {error}",
        })
        raise


def prepare_pipeline_for_type(pipeline, pipeline_type):
    """Keep only model weights needed by the requested pipeline type."""
    if pipeline is None:
        return
    torch = get_torch()
    needed = _models_for_pipeline_type(pipeline_type)
    removed = prune_pipeline_models(pipeline, needed, torch)
    if removed:
        aggressive_mps_cleanup(torch)
        sys.stderr.write(
            f"[daemon] Unloaded unused models for {pipeline_type}: {removed}\n"
        )
        sys.stderr.flush()
        send_response({
            "stage": "loadingPipeline",
            "status": "step",
            "message": f"Unloaded {len(removed)} unused model(s)",
        })
    _ensure_models_loaded(pipeline, pipeline_type)
    aggressive_mps_cleanup(torch)


def _import_torch_for_loading():
    send_response({
        "stage": "loadingPipeline",
        "status": "step",
        "current": 1,
        "total": 4,
        "message": "Importing PyTorch",
    })
    sys.stderr.write("[daemon] Step 1: Importing torch...\n")
    sys.stderr.flush()
    torch = get_torch()
    sys.stderr.write(f"[daemon] torch {torch.__version__} imported OK\n")
    sys.stderr.flush()
    return torch


def _load_filtered_pipeline(pipeline_type):
    send_response({
        "stage": "loadingPipeline",
        "status": "step",
        "current": 2,
        "total": 4,
        "message": "Importing TRELLIS pipeline",
    })
    sys.stderr.write("[daemon] Step 2: Importing TRELLIS pipeline...\n")
    sys.stderr.flush()
    from trellis2.pipelines.trellis2_image_to_3d import Trellis2ImageTo3DPipeline
    sys.stderr.write("[daemon] TRELLIS pipeline class imported OK\n")
    sys.stderr.flush()

    needed = _models_for_pipeline_type(pipeline_type)
    send_response({
        "stage": "loadingPipeline",
        "status": "step",
        "current": 3,
        "total": 4,
        "message": f"Loading model weights ({len(needed)} models for {pipeline_type})",
    })
    sys.stderr.write(f"[daemon] Step 3: Loading weights for {needed}\n")
    sys.stderr.flush()

    original_names = Trellis2ImageTo3DPipeline.model_names_to_load
    try:
        Trellis2ImageTo3DPipeline.model_names_to_load = needed
        pipeline = Trellis2ImageTo3DPipeline.from_pretrained(
            "microsoft/TRELLIS.2-4B"
        )
    finally:
        Trellis2ImageTo3DPipeline.model_names_to_load = original_names
    sys.stderr.write("[daemon] Weights loaded OK\n")
    sys.stderr.flush()
    return pipeline


def _move_pipeline_to_mps(pipeline, torch):
    send_response({
        "stage": "loadingPipeline",
        "status": "step",
        "current": 4,
        "total": 4,
        "message": "Preparing Apple GPU runtime",
    })
    sys.stderr.write("[daemon] Step 4: Preparing MPS runtime...\n")
    sys.stderr.flush()
    pipeline.to(torch.device("mps"))


def _models_for_pipeline_type(pipeline_type):
    base = [
        "sparse_structure_flow_model",
        "sparse_structure_decoder",
        "shape_slat_decoder",
        "tex_slat_decoder",
    ]
    if pipeline_type == "512":
        return base + ["shape_slat_flow_model_512", "tex_slat_flow_model_512"]
    if pipeline_type == "1024":
        return base + ["shape_slat_flow_model_1024", "tex_slat_flow_model_1024"]
    return base + [
        "shape_slat_flow_model_512",
        "shape_slat_flow_model_1024",
        "tex_slat_flow_model_1024",
    ]


def _ensure_models_loaded(pipeline, pipeline_type):
    needed = _models_for_pipeline_type(pipeline_type)
    missing = [name for name in needed if name not in pipeline.models]
    if not missing:
        return

    send_response({
        "stage": "loadingPipeline",
        "status": "started",
        "message": f"Loading {len(missing)} model(s) for {pipeline_type}",
    })
    from huggingface_hub import hf_hub_download
    from trellis2 import models as trellis_models

    config_file = hf_hub_download("microsoft/TRELLIS.2-4B", "pipeline.json")
    with open(config_file, "r") as file:
        model_paths = json.load(file)["args"]["models"]

    for name in missing:
        path = model_paths.get(name)
        if not path:
            raise RuntimeError(f"Missing model path for {name}")
        model = trellis_models.from_pretrained(f"microsoft/TRELLIS.2-4B/{path}")
        model.eval()
        pipeline.models[name] = model

    send_response({
        "stage": "loadingPipeline",
        "status": "done",
        "message": "Additional models loaded",
    })
