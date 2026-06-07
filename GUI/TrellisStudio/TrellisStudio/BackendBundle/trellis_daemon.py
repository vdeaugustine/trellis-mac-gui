#!/usr/bin/env python3
"""
Trellis persistent daemon. Loads pipeline once and processes generation requests.
Supports --dry-run mode for local contract verification.
"""

import sys
import os
import time
import json
import argparse

# Monkey-patch tqdm BEFORE any TRELLIS imports to capture steps
class PatchedTqdm:
    def __init__(self, iterable=None, desc=None, disable=False, *args, **kwargs):
        self.iterable = iterable
        self.desc = desc
        self.disable = disable
        if iterable is not None:
            try:
                self.total = len(iterable)
            except:
                self.total = kwargs.get('total', 0)
        else:
            self.total = kwargs.get('total', 0)
        self.current = 0
        
        self.stage = "unknown"
        if desc:
            if "sparse structure" in desc.lower():
                self.stage = "samplingStructure"
            elif "shape slat" in desc.lower():
                self.stage = "samplingShape"
            elif "texture slat" in desc.lower():
                self.stage = "samplingTexture"
                
        if not self.disable and self.stage != "unknown":
            send_response({"stage": self.stage, "status": "step", "current": self.current, "total": self.total})

    def __iter__(self):
        if self.iterable is None:
            return
        for item in self.iterable:
            yield item
            self.current += 1
            if not self.disable and self.stage != "unknown":
                send_response({"stage": self.stage, "status": "step", "current": self.current, "total": self.total})

# Inject PatchedTqdm into sys.modules
import tqdm
tqdm.tqdm = PatchedTqdm

os.environ.setdefault("PYTORCH_ENABLE_MPS_FALLBACK", "1")
os.environ.setdefault("ATTN_BACKEND", "sdpa")
os.environ.setdefault("SPARSE_ATTN_BACKEND", "sdpa")
if "SPARSE_CONV_BACKEND" not in os.environ:
    os.environ["SPARSE_CONV_BACKEND"] = "none"

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "TRELLIS.2"))
sys.path.append(os.path.join(os.path.dirname(__file__), "stubs"))

def send_response(data):
    print(json.dumps({"response": data}))
    sys.stdout.flush()

def load_pipeline(args):
    send_response({
        "stage": "loadingPipeline",
        "status": "started",
        "backend": os.environ.get("SPARSE_CONV_BACKEND", "unknown"),
    })
    t0 = time.time()

    if args.dry_run:
        time.sleep(0.5)
        send_response({"stage": "loadingPipeline", "status": "done", "elapsed_s": round(time.time() - t0, 2)})
        return None

    try:
        import torch
        from trellis2.pipelines.trellis2_image_to_3d import Trellis2ImageTo3DPipeline
        pipeline = Trellis2ImageTo3DPipeline.from_pretrained("microsoft/TRELLIS.2-4B")
        pipeline.to(torch.device("mps"))
        send_response({"stage": "loadingPipeline", "status": "done", "elapsed_s": round(time.time() - t0, 2)})
        return pipeline
    except Exception as e:
        send_response({
            "stage": "failed",
            "reason": "load_error",
            "message": f"{type(e).__name__}: {e}",
        })
        raise

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true", help="Run in mock mode without loading models")
    args = parser.parse_args()

    send_response({
        "stage": "daemonStatus",
        "status": "ready",
        "pipeline_loaded": False,
        "message": "Daemon ready. Pipeline loads on first generation.",
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
            except Exception as e:
                send_response({"stage": "failed", "reason": "invalid_json", "message": str(e)})
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
                image_path = cmd_payload.get("image")
                seed = cmd_payload.get("seed", 42)
                pipeline_type = cmd_payload.get("pipeline_type", "512")
                texture_size = cmd_payload.get("texture_size", 1024)
                no_texture = cmd_payload.get("no_texture", False)
                output_dir = cmd_payload.get("output_dir", ".")
                steps = cmd_payload.get("steps")
                
                if not args.dry_run and (not image_path or not os.path.exists(image_path)):
                    send_response({"stage": "failed", "reason": "missing_image", "message": f"Image not found: {image_path}"})
                    continue
                    
                os.makedirs(output_dir, exist_ok=True)
                output_prefix = os.path.join(output_dir, "output_3d")
                
                send_response({"stage": "queued", "status": "started"})

                if not pipeline_loaded:
                    try:
                        pipeline = load_pipeline(args)
                        pipeline_loaded = True
                    except Exception:
                        continue
                
                if args.dry_run:
                    # Mock progression
                    stages = [
                        ("samplingStructure", 12),
                        ("samplingShape", 12),
                        ("samplingTexture", 12)
                    ]
                    for stage_name, total_steps in stages:
                        for step in range(total_steps + 1):
                            send_response({"stage": stage_name, "status": "step", "current": step, "total": total_steps})
                            time.sleep(0.05)
                    
                    send_response({"stage": "decodingShape", "status": "started"})
                    time.sleep(0.1)
                    send_response({"stage": "decodingShape", "status": "done"})
                    
                    send_response({"stage": "decodingTexture", "status": "started"})
                    time.sleep(0.1)
                    send_response({"stage": "decodingTexture", "status": "done"})
                    
                    send_response({"stage": "extractingMesh", "status": "started"})
                    time.sleep(0.1)
                    send_response({
                        "stage": "extractingMesh", 
                        "status": "done", 
                        "vertices": 1248732, 
                        "triangles": 2497464
                    })
                    
                    send_response({"stage": "bakingTexture", "status": "started"})
                    time.sleep(0.2)
                    send_response({"stage": "bakingTexture", "status": "done"})
                    
                    glb_path = f"{output_prefix}.glb"
                    obj_path = f"{output_prefix}.obj"
                    
                    # Write dummy files
                    with open(glb_path, "w") as f:
                        f.write("mock glb")
                    with open(obj_path, "w") as f:
                        f.write("mock obj")
                        
                    send_response({
                        "stage": "complete",
                        "status": "done",
                        "glb_path": glb_path,
                        "obj_path": obj_path,
                        "vertices": 1248732,
                        "triangles": 2497464,
                        "total_s": 2.5
                    })
                    continue
                
                # Non-dry-run logic
                import torch
                from PIL import Image as PILImage
                t0 = time.time()
                sampler_overrides = {"steps": steps} if steps else {}
                
                orig_decode_shape_slat = pipeline.decode_shape_slat
                def hooked_decode_shape_slat(*args, **kwargs):
                    send_response({"stage": "decodingShape", "status": "started"})
                    res = orig_decode_shape_slat(*args, **kwargs)
                    send_response({"stage": "decodingShape", "status": "done"})
                    return res
                pipeline.decode_shape_slat = hooked_decode_shape_slat
                
                orig_decode_tex_slat = pipeline.decode_tex_slat
                def hooked_decode_tex_slat(*args, **kwargs):
                    send_response({"stage": "decodingTexture", "status": "started"})
                    res = orig_decode_tex_slat(*args, **kwargs)
                    send_response({"stage": "decodingTexture", "status": "done"})
                    return res
                pipeline.decode_tex_slat = hooked_decode_tex_slat
                
                try:
                    img = PILImage.open(image_path)
                    
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
                        "triangles": int(faces.shape[0])
                    })
                    
                    glb_path = f"{output_prefix}.glb"
                    obj_path = f"{output_prefix}.obj"
                    
                    has_voxels = hasattr(mesh_out, "attrs") and mesh_out.attrs is not None
                    
                    if has_voxels and not no_texture:
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
                                import o_voxel
                                import fast_simplification
                                target_faces = min(200000, len(faces))
                                if len(faces) > target_faces:
                                    ratio = 1.0 - (target_faces / len(faces))
                                    simp_verts, simp_faces = fast_simplification.simplify(verts, faces, ratio)
                                    simp_verts_t = torch.from_numpy(simp_verts).float().to(mesh_out.vertices.device)
                                    simp_faces_t = torch.from_numpy(simp_faces.astype('int32')).to(mesh_out.faces.device)
                                else:
                                    simp_verts_t = mesh_out.vertices
                                    simp_faces_t = mesh_out.faces
                                    
                                glb = o_voxel.postprocess.to_glb(
                                    vertices=simp_verts_t.cpu(),
                                    faces=simp_faces_t.cpu(),
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
                            except:
                                use_metal = False
                                
                        if not use_metal:
                            from backends.texture_baker import uv_unwrap, bake_texture, export_glb_with_texture
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
                                    bake_verts, bake_faces = fast_simplification.simplify(verts, faces, ratio)
                                except ImportError:
                                    pass
                                    
                            new_verts, new_faces, uvs, vmapping = uv_unwrap(bake_verts, bake_faces)
                            base_color_img, mr_img, mask = bake_texture(
                                new_verts, new_faces, uvs,
                                voxel_coords.numpy(), voxel_attrs.numpy(),
                                origin.numpy(), vs,
                                texture_size=texture_size,
                            )
                            export_glb_with_texture(new_verts, new_faces, uvs, base_color_img, mr_img, glb_path)
                            
                        send_response({"stage": "bakingTexture", "status": "done"})
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
                            
                    t_total = time.time() - t0
                    send_response({
                        "stage": "complete",
                        "status": "done",
                        "glb_path": glb_path,
                        "obj_path": obj_path,
                        "vertices": int(verts.shape[0]),
                        "triangles": int(faces.shape[0]),
                        "total_s": t_total
                    })
                    
                except (IndexError, AssertionError) as e:
                    msg = str(e)
                    watchdog_signatures = ("non-zero size", "BVH needs at least 8 triangles")
                    if any(sig in msg for sig in watchdog_signatures):
                        send_response({"stage": "failed", "reason": "watchdog", "message": "GPU watchdog killed Metal kernel."})
                    else:
                        send_response({"stage": "failed", "reason": "error", "message": msg})
                except Exception as e:
                    send_response({"stage": "failed", "reason": "error", "message": str(e)})
                    
        except KeyboardInterrupt:
            break
        except Exception as e:
            send_response({"stage": "failed", "reason": "loop_error", "message": str(e)})

if __name__ == "__main__":
    main()
