# GPU Native Terrain Shadow Path

This is the Phase 12 design checkpoint for replacing the current terrain shadow proxy with a GPU-native path. It is a design document only; current runtime behavior remains unchanged.

## Technical Brief

User request:

Continue GPU terrain work after the focused shadow proxy capture.

Goal:

Define the next safe GPU-native shadow path before changing renderer behavior.

Context inspected:

- `client/rust_ext/src/lib.rs` shadow path decision, shadow radius, proxy refresh, render mode, and perf marker fields.
- `client/rust_ext/src/gpu_terrain.rs` CPU proxy mesh builders.
- `scripts/gpu_terrain_compact_proxy_benchmark.sh` focused full/compact/disabled/collision-only capture gates.
- `docs/GPU_ROADMAP.md`, `docs/GPU_PROFILING.md`, `docs/GPU_TRENDS.md`, and `docs/AGENT_HANDOFF.md`.
- OntoIndex graph around `terrain_shadow_path_decision`, `current_terrain_shadow_path`, `enqueue_cpu_proxy_refresh`, and `build_indexed_compact_cpu_proxy_mesh`.

Scope:

- Design the rollout order, rollback gate, required telemetry, and correctness gates.

Out of scope:

- No Rust runtime, shader, Godot scene, protocol, storage, world generation, or quality changes.
- No default shadow behavior changes from local proxy counters alone.

Assumptions:

- Godot CPU shadow proxies remain the production path until a GPU-native path proves visual parity and better measured cost.
- `collision_only` and `scene_shadows_disabled` are diagnostic controls, not acceptable production substitutes for shadows.
- Local macOS/Metal FPS and Godot GPU timestamps remain report-only unless an external profiler confirms them.

Done when:

- The design states where the new path plugs in, how it rolls back, which metrics must exist, and which tests block default enablement.

Checks:

- Docs diff review, normal project checks, diff guard, OntoIndex freshness, and MCP pre-commit review.

## Current Production Contract

- `terrain_shadow_path_decision` reports `arraymesh` when GPU visible render is inactive, `godot_proxy` when GPU visible render is active and conservative shadow proxies are kept, `scene_shadows_disabled` when scene shadow distance is disabled, and `diagnostic_no_shadow_proxy` for collision-only diagnostic mode.
- `current_terrain_shadow_path` bases the active path on `gpu_terrain_visible_render_active`, `RUMPELMC_GPU_TERRAIN_SHADOW_PROXY_MODE`, and the shadow proxy radius derived from `DirectionalLight3D.SHADOW_MAX_DISTANCE`.
- `subchunk_needs_shadow_proxy` and `chunk_needs_cpu_proxy_refresh` decide which loaded subchunks/chunks still need CPU proxy refreshes for shadow coverage.
- `configure_terrain_mesh_render_mode` sets Godot `MeshInstance3D` shadow casting. Shadow proxies use `SHADOWS_ONLY`; collision-only proxies have shadows off.
- `TerrainCpuProxyMeshPayload` and `PackedFaceBatch` already support full, compact, and indexed compact CPU proxy meshes. These reduce proxy payload but still rely on Godot CPU mesh instances to participate in shadows.
- Perf text already publishes `shadow_path`, `native_shadow_requested`, `native_shadow_active`, `native_shadow_fallback`, `native_shadow_implemented`, `native_shadow_resource_status`, native-shadow resource descriptor format/usage labels, pass/sampler/depth-bias/viewport/pipeline/draw/uniform-binding/shader/light descriptor fields, native-shadow resource lifecycle counters, native-shadow coverage counters, `shadow_mode`, `shadow_mesh`, `proxy_shadow`, `proxy_shadow_only`, `compact_shadow_proxy`, and compact normal savings counters.

## Proposed Rollout

1. Keep the current `godot_proxy` path as default.
2. Add a future explicit rollback flag for any prototype, for example `RUMPELMC_GPU_TERRAIN_NATIVE_SHADOW=0/1`, with default off until parity and profiler evidence exist.
3. Split the future path selection from diagnostic no-shadow modes. The path should be one of:
   - `godot_proxy`: current production fallback.
   - `gpu_native_shadow`: future opt-in path with real terrain shadow participation.
   - `scene_shadows_disabled`: scene-level disabled shadows.
   - `diagnostic_no_shadow_proxy`: collision-only diagnostic mode.
4. Reuse the existing shadow radius calculation and chunk-role refresh rules so visible shadow distance remains tied to `SunLight.SHADOW_MAX_DISTANCE`.
5. Keep CPU collision proxies independent from shadow participation. A GPU-native shadow prototype must not remove collision refresh or collision-only mesh behavior.
6. Add telemetry before changing defaults:
   - count of chunks/subchunks covered by `gpu_native_shadow`;
   - fallback count back to `godot_proxy`;
   - shadow path per marker;
   - external profiler artifact identity when available.
7. Add a shadow correctness smoke before default enablement. It should compare current `godot_proxy` against the prototype under the existing lighting/shadow poses and reject large `avg_luma`, terrain sample, or shadow metadata deltas.

## Prototype Options

### Option A: Godot-Compatible Shadow Emitter

Create a small Godot-side shadow-only representation generated from GPU terrain metadata, but still registered with Godot's normal shadow pass. This is the safest first prototype because it preserves Godot's light/shadow integration and rollback is straightforward.

Risk:

- It may still require CPU-side geometry or buffer readback, so the benefit must be measured against the current compact proxy.

### Option B: RenderingDevice Shadow Atlas Integration

Render terrain directly into a shadow target with the existing packed face buffer and terrain shader data, then feed or composite that result into the scene shadowing path.

Risk:

- This is higher risk because Godot's built-in shadow atlas is not currently owned by the Rust compositor path. Do not start here without a narrow proof that integration is possible without breaking Godot lighting.

### Option C: Keep Compact Proxy, Reduce Refresh Scope

Before a true native path, reduce proxy rebuilds only when chunk-role transitions prove the old proxy can satisfy the new role. This is not GPU-native, but it can reduce CPU work while keeping current shadows.

Risk:

- It must preserve `proxy_refresh_reuse`, collision refresh, and shadow-only correctness, and should remain behind the existing proxy mesh controls.

## Default-On Gates

A future GPU-native shadow path can become default only after all of these are true:

- Current `godot_proxy` remains available as a runtime rollback.
- The prototype preserves draw distance, lighting, shadow distance, texture quality, and visible terrain quality.
- Visual parity passes against `lighting_shadow` and `lighting_shadow_compact` poses.
- `gpu_upload_fail=0`, terrain samples stay non-sky, and marker generation remains stable.
- Focused shadow benchmark reports the prototype path separately from diagnostic no-shadow modes.
- An external Metal, RenderDoc, PIX, or vendor-profiler capture shows better shadow pass or CPU submit cost than the current compact proxy path.
- `./scripts/check.sh fast`, `./scripts/diff_guard.sh`, and targeted Rust tests pass for the implementation slice.

## Next Implementation Slice

The current code slice is telemetry/test scaffolding, not a renderer rewrite:

- `GpuTerrainShadowPath::GpuNativeShadow` reserves the future marker token `gpu_native_shadow`.
- `RUMPELMC_GPU_TERRAIN_NATIVE_SHADOW` is off by default and is additionally blocked by `GPU_TERRAIN_NATIVE_SHADOW_IMPLEMENTED=false`, so current runtime markers remain on `godot_proxy` even if the env flag is set.
- Perf markers and `scripts/gpu_terrain_report.sh` expose `native_shadow_requested`, `native_shadow_active`, `native_shadow_fallback`, and `native_shadow_implemented`, so future captures can show when the env flag was requested without implying the native path actually ran.
- `GpuNativeShadowResources` is a state-only lifecycle scaffold for future shadow-map resources. It tracks descriptor create/reuse/replace/release decisions from `native_shadow_active`, visible GPU terrain state, conservative shadow mode, and shadow radius, but it does not allocate RenderingDevice RIDs or change the scene while `GPU_TERRAIN_NATIVE_SHADOW_IMPLEMENTED=false`.
- `terrain_godot_shadow_proxy_chunk_distance` keeps the future native renderer path distinct from the current Godot proxy fallback: when `native_shadow_active=true`, the marker path can be `gpu_native_shadow` while the Godot shadow-proxy refresh radius is `0`; while the implementation gate remains false, current `godot_proxy` behavior is unchanged.
- `terrain_shadow_path_decision` tests stay explicit for production, disabled, diagnostic, and future prototype paths.
- `scripts/gpu_terrain_compact_proxy_benchmark.sh` validates shadow-casting paths through a helper that accepts only `godot_proxy` and future `gpu_native_shadow`, keeping them separate from `scene_shadows_disabled` and `diagnostic_no_shadow_proxy`.
- `scripts/gpu_terrain_parity_smoke.sh` prepares the requested Godot Rust extension profile before full captures, requires that profile in fresh marker files, and normalizes relative output directories to the repo root before passing screenshot paths to Godot.
- The parity smoke now includes `gpu-terrain-native-shadow-fallback-parity`, which runs with `RUMPELMC_GPU_TERRAIN_NATIVE_SHADOW=1` and requires `shadow_path=godot_proxy`, `native_shadow_requested=1`, `native_shadow_active=0`, `native_shadow_fallback=1`, and `native_shadow_implemented=0` while the implementation gate remains false.
- No CPU proxy mesh builder or Godot `SHADOWS_ONLY` fallback was removed.
- Fresh release movement capture in `logs/gpu_native_shadow_requested_active_capture` reports `shadow_path=godot_proxy`, `native_shadow_requested=0`, and `native_shadow_active=0`; the aggregate report now resolves both native-shadow fields to `0.000` with metric origins instead of `n/a`.
- Fresh env-on rollback capture in `logs/gpu_native_shadow_fallback_capture` reports `shadow_path=godot_proxy`, `native_shadow_requested=1`, `native_shadow_active=0`, and `native_shadow_fallback=1`; this confirms the current env flag still falls back to Godot proxy shadows until the implementation gate changes.
- Fresh release movement capture in `logs/gpu_native_shadow_resource_lifecycle_20260614` reports `shadow_path=godot_proxy`, `native_shadow_requested=1`, `native_shadow_active=0`, `native_shadow_fallback=1`, `native_shadow_implemented=0`, `native_shadow_resource_status=disabled`, and zero create/reuse/replace/release counters.
- Fresh release parity capture in `logs/gpu_native_shadow_resource_lifecycle_parity_20260614` passed 17 cases. Its fallback case reports `shadow_path=godot_proxy`, `native_shadow_requested=1`, `native_shadow_active=0`, `native_shadow_fallback=1`, `native_shadow_implemented=0`, `native_shadow_resource_status=disabled`, and zero resource create/replace/release counters, with a zero visual metric delta against the ordinary GPU terrain case.
- Fresh release movement capture in `logs/gpu_native_shadow_coverage_scaffold_20260614` reports `shadow_path=godot_proxy`, `native_shadow_requested=1`, `native_shadow_active=0`, `native_shadow_fallback=1`, `native_shadow_implemented=0`, `native_shadow_resource_status=disabled`, zero resource lifecycle counters, and zero `native_shadow_covered_chunks/subchunks`.
- Fresh release movement capture in `logs/gpu_native_shadow_summary_fields_20260614` writes the same env-on fallback and zero lifecycle/coverage proof into a compact `movement_native_shadow` summary row, so reports can cite the native-shadow summary without reading the full `.png.txt` marker.
- The native-shadow resource descriptor now records future shadow-map allocation labels as `native_shadow_resource_format=d32_sfloat` and `native_shadow_resource_usage=depth_stencil_attachment|sampling`; disabled resources report `none` labels and still do not allocate RenderingDevice RIDs while `GPU_TERRAIN_NATIVE_SHADOW_IMPLEMENTED=false`.
- The native-shadow resource descriptor now records future texture extent labels as `native_shadow_resource_width=2048`, `native_shadow_resource_height=2048`, and `native_shadow_resource_layers=1` for active descriptor tests; disabled resources report `0/0/0` and still do not allocate RenderingDevice RIDs while `GPU_TERRAIN_NATIVE_SHADOW_IMPLEMENTED=false`.
- Fresh release movement capture in `logs/gpu_native_shadow_resource_extent_20260614` reports `shadow_path=godot_proxy`, `native_shadow_requested=1`, `native_shadow_active=0`, `native_shadow_fallback=1`, `native_shadow_implemented=0`, `native_shadow_resource_status=disabled`, and zero resource extent/byte/lifecycle/coverage markers.
- The native-shadow resource descriptor now records future depth pass labels as `native_shadow_pass_load_op=clear`, `native_shadow_pass_store_op=store`, and `native_shadow_pass_clear_depth_milli=1000` for active descriptor tests; disabled resources report `none/none/0` and still do not allocate RenderingDevice RIDs while `GPU_TERRAIN_NATIVE_SHADOW_IMPLEMENTED=false`.
- Fresh release movement capture in `logs/gpu_native_shadow_pass_descriptor_20260614` reports `shadow_path=godot_proxy`, `native_shadow_requested=1`, `native_shadow_active=0`, `native_shadow_fallback=1`, `native_shadow_implemented=0`, `native_shadow_resource_status=disabled`, and zero resource/pass/lifecycle/coverage markers.
- The native-shadow resource descriptor now records future depth sampler labels as `native_shadow_sampler_filter=linear`, `native_shadow_sampler_address=clamp_to_edge`, `native_shadow_sampler_compare_op=less_equal`, and `native_shadow_sampler_compare_enabled=1` for active descriptor tests; disabled resources report `none/none/none/0` and still do not allocate RenderingDevice RIDs while `GPU_TERRAIN_NATIVE_SHADOW_IMPLEMENTED=false`.
- The native-shadow resource descriptor now records future depth bias labels as `native_shadow_depth_bias_constant_milli=2`, `native_shadow_depth_bias_slope_milli=1500`, and `native_shadow_depth_bias_clamp_milli=0` for active descriptor tests; disabled resources report `0/0/0` and still do not allocate RenderingDevice RIDs while `GPU_TERRAIN_NATIVE_SHADOW_IMPLEMENTED=false`.
- The native-shadow resource descriptor now records future viewport labels as `native_shadow_viewport_x_px=0`, `native_shadow_viewport_y_px=0`, `native_shadow_viewport_width_px=2048`, `native_shadow_viewport_height_px=2048`, `native_shadow_viewport_min_depth_milli=0`, and `native_shadow_viewport_max_depth_milli=1000` for active descriptor tests; disabled resources report `0/0/0/0/0/0` and still do not allocate RenderingDevice RIDs while `GPU_TERRAIN_NATIVE_SHADOW_IMPLEMENTED=false`.
- The native-shadow resource descriptor now records future depth pipeline labels as `native_shadow_pipeline_depth_test_enabled=1`, `native_shadow_pipeline_depth_write_enabled=1`, `native_shadow_pipeline_cull_mode=back`, and `native_shadow_pipeline_front_face=clockwise` for active descriptor tests; disabled resources report `0/0/none/none` and still do not allocate RenderingDevice RIDs while `GPU_TERRAIN_NATIVE_SHADOW_IMPLEMENTED=false`.
- The native-shadow resource descriptor now records future draw/input labels as `native_shadow_draw_source=packed_faces`, `native_shadow_draw_primitive=triangles`, `native_shadow_draw_face_stride_bytes=16`, `native_shadow_draw_command_stride_bytes=16`, and `native_shadow_draw_indirect_enabled=1` for active descriptor tests; disabled resources report `none/none/0/0/0` and still do not submit RenderingDevice draw calls while `GPU_TERRAIN_NATIVE_SHADOW_IMPLEMENTED=false`.
- The native-shadow resource descriptor now records future uniform/binding labels as `native_shadow_uniform_set_index=0`, `native_shadow_face_buffer_binding=0`, `native_shadow_push_constant_bytes=64`, and `native_shadow_texture_sampling_enabled=0` for active descriptor tests; disabled resources report `0/0/0/0` and still do not allocate shader/pass/RID/draw resources while `GPU_TERRAIN_NATIVE_SHADOW_IMPLEMENTED=false`.
- The native-shadow resource descriptor now records future shader labels as `native_shadow_shader_language=glsl`, `native_shadow_shader_entry=native_shadow_depth`, `native_shadow_shader_depth_output_enabled=1`, and `native_shadow_shader_color_output_enabled=0` for active descriptor tests; disabled resources report `none/none/0/0` and still do not compile shaders or allocate shader/pass/RID/draw resources while `GPU_TERRAIN_NATIVE_SHADOW_IMPLEMENTED=false`.
- The native-shadow resource descriptor now records future light/matrix labels as `native_shadow_light_source=directional_light`, `native_shadow_light_space=world_to_shadow`, `native_shadow_cascade_count=1`, and `native_shadow_light_matrix_bytes=64` for active descriptor tests; disabled resources report `none/none/0/0` and still do not bind light matrices or allocate shader/pass/RID/draw resources while `GPU_TERRAIN_NATIVE_SHADOW_IMPLEMENTED=false`.

The next implementation slice can keep measuring the current compact proxy path with an external profiler, or start a tiny renderer proof only after the fallback and parity gates above are kept intact.
