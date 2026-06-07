#!/usr/bin/env python3
"""Test double for generate.py — prints the same milestone strings and tqdm
frames, writes empty output files, and exits 0. Lets the GUI be exercised end
to end in seconds without a GPU run.

Accepts the same argv as generate.py (only the bits the GUI sends). Honors a few
env toggles to simulate failure paths:
  MOCK_EXIT_CODE=2   -> print the watchdog help text and exit 2
  MOCK_EXIT_CODE=1   -> behave like a missing image (exit 1)
  MOCK_SLEEP=0.02    -> per-step sleep (default 0.02s) to keep runs fast
"""

import argparse
import os
import sys
import time


WATCHDOG_HELP = """
ERROR: The decoder produced an empty mesh.
On Apple Silicon this is almost always the macOS GPU watchdog
killing a long-running Metal kernel in the SLat decoder.

Workarounds, cheapest first:
  1. Run headless — close the lid / unplug external displays.
  2. MTL_CAPTURE_ENABLED=1 python generate.py ...
  3. SPARSE_CONV_BACKEND=none python generate.py ...
"""


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("image")
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--output", default="output_3d")
    parser.add_argument("--pipeline-type", default="512",
                        choices=["512", "1024", "1024_cascade"])
    parser.add_argument("--texture-size", type=int, default=1024,
                        choices=[512, 1024, 2048])
    parser.add_argument("--no-texture", action="store_true")
    parser.add_argument("--steps", type=int, default=None)
    args = parser.parse_args()

    exit_code = int(os.environ.get("MOCK_EXIT_CODE", "0"))
    sleep = float(os.environ.get("MOCK_SLEEP", "0.02"))

    if exit_code == 1:
        print(f"Error: {args.image} not found")
        sys.exit(1)

    def out(msg: str) -> None:
        print(msg, flush=True)

    out("=" * 60)
    out("TRELLIS.2 on Apple Silicon (MOCK)")
    out("=" * 60)
    out("\nLoading pipeline...")
    time.sleep(sleep)
    out("Loaded in 1s")
    out("Device: MPS")
    out(f"Input: {args.image} (1024x1024)")
    out(f"\nGenerating 3D model (pipeline={args.pipeline_type}, seed={args.seed})...")

    # Three sampling phases, emitted as tqdm-style \r frames on stderr.
    total_steps = args.steps if args.steps else 12
    for phase in ("Sampling sparse structure", "Sampling shape slat", "Sampling texture slat"):
        for step in range(1, total_steps + 1):
            sys.stderr.write(f"\r{phase}: {step}/{total_steps}")
            sys.stderr.flush()
            time.sleep(sleep)
        sys.stderr.write("\n")
        sys.stderr.flush()

    if exit_code == 2:
        out(WATCHDOG_HELP)
        sys.exit(2)

    out("\nMesh: 1,248,732 vertices, 2,497,464 triangles")
    out("Generation time: 1.0s")

    glb_path = f"{args.output}.glb"
    obj_path = f"{args.output}.obj"
    os.makedirs(os.path.dirname(glb_path) or ".", exist_ok=True)

    if not args.no_texture:
        out(f"\nBaking PBR textures via KDTree ({args.texture_size}x{args.texture_size})...")
        out("  UV unwrapping with xatlas...")
        time.sleep(sleep)
        # KDTree path also writes a basecolor PNG.
        with open(f"{args.output}_basecolor.png", "w") as f:
            f.write("mock png")

    with open(glb_path, "w") as f:
        f.write("mock glb")
    out(f"Saved: {glb_path}")
    with open(obj_path, "w") as f:
        f.write("mock obj")
    out(f"Saved: {obj_path}")

    out("\nTotal time: 1.0s generation + baking")
    sys.exit(0)


if __name__ == "__main__":
    main()
