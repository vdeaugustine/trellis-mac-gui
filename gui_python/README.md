# Trellis Studio — Python GUI

A lightweight PySide6 (Qt6) desktop GUI that wraps the existing `generate.py`
CLI. It's a thin convenience layer: pick an image, set parameters with widgets
instead of CLI flags, watch progress, and open the resulting files. The native
Swift app (`GUI/TrellisStudio/`) remains the primary front-end; this is an
interim wrapper.

Each generation runs `generate.py` as a fresh subprocess, so the ~15GB pipeline
cold-loads every run (~100s) and generation takes several minutes total. The
GUI parses `generate.py`'s text output for coarse progress; the raw log
(toggleable in the right panel) is the source of truth.

## Install

PySide6 must be installed into the **same** `.venv` that runs `generate.py`
(Pillow is already there):

```bash
# from the repo root
.venv/bin/python -m pip install -r gui_python/requirements-gui.txt
# or, if the venv was created with uv and has no pip:
VIRTUAL_ENV="$PWD/.venv" uv pip install -r gui_python/requirements-gui.txt
```

## Run

```bash
# from the repo root
.venv/bin/python -m gui_python.main
```

You can set the Hugging Face token in **Settings** (see below) or via the
environment; the saved setting takes priority, falling back to `HF_TOKEN`:

```bash
export HF_TOKEN=hf_...
```

## Controls

- **Image**: drag-and-drop an image onto the drop area, or click to browse.
- **Seed**: number + 🎲 to randomize (mirrors the CLI `--seed`).
- **Pipeline**: 512 / 1024 / 1024 Cascade (`--pipeline-type`).
- **Geometry only**: skip texture baking (`--no-texture`); disables texture size.
- **Texture size**: 512 / 1024 / 2048 px (`--texture-size`).
- **Override steps**: optional `--steps` override (off = pipeline default).
- **Also export .obj**: on by default; uncheck to write only the `.glb` (the GLB
  already carries the mesh), which is faster and saves disk on large meshes.
- **Presets**: Fast Draft / Balanced / Max Quality.
- **Generate / Cancel**: one button; becomes Cancel while running.

Outputs are written to `<output folder>/<timestamp>-<id>/output_3d.{glb,obj}`
(and `_basecolor.png` on the KDTree texture path). The Output panel offers
Reveal in Finder / Open; the Output storage panel shows cumulative size and a
**Clean old runs (keep last 5)** action.

## Settings (Cmd+,)

A small, curated settings dialog:

- **Hugging Face token** — used as `HF_TOKEN` for the subprocess (falls back to
  the environment variable when blank). Needed on first run for the gated
  weights (TRELLIS.2-4B, DINOv3, RMBG-2.0).
- **Output folder** — where per-run output folders are created (default
  `<repo>/gui_output`).
- **Watchdog protection** — `Auto` / `On` / `Off`. Sets `MTL_CAPTURE_ENABLED=1`,
  which extends the macOS GPU watchdog timeout. **Auto** (default) enables it for
  heavy renders (pipeline 1024 / 1024 Cascade), tight/risky memory, or when an
  external display is attached — so high-res "just works" without fiddling.
- **Fallback backend** — opt-in `SPARSE_CONV_BACKEND=none` (slower path) for
  stubborn watchdog cases.
- **Fast mode (experimental)** — opt-in `TRELLIS_FAST=1`, which casts the
  flow/DiT torsos to fp16 (Apple GPUs' native fast type; the decoders already
  ship fp16). Roughly speeds up the sampling phases but changes GPU numerics, so
  **validate output quality** on a few renders before relying on it. If a render
  produces a broken/empty mesh with this on, turn it off.

## Performance notes

These wins are applied and safe (no change to render output):

- The subprocess gets `OMP_NUM_THREADS` / `VECLIB_MAXIMUM_THREADS` /
  `MKL_NUM_THREADS` / `NUMEXPR_NUM_THREADS` capped to *(cores − 2)* so the
  parallel CPU phases (xatlas UV unwrap, simplification, numpy/scipy in the
  texture bake) don't oversubscribe the cores the GPU work and UI need. Any
  value you export yourself is respected.
- The OBJ writer is vectorized (~1.5× faster on large meshes); skip it entirely
  with the "Also export .obj" toggle.
- The GUI log is batched (flushed ~10×/s instead of per line), the image preview
  skips needless rescales during window drags, the output-size scan runs off the
  UI thread, and the display probe is pre-warmed — so the UI stays smooth during
  long renders and the first Generate click doesn't stall.

## Hardware-aware memory guidance

The System panel always shows your real hardware and headroom, e.g.
`Apple M4 Max · 64 GB unified · est. peak ~18 GB ✓ comfortable · Displays: 1`,
and updates live as you change settings. RAM comes from `psutil`; the per-setting
peak is an estimate anchored to the documented ~18 GB at the heaviest combo.

The pre-run warning is **hardware-aware**: it compares the estimated peak to your
*actual* RAM (not a hardcoded threshold). If RAM comfortably exceeds the estimate
(verdict `comfortable`), there is **no warning** — so a 64 GB machine isn't nagged
about an 18 GB render. Only `tight` / `risky` verdicts prompt, with accurate
numbers and real options.

## Error handling

Failed runs are classified from the subprocess exit code and output, and shown
with concrete next steps: missing image, Hugging Face auth/gated, network,
disk-full, GPU out-of-memory, GPU watchdog, and OS-killed (out of memory). The
detection strings match the native Swift app's logic.

The **GPU watchdog** is the most common real failure on Apple Silicon and is
about Metal *kernel duration + display load, not total memory* — so its advice
leads with the real levers (run headless / reduce display load / watchdog
protection / fallback backend) and treats "lower quality" as a last resort. For
watchdog/OOM errors a **"Retry with watchdog protection"** button re-runs the
*same quality* with `MTL_CAPTURE_ENABLED=1` in one click. If the GPU reports OOM
but your machine had ample RAM, the message is relabeled to point at the watchdog
instead of telling you to reduce quality. The wrapper never runs two generations
at once (concurrent GPU jobs are unsafe).

## Testing without a GPU run

Set `TRELLIS_GUI_MOCK=1` to run `gui_python/mock_generate.py` instead of the
real CLI — it emits the same milestone strings and tqdm frames and writes empty
output files in seconds:

```bash
TRELLIS_GUI_MOCK=1 .venv/bin/python -m gui_python.main
```

The mock honors these env toggles to exercise error/robustness paths:

- `MOCK_EXIT_CODE=1` (missing image) / `MOCK_EXIT_CODE=2` (watchdog).
- `MOCK_FAIL=mps_oom|hf_gated|disk_full|no_network|watchdog|oom_killed` — emits
  the matching error signature and exits non-zero.
- `MOCK_ECHO_ENV=1` — prints `HF_TOKEN` / `MTL_CAPTURE_ENABLED` (verifies
  Settings reach the subprocess env).
- `MOCK_HUGE_LINE=1` — writes a ~2 MB no-newline stderr chunk (buffer-cap test).
