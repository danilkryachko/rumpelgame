# GPU World Interaction Checkpoint

Date: 2026-06-17

Scope: summary-only checkpoint for local GPU world-interaction readiness. It composes dirty edit runtime evidence, partial dirty correctness, collision refresh cost, shadow proxy refresh cost, edit-burst budgets, edit visual parity, and upload budget evidence into one required artifact. It does not change renderer behavior, dirty upload policy, draw distance, lighting, shadows, texture quality, visible quality, protocol, storage, world generation, or chunk serialization.

## Command

Use:

```sh
sh scripts/gpu_world_interaction_checkpoint.sh logs/gpu_world_interaction_checkpoint_current
```

The script writes:

- `gpu-world-interaction-checkpoint-summary.txt`
- `gpu-world-interaction-checkpoint-sources.txt`

## Inputs

By default the checkpoint consumes:

- `logs/gpu_terrain_repeated_edit_benchmark_current/gpu-terrain-repeated-edit-benchmark-summary.txt`
- `logs/gpu_terrain_border_edit_benchmark_current/gpu-terrain-border-edit-benchmark-summary.txt`
- `logs/gpu_terrain_partial_dirty_edge_matrix_current/gpu-terrain-partial-dirty-edge-matrix-summary.txt`
- `logs/gpu_collision_refresh_cost_audit_current/gpu-collision-refresh-cost-audit-summary.txt`
- `logs/gpu_shadow_proxy_refresh_cost_audit_current/gpu-shadow-proxy-refresh-cost-audit-summary.txt`
- `logs/gpu_edit_burst_budget_gate_current/gpu-edit-burst-budget-summary.txt`
- `logs/gpu_edit_visual_parity_gate_current/gpu-edit-visual-parity-summary.txt`
- `logs/gpu_terrain_upload_budget_current/gpu-terrain-upload-budget-summary.txt`

Each input path can be overridden with `RUMPELMC_WORLD_INTERACTION_CHECKPOINT_*_SUMMARY`.

## Contract

The checkpoint fails unless:

- all source summaries exist and pass
- repeated single-edge and corner-edge edit lanes have at least three runs each
- border edit pressure keeps at least `512` dirty blocks
- partial dirty edge matrix keeps all four single-edge cases and all four corner cases
- collision refresh and shadow proxy refresh audits cover the matrix plus pressure lanes
- edit burst budget has all six source summaries passing
- edit visual parity has all eight cases and sixteen markers passing with zero visual-delta failures
- upload budget has passing movement and in-place lanes with at least one in-place upload
- normal GPU upload failures and ground misses stay zero
- default runtime, visible quality, and scheduler change permissions remain zero
- external profiler and macOS/Windows validation blockers remain explicit

## Fresh Evidence

Fresh local evidence:

- `logs/gpu_world_interaction_checkpoint_current/gpu-world-interaction-checkpoint-summary.txt`
- `logs/gpu_world_interaction_checkpoint_current/gpu-world-interaction-checkpoint-sources.txt`

The current checkpoint passed with `source_count=8`, `pass_sources=8`, `local_world_interaction_status=pass`, `rollout_status=defer_defaults`, max queue/process/submit `4.777/0.050/0.171ms`, max dirty blocks `709`, max dirty edge-neighbor subchunks `2836`, max dirty partial saved subchunks `1418`, max partial edge-neighbor subchunks `8`, max partial saved subchunks `2`, max collision refresh rebuilds `132`, max collision phase total/component `1.950/1.540ms`, max proxy shadow `243`, max compact shadow proxy `808`, max compact shadow normals saved `5236`, max proxy refresh reuse `68`, max visual deltas `0.0000/0.0000/0/0`, max upload count/KiB per frame `1/2.000`, `gpu_upload_fail=0`, `ground_misses=0`, and all default/visible/scheduler change blockers at `0`.

The checkpoint deliberately emits `checkpoint_status=local_complete_external_pending`, `external_profile_status=pending_external_profiler`, `requires_external_profiler_before_default=1`, and `requires_mac_windows_validation=1`; local summary and screenshot evidence is not enough to approve default rollout.

## Report And Strategy Wiring

- `scripts/gpu_stress_artifact_index.sh` requires the checkpoint summary as a `world_interaction` row.
- `scripts/test_strategy_gate.sh` requires the checkpoint summary and includes the gate in the nightly summary chain.
- `scripts/gpu_terrain_report.sh` surfaces checkpoint status, local world-interaction status, rollout status, and selected checkpoint summary/source rows.

## External Context

Apple Metal, Microsoft Direct3D 12, and Vulkan guidance all separate CPU submission/resource-update structure from real GPU profiler validation. This checkpoint therefore locks local correctness and CPU-side budget evidence, while keeping macOS Metal and Windows GPU profiler rows as the required next proof before default rollout.

- <https://developer.apple.com/metal/>
- <https://learn.microsoft.com/en-us/windows/win32/direct3d12/>
- <https://docs.vulkan.org/guide/latest/synchronization.html>
