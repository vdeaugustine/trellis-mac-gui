"""Classify a failed `generate.py` run into an actionable error.

Pure module — no Qt, no GPU — so it is trivially unit-testable. The detection
substrings are deliberately the SAME ones the Swift app uses, so this wrapper
reports the same diagnoses as the native front-end:

  - MPS OOM     -> GUI/.../BackendBundle/daemon_memory.py:110-115
  - HF gated    -> GUI/.../BackendBundle/download_weights.py:140
  - watchdog    -> generate.py:135-138 (exit code 2 + exception signatures)
"""

from __future__ import annotations

from typing import NamedTuple


class ErrorInfo(NamedTuple):
    kind: str               # stable identifier (see classify table)
    title: str              # short dialog title
    message: str            # one or two sentences of explanation
    suggestions: list[str]  # concrete next steps (may be empty)


# Suggestion blocks reused across kinds.
_SAFER_SETTINGS = [
    "Use pipeline type 512 instead of 1024 / 1024 Cascade.",
    "Lower the texture size (e.g. 1024 instead of 2048), or use Geometry only.",
    "Close memory-heavy apps and other windows, then retry.",
]
_WATCHDOG_EXTRA = [
    "Run headless: close the lid / unplug external displays and retry.",
    "Enable Watchdog-safe mode in Settings (sets MTL_CAPTURE_ENABLED=1).",
]


def _haystack(*parts: str) -> str:
    return "\n".join(p for p in parts if p).lower()


def classify(exit_code: int, stdout_tail: str, stderr_tail: str) -> ErrorInfo:
    """Map a non-zero run to a structured, actionable ErrorInfo.

    `exit_code` is the process exit code (137 / negative => killed by signal).
    `stdout_tail` / `stderr_tail` are the last lines of each stream.
    """
    out = (stdout_tail or "").lower()
    both = _haystack(stdout_tail, stderr_tail)

    # 1. Missing input image — generate.py prints "Error: <path> not found".
    if exit_code == 1 and "not found" in out and "error" in out:
        return ErrorInfo(
            "missing_image",
            "Image not found",
            "generate.py could not find the input image.",
            ["Re-select the image and try again."],
        )

    # 2. Hugging Face gated / auth failure (same signature as download_weights.py).
    if any(s in both for s in (
            "cannot access gated", "gated repo", "gated", " 401", "401 client",
            "403 client", "repository not found", "unauthorized")):
        return ErrorInfo(
            "hf_gated",
            "Hugging Face access required",
            "Downloading the model weights failed because of Hugging Face "
            "authentication or gated-repo access.",
            [
                "Add your Hugging Face token in Settings.",
                "Visit the model pages and accept access: "
                "microsoft/TRELLIS.2-4B, facebook/dinov3-vitl16-pretrain-lvd1689m, "
                "briaai/RMBG-2.0.",
            ],
        )

    # 3. Network problems reaching Hugging Face.
    if any(s in both for s in (
            "failed to resolve", "name or service not known", "temporary failure",
            "connection refused", "connection error", "connection aborted",
            "timed out", "max retries exceeded", "network is unreachable")):
        return ErrorInfo(
            "no_network",
            "Network problem",
            "Could not reach Hugging Face to download model weights.",
            [
                "Check your internet connection / VPN and retry.",
                "The first run downloads ~15 GB of weights.",
            ],
        )

    # 4. Disk full.
    if any(s in both for s in (
            "no space left on device", "disk quota exceeded", "errno 28")):
        return ErrorInfo(
            "disk_full",
            "Disk is full",
            "The run failed because the disk ran out of space.",
            [
                "Free up space and retry.",
                "Model weights need ~15 GB; each run's output is ~100-400 MB.",
                "Use 'Clean old runs' to remove past outputs.",
            ],
        )

    # 5. MPS out-of-memory (same signature as daemon_memory.is_mps_oom).
    if "mps backend out of memory" in both or ("mps" in both and "out of memory" in both):
        return ErrorInfo(
            "mps_oom",
            "Out of GPU memory",
            "The Apple GPU ran out of unified memory during generation.",
            list(_SAFER_SETTINGS),
        )

    # 6. GPU watchdog killed a long Metal kernel (empty mesh downstream).
    if exit_code == 2 or any(s in both for s in (
            "non-zero size", "bvh needs at least 8 triangles", "empty mesh",
            "kiogpucommandbuffercallbackerrorimpactinginteractivity")):
        return ErrorInfo(
            "watchdog",
            "GPU watchdog stopped the render",
            "macOS killed a long-running GPU kernel before the mesh finished. "
            "This is common under display load or with the heaviest settings.",
            _SAFER_SETTINGS + _WATCHDOG_EXTRA,
        )

    # 7. Killed by the OS (137 = 128+9 SIGKILL, or negative signal code) —
    #    typically the kernel out-of-memory killer.
    if exit_code == 137 or exit_code < 0:
        return ErrorInfo(
            "oom_killed",
            "Process was killed",
            "The generation process was killed by the operating system, "
            "most likely because the machine ran out of memory.",
            list(_SAFER_SETTINGS),
        )

    # 8. Anything else.
    return ErrorInfo(
        "generic",
        f"Generation failed (exit code {exit_code})",
        "The generation process exited with an error. See the log for details.",
        ["Open the log (Show log) to see the full output."],
    )
