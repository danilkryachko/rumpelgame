# Worldgen Determinism

Date: 2026-06-15

This note records the current deterministic world generation and serialization guard for the world streaming path.

## Current Contract

- `Chunk.GenerateFlat()` is deterministic for identical chunk coordinates.
- Generated flat chunks keep the current strata contract: `Stone` from `y=0..60`, `Dirt` from `y=61..62`, `Grass` at `y=63`, and `Air` above.
- Representative flat chunk serialized bytes have SHA-256 `41bc68c75bd63c8845bba319c5db67e4ef0ab627b0241cd74e406d5c1878bd94`.
- `Chunk.Serialize()` emits a stable little-endian `u16` block array with index order `x + y * ChunkWidth * ChunkDepth + z * ChunkWidth`.
- `World.ChunkSnapshot()` preserves requested chunk coordinates and produces stable serialized bytes across independent `World` instances for identical coordinates.
- `World` now owns an explicit generator configuration: `seed`, `dimension_id`, and `version=flat_v1`. The current `flat_v1` generator preserves the existing flat chunk byte vector for default and explicitly configured seeds.
- Server startup validates `RUMPELMC_WORLD_SEED`, `RUMPELMC_WORLD_DIMENSION_ID`, and `RUMPELMC_WORLD_GENERATOR_VERSION` before creating `World`; default values remain seed `0`, dimension `overworld`, and generator version `flat_v1`.
- These tests do not change generation behavior, storage, protocol, chunk dimensions, or payload encoding defaults.

## Guard

Run the focused guard with:

```sh
cd server
go test ./pkg/world
```

Fresh check:

- `go test ./pkg/world ./cmd/server` passed on 2026-06-16 with deterministic generation, explicit seed/version generator configuration, server env parsing, flat byte-hash, stable serialization order, and world snapshot determinism coverage.

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

The current expected result is `status=pass`, `quality_pass_status=designed`, `worldgen_seed_version=guarded`, `active_generator_change=0`, `active_chunk_byte_change=0`, `runtime_quality_pass=deferred`, and `flat_byte_hash=guarded`. Terrain height, caves, resources, and structures remain blocked until a non-flat generator implementation has deterministic tests and downstream evidence.
