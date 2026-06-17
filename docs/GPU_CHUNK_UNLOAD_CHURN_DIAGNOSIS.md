# GPU Chunk Unload Churn Diagnosis

Date: 2026-06-16

Scope: summary-only diagnosis for client chunk unload/reload churn on the GPU world-loading path. This gate does not change unload policy, draw distance, camera far plane, lighting, shadows, texture quality, visible quality, protocol, storage, world generation, or chunk serialization.

## Command

Use:

```sh
sh scripts/gpu_chunk_unload_churn_diagnosis.sh logs/gpu_chunk_unload_churn_diagnosis_current
```

The script writes:

- `gpu-chunk-unload-churn-diagnosis-summary.txt`

By default the gate consumes the current chunk-boundary stress summary:

- `logs/gpu_terrain_chunk_boundary_stress_current/chunk-boundary-stress-summary.txt`

Optional teleport-only controls are read when present:

- `logs/world_streaming_high_pressure_suite_teleport_unload_churn_check/world-load-suite-summary.txt`
- `logs/world_streaming_high_pressure_suite_teleport_unload_churn_grace0_check/world-load-suite-summary.txt`

Set `RUMPELMC_GPU_CHUNK_UNLOAD_REQUIRE_CONTROLS=1` to require both teleport-only control summaries in addition to the chunk-boundary proof.

## Gate Contract

The required current proof must:

- have a passing `chunk_boundary_stress` summary
- include `fast-turn` and `teleport-snap` movement cases
- require no default-grace unloads
- report `max_chunk_unload_total=0`
- report `max_chunk_unload_neighbor_refreshes=0`
- report `max_chunk_unload=0`
- report nonzero `max_chunk_unload_grace_kept`
- report zero GPU upload failures and zero ground misses
- keep current render and collision readiness passing

If optional controls are present, the default-grace control must show no unload churn, and the immediate-unload control must show positive unload and neighbor-refresh churn. Missing controls are visible as `default_control_status=missing` / `immediate_control_status=missing`; they only fail the gate when `RUMPELMC_GPU_CHUNK_UNLOAD_REQUIRE_CONTROLS=1`.

## Fresh Evidence

Fresh local evidence:

- `logs/gpu_chunk_unload_churn_diagnosis_current/gpu-chunk-unload-churn-diagnosis-summary.txt`

The current diagnosis passed with:

- `max_chunk_unload_total=0`
- `max_chunk_unload_grace_kept=48984`
- `max_chunk_unload_neighbor_refreshes=0`
- `max_chunk_unload=0`
- `max_popin_missing_chunks=140`
- `max_popin_collision_missing_chunks=109`
- max terrain queue / process p95 / compositor submit `2.258ms / 0.049ms / 0.124ms`
- packet queue lag max `27.437ms`
- `gpu_upload_fail=0`
- `ground_misses=0`
- `render_not_ready_cases=0`
- `collision_not_ready_cases=0`

The two older teleport-only control summaries are missing in this checkout, so the current summary records `default_control_status=missing`, `immediate_control_status=missing`, and `controls_required=0`.

## Decision

Keep the current grace-based unload policy. The fresh chunk-boundary proof shows that default grace absorbs unload churn across long movement, spiral movement, fast turns, and teleport snap without upload failures, ground misses, or current render/collision readiness failures.

Do not change unload policy until fresh default and immediate teleport controls are available and compared with pop-in/collision budgets. Pop-in counters remain report-only until explicit budgets are defined.

## External Context

- Godot's [3D optimization guide](https://docs.godotengine.org/en/latest/tutorials/performance/optimizing_3d_performance.html) keeps visibility, occlusion, and world-scale decisions evidence-driven; this gate keeps unload behavior measurable before changing residency.
- Godot [`RenderingDevice`](https://docs.godotengine.org/en/stable/classes/class_renderingdevice.html) GPU timestamp samples remain report-only for this local macOS/Metal path, so the gate uses CPU-side queue/submit metrics plus runtime correctness markers.
- Godot's [large world coordinates](https://docs.godotengine.org/en/stable/tutorials/physics/large_world_coordinates.html) documentation is relevant for future large-world/origin work; this gate does not change coordinate policy.
