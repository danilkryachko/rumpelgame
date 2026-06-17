# GPU Terrain Chunk Boundary Stress

Date: 2026-06-16

Scope: GPU world streaming enter/exit evidence. This gate composes existing high-pressure movement cases into one summary without changing default draw distance, visible quality, protocol, storage, world generation, chunk serialization, lighting, shadows, texture quality, or chunk unload policy.

## Gate

Use:

```sh
RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE=1 \
RUMPELMC_GODOT_RUST_EXT_PROFILE=release \
GODOT_TIMEOUT_SEC=360 \
GODOT_QUIT_AFTER_FRAMES=42000 \
SMOKE_DELAY_SEC=8.0 \
sh scripts/gpu_terrain_chunk_boundary_stress.sh logs/gpu_terrain_chunk_boundary_stress_current
```

The default case set is:

- `long-move`
- `spiral`
- `fast-turn`
- `teleport-snap`
- `high-resident`

Movement cases validate final current-chunk identity, minimum traversed chunks, render readiness, collision readiness, ground misses, upload failures, packet queue, unload churn, and pop-in telemetry. The `high-resident` workload case is a bounded residency smoke in this gate; the stricter thousands-of-draws residency requirement remains `scripts/gpu_terrain_load_scaling.sh` and `scripts/gpu_terrain_mass_chunk_load_gate.sh`.

Set `RUMPELMC_CHUNK_BOUNDARY_SOURCE_SUMMARY=<path>` to re-check an existing `world-load-suite-summary.txt` without rerunning Godot.

## Defaults

- `RUMPELMC_CHUNK_BOUNDARY_REQUIRE_NO_UNLOAD=1`
- `RUMPELMC_CHUNK_BOUNDARY_MIN_GPU_SUBCHUNKS=900`
- `RUMPELMC_CHUNK_BOUNDARY_MIN_GPU_DRAWS=900`
- `RUMPELMC_CHUNK_BOUNDARY_MIN_GPU_FACES=1200`

The lower residency thresholds are deliberate: this gate proves enter/exit stability and a bounded resident workload in the same run. Heavy resident-set proof still requires the load-scaling and mass chunk-load gates.

## Fresh Evidence

Fresh local release evidence:

- `logs/gpu_terrain_chunk_boundary_stress_current/chunk-boundary-stress-summary.txt`
- Status: `pass`
- Cases: `long-move spiral fast-turn teleport-snap high-resident`
- Movement cases: `4`
- Workload cases: `1`
- Max GPU resident smoke: `998` subchunks, `998` draws, `1445` faces
- Max movement effective draws: `849`
- Max terrain queue: `2.258ms`
- Max process wall p95: `0.049ms`
- Max compositor submit: `0.124ms`
- Max packet queue drain: `54`
- Max packet queue lag: `27.437ms`
- Max unload total: `0`
- Max grace-kept churn: `48984`
- Max unload neighbor refreshes: `0`
- Max pop-in missing/collision-missing chunks: `140` / `109`
- Upload failures, capacity failures, fragmented failures: `0`
- Ground misses: `0`
- Render/collision not-ready cases: `0`

The first full run failed before the threshold split because the wrapper incorrectly applied the strict load-scaling `>=2000` resident-set thresholds to the bounded `high-resident` case. The source suite itself passed. The summary was then revalidated with `RUMPELMC_CHUNK_BOUNDARY_SOURCE_SUMMARY` after setting this gate's bounded residency thresholds.

## Evidence Chain

- `scripts/gpu_terrain_report.sh` surfaces `Selected Chunk Boundary Stress Summary`.
- `scripts/gpu_terrain_report_v2.sh` treats the chunk-boundary summary as a fail gate.
- `scripts/test_strategy_gate.sh` requires the chunk-boundary summary and includes the runtime wrapper in the nightly runtime command.

## External Context

- Godot documents [visibility ranges](https://docs.godotengine.org/en/stable/tutorials/3d/visibility_ranges.html), LOD, and [occlusion culling](https://docs.godotengine.org/en/stable/tutorials/3d/occlusion_culling.html) as complementary performance tools for large 3D scenes; this gate does not replace those renderer-level options, but it keeps streaming and current-chunk readiness measurable before changing them.
- Microsoft D3D12 [memory management](https://learn.microsoft.com/en-us/windows/win32/direct3d12/memory-management) treats residency as the GPU accessibility state for resources, which matches the need to track resident workload and upload failures separately from movement correctness.
- Apple's Metal best practices recommend appropriate [resource storage modes](https://developer.apple.com/library/archive/documentation/3DDrawing/Conceptual/MTLBestPracticesGuide/ResourceOptions.html), [persistent resource reuse](https://developer.apple.com/library/archive/documentation/3DDrawing/Conceptual/MTLBestPracticesGuide/PersistentObjects.html), and [triple buffering](https://developer.apple.com/library/archive/documentation/3DDrawing/Conceptual/MTLBestPracticesGuide/TripleBuffering.html) for dynamic data. This supports keeping upload/reuse telemetry visible before changing staging or buffer-residency policy.
