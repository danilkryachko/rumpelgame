# Item Tool Foundation

This document records the first server-owned item identity and tool slot checkpoint for the gameplay track.

## Technical Brief

Goal:

Add stable server-side item IDs for the current placeable blocks and a first server-owned tool slot that can affect counted/survival mining duration without changing storage formats, world generation, chunk serialization, or default creative behavior. Client-visible selected-tool changes are carried by the inventory action/snapshot protocol without adding item ID or tool ID packet fields.

Scope:

- Keep block voxel identity on the existing `world.BlockID` values.
- Add server-side item IDs for the current placeable blocks.
- Add server-side tool IDs for hand plus wooden pickaxe, axe, and shovel.
- Start every session with a server-owned toolbelt whose selected tool slot is `tool:hand`.
- Keep hand mining behavior identical to the current target-block duration behavior.
- Apply selected-tool mining duration adjustment only after the server chooses the target block's base duration.
- Keep explicit `RUMPELMC_SERVER_MINING_COOLDOWN_MS` override values exact.
- Guard the item catalog, selected tool fallback, and destroy cooldown adjustment with Go tests.

Outside this checkpoint:

- No item entity pickup packet.
- No crafting, stack transfer, tool durability, or equipment save format.
- No protocol fields for item IDs or tool IDs.
- No RocksDB key or payload change.
- No world generation, chunk serialization, Godot scene/resource/import, renderer, lighting, shadow, draw-distance, or texture-quality change.

## Server-Owned Item Identity

`server/pkg/item` owns the current item identity catalog:

- `block:stone` maps to `world.Stone`.
- `block:dirt` maps to `world.Dirt`.
- `block:grass` maps to `world.Grass`.
- `block:wood` maps to `world.Wood`.
- `block:leaves` maps to `world.Leaves`.

These IDs are stable server gameplay IDs, not network or storage IDs. `block_id` remains the only voxel identity in chunk payloads and current block action packets.

The catalog exposes copy-returning accessors so callers cannot mutate the registry:

- `BlockItemDefinitions()`
- `BlockItemID(block)`
- `BlockForItem(id)`

## First Tool Slot

`server/pkg/item` also owns the current tool catalog:

- `tool:hand` is the default tool and has no speed bonus.
- `tool:wooden_pickaxe` is effective on Stone.
- `tool:wooden_axe` is effective on Wood and Leaves.
- `tool:wooden_shovel` is effective on Dirt and Grass.

`DefaultToolbelt()` returns hand, wooden pickaxe, wooden axe, and wooden shovel in that order. `clientSession` stores this toolbelt and starts with selected tool slot `0`, so the default selected tool is always `tool:hand`.

Invalid selected tool slots and empty toolbelts fall back to `tool:hand`.

Client-selected tool changes use `InventoryAction SELECT_TOOL_SLOT` and are echoed through `InventorySnapshot.selected_tool_slot`. The selected slot remains session state for this checkpoint; the current RocksDB player-inventory record still stores inventory slots and selected block slot only.

## Mining Duration Contract

Connected-session `BlockAction_DESTROY` still follows the existing server sequence:

- Validate reach.
- Read the target block with `World.BlockAtGlobal`.
- Choose the target block's server-owned base mining duration.
- Adjust the duration with the selected server-side tool.
- Reject early destroy actions before any world mutation, inventory mutation, save, broadcast, or snapshot.
- Record cooldown only after a successful destroy of a placeable previous block.

Tool adjustment is intentionally integer and deterministic. Effective wooden tools divide the base duration by their multiplier with round-up. Unknown tools, ineffective tools, `tool:hand`, zero durations, and explicit global mining cooldown overrides keep the base duration unchanged.

## Compatibility Rules

- Keep `Packet.block_action = 3` and the current `BlockAction` fields.
- Keep `Packet.inventory_snapshot = 4` and `Packet.inventory_action = 5` as the selected block/tool slot inventory protocol boundary.
- Keep `block_id` as the current wire/storage identity for voxel contents.
- Do not add item/tool packet fields without a separate protocol compatibility task.
- Do not change RocksDB chunk keys, chunk payload bytes, player inventory records, chunk serialization, or world generation.
- Keep default creative sessions behavior-compatible with zero mining cooldown and retained inventory counts.
- Keep explicit `RUMPELMC_SERVER_MINING_COOLDOWN_MS` values as exact operator overrides.

## Gate

Use:

```sh
sh scripts/item_tool_foundation_gate.sh logs/item_tool_foundation_current
```

The expected current result is `status=pass`, `item_tool_foundation=server_guarded`, `item_identity=block_items_guarded`, `tool_catalog=wood_tools_guarded`, `first_tool_slot=hand_guarded`, `tool_mining=selected_tool_guarded`, `active_protocol_change=0`, `active_storage_change=0`, `active_worldgen_change=0`, and `go_tests=pass`.

The gate checks that:

- This document records server-owned item identity, first tool slot, mining duration contract, and compatibility rules.
- `server/pkg/item` contains the block item IDs, tool IDs, default toolbelt, copy-returning catalog accessors, and deterministic mining duration adjustment.
- `server/pkg/network` initializes session toolbelts, falls back to `tool:hand`, and applies selected-tool mining duration in the destroy cooldown path.
- Network tests cover default tool slot behavior, selected-tool duration adjustment, exact global override behavior, and runtime destroy cooldown with a selected wooden pickaxe.
- Protocol schema/generated files are unchanged.
- Storage package/docs and world generation sources are unchanged.
- Focused Go item and network tests pass.

## Current Status

This checkpoint is complete when the gate reports `item_tool_foundation=server_guarded` and `tool_mining=selected_tool_guarded`. It gives the server a stable item/tool vocabulary and a first selected-tool mining effect while preserving the current packet, storage, world generation, and default creative behavior contracts.
