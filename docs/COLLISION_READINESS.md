# Collision Readiness

Date: 2026-06-15

## Current Contract

Startup remains collision-gated:

1. The client receives and decodes the startup chunk.
2. The startup chunk is inserted and marked loaded.
3. Startup mesh subchunks are dispatched.
4. First mesh and collision are created.
5. The player is spawned only after startup chunk collision exists.

This contract is enforced by movement stress startup timing order checks and by the existing `current_chunk_loaded`, `current_chunk_submeshes`, `current_chunk_collision`, and ground-ray checks.

## Render-Ready Versus Collision-Ready

Movement summaries now write an explicit `movement_readiness` row:

- `current_chunk_loaded`: current player chunk data is present.
- `current_render_ready`: current chunk has at least one rendered submesh.
- `current_chunk_submeshes`: current chunk rendered submesh count.
- `current_collision_ready`: current chunk has collision bodies.
- `current_chunk_collision`: current chunk collision body count.
- `ground_misses`: final ground-ray misses around the player.
- `popin_collision_missing_max`: worst loaded-but-collision-missing probe count from the report-only pop-in metric.
- `startup_collision_ms` and `startup_player_spawn_ms`: startup ordering evidence.

The high-pressure suite carries the main readiness values into movement rows in `world-load-suite-summary.txt`.

## Fresh Evidence

```sh
RUMPELMC_WORLD_LOAD_SUITE_CASES=teleport-snap RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE=1 RUMPELMC_GODOT_RUST_EXT_PROFILE=release /bin/sh ./scripts/world_streaming_high_pressure_suite.sh logs/world_streaming_high_pressure_suite_teleport_readiness_check
```

Fresh result:

- `logs/world_streaming_high_pressure_suite_teleport_readiness_check/world-load-suite-summary.txt` passed `teleport-snap` with `current_render_ready=1`, `current_collision_ready=1`, `readiness_ground_misses=0`, `popin_collision_missing_max=5`, `terrain_queue_max_ms=2.152`, `process_wall_p95_ms=0.037`, `gpu_compositor_submit_max_ms=0.163`, and `gpu_upload_fail=0`.
- `logs/world_streaming_high_pressure_suite_teleport_readiness_check/teleport-snap/movement-stress-summary.txt` reported `movement_readiness current_chunk_loaded=1 current_render_ready=1 current_chunk_submeshes=2 current_collision_ready=1 current_chunk_collision=2 ground_misses=0`.

## Next Step

Keep spawn collision-gated. Future lazy-collision experiments must prove that current-chunk collision readiness, final ground rays, and pop-in collision-missing metrics stay within explicit budgets before changing collision scheduling.
