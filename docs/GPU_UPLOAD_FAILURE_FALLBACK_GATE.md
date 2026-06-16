# GPU Upload Failure Fallback Gate

Date: 2026-06-16

Scope: Phase 6 upload robustness. This records the opt-in runtime failure-injection gate used to prove that visual terrain, shadow casting, and collision stay valid when GPU terrain upload requests fail. It does not change default upload behavior, upload capacity, allocator policy, retry/backoff policy, draw distance, lighting, shadows, texture quality, protocol, storage, world generation, chunk serialization, or visible quality.

## Diagnostic Flag

`RUMPELMC_GPU_TERRAIN_UPLOAD_FAILURE_INJECTION=1` forces non-empty GPU subchunk upload requests to fail inside the GPU terrain upload path.

When the flag is enabled:

- the affected subchunk GPU slot is removed before the failure is reported, matching the stale-slot behavior expected after a real failed replacement upload;
- `gpu_upload_fail` increments;
- `gpu_upload_fail_injected` increments;
- `gpu_upload_fail_capacity` and `gpu_upload_fail_fragmented` remain `0`;
- retry/backoff telemetry stays at the current policy: `gpu_upload_retry_policy=none` and all retry/backoff counters `0`.

Unset or `0` keeps the normal upload path and must keep `gpu_upload_fail_injected=0`.

## Gate

Use the dedicated wrapper for visual/shadow/collision fallback evidence:

```sh
RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE=1 \
RUMPELMC_GODOT_RUST_EXT_PROFILE=release \
sh scripts/gpu_terrain_upload_failure_fallback_gate.sh logs/gpu_upload_failure_fallback_current
```

The wrapper runs movement stress with:

- `RUMPELMC_GPU_TERRAIN_UPLOAD_FAILURE_INJECTION=1`
- `RUMPELMC_MOVEMENT_STRESS_GPU_UPLOAD_FAILURE_MODE=injected`
- `RUMPELMC_MOVEMENT_STRESS_BUDGET_MODE=report`
- an isolated RocksDB path

Required evidence:

- `gpu_upload_fail >= 1`
- `gpu_upload_fail_injected >= 1`
- `gpu_upload_fail_capacity=0`
- `gpu_upload_fail_fragmented=0`
- `gpu_uploads=0`
- `gpu_subchunks=0`
- `shadow_path=arraymesh`
- `mesh_visible >= 1`
- `mesh_shadow_double >= 1`
- `movement_readiness current_render_ready=1`
- `movement_readiness current_collision_ready=1`
- `current_chunk_collision >= 1`
- `ground_misses=0`
- `terrain_samples >= 1`

The gate writes `gpu-upload-failure-fallback-summary.txt`.

Terrain queue budget is report-only in this gate because the test intentionally forces the world to stay on CPU ArrayMesh fallback. Normal GPU movement and upload budget gates still enforce their performance budgets with `gpu_upload_fail=0`.

## Evidence

Fresh 2026-06-16 release evidence:

- `logs/gpu_upload_failure_fallback_current/gpu-upload-failure-fallback-summary.txt`
- `gpu_upload_fail=1052`
- `gpu_upload_fail_injected=1052`
- `gpu_upload_fail_capacity=0`
- `gpu_upload_fail_fragmented=0`
- `gpu_uploads=0`
- `gpu_subchunks=0`
- `mesh_visible=788`
- `mesh_shadow_double=788`
- `shadow_path=arraymesh`
- `current_render_ready=1`
- `current_collision_ready=1`
- `current_chunk_collision=2`
- `ground_misses=0`
- `terrain_samples=384`

## Movement Stress Modes

`scripts/gpu_terrain_movement_stress.sh` now supports two upload-failure validation modes:

- `RUMPELMC_MOVEMENT_STRESS_GPU_UPLOAD_FAILURE_MODE=zero`: default normal performance mode. Requires GPU frames, GPU subchunks, GPU uploads, and all upload failure counters including `gpu_upload_fail_injected` to stay `0`.
- `RUMPELMC_MOVEMENT_STRESS_GPU_UPLOAD_FAILURE_MODE=injected`: diagnostic mode. Allows GPU subchunks/uploads to stay at `0`, but requires `gpu_upload_fail` and `gpu_upload_fail_injected` to reach `RUMPELMC_MOVEMENT_STRESS_MIN_GPU_UPLOAD_FAILURES` while capacity and fragmentation failure counters stay `0`.

## Guardrails

- Do not enable `RUMPELMC_GPU_TERRAIN_UPLOAD_FAILURE_INJECTION` in normal performance baselines.
- Do not interpret injected failures as real allocator pressure.
- Keep real capacity and fragmentation evidence in allocator/load gates.
- Do not remove CPU ArrayMesh fallback while a subchunk lacks a confirmed GPU slot.
- A future retry/backoff policy must keep the same visual, shadow, and collision fallback guarantees while retries are pending or exhausted.

## External References

- Godot `RenderingDevice` is the project's low-level GPU abstraction and has explicit buffer update/list constraints: <https://docs.godotengine.org/en/stable/classes/class_renderingdevice.html>
- Khronos Vulkan staging-buffer guidance keeps CPU-accessible staging separate from device-local GPU buffers and recommends allocator reuse for many objects: <https://docs.vulkan.org/tutorial/latest/04_Vertex_buffers/02_Staging_buffer.html>
- Apple Metal recommends triple buffering/reusable dynamic buffers to avoid per-frame allocation churn: <https://developer.apple.com/library/archive/documentation/3DDrawing/Conceptual/MTLBestPracticesGuide/TripleBuffering.html>
- Apple Metal resource options document macOS discrete memory behavior and storage-mode choices: <https://developer.apple.com/library/archive/documentation/3DDrawing/Conceptual/MTLBestPracticesGuide/ResourceOptions.html>
