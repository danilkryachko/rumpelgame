# Storage Persistence Foundation

Date: 2026-06-16

This note records the current approved persistence foundation for chunk storage and local-player inventory state.

## Current Contract

- RocksDB is the implemented chunk persistence backend.
- PostgreSQL remains approved by project policy, but no PostgreSQL chunk persistence path is implemented in this slice.
- `RUMPELMC_SERVER_ROCKSDB_PATH` is the only current runtime chunk-store path override; PostgreSQL environment variables do not select a chunk backend.
- RocksDB chunk keys keep the existing `c` prefix plus sortable big-endian signed `int32` `x` and `z` coordinates.
- RocksDB chunk values are the exact bytes from `world.Chunk.Serialize()`.
- RocksDB player inventory keys use a separate `p i NUL` prefix plus a bounded player id, so player records cannot collide with chunk keys.
- RocksDB player inventory values are JSON version `1` records containing placement policy, selected slot, and ordered `{block_id, count}` slots.
- Missing chunks return `(nil, false, nil)`.
- Missing player inventory records return `(zero state, false, nil)` and let the server create the current creative hotbar record for valid local-player ids.
- Corrupt persisted chunk bytes return an error and do not produce a loaded chunk.
- Corrupt player inventory records return an error and do not produce a loaded state.
- Saving a chunk overwrites only that chunk key and must not alter neighboring chunk keys.
- Opening a RocksDB store with an empty path fails before the C API boundary and does not return a usable store.
- Opening a RocksDB store creates a missing parent directory for the configured path.
- Opening a RocksDB store below an existing regular-file parent path fails and does not return a usable store.
- Opening a RocksDB store on an existing regular file fails and does not return a usable store.
- Concurrent save/load operations on distinct chunk keys through one open RocksDB store preserve each chunk payload.
- RocksDB open errors include the configured path, and corrupt chunk decode errors include the affected chunk coordinates.
- RocksDB store lifecycle is guarded: repeated `Close()` calls are safe, `LoadChunk`/`SaveChunk` after close return closed-store errors, and `SaveChunk(nil)` is rejected before the C API boundary.

## Guard

Run the focused guard with:

```sh
sh scripts/storage_package_smoke.sh logs/storage_package_smoke_current
```

Fresh check:

- `go test ./pkg/storage` covers chunk storage plus player inventory round-trip, key separation, corrupt player inventory rejection, and empty player id rejection.
- `sh scripts/storage_package_smoke.sh logs/storage_package_smoke_current`, `go test ./pkg/storage`, and `go test -race ./pkg/storage` passed on 2026-06-16 after adding RocksDB empty-path, file-parent failure, closed-store, and nil-save lifecycle coverage.
