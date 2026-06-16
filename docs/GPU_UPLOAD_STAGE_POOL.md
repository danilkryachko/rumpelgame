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

The gate runs four isolated captures:

- Movement baseline with `RUMPELMC_GPU_TERRAIN_UPLOAD_STAGE_POOL=0`.
- Movement pooled with `RUMPELMC_GPU_TERRAIN_UPLOAD_STAGE_POOL=1`.
- In-place dirty upload baseline with `RUMPELMC_GPU_TERRAIN_UPLOAD_STAGE_POOL=0`.
- In-place dirty upload pooled with `RUMPELMC_GPU_TERRAIN_UPLOAD_STAGE_POOL=1`.

Each baseline must keep the pool disabled and report zero pooled `PackedByteArray` creates/reuses. Each pooled run must show at least one pool entry, at least one create, at least the configured reuse count, fewer creates than total uploads, and zero upload failure/retry/backoff activity. The in-place lane also proves the same-face-count dirty upload path still executes while the staging pool is enabled.

## Load-Scaling Gate

Run the high resident-set comparison gate before treating the stage pool as broadly validated:

```sh
RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE=1 \
RUMPELMC_GODOT_RUST_EXT_PROFILE=release \
GODOT_QUIT_AFTER_FRAMES=36000 \
GODOT_TIMEOUT_SEC=600 \
sh scripts/gpu_terrain_upload_stage_pool_load_scaling_gate.sh logs/gpu_terrain_upload_stage_pool_load_scaling_current
```

The gate runs baseline and pooled `scripts/gpu_terrain_load_scaling.sh` captures against isolated RocksDB paths unless `RUMPELMC_GPU_STAGE_POOL_LOAD_BASELINE_SUMMARY` and `RUMPELMC_GPU_STAGE_POOL_LOAD_POOLED_SUMMARY` point at existing `gpu-terrain-load-scaling-summary.txt` files. By default it uses the `pressure` workload case with a `chunk_disc` visual-smoke terrain pressure fixture inside the current client keep radius, then requires the high resident-set pressure thresholds (`2000` subchunks, `2000` draws, `3000` faces, `25%` draw-command occupancy), queue/process/submit within the 150 FPS budget, and zero upload failures. The baseline must report pool enabled/creates/reuses as `0/0/0`; the pooled run must report the pool enabled with nonzero entries/bytes/creates/reuses and fewer creates than total uploads. Summary-only mode rejects older load-scaling summaries that lack `source_case_set`, terrain-pressure fixture fields, or upload/stage-pool counters.

## Fresh Evidence

Fresh local release evidence from `logs/gpu_terrain_upload_stage_pool_current/gpu-terrain-upload-stage-pool-summary.txt`:

- Movement baseline: `movement_baseline_uploads=850`, pool enabled/creates/reuses `0/0/0`, upload failures `0`.
- Movement pooled: `movement_pooled_uploads=851`, pool enabled `1`, entries `8`, bytes `720`, creates `8`, reuses `843`, upload failures `0`.
- In-place baseline: `in_place_baseline_uploads=853`, `in_place_baseline_in_place_uploads=1`, pool enabled/creates/reuses `0/0/0`, upload failures `0`.
- In-place pooled: `in_place_pooled_uploads=853`, `in_place_pooled_in_place_uploads=1`, pool enabled `1`, entries `8`, bytes `720`, creates `8`, reuses `845`, upload failures `0`.
- Pooled dirty upload summary stayed within local CPU-side budgets: `terrain_queue_max_ms=2.141`, `process_wall_p95_ms=0.054`, `gpu_compositor_submit_max_ms=0.148`, retry/backoff `none/0`.

Fresh 2026-06-16 load-scaling evidence from `logs/gpu_terrain_upload_stage_pool_load_scaling_current/gpu-terrain-upload-stage-pool-load-scaling-summary.txt`:

- Baseline lane passed with `source_case_set=pressure`, `terrain_pressure_fixture=chunk_disc`, `terrain_pressure_fixture_blocks=709`, `max_gpu_subchunks=2289`, `max_gpu_draws=2289`, `max_gpu_faces=6292`, draw-command occupancy `27.942%`, `max_terrain_queue_ms=1.432`, `max_process_wall_p95_ms=0.031`, `max_gpu_compositor_submit_ms=0.119`, `baseline_uploads=3135`, upload failures `0`, and pool enabled/entries/bytes/creates/reuses `0/0/0/0/0`.
- Pooled lane passed on the same pressure with `max_gpu_subchunks=2289`, `max_gpu_draws=2289`, `max_gpu_faces=6292`, draw-command occupancy `27.942%`, `max_terrain_queue_ms=1.518`, `max_process_wall_p95_ms=0.029`, `max_gpu_compositor_submit_ms=0.157`, `pooled_uploads=3137`, upload failures `0`, pool enabled `1`, entries `9`, bytes `816`, creates `9`, and reuses `3128`.
- Summary-only negative validation over the older radius-16 summary failed with `missing source_case_set`, proving stale pre-fixture summaries are rejected.

The pool remains default-off. This is local macOS/Metal runtime evidence; Windows/Vulkan/Direct3D profiler validation and any default-on rollout remain separate work.

## Rollout Rules

- Keep the pool default-off until broader movement, in-place dirty update, upload-pressure, resident-set/load-scaling, and external profiler evidence all support enabling it by default.
- Do not use this pool to hide upload failures, retry/backoff activity, or allocator pressure.
- Do not change visible quality or default streaming distances as part of this optimization.
- Windows/Vulkan/Direct3D profiler validation remains separate work before treating this as cross-platform performance evidence.
