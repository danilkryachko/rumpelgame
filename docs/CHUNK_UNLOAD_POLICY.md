# Chunk Unload Policy

Date: 2026-06-15

## Current Policy

Chunk unload is client-side and behavior-preserving:

- `RUMPELMC_CLIENT_KEEP_CHUNK_DISTANCE` controls the loaded radius around the current player chunk. The default is `10`, clamped to `16`.
- `RUMPELMC_CLIENT_CHUNK_UNLOAD_GRACE_SEC` keeps recently seen chunks resident after they leave the keep radius. The default is `20.0`, clamped to `120.0`.
- `RUMPELMC_CLIENT_CHUNK_UNLOAD_GRACE_SEC=0` is the rollback/control path for immediate unload.

The current policy does not change protocol, server streaming, storage, world generation, chunk serialization, visible quality, lighting, shadows, texture quality, or default draw distance.

## Churn Metrics

The Rust client reports unload churn in `GameClient.get_perf_text()`:

- `chunk_unload_scans`: unload-policy scan count.
- `chunk_unload_scanned`: total loaded chunks inspected by unload-policy scans.
- `chunk_unload_grace_kept`: chunks outside the keep radius but kept resident by the grace window.
- `chunk_unload_total`: chunks actually unloaded.
- `chunk_unload_neighbor_refresh`: loaded neighbor chunks re-enqueued after an unload.
- `chunk_unload_last`, `chunk_unload_last_grace_kept`, and `chunk_unload_last_neighbor_refresh`: last scan values.
- `chunk_unload_max`, `chunk_unload_max_grace_kept`, and `chunk_unload_max_neighbor_refresh`: worst single-scan values.

`scripts/gpu_terrain_movement_stress.sh` writes these values as `movement_chunk_unload`, and `scripts/world_streaming_high_pressure_suite.sh` carries the main churn values into `world-load-suite-summary.txt`.

## Fresh Evidence

Default grace:

```sh
RUMPELMC_WORLD_LOAD_SUITE_CASES=teleport-snap RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE=1 RUMPELMC_GODOT_RUST_EXT_PROFILE=release ./scripts/world_streaming_high_pressure_suite.sh logs/world_streaming_high_pressure_suite_teleport_unload_churn_check
```

- `logs/world_streaming_high_pressure_suite_teleport_unload_churn_check/world-load-suite-summary.txt` passed with `chunk_unload_total=0`, `chunk_unload_grace_kept=24375`, `chunk_unload_neighbor_refreshes=0`, `chunk_unload_max=0`, `chunk_unload_max_grace_kept=311`, `gpu_effective_draws=645`, `terrain_queue_max_ms=2.062`, `process_wall_p95_ms=0.039`, `gpu_compositor_submit_max_ms=0.127`, and `gpu_upload_fail=0`.

Immediate-unload control:

```sh
RUMPELMC_CLIENT_CHUNK_UNLOAD_GRACE_SEC=0 RUMPELMC_WORLD_LOAD_SUITE_CASES=teleport-snap RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE=1 RUMPELMC_GODOT_RUST_EXT_PROFILE=release ./scripts/world_streaming_high_pressure_suite.sh logs/world_streaming_high_pressure_suite_teleport_unload_churn_grace0_check
```

- `logs/world_streaming_high_pressure_suite_teleport_unload_churn_grace0_check/world-load-suite-summary.txt` passed with `chunk_unload_total=375`, `chunk_unload_grace_kept=0`, `chunk_unload_neighbor_refreshes=296`, `chunk_unload_max=311`, `gpu_effective_draws=38`, `terrain_queue_max_ms=2.222`, `process_wall_p95_ms=0.036`, `gpu_compositor_submit_max_ms=0.127`, and `gpu_upload_fail=0`.

## Decision

Keep the default grace-based unload policy. The fresh `teleport-snap` control proves immediate unload still creates large unload/reload churn and neighbor rerender pressure, while default grace absorbs that churn without upload failures or frame-budget pressure in the current scenario.

Do not redesign the default unload policy again until pop-in metrics can show whether grace is hiding visible holes, over-retaining memory, or delaying correctness-relevant collision updates.

## Next Policy Shape

The next unload-policy change should be data-driven and reversible:

1. Add pop-in and visible-hole metrics before changing behavior.
2. Compare default grace, immediate unload, and any candidate hysteresis policy on the same `teleport-snap`, `fast-turn`, and resident-set gates.
3. Require zero GPU upload failures and no loss of collision readiness.
4. Keep `RUMPELMC_CLIENT_CHUNK_UNLOAD_GRACE_SEC=0` as rollback/control.
