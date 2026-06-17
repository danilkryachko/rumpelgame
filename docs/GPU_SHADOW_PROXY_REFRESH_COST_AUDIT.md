# GPU Shadow Proxy Refresh Cost Audit

Date: 2026-06-17

Scope: summary-only audit for Godot shadow proxy refresh cost during GPU terrain dirty-edit workloads. The audit reads existing partial dirty edge matrix and pressure dirty compare artifacts, then gates shadow proxy counters, compact proxy savings, native-shadow lockout, readiness, upload failures, and CPU-side queue/process/submit budgets against the 150 FPS frame budget. It does not change renderer behavior, draw distance, lighting, shadows, texture quality, visible quality, protocol, storage, world generation, chunk serialization, or the default runtime path.

## Command

Use:

```sh
sh scripts/gpu_shadow_proxy_refresh_cost_audit.sh logs/gpu_shadow_proxy_refresh_cost_audit_current
```

The script writes:

- `gpu-shadow-proxy-refresh-cost-audit-summary.txt`
- `gpu-shadow-proxy-refresh-cost-audit-cases.txt`

## Evidence Sources

The audit currently requires:

- all 16 movement marker files from `logs/gpu_terrain_partial_dirty_edge_matrix_current/cases/*/{full,partial}/gpu-terrain-movement-stress.png.txt`
- the 2 pressure dirty compare movement marker files under `logs/gpu_terrain_pressure_dirty_compare_current/{full,partial}/pressure/`
- the matching `movement-stress-summary.txt` files beside each marker

Each case must have:

- `shadow_path=godot_proxy`
- `shadow_mode=conservative`
- `shadow_mesh=compact`
- `mesh_shadow_only >= 1`
- `proxy_shadow >= 1`
- `proxy_shadow_only >= 1`
- `proxy_shadow == mesh_shadow_only`
- `cpu_proxy == proxy_shadow`
- `compact_shadow_proxy >= proxy_shadow`
- `compact_shadow_normals_saved >= 1`
- `proxy_refresh_reuse >= 1`
- `fast_proxy == compact_shadow_proxy`
- `native_shadow_requested=0`
- `native_shadow_active=0`
- `native_shadow_fallback=0`
- `native_shadow_implemented=0`
- `native_shadow_resource_status=disabled`
- `current_chunk_collision >= 1`
- `ground_misses=0`
- `gpu_upload_fail=0`
- `gpu_upload_fail_capacity=0`
- `gpu_upload_fail_fragmented=0`
- `terrain_queue_max_ms <= 6.667`
- `process_wall_p95_ms <= 6.667`
- `gpu_compositor_submit_max_ms <= 6.667`

This intentionally validates the current Godot proxy path. It is not approval to enable a GPU-native shadow path, reduce shadow distance, disable shadows, or change visible quality.

## Fresh Evidence

Fresh local evidence:

- `logs/gpu_shadow_proxy_refresh_cost_audit_current/gpu-shadow-proxy-refresh-cost-audit-summary.txt`
- `logs/gpu_shadow_proxy_refresh_cost_audit_current/gpu-shadow-proxy-refresh-cost-audit-cases.txt`

The current audit passed with `18` cases, `18` passes, `16` partial dirty edge matrix cases, `2` pressure dirty cases, max mesh/proxy shadow `243/243`, max proxy-shadow-only `228`, max compact shadow proxy `808`, max compact shadow normals saved `5236`, max proxy refresh reuse `68`, max queue/process/submit `4.777/0.041/0.171ms`, zero native-shadow activation, zero upload failures, and zero ground misses.

The summary records `default_runtime_change_allowed=0`, `visible_quality_change_allowed=0`, `external_profile_status=pending_external_profiler`, `requires_external_profiler_before_default=1`, and `requires_mac_windows_validation=1`.

## Report And Strategy Wiring

- `scripts/gpu_stress_artifact_index.sh` requires the shadow proxy refresh cost audit as a `world_interaction` row.
- `scripts/test_strategy_gate.sh` requires the audit summary before the GPU stress artifact index and includes the wrapper in the nightly summary chain.
- `scripts/gpu_terrain_report.sh` surfaces the selected audit summary and case rows.

## External Context

- Godot's 3D lights and shadows documentation records shadow-quality and shadow-distance tradeoffs for real-time 3D lights: https://docs.godotengine.org/en/stable/tutorials/3d/lights_and_shadows.html
- Godot's 3D optimization guide calls out visibility, occlusion, LOD, and large-world considerations for complex scenes: https://docs.godotengine.org/en/stable/tutorials/performance/optimizing_3d_performance.html

Those docs support treating shadow proxy refresh as explicit workload evidence. Local FPS and Godot GPU timestamps remain report-only until external profiler rows cover macOS/Metal and Windows/Vulkan/Direct3D.
