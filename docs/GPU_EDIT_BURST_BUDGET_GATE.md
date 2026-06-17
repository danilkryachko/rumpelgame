# GPU Edit Burst Budget Gate

Date: 2026-06-17

Scope: summary-only budget gate for current GPU dirty-edit burst evidence. It composes repeated edge edits, border pressure edits, the partial dirty edge matrix, collision refresh cost, shadow proxy refresh cost, and the GPU upload budget into one required world-interaction artifact. It does not change renderer behavior, dirty upload policy, draw distance, lighting, shadows, texture quality, visible quality, protocol, storage, world generation, or chunk serialization.

## Command

Use:

```sh
sh scripts/gpu_edit_burst_budget_gate.sh logs/gpu_edit_burst_budget_gate_current
```

The script writes:

- `gpu-edit-burst-budget-summary.txt`
- `gpu-edit-burst-budget-cases.txt`

## Inputs

By default the gate consumes:

- `logs/gpu_terrain_repeated_edit_benchmark_current/gpu-terrain-repeated-edit-benchmark-summary.txt`
- `logs/gpu_terrain_border_edit_benchmark_current/gpu-terrain-border-edit-benchmark-summary.txt`
- `logs/gpu_terrain_partial_dirty_edge_matrix_current/gpu-terrain-partial-dirty-edge-matrix-summary.txt`
- `logs/gpu_collision_refresh_cost_audit_current/gpu-collision-refresh-cost-audit-summary.txt`
- `logs/gpu_shadow_proxy_refresh_cost_audit_current/gpu-shadow-proxy-refresh-cost-audit-summary.txt`
- `logs/gpu_terrain_upload_budget_current/gpu-terrain-upload-budget-summary.txt`

Each input path can be overridden with `RUMPELMC_EDIT_BURST_BUDGET_*_SUMMARY`.

## Contract

The gate fails unless:

- all required source summaries exist and pass
- repeated single-edge and corner-edge edit lanes have at least three passing runs each
- border pressure evidence keeps at least `512` dirty blocks by default
- partial dirty edge evidence includes all four single-edge cases and all four corner cases
- collision refresh has matrix plus pressure coverage, positive rebuild evidence, zero refresh missing, and zero duplicate/stale/missing queue counters
- shadow proxy refresh keeps the current `godot_proxy` conservative compact path, positive compact savings/reuse, and zero native-shadow activation
- normal GPU upload failures and ground misses stay zero
- queue/process/submit maxima stay under the `150 FPS` CPU-side frame budget by default
- `default_runtime_change_allowed=0`, `visible_quality_change_allowed=0`, and `scheduler_change_allowed=0`

The default budget is derived from `RUMPELMC_EDIT_BURST_BUDGET_TARGET_FPS=150`. Override `RUMPELMC_EDIT_BURST_BUDGET_MAX_QUEUE_MS`, `RUMPELMC_EDIT_BURST_BUDGET_MAX_PROCESS_MS`, or `RUMPELMC_EDIT_BURST_BUDGET_MAX_SUBMIT_MS` only for focused negative checks or explicit rebaselining.

## Fresh Evidence

Fresh local evidence:

- `logs/gpu_edit_burst_budget_gate_current/gpu-edit-burst-budget-summary.txt`
- `logs/gpu_edit_burst_budget_gate_current/gpu-edit-burst-budget-cases.txt`

The current gate passed with `source_count=6`, `pass_sources=6`, max queue/process/submit `4.777/0.050/0.171ms`, max dirty blocks `709`, max dirty edge-neighbor subchunks `2836`, max dirty partial saved subchunks `1418`, max partial edge-neighbor subchunks `8`, max partial saved subchunks `2`, max collision refresh rebuilds `132`, max collision queue depth `17`, max collision phase total/component `1.950/1.540ms`, max proxy shadow `243`, max proxy-shadow-only `228`, max compact shadow proxy `808`, max compact shadow normals saved `5236`, max proxy refresh reuse `68`, `gpu_upload_fail=0`, `ground_misses=0`, and default/visible/scheduler change blockers all `0`.

The gate emits `external_profile_status=pending_external_profiler`, `requires_external_profiler_before_default=1`, and `requires_mac_windows_validation=1`; local macOS/Metal CPU-side evidence is not enough to approve new defaults on its own.

## Report And Strategy Wiring

- `scripts/gpu_stress_artifact_index.sh` requires the edit-burst budget summary as a `world_interaction` row.
- `scripts/test_strategy_gate.sh` requires the edit-burst budget summary and includes the gate in the nightly summary chain.
- `scripts/gpu_terrain_report.sh` surfaces the selected edit-burst budget summary and case rows.

## External Context

Godot's official 3D optimization guidance keeps culling/visibility and workload reduction as explicit performance topics, while the RenderingDevice API exposes buffer update behavior that should be validated with platform profiler evidence before default policy changes. Godot's light and shadow documentation also treats shadow quality/cost as renderer-facing state, so this gate keeps the existing Godot proxy shadow path locked until separate visual parity and external profiler evidence exist.

- <https://docs.godotengine.org/en/stable/tutorials/performance/optimizing_3d_performance.html>
- <https://docs.godotengine.org/en/stable/classes/class_renderingdevice.html>
- <https://docs.godotengine.org/en/stable/tutorials/3d/lights_and_shadows.html>
