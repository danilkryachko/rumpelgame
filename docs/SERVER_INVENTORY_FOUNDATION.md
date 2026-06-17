# Server Inventory Foundation

This document records the server-owned inventory checkpoint for the gameplay track.

## Technical Brief

Goal:

Move block placement validation from block-registry-only checks to a session-owned inventory boundary, then persist local-player inventory state through the approved RocksDB store while preserving current creative gameplay behavior and chunk storage compatibility.

Scope:

- Add `server/pkg/inventory` as the authoritative domain model for placeable block stacks.
- Give each `clientSession` a server-owned creative hotbar inventory.
- Add an explicit server inventory mode switch for finite counted hotbar sessions.
- Keep `BlockAction PLACE` on the existing packet shape and require the session inventory before applying the edit.
- Keep selected hotbar slot state on the server session and validate selected-slot actions against the session inventory.
- Load and save local-player inventory slots plus selected slot when a client sends a valid `ClientPosition.player_id`.
- Guard creative and counted stack behavior with Go unit tests.
- Guard the session placement and selected-slot boundaries with network handler tests.
- Guard RocksDB player inventory key separation and record round-trip with storage tests.
- Guard counted runtime placement, count decrement, server restart, and persisted count reload with `scripts/player_inventory_counted_smoke.sh`.
- Guard counted runtime destroy-drop pickup, item entity snapshot delivery, server restart, and persisted count reload with `scripts/player_inventory_break_drop_smoke.sh`.
- Guard the local-player reconnect/restart runtime path through `scripts/player_inventory_reconnect_smoke.sh` as part of the gameplay loop foundation.

Out of scope:

- No crafting rules, Godot scene/resource/import changes, block IDs, chunk serialization changes, world generation changes, or new database engines. Inventory action, snapshot, item entity snapshot, and pickup compatibility is owned by `docs/INVENTORY_PROTOCOL_COMPATIBILITY.md`; item entity restart persistence is owned by `docs/ITEM_ENTITY_PERSISTENCE.md`.

## Current Contract

- `server/pkg/inventory.Inventory` owns inventory slots as `{BlockID, Count}`.
- `NewCreativeHotbar()` derives its slots from the current server block registry and includes only placeable block IDs.
- `CreativeStackCount = 999` matches the current creative gameplay count convention.
- `CountedHotbarStackCount = 8` is the finite count used by the server counted hotbar mode.
- `PlacementPolicyRetain` keeps creative stacks unchanged after placement.
- `NewCounted()` creates a counted inventory where successful placement decrements the matching stack.
- `NewCountedHotbar()` derives the same placeable hotbar slots as creative mode, with `PlacementPolicyConsume` and finite stack counts.
- `CanPlaceBlock()` and `PlaceBlock()` reject air, unknown block IDs, empty slots, and non-placeable registry entries.
- `AddBlock()` accepts one placeable block already represented by an inventory slot and increments counted stacks.
- `CollectBlock()` accepts picked-up placeable block stacks already represented by an inventory slot, increments counted stacks, rejects overflow/zero-count pickups, and leaves creative retained stacks unchanged.
- `CanSelectSlot()`, `PlaceableBlockAtSlot()`, and `FirstPlaceableSlot()` reject unavailable slots and expose slot selection without giving callers mutable inventory state.
- `Slots()` returns a copy so callers cannot mutate inventory internals without going through the domain methods.
- `State(selectedSlot)` and `NewFromState()` are the typed boundary used by persistence without exposing mutable inventory internals.

## Session Placement Boundary

- `newClientSession()` creates a server-owned creative hotbar inventory.
- `Server.newClientSession()` creates the configured session inventory; default mode remains creative, and `RUMPELMC_SERVER_INVENTORY_MODE=counted` creates a finite counted hotbar.
- `newClientSession()` initializes `selectedInventorySlot` from the first available placeable slot.
- Connected sessions receive a server-to-client `InventorySnapshot` for the current inventory slots and selected slot after admission.
- `InventoryAction SELECT_SLOT` updates the selected slot only when the requested slot is available in the session inventory, then sends a fresh snapshot.
- Unavailable selected-slot requests leave server state unchanged and return the current snapshot for client reconciliation.
- `BlockAction PLACE` still validates `world.IsPlaceable(block)` and now also requires `client.inventory.CanPlaceBlock(block)` before applying the edit.
- `client.inventory.PlaceBlock(block)` is applied only after `World.SetBlockGlobal` succeeds, so rejected world edits do not consume counted stacks.
- After successful counted placement, the server normalizes the selected slot if the selected stack becomes unavailable and sends a fresh snapshot after the chunk update.
- If a connected client sends a valid `ClientPosition.player_id`, the session binds once to that player id, loads the persisted inventory state when present, and saves the current creative hotbar state when no record exists.
- Accepted selected-slot changes and successful counted placements save the bound player inventory state through the configured store before sending the refreshed snapshot.
- In counted mode, the first persisted player inventory record stores `PlacementPolicyConsume` and the finite hotbar counts, so later reconnects keep the counted state.
- Invalid or missing `player_id` values keep session-local inventory behavior and do not touch player inventory storage.
- `BlockAction DESTROY` still maps to `world.Air` and does not require an inventory slot.
- Connected-session destroy uses `World.ReplaceBlockGlobal` so the previous block is read atomically with the world edit.
- After successful destroy of a placeable previous block, the server spawns or merges a server-owned item entity at the destroyed block center and broadcasts a fresh `ItemEntitySnapshot`.
- Server-owned item entities are persisted through the approved RocksDB store so uncollected destroyed-block drops survive restart without changing chunk payload bytes.
- `ItemPickupAction` validates the requested item entity id, recorded client position, server pickup reach, item-to-block mapping, and `CollectBlock()` inventory acceptance before mutating inventory.
- Successful pickup removes the item entity, saves the bound player inventory state, broadcasts a fresh item entity snapshot, and sends the collecting client a fresh inventory snapshot.
- Creative retained inventories accept pickup without changing counts.
- The legacy state handler keeps behavior-preserving creative inventory validation for tests that bypass `clientSession`.
- A rejected placement due to missing inventory writes no chunk update to the origin client or interested clients.

## Compatibility Rules

- Keep the inventory protocol compatibility contract in `docs/INVENTORY_PROTOCOL_COMPATIBILITY.md` clean before advancing schema work.
- Do not hand-edit generated protocol files.
- Persist player inventory only through the RocksDB player-inventory record format documented in `docs/STORAGE.md`.
- Do not change RocksDB chunk keys, chunk payload bytes, or `Chunk.Serialize()`.
- Do not bypass `World.SetBlockGlobal` or `World.ReplaceBlockGlobal` after inventory validation passes.
- Do not change block ID numeric values or block registry placeability semantics from this checkpoint.
- Keep creative placement count retention unless a counted/survival gameplay gate explicitly owns the behavior change.
- Keep counted mode behind `RUMPELMC_SERVER_INVENTORY_MODE=counted` until the broader survival loop owns default gameplay rules.

## Gate

Use:

```sh
sh scripts/player_inventory_counted_smoke.sh logs/player_inventory_counted_smoke_current
sh scripts/player_inventory_break_drop_smoke.sh logs/player_inventory_break_drop_smoke_current
sh scripts/player_item_entity_persistence_smoke.sh logs/player_item_entity_persistence_smoke_current
sh scripts/server_inventory_foundation_gate.sh logs/server_inventory_foundation_current
sh scripts/item_entity_persistence_gate.sh logs/item_entity_persistence_current
sh scripts/inventory_protocol_compatibility_gate.sh logs/inventory_protocol_compatibility_current
```

The expected current result is `status=pass`, `server_inventory_status=session_guarded`, `creative_inventory=unit_guarded`, `counted_inventory=unit_guarded`, `counted_inventory_runtime=live_server_guarded`, `counted_inventory_runtime_status=pass`, `counted_inventory_restarts>=1`, `break_drop_inventory=live_server_guarded`, `break_drop_inventory_status=pass`, `break_drop_inventory_restarts>=1`, `item_entity_pickup=live_server_guarded`, `item_entity_pickup_status=pass`, `block_action_inventory=session_guarded`, `player_inventory_persistence=rocksdb_guarded`, `active_protocol_change=0`, `active_storage_change=0`, and `go_tests=pass`.

The gate checks that:

- This document records the current contract, session placement boundary, and compatibility rules.
- `server/pkg/inventory` exposes the slot model, creative inventory, counted inventory, placement/drop insertion methods, selected-slot methods, and copy-out slots.
- Inventory tests cover creative placeable blocks, retained creative counts, counted hotbar stacks, counted stack consumption, counted stack add-back, counted stack pickup, selected-slot validation, empty-slot rejection, air/unknown/overflow rejection, and copied slots.
- World tests cover the previous-block-returning `ReplaceBlockGlobal` boundary and save-error rollback behavior.
- Network tests cover session creative inventory, counted inventory mode, selected-slot action handling, player inventory load/save binding from `ClientPosition.player_id`, rejected placement when the session inventory lacks the requested block, retained counted inventory after a failed world edit, snapshot refresh after counted placement, destroy spawning item entity snapshots, pickup persistence, out-of-reach pickup rejection, no Air item spawn, and no item spawn after failed block edits.
- The counted smoke summary proves a real counted-mode server decrements a placed stack and reloads the decremented count after restart.
- The break-drop smoke summary proves a real counted-mode server spawns a destroyed-block item entity, picks it up through the protocol path, saves the collected count, and reloads the added count after restart.
- The item entity persistence smoke summary proves a real counted-mode server reloads an uncollected destroyed-block item entity after restart, accepts pickup after restart, persists the collected inventory count, and restarts with the item entity absent.
- The item entity policy smoke summary proves a real counted-mode server merges nearby same-item destroyed-block drops into one stack and removes expired drops after restart through the documented item entity persistence path.
- `server/pkg/network/server.go` keeps the existing block registry placeability check, adds the session inventory placement check, spawns item entities after successful destroys, validates `ItemPickupAction`, and validates `InventoryAction SELECT_SLOT` through session inventory.
- Storage tests cover player inventory record round-trip, key separation from chunk records, corrupt record rejection, and empty id rejection.
- The gameplay loop foundation consumes the live player-inventory reconnect smoke and reports `player_inventory_reconnect=live_server_guarded`.
- Protocol schema compatibility is owned by `docs/INVENTORY_PROTOCOL_COMPATIBILITY.md`.

## Current Status

This checkpoint is complete when the gate reports `server_inventory_status=session_guarded`, `player_inventory_persistence=rocksdb_guarded`, `counted_inventory_runtime=live_server_guarded`, `break_drop_inventory=live_server_guarded`, and `item_entity_pickup=live_server_guarded`. The gameplay foundation additionally proves the runtime reconnect/restart path with `player_inventory_reconnect=live_server_guarded`. The server now owns the placement and counted destroy-drop pickup boundary for connected sessions, persists local-player inventory state, and has live guarded counted placement/drop pickup while current default creative placement behavior, chunk serialization, world generation, and renderer behavior remain unchanged.
