"""Hugging Face cache checks used before TRELLIS pipeline loading."""

from contextlib import contextmanager
import json
import os


TRELLIS_REPO_ID = "microsoft/TRELLIS.2-4B"


def assert_pipeline_assets_cached(pipeline_type, model_names):
    """Raise a clear error when required pipeline assets are not cached locally."""
    config = load_cached_pipeline_config()
    missing = _missing_model_files(config, model_names)
    missing.extend(_missing_auxiliary_models(config))
    if not missing:
        return

    preview = ", ".join(missing[:5])
    suffix = "" if len(missing) <= 5 else f", +{len(missing) - 5} more"
    raise RuntimeError(
        "Model weights missing from local Hugging Face cache. "
        "Open Settings > Models and run Download Missing before generation. "
        f"Pipeline {pipeline_type} missing: {preview}{suffix}"
    )


def load_cached_pipeline_config():
    """Load TRELLIS pipeline config from local Hugging Face cache only."""
    from huggingface_hub import hf_hub_download

    try:
        config_path = hf_hub_download(
            TRELLIS_REPO_ID,
            "pipeline.json",
            local_files_only=True,
        )
    except Exception as error:
        raise RuntimeError(
            "TRELLIS pipeline config is not cached. "
            "Open Settings > Models and run Download Missing before generation."
        ) from error

    with open(config_path, "r") as file:
        return json.load(file)


@contextmanager
def local_hf_cache_only():
    """Force Hugging Face loads in this process to use local cache only."""
    import huggingface_hub

    previous_offline = os.environ.get("HF_HUB_OFFLINE")
    os.environ["HF_HUB_OFFLINE"] = "1"

    originals = _patch_huggingface_downloads(huggingface_hub)
    try:
        yield
    finally:
        _restore_huggingface_downloads(originals)
        if previous_offline is None:
            os.environ.pop("HF_HUB_OFFLINE", None)
        else:
            os.environ["HF_HUB_OFFLINE"] = previous_offline


def _missing_model_files(config, model_names):
    missing = []
    model_paths = config.get("args", {}).get("models", {})
    for name in model_names:
        path = model_paths.get(name)
        if not path:
            missing.append(f"{name}/config")
            continue
        repo_id, model_name = _split_model_path(path)
        missing.extend(_missing_hf_files(repo_id, name, model_name))
    return missing


def _missing_auxiliary_models(config):
    missing = []
    args = config.get("args", {})
    for label, key in (
        ("image_cond_model", "image_cond_model"),
        ("rembg_model", "rembg_model"),
    ):
        repo_id = args.get(key, {}).get("args", {}).get("repo_id")
        if not repo_id:
            continue
        if not _snapshot_cached(repo_id):
            missing.append(label)
    return missing


def _split_model_path(path):
    parts = path.split("/")
    if _is_external_hf_path(path):
        return f"{parts[0]}/{parts[1]}", "/".join(parts[2:])
    return TRELLIS_REPO_ID, path


def _is_external_hf_path(path):
    return not path.startswith("ckpts/") and len(path.split("/")) >= 3


def _missing_hf_files(repo_id, label, model_name):
    from huggingface_hub import hf_hub_download

    missing = []
    for extension in ("json", "safetensors"):
        filename = f"{model_name}.{extension}"
        try:
            hf_hub_download(repo_id, filename, local_files_only=True)
        except Exception:
            missing.append(f"{label}/{extension}")
    return missing


def _snapshot_cached(repo_id):
    from huggingface_hub import snapshot_download

    try:
        snapshot_download(repo_id, local_files_only=True)
        return True
    except Exception:
        return False


def _patch_huggingface_downloads(huggingface_hub):
    originals = []
    targets = [huggingface_hub]
    file_download = getattr(huggingface_hub, "file_download", None)
    if file_download is not None:
        targets.append(file_download)

    for target in targets:
        originals.extend(_patch_download_attr(target, "hf_hub_download"))
        originals.extend(_patch_download_attr(target, "snapshot_download"))

    return originals


def _patch_download_attr(target, attr):
    original = getattr(target, attr, None)
    if original is None:
        return []

    def cached_download(*args, **kwargs):
        kwargs["local_files_only"] = True
        return original(*args, **kwargs)

    setattr(target, attr, cached_download)
    return [(target, attr, original)]


def _restore_huggingface_downloads(originals):
    for target, attr, original in originals:
        setattr(target, attr, original)
