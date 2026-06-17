# GPU Collision Refresh Cost Audit

Date: 2026-06-17

Scope: summary-only audit for collision refresh cost during GPU terrain dirty-edit workloads. The audit reads existing partial dirty edge matrix and pressure dirty compare artifacts, then gates collision rebuild churn, queue health, readiness, upload failures, and `collision_refresh_phase_max` against the 150 FPS CPU-side frame budget. It does not change renderer behavior, draw distance, lighting, shadows, texture quality, visible quality, protocol, storage, world generation, chunk serialization, or the default runtime path.

## Command

Use:

```sh
sh scripts/gpu_collision_refresh_cost_audit.sh logs/gpu_collision_refresh_cost_audit_current
```

The script writes:

- `gpu-collision-refresh-cost-audit-summary.txt`
- `gpu-collision-refresh-cost-audit-cases.txt`

## Evidence Sources

The audit currently requires:

- all 16 movement marker files from `logs/gpu_terrain_partial_dirty_edge_matrix_current/cases/*/{full,partial}/gpu-terrain-movement-stress.png.txt`
- the 2 pressure dirty compare movement marker files under `logs/gpu_terrain_pressure_dirty_compare_current/{full,partial}/pressure/`
- the matching `movement-stress-summary.txt` files beside each marker

Each case must have:

- `collision_refresh >= 1`
- `collision_refresh_rebuilt >= 1`
- `collision_refresh_last_rebuilt >= 1`
- `collision_refresh_missing=0`
- `collision_q_dup=0`
- `collision_q_stale=0`
- `collision_q_missing=0`
- `collision_q_max <= 64`
- `collision_phase_total_ms <= 6.667`
- `collision_phase_component_ms <= 6.667`
- `current_chunk_collision >= 1`
- `ground_misses=0`
- `gpu_upload_fail=0`
- `gpu_upload_fail_capacity=0`
- `gpu_upload_fail_fragmented=0`

`collision_refresh_phase_max` is parsed as `faces/clear/create/count/node_counts`; the gate records both total and max component so a future regression in any one part is visible.

## Fresh Evidence

Fresh local evidence:

- `logs/gpu_collision_refresh_cost_audit_current/gpu-collision-refresh-cost-audit-summary.txt`
- `logs/gpu_collision_refresh_cost_audit_current/gpu-collision-refresh-cost-audit-cases.txt`

The current audit passed with `18` cases, `18` passes, `16` partial dirty edge matrix cases, `2` pressure dirty cases, max collision refresh rebuilds `132`, max collision queue depth `17`, max phase total `1.950ms`, max phase component `1.540ms`, max queue/process/submit `4.777/0.041/0.171ms`, zero collision refresh missing, zero queue duplicate/stale/missing counters, zero GPU upload failures, and zero ground misses.

The summary records `default_runtime_change_allowed=0`, `visible_quality_change_allowed=0`, `external_profile_status=pending_external_profiler`, `requires_external_profiler_before_default=1`, and `requires_mac_windows_validation=1`.

## Report And Strategy Wiring

- `scripts/gpu_stress_artifact_index.sh` requires the collision refresh cost audit as a `world_interaction` row.
- `scripts/test_strategy_gate.sh` requires the audit summary before the GPU stress artifact index and includes the wrapper in the nightly summary chain.
- `scripts/gpu_terrain_report.sh` surfaces the selected audit summary and case rows.

## External Context

- Godot `PhysicsServer3D` exposes body/shape lifecycle APIs such as `body_clear_shapes()`, `body_create()`, and `body_add_shape()`: https://docs.godotengine.org/en/stable/classes/class_physicsserver3d.html
- Godot's 3D optimization guide calls out large-level culling/visibility problems and LOD/occlusion strategies: https://docs.godotengine.org/en/stable/tutorials/performance/optimizing_3d_performance.html

Those docs support treating collision refresh as resource churn plus phase-time evidence. Local FPS and Godot GPU timestamps remain report-only until external profiler rows cover macOS/Metal and Windows/Vulkan/Direct3D.
