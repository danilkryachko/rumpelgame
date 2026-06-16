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
- streaming priority audit
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

Missing optional rows keep the index visible but do not fail it. This prevents silent evidence gaps while still allowing focused GPU work on a checkout that does not have every historical log.

## Fresh Evidence

Fresh local evidence:

- `logs/gpu_stress_artifact_index_current/gpu-stress-artifact-index-summary.txt`
- `logs/gpu_stress_artifact_index_current/gpu-stress-artifact-index.txt`

The current index passed with `26` rows, `17` required rows, `17` required passes, `8` optional missing rows, zero upload-failure violations, zero ground-miss violations, zero default-runtime-change violations, and zero scheduler-change violations.

Current normalized maxima:

- GPU subchunks/draws/faces: `2482` / `2482` / `6292`
- Draw-command occupancy: `30.298%`
- Buffer residency pressure: `high`
- Streaming priority proof: `partial`
- Source priority contracts: `pass`
- Runtime priority status: `pass`
- Upload fallback expected/injected failures: `1052` / `1052`
- Upload fallback shadow path: `arraymesh`
- Configured buffer bytes/budget: `67239936` / `95.709%`
- Active face bytes/budget: `100672` / `2.400%`
- Logical/submitted draw records: `2482` / `2482`
- Draw-command headroom: `91360` bytes
- Terrain queue max: `3.928ms`
- Process wall p95: `0.059ms`
- Compositor submit max: `5.677ms`
- Packet queue lag max: `27.437ms`
- Cutout uploads: `265`
- Cutout build envelope: `2.121ms`
- Stage-pool reuses: `3128`
- Grouped draw saved records: `2174`

The summary explicitly records `external_profiler_status=pending_external_profiler`, `mac_windows_validation_status=pending_external_validation`, `local_fps_status=report_only`, and `godot_gpu_timestamp_status=report_only`.

## Report And Strategy Wiring

- `scripts/gpu_terrain_report.sh` surfaces the selected GPU stress artifact index summary and index rows.
- `scripts/gpu_terrain_report.sh` surfaces the selected GPU streaming priority audit summary when present.
- `scripts/gpu_terrain_report.sh` also surfaces the selected GPU buffer residency budget summary when present.
- `scripts/test_strategy_gate.sh` requires the index summary and includes the index command in the nightly summary command.
- `scripts/test_strategy_gate.sh` requires the streaming priority audit summary before the index.
- `scripts/test_strategy_gate.sh` requires the buffer residency budget summary before the index.
- `docs/GPU_ROADMAP.md` uses this to close the Phase 3 stress artifact index item and keeps the residency/streaming unload diagnosis, streaming priority audit, upload-failure fallback, and buffer residency budget visible as required rows.

## External Context

- Godot's [3D optimization guide](https://docs.godotengine.org/en/latest/tutorials/performance/optimizing_3d_performance.html) recommends visibility, occlusion, LOD, and large-world strategies for complex 3D scenes. This index records whether our current world-loading/rendering gates have enough evidence before changing those controls.
- Godot [`RenderingDevice`](https://docs.godotengine.org/en/stable/classes/class_renderingdevice.html) exposes GPU timestamp capture APIs, but the local macOS/Metal path in this project still reports zero GPU timestamp samples; the index therefore keeps those fields report-only until real external profiler rows exist.
- Godot's [large world coordinates](https://docs.godotengine.org/en/stable/tutorials/physics/large_world_coordinates.html) documentation calls out precision for large worlds. This index does not change coordinate policy; it keeps the existing chunk/residency evidence visible before any future large-world or origin-management work.
