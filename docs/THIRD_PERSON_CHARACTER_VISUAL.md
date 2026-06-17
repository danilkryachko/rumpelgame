# Third Person Character Visual

This checkpoint owns the first finished third-person player visual slice.

## Technical Brief

Goal:

- Add a player-controlled first-person/third-person camera toggle.
- Attach a visible modular voxel character only in third-person mode.
- Load guarded Biomes character skeleton, wearable slots, reserved palette ranges, MagicaVoxel `.vox` base model, and source character animation GLTF with local attribution and license evidence.
- Drive procedural idle/run/jump poses from the player movement state.
- Allow local appearance preset cycling for skin, eye, and hair palette IDs.
- Expose a HUD character creator menu for local appearance and all Biomes source animation clips.
- Keep block targeting functional in both camera modes.

Scope:

- Client Rust `Player` camera toggle, character visual construction, raycast reach adjustment, and procedural motion-state pose application.
- Rust-built `Node3D` pivots using Biomes-derived head, chest, waist, arm, forearm, hand, thigh, leg, and foot meshes.
- Local Biomes-style avatar module for skeleton joint ordering, wearable slot names, 44 Biomes source animation clips, source animation GLTF path, and reserved skin/eye/hair palette ranges, backed by checked-in Biomes `base_model.vox`.
- HUD character menu controls for third-person mode, appearance presets, preview mode, and the 44 Biomes source animation clips.
- Local MagicaVoxel parser/mesh builder coverage plus focused Rust unit tests and a gate that proves no packet, storage, world generation, or Godot scene/resource dependency is introduced.

Out of scope:

- No packet, storage, world generation, chunk serialization, server gameplay, GPU terrain renderer, draw-distance, lighting, shadow, texture-atlas, or texture-quality changes.
- No multiplayer avatar replication.
- No camera collision solver or over-shoulder aim offset beyond the guarded reach adjustment.

## Runtime Contract

- `V` toggles first-person and third-person camera mode.
- `B` cycles the local Biomes appearance preset and rebuilds the character visual.
- `C` opens the HUD character creator menu, enables third-person preview, and exposes appearance buttons plus the Biomes animation clip list.
- First-person mode uses the player eye height (`1.80m`) and hides the character visual.
- Third-person mode moves the camera behind the player and shows `PlayerVoxelCharacter`.
- The block raycast target is extended by the third-person camera offset and a small reach padding so current targeting still reaches the same gameplay envelope.
- `Player.is_third_person_camera_enabled()` exposes the current camera mode to Godot/tests.
- `Player.character_appearance_label()` exposes the current local appearance preset label to Godot/tests.
- `Player.character_animation_clip_count()`, `Player.character_animation_clip_name(index)`, `Player.select_character_animation_clip(index)`, and `Player.set_character_animation_preview_enabled(enabled)` expose the Biomes source animation preview catalog to Godot/tests.
- The character visual is built in Rust from named `Node3D` pivots and vertex-colored composed voxel mesh children.
- `client/rust_ext/src/biomes_avatar.rs` owns the local Biomes avatar path, including `Armature` skeleton metadata, Biomes joint ordering, wearable slots, the full source animation-name catalog, source `character-animations.gltf` path, `base_model.vox` model-index mapping, and palette transforms for `skin_color_*`, `eye_color_*`, and `hair_color_*`.
- If the Biomes `.vox` asset cannot be read or parsed, that part falls back to a local `BoxMesh` shape without disabling the third-person character.
- Idle, run, and jump movement poses are applied procedurally to the same body pivots.
- The character creator animation dropdown exposes all 44 Biomes source animation clips and maps each clip into a guarded preview pose group until a full GLTF sampler runtime is added.
- Animation time wraps at a bounded interval so long sessions do not grow the pose timer without bound.

## Visual Contract

- The visual root name is `PlayerVoxelCharacter`.
- The visual root is hidden in first-person mode and visible in third-person mode.
- The local player scale is guarded as roughly `1.90m` total height with eyes/camera around `1.80m`.
- The Rust player source owns all visual dimensions, colors, animation rates, and motion-state thresholds.
- Character assets are limited to guarded Biomes-derived MagicaVoxel `.vox` and source animation `.gltf` files under `client/assets/biomes/`.
- `client/assets/biomes/ATTRIBUTION.md` records the source commit, copied files, MIT license, and local integration notes.
- No FBX, tracked PNG, Godot scene, Godot script, `.import`, `.uid`, or runtime Godot resource loader path is required for the character visual; Godot-extracted `character-animations_*.png` files are ignored generated artifacts.
- The HUD character creator is UI only; it uses exported `Player` methods and does not own gameplay state.
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
- `character_visual=biomes_avatar_guarded`
- `character_creator=godot_hud_guarded`
- `character_assets=biomes_vox_guarded`
- `character_asset_license=mit_attributed`
- `character_animation=biomes_44_clip_preview_guarded`
- `biomes_avatar=palette_wearable_guarded`
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
