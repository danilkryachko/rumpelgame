# Code Review

Use this checklist for review passes and sensitive changes.

## Priorities

- Find regressions, correctness bugs, missing tests, security issues, and code degradation.
- Prefer concrete findings with file paths and line references.
- Do not rewrite code during a review pass unless the user explicitly asks for fixes.
- Treat compatibility issues as high risk in protocol, storage, persistence, world generation, chunk serialization, and Rust GDExtension code.

## Check For

- Unrelated refactors or whole-file rewrites.
- Removed validation, error handling, logging, tests, or intent-bearing comments.
- New abstractions that do not match existing local patterns.
- Hand edits to generated files.
- Casual changes to Godot `.tscn`, `.uid`, `.import`, or resource files.
- Persistence format changes without migration or compatibility notes.
- Protocol changes without matching client and server updates.
- Missing round-trip, determinism, or compatibility tests for sensitive behavior.

## Before Finalizing Sensitive Changes

- Run `./scripts/diff_guard.sh`.
- Run `./scripts/check.sh full` when the local toolchain is available.
- Report what was checked, what was not checked, and any risky assumption.
