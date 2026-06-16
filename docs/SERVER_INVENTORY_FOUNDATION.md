# Server Inventory Foundation

This document records the first server-owned inventory checkpoint for the gameplay track.

## Technical Brief

Goal:

Move block placement validation from block-registry-only checks to a session-owned inventory boundary while preserving current creative gameplay behavior and the current protocol/storage formats.

Scope:

- Add `server/pkg/inventory` as the authoritative domain model for placeable block stacks.
- Give each `clientSession` a server-owned creative hotbar inventory.
- Keep `BlockAction PLACE` on the existing packet shape and require the session inventory before applying the edit.
- Keep selected hotbar slot state on the server session and validate selected-slot actions against the session inventory.
- Guard creative and counted stack behavior with Go unit tests.
- Guard the session placement and selected-slot boundaries with network handler tests.

Out of scope:

- No storage records, item-stack persistence, crafting rules, drops, pickup packets, client UI changes, Godot scene/resource/import changes, block IDs, chunk serialization changes, world generation changes, or database changes. Inventory action and snapshot compatibility is owned by `docs/INVENTORY_PROTOCOL_COMPATIBILITY.md`.

## Current Contract

- `server/pkg/inventory.Inventory` owns inventory slots as `{BlockID, Count}`.
- `NewCreativeHotbar()` derives its slots from the current server block registry and includes only placeable block IDs.
- `CreativeStackCount = 999` matches the current creative gameplay count convention.
- `PlacementPolicyRetain` keeps creative stacks unchanged after placement.
- `NewCounted()` creates a counted inventory where successful placement decrements the matching stack.
- `CanPlaceBlock()` and `PlaceBlock()` reject air, unknown block IDs, empty slots, and non-placeable registry entries.
- `CanSelectSlot()`, `PlaceableBlockAtSlot()`, and `FirstPlaceableSlot()` reject unavailable slots and expose slot selection without giving callers mutable inventory state.
- `Slots()` returns a copy so callers cannot mutate inventory internals without going through the domain methods.

## Session Placement Boundary

- `newClientSession()` creates a server-owned creative hotbar inventory.
- `newClientSession()` initializes `selectedInventorySlot` from the first available placeable slot.
- Connected sessions receive a server-to-client `InventorySnapshot` for the current inventory slots and selected slot after admission.
- `InventoryAction SELECT_SLOT` updates the selected slot only when the requested slot is available in the session inventory, then sends a fresh snapshot.
- Unavailable selected-slot requests leave server state unchanged and return the current snapshot for client reconciliation.
- `BlockAction PLACE` still validates `world.IsPlaceable(block)` and now also requires `client.inventory.CanPlaceBlock(block)` before applying the edit.
- `client.inventory.PlaceBlock(block)` is applied only after `World.SetBlockGlobal` succeeds, so rejected world edits do not consume counted stacks.
- After successful counted placement, the server normalizes the selected slot if the selected stack becomes unavailable and sends a fresh snapshot after the chunk update.
- `BlockAction DESTROY` still maps to `world.Air` and does not require an inventory slot.
- The legacy state handler keeps behavior-preserving creative inventory validation for tests that bypass `clientSession`.
- A rejected placement due to missing inventory writes no chunk update to the origin client or interested clients.

## Compatibility Rules

- Keep the inventory protocol compatibility contract in `docs/INVENTORY_PROTOCOL_COMPATIBILITY.md` clean before advancing schema work.
- Do not hand-edit generated protocol files.
- Do not persist item stacks or session inventory without a storage design and migration gate.
- Do not change RocksDB chunk keys, chunk payload bytes, or `Chunk.Serialize()`.
- Do not bypass `World.SetBlockGlobal` after inventory validation passes.
- Do not change block ID numeric values or block registry placeability semantics from this checkpoint.
- Keep creative placement count retention unless a counted/survival gameplay gate explicitly owns the behavior change.

## Gate

Use:

```sh
sh scripts/server_inventory_foundation_gate.sh logs/server_inventory_foundation_current
sh scripts/inventory_protocol_compatibility_gate.sh logs/inventory_protocol_compatibility_current
```

The expected current result is `status=pass`, `server_inventory_status=session_guarded`, `creative_inventory=unit_guarded`, `counted_inventory=unit_guarded`, `block_action_inventory=session_guarded`, `active_protocol_change=0`, `active_storage_change=0`, and `go_tests=pass`.

The gate checks that:

- This document records the current contract, session placement boundary, and compatibility rules.
- `server/pkg/inventory` exposes the slot model, creative inventory, counted inventory, placement methods, selected-slot methods, and copy-out slots.
- Inventory tests cover creative placeable blocks, retained creative counts, counted stack consumption, selected-slot validation, empty-slot rejection, air/unknown rejection, and copied slots.
- Network tests cover session creative inventory, selected-slot action handling, rejected placement when the session inventory lacks the requested block, retained counted inventory after a failed world edit, and snapshot refresh after counted placement.
- `server/pkg/network/server.go` keeps the existing block registry placeability check, adds the session inventory placement check, and validates `InventoryAction SELECT_SLOT` through session inventory.
- Storage docs/source remain unchanged; protocol schema compatibility is owned by `docs/INVENTORY_PROTOCOL_COMPATIBILITY.md`.

## Current Status

This checkpoint is complete when the gate reports `server_inventory_status=session_guarded`. The server now owns the placement inventory boundary for connected sessions while current creative placement behavior, protocol, storage, chunk serialization, world generation, and renderer behavior remain unchanged.
