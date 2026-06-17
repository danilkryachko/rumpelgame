# GPU Streaming Scheduler Workload Matrix

Date: 2026-06-16

Scope: runtime comparison gate for the default-off client streaming scheduler modes. This slice compares `nearest`, `directional_tie_preview`, and `directional_tie` against the same movement workloads. It does not change the default scheduler, server chunk ordering, protocol, storage, world generation, chunk serialization, draw distance, lighting, shadows, texture quality, visible quality, unload policy, buffer repack/eviction policy, or collision-refresh backpressure.

## Command

Use existing captured lane summaries:

```sh
sh scripts/gpu_streaming_scheduler_workload_matrix.sh logs/gpu_streaming_scheduler_workload_matrix_current
```

Capture fresh lanes:

```sh
RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE=1 \
RUMPELMC_GODOT_RUST_EXT_PROFILE=release \
RUMPELMC_STREAMING_SCHEDULER_MATRIX_RUN_WORKLOADS=1 \
sh scripts/gpu_streaming_scheduler_workload_matrix.sh logs/gpu_streaming_scheduler_workload_matrix_current
```

The script writes:

- `gpu-streaming-scheduler-workload-matrix-summary.txt`
- `gpu-streaming-scheduler-workload-matrix-cases.txt`

## Default Workloads

The default matrix covers:

- `chunk_walk_extended`
- `chunk_spiral`
- `chunk_fly_snap_back`

The `nearest` baseline and `directional_tie_preview` telemetry lane must produce the expected current chunk, current render readiness, current collision readiness, zero ground misses, zero normal GPU upload failures, zero injected upload failures, zero unload churn, and queue/process/compositor budgets within the baseline-relative guard.

The active `directional_tie` lane is an opt-in candidate lane. If it fails readiness, unload, upload, or budget checks, the matrix should still pass as a decision gate while emitting `candidate_scheduler_status=reject_runtime_regression`, `active_failed_cases`, or `active_regression_cases`. That result blocks rollout and keeps `scheduler_change_allowed=0`.

## Decision Rules

- `nearest` is the baseline and must remain default.
- `directional_tie_preview` must report `stream_scheduler_active=0`.
- `directional_tie` must report `stream_scheduler_active=1`.
- All modes must use the same movement workload set.
- Candidate scheduler decisions remain blocked by `scheduler_change_allowed=0` and `default_runtime_change_allowed=0`.
- Baseline or preview lane failures fail the matrix.
- Active lane failures reject the candidate scheduler instead of failing the whole evidence gate.
- If no directional tie or preview mismatch is observed, the result is healthy but decision status is `defer_no_runtime_signal`.
- If runtime signal is observed and local budgets still pass, the result remains `defer_external_profiler_required`.
- If active runtime signal appears with unload/readiness/budget regressions, the result is `reject_runtime_regression`.

The matrix uses a configurable baseline-relative budget guard:

- `RUMPELMC_STREAMING_SCHEDULER_MATRIX_MAX_RELATIVE_BUDGET_REGRESSION_PCT`
- `RUMPELMC_STREAMING_SCHEDULER_MATRIX_MAX_ABSOLUTE_BUDGET_REGRESSION_MS`

The default is intentionally tolerant enough for local runtime variance, but still fails clear regressions.

## Fresh Evidence

Fresh local evidence:

- `logs/gpu_streaming_scheduler_workload_matrix_current/gpu-streaming-scheduler-workload-matrix-summary.txt`
- `logs/gpu_streaming_scheduler_workload_matrix_current/gpu-streaming-scheduler-workload-matrix-cases.txt`

The current matrix keeps:

- `status=pass`
- `matrix_harness_status=partial`
- `expected_cases=9`
- `completed_cases=9`
- `baseline_pass_cases=2`
- `preview_pass_cases=1`
- `active_pass_cases=1`
- `failed_cases=5`
- `runtime_signal=683`
- `max_stream_scheduler_preview_mismatch=117`
- `max_mesh_scheduler_directional_ties=361`
- `max_collision_scheduler_directional_ties=10`
- `max_stream_scheduler_fifo_fallbacks=902`
- `max_terrain_queue_ms=6.174`
- `max_process_wall_p95_ms=0.070`
- `max_gpu_compositor_submit_ms=0.408`
- `max_packet_queue_lag_ms=67.578`
- `candidate_scheduler_status=defer_matrix_harness_unstable`
- `scheduler_change_allowed=0`
- `default_runtime_change_allowed=0`
- `external_profile_status=pending_external_profiler`
- `requires_external_profiler_before_default=1`
- `requires_mac_windows_validation=1`

This result is intentionally not a scheduler rollout signal. The standalone matrix produced useful runtime signal, but it also exposed harness instability and unload/screenshot failures outside the stronger chunk-boundary gate. Treat the result as proof that default scheduler changes remain blocked.

## Runtime Telemetry

`scripts/gpu_terrain_movement_stress.sh` now writes a compact `movement_stream_scheduler` row with:

- `mode`
- `active`
- `preview_mismatch`
- `direction_x`
- `direction_z`
- `mesh_directional_ties`
- `collision_directional_ties`
- `fifo_fallbacks`

`scripts/world_streaming_high_pressure_suite.sh` and `scripts/gpu_terrain_chunk_boundary_stress.sh` propagate the same counters through suite and boundary summaries.

## External Context

- Godot `RenderingDevice` is a low-level abstraction over modern graphics APIs, so mode decisions need backend-aware evidence: <https://docs.godotengine.org/en/stable/classes/class_renderingdevice.html>
- Apple Metal resource guidance distinguishes memory/storage behavior by platform and resource mode, so macOS evidence cannot be replaced by generic local CPU timing alone: <https://developer.apple.com/documentation/metal/resource-fundamentals>
- Direct3D 12 residency guidance treats memory budget and residency as explicit management concerns on Windows: <https://learn.microsoft.com/en-us/windows/win32/direct3d12/residency>
- Vulkan memory-budget reporting is implementation-dependent and useful as evidence, not as a cross-platform defaulting shortcut: <https://registry.khronos.org/vulkan/specs/latest/man/html/VK_EXT_memory_budget.html>

## Next Step

Use the matrix to choose the next capture target:

- If `defer_no_runtime_signal`, add a deterministic tie-heavy movement fixture before changing policy.
- If runtime signal exists without local regressions, capture external macOS Metal and Windows GPU profiler rows before any default scheduler decision.
- Current follow-up is `docs/GPU_STREAMING_SCHEDULER_TIE_PROBE.md`: the deterministic tie probe extracts the stable `chunk_fly_snap_back` lanes before the decision checkpoint composes this matrix with chunk-boundary and residency evidence. `scripts/gpu_streaming_scheduler_boundary_matrix.sh` remains an optional boundary-backed capture tool until its lanes are stable.
