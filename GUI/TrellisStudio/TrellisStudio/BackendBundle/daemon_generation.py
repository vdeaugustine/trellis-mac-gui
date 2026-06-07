"""Generation request handling, texture baking, and dry-run simulation."""

import os
import time

from daemon_memory import (
    aggressive_mps_cleanup,
    is_mps_oom,
    mps_oom_message,
    release_pipeline_memory,
    synchronize_mps,
)
from daemon_pipeline import get_pil_image, get_torch, prepare_pipeline_for_type
from daemon_transport import send_response


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

    outputs = None
    mesh_out = None
    verts = None
    faces = None
    img = None
    orig_decode_shape = pipeline.decode_shape_slat
    orig_decode_tex = pipeline.decode_tex_slat

    def hooked_decode_shape(*args_, **kwargs):
        send_response({"stage": "decodingShape", "status": "started"})
        synchronize_mps(get_torch())
        result = orig_decode_shape(*args_, **kwargs)
        synchronize_mps(get_torch())
        send_response({"stage": "decodingShape", "status": "done"})
        return result

    def hooked_decode_tex(*args_, **kwargs):
        send_response({"stage": "decodingTexture", "status": "started"})
        synchronize_mps(get_torch())
        result = orig_decode_tex(*args_, **kwargs)
        synchronize_mps(get_torch())
        send_response({"stage": "decodingTexture", "status": "done"})
        return result

    pipeline.decode_shape_slat = hooked_decode_shape
    pipeline.decode_tex_slat = hooked_decode_tex

    try:
        # Purge leftover tensors from previous generation before loading
        aggressive_mps_cleanup(get_torch())
        prepare_pipeline_for_type(pipeline, pipeline_type)
        t0 = time.time()
        sampler_overrides = {"steps": steps} if steps else {}
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
            trimesh.Trimesh(vertices=verts, faces=faces).export(glb_path)

        _write_obj(obj_path, verts, faces)
        send_response({
            "stage": "complete",
            "status": "done",
            "glb_path": glb_path,
            "obj_path": obj_path,
            "vertices": int(verts.shape[0]),
            "triangles": int(faces.shape[0]),
            "total_s": time.time() - t0,
        })
    except (IndexError, AssertionError) as error:
        _send_known_generation_error(error)
    except Exception as error:
        if is_mps_oom(error):
            release_pipeline_memory(pipeline, get_torch())
            send_response({
                "stage": "failed",
                "reason": "mps_oom",
                "message": mps_oom_message(error),
            })
        else:
            send_response({
                "stage": "failed",
                "reason": "error",
                "message": str(error),
            })
    finally:
        pipeline.decode_shape_slat = orig_decode_shape
        pipeline.decode_tex_slat = orig_decode_tex
        del outputs, mesh_out, verts, faces, img
        aggressive_mps_cleanup(get_torch())
        release_pipeline_memory(pipeline, get_torch())


def _bake_and_export(mesh_out, verts, faces, glb_path, texture_size):
    send_response({"stage": "bakingTexture", "status": "started"})
    if not _try_metal_export(mesh_out, verts, faces, glb_path, texture_size):
        _fallback_texture_export(mesh_out, verts, faces, glb_path, texture_size)
    send_response({"stage": "bakingTexture", "status": "done"})


def _try_metal_export(mesh_out, verts, faces, glb_path, texture_size):
    use_metal = False
    try:
        import o_voxel.postprocess
        backend = getattr(o_voxel.postprocess, "_BACKEND", None)
        has_dr = getattr(o_voxel.postprocess, "_HAS_DR", False)
        use_metal = backend == "metal" and has_dr
    except (ImportError, AttributeError):
        return False
    if not use_metal:
        return False

    try:
        import fast_simplification
        import o_voxel

        target_faces = min(200000, len(faces))
        if len(faces) > target_faces:
            ratio = 1.0 - (target_faces / len(faces))
            simple_verts, simple_faces = fast_simplification.simplify(
                verts, faces, ratio
            )
            torch = get_torch()
            verts_t = torch.from_numpy(simple_verts).float()
            faces_t = torch.from_numpy(simple_faces.astype("int32"))
        else:
            verts_t = mesh_out.vertices.cpu()
            faces_t = mesh_out.faces.cpu()

        glb = o_voxel.postprocess.to_glb(
            vertices=verts_t,
            faces=faces_t,
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
        return True
    except Exception:
        return False


def _fallback_texture_export(mesh_out, verts, faces, glb_path, texture_size):
    from backends.texture_baker import bake_texture, export_glb_with_texture, uv_unwrap

    voxel_coords = mesh_out.coords.cpu().float()
    voxel_attrs = mesh_out.attrs.cpu().float()
    origin = mesh_out.origin.cpu().float()
    bake_verts, bake_faces = _simplify_for_baking(verts, faces)
    new_verts, new_faces, uvs, _ = uv_unwrap(bake_verts, bake_faces)
    base_color, mr, _ = bake_texture(
        new_verts,
        new_faces,
        uvs,
        voxel_coords.numpy(),
        voxel_attrs.numpy(),
        origin.numpy(),
        mesh_out.voxel_size,
        texture_size=texture_size,
    )
    export_glb_with_texture(new_verts, new_faces, uvs, base_color, mr, glb_path)


def _simplify_for_baking(verts, faces):
    target_faces = min(200000, len(faces))
    if len(faces) <= target_faces:
        return verts, faces
    try:
        import fast_simplification
        ratio = 1.0 - (target_faces / len(faces))
        return fast_simplification.simplify(verts, faces, ratio)
    except ImportError:
        return verts, faces


def _write_obj(obj_path, verts, faces):
    with open(obj_path, "w") as file:
        for vertex in verts:
            file.write(f"v {vertex[0]:.6f} {vertex[1]:.6f} {vertex[2]:.6f}\n")
        for face in faces:
            file.write(f"f {face[0] + 1} {face[1] + 1} {face[2] + 1}\n")


def _send_known_generation_error(error):
    message = str(error)
    watchdog_signatures = ("non-zero size", "BVH needs at least 8 triangles")
    if any(signature in message for signature in watchdog_signatures):
        send_response({
            "stage": "failed",
            "reason": "watchdog",
            "message": "GPU watchdog killed Metal kernel.",
        })
        return
    send_response({"stage": "failed", "reason": "error", "message": message})


def _handle_dry_run(output_prefix):
    stages = [
        ("samplingStructure", 12),
        ("samplingShape", 12),
        ("samplingTexture", 12),
    ]
    for stage_name, total_steps in stages:
        for step in range(total_steps + 1):
            send_response({
                "stage": stage_name,
                "status": "step",
                "current": step,
                "total": total_steps,
            })
            time.sleep(0.05)

    for stage in ["decodingShape", "decodingTexture"]:
        send_response({"stage": stage, "status": "started"})
        time.sleep(0.1)
        send_response({"stage": stage, "status": "done"})

    send_response({"stage": "extractingMesh", "status": "started"})
    time.sleep(0.1)
    send_response({
        "stage": "extractingMesh",
        "status": "done",
        "vertices": 1248732,
        "triangles": 2497464,
    })
    send_response({"stage": "bakingTexture", "status": "started"})
    time.sleep(0.2)
    send_response({"stage": "bakingTexture", "status": "done"})

    glb_path = f"{output_prefix}.glb"
    obj_path = f"{output_prefix}.obj"
    with open(glb_path, "w") as file:
        file.write("mock glb")
    with open(obj_path, "w") as file:
        file.write("mock obj")

    send_response({
        "stage": "complete",
        "status": "done",
        "glb_path": glb_path,
        "obj_path": obj_path,
        "vertices": 1248732,
        "triangles": 2497464,
        "total_s": 2.5,
    })
