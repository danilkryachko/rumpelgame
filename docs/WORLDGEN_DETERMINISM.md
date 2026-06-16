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
- `height_v1` is an opt-in generator version. It uses deterministic integer coordinate hashing from seed, dimension, world X/Z, and algorithm salts to produce surface heights in the guarded `48..80` range while preserving chunk dimensions and serialization.
- Representative `height_v1` bytes for seed `8675309`, dimension `overworld`, and chunk `(-3,5)` have SHA-256 `1101411ccf572478dc9dee8772428714fd80d5ea9f82f491401e2ca410369dc7`.
- `TestEncodeSerializedChunkRLERoundTripsHeightV1Chunk` proves a representative `height_v1` chunk round-trips through the existing RLE codec and stays smaller than raw serialized bytes.
- `TestHeightV1EditedChunkPersistsThroughStoreReload` proves an edited `height_v1` chunk saves through `ChunkStore`, reloads from stored bytes, and is not replaced by a newly generated chunk.
- `scripts/server_height_generator_smoke.sh` proves a live server configured with `RUMPELMC_WORLD_GENERATOR_VERSION=height_v1` streams the representative chunk through RLE with raw SHA-256 `1101411ccf572478dc9dee8772428714fd80d5ea9f82f491401e2ca410369dc7`.
- `TestBiomeSamplerV1StableVector` and `TestBiomeSamplerChangesWithSeedAndDimension` prove the metadata-only `biome_v1` sampler is deterministic for representative positive, negative, and high-magnitude world coordinates.
- `TestBiomeSamplerDoesNotChangeGeneratedChunkBytes` proves biome sampling does not change `flat_v1` generated chunk bytes.
- These tests do not change storage, protocol, chunk dimensions, payload encoding defaults, or default `flat_v1` generation behavior.

## Guard

Run the focused guard with:

```sh
cd server
go test ./pkg/world
```

Fresh check:

- `go test ./pkg/world ./cmd/server` passed on 2026-06-16 with deterministic generation, explicit seed/version generator configuration, server env parsing, flat byte-hash, opt-in `height_v1` byte-hash, seed/dimension sensitivity, stable serialization order, RLE round-trip coverage, persistence reload coverage, and world snapshot determinism coverage.

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

The current expected result is `status=pass`, `quality_pass_status=designed`, `worldgen_seed_version=guarded`, `worldgen_height_v1=guarded`, `height_v1_serialization=guarded`, `height_v1_live_smoke=guarded`, `biome_sampler=guarded`, `active_generator_change=0`, `active_chunk_byte_change=0`, `runtime_quality_pass=opt_in_height_v1_guarded`, and `flat_byte_hash=guarded`. Caves, resources, structures, biome runtime, and default-world changes remain blocked until versioned implementations have deterministic tests and downstream evidence.
