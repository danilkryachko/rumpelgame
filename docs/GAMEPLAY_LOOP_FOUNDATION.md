# Gameplay Loop Foundation

Block 40, Gameplay Loop Foundation, records the first minimal gameplay loop checkpoint after the streaming/client lifecycle hardening work.

## Technical Brief

User request:

Continue the annual world streaming architecture plan in order and use MCP/OntoIndex context.

Goal:

Keep the existing mining/building loop stable, confirm that block edits still flow through persistence-capable server state, and guard the client/server creative inventory foundations plus local-player inventory persistence without changing chunk storage format.

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
- Add a server-owned session inventory placement boundary for the current creative block set.
- Keep the current creative five-slot hotbar behavior over existing placeable block IDs.
- Show server-authoritative hotbar slot names, counts, and selected slot in the Godot HUD from `InventorySnapshot`.
- Guard server-owned counted break-drop insertion for destroyed placeable blocks.
- Guard server-owned item identity and a first selected tool slot for mining duration adjustment.
- Guard inventory slot rules with Rust unit tests.
- Guard server session inventory rules with Go unit tests and a network handler test.
- Guard local-player inventory persistence with a live TCP server restart/reconnect smoke over an isolated RocksDB store.
- Define the minimum mining/building persistence contract before the dedicated Block Edit Persistence Track.

Out of scope:

- No crafting, item entity pickup packets, tool durability, client-visible tool selection, survival rules beyond counted mining duration, new block IDs beyond inventory action/snapshot/player-id compatibility, dirty chunk scheduler, visual smoke rewrite, or Godot scene/resource/import change.

Assumptions:

- Mining and building remain client input actions that emit `block_broken` and `block_placed` signals.
- Server `BlockAction` remains the only networked edit command.
- Server `World.SetBlockGlobal` and `World.ReplaceBlockGlobal` are the persistence-capable edit boundaries because they call `ChunkStore.SaveChunk` when a store is configured.
- The current hotbar is creative-mode inventory, so counts are guard data and are not decremented by placement yet.
- Server sessions use the same creative placement retention through `server/pkg/inventory`.
- The Rust client sends `ClientPosition.player_id = "local_player"` so the loopback local-player inventory can persist across reconnects.
- The Godot HUD reads authoritative inventory getters from `GameClient` and keeps local key selection only as the pre-snapshot display state.
- Full edit persistence verification is supplied by the completed Block 41 persisted visual evidence chain.
- Inventory protocol compatibility is guarded separately in `docs/INVENTORY_PROTOCOL_COMPATIBILITY.md` and keeps this checkpoint on the existing `BlockAction` packet shape.

Done when:

- The player hotbar has an explicit inventory slot model, selected slot state, and tests.
- The HUD displays authoritative inventory slot labels/counts and selected-slot highlight from `InventorySnapshot`.
- The server session inventory gate reports `server_inventory_status=session_guarded`.
- A gameplay foundation gate checks the client inventory tests, the server edit/persistence path, the local-player inventory reconnect smoke, and the completed Block 41 persisted visual proof.

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
- `selected_hotbar_slot` stores the active slot separately from `selected_block`
- `initial_hotbar_inventory()` derives slots from `blocks::PLACEABLE_BLOCKS`
- `inventory_slot_can_place()` requires positive count and a placeable block ID
- `inventory_has_placeable_block()` gates right-click placement
- `first_placeable_hotbar_slot()` initializes selection from the first usable slot
- `selected_hotbar_state_after_request()` updates slot and block ID together only for usable slots
- `hotbar_key_for_slot()` keeps key mapping bounded to slots `1..5`
- `hotbar_selected(slot, block_id)` emits only when the requested usable slot changes, and `GameClient.on_hotbar_selected` sends `InventoryAction SELECT_SLOT`
- `client_position_packet()` includes the stable local `player_id` on bootstrap and periodic position packets
- `GameClient` copies authoritative inventory slots and selected slot from `InventorySnapshot`, exposes slot/count text through `get_authoritative_inventory_slot_text()`, and exposes selected slot/block getters for the HUD.

This keeps the existing hotbar behavior while making selected-slot intent visible to the server. Authoritative selected-slot state comes back through `InventorySnapshot`, and the HUD uses that state for labels and highlight once it arrives.

## Server Inventory Foundation

The server now has a session-owned inventory foundation:

- `server/pkg/inventory.Inventory` owns `{BlockID, Count}` slots.
- `NewCreativeHotbar()` derives placeable slots from the server block registry.
- `NewCounted()` supports counted stack consumption for server-side rules.
- `NewCountedHotbar()` and `RUMPELMC_SERVER_INVENTORY_MODE=counted` provide a guarded finite-count runtime mode over the same inventory snapshot/action protocol.
- `clientSession` owns an inventory created by `NewCreativeHotbar()`.
- `clientSession` owns `selectedInventorySlot`, initializes it from the first placeable slot, and validates `InventoryAction SELECT_SLOT` against session inventory.
- `BlockAction_PLACE` keeps the existing `world.IsPlaceable(block)` check and requires `client.inventory.CanPlaceBlock(block)` before the world edit.
- Connected-session block edits require a recorded `ClientPosition` and a target block within the server reach envelope before the world edit.
- Connected-session `BlockAction_PLACE` rejects target blocks that intersect the last recorded player body AABB before world mutation or inventory consumption.
- Counted placement is applied only after `World.SetBlockGlobal` succeeds.
- Successful counted placement sends a fresh inventory snapshot after the chunk update and normalizes the selected slot if the selected stack is depleted.
- Connected-session `BlockAction_DESTROY` uses `World.ReplaceBlockGlobal`, maps the block to `Air`, and adds one placeable previous block back into matching counted inventory slots after the world edit succeeds.
- Counted destroy-drop insertion saves bound player inventory and is guarded by a live server restart smoke; creative retained inventories keep counts unchanged.
- A valid `ClientPosition.player_id` binds the session to a persisted player inventory state through the configured RocksDB store.
- Missing inventory records create the current creative hotbar record; existing records restore slots and selected slot.
- Selected-slot changes and successful counted placements save the bound inventory state.
- Creative placement keeps counts retained, so current creative block placement behavior is unchanged.
- Counted runtime placement is guarded by a live server smoke that decrements a placed stack and reloads the decremented count after restart.
- Counted break-drop insertion is guarded by a live server smoke that destroys a generated Stone block, increments the selected stack, and reloads the added count after restart.
- Missing inventory entries reject placement before `World.SetBlockGlobal` and before chunk update broadcast.

## Item Tool Foundation

The server now has a first item/tool foundation checkpoint:

- `server/pkg/item` maps the current placeable blocks to stable gameplay item IDs: `block:stone`, `block:dirt`, `block:grass`, `block:wood`, and `block:leaves`.
- `server/pkg/item` maps the first tool IDs: `tool:hand`, `tool:wooden_pickaxe`, `tool:wooden_axe`, and `tool:wooden_shovel`.
- New sessions start with `DefaultToolbelt()` and selected tool slot `0`, so the selected tool defaults to `tool:hand`.
- Invalid selected tool slots and empty toolbelts fall back to `tool:hand`.
- Wooden pickaxe is effective on Stone, wooden axe on Wood/Leaves, and wooden shovel on Dirt/Grass.
- Item and tool IDs are server gameplay IDs only; they are not packet fields, RocksDB keys, chunk payload IDs, or worldgen inputs.

## Mining Rules Foundation

- `RUMPELMC_SERVER_MINING_COOLDOWN_MS` configures the server mining cooldown in milliseconds.
- Default creative sessions keep zero mining cooldown.
- Counted/survival sessions use server-owned target-block mining durations unless the operator sets an explicit global value.
- Connected-session `BlockAction_DESTROY` reads the target block and checks its duration after reach validation and before world mutation.
- Connected-session destroy applies the selected server-side tool adjustment after choosing the target block's base duration.
- `tool:hand`, unknown tools, ineffective tools, zero durations, and explicit global mining cooldown overrides keep the base duration unchanged.
- Cooldown rejection emits no chunk update, no inventory mutation, no player inventory save, and no inventory snapshot.
- The cooldown is recorded only after `World.ReplaceBlockGlobal` succeeds and the previous block was placeable.
- This keeps mining-time authority on the server without adding protocol fields; tool durability and client-visible tool selection remain separate gameplay work.

## Persistence Boundary

The gameplay foundation relies on the existing server boundary:

- `BlockAction_PLACE` flows through `World.SetBlockGlobal`; connected-session `BlockAction_DESTROY` flows through `World.ReplaceBlockGlobal`, which preserves the same edit/save boundary while returning the previous block for counted drop insertion.
- `World.SetBlockGlobal` persists the edited chunk only when `World` was created with a `ChunkStore`.
- `World.ReplaceBlockGlobal` is the atomic previous-block-returning variant used by session destroy handling; `World.SetBlockGlobal` wraps it for existing callers.
- `World.SetBlockGlobal` rejects block edits outside `[0, ChunkHeight)` before creating/loading a chunk or returning an updated snapshot.
- `server/cmd/server/main.go` creates the default server with `storage.OpenRocksChunkStore`, so normal server runs are persistence-capable.
- `server/cmd/server/main.go` passes that same store to `network.NewServerWithPlayerInventoryStore`, so local-player inventory records use RocksDB without changing chunk keys or chunk payload bytes.
- `scripts/player_inventory_reconnect_smoke.sh` starts the real Go server with an isolated RocksDB store, selects a local-player inventory slot over TCP, restarts the server, reconnects, and requires the persisted selected slot to arrive in an `InventorySnapshot`.
- Block 40 consumes save -> process restart -> reload -> visual/collision/GPU update proof from Block 41 instead of duplicating that heavier runtime matrix.

## Deferred Work

Still needed before calling gameplay production-ready:

- Tool durability and client-visible tool selection.
- Item entity pickup flow.
- Stack transfer and crafting inventory actions.
- Edit broadcast/fanout to other clients.
- Broader dirty chunk save/reload coverage beyond the Block 41 persisted visual smoke.
- Mass edit, chunk edge, collision, and GPU dirty scalability from Block 42.

## Compatibility Rules

- Keep `Packet.inventory_snapshot = 4` as the server-to-client inventory snapshot payload.
- Keep `Packet.inventory_action = 5` as the client-to-server selected-slot inventory action payload.
- Keep `scripts/inventory_protocol_compatibility_gate.sh` clean after inventory schema work.
- Keep player inventory persistence on the documented RocksDB player-inventory record format.
- Do not bypass `World.SetBlockGlobal` or `World.ReplaceBlockGlobal` for persistent block edits.
- Do not allow client-only block IDs through `BlockAction`.
- Do not decrement creative hotbar or server creative inventory counts in this checkpoint.
- Do not change world generation or chunk serialization for gameplay foundation work.

## Block 40 Gate

Use:

```sh
sh scripts/player_inventory_reconnect_smoke.sh logs/player_inventory_reconnect_smoke_current
sh scripts/item_tool_foundation_gate.sh logs/item_tool_foundation_current
sh scripts/gameplay_loop_foundation_gate.sh logs/gameplay_loop_foundation_current
sh scripts/inventory_protocol_compatibility_gate.sh logs/inventory_protocol_compatibility_current
```

The expected current result is `status=pass`, `gameplay_loop_status=foundation_guarded`, `inventory_foundation=unit_guarded`, `hotbar_selection=unit_guarded`, `inventory_hud=authoritative_guarded`, `server_inventory_status=session_guarded`, `server_inventory_block_action=session_guarded`, `server_inventory_persistence=rocksdb_guarded`, `mining_rules_status=cooldown_guarded`, `mining_cooldown=server_guarded`, `mining_block_durations=target_block_guarded`, `item_tool_foundation=server_guarded`, `item_identity=block_items_guarded`, `tool_catalog=wood_tools_guarded`, `first_tool_slot=hand_guarded`, `tool_mining=selected_tool_guarded`, `player_inventory_reconnect=live_server_guarded`, `player_inventory_reconnect_status=pass`, `player_inventory_reconnect_restarts>=1`, `server_edit_persistence=store_save_boundary`, `active_protocol_change=0`, `full_reload_persistence=block_41_visual_guarded`, `block_edit_persistence_status=pass`, `block_edit_visual_path=godot_persisted_reload_guarded`, `block_edit_persisted_visual_smoke=godot_guarded`, `block_edit_persisted_visual_smoke_status=pass`, `block_edit_persisted_visual_scenarios=3`, `block_edit_persisted_visual_place_reload_status=pass`, `block_edit_persisted_visual_destroy_after_reload_status=pass`, `block_edit_persisted_visual_edge_place_status=pass`, and `block_edit_active_protocol_change=0`.

The gate checks that:

- This document records mining/building flow, inventory foundation, persistence boundary, deferred work, and compatibility rules.
- The player source contains the hotbar inventory model, selected slot state, selected-slot signal, selection helpers, and tests.
- The client source contains selected-slot inventory action send coverage, local player-id position packet coverage, authoritative inventory HUD getter coverage, and authoritative inventory formatting tests.
- The HUD source reads authoritative inventory slot text, selected slot, selected block, and summary text from `GameClient`.
- The server inventory foundation summary is present and clean.
- The server inventory foundation summary includes counted break-drop live evidence.
- The mining rules foundation summary is present and proves counted/survival server cooldown plus target-block duration enforcement without protocol drift.
- The item tool foundation summary is present and proves server-owned item identity, first hand tool slot, wooden tool catalog, selected-tool mining adjustment, and no protocol/storage/worldgen drift.
- The player inventory reconnect smoke summary is present and proves selected-slot persistence after a real server restart.
- Server block edits still flow through `World.SetBlockGlobal` or `World.ReplaceBlockGlobal`.
- `World.SetBlockGlobal` still calls `ChunkStore.SaveChunk`.
- The Block 41 block-edit persistence summary is present and its persisted visual/collision/GPU matrix is clean.
- Previous client state-machine hardening is clean.
- Focused Rust inventory tests and Go world/network/storage tests pass.
- Protocol schema/generated files are unchanged.

## Current Status

This block is complete as a gameplay foundation checkpoint and now requires the completed Block 41 dirty chunk save/reload plus visual/collision/GPU proof. The selected hotbar slot is guarded as explicit player state alongside the selected block ID, local-player inventory state persists through RocksDB with live TCP reconnect/restart evidence, counted break-drop insertion is guarded through a real server restart, counted/survival mining cooldown and target-block durations are guarded on the server, the first server-owned item/tool catalog is guarded with selected-tool mining adjustment, server-side placement rejects blocks that intersect the player body, and the Godot HUD displays authoritative inventory labels/counts from the latest server snapshot. Broader gameplay systems still remain outside this foundation checkpoint.
