# Agent Instructions

## Defaults

- Communicate with the user in Russian unless the user explicitly asks for another language.
- Work incrementally: inspect the directly relevant files and local patterns before editing.
- Preserve the current architecture, naming, formatting, and style.
- Keep changes scoped to the user's request and change the minimum necessary places.
- Do not refactor unrelated code or introduce new frameworks, dependencies, formats, or architecture without approval.
- Do not remove existing functionality, validation, logging, errors, tests, or intent-carrying comments unless explicitly requested.
- Do not casually reformat Godot scene/resource/import files, and do not hand-edit generated files.

## Planning And Context

- Use `docs/AI_TASK_TEMPLATE.md` for large, ambiguous, multi-layer, or feature-style requests; skip it for narrow fixes, config edits, and obvious small changes.
- Use `docs/NEXT_STEP_WORKFLOW.md` for planning questions such as "what next?", "what should we improve?", or "where should development go now?".
- Read `docs/HANDOFF.md` and `docs/AGENT_HANDOFF.md` before resuming work from another chat, after a long interruption, or before handing off non-trivial work.
- Use research subagents only for read-only exploration. Use review subagents to find risks, not to rewrite code.

## Area-Specific Docs

Read the matching docs before changing these areas:

- Design or architecture changes: `docs/ARCHITECTURE.md`
- Architecture, storage, networking, world generation, chunk serialization, persistence, or Rust extension changes: `docs/AGENT_MEMORY.md`
- GPU terrain, renderer, profiling, or performance optimization: `docs/GPU_ROADMAP.md`, `docs/GPU_PROFILING.md`, `docs/GPU_TRENDS.md`
- Storage or persistence: `docs/STORAGE.md`
- Client/server protocol or packet schema: `docs/PROTOCOL.md`
- Review passes or sensitive changes: `docs/CODE_REVIEW.md`
- OntoIndex graph navigation: `docs/ONTOINDEX.md`

## Sensitive Areas

- Client/server protocol compatibility matters.
- PostgreSQL and RocksDB are the approved project databases; do not introduce or expand other database engines without explicit approval.
- World generation and chunk serialization must remain deterministic unless explicitly changed.
- Performance optimization must not reduce draw distance, lighting, shadows, texture quality, or other visible quality unless explicitly requested.

## Checks

- Run the narrowest relevant check for the change.
- Run `./scripts/check.sh fast` for normal code changes.
- Run `./scripts/check.sh full` for broad changes or before handing off a larger patch.
- Run `./scripts/diff_guard.sh` before finishing broad or sensitive changes.
- For docs/config-only changes, prefer syntax or diff checks over the full project suite.
- Run `./scripts/handoff.sh` to collect a continuation snapshot before delegating or resuming another chat's work.
- Rust checks use optional `sccache`; see `docs/BUILD_CACHE.md`.

## Code Navigation

- Prefer `rg` for exact text/file search.
- For broad or ambiguous code searches, start with `bash ./scripts/agent_search.sh query "..."`; use `bash ./scripts/agent_search.sh symbol "..."` once a likely symbol is known. See `docs/AGENT_CODE_SEARCH.md`.
- Use OntoIndex for graph questions, impact checks, and broad orientation when it is installed and indexed.
- Run OntoIndex through `bash ./scripts/ontoindex.sh`; do not run raw `ontoindex setup` or `ontoindex analyze` without explicit approval.
- When indexing, keep `--skip-agents-md --no-stats` so OntoIndex does not rewrite project agent rules.
- Treat OntoIndex failures as non-blocking and fall back to `rg`, project docs, tests, and review passes.
