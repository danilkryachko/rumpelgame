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
- Define reconnect, live slow-reader, and overload gaps before broader runtime policy changes.

Out of scope:

- No protobuf schema change, new packet type, wire framing change, reconnect state machine, write backpressure queue, server admission control, packet retry layer, queue drop behavior, or live load harness.

Assumptions:

- TCP remains the only transport.
- Packet framing remains a 4-byte little-endian payload length followed by exact protobuf payload bytes.
- The server treats read/decode errors as connection termination.
- The client reader thread reports receive errors and exits the reader loop; reconnect policy is not implemented in this block.
- Slow-client behavior is unit-guarded for bounded writes and failed broadcast cleanup; real slow-reader/live-load behavior still needs a dedicated harness.

Done when:

- Server and Rust client packet boundary tests cover short, oversized, and malformed input paths.
- A networking robustness gate runs the focused tests and records deferred reconnect, live slow-reader, and overload work.

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

## Deferred Robustness Work

Still needed before claiming a full networking robustness program:

- Client reconnect state machine with explicit states, backoff, and stale packet handling.
- Live multi-client slow-reader harness that proves one slow client does not stall unrelated clients.
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

The expected current result is `status=pass`, `robustness_status=unit_guarded`, `client_boundary_tests=pass`, `server_boundary_tests=pass`, `active_protocol_change=0`, `reconnect_status=deferred`, `slow_client_status=unit_guarded`, and `overload_status=deferred`.

The gate checks that:

- This document records the current robustness contract, added client guards, existing server guards, deferred robustness work, and compatibility rules.
- Server and client sources still enforce max packet sizes and exact reads.
- Go server framing/network tests pass.
- Rust network tests pass.
- Protocol schema/generated files are unchanged.

## Current Status

This block is complete as a packet-boundary and unit-guarded write-timeout checkpoint. Reconnect, live slow-reader validation, overload handling, and runtime telemetry remain future work.
