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
- Add an opt-in max-client admission cap with a default unlimited rollback/control.
- Add a bounded live two-client smoke that validates real TCP chunk bootstrap, block-edit fanout, and server RSS/CPU sampling.
- Add a bounded broader live smoke that validates bootstrap, block-edit fanout, and server RSS/CPU sampling across more than two clients.
- Add a bounded repeated six-client smoke that validates several consecutive live runs and aggregates detail/resource evidence.
- Add a bounded live admission-limit smoke that validates one accepted holder and one rejected excess TCP client.
- Add a server connection lifecycle summary that counts connected, rejected, disconnected, close-failure, and accept-failure events from live smoke logs.
- Define the next scalability evidence needed before broader runtime policy changes.

Out of scope:

- No protocol change, packet shape change, connection pool, backpressure queue, global scheduler, CPU profiling harness, memory profiling harness, disconnect metric, broad slow-reader harness, adaptive admission policy, or production concurrency sizing.

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
- The scalability gate runs the focused network tests and can run or consume the live two-client and broader multi-client smoke summaries with server resource samples.
- The scalability gate can run or consume repeated multi-client smoke evidence.
- The scalability gate can run or consume a live max-client admission-limit smoke summary.
- The scalability gate can generate and consume a connection lifecycle summary from available smoke server logs.

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
- `RUMPELMC_SERVER_MAX_CLIENTS` defaults to `0` for unlimited clients. Positive values make `handleConnection` reject excess accepted TCP sessions before registering them, close the connection, and log `admission_result=rejected` with active/max client counts.

## Added Unit Guard

`TestSendChunksAroundKeepsPerClientSentStateIndependent` proves that two clients with independent `sentChunks` maps can both receive the current chunk, and that progress in one client's sent map does not mutate the other client's sent map.

`TestHandleClientPacketBroadcastsBlockUpdateToInterestedClients` proves that a block edit sends the updated chunk to the origin client and to already-interested clients, while clients without that chunk receive no update.

`TestBroadcastDisconnectsFailedInterestedClient` proves that a failed interested-client broadcast closes and unregisters the failed client without failing the origin edit.

`TestSendChunkToSessionSetsAndClearsWriteDeadline` proves that session chunk writes set and clear the configured write deadline.

`TestConfiguredMaxClientsParsesSupportedValues`, `TestTryRegisterClientHonorsMaxClients`, and `TestHandleConnectionRejectsWhenMaxClientsReached` prove the opt-in admission cap, default unlimited mode, invalid-env fallback, atomic registry rejection, and rejected-connection logging.

These tests lock core fairness, fanout, failed-write cleanup, and admission-cap invariants without changing protocol shape.

## Live Multi-Client Smoke

`scripts/server_multi_client_smoke.sh` builds and starts the Go server on an isolated local smoke port and temporary RocksDB path, then runs `server/cmd/multi_client_smoke` against it. The smoke uses the real 4-byte little-endian frame prefix and protobuf `Packet` schema.

The live client opens TCP sessions, sends initial positions for each, waits for each client to receive chunk `0,0`, sends a `BlockAction_PLACE` for wood at `1,64,1`, and verifies that every interested client receives the updated chunk with that block present. The wrapper writes per-client initial/update detail rows to `server-multi-client-details.tsv`, samples server RSS and CPU percentage while the client smoke runs, and writes `server-resource-samples.tsv`. The default remains two clients. Set `RUMPELMC_SERVER_MULTI_CLIENT_SMOKE_CLIENTS=<n>` for broader load evidence. The client accepts both raw and RLE chunk encodings and decodes RLE through the server world package.

Use:

```sh
sh scripts/server_multi_client_smoke.sh logs/server_multi_client_smoke_current
```

Expected summary:

```text
server_multi_client_smoke status=pass clients=2 origin_initial=1 watcher_initial=1 origin_update=1 watcher_update=1 ... detail_status=pass detail_clients=2 server_resource_samples=7 server_rss_kb_max=26512 server_cpu_pct_max=1.4 protocol_change=0
```

This is a live fanout/bootstrap/resource-sampling smoke, not a throughput benchmark, production profiler capture, slow-reader harness, or overload benchmark.

## Broader Live Multi-Client Load Smoke

The broader load smoke reuses `scripts/server_multi_client_smoke.sh` with a higher client count. Current bounded target:

```sh
RUMPELMC_SERVER_MULTI_CLIENT_SMOKE_CLIENTS=6 sh scripts/server_multi_client_smoke.sh logs/server_multi_client_load_current
```

Expected summary:

```text
server_multi_client_smoke status=pass clients=6 initial_chunks=6 fanout_updates=6 ... detail_status=pass detail_clients=6 server_resource_samples=6 server_rss_kb_max=31584 server_cpu_pct_max=5.2 protocol_change=0
```

This proves a single live server can bootstrap and fan out one block edit to more than two interested clients while exposing bounded RSS/CPU samples. It does not claim throughput capacity, production memory headroom, admission behavior, slow-reader fairness, or overload policy.

## Resource Profile Evidence

`scripts/server_multi_client_smoke.sh` writes per-client observations to `server-multi-client-details.tsv`, writes process resource samples for the live Go server to `server-resource-samples.tsv`, and appends detail and resource fields to the smoke summary. The detail fields include `detail_status`, `detail_clients`, `detail_initial_chunks`, `detail_update_chunks`, `detail_initial_ms_max`, and `detail_update_ms_max`; resource fields include `server_resource_samples`, `server_rss_kb_max`, `server_rss_kb_avg`, `server_cpu_pct_max`, and `server_cpu_pct_avg`.

Current bounded evidence:

- Two-client fanout smoke: `detail_clients=2`, `server_resource_samples=7`, `server_rss_kb_max=26512`, and `server_cpu_pct_max=1.4`.
- Six-client fanout/load smoke: `detail_clients=6`, `server_resource_samples=6`, `server_rss_kb_max=31584`, and `server_cpu_pct_max=5.2`.

The scalability gate reports `resource_profile_status=broader_live_guarded` when the broader live smoke summary has per-client detail rows for every client, at least one server resource sample, and a nonzero RSS maximum. When repeated multi-client evidence is present and clean, the gate raises both `scalability_status` and `resource_profile_status` to `repeat_live_guarded`.

## Repeated Multi-Client Smoke

`scripts/server_multi_client_repeat_smoke.sh` runs `scripts/server_multi_client_smoke.sh` several times, defaulting to three repeats with six clients each, then aggregates per-run totals, per-client detail counts, resource samples, max RSS, max CPU percentage, and protocol-change count.

Use:

```sh
sh scripts/server_multi_client_repeat_smoke.sh logs/server_multi_client_repeat_smoke_current
```

Expected summary:

```text
server_multi_client_repeat_smoke status=pass repeats=3 clients=6 passed_runs=3 total_initial_chunks=18 total_fanout_updates=18 total_detail_clients=18 total_resource_samples=9 max_rss_kb=31120 max_cpu_pct=0.3 protocol_change=0
```

This is bounded repeated runtime evidence for fanout, per-client delivery detail, and resource sampling. It is not a soak test, throughput benchmark, admission sizing result, or production capacity claim.

## Live Admission Limit Smoke

`scripts/server_admission_limit_smoke.sh` builds and starts the Go server on an isolated local smoke port and temporary RocksDB path with `RUMPELMC_SERVER_MAX_CLIENTS=1`. It then runs `server/cmd/admission_limit_smoke`, which opens one holder client, verifies that client receives chunk `0,0`, opens a second TCP client, and requires that second client to observe a server-side close. The wrapper also requires server-log evidence of `admission_result=rejected`, `active_clients=1`, and `max_clients=1`.

Use:

```sh
sh scripts/server_admission_limit_smoke.sh logs/server_admission_limit_smoke_current
```

Expected summary:

```text
server_admission_limit_smoke status=pass max_clients=1 attempted_clients=2 admitted_clients=1 rejected_clients=1 holder_initial_chunk=1 rejected_close_observed=1 admission_rejection_log=1 protocol_change=0
```

This proves the opt-in cap works against a live TCP server. It is not production concurrency sizing, adaptive overload control, queue backpressure, or a load-test result.

## Connection Lifecycle Summary

`scripts/server_connection_lifecycle_summary.sh` parses one or more server log files and writes `server-connection-lifecycle-summary.txt` plus a TSV count file. It counts `Client connected`, `admission_result=rejected`, `Client disconnected`, `Failed to close client`, and `Failed to accept connection` events, then fails if close or accept failures are present.

The scalability gate runs this summary automatically when current smoke summaries expose `server_log=` paths. The current combined summary covers the two-client fanout, six-client fanout/load, and admission-limit server logs.

Expected summary:

```text
server_connection_lifecycle status=pass connected_clients=9 rejected_clients=1 disconnected_clients=9 close_failures=0 accept_failures=0 ...
```

This is log-summary evidence for connection cleanup visibility. It is not a reconnect policy, long-run leak detector, or production session metric pipeline.

## Scalability Gaps

Still needed before claiming full live multi-client scalability:

- Longer CPU/memory profiling under multiple active clients beyond the bounded RSS/CPU smoke sampling.
- Longer multi-client load evidence beyond the bounded repeated three-run smoke.
- Broader slow-client handling evidence under more clients and broadcast load; the networking robustness block now owns the bounded two-client slow-reader smoke.
- Longer disconnect cleanup counters or production metric summaries beyond the bounded smoke-log lifecycle parser.
- Load-tested max-client sizing for representative hardware and gameplay workloads beyond the bounded one-holder/one-rejected smoke.
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

For the fast default gate, the expected current result after collecting the broader live, repeated, and admission-limit artifacts is `status=pass`, `scalability_status=repeat_live_guarded`, `resource_profile_status=repeat_live_guarded`, `multi_client_sent_state=guarded`, `block_edit_fanout=interested_clients_guarded`, `slow_client_write_timeout=guarded`, `admission_policy=live_guarded`, `disconnect_cleanup_status=lifecycle_summary_guarded`, `active_protocol_change=0`, `live_load_status=pass`, `live_detail_status=pass`, `live_detail_clients=2`, `broader_live_load_status=pass`, `broader_live_clients>=6`, `broader_live_initial_chunks=broader_live_clients`, `broader_live_fanout_updates=broader_live_clients`, `broader_live_detail_status=pass`, `broader_live_detail_clients=broader_live_clients`, `broader_live_resource_samples>=1`, `broader_live_resource_rss_kb_max>0`, `repeat_smoke_status=pass`, `repeat_smoke_repeats=3`, `repeat_smoke_clients=6`, `repeat_smoke_initial_chunks=18`, `repeat_smoke_fanout_updates=18`, `repeat_smoke_detail_clients=18`, `repeat_smoke_resource_samples=9`, `admission_limit_smoke_status=pass`, `admission_limit_rejected_clients=1`, `connection_lifecycle_status=pass`, `connection_lifecycle_close_failures=0`, and `network_tests=pass`.

To run the live smoke inside the gate:

```sh
RUMPELMC_SERVER_SCALABILITY_RUN_LIVE_SMOKE=1 sh scripts/server_scalability_pass_gate.sh logs/server_scalability_pass_current
```

With the live smoke enabled, the expected result includes `live_load_status=pass`.

To run the broader live smoke inside the gate:

```sh
RUMPELMC_SERVER_SCALABILITY_RUN_BROADER_LIVE_SMOKE=1 sh scripts/server_scalability_pass_gate.sh logs/server_scalability_pass_current
```

With the broader smoke enabled, the expected result includes `broader_live_load_status=pass`.

To run the repeated multi-client smoke inside the gate:

```sh
RUMPELMC_SERVER_SCALABILITY_RUN_REPEAT_SMOKE=1 sh scripts/server_scalability_pass_gate.sh logs/server_scalability_pass_current
```

With the repeated smoke enabled, the expected result includes `scalability_status=repeat_live_guarded` and `repeat_smoke_status=pass`.

To run the live admission-limit smoke inside the gate:

```sh
RUMPELMC_SERVER_SCALABILITY_RUN_ADMISSION_LIMIT_SMOKE=1 sh scripts/server_scalability_pass_gate.sh logs/server_scalability_pass_current
```

With the admission-limit smoke enabled, the expected result includes `admission_policy=live_guarded` and `admission_limit_smoke_status=pass`.

The gate checks that:

- This document records current server behavior, added unit guards, live scalability gaps, and compatibility rules.
- `server.go` still has per-session `clientChunkStreamState`, connection close cleanup, block-edit fanout, and write deadlines.
- `server.go` still has the opt-in max-client admission cap and rejected-connection log marker.
- The live smoke script exists and records `server_multi_client_smoke status=pass`.
- The live smoke script records per-client detail fields in its summary.
- The live smoke script records server resource sample fields in its summary.
- The admission-limit smoke script exists and records `server_admission_limit_smoke status=pass`.
- The repeated multi-client smoke script exists and records `server_multi_client_repeat_smoke status=pass`.
- The broader live smoke summary is consumed when present, or generated when `RUMPELMC_SERVER_SCALABILITY_RUN_BROADER_LIVE_SMOKE=1`.
- The repeated multi-client smoke summary is consumed when present, or generated when `RUMPELMC_SERVER_SCALABILITY_RUN_REPEAT_SMOKE=1`.
- The admission-limit smoke summary is consumed when present, or generated when `RUMPELMC_SERVER_SCALABILITY_RUN_ADMISSION_LIMIT_SMOKE=1`.
- The connection lifecycle summary script exists and records connected/rejected/disconnected counts with zero close and accept failures.
- The multi-client sent-state, interested-client fanout, failed-broadcast cleanup, write-deadline, and max-client admission tests exist.
- `api/schema/packets.proto` is unchanged.
- Focused network tests pass.

## Current Status

This block is complete as a unit-guard/checkpoint block with bounded live two-client and six-client fanout/resource/detail smokes, a bounded repeated six-client smoke, a bounded live opt-in max-client admission smoke, and a bounded connection lifecycle log summary. Longer CPU/memory profiling, broad slow-reader/load harnesses, load-tested admission sizing, adaptive overload policy, and production disconnect metrics remain future work.
