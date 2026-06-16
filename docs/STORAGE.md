# Storage

## Approved Databases

- PostgreSQL
- RocksDB

Do not introduce, expand, or migrate to another database engine without explicit approval.

## Rules

- Preserve persistence compatibility unless the task explicitly changes it.
- Do not silently change chunk serialization, key formats, schema layout, migrations, or save data behavior.
- Storage changes require a review pass before finalizing.
- Add or update the smallest relevant round-trip test when changing storage behavior.
- Keep generated data directories, local database files, and build artifacts out of commits.

## Current Notes

- RocksDB-backed chunk storage lives under `server/pkg/storage`.
- RocksDB chunk keys use a `c` byte prefix followed by sortable big-endian signed `int32` `x` and `z` coordinates. Preserve this key format unless a migration is explicitly planned.
- Persisted chunk payloads use the exact byte output of `world.Chunk.Serialize()` and must match the current serialized chunk size when loaded.
- RocksDB path/config behavior is guarded: empty RocksDB chunk store paths are rejected before the C API, missing parent directories are created, and existing regular-file parent/database paths are rejected.
- RocksDB concurrent access is guarded for distinct chunk keys: concurrent save/load operations on one open store must preserve each chunk payload.
- RocksDB open/read/write/decode errors include path or chunk-coordinate context so failures are actionable from logs and test output.
- RocksDB lifecycle behavior is guarded: double close is safe, operations after close return Go errors, and nil chunk saves are rejected before reaching the C API.
- Security review gates scan runtime source areas for unapproved database engine references; PostgreSQL and RocksDB remain the only approved project databases.
- PostgreSQL is approved for project storage, but its exact project role should be documented when implemented or changed.
- Current RocksDB persistence foundation coverage is documented in `docs/STORAGE_PERSISTENCE_FOUNDATION.md`.

## Ownership Boundary

- RocksDB owns current server chunk persistence.
- `server/cmd/server/main.go` opens `storage.OpenRocksChunkStore(defaultRocksDBPath())` and passes that store to `world.NewWorld`.
- `RUMPELMC_SERVER_ROCKSDB_PATH` is the only current runtime chunk-store path override.
- PostgreSQL is approved by project policy, but no PostgreSQL runtime chunk persistence path, connection string, schema, migration, or fallback exists yet.
- Adding PostgreSQL-backed persistence requires a separate storage design, migration/compatibility plan, and tests before any runtime backend switch.
