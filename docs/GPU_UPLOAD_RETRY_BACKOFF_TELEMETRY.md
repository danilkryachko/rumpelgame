# GPU Upload Retry/Backoff Telemetry

Date: 2026-06-16

Scope: Phase 5 upload pipeline telemetry. This records the current GPU terrain upload retry/backoff policy and exposes it in runtime markers, summaries, reports, and budget gates. It does not add a retry loop and does not change upload capacity, allocator policy, draw distance, lighting, shadows, texture quality, protocol, storage, world generation, chunk serialization, or visible quality.

## Current Decision

The current GPU terrain upload policy is `none`: an allocation failure is counted as an upload failure and classified as capacity or fragmentation, but the renderer does not retry the upload in the same frame and does not enter a backoff window. The new telemetry makes that policy explicit so a future retry/backoff implementation must update tests and gates deliberately.

Runtime marker fields:

- `gpu_upload_retry_policy=none`
- `gpu_upload_retry_attempts=0`
- `gpu_upload_retry_success=0`
- `gpu_upload_retry_giveups=0`
- `gpu_upload_backoff_active=0`
- `gpu_upload_backoff_frames=0`
- `gpu_upload_backoff_max_frames=0`

## Gates

Movement stress now requires the marker fields above and fails if retry/backoff activity appears under the current policy:

```sh
RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE=1 \
RUMPELMC_GODOT_RUST_EXT_PROFILE=release \
GODOT_QUIT_AFTER_FRAMES=36000 \
GODOT_TIMEOUT_SEC=300 \
sh scripts/gpu_terrain_movement_stress.sh logs/gpu_upload_retry_backoff_movement_current
```

In-place upload evidence carries the same checks for the dirty-update replacement path:

```sh
RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE=1 \
RUMPELMC_GODOT_RUST_EXT_PROFILE=release \
GODOT_QUIT_AFTER_FRAMES=36000 \
GODOT_TIMEOUT_SEC=300 \
sh scripts/gpu_terrain_in_place_upload_gate.sh logs/gpu_upload_retry_backoff_in_place_current
```

The upload budget gate now consumes the movement and in-place retry/backoff fields and fails with `reason=upload_retry_backoff_budget` if any current-policy retry/backoff activity is observed:

```sh
RUMPELMC_GPU_UPLOAD_BUDGET_MOVEMENT_SUMMARY=logs/gpu_upload_retry_backoff_movement_current/movement-stress-summary.txt \
RUMPELMC_GPU_UPLOAD_BUDGET_IN_PLACE_SUMMARY=logs/gpu_upload_retry_backoff_in_place_current/gpu-in-place-upload-summary.txt \
sh scripts/gpu_terrain_upload_budget.sh logs/gpu_upload_retry_backoff_budget_current
```

## Evidence

Fresh local macOS/Metal evidence:

- Movement: `logs/gpu_upload_retry_backoff_movement_current/movement-stress-summary.txt`
- In-place: `logs/gpu_upload_retry_backoff_in_place_current/gpu-in-place-upload-summary.txt`
- Budget: `logs/gpu_upload_retry_backoff_budget_current/gpu-terrain-upload-budget-summary.txt`
- Aggregate report: `/tmp/rumpel-gpu-report-upload-retry-backoff.txt`

Movement passed with `gpu_upload_fail=0`, retry/backoff policy `none`, all retry/backoff counters `0`, `terrain_queue_max_ms=1.950`, `process_wall_p95_ms=0.029`, `gpu_compositor_submit_max_ms=0.086`, upload count max `1`, new/replacement slot maxima `1/1`, and new/replacement payload maxima `0.2/0.1 KiB`.

In-place passed with `gpu_in_place_uploads=1`, `gpu_in_place_upload_misses=63`, `gpu_uploads=852`, `gpu_upload_fail=0`, retry/backoff policy `none`, all retry/backoff counters `0`, `terrain_queue_max_ms=1.953`, `process_wall_p95_ms=0.023`, `gpu_compositor_submit_max_ms=0.084`, and new/replacement slot maxima `1/1`.

Upload budget passed with `reason=within_budget`, movement and in-place retry/backoff policy `none`, all retry/backoff counters `0`, and zero upload failure counters.

## Guardrails

- Do not add upload retries without measuring frame cost, upload pressure, failure recovery, visual fallback, shadow fallback, and collision fallback.
- Do not use local macOS/Metal Godot timestamp samples as trusted GPU timing until external profiler evidence proves them reliable.
- Keep retry/backoff telemetry separate from upload failure telemetry; `gpu_upload_fail=0` and `gpu_upload_retry_attempts=0` answer different questions.
- Keep movement/new-slot evidence separate from in-place/replacement evidence.
- A future non-`none` policy must update this document, `scripts/gpu_terrain_upload_budget.sh`, `scripts/gpu_terrain_movement_stress.sh`, `scripts/gpu_terrain_in_place_upload_gate.sh`, and `docs/GPU_TRENDS.md`.

## External References

- Godot `RenderingDevice.buffer_update` updates buffer ranges and has explicit active draw/compute list constraints: <https://docs.godotengine.org/en/stable/classes/class_renderingdevice.html>
- Vulkan queue submission can fail with host/device memory errors or device loss, so retry behavior must be designed as explicit recovery, not hidden looping: <https://docs.vulkan.org/spec/latest/chapters/cmdbuffers.html>
- Apple Metal guidance recommends reusable dynamic buffers/triple buffering instead of creating new buffers every frame: <https://developer.apple.com/library/archive/documentation/3DDrawing/Conceptual/MTLBestPracticesGuide/TripleBuffering.html>
