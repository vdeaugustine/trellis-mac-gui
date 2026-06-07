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

If you have a Hugging Face token for the gated models, export it first:

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

Outputs are written to `gui_output/<timestamp>-<id>/output_3d.{glb,obj}`
(and `_basecolor.png` on the KDTree texture path). The Output panel offers
Reveal in Finder / Open / Open output folder.

## Testing without a GPU run

Set `TRELLIS_GUI_MOCK=1` to run `gui_python/mock_generate.py` instead of the
real CLI — it emits the same milestone strings and tqdm frames and writes empty
output files in seconds:

```bash
TRELLIS_GUI_MOCK=1 .venv/bin/python -m gui_python.main
```

The mock honors `MOCK_EXIT_CODE=1` (missing image) and `MOCK_EXIT_CODE=2`
(GPU watchdog) to exercise the error paths.
