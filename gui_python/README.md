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
- **Watchdog-safe mode** — sets `MTL_CAPTURE_ENABLED=1`, which extends the macOS
  GPU watchdog timeout. Enable this if generations fail with a watchdog error.

## Error handling

Failed runs are classified from the subprocess exit code and output, and shown
with concrete next steps: missing image, Hugging Face auth/gated, network,
disk-full, GPU out-of-memory, GPU watchdog, and OS-killed (out of memory). The
detection strings match the native Swift app's logic. The wrapper never runs two
generations at once (concurrent GPU jobs are unsafe).

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
