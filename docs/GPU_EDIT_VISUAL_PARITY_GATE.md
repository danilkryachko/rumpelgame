# GPU Edit Visual Parity Gate

Date: 2026-06-17

Scope: summary-only visual parity gate for current GPU dirty-edit evidence. It validates the existing full rebuild versus partial dirty screenshot markers from the partial dirty edge matrix. It does not change renderer behavior, dirty upload policy, draw distance, lighting, shadows, texture quality, visible quality, protocol, storage, world generation, or chunk serialization.

## Command

Use:

```sh
sh scripts/gpu_edit_visual_parity_gate.sh logs/gpu_edit_visual_parity_gate_current
```

The script writes:

- `gpu-edit-visual-parity-summary.txt`
- `gpu-edit-visual-parity-cases.txt`

## Inputs

By default the gate consumes full and partial marker pairs under:

- `logs/gpu_terrain_partial_dirty_edge_matrix_current/cases`

The case root can be overridden with `RUMPELMC_EDIT_VISUAL_PARITY_CASE_ROOT`. The default cases are:

- `pos_x_single`
- `neg_x_single`
- `pos_z_single`
- `neg_z_single`
- `pos_x_pos_z_corner`
- `pos_x_neg_z_corner`
- `neg_x_pos_z_corner`
- `neg_x_neg_z_corner`

## Contract

The gate fails unless every full and partial case has:

- a non-empty screenshot and marker file
- `Visual smoke screenshot saved`
- `pose=default`, `motion=chunk_walk`, and `block_edit=toggle`
- `block_edit_dirty_observed=1`
- `shadow_path=godot_proxy`, `shadow_mode=conservative`, and `shadow_mesh=compact`
- `smoke_err=0`, `gpu_upload_fail=0`, and `ground_misses=0`
- positive GPU frame/subchunk/face evidence
- current chunk render and collision readiness
- terrain sample, color bucket, chroma, luma range, and screen-region sample minimums
- matching edit identity between full and partial summaries
- matching current chunk submesh and collision counts

The default visual parity thresholds are intentionally tighter than broad CPU/GPU parity:

- `RUMPELMC_EDIT_VISUAL_PARITY_MAX_AVG_LUMA_DELTA=0.02`
- `RUMPELMC_EDIT_VISUAL_PARITY_MAX_TERRAIN_LUMA_RANGE_DELTA=0.02`
- `RUMPELMC_EDIT_VISUAL_PARITY_MAX_TERRAIN_SAMPLE_DELTA_PERCENT=5`
- `RUMPELMC_EDIT_VISUAL_PARITY_MAX_TERRAIN_COLOR_BUCKET_DELTA_PERCENT=15`

## Fresh Evidence

Fresh local evidence:

- `logs/gpu_edit_visual_parity_gate_current/gpu-edit-visual-parity-summary.txt`
- `logs/gpu_edit_visual_parity_gate_current/gpu-edit-visual-parity-cases.txt`

The current gate passed with `case_count=8`, `pass_cases=8`, `marker_count=16`, max average-luma delta `0.0000`, max terrain-luma-range delta `0.0000`, max terrain sample delta `0`, max terrain color bucket delta `0`, max terrain chroma sample delta `0`, max partial dirty edge-neighbor subchunks `8`, max partial dirty partial subchunks `4`, max partial dirty saved subchunks `2`, `smoke_err=0`, `gpu_upload_fail=0`, `ground_misses=0`, and `block_edit_dirty_observed_failures=0`.

The gate emits `external_profile_status=pending_external_profiler`, `requires_external_profiler_before_default=1`, and `requires_mac_windows_validation=1`; local screenshot parity is not enough to approve new defaults on its own.

## Report And Strategy Wiring

- `scripts/gpu_stress_artifact_index.sh` requires the edit visual parity summary as a `world_interaction` row.
- `scripts/test_strategy_gate.sh` requires the edit visual parity summary and includes the gate in the nightly summary chain.
- `scripts/gpu_terrain_report.sh` surfaces the selected edit visual parity summary and case rows, plus max visual deltas.

## External Context

Godot's `Viewport.get_texture()` documentation notes that correct screenshot capture should wait until after draw completion, which matches the current visual smoke marker model. Godot's 3D optimization guidance keeps culling, visibility, LOD, and GPU workload topics explicit; this gate keeps visual output stable before using edit-path performance evidence for any runtime-default decision.

- <https://docs.godotengine.org/en/stable/classes/class_viewport.html>
- <https://docs.godotengine.org/en/stable/tutorials/performance/optimizing_3d_performance.html>
