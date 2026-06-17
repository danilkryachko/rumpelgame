# Inventory Protocol Compatibility

Date: 2026-06-16

This document records the inventory action, tool action, and snapshot wire-compatibility checkpoint for the gameplay track.

## Current Decision

The current inventory protocol checkpoint adds server-authoritative selected block-slot and tool-slot actions, keeps snapshot delivery guarded, and uses optional `ClientPosition.player_id` for local-player inventory persistence.

The current inventory runtime uses three packet paths:

- Client placement still sends `Packet.block_action = 3`.
- `BlockAction PLACE` still carries the requested block ID in `block_id = 5`.
- The server now validates that block ID through the server block registry and the connected session inventory before applying `World.SetBlockGlobal`.
- The server sends `Packet.inventory_snapshot = 4` after a client is admitted.
- The Rust client accepts `InventorySnapshot` and stores the latest authoritative slot list, selected block slot, and selected tool slot.
- The Rust client sends `Packet.inventory_action = 5` with `InventoryAction SELECT_SLOT` when the player chooses a valid hotbar slot.
- The Rust client sends `Packet.inventory_action = 5` with `InventoryAction SELECT_TOOL_SLOT` when the player chooses a valid tool slot.
- The Rust client sends `ClientPosition.player_id = "local_player"` on bootstrap and periodic position packets.
- The server validates `InventoryAction.slot` against the connected session inventory before changing the selected block slot.
- The server validates `InventoryAction.tool_slot` against the connected session toolbelt before changing the selected tool slot.
- Accepted block-slot and tool-slot changes are echoed through a fresh `InventorySnapshot`.
- Successful counted placements send the editing client a chunk update followed by an updated `InventorySnapshot`.
- The server loads and saves bound player inventory state through RocksDB when `ClientPosition.player_id` is valid.
- Selected tool slot state is current-session equipment selection in this checkpoint; it is not saved into the RocksDB player-inventory record.
- A rejected placement does not apply a world edit, does not consume a counted server stack, and does not emit a chunk update.
- Creative session inventory retains counts, so existing creative placement behavior stays compatible with current clients.

## Current Wire Contract

- `Packet.chunk = 1` is the current server-to-client chunk snapshot payload.
- `Packet.position = 2` is the current client-to-server position payload.
- `Packet.block_action = 3` is the current client-to-server edit payload.
- `Packet.inventory_snapshot = 4` is the current server-to-client inventory snapshot payload.
- `Packet.inventory_action = 5` is the current client-to-server selected block-slot and tool-slot action payload.
- `ClientPosition.player_id = 4` is the optional client-to-server local-player identity used by inventory persistence.
- `BlockAction.action = 1`, `x = 2`, `y = 3`, `z = 4`, and `block_id = 5` keep their current meanings.
- `BlockAction DESTROY` ignores `block_id`.
- `BlockAction PLACE` treats `block_id` as a requested block placement and leaves final authority on the server.

## Inventory Snapshot Contract

- `InventorySlot.block_id = 1` carries the block ID for the slot.
- `InventorySlot.count = 2` carries the server-authoritative stack count.
- `InventorySnapshot.slots = 1` carries the ordered slot list.
- `InventorySnapshot.selected_slot = 2` carries the server-authoritative selected slot index.
- `InventorySnapshot.selected_tool_slot = 3` carries the server-authoritative selected tool slot index.
- The server snapshot is built from `server/pkg/inventory.Inventory.Slots()`, so callers receive copied slot state.
- The server sends the snapshot through the same session write lock and write-deadline path used by chunk packets.
- The Rust client copies snapshot slots, selected slot, and selected tool slot into client state without treating the packet as a chunk for packet queue chunk counts.

## Inventory Action Contract

- `InventoryAction.action = 1` carries the inventory action enum.
- `InventoryAction.slot = 2` carries the requested slot index.
- `InventoryAction.tool_slot = 3` carries the requested tool slot index.
- `InventoryAction SELECT_SLOT = 0` requests server-authoritative hotbar selection.
- `InventoryAction SELECT_TOOL_SLOT = 1` requests server-authoritative tool selection.
- The server ignores nil inventory action bodies and unknown actions.
- Unavailable block-slot or tool-slot indexes leave the selected slot unchanged and return the current authoritative snapshot.
- The client emits selected-slot actions only for locally placeable hotbar slots and bounded tool slots; this is a usability guard, not server authority.

## Reserved Allocation

Additional inventory schema work must use new field numbers:

- New `Packet.payload` variants must use tags greater than `5`.
- Extra fields on `BlockAction` must use field numbers greater than `5`.
- Existing `Packet.payload` tags `1` through `5` must not be reused or repurposed.
- Existing `BlockAction` fields `1` through `5` stay fixed.
- Additional `InventorySnapshot` fields must use field numbers greater than `3`.
- Additional `InventoryAction` fields must use field numbers greater than `3`.

## Compatibility Rules

- Do not change or reuse `Packet.inventory_snapshot = 4`.
- Do not change or reuse `Packet.inventory_action = 5`.
- Do not change or reuse `ClientPosition.player_id = 4`.
- Do not hand-edit generated protocol files.
- Persist inventory stacks only through the RocksDB player-inventory record format documented in `docs/STORAGE.md`.
- Do not add selected tool slot persistence without a separate storage compatibility task.
- Old clients that only send `BlockAction PLACE` must continue to work against creative session inventory.
- Current server placement validation must remain server-owned and must not trust client-only hotbar state.
- Keep `World.SetBlockGlobal` as the persistence-capable world-edit boundary after inventory validation passes.
- Keep block IDs as the only current wire/storage identity for voxel contents.

## Gate

Use:

```sh
sh scripts/inventory_protocol_compatibility_gate.sh logs/inventory_protocol_compatibility_current
```

The expected post-commit result is `status=pass`, `inventory_protocol_status=tool_action_guarded`, `active_schema_change=0`, `current_wire_contract=block_action_inventory_snapshot_action_tool_action_and_player_id`, `position_identity_schema=tag_4_guarded`, `inventory_snapshot_schema=tag_4_guarded`, `inventory_action_schema=tag_5_guarded`, `tool_selection_schema=field_3_guarded`, `future_packet_tags=packet_gt_5`, `future_block_action_fields=block_action_gt_5`, `protocol_generated_drift=guarded`, `server_inventory_status=session_guarded`, and `gameplay_inventory_status=session_guarded`.

The gate checks that:

- This document records the current decision, wire contract, inventory snapshot contract, inventory action contract, reserved allocation, and compatibility rules.
- `api/schema/packets.proto` has the current `Packet.payload` tags `chunk=1`, `position=2`, `block_action=3`, `inventory_snapshot=4`, and `inventory_action=5`.
- `ClientPosition.player_id` uses field number `4`.
- `BlockAction.block_id` still uses field number `5`.
- `InventorySlot`, `InventorySnapshot`, and `InventoryAction` field numbers are guarded, including `selected_tool_slot = 3` and `tool_slot = 3`.
- Protocol schema and generated Go protocol files have no active diff.
- The protocol generated drift gate is clean.
- Go compatibility tests guard exact inventory snapshot, selected-tool snapshot, inventory action, and tool action wire bytes.
- The server sends inventory snapshots through the session write path.
- The server handles selected block-slot and tool-slot inventory actions through session validation.
- The Rust client accepts inventory snapshot payloads, stores copied slot/tool state, sends selected-slot inventory actions, and exposes the selected tool to HUD/debug UI.
- The server inventory foundation gate is clean and reports session-owned placement validation.
- The gameplay foundation gate is clean and consumes the server inventory evidence.

## Current Status

This checkpoint is complete when the gate reports `inventory_protocol_status=tool_action_guarded`. Inventory can keep advancing toward persisted stacks, drops, pickups, durability, and crafting while selected block-slot actions, selected tool-slot actions, and snapshot delivery remain guarded protocol features.
