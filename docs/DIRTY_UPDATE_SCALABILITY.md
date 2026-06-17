# Dirty Update Scalability

Block 42, Dirty Update Scalability, records the current scalable dirty update contract for mass block edits, chunk edges, neighbor rebuilds, collision refresh, and partial GPU dirty upload.

## Technical Brief

User request:

Continue the annual world streaming architecture plan in order and use MCP/OntoIndex context.

Goal:

Check that the dirty update model can reason about mass edits and edge-neighbor refreshes before widening runtime block edit workloads.

Context inspected:

- OntoIndex concept search for partial dirty upload, mass block edits, chunk edges, neighbor rebuilds, collision refresh, dirty counters, and GPU terrain stress scripts.
- `client/rust_ext/src/lib.rs` dirty update masks, partial subchunk counters, edge-neighbor refresh, collision refresh, and GPU upload path.
- `scripts/gpu_terrain_block_edit_stress.sh`.
- `scripts/gpu_terrain_edge_block_edit_stress.sh`.
- `scripts/gpu_terrain_edge_dirty_compare.sh`.
- `scripts/gpu_terrain_edge_dirty_repeat.sh`.
- `scripts/gpu_terrain_single_edge_dirty_compare.sh`.
- `scripts/gpu_terrain_single_edge_dirty_repeat.sh`.
- `docs/BLOCK_EDIT_PERSISTENCE_TRACK.md`.
- `docs/GPU_TRENDS.md`.

Scope:

- Add a pure Rust unit guard for multiple dirty blocks touching all chunk edges and multiple subchunks.
- Verify the dirty model computes changed subchunks, rebuild subchunks, edge-neighbor targets, partial dirty subchunks, and saved full-rebuild work.
- Keep existing edge dirty runtime wrappers as the heavier scalability evidence path.
- Record which runtime workloads remain deferred.

Out of scope:

- No new runtime mass-edit Godot smoke by default, no protocol change, no storage change, no world generation change, no chunk serialization change, no GPU allocator policy change, no draw distance or visual quality reduction, and no new dirty packet.

Assumptions:

- The current partial dirty upload default remains enabled unless `RUMPELMC_GPU_TERRAIN_PARTIAL_DIRTY_UPLOAD=0`.
- Full rebuild remains the rollback/control path.
- Unit tests are allowed to guard dirty surface math, but runtime scale claims still need Godot artifacts.
- Existing edge compare/repeat scripts remain the runtime entry points for collision/GPU edge coverage.

Done when:

- Mass dirty update math is unit-guarded.
- A dirty scalability gate checks the unit guard, edge scripts, prior block-edit persistence gate, and focused Rust dirty tests.

Checks:

- `sh scripts/dirty_update_scalability_gate.sh logs/dirty_update_scalability_current`

## Current Dirty Update Contract

- `chunk_dirty_update` compares previous/current serialized chunk bytes.
- It records changed block count, changed subchunk mask, rebuild subchunk mask, chunk edge mask, and bounds.
- `dirty_rebuild_subchunk_mask_for_y` includes adjacent subchunks when a change touches a subchunk vertical boundary.
- `dirty_edge_neighbors` maps touched chunk edges to neighboring chunk coordinates.
- `dirty_partial_subchunk_count` reports rebuilt non-empty subchunks under the partial path.
- `dirty_partial_saved_subchunks` reports non-empty subchunks avoided by partial dirty upload.
- `PerfStats.record_dirty_edge_neighbor_refresh` records neighbor refresh chunks and subchunks.

## Added Unit Guard

`mass_dirty_update_tracks_all_edges_and_partial_scope` creates a synthetic mass dirty update with four edits:

- one touching negative X and negative Z
- one touching positive X and positive Z
- one touching a vertical subchunk boundary
- one touching the top subchunk

The test locks:

- `changed_blocks = 4`
- changed subchunk mask across three subchunks
- rebuild mask across four subchunks
- all four edge bits
- four edge-neighbor coordinates
- partial dirty subchunk count
- partial saved subchunk count

## Runtime Evidence Entry Points

Existing runtime wrappers remain the correct heavy checks:

- `scripts/gpu_terrain_block_edit_stress.sh`
- `scripts/gpu_terrain_edge_block_edit_stress.sh`
- `scripts/gpu_terrain_edge_dirty_compare.sh`
- `scripts/gpu_terrain_edge_dirty_repeat.sh`
- `scripts/gpu_terrain_single_edge_dirty_compare.sh`
- `scripts/gpu_terrain_single_edge_dirty_repeat.sh`
- `scripts/gpu_terrain_repeated_edit_benchmark.sh`
- `scripts/gpu_terrain_border_edit_benchmark.sh`
- `scripts/gpu_terrain_partial_dirty_edge_matrix.sh`
- `scripts/gpu_collision_refresh_cost_audit.sh`

The gate does not run them by default because they require Godot runtime capture, a free local server port, and longer execution time. It does verify their shell syntax and required metric tokens.

Fresh repeated-edit benchmark evidence now lives at `logs/gpu_terrain_repeated_edit_benchmark_current/gpu-terrain-repeated-edit-benchmark-summary.txt`. It composes three single-edge repeats and three corner-edge repeats, passed with max queue/process/submit `2.972/0.050/0.150ms`, zero GPU upload failures, and default/visible-quality changes blocked.

Fresh border-edit benchmark evidence now lives at `logs/gpu_terrain_border_edit_benchmark_current/gpu-terrain-border-edit-benchmark-summary.txt`. It composes the repeated single/corner-edge benchmark with the pressure dirty compare at local `31,31`, passed with `case_count=3`, max dirty blocks `709`, max edge-neighbor subchunks `2836`, max partial saved subchunks `1418`, max queue/process/submit `4.777/0.050/0.171ms`, zero GPU upload failures, zero ground misses, and default/visible-quality changes blocked.

Fresh partial dirty edge matrix evidence now lives at `logs/gpu_terrain_partial_dirty_edge_matrix_current/gpu-terrain-partial-dirty-edge-matrix-summary.txt`. It refreshes full-vs-partial runtime compares for all four single edges and all four corner combinations, passed with `case_count=8`, min/max partial edge-neighbor subchunks `4/8`, min/max partial saved subchunks `2/2`, max queue/process/submit `3.734/0.041/0.102ms`, full rollback partial counters disabled, zero GPU upload failures, and default/visible-quality changes blocked.

Fresh collision refresh cost evidence now lives at `logs/gpu_collision_refresh_cost_audit_current/gpu-collision-refresh-cost-audit-summary.txt`. It consumes the partial dirty edge matrix and pressure dirty compare movement markers, passed with `case_count=18`, max collision refresh rebuilds `132`, max queue depth `17`, max phase total/component `1.950/1.540ms`, zero refresh missing, zero queue duplicate/stale/missing counters, zero GPU upload failures, and zero ground misses.

## Deferred Work

Still needed:

- Multi-edit runtime smoke that applies many block edits in one session.
- Chunk-edge mass-edit runtime smoke with both full and partial dirty controls.
- Repeated persisted reload plus dirty update runtime smoke from Block 41 follow-up.
- Collision refresh budget under mass edits beyond the current edge-matrix and pressure dirty lanes.
- GPU upload budget under mass edits.
- Multi-client block edit fanout once server broadcast exists.

## Compatibility Rules

- Keep explicit `RUMPELMC_GPU_TERRAIN_PARTIAL_DIRTY_UPLOAD=0` as the full rebuild rollback path.
- Do not reduce collision, shadow, texture, draw-distance, or visible quality to make dirty updates pass.
- Do not change protocol or storage to optimize dirty updates without a protocol/storage task.
- Do not treat unit dirty math as full runtime scalability evidence.
- Do not run heavy Godot dirty repeat gates inside normal `check.sh`.

## Block 42 Gate

Use:

```sh
sh scripts/dirty_update_scalability_gate.sh logs/dirty_update_scalability_current
```

The expected current result is `status=pass`, `dirty_scalability_status=unit_guarded`, `mass_dirty_unit=pass`, `edge_runtime_scripts=available`, `runtime_mass_edit=deferred`, `active_protocol_change=0`, and `block_edit_persistence_status=pass`.

The gate checks that:

- This document records dirty contract, added unit guard, runtime entry points, deferred work, and compatibility rules.
- The mass dirty unit test exists.
- Required dirty runtime scripts exist and pass `sh -n`.
- Previous block edit persistence gate is clean.
- Focused Rust dirty tests pass.
- Protocol schema/generated files are unchanged.

## Current Status

This block is complete as a unit-guarded dirty scalability checkpoint plus repeated single-edge/corner runtime evidence. Heavy runtime mass-edit scalability remains future work.
