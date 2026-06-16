# Networking Robustness Program

Block 38, Networking Robustness Program, records the current packet-framing robustness contract for disconnects, partial streams, packet errors, reconnect, slow clients, and overloaded clients.

## Technical Brief

User request:

Continue the annual world streaming architecture plan in order and use MCP/OntoIndex context.

Goal:

Harden the current networking boundary with focused tests and documentation without changing the TCP wire format or protocol schema.

Context inspected:

- OntoIndex concept search for networking robustness, packet errors, partial streams, reconnect, slow clients, overloaded clients, and framing tests.
- `server/pkg/network/server.go` packet framing, initial-client packet timeout, connection loop, and write path.
- `server/pkg/network/framing_test.go` server-side short-frame, oversized-length, malformed-payload, and handshake tests.
- `client/rust_ext/src/network.rs` Rust client framing, max packet length guard, and packet receive/send tests.
- `docs/PROTOCOL.md`.
- `docs/SERVER_SCALABILITY_PASS.md`.

Scope:

- Add focused Rust client unit coverage for short length prefixes, short payloads, and malformed protobuf payloads.
- Keep the current server framing tests as the server-side packet-boundary robustness guard.
- Add server session-write timeout and failed-broadcast cleanup guards.
- Add stable server-side packet error classification for EOF, short frame, oversized frame, malformed protobuf, timeout, short write, encode, and other errors.
- Consume the server scalability live two-client fanout smoke as networking runtime evidence when available.
- Add a bounded live slow-reader smoke that proves a non-reading TCP client hits the session write timeout while a separate fast client still receives bootstrap chunk data.
- Consume a bounded client reconnect smoke that proves a live TCP disconnect, server restart, client reconnect, and rebootstrap back to `client_state=active`.
- Define reconnect and overload gaps before broader runtime policy changes.

Out of scope:

- No protobuf schema change, new packet type, wire framing change, packet replay layer, write backpressure queue, server admission control, queue drop behavior, or broad load harness.

Assumptions:

- TCP remains the only transport.
- Packet framing remains a 4-byte little-endian payload length followed by exact protobuf payload bytes.
- The server treats read/decode errors as connection termination.
- The client reader thread reports receive errors to the main thread, exits the reader loop, moves the client lifecycle to `reconnecting`, then the client retries with a bounded cadence and reboots the stream by sending the current player position.
- Slow-client behavior is unit-guarded for bounded writes and failed broadcast cleanup, with a bounded live slow-reader smoke covering one slow reader plus one fast client. Broader load behavior still needs a dedicated harness.

Done when:

- Server and Rust client packet boundary tests cover short, oversized, and malformed input paths.
- A networking robustness gate runs the focused tests, can run or consume the slow-reader and reconnect smokes, and records deferred overload/backpressure work.

Checks:

- `sh scripts/networking_robustness_gate.sh logs/networking_robustness_current`

## Current Robustness Contract

- Server `receivePacket` uses `io.ReadFull` for both the length prefix and the advertised payload.
- Server `receivePacket` rejects lengths above `maxPacketSize` before allocating payload storage.
- Server `receivePacket` decodes exactly one protobuf `api.Packet` per frame and returns decode errors to the connection loop.
- Server `handleConnection` logs receive errors as disconnects and closes the connection through `defer conn.Close()`.
- Server packet and write errors are classified into stable `packet_error_class` labels: `eof`, `short_frame`, `oversized_frame`, `malformed_protobuf`, `timeout`, `short_write`, `encode_error`, and `other`.
- Server `receiveInitialClientPacket` has a bounded read deadline for startup probing and clears the deadline before normal streaming.
- Server `sendPacket` writes the length prefix and payload through `writeFull`, which rejects zero-byte writes with `io.ErrShortWrite`.
- Live session chunk writes set and clear a bounded write deadline using `RUMPELMC_SERVER_CLIENT_WRITE_TIMEOUT_MS`; `0` disables it as a rollback/control.
- Failed non-origin block-update broadcasts close and unregister the failed client.
- The server scalability live smoke validates two real TCP clients receiving bootstrap chunk data and the same block-edit update through the existing frame/protobuf path.
- The slow-reader smoke validates a real non-reading TCP client timing out during a large RAW bootstrap stream while a separate fast client still receives chunk `0,0`.
- The client reconnect smoke validates a real Godot client detecting a server-side TCP disconnect, retrying after server restart, and exposing `client_state=active`, `reconnect_events`, `reconnect_successes`, and `network_reader_errors` in the perf marker.
- The repeated reconnect soak validates multiple server-side TCP disconnect/restart/rebootstrap cycles in one Godot session with the client ending in `active`.
- The Rust client tags reader-thread packet/error events with a session id, ignores events from stale sessions, and drops same-drain queued packets when the current session reports a reader error.
- Rust `NetworkClient::receive_packet_with_timing_since` reads the exact length prefix, rejects lengths above `MAX_PACKET_LENGTH`, reads the exact payload, then decodes one protobuf `Packet`.
- Rust `NetworkClient::send_packet` rejects encoded packets larger than `MAX_PACKET_LENGTH` before writing.

## Added Client Guards

`client/rust_ext/src/network.rs` now has focused unit coverage for:

- `receive_returns_unexpected_eof_on_short_length_prefix`
- `receive_returns_unexpected_eof_on_short_payload`
- `receive_rejects_malformed_payload`

These complement the existing Rust oversized-length test and the Go server framing tests. The tests do not change runtime reconnect, queueing, decode, or send behavior.

## Session/Stale Packet Policy

Reconnect uses a client-side session generation guard without changing the wire format. Each successful connect/reconnect increments `network_session_id`, installs a new receiver, and spawns a reader thread whose events carry that id.

The main thread treats reader events from older sessions as stale and ignores them. If an error for the current session is drained together with packets from that same session, those packets are also ignored; the error moves the lifecycle to `reconnecting` and the next successful reconnect performs a normal position bootstrap. Perf markers expose `network_session`, `network_stale_events`, `network_stale_packets`, and `network_stale_errors`.

This policy prevents old reader errors or same-frame disconnect packets from mutating the current client state. It does not implement packet replay, backpressure, overloaded-client admission, or broad clearing of loaded chunks, mesh queues, collision queues, or GPU residency.

## Existing Server Guards

`server/pkg/network/framing_test.go` already covers:

- length-prefixed protobuf send/receive shape
- short frame receive errors
- short payload receive errors
- oversized length rejection
- malformed protobuf rejection
- closed initial-client probe handling
- initial position handshake read
- stable packet error classification labels
- connection-loop `packet_error_class` logging for malformed initial packets
- zero-byte write classification as `short_write`

`server/pkg/network/server_test.go` also covers:

- client write-timeout configuration parsing
- session write deadline set/clear behavior
- interested-client block-update fanout
- failed interested-client broadcast disconnect cleanup

`scripts/server_multi_client_smoke.sh` complements those unit guards with a bounded live two-client fanout smoke. It is not a slow-reader, reconnect, or overload harness.

## Live Slow-Reader Smoke

`scripts/server_slow_reader_smoke.sh` builds and starts the Go server on an isolated local smoke port and temporary RocksDB path, then runs `server/cmd/slow_reader_smoke` against it. The server is configured with RAW chunks, full bootstrap radius, high chunk batch size, and a short `RUMPELMC_SERVER_CLIENT_WRITE_TIMEOUT_MS` so the non-reading client creates real TCP write pressure.

The live client opens a slow TCP session, sends an initial position, does not read from that session, then opens a separate fast client and verifies that the fast client receives chunk `0,0`. The wrapper also requires server-log evidence of an `i/o timeout` on the slow client's initial chunk stream.

Use:

```sh
sh scripts/server_slow_reader_smoke.sh logs/server_slow_reader_smoke_current
```

Expected summary:

```text
server_slow_reader_smoke status=pass slow_client=1 fast_client=1 fast_bootstrap_chunk=1 slow_timeout_observed=1 ... protocol_change=0
```

This is a bounded isolation smoke, not a throughput benchmark, admission-control policy, reconnect harness, or proof of broadcast/backpressure fairness under large client counts.

## Live Reconnect Smoke

`scripts/client_reconnect_smoke.sh` starts the Go server on the normal local client port, starts a Godot visual smoke, kills the server, restarts it before capture, and requires the marker to report `client_state=active`, at least one reconnect event, at least one reconnect success, and at least one reader-thread network error.

Use:

```sh
RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE=1 RUMPELMC_GODOT_RUST_EXT_PROFILE=release sh scripts/client_reconnect_smoke.sh logs/client_reconnect_smoke_current
```

Expected summary:

```text
client_reconnect_smoke status=pass client_state=active reconnect_events=1 reconnect_successes=1 network_reader_errors=1 ... active_protocol_change=0
```

This is a bounded retry/rebootstrap smoke. It is not a stale packet, packet replay, overload, queue reset, or backpressure proof.

## Repeated Reconnect Soak

`scripts/client_reconnect_soak.sh` wraps the live reconnect smoke with multiple kill/restart cycles in one Godot session. The default run uses three cycles and requires each cycle to produce a reader error and a reconnect success.

Use:

```sh
RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE=1 RUMPELMC_GODOT_RUST_EXT_PROFILE=release sh scripts/client_reconnect_soak.sh logs/client_reconnect_soak_current
```

Expected summary:

```text
client_reconnect_soak status=pass reconnect_cycles=3 client_state=active reconnect_successes=3 network_reader_errors=3 ... active_protocol_change=0
```

This is bounded repeated runtime evidence. It does not define packet replay, overload behavior, broad loaded-state reset, or backpressure policy.

## Deferred Robustness Work

Still needed before claiming a full networking robustness program:

- Broader reconnect state reset rules, packet replay policy, and longer reconnect failure/idle soak.
- Broader multi-client slow-reader load evidence across more active clients, broadcast fanout, and longer runs.
- Server overload/admission behavior and connection limits under load.
- Operational aggregation and alert thresholds for the existing classified packet error labels.
- Backpressure policy for the existing client reader-thread channel.

## Compatibility Rules

- Do not change `api/schema/packets.proto` for networking robustness instrumentation unless a protocol task approves it.
- Do not change the 4-byte little-endian frame prefix.
- Do not add packet retries or ordering semantics inside `ChunkData`.
- Do not drop, coalesce, or reorder current-session packets outside the session-error reset policy without an explicit queue/backpressure design.
- Do not treat reconnect recovery as complete for adversarial networks until repeated reconnect behavior, broader state reset policy, overload behavior, and backpressure are defined and tested.
- Do not tighten slow-client timeout defaults without proving startup, bootstrap, and normal movement are not falsely terminated.

## Block 38 Gate

Use:

```sh
sh scripts/networking_robustness_gate.sh logs/networking_robustness_current
```

The expected current result is `status=pass`, `robustness_status=unit_guarded`, `client_boundary_tests=pass`, `server_boundary_tests=pass`, `stale_packet_policy=session_guarded`, `packet_error_classification=unit_guarded`, `active_protocol_change=0`, `reconnect_status=repeated_live_rebootstrap_guarded` when current reconnect smoke and soak summaries exist, `slow_client_status=unit_guarded` or `live_guarded` when a current slow-reader smoke summary exists, `slow_reader_smoke_status=deferred` or `pass`, `multi_client_live_status=deferred` or `pass` depending on the server scalability summary, and `overload_status=deferred`.

To run the slow-reader smoke inside the gate:

```sh
RUMPELMC_NETWORKING_ROBUSTNESS_RUN_SLOW_READER_SMOKE=1 sh scripts/networking_robustness_gate.sh logs/networking_robustness_current
```

To run the reconnect soak inside the gate:

```sh
RUMPELMC_NETWORKING_ROBUSTNESS_RUN_RECONNECT_SOAK=1 sh scripts/networking_robustness_gate.sh logs/networking_robustness_current
```

The gate checks that:

- This document records the current robustness contract, added client guards, existing server guards, deferred robustness work, and compatibility rules.
- Server and client sources still enforce max packet sizes and exact reads.
- Server logs still expose stable packet error classification labels for receive, decode, timeout, encode, and short-write failures.
- Go server framing/network tests pass.
- Rust network and reader-drain session tests pass.
- The server scalability summary is clean and carries the current live two-client smoke status when that smoke has been run.
- The reconnect smoke and repeated reconnect soak summaries are clean when current artifacts exist or the runs are explicitly requested.
- The slow-reader smoke script exists, and the gate carries its status when a current slow-reader summary exists or the smoke is explicitly run.
- The reconnect smoke script exists, and the gate carries its status when a current reconnect summary exists or the smoke is explicitly run.
- Protocol schema/generated files are unchanged.

## Current Status

This block is complete as a packet-boundary, classified packet-error, unit-guarded write-timeout, two-client live fanout, bounded slow-reader, bounded repeated reconnect/rebootstrap, and unit-guarded reader-session stale-packet checkpoint. Overload handling, broader live load, broadcast/backpressure policy, broad reconnect state reset, packet replay, and classified-error aggregation remain future work.
