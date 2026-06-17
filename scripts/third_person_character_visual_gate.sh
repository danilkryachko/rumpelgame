#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/third_person_character_visual"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

SUMMARY_PATH="$OUT_DIR/third-person-character-visual-summary.txt"
DESIGN_DOC="${RUMPELMC_THIRD_PERSON_CHARACTER_VISUAL_DOC:-"$ROOT_DIR/docs/THIRD_PERSON_CHARACTER_VISUAL.md"}"
PLAYER_SOURCE="${RUMPELMC_THIRD_PERSON_PLAYER_SOURCE:-"$ROOT_DIR/client/rust_ext/src/player.rs"}"
SCENE_PATH="${RUMPELMC_THIRD_PERSON_SCENE_PATH:-"$ROOT_DIR/client/kenney_character_preview.tscn"}"
SCRIPT_PATH="${RUMPELMC_THIRD_PERSON_SCRIPT_PATH:-"$ROOT_DIR/client/kenney_character_preview.gd"}"
ASSET_ROOT="${RUMPELMC_THIRD_PERSON_ASSET_ROOT:-"$ROOT_DIR/client/assets/characters/kenney_animated_characters_3"}"
GODOT_BIN="${GODOT_BIN:-/opt/homebrew/bin/godot}"
RUN_RUST_TESTS="${RUMPELMC_THIRD_PERSON_RUN_RUST_TESTS:-1}"
RUN_GODOT_CHECKS="${RUMPELMC_THIRD_PERSON_RUN_GODOT_CHECKS:-1}"

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

require_file() {
  path="$1"
  test -s "$path" || fail "missing required asset $path"
}

for path in "$DESIGN_DOC" "$PLAYER_SOURCE" "$SCENE_PATH" "$SCRIPT_PATH"; do
  test -s "$path" || fail "missing required input $path"
done

for token in \
  'Technical Brief' \
  'Runtime Contract' \
  'Asset Contract' \
  'Compatibility Rules' \
  'No packet, storage, world generation, chunk serialization, server gameplay, GPU terrain renderer' \
  'Do not make third-person mode affect server reach validation'; do
  require_token "$DESIGN_DOC" "$token"
done

for token in \
  'PLAYER_CHARACTER_SCENE_PATH' \
  'PlayerCharacterVisual' \
  'THIRD_PERSON_CAMERA_DISTANCE' \
  'THIRD_PERSON_BLOCK_REACH_PADDING' \
  'third_person_camera: bool' \
  'character_visual: Option<Gd<Node3D>>' \
  'CharacterMotionState' \
  'fn attach_character_visual' \
  'fn set_third_person_camera' \
  'fn apply_camera_mode' \
  'fn update_character_motion_state' \
  'fn is_third_person_camera_enabled' \
  'fn third_person_camera_position' \
  'fn block_raycast_target' \
  'third_person_raycast_extends_reach_by_camera_offset' \
  'camera_positions_are_mode_specific' \
  'character_motion_state_follows_velocity' \
  'character_motion_state_labels_are_stable_for_godot_script'; do
  require_token "$PLAYER_SOURCE" "$token"
done

for token in \
  'res://assets/characters/kenney_animated_characters_3/Model/characterMedium.fbx' \
  'res://assets/characters/kenney_animated_characters_3/Skins/humanMaleA.png' \
  'ANIMATION_SCENES' \
  '"idle"' \
  '"run"' \
  '"jump"' \
  'func set_motion_state' \
  'func apply_skin' \
  'func find_animation_player'; do
  require_token "$SCRIPT_PATH" "$token"
done

require_token "$SCENE_PATH" 'KenneyCharacterPreview'
require_token "$SCENE_PATH" 'res://kenney_character_preview.gd'

for asset in \
  "$ASSET_ROOT/License.txt" \
  "$ASSET_ROOT/Model/characterMedium.fbx" \
  "$ASSET_ROOT/Animations/idle.fbx" \
  "$ASSET_ROOT/Animations/run.fbx" \
  "$ASSET_ROOT/Animations/jump.fbx" \
  "$ASSET_ROOT/Skins/humanMaleA.png" \
  "$ASSET_ROOT/Preview.png"; do
  require_file "$asset"
done

active_protocol_change="$(git -C "$ROOT_DIR" diff --name-only -- api/schema/packets.proto server/pkg/api/packets.pb.go | awk 'END { print NR + 0 }')"
active_storage_change="$(git -C "$ROOT_DIR" diff --name-only -- server/pkg/storage | awk 'END { print NR + 0 }')"
active_worldgen_change="$(git -C "$ROOT_DIR" diff --name-only -- server/pkg/world/chunk.go server/pkg/world/generator.go server/pkg/world/biome.go server/pkg/world/cave.go server/pkg/world/resource.go | awk 'END { print NR + 0 }')"

changed_client_paths="$(mktemp)"
trap 'rm -f "$changed_client_paths"' EXIT
{
  git -C "$ROOT_DIR" diff --name-only -- client
  git -C "$ROOT_DIR" diff --cached --name-only -- client
  git -C "$ROOT_DIR" ls-files --others --exclude-standard -- client
} | sed '/^$/d' | sort -u > "$changed_client_paths"

unexpected_client_paths="$(awk '
  $0 == "client/rust_ext/src/player.rs" { next }
  $0 == "client/kenney_character_preview.gd" { next }
  $0 == "client/kenney_character_preview.tscn" { next }
  index($0, "client/assets/characters/kenney_animated_characters_3/") == 1 { next }
  { print }
' "$changed_client_paths" | tr '\n' ' ')"

rust_tests="skipped"
if [ "$RUN_RUST_TESTS" = "1" ]; then
  if (
    cd "$ROOT_DIR/client/rust_ext"
    cargo test --lib third_person > "$OUT_DIR/cargo-test-third-person.txt" 2>&1
    cargo test --lib camera_positions >> "$OUT_DIR/cargo-test-third-person.txt" 2>&1
    cargo test --lib character_motion_state >> "$OUT_DIR/cargo-test-third-person.txt" 2>&1
  ); then
    rust_tests="pass"
  else
    cat "$OUT_DIR/cargo-test-third-person.txt" >&2 || true
    rust_tests="fail"
  fi
fi

godot_parse="skipped"
godot_scene_load="skipped"
if [ "$RUN_GODOT_CHECKS" = "1" ]; then
  if ! command -v "$GODOT_BIN" >/dev/null 2>&1; then
    fail "missing Godot binary $GODOT_BIN"
  fi
  if "$GODOT_BIN" --headless --path "$ROOT_DIR/client" --check-only --script res://kenney_character_preview.gd > "$OUT_DIR/godot-gdscript-check.txt" 2>&1; then
    godot_parse="pass"
  else
    cat "$OUT_DIR/godot-gdscript-check.txt" >&2 || true
    godot_parse="fail"
  fi
  if "$GODOT_BIN" --headless --path "$ROOT_DIR/client" --scene res://kenney_character_preview.tscn --quit-after 2 > "$OUT_DIR/godot-scene-load.txt" 2>&1; then
    godot_scene_load="pass"
  else
    cat "$OUT_DIR/godot-scene-load.txt" >&2 || true
    godot_scene_load="fail"
  fi
fi

awk \
  -v active_protocol_change="$active_protocol_change" \
  -v active_storage_change="$active_storage_change" \
  -v active_worldgen_change="$active_worldgen_change" \
  -v unexpected_client_paths="$unexpected_client_paths" \
  -v rust_tests="$rust_tests" \
  -v godot_parse="$godot_parse" \
  -v godot_scene_load="$godot_scene_load" \
  -v design_doc="$DESIGN_DOC" \
  '
  BEGIN {
    status = "pass"
    reason = "ok"
    third_person_visual = "guarded"
    camera_toggle = "rust_guarded"
    character_assets = "kenney_guarded"
    character_animation = "idle_run_jump_guarded"

    if (active_protocol_change + 0 != 0) {
      status = "fail"
      reason = "protocol_diff_present"
    } else if (active_storage_change + 0 != 0) {
      status = "fail"
      reason = "storage_diff_present"
    } else if (active_worldgen_change + 0 != 0) {
      status = "fail"
      reason = "worldgen_diff_present"
    } else if (unexpected_client_paths != "") {
      status = "fail"
      reason = "unexpected_client_paths"
    } else if (!(rust_tests == "pass" || rust_tests == "skipped")) {
      status = "fail"
      reason = "rust_tests_failed"
    } else if (!(godot_parse == "pass" || godot_parse == "skipped")) {
      status = "fail"
      reason = "godot_parse_failed"
    } else if (!(godot_scene_load == "pass" || godot_scene_load == "skipped")) {
      status = "fail"
      reason = "godot_scene_load_failed"
    }

    printf("third_person_character_visual status=%s reason=%s third_person_visual=%s camera_toggle=%s character_assets=%s character_animation=%s godot_parse=%s godot_scene_load=%s rust_tests=%s active_protocol_change=%d active_storage_change=%d active_worldgen_change=%d unexpected_client_paths=\"%s\" design_doc=%s\n", status, reason, third_person_visual, camera_toggle, character_assets, character_animation, godot_parse, godot_scene_load, rust_tests, active_protocol_change, active_storage_change, active_worldgen_change, unexpected_client_paths, design_doc)
    if (status != "pass") {
      exit 1
    }
  }
' > "$SUMMARY_PATH" || {
  cat "$SUMMARY_PATH" >&2 || true
  fail "third person character visual gate failed"
}

cat "$SUMMARY_PATH"
echo "Third person character visual artifacts: $OUT_DIR"
