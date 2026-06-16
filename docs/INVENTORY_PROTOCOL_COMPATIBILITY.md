# Inventory Protocol Compatibility

Date: 2026-06-16

This document records the inventory snapshot wire-compatibility checkpoint for the gameplay track.

## Current Decision

The current inventory protocol checkpoint adds a server-to-client inventory snapshot packet.

The current inventory runtime uses two packet paths:

- Client placement still sends `Packet.block_action = 3`.
- `BlockAction PLACE` still carries the requested block ID in `block_id = 5`.
- The server now validates that block ID through the server block registry and the connected session inventory before applying `World.SetBlockGlobal`.
- The server sends `Packet.inventory_snapshot = 4` after a client is admitted.
- The Rust client accepts `InventorySnapshot` and stores the latest authoritative slot list.
- A rejected placement does not apply a world edit, does not consume a counted server stack, and does not emit a chunk update.
- Creative session inventory retains counts, so existing creative placement behavior stays compatible with current clients.

## Current Wire Contract

- `Packet.chunk = 1` is the current server-to-client chunk snapshot payload.
- `Packet.position = 2` is the current client-to-server position payload.
- `Packet.block_action = 3` is the current client-to-server edit payload.
- `Packet.inventory_snapshot = 4` is the current server-to-client inventory snapshot payload.
- `BlockAction.action = 1`, `x = 2`, `y = 3`, `z = 4`, and `block_id = 5` keep their current meanings.
- `BlockAction DESTROY` ignores `block_id`.
- `BlockAction PLACE` treats `block_id` as a requested block placement and leaves final authority on the server.

## Inventory Snapshot Contract

- `InventorySlot.block_id = 1` carries the block ID for the slot.
- `InventorySlot.count = 2` carries the server-authoritative stack count.
- `InventorySnapshot.slots = 1` carries the ordered slot list.
- The server snapshot is built from `server/pkg/inventory.Inventory.Slots()`, so callers receive copied slot state.
- The server sends the snapshot through the same session write lock and write-deadline path used by chunk packets.
- The Rust client copies snapshot slots into client state without treating the packet as a chunk for packet queue chunk counts.

## Reserved Allocation

The next inventory schema work must use new field numbers:

- A client-to-server inventory action payload uses a new `Packet.payload` tag greater than `4`; reserve `inventory_action = 5` for that role.
- Extra fields on `BlockAction` must use field numbers greater than `5`.
- Existing `Packet.payload` tags `1` through `4` must not be reused or repurposed.
- Existing `BlockAction` fields `1` through `5` stay fixed.

The `inventory_action = 5` reservation is a compatibility rule for the next schema task. It is not present in `api/schema/packets.proto` in this checkpoint.

## Compatibility Rules

- Do not change or reuse `Packet.inventory_snapshot = 4`.
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

The expected post-commit result is `status=pass`, `inventory_protocol_status=snapshot_guarded`, `active_schema_change=0`, `current_wire_contract=block_action_and_inventory_snapshot`, `inventory_snapshot_schema=tag_4_guarded`, `future_packet_tags=packet_gt_4`, `future_block_action_fields=block_action_gt_5`, `protocol_generated_drift=guarded`, `server_inventory_status=session_guarded`, and `gameplay_inventory_status=session_guarded`.

The gate checks that:

- This document records the current decision, wire contract, inventory snapshot contract, reserved allocation, and compatibility rules.
- `api/schema/packets.proto` has the current `Packet.payload` tags `chunk=1`, `position=2`, `block_action=3`, and `inventory_snapshot=4`.
- `BlockAction.block_id` still uses field number `5`.
- `InventorySlot` and `InventorySnapshot` field numbers are guarded.
- Protocol schema and generated Go protocol files have no active diff.
- The protocol generated drift gate is clean.
- Go compatibility tests guard exact inventory snapshot wire bytes.
- The server sends inventory snapshots through the session write path.
- The Rust client accepts inventory snapshot payloads and stores copied slot state.
- The server inventory foundation gate is clean and reports session-owned placement validation.
- The gameplay foundation gate is clean and consumes the server inventory evidence.

## Current Status

This checkpoint is complete when the gate reports `inventory_protocol_status=snapshot_guarded`. Inventory can keep advancing toward server-owned actions and persistence while snapshot delivery remains a guarded protocol feature.
