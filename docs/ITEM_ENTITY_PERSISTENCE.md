# Item Entity Persistence

This document records the finished item-entity persistence checkpoint for the gameplay track.

## Technical Brief

Goal:

Persist server-owned item entities through the approved RocksDB backend so a destroyed-block drop that has not been collected survives server restart, nearby same-item drops merge into bounded stacks, expired drops are removed, and live drops can still be picked up through the existing `ItemPickupAction` protocol path.

Scope:

- Add a small `server/pkg/itementity` state DTO shared by the network and storage layers.
- Store the complete item-entity set as one RocksDB JSON version `2` record under the separate `i e NUL` key, while accepting legacy version `1` records without timestamps.
- Keep chunk keys, chunk payload bytes, world generation, block IDs, and protobuf packet fields unchanged.
- Load item entities before the TCP listener starts.
- Save item entities after successful destroyed-block spawn, merge, pickup removal, load-time despawn, and pickup-triggered despawn.
- Guard RocksDB round-trip, legacy record loading, key separation, corrupt payload rejection, duplicate id rejection, non-finite position rejection, count bounds, timestamp validation, and next-id validation with storage tests.
- Guard server load, next-id continuity, destroy persistence, dropped stack merge, stack cap behavior, pickup removal persistence, despawn, and pickup save-failure rollback with network tests.
- Guard live restart behavior with `scripts/player_item_entity_persistence_smoke.sh`.
- Guard live merge/despawn behavior with `scripts/item_entity_policy_smoke.sh`.

Out of scope:

- No protobuf schema change.
- No chunk serialization change.
- No new storage engine.
- No crafting, durability, entity physics, or multi-record RocksDB transaction policy in this checkpoint.

## Current Contract

- `itementity.State` contains `NextEntityID`, `Revision`, and a copied list of `itementity.Entity` records.
- `itementity.Entity` contains `EntityID`, stable gameplay `ItemID`, `Count`, world position `X/Y/Z`, and `SpawnedAtUnixMS`.
- `itementity.MaxEntityStackCount` is `64`. Stored item entity counts must be `1..64`.
- `storage.RocksChunkStore.SaveItemEntities()` writes JSON record version `2`.
- `storage.RocksChunkStore.LoadItemEntities()` accepts version `2` and legacy version `1`, then rejects unsupported versions and structurally invalid records.
- Legacy version `1` entities have `SpawnedAtUnixMS = 0`; the server treats them as freshly loaded instead of immediately expiring them.
- Valid stored entities require nonzero entity ids, unique ids, nonempty bounded item ids, nonzero bounded counts, finite coordinates, nonnegative spawned timestamps, and a `NextEntityID` greater than every stored id.
- The storage encoder sorts entities by entity id for deterministic JSON output.
- An empty item-entity set is persisted as a nonempty JSON record with `entities: []`, not by deleting the key.
- Item entity storage is separate from chunk storage and player inventory storage.

## Dropped Stack Merge And Despawn

- Destroyed placeable blocks still create one block item worth of drop intent.
- Before spawning a new runtime entity, the server prunes expired item entities, then attempts to merge into the nearest same-item entity within radius `1.25`.
- Merge is deterministic: nearest stack wins; exact distance ties choose the lower entity id.
- A stack can merge only when the resulting count stays at or below `64`.
- When no merge target is available, the server allocates the next item entity id and spawns a new stack at the destroyed block center.
- If the runtime item entity map is already at `itementity.MaxStateEntities`, the oldest stack is removed before the new stack is allocated, preserving the bounded full-state record.
- `RUMPELMC_SERVER_ITEM_ENTITY_DESPAWN_MS` controls despawn. The default is `300000` ms; `0` disables despawn for tests or diagnostics.
- Expired entities are pruned on server load, item entity snapshot send, spawn, and pickup handling. There is no background goroutine in this checkpoint.
- Pickup of an expired entity removes and persists the expired entity set, returns the current item entity snapshot, and does not mutate player inventory.
- Spawn, merge, despawn, and pickup mutations are rolled back in memory when item-entity persistence fails.

## Restart Flow

1. `server/cmd/server/main.go` opens the existing RocksDB store and passes it to `network.NewServerWithPlayerInventoryStore`.
2. `network.NewServerWithPlayerInventoryStore` detects that the same store also implements the item entity store interface.
3. `Server.Start()` calls `loadItemEntitiesFromStore()` before `net.Listen`.
4. Loaded entities are copied into the server runtime map, legacy timestamps are treated as fresh load time, `itemEntityRevision` is restored, and `nextItemEntityID` resumes from the stored state.
5. Expired loaded entities are pruned and the reduced state is saved before the listener starts.
6. New client sessions receive the current `ItemEntitySnapshot` when at least one non-expired item entity is loaded.
7. Successful destroy of a placeable previous block prunes expired entities, merges into a nearby same-item stack when possible, otherwise adds a server-owned item entity, persists the full item-entity state, then broadcasts the snapshot.
8. Successful pickup validates reach and item-to-block mapping, saves the collected player inventory, persists the full item-entity state without the collected entity, then broadcasts the empty or reduced snapshot and sends the inventory snapshot.
9. If pickup inventory save fails, the runtime inventory and item entity remain unchanged. If item-entity save fails after inventory save, the server restores the runtime entity and writes the previous player inventory state back before returning the error.

## Compatibility Rules

- Do not change `Packet.item_entities = 6` or `Packet.item_pickup = 7` for this checkpoint.
- Do not store item entities inside chunk payloads.
- Do not alter the `c` chunk key prefix or the `p i NUL` player inventory prefix.
- `Packet.ItemEntity.count` already represents a stack count, so merge/despawn does not require a protobuf schema change.
- Future protobuf item entity fields must be added through a separate compatibility task and protocol tests.
- Future per-entity RocksDB records, transactional pickup/inventory writes, item physics, or client-visible despawn timer fields require a separate storage/protocol design.

## Gate

Use:

```sh
sh scripts/player_item_entity_persistence_smoke.sh logs/player_item_entity_persistence_smoke_current
sh scripts/item_entity_policy_smoke.sh logs/item_entity_policy_current
sh scripts/item_entity_persistence_gate.sh logs/item_entity_persistence_current
```

The expected committed result is `status=pass`, `item_entity_persistence=rocksdb_guarded`, `item_entity_policy=merge_despawn_guarded`, `dropped_stack_merge=live_server_guarded`, `despawn_restart=live_server_guarded`, `storage_status=json_record_guarded`, `uncollected_drop_restart=live_server_guarded`, `pickup_after_restart=live_server_guarded`, `empty_after_pickup_restart=live_server_guarded`, pickup save-failure rollback tests present, `active_protocol_change=0`, `active_chunk_payload_change=0`, and `go_tests=pass`.

## Current Status

This checkpoint is complete when the storage tests, network tests, live smoke, and gate prove that an uncollected destroyed-block item entity survives restart, can be picked up after restart, persists the collected inventory count, is absent after the pickup state is restarted, merges nearby same-item drops into one bounded stack, and despawns expired drops across restart without changing protobuf fields or chunk payload bytes.
