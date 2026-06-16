# Security And Data Integrity Review

Block 47, Security And Data Integrity Review, records the current protocol, storage, chunk decode, block edit, and runtime evidence boundaries before release-candidate gating.

## Technical Brief

User request:

Continue the annual world streaming architecture plan in order, use MCP/OntoIndex context, and move to the next block if a local blocker cannot be bypassed.

Goal:

Review security and data-integrity boundaries with focused local tests and MCP systems-audit signals, without changing protocol, storage, worldgen, or renderer behavior.

Context inspected:

- `docs/CODE_REVIEW.md`.
- `docs/PROTOCOL.md`.
- `docs/STORAGE.md`.
- `docs/NETWORKING_ROBUSTNESS_PROGRAM.md`.
- `docs/BLOCK_EDIT_PERSISTENCE_TRACK.md`.
- `docs/CHUNK_SERIALIZATION_COMPATIBILITY.md`.
- `server/pkg/network/server.go`.
- `server/pkg/world/world.go`.
- `client/rust_ext/src/network.rs`.
- OntoIndex/MCP error topology, taint trace, and concurrency logic scans.

Scope:

- Validate packet framing and malformed input guards.
- Validate chunk serialization, RLE compatibility guards, and deterministic packet/RLE property coverage.
- Validate storage/load/save integrity guards.
- Validate block edit persistence and invalid place-block rejection.
- Record the local-only server exposure boundary before any non-local deployment.
- Record current guarded runtime boundaries and remaining security/data-integrity work.

Out of scope:

- No authentication, encryption, broad reconnect policy, broad slow-client/backpressure policy, adaptive server admission control, packet schema change, storage migration, worldgen change, renderer change, or new external scanner integration.

Assumptions:

- This project currently enforces a local loopback development server and does not yet expose a production auth/trust boundary.
- Non-local binds through `RUMPELMC_SERVER_ADDRESS` are rejected until a separate auth/encryption review explicitly changes that boundary.
- Packet and storage correctness are the most relevant release-candidate integrity gates for the current architecture.
- MCP findings are bounded static heuristics and must be interpreted against local tests and source.

Done when:

- Focused Go protocol/network/storage/world tests pass.
- Focused Rust packet-boundary and chunk-decode tests pass.
- The review gate confirms no protocol schema/generated diff and clean prerequisite summaries.

Checks:

- `sh scripts/security_data_integrity_review_gate.sh logs/security_data_integrity_review_current`

## Reviewed Boundaries

### Packet Framing

- Server and Rust client both reject packet lengths over `16 MiB`.
- Server and Rust client both use exact reads for the length prefix and payload.
- Malformed protobuf payloads return errors instead of partial packets.
- Server receive/decode errors close the client connection through the existing connection loop.
- Server receive, decode, timeout, encode, and short-write errors are logged with stable `packet_error_class` labels guarded by Go network tests, including a connection-loop malformed-packet log test, and the networking robustness gate.
- Go packet framing tests include an exact-boundary check that reads two back-to-back protobuf frames without over-reading across frame boundaries.

### Chunk Serialization

- `Packet` empty zero-wire behavior plus `ChunkData` raw and RLE compatibility are covered by Go tests.
- RLE payloads remain runs over the same serialized chunk byte order.
- Unknown Go-side `ChunkData` fields are preserved through protobuf round trip.
- Go and Rust RLE tests cover representative run patterns across single-byte and multi-byte varint run-length boundaries.
- Go RLE tests also cover representative opt-in `height_v1`, `biome_height_v1`, `cave_height_v1`, and `biome_cave_height_v1` chunks, proving generated terrain decodes back to the exact raw serialized bytes.
- Rust chunk decode rejects short raw chunks, bad RLE uncompressed size, malformed RLE runs, and unknown encodings.

### Storage Integrity

- RocksDB keys keep the stable chunk-coordinate key format.
- RocksDB tests cover missing chunks, save/reopen round-trip, overwrite isolation, concurrent distinct-key save/load, corrupt payload rejection, empty-path rejection before the C API boundary, missing-parent path creation, regular-file parent path rejection, regular-file database path rejection, key format, and signed coordinate ordering.
- Server config tests prove `RUMPELMC_SERVER_ROCKSDB_PATH` is the current chunk-store override and PostgreSQL environment variables do not select a runtime chunk backend.
- Server config tests prove world generator env parsing rejects invalid seeds and unknown generator versions before startup creates `World`.
- The review gate reports `storage_package_smoke=guarded` after running `scripts/storage_package_smoke.sh` and validating that the storage smoke needs no external secret, ignores PostgreSQL environment variables for runtime chunk backend selection, and keeps approved databases at PostgreSQL/RocksDB.
- The review gate reports `storage_config=path_guarded` after validating empty path rejection, the RocksDB path/config documentation, and the current server config tests.
- The review gate reports `storage_backend_policy=approved_only_guarded` after scanning runtime source areas for unapproved database engine references.
- The review gate reports `storage_backend_ownership=guarded` after validating the RocksDB/PostgreSQL ownership documentation and server config tests.
- The review gate reports `storage_concurrency=guarded` after validating the concurrent RocksDB save/load test.
- The review gate reports `storage_errors=actionable_guarded` after validating RocksDB path/chunk-coordinate error context.
- The review gate reports `storage_lifecycle=guarded` after validating closed-store operation errors, repeated close safety, and nil chunk save rejection.
- `World.SetBlockGlobal` saves edited chunks through the configured `ChunkStore`.
- The block edit reload guard proves place/destroy edits survive fresh `World(store)` instances.
- The opt-in `height_v1` reload guard proves stored edited height chunks remain authoritative over newly generated chunks.

### Block Edit Boundary

- `BlockAction_PLACE` rejects non-placeable block IDs before mutating world state.
- `BlockAction_DESTROY` maps to `Air`.
- Connected-session `BlockAction` edits require a recorded `ClientPosition` and a target block within the server reach envelope before mutating world state or inventory.
- Connected-session `BlockAction_PLACE` rejects valid-height target blocks that intersect the last recorded player body AABB before mutating world state or inventory.
- `World.SetBlockGlobal` rejects block edits with `Y` outside `[0, ChunkHeight)` before loading, creating, saving, or broadcasting an edited chunk snapshot.
- Current edits return a full chunk snapshot; delta packets remain future protocol work.

### Runtime Session Evidence

- Server write deadlines, failed interested-client broadcast cleanup, bounded connection lifecycle log summaries, bounded slow-reader timeout and multi-fast-client matrix evidence, bounded six-client fanout/load/resource/per-client detail evidence, and bounded three-run repeat evidence are guarded by the networking and server scalability gates.
- Opt-in max-client admission rejection is unit-guarded, bounded-live-guarded, and matrix-guarded by the server scalability gate without adding wire semantics.
- Classified server packet-error labels are guarded through the networking gate as `packet_error_classification`.
- Classified server packet-error aggregation is guarded through the networking gate as `packet_error_aggregation`.
- Classified server packet-error alert thresholds, including current slow-reader matrix timeout evidence, are guarded through the networking gate as `packet_error_alerts`.
- The local packet-error monitoring export contract is guarded through `scripts/packet_error_monitoring_contract_gate.sh` and surfaced by the security gate as `packet_error_monitoring=export_ready`, with zero unknown, protocol-error, and write-error classes.
- The local server session monitoring export contract is guarded through `scripts/server_session_monitoring_contract_gate.sh` and surfaced by the security gate as `server_session_monitoring=export_ready`, with metrics export present and zero close failures, accept failures, and missing active-client log fields.
- Empty or unsupported packet payloads are guarded through the networking gate and surfaced by the security gate as `unknown_packet_policy=ignored_guarded`.
- Nil packet handler inputs are guarded through the networking gate and surfaced by the security gate as `nil_packet_policy=ignored_guarded`.
- Nil `ClientPosition` payload bodies are guarded through the networking gate and surfaced by the security gate as `nil_position_policy=ignored_guarded`.
- Nil `BlockAction` payload bodies are guarded through the networking gate and surfaced by the security gate as `nil_block_action_policy=ignored_guarded`.
- Focused deterministic packet/RLE property coverage, including representative `height_v1`, `biome_height_v1`, `cave_height_v1`, and `biome_cave_height_v1` RLE round-trip coverage, is surfaced by the security gate as `deterministic_property_tests=guarded`.
- Valid multi-client block edits at the same coordinate are guarded as sequential last-write-wins snapshots through the server scalability and networking gates, then surfaced by the security gate as `conflict_semantics=last_write_wins_guarded`.
- Worldgen atlas guard propagation is consumed through the networking gate and surfaced by the security gate as `worldgen_biome_atlas_tile_identity=guarded` and `worldgen_biome_atlas_block_texture_usage=guarded`.
- Out-of-height block edits are guarded at the world boundary and network handler as `block_edit_validation=y_bounds_guarded`.
- Out-of-reach block edits and block edits before the first position are guarded at the session boundary as `block_edit_reach=position_guarded`.
- Player-intersecting placement is guarded at the session boundary as `block_edit_player_collision=place_player_aabb_guarded`.
- Client reconnect/rebootstrap is guarded by live disconnect/server-restart smoke and a bounded repeated reconnect soak, with reader-session stale-packet filtering covered by Rust unit tests, and surfaced by the security gate as `runtime_reconnect=repeated_live_rebootstrap_guarded`.
- Slow-reader behavior is guarded by a live timeout smoke and multi-fast-client matrix, then surfaced by the security gate as `slow_client_status=load_matrix_guarded`.
- Block edit persistence is guarded at the world/storage boundary, including opt-in `height_v1` edited chunk reload, failed-save rollback, persisted load-error propagation, the live server restart/reopen boundary, and the Godot visual/collision/GPU boundary.
- These runtime guards do not add authentication, packet replay, adaptive admission, or new wire semantics.

### Local-Only Threat Model

- `server/cmd/server/main.go` defaults `configuredServerAddress()` to `127.0.0.1:25565`, and validates `RUMPELMC_SERVER_ADDRESS` with loopback-only host parsing before server startup.
- The Godot client default host is `127.0.0.1`, and the Rust client default address remains `127.0.0.1:25565`.
- `RUMPELMC_SERVER_ADDRESS` remains the explicit override for smoke scripts and operator-controlled loopback ports; setting it to a non-loopback host now fails before server startup because it would not add authentication, encryption, replay protection, or production monitoring.
- Smoke scripts that bind isolated test ports now set `RUMPELMC_SERVER_ADDRESS` to their explicit loopback `SMOKE_ADDR`; they are local runtime evidence only and do not authorize exposing the server outside localhost.

## MCP Review Notes

- Fresh 2026-06-16 server error topology showed expected validation/check sites such as invalid place-block rejection and env parsing; no findings were emitted.
- Fresh 2026-06-16 server taint trace from `receivePacket` to `proto.Unmarshal` did not match an unguarded source-to-sink path.
- World concurrency logic scan emitted no findings for `server/pkg/world/world.go`.
- Rust network error-topology warnings remain bounded heuristic false positives around `Result`-returning connect paths and test-helper `bind`/`accept` calls; focused Rust tests cover short prefix, short payload, malformed payload, and oversized length behavior.

## Deferred Work

Still needed:

- Authentication/encryption and a deliberate exposure policy before any non-local server bind is allowed.
- Sustained overload/admission sizing and backpressure policy beyond the opt-in max-client cap, bounded admission matrix, bounded write-timeout, and bounded slow-reader matrix guards.
- Longer reconnect failure/idle soak and broad client loaded-state reset policy beyond the bounded reconnect/rebootstrap guards.
- Corrupt edit recovery policy beyond current corrupt chunk load rejection and world-level load-error propagation.
- External monitoring service/upload/retention integration for classified packet errors and server session metrics beyond the local monitoring contracts.
- External fuzz campaigns for packet framing and RLE decode remain outside the current local gate unless exposure changes.

## Compatibility Rules

- Do not change packet field numbers, wire meanings, or frame prefix without explicit protocol work.
- Do not change RocksDB key/value format without migration design and tests.
- Do not bypass `World.SetBlockGlobal` for persistent block edits.
- Do not reduce collision, rendering, shadow, texture, draw distance, or worldgen quality to pass integrity gates.
- Treat MCP heuristic warnings as review prompts, not proof, unless fresh source evidence confirms them.

## Block 47 Gate

Use:

```sh
sh scripts/security_data_integrity_review_gate.sh logs/security_data_integrity_review_current
```

The expected current result is `status=pass`, `security_status=reviewed`, `packet_boundary=guarded`, `packet_error_classification=unit_guarded`, `packet_error_aggregation=parser_guarded`, `packet_error_alerts=threshold_guarded`, `packet_error_monitoring=export_ready`, `server_session_monitoring=export_ready`, `unknown_packet_policy=ignored_guarded`, `nil_packet_policy=ignored_guarded`, `nil_position_policy=ignored_guarded`, `nil_block_action_policy=ignored_guarded`, `storage_integrity=guarded`, `storage_package_smoke=guarded`, `storage_config=path_guarded`, `storage_backend_policy=approved_only_guarded`, `storage_backend_ownership=guarded`, `storage_concurrency=guarded`, `storage_errors=actionable_guarded`, `storage_lifecycle=guarded`, `block_edit_validation=y_bounds_guarded`, `block_edit_reach=position_guarded`, `block_edit_player_collision=place_player_aabb_guarded`, `block_edit_save_failure_rollback=guarded`, `chunk_decode=guarded`, `deterministic_property_tests=guarded`, `conflict_semantics=last_write_wins_guarded`, `worldgen_biome_atlas_tile_identity=guarded`, `worldgen_biome_atlas_block_texture_usage=guarded`, `overload_status=admission_matrix_guarded`, `runtime_reconnect=repeated_live_rebootstrap_guarded`, `reconnect_smoke_status=pass`, `reconnect_soak_status=pass`, `slow_client_status=load_matrix_guarded`, `slow_reader_smoke_status=pass`, `slow_reader_matrix_status=pass`, `local_server_exposure=loopback_enforced`, `smoke_bind_exposure=loopback_guarded`, `observability_gpu_report_freshness=guarded`, and `active_protocol_change=0`.

The gate checks that:

- This document records reviewed boundaries, MCP notes, deferred work, and compatibility rules.
- Server/Rust sources still contain packet-size, exact-read, decode, and block-edit validation hooks.
- Storage docs record RocksDB as the current chunk persistence owner and PostgreSQL as approved but not implemented for runtime chunks.
- Storage package smoke reports `storage_package_smoke=guarded`, `storage_smoke_external_secret_required=0`, `storage_smoke_database_env_policy=postgres_env_ignored`, and `storage_smoke_approved_databases=postgresql_rocksdb` before security review can pass.
- Runtime source scans reject unapproved database engine references before the gate reports `storage_backend_policy=approved_only_guarded`.
- Server and client defaults still keep normal runtime traffic on loopback, non-loopback server overrides are rejected, and smoke scripts do not use wildcard `RUMPELMC_SERVER_ADDRESS=":<port>"` binds.
- Server source still contains stable packet-error classification and `packet_error_class` logging hooks.
- The packet-error monitoring contract summary reports `monitoring_contract=export_ready`, `metrics_export=present`, and zero unknown/protocol/write error classes before security review can pass.
- The server session monitoring contract summary reports `monitoring_contract=export_ready`, `metrics_export=present`, and zero close/accept/missing active-client field failures before security review can pass.
- Focused deterministic packet/RLE property tests are present in Go and Rust test sources, including representative `height_v1`, `biome_height_v1`, `cave_height_v1`, and `biome_cave_height_v1` RLE round-trip coverage, and surfaced in the summary as `deterministic_property_tests=guarded`.
- Focused Go protocol/network/storage/world tests pass.
- Storage tests prove empty RocksDB paths are rejected before the C API boundary, missing parent directories are created, and existing regular-file parent/database RocksDB paths fail to open.
- Storage tests prove concurrent save/load operations on distinct RocksDB chunk keys preserve each chunk payload.
- Storage tests prove open-path failures and corrupt persisted payload failures include actionable context.
- Storage tests prove closed-store and nil-save paths return Go errors before the C API boundary.
- Server config tests prove PostgreSQL environment variables do not bypass `RUMPELMC_SERVER_ROCKSDB_PATH`.
- Focused Rust packet-boundary and chunk-decode tests pass.
- Networking, block-edit persistence, architecture, and observability summaries are clean, including guarded aggregate GPU terrain report freshness from observability.
- Networking summary reports `unknown_packet_policy=ignored_guarded`, `nil_packet_policy=ignored_guarded`, `nil_position_policy=ignored_guarded`, and `nil_block_action_policy=ignored_guarded`; API compatibility tests lock empty `Packet{}` zero-wire bytes.
- Networking summary reports `conflict_semantics=last_write_wins_guarded`, `worldgen_biome_atlas_tile_identity=guarded`, `worldgen_biome_atlas_block_texture_usage=guarded`, and `overload_status=admission_matrix_guarded`.
- Networking summary reports `reconnect_status=repeated_live_rebootstrap_guarded`, clean reconnect smoke and soak counts, `slow_client_status=load_matrix_guarded`, clean slow-reader smoke timeout evidence, and clean slow-reader matrix counts before security review can pass.
- Server world/network tests prove out-of-range block-edit `Y` is rejected without a save or chunk broadcast, session block edits are ignored before a recorded position or beyond the server reach envelope, and valid-height placements intersecting the player body AABB are ignored before inventory consumption or chunk broadcast.
- Server world tests prove failed `SaveChunk` calls roll the in-memory block edit back before returning an error.
- Protocol schema/generated files are unchanged.

## Current Status

This block is complete as a focused security and data-integrity review checkpoint. Packet framing, nil packet input handling, nil client-position handling, nil block-action handling, machine-readable deterministic packet/RLE property coverage, enforced loopback-only local server exposure, loopback smoke binds, classified packet errors, parser-guarded classified-error aggregation, classified-error alert thresholds, local packet-error monitoring export, local server session monitoring export, guarded aggregate GPU terrain report freshness from observability, chunk decode, storage integrity including RocksDB empty-path and open-path failure coverage, approved-only database backend policy, concurrent distinct-key save/load coverage, actionable storage error context, lifecycle error guards, and PostgreSQL/RocksDB ownership boundaries, block edit Y-bound validation, block edit reach validation, player-intersecting placement rejection, block edit save-failure rollback, sequential last-write-wins conflict semantics, opt-in max-client admission with bounded live rejection and matrix evidence, explicitly surfaced bounded slow-reader matrix behavior, explicitly surfaced bounded reconnect/rebootstrap, interested-client fanout, and persisted edit runtime evidence are guarded. Production auth before non-local exposure, sustained overload/admission sizing, broad reconnect reset policy, external monitoring service/upload integration, and external fuzz campaigns remain future work.
