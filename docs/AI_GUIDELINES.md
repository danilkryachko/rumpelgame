# AI Guidelines

These rules are for AI-assisted development in this repository. Keep them concrete and update them only when repeated agent behavior needs correction.

## Scope Control

- Communicate with the user in Russian unless the user explicitly asks for another language.
- Translate plain-language feature requests into a technical brief with `docs/AI_TASK_TEMPLATE.md` before implementation or delegation.
- For "what next?" planning requests, inspect the project and use `docs/NEXT_STEP_WORKFLOW.md` before recommending work.
- Prefer existing module boundaries. Add a new package, module, crate, or abstraction only when it removes real complexity or matches an existing local pattern.
- Keep patches focused on the requested task.
- Do not refactor unrelated code.
- Do not rewrite whole files when a small patch is enough.

## Required Docs

- Use `docs/AI_TASK_TEMPLATE.md` for large, ambiguous, or multi-layer tasks.
- Use `docs/NEXT_STEP_WORKFLOW.md` for current-state planning and prioritization.
- Use `docs/HANDOFF.md` and `docs/AGENT_HANDOFF.md` when resuming, pausing, or delegating work across chats.
- Read `docs/ARCHITECTURE.md` before design changes.
- Read `docs/STORAGE.md` before storage or persistence changes.
- Read `docs/PROTOCOL.md` before protocol or packet schema changes.
- Read `docs/CODE_REVIEW.md` before review passes and sensitive changes.
- Use `docs/AGENT_MEMORY.md` only for stable project decisions and invariants.

## Checks

- Run `./scripts/check.sh fast` for normal code changes.
- Run `./scripts/check.sh full` for broad changes or before handing off a larger patch.
- Run `./scripts/diff_guard.sh` before finalizing broad or sensitive changes.
- Run `./scripts/handoff.sh` to collect current continuation context for another agent.
- Rust checks use optional `sccache`; see `docs/BUILD_CACHE.md`.

## Sensitive Changes

- PostgreSQL and RocksDB are the approved databases.
- Storage, networking, world generation, chunk serialization, persistence, and Rust GDExtension changes require a review pass before finalizing.
- Protocol changes must account for both client and server behavior.
- Performance optimization must preserve draw distance, lighting, shadows, texture quality, and visible quality unless the user explicitly requests a quality tradeoff.
- Generated files, Godot import files, and local database files should not be changed casually.
