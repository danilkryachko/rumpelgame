# GPU Terrain Buffer Repack Design

## Purpose

GPU terrain buffer repack is a future fragmentation recovery path for the GPU terrain face buffer. It must reduce allocator fragmentation only when telemetry proves that fragmentation is a real limit. The current best-fit allocator, buffer capacity, draw distance, lighting, shadows, texture quality, protocol, storage, world generation, and chunk serialization remain unchanged by default.

This document is design-only. It does not enable repack behavior.

## Current Baseline

The GPU terrain path stores packed terrain faces in one terrain face buffer owned by `GpuTerrainBufferPool`. The pool tracks resident subchunks in a slot map keyed by `GpuSubchunkKey`; each slot records a start face and face count. Draw commands are derived from those slots and must stay consistent with any slot move.

The allocator already exposes the telemetry needed to decide whether repack is worth prototyping:

- `gpu_free_ranges`
- `gpu_free_faces`
- `gpu_largest_free`
- `gpu_fragmented_free_faces`
- `gpu_fragmentation_pct`
- `gpu_upload_fail_capacity`
- `gpu_upload_fail_fragmented`

The existing allocator stress gate must keep passing before and after any repack experiment.

## Rollback Flag

Repack must be behind an explicit rollback flag:

```text
RUMPELMC_GPU_TERRAIN_BUFFER_REPACK=0|1
```

The default is off. Unset and `0` must keep the current allocator path. No automatic environment default, wrapper default, or project template should enable repack until the evidence gates below pass and a separate default-on decision is recorded.

If repack reports any internal error, the runtime should disable repack for the rest of that process and continue with the existing allocator state when possible.

## Telemetry

The first implementation slice should add marker-only counters while the flag is off, then add active counters behind the flag:

- `gpu_repack_requested`
- `gpu_repack_active`
- `gpu_repack_attempts`
- `gpu_repack_success`
- `gpu_repack_abort`
- `gpu_repack_moved_subchunks`
- `gpu_repack_moved_faces`
- `gpu_repack_bytes`
- `gpu_repack_source_subchunks`
- `gpu_repack_source_bytes`
- `gpu_repack_source_missing`
- `gpu_repack_payload_ready`
- `gpu_repack_payload_bytes`
- `gpu_repack_upload_ready`
- `gpu_repack_upload_bytes`
- `gpu_repack_upload_ms`
- `gpu_repack_bind_ready`
- `gpu_repack_bind_ms`
- `gpu_repack_draw_ready`
- `gpu_repack_draw_bytes`
- `gpu_repack_stage_ready`
- `gpu_repack_stage_slots`
- `gpu_repack_stage_bytes`
- `gpu_repack_ms`
- `gpu_repack_fragmentation_before_pct`
- `gpu_repack_fragmentation_after_pct`
- `gpu_repack_largest_free_before`
- `gpu_repack_largest_free_after`
- `gpu_repack_failure_reason`

`gpu_repack_failure_reason` should use bounded values such as `none`, `disabled`, `marker_only`, `threshold_not_met`, `in_flight`, `missing_source`, `source_size_mismatch`, `capacity`, `upload_error`, and `draw_rebuild_error`.

## Trigger Policy

Repack must not run automatically in normal gameplay until the prototype has evidence. The prototype trigger should require the flag plus one of these conditions:

- a manual force flag for local profiling, for example `RUMPELMC_GPU_TERRAIN_BUFFER_REPACK_FORCE=1`
- fragmentation pressure above a configured threshold and at least one fragmented upload failure

The implementation should also debounce repack with a cooldown and allow at most one active repack operation at a time. A single repack per profiling run is enough for the first prototype.

## Safe Algorithm

A safe repack should be all-or-nothing from the renderer's point of view:

1. Run only at a terrain queue boundary where no terrain upload, slot mutation, or indirect draw update is in progress.
2. Freeze terrain slot mutations for that queue pass.
3. Build a deterministic plan by sorting resident `GpuSubchunkKey` values and packing their ranges contiguously from face offset `0`.
4. Validate total face count against the current face-buffer capacity.
5. Rebuild packed face bytes from CPU-owned resident subchunk data. The first prototype must not depend on GPU readback. If resident CPU source data is unavailable, abort before changing state.
6. Prefer creating and filling a replacement face buffer, then swapping it into the terrain render binding only after the full upload succeeds. If the binding swap cannot be made atomic in the current render path, the prototype should stay marker-only.
7. Replace slot offsets and rebuild indirect draw commands only after the replacement buffer upload has succeeded.
8. Rebuild allocator state to one tail free range after the final resident face.
9. Record before/after fragmentation, largest-free-range, moved-face, moved-subchunk, and timing counters.

The old buffer and old slot map remain authoritative until the commit point. Any validation or upload failure aborts the plan before state mutation.

## Correctness Gates

Before a repack prototype can be considered useful, it must pass these gates with the flag off and with the flag on:

- `gpu_upload_fail=0`
- `gpu_upload_fail_capacity=0`
- `gpu_upload_fail_fragmented=0`
- `scripts/gpu_terrain_allocator_stress_gate.sh`
- movement stress
- standard workload matrix
- fill stress repeats `1`, `4`, and `8`
- dirty-update single-edge stress
- block-edit stress
- visible terrain samples present, with no new terrain holes
- current chunk collision remains present
- shadow and transparent counters remain unchanged unless that specific feature is under test

Performance acceptance is evidence-led: queue and compositor p95/max timings must not regress materially in the profiling artifacts, and fragmentation must improve in the scenarios that triggered repack.

## Non-Goals

This design does not authorize:

- increasing terrain face buffer capacity
- changing the allocator policy for the default path
- changing draw distance, lighting, shadows, texture quality, or visible quality
- changing protocol, storage, world generation, persistence, or chunk serialization
- using GPU readback in the first prototype
- enabling repack by default
- hiding upload failures by reducing terrain quality

## Current Prototype Status

The first prototype slice is implemented as marker-only telemetry plus a pure planner. `RUMPELMC_GPU_TERRAIN_BUFFER_REPACK=1` records `gpu_repack_requested=1`, keeps `gpu_repack_active=0`, keeps runtime attempts and success at `0`, records an abort reason of `marker_only`, and computes a read-only deterministic compaction preview from current slots. It does not replace the GPU face buffer or mutate slot offsets.

The current source-readiness slice stores CPU-owned encoded packed-face bytes for resident subchunks only when the repack flag is enabled. Upload behavior is otherwise unchanged. Removing a subchunk removes its source bytes. Telemetry reports `gpu_repack_source_subchunks`, `gpu_repack_source_bytes`, and `gpu_repack_source_missing`; a missing resident source changes the marker-only reason to `missing_source`.

The current replacement-upload, binding-preview, draw-remap-preview, and staged-guard slice assembles a compact replacement byte payload from the resident source map in deterministic plan order, builds replacement indirect draw command bytes for the current draw order using the compacted `first_instance` offsets, then collects the replacement face bytes, draw bytes, deterministic slot map, and tail free range into one all-or-nothing staged swap preview. With the additional explicit `RUMPELMC_GPU_TERRAIN_BUFFER_REPACK_UPLOAD_PREVIEW=1` profiling flag, the runtime takes one sample: it creates a temporary replacement storage buffer, uploads the staged face bytes, creates and validates a temporary uniform set that binds the replacement face buffer to the existing shader/atlas resources, then immediately frees the temporary uniform set and buffer. Telemetry reports `gpu_repack_payload_ready`, `gpu_repack_payload_bytes`, `gpu_repack_upload_ready`, `gpu_repack_upload_bytes`, `gpu_repack_upload_ms`, `gpu_repack_bind_ready`, `gpu_repack_bind_ms`, `gpu_repack_draw_ready`, `gpu_repack_draw_bytes`, `gpu_repack_stage_ready`, `gpu_repack_stage_slots`, and `gpu_repack_stage_bytes`; source size mismatches report `gpu_repack_failure_reason=source_size_mismatch`, invalid temporary buffer creation reports `gpu_repack_failure_reason=upload_error`, and temporary binding, draw-remap, or staged draw-size failure reports `gpu_repack_failure_reason=draw_rebuild_error`. Runtime buffer replacement, active render binding swap, indirect-buffer upload/swap, slot mutation, and allocator mutation are still disabled.

`scripts/gpu_terrain_report.sh` aggregates the numeric `gpu_repack_*` fields, including source readiness, payload-preview, upload-preview, binding-preview, draw-remap-preview, and staged-guard counters, and reports the latest `gpu_repack_failure_reason`.

## Next Implementation Slice

The next slice should add a disabled commit-point proof that consumes the staged swap preview and verifies the exact ordering for active face-buffer RID swap, uniform-set swap, indirect-buffer swap, slot-map replacement, and allocator rebuild without enabling the final RenderingDevice swap. The final RenderingDevice buffer swap must stay disabled until upload, swap, telemetry, and abort paths are covered by tests.
