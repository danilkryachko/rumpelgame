# Tooling And Debug Overlay

Block 43, Tooling And Debug Overlay, surfaces the current streaming, render, collision, GPU, storage, dirty-update, and lifecycle signals through the in-client dev overlay.

## Technical Brief

User request:

Continue the annual world streaming architecture plan in order, use MCP/OntoIndex context, and move to the next block if a local blocker cannot be bypassed.

Goal:

Make runtime state visible in the client without requiring agents to parse the full `get_perf_text` dump on screen.

Context inspected:

- OntoIndex concept search for debug overlay, streaming/render/collision/GPU/storage metrics, Rust getters, and HUD wiring.
- `client/hud.gd` dev panel, perf log writer, and existing texture debug controls.
- `client/rust_ext/src/lib.rs` `GameClient` debug getters, perf counters, lifecycle state, dirty update counters, GPU stats, and storage event text.
- `docs/DIRTY_UPDATE_SCALABILITY.md`.

Scope:

- Add a compact Rust getter for the overlay text.
- Wire the existing HUD dev panel to the compact overlay text.
- Keep the full perf dump in `logs/perf.log` for scripts and detailed diagnosis.
- Add a narrow guard for lifecycle labels used by the overlay.

Out of scope:

- No new Godot scenes, resources, imports, panels, hotkeys, protocol fields, storage schema, world generation, renderer policy, draw-distance change, visual-quality reduction, or new dependency.

Assumptions:

- The `I` dev menu remains the existing overlay entry point.
- `get_perf_text` remains the canonical full diagnostic stream for scripts.
- The overlay may report storage through the latest save/update event until a richer server acknowledgement or storage telemetry path exists.

Done when:

- The HUD shows a compact multiline overlay when the dev menu is open.
- The perf log records both compact overlay text and the full perf dump.
- A gate verifies source wiring, no protocol diff, no Godot scene/resource diff, and a focused Rust overlay-related test.

Checks:

- `sh scripts/tooling_debug_overlay_gate.sh logs/tooling_debug_overlay_current`

## Runtime Overlay Contract

`GameClient.get_debug_overlay_text()` now returns these sections:

- `State`: client lifecycle state, using stable labels for connecting, waiting_chunks, spawning, active, reconnecting, and shutdown.
- `Streaming`: loaded chunk count, current chunk coordinate, current chunk loaded flag, mesh queue depth/max, and packet drain last/max.
- `Render/GPU`: rendered submesh count, current chunk rendered submesh count, GPU subchunks, draws, faces, upload failures, active bytes, and fragmentation.
- `Collision`: total and current collision bodies plus collision refresh queue and last refresh work.
- `Dirty/storage`: dirty chunk/block counters, last dirty scope, partial/saved subchunk counters, dirty bounds/edges, and latest save event.
- `Events`: latest chunk event and latest block action.

This is intentionally a compact screen summary, not a replacement for the full perf stream.

## HUD Wiring

`client/hud.gd` keeps the existing `I` dev panel. The panel now calls `get_debug_overlay_text()` and falls back to existing chunk/perf/event getters if the Rust extension is older or unavailable.

The hotbar, FPS counter, texture debug stand hotkey, and dev log behavior are unchanged.

## Perf Log Policy

`write_perf_log_sample()` now writes:

- `overlay="..."` with compact multiline text collapsed to ` | `.
- `perf="..."` with the full legacy `get_perf_text` output.

Existing scripts that parse `perf=` should continue to work. New tooling can prefer `overlay=` for fast human-readable triage.

## Deferred Work

Still needed:

- Runtime screenshot capture with the dev panel open on representative movement and block-edit smokes.
- A server-side storage acknowledgement or save latency metric instead of the current last-save event proxy.
- User-facing toggle/preset if the debug panel becomes too dense.
- Optional external profiler correlation between overlay `Render/GPU` fields and captured GPU timings.

## Compatibility Rules

- Keep `get_perf_text` output available and script-compatible.
- Do not add protocol or storage fields for overlay-only work.
- Do not create or reformat Godot scene/resource/import files for this checkpoint.
- Do not make overlay visibility affect rendering, collision, world generation, chunk serialization, storage, or network behavior.
- Do not treat overlay presence as runtime performance evidence; it is tooling visibility only.

## Block 43 Gate

Use:

```sh
sh scripts/tooling_debug_overlay_gate.sh logs/tooling_debug_overlay_current
```

The expected current result is `status=pass`, `overlay_status=runtime_wired`, `hud_overlay=compact`, `perf_log_full=preserved`, `active_protocol_change=0`, and `active_scene_resource_change=0`.

The gate checks that:

- This document records the overlay contract, HUD wiring, perf log policy, deferred work, and compatibility rules.
- The Rust client exposes `get_debug_overlay_text()`.
- The HUD uses the compact overlay and preserves full perf logging.
- Lifecycle labels used by the overlay are unit-guarded.
- Protocol schema/generated files and Godot scene/resource/import files are unchanged.
- Previous dirty update scalability evidence remains clean.

## Current Status

This block is complete as a runtime-wired debug overlay checkpoint. Heavy visual capture with the dev panel open and richer storage acknowledgements remain future work.
