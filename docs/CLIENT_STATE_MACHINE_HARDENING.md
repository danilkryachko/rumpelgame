# Client State Machine Hardening

Block 39, Client State Machine Hardening, makes the current client lifecycle states explicit and testable without changing chunk streaming or packet schema.

## Technical Brief

User request:

Continue the annual world streaming architecture plan in order and use MCP/OntoIndex context.

Goal:

Define and check the client states `connecting`, `waiting_chunks`, `spawning`, `active`, `reconnecting`, and `shutdown`, then guard the first runtime disconnect transition into `reconnecting`.

Context inspected:

- OntoIndex concept search for client state machine hardening, startup readiness, packet reader, chunk loading, player spawn, reconnect, and shutdown.
- `client/rust_ext/src/lib.rs` `GameClient.ready`, packet drain, startup chunk path, player spawn, send path, and shutdown cleanup.
- `client/rust_ext/src/network.rs` packet receive/send behavior.
- `scripts/client_reconnect_smoke.sh` live disconnect marker smoke.
- `docs/PROTOCOL.md`.
- `docs/NETWORKING_ROBUSTNESS_PROGRAM.md`.

Scope:

- Add a small `ClientLifecycleState` enum and pure transition function.
- Wire the model to current connect success/failure, startup chunk, player spawn, send error, and shutdown cleanup events.
- Deliver reader-thread network errors to the main thread as lifecycle events.
- Add perf-marker state telemetry for runtime reconnect smoke evidence.
- Add a live smoke that starts the server, lets the client reach active startup, kills the server, and requires `client_state=reconnecting`.
- Add focused Rust unit tests for the allowed happy path, reconnect path, shutdown terminal behavior, and out-of-order startup events.

Out of scope:

- No automatic retry loop, retry backoff, server restart recovery, packet replay, packet queue policy beyond reader-error delivery, Godot scene change, protocol change, storage change, worldgen change, or streaming scheduler change.

Assumptions:

- The current runtime already behaves like `connecting -> waiting_chunks -> spawning -> active` on a successful first chunk.
- Connection setup failures, send failures, and reader-thread network errors should be modeled as `reconnecting`.
- Shutdown cleanup should be terminal for this model.
- This checkpoint detects disconnects and blocks further outbound gameplay/movement packets while `reconnecting`; active retry/rebootstrap remains future work.

Done when:

- The client lifecycle model names the required states and guards legal transitions with unit tests.
- A state-machine hardening gate runs the focused Rust tests, can run or consume the live reconnect smoke, and records state telemetry.

Checks:

- `sh scripts/client_state_machine_hardening_gate.sh logs/client_state_machine_hardening_current`

## State Contract

- `connecting`: `GameClient.ready` is initializing resources and opening the TCP connection.
- `waiting_chunks`: connection setup succeeded, the initial position packet was sent, and the client is waiting for the first startup chunk.
- `spawning`: the startup chunk reached collision-ready handling and the player spawn path is executing.
- `active`: the player has spawned and normal movement/block-edit packet flow is allowed.
- `reconnecting`: connection setup, packet send, or reader-thread receive failed. No retry loop is active yet.
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
- `ShutdownRequested` is recorded before runtime resources are released.

## State Telemetry

`GameClient.get_perf_text()` now reports:

- `client_state`
- `lifecycle_transitions`
- `reconnect_events`
- `network_reader_errors`
- `last_network_error`

These are marker-only diagnostics. They do not change packet schema, server behavior, chunk streaming order, loaded chunk retention, or GPU state.

## Live Reconnect Smoke

`scripts/client_reconnect_smoke.sh` builds and starts the Go server on the normal local client port, starts a Godot visual smoke, kills the server before capture, and requires the marker to report:

- `client_state=reconnecting`
- `reconnect_events>=1`
- `network_reader_errors>=1`
- `current_chunk_loaded=1`

Use:

```sh
RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE=1 RUMPELMC_GODOT_RUST_EXT_PROFILE=release sh scripts/client_reconnect_smoke.sh logs/client_reconnect_smoke_current
```

This validates runtime disconnect detection and telemetry. It is not a reconnect retry, rebootstrap, stale-packet, or server-restart recovery proof.

## Deferred Work

Still needed before claiming a complete client state machine:

- Reconnect execution needs backoff, state reset rules, stale packet handling, and rebootstrap tests.
- `reconnecting` must define what happens to loaded chunks, mesh queues, collision queues, and player input.
- Visual/runtime smoke should prove future retry/rebootstrap transitions after policy is defined.

## Compatibility Rules

- Do not change packet schema or framing for client state tracking.
- Do not move player spawn earlier than collision-ready startup handling.
- Do not send movement/block-edit packets while the model is `connecting`, `waiting_chunks`, `spawning`, `reconnecting`, or `shutdown`.
- Do not implement reconnect by clearing loaded chunk or GPU state until stale-state rules are defined.
- Do not change Godot scene/resource/import files for this checkpoint.

## Block 39 Gate

Use:

```sh
sh scripts/client_state_machine_hardening_gate.sh logs/client_state_machine_hardening_current
```

The expected current result after collecting the live artifact is `status=pass`, `state_machine_status=runtime_guarded`, `runtime_reconnect=live_disconnect_guarded`, `state_telemetry=live_marker_guarded`, `reconnect_smoke_status=pass`, `reconnect_smoke_client_state=reconnecting`, `client_lifecycle_tests=pass`, and `active_protocol_change=0`.

The gate checks that:

- This document records state contract, transition contract, runtime wiring, deferred work, and compatibility rules.
- The Rust client source contains the lifecycle states, event enum, transition function, runtime event wiring, and focused tests.
- The Rust client source carries reader-thread error events to the main thread and exports marker state telemetry.
- The reconnect smoke script exists, and the gate carries its status when a current reconnect summary exists or the smoke is explicitly run.
- The previous networking robustness gate is clean.
- Focused Rust lifecycle tests pass.
- Protocol schema/generated files are unchanged.

## Current Status

This block is complete as a unit-guarded state model plus live disconnect-to-`reconnecting` telemetry proof. Automatic retry/backoff, stale packet handling, and rebootstrap recovery remain future work.
