#!/usr/bin/env python3
"""
Pre-download all TRELLIS.2-4B model weights with progress.
Outputs JSON lines so the Swift GUI can parse progress.
"""
import sys
import os
import json

os.environ.setdefault("PYTORCH_ENABLE_MPS_FALLBACK", "1")
os.environ.setdefault("ATTN_BACKEND", "sdpa")
os.environ.setdefault("SPARSE_ATTN_BACKEND", "sdpa")
os.environ.setdefault("SPARSE_CONV_BACKEND", "none")

def send(data):
    print(json.dumps(data), flush=True)


def main():
    from huggingface_hub import hf_hub_download, snapshot_download

    repo_id = "microsoft/TRELLIS.2-4B"

    # First, download the pipeline config to discover all checkpoint paths
    send({"stage": "config", "status": "downloading", "message": "Fetching pipeline config…"})
    try:
        config_path = hf_hub_download(repo_id, "pipeline.json")
    except Exception as e:
        send({"stage": "config", "status": "error", "message": str(e)})
        sys.exit(1)

    with open(config_path) as f:
        config = json.load(f)

    model_paths = config["args"]["models"]
    send({"stage": "config", "status": "done", "total_models": len(model_paths)})

    # Build the list of files to download
    files_to_download = []
    for name, path in model_paths.items():
        # Paths starting with the repo_id are from a different repo — handle separately
        if path.startswith("microsoft/"):
            # Full HF path like "microsoft/TRELLIS-image-large/ckpts/..."
            parts = path.split("/")
            other_repo = f"{parts[0]}/{parts[1]}"
            model_name = "/".join(parts[2:])
            files_to_download.append({
                "name": name,
                "repo": other_repo,
                "json": f"{model_name}.json",
                "safetensors": f"{model_name}.safetensors",
            })
        else:
            # Relative path like "ckpts/shape_dec_..."
            files_to_download.append({
                "name": name,
                "repo": repo_id,
                "json": f"{path}.json",
                "safetensors": f"{path}.safetensors",
            })

    # Also download image conditioning models referenced in the config
    extra_models = []
    args = config.get("args", {})
    image_cond = args.get("image_cond_model", {}).get("args", {})
    rembg = args.get("rembg_model", {}).get("args", {})

    if "repo_id" in image_cond:
        extra_models.append(("image_cond", image_cond["repo_id"]))
    if "repo_id" in rembg:
        extra_models.append(("rembg", rembg["repo_id"]))

    total = len(files_to_download) + len(extra_models)
    completed = 0
    errors = []

    for item in files_to_download:
        name = item["name"]
        repo = item["repo"]
        send({
            "stage": "download",
            "status": "downloading",
            "model": name,
            "repo": repo,
            "current": completed,
            "total": total,
            "message": f"Downloading {name}…",
        })

        for file_key in ["json", "safetensors"]:
            filename = item[file_key]
            try:
                hf_hub_download(repo, filename)
            except Exception as e:
                err_msg = f"{name}/{file_key}: {str(e)[:200]}"
                errors.append(err_msg)
                send({
                    "stage": "download",
                    "status": "error",
                    "model": name,
                    "repo": repo,
                    "file": file_key,
                    "message": err_msg,
                })

        completed += 1
        send({
            "stage": "download",
            "status": "done",
            "model": name,
            "repo": repo,
            "current": completed,
            "total": total,
        })

    for label, extra_repo in extra_models:
        send({
            "stage": "download",
            "status": "downloading",
            "model": label,
            "repo": extra_repo,
            "current": completed,
            "total": total,
            "message": f"Downloading {extra_repo}…",
        })
        try:
            snapshot_download(extra_repo)
            completed += 1
            send({
                "stage": "download",
                "status": "done",
                "model": label,
                "repo": extra_repo,
                "current": completed,
                "total": total,
                "message": f"Downloaded: {extra_repo}",
            })
        except Exception as e:
            err_msg = str(e)[:200]
            if "401" in err_msg or "403" in err_msg or "gated" in err_msg.lower():
                errors.append(f"{label}: Gated repo — request access at https://huggingface.co/{extra_repo}")
                send({
                    "stage": "download",
                    "status": "gated",
                    "model": label,
                    "repo": extra_repo,
                    "message": f"Access required: https://huggingface.co/{extra_repo}",
                })
            else:
                errors.append(f"{label}: {err_msg}")
                send({
                    "stage": "download",
                    "status": "error",
                    "model": label,
                    "message": err_msg,
                })

    # Summary
    if errors:
        send({
            "stage": "complete",
            "status": "partial",
            "errors": errors,
            "message": f"Downloaded with {len(errors)} warning(s).",
        })
    else:
        send({
            "stage": "complete",
            "status": "done",
            "message": "All model weights downloaded successfully.",
        })


if __name__ == "__main__":
    main()
