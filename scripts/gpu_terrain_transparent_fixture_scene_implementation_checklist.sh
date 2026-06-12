#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
PACK_PATH="${1:-"$ROOT_DIR/logs/gpu_transparent_fixture_plan/transparent-fixture-pack.txt"}"
case "$PACK_PATH" in
  /*) ;;
  *) PACK_PATH="$ROOT_DIR/$PACK_PATH" ;;
esac
OUT_PATH="${2:-"$(dirname -- "$PACK_PATH")/transparent-fixture-scene-implementation-checklist.txt"}"
case "$OUT_PATH" in
  /*) ;;
  *) OUT_PATH="$ROOT_DIR/$OUT_PATH" ;;
esac

fail() {
  echo "gpu_terrain_transparent_fixture_scene_implementation_checklist: $*" >&2
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

test -s "$PACK_PATH" || fail "missing transparent fixture pack $PACK_PATH"
mkdir -p "$(dirname -- "$OUT_PATH")"

summary_line="$(required_line "$PACK_PATH" "summary transparent_fixture_pack_status=")"
final_report_steps_line="$(required_line "$PACK_PATH" "final_report_steps=final_report_check/report_refresh")"
runtime_line="$(required_line "$PACK_PATH" "runtime_behavior=unchanged")"
ordinary_line="$(required_line "$PACK_PATH" "ordinary_world_visibility=absent")"

pack_status="$(required_token "transparent_fixture_pack_status" "$summary_line" "pack summary")"
acceptance_status="$(required_token "transparent_fixture_acceptance_status" "$summary_line" "pack summary")"
default_off_status="$(required_token "transparent_fixture_default_off_status" "$summary_line" "pack summary")"
final_report_status="$(required_token "transparent_fixture_final_report_check_status" "$summary_line" "pack summary")"
report_check_status="$(required_token "transparent_fixture_report_check_status" "$summary_line" "pack summary")"
scene_check_status="$(required_token "transparent_fixture_scene_harness_check_status" "$summary_line" "pack summary")"
plan_status="$(required_token "fixture_plan_status" "$summary_line" "pack summary")"
harness_status="$(required_token "transparent_fixture_harness_status" "$summary_line" "pack summary")"
env_expected="$(required_token "env_on_expected" "$summary_line" "pack summary")"

test "$pack_status" = "pass" || fail "unexpected transparent_fixture_pack_status=$pack_status"
test "$acceptance_status" = "pass" || fail "unexpected transparent_fixture_acceptance_status=$acceptance_status"
test "$default_off_status" = "pass" || fail "unexpected transparent_fixture_default_off_status=$default_off_status"
test "$final_report_status" = "pass" || fail "unexpected transparent_fixture_final_report_check_status=$final_report_status"
test "$report_check_status" = "pass" || fail "unexpected transparent_fixture_report_check_status=$report_check_status"
test "$scene_check_status" = "pass" || fail "unexpected transparent_fixture_scene_harness_check_status=$scene_check_status"
test "$plan_status" = "pending_fixture_harness" || fail "unexpected fixture_plan_status=$plan_status"
test "$harness_status" = "placeholder" || fail "unexpected transparent_fixture_harness_status=$harness_status"
test "$env_expected" = "1/0/1" || fail "unexpected env_on_expected=$env_expected"
test "${final_report_steps_line#final_report_steps=}" = "final_report_check/report_refresh" || fail "unexpected final-report steps"
test "${runtime_line#runtime_behavior=}" = "unchanged" || fail "unexpected runtime behavior"
test "${ordinary_line#ordinary_world_visibility=}" = "absent" || fail "unexpected ordinary-world visibility"

smoke_plan_path="$(resolve_pack_path "$(required_value "$PACK_PATH" "smoke_plan")")"
scene_checklist_path="$(resolve_pack_path "$(required_value "$PACK_PATH" "scene_checklist")")"
scene_harness_path="$(resolve_pack_path "$(required_value "$PACK_PATH" "scene_harness")")"
scene_harness_check_path="$(resolve_pack_path "$(required_value "$PACK_PATH" "scene_harness_check")")"
acceptance_check_path="$(resolve_pack_path "$(required_value "$PACK_PATH" "acceptance_check")")"
default_off_check_path="$(resolve_pack_path "$(required_value "$PACK_PATH" "default_off_check")")"
final_report_check_path="$(resolve_pack_path "$(required_value "$PACK_PATH" "final_report_check")")"

for artifact_path in \
  "$smoke_plan_path" \
  "$scene_checklist_path" \
  "$scene_harness_path" \
  "$scene_harness_check_path" \
  "$acceptance_check_path" \
  "$default_off_check_path" \
  "$final_report_check_path"; do
  test -s "$artifact_path" || fail "missing linked artifact $(relative_path "$artifact_path")"
done

scene_summary_line="$(required_line "$scene_harness_check_path" "summary transparent_fixture_scene_harness_check_status=pass")"
acceptance_summary_line="$(required_line "$acceptance_check_path" "summary transparent_fixture_acceptance_status=pass")"
default_off_summary_line="$(required_line "$default_off_check_path" "summary transparent_fixture_default_off_status=pass")"
final_report_summary_line="$(required_line "$final_report_check_path" "summary transparent_fixture_final_report_check_status=pass")"

scene_roles="$(required_token "roles" "$scene_summary_line" "scene harness-check summary")"
scene_env="$(required_token "env_on_expected" "$scene_summary_line" "scene harness-check summary")"
acceptance_env="$(required_token "env_on_expected" "$acceptance_summary_line" "acceptance summary")"
default_off_gate="$(required_token "transparent_implementation_gate" "$default_off_summary_line" "default-off summary")"
default_off_future_active="$(required_token "future_active_expected" "$default_off_summary_line" "default-off summary")"
final_report_env="$(required_token "env_on_expected" "$final_report_summary_line" "final-report summary")"

test "$scene_roles" = "5" || fail "unexpected scene role count=$scene_roles"
test "$scene_env" = "$env_expected" || fail "scene env_on_expected does not match pack"
test "$acceptance_env" = "$env_expected" || fail "acceptance env_on_expected does not match pack"
test "$default_off_gate" = "false" || fail "unexpected transparent implementation gate=$default_off_gate"
test "$default_off_future_active" = "1/0/0" || fail "unexpected future active triplet=$default_off_future_active"
test "$final_report_env" = "$env_expected" || fail "final-report env_on_expected does not match pack"

camera_line="$(required_line "$scene_checklist_path" "camera fixed=required")"
light_line="$(required_line "$scene_checklist_path" "light fixed=required")"
chunk_line="$(required_line "$scene_checklist_path" "chunk fixed=required")"
front_line="$(required_line "$scene_harness_path" "role_check=front_transparent")"
behind_line="$(required_line "$scene_harness_path" "role_check=behind_wall_transparent")"
occluder_line="$(required_line "$scene_harness_path" "role_check=opaque_depth_occluder")"
adjacent_line="$(required_line "$scene_harness_path" "role_check=adjacent_same_material_pair")"
collision_line="$(required_line "$scene_harness_path" "role_check=collision_probe")"
env_on_line="$(required_line "$smoke_plan_path" "step=env_on_fallback_current status=required")"
future_active_line="$(required_line "$smoke_plan_path" "step=future_active_gate status=blocked_until_implementation")"

for token in position=fixture_camera_static look_at=fixture_center; do
  require_text "$camera_line" "$token" "camera"
done
for token in source=fixture_sun_static shadows=unchanged; do
  require_text "$light_line" "$token" "light"
done
for token in origin=fixture_chunk_0_0_0 worldgen=absent protocol=absent storage=absent; do
  require_text "$chunk_line" "$token" "chunk"
done
for token in material=transparent_test_glass expected_visible=required expected_collision=solid; do
  require_text "$front_line" "$token" "front transparent role"
done
for token in material=transparent_test_glass expected_opaque_occlusion=required; do
  require_text "$behind_line" "$token" "behind wall transparent role"
done
for token in material=current_opaque_block expected_depth_write=required; do
  require_text "$occluder_line" "$token" "opaque depth occluder role"
done
for token in material=transparent_test_glass expected_same_material_seam=hidden_or_explicit; do
  require_text "$adjacent_line" "$token" "adjacent same-material role"
done
for token in material=transparent_test_glass expected_collision_solidity=explicit; do
  require_text "$collision_line" "$token" "collision probe role"
done
for token in transparent_requested=1 transparent_active=0 transparent_fallback=1 gpu_upload_fail=0 smoke_err=0 terrain_samples=nonzero; do
  require_text "$env_on_line" "$token" "current env-on fallback"
done
for token in transparent_active=1 transparent_fallback=0 gpu_upload_fail=0 opaque_depth_occlusion=required collision_solidity=required opaque_adjacent_faces_visible=required; do
  require_text "$future_active_line" "$token" "future active gate"
done

tmp_checklist="$OUT_PATH.tmp"
trap 'rm -f "$tmp_checklist"' EXIT
{
  printf 'GPU terrain transparent fixture scene implementation checklist\n'
  printf 'pack=%s\n' "$(relative_path "$PACK_PATH")"
  printf 'smoke_plan=%s\n' "$(relative_path "$smoke_plan_path")"
  printf 'scene_checklist=%s\n' "$(relative_path "$scene_checklist_path")"
  printf 'scene_harness=%s\n' "$(relative_path "$scene_harness_path")"
  printf 'scene_harness_check=%s\n' "$(relative_path "$scene_harness_check_path")"
  printf 'acceptance_check=%s\n' "$(relative_path "$acceptance_check_path")"
  printf 'default_off_check=%s\n' "$(relative_path "$default_off_check_path")"
  printf 'final_report_check=%s\n' "$(relative_path "$final_report_check_path")"
  printf 'fixture=gpu-transparent-depth-collision\n'
  printf 'material=transparent_test_glass\n'
  printf 'scene_implementation_checklist_status=pending_scene_implementation\n'
  printf 'implementation_scope=fixture_scene_only\n'
  printf 'transparent_implementation_gate=false\n'
  printf 'runtime_behavior=unchanged\n'
  printf 'ordinary_world_visibility=absent\n'
  printf 'env_on_expected=%s\n' "$env_expected"
  printf 'future_active_expected=1/0/0\n'
  printf 'required_scene camera=fixture_camera_static light=fixture_sun_static chunk=fixture_chunk_0_0_0\n'
  printf 'required_role front_transparent material=transparent_test_glass visible=required collision=solid\n'
  printf 'required_role behind_wall_transparent material=transparent_test_glass opaque_occlusion=required\n'
  printf 'required_role opaque_depth_occluder material=current_opaque_block depth_write=required\n'
  printf 'required_role adjacent_same_material_pair material=transparent_test_glass same_material_seam=hidden_or_explicit\n'
  printf 'required_role collision_probe material=transparent_test_glass collision_solidity=explicit\n'
  printf 'required_current_guard env_on_fallback transparent_requested=1 transparent_active=0 transparent_fallback=1 gpu_upload_fail=0 smoke_err=0 terrain_samples=nonzero\n'
  printf 'required_future_gate active_path transparent_active=1 transparent_fallback=0 gpu_upload_fail=0 opaque_depth_occlusion=required collision_solidity=required opaque_adjacent_faces_visible=required\n'
  printf 'non_goals shader_alpha=no transparent_pass=no sorting=no block_id=no asset=no protocol=no storage=no worldgen=no\n'
  printf 'summary transparent_fixture_scene_implementation_checklist_status=pending_scene_implementation transparent_fixture_pack_status=%s transparent_fixture_final_report_check_status=%s transparent_fixture_default_off_status=%s transparent_implementation_gate=false env_on_expected=%s future_active_expected=1/0/0\n' \
    "$pack_status" \
    "$final_report_status" \
    "$default_off_status" \
    "$env_expected"
} > "$tmp_checklist"

mv "$tmp_checklist" "$OUT_PATH"
cat "$OUT_PATH"
