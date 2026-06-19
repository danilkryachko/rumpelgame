# Third Person Character Visual

This checkpoint owns the first finished third-person player visual slice.

## Technical Brief

Goal:

- Add a player-controlled first-person/third-person camera toggle.
- Attach a visible modular voxel character only in third-person mode.
- Load guarded Biomes character skeleton, wearable slots, reserved palette ranges, MagicaVoxel `.vox` base model, source wearable `.vox` slots, and source character animation GLTF with local attribution and license evidence.
- Drive directional movement, airborne/fall, fly, and block-action poses from the Biomes source animation clips.
- Allow local Biomes appearance editing by category: skin color, eye color, hair style, hair color, head style, face, ears, hat, neck, top, bottoms, outerwear, hands, feet, and robot accessories.
- Expose a fullscreen HUD character creator page for local appearance categories, thumbnail-based wearable selection, a live draggable 3D character preview, and all Biomes source animation clips.
- Keep block targeting functional in both camera modes.

Scope:

- Client Rust `Player` camera toggle, character visual construction, raycast reach adjustment, and Biomes motion-state animation pose application.
- Rust-built `Node3D` pivots using Biomes-derived head, chest, waist, arm, forearm, hand, thigh, leg, and foot meshes.
- Local Biomes-style avatar module for skeleton joint ordering, wearable slot names, 44 Biomes source animation clips, source animation GLTF path, full 18-option skin/eye/hair palettes, dynamic wearable slot catalogs, and checked-in Biomes `base_model.vox` plus slot `.vox` assets.
- HUD character creator page controls for third-person mode, category tabs, color swatches, thumbnail wearable/accessory option grids, an isolated draggable `SubViewport` preview cloned from `PlayerVoxelCharacter`, preview animation mode, and the 44 Biomes source animation clips.
- Local MagicaVoxel parser/mesh builder coverage plus focused Rust unit tests and a gate that proves no packet, storage, world generation, or Godot scene/resource dependency is introduced.

Out of scope:

- No packet, storage, world generation, chunk serialization, server gameplay, GPU terrain renderer, draw-distance, lighting, shadow, texture-atlas, or texture-quality changes.
- No multiplayer avatar replication.
- No camera collision solver or over-shoulder aim offset beyond the guarded reach adjustment.

## Runtime Contract

- `V` toggles first-person and third-person camera mode.
- `C` opens the fullscreen HUD character creator page, enables third-person preview, and exposes Biomes-style category tabs, color swatches, source wearable/accessory thumbnail options, a live character preview window, and the Biomes animation clip list.
- The creator preview opens with the avatar facing the viewer, and left-drag inside the preview rotates only the preview avatar for front/side/back inspection.
- The creator page blocks gameplay input while open, so ordinary menu clicks keep the cursor visible instead of recapturing the mouse.
- First-person mode uses the player eye height (`1.80m`) and hides the character visual.
- Third-person mode moves the camera behind the player and shows the back of `PlayerVoxelCharacter`.
- The block raycast target is extended by the third-person camera offset and a small reach padding so current targeting still reaches the same gameplay envelope.
- `Player.is_third_person_camera_enabled()` exposes the current camera mode to Godot/tests.
- `Player.character_appearance_label()` exposes the current local category-composed appearance label to Godot/tests.
- `Player.character_creator_category_count()`, `Player.character_creator_category_key(index)`, `Player.character_creator_category_label(index)`, `Player.character_creator_option_count(category)`, `Player.character_creator_option_label(category, option)`, `Player.character_creator_option_color(category, option)`, `Player.character_creator_option_thumbnail_path(category, option)`, `Player.character_creator_selected_option_index(category)`, and `Player.select_character_creator_option(category, option)` expose the Biomes-style creator catalog to Godot/tests.
- `Player.character_animation_clip_count()`, `Player.character_animation_clip_name(index)`, `Player.select_character_animation_clip(index)`, `Player.selected_character_animation_sample_track_count()`, and `Player.set_character_animation_preview_enabled(enabled)` expose the Biomes source animation catalog and sampled track count to Godot/tests.
- The character visual is built in Rust from a Biomes-style `Armature` `Node3D` hierarchy, named joint pivots, inverse-bound vertex-colored composed voxel mesh children, and a flat fallback only when source animation metadata is unavailable.
- `client/rust_ext/src/biomes_avatar.rs` owns the local Biomes avatar path, including `Armature` skeleton metadata, source GLTF node hierarchy/rest transforms, Biomes joint ordering, wearable slots, the full source animation-name catalog, source `character-animations.gltf` path, embedded GLTF animation accessor/bufferView sampling, rest-relative joint retargeting, `base_model.vox` model-index mapping, source wearable `.vox` scene-model composition, and palette transforms for all Biomes `skin_color_*`, `eye_color_*`, and `hair_color_*` options.
- If the Biomes `.vox` asset cannot be read or parsed, that part falls back to a local `BoxMesh` shape without disabling the third-person character.
- Normal gameplay movement samples Biomes directional clips: `Idle`, `Walking`, `Running`, `RunningBackward`, `StrafeLeftWalking`, `StrafeLeftRunning`, `StrafeRightWalking`, `StrafeRightRunning`, `Jump`, `Fall`, `SwimmingIdle`, `SwimmingForward`, and `SwimmingBackward`. Short block break/place actions use Biomes `DiggingHand`, `DiggingTool`, and `Place` animation mappings above locomotion, then return to the current movement clip.
- Sampled Biomes animation retargeting follows the source `transformFromPoseToGame` axis contract: source pose `+X` maps to authored/game `-Z` front, source `+Z` maps to `+X`, and source `+Y` remains up.
- Biomes scene-VOX local depth uses the same authored front contract as the skeleton: scene voxel `+X` maps to authored/game `-Z`, so wearable/body meshes do not face the opposite way from the sampled animation pose.
- Biomes joint voxels are composed in joint-local space before being attached to their runtime `Node3D` pivots. The visible avatar applies sampled GLTF local translation/rotation/scale transforms to the Biomes `Armature -> Chest/Waist -> limb` hierarchy, with inverse-bind mesh children, small axis-specific joint-local rigid limb overlap, side-specific parent-space thigh root weld offsets, side-specific upper-limb stitch offsets, and a left-leg-only mesh stitch that pulls the visible left thigh/lower-leg/foot back toward the torso while leaving the already-aligned right leg unchanged.
- The character creator animation dropdown exposes all 44 Biomes source animation clips and samples each selected clip from its source GLTF translation, rotation, and scale keyframes through the source skeleton hierarchy; procedural grouped poses remain only as a fallback if source sampling or source skeleton metadata is unavailable.
- Animation time wraps at a bounded interval so long sessions do not grow the pose timer without bound.

## Visual Contract

- The visual follows `docs/COORDINATE_SYSTEM.md`: authored avatar front is `-Z`, authored avatar back is `+Z`, left is `-X`, right is `+X`, and vertical up is `+Y`.
- The visual root name is `PlayerVoxelCharacter`.
- The visual root is hidden in first-person mode and visible in third-person mode.
- The gameplay visual root uses no presentation yaw, so the local `+Z` behind-player third-person camera sees the avatar's back while authored avatar front remains `-Z`. The HUD preview clone applies its own 180 degree editor yaw so the character creator opens facing the viewer.
- The local player collision height remains guarded as roughly `1.90m` with eyes/camera around `1.80m`; the rendered Biomes avatar uses a `2.10m` visual height so it reads correctly against one-meter blocks.
- The Rust player source owns all visual dimensions, colors, animation rates, and motion-state thresholds.
- Hand mesh geometry keeps the source mirrored Biomes orientation inside the hand pivots so palm details are not flipped outward by an extra shared yaw in rest, run, jump, or sampled animation poses.
- Character assets are limited to guarded Biomes-derived MagicaVoxel `.vox` base/wearable files and source animation `.gltf` files under `client/assets/biomes/`.
- Clothing, hair, and hat wearable shells mask lower avatar layers while composing each joint, so thin walls do not show body, scalp, or lower hair layers through the selected wearable.
- `client/assets/biomes/ATTRIBUTION.md` records the source commit, copied files, MIT license, and local integration notes.
- No FBX, Godot scene, `.import`, `.uid`, or runtime Godot resource loader path is required for the character visual mesh; Godot-extracted `character-animations_*.png` files are ignored generated artifacts.
- The tracked PNG files under `client/assets/biomes/thumbnails/` are UI-only creator thumbnails generated from the checked-in Biomes `.vox` wearable assets; they render item-only wearable voxels and exclude reference mannequin layers.
- The HUD character creator page is UI only; it uses exported `Player` methods and does not own gameplay state.
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
- `character_animation=biomes_44_clip_keyframes_guarded`
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
