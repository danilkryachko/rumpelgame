# GPU Upload Stage Pool

This note records the default-off GPU terrain upload staging pool prototype. The goal is to reduce CPU-side `PackedByteArray` allocation churn in the hot upload path without changing GPU face data layout, draw distance, lighting, shadows, texture quality, protocol, storage, world generation, or chunk serialization.

## Runtime Flag

- `RUMPELMC_GPU_TERRAIN_UPLOAD_STAGE_POOL=1` enables the prototype.
- Unset or `0` keeps the current upload path.
- The flag is intentionally separate from GPU render/upload enablement so baseline runs can compare the exact same world workload with and without pooled staging.

## Design

- The existing packed-face upload scratch buffer remains the first staging layer.
- When the flag is enabled, the upload path reuses an exact-size `PackedByteArray` per payload length before calling `RenderingDevice::buffer_update`.
- The pool is per `GpuTerrainBufferPool`, so it is scoped to the renderer resource owner and is dropped with the buffer pool.
- The pool is exact-size instead of over-allocating so staged payload length still matches the `buffer_update` payload.
- Metrics are emitted in the normal GPU terrain perf marker:
  - `gpu_upload_stage_pool_enabled`
  - `gpu_upload_stage_pool_entries`
  - `gpu_upload_stage_pool_bytes`
  - `gpu_upload_stage_pba_creates`
  - `gpu_upload_stage_pba_reuses`

This follows the same broad direction as GPU API guidance to keep upload resources reusable. Godot exposes low-level `RenderingDevice` buffer creation/update APIs, Vulkan documents the common staging-buffer pattern for device-local upload, and Apple's Metal guidance recommends reusing persistent resources and avoiding per-frame buffer creation for dynamic data.

References:

- [Godot RenderingDevice](https://docs.godotengine.org/en/stable/classes/class_renderingdevice.html)
- [Vulkan staging buffer tutorial](https://docs.vulkan.org/tutorial/latest/04_Vertex_buffers/02_Staging_buffer.html)
- [Apple Metal triple buffering](https://developer.apple.com/library/archive/documentation/3DDrawing/Conceptual/MTLBestPracticesGuide/TripleBuffering.html)
- [Apple Metal resource options](https://developer.apple.com/library/archive/documentation/3DDrawing/Conceptual/MTLBestPracticesGuide/ResourceOptions.html)
- [Apple Metal persistent objects](https://developer.apple.com/library/archive/documentation/3DDrawing/Conceptual/MTLBestPracticesGuide/PersistentObjects.html)

## Gate

Run:

```sh
RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE=1 \
RUMPELMC_GODOT_RUST_EXT_PROFILE=release \
GODOT_QUIT_AFTER_FRAMES=30000 \
GODOT_TIMEOUT_SEC=240 \
sh scripts/gpu_terrain_upload_stage_pool_gate.sh logs/gpu_terrain_upload_stage_pool_current
```

The gate runs two isolated movement stress captures:

- Baseline with `RUMPELMC_GPU_TERRAIN_UPLOAD_STAGE_POOL=0`.
- Pooled with `RUMPELMC_GPU_TERRAIN_UPLOAD_STAGE_POOL=1`.

The baseline must keep the pool disabled and report zero pooled `PackedByteArray` creates/reuses. The pooled run must show at least one pool entry, at least one create, at least the configured reuse count, fewer creates than total uploads, and zero upload failure/retry/backoff activity.

## Fresh Evidence

Fresh local release evidence from `logs/gpu_terrain_upload_stage_pool_current/gpu-terrain-upload-stage-pool-summary.txt`:

- Baseline: `baseline_uploads=850`, `baseline_stage_pool_enabled=0`, `baseline_stage_pba_creates=0`, `baseline_stage_pba_reuses=0`, upload failures `0`.
- Pooled: `pooled_uploads=850`, `pooled_stage_pool_enabled=1`, `pooled_stage_pool_entries=8`, `pooled_stage_pool_bytes=720`, `pooled_stage_pba_creates=8`, `pooled_stage_pba_reuses=842`, upload failures `0`.
- Pooled movement summary stayed within the local CPU-side budgets: `terrain_queue_max_ms=1.993`, `process_wall_p95_ms=0.052`, `gpu_compositor_submit_max_ms=0.145`.

## Rollout Rules

- Keep the pool default-off until broader movement, in-place dirty update, upload-pressure, resident-set/load-scaling, and external profiler evidence all support enabling it by default.
- Do not use this pool to hide upload failures, retry/backoff activity, or allocator pressure.
- Do not change visible quality or default streaming distances as part of this optimization.
- Windows/Vulkan/Direct3D profiler validation remains separate work before treating this as cross-platform performance evidence.
