#!/usr/bin/env python3
"""
Trellis persistent daemon. Runs as a TCP server that survives app restarts.
Loads pipeline once and processes generation requests over JSON-over-TCP.
Supports --dry-run mode for local contract verification.
"""

import sys
import os
import time
import json
import argparse
import socket
import threading
import signal

# ── Environment setup (must happen before any ML imports) ──────────────
os.environ.setdefault("PYTORCH_ENABLE_MPS_FALLBACK", "1")
os.environ.setdefault("ATTN_BACKEND", "sdpa")
os.environ.setdefault("SPARSE_ATTN_BACKEND", "sdpa")
if "SPARSE_CONV_BACKEND" not in os.environ:
    os.environ["SPARSE_CONV_BACKEND"] = "none"

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "TRELLIS.2"))
sys.path.append(os.path.join(os.path.dirname(__file__), "stubs"))

# ── Monkey-patch tqdm BEFORE any TRELLIS imports ───────────────────────
# Global reference; set once a client connects
_active_client_send = None
_send_lock = threading.Lock()


def send_response(data):
    """Send a JSON response to the active client, or stdout as fallback."""
    with _send_lock:
        func = _active_client_send
    if func:
        func(data)
    else:
        # Fallback for early startup messages (before any client)
        print(json.dumps({"response": data}))
        sys.stdout.flush()


class PatchedTqdm:
    _lock = None

    def __init__(self, iterable=None, desc=None, disable=False, *args, **kwargs):
        self.iterable = iterable
        self.desc = desc
        self.disable = disable
        if iterable is not None:
            try:
                self.total = len(iterable)
            except Exception:
                self.total = kwargs.get('total', 0)
        else:
            self.total = kwargs.get('total', 0)
        self.current = 0
        self.n = 0
        self.pos = 0

        self.stage = "unknown"
        if desc:
            desc_lower = desc.lower()
            if "loading weights" in desc_lower:
                self.stage = "loadingPipeline"
            elif "sparse structure" in desc_lower:
                self.stage = "samplingStructure"
            elif "shape slat" in desc_lower:
                self.stage = "samplingShape"
            elif "texture slat" in desc_lower:
                self.stage = "samplingTexture"

        if not self.disable and self.stage != "unknown":
            send_response({
                "stage": self.stage,
                "status": "step",
                "current": self.current,
                "total": self.total,
                "message": self.desc or self.stage,
            })

    def __iter__(self):
        if self.iterable is None:
            return
        for item in self.iterable:
            yield item
            self.current += 1
            self.n = self.current
            if not self.disable and self.stage != "unknown":
                send_response({
                    "stage": self.stage,
                    "status": "step",
                    "current": self.current,
                    "total": self.total,
                    "message": self.desc or self.stage,
                })

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.close()

    def update(self, n=1):
        self.current += n
        self.n = self.current

    def close(self):
        pass

    def clear(self, *args, **kwargs):
        pass

    def refresh(self, *args, **kwargs):
        pass

    def set_description(self, desc=None, refresh=True):
        self.desc = desc

    def set_postfix(self, *args, **kwargs):
        pass

    @classmethod
    def set_lock(cls, lock):
        cls._lock = lock

    @classmethod
    def get_lock(cls):
        if cls._lock is None:
            import threading
            cls._lock = threading.RLock()
        return cls._lock

    @classmethod
    def write(cls, s, file=None, end="\n", nolock=False):
        pass

    @classmethod
    def external_write_mode(cls, *args, **kwargs):
        import contextlib
        return contextlib.nullcontext()

    @classmethod
    def pandas(cls, *args, **kwargs):
        raise NotImplementedError("PatchedTqdm does not support pandas integration")


import tqdm
tqdm.tqdm = PatchedTqdm
try:
    import tqdm.auto
    tqdm.auto.tqdm = PatchedTqdm
except Exception:
    pass

# ── Lazy-loaded heavy modules ──────────────────────────────────────────
# torch and PIL are imported eagerly in a background thread once the TCP
# server binds. get_torch()/get_pil_image() block until ready.
_torch = None
_PILImage = None
_warmup_done = threading.Event()
_warmup_lock = threading.Lock()


def get_torch():
    """Get torch module. Blocks until background warmup finishes."""
    _warmup_done.wait()
    return _torch


def get_pil_image():
    """Get PIL.Image module. Blocks until background warmup finishes."""
    _warmup_done.wait()
    return _PILImage


def _run_warmup():
    """Background thread: import torch and PIL so first generation is fast."""
    global _torch, _PILImage
    try:
        sys.stderr.write("[daemon] Warmup: importing torch...\n")
        sys.stderr.flush()
        _torch = __import__("torch")
        sys.stderr.write(f"[daemon] Warmup: torch {_torch.__version__} OK\n")
        sys.stderr.flush()

        sys.stderr.write("[daemon] Warmup: importing PIL...\n")
        sys.stderr.flush()
        from PIL import Image
        _PILImage = Image
        sys.stderr.write("[daemon] Warmup: PIL OK\n")
        sys.stderr.flush()

        # Notify any waiters that modules are ready
        send_response({
            "stage": "daemonStatus",
            "status": "ready",
            "pipeline_loaded": False,
            "warmup_complete": True,
            "message": "Core imports ready. Pipeline loads on first generation.",
        })
    except Exception as e:
        sys.stderr.write(f"[daemon] Warmup FAILED: {e}\n")
        sys.stderr.flush()
    finally:
        _warmup_done.set()

# ── Constants ──────────────────────────────────────────────────────────
IDLE_TIMEOUT_SECONDS = 30 * 60  # 30 minutes default
APP_SUPPORT_DIR = os.path.expanduser(
    "~/Library/Application Support/com.vinware.trellis-studio"
)
PORT_FILE = os.path.join(APP_SUPPORT_DIR, "daemon.port")
PID_FILE = os.path.join(APP_SUPPORT_DIR, "daemon.pid")


# ── Pipeline loading ──────────────────────────────────────────────────

def load_pipeline(args, pipeline_type="512"):
    """Load the TRELLIS pipeline, filtering models by pipeline_type."""
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
        send_response({
            "stage": "loadingPipeline",
            "status": "step",
            "current": 1, "total": 4,
            "message": "Importing PyTorch",
        })
        sys.stderr.write("[daemon] Step 1: Importing torch...\n")
        sys.stderr.flush()
        torch = get_torch()
        sys.stderr.write(f"[daemon] torch {torch.__version__} imported OK\n")
        sys.stderr.flush()

        send_response({
            "stage": "loadingPipeline",
            "status": "step",
            "current": 2, "total": 4,
            "message": "Importing TRELLIS pipeline",
        })
        sys.stderr.write("[daemon] Step 2: Importing TRELLIS pipeline...\n")
        sys.stderr.flush()
        from trellis2.pipelines.trellis2_image_to_3d import (
            Trellis2ImageTo3DPipeline,
        )
        sys.stderr.write("[daemon] TRELLIS pipeline class imported OK\n")
        sys.stderr.flush()

        # Filter models based on pipeline type to save memory and time
        original_names = Trellis2ImageTo3DPipeline.model_names_to_load
        needed = _models_for_pipeline_type(pipeline_type)
        Trellis2ImageTo3DPipeline.model_names_to_load = needed

        send_response({
            "stage": "loadingPipeline",
            "status": "step",
            "current": 3, "total": 4,
            "message": f"Loading model weights ({len(needed)} models for {pipeline_type})",
        })
        sys.stderr.write(f"[daemon] Step 3: Loading weights for {needed}...\n")
        sys.stderr.flush()
        pipeline = Trellis2ImageTo3DPipeline.from_pretrained(
            "microsoft/TRELLIS.2-4B"
        )
        # Restore so hot-upgrade can add more models later
        Trellis2ImageTo3DPipeline.model_names_to_load = original_names
        sys.stderr.write("[daemon] Weights loaded OK\n")
        sys.stderr.flush()

        send_response({
            "stage": "loadingPipeline",
            "status": "step",
            "current": 4, "total": 4,
            "message": "Moving pipeline to Apple GPU",
        })
        sys.stderr.write("[daemon] Step 4: Moving to MPS...\n")
        sys.stderr.flush()
        pipeline.to(get_torch().device("mps"))

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

    except Exception as e:
        import traceback
        tb = traceback.format_exc()
        sys.stderr.write(f"[daemon] PIPELINE LOAD FAILED:\n{tb}\n")
        sys.stderr.flush()
        send_response({
            "stage": "failed",
            "reason": "load_error",
            "message": f"{type(e).__name__}: {e}",
        })
        raise


def _models_for_pipeline_type(pipeline_type):
    """Return the subset of model names needed for a given pipeline type."""
    # These two are always needed
    base = [
        "sparse_structure_flow_model",
        "sparse_structure_decoder",
        "shape_slat_decoder",
        "tex_slat_decoder",
    ]
    if pipeline_type == "512":
        return base + ["shape_slat_flow_model_512", "tex_slat_flow_model_512"]
    elif pipeline_type == "1024":
        return base + ["shape_slat_flow_model_1024", "tex_slat_flow_model_1024"]
    else:
        # 1024_cascade or 1536_cascade need both
        return base + [
            "shape_slat_flow_model_512",
            "shape_slat_flow_model_1024",
            "tex_slat_flow_model_1024",
        ]


def _ensure_models_loaded(pipeline, pipeline_type):
    """Hot-load any missing models needed for a pipeline_type switch."""
    needed = _models_for_pipeline_type(pipeline_type)
    missing = [n for n in needed if n not in pipeline.models]
    if not missing:
        return

    send_response({
        "stage": "loadingPipeline",
        "status": "started",
        "message": f"Loading {len(missing)} additional model(s) for {pipeline_type}",
    })
    from trellis2 import models as trellis_models
    from huggingface_hub import hf_hub_download
    import json as _json

    # Re-read the pipeline config to get model paths
    config_file = hf_hub_download("microsoft/TRELLIS.2-4B", "pipeline.json")
    with open(config_file, "r") as f:
        config = _json.load(f)
    model_paths = config["args"]["models"]

    for name in missing:
        path = model_paths.get(name)
        if not path:
            continue
        try:
            model = trellis_models.from_pretrained(
                f"microsoft/TRELLIS.2-4B/{path}"
            )
            model.eval()
            pipeline.models[name] = model
        except Exception as e:
            send_response({
                "stage": "failed",
                "reason": "hot_load_error",
                "message": f"Failed to load {name}: {e}",
            })

    send_response({
        "stage": "loadingPipeline",
        "status": "done",
        "message": "Additional models loaded",
    })


# ── Generation handler ────────────────────────────────────────────────

def handle_generate(cmd_payload, pipeline, args):
    """Process a single generation request."""
    image_path = cmd_payload.get("image")
    seed = cmd_payload.get("seed", 42)
    pipeline_type = cmd_payload.get("pipeline_type", "512")
    texture_size = cmd_payload.get("texture_size", 1024)
    no_texture = cmd_payload.get("no_texture", False)
    output_dir = cmd_payload.get("output_dir", ".")
    steps = cmd_payload.get("steps")

    if not args.dry_run and (not image_path or not os.path.exists(image_path)):
        send_response({
            "stage": "failed",
            "reason": "missing_image",
            "message": f"Image not found: {image_path}",
        })
        return

    os.makedirs(output_dir, exist_ok=True)
    output_prefix = os.path.join(output_dir, "output_3d")

    send_response({"stage": "queued", "status": "started"})

    if args.dry_run:
        _handle_dry_run(output_prefix)
        return

    # Hot-load models if needed for this pipeline type
    _ensure_models_loaded(pipeline, pipeline_type)

    t0 = time.time()
    sampler_overrides = {"steps": steps} if steps else {}

    # Hook decode methods for progress
    orig_decode_shape = pipeline.decode_shape_slat
    orig_decode_tex = pipeline.decode_tex_slat

    def hooked_decode_shape(*a, **kw):
        send_response({"stage": "decodingShape", "status": "started"})
        res = orig_decode_shape(*a, **kw)
        send_response({"stage": "decodingShape", "status": "done"})
        return res

    def hooked_decode_tex(*a, **kw):
        send_response({"stage": "decodingTexture", "status": "started"})
        res = orig_decode_tex(*a, **kw)
        send_response({"stage": "decodingTexture", "status": "done"})
        return res

    pipeline.decode_shape_slat = hooked_decode_shape
    pipeline.decode_tex_slat = hooked_decode_tex

    try:
        img = get_pil_image().open(image_path)
        outputs = pipeline.run(
            img,
            seed=seed,
            pipeline_type=pipeline_type,
            sparse_structure_sampler_params=sampler_overrides,
            shape_slat_sampler_params=sampler_overrides,
            tex_slat_sampler_params=sampler_overrides,
        )

        send_response({"stage": "extractingMesh", "status": "started"})
        mesh_out = outputs[0] if isinstance(outputs, list) else outputs
        verts = mesh_out.vertices.cpu().numpy()
        faces = mesh_out.faces.cpu().numpy()

        if verts.shape[0] == 0 or faces.shape[0] == 0:
            raise ValueError("Empty mesh produced (watchdog likely).")

        send_response({
            "stage": "extractingMesh",
            "status": "done",
            "vertices": int(verts.shape[0]),
            "triangles": int(faces.shape[0]),
        })

        glb_path = f"{output_prefix}.glb"
        obj_path = f"{output_prefix}.obj"
        has_voxels = hasattr(mesh_out, "attrs") and mesh_out.attrs is not None

        if has_voxels and not no_texture:
            _bake_and_export(mesh_out, verts, faces, glb_path, texture_size)
        else:
            import trimesh
            tm = trimesh.Trimesh(vertices=verts, faces=faces)
            tm.export(glb_path)

        # Save OBJ
        with open(obj_path, "w") as f:
            for v in verts:
                f.write(f"v {v[0]:.6f} {v[1]:.6f} {v[2]:.6f}\n")
            for face in faces:
                f.write(f"f {face[0]+1} {face[1]+1} {face[2]+1}\n")

        send_response({
            "stage": "complete",
            "status": "done",
            "glb_path": glb_path,
            "obj_path": obj_path,
            "vertices": int(verts.shape[0]),
            "triangles": int(faces.shape[0]),
            "total_s": time.time() - t0,
        })

    except (IndexError, AssertionError) as e:
        msg = str(e)
        sigs = ("non-zero size", "BVH needs at least 8 triangles")
        if any(s in msg for s in sigs):
            send_response({
                "stage": "failed",
                "reason": "watchdog",
                "message": "GPU watchdog killed Metal kernel.",
            })
        else:
            send_response({"stage": "failed", "reason": "error", "message": msg})
    except Exception as e:
        send_response({"stage": "failed", "reason": "error", "message": str(e)})
    finally:
        # Restore original methods
        pipeline.decode_shape_slat = orig_decode_shape
        pipeline.decode_tex_slat = orig_decode_tex


def _bake_and_export(mesh_out, verts, faces, glb_path, texture_size):
    """Handle texture baking and GLB export."""
    send_response({"stage": "bakingTexture", "status": "started"})

    use_metal = False
    try:
        import o_voxel.postprocess
        backend = getattr(o_voxel.postprocess, '_BACKEND', None)
        has_dr = getattr(o_voxel.postprocess, '_HAS_DR', False)
        use_metal = (backend == 'metal' and has_dr)
    except (ImportError, AttributeError):
        pass

    if use_metal:
        try:
            import o_voxel  # noqa: F811
            import fast_simplification
            target_faces = min(200000, len(faces))
            if len(faces) > target_faces:
                ratio = 1.0 - (target_faces / len(faces))
                sv, sf = fast_simplification.simplify(verts, faces, ratio)
                sv_t = get_torch().from_numpy(sv).float().to(mesh_out.vertices.device)
                sf_t = get_torch().from_numpy(sf.astype('int32')).to(mesh_out.faces.device)
            else:
                sv_t = mesh_out.vertices
                sf_t = mesh_out.faces

            glb = o_voxel.postprocess.to_glb(
                vertices=sv_t.cpu(), faces=sf_t.cpu(),
                attr_volume=mesh_out.attrs.cpu(),
                coords=mesh_out.coords.cpu(),
                attr_layout=mesh_out.layout,
                voxel_size=mesh_out.voxel_size,
                aabb=[[-0.5, -0.5, -0.5], [0.5, 0.5, 0.5]],
                decimation_target=target_faces,
                texture_size=texture_size,
                verbose=False,
            )
            glb.export(glb_path)
        except Exception:
            use_metal = False

    if not use_metal:
        from backends.texture_baker import (
            uv_unwrap, bake_texture, export_glb_with_texture,
        )
        voxel_coords = mesh_out.coords.cpu().float()
        voxel_attrs = mesh_out.attrs.cpu().float()
        origin = mesh_out.origin.cpu().float()
        vs = mesh_out.voxel_size

        bake_verts, bake_faces = verts, faces
        target_faces = min(200000, len(faces))
        if len(faces) > target_faces:
            try:
                import fast_simplification
                ratio = 1.0 - (target_faces / len(faces))
                bake_verts, bake_faces = fast_simplification.simplify(
                    verts, faces, ratio
                )
            except ImportError:
                pass

        nv, nf, uvs, _ = uv_unwrap(bake_verts, bake_faces)
        base_color, mr, _ = bake_texture(
            nv, nf, uvs,
            voxel_coords.numpy(), voxel_attrs.numpy(),
            origin.numpy(), vs,
            texture_size=texture_size,
        )
        export_glb_with_texture(nv, nf, uvs, base_color, mr, glb_path)

    send_response({"stage": "bakingTexture", "status": "done"})


def _handle_dry_run(output_prefix):
    """Simulate generation stages for dry-run testing."""
    stages = [
        ("samplingStructure", 12),
        ("samplingShape", 12),
        ("samplingTexture", 12),
    ]
    for stage_name, total_steps in stages:
        for step in range(total_steps + 1):
            send_response({
                "stage": stage_name, "status": "step",
                "current": step, "total": total_steps,
            })
            time.sleep(0.05)

    for s in ["decodingShape", "decodingTexture"]:
        send_response({"stage": s, "status": "started"})
        time.sleep(0.1)
        send_response({"stage": s, "status": "done"})

    send_response({"stage": "extractingMesh", "status": "started"})
    time.sleep(0.1)
    send_response({
        "stage": "extractingMesh", "status": "done",
        "vertices": 1248732, "triangles": 2497464,
    })

    send_response({"stage": "bakingTexture", "status": "started"})
    time.sleep(0.2)
    send_response({"stage": "bakingTexture", "status": "done"})

    glb_path = f"{output_prefix}.glb"
    obj_path = f"{output_prefix}.obj"
    with open(glb_path, "w") as f:
        f.write("mock glb")
    with open(obj_path, "w") as f:
        f.write("mock obj")

    send_response({
        "stage": "complete", "status": "done",
        "glb_path": glb_path, "obj_path": obj_path,
        "vertices": 1248732, "triangles": 2497464,
        "total_s": 2.5,
    })


# ── TCP Server ────────────────────────────────────────────────────────

class DaemonServer:
    """TCP server that handles one client at a time. Persists between connects."""

    def __init__(self, args, idle_timeout=IDLE_TIMEOUT_SECONDS):
        self.args = args
        self.idle_timeout = idle_timeout
        self.pipeline = None
        self.pipeline_loaded = False
        self.pipeline_type = args.default_pipeline
        self.server_socket = None
        self.running = True
        self.last_activity = time.time()

    def start(self, port=0):
        """Bind, write port/pid files, and enter accept loop."""
        self.server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.server_socket.bind(("127.0.0.1", port))
        self.server_socket.listen(1)
        self.server_socket.settimeout(60)  # Check idle every 60s

        actual_port = self.server_socket.getsockname()[1]
        os.makedirs(APP_SUPPORT_DIR, exist_ok=True)
        with open(PORT_FILE, "w") as f:
            f.write(str(actual_port))
        with open(PID_FILE, "w") as f:
            f.write(str(os.getpid()))

        # Also print to stdout for the Swift app to read on first launch
        send_response({
            "stage": "daemonStatus",
            "status": "ready",
            "pipeline_loaded": False,
            "port": actual_port,
            "message": "Daemon listening. Warming up imports in background…",
        })

        # Start importing torch/PIL in the background immediately
        warmup_thread = threading.Thread(
            target=_run_warmup, name="ImportWarmup", daemon=True
        )
        warmup_thread.start()

        self._accept_loop()

    def _accept_loop(self):
        """Accept clients in a loop. Daemon stays alive between disconnects."""
        while self.running:
            try:
                conn, addr = self.server_socket.accept()
            except socket.timeout:
                if self._check_idle_timeout():
                    break
                continue
            except OSError:
                break

            self.last_activity = time.time()
            self._handle_client(conn)

        self._cleanup()

    def _handle_client(self, conn):
        """Handle a single client connection until disconnect or shutdown."""
        global _active_client_send

        def client_send(data):
            try:
                line = json.dumps({"response": data}) + "\n"
                conn.sendall(line.encode("utf-8"))
            except (BrokenPipeError, ConnectionResetError, OSError):
                pass

        with _send_lock:
            _active_client_send = client_send

        # Tell client current state
        client_send({
            "stage": "daemonStatus",
            "status": "ready",
            "pipeline_loaded": self.pipeline_loaded,
        })

        buffer = b""
        conn.settimeout(5)  # Timeout for read loop

        while self.running:
            try:
                data = conn.recv(8192)
            except socket.timeout:
                self.last_activity = time.time()
                continue
            except (ConnectionResetError, OSError):
                break

            if not data:
                break  # Client disconnected

            buffer += data
            while b"\n" in buffer:
                line_bytes, buffer = buffer.split(b"\n", 1)
                line_str = line_bytes.decode("utf-8", errors="replace").strip()
                if not line_str:
                    continue

                self.last_activity = time.time()
                should_shutdown = self._process_message(line_str)
                if should_shutdown:
                    self.running = False
                    break

        # Client gone — clear send function but keep daemon alive
        with _send_lock:
            _active_client_send = None
        try:
            conn.close()
        except OSError:
            pass

    def _process_message(self, line_str):
        """Process a single JSON message. Returns True if shutdown requested."""
        try:
            msg = json.loads(line_str)
        except json.JSONDecodeError as e:
            send_response({
                "stage": "failed",
                "reason": "invalid_json",
                "message": str(e),
            })
            return False

        cmd_payload = msg.get("command")
        if not cmd_payload:
            return False

        cmd = cmd_payload.get("command")

        if cmd == "shutdown":
            send_response({"stage": "shutdown", "status": "done"})
            return True

        if cmd == "status":
            send_response({
                "stage": "daemonStatus",
                "status": "ready",
                "pipeline_loaded": self.pipeline_loaded,
            })
            return False

        if cmd == "generate":
            if not self.pipeline_loaded:
                try:
                    pt = cmd_payload.get("pipeline_type", self.pipeline_type)
                    self.pipeline = load_pipeline(self.args, pipeline_type=pt)
                    self.pipeline_loaded = True
                    self.pipeline_type = pt
                except Exception:
                    return False

            handle_generate(cmd_payload, self.pipeline, self.args)
            return False

        return False

    def _check_idle_timeout(self):
        """Return True if daemon should shut down due to inactivity."""
        if self.idle_timeout <= 0:
            return False
        elapsed = time.time() - self.last_activity
        if elapsed > self.idle_timeout:
            send_response({
                "stage": "shutdown",
                "status": "done",
                "reason": "idle_timeout",
                "message": f"Shutting down after {int(elapsed)}s idle",
            })
            return True
        return False

    def _cleanup(self):
        """Remove port/pid files and close socket."""
        for path in (PORT_FILE, PID_FILE):
            try:
                os.remove(path)
            except OSError:
                pass
        if self.server_socket:
            try:
                self.server_socket.close()
            except OSError:
                pass


# ── Legacy stdin/stdout mode (fallback) ───────────────────────────────

def run_legacy_mode(args):
    """Original stdin/stdout JSON protocol for backward compatibility."""
    send_response({
        "stage": "daemonStatus",
        "status": "ready",
        "pipeline_loaded": False,
        "message": "Daemon ready (legacy mode). Pipeline loads on first generation.",
    })
    pipeline = None
    pipeline_loaded = False

    while True:
        try:
            line = sys.stdin.readline()
            if not line:
                break

            line_str = line.strip()
            if not line_str:
                continue

            try:
                msg = json.loads(line_str)
            except json.JSONDecodeError as e:
                send_response({
                    "stage": "failed",
                    "reason": "invalid_json",
                    "message": str(e),
                })
                continue

            cmd_payload = msg.get("command")
            if not cmd_payload:
                continue

            cmd = cmd_payload.get("command")
            if cmd == "shutdown":
                send_response({"stage": "shutdown", "status": "done"})
                break
            if cmd == "status":
                send_response({
                    "stage": "daemonStatus",
                    "status": "ready",
                    "pipeline_loaded": pipeline_loaded,
                })
                continue

            if cmd == "generate":
                if not pipeline_loaded:
                    try:
                        pt = cmd_payload.get("pipeline_type", "512")
                        pipeline = load_pipeline(args, pipeline_type=pt)
                        pipeline_loaded = True
                    except Exception:
                        continue

                handle_generate(cmd_payload, pipeline, args)

        except KeyboardInterrupt:
            break
        except Exception as e:
            send_response({
                "stage": "failed",
                "reason": "loop_error",
                "message": str(e),
            })


# ── Entry point ───────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="Trellis 3D generation daemon")
    parser.add_argument(
        "--dry-run", action="store_true",
        help="Run in mock mode without loading models",
    )
    parser.add_argument(
        "--port", type=int, default=0,
        help="TCP port to listen on (0 = auto-assign)",
    )
    parser.add_argument(
        "--legacy", action="store_true",
        help="Use stdin/stdout mode instead of TCP",
    )
    parser.add_argument(
        "--idle-timeout", type=int, default=IDLE_TIMEOUT_SECONDS,
        help="Seconds of idle before auto-shutdown (0 = never)",
    )
    parser.add_argument(
        "--default-pipeline", type=str, default="512",
        choices=["512", "1024", "1024_cascade", "1536_cascade"],
        help="Default pipeline type for initial model loading",
    )
    args = parser.parse_args()

    # Handle SIGTERM gracefully (from launchctl or kill)
    def sigterm_handler(signum, frame):
        sys.exit(0)
    signal.signal(signal.SIGTERM, sigterm_handler)

    if args.legacy:
        run_legacy_mode(args)
    else:
        server = DaemonServer(args, idle_timeout=args.idle_timeout)
        server.start(port=args.port)


if __name__ == "__main__":
    main()
