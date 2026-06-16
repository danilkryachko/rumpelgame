# Storage Persistence Foundation

Date: 2026-06-16

This note records the current approved persistence foundation for chunk storage.

## Current Contract

- RocksDB is the implemented chunk persistence backend.
- PostgreSQL remains approved by project policy, but no PostgreSQL chunk persistence path is implemented in this slice.
- `RUMPELMC_SERVER_ROCKSDB_PATH` is the only current runtime chunk-store path override; PostgreSQL environment variables do not select a chunk backend.
- RocksDB chunk keys keep the existing `c` prefix plus sortable big-endian signed `int32` `x` and `z` coordinates.
- RocksDB chunk values are the exact bytes from `world.Chunk.Serialize()`.
- Missing chunks return `(nil, false, nil)`.
- Corrupt persisted chunk bytes return an error and do not produce a loaded chunk.
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
cd server
go test ./pkg/storage
```

Fresh check:

- `go test ./pkg/storage` and `go test -race ./pkg/storage` passed on 2026-06-16 after adding RocksDB empty-path, closed-store, and nil-save lifecycle coverage.
