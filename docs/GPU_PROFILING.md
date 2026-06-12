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
- `proxy_shadow`, `proxy_shadow_only`, `compact_shadow_proxy`, and `compact_shadow_normals_saved`: useful local signals for shadow proxy load and compact proxy savings.
- `smoke_err`, `terrain_samples`, color buckets, and marker generation: useful for visual correctness gates.

## Shader Findings

- GPU terrain face lighting normals now use a branchless 8-entry shader lookup table. Entries `5`, `6`, and `7` intentionally resolve to `+Z`, preserving the previous fallback behavior for any masked nonstandard face index while removing the old `face_normal` branch chain.
- GPU terrain face UVs now use a branchless 32-entry shader lookup table. Rows `6` and `7` intentionally preserve the previous fallback UV order.
- GPU terrain face corners now use branchless `FACE_CORNER_BASES`, `FACE_CORNER_EXTENT_X_FACTORS`, and `FACE_CORNER_EXTENT_Y_FACTORS` tables. Rows `6` and `7` intentionally preserve the previous front-face fallback, and the geometry-affecting change was checked with full CPU/GPU terrain parity in `logs/gpu_shader_branchless_corners_parity`.
- `scripts/gpu_terrain_parity_smoke.sh` writes `parity-summary.txt` after a passing full or validate-only parity run. Use it as the compact evidence for atlas/depth, lighting/shadow, compact-shadow, and texture-stand visual deltas before deciding whether another shader change needs fresh captures.
- The render shader lighting contract is guarded in Rust tests: vertex code computes lighting from `face_normal(face_idx)` and lighting push constants, passes it through `lighting_out`/`lighting_in`, and fragment code only applies that lighting to the sampled atlas texel with opaque alpha. Scene depth remains guarded separately as reverse-Z `GREATER_OR_EQUAL`.

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

Use report-only repeats for intentionally heavy cases that may fail capture without hiding the rest of the batch:

```sh
RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE=1 \
RUMPELMC_GODOT_RUST_EXT_PROFILE=release \
RUMPELMC_FILL_STRESS_REPEATS="1 4 8" \
RUMPELMC_FILL_STRESS_REPORT_ONLY_REPEATS="16" \
./scripts/gpu_terrain_fill_stress.sh logs/gpu_terrain_profile_fill_heavy
```

Use workload matrix to compare movement and resident-load cases:

```sh
RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE=1 \
RUMPELMC_GODOT_RUST_EXT_PROFILE=release \
./scripts/gpu_terrain_workload_matrix.sh logs/gpu_terrain_profile_matrix
```

Use the compact proxy benchmark for focused shadow-proxy measurements. It writes `compact-proxy-benchmark-summary.txt` and, in capture mode, requires a free local `25565` server port:

```sh
RUMPELMC_COMPACT_PROXY_BENCH_CAPTURE=1 \
RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE=1 \
RUMPELMC_GODOT_RUST_EXT_PROFILE=release \
sh scripts/gpu_terrain_compact_proxy_benchmark.sh logs/gpu_shadow_proxy_focused_capture
```

Use an explicit shadow radius when preparing profiler control captures. `0` is reserved for the built-in shadow-disabled control case, so shadow-casting radius overrides must be positive integers. If a local server is intentionally already running, `RUMPELMC_COMPACT_PROXY_BENCH_REUSE_SERVER=1` reuses it and leaves it running after capture:

```sh
RUMPELMC_COMPACT_PROXY_BENCH_CAPTURE=1 \
RUMPELMC_COMPACT_PROXY_BENCH_REUSE_SERVER=1 \
RUMPELMC_COMPACT_PROXY_BENCH_SHADOW_RADIUS=1 \
RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE=1 \
RUMPELMC_GODOT_RUST_EXT_PROFILE=release \
sh scripts/gpu_terrain_compact_proxy_benchmark.sh logs/gpu_shadow_proxy_radius1_capture
```

Use the shadow-radius matrix wrapper to run or re-report several compact-proxy profiler controls into one `shadow-radius-matrix-summary.txt` plus a line-oriented `shadow-radius-profiler-manifest.txt` for external Xcode/Metal capture planning. The `scene` entry keeps the scene-derived shadow radius, positive integers set explicit shadow-casting radius overrides, and `0` stays reserved for the compact proxy benchmark's shadow-disabled control. The wrapper also emits `shadow_normal_total_savings_evidence`; only `usable` rows may be cited as normal-total savings evidence, while `rejected` rows must fall back to per-marker compact counters and external profiler data.

```sh
RUMPELMC_SHADOW_RADIUS_MATRIX_CAPTURE=1 \
RUMPELMC_SHADOW_RADIUS_MATRIX_RADII="scene 1" \
RUMPELMC_COMPACT_PROXY_BENCH_REUSE_SERVER=1 \
RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE=1 \
RUMPELMC_GODOT_RUST_EXT_PROFILE=release \
sh scripts/gpu_terrain_shadow_radius_matrix.sh logs/gpu_shadow_radius_matrix
```

After a capture, re-run the same matrix with `RUMPELMC_SHADOW_RADIUS_MATRIX_CAPTURE=0` to validate the existing case directories and regenerate the top-level summary and profiler manifest without taking new screenshots.

Use the profiler plan guard before external capture handoff. It validates the manifest rows and referenced artifacts, sorts rows by priority, and writes `external_profile_status=pending` until a real Metal/Xcode profiler artifact is recorded. Rows with `normal_total_decision=do_not_cite` must not be used as normal-total savings evidence:

```sh
sh scripts/gpu_terrain_shadow_profiler_plan.sh \
  logs/gpu_shadow_radius_matrix_wide/shadow-radius-profiler-manifest.txt \
  logs/gpu_shadow_radius_matrix_wide/shadow-radius-profiler-plan.txt
```

Generate a fillable results template from the pending plan before recording external profiler data. The template rows are commented and contain `TODO` fields, so they are not accepted as evidence until the leading `# ` is removed and real `profiler_tool`, `profiler_artifact`, and positive `gpu_shadow_pass_ms` values are recorded:

```sh
sh scripts/gpu_terrain_shadow_profiler_results_template.sh \
  logs/gpu_shadow_radius_matrix_wide/shadow-radius-profiler-plan.txt \
  logs/gpu_shadow_radius_matrix_wide/shadow-radius-profiler-results-template.txt
```

Record external profiler rows separately from the pending plan. Each result row must start with `external_profile_status=captured` and include `priority`, `radius`, `artifact`, `profiler_tool`, `profiler_artifact`, and a positive `gpu_shadow_pass_ms`. Validate results against the plan before citing them; by default all planned rows must be captured, while partial handoff validation requires an explicit `RUMPELMC_SHADOW_PROFILER_RESULTS_ALLOW_PARTIAL=1`:

```sh
sh scripts/gpu_terrain_shadow_profiler_results_check.sh \
  logs/gpu_shadow_radius_matrix_wide/shadow-radius-profiler-plan.txt \
  logs/gpu_shadow_radius_matrix_wide/shadow-radius-profiler-results.txt \
  logs/gpu_shadow_radius_matrix_wide/shadow-radius-profiler-results-summary.txt
```

`scripts/gpu_terrain_report.sh` surfaces the latest `shadow-radius-profiler-results-summary.txt` under the log directory when one exists. This report section is only as trustworthy as the validated external result rows it displays.

## Shadow Path Design

The current production GPU terrain shadow path is still Godot CPU shadow proxies. `docs/GPU_SHADOW_PATH.md` records the Phase 12 design for a future GPU-native terrain shadow path. Treat `scene_shadows_disabled` and `diagnostic_no_shadow_proxy` as diagnostic controls only; they cannot justify production shadow reductions. A future native path must be behind an explicit rollback flag, report its own `shadow_path`, preserve the existing Godot proxy fallback, and pass visual parity plus an external profiler comparison before becoming default.

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
