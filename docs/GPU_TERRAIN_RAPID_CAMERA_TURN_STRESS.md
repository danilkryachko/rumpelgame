# GPU Terrain Rapid Camera-Turn Stress

Date: 2026-06-16

Scope: rapid camera-orientation stress for the GPU terrain path. This gate uses the existing `chunk_fast_turn` visual-smoke motion to rotate the camera repeatedly while staying inside the same chunk. It does not change default draw distance, visible quality, camera FOV, protocol, storage, world generation, chunk serialization, lighting, shadows, texture quality, or chunk unload policy.

## Gate

Use:

```sh
RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE=1 \
RUMPELMC_GODOT_RUST_EXT_PROFILE=release \
GODOT_TIMEOUT_SEC=240 \
GODOT_QUIT_AFTER_FRAMES=30000 \
SMOKE_DELAY_SEC=8.0 \
sh scripts/gpu_terrain_rapid_camera_turn_stress.sh logs/gpu_terrain_rapid_camera_turn_stress_current
```

The wrapper runs `scripts/gpu_terrain_movement_stress.sh` with:

- `RUMPELMC_MOVEMENT_STRESS_MOTION=chunk_fast_turn`
- `RUMPELMC_MOVEMENT_STRESS_EXPECTED_CHUNK=2,2`
- `RUMPELMC_MOVEMENT_STRESS_MIN_CHUNKS=1`
- `RUMPELMC_MOVEMENT_STRESS_STEP_SEC=0.08`
- `RUMPELMC_MOVEMENT_STRESS_SETTLE_SEC=4.0`

It then writes `rapid-camera-turn-stress-summary.txt`.

Set `RUMPELMC_RAPID_CAMERA_TURN_SOURCE_SUMMARY=<path>` to re-check an existing movement-stress summary without rerunning Godot. If `RUMPELMC_RAPID_CAMERA_TURN_SOURCE_MARKER` is omitted, the wrapper expects `gpu-terrain-movement-stress.png.txt` beside the source summary.

## Contract

The gate fails unless:

- `motion=chunk_fast_turn`
- `motion_steps >= 8`
- `motion_chunks == 1`
- final `current_chunk=2,2`
- current chunk render and collision readiness are present
- `ground_misses=0`
- `terrain_samples > 0`
- `smoke_err=0`
- all GPU upload failure counters are `0`
- chunk unload total, max unload, and neighbor refreshes are `0`
- terrain queue max, process wall p95, and compositor submit max stay within the `150 FPS` CPU-side budget

Pop-in counters and local visual FPS/GPU timestamp fields remain telemetry/report-only.

## Fresh Evidence

Fresh local release evidence:

- `logs/gpu_terrain_rapid_camera_turn_stress_current/rapid-camera-turn-stress-summary.txt`
- Status: `pass`
- Motion: `chunk_fast_turn`
- Final chunk: `2,2`
- Motion steps/chunks: `8` / `1`
- Terrain queue max: `1.535ms`
- Process wall p95: `0.049ms`
- Compositor submit max: `0.100ms`
- GPU effective draws: `634`
- Packet queue max drain: `51`
- Packet queue max lag: `22.405ms`
- Chunk unload total/grace-kept/neighbor-refreshes/max: `0` / `3886` / `0` / `0`
- Pop-in missing/collision-missing chunks: `132` / `40`
- Upload failures/capacity/fragmented/injected: `0` / `0` / `0` / `0`
- Ground misses: `0`
- Terrain samples: `416`

## Evidence Chain

- `scripts/gpu_terrain_report.sh` surfaces `Selected Rapid Camera-Turn Stress Summary`.
- `scripts/test_strategy_gate.sh` requires the summary and includes the runtime wrapper in the nightly runtime command.
- The broader chunk-boundary stress gate still includes `fast-turn`; this standalone gate keeps the rapid-turn contract easier to refresh and diagnose.

## Validation

Validated 2026-06-16 with shell syntax checks for touched scripts, source-summary recheck against the chunk-boundary `fast-turn` row, fresh release runtime gate, V1 report surfacing, test-strategy summary override, `./scripts/check.sh fast`, `git diff --check`, `./scripts/diff_guard.sh`, and `./scripts/handoff.sh`.

## External Context

- Godot's [3D optimization guide](https://docs.godotengine.org/en/latest/tutorials/performance/optimizing_3d_performance.html) documents view frustum culling, occlusion culling, LOD, and visibility ranges as ways to keep large scenes from rendering unnecessary objects. Rapid camera-turn stress keeps our own GPU terrain stream/render readiness measurable before changing those scene-level controls.
- Godot [`Camera3D`](https://docs.godotengine.org/en/stable/classes/class_camera3d.html) exposes the camera far culling boundary; the project must not lower that or other visible-quality controls just to pass this stress gate.
