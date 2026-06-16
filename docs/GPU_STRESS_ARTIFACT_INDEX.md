# GPU Stress Artifact Index

Date: 2026-06-16

Scope: summary-only index for current GPU terrain stress evidence. The index keeps world loading, residency, upload, draw submission, transparent/cutout, shader-profiler handoff, and governance artifacts visible in one compact file. It does not change rendering behavior, draw distance, camera far plane, lighting, shadows, texture quality, visible quality, protocol, storage, world generation, or chunk serialization.

## Command

Use:

```sh
sh scripts/gpu_stress_artifact_index.sh logs/gpu_stress_artifact_index_current
```

The script writes:

- `gpu-stress-artifact-index-summary.txt`
- `gpu-stress-artifact-index.txt`

## Required Evidence

The current required GPU core rows are:

- rapid camera-turn gate and its movement source summary
- chunk-boundary gate and its high-pressure suite source summary
- chunk unload churn diagnosis
- repeated edit benchmark
- border edit benchmark
- partial dirty edge matrix
- streaming priority audit
- streaming scheduler prototype preflight
- streaming scheduler workload matrix
- streaming scheduler tie probe
- streaming scheduler decision checkpoint
- upload-failure fallback expected-failure artifact
- strict load-scaling gate and its resident-set source summary
- mass chunk-load gate
- buffer residency budget gate
- upload budget gate
- upload stage-pool load-scaling gate
- grouped draw gate
- cutout pressure gate
- cutout fixture acceptance gate
- transparent cutout sort/build cost gate

The index fails if any required row is missing, has a non-pass status, reports nonzero normal GPU upload failures, reports nonzero ground misses where that metric exists, allows a default runtime change, or allows a scheduler change. The upload-failure fallback row is an expected-failure artifact: its injected upload failures are surfaced as `expected_gpu_upload_fail` / `expected_gpu_upload_fail_injected`, while the generic `gpu_upload_fail` guard remains `0`.

## Optional Gap Rows

The index also lists optional governance and profiler rows even when they are missing locally:

- exploration soak
- upload pressure and resource lifecycle
- memory budget
- report V2
- performance baseline governance
- test strategy
- external profiling campaign
- shader profiler capture pack
- streaming scheduler boundary matrix

Missing optional rows keep the index visible but do not fail it. This prevents silent evidence gaps while still allowing focused GPU work on a checkout that does not have every historical log.

## Fresh Evidence

Fresh local evidence:

- `logs/gpu_stress_artifact_index_current/gpu-stress-artifact-index-summary.txt`
- `logs/gpu_stress_artifact_index_current/gpu-stress-artifact-index.txt`

The current index passed with `34` rows, `24` required rows, `24` required passes, `9` optional missing rows, zero upload-failure violations, zero ground-miss violations, zero default-runtime-change violations, and zero scheduler-change violations.

Current normalized maxima:

- GPU subchunks/draws/faces: `2482` / `2482` / `6292`
- Draw-command occupancy: `30.298%`
- Buffer residency pressure: `high`
- Streaming priority proof: `partial`
- Source priority contracts: `pass`
- Runtime priority status: `pass`
- Repeated edit benchmark: `case_count=2`, `single_edge_runs=3`, `corner_edge_runs=3`, `gpu_upload_fail=0`
- Border edit benchmark: `case_count=3`, `pressure_local=31,31`, `max_dirty_blocks=709`, `max_dirty_edge_neighbor_subchunks=2836`, `gpu_upload_fail=0`
- Partial dirty edge matrix: `case_count=8`, `single_edge_cases=4`, `corner_edge_cases=4`, `max_partial_edge_neighbor_subchunks=8`, `gpu_upload_fail=0`
- Streaming scheduler prototype: `prototype_only`
- Streaming scheduler workload matrix: `matrix_harness_status=partial`, `candidate_scheduler_status=defer_matrix_harness_unstable`, `scheduler_change_allowed=0`
- Streaming scheduler tie probe: `runtime_signal=312`, `candidate_scheduler_status=stable_tie_probe_external_profiler_required`, `scheduler_change_allowed=0`
- Streaming scheduler decision checkpoint: `decision_status=defer_matrix_harness_unstable`, `scheduler_change_allowed=0`
- Upload fallback expected/injected failures: `1052` / `1052`
- Upload fallback shadow path: `arraymesh`
- Configured buffer bytes/budget: `67239936` / `95.709%`
- Active face bytes/budget: `100672` / `2.400%`
- Logical/submitted draw records: `2482` / `2482`
- Draw-command headroom: `91360` bytes
- Terrain queue max: `6.174ms`
- Process wall p95: `0.070ms`
- Compositor submit max: `5.677ms`
- Packet queue lag max: `67.578ms`
- Cutout uploads: `265`
- Cutout build envelope: `2.121ms`
- Stage-pool reuses: `3128`
- Grouped draw saved records: `2174`

The summary explicitly records `external_profiler_status=pending_external_profiler`, `mac_windows_validation_status=pending_external_validation`, `local_fps_status=report_only`, and `godot_gpu_timestamp_status=report_only`.

## Report And Strategy Wiring

- `scripts/gpu_terrain_report.sh` surfaces the selected GPU stress artifact index summary and index rows.
- `scripts/gpu_terrain_report.sh` surfaces the selected GPU terrain repeated edit benchmark summary and case rows when present.
- `scripts/gpu_terrain_report.sh` surfaces the selected GPU terrain border edit benchmark summary and case rows when present.
- `scripts/gpu_terrain_report.sh` surfaces the selected GPU terrain partial dirty edge matrix summary and case rows when present.
- `scripts/gpu_terrain_report.sh` surfaces the selected GPU streaming priority audit summary when present.
- `scripts/gpu_terrain_report.sh` surfaces the selected GPU streaming scheduler prototype summary when present.
- `scripts/gpu_terrain_report.sh` surfaces the selected GPU streaming scheduler workload matrix summary and case rows when present.
- `scripts/gpu_terrain_report.sh` surfaces the selected GPU streaming scheduler tie probe summary when present.
- `scripts/gpu_terrain_report.sh` surfaces the selected GPU streaming scheduler decision checkpoint summary when present.
- `scripts/gpu_terrain_report.sh` surfaces optional GPU streaming scheduler boundary matrix summary and case rows when present.
- `scripts/gpu_terrain_report.sh` also surfaces the selected GPU buffer residency budget summary when present.
- `scripts/test_strategy_gate.sh` requires the index summary and includes the index command in the nightly summary command.
- `scripts/test_strategy_gate.sh` requires the repeated edit benchmark summary before the index.
- `scripts/test_strategy_gate.sh` requires the border edit benchmark summary before the index.
- `scripts/test_strategy_gate.sh` requires the partial dirty edge matrix summary before the index.
- `scripts/test_strategy_gate.sh` requires the streaming priority audit summary before the index.
- `scripts/test_strategy_gate.sh` requires the streaming scheduler prototype summary before the index.
- `scripts/test_strategy_gate.sh` requires the streaming scheduler workload matrix summary before the index.
- `scripts/test_strategy_gate.sh` requires the streaming scheduler tie probe summary before the index.
- `scripts/test_strategy_gate.sh` requires the streaming scheduler decision checkpoint summary before the index.
- `scripts/test_strategy_gate.sh` requires the buffer residency budget summary before the index.
- `docs/GPU_ROADMAP.md` uses this to close the Phase 3 stress artifact index item and keeps the residency/streaming unload diagnosis, repeated edit benchmark, border edit benchmark, partial dirty edge matrix, streaming priority audit, streaming scheduler prototype, streaming scheduler workload matrix, streaming scheduler decision checkpoint, upload-failure fallback, and buffer residency budget visible as required rows.

## External Context

- Godot's [3D optimization guide](https://docs.godotengine.org/en/latest/tutorials/performance/optimizing_3d_performance.html) recommends visibility, occlusion, LOD, and large-world strategies for complex 3D scenes. This index records whether our current world-loading/rendering gates have enough evidence before changing those controls.
- Godot [`RenderingDevice`](https://docs.godotengine.org/en/stable/classes/class_renderingdevice.html) exposes GPU timestamp capture APIs, but the local macOS/Metal path in this project still reports zero GPU timestamp samples; the index therefore keeps those fields report-only until real external profiler rows exist.
- Godot's [large world coordinates](https://docs.godotengine.org/en/stable/tutorials/physics/large_world_coordinates.html) documentation calls out precision for large worlds. This index does not change coordinate policy; it keeps the existing chunk/residency evidence visible before any future large-world or origin-management work.
