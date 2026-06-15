# GPU Upload Pressure

Date: 2026-06-15

This note records the current GPU upload pressure track.

## Gate

The upload-pressure wrapper is:

```sh
RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE=1 RUMPELMC_GODOT_RUST_EXT_PROFILE=release ./scripts/gpu_terrain_upload_pressure.sh logs/gpu_terrain_upload_pressure
```

It runs fill stress, then runs the allocator stress gate over the captured artifact, and writes `gpu-upload-pressure-summary.txt`.

Default behavior is intentionally stressful but still reversible:

- server view distance `16`
- client keep distance `16`
- enforced fill repeats `1 2 4 8`
- report-only repeat `16`
- allocator gate requires zero upload failures, zero capacity failures, zero fragmentation failures, and fragmentation within budget

Set `RUMPELMC_GPU_UPLOAD_PRESSURE_REPORT_ONLY_REPEATS=''` to disable report-only repeats for a narrow smoke. Set `RUMPELMC_GPU_UPLOAD_PRESSURE_SOURCE_FILL_SUMMARY=<path>` and `RUMPELMC_GPU_UPLOAD_PRESSURE_SOURCE_ALLOCATOR_SUMMARY=<path>` to summarize existing artifacts without rerunning.

## Fresh Evidence

Short validation:

```sh
GODOT_TIMEOUT_SEC=180 \
RUMPELMC_GPU_UPLOAD_PRESSURE_REPEATS=1 \
RUMPELMC_GPU_UPLOAD_PRESSURE_SETTLE_SEC=4.0 \
RUMPELMC_GPU_UPLOAD_PRESSURE_SMOKE_DELAY_SEC=5.0 \
RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE=1 \
RUMPELMC_GODOT_RUST_EXT_PROFILE=release \
/bin/sh scripts/gpu_terrain_upload_pressure.sh logs/gpu_terrain_upload_pressure_smoke
```

Fresh check:

- `logs/gpu_terrain_upload_pressure_smoke/gpu-upload-pressure-summary.txt` passed with enforced repeat `1` and report-only repeat `16`, `max_gpu_effective_draws=21216`, `max_gpu_faces=1469`, `gpu_upload_fail=0`, `gpu_upload_fail_capacity=0`, `gpu_upload_fail_fragmented=0`, `max_gpu_fragmentation_pct=0.0`, `max_terrain_queue_ms=2.079`, `max_process_wall_p95_ms=0.047`, and `max_gpu_compositor_submit_ms=0.132`.
- `logs/gpu_terrain_upload_pressure_smoke/gpu-upload-pressure-allocator-summary.txt` passed with allocator fragmentation `0.000` and zero upload/capacity/fragmentation failures.
