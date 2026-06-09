# AI Guidelines

These rules are for AI-assisted development in this repository. Keep them concrete and update them only when repeated agent behavior needs correction.

## Scope Control

- Prefer existing module boundaries. Add a new package, module, crate, or abstraction only when it removes real complexity or matches an existing local pattern.
- Keep patches focused on the requested task.
- Do not refactor unrelated code.
- Do not rewrite whole files when a small patch is enough.

## Required Docs

- Read `docs/ARCHITECTURE.md` before design changes.
- Read `docs/STORAGE.md` before storage or persistence changes.
- Read `docs/PROTOCOL.md` before protocol or packet schema changes.
- Read `docs/CODE_REVIEW.md` before review passes and sensitive changes.
- Use `docs/AGENT_MEMORY.md` only for stable project decisions and invariants.

## Checks

- Run `./scripts/check.sh fast` for normal code changes.
- Run `./scripts/check.sh full` for broad changes or before handing off a larger patch.
- Run `./scripts/diff_guard.sh` before finalizing broad or sensitive changes.

## Sensitive Changes

- PostgreSQL and RocksDB are the approved databases.
- Storage, networking, world generation, chunk serialization, persistence, and Rust GDExtension changes require a review pass before finalizing.
- Protocol changes must account for both client and server behavior.
- Generated files, Godot import files, and local database files should not be changed casually.
