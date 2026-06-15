# Server Scalability Pass

Block 37, Server Scalability Pass, records the first multi-client server scalability checkpoint for chunk scheduling fairness, CPU/memory evidence, and disconnect cleanup.

## Technical Brief

User request:

Continue the annual world streaming architecture plan in order and use MCP/OntoIndex context.

Goal:

Check server behavior under multiple clients without changing protocol or runtime scheduling policy.

Context inspected:

- OntoIndex concept search for multi-client server scalability, chunk scheduling fairness, disconnect cleanup, and network tests.
- `server/pkg/network/server.go` connection loop, per-connection stream state, chunk send path, and packet receive path.
- `server/pkg/network/server_test.go` chunk batching, bootstrap, RLE send, and stream ordering tests.
- `docs/PROTOCOL.md`.
- `docs/WORLD_GENERATION_QUALITY_PASS.md`.

Scope:

- Add a narrow unit guard for per-client sent-chunk state isolation.
- Add a session registry for live connections.
- Broadcast block-edit chunk snapshots to interested clients that have already received that chunk.
- Add a bounded write timeout and disconnect cleanup for failed non-origin broadcast clients.
- Add a bounded live two-client smoke that validates real TCP chunk bootstrap and block-edit fanout.
- Define the next scalability evidence needed before broader runtime policy changes.

Out of scope:

- No protocol change, packet shape change, connection pool, backpressure queue, global scheduler, CPU profiling harness, memory profiling harness, disconnect metric, slow-reader harness, or production concurrency limit.

Assumptions:

- The current server handles each accepted connection in its own goroutine.
- `clientChunkStreamState` is intentionally per connection.
- Chunk generation/storage access remains serialized through `World` locking.
- Broadcast uses the existing `ChunkData` snapshot packet and only targets clients whose sent-chunk state already includes the edited chunk.

Done when:

- Per-client sent-chunk state isolation has a focused unit test.
- Block-edit fanout to interested clients has a focused unit test.
- Failed interested-client broadcast closes and unregisters that client.
- Session writes set and clear a write deadline.
- The scalability gate runs the focused network tests and can run or consume the live two-client smoke summary.

Checks:

- `sh scripts/server_scalability_pass_gate.sh logs/server_scalability_pass_current`

## Current Server Contract

- `Server.Start()` accepts TCP connections and launches `go s.handleConnection(conn)` for each accepted connection.
- `handleConnection` owns a registered `clientSession` with its own `clientChunkStreamState` and `sentChunks` map.
- `defer conn.Close()` remains the normal connection cleanup; failed non-origin broadcast clients are also closed and unregistered immediately.
- `sendChunksAroundWithRadiusOrdered` asks the shared `World` for chunks and mutates only the caller-provided sent map.
- The current protocol has no multi-client session identity, global scheduler packet, or server broadcast packet.
- Chunk stream metrics are per batch and log-only.
- Session writes are serialized per connection and bounded by `RUMPELMC_SERVER_CLIENT_WRITE_TIMEOUT_MS`; `0` disables the timeout as a rollback/control.

## Added Unit Guard

`TestSendChunksAroundKeepsPerClientSentStateIndependent` proves that two clients with independent `sentChunks` maps can both receive the current chunk, and that progress in one client's sent map does not mutate the other client's sent map.

`TestHandleClientPacketBroadcastsBlockUpdateToInterestedClients` proves that a block edit sends the updated chunk to the origin client and to already-interested clients, while clients without that chunk receive no update.

`TestBroadcastDisconnectsFailedInterestedClient` proves that a failed interested-client broadcast closes and unregisters the failed client without failing the origin edit.

`TestSendChunkToSessionSetsAndClearsWriteDeadline` proves that session chunk writes set and clear the configured write deadline.

These tests lock core fairness, fanout, and failed-write cleanup invariants without changing protocol shape.

## Live Multi-Client Smoke

`scripts/server_multi_client_smoke.sh` builds and starts the Go server on an isolated local smoke port and temporary RocksDB path, then runs `server/cmd/multi_client_smoke` against it. The smoke uses the real 4-byte little-endian frame prefix and protobuf `Packet` schema.

The live client opens two TCP sessions, sends initial positions for both, waits for both clients to receive chunk `0,0`, sends a `BlockAction_PLACE` for wood at `1,64,1`, and verifies that both the origin and watcher receive the updated chunk with that block present. The client accepts both raw and RLE chunk encodings and decodes RLE through the server world package.

Use:

```sh
sh scripts/server_multi_client_smoke.sh logs/server_multi_client_smoke_current
```

Expected summary:

```text
server_multi_client_smoke status=pass clients=2 origin_initial=1 watcher_initial=1 origin_update=1 watcher_update=1 ... protocol_change=0
```

This is a live fanout/bootstrap smoke, not a throughput, memory, slow-reader, or overload benchmark.

## Scalability Gaps

Still needed before claiming full live multi-client scalability:

- Live multi-client load beyond the bounded two-client fanout smoke.
- More-than-two-client load evidence that records per-client chunks sent, elapsed time, disconnect behavior, and server errors.
- CPU/memory profiling under multiple active clients.
- Broader slow-client handling evidence under more clients and broadcast load; the networking robustness block now owns the bounded two-client slow-reader smoke.
- Disconnect cleanup counters or log summaries.
- Block-edit fanout/broadcast load evidence under several active clients beyond the two-client smoke.
- Fair scheduling or backpressure design if one client can monopolize generation/send work.

## Compatibility Rules

- Do not change `api/schema/packets.proto` for scalability instrumentation unless a protocol task approves it.
- Do not change chunk payload encoding for multi-client work.
- Do not promote directional ordering or any future scheduler to default without pop-in/queue evidence.
- Do not add global mutable scheduling state without race and fairness tests.
- Do not persist connection state in world/storage data.

## Block 37 Gate

Use:

```sh
sh scripts/server_scalability_pass_gate.sh logs/server_scalability_pass_current
```

For the fast default gate, the expected current result is `status=pass`, `scalability_status=unit_guarded`, `multi_client_sent_state=guarded`, `block_edit_fanout=interested_clients_guarded`, `slow_client_write_timeout=guarded`, `active_protocol_change=0`, `live_load_status=deferred` or `pass` when a current smoke summary exists, and `network_tests=pass`.

To run the live smoke inside the gate:

```sh
RUMPELMC_SERVER_SCALABILITY_RUN_LIVE_SMOKE=1 sh scripts/server_scalability_pass_gate.sh logs/server_scalability_pass_current
```

With the live smoke enabled, the expected result includes `live_load_status=pass`.

The gate checks that:

- This document records current server behavior, added unit guards, live scalability gaps, and compatibility rules.
- `server.go` still has per-session `clientChunkStreamState`, connection close cleanup, block-edit fanout, and write deadlines.
- The live smoke script exists and records `server_multi_client_smoke status=pass`.
- The multi-client sent-state, interested-client fanout, failed-broadcast cleanup, and write-deadline tests exist.
- `api/schema/packets.proto` is unchanged.
- Focused network tests pass.

## Current Status

This block is complete as a unit-guard/checkpoint block with a bounded live two-client fanout smoke. Broader live load, CPU/memory profiling, broad slow-reader/load harnesses, and disconnect metrics remain future work.
