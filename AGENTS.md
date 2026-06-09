# Agent Instructions

## Core Rules

- Work incrementally: first study the existing code and local patterns.
- Preserve the current architecture, naming, formatting, and style.
- Change only the minimum necessary places.
- Do not rewrite whole files unless it is necessary.
- Keep changes scoped to the user's request.
- Do not refactor unrelated code.
- Do not introduce new frameworks, dependencies, formats, or architecture without approval.
- Do not remove existing functionality unless explicitly requested.
- Do not simplify code by deleting edge cases, validation, logging, errors, tests, or comments that carry intent.

## Required Context

- Read `docs/ARCHITECTURE.md` before design changes.
- Read `docs/AGENT_MEMORY.md` before architectural, storage, networking, world generation, chunk serialization, persistence, or Rust extension changes.
- Read `docs/STORAGE.md` before storage or persistence changes.
- Read `docs/PROTOCOL.md` before client/server protocol or packet schema changes.
- Read `docs/CODE_REVIEW.md` before review passes or sensitive changes.

## Sensitive Areas

- Client/server protocol compatibility matters.
- PostgreSQL and RocksDB are the approved project databases. Do not introduce or expand other database engines without explicit approval.
- World generation and chunk serialization must remain deterministic unless explicitly changed.
- Godot scene/resource/import files should not be reformatted casually.
- Generated files must not be hand-edited.

## Checks

- Run the narrowest relevant check for small changes.
- Run `./scripts/check.sh fast` for normal code changes.
- Run `./scripts/check.sh full` for broad changes or before handing off a larger patch.
- Run `./scripts/diff_guard.sh` before finishing broad or sensitive changes.

## Review And Subagents

- Use research subagents only for read-only exploration.
- Use review subagents to find risks, not to rewrite code.
- Run a review pass before finalizing storage, networking, world generation, chunk serialization, persistence, or Rust extension changes.
- If a task changes more than 5 files or more than 300 lines, stop and explain why before continuing.
- Update `docs/AGENT_MEMORY.md` only with stable project decisions and invariants, not temporary task notes.
