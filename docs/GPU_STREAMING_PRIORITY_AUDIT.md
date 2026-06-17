# GPU Streaming Priority Audit

Date: 2026-06-16

Scope: summary-only audit for GPU world-loading streaming priority. This gate checks the current server chunk-ordering contracts, client mesh/collision queue priority contracts, runtime chunk-boundary and rapid-turn evidence, unload churn evidence, buffer residency evidence, and diagnostic upload-failure fallback evidence. It does not change scheduler behavior, rendering behavior, draw distance, camera far plane, lighting, shadows, texture quality, visible quality, protocol, storage, world generation, or chunk serialization.

## Command

Use:

```sh
sh scripts/gpu_streaming_priority_audit.sh logs/gpu_streaming_priority_audit_current
```

The script writes:

- `gpu-streaming-priority-audit-summary.txt`

## Required Inputs

Default summaries:

- `logs/gpu_terrain_chunk_boundary_stress_current/chunk-boundary-stress-summary.txt`
- `logs/gpu_terrain_rapid_camera_turn_stress_current/rapid-camera-turn-stress-summary.txt`
- `logs/gpu_chunk_unload_churn_diagnosis_current/gpu-chunk-unload-churn-diagnosis-summary.txt`
- `logs/gpu_buffer_residency_budget_current/gpu-buffer-residency-budget-summary.txt`
- `logs/gpu_upload_failure_fallback_current/gpu-upload-failure-fallback-summary.txt`

Default source contracts:

- `client/rust_ext/src/lib.rs`
- `server/pkg/world/world.go`
- `server/pkg/world/world_test.go`
- `server/pkg/network/server.go`
- `server/pkg/network/server_test.go`

Source tokens cover:

- client mesh queue one-job frame budget and nearest-current-chunk/FIFO tie priority
- client collision-refresh backpressure before mesh queue work
- client current render/collision readiness and pop-in probe counters
- client upload-failure recovery keeping CPU fallback until a confirmed GPU slot exists
- server `ChunksAroundOrdered` nearest-first ordering and directional tie-break tests
- server current-chunk bootstrap radius default and config tests

## Runtime Contract

The audit requires:

- chunk-boundary and rapid camera-turn summaries pass
- current chunk render/collision readiness is present
- zero normal GPU upload failures
- zero ground misses
- zero chunk unload and neighbor-refresh churn in the default evidence
- packet queue lag stays under the configured summary budget
- unload and buffer policy changes remain deferred
- buffer residency summary keeps external profiler and macOS/Windows validation blockers explicit
- diagnostic upload-failure fallback passes as an expected-failure lane with `shadow_path=arraymesh`, nonzero injected failures, zero capacity/fragmentation failures, zero GPU subchunks/uploads, and current chunk readiness

Packet queue lag and pop-in counters are evidence, not full server backlog proof. Buffer residency is summary-only when allocator/free-range evidence is missing.

## Fresh Evidence

Fresh local evidence:

- `logs/gpu_streaming_priority_audit_current/gpu-streaming-priority-audit-summary.txt`

The current audit passed with:

- `source_contracts_present=18`
- `source_contracts_required=18`
- `runtime_priority_status=pass`
- `upload_fallback_status=pass`
- `priority_proof_status=partial`
- `max_packet_queue_lag_ms=27.437`
- `current_chunk=2,2`
- `current_render_ready=1`
- `current_collision_ready=1`
- `current_chunk_submeshes=2`
- `current_chunk_collision=2`
- `gpu_upload_fail=0`
- `buffer_upload_fail_total=0`
- `upload_fallback_expected_failures=1052`
- `upload_fallback_injected_failures=1052`
- `upload_fallback_shadow_path=arraymesh`
- `residency_pressure_class=high`
- `residency_proof_status=partial`
- `allocator_evidence_status=missing_optional`
- `scheduler_change_allowed=0`
- `candidate_scheduler_status=deferred`

The `partial` proof status is intentional: allocator/free-range memory-budget evidence, external profiler rows, and cross-platform macOS/Windows validation are still required before a default scheduler, repack, eviction, or streaming-policy change.

## Wiring

- `scripts/gpu_terrain_report.sh` surfaces the selected streaming priority audit summary.
- `scripts/gpu_stress_artifact_index.sh` requires the streaming priority audit and the upload-failure fallback artifact as core streaming rows.
- `scripts/test_strategy_gate.sh` requires the streaming priority audit summary and includes the command before the stress index in the nightly summary command.

## External Context

- Godot's 3D optimization guidance emphasizes visibility reduction, occlusion culling, LOD, and scene-structure choices before treating local FPS as proof of a better world streaming policy.
- Direct3D 12 memory-management guidance recommends a classify, budget, and stream strategy for GPU memory pressure.
- Vulkan `VK_EXT_memory_budget` exposes heap usage and budget, but values are implementation-dependent and can change with OS and system load.

This audit follows that direction by classifying current priority/residency evidence and keeping platform/profiler blockers explicit instead of changing defaults from local summaries alone.
