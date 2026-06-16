# GPU Terrain Repeated Edit Benchmark

Date: 2026-06-16

Scope: repeated world-interaction benchmark for GPU terrain dirty updates. This gate composes the existing single-edge and corner-edge dirty repeat harnesses into one summary artifact. It does not change default runtime behavior, partial dirty policy, upload capacity, allocator policy, draw distance, lighting, shadows, texture quality, visible quality, protocol, storage, world generation, or chunk serialization.

## Command

Use existing captured repeat summaries:

```sh
sh scripts/gpu_terrain_repeated_edit_benchmark.sh logs/gpu_terrain_repeated_edit_benchmark_current
```

Capture fresh repeat lanes first:

```sh
RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE=1 \
RUMPELMC_GODOT_RUST_EXT_PROFILE=release \
RUMPELMC_REPEATED_EDIT_BENCHMARK_RUN_REPEATS=1 \
sh scripts/gpu_terrain_repeated_edit_benchmark.sh logs/gpu_terrain_repeated_edit_benchmark_current
```

The script writes:

- `gpu-terrain-repeated-edit-benchmark-summary.txt`
- `gpu-terrain-repeated-edit-benchmark-cases.txt`

## Inputs

Default source summaries:

- `logs/gpu_single_edge_dirty_repeat_current/edge-dirty-repeat-summary.txt`
- `logs/gpu_edge_dirty_repeat_current/edge-dirty-repeat-summary.txt`

The single-edge lane validates repeated edits at global `127,64,80`, expected `pos_x`, and bounds `31,64,16:31,64,16`.

The corner-edge lane validates repeated edits at global `127,64,95`, expected `pos_x,pos_z`, and bounds `31,64,31:31,64,31`.

## Validation

The benchmark requires:

- at least `3` runs per lane by default
- every run status to pass
- aggregate repeat status to pass
- zero GPU upload failures
- expected dirty edge and bounds identity
- repeated edge-neighbor refresh evidence
- repeated partial dirty saved-subchunk evidence
- terrain queue max, process wall p95, and compositor submit max under the `150 FPS` CPU-side budget
- `scheduler_change_allowed=0`
- `default_runtime_change_allowed=0`
- `visible_quality_change_allowed=0`
- external profiler and macOS/Windows validation blockers to remain explicit

## Fresh Evidence

Fresh local evidence:

- `logs/gpu_single_edge_dirty_repeat_current/edge-dirty-repeat-summary.txt`
- `logs/gpu_edge_dirty_repeat_current/edge-dirty-repeat-summary.txt`
- `logs/gpu_terrain_repeated_edit_benchmark_current/gpu-terrain-repeated-edit-benchmark-summary.txt`
- `logs/gpu_terrain_repeated_edit_benchmark_current/gpu-terrain-repeated-edit-benchmark-cases.txt`

The current benchmark passed with:

- `case_count=2`
- `pass_cases=2`
- `single_edge_runs=3`
- `corner_edge_runs=3`
- `min_dirty_edge_neighbor_subchunks=4`
- `min_dirty_partial_saved_subchunks=2`
- `max_terrain_queue_ms=2.972`
- `max_process_wall_p95_ms=0.050`
- `max_gpu_compositor_submit_ms=0.150`
- `gpu_upload_fail=0`
- `default_runtime_change_allowed=0`
- `visible_quality_change_allowed=0`
- `external_profile_status=pending_external_profiler`
- `requires_mac_windows_validation=1`

This is repeated edit budget evidence only. It does not replace high-resident load scaling, pressure dirty full-vs-partial comparison, collision refresh cost audit, external profiler rows, or Windows validation.

## External Context

- Godot's 3D optimization guidance frames visibility, LOD, occlusion, and draw-call pressure as workload-specific performance controls: <https://docs.godotengine.org/en/latest/tutorials/performance/optimizing_3d_performance.html>
- Godot `RenderingDevice` remains backend-sensitive, so local CPU-side queue and submit budgets are not a replacement for external GPU profiler rows: <https://docs.godotengine.org/en/stable/classes/class_renderingdevice.html>
