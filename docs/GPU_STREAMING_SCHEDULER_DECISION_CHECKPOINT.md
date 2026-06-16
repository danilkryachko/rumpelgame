# GPU Streaming Scheduler Decision Checkpoint

Date: 2026-06-16

Scope: summary-only decision checkpoint for the default-off client streaming scheduler. This checkpoint composes the scheduler prototype, scheduler workload matrix, chunk-boundary baseline, and buffer residency budget evidence into one required artifact. It does not change default scheduler behavior, server chunk ordering, protocol, storage, world generation, chunk serialization, draw distance, lighting, shadows, texture quality, visible quality, unload policy, buffer repack/eviction policy, or collision-refresh backpressure.

## Command

Use:

```sh
sh scripts/gpu_streaming_scheduler_decision_checkpoint.sh logs/gpu_streaming_scheduler_decision_checkpoint_current
```

The script writes:

- `gpu-streaming-scheduler-decision-checkpoint-summary.txt`

## Required Inputs

The checkpoint requires these summaries to pass:

- `logs/gpu_streaming_scheduler_prototype_current/gpu-streaming-scheduler-prototype-summary.txt`
- `logs/gpu_streaming_scheduler_workload_matrix_current/gpu-streaming-scheduler-workload-matrix-summary.txt`
- `logs/gpu_terrain_chunk_boundary_stress_current/chunk-boundary-stress-summary.txt`
- `logs/gpu_buffer_residency_budget_current/gpu-buffer-residency-budget-summary.txt`

It optionally consumes:

- `logs/gpu_streaming_scheduler_boundary_matrix_current/gpu-streaming-scheduler-boundary-matrix-summary.txt`

The optional boundary matrix is a capture tool for future scheduler lanes through `scripts/gpu_terrain_chunk_boundary_stress.sh`; it is not a required row yet because current nested runtime attempts can fail before stable summaries are emitted.

## Fresh Evidence

Fresh local evidence:

- `logs/gpu_streaming_scheduler_decision_checkpoint_current/gpu-streaming-scheduler-decision-checkpoint-summary.txt`

The current checkpoint passed with:

- `workload_matrix_harness_status=partial`
- `workload_candidate_scheduler_status=defer_matrix_harness_unstable`
- `workload_runtime_signal=683`
- `workload_failed_cases=5`
- `chunk_boundary_status=pass`
- `chunk_boundary_upload_fail=0`
- `chunk_boundary_ground_misses=0`
- `chunk_boundary_unload_total=0`
- `chunk_boundary_unload_neighbor_refreshes=0`
- `residency_status=pass`
- `residency_pressure_class=high`
- `residency_proof_status=partial`
- `allocator_evidence_status=missing_optional`
- `boundary_matrix_status=missing`
- `scheduler_change_allowed=0`
- `default_runtime_change_allowed=0`
- `decision_status=defer_matrix_harness_unstable`
- `external_profile_status=pending_external_profiler`
- `requires_external_profiler_before_default=1`
- `requires_mac_windows_validation=1`

This is not rollout approval. It is the current decision record: the scheduler prototype has runtime signal, but standalone matrix instability, missing allocator/free-range evidence, and missing external macOS/Windows profiler rows block any default scheduler change.

## Boundary Matrix Capture

Use the optional boundary-backed capture when working specifically on scheduler lane stability:

```sh
RUMPELMC_STREAMING_SCHEDULER_BOUNDARY_MATRIX_RUN_WORKLOADS=1 \
sh scripts/gpu_streaming_scheduler_boundary_matrix.sh logs/gpu_streaming_scheduler_boundary_matrix_current
```

Default cases are `fast-turn teleport-snap`. Use `RUMPELMC_STREAMING_SCHEDULER_BOUNDARY_MATRIX_CASES` to widen the case set. Treat failed or partial boundary matrix output as a blocker and feed it back into this decision checkpoint, not as a reason to change runtime defaults.
