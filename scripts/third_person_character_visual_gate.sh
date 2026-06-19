#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/third_person_character_visual"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

SUMMARY_PATH="$OUT_DIR/third-person-character-visual-summary.txt"
DESIGN_DOC="${RUMPELMC_THIRD_PERSON_VISUAL_DOC:-${RUMPELMC_THIRD_PERSON_CHARACTER_VISUAL_DOC:-"$ROOT_DIR/docs/THIRD_PERSON_CHARACTER_VISUAL.md"}}"
PLAYER_SOURCE="${RUMPELMC_THIRD_PERSON_VISUAL_PLAYER_SOURCE:-${RUMPELMC_THIRD_PERSON_PLAYER_SOURCE:-"$ROOT_DIR/client/rust_ext/src/player.rs"}}"
HUD_SOURCE="${RUMPELMC_THIRD_PERSON_VISUAL_HUD_SOURCE:-"$ROOT_DIR/client/hud.gd"}"
LIB_SOURCE="${RUMPELMC_THIRD_PERSON_VISUAL_LIB_SOURCE:-"$ROOT_DIR/client/rust_ext/src/lib.rs"}"
VOX_SOURCE="${RUMPELMC_THIRD_PERSON_VISUAL_VOX_SOURCE:-"$ROOT_DIR/client/rust_ext/src/vox.rs"}"
AVATAR_SOURCE="${RUMPELMC_THIRD_PERSON_VISUAL_AVATAR_SOURCE:-"$ROOT_DIR/client/rust_ext/src/biomes_avatar.rs"}"
CARGO_MANIFEST="${RUMPELMC_THIRD_PERSON_VISUAL_CARGO_MANIFEST:-"$ROOT_DIR/client/rust_ext/Cargo.toml"}"
ASSET_ROOT="${RUMPELMC_THIRD_PERSON_VISUAL_ASSET_ROOT:-"$ROOT_DIR/client/assets/biomes"}"
ATTRIBUTION_PATH="$ASSET_ROOT/ATTRIBUTION.md"
LICENSE_PATH="$ASSET_ROOT/licenses/BIOMES-MIT-LICENSE.txt"
GODOT_BIN="${GODOT_BIN:-godot}"
RUN_RUST_TESTS="${RUMPELMC_THIRD_PERSON_VISUAL_RUN_RUST_TESTS:-${RUMPELMC_THIRD_PERSON_RUN_RUST_TESTS:-1}}"
RUN_GODOT_SMOKE="${RUMPELMC_THIRD_PERSON_VISUAL_RUN_GODOT_SMOKE:-${RUMPELMC_THIRD_PERSON_RUN_GODOT_CHECKS:-1}}"

mkdir -p "$OUT_DIR"

fail() {
  echo "third_person_character_visual_gate: $*" >&2
  exit 1
}

require_token() {
  path="$1"
  token="$2"
  test -s "$path" || fail "missing file $path"
  grep -Fq "$token" "$path" || fail "missing token '$token' in $path"
}

for path in "$DESIGN_DOC" "$PLAYER_SOURCE" "$HUD_SOURCE" "$LIB_SOURCE" "$VOX_SOURCE" "$AVATAR_SOURCE" "$CARGO_MANIFEST" "$ATTRIBUTION_PATH" "$LICENSE_PATH"; do
  test -s "$path" || fail "missing required input $path"
done

for token in \
  'Attach a visible modular voxel character only in third-person mode' \
  'Biomes character skeleton, wearable slots, reserved palette ranges, MagicaVoxel `.vox` base model, source wearable `.vox` slots, and source character animation GLTF' \
  'Drive directional movement, airborne/fall, fly, and block-action poses from the Biomes source animation clips' \
  'Expose a fullscreen HUD character creator page for local appearance categories, thumbnail-based wearable selection, a live draggable 3D character preview, and all Biomes source animation clips' \
  '44 Biomes source animation clips' \
  'embedded GLTF animation accessor/bufferView sampling' \
  'source GLTF translation, rotation, and scale keyframes through the source skeleton hierarchy' \
  'Biomes-style `Armature` `Node3D` hierarchy' \
  'source pose `+X` maps to authored/game `-Z` front' \
  'scene voxel `+X` maps to authored/game `-Z`' \
  'applies sampled GLTF local translation/rotation/scale transforms to the Biomes `Armature -> Chest/Waist -> limb` hierarchy' \
  'small axis-specific joint-local rigid limb overlap' \
  'side-specific parent-space thigh root weld offsets' \
  'side-specific upper-limb stitch offsets' \
  'item-only wearable voxels' \
  '1.90m' \
  '1.80m' \
  'PlayerVoxelCharacter' \
  'MIT'; do
  require_token "$DESIGN_DOC" "$token"
done

for token in \
  'BiomesSampledPose' \
  'const PLAYER_CHARACTER_VISUAL_NAME: &str = "PlayerVoxelCharacter"' \
  'const PLAYER_HEIGHT_METERS: f32 = 1.90' \
  'const PLAYER_EYE_HEIGHT_METERS: f32 = 1.80' \
  'const CHARACTER_ROOT_YAW_DEGREES: f32 = 0.0' \
  'const CHARACTER_LEFT_ARM_REST_Z_DEGREES: f32 = -86.0' \
  'const CHARACTER_ARM_MESH_OVERLAP_SCALE: f32 = 1.35' \
  'const CHARACTER_LEG_MESH_OVERLAP_SCALE: f32 = 1.18' \
  'const CHARACTER_ARM_ROOT_WELD_INSET_METERS: f32 = 0.08' \
  'const CHARACTER_LEFT_LEG_ROOT_WELD_INSET_METERS: f32 = 0.020' \
  'const CHARACTER_RIGHT_LEG_ROOT_WELD_INSET_METERS: f32 = 0.012' \
  'const CHARACTER_ARM_MESH_STITCH_INSET_METERS: f32 = 0.09' \
  'const CHARACTER_HEAD_VOXEL_HEIGHT: f32 = 18.0' \
  'struct VoxelCharacterVisual' \
  'character_visual: Option<VoxelCharacterVisual>' \
  'character_appearance: BiomesAvatarAppearance' \
  'character_animation_catalog: Option<BiomesAnimationCatalog>' \
  'character_preview_animation_enabled: bool' \
  'character_action_animation: Option<BiomesPlayerAnimation>' \
  'character_action_animation_remaining_sec: f32' \
  'uses_biomes_skeleton_hierarchy: bool' \
  'fn create_voxel_character_visual' \
  'fn create_biomes_skeleton_character_visual' \
  'fn create_biomes_skeleton_character_part' \
  'fn set_biomes_joint_node_transform' \
  'fn biomes_skeleton_joint_for_visual_joint' \
  'fn biomes_visual_joint_for_skeleton_joint' \
  'fn create_biomes_avatar_character_part' \
  'fn biomes_joint_mesh_inverse_bind_transform' \
  'fn biomes_joint_mesh_overlap_scale' \
  'fn biomes_joint_root_weld_offset' \
  'fn biomes_joint_mesh_stitch_offset' \
  '"HandL"' \
  '"HandR"' \
  'crate::biomes_avatar::load_avatar_joint_mesh' \
  'BiomesAvatarJoint::Head' \
  'BiomesAvatarJoint::Chest' \
  'BiomesAvatarJoint::LForearm' \
  'BiomesAvatarJoint::RFoot' \
  'BoxMesh::new_gd()' \
  'ALBEDO_FROM_VERTEX_COLOR' \
  'fn update_character_visual' \
  'fn next_character_animation_time' \
  'fn character_motion_biomes_animation' \
  'fn trigger_character_action_animation' \
  'fn character_action_animation_duration' \
  'fn apply_voxel_character_pose' \
  'fn apply_biomes_sampled_pose' \
  'fn apply_biomes_sampled_joint_pose' \
  'fn should_apply_raw_biomes_sampled_pose_to_flat_avatar' \
  'fn biomes_sampled_joint_position' \
  'fn biomes_pose_translation_to_godot' \
  'fn biomes_pose_translation_delta_to_godot' \
  'fn biomes_pose_rotation_to_godot' \
  'fn rotate_vector3_by_quaternion4' \
  'fn apply_voxel_character_clip_pose' \
  'fn character_clip_preview_kind' \
  'fn set_character_preview_animation_index' \
  'fn character_animation_clip_count' \
  'fn select_character_animation_clip' \
  'fn set_character_animation_preview_enabled' \
  'fn selected_character_animation_sample_track_count' \
  'fn character_creator_category_count' \
  'fn character_creator_option_count' \
  'fn character_creator_option_color' \
  'fn character_creator_option_thumbnail_path' \
  'fn select_character_creator_option' \
  'biomes_clip_preview_kind_covers_all_source_animation_names' \
  'CharacterMotionState::Idle' \
  'CharacterMotionState::WalkForward' \
  'CharacterMotionState::RunForward' \
  'CharacterMotionState::RunBackward' \
  'CharacterMotionState::StrafeLeftSlow' \
  'CharacterMotionState::StrafeLeftFast' \
  'CharacterMotionState::StrafeRightSlow' \
  'CharacterMotionState::StrafeRightFast' \
  'CharacterMotionState::Jump' \
  'CharacterMotionState::Fall' \
  'CharacterMotionState::FlyIdle' \
  'CharacterMotionState::FlyForwards' \
  'CharacterMotionState::FlyBackwards' \
  'Key::V' \
  'fn is_third_person_camera_enabled' \
  'fn set_gameplay_input_blocked' \
  'fn character_appearance_label' \
  'third_person_camera_position()' \
  'block_raycast_target(self.third_person_camera)' \
  'voxel_character_animation_time_wraps_and_ignores_invalid_delta' \
  'character_motion_states_select_biomes_source_animation_clips' \
  'character_action_animation_duration_uses_bounded_fallback_without_catalog' \
  'biomes_pose_retarget_converts_animation_axes_to_godot_axes' \
  'biomes_joint_mesh_overlap_scales_cover_rigid_limb_gaps' \
  'biomes_joint_mesh_stitch_offsets_keep_leg_chain_aligned' \
  'biomes_leg_visual_joints_keep_source_skeleton_sides' \
  'biomes_leg_visual_rest_poses_match_vox_bind_sides' \
  'biomes_joint_root_weld_offsets_pull_root_limb_chains_toward_torso' \
  'biomes_sampled_joint_positions_stay_bound_for_modular_skin' \
  'raw_biomes_sampled_pose_is_disabled_for_flat_modular_avatar' \
  'character_visual_scale_tracks_player_height_and_eye_height' \
  'voxel_character_visual_name_is_stable_for_godot_smoke'; do
  require_token "$PLAYER_SOURCE" "$token"
done

for token in \
  'const CHARACTER_MENU_UPDATE_INTERVAL = 0.2' \
  'func create_character_menu' \
  'CharacterCreator' \
  'KEY_C' \
  'OptionButton.new()' \
  'SubViewportContainer.new()' \
  'handle_character_preview_input' \
  'character_preview_yaw_degrees' \
  'own_world_3d' \
  'character_preview_model' \
  'character_creator_category_count' \
  'character_creator_option_count' \
  'character_creator_option_color' \
  'character_creator_option_thumbnail_path' \
  'load_character_thumbnail' \
  'character_animation_clip_count' \
  'selected_character_animation_sample_track_count' \
  'select_character_creator_option' \
  'select_character_animation_clip' \
  'set_character_animation_preview_enabled' \
  'set_third_person_camera_enabled' \
  'set_gameplay_input_blocked'; do
  require_token "$HUD_SOURCE" "$token"
done

require_token "$LIB_SOURCE" 'mod biomes_avatar;'
require_token "$LIB_SOURCE" 'mod vox;'

for token in \
  'pub(crate) fn load_vox_model_from_res' \
  'fn parse_vox_model_index' \
  'fn parse_vox_models' \
  'pub(crate) fn build_colored_voxels_mesh' \
  'fn scene_voxel_corner_to_godot' \
  'pub(crate) fn model_palette_color' \
  'b"SIZE"' \
  'b"XYZI"' \
  'b"RGBA"' \
  'PackedColorArray' \
  'parse_vox_models_reads_size_voxels_and_palette' \
  'scene_voxel_axes_match_biomes_pose_to_game_transform' \
  'parse_vox_models_rejects_truncated_input'; do
  require_token "$VOX_SOURCE" "$token"
done

for token in \
  'pub(crate) enum BiomesAvatarJoint' \
  'pub(crate) enum BiomesWearableSlot' \
  'pub(crate) enum BiomesPlayerAnimation' \
  'pub(crate) struct BiomesAvatarAppearance' \
  'pub(crate) const BIOMES_CHARACTER_SKELETON_ROOT: &str = "Armature"' \
  'pub(crate) const BIOMES_CHARACTER_ANIMATIONS_PATH' \
  'pub(crate) const BIOMES_ANIMATION_VOX_TO_POSE_SCALE' \
  'pub(crate) const BIOMES_CHARACTER_JOINT_ORDERING' \
  'pub(crate) const BIOMES_CHARACTER_WEARABLE_SLOTS' \
  'pub(crate) const BIOMES_CHARACTER_ANIMATION_CLIP_NAMES' \
  'pub(crate) struct BiomesAnimationClip' \
  'pub(crate) enum BiomesAnimationTransformPath' \
  'pub(crate) struct BiomesAnimationTrack' \
  'pub(crate) struct BiomesSampledJointPose' \
  'pub(crate) struct BiomesSampledPose' \
  'pub(crate) struct BiomesTransform' \
  'pub(crate) struct BiomesJointRestPose' \
  'pub(crate) struct BiomesAnimationCatalog' \
  'pub(crate) fn skeleton_parent' \
  'pub(crate) fn armature_rest_pose' \
  'pub(crate) fn joint_rest_poses' \
  'pub(crate) local_translation: [f32; 3]' \
  'pub(crate) enum BiomesAvatarOptionCategory' \
  'pub(crate) fn avatar_creator_category_count' \
  'pub(crate) fn avatar_creator_option_count' \
  'pub(crate) fn avatar_creator_option_thumbnail_path' \
  'pub(crate) fn avatar_creator_select_option' \
  'fn available_wearable_ids' \
  'fn wearable_joint_voxels' \
  'WEARABLE_BASE_OCCLUSION_RADIUS' \
  'fn compose_avatar_joint_voxels' \
  'fn wearable_slot_masks_lower_layers' \
  'wearable_body_mask_removes_base_voxels_under_clothing_shells' \
  'hair_and_hat_layers_mask_lower_head_layers' \
  'fn base_model_index' \
  'fn file_animation_name' \
  'pub(crate) fn load_biomes_animation_catalog_from_res' \
  'fn parse_biomes_animation_catalog' \
  'fn parse_gltf_nodes' \
  'fn parse_gltf_animation_track' \
  'struct GltfNodeTransform' \
  'fn compute_gltf_global_transforms' \
  'fn parse_json_optional_f32_array_field' \
  'fn read_gltf_accessor_f32_components' \
  'fn decode_base64' \
  'fn sample_pose' \
  'pub(crate) fn load_avatar_joint_mesh' \
  'fn scene_colored_voxels_from_biomes_model_transform' \
  'fn scene_model_is_visible_joint_layer' \
  'fn wearable_asset_has_visible_joint_layer' \
  'fn is_biomes_joint_layer_name' \
  'fn biomes_palette_color' \
  'const SKIN_PALETTE_START: u8 = 241' \
  'const HAIR_PALETTE_START: u8 = 233' \
  'const EYE_PALETTE_START: u8 = 249' \
  'build_scene_colored_voxels_mesh' \
  'biomes_skeleton_contract_matches_player_wearable_pipeline' \
  'biomes_wearable_slots_include_base_and_character_slots' \
  'base_model_indices_match_biomes_vox_layers' \
  'base_hand_scene_models_keep_source_mirrored_rotations' \
  'base_joint_scene_voxels_are_local_to_their_joint' \
  'reserved_palette_ranges_follow_biomes_character_appearance' \
  'wearable_scene_model_filter_uses_visible_joint_layers' \
  'available_wearables_exclude_reference_only_assets' \
  'creator_visual_options_expose_thumbnail_paths' \
  'biomes_animation_catalog_reads_all_source_clips' \
  'biomes_animation_catalog_preserves_source_skeleton_for_retargeting' \
  'biomes_animation_samples_all_source_clips_into_bounded_joint_poses' \
  'biomes_player_animation_names_cover_source_clip_catalog'; do
  require_token "$AVATAR_SOURCE" "$token"
done

require_token "$VOX_SOURCE" 'parse_vox_scene_models_reads_layers_and_hidden_flags'

if grep -Fq 'veloren_composer' "$LIB_SOURCE" || grep -Fq 'VelorenHumanoidPart' "$PLAYER_SOURCE"; then
  fail "third-person character visual must not use the old Veloren composer"
fi

if grep -Fq 'character_appearance_preset' "$PLAYER_SOURCE" || grep -Fq 'select_character_appearance_preset' "$HUD_SOURCE"; then
  fail "third-person character creator must use Biomes categories, not local appearance presets"
fi

if grep -Fq 'CHARACTER_HAND_MESH_YAW_DEGREES' "$PLAYER_SOURCE"; then
  fail "Biomes hand meshes must keep source mirrored orientation without an extra shared yaw flip"
fi

if grep -Eq '^[[:space:]]*(ron|serde|three|gltf)[[:space:]]*=' "$CARGO_MANIFEST"; then
  fail "third-person Biomes avatar must not add ron/serde/three/gltf Cargo dependencies"
fi

for token in \
  'Project: Biomes' \
  'ill-inc/biomes-game' \
  '669da235acbc5ec19720b047889c4aaa1c013ce2' \
  'License: MIT' \
  'src/galois/data/wearables/base_model.vox' \
  'src/galois/data/wearables/{head,hair,hair_with_hat,face,ears,hat,neck,top,bottoms,outerwear,hands,feet,robot}/*.vox' \
  'src/galois/data/animations/character-animations.gltf' \
  'thumbnails/.../*.png' \
  'reference mannequin layers' \
  'client/rust_ext/src/biomes_avatar.rs'; do
  require_token "$ATTRIBUTION_PATH" "$token"
done

for asset in \
  "$ASSET_ROOT/wearables/base_model.vox" \
  "$ASSET_ROOT/animations/character-animations.gltf" \
  "$ASSET_ROOT/licenses/BIOMES-MIT-LICENSE.txt"; do
  test -s "$asset" || fail "missing Biomes character asset $asset"
done

for slot in head hair hair_with_hat face ears hat neck top bottoms outerwear hands feet robot; do
  if [ -d "$ASSET_ROOT/wearables/$slot" ]; then
    find "$ASSET_ROOT/wearables/$slot" -type f -name '*.vox' | grep -q . || fail "missing Biomes wearable vox assets for $slot"
  fi
done

if git -C "$ROOT_DIR" status --short -- client/assets/biomes/animations/character-animations_*.png | grep -q .; then
  fail "Godot-generated Biomes animation PNGs must stay ignored and uncommitted"
fi

if grep -Fq 'ResourceLoader' "$PLAYER_SOURCE" || grep -Fq 'PackedScene' "$PLAYER_SOURCE"; then
  fail "player visual must not depend on Godot resource loading"
fi

if [ -e "$ROOT_DIR/client/kenney_character_preview.gd" ] || \
  [ -e "$ROOT_DIR/client/kenney_character_preview.tscn" ] || \
  [ -e "$ROOT_DIR/client/assets/characters/kenney_animated_characters_3" ]; then
  fail "Kenney character scene/assets are still present"
fi

rust_tests="skipped"
if [ "$RUN_RUST_TESTS" = "1" ]; then
  if (
    cd "$ROOT_DIR" &&
      cargo test --manifest-path client/rust_ext/Cargo.toml --lib third_person > "$OUT_DIR/cargo-test-third-person.txt" 2>&1 &&
      cargo test --manifest-path client/rust_ext/Cargo.toml --lib camera_positions >> "$OUT_DIR/cargo-test-third-person.txt" 2>&1 &&
      cargo test --manifest-path client/rust_ext/Cargo.toml --lib character_motion_state >> "$OUT_DIR/cargo-test-third-person.txt" 2>&1 &&
      cargo test --manifest-path client/rust_ext/Cargo.toml --lib voxel_character >> "$OUT_DIR/cargo-test-third-person.txt" 2>&1 &&
      cargo test --manifest-path client/rust_ext/Cargo.toml --lib vox >> "$OUT_DIR/cargo-test-third-person.txt" 2>&1 &&
      cargo test --manifest-path client/rust_ext/Cargo.toml --lib biomes_avatar >> "$OUT_DIR/cargo-test-third-person.txt" 2>&1 &&
      cargo test --manifest-path client/rust_ext/Cargo.toml --lib biomes_clip_preview_kind >> "$OUT_DIR/cargo-test-third-person.txt" 2>&1
  ); then
    rust_tests="pass"
  else
    cat "$OUT_DIR/cargo-test-third-person.txt" >&2 || true
    rust_tests="fail"
  fi
fi

godot_smoke="skipped"
if [ "$RUN_GODOT_SMOKE" = "1" ]; then
  if ! command -v "$GODOT_BIN" >/dev/null 2>&1; then
    godot_smoke="missing_godot"
  else
    SMOKE_SCRIPT="$OUT_DIR/player-voxel-smoke.gd"
    cat > "$SMOKE_SCRIPT" <<'GDSCRIPT'
extends SceneTree

func _init():
	call_deferred("_run")

func _run():
	var player = ClassDB.instantiate("Player")
	if player == null:
		push_error("Player class is not available")
		quit(1)
		return

	player.name = "Player"
	root.add_child(player)
	await process_frame

	var visual = player.get_node_or_null("PlayerVoxelCharacter")
	if visual == null:
		push_error("PlayerVoxelCharacter node is missing")
		quit(1)
		return
	if visual.visible:
		push_error("PlayerVoxelCharacter must start hidden in first person")
		quit(1)
		return

	var event = InputEventKey.new()
	event.physical_keycode = KEY_V
	event.keycode = KEY_V
	event.pressed = true
	root.get_viewport().push_input(event)
	await process_frame

	if not player.is_third_person_camera_enabled():
		push_error("V did not enable third-person camera")
		quit(1)
		return
	if not visual.visible:
		push_error("PlayerVoxelCharacter did not become visible in third person")
		quit(1)
		return
if absf(visual.rotation_degrees.y) > 0.01:
		push_error("PlayerVoxelCharacter must face away from the third-person camera")
		quit(1)
		return

	if player.has_method("character_appearance_preset_count") or player.has_method("select_character_appearance_preset"):
		push_error("Character creator still exposes local appearance presets")
		quit(1)
		return

	if player.character_creator_category_count() < 15:
		push_error("Biomes creator did not expose all appearance categories")
		quit(1)
		return
	var skin_category = -1
	var eye_category = -1
	var hair_category = -1
	var hair_color_category = -1
	var face_category = -1
	var hat_category = -1
	for index in range(player.character_creator_category_count()):
		match player.character_creator_category_key(index):
			"skin_color":
				skin_category = index
			"eye_color":
				eye_category = index
			"hair_style":
				hair_category = index
			"hair_color":
				hair_color_category = index
			"face":
				face_category = index
			"hat":
				hat_category = index
	if skin_category < 0 or eye_category < 0 or hair_category < 0 or hair_color_category < 0 or face_category < 0 or hat_category < 0:
		push_error("Biomes creator is missing a required category")
		quit(1)
		return
	if player.character_creator_option_count(skin_category) != 18 or player.character_creator_option_count(eye_category) != 18 or player.character_creator_option_count(hair_color_category) != 18:
		push_error("Biomes creator must expose 18 skin, eye, and hair color options")
		quit(1)
		return
	if player.character_creator_option_count(hair_category) < 20 or player.character_creator_option_count(face_category) < 19 or player.character_creator_option_count(hat_category) < 32:
		push_error("Biomes creator must expose source hair, face, and hat wearable options")
		quit(1)
		return
	var skin_swatch = player.character_creator_option_color(skin_category, 17)
	if typeof(skin_swatch) != TYPE_COLOR or skin_swatch.a <= 0.0:
		push_error("Biomes creator skin swatch is missing")
		quit(1)
		return
	if not player.has_method("character_creator_option_thumbnail_path"):
		push_error("Biomes creator thumbnail path API is missing")
		quit(1)
		return
	var skin_thumbnail = str(player.character_creator_option_thumbnail_path(skin_category, 0))
	if not skin_thumbnail.is_empty():
		push_error("Biomes creator color swatches must not use wearable thumbnails")
		quit(1)
		return
	var hair_thumbnail = str(player.character_creator_option_thumbnail_path(hair_category, 1))
	if not hair_thumbnail.begins_with("res://assets/biomes/thumbnails/hair/") or not hair_thumbnail.ends_with(".png"):
		push_error("Biomes creator hair thumbnail path is missing")
		quit(1)
		return

	var hud_script = load("res://hud.gd")
	var hud = hud_script.new()
	root.add_child(hud)
	await process_frame
	hud.toggle_character_menu()
	await process_frame
	if not player.has_method("is_gameplay_input_blocked") or not player.is_gameplay_input_blocked():
		push_error("HUD character creator did not block gameplay input")
		quit(1)
		return
	var menu_click = InputEventMouseButton.new()
	menu_click.button_index = MOUSE_BUTTON_LEFT
	menu_click.pressed = true
	root.get_viewport().push_input(menu_click)
	await process_frame
	if Input.get_mouse_mode() != Input.MOUSE_MODE_VISIBLE:
		push_error("HUD character creator click captured the mouse")
		quit(1)
		return
	menu_click.pressed = false
	root.get_viewport().push_input(menu_click)
	await process_frame
	hud.select_character_creator_category(hair_category)
	await process_frame
	if not hud.character_panel.visible:
		push_error("HUD character creator page did not open")
		quit(1)
		return
	if hud.character_preview_viewport == null or hud.character_preview_model == null:
		push_error("HUD character creator preview is missing")
		quit(1)
		return
	if not hud.character_preview_viewport.own_world_3d:
		push_error("HUD character creator preview must use an isolated 3D world")
		quit(1)
		return
if absf(hud.character_preview_model.rotation_degrees.y - 180.0) > 0.01:
		push_error("HUD character creator preview must open facing the viewer")
		quit(1)
		return
	var preview_press = InputEventMouseButton.new()
	preview_press.button_index = MOUSE_BUTTON_LEFT
	preview_press.pressed = true
	hud.handle_character_preview_input(preview_press)
	var preview_drag = InputEventMouseMotion.new()
	preview_drag.relative = Vector2(120.0, 0.0)
	hud.handle_character_preview_input(preview_drag)
	var preview_release = InputEventMouseButton.new()
	preview_release.button_index = MOUSE_BUTTON_LEFT
	preview_release.pressed = false
	hud.handle_character_preview_input(preview_release)
	await process_frame
	if absf(hud.character_preview_model.rotation_degrees.y - 180.0) < 1.0:
		push_error("HUD character creator preview drag did not rotate the model")
		quit(1)
		return
	if hud.character_option_buttons.size() < 20:
		push_error("HUD character creator hair option tiles were not built")
		quit(1)
		return
	if not _has_thumbnail_texture(hud.character_option_grid):
		push_error("HUD character creator hair thumbnails were not loaded")
		quit(1)
		return

	player.select_character_creator_option(skin_category, 17)
	player.select_character_creator_option(hair_category, 0)
	await process_frame
	if player.character_creator_selected_option_index(skin_category) != 17:
		push_error("Biomes creator skin selection did not update")
		quit(1)
		return
	if player.character_creator_selected_option_index(hair_category) != 0:
		push_error("Biomes creator hair None selection did not update")
		quit(1)
		return

	if player.character_animation_clip_count() != 44:
		push_error("Biomes animation clip catalog must expose 44 source clips")
		quit(1)
		return

	var wave_index = -1
	for index in range(player.character_animation_clip_count()):
		if player.character_animation_clip_name(index) == "Waving":
			wave_index = index
			break
	if wave_index < 0:
		push_error("Waving clip is missing from Biomes animation catalog")
		quit(1)
		return

	player.select_character_animation_clip(wave_index)
	await process_frame
	if player.selected_character_animation_clip_name() != "Waving":
		push_error("Biomes animation preview did not select Waving")
		quit(1)
		return
	if not player.is_character_animation_preview_enabled():
		push_error("Biomes animation preview did not enable preview mode")
		quit(1)
		return
	if player.selected_character_animation_sample_track_count() <= 0:
		push_error("Biomes animation preview did not expose sampled GLTF tracks")
		quit(1)
		return

	print("player voxel smoke ok")
	quit(0)

func _has_thumbnail_texture(node: Node) -> bool:
	if node is TextureRect and node.texture != null:
		return true
	for child in node.get_children():
		if _has_thumbnail_texture(child):
			return true
	return false
GDSCRIPT

    if (
      cd "$ROOT_DIR" &&
        cargo build --manifest-path client/rust_ext/Cargo.toml > "$OUT_DIR/cargo-build-gdextension.txt" 2>&1 &&
        "$GODOT_BIN" --headless --path client --script "$SMOKE_SCRIPT" > "$OUT_DIR/godot-player-voxel-smoke.txt" 2>&1
    ); then
      if grep -Eq 'fallback|failed to read|not a MagicaVoxel' "$OUT_DIR/godot-player-voxel-smoke.txt"; then
        cat "$OUT_DIR/godot-player-voxel-smoke.txt" >&2 || true
        godot_smoke="fallback"
      else
        godot_smoke="pass"
      fi
    else
      cat "$OUT_DIR/cargo-build-gdextension.txt" >&2 || true
      cat "$OUT_DIR/godot-player-voxel-smoke.txt" >&2 || true
      godot_smoke="fail"
    fi
  fi
fi

protocol_diff_count="$(git -C "$ROOT_DIR" diff --name-only -- api/schema server/pkg/api client/proto | awk 'END { print NR + 0 }')"
storage_diff_count="$(git -C "$ROOT_DIR" diff --name-only -- server/pkg/storage docs/STORAGE.md | awk 'END { print NR + 0 }')"
worldgen_diff_count="$(git -C "$ROOT_DIR" diff --name-only -- server/pkg/world docs/WORLDGEN_DETERMINISM.md | awk 'END { print NR + 0 }')"

awk \
  -v rust_tests="$rust_tests" \
  -v godot_smoke="$godot_smoke" \
  -v protocol_diff_count="$protocol_diff_count" \
  -v storage_diff_count="$storage_diff_count" \
  -v worldgen_diff_count="$worldgen_diff_count" \
  -v design_doc="$DESIGN_DOC" \
  -v player_source="$PLAYER_SOURCE" '
  BEGIN {
    status = "pass"
    reason = "ok"
    if (rust_tests != "pass") {
      status = "fail"
      reason = "rust_tests_not_pass"
    } else if (godot_smoke != "pass") {
      status = "fail"
      reason = "godot_smoke_not_pass"
    } else if (protocol_diff_count != 0) {
      status = "fail"
      reason = "protocol_diff"
    } else if (storage_diff_count != 0) {
      status = "fail"
      reason = "storage_diff"
    } else if (worldgen_diff_count != 0) {
      status = "fail"
      reason = "worldgen_diff"
    }

    printf("third_person_character_visual status=%s reason=%s third_person_visual=guarded camera_toggle=rust_guarded character_visual=biomes_avatar_guarded character_creator=godot_hud_guarded character_assets=biomes_vox_guarded character_asset_license=mit_attributed character_animation=biomes_44_clip_keyframes_guarded biomes_avatar=palette_wearable_guarded vox_loader=magica_vox_guarded rust_tests=%s godot_smoke=%s active_protocol_change=%d active_storage_change=%d active_worldgen_change=%d design_doc=%s player_source=%s\n", status, reason, rust_tests, godot_smoke, protocol_diff_count, storage_diff_count, worldgen_diff_count, design_doc, player_source)
    if (status != "pass") {
      exit 1
    }
  }
' > "$SUMMARY_PATH" || {
  cat "$SUMMARY_PATH" >&2 || true
  fail "third-person character visual gate failed"
}

cat "$SUMMARY_PATH"
echo "Third-person character visual artifacts: $OUT_DIR"
