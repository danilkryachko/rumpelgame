# Client State Machine Hardening

Block 39, Client State Machine Hardening, makes the current client lifecycle states explicit and testable without changing chunk streaming, packet schema, or reconnect behavior.

## Technical Brief

User request:

Continue the annual world streaming architecture plan in order and use MCP/OntoIndex context.

Goal:

Define and check the client states `connecting`, `waiting_chunks`, `spawning`, `active`, `reconnecting`, and `shutdown` so future reconnect and error-handling work has a narrow contract.

Context inspected:

- OntoIndex concept search for client state machine hardening, startup readiness, packet reader, chunk loading, player spawn, reconnect, and shutdown.
- `client/rust_ext/src/lib.rs` `GameClient.ready`, packet drain, startup chunk path, player spawn, send path, and shutdown cleanup.
- `client/rust_ext/src/network.rs` packet receive/send behavior.
- `docs/PROTOCOL.md`.
- `docs/NETWORKING_ROBUSTNESS_PROGRAM.md`.

Scope:

- Add a small `ClientLifecycleState` enum and pure transition function.
- Wire the model to current connect success/failure, startup chunk, player spawn, send error, and shutdown cleanup events.
- Add focused Rust unit tests for the allowed happy path, reconnect path, shutdown terminal behavior, and out-of-order startup events.

Out of scope:

- No automatic reconnect loop, retry backoff, server restart recovery, packet replay, packet queue policy, state telemetry field, Godot scene change, protocol change, storage change, worldgen change, or streaming scheduler change.

Assumptions:

- The current runtime already behaves like `connecting -> waiting_chunks -> spawning -> active` on a successful first chunk.
- Connection setup failures and send failures should be modeled as `reconnecting`, but active reconnect execution remains future work.
- Shutdown cleanup should be terminal for this model.
- The packet reader thread cannot yet emit lifecycle events back to `GameClient` without a broader channel/event design.

Done when:

- The client lifecycle model names the required states and guards legal transitions with unit tests.
- A state-machine hardening gate runs the focused Rust tests and records reconnect execution as deferred.

Checks:

- `sh scripts/client_state_machine_hardening_gate.sh logs/client_state_machine_hardening_current`

## State Contract

- `connecting`: `GameClient.ready` is initializing resources and opening the TCP connection.
- `waiting_chunks`: connection setup succeeded, the initial position packet was sent, and the client is waiting for the first startup chunk.
- `spawning`: the startup chunk reached collision-ready handling and the player spawn path is executing.
- `active`: the player has spawned and normal movement/block-edit packet flow is allowed.
- `reconnecting`: connection setup or packet send failed. The state exists as a contract, but no retry loop is active yet.
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
- `ShutdownRequested` is recorded before runtime resources are released.

## Deferred Work

Still needed before claiming a complete client state machine:

- Reader-thread network errors must be delivered to the main thread as lifecycle events.
- Reconnect execution needs backoff, state reset rules, stale packet handling, and rebootstrap tests.
- `reconnecting` must define what happens to loaded chunks, mesh queues, collision queues, and player input.
- State telemetry can be added to perf markers only after the semantics are stable.
- Visual/runtime smoke should prove startup, shutdown, and future reconnect transitions.

## Compatibility Rules

- Do not change packet schema or framing for client state tracking.
- Do not move player spawn earlier than collision-ready startup handling.
- Do not send movement/block-edit packets while the model is `connecting`, `waiting_chunks`, `spawning`, `reconnecting`, or `shutdown` without an explicit gameplay/networking task.
- Do not implement reconnect by clearing loaded chunk or GPU state until stale-state rules are defined.
- Do not change Godot scene/resource/import files for this checkpoint.

## Block 39 Gate

Use:

```sh
sh scripts/client_state_machine_hardening_gate.sh logs/client_state_machine_hardening_current
```

The expected current result is `status=pass`, `state_machine_status=unit_guarded`, `runtime_reconnect=deferred`, `state_telemetry=deferred`, `client_lifecycle_tests=pass`, and `active_protocol_change=0`.

The gate checks that:

- This document records state contract, transition contract, runtime wiring, deferred work, and compatibility rules.
- The Rust client source contains the lifecycle states, event enum, transition function, runtime event wiring, and focused tests.
- The previous networking robustness gate is clean.
- Focused Rust lifecycle tests pass.
- Protocol schema/generated files are unchanged.

## Current Status

This block is complete as a unit-guarded state model. Runtime reconnect execution, reader-thread error propagation, and state telemetry remain future work.
