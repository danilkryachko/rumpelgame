# Item Entity Persistence

This document records the finished item-entity persistence checkpoint for the gameplay track.

## Technical Brief

Goal:

Persist server-owned item entities through the approved RocksDB backend so a destroyed-block drop that has not been collected survives server restart and can still be picked up through the existing `ItemPickupAction` protocol path.

Scope:

- Add a small `server/pkg/itementity` state DTO shared by the network and storage layers.
- Store the complete item-entity set as one RocksDB JSON record under the separate `i e NUL` key.
- Keep chunk keys, chunk payload bytes, world generation, block IDs, and protobuf packet fields unchanged.
- Load item entities before the TCP listener starts.
- Save item entities after successful destroyed-block spawn and after successful pickup removal.
- Guard RocksDB round-trip, key separation, corrupt payload rejection, duplicate id rejection, non-finite position rejection, and next-id validation with storage tests.
- Guard server load, next-id continuity, destroy persistence, pickup removal persistence, and pickup save-failure rollback with network tests.
- Guard live restart behavior with `scripts/player_item_entity_persistence_smoke.sh`.

Out of scope:

- No protobuf schema change.
- No chunk serialization change.
- No new storage engine.
- No crafting, durability, dropped stack merging, despawn timers, entity physics, or multi-record RocksDB transaction policy in this checkpoint.

## Current Contract

- `itementity.State` contains `NextEntityID`, `Revision`, and a copied list of `itementity.Entity` records.
- `itementity.Entity` contains `EntityID`, stable gameplay `ItemID`, `Count`, and world position `X/Y/Z`.
- `storage.RocksChunkStore.SaveItemEntities()` writes JSON record version `1`.
- `storage.RocksChunkStore.LoadItemEntities()` rejects unsupported versions and structurally invalid records.
- Valid stored entities require nonzero entity ids, unique ids, nonempty bounded item ids, nonzero counts, finite coordinates, and a `NextEntityID` greater than every stored id.
- The storage encoder sorts entities by entity id for deterministic JSON output.
- An empty item-entity set is persisted as a nonempty JSON record with `entities: []`, not by deleting the key.
- Item entity storage is separate from chunk storage and player inventory storage.

## Restart Flow

1. `server/cmd/server/main.go` opens the existing RocksDB store and passes it to `network.NewServerWithPlayerInventoryStore`.
2. `network.NewServerWithPlayerInventoryStore` detects that the same store also implements the item entity store interface.
3. `Server.Start()` calls `loadItemEntitiesFromStore()` before `net.Listen`.
4. Loaded entities are copied into the server runtime map, `itemEntityRevision` is restored, and `nextItemEntityID` resumes from the stored state.
5. New client sessions receive the current `ItemEntitySnapshot` when at least one item entity is loaded.
6. Successful destroy of a placeable previous block adds a server-owned item entity, persists the full item-entity state, then broadcasts the snapshot.
7. Successful pickup validates reach and item-to-block mapping, saves the collected player inventory, persists the full item-entity state without the collected entity, then broadcasts the empty or reduced snapshot and sends the inventory snapshot.
8. If pickup inventory save fails, the runtime inventory and item entity remain unchanged. If item-entity save fails after inventory save, the server restores the runtime entity and writes the previous player inventory state back before returning the error.

## Compatibility Rules

- Do not change `Packet.item_entities = 6` or `Packet.item_pickup = 7` for this checkpoint.
- Do not store item entities inside chunk payloads.
- Do not alter the `c` chunk key prefix or the `p i NUL` player inventory prefix.
- Future item entity fields must be added through a separate compatibility task and protocol tests.
- Future per-entity RocksDB records, despawn policy, dropped stack merge policy, or transactional pickup/inventory writes require a separate storage design.

## Gate

Use:

```sh
sh scripts/player_item_entity_persistence_smoke.sh logs/player_item_entity_persistence_smoke_current
sh scripts/item_entity_persistence_gate.sh logs/item_entity_persistence_current
```

The expected committed result is `status=pass`, `item_entity_persistence=rocksdb_guarded`, `storage_status=json_record_guarded`, `uncollected_drop_restart=live_server_guarded`, `pickup_after_restart=live_server_guarded`, `empty_after_pickup_restart=live_server_guarded`, pickup save-failure rollback tests present, `active_protocol_change=0`, `active_chunk_payload_change=0`, and `go_tests=pass`.

## Current Status

This checkpoint is complete when the storage tests, network tests, live smoke, and gate prove that an uncollected destroyed-block item entity survives restart, can be picked up after restart, persists the collected inventory count, and is absent after the pickup state is restarted.
