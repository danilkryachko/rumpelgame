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
LIB_SOURCE="${RUMPELMC_THIRD_PERSON_VISUAL_LIB_SOURCE:-"$ROOT_DIR/client/rust_ext/src/lib.rs"}"
VOX_SOURCE="${RUMPELMC_THIRD_PERSON_VISUAL_VOX_SOURCE:-"$ROOT_DIR/client/rust_ext/src/vox.rs"}"
COMPOSER_SOURCE="${RUMPELMC_THIRD_PERSON_VISUAL_COMPOSER_SOURCE:-"$ROOT_DIR/client/rust_ext/src/veloren_composer.rs"}"
CARGO_MANIFEST="${RUMPELMC_THIRD_PERSON_VISUAL_CARGO_MANIFEST:-"$ROOT_DIR/client/rust_ext/Cargo.toml"}"
ASSET_ROOT="${RUMPELMC_THIRD_PERSON_VISUAL_ASSET_ROOT:-"$ROOT_DIR/client/assets/veloren"}"
ATTRIBUTION_PATH="$ASSET_ROOT/ATTRIBUTION.md"
LICENSE_PATH="$ASSET_ROOT/licenses/VELoren-GPL-3.0-or-later-LICENSE.txt"
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

for path in "$DESIGN_DOC" "$PLAYER_SOURCE" "$LIB_SOURCE" "$VOX_SOURCE" "$COMPOSER_SOURCE" "$CARGO_MANIFEST" "$ATTRIBUTION_PATH" "$LICENSE_PATH"; do
  test -s "$path" || fail "missing required input $path"
done

for token in \
  'Attach a visible modular voxel character only in third-person mode' \
  'Veloren voxygen RON manifests and MagicaVoxel `.vox` body parts' \
  'Drive procedural idle/run/jump poses' \
  '1.90m' \
  '1.80m' \
  'PlayerVoxelCharacter' \
  'GPL-3.0-or-later'; do
  require_token "$DESIGN_DOC" "$token"
done

for token in \
  'use crate::veloren_composer::VelorenHumanoidPart' \
  'const PLAYER_CHARACTER_VISUAL_NAME: &str = "PlayerVoxelCharacter"' \
  'const PLAYER_HEIGHT_METERS: f32 = 1.90' \
  'const PLAYER_EYE_HEIGHT_METERS: f32 = 1.80' \
  'const CHARACTER_ROOT_YAW_DEGREES: f32 = 0.0' \
  'const CHARACTER_HEAD_VOXEL_HEIGHT: f32 = 11.0' \
  'struct VoxelCharacterVisual' \
  'character_visual: Option<VoxelCharacterVisual>' \
  'fn create_voxel_character_visual' \
  'fn create_veloren_composed_character_part' \
  'crate::veloren_composer::load_default_humanoid_part_mesh' \
  'VelorenHumanoidPart::Head' \
  'VelorenHumanoidPart::Chest' \
  'VelorenHumanoidPart::LeftHand' \
  'VelorenHumanoidPart::RightFoot' \
  'BoxMesh::new_gd()' \
  'ALBEDO_FROM_VERTEX_COLOR' \
  'fn update_character_visual' \
  'fn next_character_animation_time' \
  'fn apply_voxel_character_pose' \
  'CharacterMotionState::Idle' \
  'CharacterMotionState::Run' \
  'CharacterMotionState::Jump' \
  'Key::V' \
  'fn is_third_person_camera_enabled' \
  'third_person_camera_position()' \
  'block_raycast_target(self.third_person_camera)' \
  'voxel_character_animation_time_wraps_and_ignores_invalid_delta' \
  'character_visual_scale_tracks_player_height_and_eye_height' \
  'voxel_character_visual_name_is_stable_for_godot_smoke'; do
  require_token "$PLAYER_SOURCE" "$token"
done

require_token "$LIB_SOURCE" 'mod veloren_composer;'
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
  'pub(crate) enum VelorenHumanoidPart' \
  'pub(crate) fn load_default_humanoid_part_mesh' \
  'MaterialPalette::for_body' \
  'fn compose_head' \
  'fn compose_center_armor_part' \
  'fn compose_sided_armor_part' \
  'fn compose_flipped_armor_part' \
  'fn load_manifest_source' \
  'fn load_hum_color_manifest' \
  'fn parse_hum_color_manifest' \
  'fn parse_head_manifest' \
  'fn parse_armor_manifest' \
  'fn parse_sided_armor_manifest' \
  'fn strip_ron_line_comments' \
  'fn parse_named_color_tuple' \
  'build_colored_voxels_mesh' \
  'default_human_male_composer_assets_are_local' \
  'material_palette_uses_official_color_manifest' \
  'armor_manifest_named_lookup_reads_map_entries' \
  'veloren_spec_paths_match_github_layout' \
  'union_segments_matches_veloren_head_overlay_rules'; do
  require_token "$COMPOSER_SOURCE" "$token"
done

if grep -Fq 'serde::Deserialize' "$COMPOSER_SOURCE" || grep -Fq 'ron::from_str' "$COMPOSER_SOURCE"; then
  fail "Veloren composer must use the local checked parser, not serde/ron runtime dependencies"
fi

if grep -Eq '^[[:space:]]*(ron|serde)[[:space:]]*=' "$CARGO_MANIFEST"; then
  fail "third-person Veloren composer must not add ron/serde Cargo dependencies"
fi

for token in \
  'Project: Veloren' \
  'bd7d694ec1353b8b5be5be389f0c3f08b1bae28a' \
  'GNU General Public License v3.0 or later' \
  'voxygen/voxel/humanoid_head_manifest.ron' \
  'voxygen/voxel/humanoid_color_manifest.ron' \
  'voxygen/voxel/figure/head/human/male.vox' \
  'voxygen/voxel/figure/eyes/general/male_default-0.vox' \
  'voxygen/voxel/figure/hair/human/male-16.vox' \
  'voxygen/voxel/figure/beard/human/human-4.vox' \
  'voxygen/voxel/armor/misc/chest/none.vox'; do
  require_token "$ATTRIBUTION_PATH" "$token"
done

for asset in \
  "$ASSET_ROOT/voxygen/voxel/humanoid_head_manifest.ron" \
  "$ASSET_ROOT/voxygen/voxel/humanoid_color_manifest.ron" \
  "$ASSET_ROOT/voxygen/voxel/humanoid_armor_chest_manifest.ron" \
  "$ASSET_ROOT/voxygen/voxel/humanoid_armor_belt_manifest.ron" \
  "$ASSET_ROOT/voxygen/voxel/humanoid_armor_pants_manifest.ron" \
  "$ASSET_ROOT/voxygen/voxel/humanoid_armor_hand_manifest.ron" \
  "$ASSET_ROOT/voxygen/voxel/humanoid_armor_foot_manifest.ron" \
  "$ASSET_ROOT/voxygen/voxel/figure/head/human/male.vox" \
  "$ASSET_ROOT/voxygen/voxel/figure/eyes/general/male_default-0.vox" \
  "$ASSET_ROOT/voxygen/voxel/figure/hair/human/male-16.vox" \
  "$ASSET_ROOT/voxygen/voxel/figure/beard/human/human-4.vox" \
  "$ASSET_ROOT/voxygen/voxel/armor/empty.vox" \
  "$ASSET_ROOT/voxygen/voxel/armor/misc/chest/none.vox" \
  "$ASSET_ROOT/voxygen/voxel/armor/misc/belt/none.vox" \
  "$ASSET_ROOT/voxygen/voxel/armor/misc/pants/none.vox" \
  "$ASSET_ROOT/voxygen/voxel/armor/misc/hand/none.vox" \
  "$ASSET_ROOT/voxygen/voxel/armor/misc/foot/none.vox"; do
  test -s "$asset" || fail "missing Veloren character asset $asset"
done

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
      cargo test --manifest-path client/rust_ext/Cargo.toml --lib veloren >> "$OUT_DIR/cargo-test-third-person.txt" 2>&1
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

    printf("third_person_character_visual status=%s reason=%s third_person_visual=guarded camera_toggle=rust_guarded character_visual=veloren_composer_guarded character_assets=veloren_voxygen_guarded character_asset_license=gpl3_attributed character_animation=procedural_idle_run_jump_guarded veloren_composer=ron_manifest_guarded vox_loader=magica_vox_guarded rust_tests=%s godot_smoke=%s active_protocol_change=%d active_storage_change=%d active_worldgen_change=%d design_doc=%s player_source=%s\n", status, reason, rust_tests, godot_smoke, protocol_diff_count, storage_diff_count, worldgen_diff_count, design_doc, player_source)
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
