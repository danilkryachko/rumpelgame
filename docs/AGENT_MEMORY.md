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
- Client startup readiness telemetry is split into one-shot wall-clock timestamps `startup_chunk_packet_ms`, `startup_chunk_inserted_ms`, `startup_chunk_loaded_ms`, `startup_mesh_queued_ms`, `startup_mesh_dispatched_ms`, `startup_first_mesh_ms`, `startup_collision_ms`, and `startup_player_spawn_ms`; movement gates should preserve that nondecreasing order and keep `startup_packet_read_work_ms`, `startup_packet_decode_work_ms`, `startup_packet_reader_elapsed_ms`, `startup_packet_queue_lag_ms`, `startup_chunk_decode_work_ms`, `startup_first_mesh_work_ms`, `startup_first_mesh_phase_ms`, and `startup_first_mesh_collision_work_ms` as work-duration/scheduling evidence separate from wall-clock startup timestamps.
- GPU terrain render shader assumptions matter: vertex code computes terrain lighting from packed face normals and lighting push constants, fragment code applies the passed lighting to atlas color with opaque alpha, perf markers expose the sanitized `gpu_light_*` values, and scene depth uses reverse-Z `GREATER_OR_EQUAL`.
- Godot scene/resource/import files should not be reformatted casually.

## Agent Roles

- Research agents are read-only and should return concise findings with file paths.
- Review agents look for risks, regressions, missing tests, and code degradation.
- Protocol/world review is required for networking, storage, world generation, chunk serialization, persistence, or Rust extension changes.
- The main agent decides what to change and remains responsible for the final patch.
