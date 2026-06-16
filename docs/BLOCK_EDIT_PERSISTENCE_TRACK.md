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
- Add a dedicated Godot visual reload smoke matrix that proves placed, destroyed-after-reload, and chunk-edge persisted edits through server restart, then validates the restarted server's bootstrap chunk through screenshot, collision, and GPU markers.

Out of scope:

- No protocol change, storage key change, chunk byte migration, new dirty packet, delta packet, edit journal, inventory persistence, multiplayer broadcast, background save queue, Godot scene/resource/import change, renderer behavior change, or new database engine.

Assumptions:

- A block edit is reliable only if it passes through `World.SetBlockGlobal`.
- `ChunkStore.SaveChunk` persists the exact `Chunk.Serialize()` bytes.
- Reloading a dirty edit through `World.ChunkSnapshot` sends the same full chunk snapshot path used for generated chunks.
- The Rust client already treats edited/reloaded snapshots as chunk replacements and runs the existing dirty update, mesh, collision, and GPU queue path.
- The server-side persisted reload smoke proves the exact block value; the Godot persisted visual smoke matrix proves the reloaded chunk reaches the visual/collision/GPU path after process restart for place, destroy-after-reload, and chunk-edge edits.

Done when:

- Unit evidence proves place and destroy edits survive a new `World(store)` load.
- A block-edit persistence gate runs focused world/storage/network/Rust update-path checks and records live restart/reload plus persisted visual smoke status.

Checks:

- `sh scripts/block_edit_persistence_gate.sh logs/block_edit_persistence_current`
- `RUMPELMC_BLOCK_EDIT_PERSISTENCE_RUN_PERSISTED_VISUAL_SMOKE=1 sh scripts/block_edit_persistence_gate.sh logs/block_edit_persistence_current`

## Persistence Contract

- `BlockAction_PLACE` and `BlockAction_DESTROY` are applied by `server/pkg/network` through `World.SetBlockGlobal`.
- `World.SetBlockGlobal` rejects block edits with `Y` outside `[0, ChunkHeight)` before chunk load/create/save, maps valid global block coordinates to chunk/local coordinates, updates the chunk, then calls `ChunkStore.SaveChunk` if a store exists.
- If `ChunkStore.SaveChunk` fails, `World.SetBlockGlobal` rolls the in-memory block value back before returning the save error.
- `ChunkStore.SaveChunk` persists serialized chunk bytes, not block diffs.
- `World.getOrCreateLocked` checks `ChunkStore.LoadChunk` before generating a fresh flat chunk.
- `World.getOrCreateLocked` propagates `ChunkStore.LoadChunk` errors and must not silently regenerate a flat chunk over a failed persisted load.
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

`TestSetBlockGlobalRejectsOutOfRangeYWithoutSave` proves invalid block heights fail before any serialized chunk save or stored chunk entry is created. The paired network test `TestHandleClientPacketRejectsOutOfRangeBlockAction` proves that the server handler returns an error and emits no updated chunk frame to the editor or interested clients.

`TestSetBlockGlobalPersistsNegativeBoundaryCoordinates` proves valid edits at negative global chunk boundaries persist and reload from the expected chunk/local coordinates.

`TestChunkSnapshotPropagatesStoreLoadErrorWithoutRegenerating` proves corrupt stored chunk bytes surface as a `ChunkSnapshot` error instead of being replaced with a newly generated flat chunk. After the bad stored bytes are removed, the same world can generate the chunk normally, proving the failed load did not cache replacement state.

`TestSetBlockGlobalRollsBackInMemoryBlockOnSaveError` proves a failed chunk save does not leak an unpersisted edit into the authoritative in-memory snapshot. The test first persists `Wood`, forces a later `SaveChunk` failure for `Dirt`, then verifies both the same `World` and a fresh `World(store)` still expose `Wood`.

## Live Restart/Reload Smoke

`scripts/server_persisted_reload_smoke.sh` is the runtime persistence proof for the server process boundary:

- Start the Go server with an isolated RocksDB path.
- Send a live `BlockAction_PLACE` for block `1,64,1` and require the updated chunk to contain `Wood`.
- Stop the server, start a new server process against the same RocksDB path, and require the bootstrap chunk to still contain `Wood`.
- Send a live `BlockAction_DESTROY`, require the updated chunk to contain `Air`, then restart again and require the bootstrap chunk to still contain `Air`.

This validates edit -> save -> process restart/reopen -> normal chunk snapshot without changing protocol, chunk serialization, storage keys, or client rendering behavior.

## Visual/Collision/GPU Update Path

Godot persisted visual smoke proves that persisted block edits reach screenshot, collision, and GPU marker validation after a server restart.

The current client update path for any edited or reloaded chunk snapshot is:

- `GameClient.update_chunk` decodes raw/RLE block payloads to full raw block bytes.
- `chunk_dirty_update` compares previous and current raw chunk bytes.
- `chunk_update_needs_geometry_refresh` decides whether geometry refresh is required.
- Dirty chunk updates enqueue affected subchunks through the full or partial dirty path.
- Collision refresh and GPU upload are driven by the normal mesh queue and collision refresh queue.
- `scripts/gpu_terrain_block_edit_stress.sh` is the current runtime smoke wrapper for same-session visual dirty update, collision, and GPU upload markers.
- `scripts/server_persisted_reload_smoke.sh` verifies that a restarted server sends the persisted edited chunk through the normal snapshot path.
- `scripts/block_edit_persisted_visual_smoke.sh` starts isolated servers on the Godot client's fixed local port and runs `place_reload`, `destroy_after_reload`, and `edge_place` scenarios through `server/cmd/persisted_reload_smoke`, restart/reopen verification, and Godot visual smoke.
- The persisted visual smoke requires `current_chunk_loaded>=1`, `current_chunk_submeshes>=1`, `current_chunk_collision>=1`, `terrain_samples>=1`, `gpu_frames>=1`, `gpu_uploads>=1`, and zero GPU upload failures.

Block 41 now has both live server restart/reload evidence and a heavier Godot persisted-reload screenshot matrix. The Godot smoke intentionally uses the existing full snapshot path and does not add client-side block-id inspection or protocol fields.

## Deferred Work

Still needed:

- Multi-client edit fanout/broadcast.
- Dirty chunk save batching or async save policy.
- Delta packet or subchunk edit packet design, if full chunk snapshots become too expensive.
- Corrupt edit recovery beyond current corrupt-load propagation and malicious edit boundary tests.
- Cross-chunk or non-current-chunk persisted visual coverage beyond the current bootstrap chunk.

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

The expected current result after collecting the live and persisted visual artifacts is `status=pass`, `persistence_status=runtime_guarded`, `place_reload=live_restart_guarded`, `destroy_reload=live_restart_guarded`, `runtime_reload_smoke=live_restart_guarded`, `runtime_reload_smoke_status=pass`, `persisted_visual_smoke=godot_guarded`, `persisted_visual_smoke_status=pass`, `persisted_visual_scenarios=3`, `persisted_visual_place_reload_status=pass`, `persisted_visual_destroy_after_reload_status=pass`, `persisted_visual_edge_place_status=pass`, `visual_collision_gpu_path=godot_persisted_reload_guarded`, `negative_boundary_edits=guarded`, `store_load_errors=propagated_guarded`, `save_failure_rollback=guarded`, and `active_protocol_change=0`.

The gate checks that:

- This document records the persistence contract, added unit guard, update path, deferred work, and compatibility rules.
- `TestSetBlockGlobalPersistsEditedChunkForReload` exists.
- `TestSetBlockGlobalRejectsOutOfRangeYWithoutSave` exists.
- `TestSetBlockGlobalPersistsNegativeBoundaryCoordinates` exists.
- `TestChunkSnapshotPropagatesStoreLoadErrorWithoutRegenerating` exists and is included in the focused world persistence test run.
- `TestSetBlockGlobalRollsBackInMemoryBlockOnSaveError` exists and is included in the focused world persistence test run.
- `World.SetBlockGlobal` still saves through `ChunkStore.SaveChunk`.
- The client still runs edited snapshots through `update_chunk` dirty/collision/GPU queues.
- The live server restart/reload smoke passes, when `RUMPELMC_BLOCK_EDIT_PERSISTENCE_RUN_RUNTIME_RELOAD_SMOKE=1` is enabled or a current summary exists.
- The persisted visual smoke passes, when `RUMPELMC_BLOCK_EDIT_PERSISTENCE_RUN_PERSISTED_VISUAL_SMOKE=1` is enabled or a current summary exists.
- The gameplay foundation gate is clean.
- Focused world, storage, network, and Rust dirty-update tests pass.
- Protocol schema/generated files are unchanged.

## Current Status

This block is complete as a fast persistence proof, negative-boundary edit persistence proof, save-failure rollback proof, persisted load-error propagation proof, live server restart/reload proof, and dedicated Godot persisted-reload visual/collision/GPU screenshot matrix for place, destroy-after-reload, and chunk-edge coordinates. Cross-chunk/non-current-chunk visual coverage remains future work.

Fresh `logs/block_edit_persisted_visual_smoke_current/block-edit-persisted-visual-smoke-summary.txt` evidence reports `status=pass`, `scenarios=3`, `place_reload_status=pass`, `destroy_after_reload_status=pass`, `edge_place_status=pass`, and `protocol_change=0`. Scenario details: `place_reload` reloaded block `1,64,1` as id `4` with `current_chunk_collision=3`, `terrain_samples=288`, `gpu_frames=123`, `gpu_uploads=637`, and `gpu_upload_fail=0`; `destroy_after_reload` reloaded the same coordinate as `Air` with `current_chunk_collision=2`, `gpu_frames=414`, `gpu_uploads=385`, and `gpu_upload_fail=0`; `edge_place` reloaded block `31,64,31` as id `4` with `current_chunk_collision=3`, `gpu_frames=420`, `gpu_uploads=387`, and `gpu_upload_fail=0`.
