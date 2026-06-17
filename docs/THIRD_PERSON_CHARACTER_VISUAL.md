# Third Person Character Visual

This checkpoint owns the first finished third-person player visual slice.

## Technical Brief

Goal:

- Add a player-controlled first-person/third-person camera toggle.
- Attach a visible character model only in third-person mode.
- Drive idle/run/jump animation state from the player movement state.
- Keep block targeting functional in both camera modes.

Scope:

- Client Rust `Player` camera toggle, character visual attachment, raycast reach adjustment, and motion-state dispatch.
- Godot `kenney_character_preview.tscn` and `kenney_character_preview.gd` as the character visual scene.
- Kenney Animated Characters model, idle/run/jump clips, skins, preview image, and license under `client/assets/characters/kenney_animated_characters_3`.
- Focused Rust unit tests and headless Godot parse/scene-load checks.

Out of scope:

- No packet, storage, world generation, chunk serialization, server gameplay, GPU terrain renderer, draw-distance, lighting, shadow, texture-atlas, or texture-quality changes.
- No multiplayer avatar replication.
- No camera collision solver or over-shoulder aim offset beyond the guarded reach adjustment.

## Runtime Contract

- `V` toggles first-person and third-person camera mode.
- First-person mode keeps the existing camera height and hides the character visual.
- Third-person mode moves the camera behind the player and shows `PlayerCharacterVisual`.
- The block raycast target is extended by the third-person camera offset and a small reach padding so current targeting still reaches the same gameplay envelope.
- `Player.is_third_person_camera_enabled()` exposes the current camera mode to Godot/tests.
- The character scene accepts `set_motion_state("idle" | "run" | "jump")`.
- Idle, run, and jump labels stay stable because the Rust enum labels are unit-guarded and the Godot animation map uses the same names.

## Asset Contract

- The model scene path is `res://assets/characters/kenney_animated_characters_3/Model/characterMedium.fbx`.
- The default skin path is `res://assets/characters/kenney_animated_characters_3/Skins/humanMaleA.png`.
- Animation clips are loaded from `Animations/idle.fbx`, `Animations/run.fbx`, and `Animations/jump.fbx`.
- `client/assets/characters/kenney_animated_characters_3/License.txt` must stay with the imported asset pack.
- Godot `.import` files remain generated local artifacts under the existing project ignore policy.

## Checks

Use:

```sh
sh scripts/third_person_character_visual_gate.sh logs/third_person_character_visual_current
```

Expected current result:

- `status=pass`
- `third_person_visual=guarded`
- `camera_toggle=rust_guarded`
- `character_assets=kenney_guarded`
- `character_animation=idle_run_jump_guarded`
- `godot_scene_load=pass`
- `rust_tests=pass`
- `active_protocol_change=0`
- `active_storage_change=0`
- `active_worldgen_change=0`

## Compatibility Rules

- Do not change protocol or server authority for camera mode.
- Do not make third-person mode affect server reach validation.
- Do not remove first-person behavior.
- Do not hand-edit generated `.import` files.
- Do not reduce render quality, draw distance, lighting, shadows, or texture quality for this visual slice.
