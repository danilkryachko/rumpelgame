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
28. Add chunk enter/exit stress.
29. Add rapid camera-turn stress.
30. Add a stress artifact index.

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
55. Reduce staging allocation churn.
56. Done 2026-06-16: reused the packed-face upload scratch buffer where safe and added an isolated in-place upload gate for the opt-in same-face-count subchunk update path.
57. Prototype an upload memory pool behind an env flag.
58. Compare pooled and current upload paths.
59. Keep the pool only with better metrics.
60. Record upload invariants in agent memory if they become stable.

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
70. Smoke-test edits near chunk borders.

## Phase 8: Dirty Update Correctness

71. Verify neighbor face refresh after edits.
72. Verify collision refresh after edits.
73. Verify shadow proxy refresh after edits.
74. Done 2026-06-16: verified opt-in GPU slot reuse after same-face-count dirty edits with `scripts/gpu_terrain_in_place_upload_gate.sh`; mismatched face counts still fall back to the existing remove/allocate/insert path.
75. Compare dirty update against full rebuild.
76. Add dirty update perf report.
77. Make dirty update default only after stable parity.
78. Keep dirty update rollback env.
79. Record stable dirty update invariants.
80. Update handoff docs.

## Phase 9: Draw Submission

81. Audit indirect draw layout.
82. Remove or justify unused draw command fields.
83. Verify draw command alignment.
84. Log draw command buffer size.
85. Research grouped draws.
86. Prototype grouped draws behind an env flag.
87. Test grouped draw layout.
88. Compare grouped and current draws on workload matrix.
89. Keep grouped draws only with equal parity and better metrics.
90. Record draw submission decisions.

## Phase 10: Binding And Frame Data

91. Audit atlas/material binding churn.
92. Verify sampler and texture reuse.
93. Verify uniform set recreation frequency.
94. Cache immutable bindings where safe.
95. Audit push constants.
96. Separate static terrain data from per-frame camera/light data.
97. Reduce per-frame constant updates.
98. Add binding churn metrics.
99. Add frame data metrics.
100. Record binding invariants.

## Phase 11: Shader Hot Path

101. Audit shader branches.
102. Simplify shader hot path without changing output.
103. Verify atlas UV parity.
104. Verify lighting parity.
105. Verify depth parity.
106. Verify shadow proxy parity.
107. Compare shader variants behind env flags if needed.
108. Keep only variants with measured benefit.
109. Record shader assumptions.
110. Update profiling docs with shader findings.

## Phase 12: Larger GPU Directions

111. Measure shadow proxy cost.
112. Design GPU-native terrain shadow path. See `docs/GPU_SHADOW_PATH.md`.
113. Prototype shadow proxy reduction without disabling shadows.
114. Add shadow correctness smoke.
115. Design transparent block GPU path. See `docs/GPU_TRANSPARENT_PATH.md`.
116. Split opaque and transparent pass design.
117. Prototype transparent terrain behind an env flag.
118. Add cross-platform GPU validation matrix.
119. Keep a trend log for important GPU metrics.
120. Checkpoint the roadmap and choose the next bottleneck from data.

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
22. Prepare shader profiler capture packs for the current branchless shader path.
23. Integrate validated external profiler results into reports when available.
24. Decide the next shadow proxy optimization from measured cost.
25. Checkpoint the shadow path; keep native shadow work behind a rollback flag.
26. Build the first transparent fixture scene harness without enabling transparent rendering.
27. Add transparent workload telemetry fields for blocks, faces, draws, and subchunks.
28. Decide the first transparent prototype shape: split buffers, cutout-only, or Godot fallback.
29. Build the first transparent prototype behind an explicit rollback flag.
30. Checkpoint transparent fixture/prototype evidence and choose the next bottleneck.

### Weeks 31-40: Transparent Terrain Hardening

31. Refresh opaque parity with transparent features disabled.
32. Add transparent fixture visual smoke.
33. Add opaque-depth occlusion gates for transparent fixtures.
34. Add collision-by-solidity gates.
35. Add same-material transparent seam or culling gates.
36. Add transparent upload metrics.
37. Add transparent sort/build cost metrics.
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
52. Refresh chunk enter/exit stress.
53. Refresh rapid camera-turn stress.
54. Track max-resident memory trends.
55. Diagnose unload/reload churn.
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
