"""Pipeline loading, model hot-loading, and model pruning."""

import os
import sys
import time

from daemon_hf_cache import (
    TRELLIS_REPO_ID,
    assert_pipeline_assets_cached,
    load_cached_pipeline_config,
    local_hf_cache_only,
)
from daemon_load_heartbeat import PipelineLoadHeartbeat
from daemon_memory import (
    aggressive_mps_cleanup,
    install_mps_cpu_cleanup_hook,
    prune_pipeline_models,
    release_pipeline_memory,
)
from daemon_transport import send_response


_torch = None
_pil_image = None

LOAD_TOTAL_STEPS = 8
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
    t0 = time.time()
    _send_load_step(
        status="started",
        current=0,
        message="Preparing pipeline loader",
        phase="prepare",
        detail=f"pipeline={pipeline_type}",
        backend=os.environ.get("SPARSE_CONV_BACKEND", "unknown"),
        started_at=t0,
    )

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
        _send_load_step(
            current=8,
            message="Releasing warmup GPU memory",
            phase="release_memory",
            detail="Moving model weights back to CPU until generation starts",
            started_at=t0,
        )
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
    _send_load_step(
        current=1,
        message="Importing PyTorch package",
        phase="import_torch",
        detail="Loading torch native libraries and MPS bindings",
    )
    sys.stderr.write("[daemon] Step 1/8: Importing torch package...\n")
    sys.stderr.flush()
    with PipelineLoadHeartbeat(
        "Importing PyTorch package",
        current=1,
        total=LOAD_TOTAL_STEPS,
        phase="import_torch",
        detail="Loading torch native libraries and MPS bindings",
    ):
        torch = get_torch()
    _send_load_step(
        current=2,
        message=f"PyTorch ready ({torch.__version__})",
        phase="torch_ready",
        detail="MPS cleanup hook installed",
    )
    sys.stderr.write(f"[daemon] torch {torch.__version__} imported OK\n")
    sys.stderr.flush()
    return torch


def _load_filtered_pipeline(pipeline_type):
    _send_load_step(
        current=3,
        message="Importing TRELLIS pipeline class",
        phase="import_trellis",
        detail="Loading patched TRELLIS.2 modules",
    )
    sys.stderr.write("[daemon] Step 3/8: Importing TRELLIS pipeline...\n")
    sys.stderr.flush()
    with PipelineLoadHeartbeat(
        "Importing TRELLIS pipeline class",
        current=3,
        total=LOAD_TOTAL_STEPS,
        phase="import_trellis",
        detail="Loading patched TRELLIS.2 modules",
    ):
        from trellis2.pipelines.trellis2_image_to_3d import Trellis2ImageTo3DPipeline
    sys.stderr.write("[daemon] TRELLIS pipeline class imported OK\n")
    sys.stderr.flush()

    needed = _models_for_pipeline_type(pipeline_type)
    _check_cached_pipeline_assets(pipeline_type, needed)

    _send_load_step(
        current=5,
        message=f"Loading model weights ({len(needed)} models for {pipeline_type})",
        phase="load_weights",
        detail=", ".join(needed),
    )
    sys.stderr.write(f"[daemon] Step 5/8: Loading weights for {needed}\n")
    sys.stderr.flush()

    original_names = Trellis2ImageTo3DPipeline.model_names_to_load
    try:
        Trellis2ImageTo3DPipeline.model_names_to_load = needed
        with local_hf_cache_only(), PipelineLoadHeartbeat(
            "Loading model weights",
            current=5,
            total=LOAD_TOTAL_STEPS,
            phase="load_weights",
            detail=", ".join(needed),
        ):
            pipeline = Trellis2ImageTo3DPipeline.from_pretrained(TRELLIS_REPO_ID)
    finally:
        Trellis2ImageTo3DPipeline.model_names_to_load = original_names
    sys.stderr.write("[daemon] Weights loaded OK\n")
    sys.stderr.flush()
    return pipeline


def _move_pipeline_to_mps(pipeline, torch):
    _send_load_step(
        current=6,
        message="Preparing Apple GPU runtime",
        phase="prepare_mps",
        detail="Binding pipeline modules to torch.device('mps')",
    )
    sys.stderr.write("[daemon] Step 6/8: Preparing MPS runtime...\n")
    sys.stderr.flush()
    with PipelineLoadHeartbeat(
        "Preparing Apple GPU runtime",
        current=6,
        total=LOAD_TOTAL_STEPS,
        phase="prepare_mps",
        detail="Binding pipeline modules to torch.device('mps')",
    ):
        pipeline.to(torch.device("mps"))
    _send_load_step(
        current=7,
        message="Apple GPU runtime ready",
        phase="mps_ready",
        detail="MPS device accepted pipeline modules",
    )


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
    from trellis2 import models as trellis_models

    config = load_cached_pipeline_config()
    model_paths = config["args"]["models"]

    for name in missing:
        path = model_paths.get(name)
        if not path:
            raise RuntimeError(f"Missing model path for {name}")
        with local_hf_cache_only():
            model = trellis_models.from_pretrained(_model_hf_path(path))
        model.eval()
        pipeline.models[name] = model

    send_response({
        "stage": "loadingPipeline",
        "status": "done",
        "message": "Additional models loaded",
    })


def _check_cached_pipeline_assets(pipeline_type, needed):
    _send_load_step(
        current=4,
        message="Checking local model cache",
        phase="check_cache",
        detail=f"{len(needed)} required checkpoint(s) for {pipeline_type}",
    )
    assert_pipeline_assets_cached(pipeline_type, needed)


def _model_hf_path(path):
    if not path.startswith("ckpts/") and len(path.split("/")) >= 3:
        return path
    return f"{TRELLIS_REPO_ID}/{path}"


def _send_load_step(
    current,
    message,
    phase,
    detail=None,
    status="step",
    backend=None,
    started_at=None,
):
    payload = {
        "stage": "loadingPipeline",
        "status": status,
        "current": current,
        "total": LOAD_TOTAL_STEPS,
        "phase": phase,
        "message": message,
    }
    if detail:
        payload["detail"] = detail
    if backend:
        payload["backend"] = backend
    if started_at:
        payload["elapsed_s"] = round(time.time() - started_at, 2)
    send_response(payload)
