# Third Person Character Visual

This checkpoint owns the first finished third-person player visual slice.

## Technical Brief

Goal:

- Add a player-controlled first-person/third-person camera toggle.
- Attach a visible modular voxel character only in third-person mode.
- Load guarded Veloren voxygen RON manifests and MagicaVoxel `.vox` body parts with local attribution and license evidence.
- Drive procedural idle/run/jump poses from the player movement state.
- Keep block targeting functional in both camera modes.

Scope:

- Client Rust `Player` camera toggle, character visual construction, raycast reach adjustment, and procedural motion-state pose application.
- Rust-built `Node3D` pivots using Veloren-derived composed head, chest, belt, pants, hand, and foot meshes.
- Local Veloren-style RON manifest parsing for the selected Human/Male head, eyes, hair, beard, palette colors, default armor parts, and named armor map entries, backed by checked-in voxygen `.vox` files and no added `serde`/`ron` Cargo dependencies.
- Local MagicaVoxel parser/mesh builder coverage plus focused Rust unit tests and a gate that proves no packet, storage, world generation, or Godot scene/resource dependency is introduced.

Out of scope:

- No packet, storage, world generation, chunk serialization, server gameplay, GPU terrain renderer, draw-distance, lighting, shadow, texture-atlas, or texture-quality changes.
- No multiplayer avatar replication.
- No camera collision solver or over-shoulder aim offset beyond the guarded reach adjustment.

## Runtime Contract

- `V` toggles first-person and third-person camera mode.
- First-person mode uses the player eye height (`1.80m`) and hides the character visual.
- Third-person mode moves the camera behind the player and shows `PlayerVoxelCharacter`.
- The block raycast target is extended by the third-person camera offset and a small reach padding so current targeting still reaches the same gameplay envelope.
- `Player.is_third_person_camera_enabled()` exposes the current camera mode to Godot/tests.
- The character visual is built in Rust from named `Node3D` pivots and vertex-colored composed voxel mesh children.
- `client/rust_ext/src/veloren_composer.rs` owns the local Veloren Human/Male composition path, including color-manifest material mapping and DynaUnionizer-style hollow/override overlay rules, through a project-local parser over checked-in RON manifests from `client/assets/veloren/voxygen/voxel/`.
- If a manifest or `.vox` part cannot be read or parsed, that part falls back to a local `BoxMesh` shape without disabling the third-person character.
- Idle, run, and jump poses are applied procedurally to the same body pivots.
- Animation time wraps at a bounded interval so long sessions do not grow the pose timer without bound.

## Visual Contract

- The visual root name is `PlayerVoxelCharacter`.
- The visual root is hidden in first-person mode and visible in third-person mode.
- The local player scale is guarded as roughly `1.90m` total height with eyes/camera around `1.80m`.
- The Rust player source owns all visual dimensions, colors, animation rates, and motion-state thresholds.
- Character assets are limited to guarded Veloren-derived RON and MagicaVoxel `.vox` files under `client/assets/veloren/`.
- `client/assets/veloren/ATTRIBUTION.md` records the source commit, copied files, GPL-3.0-or-later license, and local integration notes.
- No FBX, PNG, Godot scene, Godot script, `.import`, `.uid`, or runtime Godot resource loader path is required for the character visual.
- The visual remains client presentation only and must not affect server authority.

## Checks

Use:

```sh
sh scripts/third_person_character_visual_gate.sh logs/third_person_character_visual_current
```

Expected current result:

- `status=pass`
- `third_person_visual=guarded`
- `camera_toggle=rust_guarded`
- `character_visual=veloren_composer_guarded`
- `character_assets=veloren_voxygen_guarded`
- `character_asset_license=gpl3_attributed`
- `character_animation=procedural_idle_run_jump_guarded`
- `veloren_composer=ron_manifest_guarded`
- `vox_loader=magica_vox_guarded`
- `rust_tests=pass`
- `godot_smoke=pass`
- `active_protocol_change=0`
- `active_storage_change=0`
- `active_worldgen_change=0`

## Compatibility Rules

- Do not change protocol or server authority for camera mode.
- Do not make third-person mode affect server reach validation.
- Do not remove first-person behavior.
- Do not add or swap character asset sources without attribution/license updates and a matching visual asset gate.
- Do not reintroduce a required Godot scene/resource/import path for the player character visual without a separate visual asset gate.
- Do not reduce render quality, draw distance, lighting, shadows, or texture quality for this visual slice.
