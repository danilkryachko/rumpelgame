# Agent Memory

This file stores stable project decisions and invariants for agents. Keep it short and factual.

## Project Decisions

- The approved project databases are PostgreSQL and RocksDB.
- Do not introduce, expand, or migrate to another database engine without explicit approval.

## Sensitive Areas

- Client/server protocol compatibility matters.
- World generation and chunk serialization must remain deterministic unless explicitly changed.
- Storage and persistence changes require extra review before finalizing.
- Rust GDExtension changes can affect client behavior and performance; review them carefully.
- Godot scene/resource/import files should not be reformatted casually.

## Agent Roles

- Research agents are read-only and should return concise findings with file paths.
- Review agents look for risks, regressions, missing tests, and code degradation.
- Protocol/world review is required for networking, storage, world generation, chunk serialization, persistence, or Rust extension changes.
- The main agent decides what to change and remains responsible for the final patch.
