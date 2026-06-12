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
- PostgreSQL is approved for project storage, but its exact project role should be documented when implemented or changed.
