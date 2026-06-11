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
39. Design safe GPU terrain buffer repack.
40. Prototype repack behind an env flag.

## Phase 5: Upload Pipeline

41. Audit CPU copies before GPU upload.
42. Log upload bytes per frame.
43. Log upload count per frame.
44. Log upload queue depth.
45. Log upload latency.
46. Separate initial chunk upload from block-update upload.
47. Add upload budget per frame.
48. Add upload budget tests.
49. Add mass chunk-load stress.
50. Add upload retry/backoff telemetry.

## Phase 6: Upload Robustness

51. Verify upload failure recovery.
52. Keep visual fallback valid after upload failure.
53. Keep shadow fallback valid after upload failure.
54. Keep collision fallback valid after upload failure.
55. Reduce staging allocation churn.
56. Reuse staging buffers where safe.
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
74. Verify GPU slot reuse after edits.
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
112. Design GPU-native terrain shadow path.
113. Prototype shadow proxy reduction without disabling shadows.
114. Add shadow correctness smoke.
115. Design transparent block GPU path.
116. Split opaque and transparent pass design.
117. Prototype transparent terrain behind an env flag.
118. Add cross-platform GPU validation matrix.
119. Keep a trend log for important GPU metrics.
120. Checkpoint the roadmap and choose the next bottleneck from data.
