# GPU Transparent Terrain Path

This is the Phase 12 design checkpoint for adding transparent terrain blocks to the GPU terrain renderer. The default runtime path remains opaque-only. A default-off cutout alpha-test prototype now exists for leaf-style blocks behind `RUMPELMC_GPU_TERRAIN_CUTOUT_PROTOTYPE=1`; blended transparency, sorting, and split transparent buffers remain deferred.

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

Out of scope for the default runtime:

- No default-on Rust runtime, Godot scene, protocol, storage, world generation, atlas, or quality changes.
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

## Prototype Shape Decision

Current decision, 2026-06-16: use `cutout_only_first` as the first transparent-family prototype shape.

This started as a planning/runtime-readiness decision. `scripts/transparent_prototype_shape_decision_gate.sh` remains the guard before broadening the prototype shape; split buffers and blended alpha stay blocked while `GPU_TERRAIN_TRANSPARENT_IMPLEMENTED=false` and no sorting/depth/profiler evidence exists.

Rationale:

- Cutout/alpha-test blocks keep opaque-depth behavior and avoid the full blended-transparency sorting problem for the first prototype.
- Split transparent buffers and blended alpha remain deferred until there is nonzero transparent workload, sorting/depth evidence, and external profiler evidence.
- Godot material fallback remains a compatibility fallback only until its CPU/Godot mesh cost is measured.

External references checked for this decision:

- Godot 3D rendering limitations: transparent geometry is drawn after opaque geometry and sorted back-to-front by `Node3D` position, so complex overlap can sort incorrectly.
- Godot StandardMaterial3D: alpha scissor/cutout is faster than alpha blending, avoids sorting issues, and can still cast shadows.
- Khronos Vulkan tutorial: alpha-cut transparency is a common discard-based technique that avoids complex blending/sorting for cutout materials.

Use:

```sh
sh scripts/transparent_prototype_shape_decision_gate.sh logs/transparent_prototype_shape_decision_current
```

The gate consumes active-path preflight, sorting/depth, fixture acceptance, and block-material metadata summaries. It rejects unexpected nonzero transparent workload or active implementation changes before another reviewed prototype slice.

## Cutout Prototype Slice

Current default-off prototype, 2026-06-16:

- `RUMPELMC_GPU_TERRAIN_CUTOUT_PROTOTYPE=1` enables a leaf-only cutout alpha-test path inside the existing GPU terrain opaque pass.
- `RUMPELMC_GPU_TERRAIN_TRANSPARENT=1` remains the reserved future full-transparent request and still falls back while `GPU_TERRAIN_TRANSPARENT_IMPLEMENTED=false`.
- `LEAVES` keeps the existing block ID, atlas tile, `solid=true`, and `opaque=true` default contract, with additional `cutout_alpha_test=true` metadata for the prototype.
- Packed GPU faces keep their 16-byte layout. Bit `12` in the low `extent` word marks cutout faces; chunk/subchunk packing and indirect draw stride are unchanged.
- The vertex shader forwards the cutout bit as a `flat uint`; the fragment shader discards texels with `alpha < 0.5` only for marked faces, then still writes `alpha=1.0` for surviving pixels.
- There is no alpha blending, no transparent pass, and no transparent sorting in this slice.
- When the prototype is active, opaque faces next to cutout leaves remain visible because cutout leaves do not fully occlude neighbors.
- Same-material cutout seam policy is conservative in this first slice; full seam/sorting policy remains future work.
- `transparent_blocks` counts loaded cutout metadata blocks only when the cutout prototype is active; `transparent_faces`, `transparent_draws`, and `transparent_subchunks` come from the GPU packed-face pool.

Use a leaf block-edit smoke for runtime evidence:

```sh
RUMPELMC_GPU_TERRAIN_CUTOUT_PROTOTYPE=1 \
RUMPELMC_BLOCK_EDIT_STRESS_ACTION=place \
RUMPELMC_BLOCK_EDIT_STRESS_BLOCK_ID=5 \
RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE=1 \
RUMPELMC_GODOT_RUST_EXT_PROFILE=release \
sh scripts/gpu_terrain_block_edit_stress.sh logs/gpu_transparent_cutout_prototype_current
```

The block-edit stress summary now includes `block_edit_transparent ...`. With the cutout prototype flag enabled it must report `transparent_requested=1`, `transparent_active=1`, `transparent_fallback=0`, nonzero transparent workload counts, and `gpu_upload_fail=0`.

Promote the runtime smoke into an aggregate-report acceptance artifact with:

```sh
sh scripts/gpu_terrain_cutout_prototype_acceptance_gate.sh logs/gpu_transparent_cutout_prototype_current
```

The gate validates the leaf placement smoke, source contracts, and report surfacing together. It requires block ID `5`, `transparent_requested=1`, `transparent_active=1`, `transparent_fallback=0`, nonzero cutout workload counts, `gpu_upload_fail=0`, `GPU_TERRAIN_TRANSPARENT_IMPLEMENTED=false`, and no blended/sorted/default-on claim.

Promote the same default-off cutout path into a high resident-set world-loading pressure artifact with:

```sh
sh scripts/gpu_terrain_cutout_pressure_load_scaling_gate.sh logs/gpu_terrain_cutout_pressure_load_scaling_current
```

The pressure gate runs the existing load-scaling stack with `RUMPELMC_GPU_TERRAIN_CUTOUT_PROTOTYPE=1`, a `pressure` workload, the `chunk_disc` terrain pressure fixture, and leaf block ID `5`. It requires the load-scaling prerequisite to pass, `transparent_requested=1`, `transparent_active=1`, `transparent_fallback=0`, high nonzero transparent workload, `gpu_upload_fail=0`, queue/process/submit budgets under `6.667ms`, and aggregate report surfacing. The cutout pressure thresholds are deliberately separate from opaque stone pressure: leaf/cutout faces occupy less of the indirect command buffer in this fixture, so the current gate requires at least `1800` GPU subchunks/draws, `3000` faces, and `22.0%` draw-command occupancy instead of treating the older `25.0%` opaque-pressure floor as a cutout invariant.

Use a fixed cutout fixture scene smoke for active depth/collision evidence:

```sh
RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE=1 \
RUMPELMC_GODOT_RUST_EXT_PROFILE=release \
GODOT_TIMEOUT_SEC=240 \
GODOT_QUIT_AFTER_FRAMES=24000 \
sh scripts/gpu_terrain_cutout_fixture_scene_smoke.sh logs/gpu_transparent_cutout_fixture_scene_smoke_current
```

Promote that scene smoke into a report-backed acceptance artifact with:

```sh
sh scripts/gpu_terrain_cutout_fixture_acceptance_gate.sh logs/gpu_transparent_cutout_fixture_scene_smoke_current
```

The scene smoke uses an isolated RocksDB path, the existing local server, `RUMPELMC_GPU_TERRAIN_CUTOUT_PROTOTYPE=1`, and `RUMPELMC_VISUAL_SMOKE_CUTOUT_FIXTURE=roles` without enabling `RUMPELMC_GPU_TERRAIN_TRANSPARENT=1`. It places four leaf/cutout roles including one same-material adjacent pair plus one opaque occluder, waits for dirty GPU terrain update and collision queue drain, then records per-role collision rays, adjacent-pair markers, and an opaque occlusion probe. The adjacent-pair seam/culling proof is cutout-only: the runtime fixture pins the adjacent pair and exact cutout workload, while the Rust mesher unit test proves same-material cutout pair seam faces stay visible. The occlusion probe is a physics depth/collision guard for this cutout slice; it is not blended transparency, per-pixel sorting, or full transparent-pass evidence.

Fresh local evidence, 2026-06-16:

- `logs/gpu_transparent_cutout_prototype_current/block-edit-stress-summary.txt` placed block ID `5` (`LEAVES`) in release mode with the cutout prototype enabled.
- `logs/gpu_transparent_cutout_prototype_current/transparent-cutout-prototype-acceptance-summary.txt` passed the acceptance/report gate and links the runtime smoke to `logs/gpu_transparent_cutout_prototype_current/gpu-terrain-cutout-prototype-report.txt`.
- `logs/gpu_terrain_cutout_pressure_load_scaling_current/gpu-terrain-cutout-pressure-load-scaling-summary.txt` passed the high resident-set cutout pressure gate with `terrain_pressure_fixture=chunk_disc`, `terrain_pressure_fixture_block_id=5`, `max_gpu_subchunks=1880`, `max_gpu_draws=1880`, `max_gpu_faces=3838`, `gpu_draw_cmd_occupancy_pct=22.949`, `transparent_blocks=709`, `transparent_faces=1716`, `transparent_draws=286`, `transparent_subchunks=286`, `max_terrain_queue_ms=2.349`, `max_process_wall_p95_ms=0.003`, `max_gpu_compositor_submit_ms=0.149`, and `gpu_upload_fail=0`.
- `logs/gpu_transparent_cutout_fixture_scene_smoke_current/transparent-cutout-fixture-scene-smoke-summary.txt` passed the fixed cutout fixture scene smoke with `cutout_fixture=roles`, `cutout_fixture_roles=5`, `cutout_fixture_leaf_blocks=4`, `cutout_fixture_opaque_blocks=1`, `cutout_fixture_dirty_observed=1`, `cutout_fixture_collision_hits=5`, `cutout_fixture_collision_misses=0`, `cutout_fixture_occlusion_probe_hit=1`, `cutout_fixture_queue_drained=1`, `cutout_fixture_adjacent_pair_blocks=2`, `cutout_fixture_adjacent_pair_block_id=5`, `cutout_fixture_adjacent_pair_same_material=1`, `cutout_fixture_adjacent_pair_neighbor=1`, `cutout_fixture_adjacent_pair_collision_hits=2`, `same_material_seam_policy=cutout_pair_visible_faces`, `transparent_requested=1`, `transparent_active=1`, `transparent_fallback=0`, `transparent_blocks=4`, `transparent_faces=17`, `transparent_draws=2`, `transparent_subchunks=2`, and `gpu_upload_fail=0`.
- `logs/gpu_transparent_cutout_fixture_scene_smoke_current/transparent-cutout-fixture-acceptance-summary.txt` passed the report-backed fixture gate and links the scene smoke to `logs/gpu_transparent_cutout_fixture_scene_smoke_current/gpu-terrain-cutout-fixture-report.txt`; it also emits `transparent_cutout_seam_culling_status=pass` for the same-material adjacent cutout pair.
- `logs/transparent_fixture_acceptance_suite_current/transparent-fixture-acceptance-suite-summary.txt` passed after refreshing the fixture scene smoke and deferred active/sorting preflight summaries; the legacy full-transparent fixture remains requested-but-fallback while cutout stays the only active prototype path.
- The runtime smoke passed with `transparent_requested=1`, `transparent_active=1`, `transparent_fallback=0`, `transparent_blocks=1`, `transparent_faces=5`, `transparent_draws=1`, `transparent_subchunks=1`, `gpu_upload_fail=0`, `terrain_samples=384` from the movement marker, and `ground_misses=0` from the movement summary.
- This is local macOS/Metal cutout-only evidence, not blended transparency, sorting, default-on, Windows validation, or external profiler evidence.

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
- While `GPU_TERRAIN_TRANSPARENT_IMPLEMENTED=false`, the legacy `RUMPELMC_GPU_TERRAIN_TRANSPARENT=1` env-on fixture must still report requested-but-fallback markers: `transparent_requested=1`, `transparent_active=0`, and `transparent_fallback=1`.
- A future active transparent path must prove `transparent_active=1`, `transparent_fallback=0`, `gpu_upload_fail=0`, non-sky terrain samples, opaque-depth occlusion, explicit collision-by-solidity behavior, and visible opaque faces next to transparent fixture blocks.
- CPU/GPU parity and external profiler evidence are required before the transparent path can move beyond fixture/prototype status.

Non-goals for this contract:

- No new production block ID, asset, protocol field, storage record, worldgen rule, shader alpha path, transparent pass, or sort implementation.
- No change to default opaque terrain rendering.

## Current Implementation Slice

The current code slice is a default-off cutout prototype, not blended rendering:

- `RUMPELMC_GPU_TERRAIN_TRANSPARENT` is reserved as a future opt-in flag.
- `GPU_TERRAIN_TRANSPARENT_IMPLEMENTED=false` keeps the requested flag inactive, so current runtime behavior stays opaque-only even when the env flag is set.
- `RUMPELMC_GPU_TERRAIN_CUTOUT_PROTOTYPE=1` activates only the cutout alpha-test prototype and does not make blended transparency active.
- Perf markers expose `transparent_requested`, `transparent_active`, and `transparent_fallback`.
- Perf markers expose current transparent workload fields: `transparent_blocks`, `transparent_faces`, `transparent_draws`, and `transparent_subchunks`. They stay `0` for the legacy transparent fallback path and become nonzero only for active default-off cutout workload.
- The Rust env flag parser and GPU terrain mesher now share the same cutout truthy contract for `1`, `true`, `yes`, `on`, and `enabled`; `disabled` is explicit false.
- Perf markers expose client-only fixture overlay metadata counts as `transparent_fixture_overlay_roles` and `transparent_fixture_overlay_blocks`. They are expected to stay `5` only when `RUMPELMC_GPU_TERRAIN_TRANSPARENT_FIXTURE_OVERLAY=1` is requested, and `0` otherwise.
- `scripts/gpu_terrain_report.sh` aggregates those marker fields and records metric origins.
- `scripts/gpu_terrain_cutout_prototype_acceptance_gate.sh` validates a default-off cutout block-edit smoke and requires the aggregate report to surface its selected acceptance summary.
- `scripts/gpu_terrain_cutout_pressure_load_scaling_gate.sh` validates the same default-off cutout path under high resident-set `pressure` world-loading evidence and requires the aggregate report to surface its selected pressure summary.
- The env-on release movement smoke in `logs/gpu_transparent_fallback_capture` passed with `transparent_requested=1`, `transparent_active=0`, `transparent_fallback=1`, `gpu_upload_fail=0`, `smoke_err=0`, and non-sky terrain samples.
- `scripts/gpu_terrain_movement_stress.sh` now fails env-on transparent captures unless those same requested/active/fallback marker values are present.
- `scripts/gpu_terrain_transparent_fixture_plan.sh` validates this fixture contract plus the current movement-stress fallback guard and writes a line-oriented `transparent-fixture-plan.txt` checklist.
- `scripts/gpu_terrain_transparent_fixture_harness.sh` consumes that plan and writes a placeholder `transparent-fixture-harness.txt` with env-off, env-on fallback, future marker, future active, and non-goal gates.
- `scripts/gpu_terrain_transparent_fixture_check.sh` validates the generated plan and harness summaries together and writes a line-oriented `transparent-fixture-check.txt` pass artifact.
- `scripts/gpu_terrain_report.sh` surfaces the latest transparent fixture plan, harness, and check artifacts under the selected log directory when they exist.
- `scripts/gpu_terrain_transparent_fixture_report_check.sh` validates that an aggregate GPU report includes the selected transparent fixture plan, harness, and check artifacts from the fixture directory.
- `scripts/gpu_terrain_transparent_fixture_pack.sh` regenerates the fixture plan, harness, check, smoke-plan, scene checklist, scene harness, scene harness-check, aggregate report, report-check, acceptance-check, default-off check, final-report check, scene implementation checklist, scene implementation gate-check, and refreshed aggregate report artifacts together without launching Godot.
- `scripts/gpu_terrain_transparent_fixture_smoke_plan.sh` consumes the pack and writes a no-render `transparent-fixture-smoke-plan.txt` with current fallback and future fixture scene gates.
- `scripts/gpu_terrain_transparent_fixture_scene_checklist.sh` consumes the smoke plan and writes a no-render `transparent-fixture-scene-checklist.txt` with fixed scene roles for depth, adjacency, and collision checks.
- `scripts/gpu_terrain_transparent_fixture_scene_harness.sh` consumes the scene checklist and writes a no-render `transparent-fixture-scene-harness.txt` placeholder with fixed role checks and current/future acceptance gates.
- `scripts/gpu_terrain_transparent_fixture_scene_harness_check.sh` validates the generated scene checklist and harness together and writes a no-render `transparent-fixture-scene-harness-check.txt` pass artifact; aggregate reports and report checks now surface this scene artifact chain.
- `scripts/gpu_terrain_transparent_fixture_acceptance_check.sh` validates the no-render pack, report-check, smoke-plan, and scene harness-check artifacts together before any real fixture scene or renderer path is allowed; the pack now emits and reports this acceptance artifact.
- `scripts/gpu_terrain_transparent_fixture_default_off_check.sh` validates the final no-render pack against the Rust implementation gate, the movement-stress env-on fallback guard, and the transparent fixture contract so `GPU_TERRAIN_TRANSPARENT_IMPLEMENTED=false` keeps env-on captures requested-but-fallback until a real implementation exists; the pack now emits and reports this default-off artifact.
- `scripts/gpu_terrain_transparent_fixture_final_report_check.sh` validates the final no-render pack and aggregate report together, requiring both selected acceptance and default-off report sections to point at the linked artifacts and surface their pass summaries; the pack now emits and reports this final guard artifact.
- `scripts/gpu_terrain_transparent_fixture_scene_implementation_checklist.sh` validates the final no-render pack and scene artifact chain, then writes a pending fixture-scene implementation checklist for the future scene-only harness work; the pack now emits and reports this checklist artifact.
- `scripts/gpu_terrain_transparent_fixture_scene_implementation_gate_check.sh` validates that the pending scene implementation checklist, linked pack, and aggregate report still keep the transparent implementation gate false with current env-on fallback and future active-path gates intact; the pack now emits and reports this gate-check artifact.
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

The current expected result is `status=pass`, `production_metadata_status=designed`, `active_schema_change=0`, and `current_runtime_contract=opaque_only`. Production transparent, liquid, emissive, collision, and render metadata remains registry design work until a separate migration slice updates both client and server block definitions without changing chunk wire/storage payloads.

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
