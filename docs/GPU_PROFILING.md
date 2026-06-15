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
- `scripts/gpu_terrain_parity_smoke.sh` writes `parity-summary.txt` after a passing full or validate-only parity run. Use it as the compact evidence for atlas/depth, lighting/shadow, low-angle lighting, compact-shadow including low-angle compact-vs-full shadow proxy, and texture-stand visual deltas before deciding whether another shader change needs fresh captures.
- The render shader lighting contract is guarded in Rust tests: vertex code computes lighting from `face_normal(face_idx)` and lighting push constants, passes it through `lighting_out`/`lighting_in`, and fragment code only applies that lighting to the sampled atlas texel with opaque alpha. Scene depth remains guarded separately as reverse-Z `GREATER_OR_EQUAL`.
- Runtime markers expose the sanitized lighting push block as `gpu_light_dir`, `gpu_light_color`, `gpu_light_energy`, and `gpu_light_ambient`. Use these fields to prove which scene light values were rendered before comparing lighting variants or shadow paths.
- `RUMPELMC_VISUAL_SMOKE_POSE=lighting_low_angle` is a smoke-only controlled lighting variant. It keeps the existing visual smoke path and Godot shadow proxy but changes the `SunLight` rotation/energy for comparison captures, and the marker records `lighting_variant="low_angle"`.
- Native-shadow fallback markers expose `native_shadow_requested`, `native_shadow_active`, `native_shadow_fallback`, `native_shadow_implemented`, `native_shadow_resource_*`, and native-shadow coverage counters. Movement-stress summaries also surface these existing marker values in a compact `movement_native_shadow` row. While `native_shadow_implemented=0`, env-on captures must remain on `shadow_path=godot_proxy` with `requested=1`, `active=0`, `fallback=1`, `native_shadow_resource_status=disabled`, and zero native-shadow resource lifecycle plus coverage counters.

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

Use the low-angle lighting pose when comparing directional-light behavior without changing the default scene:

```sh
RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE=1 \
RUMPELMC_GODOT_RUST_EXT_PROFILE=release \
RUMPELMC_VISUAL_SMOKE_POSE=lighting_low_angle \
./scripts/gpu_terrain_movement_stress.sh logs/gpu_lighting_low_angle_smoke
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

Use the allocator stress gate after a movement/workload/fill artifact has been captured. It refreshes the scoped GPU report and fails on upload failures, capacity/fragmentation failure causes, missing free-range telemetry, or allocator fragmentation above the configured threshold:

```sh
./scripts/gpu_terrain_allocator_stress_gate.sh logs/week2_gpu_allocator_telemetry_20260614
```

Use the upload-pressure wrapper when a task needs fill stress and allocator validation in one artifact:

```sh
RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE=1 RUMPELMC_GODOT_RUST_EXT_PROFILE=release ./scripts/gpu_terrain_upload_pressure.sh logs/gpu_terrain_upload_pressure
```

The wrapper writes `gpu-upload-pressure-summary.txt`; see `docs/GPU_UPLOAD_PRESSURE.md`.

Use the resource lifecycle audit after upload-pressure, renderer resource ownership, atlas/uniform, native-shadow, repack upload, or shutdown cleanup work. It refreshes a scoped GPU report and fails on dirty error scans, upload failures, unexpected scene-target replacement, missing default terrain resources, or native-shadow resource error counters:

```sh
sh scripts/gpu_resource_lifecycle_audit.sh logs/gpu_terrain_upload_pressure_smoke
```

The gate writes `gpu-resource-lifecycle-audit-summary.txt`; see `docs/RENDERINGDEVICE_RESOURCE_LIFECYCLE_AUDIT.md`.

Use the memory budget gate when a task needs explicit resident-memory, draw-command, face, subchunk, and fragmentation limits from existing artifacts:

```sh
sh scripts/gpu_terrain_memory_budget.sh logs/gpu_terrain_memory_budget_current
```

The gate writes `gpu-terrain-memory-budget-summary.txt`; see `docs/GPU_TERRAIN_MEMORY_BUDGETING.md`.

Use the V2 report wrapper when a task needs report consumers to distinguish one scoped summary, fail gates, historical aggregate maxima, and warning-only local signals:

```sh
sh scripts/gpu_terrain_report_v2.sh logs/gpu_terrain_upload_pressure_smoke logs/gpu_terrain_report_v2_current
```

The wrapper writes `gpu-terrain-report-v2-summary.txt` and `gpu-terrain-report-v2.txt`; see `docs/GPU_REPORT_SYSTEM_V2.md`.

Use performance baseline governance after V2 reports when a task needs accepted baseline comparison, threshold policy, and a controlled update flow:

```sh
sh scripts/performance_baseline_governance.sh
```

The check writes `performance-baseline-governance-summary.txt`; see `docs/PERFORMANCE_BASELINE_GOVERNANCE.md`.

Use native-shadow prototype preflight before any task tries to move from marker/descriptor scaffolding to a real RenderingDevice shadow pass. It requires clean env-on Godot-proxy fallback markers, clean resource lifecycle, and a passing performance baseline. While `GPU_TERRAIN_NATIVE_SHADOW_IMPLEMENTED=false`, the expected result is deferred:

```sh
sh scripts/gpu_native_shadow_prototype_preflight.sh logs/gpu_native_shadow_prototype_preflight_current
```

The gate writes `gpu-native-shadow-prototype-preflight-summary.txt`; see `docs/NATIVE_SHADOW_PROTOTYPE_PREFLIGHT.md`.

Use shadow quality parity after native-shadow preflight when a task needs one current summary for Godot proxy, native-shadow fallback parity, shadow-radius proxy counters, pending external profiler state, and report-only FPS fields:

```sh
sh scripts/shadow_quality_parity_program.sh logs/shadow_quality_parity_program_current
```

The gate writes `shadow-quality-parity-summary.txt`; see `docs/SHADOW_QUALITY_PARITY_PROGRAM.md`.

Use shadow proxy retirement planning before removing or reducing CPU shadow-only mesh proxies. The current expected status is deferred until active native-shadow rendering and external profiler evidence exist:

```sh
sh scripts/shadow_proxy_retirement_plan.sh logs/shadow_proxy_retirement_plan_current
```

The gate writes `shadow-proxy-retirement-summary.txt`; see `docs/SHADOW_PROXY_RETIREMENT_PLAN.md`.

Use the lighting stability matrix before changing directional light extraction, lighting push constants, shadow lighting poses, or default lighting behavior:

```sh
sh scripts/lighting_stability_matrix.sh logs/lighting_stability_matrix_current
```

The gate writes `lighting-stability-matrix-summary.txt`; see `docs/LIGHTING_STABILITY_MATRIX.md`.

GPU terrain buffer repack work is documented in `docs/GPU_BUFFER_REPACK.md`. Repack is default-off behind `RUMPELMC_GPU_TERRAIN_BUFFER_REPACK=1`; unset or `0` must keep the current allocator path, and the allocator stress gate remains required before and after any prototype run. The current prototype is marker-only: env-on records `gpu_repack_requested=1`, keeps `gpu_repack_active=0`, and reports `gpu_repack_failure_reason=marker_only` while previewing the deterministic compaction plan. Env-on also stores CPU-owned resident packed-face source bytes and reports `gpu_repack_source_subchunks`, `gpu_repack_source_bytes`, and `gpu_repack_source_missing`; any missing resident source should keep real buffer replacement disabled. Replacement upload, binding, draw-remap, staged-guard, commit-proof, apply-scaffold, and final-swap-guard preview reports `gpu_repack_payload_ready`, `gpu_repack_payload_bytes`, `gpu_repack_upload_ready`, `gpu_repack_upload_bytes`, `gpu_repack_upload_ms`, `gpu_repack_bind_ready`, `gpu_repack_bind_ms`, `gpu_repack_draw_ready`, `gpu_repack_draw_bytes`, `gpu_repack_stage_ready`, `gpu_repack_stage_slots`, `gpu_repack_stage_bytes`, `gpu_repack_commit_ready`, `gpu_repack_commit_steps`, `gpu_repack_commit_tail_free`, `gpu_repack_apply_ready`, `gpu_repack_apply_steps`, `gpu_repack_apply_slots`, `gpu_repack_final_swap_ready`, `gpu_repack_final_swap_blocked`, and `gpu_repack_final_swap_slots`; with `RUMPELMC_GPU_TERRAIN_BUFFER_REPACK_UPLOAD_PREVIEW=1`, it takes one sample upload to a temporary replacement storage buffer, validates a temporary uniform set against the existing shader/atlas resources, builds replacement indirect draw command bytes and a deterministic replacement slot map for compacted slot offsets, validates the disabled commit ordering and allocator tail rebuild, proves the disabled apply bookkeeping from the same staged data, records that final swap remains blocked, and immediately frees temporary GPU resources without swapping active render bindings or slot state.

Use workload matrix to compare movement and resident-load cases:

```sh
RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE=1 \
RUMPELMC_GODOT_RUST_EXT_PROFILE=release \
./scripts/gpu_terrain_workload_matrix.sh logs/gpu_terrain_profile_matrix
```

Use the load-scaling gate when a task needs a high resident set rather than the standard workload:

```sh
RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE=1 RUMPELMC_GODOT_RUST_EXT_PROFILE=release ./scripts/gpu_terrain_load_scaling.sh logs/gpu_terrain_load_scaling
```

The gate requires thousands of subchunks/draws/faces and nontrivial draw-command occupancy; see `docs/GPU_TERRAIN_LOAD_SCALING.md`.

Use the resident-set matrix wrapper when planning needs a compact trend summary over resident-set growth artifacts without rerunning heavy captures:

```sh
sh scripts/world_streaming_resident_set_matrix.sh logs/world_streaming_resident_set_matrix_current
```

Set `RUMPELMC_RESIDENT_SET_MATRIX_RUN=1` only when fresh heavy captures are intended.

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

For external handoff, generate the plan, template, and capture checklist together. The capture pack still records `capture_pack_status=pending_external_profiler`; it is not profiler evidence:

```sh
sh scripts/gpu_terrain_shadow_profiler_capture_pack.sh \
  logs/gpu_shadow_radius_matrix_wide/shadow-radius-profiler-manifest.txt \
  logs/gpu_shadow_radius_matrix_wide/shadow-radius-profiler-capture-pack.txt
```

For local macOS/Xcode Metal attempts, use the sanitized attach helper instead of an all-processes trace. It launches Godot with a minimal environment, attaches `Metal System Trace` to the Godot process, exports command-buffer and encoder tables, and writes a capture summary:

```sh
RUMPELMC_SHADOW_XCTRACE_RECORD_SEC=10 \
RUMPELMC_SHADOW_XCTRACE_SMOKE_DELAY_SEC=25 \
sh scripts/gpu_terrain_shadow_xctrace_attach_capture.sh logs/gpu_shadow_xctrace_attach_current
```

The generated trace and exported Metal tables are review artifacts, not accepted profiler result rows. Only set `RUMPELMC_SHADOW_XCTRACE_GPU_SHADOW_PASS_MS=<positive_decimal>` after manual profiler review identifies the matching shadow-pass GPU time; the helper then writes a candidate row that still must be copied into `shadow-radius-profiler-results.txt` and validated with the results checker.

The helper validates the current GPU terrain compositor profiler markers from the runtime smoke marker before it reports pass: `gpu_profiler_breadcrumb=1381256515`, `gpu_profiler_shader=rumpel_gpu_terrain_render_shader`, and `gpu_profiler_pipeline=rumpel_gpu_terrain_compositor_pipeline`. These identify the terrain compositor runtime path, not the Godot shadow-proxy pass time.

When reviewing `xctrace` CLI exports, generic rows such as command-buffer render/blit commands, drawable present events, completion handlers, or shader-list entries are insufficient for `gpu_shadow_pass_ms` unless they can be tied to the exact shadow pass by a stable profiler label or manual Xcode/Instruments inspection. Current CLI XML exports did not surface the new terrain compositor markers, so treat exported XML tables as navigation aids only.

Record external profiler rows separately from the pending plan. Each result row must start with `external_profile_status=captured` and include `priority`, `radius`, `artifact`, `profiler_tool`, `profiler_artifact`, and a positive `gpu_shadow_pass_ms`. Validate results against the plan before citing them; by default all planned rows must be captured, while partial handoff validation requires an explicit `RUMPELMC_SHADOW_PROFILER_RESULTS_ALLOW_PARTIAL=1`:

```sh
sh scripts/gpu_terrain_shadow_profiler_results_check.sh \
  logs/gpu_shadow_radius_matrix_wide/shadow-radius-profiler-plan.txt \
  logs/gpu_shadow_radius_matrix_wide/shadow-radius-profiler-results.txt \
  logs/gpu_shadow_radius_matrix_wide/shadow-radius-profiler-results-summary.txt
```

`scripts/gpu_terrain_report.sh` surfaces the latest `shadow-radius-profiler-results-summary.txt` under the log directory when one exists, and also surfaces the latest `shadow-radius-profiler-capture-pack.txt` as pending external-profiler handoff state. Only the validated results summary is profiler evidence; the capture pack remains a checklist until real captured rows are recorded and checked.

## Shadow Path Design

The current production GPU terrain shadow path is still Godot CPU shadow proxies. `docs/GPU_SHADOW_PATH.md` records the Phase 12 design for a future GPU-native terrain shadow path. Treat `scene_shadows_disabled` and `diagnostic_no_shadow_proxy` as diagnostic controls only; they cannot justify production shadow reductions. A future native path must be behind an explicit rollback flag, flip `native_shadow_implemented` only with a real implementation, report its own `shadow_path`, preserve the existing Godot proxy fallback, and pass visual parity plus an external profiler comparison before becoming default. For marker/lifecycle-only changes that do not alter shader, visual path, scene setup, or parity case definitions, prefer targeted Rust tests plus env-on movement smoke, validate-only over a fresh compatible parity artifact, aggregate report, `./scripts/check.sh fast`, and `./scripts/diff_guard.sh`; reserve full parity recaptures for visual-path, shader, or parity-validator changes.

## Transparent Path Design

The current production GPU terrain path is opaque-only. `docs/GPU_TRANSPARENT_PATH.md` records the Phase 12 design for a future transparent terrain path. A future transparent path must keep the current opaque pass as the default rollback, separate render opacity from collision solidity, report requested/active/fallback transparent markers, and pass visual/depth/collision parity plus external profiler evidence before becoming default.

Use transparent active path preflight before adding a real transparent face buffer, shader alpha path, sort policy, or active fixture workload:

```sh
sh scripts/transparent_active_path_preflight.sh logs/transparent_active_path_preflight_current
```

The gate writes `transparent-active-path-preflight-summary.txt`; see `docs/TRANSPARENT_ACTIVE_PATH_PREFLIGHT.md`.

Use transparent sorting/depth program before enabling a transparent pass or accepting nonzero transparent workload markers:

```sh
sh scripts/transparent_sorting_depth_program.sh logs/transparent_sorting_depth_program_current
```

The gate writes `transparent-sorting-depth-summary.txt`; see `docs/TRANSPARENT_SORTING_DEPTH_PROGRAM.md`.

Use transparent fixture acceptance suite to consolidate the fixture pack, runtime scene smoke, active-path preflight, sorting/depth program, default-off guard, and report guard:

```sh
sh scripts/transparent_fixture_acceptance_suite.sh logs/transparent_fixture_acceptance_suite_current
```

The gate writes `transparent-fixture-acceptance-suite-summary.txt`; see `docs/TRANSPARENT_FIXTURE_ACCEPTANCE_SUITE.md`.

Use the external profiling campaign gate before citing cross-platform GPU profiler state:

```sh
sh scripts/external_profiling_campaign_gate.sh logs/external_profiling_campaign_current
```

The gate writes `external-profiling-campaign-summary.txt`; see `docs/EXTERNAL_PROFILING_CAMPAIGN.md`. The current expected result is `pass` with `external_profile_status=pending_external_profiler` until real Xcode/Metal, Windows, or Linux/Vulkan profiler artifacts are captured and validated.

Use the texture atlas evolution gate before changing atlas metadata, atlas assets, or shader atlas layout:

```sh
sh scripts/texture_atlas_evolution_gate.sh logs/texture_atlas_evolution_current
```

The gate writes `texture-atlas-evolution-summary.txt`; see `docs/TEXTURE_ATLAS_EVOLUTION_TRACK.md`. The current expected result is `pass` with no atlas asset diff, no shader layout change, `64px` tiles, a `10x1` atlas, and packed tile capacity `2048`.

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
