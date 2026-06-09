# Agent Handoff State

This file is the current continuation state for Codex threads. Update it after non-trivial work, before delegating to another chat, or before stopping in the middle of a task.

## Latest Snapshot

Date: 2026-06-09

Goal:

- Continue performance optimization toward stable high FPS without reducing draw distance, lighting, shadows, or visible quality.
- Current technical direction is GPU-resident terrain on Godot RenderingDevice, compatible with macOS and Windows.

Done:

- Added GPU terrain upload/render prototype behind `RUMPELMC_GPU_TERRAIN_RENDER=1`.
- Added Godot compositor integration that attaches to the player camera and draws GPU terrain into the scene color target.
- Added GPU terrain texture atlas sampling from `res://assets/textures/blocks/block_texture_atlas.png`.
- Kept the current GPU terrain solid-block pass opaque; atlas alpha is not used for block opacity until transparent block metadata and a dedicated transparency path exist.
- Moved GPU terrain atlas layout from a hard-coded shader column count into Rust-validated atlas metadata pushed to the render shader; the current atlas is validated as 64px tiles, 10 columns, 1 row.
- Made the GPU terrain atlas texture prefer `R8G8B8A8_SRGB` sampling for closer albedo parity with Godot materials, with a guarded fallback to `R8G8B8A8_UNORM` if the backend rejects sRGB sampling.
- Made the opt-in GPU terrain compositor path depth-compatible by requesting resolved depth, binding a color+depth framebuffer, and enabling depth test/write for scene rendering.
- Fixed the GPU compositor depth test for Godot 4.6 reverse-Z by using `GREATER_OR_EQUAL`; `LESS_OR_EQUAL` could produce sky-only screenshots even while GPU draw counters advanced.
- Added a lighting-aware GPU terrain slice: the Rust client reads the scene `SunLight` direction/color/energy, passes it through GPU terrain push constants, and the GPU terrain shader shades block faces from per-face normals with directional diffuse plus ambient.
- Added a conservative shadow-compatibility slice: terrain `MeshInstance3D` shadow casting is explicitly configured as double-sided, so the retained ArrayMesh terrain can serve as the Godot shadow-map proxy while the opt-in GPU RD compositor path handles visible terrain rendering.
- Added an opt-in GPU render bridge where CPU ArrayMesh subchunk nodes switch to Godot `SHADOWS_ONLY` after the GPU compositor is attached and the GPU render pipeline is ready, preserving fallback visibility if GPU render setup fails.
- Added the first safe CPU ArrayMesh reduction step for the opt-in GPU path: after GPU upload, distant subchunks that do not need local collision or a Godot shadow proxy drop their CPU `MeshInstance3D` while keeping the GPU slot intact.
- Added a delayed visible-path transition: CPU fallback/proxy nodes are not hidden or removed until the GPU compositor has produced at least one frame, and a subchunk keeps CPU fallback if its GPU upload did not produce a slot.
- Added a GPU-visible refresh so existing CPU subchunk nodes are re-evaluated once the GPU compositor becomes the confirmed visible terrain path, instead of waiting for later player movement or chunk updates.
- Added a faster CPU shadow/collision proxy path for opt-in GPU terrain: after successful GPU upload and confirmed GPU visible rendering, retained CPU proxy `ArrayMesh` geometry is built directly from `PackedFaceBatch` vertices/normals instead of rerunning the full compute mesher/readback/UV path.
- Kept visible CPU fallback behavior unchanged: CPU-only rendering and failed GPU uploads still use the existing compute mesher with UVs/materials.
- Added visual smoke capture hooks in `client/main.gd` through `RUMPELMC_VISUAL_SMOKE_PATH`, `RUMPELMC_VISUAL_SMOKE_DELAY_SEC`, and `RUMPELMC_VISUAL_SMOKE_HIDE_HUD`.
- Strengthened visual smoke validation with `terrain_samples` and `smoke_err`; sky-only frames now fail even if the image is bright and GPU counters are nonzero.
- Added `scripts/gpu_terrain_visual_smoke.sh` as a CPU/GPU smoke wrapper; in the current Codex PTY environment direct Godot commands are the reliable gate because the wrapper can stall before project logs appear.
- Added `scripts/gpu_terrain_parity_smoke.sh` as a CPU/GPU/radius=1 parity gate. It validates marker files for `smoke_err=0`, terrain samples, CPU fallback counters, GPU counters, fast proxy usage, radius=1 proxy/collision parity, and a conservative CPU/GPU luma/terrain-sample envelope.
- Added `RUMPELMC_VISUAL_SMOKE_DISABLE_PLAYER_INPUT=1` for automated visual smokes so player input does not accidentally break/place blocks and mutate the world during capture.
- Added GPU terrain log/perf visibility, including `gpu_frames`.
- Kept ArrayMesh terrain fallback active.
- Added this handoff system: `docs/HANDOFF.md`, `docs/AGENT_HANDOFF.md`, and `scripts/handoff.sh`.

Relevant files:

- `client/rust_ext/src/gpu_terrain.rs`
- `client/rust_ext/src/lib.rs`
- `client/rust_ext/src/player.rs`
- `client/shaders/gpu_terrain_render.glsl`
- `scripts/gpu_terrain_visual_smoke.sh`
- `scripts/gpu_terrain_parity_smoke.sh`
- `logs/gpu_terrain_visual_smoke/direct-cpu.png`
- `logs/gpu_terrain_visual_smoke/direct-cpu.png.txt`
- `logs/gpu_terrain_visual_smoke/direct-cpu-smoke-gate.png`
- `logs/gpu_terrain_visual_smoke/direct-cpu-smoke-gate.png.txt`
- `logs/gpu_terrain_visual_smoke/direct-gpu.png`
- `logs/gpu_terrain_visual_smoke/direct-gpu.png.txt`
- `logs/gpu_terrain_visual_smoke/direct-gpu-reverse-z.png`
- `logs/gpu_terrain_visual_smoke/direct-gpu-reverse-z.png.txt`
- `logs/gpu_terrain_visual_smoke/direct-gpu-reverse-z-proxy-radius1.png`
- `logs/gpu_terrain_visual_smoke/direct-gpu-reverse-z-proxy-radius1.png.txt`
- `logs/gpu_terrain_visual_smoke/direct-gpu-fast-proxy-final.png`
- `logs/gpu_terrain_visual_smoke/direct-gpu-fast-proxy-final.png.txt`
- `logs/gpu_terrain_visual_smoke/direct-gpu-fast-proxy-radius1-final.png`
- `logs/gpu_terrain_visual_smoke/direct-gpu-fast-proxy-radius1-final.png.txt`
- `logs/gpu_terrain_visual_smoke/direct-cpu-fast-proxy-final.png`
- `logs/gpu_terrain_visual_smoke/direct-cpu-fast-proxy-final.png.txt`
- `logs/gpu_terrain_visual_smoke/parity/cpu-arraymesh-parity.png`
- `logs/gpu_terrain_visual_smoke/parity/cpu-arraymesh-parity.png.txt`
- `logs/gpu_terrain_visual_smoke/parity/gpu-terrain-parity.png`
- `logs/gpu_terrain_visual_smoke/parity/gpu-terrain-parity.png.txt`
- `logs/gpu_terrain_visual_smoke/parity/gpu-terrain-radius1-parity.png`
- `logs/gpu_terrain_visual_smoke/parity/gpu-terrain-radius1-parity.png.txt`
- `logs/godot-gpu-terrain-smoke.log`
- `logs/godot-gpu-terrain-atlas-smoke.log`
- `logs/godot-gpu-terrain-depth-smoke.log`
- `logs/godot-gpu-terrain-lighting-smoke.log`
- `logs/godot-gpu-terrain-shadow-proxy-smoke.log`
- `logs/godot-gpu-terrain-opaque-smoke.log`
- `logs/godot-gpu-terrain-atlas-layout-smoke.log`
- `logs/godot-gpu-terrain-atlas-layout-shadow-proxy-smoke.log`
- `logs/godot-gpu-terrain-srgb-atlas-shadow-proxy-smoke.log`
- `docs/HANDOFF.md`
- `scripts/handoff.sh`

Checks:

- `RUMPELMC_USE_SCCACHE=0 ./scripts/check.sh full` passed after the shadow-proxy slice.
- `RUMPELMC_USE_SCCACHE=0 ./scripts/check.sh full` passed after the lighting-aware GPU terrain slice.
- `./scripts/check.sh full` passed after the GPU compositor changes.
- `RUMPELMC_USE_SCCACHE=0 ./scripts/check.sh full` passed after atlas/depth work.
- `./scripts/check.sh full` with sccache failed locally with `sccache: error: Operation not permitted (os error 1)`; rerun without sccache passed.
- `cargo fmt -- --check`, `cargo build`, `cargo check`, and `cargo test` passed in `client/rust_ext`; Rust tests: 7/7.
- `cargo build --manifest-path client/rust_ext/Cargo.toml` passed.
- Godot smoke passed with `RUMPELMC_GPU_TERRAIN_RENDER=1`.
- Godot atlas smoke passed with `RUMPELMC_GPU_TERRAIN_RENDER=1`.
- Godot depth smoke passed with `RUMPELMC_GPU_TERRAIN_RENDER=1`.
- Godot lighting smoke passed with `RUMPELMC_GPU_TERRAIN_RENDER=1`.
- Godot shadow-proxy smoke passed with `RUMPELMC_GPU_TERRAIN_RENDER=1`.
- Godot opaque solid-block smoke passed with `RUMPELMC_GPU_TERRAIN_RENDER=1`.
- Godot atlas-layout smoke passed with `RUMPELMC_GPU_TERRAIN_RENDER=1`.
- Godot atlas-layout plus shadow-proxy bridge smoke passed with `RUMPELMC_GPU_TERRAIN_RENDER=1`.
- Godot sRGB atlas plus shadow-proxy bridge smoke passed with `RUMPELMC_GPU_TERRAIN_RENDER=1`; no UNORM fallback warning was observed on the local Metal backend.
- Direct CPU visual smoke passed with `RUMPELMC_GPU_TERRAIN_RENDER=0`, screenshot and marker saved under `logs/gpu_terrain_visual_smoke/`.
- Direct GPU visual smoke passed with `RUMPELMC_GPU_TERRAIN_RENDER=1`, screenshot and marker saved under `logs/gpu_terrain_visual_smoke/`; marker included nonzero `gpu_frames`, `gpu_subchunks`, `gpu_draws`, and `gpu_faces`.
- Direct GPU visual smoke passed after the reverse-Z depth fix: `direct-gpu-reverse-z.png`, `terrain_samples=576`, `smoke_err=0`, `gpu_frames=160`, `gpu_subchunks=88`, `gpu_faces=143452`.
- Direct GPU proxy-reduction smoke passed with `RUMPELMC_GPU_TERRAIN_SHADOW_PROXY_CHUNK_DISTANCE=1`: `direct-gpu-reverse-z-proxy-radius1.png`, `cpu_proxy=10`, `collision=10`, `gpu_subchunks=92`, `terrain_samples=288`, `smoke_err=0`.
- Direct CPU visual smoke passed after the strengthened visual gate: `direct-cpu-smoke-gate.png`, `terrain_samples=288`, `smoke_err=0`, `current_chunk="0,0"`.
- Latest `RUMPELMC_USE_SCCACHE=0 ./scripts/check.sh full` passed after the reverse-Z/fallback-transition/smoke-gate fixes; `golangci-lint` is not installed locally and was skipped by the script.
- Latest Rust fast-proxy checks passed in `client/rust_ext`: `cargo fmt -- --check`, `cargo check`, `cargo test` (10/10), and `cargo build`.
- Latest `RUMPELMC_USE_SCCACHE=0 ./scripts/check.sh full` passed after the fast CPU proxy slice; `golangci-lint` is not installed locally and was skipped by the script.
- Direct GPU fast-proxy smoke passed with `RUMPELMC_GPU_TERRAIN_RENDER=1`: `direct-gpu-fast-proxy-final.png`, `terrain_samples=288`, `smoke_err=0`, `gpu_frames=190`, `gpu_subchunks=90`, `gpu_faces=145506`, `fast_proxy=163`.
- Direct GPU fast-proxy radius smoke passed with `RUMPELMC_GPU_TERRAIN_RENDER=1` and `RUMPELMC_GPU_TERRAIN_SHADOW_PROXY_CHUNK_DISTANCE=1`: `direct-gpu-fast-proxy-radius1-final.png`, `cpu_proxy=10`, `collision=10`, `fast_proxy=20`, `terrain_samples=288`, `smoke_err=0`, `gpu_frames=195`.
- Direct CPU fallback smoke passed with `RUMPELMC_GPU_TERRAIN_RENDER=0`: `direct-cpu-fast-proxy-final.png`, `terrain_samples=288`, `smoke_err=0`, `fast_proxy=0`, `current_chunk="0,0"`.
- Latest parity smoke artifacts passed on the final Rust build with player input disabled:
  - CPU fallback: `parity/cpu-arraymesh-parity.png`, `terrain_samples=256`, `avg_luma=0.3517`, `smoke_err=0`, `fast_proxy=0`, `collision=10`.
  - GPU terrain: `parity/gpu-terrain-parity.png`, `terrain_samples=256`, `avg_luma=0.3442`, `smoke_err=0`, `gpu_frames=68`, `gpu_subchunks=48`, `gpu_faces=80994`, `fast_proxy=62`, `collision=10`.
  - GPU radius=1: `parity/gpu-terrain-radius1-parity.png`, `terrain_samples=256`, `avg_luma=0.3442`, `smoke_err=0`, `gpu_frames=74`, `cpu_proxy=10`, `collision=10`, `fast_proxy=19`.
- `RUMPELMC_PARITY_SMOKE_VALIDATE_ONLY=1 ./scripts/gpu_terrain_parity_smoke.sh` passed against the latest parity artifacts.
- `sh -n scripts/gpu_terrain_parity_smoke.sh` passed.
- `sh -n scripts/gpu_terrain_visual_smoke.sh` passed after adding wrapper checks for `smoke_err=0` and nonzero `terrain_samples`.
- `scripts/gpu_terrain_visual_smoke.sh` passed `sh -n`, but can time out in this Codex PTY environment before Godot project logs appear. Prefer the direct `/opt/homebrew/bin/timeout ... /usr/bin/env ... /opt/homebrew/bin/godot --path client ...` commands for the current gate.
- `sh -n scripts/handoff.sh` passed.
- `./scripts/handoff.sh` ran successfully and printed the continuation snapshot.
- Latest `RUMPELMC_USE_SCCACHE=0 ./scripts/check.sh full` passed after the parity smoke slice; `golangci-lint` is not installed locally and was skipped by the script.
- Latest `./scripts/diff_guard.sh` exited 1 because the repository already has a broad dirty tree: 51 tracked files, 6882 tracked lines, Godot `.import/.uid` files, and sensitive paths.

Useful log lines:

- `GPU terrain compositor initialized`
- `GPU terrain compositor attached to player camera`
- `GPU terrain compositor draw: size=1280x720 views=1 draws=2 faces=7242`
- `GPU terrain compositor draw: size=1280x720 views=1 depth=true draws=2 faces=7242`
- `Visual smoke screenshot saved ... current_chunk="0,0"`
- `perf="... gpu_subchunks=66 gpu_draws=66 gpu_faces=116824 gpu_frames=116 ..."`
- `GPU terrain visible path confirmed`
- `Visual smoke screenshot saved ... terrain_samples=576 ... smoke_err=0 ... gpu_frames=160 ...`
- `Visual smoke screenshot saved ... terrain_samples=288 ... smoke_err=0 ... cpu_proxy=10 collision=10 ... gpu_subchunks=92 ...`
- `Visual smoke screenshot saved ... terrain_samples=288 ... smoke_err=0 ... current_chunk="0,0"` for CPU fallback.
- `Visual smoke screenshot saved ... terrain_samples=288 ... smoke_err=0 ... fast_proxy=163 ... gpu_frames=190 ...`
- `Visual smoke screenshot saved ... terrain_samples=288 ... smoke_err=0 ... cpu_proxy=10 collision=10 fast_proxy=20 ... gpu_frames=195 ...`
- `Visual smoke screenshot saved ... terrain_samples=288 ... smoke_err=0 ... fast_proxy=0 ... current_chunk="0,0"` for CPU fallback.
- `Visual smoke screenshot saved ... parity/cpu-arraymesh-parity.png ... avg_luma=0.3517 ... terrain_samples=256 ... smoke_err=0 ... fast_proxy=0 collision=10 ...`
- `Visual smoke screenshot saved ... parity/gpu-terrain-parity.png ... avg_luma=0.3442 ... terrain_samples=256 ... smoke_err=0 ... fast_proxy=62 ... gpu_frames=68 ...`
- `Visual smoke screenshot saved ... parity/gpu-terrain-radius1-parity.png ... terrain_samples=256 ... smoke_err=0 ... cpu_proxy=10 fast_proxy=19 collision=10 ... gpu_frames=74 ...`

Known limitations:

- GPU terrain render is still opt-in via `RUMPELMC_GPU_TERRAIN_RENDER=1`.
- GPU terrain now samples the real block texture atlas and applies directional lighting, but visual parity still needs shadow integration and visual tuning.
- GPU terrain solid blocks force opaque alpha in the shader; do not infer grass/solid block transparency from the RGBA atlas alpha.
- GPU terrain shader atlas UVs now use runtime atlas layout push constants instead of a hard-coded column count.
- GPU terrain atlas texture now prefers sRGB sampling; color parity should still be visually compared against the ArrayMesh fallback before deleting more CPU rendering.
- Depth-compatible scene rendering is wired and smoke-tested with Godot 4.6 reverse-Z depth compare.
- GPU terrain is now directional-light aware, and retained ArrayMesh terrain is explicitly configured as a double-sided Godot shadow caster proxy.
- With `RUMPELMC_GPU_TERRAIN_RENDER=1`, CPU ArrayMesh nodes become `SHADOWS_ONLY` only after the GPU visible render path has rendered at least one compositor frame; this avoids double visible terrain while preserving fallback if GPU setup fails or a subchunk fails GPU upload.
- With `RUMPELMC_GPU_TERRAIN_RENDER=1`, CPU ArrayMesh nodes are still kept where needed for nearby collision and the conservative Godot shadow-map proxy. Distant CPU `MeshInstance3D` removal has started, but the retained proxy radius is intentionally conservative.
- With `RUMPELMC_GPU_TERRAIN_RENDER=1`, retained CPU proxy meshes can now be built from packed GPU terrain faces after the GPU visible path is confirmed. These proxy meshes intentionally omit UVs because they are used for collision and `SHADOWS_ONLY`, not visible terrain.
- `scripts/gpu_terrain_parity_smoke.sh` can validate existing artifacts with `RUMPELMC_PARITY_SMOKE_VALIDATE_ONLY=1`. In this Codex PTY environment, launching Godot through shell wrappers can still stall before project logs appear, so direct Godot commands plus validate-only are the reliable local gate.
- The custom RD compositor draw still does not natively participate in Godot shadow maps as a real shadow caster/receiver. Full shadow parity without ArrayMesh proxy needs a separate render integration plan.
- Final ArrayMesh replacement for distant terrain is not finished.
- The working tree contains many unrelated modified/untracked files; do not revert user or prior-agent changes.

Next steps:

1. After any GPU terrain edit, run the parity gate: direct CPU/GPU/radius=1 visual smoke captures with `RUMPELMC_VISUAL_SMOKE_DISABLE_PLAYER_INPUT=1`, then `RUMPELMC_PARITY_SMOKE_VALIDATE_ONLY=1 ./scripts/gpu_terrain_parity_smoke.sh`.
2. Tighten the CPU shadow-proxy strategy only after parity stays stable: keep a conservative invisible/nearby ArrayMesh proxy, build a lower-cost dedicated shadow proxy, or implement native shadow-map participation for the custom RD path. Do not disable the ArrayMesh shadow proxy until the replacement is verified.
3. Expand parity validation toward real shadow behavior and atlas orientation/depth checks beyond the current luma/terrain-sample envelope.
4. Continue reducing CPU ArrayMesh generation for distant chunks while preserving nearby collision meshes, shadow proxy requirements, and the fallback path.
5. Run `RUMPELMC_USE_SCCACHE=0 ./scripts/check.sh full`, parity visual smoke validation, and `./scripts/diff_guard.sh` before handing off again.
