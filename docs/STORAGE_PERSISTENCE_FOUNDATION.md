# Storage Persistence Foundation

Date: 2026-06-15

This note records the current approved persistence foundation for chunk storage.

## Current Contract

- RocksDB is the implemented chunk persistence backend.
- PostgreSQL remains approved by project policy, but no PostgreSQL chunk persistence path is implemented in this slice.
- RocksDB chunk keys keep the existing `c` prefix plus sortable big-endian signed `int32` `x` and `z` coordinates.
- RocksDB chunk values are the exact bytes from `world.Chunk.Serialize()`.
- Missing chunks return `(nil, false, nil)`.
- Corrupt persisted chunk bytes return an error and do not produce a loaded chunk.
- Saving a chunk overwrites only that chunk key and must not alter neighboring chunk keys.

## Guard

Run the focused guard with:

```sh
cd server
go test ./pkg/storage
```

Fresh check:

- `go test ./pkg/storage` passed on 2026-06-15 after adding missing-load, overwrite-isolation, and corrupt-payload coverage for the RocksDB chunk store.
