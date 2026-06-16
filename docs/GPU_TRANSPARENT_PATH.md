# GPU Transparent Terrain Path

This is the Phase 12 design checkpoint for adding transparent terrain blocks to the GPU terrain renderer. It is a design document only; current runtime behavior remains unchanged.

## Technical Brief

User request:

Continue GPU terrain work after the shadow profiler handoff reached the external-profiler boundary.

Goal:

Define the next safe transparent terrain path before changing renderer behavior.

Context inspected:

- `client/rust_ext/src/blocks.rs` block definitions and generated mesher semantics.
- `client/shaders/mesher.glsl` solid-block face emission.
- `client/shaders/gpu_terrain_render.glsl` fragment alpha contract.
- `client/rust_ext/src/lib.rs` Godot fallback chunk material.
- `client/rust_ext/src/gpu_terrain.rs` GPU terrain opacity tests and packed block lookup.
- `docs/GPU_ROADMAP.md`, `docs/GPU_PROFILING.md`, `docs/GPU_SHADOW_PATH.md`, `docs/ARCHITECTURE.md`, and `docs/AGENT_MEMORY.md`.

Scope:

- Design the rollout order, data contracts, rollback gate, required telemetry, and correctness gates.

Out of scope:

- No Rust runtime, shader, Godot scene, protocol, storage, world generation, atlas, or quality changes.
- No new block IDs or transparent assets.
- No default render behavior changes from local design work alone.

Assumptions:

- The current terrain render path is opaque-only by design.
- Transparent terrain needs a separate pass or explicit fallback; it must not weaken current opaque terrain, collision, lighting, or shadow behavior.
- Any new networked block identity still goes through the normal protocol/world/storage review path.

Done when:

- The design states where transparent blocks plug in, how they roll back, which metrics must exist, and which tests block default enablement.

Checks:

- Docs diff review, normal project checks, diff guard, OntoIndex freshness, and MCP pre-commit review.

## Current Opaque Contract

- `BlockDefinition` already has `solid` and `opaque`, but all current placeable blocks are opaque solids.
- `compute_mesher_glsl_block_semantics` emits shader `is_solid` checks only for blocks that are both solid and opaque.
- The compute mesher emits faces only for blocks whose generated `is_solid` returns true, and hides a face when the neighbor also returns solid.
- `PackedBlockLookup::from_definitions` and current packed-face tests treat GPU terrain blocks as opaque solids.
- The GPU terrain fragment shader samples the atlas and writes `frag_color = vec4(texel.rgb * lighting_in, 1.0)`.
- The Godot fallback chunk material uses nearest filtering with `Transparency::DISABLED` and `DepthDrawMode::OPAQUE_ONLY`.
- Existing lighting, reverse-Z depth, atlas binding, and shadow proxy tests assume an opaque terrain pass.

## Proposed Rollout

1. Keep the current opaque pass as the default path.
2. Add a future explicit rollback flag for any prototype, for example `RUMPELMC_GPU_TERRAIN_TRANSPARENT=0/1`, default off until parity and profiler evidence exist.
3. Split render classification from collision:
   - `air`: no render and no collision.
   - `opaque`: current pass, depth writes, current shadow/collision behavior.
   - `transparent`: future transparent pass, collision only if the block definition says it is solid.
4. Keep opaque face culling conservative: opaque faces next to transparent blocks must remain visible because transparent blocks do not fully occlude them.
5. For transparent face culling, hide only faces between equivalent transparent blocks unless a later material rule requires showing liquid/glass seams.
6. Render transparent terrain after opaque terrain with depth testing against the opaque pass. Do not make this default until the sort strategy is explicit.
7. Use a simple first sort policy, such as chunk/subchunk back-to-front from camera, before considering per-face sorting or order-independent transparency.
8. Keep Godot CPU fallback available for transparent blocks until the GPU path proves parity.
9. Keep shadow behavior explicit per transparent material. Do not disable existing opaque shadows to make transparent blocks cheaper.

## Prototype Options

### Option A: Split Opaque And Transparent GPU Buffers

Build a separate transparent face buffer and draw it after the opaque indirect draw set.

Risk:

- Sorting is approximate unless per-face ordering is added. Good first proof if the visual test case is simple.

### Option B: Alpha-Tested Cutout Only

Support cutout-style blocks by discarding low-alpha texels while keeping opaque-depth behavior.

Risk:

- This works for leaves or fences, not water/glass blending. It must be named as cutout, not full transparency.

### Option C: Godot Material Fallback First

Route transparent blocks through a separate Godot `MeshInstance3D` material while GPU opaque terrain remains unchanged.

Risk:

- It may preserve visual behavior faster, but it adds CPU/Godot mesh work and needs measurement before becoming more than a compatibility fallback.

## Required Telemetry

A future implementation should emit these marker fields before any default-on decision:

- `transparent_requested`, `transparent_active`, and `transparent_fallback`.
- `transparent_blocks`, `transparent_faces`, `transparent_draws`, and `transparent_subchunks`.
- transparent upload bytes/counts if separate buffers are used.
- transparent sort or build cost if sorting is performed on CPU.
- fallback reason when the transparent path is requested but inactive.

## Correctness Gates

- Existing opaque visual parity must remain unchanged when no transparent blocks are present.
- A dedicated transparent test scene must include at least one transparent block in front of terrain and one behind terrain.
- The smoke marker must prove non-sky terrain samples, `gpu_upload_fail=0`, and stable marker generation.
- Depth behavior must show that opaque terrain still occludes transparent blocks behind it.
- Collision behavior must remain tied to block solidity, not render opacity.
- Shadow behavior must be checked explicitly for each transparent material policy.

## Default-On Gates

Transparent terrain can become default only after all of these are true:

- The current opaque path remains a runtime rollback.
- Draw distance, lighting, shadow distance, texture quality, and visible opaque terrain quality are unchanged.
- Transparent scenes pass visual smoke and parity thresholds on macOS and at least one non-macOS backend before broad enablement.
- Local CPU-side metrics stay within existing terrain queue, process wall, and compositor submit budgets.
- External GPU profiler evidence shows acceptable pass cost for the transparent workload.
- `./scripts/check.sh fast`, `./scripts/diff_guard.sh`, and targeted Rust/render tests pass for the implementation slice.

## First Fixture Contract

The first transparent terrain fixture is a fixture-only contract, not a production block or asset rollout.

Fixture identity:

- Use a non-production material label such as `transparent_test_glass` until a real block ID is approved.
- Keep the material absent from ordinary world generation, storage defaults, server protocol payloads, and atlas defaults.
- Load it only through a dedicated transparent fixture or smoke harness.
- Treat the fixture name as stable, for example `gpu-transparent-depth-collision`, so future logs and reports can cite one scenario.

Material semantics:

- `render_class=transparent` means the block does not fully occlude neighboring opaque faces.
- `solid=true` is allowed only when the fixture is testing glass-like collision; collision assertions must name that solidity explicitly.
- Render opacity and collision solidity must stay separate. An alpha value cannot imply collision.
- Opaque faces next to transparent fixture blocks must remain visible.
- Faces between equivalent adjacent transparent fixture blocks may be culled only when the fixture states that same-material seams are hidden.

Scene shape:

- Use a fixed camera, fixed light setup, and fixed fixture chunk coordinates.
- Put one transparent fixture block in front of opaque terrain and one behind an opaque terrain wall.
- Add one opaque occluder in front of a transparent block to prove depth testing against the opaque pass.
- Add an adjacent same-material transparent pair to define seam/culling behavior.
- Include a ground or ray/collision path that touches or passes beside the transparent fixture block, so collision checks cannot be inferred from visuals alone.

Required future marker fields:

- Keep `transparent_requested`, `transparent_active`, and `transparent_fallback`.
- Keep transparent workload fields before an active path is accepted: `transparent_blocks`, `transparent_faces`, `transparent_draws`, and `transparent_subchunks`.
- If sorting or a separate upload path exists, report sort/build cost and transparent upload bytes/counts.
- Keep a fallback reason when the env flag is requested but the active path is disabled.

Acceptance gates:

- With the transparent env flag unset, ordinary opaque terrain markers and parity gates remain unchanged.
- While `GPU_TERRAIN_TRANSPARENT_IMPLEMENTED=false`, the env-on fixture must still report requested-but-fallback markers: `transparent_requested=1`, `transparent_active=0`, and `transparent_fallback=1`.
- A future active transparent path must prove `transparent_active=1`, `transparent_fallback=0`, `gpu_upload_fail=0`, non-sky terrain samples, opaque-depth occlusion, explicit collision-by-solidity behavior, and visible opaque faces next to transparent fixture blocks.
- CPU/GPU parity and external profiler evidence are required before the transparent path can move beyond fixture/prototype status.

Non-goals for this contract:

- No new production block ID, asset, protocol field, storage record, worldgen rule, shader alpha path, transparent pass, or sort implementation.
- No change to default opaque terrain rendering.

## Current Implementation Slice

The current code slice is telemetry/test scaffolding, not blended rendering:

- `RUMPELMC_GPU_TERRAIN_TRANSPARENT` is reserved as a future opt-in flag.
- `GPU_TERRAIN_TRANSPARENT_IMPLEMENTED=false` keeps the requested flag inactive, so current runtime behavior stays opaque-only even when the env flag is set.
- Perf markers expose `transparent_requested`, `transparent_active`, and `transparent_fallback`.
- Perf markers expose current transparent workload fields: `transparent_blocks`, `transparent_faces`, `transparent_draws`, and `transparent_subchunks`. They are expected to stay `0` while `GPU_TERRAIN_TRANSPARENT_IMPLEMENTED=false`.
- Perf markers expose client-only fixture overlay metadata counts as `transparent_fixture_overlay_roles` and `transparent_fixture_overlay_blocks`. They are expected to stay `5` only when `RUMPELMC_GPU_TERRAIN_TRANSPARENT_FIXTURE_OVERLAY=1` is requested, and `0` otherwise.
- `scripts/gpu_terrain_report.sh` aggregates those marker fields and records metric origins.
- The env-on release movement smoke in `logs/gpu_transparent_fallback_capture` passed with `transparent_requested=1`, `transparent_active=0`, `transparent_fallback=1`, `gpu_upload_fail=0`, `smoke_err=0`, and non-sky terrain samples.
- `scripts/gpu_terrain_movement_stress.sh` now fails env-on transparent captures unless those same requested/active/fallback marker values are present.
- `scripts/gpu_terrain_transparent_fixture_plan.sh` validates this fixture contract plus the current movement-stress fallback guard and writes a line-oriented `transparent-fixture-plan.txt` checklist.
- `scripts/gpu_terrain_transparent_fixture_harness.sh` consumes that plan and writes a contract-ready `transparent-fixture-harness.txt` with env-off, env-on fallback, future marker, future active, and non-goal gates.
- `scripts/gpu_terrain_transparent_fixture_check.sh` validates the generated plan and harness summaries together and writes a line-oriented `transparent-fixture-check.txt` pass artifact.
- `scripts/gpu_terrain_report.sh` surfaces the latest transparent fixture plan, harness, and check artifacts under the selected log directory when they exist.
- `scripts/gpu_terrain_transparent_fixture_report_check.sh` validates that an aggregate GPU report includes the selected transparent fixture plan, harness, and check artifacts from the fixture directory.
- `scripts/gpu_terrain_transparent_fixture_pack.sh` regenerates the fixture plan, harness, check, smoke-plan, scene checklist, scene harness, scene harness-check, aggregate report, report-check, acceptance-check, default-off check, final-report check, scene implementation checklist, scene implementation gate-check, and refreshed aggregate report artifacts together without launching Godot.
- `scripts/gpu_terrain_transparent_fixture_smoke_plan.sh` consumes the pack and writes a no-render `transparent-fixture-smoke-plan.txt` with current fallback and future fixture scene gates.
- `scripts/gpu_terrain_transparent_fixture_scene_checklist.sh` consumes the smoke plan and writes a no-render `transparent-fixture-scene-checklist.txt` with fixed scene roles for depth, adjacency, and collision checks.
- `scripts/gpu_terrain_transparent_fixture_scene_harness.sh` consumes the scene checklist and writes a no-render contract-ready `transparent-fixture-scene-harness.txt` with fixed role checks and current/future acceptance gates.
- `scripts/gpu_terrain_transparent_fixture_scene_harness_check.sh` validates the generated scene checklist and harness together and writes a no-render `transparent-fixture-scene-harness-check.txt` pass artifact; aggregate reports and report checks now surface this scene artifact chain.
- `scripts/gpu_terrain_transparent_fixture_acceptance_check.sh` validates the no-render pack, report-check, smoke-plan, and scene harness-check artifacts together before any real fixture scene or renderer path is allowed; the pack now emits and reports this acceptance artifact.
- `scripts/gpu_terrain_transparent_fixture_default_off_check.sh` validates the final no-render pack against the Rust implementation gate, the movement-stress env-on fallback guard, and the transparent fixture contract so `GPU_TERRAIN_TRANSPARENT_IMPLEMENTED=false` keeps env-on captures requested-but-fallback until a real implementation exists; the pack now emits and reports this default-off artifact.
- `scripts/gpu_terrain_transparent_fixture_final_report_check.sh` validates the final no-render pack and aggregate report together, requiring both selected acceptance and default-off report sections to point at the linked artifacts and surface their pass summaries; the pack now emits and reports this final guard artifact.
- `scripts/gpu_terrain_transparent_fixture_scene_implementation_checklist.sh` validates the final no-render pack and scene artifact chain, then writes an implementation-contract-ready fixture-scene checklist for the future scene-only harness work; the pack now emits and reports this checklist artifact.
- `scripts/gpu_terrain_transparent_fixture_scene_implementation_gate_check.sh` validates that the implementation-contract-ready scene checklist, linked pack, and aggregate report still keep the transparent implementation gate false with current env-on fallback and future active-path gates intact; the pack now emits and reports this gate-check artifact.
- `scripts/gpu_terrain_transparent_fixture_scene_smoke.sh` launches the existing Godot visual smoke path with `RUMPELMC_VISUAL_SMOKE_POSE=transparent_fixture`, `RUMPELMC_GPU_TERRAIN_TRANSPARENT=1`, and the overlay request flag, then validates the current requested-but-fallback marker triplet, overlay fallback marker triplet, overlay metadata counts, zero transparent workload markers, `gpu_upload_fail=0`, `smoke_err=0`, and non-sky terrain samples. The fresh release capture in `logs/gpu_transparent_fixture_scene_smoke` passed with `transparent_requested=1`, `transparent_active=0`, `transparent_fallback=1`, `transparent_blocks=0`, `transparent_faces=0`, `transparent_draws=0`, `transparent_subchunks=0`, `transparent_fixture_overlay_requested=1`, `transparent_fixture_overlay_active=0`, `transparent_fixture_overlay_fallback=1`, `transparent_fixture_overlay_roles=5`, `transparent_fixture_overlay_blocks=5`, `terrain_samples=488`, and `gpu_upload_fail=0`.
- `scripts/gpu_terrain_report.sh` now surfaces the latest `transparent-fixture-scene-smoke-summary.txt` under the selected log directory so aggregate reports cite the real fixture scene fallback capture alongside the no-render fixture artifact chain.
- The no-render fixture pack/check chain now carries those same zero workload markers in current env-on fallback guard lines while keeping future active workload markers blocked until a real fixture material/render path exists.
- Ignored local fixture artifacts under `logs/gpu_transparent_fixture_plan` now provide the current real-log checklist source for aggregate reports.
- Existing tests still lock the current opaque-only block and fragment-alpha contracts.
- No transparent face buffer, alpha blending, sort policy, shader alpha path, Godot transparent material, block ID, atlas asset, or protocol behavior is implemented.

## Block 30 Active Path Preflight

Block 30, Transparent Terrain Active Path, is currently deferred by a local active-path preflight instead of changing renderer behavior. Use:

```sh
sh scripts/transparent_active_path_preflight.sh logs/transparent_active_path_preflight_current
```

Fresh evidence in `logs/transparent_active_path_preflight_current/transparent-active-path-preflight-summary.txt` reports `status=deferred`, `active_path_allowed=0`, and `reason=implementation_gate_false`. The fixture pack, scene smoke, default-off, and final-report guards are clean, but runtime workload markers remain `transparent_blocks=0`, `transparent_faces=0`, `transparent_draws=0`, and `transparent_subchunks=0`.

## Block 31 Sorting And Depth

Block 31, Transparent Sorting And Depth Program, now has a policy gate:

```sh
sh scripts/transparent_sorting_depth_program.sh logs/transparent_sorting_depth_program_current
```

Fresh evidence in `logs/transparent_sorting_depth_program_current/transparent-sorting-depth-summary.txt` reports `status=deferred`, `sort_depth_active_allowed=0`, and `reason=active_transparent_not_available`. The first proposed policy is chunk/subchunk back-to-front sorting after opaque depth, with active fixture gates for opaque occlusion, collision solidity, and same-material transparent seams before any runtime path can be enabled.

## Block 32 Acceptance Suite

Block 32, Transparent Fixture Acceptance Suite, now has a consolidated gate:

```sh
sh scripts/transparent_fixture_acceptance_suite.sh logs/transparent_fixture_acceptance_suite_current
```

Fresh evidence in `logs/transparent_fixture_acceptance_suite_current/transparent-fixture-acceptance-suite-summary.txt` reports `status=pass`, `current_fallback_acceptance=pass`, and `active_fixture_acceptance=deferred`. It validates the fixture pack, runtime scene smoke, active-path preflight, sorting/depth program, default-off guard, and final-report guard together while keeping transparent workload markers at zero.

## Block 33 Material Metadata

Block 33, Block Material Metadata Design, is captured in `docs/BLOCK_MATERIAL_METADATA_DESIGN.md` and checked by:

```sh
sh scripts/block_material_metadata_design_gate.sh logs/block_material_metadata_design_current
```

The current expected result is `status=pass`, `production_metadata_status=server_registry_guarded`, `server_material_metadata=guarded`, `active_schema_change=0`, and `current_runtime_contract=opaque_only`. The server now has registry-derived material metadata for existing block IDs only; production transparent, liquid, emissive, client-render, atlas, and non-opaque runtime behavior remains separate migration work without changing chunk wire/storage payloads.

## Fixture Scene Implementation Plan

The next implementation step should stop extending the no-render guard chain and move to an env-driven fixture scene harness. The current Godot project has a minimal scene structure (`client/main.tscn` plus `client/main.gd`), and visual smoke behavior is already controlled through environment variables, so the first fixture harness should avoid hand-editing new `.tscn` resources unless a later slice proves it is necessary.

First runtime slice:

- Add a dedicated fixture-smoke mode to the existing visual smoke path, not a new default scene.
- Keep `GPU_TERRAIN_TRANSPARENT_IMPLEMENTED=false`, so `RUMPELMC_GPU_TERRAIN_TRANSPARENT=1` still reports `transparent_requested=1`, `transparent_active=0`, and `transparent_fallback=1`.
- Reuse existing `main.gd` smoke controls for fixed camera, fixed light, block edit, movement, ground/collision sampling, marker writing, and runtime shutdown.
- Prefer placing or toggling fixture blocks through existing `GameClient` block-edit methods only after the fixture identity is explicitly isolated from ordinary world generation and storage.
- Keep the first fixture run out of ordinary gameplay and ordinary world generation.

Implementation order:

1. Add an env name for the fixture scenario, for example `RUMPELMC_VISUAL_SMOKE_POSE=transparent_fixture`, with a fixed camera target and no renderer behavior change. Done in `client/main.gd`.
2. Add a wrapper script that launches the existing visual smoke path with `RUMPELMC_GPU_TERRAIN_TRANSPARENT=1`, the fixture pose, and a dedicated output directory. Done in `scripts/gpu_terrain_transparent_fixture_scene_smoke.sh`.
3. Make the wrapper assert current fallback markers, `gpu_upload_fail=0`, `smoke_err=0`, and non-sky terrain samples. Done for the current fallback harness.
4. Add fixture workload marker fields only after the harness can produce a stable current fallback capture. Done for the current inactive path with zero `transparent_blocks`, `transparent_faces`, `transparent_draws`, and `transparent_subchunks`.
5. Add fixture-only block/material identity only after the fallback harness is stable and reviewed.

Current blocker for step 5:

- A real fixture-only transparent material cannot be represented today without either a production block ID/asset/protocol/storage/worldgen change or a new client-only fixture overlay path.
- The current runtime receives serialized `u16` block IDs from the server and resolves solid/texture behavior through client/server block definitions. Adding `transparent_test_glass` directly as a block would therefore cross protocol/storage/worldgen compatibility boundaries.
- Next safe implementation should first design a client-only fixture overlay or explicitly approve a production block ID path.

## Client-Only Fixture Overlay Design

The client-only fixture overlay is the next safe path for `transparent_test_glass`. It is a smoke-only overlay contract, not chunk data, not a production block, and not a default gameplay feature.

Overlay ownership and lifetime:

- The overlay is owned by the client visual smoke harness.
- The overlay is created only when an explicit fixture env flag is enabled.
- The overlay lifetime is one visual smoke run and must be cleared on runtime shutdown.
- The overlay must not be serialized, sent to the server, stored in RocksDB/PostgreSQL, or included in world generation.
- The overlay must not use a production block ID until a separate protocol/storage/worldgen change is approved.

Overlay identity:

- Use `overlay_id=transparent_test_glass`.
- Use `fixture=gpu-transparent-depth-collision`.
- Keep `render_class=transparent` separate from `solid=true`.
- Treat the fixture overlay as client-only geometry metadata until a renderer implementation consumes it.

Runtime gates:

- Keep `RUMPELMC_GPU_TERRAIN_TRANSPARENT` as the opt-in request flag.
- Add a future overlay request flag before the overlay becomes active, for example `RUMPELMC_GPU_TERRAIN_TRANSPARENT_FIXTURE_OVERLAY=1`.
- While `GPU_TERRAIN_TRANSPARENT_IMPLEMENTED=false`, overlay-enabled captures must still report `transparent_requested=1`, `transparent_active=0`, `transparent_fallback=1`, `transparent_fixture_overlay_requested=1`, `transparent_fixture_overlay_active=0`, `transparent_fixture_overlay_fallback=1`, and zero transparent workload markers.
- No-render fixture artifacts must carry `overlay_env_on_expected=1/0/1` and a client-only metadata scaffold with `transparent_fixture_overlay_roles=5`, `transparent_fixture_overlay_blocks=5`, `geometry_active=0`, and `chunk_data_mutation=no`.
- Default gameplay and ordinary visual smoke captures must keep `transparent_fixture_overlay_active=0`.

Allowed first implementation shape:

- A client-side fixture metadata list with fixed coordinates and five fixed roles: front transparent, behind-wall transparent, opaque depth occluder, adjacent same-material pair, and collision probe.
- Marker-only validation for overlay requested/active/fallback state.
- No `ChunkData` mutation and no `BlockAction` packet.
- No atlas asset, shader alpha, blending, sorting, or transparent pass.
- No `.tscn`, `.import`, or generated file edits.

Current marker-only scaffold:

- `RUMPELMC_GPU_TERRAIN_TRANSPARENT_FIXTURE_OVERLAY=1` is parsed by the Rust extension and emitted as `transparent_fixture_overlay_requested=1`.
- `transparent_fixture_overlay_active` is gated by `transparent_active`, so it remains `0` while `GPU_TERRAIN_TRANSPARENT_IMPLEMENTED=false`.
- `transparent_fixture_overlay_fallback=1` identifies overlay requests that are intentionally blocked by the transparent implementation gate.
- The Rust extension now carries a fixed client-only fixture metadata list with five role/offset entries: front transparent, behind-wall transparent, opaque depth occluder, adjacent same-material pair, and collision probe.
- Runtime perf markers and the no-render pack/check chain now record that metadata as `transparent_fixture_overlay_roles=5` and `transparent_fixture_overlay_blocks=5` when the overlay is requested, while keeping `geometry_active=0` and `chunk_data_mutation=no`.
- The scaffold emits markers only; it does not create overlay geometry, mutate chunk data, send packets, allocate block IDs, change assets, or change render behavior.

Required future markers:

- `transparent_fixture_overlay_requested`
- `transparent_fixture_overlay_active`
- `transparent_fixture_overlay_fallback`
- `transparent_fixture_overlay_roles`
- `transparent_fixture_overlay_blocks`

Still out of scope for the first runtime slice:

- No shader alpha, blending, transparent pass, sorting, production block ID, atlas asset, protocol field, storage record, worldgen rule, or default behavior change.
- No broad `.tscn` rewrite or generated/imported Godot file edit.
- No default-on decision without visual/depth/collision parity and external profiler evidence.
