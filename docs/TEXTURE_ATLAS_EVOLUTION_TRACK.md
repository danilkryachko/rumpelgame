# Texture Atlas Evolution Track

Block 34, Texture Atlas Evolution Track, defines how block texture atlas metadata can evolve without breaking the current shader layout or asset pipeline.

## Technical Brief

User request:

Continue the annual world streaming architecture plan in order and use MCP/OntoIndex context.

Goal:

Prepare texture atlas metadata expansion without changing current shader packing, atlas sampling, block IDs, material behavior, or Godot asset imports.

Context inspected:

- OntoIndex concept search for atlas metadata, tile indices, shader layout, and asset pipeline.
- `client/rust_ext/src/blocks.rs` atlas constants, block texture IDs, UV helper, and compute-mesher code generation.
- `client/rust_ext/src/gpu_terrain.rs` packed face layout, atlas image validation, sampler creation, push constants, and atlas texture upload.
- `client/shaders/gpu_terrain_render.glsl` packed tile extraction and atlas UV sampling.
- `client/shaders/mesher.glsl` generated atlas layout declarations.
- `client/assets/textures/blocks/block_texture_atlas.png`.
- `docs/BLOCK_MATERIAL_METADATA_DESIGN.md`, `docs/GPU_TRANSPARENT_PATH.md`, and `docs/GPU_PROFILING.md`.

Scope:

- Define the current atlas contract, future metadata shape, compatibility limits, rollout order, and local gate.

Out of scope:

- No atlas image edit, `.import` edit, new asset format, generated manifest file, shader layout change, packed-face layout change, sampler change, material behavior change, texture quality change, protocol change, storage change, or worldgen change.

Assumptions:

- The current atlas image is still a fixed grid of `64px` tiles.
- Current tile IDs are code-owned constants in `client/rust_ext/src/blocks.rs`.
- Future atlas metadata should attach to block material metadata, but it should not become per-voxel payload data.

Done when:

- Current atlas constraints and a safe expansion path are documented.
- A local gate proves the current atlas/shader contract remains unchanged.

Checks:

- `sh scripts/texture_atlas_evolution_gate.sh logs/texture_atlas_evolution_current`

## Current Atlas Contract

- Atlas path: `res://assets/textures/blocks/block_texture_atlas.png`.
- Current image dimensions: `640 x 64`.
- Current tile size: `64px`.
- Current grid: `10 columns x 1 row`.
- Current capacity: `10` tiles.
- Current maximum referenced tile is `TILE_LEAVES = 9`.
- `MAX_TEXTURE_TILE` points at `TILE_LEAVES`, so the current atlas exactly covers tile IDs `0..9`.
- Current code-owned tile identity rows are guarded by `texture_atlas_tile_identity_rows_are_stable`.
- Current block texture references are guarded by `block_material_textures_reference_guarded_atlas_tiles`.
- `GpuTerrainAtlasLayout::from_image_size` rejects images whose dimensions are not divisible by tile size or whose capacity cannot contain `MAX_TEXTURE_TILE`.
- The GPU terrain shader extracts tile IDs from `PackedFace.pos_face_tile` with `(>> 21) & 2047`, so the current packed layout allows up to `2048` tile IDs before a layout migration is needed.
- Atlas layout push constants are four floats: inverse columns, inverse rows, columns, rows.
- The atlas sampler uses nearest filtering and clamp-to-edge addressing.
- The fragment shader samples RGB and forces alpha `1.0`; atlas alpha is not a render contract yet.
- The compute mesher receives generated `ATLAS_COLUMNS` and `ATLAS_ROWS` constants from Rust.

## Target Metadata Shape

The first production atlas metadata should be registry-owned and testable. It does not need a new file format until a concrete asset pipeline task approves one.

Conceptual fields:

```text
atlas_id: stable ASCII identifier
image_path: Godot resource path
tile_size_px: fixed tile size for this atlas
columns: image-derived or explicitly verified column count
rows: image-derived or explicitly verified row count
tile_capacity: columns * rows
sampler_filter: nearest | future_linear
sampler_address: clamp_to_edge
color_space: srgb | unorm_fallback
tile_id: stable numeric tile index
tile_name: stable ASCII tile identifier
alpha_mode: opaque | cutout | blend_candidate
material_tags: optional future tags linked to block material metadata
```

Required invariants:

- Tile IDs remain stable once networked block definitions reference them.
- `tile_size_px` stays `64` until a shader/asset migration explicitly changes UV math and visual tests.
- Atlas metadata expands by adding tiles or rows first, not by repacking existing tile IDs.
- The shader packed-face layout is unchanged while tile IDs remain within `0..2047`.
- Alpha metadata is inert until cutout/transparent rendering explicitly consumes it.
- Atlas metadata is not serialized in chunk payloads and is not sent in block-action packets.

## Safe Expansion Path

1. Keep the current code-owned constants as the source of truth for existing tiles.
2. Keep tests that guard current tile identity rows and compare declared columns/rows/tile capacity against the atlas image dimensions.
3. Add new tile names only after the image includes the tile and `MAX_TEXTURE_TILE` is updated.
4. Do not repack `grass`, `soil`, `stone`, `wood`, or `leaves` tile IDs.
5. If the atlas grows beyond one row, verify CPU array mesh UVs, compute mesher UVs, and GPU renderer UVs with the same fixture.
6. If tile IDs ever exceed `2047`, design a new `PackedFace` layout/version before changing the shader.
7. If alpha/cutout/blend metadata is added, keep it blocked by the transparent/cutout material gates from `docs/BLOCK_MATERIAL_METADATA_DESIGN.md`.

## Blocked Changes

These require a separate implementation task and evidence:

- No atlas image edit or `.import` metadata edit.
- Introducing a new atlas manifest file format.
- Changing tile size.
- Repacking existing tile IDs.
- Changing the packed face bit layout.
- Changing atlas sampler filtering/addressing.
- Consuming atlas alpha in the opaque terrain fragment shader.
- Adding transparent/cutout/liquid blocks through atlas metadata alone.

## Block 34 Gate

Use:

```sh
sh scripts/texture_atlas_evolution_gate.sh logs/texture_atlas_evolution_current
```

The expected current result is `status=pass`, `atlas_metadata_status=designed`, `atlas_tile_identity=guarded`, `block_texture_usage=guarded`, `active_asset_change=0`, `shader_layout_change=0`, `tile_size_px=64`, `columns=10`, `rows=1`, `tile_capacity=10`, `max_texture_tile=9`, and `packed_tile_capacity=2048`.

The gate checks that:

- This design includes atlas metadata, compatibility limits, sampler policy, alpha policy, and rollout rules.
- The Rust block atlas constants include a stable current tile identity test.
- Current block material texture references use only guarded atlas tiles within capacity.
- The current PNG dimensions still match the code-owned tile layout.
- Runtime atlas validation still rejects incompatible image sizes or insufficient capacity.
- The shader still extracts an 11-bit tile index from `PackedFace.pos_face_tile`.
- The fragment shader still forces opaque alpha.
- The sampler remains nearest/clamp-to-edge.
- Block material metadata remains at `active_schema_change=0` with the existing-ID server and client registry foundations guarded.

## Current Status

This block is complete as a design/checkpoint block. Texture atlas evolution should start with guarded metadata/tests over existing tiles, then append stable tile IDs only after explicit asset and visual-smoke work.
