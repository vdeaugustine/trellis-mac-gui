"""MPS memory cleanup helpers for low-VRAM TRELLIS inference."""

import gc


_cpu_hook_installed = False
_original_module_cpu = None


def install_mps_cpu_cleanup_hook(torch):
    """Clear MPS cache whenever TRELLIS offloads a model back to CPU."""
    global _cpu_hook_installed, _original_module_cpu
    if _cpu_hook_installed:
        return

    _original_module_cpu = torch.nn.Module.cpu

    def cpu_with_mps_cleanup(module):
        result = _original_module_cpu(module)
        empty_mps_cache(torch)
        return result

    cpu_with_mps_cleanup._trellis_mps_cleanup = True
    torch.nn.Module.cpu = cpu_with_mps_cleanup
    _cpu_hook_installed = True


def release_pipeline_memory(pipeline, torch=None):
    """Move all pipeline models to CPU and release cached MPS allocations."""
    if pipeline is not None:
        for model in getattr(pipeline, "models", {}).values():
            try:
                model.cpu()
            except Exception:
                pass
    gc.collect()
    empty_mps_cache(torch)


def prune_pipeline_models(pipeline, needed_names, torch=None):
    """Drop model weights not needed for the next selected pipeline."""
    models = getattr(pipeline, "models", {})
    keep = set(needed_names)
    removed = []
    for name in list(models.keys()):
        if name in keep:
            continue
        model = models.pop(name)
        try:
            model.cpu()
        except Exception:
            pass
        removed.append(name)
        del model
    if removed:
        gc.collect()
        empty_mps_cache(torch)
    return removed


def empty_mps_cache(torch=None):
    """Synchronize and release PyTorch MPS cache when available."""
    if torch is None:
        try:
            torch = __import__("torch")
        except Exception:
            return
    if not _mps_available(torch):
        return
    try:
        if hasattr(torch.mps, "synchronize"):
            torch.mps.synchronize()
        if hasattr(torch.mps, "empty_cache"):
            torch.mps.empty_cache()
    except Exception:
        pass


def synchronize_mps(torch):
    """Synchronize MPS work before long CPU or export phases."""
    if not _mps_available(torch):
        return
    try:
        if hasattr(torch.mps, "synchronize"):
            torch.mps.synchronize()
    except Exception:
        pass


def is_mps_oom(error):
    """Return True when an exception is PyTorch MPS out-of-memory."""
    message = str(error).lower()
    return "mps backend out of memory" in message or (
        "mps" in message and "out of memory" in message
    )


def mps_oom_message(error):
    """Build a concise user-facing MPS OOM message."""
    return (
        "Apple GPU ran out of unified memory. Cached GPU memory was released; "
        "close memory-heavy apps or use pipeline 512, then retry. Original: "
        f"{error}"
    )


def _mps_available(torch):
    backends = getattr(torch, "backends", None)
    mps_backend = getattr(backends, "mps", None)
    return bool(mps_backend and mps_backend.is_available())
