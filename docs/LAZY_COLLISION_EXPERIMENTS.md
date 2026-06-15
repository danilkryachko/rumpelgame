# Lazy Collision Experiments

Date: 2026-06-15

## Scope

Lazy collision is experimental and opt-in only. The default client collision radius remains `1` chunk around the current player chunk.

`RUMPELMC_CLIENT_COLLISION_CHUNK_DISTANCE` controls the experiment radius, clamped to `0..4`. Setting it to `0` keeps collision only for the current player chunk. Leaving it unset preserves the existing default behavior.

This experiment does not change protocol, storage, world generation, chunk serialization, server streaming, visible quality, lighting, shadows, texture quality, or default draw distance.

## Gate

Use the high-pressure `teleport-snap` case as the first lazy-collision gate:

```sh
RUMPELMC_CLIENT_COLLISION_CHUNK_DISTANCE=0 RUMPELMC_WORLD_LOAD_SUITE_CASES=teleport-snap RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE=1 RUMPELMC_GODOT_RUST_EXT_PROFILE=release /bin/sh ./scripts/world_streaming_high_pressure_suite.sh logs/world_streaming_high_pressure_suite_teleport_lazy_collision_r0_check
```

Fresh result:

- `logs/world_streaming_high_pressure_suite_teleport_lazy_collision_r0_check/world-load-suite-summary.txt` passed final readiness with `current_render_ready=1`, `current_collision_ready=1`, `readiness_ground_misses=0`, `terrain_queue_max_ms=2.067`, `process_wall_p95_ms=0.038`, `gpu_compositor_submit_max_ms=0.139`, and `gpu_upload_fail=0`.
- The same run reported `popin_collision_missing_chunks=2706` and `popin_collision_missing_max=4`, much higher than the default radius evidence. This means radius `0` is not ready for default promotion without budgets and broader movement coverage.

## Decision

Keep lazy collision as an opt-in experiment. Do not change the default collision radius until the project defines acceptable pop-in/collision-missing budgets and passes at least `teleport-snap`, `fast-turn`, and resident-set movement gates with final readiness and ground rays intact.
