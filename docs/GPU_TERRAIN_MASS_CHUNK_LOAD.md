# GPU Terrain Mass Chunk Load

Date: 2026-06-16

Scope: Phase 5 mass chunk-load stress. This gate combines the high resident-set GPU terrain load-scaling evidence with the per-frame upload budget evidence. It does not change draw distance defaults, chunk unload policy, upload capacity, allocator policy, protocol, storage, world generation, chunk serialization, lighting, shadows, texture quality, or visible quality.

## Current Decision

Treat mass chunk-load as a two-part requirement:

- the renderer must prove a high resident set with thousands of GPU subchunks, draws, and faces;
- the upload path must still stay inside the current total/new-slot/replacement-slot per-frame upload budget, with zero upload failures.

This is intentionally a governance/evidence gate. It is not runtime throttling and it is not a reason to lower visual quality.

## Gate

Use:

```sh
sh scripts/gpu_terrain_mass_chunk_load_gate.sh logs/gpu_terrain_mass_chunk_load_current
```

Default inputs:

- `logs/gpu_terrain_load_scaling_radius16_summary_check/gpu-terrain-load-scaling-summary.txt`
- `logs/gpu_terrain_upload_budget_current/gpu-terrain-upload-budget-summary.txt`

If a fresh high-resident capture is needed, regenerate the load-scaling input first:

```sh
RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE=1 \
RUMPELMC_GODOT_RUST_EXT_PROFILE=release \
sh scripts/gpu_terrain_load_scaling.sh logs/gpu_terrain_load_scaling_radius16_summary_check
```

The gate requires, by default:

- `max_gpu_subchunks >= 2000`
- `max_gpu_draws >= 2000`
- `max_gpu_faces >= 3000`
- draw-command occupancy at least `25%`
- `max_terrain_queue_ms <= 6.667`
- `max_process_wall_p95_ms <= 6.667`
- `max_gpu_compositor_submit_ms <= 6.667`
- load-scaling upload failures, capacity failures, and fragmentation failures equal `0`
- upload-budget status `pass`, including movement and in-place upload lanes

Override `RUMPELMC_GPU_MASS_LOAD_*` thresholds only for explicit experiments or negative validation.

## Evidence

Fresh local evidence:

- `logs/gpu_terrain_load_scaling_radius16_summary_check/gpu-terrain-load-scaling-summary.txt`
- `logs/gpu_terrain_upload_budget_current/gpu-terrain-upload-budget-summary.txt`
- `logs/gpu_terrain_mass_chunk_load_current/gpu-terrain-mass-chunk-load-summary.txt`
- Status: `pass`
- Reason: `mass_load_within_budget`
- Resident pressure: `2482` GPU subchunks, `2482` GPU draws, `3165` GPU faces
- Draw-command occupancy: `30.298%` with `91360` bytes of headroom
- CPU-side budgets: terrain queue `2.214ms`, process wall p95 `0.059ms`, compositor submit `5.677ms`; all under the `6.667ms` target budget
- Load-scaling and upload-budget upload failures: `0`
- Upload budget carried into the mass-load check: movement uploads `1/1`, movement payload `0.2/2.0 KiB`, movement/in-place new-slot maxima `1/1`, movement/in-place replacement-slot maxima `1/1`

Negative validation example:

```sh
RUMPELMC_GPU_MASS_LOAD_MIN_GPU_SUBCHUNKS=999999 \
sh scripts/gpu_terrain_mass_chunk_load_gate.sh logs/gpu_terrain_mass_chunk_load_negative
```

Expected result: failure with `reason=mass_subchunk_pressure`.

## Guardrails

- Do not lower draw distance, lighting, shadows, texture quality, or visible quality to pass this gate.
- Do not use a passing mass-load gate alone to enable buffer repack, allocator changes, upload pooling, or retry/backoff behavior.
- Keep world-load pressure (`new-slot` upload lane) separate from dirty/update pressure (`replacement-slot` upload lane).
- Keep macOS/Metal local FPS and Godot GPU timestamps report-only until external profiler data proves they are reliable.
- Rebaseline deliberately when transparent terrain, native shadows, larger worlds, or Windows profiler captures create a stable higher pressure envelope.

## External References

- Godot `RenderingDevice.buffer_update` updates a byte range and errors when a draw or compute list is active, so upload gates must keep update timing and active-list boundaries visible: <https://docs.godotengine.org/en/stable/classes/class_renderingdevice.html>
- Vulkan synchronization examples use explicit staging and transfer dependencies for CPU-to-GPU uploads, which matches the need to measure upload pressure separately from draw pressure: <https://docs.vulkan.org/guide/latest/synchronization_examples.html>
- Apple Metal recommends choosing resource storage modes by CPU/GPU access pattern on macOS and avoiding per-frame buffer creation for dynamic data through reusable buffering: <https://developer.apple.com/library/archive/documentation/3DDrawing/Conceptual/MTLBestPracticesGuide/ResourceOptions.html> and <https://developer.apple.com/library/archive/documentation/3DDrawing/Conceptual/MTLBestPracticesGuide/TripleBuffering.html>
