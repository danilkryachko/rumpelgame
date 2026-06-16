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

- This project currently defaults to a local loopback development server and does not yet expose a production auth/trust boundary.
- Any non-local bind is an explicit operator override through `RUMPELMC_SERVER_ADDRESS` and is not production-safe without a separate auth/encryption review.
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

- `ChunkData` raw and RLE compatibility is covered by Go tests.
- RLE payloads remain runs over the same serialized chunk byte order.
- Unknown Go-side `ChunkData` fields are preserved through protobuf round trip.
- Go and Rust RLE tests cover representative run patterns across single-byte and multi-byte varint run-length boundaries.
- Rust chunk decode rejects short raw chunks, bad RLE uncompressed size, malformed RLE runs, and unknown encodings.

### Storage Integrity

- RocksDB keys keep the stable chunk-coordinate key format.
- RocksDB tests cover missing chunks, save/reopen round-trip, overwrite isolation, corrupt payload rejection, key format, and signed coordinate ordering.
- `World.SetBlockGlobal` saves edited chunks through the configured `ChunkStore`.
- The block edit reload guard proves place/destroy edits survive fresh `World(store)` instances.

### Block Edit Boundary

- `BlockAction_PLACE` rejects non-placeable block IDs before mutating world state.
- `BlockAction_DESTROY` maps to `Air`.
- Current edits return a full chunk snapshot; delta packets remain future protocol work.

### Runtime Session Evidence

- Server write deadlines, failed interested-client broadcast cleanup, bounded connection lifecycle log summaries, bounded slow-reader timeout and multi-fast-client matrix evidence, bounded six-client fanout/load/resource/per-client detail evidence, and bounded three-run repeat evidence are guarded by the networking and server scalability gates.
- Opt-in max-client admission rejection is unit-guarded, bounded-live-guarded, and matrix-guarded by the server scalability gate without adding wire semantics.
- Classified server packet-error labels are guarded through the networking gate as `packet_error_classification`.
- Classified server packet-error aggregation is guarded through the networking gate as `packet_error_aggregation`.
- Classified server packet-error alert thresholds, including current slow-reader matrix timeout evidence, are guarded through the networking gate as `packet_error_alerts`.
- Focused deterministic packet/RLE property coverage is surfaced by the security gate as `deterministic_property_tests=guarded`.
- Client reconnect/rebootstrap is guarded by live disconnect/server-restart smoke and a bounded repeated reconnect soak, with reader-session stale-packet filtering covered by Rust unit tests.
- Block edit persistence is guarded at the world/storage boundary, the live server restart/reopen boundary, and the Godot visual/collision/GPU boundary.
- These runtime guards do not add authentication, packet replay, adaptive admission, or new wire semantics.

### Local-Only Threat Model

- `server/cmd/server/main.go` defaults `configuredServerAddress()` to `127.0.0.1:25565`, so a normal server launch listens on loopback only.
- The Godot client default host is `127.0.0.1`, and the Rust client default address remains `127.0.0.1:25565`.
- `RUMPELMC_SERVER_ADDRESS` remains the explicit override for smoke scripts and operator-controlled non-default binds; setting it to a non-loopback address does not add authentication, encryption, replay protection, or production monitoring.
- Smoke scripts that bind isolated test ports now set `RUMPELMC_SERVER_ADDRESS` to their explicit loopback `SMOKE_ADDR`; they are local runtime evidence only and do not authorize exposing the server outside localhost.

## MCP Review Notes

- Fresh 2026-06-16 server error topology showed expected validation/check sites such as invalid place-block rejection and env parsing; no findings were emitted.
- Fresh 2026-06-16 server taint trace from `receivePacket` to `proto.Unmarshal` did not match an unguarded source-to-sink path.
- World concurrency logic scan emitted no findings for `server/pkg/world/world.go`.
- Rust network error-topology warnings remain bounded heuristic false positives around `Result`-returning connect paths and test-helper `bind`/`accept` calls; focused Rust tests cover short prefix, short payload, malformed payload, and oversized length behavior.

## Deferred Work

Still needed:

- Authentication/encryption before any non-local server exposure; the current loopback default only makes local development safe by default.
- Sustained overload/admission sizing and backpressure policy beyond the opt-in max-client cap, bounded admission matrix, bounded write-timeout, and bounded slow-reader matrix guards.
- Longer reconnect failure/idle soak and broad client loaded-state reset policy beyond the bounded reconnect/rebootstrap guards.
- Corrupt edit recovery policy beyond current corrupt chunk load rejection.
- Multi-client conflict semantics beyond current interested-client fanout and failed-broadcast cleanup.
- Production monitoring integration for classified packet errors beyond the local threshold gate.
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

The expected current result is `status=pass`, `security_status=reviewed`, `packet_boundary=guarded`, `packet_error_classification=unit_guarded`, `packet_error_aggregation=parser_guarded`, `packet_error_alerts=threshold_guarded`, `storage_integrity=guarded`, `chunk_decode=guarded`, `deterministic_property_tests=guarded`, `local_server_exposure=loopback_default_guarded`, `smoke_bind_exposure=loopback_guarded`, and `active_protocol_change=0`.

The gate checks that:

- This document records reviewed boundaries, MCP notes, deferred work, and compatibility rules.
- Server/Rust sources still contain packet-size, exact-read, decode, and block-edit validation hooks.
- Server and client defaults still keep normal runtime traffic on loopback, and smoke scripts do not use wildcard `RUMPELMC_SERVER_ADDRESS=":<port>"` binds.
- Server source still contains stable packet-error classification and `packet_error_class` logging hooks.
- Focused deterministic packet/RLE property tests are present in Go and Rust test sources and surfaced in the summary as `deterministic_property_tests=guarded`.
- Focused Go protocol/network/storage/world tests pass.
- Focused Rust packet-boundary and chunk-decode tests pass.
- Networking, block-edit persistence, architecture, and observability summaries are clean.
- Protocol schema/generated files are unchanged.

## Current Status

This block is complete as a focused security and data-integrity review checkpoint. Packet framing, machine-readable deterministic packet/RLE property coverage, loopback-by-default local server exposure, loopback smoke binds, classified packet errors, parser-guarded classified-error aggregation, classified-error alert thresholds, chunk decode, storage integrity, block edit validation, opt-in max-client admission with bounded live rejection and matrix evidence, bounded slow-reader matrix behavior, bounded reconnect/rebootstrap, interested-client fanout, and persisted edit runtime evidence are guarded. Production auth before non-local exposure, sustained overload/admission sizing, broad reconnect reset policy, production monitoring integration, conflict semantics, and external fuzz campaigns remain future work.
