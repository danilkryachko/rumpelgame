# Client State Machine Hardening

Block 39, Client State Machine Hardening, makes the current client lifecycle states explicit and testable without changing chunk streaming or packet schema.

## Technical Brief

User request:

Continue the annual world streaming architecture plan in order and use MCP/OntoIndex context.

Goal:

Define and check the client states `connecting`, `waiting_chunks`, `spawning`, `active`, `reconnecting`, and `shutdown`, then guard a minimal disconnect -> reconnect -> rebootstrap -> active path.

Context inspected:

- OntoIndex concept search for client state machine hardening, startup readiness, packet reader, chunk loading, player spawn, reconnect, and shutdown.
- `client/rust_ext/src/lib.rs` `GameClient.ready`, packet drain, startup chunk path, player spawn, send path, and shutdown cleanup.
- `client/rust_ext/src/network.rs` packet receive/send behavior.
- `scripts/client_reconnect_smoke.sh` live disconnect/rebootstrap marker smoke.
- `docs/PROTOCOL.md`.
- `docs/NETWORKING_ROBUSTNESS_PROGRAM.md`.

Scope:

- Add a small `ClientLifecycleState` enum and pure transition function.
- Wire the model to current connect success/failure, startup chunk, player spawn, send error, and shutdown cleanup events.
- Deliver reader-thread network errors to the main thread as lifecycle events.
- Add perf-marker state telemetry for runtime reconnect smoke evidence.
- Add a minimal retry loop with bounded retry cadence that resends the current player position as the bootstrap request after reconnect.
- Add a live smoke that starts the server, lets the client reach active startup, kills the server, restarts it, and requires the client to return to `client_state=active`.
- Add focused Rust unit tests for the allowed happy path, reconnect path, shutdown terminal behavior, and out-of-order startup events.

Out of scope:

- No packet replay, stale packet reconciliation, broad queue reset policy, Godot scene change, protocol change, storage change, worldgen change, or streaming scheduler change.

Assumptions:

- The current runtime already behaves like `connecting -> waiting_chunks -> spawning -> active` on a successful first chunk.
- Connection setup failures, send failures, and reader-thread network errors should be modeled as `reconnecting`.
- Shutdown cleanup should be terminal for this model.
- This checkpoint detects disconnects, blocks normal outbound gameplay/movement packets while `reconnecting`, and uses the reconnect bootstrap position send as the only outbound packet during recovery.

Done when:

- The client lifecycle model names the required states and guards legal transitions with unit tests.
- A state-machine hardening gate runs the focused Rust tests, requires the bounded live reconnect smoke and repeated reconnect soak evidence, and records state telemetry.

Checks:

- `sh scripts/client_state_machine_hardening_gate.sh logs/client_state_machine_hardening_current`

## State Contract

- `connecting`: `GameClient.ready` is initializing resources and opening the TCP connection.
- `waiting_chunks`: connection setup succeeded, the initial position packet was sent, and the client is waiting for the first startup chunk.
- `spawning`: the startup chunk reached collision-ready handling and the player spawn path is executing.
- `active`: the player has spawned and normal movement/block-edit packet flow is allowed.
- `reconnecting`: connection setup, packet send, or reader-thread receive failed. A minimal retry loop attempts to reconnect and rebootstrap with the current or initial player position.
- `shutdown`: `exit_tree` or `shutdown_for_quit` requested cleanup; runtime resources are being released and the model is terminal.

## Transition Contract

Allowed transitions:

- `connecting + connect_succeeded -> waiting_chunks`
- `connecting + connect_failed -> reconnecting`
- `waiting_chunks + startup_chunk_ready -> spawning`
- `waiting_chunks + network_error -> reconnecting`
- `spawning + spawn_complete -> active`
- `spawning + network_error -> reconnecting`
- `active + network_error -> reconnecting`
- `reconnecting + connect_succeeded -> waiting_chunks`
- `reconnecting + connect_failed -> reconnecting`
- `any_state + shutdown_requested -> shutdown`

Out-of-order startup events remain invalid. For example, `startup_chunk_ready` cannot move a client directly out of `connecting`, and `spawn_complete` cannot move a client directly out of `waiting_chunks`.

## Current Runtime Wiring

- `ConnectSucceeded` is recorded after the stream clone, packet receiver, and `network` handle are installed.
- `ConnectFailed` is recorded for connection, initial-position send, and TCP stream clone failures during startup.
- `StartupChunkReady` is recorded after the first startup chunk has a collision-ready startup marker.
- `SpawnComplete` is recorded when `spawn_player` marks `player_spawned = true`.
- `NetworkError` is recorded when a synchronous packet send through the retained client stream fails.
- Reader-thread receive errors are sent to the main thread through `NetworkReaderEvent::Error`, then recorded as `NetworkError`.
- Outbound movement/block-edit packets are allowed only while the lifecycle state is `active`.
- Automatic retry/backoff uses a short bounded timer while `reconnecting`; a successful reconnect sends the current player position, waits for the startup chunk, and returns to `active` through `StartupChunkReady` and `SpawnComplete`.
- `ShutdownRequested` is recorded before runtime resources are released.

## State Telemetry

`GameClient.get_perf_text()` now reports:

- `client_state`
- `lifecycle_transitions`
- `reconnect_events`
- `reconnect_attempts`
- `reconnect_successes`
- `network_reader_errors`
- `last_network_error`

These are marker-only diagnostics. They do not change packet schema, server behavior, chunk streaming order, loaded chunk retention, or GPU state.

## Live Reconnect Smoke

`scripts/client_reconnect_smoke.sh` builds and starts the Go server on the normal local client port, starts a Godot visual smoke, kills the server, restarts it before capture, and requires the marker to report:

- `client_state=active`
- `reconnect_events>=1`
- `reconnect_attempts>=1`
- `reconnect_successes>=1`
- `network_reader_errors>=1`
- `current_chunk_loaded=1`

Use:

```sh
RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE=1 RUMPELMC_GODOT_RUST_EXT_PROFILE=release sh scripts/client_reconnect_smoke.sh logs/client_reconnect_smoke_current
```

This validates runtime disconnect detection, retry, server restart recovery, rebootstrap chunk delivery, and marker telemetry. It is not a stale-packet, packet replay, queue reset, overload, or backpressure proof.

## Repeated Reconnect Soak

`scripts/client_reconnect_soak.sh` runs `scripts/client_reconnect_smoke.sh` with multiple server kill/restart cycles in one Godot session. The default is three reconnect cycles.

Use:

```sh
RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE=1 RUMPELMC_GODOT_RUST_EXT_PROFILE=release sh scripts/client_reconnect_soak.sh logs/client_reconnect_soak_current
```

The soak requires `client_state=active`, `reconnect_successes>=reconnect_cycles`, `network_reader_errors>=reconnect_cycles`, `current_chunk_loaded>=1`, and `active_protocol_change=0`. This is still bounded smoke evidence, not a long-run network soak, packet replay proof, or broader state-reset proof.

## Session/Stale Packet Policy

Network reader events now carry a monotonically increasing `network_session_id`. A successful connect/reconnect increments the session id before installing the new packet receiver, and the reader thread attaches that id to every packet or error event.

The main-thread drain applies a strict session policy:

- Events from non-current sessions are counted as stale and ignored.
- If the current session reports a reader error in the same drain batch as queued packets, those packets are counted as stale and are not applied.
- Only the current session's reader error is allowed to move the lifecycle to `reconnecting`.
- The policy is marker-observable through `network_session`, `network_stale_events`, `network_stale_packets`, and `network_stale_errors`.

This is a queue-boundary guard. It does not replay packets, clear loaded chunks, clear GPU residency, or define broader reconnect state reset rules.

## Deferred Work

Still needed before claiming a complete client state machine:

- Broader state reset rules for loaded chunks, mesh queues, collision queues, and GPU residency remain deferred.
- Longer runtime smokes should cover reconnect failures and longer idle/play windows beyond the current bounded repeated reconnect soak.

## Compatibility Rules

- Do not change packet schema or framing for client state tracking.
- Do not move player spawn earlier than collision-ready startup handling.
- Do not send movement/block-edit packets while the model is `connecting`, `waiting_chunks`, `spawning`, `reconnecting`, or `shutdown`.
- Do not clear loaded chunk or GPU state on reconnect until stale-state rules are defined.
- Do not change Godot scene/resource/import files for this checkpoint.

## Block 39 Gate

Use:

```sh
sh scripts/client_state_machine_hardening_gate.sh logs/client_state_machine_hardening_current
```

The expected current result after collecting the live artifacts is `status=pass`, `state_machine_status=repeated_runtime_guarded`, `runtime_reconnect=repeated_live_rebootstrap_guarded`, `state_telemetry=live_marker_guarded`, `stale_packet_policy=session_guarded`, `reconnect_smoke_status=pass`, `reconnect_smoke_client_state=active`, `reconnect_soak_status=pass`, `reconnect_soak_cycles>=3`, `reconnect_soak_successes>=reconnect_soak_cycles`, `client_lifecycle_tests=pass`, and `active_protocol_change=0`.

The gate checks that:

- This document records state contract, transition contract, runtime wiring, deferred work, and compatibility rules.
- The Rust client source contains the lifecycle states, event enum, transition function, runtime event wiring, and focused tests.
- The Rust client source carries reader-thread error events to the main thread and exports marker state telemetry.
- The Rust client source carries session ids on reader events, ignores stale-session events, and unit-guards same-drain packet reset after a current-session error.
- The reconnect smoke script exists, and the gate requires a clean current reconnect summary or a successful explicit smoke run.
- The repeated reconnect soak script exists, and the gate requires a clean current soak summary or a successful explicit soak run.
- The previous networking robustness gate is clean.
- Focused Rust lifecycle tests pass.
- Protocol schema/generated files are unchanged.

## Current Status

This block is complete as a unit-guarded state model plus bounded repeated live disconnect/restart/rebootstrap-to-`active` proof. Reader-event stale-session handling and same-drain packet reset are unit-guarded. Broader loaded-state reset, reconnect failure soak, overload handling, and backpressure remain future work.
