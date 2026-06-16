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
- Add a parser-guarded offline summary for `packet_error_class` counts across server log artifacts.
- Consume the server scalability opt-in max-client admission cap, bounded live admission-limit smoke, and bounded admission-limit matrix as the current overload/admission checkpoint.
- Consume the server scalability live two-client fanout smoke as networking runtime evidence when available.
- Consume the server scalability conflict-semantics guard as the current block-edit concurrency policy checkpoint.
- Guard nil packet handler inputs as ignored unsupported packet shapes instead of panicking or emitting chunk updates.
- Guard nil `ClientPosition` payload bodies as ignored unsupported packet shapes instead of panicking or emitting chunk updates.
- Guard nil `BlockAction` payload bodies as ignored unsupported packet shapes instead of panicking or emitting chunk updates.
- Add a bounded live slow-reader smoke and load matrix that prove a non-reading TCP client hits the session write timeout while fast clients still receive bootstrap chunk data.
- Require bounded client reconnect smoke and repeated reconnect soak summaries that prove live TCP disconnects, server restarts, client reconnects, and rebootstrap back to `client_state=active`.
- Define reconnect and overload gaps before broader runtime policy changes.

Out of scope:

- No protobuf schema change, new packet type, wire framing change, packet replay layer, write backpressure queue, adaptive overload control, queue drop behavior, or broad load harness.

Assumptions:

- TCP remains the only transport.
- Packet framing remains a 4-byte little-endian payload length followed by exact protobuf payload bytes.
- The server treats read/decode errors as connection termination.
- The client reader thread reports receive errors to the main thread, exits the reader loop, moves the client lifecycle to `reconnecting`, then the client retries with a bounded cadence and reboots the stream by sending the current player position.
- Slow-client behavior is unit-guarded for bounded writes and failed broadcast cleanup, with bounded live slow-reader smoke and matrix evidence covering one slow reader plus multiple fast clients. Broadcast fanout and longer-run behavior still need dedicated harnesses.

Done when:

- Server and Rust client packet boundary tests cover short, oversized, and malformed input paths.
- A networking robustness gate runs the focused tests, requires bounded slow-reader and reconnect runtime evidence, and records remaining overload/backpressure gaps.

Checks:

- `sh scripts/networking_robustness_gate.sh logs/networking_robustness_current`

## Current Robustness Contract

- Server `receivePacket` uses `io.ReadFull` for both the length prefix and the advertised payload.
- Server `receivePacket` rejects lengths above `maxPacketSize` before allocating payload storage.
- Server `receivePacket` decodes exactly one protobuf `api.Packet` per frame and returns decode errors to the connection loop.
- Go packet framing tests prove back-to-back protobuf frames are consumed on exact frame boundaries.
- Go packet framing tests prove a zero-length protobuf payload frame decodes as an empty `api.Packet` instead of a malformed frame.
- Server `handleConnection` logs receive errors as disconnects and closes the connection through `defer conn.Close()`.
- Server packet and write errors are classified into stable `packet_error_class` labels: `eof`, `short_frame`, `oversized_frame`, `malformed_protobuf`, `timeout`, `short_write`, `encode_error`, and `other`.
- `scripts/packet_error_class_summary.sh` aggregates those labels from server log files, rejects unknown classes, and writes a count summary plus TSV.
- `scripts/packet_error_alert_threshold_gate.sh` runs the class summary over current live server smoke logs, including the slow-reader matrix logs when present, and applies operational thresholds to the classified labels.
- Server `receiveInitialClientPacket` has a bounded read deadline for startup probing and clears the deadline before normal streaming.
- Server `sendPacket` writes the length prefix and payload through `writeFull`, which rejects zero-byte writes with `io.ErrShortWrite`.
- Live session chunk writes set and clear a bounded write deadline using `RUMPELMC_SERVER_CLIENT_WRITE_TIMEOUT_MS`; `0` disables it as a rollback/control.
- Failed non-origin block-update broadcasts close and unregister the failed client.
- The server scalability live smoke validates two real TCP clients receiving bootstrap chunk data and the same block-edit update through the existing frame/protobuf path.
- The server scalability gate reports `conflict_semantics=last_write_wins_guarded` for valid sequential block edits at the same coordinate, proving interested clients receive the latest authoritative snapshot.
- The server scalability gate unit-guards the opt-in `RUMPELMC_SERVER_MAX_CLIENTS` admission cap and consumes bounded live admission-limit smoke plus matrix evidence without changing packet framing.
- Empty, unsupported, nil packet handler inputs, nil `ClientPosition`, or nil `BlockAction` packet payloads are ignored by the server handler without sending chunk updates.
- The slow-reader smoke validates a real non-reading TCP client timing out during a large RAW bootstrap stream while fast clients still receive bootstrap chunks.
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

This policy prevents old reader errors or same-frame disconnect packets from mutating the current client state. It does not implement packet replay, backpressure, adaptive overload handling, or broad clearing of loaded chunks, mesh queues, collision queues, or GPU residency.

## Existing Server Guards

`server/pkg/network/framing_test.go` already covers:

- length-prefixed protobuf send/receive shape
- short frame receive errors
- short payload receive errors
- oversized length rejection
- malformed protobuf rejection
- zero-length protobuf payload frame decoding to an empty packet
- exact back-to-back frame-boundary reads
- closed initial-client probe handling
- timeout initial-client probe handling after wrapped read errors
- initial position handshake read
- stable packet error classification labels
- connection-loop `packet_error_class` logging for malformed initial packets
- zero-byte write classification as `short_write`

`server/pkg/network/server_test.go` also covers:

- nil packet handler inputs ignored on initial and normal packet paths without chunk frames
- nil `ClientPosition` payload bodies ignored on initial and normal packet paths without chunk frames
- client write-timeout configuration parsing
- session write deadline set/clear behavior
- interested-client block-update fanout
- last-write-wins conflict semantics for valid block edits at the same coordinate
- failed interested-client broadcast disconnect cleanup
- nil `BlockAction` payload bodies ignored without origin or watcher chunk frames

`scripts/server_multi_client_smoke.sh` complements those unit guards with a bounded live two-client fanout smoke. It is not a slow-reader, reconnect, or overload harness.

## Live Slow-Reader Smoke

`scripts/server_slow_reader_smoke.sh` builds and starts the Go server on an isolated local smoke port and temporary RocksDB path, then runs `server/cmd/slow_reader_smoke` against it. The server is configured with RAW chunks, full bootstrap radius, high chunk batch size, and a short `RUMPELMC_SERVER_CLIENT_WRITE_TIMEOUT_MS` so the non-reading client creates real TCP write pressure.

The live client opens a slow TCP session, sends an initial position, does not read from that session, then opens one or more fast clients and verifies that each fast client receives its bootstrap chunk. The wrapper also requires server-log evidence of `packet_error_class=timeout` and `i/o timeout` on the slow client's initial chunk stream.

Use:

```sh
sh scripts/server_slow_reader_smoke.sh logs/server_slow_reader_smoke_current
```

Expected summary:

```text
server_slow_reader_smoke status=pass slow_client=1 fast_client=1 fast_bootstrap_chunk=1 slow_timeout_observed=1 slow_timeout_class=timeout ... protocol_change=0
```

This is a bounded isolation smoke, not a throughput benchmark, admission-control policy, reconnect harness, or proof of broadcast/backpressure fairness under large client counts.

## Slow-Reader Load Matrix

`scripts/server_slow_reader_matrix_smoke.sh` runs the live slow-reader smoke across several fast-client counts, defaulting to `1 2 4`. Each run keeps one slow non-reading client connected, requires every fast client to receive a bootstrap chunk, and requires one classified timeout for the slow client.

Use:

```sh
sh scripts/server_slow_reader_matrix_smoke.sh logs/server_slow_reader_matrix_current
```

Expected summary:

```text
server_slow_reader_matrix status=pass counts_checked=3 passed_counts=3 max_fast_clients=4 total_fast_clients=7 total_fast_bootstrap_chunks=7 total_slow_timeouts=3 protocol_change=0
```

When this matrix is present and clean, the networking gate reports `slow_client_status=load_matrix_guarded`. This is bounded local isolation/load evidence, not broadcast fanout fairness, long-run soak, or backpressure policy.

## Packet Error Alert Thresholds

`scripts/packet_error_alert_threshold_gate.sh` is the current operational alert threshold gate for live `packet_error_class` evidence. It intentionally uses live server smoke logs, including the bounded slow-reader matrix logs when present, instead of the synthetic parser fixture used by `networking_robustness_gate.sh`.

Default thresholds:

- Unknown classes: `0`
- Protocol error classes (`short_frame`, `oversized_frame`, `malformed_protobuf`): `0`
- Write/internal error classes (`short_write`, `encode_error`, `other`): `0`
- Timeout class: `4`, matching the current bounded slow-reader smoke plus matrix evidence
- EOF class: high default threshold, because clean client shutdowns currently log EOF disconnects

Use:

```sh
sh scripts/packet_error_alert_threshold_gate.sh logs/packet_error_alert_threshold_current
```

Expected current summary:

```text
packet_error_alert_threshold status=pass alert_status=threshold_guarded classified_events=39 unknown_classes=0 eof=35 timeout=4 protocol_errors=0 write_errors=0
```

This threshold gate is consumed by `scripts/packet_error_monitoring_contract_gate.sh` as the local packet-error monitoring export boundary. It is not authentication, abuse detection, external alert delivery, or long-run production traffic monitoring.

## Packet Error Monitoring Contract

`scripts/packet_error_monitoring_contract_gate.sh` converts the current classified packet-error alert evidence into a release-checkable local monitoring contract. It runs or consumes the alert-threshold gate, requires networking robustness and observability evidence to be clean, and writes `packet-error-monitoring-metrics.txt` for future CI or external monitoring ingestion.

Use:

```sh
sh scripts/packet_error_monitoring_contract_gate.sh logs/packet_error_monitoring_contract_current
```

Expected current summary:

```text
packet_error_monitoring_contract status=pass monitoring_contract=export_ready metrics_export=present alert_guard=threshold_guarded classified_events=39 unknown_classes=0 protocol_errors=0 write_errors=0
```

This is a local line-oriented export contract. It does not add a network endpoint, daemon, push job, SaaS integration, auth boundary, packet schema change, or server runtime behavior change.

## Live Admission Limit Smoke

The server scalability block owns `scripts/server_admission_limit_smoke.sh` and `scripts/server_admission_limit_matrix_smoke.sh`. Networking consumes their summaries through `scripts/server_scalability_pass_gate.sh`: when the matrix passes, `admission_policy=matrix_live_guarded` and this gate reports `overload_status=admission_matrix_guarded`. The same server-scalability summary must also report `scalability_status=repeat_live_guarded`, `resource_profile_status=repeat_live_guarded`, `multi_client_sent_state=guarded`, `block_edit_fanout=interested_clients_guarded`, `chunk_request_ordering=guarded`, `worldgen_biome_atlas_tile_identity=guarded`, `worldgen_biome_atlas_block_texture_usage=guarded`, `nil_sent_state_policy=empty_guarded`, `view_distance_config=guarded`, `disconnect_cleanup_status=lifecycle_summary_guarded`, `connection_lifecycle_status=pass`, zero close/accept failures, and complete active-client lifecycle fields before networking robustness can pass, so repeated live scalability, resource profile, streaming state, fanout, request ordering, worldgen atlas guard propagation, view-distance, and lifecycle cleanup evidence stay attached to the networking checkpoint.

The single smoke starts a local server with `RUMPELMC_SERVER_MAX_CLIENTS=<n>`, keeps `n` holder clients admitted through real chunk bootstrap, opens one excess client, requires that client to observe a close, and requires the server log to include `admission_result=rejected` with matching active/max client counts. The matrix currently checks limits `1 2 3`.

This is bounded overload evidence for the opt-in cap. It is not adaptive overload control, queue backpressure, sustained production max-client sizing, or broad load behavior.

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
- Broader slow-reader evidence under broadcast fanout and longer runs.
- Sustained max-client sizing and adaptive overload behavior under representative load.
- External monitoring service/upload/retention integration beyond the local packet-error monitoring contract.
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

The expected current result is `status=pass`, `robustness_status=unit_guarded`, `client_boundary_tests=pass`, `server_boundary_tests=pass`, `stale_packet_policy=session_guarded`, `unknown_packet_policy=ignored_guarded`, `nil_packet_policy=ignored_guarded`, `nil_position_policy=ignored_guarded`, `nil_block_action_policy=ignored_guarded`, `empty_payload_frame=decode_guarded`, `packet_error_classification=unit_guarded`, `packet_error_aggregation=parser_guarded`, `packet_error_alerts=threshold_guarded`, `conflict_semantics=last_write_wins_guarded`, `active_protocol_change=0`, `reconnect_status=repeated_live_rebootstrap_guarded`, `reconnect_smoke_status=pass`, `reconnect_soak_status=pass`, `slow_client_status=load_matrix_guarded`, `slow_reader_smoke_status=pass`, `slow_reader_timeout_class=timeout`, `slow_reader_matrix_status=pass`, `multi_client_live_status=pass`, and `overload_status=admission_matrix_guarded`.

To run the slow-reader smoke inside the gate:

```sh
RUMPELMC_NETWORKING_ROBUSTNESS_RUN_SLOW_READER_SMOKE=1 sh scripts/networking_robustness_gate.sh logs/networking_robustness_current
```

To run the slow-reader matrix inside the gate:

```sh
RUMPELMC_NETWORKING_ROBUSTNESS_RUN_SLOW_READER_MATRIX=1 sh scripts/networking_robustness_gate.sh logs/networking_robustness_current
```

To run the reconnect smoke and soak inside the gate:

```sh
RUMPELMC_NETWORKING_ROBUSTNESS_RUN_RECONNECT_SMOKE=1 sh scripts/networking_robustness_gate.sh logs/networking_robustness_current
RUMPELMC_NETWORKING_ROBUSTNESS_RUN_RECONNECT_SOAK=1 sh scripts/networking_robustness_gate.sh logs/networking_robustness_current
```

The gate checks that:

- This document records the current robustness contract, added client guards, existing server guards, deferred robustness work, and compatibility rules.
- Server and client sources still enforce max packet sizes and exact reads.
- Server logs still expose stable packet error classification labels for receive, decode, timeout, encode, and short-write failures.
- The packet-error class summary parser accepts all known labels and rejects unknown label drift.
- The packet-error alert threshold gate reports `packet_error_alert_threshold status=pass` over current live server smoke logs.
- Go server framing/network tests pass.
- Go server session tests prove empty payload packets are ignored without sending chunk frames.
- Go server session tests prove nil packet handler inputs are ignored without sending chunk frames.
- Go server session tests prove nil `ClientPosition` payload bodies are ignored without sending chunk frames.
- Go server session tests prove nil `BlockAction` payload bodies are ignored without sending chunk frames.
- Go server framing tests prove zero-length payload frames decode to empty packets before the session-level ignore policy applies.
- Rust network and reader-drain session tests pass.
- The server scalability summary is clean and carries the current live two-client smoke status when that smoke has been run.
- The reconnect smoke and repeated reconnect soak summaries are current and clean; explicit run flags refresh those required summaries before validation.
- The slow-reader smoke and matrix scripts exist, require classified timeout log evidence, and the gate requires current clean summaries before reporting `status=pass`.
- The reconnect smoke and soak scripts exist, and the gate requires current clean summaries before reporting `status=pass`.
- Protocol schema/generated files are unchanged.

## Current Status

This block is complete as a packet-boundary, zero-length frame decode, empty/unknown/nil-packet/nil-position/nil-block-action ignore policy, classified packet-error, parser-guarded classified-error aggregation, local classified-error alert threshold, local packet-error monitoring export contract, unit-guarded write-timeout, opt-in max-client admission with bounded live rejection and admission-matrix evidence, two-client live fanout, bounded slow-reader load matrix, bounded repeated reconnect/rebootstrap, and unit-guarded reader-session stale-packet checkpoint. Adaptive overload handling, broadcast/backpressure policy, broad reconnect state reset, packet replay, and external monitoring service/upload integration remain future work.
