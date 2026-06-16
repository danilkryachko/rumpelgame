# GPU Streaming Scheduler Tie Probe

Date: 2026-06-16

Scope: deterministic tie-heavy evidence gate for the default-off client streaming scheduler. This probe extracts the stable `chunk_fly_snap_back` workload lanes from the scheduler workload matrix and verifies that `nearest`, `directional_tie_preview`, and `directional_tie` all pass the same readiness, upload, unload, and scheduler-marker contracts. It does not change default scheduler behavior, server chunk ordering, protocol, storage, world generation, chunk serialization, draw distance, lighting, shadows, texture quality, visible quality, unload policy, buffer repack/eviction policy, or collision-refresh backpressure.

## Command

Use existing captured matrix rows:

```sh
sh scripts/gpu_streaming_scheduler_tie_probe.sh logs/gpu_streaming_scheduler_tie_probe_current
```

Capture a fresh one-motion matrix first:

```sh
RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE=1 \
RUMPELMC_GODOT_RUST_EXT_PROFILE=release \
RUMPELMC_STREAMING_SCHEDULER_TIE_PROBE_RUN_WORKLOADS=1 \
sh scripts/gpu_streaming_scheduler_tie_probe.sh logs/gpu_streaming_scheduler_tie_probe_current
```

The script writes:

- `gpu-streaming-scheduler-tie-probe-summary.txt`

## Validation

The probe requires:

- source workload matrix `status=pass`
- `scheduler_change_allowed=0`
- `default_runtime_change_allowed=0`
- `requires_external_profiler_before_default=1`
- `requires_mac_windows_validation=1`
- one passing row each for `nearest`, `directional_tie_preview`, and `directional_tie`
- expected scheduler active markers: `0`, `0`, and `1`
- current chunk, render readiness, and collision readiness
- zero ground misses
- zero normal and injected GPU upload failures
- zero chunk unload and neighbor-refresh churn
- positive deterministic tie signal by default

## Fresh Evidence

Fresh local evidence:

- `logs/gpu_streaming_scheduler_tie_probe_current/gpu-streaming-scheduler-tie-probe-summary.txt`

The current probe passed with:

- `motion=chunk_fly_snap_back`
- `expected_cases=3`
- `completed_cases=3`
- `pass_cases=3`
- `failed_cases=0`
- `runtime_signal=312`
- `max_stream_scheduler_preview_mismatch=117`
- `max_mesh_scheduler_directional_ties=114`
- `max_collision_scheduler_directional_ties=6`
- `max_stream_scheduler_fifo_fallbacks=867`
- `max_terrain_queue_ms=5.851`
- `max_process_wall_p95_ms=0.048`
- `max_gpu_compositor_submit_ms=0.191`
- `max_packet_queue_lag_ms=42.019`
- `candidate_scheduler_status=stable_tie_probe_external_profiler_required`
- `scheduler_change_allowed=0`
- `default_runtime_change_allowed=0`
- `external_profile_status=pending_external_profiler`
- `requires_external_profiler_before_default=1`
- `requires_mac_windows_validation=1`

This is not scheduler rollout approval. It proves the current matrix contains a deterministic tie-heavy lane with useful scheduler signal and no local readiness/upload/unload failures. The wider matrix is still partial, allocator/free-range evidence is still incomplete, and external macOS/Windows profiler rows are still required before any default scheduler decision.

## Relationship To Other Gates

- `scripts/gpu_streaming_scheduler_workload_matrix.sh` remains the wider comparison gate over all configured movement workloads.
- `scripts/gpu_streaming_scheduler_tie_probe.sh` is now required by `scripts/gpu_streaming_scheduler_decision_checkpoint.sh` so the decision record cannot cite runtime signal without a stable deterministic tie-heavy subset.
- `scripts/gpu_streaming_scheduler_boundary_matrix.sh` remains optional until boundary-backed scheduler lanes emit stable summaries.
