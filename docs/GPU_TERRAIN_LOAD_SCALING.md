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

## Fresh Evidence

Summary-only validation over the fresh radius-16 resident-set artifact:

```sh
RUMPELMC_GPU_LOAD_SCALING_SOURCE_SUMMARY=logs/world_streaming_resident_set_growth_radius16_check/resident-set-growth-summary.txt \
/bin/sh scripts/gpu_terrain_load_scaling.sh logs/gpu_terrain_load_scaling_radius16_summary_check
```

Fresh check:

- `logs/gpu_terrain_load_scaling_radius16_summary_check/gpu-terrain-load-scaling-summary.txt` passed with `max_gpu_subchunks=2482`, `max_gpu_draws=2482`, `max_gpu_faces=3165`, draw-command occupancy `30.298%`, headroom `91360` bytes, `max_terrain_queue_ms=2.214`, `max_process_wall_p95_ms=0.059`, `max_gpu_compositor_submit_ms=5.677`, and zero GPU upload failures.
