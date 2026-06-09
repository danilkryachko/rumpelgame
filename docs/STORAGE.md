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
- PostgreSQL is approved for project storage, but its exact project role should be documented when implemented or changed.
