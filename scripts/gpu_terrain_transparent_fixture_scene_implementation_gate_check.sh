#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
CHECKLIST_PATH="${1:-"$ROOT_DIR/logs/gpu_transparent_fixture_plan/transparent-fixture-scene-implementation-checklist.txt"}"
case "$CHECKLIST_PATH" in
  /*) ;;
  *) CHECKLIST_PATH="$ROOT_DIR/$CHECKLIST_PATH" ;;
esac
OUT_PATH="${2:-"$(dirname -- "$CHECKLIST_PATH")/transparent-fixture-scene-implementation-gate-check.txt"}"
case "$OUT_PATH" in
  /*) ;;
  *) OUT_PATH="$ROOT_DIR/$OUT_PATH" ;;
esac

fail() {
  echo "gpu_terrain_transparent_fixture_scene_implementation_gate_check: $*" >&2
  exit 1
}

relative_path() {
  path="$1"
  case "$path" in
    "$ROOT_DIR"/*) printf '%s\n' "${path#$ROOT_DIR/}" ;;
    *) printf '%s\n' "$path" ;;
  esac
}

resolve_pack_path() {
  path="$1"
  case "$path" in
    /*) printf '%s\n' "$path" ;;
    *) printf '%s\n' "$ROOT_DIR/$path" ;;
  esac
}

line_token() {
  key="$1"
  line="$2"
  printf '%s\n' "$line" | awk -v key="$key" '
    BEGIN { prefix = key "=" }
    {
      for (i = 1; i <= NF; i++) {
        if (index($i, prefix) == 1) {
          print substr($i, length(prefix) + 1)
          exit
        }
      }
    }
  '
}

required_line() {
  file_path="$1"
  pattern="$2"
  line="$(grep -F -- "$pattern" "$file_path" || true)"
  line="$(printf '%s\n' "$line" | sed -n '1p')"
  test -n "$line" || fail "missing line in $(relative_path "$file_path"): $pattern"
  printf '%s\n' "$line"
}

required_value() {
  file_path="$1"
  key="$2"
  line="$(required_line "$file_path" "$key=")"
  value="${line#"$key="}"
  test -n "$value" || fail "missing $key value in $(relative_path "$file_path")"
  printf '%s\n' "$value"
}

required_token() {
  key="$1"
  line="$2"
  row_label="$3"
  value="$(line_token "$key" "$line")"
  test -n "$value" || fail "missing $key in $row_label row: $line"
  printf '%s\n' "$value"
}

require_text() {
  line="$1"
  token="$2"
  row_label="$3"
  printf '%s\n' "$line" | grep -F -- "$token" >/dev/null || fail "$row_label missing $token"
}

test -s "$CHECKLIST_PATH" || fail "missing scene implementation checklist $CHECKLIST_PATH"
mkdir -p "$(dirname -- "$OUT_PATH")"

summary_line="$(required_line "$CHECKLIST_PATH" "summary transparent_fixture_scene_implementation_checklist_status=")"
status_line="$(required_line "$CHECKLIST_PATH" "scene_implementation_checklist_status=pending_scene_implementation")"
scope_line="$(required_line "$CHECKLIST_PATH" "implementation_scope=fixture_scene_only")"
gate_line="$(required_line "$CHECKLIST_PATH" "transparent_implementation_gate=false")"
runtime_line="$(required_line "$CHECKLIST_PATH" "runtime_behavior=unchanged")"
ordinary_line="$(required_line "$CHECKLIST_PATH" "ordinary_world_visibility=absent")"
env_line="$(required_line "$CHECKLIST_PATH" "env_on_expected=1/0/1")"
future_line="$(required_line "$CHECKLIST_PATH" "future_active_expected=1/0/0")"

checklist_status="$(required_token "transparent_fixture_scene_implementation_checklist_status" "$summary_line" "checklist summary")"
pack_status="$(required_token "transparent_fixture_pack_status" "$summary_line" "checklist summary")"
final_report_status="$(required_token "transparent_fixture_final_report_check_status" "$summary_line" "checklist summary")"
default_off_status="$(required_token "transparent_fixture_default_off_status" "$summary_line" "checklist summary")"
implementation_gate="$(required_token "transparent_implementation_gate" "$summary_line" "checklist summary")"
env_expected="$(required_token "env_on_expected" "$summary_line" "checklist summary")"
future_expected="$(required_token "future_active_expected" "$summary_line" "checklist summary")"

test "$checklist_status" = "pending_scene_implementation" || fail "unexpected checklist status=$checklist_status"
test "$pack_status" = "pass" || fail "unexpected pack status=$pack_status"
test "$final_report_status" = "pass" || fail "unexpected final-report status=$final_report_status"
test "$default_off_status" = "pass" || fail "unexpected default-off status=$default_off_status"
test "$implementation_gate" = "false" || fail "unexpected implementation gate=$implementation_gate"
test "$env_expected" = "1/0/1" || fail "unexpected env_on_expected=$env_expected"
test "$future_expected" = "1/0/0" || fail "unexpected future_active_expected=$future_expected"
test "${status_line#scene_implementation_checklist_status=}" = "pending_scene_implementation" || fail "unexpected status line"
test "${scope_line#implementation_scope=}" = "fixture_scene_only" || fail "unexpected implementation scope"
test "${gate_line#transparent_implementation_gate=}" = "false" || fail "unexpected gate line"
test "${runtime_line#runtime_behavior=}" = "unchanged" || fail "unexpected runtime behavior"
test "${ordinary_line#ordinary_world_visibility=}" = "absent" || fail "unexpected ordinary-world visibility"
test "${env_line#env_on_expected=}" = "$env_expected" || fail "env line does not match summary"
test "${future_line#future_active_expected=}" = "$future_expected" || fail "future line does not match summary"

required_line "$CHECKLIST_PATH" "required_scene camera=fixture_camera_static light=fixture_sun_static chunk=fixture_chunk_0_0_0" >/dev/null
required_line "$CHECKLIST_PATH" "required_role front_transparent material=transparent_test_glass visible=required collision=solid" >/dev/null
required_line "$CHECKLIST_PATH" "required_role behind_wall_transparent material=transparent_test_glass opaque_occlusion=required" >/dev/null
required_line "$CHECKLIST_PATH" "required_role opaque_depth_occluder material=current_opaque_block depth_write=required" >/dev/null
required_line "$CHECKLIST_PATH" "required_role adjacent_same_material_pair material=transparent_test_glass same_material_seam=hidden_or_explicit" >/dev/null
required_line "$CHECKLIST_PATH" "required_role collision_probe material=transparent_test_glass collision_solidity=explicit" >/dev/null

current_guard_line="$(required_line "$CHECKLIST_PATH" "required_current_guard env_on_fallback")"
future_gate_line="$(required_line "$CHECKLIST_PATH" "required_future_gate active_path")"
non_goals_line="$(required_line "$CHECKLIST_PATH" "non_goals shader_alpha=no transparent_pass=no sorting=no block_id=no asset=no protocol=no storage=no worldgen=no")"
for token in transparent_requested=1 transparent_active=0 transparent_fallback=1 gpu_upload_fail=0 smoke_err=0 terrain_samples=nonzero; do
  require_text "$current_guard_line" "$token" "current env-on fallback guard"
done
for token in transparent_active=1 transparent_fallback=0 gpu_upload_fail=0 opaque_depth_occlusion=required collision_solidity=required opaque_adjacent_faces_visible=required; do
  require_text "$future_gate_line" "$token" "future active gate"
done
for token in shader_alpha=no transparent_pass=no sorting=no block_id=no asset=no protocol=no storage=no worldgen=no; do
  require_text "$non_goals_line" "$token" "non-goals"
done

pack_path="$(resolve_pack_path "$(required_value "$CHECKLIST_PATH" "pack")")"
test -s "$pack_path" || fail "missing linked pack $(relative_path "$pack_path")"

pack_summary_line="$(required_line "$pack_path" "summary transparent_fixture_pack_status=pass")"
pack_scene_steps_line="$(required_line "$pack_path" "scene_implementation_steps=scene_implementation_checklist/report_refresh")"
pack_runtime_line="$(required_line "$pack_path" "runtime_behavior=unchanged")"
pack_ordinary_line="$(required_line "$pack_path" "ordinary_world_visibility=absent")"

pack_summary_status="$(required_token "transparent_fixture_pack_status" "$pack_summary_line" "pack summary")"
pack_scene_status="$(required_token "transparent_fixture_scene_implementation_checklist_status" "$pack_summary_line" "pack summary")"
pack_final_report_status="$(required_token "transparent_fixture_final_report_check_status" "$pack_summary_line" "pack summary")"
pack_default_off_status="$(required_token "transparent_fixture_default_off_status" "$pack_summary_line" "pack summary")"
pack_env_expected="$(required_token "env_on_expected" "$pack_summary_line" "pack summary")"

test "$pack_summary_status" = "$pack_status" || fail "pack status does not match checklist"
test "$pack_scene_status" = "$checklist_status" || fail "pack scene implementation status does not match checklist"
test "$pack_final_report_status" = "$final_report_status" || fail "pack final-report status does not match checklist"
test "$pack_default_off_status" = "$default_off_status" || fail "pack default-off status does not match checklist"
test "$pack_env_expected" = "$env_expected" || fail "pack env_on_expected does not match checklist"
test "${pack_scene_steps_line#scene_implementation_steps=}" = "scene_implementation_checklist/report_refresh" || fail "unexpected scene implementation steps"
test "${pack_runtime_line#runtime_behavior=}" = "unchanged" || fail "unexpected pack runtime behavior"
test "${pack_ordinary_line#ordinary_world_visibility=}" = "absent" || fail "unexpected pack ordinary-world visibility"

report_path="$(resolve_pack_path "$(required_value "$pack_path" "report")")"
linked_checklist_path="$(resolve_pack_path "$(required_value "$pack_path" "scene_implementation_checklist")")"
test -s "$report_path" || fail "missing linked report $(relative_path "$report_path")"
test -s "$linked_checklist_path" || fail "missing linked scene implementation checklist $(relative_path "$linked_checklist_path")"

required_line "$report_path" "## Selected Transparent Fixture Scene Implementation Checklist" >/dev/null
required_line "$report_path" "Source: \`$linked_checklist_path\`" >/dev/null
required_line "$report_path" "$summary_line" >/dev/null

tmp_check="$OUT_PATH.tmp"
trap 'rm -f "$tmp_check"' EXIT
{
  printf 'GPU terrain transparent fixture scene implementation gate check\n'
  printf 'checklist=%s\n' "$(relative_path "$CHECKLIST_PATH")"
  printf 'pack=%s\n' "$(relative_path "$pack_path")"
  printf 'report=%s\n' "$(relative_path "$report_path")"
  printf 'linked_scene_implementation_checklist=%s\n' "$(relative_path "$linked_checklist_path")"
  printf 'gate_check_scope=fixture_scene_implementation_gate\n'
  printf 'scene_implementation_steps=scene_implementation_checklist/report_refresh\n'
  printf 'transparent_fixture_scene_implementation_checklist_status=%s\n' "$checklist_status"
  printf 'transparent_implementation_gate=false\n'
  printf 'runtime_behavior=unchanged\n'
  printf 'ordinary_world_visibility=absent\n'
  printf 'env_on_expected=%s\n' "$env_expected"
  printf 'future_active_expected=%s\n' "$future_expected"
  printf 'current_guard=env_on_fallback\n'
  printf 'future_guard=active_path_blocked_until_implementation\n'
  printf 'non_goals shader_alpha=no transparent_pass=no sorting=no block_id=no asset=no protocol=no storage=no worldgen=no\n'
  printf 'summary transparent_fixture_scene_implementation_gate_check_status=pass transparent_fixture_scene_implementation_checklist_status=%s transparent_fixture_pack_status=%s transparent_implementation_gate=false env_on_expected=%s future_active_expected=%s\n' \
    "$checklist_status" \
    "$pack_status" \
    "$env_expected" \
    "$future_expected"
} > "$tmp_check"

mv "$tmp_check" "$OUT_PATH"
cat "$OUT_PATH"
