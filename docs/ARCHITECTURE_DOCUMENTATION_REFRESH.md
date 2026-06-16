# Architecture Documentation Refresh

Block 46, Architecture Documentation Refresh, updates the top-level architecture description after the streaming, GPU, storage, protocol, observability, and handoff checkpoints.

## Technical Brief

User request:

Continue the annual world streaming architecture plan in order, use MCP/OntoIndex context, and move to the next block if a local blocker cannot be bypassed.

Goal:

Refresh architecture docs to match the actual current code and evidence chain before security/data-integrity and release-candidate gates.

Context inspected:

- OntoIndex concept search for server startup, RocksDB store, world creation, networking, RLE chunk send, client Rust GDExtension, and GPU terrain docs.
- `docs/ARCHITECTURE.md`.
- `docs/PROTOCOL.md`.
- `docs/STORAGE.md`.
- `docs/GPU_SHADOW_PATH.md`.
- `docs/GPU_TRANSPARENT_PATH.md`.
- `docs/WORLD_STREAMING.md`.
- `docs/AUTOMATED_HANDOFF_DISCIPLINE.md`.

Scope:

- Refresh `docs/ARCHITECTURE.md` with current stack, runtime flow, world/storage, protocol, client Rust, GPU terrain, observability, and guardrails.
- Add a gate that checks the refreshed architecture sections and related docs.
- Keep this block documentation-only.

Out of scope:

- No runtime behavior changes, no protocol changes, no storage migrations, no shader changes, no Godot scene/resource changes, no generated-file edits, and no new dependency.

Assumptions:

- `docs/ARCHITECTURE.md` is the high-level map; detailed behavior stays in focused docs such as `docs/PROTOCOL.md`, `docs/STORAGE.md`, `docs/WORLD_STREAMING.md`, and GPU path docs.
- Future architecture updates should preserve links to the active gates and not duplicate every metric.

Done when:

- `docs/ARCHITECTURE.md` reflects the current actual architecture at a high level.
- The architecture refresh gate passes.

Checks:

- `sh scripts/architecture_documentation_refresh_gate.sh logs/architecture_documentation_refresh_current`

## Refreshed Areas

`docs/ARCHITECTURE.md` now covers:

- Stack ownership across Godot, Rust GDExtension, Go server, RocksDB, and protobuf/TCP.
- Current startup and chunk streaming flow.
- Server world/storage responsibilities.
- Protocol compatibility contract.
- Client Rust lifecycle, packet queue, dirty update, and gameplay roles.
- GPU terrain, CPU proxy, native-shadow, and transparent-terrain current status.
- Observability and handoff surfaces.
- Guardrails for generated files, storage engines, determinism, Godot resources, and checks.

## Deferred Work

Still needed:

- Architecture diagram once the 50-block pass reaches production readiness.
- A separate server scalability architecture note after live multi-client profiling exists.
- A dedicated protocol-delta architecture section if chunk delta packets become active.
- Architecture update for transparent or native-shadow paths only after their runtime implementation gates flip active.

## Compatibility Rules

- Keep high-level architecture docs factual and current.
- Do not use architecture refresh as permission to change runtime behavior.
- Do not duplicate protocol field definitions outside `docs/PROTOCOL.md` in a way that can drift.
- Do not document planned paths as active unless their gate reports active runtime evidence.

## Block 46 Gate

Use:

```sh
sh scripts/architecture_documentation_refresh_gate.sh logs/architecture_documentation_refresh_current
```

The expected current result is `status=pass`, `architecture_status=refreshed`, `runtime_change=none`, `handoff_status=pass`, and `handoff_gpu_report_freshness=guarded`.

The gate checks that:

- `docs/ARCHITECTURE.md` has the required current sections.
- Related protocol, storage, GPU, observability, and handoff docs are present.
- Planned native-shadow and transparent paths are documented as inactive/deferred.
- The Block 45 handoff automation summary is clean.
- The handoff automation summary carries guarded aggregate GPU terrain report freshness from observability.

## Current Status

This block is complete as a documentation refresh checkpoint. Runtime behavior remains governed by the focused implementation and evidence gates.
