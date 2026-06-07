"""
UV unwrap + texture baking for TRELLIS.2 meshes on Apple Silicon.

Replaces nvdiffrast (CUDA-only) with:
  - xatlas for UV unwrapping (C++ library, CPU)
  - Vectorized numpy rasterizer for UV-space triangles
  - scipy cKDTree for nearest-voxel lookup at native 512 resolution
  - Inverse-distance weighting for trilinear-like interpolation

Produces GLB files with PBR textures (base color, metallic, roughness).
"""

import numpy as np
import time


def uv_unwrap(vertices, faces):
    """
    Compute UV coordinates for a mesh using xatlas.

    Returns:
        new_vertices: Remapped vertices
        new_faces: Triangle indices into new_vertices
        uvs: UV coordinates per new vertex, in [0, 1]
        vmapping: Maps new vertex index -> original vertex index
    """
    import xatlas

    v = np.ascontiguousarray(vertices.astype(np.float32))
    f = np.ascontiguousarray(faces.astype(np.uint32))

    vmapping, indices, uvs = xatlas.parametrize(v, f)

    new_vertices = v[vmapping]
    new_faces = indices.reshape(-1, 3)

    return new_vertices, new_faces, uvs, vmapping


def _rasterize_uv_batch(valid_idx, areas, w_bbox, min_x_v, min_y_v,
                         uv0, d00, d01, d10, d11, denom,
                         p0, p1, p2, positions, mask):
    """
    Vectorized rasterization of a batch of triangles.

    Enumerates all texel candidates via np.repeat + cumulative offsets,
    computes barycentric coordinates in one pass, filters inside-triangle
    texels, and scatters 3D positions to the output texture.
    """
    total = int(areas.sum())
    if total == 0:
        return

    # Map each texel candidate back to its triangle
    face_per_texel = np.repeat(valid_idx, areas)

    # Cumulative area offsets for computing local (x, y) within each bbox
    cumulative = np.zeros(len(areas) + 1, dtype=np.int64)
    np.cumsum(areas, out=cumulative[1:])
    local_offset = np.arange(total, dtype=np.int64) - np.repeat(cumulative[:-1], areas)

    # Local pixel coords within each triangle's bounding box
    w_per_texel = np.repeat(w_bbox, areas)
    local_y = (local_offset // w_per_texel).astype(np.int32)
    local_x = (local_offset % w_per_texel).astype(np.int32)

    # Global pixel coords
    px = local_x + np.repeat(min_x_v, areas)
    py = local_y + np.repeat(min_y_v, areas)

    # Barycentric coordinates for all candidates at once
    fi = face_per_texel
    dx = px.astype(np.float32) - uv0[fi, 0]
    dy = py.astype(np.float32) - uv0[fi, 1]

    inv_denom = 1.0 / denom[fi]
    u = (dx * d11[fi] - d01[fi] * dy) * inv_denom
    v = (d00[fi] * dy - dx * d10[fi]) * inv_denom
    w_bary = 1.0 - u - v

    # Filter to texels inside their triangle
    inside = (u >= -0.001) & (v >= -0.001) & (w_bary >= -0.001)
    if not inside.any():
        return

    px_in = px[inside]
    py_in = py[inside]
    fi_in = fi[inside]
    u_in = u[inside]
    v_in = v[inside]
    w_in = w_bary[inside]

    # 3D positions via barycentric interpolation
    pos_3d = (w_in[:, None] * p0[fi_in] +
              u_in[:, None] * p1[fi_in] +
              v_in[:, None] * p2[fi_in])

    # Scatter to texture (last-write wins, same as original)
    positions[py_in, px_in] = pos_3d
    mask[py_in, px_in] = True


def _rasterize_uv_triangles(vertices, faces, uvs, texture_size):
    """
    Rasterize all triangles in UV space (vectorized).

    For each texel covered by a triangle, computes the 3D world position
    via barycentric interpolation.  The entire rasterization is done without
    any Python-level per-triangle loop — all work is batched through NumPy.

    Args:
        vertices: [N, 3] mesh vertices
        faces: [F, 3] triangle indices
        uvs: [N, 2] UV coordinates in [0, 1]
        texture_size: output texture resolution

    Returns:
        positions: [H, W, 3] 3D position at each texel
        mask: [H, W] bool mask of filled texels
    """
    H = W = texture_size
    positions = np.zeros((H, W, 3), dtype=np.float32)
    mask = np.zeros((H, W), dtype=bool)

    n_faces = len(faces)
    if n_faces == 0:
        return positions, mask

    uv_scale = np.array([W - 1, H - 1], dtype=np.float32)

    # Gather per-triangle vertex data (all at once)
    i0, i1, i2 = faces[:, 0], faces[:, 1], faces[:, 2]
    uv0 = uvs[i0] * uv_scale   # [F, 2]
    uv1 = uvs[i1] * uv_scale
    uv2 = uvs[i2] * uv_scale
    p0 = vertices[i0]           # [F, 3]
    p1 = vertices[i1]
    p2 = vertices[i2]

    # Bounding boxes in pixel space, clamped to texture bounds
    all_uv_x = np.stack([uv0[:, 0], uv1[:, 0], uv2[:, 0]], axis=1)  # [F, 3]
    all_uv_y = np.stack([uv0[:, 1], uv1[:, 1], uv2[:, 1]], axis=1)
    bb_min_x = np.clip(np.floor(all_uv_x.min(axis=1)).astype(np.int32), 0, W - 1)
    bb_max_x = np.clip(np.ceil(all_uv_x.max(axis=1)).astype(np.int32), 0, W - 1)
    bb_min_y = np.clip(np.floor(all_uv_y.min(axis=1)).astype(np.int32), 0, H - 1)
    bb_max_y = np.clip(np.ceil(all_uv_y.max(axis=1)).astype(np.int32), 0, H - 1)

    # Barycentric denominator
    d00 = uv1[:, 0] - uv0[:, 0]
    d01 = uv2[:, 0] - uv0[:, 0]
    d10 = uv1[:, 1] - uv0[:, 1]
    d11 = uv2[:, 1] - uv0[:, 1]
    denom = d00 * d11 - d01 * d10

    # Keep only non-degenerate triangles with non-empty bounding boxes
    valid_mask = ((np.abs(denom) >= 1e-10) &
                  (bb_max_x >= bb_min_x) &
                  (bb_max_y >= bb_min_y))
    valid_idx = np.where(valid_mask)[0].astype(np.int32)

    if len(valid_idx) == 0:
        return positions, mask

    # Bbox dimensions and texel counts per valid triangle
    w_bbox = (bb_max_x[valid_idx] - bb_min_x[valid_idx] + 1).astype(np.int64)
    h_bbox = (bb_max_y[valid_idx] - bb_min_y[valid_idx] + 1).astype(np.int64)
    areas = w_bbox * h_bbox

    min_x_v = bb_min_x[valid_idx]
    min_y_v = bb_min_y[valid_idx]

    # Process in chunks to keep memory bounded (~200 MB per chunk)
    MAX_CANDIDATES = 20_000_000
    total_candidates = int(areas.sum())

    if total_candidates <= MAX_CANDIDATES:
        _rasterize_uv_batch(
            valid_idx, areas, w_bbox, min_x_v, min_y_v,
            uv0, d00, d01, d10, d11, denom,
            p0, p1, p2, positions, mask,
        )
    else:
        # Split into chunks of triangles that fit in memory
        chunk_start = 0
        n_valid = len(valid_idx)
        while chunk_start < n_valid:
            cum = np.cumsum(areas[chunk_start:])
            chunk_end = chunk_start + int(np.searchsorted(cum, MAX_CANDIDATES, side="right"))
            chunk_end = max(chunk_end, chunk_start + 1)
            chunk_end = min(chunk_end, n_valid)

            sl = slice(chunk_start, chunk_end)
            _rasterize_uv_batch(
                valid_idx[sl], areas[sl], w_bbox[sl],
                min_x_v[sl], min_y_v[sl],
                uv0, d00, d01, d10, d11, denom,
                p0, p1, p2, positions, mask,
            )
            chunk_start = chunk_end

    return positions, mask


def bake_texture(vertices, faces, uvs, voxel_coords, voxel_attrs, origin, voxel_size,
                 texture_size=2048, k_neighbors=8, **kwargs):
    """
    Bake voxel attributes into a UV-mapped texture.

    Uses scipy cKDTree on sparse voxels for k-nearest-neighbor lookup
    with inverse-distance weighting. Avoids dense 3D volume entirely,
    preserving native voxel resolution without memory pressure.

    Pipeline:
      1. UV rasterize → 3D position per texel
      2. KDTree on sparse voxels
      3. For each texel: k-nearest voxels, inverse-distance-weighted average
      4. Gamma correct, fill holes, export
    """
    from scipy.spatial import cKDTree

    H = W = texture_size
    t0 = time.time()

    coords_np = voxel_coords.numpy() if hasattr(voxel_coords, 'numpy') else voxel_coords
    attrs_np = voxel_attrs.numpy() if hasattr(voxel_attrs, 'numpy') else voxel_attrs
    origin_np = origin.numpy() if hasattr(origin, 'numpy') else np.array(origin)

    C = attrs_np.shape[1]
    n_voxels = len(coords_np)
    print(f"  Voxels: {n_voxels:,}, channels: {C}")

    # Voxel world-space positions (voxel centers)
    voxel_world = coords_np.astype(np.float32) * voxel_size + origin_np + voxel_size * 0.5

    # Build KDTree on voxel positions
    print(f"  Building KDTree...")
    t_tree = time.time()
    tree = cKDTree(voxel_world)
    print(f"    Tree built in {time.time() - t_tree:.1f}s")

    # Rasterize UV triangles to 3D positions
    print(f"  Rasterizing {len(faces):,} triangles into {texture_size}x{texture_size}...")
    t_rast = time.time()
    positions, mask = _rasterize_uv_triangles(vertices, faces, uvs, texture_size)
    coverage = mask.sum() / (H * W) * 100
    print(f"    Coverage: {coverage:.1f}%, rasterized in {time.time() - t_rast:.1f}s")

    # For each valid texel, find k nearest voxels
    query_points = positions[mask]  # [M, 3]
    M = len(query_points)
    print(f"  Querying {M:,} texels, k={k_neighbors}...")
    t_q = time.time()
    distances, indices = tree.query(query_points, k=k_neighbors, workers=-1)
    # distances: [M, k], indices: [M, k]
    print(f"    Query done in {time.time() - t_q:.1f}s")

    # Inverse-distance weighted average. Use distance threshold to skip far voxels.
    # voxel_size is world units per voxel; 2x voxel_size = reasonable neighborhood
    max_dist = voxel_size * 2.0
    print(f"  Weighting colors (max_dist = {max_dist:.4f})...")

    # Weights: 1 / (d + eps), but zero weight for distances > max_dist
    eps = voxel_size * 0.1
    weights = 1.0 / (distances + eps)
    weights[distances > max_dist] = 0.0
    weights_sum = weights.sum(axis=1, keepdims=True)

    # Find texels with at least one nearby voxel
    has_neighbor = (weights_sum > 0).squeeze()

    # Normalize weights
    weights = np.where(weights_sum > 0, weights / np.maximum(weights_sum, 1e-10), 0.0)

    # Gather colors: attrs_np[indices] → [M, k, C]
    neighbor_attrs = attrs_np[indices]  # [M, k, C]

    # Weighted sum over k dimension
    sampled = (neighbor_attrs * weights[..., None]).sum(axis=1)  # [M, C]

    # Write texture
    base_color = np.zeros((H, W, 3), dtype=np.float32)
    metallic = np.zeros((H, W), dtype=np.float32)
    roughness = np.ones((H, W), dtype=np.float32)

    ys, xs = np.where(mask)
    valid = has_neighbor
    base_color[ys[valid], xs[valid]] = np.clip(sampled[valid, 0:3], 0, 1)
    if C > 3:
        metallic[ys[valid], xs[valid]] = np.clip(sampled[valid, 3], 0, 1)
    if C > 4:
        roughness[ys[valid], xs[valid]] = np.clip(sampled[valid, 4], 0, 1)

    valid_mask = np.zeros((H, W), dtype=bool)
    valid_mask[ys[valid], xs[valid]] = True

    # Fill holes via iterative dilation
    from scipy.ndimage import binary_dilation, uniform_filter
    current_mask = valid_mask.copy()
    for _ in range(8):
        dilated = binary_dilation(current_mask, iterations=1)
        unfilled = dilated & ~current_mask
        if not unfilled.any():
            break
        for c in range(3):
            channel = base_color[:, :, c]
            blurred = uniform_filter(channel, size=3)
            channel[unfilled] = blurred[unfilled]
        current_mask = dilated

    # Gamma correction: linear -> sRGB
    base_color = np.power(np.clip(base_color, 0, 1), 1.0 / 2.2)

    base_color_img = (base_color * 255).astype(np.uint8)

    # glTF metallic-roughness: R=0, G=roughness, B=metallic
    mr_img = np.zeros((H, W, 3), dtype=np.uint8)
    mr_img[:, :, 1] = (roughness * 255).astype(np.uint8)
    mr_img[:, :, 2] = (metallic * 255).astype(np.uint8)

    total_coverage = current_mask.sum() / (H * W) * 100
    print(f"  Final coverage: {total_coverage:.1f}%, total bake: {time.time() - t0:.1f}s")

    return base_color_img, mr_img, current_mask


def export_glb_with_texture(vertices, faces, uvs, base_color_img, mr_img=None, output_path="output.glb"):
    """Export mesh with UV-mapped PBR textures as GLB."""
    import trimesh
    from PIL import Image

    mesh = trimesh.Trimesh(vertices=vertices, faces=faces, process=False)

    base_color_pil = Image.fromarray(base_color_img)

    material = trimesh.visual.material.PBRMaterial(
        baseColorTexture=base_color_pil,
        metallicFactor=0.0,
        roughnessFactor=0.8,
    )

    if mr_img is not None:
        mr_pil = Image.fromarray(mr_img)
        material.metallicRoughnessTexture = mr_pil

    mesh.visual = trimesh.visual.TextureVisuals(
        uv=uvs,
        material=material,
    )

    mesh.export(output_path)
    return output_path
