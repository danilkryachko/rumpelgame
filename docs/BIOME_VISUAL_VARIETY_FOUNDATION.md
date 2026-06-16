# Biome And Visual Variety Foundation

Block 35, Biome And Visual Variety Foundation, defines the first safe foundation for biome-driven visual variety without changing current world generation, serialization, storage, protocol, or renderer behavior.

## Technical Brief

User request:

Continue the annual world streaming architecture plan in order and use MCP/OntoIndex context.

Goal:

Start a biome and terrain visual-variety layer while preserving determinism and chunk serialization compatibility.

Context inspected:

- OntoIndex concept search for biome visual variety, deterministic world generation, chunk serialization, and terrain shape.
- `docs/WORLDGEN_DETERMINISM.md`.
- `server/pkg/world/chunk.go` flat chunk generation and serialization.
- `server/pkg/world/world.go` chunk snapshot creation and storage fallback.
- `server/pkg/world/chunk_test.go` flat strata and serialization tests.
- `server/pkg/world/world_test.go` chunk snapshot determinism tests.
- `docs/BLOCK_MATERIAL_METADATA_DESIGN.md` and `docs/TEXTURE_ATLAS_EVOLUTION_TRACK.md`.

Scope:

- Define biome ownership, determinism rules, visual-variety rollout, a deterministic metadata-only sampler, and a local gate.

Out of scope:

- No terrain shape change, block distribution change, protocol packet, storage record, atlas asset, material tint, renderer behavior, chunk payload format, or default gameplay change.

Assumptions:

- The current generated world remains the flat strata world until a dedicated worldgen quality task changes it.
- Chunk payloads remain block-ID arrays.
- Biome metadata must be derived deterministically or persisted through an explicit storage/protocol migration; it must not be implicit mutable client state.

Done when:

- The biome/visual-variety ownership model and rollout gates are documented.
- `biome_v1` metadata catalog and deterministic sampler are implemented and guarded.
- A local gate proves the current deterministic flat worldgen and serialization contract still holds.

Checks:

- `sh scripts/biome_visual_variety_foundation_gate.sh logs/biome_visual_variety_foundation_current`

## Current Worldgen Contract

- `Chunk.GenerateFlat()` fills deterministic strata:
  - `Stone` from `y=0..60`.
  - `Dirt` from `y=61..62`.
  - `Grass` at `y=63`.
  - `Air` above.
- `Chunk.Serialize()` writes little-endian `uint16` block IDs in the stable index order `x + y * ChunkWidth * ChunkDepth + z * ChunkWidth`.
- `World.ChunkSnapshot()` produces stable serialized bytes across independent `World` instances for identical coordinates.
- `WorldGenerator` now exposes explicit `seed`, `dimension_id`, and `version=flat_v1` inputs for generated chunks while preserving the existing flat chunk byte vector.
- `BiomeDefinitionsV1()` exposes the current metadata-only biome catalog.
- `WorldGenerator.SampleBiome()` and `DeterministicBiomeID()` derive `biome_v1` IDs from seed, dimension, and world X/Z coordinates without mutating chunks.
- `scripts/biome_sampler_matrix_gate.sh` records the current representative `biome_v1` matrix hash `6fa59c33bbf1c4aa1a86028e89b04ce1dc26d9bb6fe5fa32e6f5085f5983fb4e`.
- RocksDB persistence stores serialized chunk bytes; it does not store biome metadata.
- Protocol `ChunkData.blocks` sends serialized block IDs, raw or RLE over the same serialized bytes.

## Biome Ownership Model

Future biomes should be owned by the world-generation layer if they affect blocks, terrain height, caves, resources, structures, or gameplay. Client-only visual effects may exist only when their inputs are deterministic and explicitly available to the client.

Required deterministic inputs:

```text
world_seed: stable explicit seed, not wall-clock time
dimension_id: stable world/dimension identity
chunk_x/chunk_z: chunk coordinates
block_x/block_z: optional world block coordinates for finer sampling
biome_algorithm_version: explicit version for migrations
```

Required properties:

- `deterministic_biome_id(seed, x, z)` must return the same value across processes, platforms, and runs.
- Biome sampling must not depend on map iteration order, goroutine scheduling, local time, process ID, filesystem state, or random global state.
- If biome data changes block IDs, the serialized chunk bytes must remain deterministic and compatibility tests must be updated.
- If biome data is visual-only, the client must receive or derive the same deterministic inputs; do not infer biome state from incomplete loaded chunks.

## Visual Variety Layers

Layer 0, current:

- Flat terrain and current atlas textures only.
- No biome metadata or runtime visual variety.

Layer 1, metadata-only:

- Biome IDs, names, and RGB surface-tint metadata exist in the `biome_v1` catalog.
- Deterministic biome sampling is available through `WorldGenerator.SampleBiome()` and `DeterministicBiomeID()`.
- No terrain shape, block distribution, chunk payload, or renderer change.

Layer 2, client-visible but block-preserving:

- Use deterministic biome metadata for material tint, grass/foliage color, or surface variation.
- Requires visual parity/smoke coverage, atlas/material gates, and a way for the client to derive or receive biome inputs.
- Must not change `ChunkData.blocks`.

Layer 3, block-distribution changes:

- Use biomes to vary surface blocks, resource blocks, caves, structures, or height.
- The current opt-in `biome_height_v1` generator uses `biome_v1` to vary surface/subsurface block selection over the existing `height_v1` height field.
- The current opt-in `biome_cave_height_v1` generator combines biome-selected surface/subsurface blocks with deterministic `cave_v1` carving through the world generation quality gate.
- Broader biome resources, structures, and default-world changes still require separate worldgen determinism tests, serialization compatibility checks, storage review, and updated perf/world streaming evidence.

Layer 4, persisted/migrated biomes:

- Store or transmit biome fields only through an explicit protocol/storage migration with compatibility tests.

## Rollout Gates

Before any runtime biome work:

- Keep `go test ./pkg/world` passing.
- Keep current flat strata tests passing until an explicit worldgen task updates them.
- Keep deterministic sampling tests passing before using biome output outside the world package.
- Add cross-coordinate tests for positive and negative chunk coordinates.
- Add serialization round-trip tests for any block distribution change.
- Run chunk compatibility tests if `ChunkData` behavior changes.
- Run storage persistence checks if generated or edited chunks change persisted bytes.
- Run atlas/material gates if visual-only color or texture metadata changes.

## Blocked Changes

These require a separate implementation task and evidence:

- Adding a hidden seed default that changes generated chunks.
- Changing default-world terrain height, caves, resources, structures, or surface blocks.
- Turning biome/resource metadata into new block IDs without material/atlas and downstream evidence.
- Adding biome fields to packets or storage.
- Adding client-only biome visuals without deterministic client inputs.
- Changing atlas assets or material metadata to simulate biome variety.
- Updating flat strata expectations without documenting the new worldgen contract.

## Block 35 Gate

Use:

```sh
sh scripts/biome_visual_variety_foundation_gate.sh logs/biome_visual_variety_foundation_current
```

The expected current foundation result is `status=pass`, `biome_foundation_status=designed`, `biome_sampler=guarded`, `biome_matrix=guarded`, `metadata_layer=guarded`, `active_worldgen_change=0`, `active_serialization_change=0`, `visual_variety_runtime=deferred`, and `world_tests=pass`.

The gate checks that:

- This design includes deterministic biome inputs, visual layers, rollout gates, and blocked changes.
- `server/pkg/world/biome.go` defines the stable `biome_v1` catalog and sampler.
- `server/pkg/world/biome_test.go` guards metadata uniqueness, stable sample vectors, seed/dimension sensitivity, and no generated-byte changes after sampling.
- `logs/biome_sampler_matrix_current/biome-sampler-matrix-summary.txt` guards the representative matrix counts and sample hash.
- Current worldgen docs still record the flat strata contract.
- `Chunk.GenerateFlat()` still uses the current strata thresholds.
- `Chunk.Serialize()` still writes little-endian `uint16` block IDs.
- Chunk/world determinism tests still exist and pass.
- Block material and texture atlas gates remain clean.

## Current Status

This block is complete as a metadata-only biome foundation. Default runtime biome terrain generation and visual variation remain inactive; `biome_v1` sampling and the representative matrix artifact are guarded as deterministic data and do not change chunk bytes, protocol, storage, atlas assets, material rendering, or default gameplay behavior. Opt-in `biome_height_v1` and `biome_cave_height_v1` terrain block selection is tracked by the world generation quality gate, not by changing this foundation contract.
