# GPU Terrain Partial Dirty Edge Matrix

`scripts/gpu_terrain_partial_dirty_edge_matrix.sh` is the current runtime edge-case gate for partial dirty uploads across all chunk border directions. It composes existing full-vs-partial dirty compares from `scripts/gpu_terrain_edge_dirty_compare.sh` and keeps the full-rebuild rollback lane visible for every case.

Run from existing summaries:

```sh
sh scripts/gpu_terrain_partial_dirty_edge_matrix.sh logs/gpu_terrain_partial_dirty_edge_matrix_current
```

Refresh all runtime cases:

```sh
RUMPELMC_PARTIAL_DIRTY_EDGE_MATRIX_RUN_CASES=1 \
  sh scripts/gpu_terrain_partial_dirty_edge_matrix.sh logs/gpu_terrain_partial_dirty_edge_matrix_current
```

Outputs:

- `logs/gpu_terrain_partial_dirty_edge_matrix_current/gpu-terrain-partial-dirty-edge-matrix-summary.txt`
- `logs/gpu_terrain_partial_dirty_edge_matrix_current/gpu-terrain-partial-dirty-edge-matrix-cases.txt`
- per-case `edge-dirty-compare-summary.txt` files under `logs/gpu_terrain_partial_dirty_edge_matrix_current/cases/*`

## Case Coverage

The gate requires four single-edge cases:

- `pos_x` at `31,64,16:31,64,16`
- `neg_x` at `0,64,16:0,64,16`
- `pos_z` at `16,64,31:16,64,31`
- `neg_z` at `16,64,0:16,64,0`

The gate also requires all four corner combinations:

- `pos_x,pos_z` at `31,64,31:31,64,31`
- `pos_x,neg_z` at `31,64,0:31,64,0`
- `neg_x,pos_z` at `0,64,31:0,64,31`
- `neg_x,neg_z` at `0,64,0:0,64,0`

For every case, the gate checks:

- full and partial lanes touch the same exact dirty surface
- full lane keeps partial dirty counters and edge-neighbor refresh disabled
- partial lane records edge-neighbor refresh and saved subchunks
- collision readiness remains present
- normal GPU upload failures remain zero
- terrain queue, process wall p95, and compositor submit maxima remain below the 150 FPS CPU-side frame budget
- `default_runtime_change_allowed=0` and `visible_quality_change_allowed=0`
- external profiler and macOS/Windows validation blockers remain present

Fresh local evidence:

- `case_count=8`
- `single_edge_cases=4`
- `corner_edge_cases=4`
- `min/max partial edge-neighbor subchunks=4/8`
- `min/max partial saved subchunks=2/2`
- `max queue/process/submit=3.734/0.041/0.102ms`
- `full_partial_disabled=1`
- `gpu_upload_fail=0`

## External Context

The matrix follows the same evidence policy as the surrounding GPU gates: prove bounded update pressure locally, then keep backend-specific profiler validation as a blocker before changing defaults. Relevant official references:

- Godot `RenderingDevice`: https://docs.godotengine.org/en/stable/classes/class_renderingdevice.html
- Apple Metal triple buffering for dynamic buffer data: https://developer.apple.com/library/archive/documentation/3DDrawing/Conceptual/MTLBestPracticesGuide/TripleBuffering.html
- Direct3D 12 fence-based resource management: https://learn.microsoft.com/en-us/windows/win32/direct3d12/fence-based-resource-management
- Vulkan staging buffers: https://docs.vulkan.org/tutorial/latest/04_Vertex_buffers/02_Staging_buffer.html

This benchmark is local macOS/Metal CPU-side runtime evidence only. The edit-burst budget gate now composes it with repeated/border edit, collision refresh, shadow proxy refresh, and upload budget evidence; mass-edit pressure gates, visual parity, external profiler rows, and Windows/Vulkan/Direct3D validation remain separate.
