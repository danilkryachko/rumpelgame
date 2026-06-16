# GPU Terrain Border Edit Benchmark

`scripts/gpu_terrain_border_edit_benchmark.sh` is the current summary gate for chunk-border dirty edit evidence. It composes the repeated single-edge/corner-edge dirty edit benchmark with the high-volume pressure dirty compare at local chunk border `31,31`.

Run:

```sh
sh scripts/gpu_terrain_border_edit_benchmark.sh logs/gpu_terrain_border_edit_benchmark_current
```

Inputs:

- `logs/gpu_terrain_repeated_edit_benchmark_current/gpu-terrain-repeated-edit-benchmark-summary.txt`
- `logs/gpu_terrain_repeated_edit_benchmark_current/gpu-terrain-repeated-edit-benchmark-cases.txt`
- `logs/gpu_terrain_pressure_dirty_compare_current/gpu-terrain-pressure-dirty-compare-summary.txt`

Outputs:

- `logs/gpu_terrain_border_edit_benchmark_current/gpu-terrain-border-edit-benchmark-summary.txt`
- `logs/gpu_terrain_border_edit_benchmark_current/gpu-terrain-border-edit-benchmark-cases.txt`

## Validation

The gate requires:

- repeated single-edge and corner-edge edit summaries to pass with at least three runs each
- exact single-edge surface `pos_x` with bounds `31,64,16:31,64,16`
- exact corner-edge surface `pos_x,pos_z` with bounds `31,64,31:31,64,31`
- pressure dirty compare to pass with `chunk_disc`, `local_x=31`, and `local_z=31`
- full pressure lane to keep partial dirty disabled
- partial pressure lane to report dirty blocks, edge-neighbor refresh, saved partial subchunks, collision, terrain samples, and zero ground misses
- zero normal GPU upload failures
- terrain queue, process wall p95, and compositor submit maxima below the 150 FPS CPU-side frame budget
- `default_runtime_change_allowed=0` and `visible_quality_change_allowed=0`
- external profiler and macOS/Windows validation blockers before default-policy changes

Fresh local evidence:

- `case_count=3`
- `single_edge_runs=3`
- `corner_edge_runs=3`
- `pressure_fixture=chunk_disc`
- `pressure_local_x=31`
- `pressure_local_z=31`
- `max_dirty_blocks=709`
- `min/max dirty_edge_neighbor_subchunks=4/2836`
- `min/max dirty_partial_saved_subchunks=2/1418`
- `max queue/process/submit=4.777/0.050/0.171ms`
- `gpu_upload_fail=0`
- `ground_misses=0`

## External Context

The gate is deliberately evidence-first. Official Godot documentation describes `RenderingDevice` as a lower-level abstraction over modern graphics APIs and exposes buffer update operations, so local gates focus on upload/update pressure rather than local display-limited FPS:

- https://docs.godotengine.org/en/stable/classes/class_renderingdevice.html
- https://docs.godotengine.org/en/latest/classes/class_renderingdevice.html

Apple Metal guidance recommends appropriate resource storage modes and triple buffering for frequently updated dynamic buffers:

- https://developer.apple.com/library/archive/documentation/3DDrawing/Conceptual/MTLBestPracticesGuide/ResourceOptions.html
- https://developer.apple.com/library/archive/documentation/3DDrawing/Conceptual/MTLBestPracticesGuide/TripleBuffering.html

Microsoft Direct3D 12 guidance documents upload heaps, upload-resource workflows, and ring-buffer style fence-based resource management:

- https://learn.microsoft.com/en-us/windows/win32/api/d3d12/ne-d3d12-d3d12_heap_type
- https://learn.microsoft.com/en-us/windows/win32/direct3d12/uploading-resources
- https://learn.microsoft.com/en-us/windows/win32/direct3d12/fence-based-resource-management

Vulkan documentation describes staging buffers for transferring CPU data into device-local resources:

- https://docs.vulkan.org/tutorial/latest/04_Vertex_buffers/02_Staging_buffer.html

This benchmark is local macOS/Metal CPU-side budget evidence only. It does not replace edit-burst budget gates, collision refresh cost audit, shadow proxy refresh cost audit, visual parity, external profiler rows, or Windows/Vulkan/Direct3D validation.
