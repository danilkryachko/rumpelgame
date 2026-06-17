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
- Add an opt-in runtime edge dirty smoke that composes the existing single-edge, corner-edge, and repeat wrappers.
- Add an opt-in runtime mass-edit smoke that applies several block edits in one Godot session, then broaden it to a mixed place/destroy current-chunk budget.
- Add an opt-in persisted-reload dirty runtime smoke that proves dirty updates still work across repeated server restart/reopen cycles and persist final results after each dirty pass.
- Add an opt-in cross-chunk mass-edit runtime smoke that applies mixed place/destroy edits across multiple loaded chunks in one Godot session.
- Add a high-count dirty runtime gate that requires a five-cycle persisted reload smoke and aggregates it with the current mass-edit and cross-chunk mass-edit runtime evidence.
- Record which larger runtime workloads remain deferred.

Out of scope:

- No default `check.sh` runtime mass-edit Godot smoke, no protocol change, no storage change, no world generation change, no chunk serialization change, no GPU allocator policy change, no draw distance or visual quality reduction, and no new dirty packet.

Assumptions:

- The current partial dirty upload default remains enabled unless `RUMPELMC_GPU_TERRAIN_PARTIAL_DIRTY_UPLOAD=0`.
- Full rebuild remains the rollback/control path.
- Unit tests are allowed to guard dirty surface math, but runtime scale claims still need Godot artifacts.
- Existing edge compare/repeat scripts remain the runtime entry points for collision/GPU edge coverage and are composed by the opt-in runtime smoke.
- Runtime mass-edit smoke is current-chunk correctness and budget evidence for multiple edits in one session; cross-chunk collision/GPU budget claims use a separate opt-in runtime artifact.
- Persisted-reload dirty runtime smoke uses an isolated RocksDB path and the normal Godot `127.0.0.1:25565` path; it is not part of normal fast validation.

Done when:

- Mass dirty update math is unit-guarded.
- A dirty scalability gate checks the unit guard, edge scripts, prior block-edit persistence gate, focused Rust dirty tests, optional edge runtime smoke evidence, optional mass-edit runtime smoke evidence, optional cross-chunk mass-edit runtime evidence, and optional persisted-reload dirty runtime evidence.

Checks:

- `sh scripts/dirty_update_scalability_gate.sh logs/dirty_update_scalability_current`
- `RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE=1 RUMPELMC_DIRTY_SCALABILITY_RUN_RUNTIME_SMOKE=1 sh scripts/dirty_update_scalability_gate.sh logs/dirty_update_scalability_current`
- `RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE=1 RUMPELMC_DIRTY_SCALABILITY_RUN_PERSISTED_RUNTIME_SMOKE=1 sh scripts/dirty_update_scalability_gate.sh logs/dirty_update_scalability_current`
- `RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE=1 RUMPELMC_DIRTY_SCALABILITY_RUN_CROSS_MASS_RUNTIME_SMOKE=1 sh scripts/dirty_update_scalability_gate.sh logs/dirty_update_scalability_current`
- `RUMPELMC_DIRTY_HIGH_COUNT_RUN_PERSISTED_SMOKE=1 sh scripts/dirty_update_high_count_runtime_gate.sh logs/dirty_update_high_count_runtime_current`
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
- `scripts/dirty_update_runtime_smoke.sh`
- `scripts/dirty_update_mass_edit_runtime_smoke.sh`
- `scripts/dirty_update_cross_chunk_mass_runtime_smoke.sh`
- `scripts/dirty_update_persisted_reload_runtime_smoke.sh`
- `scripts/dirty_update_high_count_runtime_gate.sh`
- `scripts/gpu_terrain_repeated_edit_benchmark.sh`
- `scripts/gpu_terrain_border_edit_benchmark.sh`
- `scripts/gpu_terrain_partial_dirty_edge_matrix.sh`
- `scripts/gpu_collision_refresh_cost_audit.sh`
- `scripts/gpu_shadow_proxy_refresh_cost_audit.sh`
- `scripts/gpu_edit_burst_budget_gate.sh`
- `scripts/gpu_edit_visual_parity_gate.sh`
- `scripts/gpu_world_interaction_checkpoint.sh`

The gate does not run them by default because they require Godot runtime capture, a free local server port, and longer execution time. It does verify their shell syntax and required metric tokens.

## Runtime Edge Dirty Smoke

`scripts/dirty_update_runtime_smoke.sh` composes the current edge evidence into one bounded runtime lane:

- single-edge full-vs-partial compare at global `127,64,80`
- corner-edge full-vs-partial compare at global `127,64,95`
- repeated corner-edge partial dirty smoke

The smoke requires matching dirty surfaces between full and partial controls, positive partial dirty/neighbor-refresh counters, zero GPU upload failures, and no active protocol diff. Its repeated edge lane defaults to a bounded `RUMPELMC_DIRTY_RUNTIME_TARGET_FPS=100` guard, with the exact value recorded in the summary. The current gate consumes `logs/dirty_update_runtime_smoke_current/dirty-update-runtime-smoke-summary.txt` when present, or runs the smoke when `RUMPELMC_DIRTY_SCALABILITY_RUN_RUNTIME_SMOKE=1`.

## Runtime Mass Edit Smoke

`scripts/dirty_update_mass_edit_runtime_smoke.sh` applies several block edits in one Godot session through `RUMPELMC_VISUAL_SMOKE_BLOCK_EDIT_SEQUENCE`. The default sequence is a broader mixed place/destroy budget run with 12 explicit actions in the same current chunk after movement settles:

- six `place` actions and six matching `destroy` actions
- positions covering negative and positive chunk X/Z edges
- positions covering additional vertical subchunks
- explicit local budgets for terrain queue max, compositor submit max, process wall p95, and zero GPU upload failures

The smoke requires the sequence marker, matching edit count, mixed place/destroy action counts, cumulative dirty block/chunk replacement counters, positive edge-neighbor refresh, positive partial dirty/saved counters, current chunk collision evidence, budget-compliant terrain/compositor/process metrics, zero GPU upload failures, and no active protocol diff. It stores nested Godot artifacts outside the `_current` lane and writes `logs/dirty_update_mass_edit_runtime_current/dirty-update-mass-edit-runtime-summary.txt` for gate consumption.

## Runtime Persisted Reload Dirty Smoke

`scripts/dirty_update_persisted_reload_runtime_smoke.sh` combines persistence restart evidence with dirty runtime evidence:

- start an isolated server and place a seed block
- restart/reopen the same RocksDB path and verify the seed block
- run the repeatable four-toggle dirty sequence through Godot against the reloaded server
- restart/reopen again and verify the toggled positions are persisted as Air
- repeat the dirty/restart/verify loop for the configured soak count, defaulting to three dirty cycles

The smoke requires at least three soak cycles, at least four reload cycles, at least 12 final persisted verifications, per-cycle dirty markers, positive dirty/partial/edge-neighbor counters, current chunk collision evidence, zero GPU upload failures, and no active protocol diff. It stores nested Godot artifacts outside the `_current` lane and writes `logs/dirty_update_persisted_reload_runtime_current/dirty-update-persisted-reload-runtime-summary.txt`.

## Runtime Cross-Chunk Mass Edit Smoke

`scripts/dirty_update_cross_chunk_mass_runtime_smoke.sh` wraps the mass-edit runtime smoke with a fixed sequence that touches four loaded chunks around the settled player chunk:

- one current-chunk corner place/destroy pair
- one diagonal neighbor chunk place/destroy pair
- one positive-X neighbor chunk place/destroy pair
- one positive-Z neighbor chunk place/destroy pair

The smoke requires at least four distinct target chunks, four place actions, four destroy actions, cumulative dirty block/chunk replacement counters, edge-neighbor refresh, partial dirty/saved counters, current chunk collision evidence, budget-compliant terrain/compositor/process metrics, zero GPU upload failures, and no active protocol diff. It stores nested Godot artifacts outside the `_current` lane and writes `logs/dirty_update_cross_chunk_mass_runtime_current/dirty-update-cross-chunk-mass-runtime-summary.txt`.

## Runtime High-Count Matrix Gate

`scripts/dirty_update_high_count_runtime_gate.sh` requires a larger persisted-reload dirty runtime artifact and the current mass-edit/cross-chunk summaries:

- five persisted dirty cycles through server restart/reopen
- six reload cycles and 20 final persisted block verifications
- 40 persisted dirty blocks, 40 chunk replacements, 80 edge-neighbor subchunks, 60 partial dirty subchunks, and 60 partial saved subchunks
- current mass-edit and four-chunk cross-mass summaries still passing
- aggregate matrix totals of at least 60 dirty blocks, 60 chunk replacements, and 24 edits
- strict local budgets for terrain queue, compositor submit, process wall p95, zero GPU upload failures, and zero active protocol diff

Run the larger artifact explicitly:

```sh
RUMPELMC_DIRTY_HIGH_COUNT_RUN_PERSISTED_SMOKE=1 \
  sh scripts/dirty_update_high_count_runtime_gate.sh logs/dirty_update_high_count_runtime_current
```

The current fresh run passed with `persisted_soak_cycles=5`, `persisted_reload_cycles=6`, `persisted_final_verify_count=20`, `matrix_dirty_blocks=60`, `matrix_chunk_replace=60`, `matrix_edit_count=40`, `persisted_gpu_compositor_submit_max_ms=0.141`, and `persisted_gpu_upload_fail=0`.

Fresh repeated-edit benchmark evidence now lives at `logs/gpu_terrain_repeated_edit_benchmark_current/gpu-terrain-repeated-edit-benchmark-summary.txt`. It composes three single-edge repeats and three corner-edge repeats, passed with max queue/process/submit `2.972/0.050/0.150ms`, zero GPU upload failures, and default/visible-quality changes blocked.

Fresh border-edit benchmark evidence now lives at `logs/gpu_terrain_border_edit_benchmark_current/gpu-terrain-border-edit-benchmark-summary.txt`. It composes the repeated single/corner-edge benchmark with the pressure dirty compare at local `31,31`, passed with `case_count=3`, max dirty blocks `709`, max edge-neighbor subchunks `2836`, max partial saved subchunks `1418`, max queue/process/submit `4.777/0.050/0.171ms`, zero GPU upload failures, zero ground misses, and default/visible-quality changes blocked.

Fresh partial dirty edge matrix evidence now lives at `logs/gpu_terrain_partial_dirty_edge_matrix_current/gpu-terrain-partial-dirty-edge-matrix-summary.txt`. It refreshes full-vs-partial runtime compares for all four single edges and all four corner combinations, passed with `case_count=8`, min/max partial edge-neighbor subchunks `4/8`, min/max partial saved subchunks `2/2`, max queue/process/submit `3.734/0.041/0.102ms`, full rollback partial counters disabled, zero GPU upload failures, and default/visible-quality changes blocked.

Fresh collision refresh cost evidence now lives at `logs/gpu_collision_refresh_cost_audit_current/gpu-collision-refresh-cost-audit-summary.txt`. It consumes the partial dirty edge matrix and pressure dirty compare movement markers, passed with `case_count=18`, max collision refresh rebuilds `132`, max queue depth `17`, max phase total/component `1.950/1.540ms`, zero refresh missing, zero queue duplicate/stale/missing counters, zero GPU upload failures, and zero ground misses.

Fresh shadow proxy refresh cost evidence now lives at `logs/gpu_shadow_proxy_refresh_cost_audit_current/gpu-shadow-proxy-refresh-cost-audit-summary.txt`. It consumes the same partial dirty edge matrix and pressure dirty compare movement markers, passed with `case_count=18`, max proxy shadow `243`, max compact shadow proxy `808`, max compact shadow normals saved `5236`, max proxy refresh reuse `68`, zero native-shadow activation, zero GPU upload failures, and zero ground misses.

Fresh edit-burst budget evidence now lives at `logs/gpu_edit_burst_budget_gate_current/gpu-edit-burst-budget-summary.txt`. It composes repeated, border, partial-matrix, collision-refresh, shadow-refresh, and upload-budget summaries, passed with `source_count=6`, max queue/process/submit `4.777/0.050/0.171ms`, max dirty blocks `709`, max collision refresh rebuilds `132`, max compact shadow proxy `808`, max proxy refresh reuse `68`, zero GPU upload failures, zero ground misses, and default/visible/scheduler changes blocked.

Fresh edit visual parity evidence now lives at `logs/gpu_edit_visual_parity_gate_current/gpu-edit-visual-parity-summary.txt`. It validates the existing full rebuild versus partial dirty screenshots for all eight partial dirty edge/corner cases, passed with `case_count=8`, max average-luma delta `0.0000`, max terrain-luma-range delta `0.0000`, max terrain sample/color bucket/chroma deltas `0`, max partial edge-neighbor subchunks `8`, max partial saved subchunks `2`, zero GPU upload failures, zero ground misses, and external profiler/macOS/Windows blockers.

Fresh world-interaction checkpoint evidence now lives at `logs/gpu_world_interaction_checkpoint_current/gpu-world-interaction-checkpoint-summary.txt`. It composes the dirty runtime, correctness, collision, shadow, budget, visual parity, and upload-budget summaries, passed with `source_count=8`, `local_world_interaction_status=pass`, `rollout_status=defer_defaults`, max queue/process/submit `4.777/0.050/0.171ms`, max dirty blocks `709`, max compact shadow proxy `808`, max visual deltas `0.0000/0.0000/0/0`, zero GPU upload failures, zero ground misses, and explicit external profiler/macOS/Windows blockers.

## Deferred Work

Still needed:

- Multi-hour overnight persisted reload soak beyond the five-cycle local high-count gate.
- Larger cross-chunk mass-edit matrices beyond the current four-chunk plus persisted high-count matrix.
- Stricter collision refresh budget under larger mass edits.
- Stricter GPU upload budget under larger mass edits.
- Multi-client block edit fanout once server broadcast exists.

## Compatibility Rules

- Keep explicit `RUMPELMC_GPU_TERRAIN_PARTIAL_DIRTY_UPLOAD=0` as the full rebuild rollback path.
- Do not reduce collision, shadow, texture, draw-distance, or visible quality to make dirty updates pass.
- Do not change protocol or storage to optimize dirty updates without a protocol/storage task.
- Do not treat unit dirty math or the mixed current-chunk budget smoke as broad cross-chunk runtime scalability evidence.
- Do not run heavy Godot dirty repeat gates inside normal `check.sh`.

## Block 42 Gate

Use:

```sh
sh scripts/dirty_update_scalability_gate.sh logs/dirty_update_scalability_current
```

Without a runtime smoke summary, the default summary remains `status=pass`, `dirty_scalability_status=unit_guarded`, `mass_dirty_unit=pass`, `edge_runtime_scripts=available`, `runtime_edge_dirty=deferred`, `runtime_mass_edit=deferred`, `runtime_cross_chunk_mass_edit=deferred`, `runtime_persisted_dirty=deferred`, `runtime_high_count_matrix=deferred`, `active_protocol_change=0`, and `block_edit_persistence_status=pass`.

The gate checks that:

- This document records dirty contract, added unit guard, runtime entry points, deferred work, and compatibility rules.
- The mass dirty unit test exists.
- Required dirty runtime scripts exist and pass `sh -n`.
- Runtime edge dirty smoke evidence is clean when present or explicitly requested.
- Runtime mass-edit smoke evidence is clean when present or explicitly requested.
- Runtime cross-chunk mass-edit smoke evidence is clean when present or explicitly requested.
- Runtime persisted-reload dirty smoke evidence is clean when present or explicitly requested.
- Runtime high-count matrix evidence is clean when present or explicitly requested.
- Previous block edit persistence gate is clean.
- Focused Rust dirty tests pass.
- Protocol schema/generated files are unchanged.

After the opt-in edge, mass, cross-chunk mass, persisted-reload, and high-count runtime gates have been run, the expected current result is `status=pass`, `dirty_scalability_status=unit_edge_mixed_mass_persisted_cross_chunk_and_high_count_runtime_guarded`, `runtime_edge_dirty=godot_guarded`, `runtime_edge_dirty_status=pass`, `single_edge_compare=pass`, `corner_edge_compare=pass`, `corner_edge_repeat=pass`, `runtime_mass_edit=godot_guarded`, `runtime_mass_edit_status=pass`, `runtime_mass_budget=godot_guarded`, `mass_runtime_edit_count>=8`, `mass_runtime_place_actions>=4`, `mass_runtime_destroy_actions>=4`, `runtime_cross_chunk_mass_edit=godot_guarded`, `runtime_cross_chunk_mass_status=pass`, `cross_chunk_mass_budget=godot_guarded`, `cross_mass_runtime_cross_chunk_count>=4`, `cross_mass_runtime_edit_count>=8`, `runtime_persisted_dirty=godot_guarded`, `runtime_persisted_dirty_status=pass`, `persisted_runtime_soak_cycles>=3`, `persisted_runtime_reload_cycles>=4`, `persisted_runtime_final_verify_count>=12`, `runtime_high_count_matrix=persisted_reload_matrix_guarded`, `runtime_high_count_matrix_status=pass`, `high_count_persisted_soak_cycles>=5`, `high_count_persisted_final_verify_count>=20`, `high_count_matrix_dirty_blocks>=60`, `active_protocol_change=0`, and `block_edit_persistence_status=pass`.

## Current Status

This block is complete as a unit, edge-runtime, mixed current-chunk mass-edit budget, bounded three-cycle persisted-reload dirty-runtime checkpoint, bounded four-chunk mass-edit runtime checkpoint, and five-cycle high-count persisted-reload matrix checkpoint. Multi-hour soaks, stricter large-edit budgets, and multi-client block-edit fanout remain outside this checkpoint.
