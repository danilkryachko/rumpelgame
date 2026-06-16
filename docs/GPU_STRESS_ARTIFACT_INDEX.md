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
- strict load-scaling gate and its resident-set source summary
- mass chunk-load gate
- upload budget gate
- upload stage-pool load-scaling gate
- grouped draw gate
- cutout pressure gate
- cutout fixture acceptance gate
- transparent cutout sort/build cost gate

The index fails if any required row is missing, has a non-pass status, reports nonzero GPU upload failures, reports nonzero ground misses where that metric exists, or allows a default runtime change.

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

The current index passed with `22` rows, `13` required rows, `13` required passes, `8` optional missing rows, zero upload-failure violations, zero ground-miss violations, and zero default-runtime-change violations.

Current normalized maxima:

- GPU subchunks/draws/faces: `2482` / `2482` / `6292`
- Draw-command occupancy: `30.298%`
- Terrain queue max: `3.928ms`
- Process wall p95: `0.059ms`
- Compositor submit max: `5.677ms`
- Packet queue lag max: `22.405ms`
- Cutout uploads: `265`
- Cutout build envelope: `2.121ms`
- Stage-pool reuses: `3128`
- Grouped draw saved records: `2174`

The summary explicitly records `external_profiler_status=pending_external_profiler`, `mac_windows_validation_status=pending_external_validation`, `local_fps_status=report_only`, and `godot_gpu_timestamp_status=report_only`.

## Report And Strategy Wiring

- `scripts/gpu_terrain_report.sh` surfaces the selected GPU stress artifact index summary and index rows.
- `scripts/test_strategy_gate.sh` requires the index summary and includes the index command in the nightly summary command.
- `docs/GPU_ROADMAP.md` uses this to close the Phase 3 stress artifact index item.

## External Context

- Godot's [3D optimization guide](https://docs.godotengine.org/en/latest/tutorials/performance/optimizing_3d_performance.html) recommends visibility, occlusion, LOD, and large-world strategies for complex 3D scenes. This index records whether our current world-loading/rendering gates have enough evidence before changing those controls.
- Godot [`RenderingDevice`](https://docs.godotengine.org/en/stable/classes/class_renderingdevice.html) exposes GPU timestamp capture APIs, but the local macOS/Metal path in this project still reports zero GPU timestamp samples; the index therefore keeps those fields report-only until real external profiler rows exist.
- Godot's [large world coordinates](https://docs.godotengine.org/en/stable/tutorials/physics/large_world_coordinates.html) documentation calls out precision for large worlds. This index does not change coordinate policy; it keeps the existing chunk/residency evidence visible before any future large-world or origin-management work.
