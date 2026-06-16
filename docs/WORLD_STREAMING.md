# World Streaming

This document tracks the chunk-loading path and planned optimizations for faster world startup and movement streaming.

See `docs/WORLD_STREAMING_ARCHITECTURE_REVIEW.md` for the 2026-06-15 end-to-end architecture review, current bottlenecks, invariants, and next acceleration strategy.

See `docs/CHUNK_COMPRESSION_DECISION.md` for the 2026-06-15 compression decision gate and current RLE/raw rollback decision.

See `docs/CHUNK_UNLOAD_POLICY.md` for the 2026-06-15 unload churn metrics, default grace decision, and immediate-unload control evidence.

See `docs/WORLD_POP_IN_METRICS.md` for the 2026-06-15 player-neighborhood pop-in probe and current report-only evidence.

See `docs/COLLISION_READINESS.md` for the 2026-06-15 render-ready versus collision-ready movement summary and startup collision-gating contract.

See `docs/LAZY_COLLISION_EXPERIMENTS.md` for the 2026-06-15 opt-in collision radius experiment and why the default collision radius remains unchanged.

See `docs/WORLDGEN_DETERMINISM.md` for the 2026-06-16 worldgen determinism and stable chunk serialization test guard.

See `docs/CHUNK_SERIALIZATION_COMPATIBILITY.md` for the 2026-06-15 chunk payload and protocol schema compatibility guard.

See `docs/NETWORKING_ROBUSTNESS_PROGRAM.md` for the 2026-06-15 packet boundary robustness gate for short, oversized, and malformed frames.

See `docs/PACKET_ERROR_MONITORING_CONTRACT.md` for the local packet-error monitoring export contract consumed by security, RC, external-profiler, and production-readiness gates.

See `docs/SERVER_SESSION_MONITORING_CONTRACT.md` for the local server session monitoring export contract consumed by security, RC, external-profiler, and production-readiness gates.

See `docs/CLIENT_STATE_MACHINE_HARDENING.md` for the 2026-06-15 client lifecycle model and transition tests.

See `docs/GAMEPLAY_LOOP_FOUNDATION.md` for the 2026-06-15 mining/building and local inventory foundation checkpoint.

See `docs/BLOCK_EDIT_PERSISTENCE_TRACK.md` for the 2026-06-15 block edit save/reload persistence proof.

See `docs/DIRTY_UPDATE_SCALABILITY.md` for the 2026-06-15 dirty update scalability checkpoint and mass dirty unit guard.

See `docs/STORAGE_PERSISTENCE_FOUNDATION.md` for the 2026-06-15 RocksDB chunk persistence guard.

See `docs/LONG_RUN_EXPLORATION_SOAK.md` for the 2026-06-15 repeated movement soak harness and smoke evidence.

See `docs/GPU_TERRAIN_LOAD_SCALING.md` for the 2026-06-15 high resident-set GPU terrain load-scaling gate.

See `docs/GPU_UPLOAD_PRESSURE.md` for the 2026-06-15 fill-stress plus allocator upload-pressure gate.

See `docs/GPU_REPACK_ACTIVATION_PREFLIGHT.md` for the 2026-06-15 GPU repack activation preflight and deferred decision.

See `docs/GPU_REPACK_SOAK_ROLLBACK.md` for the 2026-06-15 GPU repack soak/rollback deferred gate.

## High-Pressure Suite

The high-pressure world load suite is:

```sh
RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE=1 RUMPELMC_GODOT_RUST_EXT_PROFILE=release ./scripts/world_streaming_high_pressure_suite.sh logs/world_streaming_high_pressure_suite
```

It builds/signs `server/server`, refuses a pre-existing listener on port `25565`, runs selected movement/workload cases, then writes `world-load-suite-summary.txt`. The top-level summary includes `server_chunk_order` so opt-in delivery-order runs are explicit. By default it runs:

- `startup-cold`
- `startup-warm`
- `long-move`
- `spiral`
- `fast-turn`
- `teleport-snap`
- `high-view`
- `high-resident`

Use `RUMPELMC_WORLD_LOAD_SUITE_CASES="fast-turn spiral"` to run a narrow subset. The suite defaults performance budgets to report-only so high-pressure evidence is collected without hiding correctness failures; movement smoke still validates terrain, collision, startup timing, and zero GPU upload failures.

## First Playable Latency

The main scene no longer waits a fixed `1.0s` after the local server reports that it is listening before adding `GameClient`. Default startup now yields one frame, then attaches the client immediately. Use `RUMPELMC_CLIENT_ATTACH_DELAY_SEC=<seconds>` only as a diagnostic rollback/control if a platform needs extra delay after server listen readiness.

Fresh check:

- `logs/world_streaming_high_pressure_suite_startup_cold_attach_delay_check/world-load-suite-summary.txt` passed `startup-cold` with `startup_player_spawn_ms=15.152`, `startup_packet_queue_lag_ms=10.125`, `startup_chunk_decode_work_ms=0.228`, `startup_first_mesh_work_ms=3.436`, `startup_first_mesh_collision_work_ms=2.776`, `terrain_queue_max_ms=1.812`, and `gpu_upload_fail=0`.

## Chunk Delivery Order

The default server stream remains nearest-first by squared chunk distance. `world.ChunksAround` preserves that old behavior and is unit-guarded for stable X/Z tie-breaks, per-batch limits, sent-state advancement through `chunk_request_ordering=guarded`, and nil sent-state inputs through `nil_sent_state_policy=empty_guarded`.

`RUMPELMC_SERVER_CHUNK_ORDER=directional` enables an opt-in server-side tie-break for movement streaming. The server tracks the previous chunk center per connection, converts movement between chunk centers to a normalized `-1/0/1` direction, and passes that to `world.ChunksAroundOrdered`. Directional ordering does not change protocol, chunk payloads, storage, world generation, view distance, batch size, or bootstrap radius. It only chooses ahead-of-motion chunks first when candidates are already at the same distance from the current center.

Fresh check:

- `logs/world_streaming_high_pressure_suite_spiral_directional_check/world-load-suite-summary.txt` passed `spiral` with `server_chunk_order=directional`, `motion_steps=9`, `motion_chunks=9`, `current_chunk=0,2`, `terrain_queue_max_ms=1.831`, `process_wall_p95_ms=0.044`, `gpu_compositor_submit_max_ms=0.116`, `gpu_upload_fail=0`, and `startup_player_spawn_ms=16.667`.
- The matching run log recorded directional stream batches with nonzero movement directions, including `direction=1,1`, `direction=-1,0`, `direction=1,-1`, and `direction=0,1`.

## Client Packet Queue Measurement

The Rust client keeps the existing unbounded reader-thread channel and main-thread drain behavior. Packet queue metrics are measurement-only and use per-frame drain counts as a queue-depth proxy:

- `packet_q_frames`, `packet_q_nonempty`, `packet_q_drained`, and `packet_q_chunk_drained` count drain frames and drained packets.
- `packet_q_last_drain`, `packet_q_max_drain`, `packet_q_last_chunk_drain`, and `packet_q_max_chunk_drain` report frame-level drain bursts.
- `packet_q_lag_ms` reports last/average/max queue lag for packets drained on non-empty frames.
- `packet_q_decode_work_ms` reports last/average/max protobuf decode work for drained packets.

`scripts/gpu_terrain_movement_stress.sh` writes these fields as a `movement_packet_queue` line, and the high-pressure suite carries the main values into `world-load-suite-summary.txt`.

Fresh check:

- `logs/world_streaming_high_pressure_suite_startup_packet_queue_check/world-load-suite-summary.txt` passed `startup-cold` with `packet_queue_max_drain=35`, `packet_queue_drained=394`, `packet_queue_lag_max_ms=13.943`, `packet_queue_decode_work_max_ms=0.023`, `startup_player_spawn_ms=8.333`, `terrain_queue_max_ms=1.949`, and `gpu_upload_fail=0`.

## Resident Set Growth

The resident-set growth gate is measurement-only. It raises the stress workload to server view distance `16` and client keep distance `16` without changing default gameplay distance, visible quality, protocol, storage, chunk serialization, or GPU feature flags:

```sh
RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE=1 RUMPELMC_GODOT_RUST_EXT_PROFILE=release ./scripts/world_streaming_resident_set_growth.sh logs/world_streaming_resident_set_growth_radius16_check
```

The wrapper runs the heavy workload matrix, requires a minimum resident draw count, and fails on GPU upload failures. It is intended to produce resident pressure evidence before changing unload policy, repack behavior, or draw-distance defaults.

Fresh check:

- `logs/world_streaming_resident_set_growth_radius16_check/resident-set-growth-summary.txt` passed with `server_view_distance=16`, `client_keep_chunk_distance=16`, `max_gpu_subchunks=2482`, `max_gpu_draws=2482`, `max_gpu_faces=3296`, `max_gpu_draw_cmd_bytes=39712`, `max_gpu_draw_cmd_capacity_bytes=131072`, `max_terrain_queue_ms=3.453`, `max_process_wall_p95_ms=0.052`, `max_gpu_compositor_submit_ms=0.207`, and `gpu_upload_fail=0`.

## Resident Set Matrix

The resident-set matrix wrapper records a trend-oriented summary over one or more resident-set growth summaries. By default it is summary-only and validates the existing radius-16 artifact; set `RUMPELMC_RESIDENT_SET_MATRIX_RUN=1` plus `RUMPELMC_RESIDENT_SET_MATRIX_RADII="16 18"` only when a task intentionally needs fresh heavy Godot runs.

Use the summary-only path for normal planning:

```sh
sh scripts/world_streaming_resident_set_matrix.sh logs/world_streaming_resident_set_matrix_current
```

Expected current result includes `status=pass`, `mode=summary`, `max_gpu_draws>=2000`, `max_draw_cmd_occupancy_pct>=25.0`, and zero GPU upload failures. The summary also records the best radius, max subchunks/draws/faces, draw-command occupancy/headroom, terrain queue max, process wall p95, and compositor submit max.

Fresh explicit clean run:

- `logs/world_streaming_resident_set_matrix_radius16_18_clean/resident-set-matrix-summary.txt` ran `RUMPELMC_RESIDENT_SET_MATRIX_RUN=1` with radii `16 18` after clearing a stale local server listener. Both source resident-set growth rows passed and reported zero GPU upload failures, but the matrix failed the pressure gate with `reason=draw_pressure_too_low`: best radius `16`, `max_gpu_draws=1859`, `max_gpu_subchunks=1859`, `max_gpu_faces=2243`, `max_draw_cmd_occupancy_pct=22.693`, `min_draw_cmd_headroom_bytes=101328`, `max_terrain_queue_ms=2.498`, `max_process_wall_p95_ms=0.055`, and `max_gpu_compositor_submit_ms=0.160`. This fresh run is negative pressure evidence for active GPU repack or draw-capacity changes.

This wrapper is still measurement-only. It must not be used to change default draw distance, unload policy, GPU buffer repack behavior, allocator policy, protocol, storage, world generation, or chunk serialization by itself.

## Chunk Unload Churn

The default client unload policy remains keep-distance plus grace-period based. `RUMPELMC_CLIENT_CHUNK_UNLOAD_GRACE_SEC=0` is still the immediate-unload rollback/control path.

Chunk unload metrics are now part of the Rust perf marker and movement summaries:

- `chunk_unload_grace_kept` counts chunks outside the keep radius but retained by grace.
- `chunk_unload_total` counts chunks actually unloaded.
- `chunk_unload_neighbor_refresh` counts loaded neighbors re-enqueued after unloads.
- `chunk_unload_max` and `chunk_unload_max_grace_kept` capture worst single-scan churn.

Fresh `teleport-snap` checks:

- Default grace in `logs/world_streaming_high_pressure_suite_teleport_unload_churn_check/world-load-suite-summary.txt` passed with `chunk_unload_total=0`, `chunk_unload_grace_kept=24375`, `chunk_unload_neighbor_refreshes=0`, `chunk_unload_max=0`, `chunk_unload_max_grace_kept=311`, `terrain_queue_max_ms=2.062`, and `gpu_upload_fail=0`.
- Immediate-unload control in `logs/world_streaming_high_pressure_suite_teleport_unload_churn_grace0_check/world-load-suite-summary.txt` passed with `chunk_unload_total=375`, `chunk_unload_grace_kept=0`, `chunk_unload_neighbor_refreshes=296`, `chunk_unload_max=311`, `terrain_queue_max_ms=2.222`, and `gpu_upload_fail=0`.

## World Pop-In Metrics

The first pop-in metric is a report-only player-neighborhood probe. The default `RUMPELMC_CLIENT_POP_IN_PROBE_RADIUS=1` checks chunks around the current player chunk for loaded data and collision bodies. This is not yet an image-space or camera-occlusion hole detector.

Movement summaries now include:

- `movement_popin frames`, `complete_frames`, `missing_frames`, and `collision_missing_frames`.
- `missing_chunks` and `collision_missing_chunks` accumulated across frames.
- `missing_max` and `collision_missing_max` for worst single-frame probe gaps.

Fresh check:

- `logs/world_streaming_high_pressure_suite_teleport_popin_check/world-load-suite-summary.txt` passed `teleport-snap` with `popin_missing_chunks=283`, `popin_collision_missing_chunks=75`, `popin_missing_max=5`, `popin_collision_missing_max=5`, `popin_probe_radius=1`, `terrain_queue_max_ms=2.016`, and `gpu_upload_fail=0`.
- The matching movement summary reported `frames=743`, `complete_frames=647`, `missing_frames=69`, `collision_missing_frames=27`, `missing_last=0`, and `collision_missing_last=0`.

## Collision Readiness

Startup remains collision-gated, and movement summaries now include an explicit `movement_readiness` row that separates final render readiness from final collision readiness:

- `current_render_ready` is derived from `current_chunk_submeshes > 0`.
- `current_collision_ready` is derived from `current_chunk_collision > 0`.
- `readiness_ground_misses` stays tied to the final ground-ray grid around the player.
- `popin_collision_missing_max` reports transient loaded-but-collision-missing probe gaps separately from final readiness.

Fresh check:

- `logs/world_streaming_high_pressure_suite_teleport_readiness_check/world-load-suite-summary.txt` passed `teleport-snap` with `current_render_ready=1`, `current_collision_ready=1`, `readiness_ground_misses=0`, `popin_collision_missing_max=5`, `terrain_queue_max_ms=2.152`, and `gpu_upload_fail=0`.
- The matching movement summary reported `current_chunk_loaded=1`, `current_chunk_submeshes=2`, `current_chunk_collision=2`, `ground_misses=0`, `startup_collision_ms=8.333`, and `startup_player_spawn_ms=8.333`.

## Lazy Collision Experiment

`RUMPELMC_CLIENT_COLLISION_CHUNK_DISTANCE` is an opt-in experiment control. Leaving it unset keeps the current default collision radius `1`; setting it to `0` keeps collision only for the current player chunk.

Fresh check:

- `logs/world_streaming_high_pressure_suite_teleport_lazy_collision_r0_check/world-load-suite-summary.txt` passed final `teleport-snap` readiness with `current_render_ready=1`, `current_collision_ready=1`, `readiness_ground_misses=0`, `terrain_queue_max_ms=2.067`, and `gpu_upload_fail=0`.
- The same run reported `popin_collision_missing_chunks=2706` and `popin_collision_missing_max=4`, so radius `0` remains experimental and must not become default without explicit budgets and broader movement coverage.

## Worldgen Determinism

The current worldgen hardening slice now has an explicit seed/version foundation, an opt-in height generator, a metadata-only biome sampler, a metadata-only cave sampler, a metadata-only resource sampler, an opt-in biome-height generator, an opt-in cave-height generator, and an opt-in biome-cave-height generator without changing default generated bytes. It locks down `GeneratorConfig` seed/dimension/version inputs, server env parsing for `RUMPELMC_WORLD_SEED`, `RUMPELMC_WORLD_DIMENSION_ID`, and `RUMPELMC_WORLD_GENERATOR_VERSION`, `flat_v1` byte preservation across configured seeds, `height_v1` deterministic terrain surface bytes and seed/dimension sensitivity, `biome_height_v1` deterministic biome-derived surface/subsurface block selection, `cave_height_v1` deterministic underground carving with preserved surface columns, `biome_cave_height_v1` deterministic biome-selected surface/subsurface blocks plus cave carving, `height_v1`/`biome_height_v1`/`cave_height_v1`/`biome_cave_height_v1` RLE round-trips, persisted reload, and live server streaming coverage, metadata-only `biome_v1` catalog/sampling/matrix evidence, metadata-only `cave_v1` catalog/sampling/matrix evidence, metadata-only `resource_v1` catalog/sampling/matrix evidence, unknown generator-version rejection, flat generation strata for the origin chunk, representative flat/height/biome-height/cave-height/biome-cave-height chunk SHA-256 bytes, repeat generation for positive and negative chunk coordinates, global block-to-chunk coordinate mapping across negative and high-positive boundaries, stable little-endian block serialization order, and `World.ChunkSnapshot()` determinism across independent `World` instances.

Fresh check:

- `go test ./pkg/world` passed on 2026-06-16 with origin chunk flat-strata and representative flat byte-hash coverage.

## Chunk Serialization Compatibility

The compatibility suite is test-only. It guards empty-packet zero-wire compatibility, raw default payload compatibility, RLE wire-vector stability, direct serialize/deserialize round-trips, protobuf schema field numbers, enum wire values, and unknown `ChunkData` field preservation on Go protobuf round-trips.

Fresh check:

- `go test ./pkg/api ./pkg/world ./pkg/network` passed on 2026-06-16 with empty-packet zero-wire coverage and the existing compatibility coverage.

## Server Scalability

Server scalability is now guarded by per-client sent-state tests, interested-client block-edit fanout tests, failed-broadcast cleanup, session write deadlines, opt-in max-client admission, a bounded live one-holder/one-rejected admission smoke, a bounded admission-limit matrix, bounded classified connection lifecycle log summaries, a two-client live fanout/resource/detail smoke, a bounded six-client fanout/load/resource/detail smoke, a bounded three-run six-client repeat smoke, and the local server session monitoring export contract. Longer CPU/memory profiling, sustained admission sizing, adaptive overload policy, broad slow-reader/load harnesses, and external session metric upload/retention remain outside the current checkpoint.

Fresh check:

- `logs/server_scalability_pass_current/server-scalability-pass-summary.txt` reported `status=pass`, `scalability_status=repeat_live_guarded`, `resource_profile_status=repeat_live_guarded`, `multi_client_sent_state=guarded`, `block_edit_fanout=interested_clients_guarded`, `admission_policy=matrix_live_guarded`, `chunk_request_ordering=guarded`, `nil_sent_state_policy=empty_guarded`, `view_distance_config=guarded`, `disconnect_cleanup_status=lifecycle_summary_guarded`, `live_load_status=pass`, `live_detail_status=pass`, `live_detail_clients=2`, `live_resource_samples=3`, `live_resource_rss_kb_max=28832`, `broader_live_load_status=pass`, `broader_live_clients=6`, `broader_live_initial_chunks=6`, `broader_live_fanout_updates=6`, `broader_live_detail_status=pass`, `broader_live_detail_clients=6`, `broader_live_resource_samples=6`, `broader_live_resource_rss_kb_max=31584`, `repeat_smoke_status=pass`, `repeat_smoke_repeats=3`, `repeat_smoke_initial_chunks=18`, `repeat_smoke_fanout_updates=18`, `repeat_smoke_detail_clients=18`, `repeat_smoke_resource_samples=9`, `repeat_smoke_max_rss_kb=31120`, `admission_limit_smoke_status=pass`, `admission_matrix_status=pass`, `admission_matrix_limits_checked=3`, `admission_matrix_total_rejected=3`, `connection_lifecycle_status=pass`, `connection_lifecycle_packet_error_disconnects=9`, `connection_lifecycle_eof_disconnects=9`, `connection_lifecycle_timeout_disconnects=0`, `connection_lifecycle_close_failures=0`, `connection_lifecycle_accept_failures=0`, `connection_lifecycle_max_active_clients=6`, `connection_lifecycle_missing_active_client_fields=0`, and `active_protocol_change=0`.

## Networking Robustness

The networking robustness gate is packet-boundary focused. It keeps the current TCP frame contract unchanged while guarding server and Rust client behavior for short length prefixes, short payloads, oversized lengths, malformed protobuf payloads, zero-length payload frames that decode to empty packets, empty/unknown/nil-packet/nil-position/nil-block-action ignore policy, repeated live scalability and resource-profile evidence, multi-client sent-state, interested-client fanout, world-owned request ordering, nil world sent-state handling, view-distance configuration, lifecycle cleanup with zero close/accept failures and complete active-client lifecycle fields, closed initial probes, classified packet-error aggregation, live alert thresholds, local packet-error monitoring export contract, opt-in max-client admission with bounded live rejection evidence, sequential last-write-wins block-edit conflict semantics, bounded slow-reader timeout plus multi-fast-client matrix evidence, bounded repeated live disconnect/server-restart/rebootstrap recovery back to `client_state=active`, and unit-guarded reader-session stale-packet handling. Adaptive overload, packet replay, broad reconnect state reset, external monitoring service integration, and backpressure policy remain deferred.

Fresh check:

- `logs/networking_robustness_current/networking-robustness-summary.txt` reported `status=pass`, `server_boundary_tests=pass`, `client_boundary_tests=pass`, `stale_packet_policy=session_guarded`, `unknown_packet_policy=ignored_guarded`, `nil_packet_policy=ignored_guarded`, `nil_position_policy=ignored_guarded`, `nil_block_action_policy=ignored_guarded`, `nil_sent_state_policy=empty_guarded`, `view_distance_config=guarded`, `disconnect_cleanup_status=lifecycle_summary_guarded`, `connection_lifecycle_status=pass`, `connection_lifecycle_close_failures=0`, `connection_lifecycle_accept_failures=0`, `connection_lifecycle_missing_active_client_fields=0`, `empty_payload_frame=decode_guarded`, `packet_error_aggregation=parser_guarded`, `packet_error_alerts=threshold_guarded`, `reconnect_status=repeated_live_rebootstrap_guarded`, `slow_client_status=load_matrix_guarded`, `slow_reader_matrix_status=pass`, `slow_reader_matrix_max_fast_clients=4`, `scalability_status=repeat_live_guarded`, `resource_profile_status=repeat_live_guarded`, `multi_client_live_status=pass`, `multi_client_sent_state=guarded`, `block_edit_fanout=interested_clients_guarded`, `chunk_request_ordering=guarded`, `overload_status=admission_matrix_guarded`, and `active_protocol_change=0`.

## Client State Machine

The client lifecycle is now modeled explicitly as `connecting`, `waiting_chunks`, `spawning`, `active`, `reconnecting`, and `shutdown`. The model is unit-guarded and wired to current connect success/failure, startup chunk readiness, player spawn, synchronous send errors, reader-thread network errors, minimal retry/backoff, rebootstrap position send, reader-session stale-packet filtering, and shutdown cleanup. The current runtime soak proves repeated disconnect detection, server restart recovery, reconnect success, and return to `active`; broad state reset and reconnect failure soak remain deferred.

Fresh check:

- `logs/client_state_machine_hardening_current/client-state-machine-hardening-summary.txt` reported `status=pass`, `client_lifecycle_tests=pass`, `stale_packet_policy=session_guarded`, `runtime_reconnect=repeated_live_rebootstrap_guarded`, `state_telemetry=live_marker_guarded`, `reconnect_smoke_status=pass`, `reconnect_soak_status=pass`, `reconnect_soak_cycles=3`, `reconnect_soak_successes=3`, and `active_protocol_change=0`.

## Gameplay Loop Foundation

The current mining/building loop remains `Player` raycast signal -> `GameClient` `BlockAction` -> server `World.SetBlockGlobal` -> updated chunk snapshot. The client now has a local creative hotbar inventory model with explicit slot counts and placeability validation. Full save -> reload -> visual/collision/GPU verification is owned by Block 41.

Fresh check:

- `logs/gameplay_loop_foundation_current/gameplay-loop-foundation-summary.txt` reported `status=pass`, `inventory_tests=pass`, `server_tests=pass`, `server_edit_persistence=store_save_boundary`, `full_reload_persistence=block_41_visual_guarded`, `block_edit_visual_path=godot_persisted_reload_guarded`, and `active_protocol_change=0`.

## Block Edit Persistence

Block edit persistence is now guarded at the world/storage boundary, the live server process boundary, and the Godot persisted visual boundary. Focused unit tests prove `SetBlockGlobal` place/destroy edits and negative-boundary edits are saved through `ChunkStore.SaveChunk` and reloaded by fresh `World(store)` instances, failed saves roll back the in-memory block value, and persisted load errors are propagated instead of silently regenerating flat chunks; a live server smoke proves place and destroy edits survive server restart/reopen through the normal bootstrap chunk snapshot; `scripts/block_edit_persisted_visual_smoke.sh` proves placed, destroyed-after-reload, and chunk-edge persisted edits survive restart and the restarted server's chunk reaches Godot screenshot, collision, and GPU markers.

Fresh check:

- `logs/block_edit_persistence_current/block-edit-persistence-summary.txt` reported `status=pass`, `persistence_status=runtime_guarded`, `place_reload=live_restart_guarded`, `destroy_reload=live_restart_guarded`, `runtime_reload_smoke=live_restart_guarded`, `persisted_visual_smoke=godot_guarded`, `persisted_visual_smoke_status=pass`, `persisted_visual_scenarios=3`, `persisted_visual_place_reload_status=pass`, `persisted_visual_destroy_after_reload_status=pass`, `persisted_visual_edge_place_status=pass`, `visual_collision_gpu_path=godot_persisted_reload_guarded`, `negative_boundary_edits=guarded`, `height_v1_reload=guarded`, `store_load_errors=propagated_guarded`, `save_failure_rollback=guarded`, `world_reload_test=pass`, `storage_tests=pass`, `network_tests=pass`, `dirty_update_tests=pass`, and `active_protocol_change=0`.
- `logs/block_edit_persisted_visual_smoke_current/block-edit-persisted-visual-smoke-summary.txt` reported `status=pass`, `scenarios=3`, `place_reload_status=pass`, `destroy_after_reload_status=pass`, `edge_place_status=pass`, `protocol_change=0`, and zero GPU upload failures across all three visual captures.

## Dirty Update Scalability

Dirty update scalability is now guarded by a mass dirty unit test that touches all chunk edges and multiple subchunks, an opt-in edge-runtime Godot smoke that composes single-edge, corner-edge, and repeated corner-edge dirty checks, an opt-in mixed mass-edit runtime budget that applies place/destroy actions in one Godot session, an opt-in cross-chunk mass-edit runtime budget that touches four loaded chunks, an opt-in persisted-reload dirty runtime smoke that runs dirty updates across repeated server restart/reopen cycles, and a high-count matrix gate over five persisted dirty cycles plus the current mass/cross-chunk runtime summaries. These Godot lanes remain separate from normal fast validation.

Fresh check:

- `logs/dirty_update_scalability_current/dirty-update-scalability-summary.txt` reported `status=pass`, `dirty_scalability_status=unit_edge_mixed_mass_persisted_cross_chunk_and_high_count_runtime_guarded`, `mass_dirty_unit=pass`, `dirty_tests=pass`, `edge_runtime_scripts=available`, `runtime_script_count=11`, `runtime_edge_dirty=godot_guarded`, `single_edge_compare=pass`, `corner_edge_compare=pass`, `corner_edge_repeat=pass`, `runtime_repeat_runs=2`, `runtime_mass_edit=godot_guarded`, `runtime_mass_edit_status=pass`, `runtime_mass_budget=godot_guarded`, `mass_runtime_edit_count=12`, `mass_runtime_place_actions=6`, `mass_runtime_destroy_actions=6`, `runtime_cross_chunk_mass_edit=godot_guarded`, `runtime_cross_chunk_mass_status=pass`, `cross_chunk_mass_budget=godot_guarded`, `cross_mass_runtime_cross_chunk_count=4`, `cross_mass_runtime_edit_count=8`, `cross_mass_runtime_place_actions=4`, `cross_mass_runtime_destroy_actions=4`, `runtime_persisted_dirty=godot_guarded`, `runtime_persisted_dirty_status=pass`, `persisted_runtime_soak_cycles=3`, `persisted_runtime_reload_cycles=4`, `persisted_runtime_final_verify_count=12`, `runtime_high_count_matrix=persisted_reload_matrix_guarded`, `runtime_high_count_matrix_status=pass`, `high_count_persisted_soak_cycles=5`, `high_count_persisted_final_verify_count=20`, `high_count_matrix_dirty_blocks=60`, `high_count_matrix_edit_count=40`, and `active_protocol_change=0`.
- `logs/dirty_update_high_count_runtime_current/dirty-update-high-count-runtime-summary.txt` reported `status=pass`, `high_count_status=persisted_reload_matrix_guarded`, `persisted_high_count=godot_guarded`, `matrix_status=pass`, `matrix_lane_count=3`, `persisted_soak_cycles=5`, `persisted_reload_cycles=6`, `persisted_final_verify_count=20`, `persisted_dirty_blocks=40`, `persisted_chunk_replace=40`, `persisted_edge_neighbor_subchunks=80`, `persisted_partial_subchunks=60`, `persisted_partial_saved_subchunks=60`, `persisted_terrain_queue_max_ms=2.252`, `persisted_gpu_compositor_submit_max_ms=0.141`, `persisted_process_wall_p95_ms=0.050`, `persisted_gpu_upload_fail=0`, `matrix_dirty_blocks=60`, `matrix_chunk_replace=60`, `matrix_edit_count=40`, and `active_protocol_change=0`.
- `logs/dirty_update_runtime_smoke_current/dirty-update-runtime-smoke-summary.txt` reported `status=pass`, `target_fps=100`, `single_edge` partial saved subchunks `2`, single-edge neighbor refresh subchunks `4`, single-edge max terrain queue `2.425ms`, corner-edge partial saved subchunks `2`, corner-edge neighbor refresh subchunks `8`, corner-edge max terrain queue `2.904ms`, repeated corner-edge `runs=2`, repeat max terrain queue `3.868ms`, max compositor submit `0.120ms`, max process wall p95 `0.039ms`, and zero GPU upload failures.
- `logs/dirty_update_mass_edit_runtime_current/dirty-update-mass-edit-runtime-summary.txt` reported `status=pass`, `runtime_mass_budget=godot_guarded`, `mass_edit_count=12`, `place_actions=6`, `destroy_actions=6`, `target_fps=100`, mixed place/destroy sequence `place:96:64:64:1,destroy:96:64:64:0,place:127:64:95:2,destroy:127:64:95:0,place:96:80:95:3,destroy:96:80:95:0,place:127:80:64:4,destroy:127:80:64:0,place:112:96:80:5,destroy:112:96:80:0,place:112:112:80:4,destroy:112:112:80:0`, `dirty_blocks=12`, `chunk_replace=12`, `dirty_edge_neighbor_subchunks=24`, `dirty_partial_subchunks=16`, `dirty_partial_saved_subchunks=20`, `current_chunk_collision=2`, `terrain_queue_max_ms=2.891` against budget `8.000`, `gpu_compositor_submit_max_ms=0.140` against budget `1.000`, `process_wall_p95_ms=0.045` against budget `1.000`, and zero GPU upload failures.
- `logs/dirty_update_cross_chunk_mass_runtime_current/dirty-update-cross-chunk-mass-runtime-summary.txt` reported `status=pass`, `runtime_cross_chunk_mass_edit=godot_guarded`, `cross_chunk_mass_budget=godot_guarded`, `cross_chunk_count=4`, `mass_edit_count=8`, `place_actions=4`, `destroy_actions=4`, `target_fps=100`, sequence `place:127:64:95:1,destroy:127:64:95:0,place:95:64:63:2,destroy:95:64:63:0,place:128:80:64:3,destroy:128:80:64:0,place:96:96:96:4,destroy:96:96:96:0`, `dirty_blocks=8`, `chunk_replace=8`, `dirty_edge_neighbor_subchunks=28`, `dirty_partial_subchunks=12`, `dirty_partial_saved_subchunks=12`, `current_chunk_collision=2`, `terrain_queue_max_ms=2.358` against budget `8.000`, `gpu_compositor_submit_max_ms=0.147` against budget `1.000`, `process_wall_p95_ms=0.051` against budget `1.000`, and zero GPU upload failures.
- `logs/dirty_update_persisted_reload_runtime_current/dirty-update-persisted-reload-runtime-summary.txt` reported `status=pass`, `soak_status=pass`, `soak_cycles=3`, `reload_cycles=4`, `dirty_after_reload=pass`, `final_reload=pass`, `final_verify_count=12`, `mass_edit_count=4`, `target_fps=100`, seed block id `4`, `soak_dirty_blocks=24`, `soak_chunk_replace=24`, `soak_edge_neighbor_subchunks=48`, `soak_partial_subchunks=36`, `soak_partial_saved_subchunks=36`, `soak_current_chunk_collision=6`, `terrain_queue_max_ms=2.458`, `gpu_compositor_submit_max_ms=0.184`, `process_wall_p95_ms=0.062`, and zero GPU upload failures.

## Storage Persistence Foundation

The storage foundation slice keeps RocksDB as the implemented chunk persistence backend and does not add PostgreSQL behavior. It adds focused coverage for missing chunks, save/reopen round-trips, overwrite isolation between neighboring chunk keys, concurrent distinct-key save/load, corrupt persisted payload errors with chunk-coordinate context, missing-parent path creation, regular-file parent/database path rejection with path context, closed-store and nil-save lifecycle errors, and the server config boundary that keeps `RUMPELMC_SERVER_ROCKSDB_PATH` as the only current runtime chunk-store path override.

Fresh check:

- `go test ./pkg/storage` and `go test -race ./pkg/storage` passed on 2026-06-16 with RocksDB closed-store and nil-save lifecycle coverage.

## Long-Run Exploration Soak

The exploration soak wrapper repeats movement stress runs and aggregates long-run signals: packet queue drain/lag, unload churn, pop-in counters, render/collision readiness, GPU upload failures, terrain queue latency, and compositor submit time. Defaults are bounded and report-only; raise `RUMPELMC_EXPLORATION_SOAK_REPEATS` for long or overnight runs.

Fresh smoke:

- `logs/world_streaming_exploration_soak_smoke/world-streaming-exploration-soak-summary.txt` passed a single fast-turn run with `max_terrain_queue_ms=2.147`, `max_packet_queue_drain=36`, `max_packet_queue_lag_ms=15.330`, `max_chunk_unload_total=0`, `gpu_upload_fail=0`, `ground_misses=0`, and final render/collision readiness.

## GPU Terrain Load Scaling

The load-scaling gate requires a high resident set before treating GPU terrain scaling as covered: at least `2000` subchunks, `2000` draws, `3000` faces, and at least `25%` draw-command buffer occupancy with zero upload failures.

Fresh check:

- `logs/gpu_terrain_load_scaling_radius16_summary_check/gpu-terrain-load-scaling-summary.txt` passed over the radius-16 resident-set artifact with `max_gpu_subchunks=2482`, `max_gpu_draws=2482`, `max_gpu_faces=3296`, draw-command occupancy `30.298%`, `max_terrain_queue_ms=3.453`, and `gpu_upload_fail=0`.

## GPU Upload Pressure

The upload-pressure gate composes fill stress and allocator stress. It is meant to pressure draw/fill work while still checking upload failure causes and allocator fragmentation before any upload capacity or allocator behavior changes.

Fresh check:

- `logs/gpu_terrain_upload_pressure_smoke/gpu-upload-pressure-summary.txt` passed with repeat `1` plus report-only repeat `16`, `max_gpu_effective_draws=21216`, `gpu_upload_fail=0`, `gpu_upload_fail_capacity=0`, `gpu_upload_fail_fragmented=0`, `max_gpu_fragmentation_pct=0.0`, and `max_terrain_queue_ms=2.079`.

## GPU Terrain Memory Budget

The memory budget gate is summary-only. It turns current resident memory, draw-command, face/subchunk, fragmentation, and upload-failure evidence into explicit budgets before any allocator or eviction policy changes.

Fresh check:

- `logs/gpu_terrain_memory_budget_current/gpu-terrain-memory-budget-summary.txt` passed with configured terrain buffers `67,239,936` bytes under the `70,254,592` byte budget, active terrain bytes `52,736` under the `4,194,304` byte budget, `gpu_subchunks=2482`, `gpu_draws=2482`, `gpu_faces=3296`, draw-command occupancy `30.298%`, draw-command headroom `91,360` bytes, fragmentation `0.0%`, and zero upload failures.

## GPU Report System V2

The V2 report wrapper keeps the existing aggregate report but explicitly separates fresh scoped metrics, fail gates, historical aggregate maxima, and warning-only local signals.

Fresh check:

- `logs/gpu_terrain_report_v2_current/gpu-terrain-report-v2-summary.txt` passed with scoped status `pass`, resource lifecycle status `pass`, memory budget status `pass`, clean legacy error scan, historical `gpu_effective_draws=21216`, historical upload failures `0`, and warning-only local `frame_p95_ms=8.368`.

## Performance Baseline Governance

The baseline governance check compares the classified V2 report against an accepted baseline file and keeps local FPS/GPU timestamp fields warning-only.

Fresh check:

- `logs/performance_baseline_governance_current/performance-baseline-governance-summary.txt` passed against `docs/performance_baselines/gpu_terrain_world_streaming.baseline` with baseline id `gpu_terrain_world_streaming_20260615`, historical effective draw coverage `21216` over the `20000` minimum, upload failures `0`, fragmentation `0.0%`, draw-command occupancy `16.296%`, and warning status `ok`.

## Test Strategy

The check strategy separates daily `fast`, pre-merge `full`, and heavy/nightly performance evidence. Nightly runtime work remains outside `check.sh` so normal checks do not depend on local Godot capture timing or existing logs.

Fresh check:

- `logs/test_strategy_gate_current/test-strategy-gate-summary.txt` passed with fast command `./scripts/check.sh fast`, full command `./scripts/check.sh full && git diff --check && ./scripts/diff_guard.sh`, and summary/nightly gates for exploration soak, load scaling, upload pressure, resource lifecycle, memory budget, report V2, GPU report freshness, and baseline governance.

## GPU Repack Activation Preflight

Active GPU terrain buffer repack remains disabled. The activation preflight reads upload-pressure and load-scaling summaries and allows no active swap while there is no upload failure or fragmentation pressure.

Fresh check:

- `logs/gpu_repack_activation_preflight_current/gpu-repack-activation-preflight-summary.txt` reported `status=deferred`, `active_repack_allowed=0`, `reason=no_fragmentation_pressure`, `max_gpu_fragmentation_pct=0.0`, and zero upload failures.

## GPU Repack Soak And Rollback

Active repack soak is deferred while activation preflight reports `active_repack_allowed=0`. The soak/rollback gate exists so deferred status is explicit and not confused with active-repack coverage.

Fresh check:

- `logs/gpu_repack_soak_rollback_gate_current/gpu-repack-soak-rollback-summary.txt` reported `status=deferred`, `active_soak_run=0`, `reason=active_repack_not_allowed`, and `preflight_reason=no_fragmentation_pressure`.

## Current Baseline

- Server chunks are `32 x 32 x 512`.
- `world.Chunk.Serialize()` emits a full little-endian `u16` block array.
- A full raw chunk payload is `1,048,576` bytes before protobuf and TCP framing.
- `server/pkg/network` sends RLE `ChunkData.blocks` by default after the Rust client decodes them back to the same raw block bytes.
- `RUMPELMC_SERVER_CHUNK_ENCODING=raw` switches chunk payloads back to the raw full chunk rollback path.
- The default server stream sends up to `64` chunks per update, ordered nearest-first by chunk distance with stable same-distance tie-breaks.
- `RUMPELMC_SERVER_VIEW_DISTANCE` keeps valid positive overrides, rejects non-positive values back to the default, and clamps stress values to the configured maximum.
- `RUMPELMC_SERVER_CHUNK_ORDER=directional` enables opt-in movement-direction tie-break ordering while leaving nearest-first as the default.
- `RUMPELMC_SERVER_CHUNKS_PER_UPDATE=6` restores the previous conservative stream batch.
- The default first post-connect stream uses bootstrap radius `0`, sending only the current chunk first; normal position updates then continue with the full view distance.
- `RUMPELMC_SERVER_BOOTSTRAP_RADIUS=1` restores the previous default startup stream; `RUMPELMC_SERVER_BOOTSTRAP_RADIUS=2` restores the earlier wider startup stream; `RUMPELMC_SERVER_BOOTSTRAP_RADIUS=full` restores full view-distance startup streaming.
- Packet queue metrics are observational only; they do not limit, drop, delay, or reorder packet delivery.
- Resident-set growth runs use stress-only view/keep distances and do not change default gameplay distance or visual quality.
- Client chunk unload remains keep-distance plus grace based by default; immediate unload is a control path through `RUMPELMC_CLIENT_CHUNK_UNLOAD_GRACE_SEC=0`.
- Pop-in metrics are report-only player-neighborhood probes; they do not fail movement gates until explicit budgets are defined.
- Movement readiness separates final render-ready and collision-ready evidence; player spawn remains collision-gated.
- Client collision radius remains `1` by default; `RUMPELMC_CLIENT_COLLISION_CHUNK_DISTANCE=0` is an opt-in lazy-collision experiment only.
- Worldgen determinism is covered by focused `server/pkg/world` tests including origin chunk flat strata and representative flat byte-hash coverage; generation behavior, chunk dimensions, serialization order, protocol, and storage remain unchanged.
- Chunk serialization compatibility is guarded by focused `server/pkg/api`, `server/pkg/world`, and `server/pkg/network` tests for empty-packet zero-wire bytes, field numbers, enum values, raw defaults, RLE wire vectors, and protobuf unknown fields.
- Protocol generated-code drift is guarded by `scripts/protocol_generated_drift_gate.sh`, which rejects partial schema/generated diffs and checks generated-code identity headers.
- Networking robustness is guarded by focused Go and Rust packet-boundary tests, empty/unknown/nil-packet/nil-position/nil-block-action ignore policy, and opt-in max-client admission with bounded live rejection evidence; adaptive overload and backpressure policy remain deferred and must not change the wire contract without a protocol task.
- Client lifecycle state is modeled as connecting, waiting chunks, spawning, active, reconnecting, and shutdown; bounded repeated reconnect/rebootstrap execution and state telemetry are guarded, while stale packet and reset behavior remain deferred.
- Gameplay foundation keeps mining/building on `BlockAction` and `World.SetBlockGlobal`; local hotbar inventory is client-only and full edit reload persistence is deferred to the block-edit persistence gate.
- Block edit persistence has a world-level save/reload guard for place and destroy edits, save-failure rollback, and persisted load-error propagation; runtime persisted-reload visual/collision/GPU smoke is still a heavier deferred check.
- Dirty update scalability has a mass dirty unit guard, opt-in edge-runtime Godot smoke, bounded opt-in mass-edit runtime smoke, and bounded opt-in persisted-reload dirty runtime smoke; broader runtime mass-edit budgets remain separate from normal checks.
- RocksDB chunk persistence is guarded by focused `server/pkg/storage` tests for key format, sorted signed coordinate keys, round-trip save/load, missing chunks, overwrite isolation, concurrent distinct-key save/load, actionable open/decode error context, corrupt payload errors, regular-file parent/database path rejection, repeated close safety, closed-store operation errors, and nil chunk save rejection.
- Long-run exploration soak is available as a bounded report-only wrapper by default; do not treat the one-run smoke as multi-hour stability evidence.
- GPU terrain load scaling is guarded by `scripts/gpu_terrain_load_scaling.sh`; standard 996-draw workload results are not enough for this gate.
- GPU upload pressure is guarded by `scripts/gpu_terrain_upload_pressure.sh`; it must stay evidence-only unless a separate task explicitly changes upload capacity, allocator policy, or visible quality.
- GPU repack activation is currently deferred by preflight. Do not activate final buffer/render-binding/slot/allocator swaps while `active_repack_allowed=0`.
- GPU repack soak/rollback coverage is also deferred while active repack is not allowed; do not cite deferred soak as active-repack runtime validation.

## First Optimization Path

Use a compatible staged rollout:

1. Keep the existing raw chunk format as an explicit rollback path.
2. Add a deterministic block-run RLE codec over the existing serialized chunk bytes.
3. Benchmark raw serialize, RLE encode, and RLE decode on representative chunks.
4. Use the new compatible `ChunkData.encoding` and `ChunkData.uncompressed_size` fields for encoded chunks.
5. Make encoded chunk streaming the default only after visual smoke and movement streaming evidence pass, while preserving `RUMPELMC_SERVER_CHUNK_ENCODING=raw` rollback.

## Current RLE Evidence

The first server-side codec slice added `EncodeSerializedChunkRLE` and `DecodeSerializedChunkRLE` without changing storage behavior. The follow-up protocol slice added an opt-in RLE path, and the validated default-on slice makes RLE the server default while keeping `RUMPELMC_SERVER_CHUNK_ENCODING=raw` as rollback.

On the current flat generated chunk, the raw payload is `1,048,576` bytes and the RLE payload is below `64` bytes because the chunk contains long vertical strata and air runs.
`TestEncodeSerializedChunkRLERoundTripsHeightV1Chunk` adds representative opt-in non-flat terrain coverage: the encoded `height_v1` chunk must be richer than the flat fixture, remain smaller than raw serialized bytes, decode back to the exact raw bytes, and preserve varied surface columns.
`logs/server_height_generator_smoke_current/server-height-generator-smoke-summary.txt` reported `status=pass`, `generator_version=height_v1`, `encoding=rle`, `payload_bytes=5258`, `raw_bytes=1048576`, `raw_sha256=1101411ccf572478dc9dee8772428714fd80d5ea9f82f491401e2ca410369dc7`, `surface_min=62`, `surface_max=79`, `varied_surface=1`, and `protocol_change=0`.

Local benchmark command:

```sh
cd server
go test ./pkg/world -bench 'Benchmark(ChunkSerializeFlat|EncodeSerializedChunkRLEFlat|DecodeSerializedChunkRLEFlat)' -benchtime=100ms -run '^$'
```

Latest local result on Apple M4:

- `BenchmarkChunkSerializeFlat`: about `431597 ns/op`, `1,052,144 B/op`.
- `BenchmarkEncodeSerializedChunkRLEFlat`: about `421359 ns/op`, `7,662 B/op`.
- `BenchmarkDecodeSerializedChunkRLEFlat`: about `268477 ns/op`, `1,053,090 B/op`.

Latest protocol-level batch guard for three generated flat chunks:

```sh
cd server
go test ./pkg/network -run 'TestRLEChunkBatchShrinksPayloadAndWireBytes|TestSendChunkCanUseRLEPayload' -v
```

- RAW payload bytes: `3,145,728`.
- RLE payload bytes: `54`.
- RAW framed wire bytes: `3,145,786`.
- RLE framed wire bytes: `118`.
- RLE stayed below `1%` of RAW for both payload and framed wire bytes in this guard.

The 2026-06-13 handshake fix makes the Rust client send an initial `ClientPosition` packet immediately after connecting. The server waits briefly for that packet before starting the initial stream, treats a closed probe as a closed probe instead of sending initial chunks into it, and keeps the old `(0,0)` initial stream fallback when no packet arrives before the timeout.

Latest visual movement smoke evidence from 2026-06-13 used the release Rust extension profile and direct Godot launch because earlier wrapper attempts were invalid when the profile shim was not active in the same shell:

- RAW movement log: `logs/world_streaming_raw_visual_20260613/movement.godot.log`.
- RLE movement marker: `logs/world_streaming_rle_visual_20260613/movement.godot.log`.
- RLE server metrics for that movement run: `logs/world_streaming_rle_visual_20260613/godot.log`.
- Both runs passed `smoke_err=0`, `motion_steps=4`, `motion_chunks=4`, `current_chunk_loaded=1`, `current_chunk_collision=2`, `ground_hits=9`, and ended at `current_chunk="3,2"`.
- The RLE client decoded streamed chunks back to `blocks=1048576` before the normal terrain path consumed them.
- RAW movement totals: `132` chunks, raw bytes `138,412,032`, payload bytes `138,412,032`, framed wire bytes `138,414,760`.
- RLE movement totals: `132` chunks, raw bytes `138,412,032`, payload bytes `2,646`, framed wire bytes `5,640`.
- In this generated-world movement smoke, RLE framed wire bytes were about `0.0041%` of RAW framed wire bytes.

The reproducible wrapper gate for the same path is:

```sh
RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE=1 RUMPELMC_GODOT_RUST_EXT_PROFILE=release scripts/world_streaming_rle_movement_smoke.sh logs/world_streaming_rle_wrapper_20260613
```

It rebuilds `server/server`, requires port `25565` to be free, starts the normal movement stress with `RUMPELMC_SERVER_CHUNK_ENCODING=rle` and `RUMPELMC_SERVER_CHUNK_STREAM_METRICS=1`, validates the movement marker, validates that the client decoded RLE chunks to `blocks=1048576`, requires RLE payload and framed wire bytes to stay below `1%` of raw bytes, writes `world-streaming-rle-summary.txt`, and cleans up the local server.

Fresh wrapper result:

- Summary: `logs/world_streaming_rle_wrapper_20260613/world-streaming-rle-summary.txt`.
- Status: `pass`.
- Batches/chunks: `22` / `132`.
- Raw/payload/wire bytes: `138,412,032` / `2,646` / `5,640`.
- Payload/wire percent of raw: `0.001912%` / `0.004075%`.

Fresh default-on result with `RUMPELMC_SERVER_CHUNK_ENCODING` unset:

- Summary: `logs/world_streaming_default_rle_20260613/world-streaming-default-rle-summary.txt`.
- Status: `pass`.
- Batches/chunks: `22` / `132`.
- Raw/payload/wire bytes: `138,412,032` / `2,646` / `5,640`.
- Payload/wire percent of raw: `0.001912%` / `0.004075%`.

The RAW-vs-RLE comparison gate is:

```sh
RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE=1 RUMPELMC_GODOT_RUST_EXT_PROFILE=release scripts/world_streaming_chunk_encoding_compare.sh logs/world_streaming_encoding_compare_20260613
```

It runs the same movement stress twice, first with `RUMPELMC_SERVER_CHUNK_ENCODING=raw` and then with `rle`, compares normalized payload and wire bytes per raw streamed byte, and writes `world-streaming-encoding-compare-summary.txt`. The RLE run may legitimately stream more chunks in the same smoke window when the transport is faster, so this gate does not require identical chunk counts.

Fresh default-on comparison result:

- Summary: `logs/world_streaming_encoding_compare_default_final2_20260613/world-streaming-encoding-compare-summary.txt`.
- Status: `pass`.
- RAW chunks/raw bytes: `138` / `144,703,488`.
- RLE chunks/raw bytes: `138` / `144,703,488`.
- RAW payload/wire bytes: `144,703,488` / `144,706,330`.
- RLE payload/wire bytes: `2,754` / `5,874`.
- RAW payload/wire percent of raw: `100.000000%` / `100.001964%`.
- RLE payload/wire percent of raw: `0.001903%` / `0.004059%`.

Fresh encoding startup timing comparison result:

- Summary: `logs/world_streaming_encoding_startup_timing_20260613/world-streaming-encoding-compare-summary.txt`.
- Status: `pass`.
- RAW/RLE encoding summaries now include startup chunk-loaded, collision-ready, and player-spawn timings for each run and in the top-level compare artifact.
- RAW: `394` chunks, payload/wire percent of raw `100.000000%` / `100.002195%`, startup chunk/collision/player spawn `91.070ms / 91.070ms / 91.070ms`.
- RLE: `394` chunks, payload/wire percent of raw `0.001782%` / `0.004168%`, startup chunk/collision/player spawn `84.197ms / 84.197ms / 84.197ms`.

The combined world-loading regression pack is:

```sh
RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE=1 RUMPELMC_GODOT_RUST_EXT_PROFILE=release /bin/sh scripts/world_streaming_regression_pack.sh logs/world_streaming_regression_pack_20260613
```

It builds and signs `server/server` once, then runs bootstrap, batch-size, RAW-vs-RLE encoding, and standalone RLE movement gates through the existing wrappers with nested server rebuilds disabled. It writes `world-streaming-regression-summary.txt` as a single top-level pass/fail artifact.

Fresh regression pack result:

- Summary: `logs/world_streaming_regression_pack_20260613/world-streaming-regression-summary.txt`.
- Status: `pass`.
- Bootstrap default radius `0`: first stream `1` chunk, startup player spawn `93.318ms`.
- Batch `64`: `394` chunks over `9` batches, startup player spawn `83.367ms`.
- Encoding compare RLE: `394` chunks, wire percent of raw `0.004168%`, startup player spawn `95.459ms`.
- Standalone RLE movement: `394` chunks, wire percent of raw `0.004168%`, startup player spawn `87.231ms`.

The RLE batch-size comparison gate is:

```sh
RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE=1 RUMPELMC_GODOT_RUST_EXT_PROFILE=release /bin/sh scripts/world_streaming_batch_compare.sh logs/world_streaming_batch_compare_20260613_retry
```

It runs the same movement stress twice with the default RLE encoding, first with rollback batch `RUMPELMC_SERVER_CHUNKS_PER_UPDATE=6` and then with candidate/default batch `64`, validates movement/collision/ground/upload markers, records chunk stream metrics, and writes `world-streaming-batch-compare-summary.txt`.

Fresh batch comparison result:

- Summary: `logs/world_streaming_batch_compare_20260613_retry/world-streaming-batch-compare-summary.txt`.
- Status: `pass`.
- Batch `6`: `22` stream batches, `132` chunks, payload/wire percent of raw `0.001912%` / `0.004075%`, `terrain_queue_max_ms=2.065`, `process_wall_p95_ms=0.035`, `gpu_compositor_submit_max_ms=0.109`.
- Batch `64`: `8` stream batches, `394` chunks, payload/wire percent of raw `0.001782%` / `0.004168%`, `terrain_queue_max_ms=1.560`, `process_wall_p95_ms=0.036`, `gpu_compositor_submit_max_ms=0.109`.

Fresh batch startup timing comparison result:

- Summary: `logs/world_streaming_batch_startup_timing_20260613/world-streaming-batch-compare-summary.txt`.
- Status: `pass`.
- Batch compare summaries now include startup chunk-loaded, collision-ready, and player-spawn timings for each run and in the top-level compare artifact.
- Batch `6`: `23` stream batches, `133` chunks, startup chunk/collision/player spawn `97.389ms / 97.389ms / 97.389ms`, `terrain_queue_max_ms=2.225`, `process_wall_p95_ms=0.050`, `gpu_compositor_submit_max_ms=0.225`.
- Batch `64`: `9` stream batches, `394` chunks, startup chunk/collision/player spawn `76.650ms / 76.650ms / 76.650ms`, `terrain_queue_max_ms=2.052`, `process_wall_p95_ms=0.054`, `gpu_compositor_submit_max_ms=0.140`.

Fresh default batch `64` result with `RUMPELMC_SERVER_CHUNKS_PER_UPDATE` unset:

- Summary: `logs/world_streaming_default_batch64_20260613/world-streaming-default-batch64-summary.txt`.
- Status: `pass`.
- Batches/chunks: `8` / `394`.
- Raw/payload/wire bytes: `413,138,944` / `7,362` / `17,219`.
- Payload/wire percent of raw: `0.001782%` / `0.004168%`.
- Client markers: `current_chunk_loaded=1`, `current_chunk_collision=2`, `ground_hits=9`, `gpu_upload_fail=0`, and `chunk_initial=394`.

Fresh post-default batch comparison result:

- Summary: `logs/world_streaming_batch_default64_compare_20260613/world-streaming-batch-compare-summary.txt`.
- Status: `pass`.
- Rollback batch `6`: `22` stream batches, `132` chunks, `terrain_queue_max_ms=1.648`, `process_wall_p95_ms=0.038`, `gpu_compositor_submit_max_ms=0.138`.
- Default batch `64`: `8` stream batches, `394` chunks, `terrain_queue_max_ms=1.903`, `process_wall_p95_ms=0.038`, `gpu_compositor_submit_max_ms=0.159`.

## Bootstrap Radius

The server sends a smaller first stream around the initial client position before normal `RUMPELMC_SERVER_VIEW_DISTANCE` updates take over. Leaving `RUMPELMC_SERVER_BOOTSTRAP_RADIUS` unset uses the default radius `0`; set it to `1` to restore the previous default startup stream, `2` to restore the earlier wider startup stream, or `full` to restore full-radius startup streaming.

Use it to tune faster time-to-current-chunk without changing chunk encoding, batch size, protocol, storage, world generation, or client decode behavior:

```sh
RUMPELMC_SERVER_BOOTSTRAP_RADIUS=0 RUMPELMC_SERVER_CHUNK_STREAM_METRICS=1
```

The bootstrap-radius comparison gate is:

```sh
/bin/sh scripts/world_streaming_bootstrap_compare.sh logs/world_streaming_bootstrap_compare_20260613
```

It runs the same movement stress twice with default RLE encoding and batch `64`: first with rollback full-radius startup, then with candidate/default bootstrap radius `0`. It validates movement/collision/ground/upload markers, requires the candidate first stream to be smaller than the full startup stream, and writes `world-streaming-bootstrap-compare-summary.txt`.

Fresh opt-in bootstrap radius result:

- Summary: `logs/world_streaming_bootstrap_radius2_20260613/world-streaming-bootstrap-radius-summary.txt`.
- Status: `pass`.
- First stream: `radius=2`, `13` chunks, raw/payload/wire bytes `13,631,488` / `413` / `701`, elapsed `39.793ms`.
- Full run: `9` stream batches, `394` chunks, raw/payload/wire bytes `413,138,944` / `7,362` / `17,219`.
- Client markers: `current_chunk_loaded=1`, `current_chunk_collision=2`, `ground_hits=9`, `gpu_upload_fail=0`, and `chunk_initial=394`.

Fresh bootstrap comparison result:

- Summary: `logs/world_streaming_bootstrap_compare_20260613/world-streaming-bootstrap-compare-summary.txt`.
- Status: `pass`.
- Full startup: first stream `radius=10`, `64` chunks, total `394` chunks over `8` batches, `terrain_queue_max_ms=1.183`, `process_wall_p95_ms=0.037`, `gpu_compositor_submit_max_ms=0.126`.
- Bootstrap radius `2`: first stream `radius=2`, `13` chunks, total `394` chunks over `9` batches, `terrain_queue_max_ms=1.577`, `process_wall_p95_ms=0.034`, `gpu_compositor_submit_max_ms=0.105`.

Fresh post-default bootstrap comparison result:

- Summary: `logs/world_streaming_bootstrap_default2_compare_20260613/world-streaming-bootstrap-compare-summary.txt`.
- Status: `pass`.
- Rollback full startup: first stream `radius=10`, `64` chunks, total `394` chunks over `8` batches, `terrain_queue_max_ms=1.436`, `process_wall_p95_ms=0.038`, `gpu_compositor_submit_max_ms=0.291`.
- Default bootstrap radius `2`: first stream `radius=2`, `13` chunks, total `394` chunks over `9` batches, `terrain_queue_max_ms=1.426`, `process_wall_p95_ms=0.037`, `gpu_compositor_submit_max_ms=0.139`.

Fresh next-candidate bootstrap comparison result:

- Summary: `logs/world_streaming_bootstrap_radius1_compare_20260613/world-streaming-bootstrap-compare-summary.txt`.
- Status: `pass`.
- Rollback full startup: first stream `radius=10`, `64` chunks, total `394` chunks over `8` batches, `terrain_queue_max_ms=1.995`, `process_wall_p95_ms=0.039`, `gpu_compositor_submit_max_ms=0.251`.
- Candidate bootstrap radius `1`: first stream `radius=1`, `5` chunks, total `394` chunks over `9` batches, `terrain_queue_max_ms=1.758`, `process_wall_p95_ms=0.045`, `gpu_compositor_submit_max_ms=0.109`.

Fresh post-default radius `1` comparison result:

- Summary: `logs/world_streaming_bootstrap_default1_compare_20260613/world-streaming-bootstrap-compare-summary.txt`.
- Status: `pass`.
- Rollback full startup: first stream `radius=10`, `64` chunks, total `394` chunks over `8` batches, `terrain_queue_max_ms=1.276`, `process_wall_p95_ms=0.036`, `gpu_compositor_submit_max_ms=0.162`.
- Default bootstrap radius `1`: first stream `radius=1`, `5` chunks, total `394` chunks over `9` batches, `terrain_queue_max_ms=1.508`, `process_wall_p95_ms=0.039`, `gpu_compositor_submit_max_ms=0.129`.

Fresh current-chunk bootstrap candidate result:

- Summary: `logs/world_streaming_bootstrap_radius0_compare_20260613/world-streaming-bootstrap-compare-summary.txt`.
- Status: `pass`.
- Rollback full startup: first stream `radius=10`, `64` chunks, total `394` chunks over `8` batches, `terrain_queue_max_ms=2.367`, `process_wall_p95_ms=0.050`, `gpu_compositor_submit_max_ms=0.128`.
- Candidate bootstrap radius `0`: first stream `radius=0`, `1` chunk, total `394` chunks over `9` batches, `terrain_queue_max_ms=2.107`, `process_wall_p95_ms=0.053`, `gpu_compositor_submit_max_ms=0.155`.

Fresh post-default radius `0` comparison result:

- Summary: `logs/world_streaming_bootstrap_default0_compare_20260613/world-streaming-bootstrap-compare-summary.txt`.
- Status: `pass`.
- Rollback full startup: first stream `radius=10`, `64` chunks, total `394` chunks over `8` batches, `terrain_queue_max_ms=1.989`, `process_wall_p95_ms=0.033`, `gpu_compositor_submit_max_ms=0.224`.
- Default bootstrap radius `0`: first stream `radius=0`, `1` chunk, total `394` chunks over `9` batches, `terrain_queue_max_ms=1.728`, `process_wall_p95_ms=0.044`, `gpu_compositor_submit_max_ms=0.102`.

Fresh initial player startup contract result:

- Summary: `logs/world_streaming_initial_contract_default0_20260613/world-streaming-bootstrap-compare-summary.txt`.
- Status: `pass`.
- The Rust client now derives the initial position packet, spawn position, and pre-spawn mesh subchunks from one startup contract.
- Rollback full startup: first stream `radius=10`, `64` chunks, total `394` chunks over `8` batches, `terrain_queue_max_ms=1.008`, `process_wall_p95_ms=0.022`, `gpu_compositor_submit_max_ms=0.339`.
- Default bootstrap radius `0`: first stream `radius=0`, `1` chunk, total `394` chunks over `9` batches, `terrain_queue_max_ms=1.340`, `process_wall_p95_ms=0.020`, `gpu_compositor_submit_max_ms=0.195`.

Fresh pre-spawn startup queue hint result:

- Summary: `logs/world_streaming_startup_queue_hint_default0_20260613/world-streaming-bootstrap-compare-summary.txt`.
- Status: `pass`.
- The Rust client now uses the startup chunk contract as the mesh/collision queue hint until `current_player_chunk` is available, while collision and shadow fallback still target only the startup chunk before player spawn.
- Rollback full startup: first stream `radius=10`, `64` chunks, total `394` chunks over `8` batches, `terrain_queue_max_ms=0.915`, `process_wall_p95_ms=0.019`, `gpu_compositor_submit_max_ms=0.124`.
- Default bootstrap radius `0`: first stream `radius=0`, `1` chunk, total `394` chunks over `9` batches, `terrain_queue_max_ms=1.487`, `process_wall_p95_ms=0.022`, `gpu_compositor_submit_max_ms=0.158`.

Fresh startup timing telemetry result:

- Summary: `logs/world_streaming_startup_timing_default0_20260613/world-streaming-bootstrap-compare-summary.txt`.
- Status: `pass`.
- The Rust client marker now reports `startup_chunk_loaded_ms`, `startup_collision_ms`, and `startup_player_spawn_ms`; the movement and bootstrap summaries surface the same startup timing fields.
- World streaming wrapper scripts invoke nested shell scripts through `/bin/sh` to avoid a local macOS `/usr/bin/env` shebang hang observed during redirected harness runs.
- Rollback full startup: first stream `radius=10`, `64` chunks, startup player spawn `105.392ms`, total `394` chunks over `8` batches, `terrain_queue_max_ms=2.139`, `process_wall_p95_ms=0.050`, `gpu_compositor_submit_max_ms=0.140`.
- Default bootstrap radius `0`: first stream `radius=0`, `1` chunk, startup player spawn `70.746ms`, total `394` chunks over `9` batches, `terrain_queue_max_ms=2.151`, `process_wall_p95_ms=0.051`, `gpu_compositor_submit_max_ms=0.159`.

Fresh startup timing gate result:

- Summary: `logs/world_streaming_startup_metric_gate_20260613/world-streaming-bootstrap-compare-summary.txt`.
- Status: `pass`.
- `scripts/gpu_terrain_movement_stress.sh` now fails if `startup_chunk_loaded_ms`, `startup_collision_ms`, or `startup_player_spawn_ms` is missing or non-positive, and `scripts/world_streaming_bootstrap_compare.sh` enforces the same requirement before writing per-run summaries.
- `scripts/gpu_terrain_movement_stress.sh` also requires startup timings to be ordered as `chunk_loaded_ms <= collision_ms <= player_spawn_ms`, so the gate catches misplaced instrumentation or early player spawn regressions.
- The final bootstrap compare summary now includes base/candidate `startup_chunk_loaded_ms`, `startup_collision_ms`, and `startup_player_spawn_ms` so startup readiness regressions are visible in the top-level artifact.
- Rollback full startup: first stream `radius=10`, `64` chunks, startup chunk/collision/player spawn `120.459ms / 120.459ms / 120.459ms`, total `394` chunks over `8` batches, `terrain_queue_max_ms=2.151`, `process_wall_p95_ms=0.052`, `gpu_compositor_submit_max_ms=0.208`.
- Default bootstrap radius `0`: first stream `radius=0`, `1` chunk, startup chunk/collision/player spawn `78.157ms / 78.157ms / 78.157ms`, total `394` chunks over `9` batches, `terrain_queue_max_ms=4.510`, `process_wall_p95_ms=0.053`, `gpu_compositor_submit_max_ms=0.132`.

Fresh startup phase telemetry result:

- Summary: `logs/world_streaming_startup_phase_regression_20260613_retry/world-streaming-regression-summary.txt`.
- Status: `pass`.
- The Rust client marker now splits startup readiness into `startup_chunk_loaded_ms`, `startup_mesh_queued_ms`, `startup_first_mesh_ms`, `startup_collision_ms`, and `startup_player_spawn_ms`; movement, bootstrap, batch, RAW-vs-RLE encoding, standalone RLE, and the combined regression pack summaries surface the same fields where relevant.
- `scripts/gpu_terrain_movement_stress.sh` now requires startup timings to be ordered as `chunk_loaded_ms <= mesh_queued_ms <= first_mesh_ms <= collision_ms <= player_spawn_ms`.
- The first runtime attempt in `logs/world_streaming_startup_phase_regression_20260613` hit the known screenshot-capture timeout after movement reached chunk `3,2`; retrying with `GODOT_TIMEOUT_SEC=240` passed.
- Bootstrap candidate radius `0`: first stream `1` chunk, startup first mesh/player spawn `94.706ms / 94.706ms`.
- Batch candidate `64`: streamed `394` chunks over `9` batches, startup first mesh/player spawn `87.334ms / 87.334ms`.
- Encoding RLE: `394` chunks, wire percent `0.004168%`, startup first mesh/player spawn `93.806ms / 93.806ms`.
- Standalone RLE: `394` chunks, wire percent `0.004168%`, startup first mesh/player spawn `90.329ms / 90.329ms`.

Fresh startup first-mesh work breakdown result:

- Summary: `logs/world_streaming_startup_work_breakdown_20260613_frames_retry/world-streaming-regression-summary.txt`.
- Status: `pass`.
- The Rust client marker now separates first startup mesh work duration from the wall-clock startup timestamp: `startup_first_mesh_work_ms` records the first geometry-changed mesh job duration, `startup_first_mesh_phase_ms` records the phase split, and `startup_first_mesh_collision_work_ms` records collision work for that first mesh job.
- Movement, bootstrap, batch, RAW-vs-RLE encoding, standalone RLE, and the combined regression pack summaries surface the numeric first-mesh work fields where relevant.
- Two earlier runtime attempts reached the expected movement chunk but exited before the PNG marker was saved; the passing run used `GODOT_QUIT_AFTER_FRAMES=30000` to avoid early Godot exit during screenshot capture.
- Bootstrap candidate radius `0`: first stream `1` chunk, startup first mesh/work/collision work `63.932ms / 4.308ms / 3.530ms`.
- Batch candidate `64`: streamed `394` chunks over `9` batches, startup first mesh/work/collision work `88.853ms / 4.143ms / 3.418ms`.
- Encoding RLE: `394` chunks, wire percent `0.004168%`, startup first mesh/work/collision work `78.148ms / 4.729ms / 3.940ms`.
- Standalone RLE: `394` chunks, wire percent `0.004168%`, startup first mesh/work/collision work `78.337ms / 4.223ms / 3.527ms`.

Fresh startup receive/decode breakdown result:

- Summary: `logs/world_streaming_startup_receive_breakdown_20260613/world-streaming-regression-summary.txt`.
- Status: `pass`.
- The Rust client marker now separates startup packet arrival, packet read/decode work, chunk block decode work, chunk insertion, mesh dispatch, first mesh work, collision work, and player spawn. Movement, bootstrap, batch, RAW-vs-RLE encoding, standalone RLE, and the combined regression pack summaries surface the new packet/decode/dispatch fields where relevant.
- `scripts/gpu_terrain_movement_stress.sh` now requires startup timings to be ordered as `packet_ms <= chunk_inserted_ms <= chunk_loaded_ms <= mesh_queued_ms <= mesh_dispatched_ms <= first_mesh_ms <= collision_ms <= player_spawn_ms`; the default quit-after frame budget is `30000` so the smoke-owned marker save has time to complete.
- Bootstrap candidate radius `0`: first stream `1` chunk, startup packet/chunk decode/mesh dispatch/first mesh/work `89.553ms / 0.403ms / 89.553ms / 89.553ms / 5.876ms`.
- Batch candidate `64`: streamed `394` chunks over `9` batches, startup packet/chunk decode/mesh dispatch/first mesh/work `84.343ms / 0.397ms / 84.343ms / 84.343ms / 5.201ms`.
- Encoding RLE: `394` chunks, wire percent `0.004168%`, startup packet/chunk decode/mesh dispatch/first mesh/work `71.415ms / 0.441ms / 71.415ms / 71.415ms / 6.327ms`.
- Standalone RLE: `394` chunks, wire percent `0.004168%`, startup packet/chunk decode/mesh dispatch/first mesh/work `91.099ms / 0.499ms / 91.099ms / 91.099ms / 5.790ms`.

Fresh startup reader/main-thread lag telemetry result:

- Regression-pack attempt: `logs/world_streaming_startup_reader_lag_20260613_retry/world-streaming-regression-summary.txt` was not written because the final standalone RLE smoke exceeded the terrain queue budget by `0.099ms`, but its bootstrap, batch, and RAW-vs-RLE encoding legs passed and produced valid startup lag summaries.
- Passing standalone RLE summary: `logs/world_streaming_startup_reader_lag_rle_20260613_retry/world-streaming-rle-summary.txt`.
- The Rust client marker now separates packet reader elapsed time from main-thread packet queue lag. Movement, bootstrap, batch, RAW-vs-RLE encoding, standalone RLE, and the combined regression pack summaries surface `startup_packet_reader_elapsed_ms` and `startup_packet_queue_lag_ms`.
- Bootstrap candidate radius `0`: first stream `1` chunk, startup packet/reader elapsed/queue lag/chunk decode/first mesh work `72.365ms / 3.172ms / 13.247ms / 0.245ms / 5.228ms`.
- Batch candidate `64`: streamed `394` chunks over `9` batches, startup packet/reader elapsed/queue lag/chunk decode/first mesh work `89.889ms / 2.176ms / 12.178ms / 0.355ms / 3.563ms`.
- Encoding RLE: `394` chunks, wire percent `0.004168%`, startup packet/reader elapsed/queue lag/chunk decode/first mesh work `85.763ms / 1.945ms / 15.751ms / 0.242ms / 4.430ms`.
- Standalone RLE retry: `394` chunks, wire percent `0.004168%`, startup packet/reader elapsed/queue lag/chunk decode/first mesh work `70.480ms / 2.891ms / 10.885ms / 0.233ms / 3.965ms`.
- Current evidence points away from server first-stream send, packet decode, and chunk decode as the remaining startup wall-clock bottleneck for default RLE radius `0`; the next useful optimization target is earlier client connection/reader startup or Godot main-thread scheduling before packet processing.

## Stream Metrics

Set `RUMPELMC_SERVER_CHUNK_STREAM_METRICS=1` on the server to log each non-empty chunk stream batch:

```text
Chunk stream batch center=0,0 radius=10 chunks=64 raw_bytes=67108864 payload_bytes=... wire_bytes=... elapsed_ms=... chunks_per_sec=...
```

The metric is off by default and does not change packet payloads. Use it with the default RLE stream and with `RUMPELMC_SERVER_CHUNK_ENCODING=raw` rollback to compare payload shrinkage and batch throughput with the same log shape.

## RLE Protocol Path

RLE is now the default server chunk encoding. Leave `RUMPELMC_SERVER_CHUNK_ENCODING` unset or set it to `rle` to send RLE chunk payloads:

```sh
RUMPELMC_SERVER_CHUNK_STREAM_METRICS=1
```

The server encodes `ChunkData.blocks` as block runs, sets `ChunkData.encoding=CHUNK_ENCODING_RLE`, and sets `ChunkData.uncompressed_size` to `1,048,576`. The Rust client validates the encoded size, decodes RLE back into the full raw block array, and then uses the existing dirty-update, meshing, collision, and GPU upload paths.

Set `RUMPELMC_SERVER_CHUNK_ENCODING=raw` for the rollback path.

## Guardrails

- Keep raw chunk streaming available as an explicit rollback path.
- Do not hand-edit generated protocol files.
- Protocol changes must preserve raw chunk compatibility until the client and server both support the encoded path.
- Storage still persists the exact output of `world.Chunk.Serialize()` unless a separate migration is explicitly planned.
- Add round-trip tests for every encoded chunk format before enabling it in networking.
- For RenderingDevice resource lifecycle checks, use `scripts/gpu_resource_lifecycle_audit.sh`; see `docs/RENDERINGDEVICE_RESOURCE_LIFECYCLE_AUDIT.md`.
- For GPU terrain memory budget checks, use `scripts/gpu_terrain_memory_budget.sh`; see `docs/GPU_TERRAIN_MEMORY_BUDGETING.md`.
- For classified GPU report output, use `scripts/gpu_terrain_report_v2.sh`; see `docs/GPU_REPORT_SYSTEM_V2.md`.
- For accepted baseline comparison, use `scripts/performance_baseline_governance.sh`; see `docs/PERFORMANCE_BASELINE_GOVERNANCE.md`.
- For fast/full/nightly strategy checks, use `scripts/test_strategy_gate.sh`; see `docs/TEST_STRATEGY.md`. Current expected status includes `gpu_report_freshness_status=guarded`.
- For native-shadow prototype readiness, use `scripts/gpu_native_shadow_prototype_preflight.sh`; see `docs/NATIVE_SHADOW_PROTOTYPE_PREFLIGHT.md`. Current expected status is `deferred` while `GPU_TERRAIN_NATIVE_SHADOW_IMPLEMENTED=false`.
- For shadow quality parity, use `scripts/shadow_quality_parity_program.sh`; see `docs/SHADOW_QUALITY_PARITY_PROGRAM.md`. Current active native comparison remains `deferred`; only Godot proxy and native fallback parity are validated.
- For CPU shadow proxy retirement planning, use `scripts/shadow_proxy_retirement_plan.sh`; see `docs/SHADOW_PROXY_RETIREMENT_PLAN.md`. Current expected status is `deferred` and `retirement_allowed=0`.
- For lighting stability checks, use `scripts/lighting_stability_matrix.sh`; see `docs/LIGHTING_STABILITY_MATRIX.md`. Current ambient variation coverage is a deferred sub-gate.
- For transparent active-path readiness, use `scripts/transparent_active_path_preflight.sh`; see `docs/TRANSPARENT_ACTIVE_PATH_PREFLIGHT.md`. Current expected status is `deferred` while `GPU_TERRAIN_TRANSPARENT_IMPLEMENTED=false`.
- For transparent sorting/depth policy, use `scripts/transparent_sorting_depth_program.sh`; see `docs/TRANSPARENT_SORTING_DEPTH_PROGRAM.md`. Current expected status is `deferred` until a real active transparent workload exists.
- For transparent fixture acceptance, use `scripts/transparent_fixture_acceptance_suite.sh`; see `docs/TRANSPARENT_FIXTURE_ACCEPTANCE_SUITE.md`. Current fallback acceptance passes while active fixture acceptance remains deferred; no-render fixture artifacts should use contract-ready machine statuses (`fixture_plan_status=contract_ready`, `transparent_fixture_harness_status=contract_ready`, `transparent_fixture_scene_implementation_checklist_status=implementation_contract_ready`) rather than old future-work wording.
- For block material metadata design and the existing-ID server/client registry foundations, use `scripts/block_material_metadata_design_gate.sh`, `scripts/block_material_registry_foundation_gate.sh`, `scripts/client_block_material_registry_foundation_gate.sh`, and `scripts/block_material_registry_parity_gate.sh`; see `docs/BLOCK_MATERIAL_METADATA_DESIGN.md`. Current expected status is `pass` with `production_metadata_status=server_registry_guarded`, `server_material_metadata=guarded`, `client_material_metadata=guarded`, `server_registry_identity=guarded`, `client_registry_identity=guarded`, `client_server_parity_gate=present`, `parity_status=guarded`, `active_schema_change=0`, zero protocol/storage/renderer-code diff, and the runtime contract still opaque-only.
- For texture atlas evolution planning, use `scripts/texture_atlas_evolution_gate.sh`; see `docs/TEXTURE_ATLAS_EVOLUTION_TRACK.md`. Current expected status is `pass` with `atlas_tile_identity=guarded`, the atlas still `640x64`, tile size `64`, grid `10x1`, `MAX_TEXTURE_TILE=9`, and no atlas asset or shader layout change.
- For biome sampler matrix evidence, use `scripts/biome_sampler_matrix_gate.sh`. Current expected status is `pass` with `matrix_status=guarded`, sample hash `6fa59c33bbf1c4aa1a86028e89b04ce1dc26d9bb6fe5fa32e6f5085f5983fb4e`, and no chunk/protocol diff.
- For cave sampler matrix evidence, use `scripts/cave_sampler_matrix_gate.sh`; see `docs/CAVE_GENERATION_FOUNDATION.md`. Current expected status is `pass` with `matrix_status=guarded`, sample hash `f265ead2a700736c1e9b13056004af9c5c242d083c74c56d48e2cc76d1dfeeee`, and no chunk/protocol diff.
- For cave-height generator matrix evidence, use `scripts/cave_height_generator_matrix_gate.sh`. Current expected status is `pass` with `generator_version=cave_height_v1`, chunk hash `b68d1ca3e6471015c317c4b1d750dcddc59a8481f4cc2d26e394730d55fd7541`, `carved_air=34728`, `surface_preserved=1024`, and no protocol diff.
- For biome-cave-height generator matrix evidence, use `scripts/biome_cave_height_generator_matrix_gate.sh`. Current expected status is `pass` with `generator_version=biome_cave_height_v1`, chunk hash `c781f5530436094665f9596b9338065717400f4d497b9dd32f3f0d8839ff76a0`, `carved_air=28152`, `surface_preserved=1024`, `biome_surface_changed=1024`, and no protocol diff.
- For resource distribution matrix evidence, use `scripts/resource_distribution_matrix_gate.sh`; see `docs/RESOURCE_DISTRIBUTION_FOUNDATION.md`. Current expected status is `pass` with `matrix_status=guarded`, sample hash `f2beb912cffae722b9ea0322c68caa58a853c3c953fa4a0a80e618b42924e430`, and no chunk/protocol diff.
- For biome and visual-variety foundation, use `scripts/biome_visual_variety_foundation_gate.sh`; see `docs/BIOME_VISUAL_VARIETY_FOUNDATION.md`. Current expected status is `pass` with `biome_sampler=guarded`, `biome_matrix=guarded`, metadata-only runtime ownership, default runtime biome visuals deferred, and no worldgen/serialization change in the foundation gate.
- For world generation quality planning, use `scripts/world_generation_quality_gate.sh`; see `docs/WORLD_GENERATION_QUALITY_PASS.md`. Current expected status is `pass` with `worldgen_seed_version=guarded`, `worldgen_height_v1=guarded`, `worldgen_biome_height_v1=guarded`, `worldgen_cave_height_v1=guarded`, `worldgen_biome_cave_height_v1=guarded`, `height_v1_serialization=guarded`, `biome_height_v1_serialization=guarded`, `cave_height_v1_serialization=guarded`, `biome_cave_height_v1_serialization=guarded`, `cave_distribution=guarded`, `resource_distribution=guarded`, `height_v1_live_smoke=guarded`, `biome_sampler=guarded`, `biome_matrix=guarded`, `cave_matrix=guarded`, `resource_matrix=guarded`, `origin_chunk=guarded`, `flat_byte_hash=guarded`, `coordinate_mapping=guarded` for positive, negative, and high-positive boundaries, and `runtime_quality_pass=opt_in_biome_cave_height_v1_guarded`; resource-to-block/structure/broader biome runtime and default-world terrain changes remain blocked.
- For server scalability checks, use `scripts/server_scalability_pass_gate.sh`; see `docs/SERVER_SCALABILITY_PASS.md`. Current expected status is `pass` with multi-client sent-state, interested-client fanout, `conflict_semantics=last_write_wins_guarded`, `chunk_request_ordering=guarded`, `nil_sent_state_policy=empty_guarded`, `view_distance_config=guarded`, bounded classified connection lifecycle metrics, and bounded live/repeated multi-client evidence.
- For networking robustness checks, use `scripts/networking_robustness_gate.sh`; see `docs/NETWORKING_ROBUSTNESS_PROGRAM.md`. Current expected status is `pass` with Go/Rust packet boundary tests, zero-length frame decode, empty/unknown/nil-packet/nil-position/nil-block-action ignore policy, `scalability_status=repeat_live_guarded`, `resource_profile_status=repeat_live_guarded`, `multi_client_sent_state=guarded`, `block_edit_fanout=interested_clients_guarded`, `chunk_request_ordering=guarded`, `nil_sent_state_policy=empty_guarded`, `view_distance_config=guarded`, `disconnect_cleanup_status=lifecycle_summary_guarded`, zero connection close/accept failures, complete active-client lifecycle fields, reconnect, slow-client, stale-session, packet-error classification, parser aggregation, live alert thresholds, `conflict_semantics=last_write_wins_guarded`, and opt-in admission guarded while adaptive overload/backpressure work remains deferred.
- For client state-machine checks, use `scripts/client_state_machine_hardening_gate.sh`; see `docs/CLIENT_STATE_MACHINE_HARDENING.md`. Current expected status is `pass` with lifecycle transitions unit-guarded and runtime reconnect/state telemetry deferred.
- For gameplay loop foundation checks, use `scripts/gameplay_loop_foundation_gate.sh`; see `docs/GAMEPLAY_LOOP_FOUNDATION.md`. Current expected status is `pass` with local hotbar inventory guarded and full reload persistence deferred.
- For block edit persistence checks, use `scripts/block_edit_persistence_gate.sh`; see `docs/BLOCK_EDIT_PERSISTENCE_TRACK.md`. Current expected status is `pass` with place/destroy reload unit-guarded, `negative_boundary_edits=guarded`, `height_v1_reload=guarded`, `store_load_errors=propagated_guarded`, `save_failure_rollback=guarded`, and runtime reload smoke evidence consumed when present.
- For dirty update scalability checks, use `scripts/dirty_update_scalability_gate.sh`; see `docs/DIRTY_UPDATE_SCALABILITY.md`. Current expected status is `pass` with mass dirty math guarded, edge dirty runtime guarded, bounded current-chunk mass-edit runtime guarded, bounded cross-chunk mass-edit runtime guarded, bounded three-cycle persisted-reload dirty runtime guarded, and five-cycle high-count persisted-reload matrix guarded after opt-in smoke artifacts are present; multi-hour soaks and multi-client fanout remain outside this checkpoint.
- For tooling/debug overlay checks, use `scripts/tooling_debug_overlay_gate.sh`; see `docs/TOOLING_DEBUG_OVERLAY.md`. Current expected status is `pass` with compact HUD overlay wired, full perf logging preserved, and no protocol or Godot scene/resource diff.
- For observability/log cleanup checks, use `scripts/observability_logs_cleanup_gate.sh`; see `docs/OBSERVABILITY_LOGS_CLEANUP.md`. Current expected status is `pass` with HUD perf-log run IDs wired, current summary artifacts indexed, current error scan clean, and `gpu_report_freshness=guarded` after `scripts/gpu_terrain_report_freshness_gate.sh` refreshes and validates the ignored aggregate GPU terrain report.
- For automated handoff checks, use `scripts/automated_handoff_discipline_gate.sh`; see `docs/AUTOMATED_HANDOFF_DISCIPLINE.md`. Current expected status is `pass` with handoff quality inputs, the current observability evidence index, and `observability_gpu_report_freshness=guarded` included in generated snapshots.
- For architecture refresh checks, use `scripts/architecture_documentation_refresh_gate.sh`; see `docs/ARCHITECTURE_DOCUMENTATION_REFRESH.md`. Current expected status is `pass` with `docs/ARCHITECTURE.md` refreshed and `runtime_change=none`.
- For packet-error monitoring contract checks, use `scripts/packet_error_monitoring_contract_gate.sh`; see `docs/PACKET_ERROR_MONITORING_CONTRACT.md`. Current expected status is `pass` with `monitoring_contract=export_ready`, `metrics_export=present`, `alert_guard=threshold_guarded`, `unknown_classes=0`, `protocol_errors=0`, `write_errors=0`, and observability index coverage for the packet-error alert/class artifacts.
- For server session monitoring contract checks, use `scripts/server_session_monitoring_contract_gate.sh`; see `docs/SERVER_SESSION_MONITORING_CONTRACT.md`. Current expected status is `pass` with `monitoring_contract=export_ready`, `metrics_export=present`, `scalability_guard=repeat_live_guarded`, `resource_profile_status=repeat_live_guarded`, `admission_policy=matrix_live_guarded`, `disconnect_cleanup_status=lifecycle_summary_guarded`, zero close/accept failures, complete active-client lifecycle fields, and observability index coverage for the server scalability/lifecycle artifacts.
- For security/data-integrity review checks, use `scripts/security_data_integrity_review_gate.sh`; see `docs/SECURITY_DATA_INTEGRITY_REVIEW.md`. Current expected status is `pass` with packet framing, machine-readable deterministic packet/RLE property coverage, `packet_error_monitoring=export_ready`, `server_session_monitoring=export_ready`, `unknown_packet_policy=ignored_guarded`, `nil_packet_policy=ignored_guarded`, `nil_position_policy=ignored_guarded`, `nil_block_action_policy=ignored_guarded`, `conflict_semantics=last_write_wins_guarded`, `overload_status=admission_matrix_guarded`, `observability_gpu_report_freshness=guarded`, chunk decode, storage persistence/open-path behavior, `storage_package_smoke=guarded`, `storage_config=path_guarded`, `storage_backend_policy=approved_only_guarded`, `storage_backend_ownership=guarded`, `storage_concurrency=guarded`, `storage_errors=actionable_guarded`, `storage_lifecycle=guarded`, `block_edit_validation=y_bounds_guarded`, `block_edit_save_failure_rollback=guarded`, and `active_protocol_change=0`.
- For release-candidate evidence checks, use `scripts/release_candidate_gate.sh`; see `docs/RELEASE_CANDIDATE_GATE.md`. Current expected status is `pass` with `test_gpu_report_freshness=guarded`, `security_deterministic_property_tests=guarded`, `security_observability_gpu_report_freshness=guarded`, `security_packet_error_monitoring=export_ready`, `security_server_session_monitoring=export_ready`, `security_storage_package_smoke=guarded`, `security_storage_config=path_guarded`, `security_storage_backend_policy=approved_only_guarded`, `security_block_edit_validation=y_bounds_guarded`, `security_block_edit_save_failure_rollback=guarded`, `security_unknown_packet_policy=ignored_guarded`, `security_nil_packet_policy=ignored_guarded`, `security_nil_position_policy=ignored_guarded`, `security_nil_block_action_policy=ignored_guarded`, `security_conflict_semantics=last_write_wins_guarded`, `security_overload_status=admission_matrix_guarded`, `security_local_server_exposure=loopback_enforced`, `security_smoke_bind_exposure=loopback_guarded`, and `live_checks=full` after running the gate with `RUMPELMC_RC_REQUIRE_LIVE_CHECKS=1` plus live fast/full/diff flags.
- For external profiler campaign checks, use `scripts/external_profiling_campaign_gate.sh`; see `docs/EXTERNAL_PROFILING_CAMPAIGN.md`. Current expected status is `pass` with `capture_readiness=live_rc_ready_for_external_capture`, `rc_live_checks=full`, `rc_security_deterministic_property_tests=guarded`, `rc_security_observability_gpu_report_freshness=guarded`, `rc_security_packet_error_monitoring=export_ready`, `rc_security_server_session_monitoring=export_ready`, `rc_security_storage_package_smoke=guarded`, `rc_security_storage_config=path_guarded`, `rc_security_storage_backend_policy=approved_only_guarded`, `rc_security_block_edit_validation=y_bounds_guarded`, `rc_security_block_edit_save_failure_rollback=guarded`, `rc_security_unknown_packet_policy=ignored_guarded`, `rc_security_nil_packet_policy=ignored_guarded`, `rc_security_nil_position_policy=ignored_guarded`, `rc_security_nil_block_action_policy=ignored_guarded`, `rc_security_conflict_semantics=last_write_wins_guarded`, `rc_security_overload_status=admission_matrix_guarded`, `rc_security_local_server_exposure=loopback_enforced`, `rc_security_smoke_bind_exposure=loopback_guarded`, and `external_profile_status=pending_external_profiler`; use `scripts/gpu_terrain_shadow_xctrace_attach_capture.sh` for sanitized local macOS attach attempts, but do not cite the pending capture pack, results-intake file, operator-intake template, raw trace, or exported Metal tables as measured profiler evidence.
- For the production-readiness milestone, use `scripts/production_readiness_milestone_gate.sh`; see `docs/PRODUCTION_READINESS_MILESTONE.md`. Current expected status is `pass` with `production_readiness=rc_evidence_ready`, `handoff_gpu_report_freshness=guarded`, `rc_test_gpu_report_freshness=guarded`, `rc_security_deterministic_property_tests=guarded`, `security_observability_gpu_report_freshness=guarded`, `security_storage_package_smoke=guarded`, `security_packet_error_monitoring=export_ready`, `security_server_session_monitoring=export_ready`, `security_storage_config=path_guarded`, `security_storage_backend_policy=approved_only_guarded`, `security_block_edit_validation=y_bounds_guarded`, `security_block_edit_save_failure_rollback=guarded`, `security_unknown_packet_policy=ignored_guarded`, `security_nil_packet_policy=ignored_guarded`, `security_nil_position_policy=ignored_guarded`, `security_nil_block_action_policy=ignored_guarded`, `security_conflict_semantics=last_write_wins_guarded`, `security_overload_status=admission_matrix_guarded`, `security_local_server_exposure=loopback_enforced`, `security_smoke_bind_exposure=loopback_guarded`, `rc_security_observability_gpu_report_freshness=guarded`, `rc_security_storage_package_smoke=guarded`, `rc_security_packet_error_monitoring=export_ready`, `rc_security_server_session_monitoring=export_ready`, `rc_security_storage_config=path_guarded`, `rc_security_storage_backend_policy=approved_only_guarded`, `rc_security_block_edit_validation=y_bounds_guarded`, `rc_security_block_edit_save_failure_rollback=guarded`, `rc_security_unknown_packet_policy=ignored_guarded`, `rc_security_nil_packet_policy=ignored_guarded`, `rc_security_nil_position_policy=ignored_guarded`, `rc_security_nil_block_action_policy=ignored_guarded`, `rc_security_conflict_semantics=last_write_wins_guarded`, `rc_security_overload_status=admission_matrix_guarded`, `rc_security_local_server_exposure=loopback_enforced`, `rc_security_smoke_bind_exposure=loopback_guarded`, `external_rc_test_gpu_report_freshness=guarded`, `external_rc_security_observability_gpu_report_freshness=guarded`, `external_rc_security_storage_package_smoke=guarded`, `external_rc_security_packet_error_monitoring=export_ready`, `external_rc_security_server_session_monitoring=export_ready`, `external_rc_security_storage_config=path_guarded`, `external_rc_security_storage_backend_policy=approved_only_guarded`, `external_rc_security_block_edit_validation=y_bounds_guarded`, `external_rc_security_block_edit_save_failure_rollback=guarded`, `external_rc_security_unknown_packet_policy=ignored_guarded`, `external_rc_security_nil_packet_policy=ignored_guarded`, `external_rc_security_nil_position_policy=ignored_guarded`, `external_rc_security_nil_block_action_policy=ignored_guarded`, `external_rc_security_conflict_semantics=last_write_wins_guarded`, `external_rc_security_overload_status=admission_matrix_guarded`, `external_rc_security_local_server_exposure=loopback_enforced`, `external_rc_security_smoke_bind_exposure=loopback_guarded`, `external_capture_readiness=live_rc_ready_for_external_capture`, and `live_release_checks=full`, while external profiler results, native shadow, and active transparent terrain remain deferred.
