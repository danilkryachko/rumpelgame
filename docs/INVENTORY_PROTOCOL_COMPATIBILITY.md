# Inventory Protocol Compatibility

Date: 2026-06-16

This document records the inventory wire-compatibility checkpoint for the gameplay track.

## Current Decision

No protobuf schema change is active in this checkpoint.

The current inventory foundation uses the existing `BlockAction` packet:

- Client placement still sends `Packet.block_action = 3`.
- `BlockAction PLACE` still carries the requested block ID in `block_id = 5`.
- The server now validates that block ID through the server block registry and the connected session inventory before applying `World.SetBlockGlobal`.
- A rejected placement does not apply a world edit, does not consume a counted server stack, and does not emit a chunk update.
- Creative session inventory retains counts, so existing creative placement behavior stays compatible with current clients.

## Current Wire Contract

- `Packet.chunk = 1` is the current server-to-client chunk snapshot payload.
- `Packet.position = 2` is the current client-to-server position payload.
- `Packet.block_action = 3` is the current client-to-server edit payload.
- `BlockAction.action = 1`, `x = 2`, `y = 3`, `z = 4`, and `block_id = 5` keep their current meanings.
- `BlockAction DESTROY` ignores `block_id`.
- `BlockAction PLACE` treats `block_id` as a requested block placement and leaves final authority on the server.

## Reserved Allocation

The next inventory schema work must use new field numbers:

- A server-to-client inventory snapshot payload uses a new `Packet.payload` tag greater than `3`; reserve `inventory_snapshot = 4` for that role.
- A client-to-server inventory action payload uses a new `Packet.payload` tag greater than `3`; reserve `inventory_action = 5` for that role.
- Extra fields on `BlockAction` must use field numbers greater than `5`.
- Existing `Packet.payload` tags `1`, `2`, and `3` must not be reused or repurposed.
- Existing `BlockAction` fields `1` through `5` stay fixed.

Those reservations are compatibility rules for the next schema task. They are not present in `api/schema/packets.proto` in this checkpoint.

## Compatibility Rules

- Do not add inventory fields to `api/schema/packets.proto` until a schema task owns the full client/server compatibility work.
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

The expected current result is `status=pass`, `inventory_protocol_status=compatibility_guarded`, `active_schema_change=0`, `current_wire_contract=block_action_session_inventory`, `future_packet_tags=packet_gt_3`, `future_block_action_fields=block_action_gt_5`, `protocol_generated_drift=guarded`, `server_inventory_status=session_guarded`, and `gameplay_inventory_status=session_guarded`.

The gate checks that:

- This document records the current decision, wire contract, reserved allocation, and compatibility rules.
- `api/schema/packets.proto` still has only the current `Packet.payload` tags `chunk=1`, `position=2`, and `block_action=3`.
- `BlockAction.block_id` still uses field number `5`.
- Protocol schema and generated Go protocol files have no active diff.
- The protocol generated drift gate is clean.
- The server inventory foundation gate is clean and reports session-owned placement validation.
- The gameplay foundation gate is clean and consumes the server inventory evidence.

## Current Status

This checkpoint is complete when the gate reports `inventory_protocol_status=compatibility_guarded`. Inventory can keep advancing through server-owned runtime behavior while schema changes remain isolated behind a later compatibility task.
