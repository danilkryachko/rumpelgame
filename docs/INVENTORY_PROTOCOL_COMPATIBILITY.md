# Inventory Protocol Compatibility

Date: 2026-06-16

This document records the inventory action and snapshot wire-compatibility checkpoint for the gameplay track.

## Current Decision

The current inventory protocol checkpoint adds a server-authoritative selected-slot action and keeps snapshot delivery guarded.

The current inventory runtime uses three packet paths:

- Client placement still sends `Packet.block_action = 3`.
- `BlockAction PLACE` still carries the requested block ID in `block_id = 5`.
- The server now validates that block ID through the server block registry and the connected session inventory before applying `World.SetBlockGlobal`.
- The server sends `Packet.inventory_snapshot = 4` after a client is admitted.
- The Rust client accepts `InventorySnapshot` and stores the latest authoritative slot list plus selected slot.
- The Rust client sends `Packet.inventory_action = 5` with `InventoryAction SELECT_SLOT` when the player chooses a valid hotbar slot.
- The server validates `InventoryAction.slot` against the connected session inventory before changing the selected slot.
- Accepted slot changes are echoed through a fresh `InventorySnapshot`.
- Successful counted placements send the editing client a chunk update followed by an updated `InventorySnapshot`.
- A rejected placement does not apply a world edit, does not consume a counted server stack, and does not emit a chunk update.
- Creative session inventory retains counts, so existing creative placement behavior stays compatible with current clients.

## Current Wire Contract

- `Packet.chunk = 1` is the current server-to-client chunk snapshot payload.
- `Packet.position = 2` is the current client-to-server position payload.
- `Packet.block_action = 3` is the current client-to-server edit payload.
- `Packet.inventory_snapshot = 4` is the current server-to-client inventory snapshot payload.
- `Packet.inventory_action = 5` is the current client-to-server selected-slot action payload.
- `BlockAction.action = 1`, `x = 2`, `y = 3`, `z = 4`, and `block_id = 5` keep their current meanings.
- `BlockAction DESTROY` ignores `block_id`.
- `BlockAction PLACE` treats `block_id` as a requested block placement and leaves final authority on the server.

## Inventory Snapshot Contract

- `InventorySlot.block_id = 1` carries the block ID for the slot.
- `InventorySlot.count = 2` carries the server-authoritative stack count.
- `InventorySnapshot.slots = 1` carries the ordered slot list.
- `InventorySnapshot.selected_slot = 2` carries the server-authoritative selected slot index.
- The server snapshot is built from `server/pkg/inventory.Inventory.Slots()`, so callers receive copied slot state.
- The server sends the snapshot through the same session write lock and write-deadline path used by chunk packets.
- The Rust client copies snapshot slots and selected slot into client state without treating the packet as a chunk for packet queue chunk counts.

## Inventory Action Contract

- `InventoryAction.action = 1` carries the inventory action enum.
- `InventoryAction.slot = 2` carries the requested slot index.
- `InventoryAction SELECT_SLOT = 0` requests server-authoritative hotbar selection.
- The server ignores nil inventory action bodies and unknown actions.
- Unavailable slot indexes leave the selected slot unchanged and return the current authoritative snapshot.
- The client emits selected-slot actions only for locally placeable hotbar slots; this is a usability guard, not server authority.

## Reserved Allocation

Additional inventory schema work must use new field numbers:

- New `Packet.payload` variants must use tags greater than `5`.
- Extra fields on `BlockAction` must use field numbers greater than `5`.
- Existing `Packet.payload` tags `1` through `5` must not be reused or repurposed.
- Existing `BlockAction` fields `1` through `5` stay fixed.
- Additional `InventorySnapshot` fields must use field numbers greater than `2`.
- Additional `InventoryAction` fields must use field numbers greater than `2`.

## Compatibility Rules

- Do not change or reuse `Packet.inventory_snapshot = 4`.
- Do not change or reuse `Packet.inventory_action = 5`.
- Do not hand-edit generated protocol files.
- Do not persist inventory stacks until a storage design defines the record ownership, migration behavior, and rollback path.
- Old clients that only send `BlockAction PLACE` must continue to work against creative session inventory.
- Current server placement validation must remain server-owned and must not trust client-only hotbar state.
- Keep `World.SetBlockGlobal` as the persistence-capable world-edit boundary after inventory validation passes.
- Keep block IDs as the only current wire/storage identity for voxel contents.

## Gate

Use:

```sh
sh scripts/inventory_protocol_compatibility_gate.sh logs/inventory_protocol_compatibility_current
```

The expected post-commit result is `status=pass`, `inventory_protocol_status=action_guarded`, `active_schema_change=0`, `current_wire_contract=block_action_inventory_snapshot_and_action`, `inventory_snapshot_schema=tag_4_guarded`, `inventory_action_schema=tag_5_guarded`, `future_packet_tags=packet_gt_5`, `future_block_action_fields=block_action_gt_5`, `protocol_generated_drift=guarded`, `server_inventory_status=session_guarded`, and `gameplay_inventory_status=session_guarded`.

The gate checks that:

- This document records the current decision, wire contract, inventory snapshot contract, inventory action contract, reserved allocation, and compatibility rules.
- `api/schema/packets.proto` has the current `Packet.payload` tags `chunk=1`, `position=2`, `block_action=3`, `inventory_snapshot=4`, and `inventory_action=5`.
- `BlockAction.block_id` still uses field number `5`.
- `InventorySlot`, `InventorySnapshot`, and `InventoryAction` field numbers are guarded.
- Protocol schema and generated Go protocol files have no active diff.
- The protocol generated drift gate is clean.
- Go compatibility tests guard exact inventory snapshot and inventory action wire bytes.
- The server sends inventory snapshots through the session write path.
- The server handles selected-slot inventory actions through session inventory validation.
- The Rust client accepts inventory snapshot payloads, stores copied slot state, and sends selected-slot inventory actions.
- The server inventory foundation gate is clean and reports session-owned placement validation.
- The gameplay foundation gate is clean and consumes the server inventory evidence.

## Current Status

This checkpoint is complete when the gate reports `inventory_protocol_status=action_guarded`. Inventory can keep advancing toward persisted stacks, drops, pickups, and crafting while selected-slot actions and snapshot delivery remain guarded protocol features.
