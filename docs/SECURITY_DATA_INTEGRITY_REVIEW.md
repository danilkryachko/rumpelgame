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
- Validate chunk serialization and RLE compatibility guards.
- Validate storage/load/save integrity guards.
- Validate block edit persistence and invalid place-block rejection.
- Record current guarded runtime boundaries and remaining security/data-integrity work.

Out of scope:

- No authentication, encryption, broad reconnect policy, broad slow-client/backpressure policy, adaptive server admission control, packet schema change, storage migration, worldgen change, renderer change, or new external scanner integration.

Assumptions:

- This project currently runs a local development server and does not yet expose a production auth/trust boundary.
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

### Chunk Serialization

- `ChunkData` raw and RLE compatibility is covered by Go tests.
- RLE payloads remain runs over the same serialized chunk byte order.
- Unknown Go-side `ChunkData` fields are preserved through protobuf round trip.
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

- Server write deadlines, failed interested-client broadcast cleanup, bounded slow-reader timeout evidence, and bounded six-client fanout/load evidence are guarded by the networking and server scalability gates.
- Opt-in max-client admission rejection is unit-guarded by the server scalability gate without adding wire semantics.
- Classified server packet-error labels are guarded through the networking gate as `packet_error_classification`.
- Classified server packet-error aggregation is guarded through the networking gate as `packet_error_aggregation`.
- Client reconnect/rebootstrap is guarded by live disconnect/server-restart smoke and a bounded repeated reconnect soak, with reader-session stale-packet filtering covered by Rust unit tests.
- Block edit persistence is guarded at the world/storage boundary, the live server restart/reopen boundary, and the Godot visual/collision/GPU boundary.
- These runtime guards do not add authentication, packet replay, adaptive admission, or new wire semantics.

## MCP Review Notes

- Fresh 2026-06-16 server error topology showed expected validation/check sites such as invalid place-block rejection and env parsing; no findings were emitted.
- Fresh 2026-06-16 server taint trace from `receivePacket` to `proto.Unmarshal` did not match an unguarded source-to-sink path.
- World concurrency logic scan emitted no findings for `server/pkg/world/world.go`.
- Rust network error-topology warnings remain bounded heuristic false positives around `Result`-returning connect paths and test-helper `bind`/`accept` calls; focused Rust tests cover short prefix, short payload, malformed payload, and oversized length behavior.

## Deferred Work

Still needed:

- Authentication/encryption or explicit local-only threat model before any non-local server exposure.
- Broader overload/admission sizing and backpressure policy beyond the opt-in max-client cap, bounded write-timeout, and slow-reader guards.
- Longer reconnect failure/idle soak and broad client loaded-state reset policy beyond the bounded reconnect/rebootstrap guards.
- Corrupt edit recovery policy beyond current corrupt chunk load rejection.
- Multi-client conflict semantics beyond current interested-client fanout and failed-broadcast cleanup.
- Operational alert thresholds for the existing classified packet error labels.
- Fuzz/property tests for packet framing and RLE decode if external exposure increases.

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

The expected current result is `status=pass`, `security_status=reviewed`, `packet_boundary=guarded`, `packet_error_classification=unit_guarded`, `packet_error_aggregation=parser_guarded`, `storage_integrity=guarded`, `chunk_decode=guarded`, and `active_protocol_change=0`.

The gate checks that:

- This document records reviewed boundaries, MCP notes, deferred work, and compatibility rules.
- Server/Rust sources still contain packet-size, exact-read, decode, and block-edit validation hooks.
- Server source still contains stable packet-error classification and `packet_error_class` logging hooks.
- Focused Go protocol/network/storage/world tests pass.
- Focused Rust packet-boundary and chunk-decode tests pass.
- Networking, block-edit persistence, architecture, and observability summaries are clean.
- Protocol schema/generated files are unchanged.

## Current Status

This block is complete as a focused security and data-integrity review checkpoint. Packet framing, classified packet errors, parser-guarded classified-error aggregation, chunk decode, storage integrity, block edit validation, opt-in max-client admission, bounded slow-reader behavior, bounded reconnect/rebootstrap, interested-client fanout, and persisted edit runtime evidence are guarded. Production auth, overload/admission sizing, broad reconnect reset policy, classified-error alert thresholds, conflict semantics, and fuzz/property coverage remain future work.
