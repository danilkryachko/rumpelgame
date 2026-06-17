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
  'Biomes character skeleton, wearable slots, reserved palette ranges, MagicaVoxel `.vox` base model, and source character animation GLTF' \
  'Drive procedural idle/run/jump poses' \
  'Expose a HUD character creator menu for local appearance and all Biomes source animation clips' \
  '44 Biomes source animation clips' \
  '1.90m' \
  '1.80m' \
  'PlayerVoxelCharacter' \
  'MIT'; do
  require_token "$DESIGN_DOC" "$token"
done

for token in \
  'use crate::biomes_avatar::{BiomesAnimationCatalog, BiomesAvatarAppearance, BiomesAvatarJoint}' \
  'const PLAYER_CHARACTER_VISUAL_NAME: &str = "PlayerVoxelCharacter"' \
  'const PLAYER_HEIGHT_METERS: f32 = 1.90' \
  'const PLAYER_EYE_HEIGHT_METERS: f32 = 1.80' \
  'const CHARACTER_ROOT_YAW_DEGREES: f32 = 0.0' \
  'const CHARACTER_HEAD_VOXEL_HEIGHT: f32 = 18.0' \
  'struct VoxelCharacterVisual' \
  'character_visual: Option<VoxelCharacterVisual>' \
  'character_appearance: BiomesAvatarAppearance' \
  'character_animation_catalog: Option<BiomesAnimationCatalog>' \
  'character_preview_animation_enabled: bool' \
  'fn create_voxel_character_visual' \
  'fn create_biomes_avatar_character_part' \
  'crate::biomes_avatar::load_avatar_joint_mesh' \
  'BiomesAvatarJoint::Head' \
  'BiomesAvatarJoint::Chest' \
  'BiomesAvatarJoint::LForearm' \
  'BiomesAvatarJoint::RFoot' \
  'fn cycle_character_appearance' \
  'Key::B' \
  'BoxMesh::new_gd()' \
  'ALBEDO_FROM_VERTEX_COLOR' \
  'fn update_character_visual' \
  'fn next_character_animation_time' \
  'fn apply_voxel_character_pose' \
  'fn apply_voxel_character_clip_pose' \
  'fn character_clip_preview_kind' \
  'fn set_character_preview_animation_index' \
  'fn character_animation_clip_count' \
  'fn select_character_animation_clip' \
  'fn set_character_animation_preview_enabled' \
  'biomes_clip_preview_kind_covers_all_source_animation_names' \
  'CharacterMotionState::Idle' \
  'CharacterMotionState::Run' \
  'CharacterMotionState::Jump' \
  'Key::V' \
  'fn is_third_person_camera_enabled' \
  'fn character_appearance_label' \
  'third_person_camera_position()' \
  'block_raycast_target(self.third_person_camera)' \
  'voxel_character_animation_time_wraps_and_ignores_invalid_delta' \
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
  'character_appearance_preset_count' \
  'character_animation_clip_count' \
  'select_character_appearance_preset' \
  'select_character_animation_clip' \
  'set_character_animation_preview_enabled' \
  'set_third_person_camera_enabled'; do
  require_token "$HUD_SOURCE" "$token"
done

require_token "$LIB_SOURCE" 'mod biomes_avatar;'
require_token "$LIB_SOURCE" 'mod vox;'

for token in \
  'pub(crate) fn load_vox_model_from_res' \
  'fn parse_vox_model_index' \
  'fn parse_vox_models' \
  'pub(crate) fn build_colored_voxels_mesh' \
  'pub(crate) fn model_palette_color' \
  'b"SIZE"' \
  'b"XYZI"' \
  'b"RGBA"' \
  'PackedColorArray' \
  'parse_vox_models_reads_size_voxels_and_palette' \
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
  'pub(crate) const BIOMES_CHARACTER_JOINT_ORDERING' \
  'pub(crate) const BIOMES_CHARACTER_WEARABLE_SLOTS' \
  'pub(crate) const BIOMES_CHARACTER_ANIMATION_CLIP_NAMES' \
  'pub(crate) struct BiomesAnimationClip' \
  'pub(crate) struct BiomesAnimationCatalog' \
  'fn base_model_index' \
  'fn file_animation_name' \
  'pub(crate) fn load_biomes_animation_catalog_from_res' \
  'fn parse_biomes_animation_catalog' \
  'pub(crate) fn load_avatar_joint_mesh' \
  'fn colored_voxels_from_biomes_model' \
  'fn biomes_palette_color' \
  'const SKIN_PALETTE_START: u8 = 241' \
  'const HAIR_PALETTE_START: u8 = 233' \
  'const EYE_PALETTE_START: u8 = 249' \
  'build_colored_voxels_mesh' \
  'biomes_skeleton_contract_matches_player_wearable_pipeline' \
  'biomes_wearable_slots_include_base_and_character_slots' \
  'base_model_indices_match_biomes_vox_layers' \
  'reserved_palette_ranges_follow_biomes_character_appearance' \
  'biomes_animation_catalog_reads_all_source_clips' \
  'biomes_player_animation_names_cover_source_clip_catalog'; do
  require_token "$AVATAR_SOURCE" "$token"
done

if grep -Fq 'veloren_composer' "$LIB_SOURCE" || grep -Fq 'VelorenHumanoidPart' "$PLAYER_SOURCE"; then
  fail "third-person character visual must not use the old Veloren composer"
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
  'src/galois/data/animations/character-animations.gltf' \
  'client/rust_ext/src/biomes_avatar.rs'; do
  require_token "$ATTRIBUTION_PATH" "$token"
done

for asset in \
  "$ASSET_ROOT/wearables/base_model.vox" \
  "$ASSET_ROOT/animations/character-animations.gltf" \
  "$ASSET_ROOT/licenses/BIOMES-MIT-LICENSE.txt"; do
  test -s "$asset" || fail "missing Biomes character asset $asset"
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

	var appearance_before = player.character_appearance_label()
	var skin_event = InputEventKey.new()
	skin_event.physical_keycode = KEY_B
	skin_event.keycode = KEY_B
	skin_event.pressed = true
	root.get_viewport().push_input(skin_event)
	await process_frame

	var appearance_after = player.character_appearance_label()
	if appearance_before == appearance_after:
		push_error("B did not cycle character appearance")
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

	print("player voxel smoke ok")
	quit(0)
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

    printf("third_person_character_visual status=%s reason=%s third_person_visual=guarded camera_toggle=rust_guarded character_visual=biomes_avatar_guarded character_creator=godot_hud_guarded character_assets=biomes_vox_guarded character_asset_license=mit_attributed character_animation=biomes_44_clip_preview_guarded biomes_avatar=palette_wearable_guarded vox_loader=magica_vox_guarded rust_tests=%s godot_smoke=%s active_protocol_change=%d active_storage_change=%d active_worldgen_change=%d design_doc=%s player_source=%s\n", status, reason, rust_tests, godot_smoke, protocol_diff_count, storage_diff_count, worldgen_diff_count, design_doc, player_source)
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
