# World Generation Quality Pass

Block 36, World Generation Quality Pass, defines the safe path for improving terrain shape, caves, resources, and structures as deterministic generation layers.

## Technical Brief

User request:

Continue the annual world streaming architecture plan in order and use MCP/OntoIndex context.

Goal:

Prepare a deterministic world-generation quality pass without changing current generated chunk bytes, serialization, protocol, storage, or streaming behavior.

Context inspected:

- OntoIndex concept search for deterministic terrain shape, caves, resources, structures, seed migration, and chunk serialization.
- `docs/WORLDGEN_DETERMINISM.md`.
- `docs/BIOME_VISUAL_VARIETY_FOUNDATION.md`.
- `server/pkg/world/chunk.go`, `world.go`, and focused world tests.
- Chunk serialization and protocol compatibility constraints from earlier blocks.

Scope:

- Define the future generation pipeline, determinism requirements, migration gates, and local checkpoint.

Out of scope:

- No terrain height change, cave carving, resource placement, structure placement, seed field, chunk byte change, protocol field, storage migration, renderer change, atlas change, biome runtime, or default world behavior change.

Assumptions:

- Current flat generation remains the production worldgen contract until an explicit implementation slice replaces it.
- Any worldgen quality improvement must be reproducible from stable inputs and guarded by tests before it affects chunk bytes.
- Changes to generated chunk bytes force downstream evidence refresh: serialization compatibility, compression decision, storage persistence, world streaming load, resident set, and visual smoke.

Done when:

- The quality-pass pipeline and migration gates are documented.
- A local gate proves the current worldgen/serialization behavior remains unchanged.

Checks:

- `sh scripts/world_generation_quality_gate.sh logs/world_generation_quality_current`

## Current Generation Contract

- `Chunk.GenerateFlat()` fills a fixed flat world: stone, dirt, grass, then air.
- Generated chunks have no explicit world seed.
- There is no terrain height noise, cave layer, resource distribution, biome runtime, or structure placement.
- `World.ChunkSnapshot()` creates missing chunks by calling `GenerateFlat()`.
- Serialized chunk bytes are the authoritative chunk payload for storage and networking.

## Target Generation Pipeline

A future quality generator should be layered and versioned:

```text
GenerationInput:
  world_seed
  dimension_id
  chunk_x
  chunk_z
  generator_version

Layer order:
  1. biome_sample_layer
  2. terrain_height_model
  3. base_strata_fill
  4. cave_layer
  5. resource_layer
  6. structure_layer
  7. surface_detail_layer
  8. validation_and_serialization
```

Layer rules:

- `biome_sample_layer` selects deterministic context, not random local state.
- `terrain_height_model` owns height and slope; it must be deterministic for positive and negative coordinates.
- `base_strata_fill` maps height and depth to stable block IDs.
- `cave_layer` removes or replaces blocks through deterministic masks.
- `resource_layer` adds ores/resources after caves using deterministic coordinates.
- `structure_layer` must be chunk-border aware and must not depend on load order.
- `surface_detail_layer` can add visual variety only after material/atlas gates are ready.
- `validation_and_serialization` must preserve chunk dimensions and little-endian block ID serialization.

## Determinism Rules

- Use explicit seed and algorithm version inputs before any non-flat generator becomes active.
- Do not use wall-clock time, process-global random state, goroutine scheduling, map iteration order, local filesystem state, or floating-point behavior that can differ across platforms without tests.
- Prefer integer or fixed-point coordinate hashing for generation decisions.
- Cross-chunk features must be computable independent of load order.
- Any generated structure that spans chunks needs either deterministic local reconstruction or an explicit persistence model.

## Migration Gates

Before enabling a non-flat generator:

- Add tests for deterministic chunk bytes across independent `World` instances.
- Add tests for positive and negative chunk coordinates.
- Add stable byte-vector tests for representative chunks.
- Add chunk serialization/RLE round-trip tests for non-flat entropy.
- Re-run compression decision after terrain entropy changes.
- Re-run storage persistence tests for generated and edited chunks.
- Re-run high-pressure streaming, resident-set, pop-in, and collision readiness gates.
- Re-run GPU load/atlas/material gates if block distribution or visible texture variety changes.

## Quality Evidence

Quality improvements should be measured with explicit artifacts:

- Height histogram and min/max terrain height.
- Cave air ratio and connectedness sanity checks.
- Resource distribution counts by block ID and depth band.
- Structure placement counts and chunk-border overlap checks.
- Serialized byte hashes for fixed seed/chunk coordinates.
- RLE/raw payload size and encode/decode CPU cost on representative chunks.
- Visual smoke captures for ordinary terrain and edge cases.

## Blocked Changes

These are blocked until a separate implementation task supplies tests and evidence:

- Replacing `GenerateFlat()` behavior.
- Adding hidden default seeds.
- Adding caves, resources, structures, or height noise.
- Changing chunk dimensions or serialization format.
- Changing block IDs or adding generated block IDs.
- Persisting generated biome/structure metadata.
- Making client visuals infer generation state from partial chunks.

## Block 36 Gate

Use:

```sh
sh scripts/world_generation_quality_gate.sh logs/world_generation_quality_current
```

The expected current result is `status=pass`, `quality_pass_status=designed`, `active_generator_change=0`, `active_chunk_byte_change=0`, `runtime_quality_pass=deferred`, and `world_tests=pass`.

The gate checks that:

- This design includes the future generation layer order and determinism rules.
- Biome foundation is clean and still deferred at runtime.
- Current `GenerateFlat()` and serialization source remain unchanged.
- Current world tests pass.

## Current Status

This block is complete as a design/checkpoint block. Runtime worldgen quality improvements remain future work and must start with explicit seed/version inputs plus deterministic tests before any generated chunk bytes change.
