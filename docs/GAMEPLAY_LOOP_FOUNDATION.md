# Gameplay Loop Foundation

Block 40, Gameplay Loop Foundation, records the first minimal gameplay loop checkpoint after the streaming/client lifecycle hardening work.

## Technical Brief

User request:

Continue the annual world streaming architecture plan in order and use MCP/OntoIndex context.

Goal:

Keep the existing mining/building loop stable, confirm that block edits still flow through persistence-capable server state, and add a small client inventory foundation without changing protocol or storage formats.

Context inspected:

- OntoIndex concept search for gameplay loop foundation, mining, building, persistence, inventory, block edits, storage, dirty chunks, and tests.
- `client/rust_ext/src/player.rs` block raycast, mining/building signals, hotbar selection, and player input.
- `client/rust_ext/src/lib.rs` block action send path and client lifecycle model.
- `server/pkg/network/server.go` `BlockAction` handling.
- `server/pkg/world/world.go` `SetBlockGlobal` and `ChunkStore` save path.
- `docs/STORAGE_PERSISTENCE_FOUNDATION.md`.
- `docs/NETWORKING_ROBUSTNESS_PROGRAM.md`.
- `docs/CLIENT_STATE_MACHINE_HARDENING.md`.

Scope:

- Add a local hotbar inventory model with slot counts and placeability validation.
- Keep the current creative five-slot hotbar behavior over existing placeable block IDs.
- Guard inventory slot rules with Rust unit tests.
- Define the minimum mining/building persistence contract before the dedicated Block Edit Persistence Track.

Out of scope:

- No inventory protocol, server-authoritative inventory, item stack persistence, crafting, drops, tools, durability, survival rules, new block IDs, new packet fields, new storage records, dirty chunk scheduler, visual smoke rewrite, or Godot scene/resource/import change.

Assumptions:

- Mining and building remain client input actions that emit `block_broken` and `block_placed` signals.
- Server `BlockAction` remains the only networked edit command.
- Server `World.SetBlockGlobal` is the persistence-capable edit boundary because it calls `ChunkStore.SaveChunk` when a store is configured.
- The current hotbar is creative-mode inventory, so counts are guard data and are not decremented by placement yet.
- Full edit persistence verification belongs to Block 41.

Done when:

- The player hotbar has an explicit inventory slot model and tests.
- A gameplay foundation gate checks the client inventory tests and the existing server edit/persistence path.

Checks:

- `sh scripts/gameplay_loop_foundation_gate.sh logs/gameplay_loop_foundation_current`

## Current Mining And Building Loop

- `Player` raycasts from the camera to identify a target block and adjacent placement block.
- Left click emits `block_broken(x, y, z)`.
- Right click checks player intersection and inventory placeability, then emits `block_placed(x, y, z, block_id)`.
- `GameClient.on_block_broken` sends `BlockAction_DESTROY`.
- `GameClient.on_block_placed` validates client block placeability and sends `BlockAction_PLACE`.
- Server `handleClientPacketWithState` validates placeable block IDs before applying `PLACE`.
- Server `World.SetBlockGlobal` rejects out-of-height `Y` coordinates before updating or saving a chunk, then updates the in-memory chunk and calls `ChunkStore.SaveChunk` when a store is configured.
- Server sends the updated chunk snapshot back to the editing client, which drives visual, collision, and GPU dirty update handling through the normal `update_chunk` path.

## Inventory Foundation

The client now has a local creative hotbar inventory model:

- `InventorySlot { block_id, count }`
- `PLAYER_HOTBAR_SLOTS = 5`
- `CREATIVE_HOTBAR_STACK_COUNT = 999`
- `initial_hotbar_inventory()` derives slots from `blocks::PLACEABLE_BLOCKS`
- `inventory_slot_can_place()` requires positive count and a placeable block ID
- `inventory_has_placeable_block()` gates right-click placement
- `hotbar_key_for_slot()` keeps key mapping bounded to slots `1..5`

This is intentionally client-local and behavior-preserving for the existing hotbar. It gives future survival/server-inventory work a small seam without adding protocol or persistence fields now.

## Persistence Boundary

The gameplay foundation relies on the existing server boundary:

- `BlockAction_PLACE` and `BlockAction_DESTROY` both flow through `World.SetBlockGlobal`.
- `World.SetBlockGlobal` persists the edited chunk only when `World` was created with a `ChunkStore`.
- `World.SetBlockGlobal` rejects block edits outside `[0, ChunkHeight)` before creating/loading a chunk or returning an updated snapshot.
- `server/cmd/server/main.go` creates the default server with `storage.OpenRocksChunkStore`, so normal server runs are persistence-capable.
- Block 40 does not own save -> process restart -> reload -> visual/collision/GPU update proof. That evidence is collected by Block 41.

## Deferred Work

Still needed before calling gameplay production-ready:

- Server-authoritative inventory and item stack persistence.
- Inventory packet/schema design and compatibility tests.
- Tool/durability/mining-time rules.
- Drops and pickup flow.
- Edit broadcast/fanout to other clients.
- Broader dirty chunk save/reload coverage beyond the Block 41 persisted visual smoke.
- Mass edit, chunk edge, collision, and GPU dirty scalability from Block 42.

## Compatibility Rules

- Do not add inventory fields to `api/schema/packets.proto` in this checkpoint.
- Do not add storage records for item stacks without a storage migration task.
- Do not bypass `World.SetBlockGlobal` for persistent block edits.
- Do not allow client-only block IDs through `BlockAction`.
- Do not decrement creative hotbar counts until server-authoritative inventory exists.
- Do not change world generation or chunk serialization for gameplay foundation work.

## Block 40 Gate

Use:

```sh
sh scripts/gameplay_loop_foundation_gate.sh logs/gameplay_loop_foundation_current
```

The expected current result is `status=pass`, `gameplay_loop_status=foundation_guarded`, `inventory_foundation=unit_guarded`, `server_edit_persistence=store_save_boundary`, and `active_protocol_change=0`. If the Block 41 persisted visual summary is present, the gate also reports `full_reload_persistence=block_41_visual_guarded`; otherwise it remains `full_reload_persistence=deferred`.

The gate checks that:

- This document records mining/building flow, inventory foundation, persistence boundary, deferred work, and compatibility rules.
- The player source contains the hotbar inventory model and tests.
- Server block edits still flow through `World.SetBlockGlobal`.
- `World.SetBlockGlobal` still calls `ChunkStore.SaveChunk`.
- Previous client state-machine hardening is clean.
- Focused Rust inventory tests and Go world/network/storage tests pass.
- Protocol schema/generated files are unchanged.

## Current Status

This block is complete as a gameplay foundation checkpoint. Full dirty chunk save/reload and visual/collision/GPU proof is owned by Block 41, with broader gameplay systems still deferred.
