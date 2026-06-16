# GPU Roadmap

This roadmap is the sequential GPU backlog for sustained optimization work. Keep each iteration small, measurable, and reversible. Do not reduce draw distance, lighting, shadows, texture quality, or visible quality to hit a performance target.

## Operating Rules

- Work in small slices and checkpoint stable changes before starting the next slice.
- Prefer report-first telemetry before renderer rewrites.
- Record blocked or inconclusive steps in `docs/AGENT_HANDOFF.md`, then continue with the next safe iteration.
- Use rollback env flags for risky runtime behavior changes.
- Treat local visual FPS above the display refresh rate as unreliable on macOS/Metal until an external GPU profiler confirms otherwise.
- Run the narrowest relevant checks for each slice; use `./scripts/check.sh full` and `./scripts/diff_guard.sh` for broad or sensitive changes.

## Phase 1: Stabilization And Measurement

1. Stabilize GPU terrain back-face culling.
2. Record culling rollback controls and smoke results.
3. Add rasterization/culling state to perf markers.
4. Run parity smoke across all supported poses.
5. Add culling regression coverage to parity gates.
6. Create this roadmap and keep it current.
7. Create GPU profiling documentation.
8. Define trusted and untrusted performance metrics.
9. Add a unified GPU terrain report script.
10. Add report output to handoff snapshots.

## Phase 2: Stress Gates

11. Stabilize fill-stress repeat values `1/4/8`.
12. Add repeat `16` as report-only stress.
13. Make fill-stress capture failures explicit.
14. Gate on successful marker generation.
15. Gate on non-sky terrain visibility.
16. Gate on `gpu_upload_fail=0`.
17. Gate on compositor submit max.
18. Gate on terrain queue max.
19. Gate on process wall p95.
20. Add run-to-run summary diffing.

## Phase 3: Workload Scaling

21. Keep radius `10/12/14/16` comparison artifacts.
22. Compare server batch sizes under the same movement path.
23. Add repeat-count workload summaries.
24. Add long movement summaries.
25. Add max-resident summaries.
26. Add extended movement summaries.
27. Add block-edit stress.
28. Done 2026-06-16: added `scripts/gpu_terrain_chunk_boundary_stress.sh` as the chunk enter/exit stress gate over `long-move`, `spiral`, `fast-turn`, `teleport-snap`, and bounded `high-resident` workload evidence.
29. Done 2026-06-16: added `scripts/gpu_terrain_rapid_camera_turn_stress.sh` as a standalone `chunk_fast_turn` gate for rapid camera orientation changes inside one current chunk.
30. Done 2026-06-16: added `scripts/gpu_stress_artifact_index.sh` as the current GPU stress artifact index over required streaming/residency/upload/draw/transparent evidence plus optional governance/profiler gap rows.

## Phase 4: GPU Memory And Residency

31. Log GPU terrain buffer total size.
32. Log used/free allocation ranges.
33. Log allocator fragmentation.
34. Log largest free range.
35. Classify allocation failures by cause.
36. Add allocator stress tests.
37. Add fragmentation tests.
38. Add runtime warning for high fragmentation.
39. Done 2026-06-14: designed safe GPU terrain buffer repack behind explicit rollback flag in `docs/GPU_BUFFER_REPACK.md`.
40. Done 2026-06-14: added default-off GPU buffer repack prototype foundation behind `RUMPELMC_GPU_TERRAIN_BUFFER_REPACK=1`, with marker-only telemetry, source mirror, payload preview, explicit one-shot temporary replacement-buffer upload/binding preview, draw-command remap preview, all-or-nothing staged swap guard, disabled commit-point proof, disabled apply scaffold, disabled final-swap guard, report aggregation, and pure planner/payload/draw/staged/commit/apply/final-guard tests; no active render binding, indirect-buffer swap, slot mutation, or allocator mutation yet.
41. Done 2026-06-15: added `scripts/gpu_terrain_memory_budget.sh` and `docs/GPU_TERRAIN_MEMORY_BUDGETING.md` as a summary-only budget gate for configured terrain buffers, active face bytes, subchunks, draws, faces, draw-command occupancy/headroom, fragmentation, free ranges, and upload failures.

## Phase 5: Upload Pipeline

41. Audit CPU copies before GPU upload.
42. Log upload bytes per frame.
43. Log upload count per frame.
44. Log upload queue depth.
45. Log upload latency.
46. Done 2026-06-16: split terrain queue GPU upload telemetry into new-slot and replacement-slot upload counts/bytes, and validated both lanes in movement plus in-place block-edit gates.
47. Done 2026-06-16: added `scripts/gpu_terrain_upload_budget.sh` and `docs/GPU_TERRAIN_UPLOAD_BUDGETING.md` as a summary-only per-frame total/new-slot/replacement-slot upload count and KiB budget gate.
48. Done 2026-06-16: validated the upload budget gate against current movement/in-place artifacts and a negative tight-budget check (`reason=movement_upload_kb_budget`).
49. Done 2026-06-16: added `scripts/gpu_terrain_mass_chunk_load_gate.sh` and `docs/GPU_TERRAIN_MASS_CHUNK_LOAD.md` to combine high resident-set load-scaling evidence with the current per-frame upload budget.
50. Done 2026-06-16: added explicit GPU upload retry/backoff telemetry (`gpu_upload_retry_policy=none` plus zero retry/backoff counters) to runtime markers, movement/in-place summaries, aggregate report, and upload budget gate.

## Phase 6: Upload Robustness

51. Done 2026-06-16: verified upload failure recovery keeps per-subchunk CPU ArrayMesh fallback until a GPU slot is confirmed, with targeted mesh-build/proxy-refresh unit coverage and `docs/GPU_UPLOAD_FAILURE_RECOVERY.md`.
52. Done 2026-06-16: added opt-in GPU upload failure injection plus `scripts/gpu_terrain_upload_failure_fallback_gate.sh` to keep visual CPU ArrayMesh fallback valid after forced upload failures.
53. Done 2026-06-16: the upload failure fallback gate requires `shadow_path=arraymesh`, visible double-sided ArrayMesh shadow markers, and zero capacity/fragmentation failure causes under forced upload failure.
54. Done 2026-06-16: the upload failure fallback gate requires current render/collision readiness, nonzero current chunk collision, zero ground misses, and non-sky terrain samples under forced upload failure.
55. Done 2026-06-16: reduced GPU upload staging allocation churn with a default-off exact-size `PackedByteArray` stage pool and marker telemetry.
56. Done 2026-06-16: reused the packed-face upload scratch buffer where safe and added an isolated in-place upload gate for the opt-in same-face-count subchunk update path.
57. Done 2026-06-16: prototyped the upload stage pool behind `RUMPELMC_GPU_TERRAIN_UPLOAD_STAGE_POOL=1` without changing default upload behavior.
58. Done 2026-06-16: compared pooled and current upload paths with `scripts/gpu_terrain_upload_stage_pool_gate.sh`; fresh release evidence had movement baseline `850` uploads with pool creates/reuses `0/0`, movement pooled `851` uploads with `8` creates and `843` reuses, and upload failures `0`.
59. Done 2026-06-16: kept the upload stage pool default-off and broadened its gate to movement plus in-place dirty upload evidence; the in-place pooled lane had `853` uploads, `1` in-place upload, `8` stage creates, `845` stage reuses, and zero upload failures/retry/backoff.
60. Done 2026-06-16: recorded the stage-pool invariants in `docs/AGENT_MEMORY.md` and added `scripts/gpu_terrain_upload_stage_pool_load_scaling_gate.sh` for high resident-set baseline/pooled comparison. Baseline must stay disabled, pooled creates must stay below uploads, old summaries without workload/fixture/upload/stage fields must be rejected, and the pool must not be defaulted on without external profiler evidence. Fresh pressure-fixture load-scaling passed both lanes with `2289` subchunks/draws, `6292` faces, zero upload failures, and pooled stage pool `9` creates / `3128` reuses.

## Phase 7: Dirty Updates

61. Document dirty update design.
62. Split full subchunk rebuild from dirty block update.
63. Add dirty subchunk markers.
64. Track dirty region bounds.
65. Prototype minimal dirty subchunk upload behind an env flag.
66. Test dirty bounds.
67. Smoke-test breaking a block.
68. Smoke-test placing a block.
69. Smoke-test repeated edits.
70. Done 2026-06-16: added local-X/Z pressure fixture controls and `scripts/gpu_terrain_pressure_dirty_compare.sh` to smoke-test high-volume edits at chunk border/corner local block `31,31` without reducing view distance or visible quality.

## Phase 8: Dirty Update Correctness

71. Verify neighbor face refresh after edits.
72. Verify collision refresh after edits.
73. Verify shadow proxy refresh after edits.
74. Done 2026-06-16: verified opt-in GPU slot reuse after same-face-count dirty edits with `scripts/gpu_terrain_in_place_upload_gate.sh`; mismatched face counts still fall back to the existing remove/allocate/insert path.
75. Done 2026-06-16: compared full-rebuild rollback and partial-dirty lanes under the same `chunk_disc` pressure fixture; full stayed partial-disabled and partial produced edge-neighbor refresh plus saved subchunks.
76. Done 2026-06-16: added dirty pressure compare summary fields for fixture identity, dirty blocks, partial subchunks, saved subchunks, edge-neighbor chunks/subchunks, last bounds/edges, collision refresh, current collision, ground misses, and CPU-side budgets.
77. Make dirty update default only after stable parity.
78. Keep dirty update rollback env.
79. Done 2026-06-16: recorded stable dirty pressure invariants in `docs/AGENT_MEMORY.md`, `docs/GPU_TERRAIN_LOAD_SCALING.md`, `docs/GPU_PROFILING.md`, and `docs/GPU_TRENDS.md`.
80. Update handoff docs.

## Phase 9: Draw Submission

81. Audit indirect draw layout.
82. Remove or justify unused draw command fields.
83. Verify draw command alignment.
84. Log draw command buffer size.
85. Done 2026-06-16: researched grouped indirect draw submission against Godot `RenderingDevice`, Metal resource/upload guidance, Vulkan staging-buffer practice, and D3D12 upload/resource guidance.
86. Done 2026-06-16: prototyped grouped indirect draw records behind `RUMPELMC_GPU_TERRAIN_GROUPED_DRAWS=1`; unset/`0` keeps the current one-record-per-subchunk path and incremental draw-command patching.
87. Done 2026-06-16: added pure Rust coverage for contiguous face-range grouping, gap preservation, deterministic face-range sorting, draw-capacity truncation, and default-off flag behavior.
88. Done 2026-06-16: added `scripts/gpu_terrain_grouped_draws_gate.sh` to compare baseline and grouped pressure workload lanes with equal logical workload, reduced indirect records/bytes, zero upload failures, current collision, terrain samples, and queue/process/submit budgets.
89. Keep grouped draws default-off until equal parity, broader runtime stability, and external macOS/Windows profiler evidence justify rollout.
90. Record draw submission decisions.

## Phase 10: Binding And Frame Data

91. Done: audited atlas/material binding churn and found current runtime creates immutable terrain atlas/uniform resources once per GPU terrain buffer pool.
92. Done: verified atlas sampler and texture reuse with runtime markers and resource lifecycle audit gates.
93. Done: verified uniform set recreation frequency with movement/workload markers; default movement keeps `gpu_uniform_set_create=1`.
94. Done: immutable face-buffer/atlas/sampler bindings are cached in `GpuTerrainRenderPipeline`; scene targets are reused unless the scene RID/view signature changes.
95. Done: audited push constants as `64` camera/projection bytes, `32` lighting bytes, and `16` atlas-layout bytes.
96. Done: recorded that atlas layout remains in push constants for runtime atlas validation; moving it to immutable data needs focused profiler justification because constants phase is currently tiny.
97. Done 2026-06-16: reduced per-frame push-constant packing allocation by replacing the hot-path `Vec<u8>` builder with a fixed `[u8; 112]` byte array while preserving shader byte layout.
98. Done: binding churn metrics are exposed in runtime markers, movement/workload summaries, aggregate reports, and lifecycle audits.
99. Done: frame-data metrics expose push-constant update count, total bytes, average bytes, and camera/lighting/atlas byte split.
100. Done 2026-06-16: recorded binding/frame-data invariants in profiling docs, memory, trends, and handoff evidence.

## Phase 11: Shader Hot Path

101. Done 2026-06-16: audited render shader branch sites; face-dependent normal, UV, corner, and signed-coordinate unpack paths are covered by Rust source-contract tests.
102. Done 2026-06-16: simplified the shader hot path with branchless lookup tables for face normals, tiled UVs, face corners, signed 16-bit chunk/subchunk coordinate unpack, direct reads of Rust-sanitized lighting push constants, vertex-stage atlas tile-offset precompute, `flat` per-face tile-offset/lighting varyings, and global triangle corner indices while preserving packed-face layout.
103. Done: atlas UV parity is covered by the parity smoke summary contract and the render shader tiled-UV source contract.
104. Done: lighting parity is covered by default and low-angle lighting parity gates plus the render shader lighting handoff contract.
105. Done: depth parity is covered by atlas/depth parity evidence and the reverse-Z `GREATER_OR_EQUAL` depth-state unit guard.
106. Done: shadow proxy parity is covered by the lighting/shadow, compact-shadow, low-angle compact-shadow, disabled-shadow, and native-shadow fallback parity gates.
107. Done: no alternate shader env variant is retained; the measured branchless path is the single current render shader path, and future variants require profiler justification.
108. Done: stale branchy shader variants were removed rather than kept behind flags because parity and runtime smoke evidence supported the branchless path.
109. Done: shader assumptions are recorded in `docs/GPU_PROFILING.md`, `docs/AGENT_MEMORY.md`, and the Rust shader source-contract tests.
110. Done 2026-06-16: profiling docs and trend notes record the current branchless shader findings, parity evidence, and remaining external profiler caveat.

## Phase 12: Larger GPU Directions

111. Done 2026-06-16: added `scripts/shadow_proxy_cost_decision_gate.sh` to consolidate shadow quality, radius-matrix proxy counters, pending capture-pack state, and optional validated external profiler results into an explicit shadow-cost decision. Current no-results decision is `defer_runtime_change`.
112. Design GPU-native terrain shadow path. See `docs/GPU_SHADOW_PATH.md`.
113. Prototype shadow proxy reduction without disabling shadows.
114. Add shadow correctness smoke.
115. Done 2026-06-16: transparent block GPU path design is recorded in `docs/GPU_TRANSPARENT_PATH.md`, with opaque rollback, material/collision separation, fixture gates, and external-profiler requirements.
116. Done 2026-06-16: added `scripts/transparent_prototype_shape_decision_gate.sh` to choose `cutout_only_first` as the first prototype shape while keeping split buffers and full blended alpha deferred until active workload, sorting/depth, and profiler evidence exist.
117. Done 2026-06-16: added the default-off `RUMPELMC_GPU_TERRAIN_CUTOUT_PROTOTYPE=1` leaf cutout alpha-test prototype behind the existing GPU terrain opaque pass. Fresh release block-edit smoke placed block ID `5` and passed with `transparent_requested=1`, `transparent_active=1`, `transparent_fallback=0`, `transparent_blocks=1`, `transparent_faces=5`, `transparent_draws=1`, `transparent_subchunks=1`, and `gpu_upload_fail=0`. Full blended transparency, split transparent buffers, sorting, and any default-on behavior remain deferred until parity/depth, external profiler, and Windows validation evidence are captured.
118. Done 2026-06-16: added `scripts/gpu_terrain_cutout_prototype_acceptance_gate.sh` and aggregate report surfacing for `transparent-cutout-prototype-acceptance-summary.txt`, so the default-off leaf cutout runtime smoke is accepted only when block ID `5`, active cutout workload, zero fallback, zero upload failures, `GPU_TERRAIN_TRANSPARENT_IMPLEMENTED=false`, and no blended/sorted/default-on claim all hold.
119. Done 2026-06-16: added `scripts/gpu_terrain_cutout_pressure_load_scaling_gate.sh` and workload/resident/load-scaling summary propagation for cutout fixture block IDs plus transparent workload maxima. Fresh default-off cutout pressure evidence used `chunk_disc` with block ID `5` and passed with `1859` GPU subchunks/draws, `3712` faces, `22.693%` draw-command occupancy, `709` transparent blocks, `1590` transparent faces, `265` transparent draws/subchunks, `265` cutout uploads, `25440` cutout upload bytes, zero upload failures, no transparent sort work, `transparent_build_envelope_ms=1.994`, and queue/process/submit budgets below `6.667ms`; default-on remains blocked pending external profiler plus Windows validation.
120. Done 2026-06-16: added `scripts/gpu_terrain_cutout_fixture_scene_smoke.sh` plus `scripts/gpu_terrain_cutout_fixture_acceptance_gate.sh` for active cutout fixture-scene evidence. Fresh default-off cutout fixture smoke placed four leaf/cutout roles plus one opaque occluder and passed with `cutout_fixture_roles=5`, `cutout_fixture_leaf_blocks=4`, `cutout_fixture_opaque_blocks=1`, `cutout_fixture_dirty_observed=1`, `cutout_fixture_collision_hits=5`, `cutout_fixture_collision_misses=0`, `cutout_fixture_occlusion_probe_hit=1`, `transparent_requested=1`, `transparent_active=1`, `transparent_fallback=0`, `transparent_blocks=4`, `transparent_faces=17`, `transparent_draws=2`, `transparent_subchunks=2`, and `gpu_upload_fail=0`. This is local macOS/Metal cutout depth/collision evidence only; blended transparency, split transparent buffers, sorting, default-on, external profiler, and Windows validation remain deferred.
121. Done 2026-06-16: tightened the cutout fixture smoke and acceptance gate into a same-material adjacent seam/culling sentinel. Fresh evidence requires `cutout_fixture_adjacent_pair_blocks=2`, `cutout_fixture_adjacent_pair_block_id=5`, `cutout_fixture_adjacent_pair_same_material=1`, `cutout_fixture_adjacent_pair_neighbor=1`, `cutout_fixture_adjacent_pair_collision_hits=2`, exact cutout workload `transparent_blocks=4`, `transparent_faces=17`, `transparent_draws=2`, `transparent_subchunks=2`, and `same_material_seam_policy=cutout_pair_visible_faces`; the Rust unit `cutout_prototype_keeps_same_material_adjacent_seam_faces_visible` locks the two-leaf face counts at default `6/0` and cutout `8/8`. This is cutout seam/culling proof only, not blended transparency sorting or default-on approval.
122. Done 2026-06-16: added cutout upload telemetry for the default-off transparent-family prototype. Runtime markers now expose `transparent_cutout_uploads`, full payload bytes, cutout face counts, cutout face bytes, and last-upload values; terrain queue telemetry now exposes cutout upload slot/count KiB and logical cutout-face KiB; workload/resident/load-scaling summaries, fixture/prototype/pressure gates, and V1/V2 reports surface and validate those fields. Fresh pressure evidence reported `transparent_cutout_uploads=285`, `transparent_cutout_upload_bytes=27360`, `transparent_cutout_upload_faces=1710`, and `transparent_cutout_upload_face_bytes=27360`. This is upload evidence inside the existing opaque-pass packed terrain buffer, not a split transparent buffer or default-on approval.
123. In progress 2026-06-16: shader profiler capture pack now emits macOS Metal and Windows GPU capture rows, and `scripts/gpu_shader_profiler_results_check.sh` validates captured rows for the current render shader hot path; full cross-platform validation still needs real external profiler artifacts.
124. Keep a trend log for important GPU metrics.
125. Checkpoint the roadmap and choose the next bottleneck from data.

## 100-Week Long Horizon Plan

This long-horizon plan is a rolling GPU program, not a promise to follow stale details blindly. Re-check it every 4 weeks against fresh reports, profiler evidence, and current gameplay priorities. Each week should still land as a small, reversible slice with its own artifact and trend entry.

### Weeks 1-10: Measurement And Memory Groundwork

1. Done 2026-06-14: refreshed the aggregate GPU report on current native-shadow checkpoint evidence and removed the stale-report assumption from handoff.
2. Done 2026-06-14: captured fresh release movement, standard workload matrix, and fill-stress repeats `1/4/8` under `logs/week2_gpu_baseline_20260614`.
3. Done 2026-06-14: refreshed dirty-update default-on single-edge evidence under `logs/week2_gpu_dirty_default_on_20260614`.
4. Done 2026-06-14: fixed dirty-only aggregate report terrain queue diagnostics so `movement_terrain_queue max_ms` is surfaced with an origin.
5. Done 2026-06-14: checkpointed dirty-update default-on status, explicit rollback flag behavior, project memory, handoff state, and trend entry.
6. Done 2026-06-14: refreshed GPU allocator fragmentation, largest-free-range, and failure-cause telemetry in stress summaries and aggregate reports.
7. Done 2026-06-14: added allocator stress gate wrapper over scoped GPU reports with upload-failure, failure-cause, free-range, largest-free, and fragmentation checks.
8. Done 2026-06-14: designed a safe GPU terrain buffer repack behind an explicit rollback flag in `docs/GPU_BUFFER_REPACK.md`.
9. Done 2026-06-14: prototyped buffer repack foundation behind that flag with marker-only telemetry, report aggregation, and deterministic planner tests; runtime buffer replacement remains intentionally unimplemented.
10. Done 2026-06-14: added CPU-owned resident packed-face source bytes, deterministic compact payload preview, explicit one-shot temporary replacement-buffer upload/binding preview, draw-command remap preview, all-or-nothing staged swap guard, disabled commit-point proof, disabled apply scaffold, and disabled final-swap guard behind the repack flag, with source/payload/upload/bind/draw/stage/commit/apply/final-guard readiness telemetry and missing-source/source-size/upload-error/bind/draw-error validation; active render binding, indirect-buffer swap, slot mutation, and allocator mutation remain intentionally unimplemented.

### Weeks 11-20: Upload And Draw Submission

11. Audit CPU copies before GPU upload.
12. Add or refresh upload queue-depth and latency telemetry.
13. Split initial chunk upload and block-update upload in summaries.
14. Add upload budget gates and focused tests.
15. Prototype an upload pool only if staging churn evidence justifies it.
16. Audit indirect draw command layout and command-buffer occupancy.
17. Run a heavy draw-pressure workload matrix.
18. Prototype grouped draws behind an explicit rollback flag if evidence justifies it.
19. Compare grouped draws and current draws on the workload matrix.
20. Keep or drop grouped draws, then record the decision.

### Weeks 21-30: Binding, Shader, Shadow, And Transparent Fixture Setup

21. Clean up binding/frame data only where measured churn justifies it.
22. Done 2026-06-16: prepared `scripts/gpu_shader_profiler_capture_pack.sh` for the current branchless shader path. It validates the latest movement summary, source-level shader contracts, and emits pending macOS Metal plus Windows GPU profiler rows without treating the checklist as profiler evidence.
23. Done 2026-06-16: added `scripts/gpu_shader_profiler_results_check.sh` and report surfacing for captured shader profiler rows; no real external rows are present yet, so profiler status remains pending.
24. Done 2026-06-16: shadow proxy cost decisions now go through `scripts/shadow_proxy_cost_decision_gate.sh`; without validated external profiler rows the required decision is `defer_runtime_change`.
25. Checkpoint the shadow path; keep native shadow work behind a rollback flag.
26. Build the first transparent fixture scene harness without enabling transparent rendering.
27. Add transparent workload telemetry fields for blocks, faces, draws, and subchunks.
28. Done 2026-06-16: first transparent prototype shape decision is `cutout_only_first`; active/default runtime changes remain disallowed while `GPU_TERRAIN_TRANSPARENT_IMPLEMENTED=false`.
29. Build the first transparent prototype behind an explicit rollback flag.
30. Done 2026-06-16: checkpointed default-off leaf cutout prototype evidence under high resident-set pressure with `scripts/gpu_terrain_cutout_pressure_load_scaling_gate.sh`; next transparent bottleneck is real fixture-scene active/depth/collision evidence or external profiler capture, not default-on.

### Weeks 31-40: Transparent Terrain Hardening

31. Refresh opaque parity with transparent features disabled.
32. Done 2026-06-16: added active cutout fixture visual smoke plus report-backed acceptance for default-off leaf/cutout roles.
33. Done 2026-06-16: added an opaque occlusion probe for the cutout fixture smoke; per-pixel blended transparency sorting remains future work.
34. Done 2026-06-16: added collision-by-solidity fixture evidence with five cutout/opaque role ray checks.
35. Done 2026-06-16: added a same-material cutout adjacent-pair seam/culling gate by requiring exact fixture roles/workload and a Rust mesher proof that adjacent cutout leaves keep internal seam faces.
36. Done 2026-06-16: add transparent/cutout upload metrics across runtime markers, queue telemetry, summaries, gates, and reports.
37. Done 2026-06-16: added transparent sort/build cost metrics for the default-off cutout prototype. Runtime markers, fixture/prototype/pressure summaries, V1/V2 reports, and `scripts/transparent_cutout_sort_build_cost_gate.sh` now surface `transparent_sort_policy=opaque_depth_alpha_test_no_sort`, zero sort work, `transparent_build_cost_source=cutout_in_opaque_mesh_phase`, build face/subchunk envelope, and matching cutout upload cost counters. This is cutout-in-opaque-pass CPU-side evidence only, not blended transparency sorting, a split transparent buffer, default-on approval, external profiler proof, or Windows validation.
38. Capture macOS external profiler evidence for the transparent fixture workload.
39. Add at least one non-macOS validation path before broad enablement.
40. Decide whether the transparent prototype stays default-off, advances, or is dropped.

### Weeks 41-50: Shadow Path

41. Refresh the shadow proxy workload matrix.
42. Refresh compact proxy focused cost evidence.
43. Update the GPU-native shadow design from current measurements.
44. Prototype native shadow behavior behind an explicit rollback flag if justified.
45. Add shadow visual parity.
46. Add shadow depth and lighting parity.
47. Capture external profiler evidence for the shadow path.
48. Compare native and current shadow paths.
49. Harden rollback and fallback behavior.
50. Keep, drop, or defer the native shadow path.

### Weeks 51-60: Residency And Streaming

51. Refresh resident chunk pressure baselines.
52. Done 2026-06-16: refreshed chunk enter/exit stress and wired it into report V1/V2 plus the test strategy gate.
53. Done 2026-06-16: refreshed rapid camera-turn stress and wired the summary into the aggregate report plus test strategy gate.
54. Done 2026-06-16: added the GPU stress artifact index to keep current max resident subchunks/draws/faces, draw-command occupancy, upload failures, and pending profiler/Windows gaps visible in one summary.
55. Done 2026-06-16: added `scripts/gpu_chunk_unload_churn_diagnosis.sh` as a summary-only unload/reload churn diagnosis over current chunk-boundary evidence, with optional strict default/immediate teleport controls.
56. Define a buffer residency budget.
57. Audit streaming priority behavior.
58. Prototype scheduler changes behind a rollback flag if evidence justifies them.
59. Compare scheduler variants on the workload matrix.
60. Checkpoint streaming and residency decisions.

### Weeks 61-70: World Interaction Performance

61. Refresh block-edit stress.
62. Benchmark repeated edits.
63. Benchmark border edits.
64. Refresh dirty partial-upload edge cases.
65. Audit collision refresh cost.
66. Audit shadow proxy refresh cost.
67. Add edit-burst budget gates.
68. Add edit visual parity where needed.
69. Integrate edit workload evidence into the aggregate report.
70. Checkpoint world interaction performance.

### Weeks 71-80: Cross-Platform And Quality Guards

71. Refresh macOS Metal capture evidence.
72. Prepare Windows RenderDoc or PIX capture flow.
73. Add a Linux/Vulkan smoke path if the backend is available.
74. Compare marker parity across backends.
75. Audit atlas sampling quality.
76. Verify lighting quality parity.
77. Verify shadow quality parity.
78. Add texture-quality guards.
79. Document backend-specific fallback rules.
80. Checkpoint cross-platform GPU readiness.

### Weeks 81-90: Evidence-Led Optimization

81. Select the top bottleneck from current data.
82. Prototype one optimization behind a rollback flag.
83. Add explicit rollback and path markers.
84. Run narrow correctness gates.
85. Run workload comparison.
86. Run profiler comparison where required.
87. Keep or drop the optimization.
88. Record any stable invariant.
89. Remove dropped prototype paths when safe.
90. Checkpoint the optimization round.

### Weeks 91-100: Default-On Decisions And Roadmap Refresh

91. Audit all GPU env flags.
92. Audit report and trend coverage.
93. Audit stale logs and stale evidence references.
94. Consolidate GPU docs.
95. Run broad checks where practical.
96. Run diff guard and sensitive review.
97. Review default-on candidates.
98. Roll out or defer default-on candidates based on evidence.
99. Rewrite the long-horizon roadmap from current measurements.
100. Checkpoint the 100-week program and choose the next bottleneck.
