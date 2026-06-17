# GPU Streaming Scheduler Prototype

Date: 2026-06-16

Scope: default-off client streaming scheduler prototype for GPU world-loading. This slice adds an opt-in client queue ordering mode behind `RUMPELMC_CLIENT_STREAMING_SCHEDULER` and a summary-only preflight. It does not change the default scheduler, server chunk ordering, protocol, storage, world generation, chunk serialization, draw distance, lighting, shadows, texture quality, visible quality, unload policy, buffer repack/eviction policy, or collision-refresh backpressure.

## Modes

- unset / `nearest`: current nearest-current-chunk ordering with FIFO ties.
- `directional_tie_preview`: computes whether the directional tie-break would pick a different equal-distance subchunk, records preview mismatch telemetry, but still pops the current nearest/FIFO result.
- `directional_tie`: opt-in active prototype. It only changes ordering among subchunks with the same squared distance from the current player chunk. Closer chunks still win, missing movement direction falls back to FIFO, and collision-refresh backpressure remains unchanged.

## Command

Use:

```sh
sh scripts/gpu_streaming_scheduler_prototype.sh logs/gpu_streaming_scheduler_prototype_current
```

The script writes:

- `gpu-streaming-scheduler-prototype-summary.txt`

## Contract

The preflight requires:

- current streaming priority audit summary passes
- current priority audit still reports `scheduler_change_allowed=0`
- current priority audit still reports `candidate_scheduler_status=deferred`
- client source contains the scheduler env, parser, preview mode, active mode, direction scoring, player direction tracking, runtime perf markers, and tests
- default scheduler mode remains `nearest`
- default active scheduler remains `0`
- mesh queue still waits when collision refresh rebuilt this frame
- `MAX_MESH_JOBS_PER_FRAME=1`
- `MAX_COLLISION_REFRESH_REBUILDS_PER_FRAME=1`

## Fresh Evidence

Fresh local evidence:

- `logs/gpu_streaming_scheduler_prototype_current/gpu-streaming-scheduler-prototype-summary.txt`

The current preflight passed with:

- `source_contracts_present=21`
- `source_contracts_required=21`
- `priority_audit_status=pass`
- `priority_runtime_status=pass`
- `priority_scheduler_change_allowed=0`
- `priority_candidate_scheduler_status=deferred`
- `default_scheduler_mode=nearest`
- `stream_scheduler_active_default=0`
- `collision_backpressure_preserved=1`
- `scheduler_change_allowed=0`
- `default_runtime_change_allowed=0`
- `candidate_scheduler_status=prototype_only`
- `requires_external_profiler_before_default=1`
- `requires_mac_windows_validation=1`

The updated stress artifact index passed with `27` rows, `18` required passes, and zero upload-failure, ground-miss, default-runtime-change, and scheduler-change violations.

## Runtime Telemetry

The client perf text now includes:

- `stream_scheduler_mode`
- `stream_scheduler_active`
- `stream_scheduler_preview_mismatch`
- `stream_scheduler_direction_x`
- `stream_scheduler_direction_z`
- `mesh_scheduler_directional_ties`
- `collision_scheduler_directional_ties`
- `stream_scheduler_fifo_fallbacks`

Use these fields to compare baseline and opt-in scheduler variants before any default change.

## External Context

- Godot 3D optimization guidance emphasizes visibility, occlusion, LOD, and scene structure when evaluating large-scene performance: <https://docs.godotengine.org/en/stable/tutorials/performance/optimizing_3d_performance.html>
- Direct3D 12 memory management guidance recommends classifying resources, budgeting, and streaming under pressure before making broad GPU residency assumptions: <https://learn.microsoft.com/en-us/windows/win32/direct3d12/memory-management-strategies>
- Vulkan `VK_EXT_memory_budget` exposes runtime heap usage and budget, but those values are implementation-dependent and can vary by OS and load: <https://registry.khronos.org/vulkan/specs/latest/man/html/VK_EXT_memory_budget.html>

This prototype follows that direction: scheduler choices are measurable and reversible, while cross-platform profiler and macOS/Windows validation blockers stay explicit.

## Next Step

Week 59 should compare:

- default `nearest`
- `RUMPELMC_CLIENT_STREAMING_SCHEDULER=directional_tie_preview`
- `RUMPELMC_CLIENT_STREAMING_SCHEDULER=directional_tie`
- optional server lane `RUMPELMC_SERVER_CHUNK_ORDER=directional`

The comparison must keep zero GPU upload failures, zero ground misses, current render/collision readiness, no unload churn, no worse queue/process/submit budgets, no default runtime change, and no visible quality reduction.
