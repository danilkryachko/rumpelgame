# Agent Handoff State

This file is the current continuation state for Codex threads. Update it after non-trivial work, before delegating to another chat, or before stopping in the middle of a task.

## Latest Snapshot

Date: 2026-06-11

Fresh 2026-06-11 status:

- Long-running GPU backlog is now local/sequential, not delegated to worker chats. `docs/GPU_ROADMAP.md` defines 120 small GPU iterations across stabilization, stress gates, workload scaling, memory/residency, upload, dirty updates, draw submission, bindings, shader hot path, and larger GPU directions. `docs/GPU_PROFILING.md` defines trusted local metrics and macOS/Windows profiler workflows.
- Completed checkpoints: `2635006` enables GPU terrain back-face culling; `c5dad7f` adds the GPU roadmap/profiling docs. Next sequential step is to add the unified report script from the roadmap measurement phase, then continue with visual/stress gates.

- Current weak-spot slice enables GPU terrain back-face culling by default in `client/rust_ext/src/gpu_terrain.rs`. The rasterization state now uses `PolygonCullMode::BACK` with `PolygonFrontFace::CLOCKWISE`; `RUMPELMC_GPU_TERRAIN_CULL_MODE=disabled|none|off` is a rollback control and `front` is available for diagnostics. This reduces hidden/back-face GPU raster work without reducing draw distance, lighting, shadows, texture quality, or visible quality.
- Fresh correctness artifact: `logs/gpu_terrain_cull_back_smoke/movement-stress-summary.txt` passed radius-16 extended movement with `gpu_upload_fail=0`, `gpu_draws=1582`, `gpu_effective_draws=1582`, `gpu_faces=2244`, `terrain_queue_max_ms=3.152`, `gpu_compositor_submit_max_ms=0.210`, and `smoke_err=0`.
- Fresh fill-stress artifacts: `logs/gpu_terrain_fill_stress_cull_back/fill-stress-summary.txt` and control `logs/gpu_terrain_fill_stress_cull_disabled_control/fill-stress-summary.txt`. In the current macOS session both cull-back and cull-disabled repeat=4 runs report `fps_p05=60.0`, so this run is display/driver-limited and is not a clean fps comparison against the earlier repeat=4 `fps_p05=144.0` result. Error scans were clean and `gpu_upload_fail=0`.
- Next useful weak-spot step: keep culling as a safe default if checks pass, then add a platform-specific GPU profiling path or a stronger synthetic stress/report gate that avoids the current 60 Hz visual limiter. Do not reduce visible quality to chase the 150 FPS target.

- Latest synthetic fill-stress slice adds `RUMPELMC_GPU_TERRAIN_COMPOSITOR_DRAW_REPEAT` (default `1`, clamp `64`) to repeat the same GPU terrain indirect draw inside the compositor pass. This is opt-in and keeps visible terrain quality unchanged while increasing GPU draw/fill pressure. Perf text now reports `gpu_effective_draws` and `gpu_draw_repeat`; movement stress summaries include the same fields. `scripts/gpu_terrain_fill_stress.sh` runs radius-16 extended movement with configurable repeat values.
- Fresh fill-stress artifacts: `logs/gpu_terrain_fill_stress_probe/fill-stress-summary.txt` and `logs/gpu_terrain_fill_stress_repeat8/fill-stress-summary.txt`. At radius-16/extended, `1x` produced `1582` effective draws and `fps_p05=144.0`; `4x` produced `6328` effective draws and still `fps_p05=144.0`; `8x` produced `12656` effective draws and dropped back to `fps_p05=60.0`. CPU-side submit stayed low (`gpu_compositor_submit_max_ms <= 0.148`) and `gpu_upload_fail=0`.
- A manual `16x` run in `logs/gpu_terrain_fill_stress_high/repeat-16.run.log` reached `Visual smoke motion complete` but did not save a screenshot before Godot exited, so treat `16x` as above the current automated smoke window rather than a clean pass. The fill-stress script was fixed so future movement-stress failures are not hidden by `tee`.
- Current conclusion: synthetic compositor overdraw gives a useful GPU/fill pressure knob. The visible automated marker can distinguish `4x` from `8x`, but CPU submit/terrain queue metrics still do not expose GPU cost; next useful step is a report-mode fill-stress gate around `4x/8x` or a platform GPU profiler path for macOS/Windows.

- Latest stress-profiling run pushed the opt-in heavy workload beyond the initial radius-12 slice without code changes. Fresh artifacts: `logs/gpu_terrain_workload_heavy_radius14/workload-matrix-summary.txt` and `logs/gpu_terrain_workload_heavy_radius16/workload-matrix-summary.txt`.
- Radius-14 heavy passed cleanly with peak resident load `1222` GPU draws / `1816` faces, `gpu_upload_fail=0`, worst `terrain_queue_max_ms=2.414`, worst `gpu_compositor_submit_max_ms=0.157`, and worst `process_wall_p95_ms=0.062`.
- Radius-16 heavy passed cleanly with peak resident load `1588` GPU draws / `2246` faces, `gpu_upload_fail=0`, worst `terrain_queue_max_ms=2.421`, worst `gpu_compositor_submit_max_ms=0.221`, and worst `process_wall_p95_ms=0.056`. Error scans were clean and the local server was stopped after each run.
- Current conclusion: within the existing opt-in stress clamp, terrain queue work and GPU compositor submit are not the limiting factor for the 150 FPS target. Local visual FPS is still display/driver-paced around 60 Hz on macOS, and Godot GPU timestamp values still report `0.0us`, so the next useful step is either a platform GPU profiler path or a heavier synthetic draw/fill-rate stress that does not reduce visible quality.

- Latest heavy-radius workload slice adds opt-in stress radius controls without changing default gameplay radius: server `RUMPELMC_SERVER_VIEW_DISTANCE` defaults to `10` and clamps to `16`; client `RUMPELMC_CLIENT_KEEP_CHUNK_DISTANCE` defaults to `10` and clamps to `16`. `scripts/gpu_terrain_workload_matrix.sh` keeps `RUMPELMC_WORKLOAD_MATRIX_CASE_SET=standard` by default, while `case_set=heavy` defaults both stress radii to `12`.
- The same slice adds visual-smoke motion `chunk_walk_extended` ending at chunk `11,8`, plus heavy matrix cases `extended` and `extended-filled`. This raises test pressure without reducing draw distance, lighting, shadows, texture quality, or visible quality; it only asks the server/client to hold more chunks during opt-in stress runs.
- Fresh radius-12 artifact: `logs/gpu_terrain_workload_heavy_radius12/workload-matrix-summary.txt` from `RUMPELMC_WORKLOAD_MATRIX_CASE_SET=heavy`, `RUMPELMC_WORKLOAD_MATRIX_SMOKE_DELAY_SEC=20.0`, `GODOT_QUIT_AFTER_FRAMES=36000`, `GODOT_TIMEOUT_SEC=420`. It raised resident load from the previous `~628` draws / `~1090` faces to `876` draws / `1402` faces. Worst CPU-side metrics still pass the 150 FPS budget (`6.667ms`): `extended terrain_queue_max_ms=2.405`, `extended gpu_compositor_submit_max_ms=0.213`, `short process_wall_p95_ms=0.067`, and all cases had `gpu_upload_fail=0`. Error scan was clean and the local server was stopped afterward.
- Review note: the local review pass caught an accidental replacement of existing `configuredChunksPerUpdate` tests in `server/pkg/network/server_test.go`; those tests were restored and new view-distance tests were added beside them.
- Next likely optimization step: push the opt-in radius to `14` or `16` only if needed, then optimize the first metric that approaches budget. Current radius-12 results do not justify changing visible quality or rewriting renderer code.

- Latest repeat workload stability slice adds phase logs around visual-smoke capture in `client/main.gd`: capture start, motion completion, post-draw completion, and image-save timing. This diagnosed a repeat-run failure where `RUMPELMC_WORKLOAD_MATRIX_SMOKE_DELAY_SEC=20.0` made Godot reach `--quit-after 8000` immediately after motion completion, before `RenderingServer.frame_post_draw`; use a larger `GODOT_QUIT_AFTER_FRAMES` for delayed/heavy captures.
- `scripts/gpu_terrain_workload_matrix.sh` now passes `RUMPELMC_WORKLOAD_MATRIX_SMOKE_DELAY_SEC` through to movement stress as `SMOKE_DELAY_SEC`. Default remains `5.0`; the fresh heavier repeat used `20.0` plus `GODOT_QUIT_AFTER_FRAMES=20000`.
- Fresh repeat artifact: `logs/gpu_terrain_workload_repeat_2/workload-repeat-summary.txt` from `RUMPELMC_WORKLOAD_MATRIX_REPEAT_COUNT=2`, `RUMPELMC_WORKLOAD_MATRIX_SMOKE_DELAY_SEC=20.0`, `GODOT_QUIT_AFTER_FRAMES=20000`, `GODOT_TIMEOUT_SEC=240`, batch `64`. Repeat summary passed with worst reported values: `long terrain_queue_max_ms=3.791`, `max-resident gpu_compositor_submit_max_ms=0.167`, `long process_wall_p95_ms=0.077`, and `gpu_upload_fail=0` in both per-run matrix summaries. Error scans over repeat logs were clean. The local server process was stopped afterward.
- Next likely optimization step: increase resident/load pressure beyond the current `~628` GPU draws / `~1090` faces before optimizing more code; current repeated batch=64 metrics are still comfortably under the 150 FPS CPU-side budget (`6.667ms`) and the local visual FPS remains display-paced at 60 Hz.

- Latest compositor-submit breakdown slice adds Rust perf fields `gpu_compositor_submit_parts=setup/target/constants/draw` for the last compositor frame and `gpu_compositor_submit_max_parts=setup/target/constants/draw` for the same frame that produced `gpu_compositor_submit_ms` max. Movement stress and workload matrix summaries now print `gpu_compositor_submit_max_parts_ms=setup/target/constants/draw`.
- `scripts/gpu_terrain_workload_matrix.sh` now also supports optional repeat runs via `RUMPELMC_WORKLOAD_MATRIX_REPEAT_COUNT=N`; it writes `workload-repeat-summary.txt` with min/avg/max for `gpu_compositor_submit_max_ms`, `terrain_queue_max_ms`, and `process_wall_p95_ms` per case. Default remains a single run.
- Fresh breakdown artifacts: `logs/gpu_compositor_submit_breakdown/movement-stress-summary.txt` and `logs/gpu_compositor_submit_breakdown_matrix/workload-matrix-summary.txt`. Movement stress passed with `gpu_compositor_submit_max_ms=0.120` and max parts `0.026/0.000/0.028/0.065`; matrix passed with representative max parts like `short 0.023/0.000/0.031/0.089` and `long-filled 0.029/0.000/0.019/0.102`. Error scans were clean.
- Checks for this breakdown slice: `cargo fmt --manifest-path client/rust_ext/Cargo.toml -- --check`, `cargo test --manifest-path client/rust_ext/Cargo.toml` (84/84), `sh -n scripts/gpu_terrain_workload_matrix.sh`, `sh -n scripts/gpu_terrain_movement_stress.sh`, release movement stress capture, release workload matrix capture with shortened max-resident settle, log error scans, `./scripts/check.sh fast`, and `git diff --check` all passed. The local server process started for captures was stopped afterward.
- Next likely step is to rerun a heavier batch=64 workload with `RUMPELMC_WORKLOAD_MATRIX_REPEAT_COUNT=2` or `3` after starting a fresh server, then inspect whether any repeated submit spike is dominated by setup, target, constants, or draw.

- Latest server streaming test-mode slice adds `RUMPELMC_SERVER_CHUNKS_PER_UPDATE` to the Go server. Default behavior stays unchanged at `6` chunks per update; invalid, zero, or negative env values fall back to the default. `scripts/gpu_terrain_workload_matrix.sh` now passes `RUMPELMC_WORKLOAD_MATRIX_SERVER_CHUNKS_PER_UPDATE` (default `64`) through to Godot/server-started runs and prints `server_reused=0/1` per case so reused already-running servers are obvious.
- Fresh batch-aware workload artifact after rebuilding the local server binary and starting a fresh server: `logs/gpu_terrain_workload_matrix_batch_fresh/workload-matrix-summary.txt`. The short case reports `server_reused=0` and server logs confirm `batch=64`; later cases reuse that fresh server. Batch streaming raises short-route load from the prior `~260` draws to `gpu_draws=536`, while max-resident reaches `gpu_draws=628`, `gpu_faces=1090`, `gpu_upload_fail=0`. Gates still pass: max-resident `terrain_queue_max_ms=1.822`, `process_wall_p95_ms=0.042`, `gpu_compositor_submit_max_ms=0.124`. The long case had one compositor submit spike at `5.277ms`, still under the 150 FPS budget (`6.667ms`) and worth watching in future heavier runs.
- Checks for this server streaming slice: `go test ./pkg/network ./pkg/world`, `sh -n scripts/gpu_terrain_workload_matrix.sh`, release workload matrix capture, matrix log error scan, `./scripts/check.sh fast`, and `git diff --check` all passed.
- The local batch=64 server process was stopped after the capture so a hidden test-mode server is not left running. Next likely step: push the resident set higher than ~630 draws/faces ~1090, or repeat batch=64 with a larger view/load path if upload or compositor submit spikes start approaching budget.

- Latest max-resident workload slice extends `scripts/gpu_terrain_workload_matrix.sh` with a `max-resident` case. It reuses `chunk_walk_long` and a configurable `RUMPELMC_WORKLOAD_MATRIX_MAX_RESIDENT_SETTLE_SEC` defaulting to `30.0`, so the current player radius has more time to fill without reducing draw distance, lighting, shadows, texture quality, or visible quality.
- Fresh max-resident artifact: `logs/gpu_terrain_workload_matrix_max/workload-matrix-summary.txt`. The new case raises simultaneous GPU terrain load to `gpu_draws=634`, `gpu_subchunks=634`, `gpu_faces=1064` with `gpu_upload_fail=0`. It still passes refresh-independent gates: `terrain_queue_max_ms=1.961`, `process_wall_p95_ms=0.045`, `gpu_compositor_submit_max_ms=0.131`; local visual `frame_p95_ms` remains `16.667` due 60 Hz pacing and GPU timestamp max remains `0.0us` on macOS/Metal.
- Checks for this max-resident slice: `sh -n scripts/gpu_terrain_workload_matrix.sh`, `git diff --check`, release workload matrix capture, matrix log error scan, and `./scripts/check.sh fast` all passed.
- Next likely step is to push the resident set higher or make the server/client streaming fill radius faster in test mode, then optimize only if `gpu_compositor_submit_max_ms`, `terrain_queue_max_ms`, or upload failures start moving toward budget.

- Latest workload-scaling slice adds `RUMPELMC_VISUAL_SMOKE_MOTION=chunk_walk_long`, parameterizes `scripts/gpu_terrain_movement_stress.sh` with `RUMPELMC_MOVEMENT_STRESS_MOTION` and `RUMPELMC_MOVEMENT_STRESS_EXPECTED_CHUNK`, and adds `scripts/gpu_terrain_workload_matrix.sh` to compare short, long, and long-filled movement captures without reducing draw distance, lighting, shadows, texture quality, or visible quality.
- Fresh workload matrix artifact: `logs/gpu_terrain_workload_matrix/workload-matrix-summary.txt`. The `long` path alone does not increase simultaneous GPU load because far chunks are unloaded around the current player chunk, but `long-filled` gives the server more settle time at the final chunk and raises GPU terrain load from `short gpu_draws=261 gpu_faces=537` to `long-filled gpu_draws=440 gpu_faces=769`. Under that higher load, real terrain queue/process/submit metrics still pass: `terrain_queue_max_ms=1.737`, `process_wall_p95_ms=0.061`, `gpu_compositor_submit_max_ms=0.144`, `gpu_upload_fail=0`. Visual `frame_p95_ms` remains `16.667` due local 60 Hz display/driver pacing, and GPU timestamp max remains `0.0us` on the current macOS/Metal backend.
- Checks for this workload slice: `sh -n scripts/gpu_terrain_workload_matrix.sh`, `sh -n scripts/gpu_terrain_movement_stress.sh`, `git diff --check`, release workload matrix capture, log error scan for matrix artifacts, and `./scripts/check.sh fast` all passed.
- Next likely optimization target is no longer basic compositor submit or terrain queue under 440 draws; use the workload matrix to push to a heavier simultaneous loaded set or add an explicit no-quality-loss stress mode for max resident terrain, then optimize the first metric that grows past budget.

- Latest GPU compositor timestamp probe slice adds report-first Godot `RenderingDevice` timestamp capture around the GPU terrain compositor draw list. Rust perf text now includes `gpu_compositor_gpu_samples`, `gpu_compositor_gpu_ms=last/avg/max`, and `gpu_compositor_gpu_us=last/avg/max`; baseline and movement stress summaries print the same data.
- Timestamp budget enforcement is intentionally opt-in for now: `RUMPELMC_PERF_BASELINE_GPU_TIMESTAMP_BUDGET_MODE=report` and `RUMPELMC_MOVEMENT_STRESS_GPU_TIMESTAMP_BUDGET_MODE=report` are the defaults. On the current macOS/Metal Godot run, timestamp samples are captured but GPU delta is reported as `0.0us`, so this probe must not be treated as a reliable GPU-time gate locally.
- Fresh timestamp artifacts: `logs/gpu_compositor_timestamp_baseline/perf-baseline-summary.txt` and `logs/gpu_compositor_timestamp_us/movement-stress-summary.txt`. Static GPU baseline passes the real terrain queue/process/submit gates with `terrain_queue_max_ms=1.957`, `process_wall_p95_ms=0.043`, `gpu_compositor_submit_max_ms=0.120`, `gpu_compositor_gpu_samples=356`, `gpu_compositor_gpu_max_us=0.0`, and `gpu_upload_fail=0`. Movement stress passes with `terrain_queue_max_ms=1.875`, `process_wall_p95_ms=0.076`, `gpu_compositor_submit_max_ms=0.140`, `gpu_compositor_gpu_samples=673`, `gpu_compositor_gpu_max_us=0.0`, and `gpu_upload_fail=0`. Visual `frame_p95_ms` remains `16.667` due local 60 Hz display/driver pacing.
- Checks for this timestamp slice: `cargo fmt --manifest-path client/rust_ext/Cargo.toml -- --check`, `sh -n scripts/gpu_terrain_perf_baseline.sh && sh -n scripts/gpu_terrain_movement_stress.sh`, `git diff --check`, `cargo test --manifest-path client/rust_ext/Cargo.toml` (84/84), release movement stress capture, release static baseline capture, and `./scripts/check.sh fast` all passed. Error scans for the fresh timestamp movement and baseline logs had no `ObjectDB`, leaked-instance, panic, script-error, failed, or exceeds matches.
- Next optimization should not trust the local timestamp gate as proof of GPU time. Prefer a workload-scaling stress matrix that increases visible GPU terrain load/draws/faces without reducing quality, or a platform GPU profiler path for Windows/macOS, then optimize whichever metric actually moves under load.

- Latest GPU compositor submit gate slice adds `gpu_compositor_submit=count` and `gpu_compositor_submit_ms=last/avg/max` to Rust perf text, perf baseline summaries, and movement stress summaries. The gate measures CPU callback submit/setup time inside the Godot compositor path; it is not a GPU timestamp query.
- Fresh compositor submit artifacts: `logs/gpu_compositor_submit_baseline/perf-baseline-summary.txt` and `logs/gpu_compositor_submit_gate/movement-stress-summary.txt`. Static GPU baseline passes: `gpu_compositor_submit_avg_ms=0.029`, `gpu_compositor_submit_max_ms=0.121`, `terrain_queue_max_ms=2.017`, `process_wall_p95_ms=0.045`, `gpu_upload_fail=0`. Movement stress passes: `gpu_compositor_submit_avg_ms=0.033`, `gpu_compositor_submit_max_ms=0.128`, `terrain_queue_max_ms=2.051`, `process_wall_p95_ms=0.053`, `gpu_upload_fail=0`. Visual `frame_p95_ms` remains `16.667` due local 60 Hz display/driver pacing.

- Latest process-wall gate slice adds refresh-independent `_process` wall-time gates to terrain perf scripts. `scripts/gpu_terrain_perf_baseline.sh` now defaults `RUMPELMC_PERF_BASELINE_PROCESS_WALL_BUDGET_MODE=enforce`; `scripts/gpu_terrain_movement_stress.sh` now defaults `RUMPELMC_MOVEMENT_STRESS_PROCESS_WALL_BUDGET_MODE=enforce` and prints `process_wall_p95_ms` in `movement-stress-summary.txt`.
- Fresh process-wall movement artifact: `logs/terrain_queue_max_parts/movement-stress-summary.txt`. Release GPU movement stress passes both real queue and process-wall gates: `terrain_queue_avg_ms=0.874`, `terrain_queue_max_ms=1.977`, `max_mesh_ms=1.977`, `max_coll_ms=0.000`, `process_wall_p95_ms=0.042`, `budget_status=pass`, `gpu_upload_fail=0`. Visual `frame_p95_ms` remains `16.667` because the current macOS/Metal visual smoke is display/driver paced at 60 Hz.

- Latest real queue breakdown slice adds `terrain_queue_work_max_parts=mesh/collision` to Rust perf text and both terrain perf summaries. This records the mesh and collision portions from the same frame that produced `terrain_queue_work_ms` max, so future optimization targets the real peak instead of the independent `mesh_max + coll_max` pessimistic sum.
- Fresh queue breakdown artifact: `logs/terrain_queue_max_parts/movement-stress-summary.txt`. GPU movement stress passes the 150 FPS real queue budget: `terrain_queue_avg_ms=0.981`, `terrain_queue_max_ms=2.111`, `max_mesh_ms=2.111`, `max_coll_ms=0.000`, `budget_status=pass`, while independent maxima were `mesh_max_ms=4.490` and `coll_max_ms=3.540` in different frames. The fresh marker has `terrain_queue_work_max_parts=2.111/0.000`, `gpu_upload_fail=0`, and no run-log error matches.

- Latest terrain queue budget gate slice makes the real `terrain_queue_work_ms` max enforceable by default in both static and movement terrain perf scripts. `scripts/gpu_terrain_perf_baseline.sh` still keeps visual `frame_p95_ms` in report mode by default because the local automated visual FPS metric is display/driver paced at 60 Hz, but `RUMPELMC_PERF_BASELINE_TERRAIN_QUEUE_BUDGET_MODE=enforce` is now the default for CPU and GPU terrain queue max against the 150 FPS budget. `scripts/gpu_terrain_movement_stress.sh` also defaults to `RUMPELMC_MOVEMENT_STRESS_BUDGET_MODE=enforce`.
- Fresh terrain queue gate artifact: `logs/terrain_queue_budget_gate/movement-stress-summary.txt`. GPU terrain movement stress passes the real queue budget: `terrain_queue_avg_ms=0.945`, `terrain_queue_max_ms=1.921`, `budget_status=pass`, `mesh_max_ms=4.960`, `coll_max_ms=3.890`, `frame_p95_ms=16.667`, `fps_p05=60.0`, `gpu_upload_fail=0`, `current_chunk="3,2"`. Static validate-only baseline against `logs/indexed_cpu_array_mesh` also passes the new queue gate: CPU `terrain_queue_max_ms=2.698`, GPU `terrain_queue_max_ms=1.985`, budget `6.667ms`.

- Latest movement-stress gate slice updates `scripts/gpu_terrain_movement_stress.sh` to normalize relative output dirs to repo-root absolute paths and write `movement-stress-summary.txt` with `terrain_queue_avg_ms`, `terrain_queue_max_ms`, `mesh_*`, `coll_*`, and 150 FPS budget status.
- Fresh movement artifact: `logs/movement_queue_work/movement-stress-summary.txt`. GPU terrain movement stress over `chunk_walk` passes the real queue budget: `terrain_queue_avg_ms=0.934`, `terrain_queue_max_ms=1.936`, `budget_status=pass`, `mesh_max_ms=4.820`, `coll_max_ms=3.840`, `gpu_upload_fail=0`, `current_chunk="3,2"`.
- Checks for this slice: `sh -n scripts/gpu_terrain_movement_stress.sh`, release movement stress capture, `./scripts/check.sh fast`, `git diff --check`, and `./scripts/diff_guard.sh` all passed. `logs/movement_queue_work/run.log` had no `ObjectDB`, leaked-instance, panic, or script-error matches.

- Latest CPU ArrayMesh spike slice changes packed-face CPU fallback meshes to use 4 quad vertices plus 6 indices per unit quad instead of 6 duplicated vertices. UV tiling and triangle order are preserved, and visible quality/draw distance/lighting/shadows are unchanged.
- Fresh release artifact: `logs/indexed_cpu_array_mesh/perf-baseline-summary.txt`. CPU real queue work now passes the 150 FPS budget even at max: `terrain_queue_avg_ms=1.085`, `terrain_queue_max_ms=2.698`, `terrain_queue_budget_status=pass`. The previous CPU ArrayMesh spike was `terrain_queue_max_ms=16.271` with `max_mesh_phase array_mesh_ms=15.89`; after indexing, CPU `max_mesh_phase array_mesh_ms=1.13`, `mesh_max_ms=4.520`, `coll_max_ms=3.520`. GPU remains within real queue budget: `terrain_queue_avg_ms=0.872`, `terrain_queue_max_ms=1.985`.
- Checks for this slice: `cargo fmt --manifest-path client/rust_ext/Cargo.toml -- --check`, `cargo test --manifest-path client/rust_ext/Cargo.toml` (82/82), `sh -n scripts/gpu_terrain_perf_baseline.sh`, release baseline capture, `./scripts/check.sh fast`, `git diff --check`, and `./scripts/diff_guard.sh` all passed. `logs/indexed_cpu_array_mesh/run.log` had no `ObjectDB`, leaked-instance, panic, or script-error matches.

- Latest collision-refresh weak-spot slice makes collision refresh build direct packed collision faces from chunk data when cached faces are missing, instead of falling back to Godot `MeshInstance3D.create_trimesh_collision()`. It also adds `collision_refresh_phase_last=faces/clear/create/count/node_counts` and `collision_refresh_phase_max=...` to Rust perf text, and makes the `mesh` perf triplet reflect full `render_subchunk_mesh` job time including ArrayMesh/collision/node work.
- Fresh release artifact: `logs/collision_refresh_direct_faces/perf-baseline-summary.txt`. CPU collision max dropped from the previous `coll_max_ms=23.460` to `coll_max_ms=3.240`; CPU terrain average remains within 150 FPS budget (`avg_ms=1.840`, `budget_status=pass`). The remaining CPU max is now clearly an ArrayMesh surface creation spike: `terrain_queue_max_ms=16.271`, `mesh_max_ms=16.270`, `max_mesh_phase array_mesh_ms=15.89`. GPU remains within real queue budget: `terrain_queue_avg_ms=0.876`, `terrain_queue_max_ms=2.095`.
- Checks for this slice: `cargo fmt --manifest-path client/rust_ext/Cargo.toml -- --check`, `cargo test --manifest-path client/rust_ext/Cargo.toml` (80/80), `sh -n scripts/gpu_terrain_perf_baseline.sh`, release baseline capture, `./scripts/check.sh fast`, `git diff --check`, and `./scripts/diff_guard.sh` all passed. `logs/collision_refresh_direct_faces/run.log` had no `ObjectDB`, leaked-instance, panic, or script-error matches.

- Latest CPU fallback weak-spot slice adds `terrain_queue_work_ms=last/avg/max` and `terrain_queue_work_frames` to Rust perf text, and `scripts/gpu_terrain_perf_baseline.sh` now reports `terrain_queue_avg_ms`, `terrain_queue_max_ms`, and `terrain_queue_budget_status`. This gives a real per-frame mesh+collision queue max instead of relying only on independent mesh/collision maxima.
- CPU ArrayMesh fallback now uses the existing packed-face ArrayMesh path by default, with `RUMPELMC_CPU_ARRAY_MESH_PACKED_FACES=0` as a control/rollback switch for old compute/readback meshing. No draw distance, lighting, shadows, texture quality, or visible quality settings were reduced.
- Fresh release artifact: `logs/cpu_packed_faces_baseline/perf-baseline-summary.txt`. CPU terrain work improved from the previous queue-work run `avg_ms=9.340`, `mesh_max_ms=19.660`, `terrain_queue_avg_ms=7.594` to `avg_ms=1.290`, `mesh_max_ms=1.570`, `terrain_queue_avg_ms=1.575`. CPU average now passes the 150 FPS budget, but CPU `terrain_queue_max_ms=23.482` still fails due to collision/ArrayMesh spike (`coll_max_ms=23.460`, `max_array_mesh_phase array_mesh_ms=15.91` in the marker). GPU remains comfortably within real queue budget: `terrain_queue_avg_ms=0.899`, `terrain_queue_max_ms=2.388`.
- Checks for this slice: `cargo fmt --manifest-path client/rust_ext/Cargo.toml`, `cargo test --manifest-path client/rust_ext/Cargo.toml` (79/79), `sh -n scripts/gpu_terrain_perf_baseline.sh`, release baseline capture, `./scripts/check.sh fast`, `git diff --check`, and `./scripts/diff_guard.sh` all passed. `logs/cpu_packed_faces_baseline/run.log` had no `ObjectDB`, leaked-instance, panic, or script-error matches.

- Latest terrain spike-smoothing slice runs collision refresh before mesh queue work and skips mesh queue processing in frames where collision actually rebuilt. This keeps near-player collision updates responsive while avoiding stacked mesh+collision terrain work in the same frame.
- `scripts/gpu_terrain_perf_baseline.sh` now normalizes relative output dirs to repo-root absolute paths before launching Godot, matching the pacing matrix behavior and preventing markers from being written under `client/logs/...`.
- The perf baseline summary now reports `max_pessimistic_ms` plus per-component max fields (`mesh_max_ms`, `coll_max_ms`, `draw_rebuild_max_ms`, `draw_patch_max_ms`) instead of a plain ambiguous `max_ms`; the pessimistic max is still a sum of independent component maxima, not a same-frame timing sample.
- Fresh release spike-smoothing artifact: `logs/gpu_terrain_spike_smoothing/perf-baseline-summary.txt`. GPU terrain work: `avg_ms=1.005`, `max_pessimistic_ms=5.561`, `capacity_avg_fps=995.0`, `budget_status=pass`, `max_pessimistic_budget_status=pass` for the 150 FPS budget (`6.667ms`), `mesh_max_ms=1.660`, `coll_max_ms=3.870`. CPU fallback remains over budget: `avg_ms=8.650`, `max_pessimistic_ms=42.400`.
- Checks for the spike-smoothing slice: `cargo fmt --manifest-path client/rust_ext/Cargo.toml -- --check`, `cargo test --manifest-path client/rust_ext/Cargo.toml` (77/77), `sh -n scripts/gpu_terrain_perf_baseline.sh`, release baseline capture, `./scripts/check.sh fast`, `git diff --check`, and `./scripts/diff_guard.sh` all passed. `logs/gpu_terrain_spike_smoothing/run.log` had no `ObjectDB`, leaked-instance, panic, or script-error matches.

- Latest leak-cleanup slice adds explicit visual-smoke shutdown for `GameClient`, detaches the GPU terrain compositor before freeing its RIDs, and makes `ComputeMesher` free its local `RenderingDevice` through `Gd::free()` after releasing compute pipeline/shader RIDs.
- Fresh verbose smoke artifact `logs/gpu_terrain_leak_fix/run.log` no longer reports `ObjectDB instances leaked at exit`; the previous leak was `RenderingDevice` plus two internal `Object` instances from the local compute mesher device lifetime. Release wrapper smoke also passed in `logs/gpu_terrain_leak_fix_release/run.log`.
- Latest weak-spot cleanup adds `scripts/fix_godot_userdata_case.sh`, a safe local maintenance helper for the repeated macOS Godot userdata warning where `project.godot` uses `config/name="rumpelgame"` but the local app userdata directory existed as `RUMPELGAME`.
- The helper renames through a temporary path when both names resolve to the same directory on a case-insensitive filesystem. If both variants are real different directories, it refuses to merge or delete user data automatically.
- `scripts/gpu_terrain_pacing_matrix.sh` now normalizes relative output directories to repo-root absolute paths before launching Godot, so screenshot markers are not accidentally written under `client/`.
- Current pacing investigation slice adds `RUMPELMC_VISUAL_SMOKE_MAX_FPS` and `scripts/gpu_terrain_pacing_matrix.sh`.
- Fresh pacing matrix artifacts: `logs/gpu_terrain_pacing_matrix/gpu-maxfps-30.png.txt`, `gpu-maxfps-0.png.txt`, `gpu-maxfps-150.png.txt`, `gpu-maxfps-240.png.txt`, and `pacing-matrix-summary.txt`.
- Fresh pacing matrix result: `engine_max_fps=30` produces `fps_avg=30.0`, proving the Godot FPS cap works downward. `engine_max_fps=0`, `150`, and `240` all produce `fps_avg=60.0`, `vsync_mode=0`, and `screen_refresh_hz=60.000`, proving the current automated visual FPS metric is capped by display/driver pacing above the 60 Hz screen refresh.
- Godot 4.6.2 command-line help says `--disable-vsync` does not override driver-level V-Sync enforcement. This matches the matrix result and explains why `Engine.max_fps` above refresh is not enough on the current macOS/Metal run.

- Stabilization commit created on `main`: `58ebe46` (`Stabilize GPU terrain perf baseline`). It captured the previous broad GPU terrain/perf slice before starting the next profiler slice.
- Current post-commit dirty slice is intentionally small: `client/main.gd`, `scripts/gpu_terrain_perf_baseline.sh`, and `docs/AGENT_HANDOFF.md`.
- The new slice adds visual-smoke end-to-end profiler marker fields: `process_wall_samples`, `process_wall_avg_ms`, `process_wall_p95_ms`, `process_wall_max_ms`, `post_draw_wait_ms`, `image_read_ms`, `image_save_ms`, and `image_metrics_ms`. The perf baseline summary now prints these fields.
- Fresh release e2e profile artifacts: `logs/gpu_terrain_e2e_profile/cpu-arraymesh-baseline.png.txt` and `logs/gpu_terrain_e2e_profile/gpu-terrain-baseline.png.txt`. Current GPU marker: `fps_avg=60.0`, `process_wall_avg_ms=0.030`, `process_wall_p95_ms=0.044`, `post_draw_wait_ms=31.802`, `screen_refresh_hz=60.000`, `gpu_terrain_work avg_ms=0.976`, `capacity_avg_fps=1024.6`. This points at frame/display pacing rather than GDScript `_process` or terrain update work.

- The committed `58ebe46` slice covered `client/rust_ext/src/gpu_terrain.rs`, `client/rust_ext/src/lib.rs`, `client/shaders/gpu_terrain_render.glsl`, `client/main.gd`, `scripts/gpu_terrain_perf_baseline.sh`, and `scripts/gpu_terrain_movement_stress.sh`.
- The committed GPU terrain slice adds greedy packed-face merging, face extents in the GPU terrain shader, direct/cached collision-face accounting, and collision timing perf records.
- A review pass found and fixed a CPU ArrayMesh fallback cap bug: merged faces can expand into many unit quads for UV parity, so CPU fallback must enforce `MAX_CPU_ARRAY_MESH_VERTICES` against expanded vertices, not packed face count. Guard test added.
- Fresh checks passed: `RUMPELMC_USE_SCCACHE=0 ./scripts/check.sh full`, `RUMPELMC_PARITY_SMOKE_VALIDATE_ONLY=1 ./scripts/gpu_terrain_parity_smoke.sh`, `./scripts/gpu_terrain_compact_proxy_benchmark.sh`, `cargo fmt --manifest-path client/rust_ext/Cargo.toml -- --check`, and `cargo test --manifest-path client/rust_ext/Cargo.toml` with 76/76 tests.
- Fresh release perf baseline passed after building the release Rust GDExtension with `RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE=1`. Artifacts: `logs/gpu_terrain_perf_baseline/cpu-arraymesh-baseline.png.txt` and `logs/gpu_terrain_perf_baseline/gpu-terrain-baseline.png.txt`.
- Fresh release movement stress passed. Artifact: `logs/gpu_terrain_visual_smoke/movement_stress/gpu-terrain-movement-stress.png.txt`.
- Fresh perf numbers: CPU fallback `frame_p95_ms=12.500`, `fps_p05=80.0`; GPU terrain `frame_p95_ms=8.333`, `fps_p05=120.0`; movement stress GPU `frame_p95_ms=8.333`, `fps_p05=120.0`, `current_chunk="3,2"`, `gpu_upload_fail=0`.
- The 150 FPS target is still not proven. The latest GPU release captures are exactly 120 FPS, which may be a renderer/display cap rather than pure workload limit; the next step should verify or bypass that cap before chasing smaller CPU/GPU optimizations.
- FPS cap investigation added visual-smoke runtime fields to marker logs: `engine_max_fps`, `vsync_mode`, and `screen_refresh_hz`. `RUMPELMC_VISUAL_SMOKE_FORCE_UNCAPPED=1` now forces `Engine.max_fps=0` and `DisplayServer.VSYNC_DISABLED` from `client/main.gd`; the perf baseline and movement stress scripts pass that flag through.
- Fresh forced-uncapped release baseline artifacts: `logs/gpu_terrain_fps_cap/cpu-arraymesh-baseline.png.txt` and `logs/gpu_terrain_fps_cap/gpu-terrain-baseline.png.txt`. Both reported `engine_max_fps=0`, `vsync_mode=0`, `screen_refresh_hz=60.000`, and exactly ~60 FPS (`frame_p95_ms=16.667`). This confirms the current visual smoke FPS metric is display/frame-pacing limited on this run, not a reliable proof of terrain renderer capacity above monitor refresh.
- In the forced-uncapped GPU marker the terrain work itself is light: `mesh_avg_ms=0.82`, `mesh_max_ms=1.26`, `coll_avg_ms=0.16`, `gpu_upload_fail=0`, `gpu_subchunks=132`, `gpu_draws=132`, `gpu_faces=338`.
- `scripts/gpu_terrain_perf_baseline.sh` now writes `logs/gpu_terrain_fps_cap/perf-baseline-summary.txt` with refresh-independent `*_terrain_work` lines. Current derived results: CPU terrain work `avg_ms=9.930`, `capacity_avg_fps=100.7`, `budget_status=fail`; GPU terrain work `avg_ms=0.986`, `capacity_avg_fps=1014.2`, `budget_status=pass` for a 150 FPS budget (`6.667ms`). Treat this as a terrain update/work proxy, not a full end-to-end FPS claim.
- Current post-commit profiler slice passes `./scripts/diff_guard.sh`; the previous 1005-line warning was resolved by committing the broad GPU terrain slice as `58ebe46`.

Goal:

- Continue performance optimization toward stable high FPS without reducing draw distance, lighting, shadows, or visible quality.
- Current technical direction is GPU-resident terrain on Godot RenderingDevice, compatible with macOS and Windows.

Done:

- Added GPU terrain upload/render prototype behind `RUMPELMC_GPU_TERRAIN_RENDER=1`.
- Added Godot compositor integration that attaches to the player camera and draws GPU terrain into the scene color target.
- Added GPU terrain texture atlas sampling from `res://assets/textures/blocks/block_texture_atlas.png`.
- Kept the current GPU terrain solid-block pass opaque; atlas alpha is not used for block opacity until transparent block metadata and a dedicated transparency path exist.
- Moved GPU terrain atlas layout from a hard-coded shader column count into Rust-validated atlas metadata pushed to the render shader; the current atlas is validated as 64px tiles, 10 columns, 1 row.
- Made the GPU terrain atlas texture prefer `R8G8B8A8_SRGB` sampling for closer albedo parity with Godot materials, with a guarded fallback to `R8G8B8A8_UNORM` if the backend rejects sRGB sampling.
- Made the opt-in GPU terrain compositor path depth-compatible by requesting resolved depth, binding a color+depth framebuffer, and enabling depth test/write for scene rendering.
- Fixed the GPU compositor depth test for Godot 4.6 reverse-Z by using `GREATER_OR_EQUAL`; `LESS_OR_EQUAL` could produce sky-only screenshots even while GPU draw counters advanced.
- Added a lighting-aware GPU terrain slice: the Rust client reads the scene `SunLight` direction/color/energy, passes it through GPU terrain push constants, and the GPU terrain shader shades block faces from per-face normals with directional diffuse plus ambient.
- Added a conservative shadow-compatibility slice: terrain `MeshInstance3D` shadow casting is explicitly configured as double-sided, so the retained ArrayMesh terrain can serve as the Godot shadow-map proxy while the opt-in GPU RD compositor path handles visible terrain rendering.
- Added an opt-in GPU render bridge where CPU ArrayMesh subchunk nodes switch to Godot `SHADOWS_ONLY` after the GPU compositor is attached and the GPU render pipeline is ready, preserving fallback visibility if GPU render setup fails.
- Added the first safe CPU ArrayMesh reduction step for the opt-in GPU path: after GPU upload, distant subchunks that do not need local collision or a Godot shadow proxy drop their CPU `MeshInstance3D` while keeping the GPU slot intact.
- Added a delayed visible-path transition: CPU fallback/proxy nodes are not hidden or removed until the GPU compositor has produced at least one frame, and a subchunk keeps CPU fallback if its GPU upload did not produce a slot.
- Added a GPU-visible refresh so existing CPU subchunk nodes are re-evaluated once the GPU compositor becomes the confirmed visible terrain path, instead of waiting for later player movement or chunk updates.
- Added a faster CPU shadow/collision proxy path for opt-in GPU terrain: after successful GPU upload and confirmed GPU visible rendering, retained CPU proxy `ArrayMesh` geometry is built directly from `PackedFaceBatch` vertices/normals instead of rerunning the full compute mesher/readback/UV path.
- Added CPU proxy reason counters to the Rust client perf text: `proxy_coll`, `proxy_shadow`, `proxy_both`, and `proxy_shadow_only`. These counters explain why retained CPU `SubchunkMesh_*` nodes still exist in the opt-in GPU terrain path.
- Added opt-in CPU shadow proxy strategy selection through `RUMPELMC_GPU_TERRAIN_SHADOW_PROXY_MODE`. The default remains `conservative`; `collision_only` drops shadow-only CPU proxies while preserving nearby collision proxies. Rust perf text now includes `shadow_mode=...`.
- Made compact shadow-only CPU proxy meshes the default for GPU-visible shadow-only proxies. `RUMPELMC_GPU_TERRAIN_SHADOW_PROXY_MESH=full` remains an explicit opt-out/control mode; collision proxies plus CPU fallback meshes stay on the full ArrayMesh path. Rust perf text includes `shadow_mesh=...` and `compact_shadow_proxy=...`.
- Added compact proxy payload measurement to Rust perf text: `compact_shadow_normals_saved=...`, plus `normals last=... total=...`. The parity gate now requires zero saved normals outside compact mode and positive saved normals in the compact shadow-proxy case.
- Extended the parity gate with a compact `lighting_shadow` pose case. It compares compact shadow-only proxy rendering against the full GPU `lighting_shadow` marker using the same visual metric envelopes before compact can be considered for default use.
- Added `scripts/gpu_terrain_compact_proxy_benchmark.sh` as a report-first benchmark helper for compact shadow-only and collision-only proxy payload/runtime metrics. By default it reads the existing parity artifacts; direct Godot captures are opt-in with `RUMPELMC_COMPACT_PROXY_BENCH_CAPTURE=1` because shell-launched Godot wrappers can still stall in the current Codex PTY environment.
- Kept visible CPU fallback behavior unchanged: CPU-only rendering and failed GPU uploads still use the existing compute mesher with UVs/materials.
- Added visual smoke capture hooks in `client/main.gd` through `RUMPELMC_VISUAL_SMOKE_PATH`, `RUMPELMC_VISUAL_SMOKE_DELAY_SEC`, and `RUMPELMC_VISUAL_SMOKE_HIDE_HUD`.
- Strengthened visual smoke validation with `terrain_samples` and `smoke_err`; sky-only frames now fail even if the image is bright and GPU counters are nonzero.
- Extended visual smoke markers with region, color-bucket, chroma, and terrain-luma-range metrics so parity can catch atlas/color/lighting/depth distribution regressions beyond a basic non-sky frame.
- Added multi-pose visual smoke support through `RUMPELMC_VISUAL_SMOKE_POSE=default|atlas_depth|lighting_shadow`; capture waits for `RenderingServer.frame_post_draw` after applying the pose so the screenshot reflects the fixed camera.
- Added `scripts/gpu_terrain_visual_smoke.sh` as a CPU/GPU smoke wrapper; in the current Codex PTY environment direct Godot commands are the reliable gate because the wrapper can stall before project logs appear.
- Added `scripts/gpu_terrain_parity_smoke.sh` as a CPU/GPU/radius=1 parity gate. It validates marker files for `smoke_err=0`, terrain samples, region coverage, atlas/color diversity, terrain luma range, CPU fallback counters, CPU proxy reason counters, GPU counters, fast proxy usage, radius=1 proxy/collision parity, and conservative CPU/GPU visual envelopes across default, atlas/depth, and lighting/shadow poses.
- Extended the parity gate with a GPU `shadow_radius=0` conservative case that validates `shadow_path=scene_shadows_disabled` and keeps retained CPU proxy work collision-only when scene shadows are disabled.
- Extended the parity gate with a `collision_only` GPU case that verifies shadow proxy counters stay at zero while CPU proxy count still matches collision body count.
- Added `RUMPELMC_VISUAL_SMOKE_DISABLE_PLAYER_INPUT=1` for automated visual smokes so player input does not accidentally break/place blocks and mutate the world during capture.
- Added GPU terrain log/perf visibility, including `gpu_frames`.
- Kept ArrayMesh terrain fallback active.
- Added this handoff system: `docs/HANDOFF.md`, `docs/AGENT_HANDOFF.md`, and `scripts/handoff.sh`.

Relevant files:

- `client/rust_ext/src/gpu_terrain.rs`
- `client/rust_ext/src/lib.rs`
- `client/rust_ext/src/player.rs`
- `client/shaders/gpu_terrain_render.glsl`
- `scripts/gpu_terrain_visual_smoke.sh`
- `scripts/gpu_terrain_parity_smoke.sh`
- `scripts/gpu_terrain_compact_proxy_benchmark.sh`
- `logs/gpu_terrain_visual_smoke/direct-cpu.png`
- `logs/gpu_terrain_visual_smoke/direct-cpu.png.txt`
- `logs/gpu_terrain_visual_smoke/direct-cpu-smoke-gate.png`
- `logs/gpu_terrain_visual_smoke/direct-cpu-smoke-gate.png.txt`
- `logs/gpu_terrain_visual_smoke/direct-gpu.png`
- `logs/gpu_terrain_visual_smoke/direct-gpu.png.txt`
- `logs/gpu_terrain_visual_smoke/direct-gpu-reverse-z.png`
- `logs/gpu_terrain_visual_smoke/direct-gpu-reverse-z.png.txt`
- `logs/gpu_terrain_visual_smoke/direct-gpu-reverse-z-proxy-radius1.png`
- `logs/gpu_terrain_visual_smoke/direct-gpu-reverse-z-proxy-radius1.png.txt`
- `logs/gpu_terrain_visual_smoke/direct-gpu-fast-proxy-final.png`
- `logs/gpu_terrain_visual_smoke/direct-gpu-fast-proxy-final.png.txt`
- `logs/gpu_terrain_visual_smoke/direct-gpu-fast-proxy-radius1-final.png`
- `logs/gpu_terrain_visual_smoke/direct-gpu-fast-proxy-radius1-final.png.txt`
- `logs/gpu_terrain_visual_smoke/direct-cpu-fast-proxy-final.png`
- `logs/gpu_terrain_visual_smoke/direct-cpu-fast-proxy-final.png.txt`
- `logs/gpu_terrain_visual_smoke/parity/cpu-arraymesh-parity.png`
- `logs/gpu_terrain_visual_smoke/parity/cpu-arraymesh-parity.png.txt`
- `logs/gpu_terrain_visual_smoke/parity/gpu-terrain-parity.png`
- `logs/gpu_terrain_visual_smoke/parity/gpu-terrain-parity.png.txt`
- `logs/gpu_terrain_visual_smoke/parity/gpu-terrain-radius1-parity.png`
- `logs/gpu_terrain_visual_smoke/parity/gpu-terrain-radius1-parity.png.txt`
- `logs/gpu_terrain_visual_smoke/parity/gpu-terrain-collision-only-parity.png`
- `logs/gpu_terrain_visual_smoke/parity/gpu-terrain-collision-only-parity.png.txt`
- `logs/gpu_terrain_visual_smoke/parity/gpu-terrain-compact-shadow-parity.png`
- `logs/gpu_terrain_visual_smoke/parity/gpu-terrain-compact-shadow-parity.png.txt`
- `logs/gpu_terrain_visual_smoke/parity/gpu-terrain-compact-lighting-shadow-parity.png`
- `logs/gpu_terrain_visual_smoke/parity/gpu-terrain-compact-lighting-shadow-parity.png.txt`
- `logs/godot-gpu-terrain-smoke.log`
- `logs/godot-gpu-terrain-atlas-smoke.log`
- `logs/godot-gpu-terrain-depth-smoke.log`
- `logs/godot-gpu-terrain-lighting-smoke.log`
- `logs/godot-gpu-terrain-shadow-proxy-smoke.log`
- `logs/godot-gpu-terrain-opaque-smoke.log`
- `logs/godot-gpu-terrain-atlas-layout-smoke.log`
- `logs/godot-gpu-terrain-atlas-layout-shadow-proxy-smoke.log`
- `logs/godot-gpu-terrain-srgb-atlas-shadow-proxy-smoke.log`
- `docs/HANDOFF.md`
- `scripts/handoff.sh`

Checks:

- `RUMPELMC_USE_SCCACHE=0 ./scripts/check.sh full` passed after the shadow-proxy slice.
- `RUMPELMC_USE_SCCACHE=0 ./scripts/check.sh full` passed after the lighting-aware GPU terrain slice.
- `./scripts/check.sh full` passed after the GPU compositor changes.
- `RUMPELMC_USE_SCCACHE=0 ./scripts/check.sh full` passed after atlas/depth work.
- `./scripts/check.sh full` with sccache failed locally with `sccache: error: Operation not permitted (os error 1)`; rerun without sccache passed.
- `cargo fmt -- --check`, `cargo build`, `cargo check`, and `cargo test` passed in `client/rust_ext`; Rust tests: 7/7.
- `cargo build --manifest-path client/rust_ext/Cargo.toml` passed.
- Godot smoke passed with `RUMPELMC_GPU_TERRAIN_RENDER=1`.
- Godot atlas smoke passed with `RUMPELMC_GPU_TERRAIN_RENDER=1`.
- Godot depth smoke passed with `RUMPELMC_GPU_TERRAIN_RENDER=1`.
- Godot lighting smoke passed with `RUMPELMC_GPU_TERRAIN_RENDER=1`.
- Godot shadow-proxy smoke passed with `RUMPELMC_GPU_TERRAIN_RENDER=1`.
- Godot opaque solid-block smoke passed with `RUMPELMC_GPU_TERRAIN_RENDER=1`.
- Godot atlas-layout smoke passed with `RUMPELMC_GPU_TERRAIN_RENDER=1`.
- Godot atlas-layout plus shadow-proxy bridge smoke passed with `RUMPELMC_GPU_TERRAIN_RENDER=1`.
- Godot sRGB atlas plus shadow-proxy bridge smoke passed with `RUMPELMC_GPU_TERRAIN_RENDER=1`; no UNORM fallback warning was observed on the local Metal backend.
- Direct CPU visual smoke passed with `RUMPELMC_GPU_TERRAIN_RENDER=0`, screenshot and marker saved under `logs/gpu_terrain_visual_smoke/`.
- Direct GPU visual smoke passed with `RUMPELMC_GPU_TERRAIN_RENDER=1`, screenshot and marker saved under `logs/gpu_terrain_visual_smoke/`; marker included nonzero `gpu_frames`, `gpu_subchunks`, `gpu_draws`, and `gpu_faces`.
- Direct GPU visual smoke passed after the reverse-Z depth fix: `direct-gpu-reverse-z.png`, `terrain_samples=576`, `smoke_err=0`, `gpu_frames=160`, `gpu_subchunks=88`, `gpu_faces=143452`.
- Direct GPU proxy-reduction smoke passed with `RUMPELMC_GPU_TERRAIN_SHADOW_PROXY_CHUNK_DISTANCE=1`: `direct-gpu-reverse-z-proxy-radius1.png`, `cpu_proxy=10`, `collision=10`, `gpu_subchunks=92`, `terrain_samples=288`, `smoke_err=0`.
- Direct CPU visual smoke passed after the strengthened visual gate: `direct-cpu-smoke-gate.png`, `terrain_samples=288`, `smoke_err=0`, `current_chunk="0,0"`.
- Latest `RUMPELMC_USE_SCCACHE=0 ./scripts/check.sh full` passed after the reverse-Z/fallback-transition/smoke-gate fixes; `golangci-lint` is not installed locally and was skipped by the script.
- Latest Rust fast-proxy checks passed in `client/rust_ext`: `cargo fmt -- --check`, `cargo check`, `cargo test` (10/10), and `cargo build`.
- Latest `RUMPELMC_USE_SCCACHE=0 ./scripts/check.sh full` passed after the fast CPU proxy slice; `golangci-lint` is not installed locally and was skipped by the script.
- Direct GPU fast-proxy smoke passed with `RUMPELMC_GPU_TERRAIN_RENDER=1`: `direct-gpu-fast-proxy-final.png`, `terrain_samples=288`, `smoke_err=0`, `gpu_frames=190`, `gpu_subchunks=90`, `gpu_faces=145506`, `fast_proxy=163`.
- Direct GPU fast-proxy radius smoke passed with `RUMPELMC_GPU_TERRAIN_RENDER=1` and `RUMPELMC_GPU_TERRAIN_SHADOW_PROXY_CHUNK_DISTANCE=1`: `direct-gpu-fast-proxy-radius1-final.png`, `cpu_proxy=10`, `collision=10`, `fast_proxy=20`, `terrain_samples=288`, `smoke_err=0`, `gpu_frames=195`.
- Direct CPU fallback smoke passed with `RUMPELMC_GPU_TERRAIN_RENDER=0`: `direct-cpu-fast-proxy-final.png`, `terrain_samples=288`, `smoke_err=0`, `fast_proxy=0`, `current_chunk="0,0"`.
- Latest parity smoke artifacts passed on the final Rust build with player input disabled:
  - CPU fallback: `parity/cpu-arraymesh-parity.png`, `terrain_samples=256`, `avg_luma=0.3517`, `smoke_err=0`, `fast_proxy=0`, `collision=10`.
  - GPU terrain: `parity/gpu-terrain-parity.png`, `terrain_samples=256`, `avg_luma=0.3442`, `smoke_err=0`, `gpu_frames=68`, `gpu_subchunks=48`, `gpu_faces=80994`, `fast_proxy=62`, `collision=10`.
  - GPU radius=1: `parity/gpu-terrain-radius1-parity.png`, `terrain_samples=256`, `avg_luma=0.3442`, `smoke_err=0`, `gpu_frames=74`, `cpu_proxy=10`, `collision=10`, `fast_proxy=19`.
- `RUMPELMC_PARITY_SMOKE_VALIDATE_ONLY=1 ./scripts/gpu_terrain_parity_smoke.sh` passed against the latest parity artifacts.
- `sh -n scripts/gpu_terrain_parity_smoke.sh` passed.
- `sh -n scripts/gpu_terrain_visual_smoke.sh` passed after adding wrapper checks for `smoke_err=0` and nonzero `terrain_samples`.
- `scripts/gpu_terrain_visual_smoke.sh` passed `sh -n`, but can time out in this Codex PTY environment before Godot project logs appear. Prefer the direct `/opt/homebrew/bin/timeout ... /usr/bin/env ... /opt/homebrew/bin/godot --path client ...` commands for the current gate.
- `sh -n scripts/handoff.sh` passed.
- `./scripts/handoff.sh` ran successfully and printed the continuation snapshot.
- Latest `RUMPELMC_USE_SCCACHE=0 ./scripts/check.sh full` passed after the parity smoke slice; `golangci-lint` is not installed locally and was skipped by the script.
- `./scripts/diff_guard.sh` passed after the dirty-tree cleanup baseline was committed.
- Latest direct parity captures passed after the extended visual metrics slice:
  - CPU fallback: `parity/cpu-arraymesh-parity.png`, `terrain_samples=256`, `terrain_mid_samples=64`, `terrain_bottom_samples=192`, `terrain_left_samples=128`, `terrain_right_samples=128`, `terrain_color_buckets=8`, `terrain_chroma_samples=256`, `terrain_luma_range=0.3655`, `smoke_err=0`, `fast_proxy=0`, `collision=10`.
  - GPU terrain: `parity/gpu-terrain-parity.png`, `terrain_samples=256`, `terrain_color_buckets=8`, `terrain_chroma_samples=256`, `terrain_luma_range=0.3532`, `smoke_err=0`, `gpu_frames=143`, `gpu_subchunks=81`, `gpu_faces=133218`, `fast_proxy=127`, `collision=10`.
  - GPU radius=1: `parity/gpu-terrain-radius1-parity.png`, `terrain_samples=256`, `terrain_color_buckets=8`, `terrain_chroma_samples=256`, `terrain_luma_range=0.3532`, `smoke_err=0`, `gpu_frames=149`, `gpu_subchunks=82`, `gpu_faces=135266`, `cpu_proxy=10`, `collision=10`, `fast_proxy=20`.
- Latest `RUMPELMC_PARITY_SMOKE_VALIDATE_ONLY=1 ./scripts/gpu_terrain_parity_smoke.sh` passed against the extended parity artifacts.
- Latest `RUMPELMC_USE_SCCACHE=0 ./scripts/check.sh full` passed after the extended visual metrics slice; `golangci-lint` is not installed locally and was skipped by the script.
- Latest `./scripts/diff_guard.sh` passed on the small 3-file slice before commit.
- Latest proxy-reason counter slice passed:
  - Rust: `cargo fmt --manifest-path client/rust_ext/Cargo.toml -- --check`, `cargo check --manifest-path client/rust_ext/Cargo.toml`, `cargo test --manifest-path client/rust_ext/Cargo.toml` (11/11), and `cargo build --manifest-path client/rust_ext/Cargo.toml`.
  - Full check: `RUMPELMC_USE_SCCACHE=0 ./scripts/check.sh full` passed; `golangci-lint` is not installed locally and was skipped by the script.
  - Parity captures were refreshed with the new perf counters and `RUMPELMC_PARITY_SMOKE_VALIDATE_ONLY=1 ./scripts/gpu_terrain_parity_smoke.sh` passed.
  - CPU fallback marker: `cpu_proxy=80`, `proxy_coll=10`, `proxy_shadow=0`, `proxy_both=0`, `proxy_shadow_only=0`, `collision=10`.
  - GPU default marker: `cpu_proxy=82`, `proxy_coll=10`, `proxy_shadow=82`, `proxy_both=10`, `proxy_shadow_only=72`, `collision=10`.
  - GPU radius=1 marker: `cpu_proxy=10`, `proxy_coll=10`, `proxy_shadow=10`, `proxy_both=10`, `proxy_shadow_only=0`, `collision=10`.
- Latest multi-pose parity slice passed:
  - Default CPU/GPU/radius captures were refreshed with `pose="default"`.
  - Atlas/depth pose captures passed: CPU `terrain_samples=510`, `terrain_color_buckets=10`, `terrain_luma_range=0.3378`; GPU `terrain_samples=510`, `terrain_color_buckets=9`, `terrain_luma_range=0.3294`.
  - Lighting/shadow pose captures passed: CPU `terrain_samples=457`, `terrain_color_buckets=8`, `terrain_luma_range=0.3654`; GPU `terrain_samples=453`, `terrain_color_buckets=10`, `terrain_luma_range=0.3570`.
  - `RUMPELMC_PARITY_SMOKE_VALIDATE_ONLY=1 ./scripts/gpu_terrain_parity_smoke.sh` passed across all seven marker files.
  - `RUMPELMC_USE_SCCACHE=0 ./scripts/check.sh full` passed; `golangci-lint` is not installed locally and was skipped by the script.
- Latest shadow-proxy mode slice passed:
  - Rust: `cargo fmt --manifest-path client/rust_ext/Cargo.toml -- --check`, `cargo check --manifest-path client/rust_ext/Cargo.toml`, `cargo test --manifest-path client/rust_ext/Cargo.toml` (12/12), and `cargo build --manifest-path client/rust_ext/Cargo.toml`.
  - Full check: `RUMPELMC_USE_SCCACHE=0 ./scripts/check.sh full` passed; `golangci-lint` is not installed locally and was skipped by the script.
  - Fresh direct parity captures were produced with `RUMPELMC_VISUAL_SMOKE_DELAY_SEC=1.5` because the shell wrapper can time out in the current Codex PTY before Godot writes markers.
  - `RUMPELMC_PARITY_SMOKE_VALIDATE_ONLY=1 ./scripts/gpu_terrain_parity_smoke.sh` passed across eight marker files.
  - Collision-only marker: `cpu_proxy=10`, `proxy_coll=10`, `proxy_shadow=0`, `proxy_both=0`, `proxy_shadow_only=0`, `shadow_mode=collision_only`, `collision=10`.
  - Conservative radius=1 marker: `cpu_proxy=9`, `proxy_coll=9`, `proxy_shadow=9`, `proxy_both=9`, `proxy_shadow_only=0`, `shadow_mode=conservative`, `collision=9`.
- Latest compact shadow-proxy mesh slice passed:
  - Rust: `cargo fmt --manifest-path client/rust_ext/Cargo.toml -- --check`, `cargo check --manifest-path client/rust_ext/Cargo.toml`, `cargo test --manifest-path client/rust_ext/Cargo.toml` (15/15), and `cargo build --manifest-path client/rust_ext/Cargo.toml`.
  - `sh -n scripts/gpu_terrain_parity_smoke.sh` passed.
  - Fresh direct parity captures were produced across nine marker files, including the compact shadow-only proxy case.
  - `RUMPELMC_PARITY_SMOKE_VALIDATE_ONLY=1 ./scripts/gpu_terrain_parity_smoke.sh` passed against the latest parity artifacts.
  - Full check: `RUMPELMC_USE_SCCACHE=0 ./scripts/check.sh full` passed; `golangci-lint` is not installed locally and was skipped by the script.
  - Compact marker: `cpu_proxy=19`, `proxy_coll=10`, `proxy_shadow=19`, `proxy_both=10`, `proxy_shadow_only=9`, `shadow_mode=conservative`, `shadow_mesh=compact`, `compact_shadow_proxy=9`, `collision=10`, `gpu_frames=32`.
  - Conservative radius=1 marker after rerun with `RUMPELMC_VISUAL_SMOKE_DELAY_SEC=3.0`: `cpu_proxy=10`, `proxy_coll=10`, `proxy_shadow=10`, `proxy_both=10`, `proxy_shadow_only=0`, `shadow_mesh=full`, `compact_shadow_proxy=0`, `gpu_frames=131`.
- Latest compact proxy measurement slice passed:
  - Rust: `cargo fmt --manifest-path client/rust_ext/Cargo.toml -- --check`, `cargo check --manifest-path client/rust_ext/Cargo.toml`, `cargo test --manifest-path client/rust_ext/Cargo.toml` (16/16), and `cargo build --manifest-path client/rust_ext/Cargo.toml`.
  - `sh -n scripts/gpu_terrain_parity_smoke.sh` passed.
  - Fresh direct parity captures were produced across nine marker files with the new `compact_shadow_normals_saved` and `normals last/total` perf fields.
  - `RUMPELMC_PARITY_SMOKE_VALIDATE_ONLY=1 ./scripts/gpu_terrain_parity_smoke.sh` passed against the latest parity artifacts.
  - Full check: `RUMPELMC_USE_SCCACHE=0 ./scripts/check.sh full` passed; `golangci-lint` is not installed locally and was skipped by the script.
  - Compact marker: `cpu_proxy=70`, `proxy_coll=10`, `proxy_shadow=70`, `proxy_both=10`, `proxy_shadow_only=60`, `shadow_mesh=compact`, `compact_shadow_proxy=98`, `compact_shadow_normals_saved=1327104`, `collision=10`, `gpu_frames=145`.
  - Full/default GPU marker: `shadow_mesh=full`, `compact_shadow_proxy=0`, `compact_shadow_normals_saved=0`, `normals last=18432 total=1575360`.
- Latest compact shadow visual parity slice passed:
  - `sh -n scripts/gpu_terrain_parity_smoke.sh` passed.
  - Direct compact lighting/shadow capture passed: `gpu-terrain-compact-lighting-shadow-parity.png`, `pose="lighting_shadow"`, `terrain_samples=453`, `terrain_color_buckets=11`, `terrain_luma_range=0.3570`, `shadow_mesh=compact`, `compact_shadow_proxy=97`, `compact_shadow_normals_saved=1320960`, `collision=10`, `gpu_frames=141`.
  - `RUMPELMC_PARITY_SMOKE_VALIDATE_ONLY=1 ./scripts/gpu_terrain_parity_smoke.sh` passed against the full parity artifact set, including the compact-vs-full `lighting_shadow` visual metric pair.
  - `./scripts/check.sh fast` passed; Rust tests remained 16/16.
- Latest compact proxy benchmark helper slice passed:
  - `sh -n scripts/gpu_terrain_compact_proxy_benchmark.sh` passed.
  - `./scripts/gpu_terrain_compact_proxy_benchmark.sh` passed in default report mode against current parity artifacts.
  - `./scripts/check.sh fast` passed; Rust tests remained 16/16.
  - Benchmark summary from current artifacts: full `normals_total=1593792`, `mesh_avg_ms=10.18`, `mesh_max_ms=38.49`, `coll_avg_ms=0.73`, `gpu_frames=144`; compact `normals_total=260544`, `compact_shadow_proxy=97`, `compact_shadow_normals_saved=1320960`, `mesh_avg_ms=9.32`, `mesh_max_ms=34.15`, `coll_avg_ms=0.79`, `gpu_frames=141`.
  - Reported `normal_total_delta=1333248` and `normal_total_reduction=83.7%` for the compact `lighting_shadow` marker pair.
- Latest compact-default slice passed:
  - Rust: `cargo fmt --manifest-path client/rust_ext/Cargo.toml -- --check`, `cargo check --manifest-path client/rust_ext/Cargo.toml`, `cargo test --manifest-path client/rust_ext/Cargo.toml` (16/16), and `cargo build --manifest-path client/rust_ext/Cargo.toml`.
  - `sh -n scripts/gpu_terrain_parity_smoke.sh` and `sh -n scripts/gpu_terrain_compact_proxy_benchmark.sh` passed.
  - Direct baseline GPU capture with empty `RUMPELMC_GPU_TERRAIN_SHADOW_PROXY_MESH=` passed: `shadow_mesh=compact`, `compact_shadow_proxy=95`, `compact_shadow_normals_saved=1284096`, `collision=10`, `gpu_frames=138`.
  - `RUMPELMC_PARITY_SMOKE_VALIDATE_ONLY=1 ./scripts/gpu_terrain_parity_smoke.sh` passed against the full parity artifact set; explicit `full` markers remain as control/opt-out cases.
  - Full check: `RUMPELMC_USE_SCCACHE=0 ./scripts/check.sh full` passed; `golangci-lint` is not installed locally and was skipped by the script.
- Latest collision-only render-state slice passed:
  - Collision-only CPU proxies now use `visible=false` and `ShadowCastingSetting::OFF` when a subchunk has a GPU slot but does not need a shadow proxy. CPU fallback meshes stay visible/double-sided if a subchunk is not actually backed by a GPU slot.
  - Rust perf text now reports terrain mesh render-state counters: `mesh_visible`, `mesh_shadow_off`, `mesh_shadow_double`, and `mesh_shadow_only`. The parity gate uses them to catch `collision_only` regressions where retained collision proxies become visible or cast shadows again.
  - Rust: `cargo fmt --manifest-path client/rust_ext/Cargo.toml -- --check`, `cargo check --manifest-path client/rust_ext/Cargo.toml`, `cargo test --manifest-path client/rust_ext/Cargo.toml` (17/17), and `cargo build --manifest-path client/rust_ext/Cargo.toml`.
  - Direct collision-only capture passed after adding render-state counters: `mesh_visible=0`, `mesh_shadow_off=10`, `mesh_shadow_double=0`, `mesh_shadow_only=0`, `proxy_shadow=0`, `proxy_both=0`, `proxy_shadow_only=0`, `collision=10`, `gpu_frames=104`, `terrain_samples=256`.
  - `RUMPELMC_PARITY_SMOKE_VALIDATE_ONLY=1 ./scripts/gpu_terrain_parity_smoke.sh` passed against the full parity artifact set.
  - Full check: `RUMPELMC_USE_SCCACHE=0 ./scripts/check.sh full` passed; `golangci-lint` is not installed locally and was skipped by the script.
- Latest GPU terrain render flag safety slice passed:
  - `RUMPELMC_GPU_TERRAIN_RENDER` remains opt-in by default; the Rust decision helper now has a unit test that default/no env stays disabled, explicit true enables, and explicit false disables.
  - Rust: `cargo fmt --manifest-path client/rust_ext/Cargo.toml -- --check`, `cargo check --manifest-path client/rust_ext/Cargo.toml`, `cargo test --manifest-path client/rust_ext/Cargo.toml` (19/19), and `cargo build --manifest-path client/rust_ext/Cargo.toml`.
  - `RUMPELMC_PARITY_SMOKE_VALIDATE_ONLY=1 ./scripts/gpu_terrain_parity_smoke.sh` passed against the current parity artifacts.
  - Full check: `RUMPELMC_USE_SCCACHE=0 ./scripts/check.sh full` passed; `golangci-lint` is not installed locally and was skipped by the script.
- Latest opaque solid GPU terrain shader guard slice passed:
  - Added a Rust unit test that reads the included GPU terrain render shader and verifies the solid pass forces fragment alpha to `1.0` and does not use `texel.a`. This protects the prior grass/solid block transparency regression.
  - Rust: `cargo fmt --manifest-path client/rust_ext/Cargo.toml -- --check`, `cargo check --manifest-path client/rust_ext/Cargo.toml`, `cargo test --manifest-path client/rust_ext/Cargo.toml` (20/20), and `cargo build --manifest-path client/rust_ext/Cargo.toml`.
  - `RUMPELMC_PARITY_SMOKE_VALIDATE_ONLY=1 ./scripts/gpu_terrain_parity_smoke.sh` passed against the current parity artifacts.
  - Full check: `RUMPELMC_USE_SCCACHE=0 ./scripts/check.sh full` passed; `golangci-lint` is not installed locally and was skipped by the script.
- Latest GPU terrain shader push-constant layout guard slice passed:
  - Added a Rust unit test that reads the included GPU terrain render shader and verifies the GLSL push-constant order matches the Rust byte layout: clip matrix, lighting block, then atlas layout.
  - Rust: `cargo fmt --manifest-path client/rust_ext/Cargo.toml -- --check`, `cargo check --manifest-path client/rust_ext/Cargo.toml`, `cargo test --manifest-path client/rust_ext/Cargo.toml` (21/21), and `cargo build --manifest-path client/rust_ext/Cargo.toml`.
  - `RUMPELMC_PARITY_SMOKE_VALIDATE_ONLY=1 ./scripts/gpu_terrain_parity_smoke.sh` passed against the current parity artifacts.
  - Full check: `RUMPELMC_USE_SCCACHE=0 ./scripts/check.sh full` passed; `golangci-lint` is not installed locally and was skipped by the script.
- Latest GPU terrain reverse-Z depth-state guard slice passed:
  - Added a Rust unit test for the pure depth-state config used by the RD render pipeline: scene depth keeps test/write paired with `enable_depth`, and the compare operator stays `GREATER_OR_EQUAL` for Godot 4.6 reverse-Z.
  - Rust: `cargo fmt --manifest-path client/rust_ext/Cargo.toml -- --check`, `cargo check --manifest-path client/rust_ext/Cargo.toml`, `cargo test --manifest-path client/rust_ext/Cargo.toml` (22/22), and `cargo build --manifest-path client/rust_ext/Cargo.toml`.
  - `RUMPELMC_PARITY_SMOKE_VALIDATE_ONLY=1 ./scripts/gpu_terrain_parity_smoke.sh` passed against the current parity artifacts.
  - Full check: `RUMPELMC_USE_SCCACHE=0 ./scripts/check.sh full` passed; `golangci-lint` is not installed locally and was skipped by the script.
- Latest GPU terrain shadow-proxy radius slice passed:
  - `GameClient::terrain_shadow_proxy_chunk_distance()` now delegates to a pure helper covered by unit tests. Explicit radius overrides are clamped, finite Godot shadow distance is converted to chunk radius, disabled scene shadows return radius `0`, unavailable scene data uses the conservative default distance, and non-finite distances fall back to `DEFAULT_GPU_TERRAIN_SHADOW_PROXY_CHUNK_DISTANCE`.
  - This keeps the default conservative shadow-proxy behavior when the `SunLight` cannot be inspected, while avoiding unnecessary shadow-only CPU proxies when Godot shadows are explicitly disabled.
  - Rust: `cargo fmt --manifest-path client/rust_ext/Cargo.toml -- --check`, `cargo check --manifest-path client/rust_ext/Cargo.toml`, `cargo test --manifest-path client/rust_ext/Cargo.toml` (25/25), and `cargo build --manifest-path client/rust_ext/Cargo.toml`.
  - Full check: `RUMPELMC_USE_SCCACHE=0 ./scripts/check.sh full` passed; `golangci-lint` is not installed locally and was skipped by the script.
  - `RUMPELMC_PARITY_SMOKE_VALIDATE_ONLY=1 ./scripts/gpu_terrain_parity_smoke.sh` passed against the current parity artifacts.
- Latest CPU proxy decision guard slice passed:
  - `GameClient::subchunk_needs_collision()`, `subchunk_needs_shadow_proxy()`, and `subchunk_needs_cpu_proxy()` now delegate to pure helpers covered by unit tests. The tests lock the fallback rule, nearby collision radius, conservative-vs-collision-only shadow mode, shadow radius behavior, and the rule that GPU-visible subchunks without collision or shadow reasons may drop their CPU proxy.
  - The shadow helper now treats `radius <= 0` as no shadow proxy even before `current_player_chunk` is known, matching disabled Godot shadows and avoiding an origin-only shadow proxy in that state.
  - Rust: `cargo fmt --manifest-path client/rust_ext/Cargo.toml -- --check`, `cargo check --manifest-path client/rust_ext/Cargo.toml`, `cargo test --manifest-path client/rust_ext/Cargo.toml` (28/28), and `cargo build --manifest-path client/rust_ext/Cargo.toml`.
  - Full check: `RUMPELMC_USE_SCCACHE=0 ./scripts/check.sh full` passed; `golangci-lint` is not installed locally and was skipped by the script.
  - `RUMPELMC_PARITY_SMOKE_VALIDATE_ONLY=1 ./scripts/gpu_terrain_parity_smoke.sh` passed against the current parity artifacts.
- Latest CPU proxy refresh guard slice passed:
  - `GameClient::enqueue_cpu_proxy_refresh()` now delegates its per-chunk refresh condition to pure helpers covered by a unit test. The test locks start-up refresh with no previous player chunk, collision radius enter/leave edges, shadow-only refresh outside collision radius, and disabled shadow radius `0`.
  - Behavior is unchanged: the refresh still queues loaded chunks that were or are inside the collision radius or the active conservative shadow-proxy radius.
  - Rust: `cargo fmt --manifest-path client/rust_ext/Cargo.toml -- --check`, `cargo check --manifest-path client/rust_ext/Cargo.toml`, `cargo test --manifest-path client/rust_ext/Cargo.toml` (29/29), and `cargo build --manifest-path client/rust_ext/Cargo.toml`.
  - Full check: `RUMPELMC_USE_SCCACHE=0 ./scripts/check.sh full` passed; `golangci-lint` is not installed locally and was skipped by the script.
  - `RUMPELMC_PARITY_SMOKE_VALIDATE_ONLY=1 ./scripts/gpu_terrain_parity_smoke.sh` passed against the current parity artifacts.
- Latest GPU attach refresh guard slice passed:
  - `GameClient::refresh_cpu_proxies_after_gpu_attach()` now delegates the list of chunks to refresh to a pure helper covered by a unit test. The test locks the intentional behavior: no refresh before the GPU visible path is active, and all loaded chunks are refreshed after GPU visibility is confirmed.
  - This protects the distant ArrayMesh removal path from a future optimization that only refreshes nearby chunks and leaves old CPU terrain nodes alive after the first GPU frame.
  - Rust: `cargo fmt --manifest-path client/rust_ext/Cargo.toml -- --check`, `cargo check --manifest-path client/rust_ext/Cargo.toml`, `cargo test --manifest-path client/rust_ext/Cargo.toml` (30/30), and `cargo build --manifest-path client/rust_ext/Cargo.toml`.
  - Full check: `RUMPELMC_USE_SCCACHE=0 ./scripts/check.sh full` passed; `golangci-lint` is not installed locally and was skipped by the script.
  - `RUMPELMC_PARITY_SMOKE_VALIDATE_ONLY=1 ./scripts/gpu_terrain_parity_smoke.sh` passed against the current parity artifacts.
- Latest GPU terrain mesh-build plan guard slice passed:
  - `GameClient::render_subchunk_mesh()` now delegates the CPU mesh path choice to a pure `TerrainMeshBuildPlan` helper covered by a unit test. The test locks the three production-sensitive outcomes: remove the CPU node when uploaded GPU terrain has no CPU proxy reason, build a packed-face CPU proxy only after the GPU visible path is active and packed faces are available, and fall back to the full ArrayMesh path otherwise.
  - This preserves the ArrayMesh fallback for failed GPU uploads, pre-confirmation GPU state, and missing packed-face data while making future distant CPU mesh removal changes easier to review.
  - Rust: `cargo fmt --manifest-path client/rust_ext/Cargo.toml -- --check`, `cargo check --manifest-path client/rust_ext/Cargo.toml`, `cargo test --manifest-path client/rust_ext/Cargo.toml` (31/31), and `cargo build --manifest-path client/rust_ext/Cargo.toml`.
  - Full check: `RUMPELMC_USE_SCCACHE=0 ./scripts/check.sh full` passed; `golangci-lint` is not installed locally and was skipped by the script.
  - `RUMPELMC_PARITY_SMOKE_VALIDATE_ONLY=1 ./scripts/gpu_terrain_parity_smoke.sh` passed against the current parity artifacts.
- Latest GPU terrain upload flag guard slice passed:
  - `gpu_terrain_upload_enabled()` now delegates its decision to a pure helper covered by a unit test. The test locks that upload stays off by default, explicit upload enables it, and opt-in GPU render also enables upload so visible GPU terrain cannot run without GPU face uploads.
  - This preserves the current invariant that `RUMPELMC_GPU_TERRAIN_RENDER` itself remains opt-in while keeping the render/upload dependency explicit and reviewable.
  - Rust: `cargo fmt --manifest-path client/rust_ext/Cargo.toml -- --check`, `cargo check --manifest-path client/rust_ext/Cargo.toml`, `cargo test --manifest-path client/rust_ext/Cargo.toml` (32/32), and `cargo build --manifest-path client/rust_ext/Cargo.toml`.
  - Full check: `RUMPELMC_USE_SCCACHE=0 ./scripts/check.sh full` passed; `golangci-lint` is not installed locally and was skipped by the script.
  - `RUMPELMC_PARITY_SMOKE_VALIDATE_ONLY=1 ./scripts/gpu_terrain_parity_smoke.sh` passed against the current parity artifacts.
- Latest GPU terrain visible activation guard slice passed:
  - `GameClient::gpu_terrain_visible_render_active()` now delegates its decision to a pure helper covered by a unit test. The test locks the delayed transition invariant: CPU fallback/proxy nodes are only allowed to switch after the render flag is enabled, the compositor is attached, and the GPU terrain buffer pool has confirmed at least one visible render frame.
  - This protects the visible-path transition from hiding or removing ArrayMesh fallback too early when GPU setup is only partially complete.
  - Rust: `cargo fmt --manifest-path client/rust_ext/Cargo.toml -- --check`, `cargo check --manifest-path client/rust_ext/Cargo.toml`, `cargo test --manifest-path client/rust_ext/Cargo.toml` (33/33), and `cargo build --manifest-path client/rust_ext/Cargo.toml`.
  - Full check: `RUMPELMC_USE_SCCACHE=0 ./scripts/check.sh full` passed; `golangci-lint` is not installed locally and was skipped by the script.
  - `RUMPELMC_PARITY_SMOKE_VALIDATE_ONLY=1 ./scripts/gpu_terrain_parity_smoke.sh` passed against the current parity artifacts.
- Latest terrain mesh render-state counter guard slice passed:
  - `NodePerfCounts::record_mesh_render_state()` now delegates the visible/shadow bucket updates to a pure helper covered by a unit test. The test locks the `mesh_visible`, `mesh_shadow_off`, `mesh_shadow_double`, and `mesh_shadow_only` buckets that the parity gate uses for collision-only and proxy render-state regressions.
  - Behavior is unchanged for real `MeshInstance3D` nodes; the helper only makes the counter mapping reviewable without constructing Godot scene nodes in unit tests.
  - Rust: `cargo fmt --manifest-path client/rust_ext/Cargo.toml -- --check`, `cargo check --manifest-path client/rust_ext/Cargo.toml`, `cargo test --manifest-path client/rust_ext/Cargo.toml` (34/34), and `cargo build --manifest-path client/rust_ext/Cargo.toml`.
  - Full check: `RUMPELMC_USE_SCCACHE=0 ./scripts/check.sh full` passed; `golangci-lint` is not installed locally and was skipped by the script.
  - `RUMPELMC_PARITY_SMOKE_VALIDATE_ONLY=1 ./scripts/gpu_terrain_parity_smoke.sh` passed against the current parity artifacts.
- Latest terrain proxy-reason counter guard slice passed:
  - `NodePerfCounts` now records CPU proxy reason buckets through a pure `record_cpu_proxy_reasons()` helper covered by a unit test. The test locks `proxy_coll`, `proxy_shadow`, `proxy_both`, and `proxy_shadow_only` mapping for collision-only, shadow-only, both, and no-reason cases.
  - Behavior is unchanged for real terrain nodes; `GameClient::current_node_perf_counts()` still derives the same collision and shadow proxy reasons before recording the counters.
  - Rust: `cargo fmt --manifest-path client/rust_ext/Cargo.toml -- --check`, `cargo check --manifest-path client/rust_ext/Cargo.toml`, `cargo test --manifest-path client/rust_ext/Cargo.toml` (35/35), and `cargo build --manifest-path client/rust_ext/Cargo.toml`.
  - Full check: `RUMPELMC_USE_SCCACHE=0 ./scripts/check.sh full` passed; `golangci-lint` is not installed locally and was skipped by the script.
  - `RUMPELMC_PARITY_SMOKE_VALIDATE_ONLY=1 ./scripts/gpu_terrain_parity_smoke.sh` passed against the current parity artifacts.
- Latest terrain shadow-path visibility slice passed:
  - Rust perf text now includes `shadow_path=...`, with a pure `terrain_shadow_path_decision()` helper covered by a unit test. The values make the current shadow strategy explicit: `arraymesh` for CPU/fallback terrain, `godot_proxy` for the conservative GPU-visible production path, `scene_shadows_disabled` when scene shadows resolve to radius `0`, and `diagnostic_no_shadow_proxy` for `collision_only`.
  - `scripts/gpu_terrain_parity_smoke.sh` now requires the expected `shadow_path` in CPU, GPU conservative, compact proxy, radius, multi-pose, and collision-only markers. This keeps `collision_only` visibly diagnostic and protects the current Godot shadow-proxy production path from accidental removal.
  - Behavior is unchanged: GPU terrain render remains opt-in, conservative Godot shadow proxies remain active, and ArrayMesh fallback remains intact.
  - Rust: `cargo fmt --manifest-path client/rust_ext/Cargo.toml -- --check`, `cargo check --manifest-path client/rust_ext/Cargo.toml`, `cargo test --manifest-path client/rust_ext/Cargo.toml` (36/36), and `cargo build --manifest-path client/rust_ext/Cargo.toml`.
  - Full check: `RUMPELMC_USE_SCCACHE=0 ./scripts/check.sh full` passed; `golangci-lint` is not installed locally and was skipped by the script.
  - Fresh direct parity captures passed across all ten marker files; examples include `shadow_path=arraymesh` for CPU fallback, `shadow_path=godot_proxy` for conservative GPU cases, and `shadow_path=diagnostic_no_shadow_proxy` for the collision-only diagnostic case.
  - `RUMPELMC_PARITY_SMOKE_VALIDATE_ONLY=1 sh ./scripts/gpu_terrain_parity_smoke.sh` passed against the fresh artifacts. Direct executable wrapper launch can still stall in this Codex PTY environment, matching the known wrapper issue; use explicit `sh` or direct Godot commands for the reliable local gate.
- Latest collision-only compact proxy slice passed:
  - Collision-only CPU proxy meshes now use the same vertex-only compact payload as compact shadow-only proxies. This applies only when a GPU-visible proxy needs collision and does not need a Godot shadow proxy; conservative collision+shadow proxies and ArrayMesh fallback stay on the full mesh path.
  - Rust perf text now includes `compact_collision_proxy=...` and `compact_collision_normals_saved=...`. `fast_proxy` remains the total packed-face CPU proxy counter, while the new compact collision counters make the collision-only diagnostic payload reduction explicit.
  - `scripts/gpu_terrain_parity_smoke.sh` now requires zero compact-collision payload in CPU fallback and conservative shadow-proxy cases, and requires `compact_collision_proxy == fast_proxy` in the `collision_only` diagnostic marker.
  - Rust: `cargo fmt --manifest-path client/rust_ext/Cargo.toml -- --check`, `cargo check --manifest-path client/rust_ext/Cargo.toml`, `cargo test --manifest-path client/rust_ext/Cargo.toml` (37/37), and `cargo build --manifest-path client/rust_ext/Cargo.toml`.
  - Full check: `RUMPELMC_USE_SCCACHE=0 ./scripts/check.sh full` passed; `golangci-lint` is not installed locally and was skipped by the script.
  - Fresh direct parity captures passed across all ten marker files. The collision-only marker included `compact_collision_proxy=20`, `compact_collision_normals_saved=186192`, `fast_proxy=20`, `mesh_visible=0`, `mesh_shadow_off=10`, and `shadow_path=diagnostic_no_shadow_proxy`.
  - `RUMPELMC_PARITY_SMOKE_VALIDATE_ONLY=1 sh ./scripts/gpu_terrain_parity_smoke.sh` passed against the fresh artifacts.
- Latest compact proxy benchmark report slice passed:
  - `scripts/gpu_terrain_compact_proxy_benchmark.sh` now validates and reports the new collision-only compact proxy counters alongside compact shadow proxy counters. Conservative full/compact rows are required to keep `compact_collision_proxy=0`, while the collision-only diagnostic row requires `compact_collision_proxy == fast_proxy`.
  - The benchmark summary now prints `compact_collision_proxy`, `collision_normals_saved`, `shadow_normal_total_reduction`, and `collision_normal_payload_reduction`.
  - Checks passed: `sh -n scripts/gpu_terrain_compact_proxy_benchmark.sh`, `./scripts/gpu_terrain_compact_proxy_benchmark.sh`, `./scripts/check.sh fast` (Rust tests 37/37), `RUMPELMC_PARITY_SMOKE_VALIDATE_ONLY=1 sh ./scripts/gpu_terrain_parity_smoke.sh`, and `git diff --check`.
  - Current artifact report: full `normals_total=1243584`, compact `normals_total=260544`, collision-only `compact_collision_proxy=20`, `compact_collision_normals_saved=186192`, `shadow_normal_total_reduction=79.0%`, and `collision_normal_payload_reduction=71.5%`.
- Latest shadow-disabled parity guard slice passed:
  - `scripts/gpu_terrain_parity_smoke.sh` now captures and validates `gpu-terrain-shadow-disabled-parity` with `RUMPELMC_GPU_TERRAIN_SHADOW_PROXY_CHUNK_DISTANCE=0`, conservative mode, and `shadow_mesh=full`.
  - The new marker is required to report `shadow_path=scene_shadows_disabled`, `proxy_shadow=0`, `proxy_both=0`, `proxy_shadow_only=0`, `mesh_visible=0`, and `mesh_shadow_off == cpu_proxy`, while keeping `compact_collision_proxy == fast_proxy`.
  - Direct Godot capture passed for the new marker: `cpu_proxy=10`, `collision=10`, `compact_collision_proxy=20`, `compact_collision_normals_saved=192336`, `fast_proxy=20`, `mesh_shadow_off=10`, `gpu_frames=172`, and `terrain_samples=256`.
  - Checks passed: `sh -n scripts/gpu_terrain_parity_smoke.sh`, `RUMPELMC_PARITY_SMOKE_VALIDATE_ONLY=1 sh ./scripts/gpu_terrain_parity_smoke.sh`, `./scripts/check.sh fast` (Rust tests 37/37), and `git diff --check`.
- Latest compact proxy benchmark shadow-disabled report slice passed:
  - `scripts/gpu_terrain_compact_proxy_benchmark.sh` now validates and reports the production-safe `shadow_path=scene_shadows_disabled` marker alongside the diagnostic `collision_only` marker.
  - Report mode now prints a `shadow_disabled` row and separate collision normal payload reductions for `shadow_disabled` and `collision_only`, so disabled-scene-shadow savings are visible without treating `collision_only` as production behavior.
  - Checks passed: `sh -n scripts/gpu_terrain_compact_proxy_benchmark.sh`, `./scripts/gpu_terrain_compact_proxy_benchmark.sh`, `./scripts/check.sh fast` (Rust tests 37/37), `RUMPELMC_PARITY_SMOKE_VALIDATE_ONLY=1 sh ./scripts/gpu_terrain_parity_smoke.sh`, and `git diff --check`.
  - Current artifact report: `shadow_disabled compact_collision_proxy=20`, `shadow_disabled compact_collision_normals_saved=192336`, `shadow_disabled_collision_normal_payload_reduction=72.1%`; `collision_only_collision_normal_payload_reduction=71.5%`.
- Latest GPU-visible CPU-node removal guard slice passed:
  - `terrain_mesh_build_plan()` now requires `gpu_visible_render_active` before returning `RemoveCpuNode`, even if a future caller incorrectly reports no CPU proxy reason before the first confirmed GPU terrain frame.
  - The existing mesh-build-plan unit test now locks that uploaded GPU terrain still falls back to `FullArrayMesh` before the GPU visible path is active.
  - Checks passed: `cargo fmt --manifest-path client/rust_ext/Cargo.toml -- --check`, `cargo check --manifest-path client/rust_ext/Cargo.toml`, `cargo test --manifest-path client/rust_ext/Cargo.toml` (37/37), `./scripts/check.sh fast`, `RUMPELMC_USE_SCCACHE=0 ./scripts/check.sh full`, `RUMPELMC_PARITY_SMOKE_VALIDATE_ONLY=1 sh ./scripts/gpu_terrain_parity_smoke.sh`, `git diff --check`, and `./scripts/diff_guard.sh`.
- Latest GPU-backed CPU proxy activation guard slice passed:
  - Added pure `terrain_cpu_proxy_mesh_active()` and routed both mesh-build planning and render-mode refresh through it. CPU nodes are treated as GPU-backed proxy meshes only when the GPU visible path is confirmed and the specific subchunk has a GPU slot.
  - Added a unit test that locks all four active/inactive combinations, protecting fallback meshes from being switched to proxy render modes without an actual GPU subchunk.
  - Checks passed: `cargo fmt --manifest-path client/rust_ext/Cargo.toml -- --check`, `cargo check --manifest-path client/rust_ext/Cargo.toml`, `cargo test --manifest-path client/rust_ext/Cargo.toml` (38/38), `RUMPELMC_PARITY_SMOKE_VALIDATE_ONLY=1 sh ./scripts/gpu_terrain_parity_smoke.sh`, `RUMPELMC_USE_SCCACHE=0 ./scripts/check.sh full`, `git diff --check`, and `./scripts/diff_guard.sh`.
- Latest GPU upload-failure fallback guard slice passed:
  - Extended the mesh-build-plan unit test so an active GPU-visible path still returns `FullArrayMesh` when the specific subchunk has no GPU slot, even if there is no CPU proxy reason. This protects fallback rendering for per-subchunk upload failures.
  - Checks passed: `cargo fmt --manifest-path client/rust_ext/Cargo.toml -- --check`, `cargo test --manifest-path client/rust_ext/Cargo.toml` (38/38), `RUMPELMC_PARITY_SMOKE_VALIDATE_ONLY=1 sh ./scripts/gpu_terrain_parity_smoke.sh`, `RUMPELMC_USE_SCCACHE=0 ./scripts/check.sh full`, `git diff --check`, and `./scripts/diff_guard.sh`.

Useful log lines:

- `GPU terrain compositor initialized`
- `GPU terrain compositor attached to player camera`
- `GPU terrain compositor draw: size=1280x720 views=1 draws=2 faces=7242`
- `GPU terrain compositor draw: size=1280x720 views=1 depth=true draws=2 faces=7242`
- `Visual smoke screenshot saved ... current_chunk="0,0"`
- `perf="... gpu_subchunks=66 gpu_draws=66 gpu_faces=116824 gpu_frames=116 ..."`
- `GPU terrain visible path confirmed`
- `Visual smoke screenshot saved ... terrain_samples=576 ... smoke_err=0 ... gpu_frames=160 ...`
- `Visual smoke screenshot saved ... terrain_samples=288 ... smoke_err=0 ... cpu_proxy=10 collision=10 ... gpu_subchunks=92 ...`
- `Visual smoke screenshot saved ... terrain_samples=288 ... smoke_err=0 ... current_chunk="0,0"` for CPU fallback.
- `Visual smoke screenshot saved ... terrain_samples=288 ... smoke_err=0 ... fast_proxy=163 ... gpu_frames=190 ...`
- `Visual smoke screenshot saved ... terrain_samples=288 ... smoke_err=0 ... cpu_proxy=10 collision=10 fast_proxy=20 ... gpu_frames=195 ...`
- `Visual smoke screenshot saved ... terrain_samples=288 ... smoke_err=0 ... fast_proxy=0 ... current_chunk="0,0"` for CPU fallback.
- `Visual smoke screenshot saved ... parity/cpu-arraymesh-parity.png ... avg_luma=0.3517 ... terrain_samples=256 ... smoke_err=0 ... fast_proxy=0 collision=10 ...`
- `Visual smoke screenshot saved ... parity/gpu-terrain-parity.png ... avg_luma=0.3442 ... terrain_samples=256 ... smoke_err=0 ... fast_proxy=62 ... gpu_frames=68 ...`
- `Visual smoke screenshot saved ... parity/gpu-terrain-radius1-parity.png ... terrain_samples=256 ... smoke_err=0 ... cpu_proxy=10 fast_proxy=19 collision=10 ... gpu_frames=74 ...`
- `Visual smoke screenshot saved ... parity/cpu-arraymesh-parity.png ... terrain_color_buckets=8 terrain_chroma_samples=256 terrain_luma_range=0.3655 ...`
- `Visual smoke screenshot saved ... parity/gpu-terrain-parity.png ... terrain_color_buckets=8 terrain_chroma_samples=256 terrain_luma_range=0.3532 ... gpu_frames=143 ...`
- `Visual smoke screenshot saved ... parity/gpu-terrain-radius1-parity.png ... terrain_color_buckets=8 terrain_chroma_samples=256 terrain_luma_range=0.3532 ... cpu_proxy=10 fast_proxy=20 ... gpu_frames=149 ...`
- `Visual smoke screenshot saved ... parity/gpu-terrain-parity.png ... cpu_proxy=82 proxy_coll=10 proxy_shadow=82 proxy_both=10 proxy_shadow_only=72 ...`
- `Visual smoke screenshot saved ... parity/gpu-terrain-radius1-parity.png ... cpu_proxy=10 proxy_coll=10 proxy_shadow=10 proxy_both=10 proxy_shadow_only=0 ...`
- `Visual smoke screenshot saved ... parity/gpu-terrain-atlas-depth-parity.png pose="atlas_depth" ... terrain_samples=510 terrain_color_buckets=9 terrain_luma_range=0.3294 ...`
- `Visual smoke screenshot saved ... parity/gpu-terrain-lighting-shadow-parity.png pose="lighting_shadow" ... terrain_samples=453 terrain_color_buckets=10 terrain_luma_range=0.3570 ...`
- `Visual smoke screenshot saved ... parity/gpu-terrain-compact-lighting-shadow-parity.png pose="lighting_shadow" ... shadow_mesh=compact compact_shadow_proxy=97 compact_shadow_normals_saved=1320960 ...`

Known limitations:

- GPU terrain render is still opt-in via `RUMPELMC_GPU_TERRAIN_RENDER=1`.
- GPU terrain now samples the real block texture atlas and applies directional lighting, but visual parity still needs shadow integration and visual tuning.
- GPU terrain solid blocks force opaque alpha in the shader; do not infer grass/solid block transparency from the RGBA atlas alpha.
- GPU terrain shader atlas UVs now use runtime atlas layout push constants instead of a hard-coded column count.
- GPU terrain atlas texture now prefers sRGB sampling; color parity should still be visually compared against the ArrayMesh fallback before deleting more CPU rendering.
- Depth-compatible scene rendering is wired and smoke-tested with Godot 4.6 reverse-Z depth compare.
- GPU terrain is now directional-light aware, and retained ArrayMesh terrain is explicitly configured as a double-sided Godot shadow caster proxy.
- With `RUMPELMC_GPU_TERRAIN_RENDER=1`, CPU ArrayMesh nodes become `SHADOWS_ONLY` only after the GPU visible render path has rendered at least one compositor frame; this avoids double visible terrain while preserving fallback if GPU setup fails or a subchunk fails GPU upload.
- Distant CPU terrain node removal is also gated by the confirmed GPU-visible path inside `terrain_mesh_build_plan()`, not only by the current caller's proxy decision.
- CPU terrain nodes are considered GPU-backed proxies only when the confirmed GPU-visible path and the per-subchunk GPU slot are both present.
- With `RUMPELMC_GPU_TERRAIN_RENDER=1`, CPU ArrayMesh nodes are still kept where needed for nearby collision and the conservative Godot shadow-map proxy. Distant CPU `MeshInstance3D` removal has started, but the retained proxy radius is intentionally conservative.
- With `RUMPELMC_GPU_TERRAIN_RENDER=1`, retained CPU proxy meshes can now be built from packed GPU terrain faces after the GPU visible path is confirmed. These proxy meshes intentionally omit UVs because they are used for collision and `SHADOWS_ONLY`, not visible terrain.
- `RUMPELMC_GPU_TERRAIN_SHADOW_PROXY_MODE=collision_only` is diagnostic only for now. It confirms how much CPU work is shadow-proxy-only. In this mode retained collision CPU proxies are invisible and do not cast shadows, but it must not become the default until GPU terrain has a dedicated shadow-compatible path or native Godot shadow-map participation.
- `RUMPELMC_GPU_TERRAIN_SHADOW_PROXY_MESH=compact` is now the default for GPU-visible shadow-only CPU proxy meshes. Use `RUMPELMC_GPU_TERRAIN_SHADOW_PROXY_MESH=full` for a control run or opt-out. This is still a Godot shadow proxy and does not replace native RD shadow-map participation.
- `scripts/gpu_terrain_parity_smoke.sh` can validate existing artifacts with `RUMPELMC_PARITY_SMOKE_VALIDATE_ONLY=1`. It now expects markers produced by the extended visual smoke metrics and multi-pose support in `client/main.gd`, plus proxy reason counters, terrain mesh render-state counters, `shadow_mode=...`, `shadow_mesh=...`, and `compact_shadow_normals_saved=...` from `client/rust_ext/src/lib.rs`. It validates CPU/GPU pose parity, compact-vs-full `lighting_shadow` parity, disabled-shadow-radius behavior, and `collision_only` proxy render-state invariants. In this Codex PTY environment, launching Godot through shell wrappers can still stall before project logs appear, so direct Godot commands plus validate-only are the reliable local gate.
- `scripts/gpu_terrain_compact_proxy_benchmark.sh` defaults to report mode over existing parity artifacts and now includes both the disabled-shadow-radius marker and the collision-only diagnostic marker. Use `RUMPELMC_COMPACT_PROXY_BENCH_CAPTURE=1` only when the local shell/Godot wrapper is known to be reliable, or prefer direct Godot captures followed by benchmark report mode.
- The custom RD compositor draw still does not natively participate in Godot shadow maps as a real shadow caster/receiver. Full shadow parity without ArrayMesh proxy needs a separate render integration plan.
- Final ArrayMesh replacement for distant terrain is not finished.
- Keep the working tree small and commit completed slices; `diff_guard` is expected to stay green after the dirty-tree cleanup baseline.

Next steps:

1. After any GPU terrain edit, run the parity gate: direct CPU/GPU/radius=1 visual smoke captures with `RUMPELMC_VISUAL_SMOKE_DISABLE_PLAYER_INPUT=1`, then `RUMPELMC_PARITY_SMOKE_VALIDATE_ONLY=1 ./scripts/gpu_terrain_parity_smoke.sh`.
2. Keep compact shadow-only proxy meshes as the default unless fresh parity or visual shadow checks show a regression; use `RUMPELMC_GPU_TERRAIN_SHADOW_PROXY_MESH=full` for comparison runs.
3. Decide the production shadow path next: either build a dedicated lower-cost shadow proxy beyond ArrayMesh, or make the RD terrain participate in Godot shadow maps. The new `collision_only` mode is useful for measurement, not a production default.
4. Do not make `collision_only` default or remove conservative shadow proxies until multi-pose parity and visible shadow behavior are explicitly verified.
5. Continue reducing CPU ArrayMesh generation for distant chunks while preserving nearby collision meshes, shadow proxy requirements, and the fallback path.
6. Run `RUMPELMC_USE_SCCACHE=0 ./scripts/check.sh full`, parity visual smoke validation, and `./scripts/diff_guard.sh` before handing off again.
