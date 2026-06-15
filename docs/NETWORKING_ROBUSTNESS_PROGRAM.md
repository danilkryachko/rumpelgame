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
- Consume the server scalability live two-client fanout smoke as networking runtime evidence when available.
- Add a bounded live slow-reader smoke that proves a non-reading TCP client hits the session write timeout while a separate fast client still receives bootstrap chunk data.
- Define reconnect and overload gaps before broader runtime policy changes.

Out of scope:

- No protobuf schema change, new packet type, wire framing change, reconnect state machine, write backpressure queue, server admission control, packet retry layer, queue drop behavior, or broad load harness.

Assumptions:

- TCP remains the only transport.
- Packet framing remains a 4-byte little-endian payload length followed by exact protobuf payload bytes.
- The server treats read/decode errors as connection termination.
- The client reader thread reports receive errors and exits the reader loop; reconnect policy is not implemented in this block.
- Slow-client behavior is unit-guarded for bounded writes and failed broadcast cleanup, with a bounded live slow-reader smoke covering one slow reader plus one fast client. Broader load behavior still needs a dedicated harness.

Done when:

- Server and Rust client packet boundary tests cover short, oversized, and malformed input paths.
- A networking robustness gate runs the focused tests, can run or consume the slow-reader smoke, and records deferred reconnect and overload work.

Checks:

- `sh scripts/networking_robustness_gate.sh logs/networking_robustness_current`

## Current Robustness Contract

- Server `receivePacket` uses `io.ReadFull` for both the length prefix and the advertised payload.
- Server `receivePacket` rejects lengths above `maxPacketSize` before allocating payload storage.
- Server `receivePacket` decodes exactly one protobuf `api.Packet` per frame and returns decode errors to the connection loop.
- Server `handleConnection` logs receive errors as disconnects and closes the connection through `defer conn.Close()`.
- Server `receiveInitialClientPacket` has a bounded read deadline for startup probing and clears the deadline before normal streaming.
- Server `sendPacket` writes the length prefix and payload through `writeFull`, which rejects zero-byte writes with `io.ErrShortWrite`.
- Live session chunk writes set and clear a bounded write deadline using `RUMPELMC_SERVER_CLIENT_WRITE_TIMEOUT_MS`; `0` disables it as a rollback/control.
- Failed non-origin block-update broadcasts close and unregister the failed client.
- The server scalability live smoke validates two real TCP clients receiving bootstrap chunk data and the same block-edit update through the existing frame/protobuf path.
- The slow-reader smoke validates a real non-reading TCP client timing out during a large RAW bootstrap stream while a separate fast client still receives chunk `0,0`.
- Rust `NetworkClient::receive_packet_with_timing_since` reads the exact length prefix, rejects lengths above `MAX_PACKET_LENGTH`, reads the exact payload, then decodes one protobuf `Packet`.
- Rust `NetworkClient::send_packet` rejects encoded packets larger than `MAX_PACKET_LENGTH` before writing.

## Added Client Guards

`client/rust_ext/src/network.rs` now has focused unit coverage for:

- `receive_returns_unexpected_eof_on_short_length_prefix`
- `receive_returns_unexpected_eof_on_short_payload`
- `receive_rejects_malformed_payload`

These complement the existing Rust oversized-length test and the Go server framing tests. The tests do not change runtime reconnect, queueing, decode, or send behavior.

## Existing Server Guards

`server/pkg/network/framing_test.go` already covers:

- length-prefixed protobuf send/receive shape
- short frame receive errors
- oversized length rejection
- malformed protobuf rejection
- closed initial-client probe handling
- initial position handshake read

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

## Deferred Robustness Work

Still needed before claiming a full networking robustness program:

- Client reconnect state machine with explicit states, backoff, and stale packet handling.
- Broader multi-client slow-reader load evidence across more active clients, broadcast fanout, and longer runs.
- Server overload/admission behavior and connection limits under load.
- Live reconnect smoke that restarts the server and proves client recovery.
- Packet error telemetry that classifies EOF, oversized frame, malformed protobuf, timeout, and short write causes.
- Backpressure policy for the existing client reader-thread channel.

## Compatibility Rules

- Do not change `api/schema/packets.proto` for networking robustness instrumentation unless a protocol task approves it.
- Do not change the 4-byte little-endian frame prefix.
- Do not add packet retries or ordering semantics inside `ChunkData`.
- Do not drop, coalesce, or reorder packets without an explicit queue/backpressure design.
- Do not treat reconnect as complete until the client state machine is defined and tested.
- Do not tighten slow-client timeout defaults without proving startup, bootstrap, and normal movement are not falsely terminated.

## Block 38 Gate

Use:

```sh
sh scripts/networking_robustness_gate.sh logs/networking_robustness_current
```

The expected current result is `status=pass`, `robustness_status=unit_guarded`, `client_boundary_tests=pass`, `server_boundary_tests=pass`, `active_protocol_change=0`, `reconnect_status=deferred`, `slow_client_status=unit_guarded` or `live_guarded` when a current slow-reader smoke summary exists, `slow_reader_smoke_status=deferred` or `pass`, `multi_client_live_status=deferred` or `pass` depending on the server scalability summary, and `overload_status=deferred`.

To run the slow-reader smoke inside the gate:

```sh
RUMPELMC_NETWORKING_ROBUSTNESS_RUN_SLOW_READER_SMOKE=1 sh scripts/networking_robustness_gate.sh logs/networking_robustness_current
```

The gate checks that:

- This document records the current robustness contract, added client guards, existing server guards, deferred robustness work, and compatibility rules.
- Server and client sources still enforce max packet sizes and exact reads.
- Go server framing/network tests pass.
- Rust network tests pass.
- The server scalability summary is clean and carries the current live two-client smoke status when that smoke has been run.
- The slow-reader smoke script exists, and the gate carries its status when a current slow-reader summary exists or the smoke is explicitly run.
- Protocol schema/generated files are unchanged.

## Current Status

This block is complete as a packet-boundary, unit-guarded write-timeout, two-client live fanout, and bounded slow-reader checkpoint. Reconnect, overload handling, broader live load, broadcast/backpressure policy, and runtime error classification telemetry remain future work.
