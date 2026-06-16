# GPU Terrain Load Scaling

Date: 2026-06-15

This note records the current GPU terrain load-scaling gate for high resident sets.

## Gate

The dedicated load-scaling gate is:

```sh
RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE=1 RUMPELMC_GODOT_RUST_EXT_PROFILE=release ./scripts/gpu_terrain_load_scaling.sh logs/gpu_terrain_load_scaling
```

By default it runs the resident-set growth wrapper and then requires:

- `max_gpu_subchunks >= 2000`
- `max_gpu_draws >= 2000`
- `max_gpu_faces >= 3000`
- draw-command occupancy at least `25%`
- zero GPU upload failures

Set `RUMPELMC_GPU_LOAD_SCALING_SOURCE_SUMMARY=<path>` to validate an existing resident-set summary without rerunning the heavy workload.

For deterministic high face pressure on clean flat-world databases, set `RUMPELMC_RESIDENT_SET_CASE_SET=pressure` or use `scripts/gpu_terrain_upload_stage_pool_load_scaling_gate.sh`. The pressure case drives the normal visual-smoke `BlockAction_PLACE` path with `RUMPELMC_VISUAL_SMOKE_TERRAIN_PRESSURE_FIXTURE=chunk_disc`, placing one block per chunk inside the current client keep-radius disc, waiting for dirty growth and terrain queue drain, and then validating the same load-scaling thresholds. This is a stress-only workload fixture; it does not change default draw distance, visible quality, protocol, storage, world generation, or chunk serialization.

The load-scaling summary also carries upload-stage evidence for comparison gates:

- `max_gpu_uploads`
- `gpu_upload_stage_pool_enabled`
- `gpu_upload_stage_pool_entries`
- `gpu_upload_stage_pool_bytes`
- `gpu_upload_stage_pba_creates`
- `gpu_upload_stage_pba_reuses`
- `source_case_set`
- `terrain_pressure_fixture`
- `terrain_pressure_fixture_blocks`
- `terrain_pressure_fixture_dirty_observed`
- dirty-update counters such as `dirty_blocks`, `dirty_rebuild_subchunks`, `dirty_partial_subchunks`, `dirty_partial_saved_subchunks`, `dirty_edge_neighbor_chunks`, `dirty_edge_neighbor_subchunks`, `dirty_last_bounds`, and `dirty_last_edges`

For dirty-update pressure, `scripts/gpu_terrain_pressure_dirty_compare.sh` runs the pressure workload twice against isolated RocksDB paths: once with `RUMPELMC_GPU_TERRAIN_PARTIAL_DIRTY_UPLOAD=0` as the full-rebuild control and once with `=1` as the partial-dirty lane. The default fixture uses `chunk_disc` at local block `31,31` so every changed block touches both positive chunk edges. The gate rejects server reuse on port `25565`, requires both lanes to observe the same pressure fixture, requires the partial lane to produce edge-neighbor refresh and saved subchunks, and keeps upload failures, terrain queue, process wall, compositor submit, collision, ground-miss, and terrain-sample budgets intact.

## Fresh Evidence

Summary-only validation over the fresh radius-16 resident-set artifact:

```sh
RUMPELMC_GPU_LOAD_SCALING_SOURCE_SUMMARY=logs/world_streaming_resident_set_growth_radius16_check/resident-set-growth-summary.txt \
/bin/sh scripts/gpu_terrain_load_scaling.sh logs/gpu_terrain_load_scaling_radius16_summary_check
```

Fresh check:

- `logs/gpu_terrain_load_scaling_radius16_summary_check/gpu-terrain-load-scaling-summary.txt` passed with `max_gpu_subchunks=2482`, `max_gpu_draws=2482`, `max_gpu_faces=3165`, draw-command occupancy `30.298%`, headroom `91360` bytes, `max_terrain_queue_ms=2.214`, `max_process_wall_p95_ms=0.059`, `max_gpu_compositor_submit_ms=5.677`, and zero GPU upload failures.

Fresh 2026-06-16 pressure-fixture evidence replaced the stale clean-flat-world face-pressure gap without lowering thresholds. `logs/gpu_pressure_fixture_probe/workload-matrix-summary.txt` passed the pressure workload with `terrain_pressure_fixture_blocks=709`, `gpu_subchunks=2344`, `gpu_draws=2344`, `gpu_faces=6622`, and upload failures `0`. The high resident-set stage-pool comparison at `logs/gpu_terrain_upload_stage_pool_load_scaling_current/gpu-terrain-upload-stage-pool-load-scaling-summary.txt` then passed both baseline and pooled lanes with `2289` subchunks/draws, `6292` faces, draw-command occupancy `27.942%`, and zero upload failures.

Fresh pressure dirty compare evidence at `logs/gpu_terrain_pressure_dirty_compare_current/gpu-terrain-pressure-dirty-compare-summary.txt` passed with full and partial lanes both observing `terrain_pressure_fixture_blocks=709` and `dirty_blocks=709`. The full lane stayed on the rollback path with `dirty_partial_subchunks=0` and `dirty_partial_saved_subchunks=0`; the partial lane reported `dirty_partial_subchunks=709`, `dirty_partial_saved_subchunks=1418`, `dirty_edge_neighbor_chunks=1418`, `dirty_edge_neighbor_subchunks=2836`, `dirty_last_edges=pos_x,pos_z`, upload failures `0`, `terrain_queue_max_ms=4.777`, `process_wall_p95_ms=0.033`, `gpu_compositor_submit_max_ms=0.158`, `current_chunk_collision=3`, `ground_misses=0`, and `terrain_samples=385`.
