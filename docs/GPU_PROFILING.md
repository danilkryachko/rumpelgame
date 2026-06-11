# GPU Profiling

This document defines how GPU terrain performance should be measured. The goal is to make optimization decisions from stable evidence, not from a display-limited FPS counter.

## Current Situation

- The project uses Godot + Rust GDExtension with a GPU-resident terrain path.
- Local macOS/Metal automated visual captures can be display-paced at 60 Hz even with V-Sync disabled in Godot.
- Godot `RenderingDevice` timestamp samples currently report `0.0us` on the local macOS/Metal path, so they are report-only until proven reliable.
- CPU-side terrain queue, process wall time, upload failures, draw counts, and compositor submit parts are still useful local signals.

## Trusted Local Signals

- `gpu_upload_fail`: must stay `0` in normal stress runs.
- `terrain_queue_work_ms`: useful for Rust/Godot terrain queue CPU work.
- `process_wall_p95_ms`: useful for client `_process` CPU pressure.
- `gpu_compositor_submit_ms`: useful for CPU-side compositor submission overhead.
- `gpu_compositor_submit_max_parts`: useful to separate setup, target, constants, and draw submission cost.
- `gpu_draws`, `gpu_effective_draws`, `gpu_faces`, `gpu_subchunks`: useful for workload size.
- `smoke_err`, `terrain_samples`, color buckets, and marker generation: useful for visual correctness gates.

## Report-Only Or Untrusted Local Signals

- `frame_p95_ms` and `fps_p05` above monitor refresh: can be capped by display/driver pacing.
- `gpu_compositor_gpu_us` on current macOS/Metal: samples exist but currently report `0.0us`.
- Single-run fill-stress FPS: useful as a hint only when control runs prove the display limiter did not dominate.

## macOS Metal Workflow

1. Run a release stress script and save artifacts under `logs/`.
2. Prefer a case with high `gpu_effective_draws` and `gpu_upload_fail=0`.
3. Capture a Metal frame with Xcode/Metal tools outside the automated smoke path.
4. Record the Godot version, backend, display refresh, stress env vars, and artifact path.
5. Compare GPU draw/pass time against CPU submit metrics from the same run.

## Windows Workflow

1. Run the same release stress case used on macOS.
2. Capture with RenderDoc, PIX, or a vendor profiler supported by the active backend.
3. Record backend, driver version, GPU model, stress env vars, and artifact path.
4. Compare GPU pass time, draw count, bandwidth pressure, and shader cost.
5. Do not accept Windows-only optimizations unless macOS behavior remains correct or the path is explicitly backend-gated.

## Recommended Local Commands

Use release builds for terrain performance comparisons:

```sh
RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE=1 \
RUMPELMC_GODOT_RUST_EXT_PROFILE=release \
./scripts/gpu_terrain_movement_stress.sh logs/gpu_terrain_profile_movement
```

Use fill stress to increase draw/fill pressure without reducing visible quality:

```sh
RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE=1 \
RUMPELMC_GODOT_RUST_EXT_PROFILE=release \
RUMPELMC_FILL_STRESS_REPEATS="1 4 8" \
./scripts/gpu_terrain_fill_stress.sh logs/gpu_terrain_profile_fill
```

Use workload matrix to compare movement and resident-load cases:

```sh
RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE=1 \
RUMPELMC_GODOT_RUST_EXT_PROFILE=release \
./scripts/gpu_terrain_workload_matrix.sh logs/gpu_terrain_profile_matrix
```

## Recording Results

For each meaningful GPU iteration, record:

- Commit or dirty diff summary.
- Command and env vars.
- Artifact directory.
- Workload size: draws, effective draws, faces, subchunks.
- Correctness: smoke marker, terrain samples, upload failures.
- CPU-side cost: terrain queue, process wall, compositor submit.
- GPU profiler result if available.
- Blockers and whether the next iteration can continue locally.
