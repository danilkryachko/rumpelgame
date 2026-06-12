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
- Add transparent workload fields before an active path is accepted: `transparent_blocks`, `transparent_faces`, `transparent_draws`, and `transparent_subchunks`.
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
- `scripts/gpu_terrain_report.sh` aggregates those marker fields and records metric origins.
- The env-on release movement smoke in `logs/gpu_transparent_fallback_capture` passed with `transparent_requested=1`, `transparent_active=0`, `transparent_fallback=1`, `gpu_upload_fail=0`, `smoke_err=0`, and non-sky terrain samples.
- `scripts/gpu_terrain_movement_stress.sh` now fails env-on transparent captures unless those same requested/active/fallback marker values are present.
- `scripts/gpu_terrain_transparent_fixture_plan.sh` validates this fixture contract plus the current movement-stress fallback guard and writes a line-oriented `transparent-fixture-plan.txt` checklist.
- `scripts/gpu_terrain_transparent_fixture_harness.sh` consumes that plan and writes a placeholder `transparent-fixture-harness.txt` with env-off, env-on fallback, future marker, future active, and non-goal gates.
- `scripts/gpu_terrain_transparent_fixture_check.sh` validates the generated plan and harness summaries together and writes a line-oriented `transparent-fixture-check.txt` pass artifact.
- `scripts/gpu_terrain_report.sh` surfaces the latest transparent fixture plan, harness, and check artifacts under the selected log directory when they exist.
- `scripts/gpu_terrain_transparent_fixture_report_check.sh` validates that an aggregate GPU report includes the selected transparent fixture plan, harness, and check artifacts from the fixture directory.
- `scripts/gpu_terrain_transparent_fixture_pack.sh` regenerates the fixture plan, harness, check, smoke-plan, scene checklist, scene harness, scene harness-check, aggregate report, report-check, acceptance-check, default-off check, final-report check, scene implementation checklist, and refreshed aggregate report artifacts together without launching Godot.
- `scripts/gpu_terrain_transparent_fixture_smoke_plan.sh` consumes the pack and writes a no-render `transparent-fixture-smoke-plan.txt` with current fallback and future fixture scene gates.
- `scripts/gpu_terrain_transparent_fixture_scene_checklist.sh` consumes the smoke plan and writes a no-render `transparent-fixture-scene-checklist.txt` with fixed scene roles for depth, adjacency, and collision checks.
- `scripts/gpu_terrain_transparent_fixture_scene_harness.sh` consumes the scene checklist and writes a no-render `transparent-fixture-scene-harness.txt` placeholder with fixed role checks and current/future acceptance gates.
- `scripts/gpu_terrain_transparent_fixture_scene_harness_check.sh` validates the generated scene checklist and harness together and writes a no-render `transparent-fixture-scene-harness-check.txt` pass artifact; aggregate reports and report checks now surface this scene artifact chain.
- `scripts/gpu_terrain_transparent_fixture_acceptance_check.sh` validates the no-render pack, report-check, smoke-plan, and scene harness-check artifacts together before any real fixture scene or renderer path is allowed; the pack now emits and reports this acceptance artifact.
- `scripts/gpu_terrain_transparent_fixture_default_off_check.sh` validates the final no-render pack against the Rust implementation gate, the movement-stress env-on fallback guard, and the transparent fixture contract so `GPU_TERRAIN_TRANSPARENT_IMPLEMENTED=false` keeps env-on captures requested-but-fallback until a real implementation exists; the pack now emits and reports this default-off artifact.
- `scripts/gpu_terrain_transparent_fixture_final_report_check.sh` validates the final no-render pack and aggregate report together, requiring both selected acceptance and default-off report sections to point at the linked artifacts and surface their pass summaries; the pack now emits and reports this final guard artifact.
- `scripts/gpu_terrain_transparent_fixture_scene_implementation_checklist.sh` validates the final no-render pack and scene artifact chain, then writes a pending fixture-scene implementation checklist for the future scene-only harness work; the pack now emits and reports this checklist artifact.
- Ignored local fixture artifacts under `logs/gpu_transparent_fixture_plan` now provide the current real-log checklist source for aggregate reports.
- Existing tests still lock the current opaque-only block and fragment-alpha contracts.
- No transparent face buffer, alpha blending, sort policy, shader alpha path, Godot transparent material, block ID, atlas asset, or protocol behavior is implemented.

The next safe implementation slice is still no-render work:

- Add the next fixture-only guard or fixture-scene harness checklist while preserving current opaque behavior.
- Keep all current opaque correctness gates unchanged while the implementation gate remains false.
- Defer shader alpha, blending, sorting, block-ID, asset, protocol, storage, worldgen, and render-path work until the fixture contract has env-off and env-on fallback gates.
