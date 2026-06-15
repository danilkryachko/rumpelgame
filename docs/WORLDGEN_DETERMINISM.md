# Worldgen Determinism

Date: 2026-06-15

This note records the current deterministic world generation and serialization guard for the world streaming path.

## Current Contract

- `Chunk.GenerateFlat()` is deterministic for identical chunk coordinates.
- Generated flat chunks keep the current strata contract: `Stone` from `y=0..60`, `Dirt` from `y=61..62`, `Grass` at `y=63`, and `Air` above.
- `Chunk.Serialize()` emits a stable little-endian `u16` block array with index order `x + y * ChunkWidth * ChunkDepth + z * ChunkWidth`.
- `World.ChunkSnapshot()` preserves requested chunk coordinates and produces stable serialized bytes across independent `World` instances for identical coordinates.
- These tests do not change generation behavior, storage, protocol, chunk dimensions, or payload encoding defaults.

## Guard

Run the focused guard with:

```sh
cd server
go test ./pkg/world
```

Fresh check:

- `go test ./pkg/world` passed on 2026-06-15 after adding deterministic generation, stable serialization order, and world snapshot determinism coverage.

## Biome Foundation

Biome and visual-variety foundation work is tracked in `docs/BIOME_VISUAL_VARIETY_FOUNDATION.md` and checked by:

```sh
sh scripts/biome_visual_variety_foundation_gate.sh logs/biome_visual_variety_foundation_current
```

The current expected result is `status=pass`, `biome_foundation_status=designed`, `active_worldgen_change=0`, `active_serialization_change=0`, and `visual_variety_runtime=deferred`. Do not add biome-driven terrain shape, block distribution, visual tint, storage, or protocol behavior without a deterministic seed/model and updated compatibility gates.

## Worldgen Quality Pass

World generation quality work is tracked in `docs/WORLD_GENERATION_QUALITY_PASS.md` and checked by:

```sh
sh scripts/world_generation_quality_gate.sh logs/world_generation_quality_current
```

The current expected result is `status=pass`, `quality_pass_status=designed`, `active_generator_change=0`, `active_chunk_byte_change=0`, and `runtime_quality_pass=deferred`. Terrain height, caves, resources, and structures remain blocked until an explicit seed/version model and deterministic tests exist.
