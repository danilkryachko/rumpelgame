# Long-Run Exploration Soak

Date: 2026-06-15

This note records the current long-run exploration soak harness for world streaming.

## Harness

The soak wrapper is:

```sh
RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE=1 RUMPELMC_GODOT_RUST_EXT_PROFILE=release ./scripts/world_streaming_exploration_soak.sh logs/world_streaming_exploration_soak
```

It builds/signs `server/server`, refuses a pre-existing listener on port `25565`, runs repeated movement stress passes, and writes `world-streaming-exploration-soak-summary.txt`.

Default behavior is intentionally bounded:

- `RUMPELMC_EXPLORATION_SOAK_REPEATS=3`
- `RUMPELMC_EXPLORATION_SOAK_MOTION=chunk_walk_extended`
- `RUMPELMC_EXPLORATION_SOAK_BUDGET_MODE=report`

Raise `RUMPELMC_EXPLORATION_SOAK_REPEATS` for true long or overnight runs. The wrapper aggregates max terrain queue time, process wall p95, GPU compositor submit time, effective draws, packet queue drain/lag, unload churn, pop-in counters, upload failures, ground misses, and final render/collision readiness.

## Fresh Smoke

Short harness validation:

```sh
GODOT_TIMEOUT_SEC=180 \
RUMPELMC_EXPLORATION_SOAK_REPEATS=1 \
RUMPELMC_EXPLORATION_SOAK_MOTION=chunk_fast_turn \
RUMPELMC_EXPLORATION_SOAK_EXPECTED_CHUNK=2,2 \
RUMPELMC_EXPLORATION_SOAK_MIN_CHUNKS=1 \
RUMPELMC_EXPLORATION_SOAK_STEP_SEC=0.08 \
RUMPELMC_EXPLORATION_SOAK_SETTLE_SEC=4.0 \
RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE=1 \
RUMPELMC_GODOT_RUST_EXT_PROFILE=release \
/bin/sh scripts/world_streaming_exploration_soak.sh logs/world_streaming_exploration_soak_smoke
```

Fresh check:

- `logs/world_streaming_exploration_soak_smoke/world-streaming-exploration-soak-summary.txt` passed with `max_terrain_queue_ms=2.147`, `max_process_wall_p95_ms=0.048`, `max_gpu_compositor_submit_ms=0.142`, `max_gpu_effective_draws=750`, `max_packet_queue_drain=36`, `max_packet_queue_lag_ms=15.330`, `max_chunk_unload_total=0`, `max_popin_missing_chunks=251`, `max_popin_collision_missing_chunks=41`, `gpu_upload_fail=0`, `ground_misses=0`, and final render/collision readiness in all runs.
