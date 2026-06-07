# Audit Synthesis — Status Report & Remaining Work

Every recommendation from all 5 auditors is catalogued below with its current status: **✅ DONE**, **🔲 REMAINING**, or **❌ REJECTED** (with rationale).

---

## Quick Summary

| Category | Done | Remaining | Rejected |
|---|:---:|:---:|:---:|
| Critical bugs & correctness | 5 | 1 | 0 |
| Sampling / inference speed | 3 | 5 | 1 |
| Post-processing (mesh, bake, export) | 2 | 3 | 0 |
| Memory & thermal management | 1 | 4 | 0 |
| Instrumentation & diagnostics | 2 | 2 | 0 |
| Architecture / framework changes | 0 | 3 | 3 |
| **Total** | **13** | **18** | **4** |

---

## Auditor 1 — Detailed Mapping

### §1 — Reframing the starting assumption
*Context/framing — no action item.*

### §2 — The 80-second mystery (kernel compilation)
| Item | Status | Notes |
|---|---|---|
| Warmup pass after `pipeline.to(mps)` | ✅ DONE | Added `_warmup_pipeline()` in bundled daemon. Runs dummy forward through sparse structure model after load. |
| Diagnostic: two back-to-back gens to verify it's compilation | 🔲 REMAINING | Needs user to run. See [How to verify](#how-to-verify-warmup). |

### §3 — fp16 for the DiT (bf16 → fp16 conversion)
| Item | Status | Notes |
|---|---|---|
| Cast flow models to fp16 at load time | 🔲 REMAINING | Requires numerical validation on 5-10 images. |
| Validate no NaN/Inf in velocity field | 🔲 REMAINING | Prerequisite for above. |

> [!IMPORTANT]
> **How to implement fp16 conversion:**
> After `pipeline = Trellis2ImageTo3DPipeline.from_pretrained(...)`, iterate over the flow models and call `.half()`:
> ```python
> for name in ['sparse_structure_flow_model', 'shape_slat_flow_model_512',
>              'tex_slat_flow_model_512']:
>     if name in pipeline.models:
>         pipeline.models[name] = pipeline.models[name].half()
> ```
> The normalization layers (`MultiHeadRMSNorm`) already upcast to `.float()` internally, so fp32 accumulation is preserved. Risk: the flow-matching velocity field can occasionally spike beyond fp16's max (~65504). If NaN appears, clamp the velocity output or keep bf16 for just the output projection layer.

### §4 — RoPE complex-number CPU fallback
| Item | Status | Notes |
|---|---|---|
| Rewrite RoPE with real-valued cos/sin | ✅ DONE | `patch_rope_real_valued()` replaces both dense and sparse RoPE. |
| Diagnostic: run with `MPS_FALLBACK=0` | 🔲 REMAINING | Optional — verifies whether complex ops were actually falling back. |

### §5 — Attention improvements
| Item | Status | Notes |
|---|---|---|
| §5a: B==1 SDPA skip padding | ✅ DONE | Zero-copy `unsqueeze().permute()` path in `patch_sparse_attention()`. |
| §5b: Batch CFG into B=2 forward | 🔲 REMAINING | Medium effort. See [implementation approach below](#cfg-batching). |
| §5c: Fused varlen Metal attention kernel | 🔲 REMAINING | High effort (weeks). Requires Metal shader + PyTorch C++ extension. |
| §5d: Windowed attention SDPA branch | ❌ REJECTED | Models trained with full attention; switching degrades quality. Code fix is trivial but the trained-weight constraint makes it useless. |

### §6 — `low_vram` unified memory management
| Item | Status | Notes |
|---|---|---|
| Memory-aware `low_vram=False` on ≥48GB | 🔲 REMAINING | Low effort once Phase 3 instrumentation validates memory impact. |
| `PYTORCH_MPS_HIGH_WATERMARK_RATIO=0.0` | 🔲 REMAINING | Gated behind testing — risky if abused. |
| `torch.mps.empty_cache()` between stages | ✅ DONE | Added to `patch_pipeline()` in mps_compat.py. |
| Hoist normalization tensors to device buffers | 🔲 REMAINING | Trivial but minor impact. |

### §7 — Pure-Python sparse conv (`conv_none.py`)
| Item | Status | Notes |
|---|---|---|
| Vectorize `conv_none` rulebook | ❌ REJECTED | The GUI was forcing `conv_none` due to the backend regression. Now that `flex_gemm` auto-detects correctly, `conv_none` only runs on macOS <26 without `flex_gemm`. Not worth optimizing unless that's a deployment target. |

### §8 — CPU-side post-processing
| Item | Status | Notes |
|---|---|---|
| UV rasterizer → Metal | 🔲 REMAINING | Separate Metal shader project. All 5 auditors agree. |
| OBJ export vectorization | ✅ DONE | Replaced f-string loops with numpy batch writes. |
| Mesh extraction vectorization | ✅ DONE | GPU-native `torch.searchsorted` spatial hash. |

### §9 — DINOv3/RMBG → CoreML/ANE
| Item | Status | Notes |
|---|---|---|
| Convert to CoreML with ANE targeting | 🔲 REMAINING | High effort. See [implementation approach below](#coreml-ane). |

### §10 — Apple Silicon runtime realities
| Item | Status | Notes |
|---|---|---|
| Watchdog mitigation via `torch.mps.synchronize()` | ✅ DONE | Added to decode hooks in bundled daemon. |
| Thermal state UI warning | 🔲 REMAINING | Swift side — use `ProcessInfo.processInfo.thermalState`. |
| MPSGraph shape bucketing | 🔲 REMAINING | Needs profiling data. See Auditor 4 §1. |
| Verify Accelerate BLAS for numpy/scipy | 🔲 REMAINING | Trivial diagnostic. |

### §11 — Concurrency / batch pipelining
| Item | Status | Notes |
|---|---|---|
| ANE+GPU+CPU overlap in batch mode | 🔲 REMAINING | Depends on CoreML conversion. High effort. |
| Batch the two DINOv3 encodes | 🔲 REMAINING | Medium effort, standalone win. |

### §12 — Priority table
*Meta item — all individual items tracked above.*

---

## Auditor 2 — Detailed Mapping

### 1. Backend selection regression
| Item | Status | Notes |
|---|---|---|
| Remove forced `SPARSE_CONV_BACKEND=none` | ✅ DONE | Both Swift files fixed. |
| Mirror `generate.py` auto-detection in daemon | ✅ DONE | Bundled daemon now tries `import flex_gemm`. |
| Log selected backend at startup | ✅ DONE | `_audit_pipeline()` emits `backendAudit` JSON. |
| Backend picker in Settings UI | 🔲 REMAINING | Swift UI work. |

### 2. Fused varlen sparse attention
| Item | Status | Notes |
|---|---|---|
| Metal compute shader for varlen attention | 🔲 REMAINING | Same as Auditor 1 §5c. |

### 3. Keep `flex_gemm` hot, don't optimize `conv_none`
*Same conclusion as our approach — `conv_none` optimization deferred.*

### 4. Hot-loaded model device assertion
| Item | Status | Notes |
|---|---|---|
| `assert_model_device()` before generation | 🔲 REMAINING | Low effort defensive check. |

### 5. `torch.inference_mode()`
| Item | Status | Notes |
|---|---|---|
| Gate behind measured flag | 🔲 REMAINING | Trivial to try; needs benchmark. |

### 6. Metal UV rasterizer
*Same as Auditor 1 §8 — 🔲 REMAINING.*

### 7. CPU/GPU transfer audit
| Item | Status | Notes |
|---|---|---|
| Audit every `.cpu()`, `.numpy()`, `.to("mps")` | 🔲 REMAINING | Partially done — mesh extraction now stays on GPU. |
| `log_tensor()` debug transfer logger | 🔲 REMAINING | Nice diagnostic tool. |

### 8. MPS allocator env profiles
| Item | Status | Notes |
|---|---|---|
| Safe / Performance / Diagnostic profiles | 🔲 REMAINING | Expose via Settings UI. |

### 9-10. Memory tiering & viewer suspension
| Item | Status | Notes |
|---|---|---|
| Memory-tier-aware concurrency | 🔲 REMAINING | Policy decision. |
| Suspend RealityKit during inference | 🔲 REMAINING | Swift UI work. |

### 11. Eager pipeline warmup setting
| Item | Status | Notes |
|---|---|---|
| Lazy / Eager / Manual warmup UI | 🔲 REMAINING | Swift UI + daemon protocol. |

### 12. Local model snapshot (skip HF checks)
| Item | Status | Notes |
|---|---|---|
| `local_files_only` loading mode | 🔲 REMAINING | Low effort Python change. |

---

## Auditor 3 — Detailed Mapping

### 1. MLX port of DiT
| Item | Status | Notes |
|---|---|---|
| Full MLX rewrite | ❌ REJECTED | Multi-month rewrite. Sparse tensor support in MLX is uncertain. Stay on PyTorch/MPS. |

### 2. `mmap` / Safetensors cold start
| Item | Status | Notes |
|---|---|---|
| `mmap=True` for "instant" load | ❌ REJECTED | Overstated claim. The 103s includes Python import time + model init, not just file I/O. HF already uses safetensors. The daemon architecture already solves this by staying warm. |

### 3. Custom Metal FlashAttention
*Same as Auditor 1 §5c — 🔲 REMAINING.*

### 4. CoreML/ANE for DINO + RMBG
*Same as Auditor 1 §9 — 🔲 REMAINING.*

### 5. Metal compute shaders for post-processing
*UV rasterizer, KDTree, mesh extraction — same as Auditor 1 §8.*
*Mesh extraction: ✅ DONE (GPU-native via torch.searchsorted).*
*UV rasterizer: 🔲 REMAINING.*

### 6. DPM-Solver (cut steps 12→6)
| Item | Status | Notes |
|---|---|---|
| Integrate higher-order ODE solver | ❌ REJECTED | Flow-matching models are trained with specific solvers. Changing the solver requires quality validation that may not hold. The "zero quality loss" claim is unsupported for this specific architecture. |

### 7. Shared Memory IPC / QoS tuning
| Item | Status | Notes |
|---|---|---|
| POSIX shm / IOSurface for zero-copy IPC | 🔲 REMAINING | Architectural change. GLB files work fine for now. |
| QoS tuning for Swift tasks | 🔲 REMAINING | Swift side. |

---

## Auditor 4 — Detailed Mapping

### 1. Shape bucketing (static shapes for MPSGraph)
| Item | Status | Notes |
|---|---|---|
| Pad sparse tensors to power-of-2 buckets | 🔲 REMAINING | Interesting idea. Needs profiling to determine if MPSGraph recompilation is actually a bottleneck after warmup. |

### 2. MLX port
*Same as Auditor 3 §1 — ❌ REJECTED.*

### 3. bf16 → fp16 conversion
*Same as Auditor 1 §3 — 🔲 REMAINING.*

### 4. Custom ragged/varlen Metal attention
*Same as Auditor 1 §5c — 🔲 REMAINING.*

### 5. Metal mesh extraction & texture baking
*Mesh extraction: ✅ DONE. UV rasterizer: 🔲 REMAINING.*

### 6. CoreML/ANE offloading
*Same as Auditor 1 §9 — 🔲 REMAINING.*

### 7. Zero-copy IPC (shared memory)
*Same as Auditor 3 §7 — 🔲 REMAINING.*

### 8. QoS & GPU duty cycle throttling
| Item | Status | Notes |
|---|---|---|
| Micro-delays between diffusion steps | 🔲 REMAINING | Low effort, needs benchmarking for actual thermal impact. |

---

## Auditor 5 — Detailed Mapping

### 1. "Random weights" bug (`conv_none` key mismatch)
| Item | Status | Notes |
|---|---|---|
| `_load_state_dict_pre_hook` for key remapping | 🔲 REMAINING | Needs verification first. The claim may be incorrect — `conv_none` defines `self.weight` directly and the init permutes to match `flex_gemm` layout. But a diagnostic check is warranted. |

### 2A. GPU-native spatial hashing
| Item | Status | Notes |
|---|---|---|
| Replace NumPy hash with `torch.searchsorted` | ✅ DONE | Implemented exactly as Auditor 5 described. |

### 2B. B=1 zero-copy attention
| Item | Status | Notes |
|---|---|---|
| SDPA fast-path for B==1 | ✅ DONE | Implemented with `unsqueeze().permute()`. |

### 3A. Watchdog yielding
| Item | Status | Notes |
|---|---|---|
| `torch.mps.synchronize()` in decode hooks | ✅ DONE | Added to both shape and texture decode hooks. |

### 3B. MPS empty cache leak
| Item | Status | Notes |
|---|---|---|
| Add `torch.mps.empty_cache()` | ✅ DONE | Added to `patch_pipeline()`. |

### 4. ANE offloading for RMBG
| Item | Status | Notes |
|---|---|---|
| Use `VNGenerateForegroundInstanceMaskRequest` | 🔲 REMAINING | Swift-only approach, interesting alternative to CoreML conversion. |

### 5A. Zero-copy IPC
*Same as Auditor 3 §7 — 🔲 REMAINING.*

### 5B. Metal UV rasterization
*Same as Auditor 1 §8 — 🔲 REMAINING.*

---

## Remaining Work — Prioritized

Ordered by return-on-effort, with prerequisites and implementation approach.

### Tier 1: High ROI, Low-Medium Effort

#### 1. fp16 for DiT Flow Models
- **Auditors:** 1, 3, 4
- **Effort:** Low (code) + Medium (validation)
- **Prerequisite:** None
- **Expected impact:** 1.2-1.6× sampling speedup (~114s → ~70-95s)
- **How:**
  1. After `from_pretrained`, call `.half()` on each flow model
  2. Run 5-10 test images, compare meshes vertex-by-vertex against bf16 baseline
  3. Check for NaN/Inf in sampled latents
  4. If overflow: clamp velocity output or keep bf16 for output projection only
- **Risk:** Medium — fp16 range is 5-bit exponent vs bf16's 8-bit. Flow velocity can spike.

#### 2. `low_vram=False` on ≥48GB Machines
- **Auditors:** 1, 2, 3
- **Effort:** Low
- **Prerequisite:** Phase 3 instrumentation (done) to measure memory impact
- **Expected impact:** Eliminates model CPU↔GPU shuffling on every generation
- **How:**
  1. Read physical RAM from `SystemInfoProvider.memoryString`
  2. Pass `--low-vram=false` to daemon when RAM ≥ 48GB
  3. For 32-48GB, only disable for `512` pipeline type
  4. Test memory usage with Activity Monitor
- **Risk:** Low — worst case is OOM, gate conservatively

#### 3. `torch.inference_mode()` Wrapper
- **Auditors:** 2
- **Effort:** Trivial
- **Prerequisite:** None
- **Expected impact:** Small — may reduce autograd overhead beyond `no_grad()`
- **How:** Wrap `pipeline.run()` in `torch.inference_mode()` context. Gate behind env var. Validate same outputs.

#### 4. Verify Warmup Actually Helps
- **Auditors:** 1, 2, 4
- **Effort:** Trivial (user runs 2 generations)
- **Prerequisite:** Warmup already implemented
- **How:** Run two generations back-to-back. If gen-1 sparse structure is ~80s and gen-2 is ~25s, warmup is working. If both are ~80s, the cost is real compute, not compilation, and fp16 (item 1) becomes more critical.

#### 5. Hot-loaded Model Device Assertion
- **Auditors:** 2
- **Effort:** Trivial
- **How:** Add `assert_model_device(model, "mps")` before generation. Already have `_audit_pipeline()` — extend to check hot-loaded models.

---

### Tier 2: Medium ROI, Medium Effort

<a id="cfg-batching"></a>
#### 6. CFG Batching (B=2 Single Forward)
- **Auditors:** 1
- **Effort:** Medium
- **Prerequisite:** B==1 fast-path (done)
- **Expected impact:** ~halve kernel-launch overhead per sampling step
- **How:**
  1. In `ClassifierFreeGuidanceSamplerMixin._inference_model`, stack cond+uncond into one B=2 `SparseTensor` (batch index 0=cond, 1=uncond)
  2. Run single forward pass
  3. Split output along batch dim
  4. SDPA naturally keeps samples separate (block-diagonal)
  5. Gate on memory: ~2× activation memory during attention
- **Risk:** Low-medium (memory on 24GB machines)

#### 7. Shape Bucketing for MPSGraph Cache
- **Auditors:** 4
- **Effort:** Medium
- **Prerequisite:** Verify warmup impact first (item 4)
- **How:** Pad sparse tensor coordinate/feature arrays to nearest multiple of 256 before ops. Add dummy voxels at `[-999,-999,-999]`, mask out in output. This ensures `MPSGraph` hits cached compiled kernels.
- **Risk:** Low — padding adds negligible compute

#### 8. Local Model Snapshot Loading
- **Auditors:** 2
- **Effort:** Low
- **How:** After initial download, use `local_files_only=True` in `from_pretrained()`. Skip HF Hub checks during normal generation.

#### 9. Thermal State Warning in UI
- **Auditors:** 1, 4
- **Effort:** Low (Swift)
- **How:** Check `ProcessInfo.processInfo.thermalState` before generation. Show warning if `.serious` or `.critical`. Monitor during generation and log.

#### 10. MPS Env Profiles in Settings
- **Auditors:** 2
- **Effort:** Low-medium (Swift UI)
- **How:** Add a picker: Safe (default) / Performance (`FAST_MATH=1`, higher watermarks) / Diagnostic (`LOG_PROFILE_INFO=1`, `TRACE_SIGNPOSTS=1`)

---

### Tier 3: High ROI, High Effort (Projects)

#### 11. Metal UV Rasterizer
- **Auditors:** ALL 5
- **Effort:** High (1-2 weeks)
- **Expected impact:** 15-20s → <10ms for UV rasterization
- **How:**
  1. Create `MTLRenderPipelineState` in Swift
  2. Pass 2D UV coords as vertex positions, 3D world coords as varyings
  3. Fragment shader writes hardware-interpolated 3D position to texture
  4. Metal's hardware rasterizer does this natively in <5ms
  5. Keep Python fallback for environments without Metal
- **Prerequisite:** Can be done independently of all other work

<a id="coreml-ane"></a>
#### 12. CoreML/ANE for DINOv3 + RMBG
- **Auditors:** 1, 3, 4, 5
- **Effort:** High
- **Expected impact:** Lower thermals (ANE draws ~1W vs GPU ~15W), frees GPU memory
- **How:**
  1. Export DINOv3 ViT-L to CoreML with `coremltools.convert()`
  2. Follow Apple's `ml-ane-transformers` layout: 4D tensors, split-einsum attention
  3. Set `MLComputeUnits = .cpuAndNeuralEngine`
  4. For RMBG, consider Auditor 5's suggestion: use `VNGenerateForegroundInstanceMaskRequest` (built-in, zero effort) instead of converting the model
  5. Keep MPS fallback path
- **Caveat:** Latency win is small for single generation (preprocessing runs before GPU is busy). Main win is thermal + batch mode.

#### 13. Fused Varlen Metal Attention Kernel
- **Auditors:** 1, 2, 3, 4
- **Effort:** Very high (2-4 weeks)
- **Expected impact:** Potentially the largest inference ceiling-raiser
- **Prerequisite:** Confirm with profiler that SDPA is actually running unfused `bmm+softmax+bmm` triple, not the efficient kernel
- **How:**
  1. Write Metal compute shader: tile over K/V, maintain running max+sum for stable softmax, never materialize T×T score matrix
  2. Accept packed `q/k/v` + offset arrays directly (no padding)
  3. Specialize for head_dim=128 (the model's value)
  4. Expose via `torch.utils.cpp_extension` or PyObjC
  5. Keep padded SDPA as fallback
  6. Correctness test against existing padded path

---

### Tier 4: Low ROI or Speculative

| # | Item | Why Low Priority |
|---|---|---|
| 14 | Shared memory IPC (IOSurface/shm) | GLB files are <2s. Architectural change for marginal gain. |
| 15 | GPU duty cycle micro-delays | May help thermals, but unclear vs. just reducing compute (fp16). |
| 16 | Batch DINOv3 encodes (512+1024) | Only helps cascade mode. Single forward is already fast. |
| 17 | Suspend RealityKit during inference | Low impact unless viewer is rendering complex scenes. |
| 18 | CPU BLAS Accelerate verification | Trivial diagnostic: `numpy.show_config()`. |

---

## Rejected Items — Full Rationale

| Item | Auditor | Reason |
|---|---|---|
| **MLX port of DiT** | 3, 4 | Multi-month rewrite. MLX lacks sparse tensor support equivalent to what TRELLIS needs. The PyTorch/MPS path with our optimizations is already fast. |
| **`mmap=True` for "instant" load** | 3 | Claimed 103s→2s is wildly overstated. The 103s includes Python import time, model class instantiation, and TRELLIS module initialization — not just file I/O. HF already uses safetensors with efficient loading. The persistent daemon architecture already amortizes this to zero per-generation. |
| **DPM-Solver (cut steps 12→6)** | 3 | Flow-matching models are trained with a specific solver (Euler + flow-matching ODE). Switching to DPM-Solver++ requires the model to have been trained with the noise prediction formulation, not velocity. The "zero quality loss" claim is unsupported for this architecture. |
| **Windowed attention SDPA branch** | 1 | The SLAT models were trained with full attention. Switching to windowed attention at inference would degrade output quality. The code fix is trivial but the trained-weight constraint makes it useless. |

---

## Verification Checklist for Remaining Work

<a id="how-to-verify-warmup"></a>
### Verify Warmup (Do This First)
```bash
# Run two generations back-to-back in one daemon session.
# Compare sparse structure stage times.
# If gen-1 SS ≈ 80s and gen-2 SS ≈ 25s → warmup works.
# If both ≈ 80s → warmup doesn't help, focus on fp16.
```

### Verify RoPE Fix
```bash
# Set PYTORCH_ENABLE_MPS_FALLBACK=0 and run one generation.
# If it succeeds → complex ops now have MPS kernels (our fix was defensive).
# If it crashes with aten::polar or aten::view_as_complex → our fix was critical.
```

### Verify Backend Selection
```text
Look for the backendAudit JSON response in daemon logs.
Expected: sparse_conv_backend = "flex_gemm" (not "none")
If still "none": flex_gemm package not installed in the venv.
```
