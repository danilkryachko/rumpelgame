# Block Edit Persistence Track

Block 41, Block Edit Persistence Track, proves the fast storage boundary for dirty block edits and defines the remaining runtime reload evidence needed for visual, collision, and GPU update confidence.

## Technical Brief

User request:

Continue the annual world streaming architecture plan in order and use MCP/OntoIndex context.

Goal:

Make the block edit persistence path reliable enough to build on: dirty chunk edit -> save -> new world reload -> normal chunk snapshot, while keeping protocol, chunk serialization, and client render behavior unchanged.

Context inspected:

- OntoIndex concept search for block edit persistence, dirty chunks, save, reload, visual/collision/GPU update, `SetBlockGlobal`, `ChunkStore`, RocksDB, and tests.
- `docs/STORAGE.md`.
- `docs/STORAGE_PERSISTENCE_FOUNDATION.md`.
- `docs/GAMEPLAY_LOOP_FOUNDATION.md`.
- `server/pkg/world/world.go` chunk store boundary.
- `server/pkg/world/world_test.go` world-level tests.
- `server/pkg/storage/rocksdb_test.go` RocksDB round-trip and corruption tests.
- `client/rust_ext/src/lib.rs` chunk replacement, dirty update, collision refresh, and GPU upload path.
- `scripts/gpu_terrain_block_edit_stress.sh` block edit runtime smoke wrapper.
- `scripts/server_persisted_reload_smoke.sh` live server restart/reload wrapper.

Scope:

- Add a world-level unit test proving `SetBlockGlobal` persists an edited chunk through the configured `ChunkStore`.
- In the same test, prove a new `World(store)` reloads the placed block, then reloads the destroyed block after a follow-up edit.
- Add a live server restart/reload smoke that reuses one RocksDB path across separate server processes.
- Record the current client visual/collision/GPU update path for reloaded edited chunks.
- Keep dedicated Godot visual reload smoke deferred unless a separate heavy run is requested.

Out of scope:

- No protocol change, storage key change, chunk byte migration, new dirty packet, delta packet, edit journal, inventory persistence, multiplayer broadcast, background save queue, Godot scene/resource/import change, renderer behavior change, or new database engine.

Assumptions:

- A block edit is reliable only if it passes through `World.SetBlockGlobal`.
- `ChunkStore.SaveChunk` persists the exact `Chunk.Serialize()` bytes.
- Reloading a dirty edit through `World.ChunkSnapshot` sends the same full chunk snapshot path used for generated chunks.
- The Rust client already treats edited/reloaded snapshots as chunk replacements and runs the existing dirty update, mesh, collision, and GPU queue path.
- Full visual verification still requires a Godot smoke that restarts or reopens server state after the edit.

Done when:

- Unit evidence proves place and destroy edits survive a new `World(store)` load.
- A block-edit persistence gate runs focused world/storage/network/Rust update-path checks and records live restart/reload smoke status.

Checks:

- `sh scripts/block_edit_persistence_gate.sh logs/block_edit_persistence_current`

## Persistence Contract

- `BlockAction_PLACE` and `BlockAction_DESTROY` are applied by `server/pkg/network` through `World.SetBlockGlobal`.
- `World.SetBlockGlobal` maps global block coordinates to chunk/local coordinates, updates the chunk, then calls `ChunkStore.SaveChunk` if a store exists.
- `ChunkStore.SaveChunk` persists serialized chunk bytes, not block diffs.
- `World.getOrCreateLocked` checks `ChunkStore.LoadChunk` before generating a fresh flat chunk.
- `World.ChunkSnapshot` serializes the loaded edited chunk and returns the full snapshot to the network layer.
- The current protocol still sends full chunk snapshots; delta packets remain future protocol work.

## Added Unit Guard

`TestSetBlockGlobalPersistsEditedChunkForReload` uses an in-memory serialized `ChunkStore` test double:

- Place `Wood` at a global coordinate crossing chunk boundaries.
- Assert `SaveChunk` was called once.
- Create a new `World(store)` and assert `ChunkSnapshot` reloads the placed block.
- Destroy the same block back to `Air`.
- Assert `SaveChunk` was called again.
- Create another new `World(store)` and assert `ChunkSnapshot` reloads the destroyed block.

This proves the storage boundary without depending on RocksDB process state or a Godot runtime.

## Live Restart/Reload Smoke

`scripts/server_persisted_reload_smoke.sh` is the runtime persistence proof for the server process boundary:

- Start the Go server with an isolated RocksDB path.
- Send a live `BlockAction_PLACE` for block `1,64,1` and require the updated chunk to contain `Wood`.
- Stop the server, start a new server process against the same RocksDB path, and require the bootstrap chunk to still contain `Wood`.
- Send a live `BlockAction_DESTROY`, require the updated chunk to contain `Air`, then restart again and require the bootstrap chunk to still contain `Air`.

This validates edit -> save -> process restart/reopen -> normal chunk snapshot without changing protocol, chunk serialization, storage keys, or client rendering behavior.

## Visual/Collision/GPU Update Path

The current client update path for any edited or reloaded chunk snapshot is:

- `GameClient.update_chunk` decodes raw/RLE block payloads to full raw block bytes.
- `chunk_dirty_update` compares previous and current raw chunk bytes.
- `chunk_update_needs_geometry_refresh` decides whether geometry refresh is required.
- Dirty chunk updates enqueue affected subchunks through the full or partial dirty path.
- Collision refresh and GPU upload are driven by the normal mesh queue and collision refresh queue.
- `scripts/gpu_terrain_block_edit_stress.sh` is the current runtime smoke wrapper for same-session visual dirty update, collision, and GPU upload markers.
- `scripts/server_persisted_reload_smoke.sh` verifies that a restarted server sends the persisted edited chunk through the normal snapshot path.

Block 41 now has live server restart/reload evidence. A dedicated restart/reload Godot visual smoke remains a heavier future gate if visual parity after process restart needs direct screenshot evidence.

## Deferred Work

Still needed:

- Runtime edit -> server restart/reopen -> client reload visual smoke with screenshot evidence.
- Collision and GPU marker assertions after an actual Godot persisted reload, not just same-session replacement.
- Multi-client edit fanout/broadcast.
- Dirty chunk save batching or async save policy.
- Delta packet or subchunk edit packet design, if full chunk snapshots become too expensive.
- Corrupt edit recovery and malicious edit boundary tests.

## Compatibility Rules

- Do not change the RocksDB key format or chunk value bytes.
- Do not add new packet fields or delta packets in this checkpoint.
- Do not bypass `World.SetBlockGlobal` for persistent edits.
- Do not change `Chunk.Serialize()` order or size.
- Do not add another database engine.
- Do not reduce collision, shadow, texture, draw-distance, or GPU quality for edit persistence.

## Block 41 Gate

Use:

```sh
sh scripts/block_edit_persistence_gate.sh logs/block_edit_persistence_current
```

The expected current result after collecting the live artifact is `status=pass`, `persistence_status=runtime_guarded`, `place_reload=live_restart_guarded`, `destroy_reload=live_restart_guarded`, `runtime_reload_smoke=live_restart_guarded`, `runtime_reload_smoke_status=pass`, `visual_collision_gpu_path=existing_update_chunk_path`, and `active_protocol_change=0`.

The gate checks that:

- This document records the persistence contract, added unit guard, update path, deferred work, and compatibility rules.
- `TestSetBlockGlobalPersistsEditedChunkForReload` exists.
- `World.SetBlockGlobal` still saves through `ChunkStore.SaveChunk`.
- The client still runs edited snapshots through `update_chunk` dirty/collision/GPU queues.
- The live server restart/reload smoke passes, when `RUMPELMC_BLOCK_EDIT_PERSISTENCE_RUN_RUNTIME_RELOAD_SMOKE=1` is enabled or a current summary exists.
- The gameplay foundation gate is clean.
- Focused world, storage, network, and Rust dirty-update tests pass.
- Protocol schema/generated files are unchanged.

## Current Status

This block is complete as a fast persistence proof plus live server restart/reload proof. Dedicated Godot persisted-reload visual/collision/GPU screenshot evidence remains future work.
