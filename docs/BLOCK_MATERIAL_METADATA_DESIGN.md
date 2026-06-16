# Block Material Metadata Design

Block 33, Block Material Metadata Design, defines the production target for block material metadata without changing current runtime behavior.

## Technical Brief

User request:

Continue the annual world streaming architecture plan in order and use MCP/OntoIndex context.

Goal:

Design production-ready block material metadata for opaque, transparent, liquid, emissive, collision, and render behavior.

Context inspected:

- OntoIndex concept search for block material metadata, block definitions, meshing, protocol, and serialization.
- `client/rust_ext/src/blocks.rs` block definitions and generated compute-mesher semantics.
- `client/rust_ext/src/gpu_terrain.rs` packed block lookup, opaque terrain tests, and fragment alpha contract.
- `client/rust_ext/src/lib.rs` CPU fallback texture lookup and material creation.
- `server/pkg/world/blocks.go` server block registry.
- `docs/GPU_TRANSPARENT_PATH.md`, `docs/PROTOCOL.md`, `docs/ARCHITECTURE.md`, and `docs/AGENT_MEMORY.md`.

Scope:

- Define the metadata model, invariants, rollout order, and verification gate.

Out of scope:

- No new block IDs, protocol fields, storage records, worldgen rules, atlas assets, shader alpha path, transparent pass, liquid simulation, emissive lighting, or default render behavior changes.

Assumptions:

- `block_id` remains the only wire/storage identity for chunks and block actions.
- Material metadata is registry-derived behavior, not per-voxel payload data.
- Current gameplay blocks remain opaque solids until a separate migration slice changes both client and server registries.

Done when:

- The design states the target metadata fields, where they plug in, and which gates block activation.
- A local gate proves the current runtime still matches the opaque-only contract.

Checks:

- `sh scripts/block_material_metadata_design_gate.sh logs/block_material_metadata_design_current`
- Normal project checks and diff guard before broad handoff.

## Current Contract

- Server world block identity is `world.BlockID uint16`.
- Chunk serialization stores one little-endian `uint16` block ID per voxel.
- Network chunk payloads carry serialized chunk block IDs, either raw or RLE over the same bytes.
- `BlockAction.block_id` is a `uint32` protocol field, but the server casts it to `world.BlockID` and validates placeability through the server registry.
- The Rust client receives `u16` block IDs from chunk bytes and stores them in wider local types for renderer work.
- Rust `BlockDefinition` now has a client material registry foundation for existing block IDs: `solid`, `opaque`, `placeable`, render/collision/occlusion/shadow/depth/storage/liquid/sort policies, bounded light emission, and texture fields.
- Go `BlockDefinition` now has a server material registry foundation for existing block IDs: `Solid`, `Opaque`, `Placeable`, render/collision/occlusion/shadow/depth/storage/liquid/sort policies, bounded light emission, and texture fields.
- The GPU compute mesher only emits faces for blocks that are both solid and opaque.
- `PackedBlockLookup::from_definitions` only includes `blocks::is_opaque_solid` definitions.
- The GPU terrain fragment shader writes alpha `1.0`; it does not consume atlas alpha.
- Transparent fixture metadata is client-only and must not allocate a production block ID.

## Target Metadata Model

Production block metadata should be explicit and registry-owned. The registry may live in code at first, but the client and server must expose the same stable semantics for networked block IDs.

Conceptual fields:

```text
id: u16-compatible stable block identity
stable_name: ASCII identifier used in logs, docs, tests, and tooling
placeable: whether BlockAction PLACE may use this block ID
render_class: air | opaque | cutout | transparent | liquid
collision_class: none | solid | fluid | custom
occlusion_class: none | opaque | same_material_only | material_policy
texture_set: top/side/bottom atlas references, or future per-face material references
shadow_policy: opaque_shadow | transparent_shadow | no_shadow | material_policy
light_emission: zero or bounded emissive strength/color
liquid_policy: none | still_liquid | flowing_liquid
sort_policy: none | chunk_subchunk_back_to_front | future_precise
depth_policy: no_draw | opaque_depth_write | depth_test_no_write | material_policy
storage_policy: networked | client_fixture_only | generated_only
```

Required first-class flags:

- `render_class=opaque` means current opaque pass, depth writes, current face culling, current shadow/collision expectations.
- `render_class=transparent` means no full neighbor occlusion and a future transparent pass or fallback path.
- `render_class=cutout` is alpha-tested opaque-depth behavior, not full transparency.
- `render_class=liquid` is a render classification plus explicit liquid policy; it must not imply collision or persistence behavior by itself.
- `light_emission>0` marks emissive behavior; it must stay separate from texture brightness until a lighting model consumes it.
- `collision_class=solid` is the only flag that can create solid gameplay collision.
- `occlusion_class=opaque` is the only flag that can hide neighboring opaque faces.
- `storage_policy=client_fixture_only` blocks protocol, storage, worldgen, and BlockAction use.

## Renderer Mapping

Opaque path:

- `render_class=opaque` and `occlusion_class=opaque` continue through the current compute mesher and packed-face pipeline.
- Opaque material metadata may add fields only if all existing block IDs preserve current generated shader semantics.

Transparent path:

- `render_class=transparent` and `render_class=liquid` must build separate workload markers before activation: blocks, faces, draws, subchunks, upload bytes, and sort/build cost.
- Opaque faces adjacent to transparent/liquid blocks remain visible unless a material-specific seam rule says otherwise.
- Transparent/liquid rendering must happen after opaque depth and must not make opaque terrain quality worse.

Cutout path:

- `render_class=cutout` may use alpha test with opaque depth, but it must be named and tested separately from blended transparency.

Emissive path:

- Emissive metadata is inert until a lighting implementation consumes it.
- Emissive blocks must not change terrain lighting, shadow, or atlas behavior without a dedicated visual/performance gate.

## Collision Mapping

- Collision comes from `collision_class`, not from opacity, alpha, or liquid status.
- `collision_class=none` creates no gameplay collision even if a block has visible geometry.
- `collision_class=solid` participates in current trimesh/static-body collision refresh.
- `collision_class=fluid` is future gameplay behavior and must not be treated as solid without an explicit movement/collision test.
- Render-only fixture blocks must remain `storage_policy=client_fixture_only` until a production block ID is approved.

## Compatibility Rules

- Do not add material fields to `ChunkData.blocks`; chunks still serialize block IDs only.
- Do not change existing block ID numeric values.
- Do not introduce a production block ID from a renderer-only fixture.
- Do not hand-edit generated protocol files.
- If metadata ever needs to cross the wire, add new protobuf fields with new field numbers and compatibility tests.
- Storage should continue persisting the existing serialized chunk bytes unless a migration is explicitly designed.
- World generation must remain deterministic; metadata changes cannot alter terrain shape or block IDs without a worldgen task.

## Rollout Order

1. Keep this design gate active while the current renderer is opaque-only.
2. Keep the server and client material registry foundations guarded for existing block IDs only; preserve current opaque-solid semantics.
3. Keep client/server parity tests comparing stable block IDs, names, placeability, render class, collision class, and texture identity for existing networked IDs before any new production block IDs are introduced.
4. Keep transparent fixture overlay client-only until the active transparent path gate passes.
5. Add one production transparent/cutout/liquid block ID only after protocol, storage, worldgen, atlas, render, collision, and fixture gates are explicitly approved.
6. Add render-pass implementation behind a rollback flag.
7. Promote any non-opaque material only after visual smoke, collision smoke, performance summaries, and external profiler evidence are clean.

## Block 33 Gate

Use:

```sh
sh scripts/block_material_metadata_design_gate.sh logs/block_material_metadata_design_current
```

The expected current result is `status=pass`, `production_metadata_status=server_registry_guarded`, `server_material_metadata=guarded`, `client_material_metadata=guarded`, `active_schema_change=0`, and `current_runtime_contract=opaque_only`.

The gate checks that:

- This design includes render, collision, liquid, emissive, depth, storage, and compatibility rules.
- Protocol docs still define chunk block IDs as unsigned 16-bit little-endian values.
- Rust block definitions expose explicit material metadata for existing block IDs and still preserve the current `solid` and `opaque` contract.
- The compute mesher and packed GPU lookup still filter through opaque-solid block definitions.
- The GPU terrain fragment shader remains opaque alpha-only.
- Server block definitions remain the existing `uint16` block registry and expose explicit material metadata for existing block IDs only.
- `scripts/block_material_registry_foundation_gate.sh` guards the server registry signature for current networked opaque-only blocks.
- `scripts/client_block_material_registry_foundation_gate.sh` guards the client registry signature for current networked opaque-only blocks and consumes the server registry gate.
- Transparent fixture acceptance is clean while active transparent rendering remains deferred.

## Current Status

This block is complete as a design/checkpoint block plus server and client material registry foundations. Runtime production material metadata is guarded for existing block IDs only; new production block IDs, protocol shape, storage behavior, renderer behavior, and atlas behavior remain unchanged.

Texture atlas metadata expansion is tracked separately in `docs/TEXTURE_ATLAS_EVOLUTION_TRACK.md`; material metadata may reference atlas tile identities, but it must not repack current tile IDs or consume alpha metadata without a dedicated render gate.
