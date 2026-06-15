# World Pop-In Metrics

Date: 2026-06-15

## Definition

The first pop-in metric is a client-side probe around the current player chunk. It is telemetry-only and does not change server streaming, client unload policy, draw distance, visible quality, collision rules, protocol, storage, world generation, or chunk serialization.

Default probe radius is `1` chunk and is controlled by `RUMPELMC_CLIENT_POP_IN_PROBE_RADIUS`, clamped to `0..4`.

For each client process frame, the probe counts chunks inside the circular radius:

- `popin_frames`: frames with a probe sample.
- `popin_complete_frames`: frames with no missing loaded chunks and no missing collision chunks in the probe.
- `popin_missing_frames`: frames where at least one probe chunk is not loaded.
- `popin_collision_missing_frames`: frames where at least one loaded probe chunk lacks collision bodies.
- `popin_missing_chunks`: total missing loaded chunks across sampled frames.
- `popin_collision_missing_chunks`: total loaded-but-collision-missing chunks across sampled frames.
- `popin_missing_max`: worst missing-loaded chunk count in one frame.
- `popin_collision_missing_max`: worst loaded-but-collision-missing count in one frame.

This is not a camera-occlusion or image-space hole detector yet. It is the first correctness-oriented streaming metric for the ground/player neighborhood.

## Reporting

The Rust client emits the `popin_*` fields in `GameClient.get_perf_text()`.

`scripts/gpu_terrain_movement_stress.sh` writes a `movement_popin` row. `scripts/gpu_terrain_flyback_stress.sh` writes a `flyback_popin` row. `scripts/world_streaming_high_pressure_suite.sh` carries the main values into movement rows in `world-load-suite-summary.txt`.

## Fresh Evidence

```sh
RUMPELMC_WORLD_LOAD_SUITE_CASES=teleport-snap RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE=1 RUMPELMC_GODOT_RUST_EXT_PROFILE=release /bin/sh ./scripts/world_streaming_high_pressure_suite.sh logs/world_streaming_high_pressure_suite_teleport_popin_check
```

Fresh result:

- `logs/world_streaming_high_pressure_suite_teleport_popin_check/world-load-suite-summary.txt` passed `teleport-snap` with `popin_missing_chunks=283`, `popin_collision_missing_chunks=75`, `popin_missing_max=5`, `popin_collision_missing_max=5`, `popin_probe_radius=1`, `terrain_queue_max_ms=2.016`, `process_wall_p95_ms=0.038`, `gpu_compositor_submit_max_ms=0.130`, and `gpu_upload_fail=0`.
- `logs/world_streaming_high_pressure_suite_teleport_popin_check/teleport-snap/movement-stress-summary.txt` reported `movement_popin frames=743`, `complete_frames=647`, `missing_frames=69`, `collision_missing_frames=27`, `missing_last=0`, and `collision_missing_last=0`.

## Next Step

Use these metrics as evidence for collision readiness and future unload-policy changes. They should remain report-only until the project defines budget thresholds for allowed startup/movement transient missing frames.
