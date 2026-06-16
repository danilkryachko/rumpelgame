#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
CHECKLIST_PATH="${1:-"$ROOT_DIR/logs/gpu_transparent_fixture_plan/transparent-fixture-scene-checklist.txt"}"
case "$CHECKLIST_PATH" in
  /*) ;;
  *) CHECKLIST_PATH="$ROOT_DIR/$CHECKLIST_PATH" ;;
esac
HARNESS_PATH="${2:-"$(dirname -- "$CHECKLIST_PATH")/transparent-fixture-scene-harness.txt"}"
case "$HARNESS_PATH" in
  /*) ;;
  *) HARNESS_PATH="$ROOT_DIR/$HARNESS_PATH" ;;
esac
OUT_PATH="${3:-"$(dirname -- "$HARNESS_PATH")/transparent-fixture-scene-harness-check.txt"}"
case "$OUT_PATH" in
  /*) ;;
  *) OUT_PATH="$ROOT_DIR/$OUT_PATH" ;;
esac

fail() {
  echo "gpu_terrain_transparent_fixture_scene_harness_check: $*" >&2
  exit 1
}

relative_path() {
  path="$1"
  case "$path" in
    "$ROOT_DIR"/*) printf '%s\n' "${path#$ROOT_DIR/}" ;;
    *) printf '%s\n' "$path" ;;
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

required_token() {
  key="$1"
  line="$2"
  row_label="$3"
  value="$(line_token "$key" "$line")"
  test -n "$value" || fail "missing $key in $row_label row: $line"
  printf '%s\n' "$value"
}

require_text() {
  text="$1"
  token="$2"
  row_label="$3"
  printf '%s\n' "$text" | grep -F -- "$token" >/dev/null || fail "$row_label missing $token"
}

test -s "$CHECKLIST_PATH" || fail "missing transparent fixture scene checklist $CHECKLIST_PATH"
test -s "$HARNESS_PATH" || fail "missing transparent fixture scene harness $HARNESS_PATH"
mkdir -p "$(dirname -- "$OUT_PATH")"

checklist_fixture_line="$(required_line "$CHECKLIST_PATH" "fixture=gpu-transparent-depth-collision")"
checklist_material_line="$(required_line "$CHECKLIST_PATH" "material=transparent_test_glass")"
checklist_status_line="$(required_line "$CHECKLIST_PATH" "scene_checklist_status=contract_ready")"
checklist_runtime_line="$(required_line "$CHECKLIST_PATH" "runtime_behavior=unchanged")"
checklist_ordinary_line="$(required_line "$CHECKLIST_PATH" "ordinary_world_visibility=absent")"
checklist_env_line="$(required_line "$CHECKLIST_PATH" "env_on_expected=1/0/1")"
checklist_overlay_env_line="$(required_line "$CHECKLIST_PATH" "overlay_env_on_expected=1/0/1")"
checklist_overlay_metadata_expected_line="$(required_line "$CHECKLIST_PATH" "overlay_metadata_expected=5/5")"
checklist_front_line="$(required_line "$CHECKLIST_PATH" "block_role=front_transparent")"
checklist_behind_line="$(required_line "$CHECKLIST_PATH" "block_role=behind_wall_transparent")"
checklist_occluder_line="$(required_line "$CHECKLIST_PATH" "block_role=opaque_depth_occluder")"
checklist_adjacent_line="$(required_line "$CHECKLIST_PATH" "block_role=adjacent_same_material_pair")"
checklist_collision_line="$(required_line "$CHECKLIST_PATH" "block_role=collision_probe")"
checklist_overlay_metadata_line="$(required_line "$CHECKLIST_PATH" "overlay_metadata overlay_id=transparent_test_glass")"
checklist_env_off_line="$(required_line "$CHECKLIST_PATH" "assertion=env_off_current status=required")"
checklist_env_on_line="$(required_line "$CHECKLIST_PATH" "assertion=env_on_fallback_current status=required")"
checklist_future_line="$(required_line "$CHECKLIST_PATH" "assertion=future_active_path status=blocked_until_implementation")"
checklist_workload_line="$(required_line "$CHECKLIST_PATH" "assertion=future_workload_markers status=blocked_until_fixture")"
checklist_non_goals_line="$(required_line "$CHECKLIST_PATH" "non_goals")"
checklist_summary_line="$(required_line "$CHECKLIST_PATH" "summary transparent_fixture_scene_checklist_status=")"

fixture="${checklist_fixture_line#fixture=}"
material="${checklist_material_line#material=}"
scene_status="${checklist_status_line#scene_checklist_status=}"
runtime_behavior="${checklist_runtime_line#runtime_behavior=}"
ordinary_visibility="${checklist_ordinary_line#ordinary_world_visibility=}"
env_expected="${checklist_env_line#env_on_expected=}"
overlay_env_expected="${checklist_overlay_env_line#overlay_env_on_expected=}"
overlay_metadata_expected="${checklist_overlay_metadata_expected_line#overlay_metadata_expected=}"
summary_scene_status="$(required_token "transparent_fixture_scene_checklist_status" "$checklist_summary_line" "checklist summary")"
summary_smoke_status="$(required_token "transparent_fixture_smoke_plan_status" "$checklist_summary_line" "checklist summary")"
summary_fixture="$(required_token "fixture" "$checklist_summary_line" "checklist summary")"
summary_material="$(required_token "material" "$checklist_summary_line" "checklist summary")"
summary_env_expected="$(required_token "env_on_expected" "$checklist_summary_line" "checklist summary")"
summary_overlay_env_expected="$(required_token "overlay_env_on_expected" "$checklist_summary_line" "checklist summary")"
summary_overlay_metadata_expected="$(required_token "overlay_metadata_expected" "$checklist_summary_line" "checklist summary")"

test "$fixture" = "gpu-transparent-depth-collision" || fail "unexpected checklist fixture=$fixture"
test "$material" = "transparent_test_glass" || fail "unexpected checklist material=$material"
test "$scene_status" = "contract_ready" || fail "unexpected scene_checklist_status=$scene_status"
test "$runtime_behavior" = "unchanged" || fail "unexpected runtime_behavior=$runtime_behavior"
test "$ordinary_visibility" = "absent" || fail "unexpected ordinary_world_visibility=$ordinary_visibility"
test "$env_expected" = "1/0/1" || fail "unexpected env_on_expected=$env_expected"
test "$overlay_env_expected" = "1/0/1" || fail "unexpected overlay_env_on_expected=$overlay_env_expected"
test "$overlay_metadata_expected" = "5/5" || fail "unexpected overlay_metadata_expected=$overlay_metadata_expected"
test "$summary_scene_status" = "$scene_status" || fail "checklist summary scene status does not match"
test "$summary_smoke_status" = "contract_ready" || fail "unexpected transparent_fixture_smoke_plan_status=$summary_smoke_status"
test "$summary_fixture" = "$fixture" || fail "checklist summary fixture does not match"
test "$summary_material" = "$material" || fail "checklist summary material does not match"
test "$summary_env_expected" = "$env_expected" || fail "checklist summary env_on_expected does not match"
test "$summary_overlay_env_expected" = "$overlay_env_expected" || fail "checklist summary overlay_env_on_expected does not match"
test "$summary_overlay_metadata_expected" = "$overlay_metadata_expected" || fail "checklist summary overlay_metadata_expected does not match"

harness_fixture_line="$(required_line "$HARNESS_PATH" "fixture=gpu-transparent-depth-collision")"
harness_material_line="$(required_line "$HARNESS_PATH" "material=transparent_test_glass")"
harness_status_line="$(required_line "$HARNESS_PATH" "scene_harness_status=contract_ready")"
harness_scene_status_line="$(required_line "$HARNESS_PATH" "scene_checklist_status=contract_ready")"
harness_runtime_line="$(required_line "$HARNESS_PATH" "runtime_behavior=unchanged")"
harness_ordinary_line="$(required_line "$HARNESS_PATH" "ordinary_world_visibility=absent")"
harness_env_line="$(required_line "$HARNESS_PATH" "env_on_expected=1/0/1")"
harness_overlay_env_line="$(required_line "$HARNESS_PATH" "overlay_env_on_expected=1/0/1")"
harness_overlay_metadata_expected_line="$(required_line "$HARNESS_PATH" "overlay_metadata_expected=5/5")"
harness_scene_line="$(required_line "$HARNESS_PATH" "fixture_scene status=blocked_until_scene_harness")"
harness_front_line="$(required_line "$HARNESS_PATH" "role_check=front_transparent")"
harness_behind_line="$(required_line "$HARNESS_PATH" "role_check=behind_wall_transparent")"
harness_occluder_line="$(required_line "$HARNESS_PATH" "role_check=opaque_depth_occluder")"
harness_adjacent_line="$(required_line "$HARNESS_PATH" "role_check=adjacent_same_material_pair")"
harness_collision_line="$(required_line "$HARNESS_PATH" "role_check=collision_probe")"
harness_overlay_metadata_line="$(required_line "$HARNESS_PATH" "overlay_metadata status=contract_ready overlay_id=transparent_test_glass")"
harness_env_off_line="$(required_line "$HARNESS_PATH" "assertion=env_off_current status=required")"
harness_env_on_line="$(required_line "$HARNESS_PATH" "assertion=env_on_fallback_current status=required")"
harness_future_line="$(required_line "$HARNESS_PATH" "assertion=future_active_path status=blocked_until_implementation")"
harness_workload_line="$(required_line "$HARNESS_PATH" "assertion=future_workload_markers status=blocked_until_fixture")"
harness_non_goals_line="$(required_line "$HARNESS_PATH" "non_goals")"
harness_summary_line="$(required_line "$HARNESS_PATH" "summary transparent_fixture_scene_harness_status=")"

harness_status="${harness_status_line#scene_harness_status=}"
harness_summary_status="$(required_token "transparent_fixture_scene_harness_status" "$harness_summary_line" "harness summary")"
harness_summary_scene_status="$(required_token "transparent_fixture_scene_checklist_status" "$harness_summary_line" "harness summary")"
harness_summary_smoke_status="$(required_token "transparent_fixture_smoke_plan_status" "$harness_summary_line" "harness summary")"
harness_summary_fixture="$(required_token "fixture" "$harness_summary_line" "harness summary")"
harness_summary_material="$(required_token "material" "$harness_summary_line" "harness summary")"
harness_summary_roles="$(required_token "roles" "$harness_summary_line" "harness summary")"
harness_summary_env_expected="$(required_token "env_on_expected" "$harness_summary_line" "harness summary")"
harness_summary_overlay_env_expected="$(required_token "overlay_env_on_expected" "$harness_summary_line" "harness summary")"
harness_summary_overlay_metadata_expected="$(required_token "overlay_metadata_expected" "$harness_summary_line" "harness summary")"
harness_summary_overlay_roles="$(required_token "transparent_fixture_overlay_roles" "$harness_summary_line" "harness summary")"
harness_summary_overlay_blocks="$(required_token "transparent_fixture_overlay_blocks" "$harness_summary_line" "harness summary")"

test "${harness_fixture_line#fixture=}" = "$fixture" || fail "harness fixture does not match checklist"
test "${harness_material_line#material=}" = "$material" || fail "harness material does not match checklist"
test "$harness_status" = "contract_ready" || fail "unexpected scene_harness_status=$harness_status"
test "${harness_scene_status_line#scene_checklist_status=}" = "$scene_status" || fail "harness scene_checklist_status does not match checklist"
test "${harness_runtime_line#runtime_behavior=}" = "$runtime_behavior" || fail "harness runtime_behavior does not match checklist"
test "${harness_ordinary_line#ordinary_world_visibility=}" = "$ordinary_visibility" || fail "harness ordinary_world_visibility does not match checklist"
test "${harness_env_line#env_on_expected=}" = "$env_expected" || fail "harness env_on_expected does not match checklist"
test "${harness_overlay_env_line#overlay_env_on_expected=}" = "$overlay_env_expected" || fail "harness overlay_env_on_expected does not match checklist"
test "${harness_overlay_metadata_expected_line#overlay_metadata_expected=}" = "$overlay_metadata_expected" || fail "harness overlay_metadata_expected does not match checklist"
test "$harness_summary_status" = "$harness_status" || fail "harness summary status does not match"
test "$harness_summary_scene_status" = "$scene_status" || fail "harness summary scene checklist status does not match"
test "$harness_summary_smoke_status" = "$summary_smoke_status" || fail "harness summary smoke status does not match"
test "$harness_summary_fixture" = "$fixture" || fail "harness summary fixture does not match"
test "$harness_summary_material" = "$material" || fail "harness summary material does not match"
test "$harness_summary_roles" = "5" || fail "unexpected harness summary roles=$harness_summary_roles"
test "$harness_summary_env_expected" = "$env_expected" || fail "harness summary env_on_expected does not match"
test "$harness_summary_overlay_env_expected" = "$overlay_env_expected" || fail "harness summary overlay_env_on_expected does not match"
test "$harness_summary_overlay_metadata_expected" = "$overlay_metadata_expected" || fail "harness summary overlay_metadata_expected does not match"
test "$harness_summary_overlay_roles" = "5" || fail "unexpected harness summary overlay roles=$harness_summary_overlay_roles"
test "$harness_summary_overlay_blocks" = "5" || fail "unexpected harness summary overlay blocks=$harness_summary_overlay_blocks"

for token in camera=fixture_camera_static light=fixture_sun_static chunk=fixture_chunk_0_0_0; do
  require_text "$harness_scene_line" "$token" "harness fixture scene"
done
for token in "material=$material" expected_visible=required expected_collision=solid; do
  require_text "$checklist_front_line" "$token" "checklist front transparent role"
  require_text "$harness_front_line" "$token" "harness front transparent role"
done
for token in "material=$material" expected_opaque_occlusion=required; do
  require_text "$checklist_behind_line" "$token" "checklist behind wall role"
  require_text "$harness_behind_line" "$token" "harness behind wall role"
done
for token in material=current_opaque_block expected_depth_write=required; do
  require_text "$checklist_occluder_line" "$token" "checklist opaque depth occluder role"
  require_text "$harness_occluder_line" "$token" "harness opaque depth occluder role"
done
for token in "material=$material" expected_same_material_seam=hidden_or_explicit; do
  require_text "$checklist_adjacent_line" "$token" "checklist adjacent same-material role"
  require_text "$harness_adjacent_line" "$token" "harness adjacent same-material role"
done
for token in "material=$material" expected_collision_solidity=explicit; do
  require_text "$checklist_collision_line" "$token" "checklist collision probe role"
  require_text "$harness_collision_line" "$token" "harness collision probe role"
done
for token in transparent_fixture_overlay_roles=5 transparent_fixture_overlay_blocks=5 geometry_active=0 chunk_data_mutation=no; do
  require_text "$checklist_overlay_metadata_line" "$token" "checklist overlay metadata"
  require_text "$harness_overlay_metadata_line" "$token" "harness overlay metadata"
done
for token in expected=ordinary_opaque_markers_unchanged; do
  require_text "$checklist_env_off_line" "$token" "checklist env-off assertion"
  require_text "$harness_env_off_line" "$token" "harness env-off assertion"
done
for token in transparent_requested=1 transparent_active=0 transparent_fallback=1 transparent_fixture_overlay_requested=1 transparent_fixture_overlay_active=0 transparent_fixture_overlay_fallback=1 transparent_blocks=0 transparent_faces=0 transparent_draws=0 transparent_subchunks=0 gpu_upload_fail=0 smoke_err=0 terrain_samples=nonzero; do
  require_text "$checklist_env_on_line" "$token" "checklist env-on assertion"
  require_text "$harness_env_on_line" "$token" "harness env-on assertion"
done
for token in transparent_active=1 transparent_fallback=0 gpu_upload_fail=0 opaque_depth_occlusion=required collision_solidity=required opaque_adjacent_faces_visible=required; do
  require_text "$checklist_future_line" "$token" "checklist future active assertion"
  require_text "$harness_future_line" "$token" "harness future active assertion"
done
for token in transparent_blocks=blocked_until_fixture transparent_faces=blocked_until_fixture transparent_draws=blocked_until_fixture transparent_subchunks=blocked_until_fixture; do
  require_text "$checklist_workload_line" "$token" "checklist workload assertion"
  require_text "$harness_workload_line" "$token" "harness workload assertion"
done
non_goals="shader_alpha=no transparent_pass=no sorting=no block_id=no asset=no protocol=no storage=no worldgen=no"
require_text "$checklist_non_goals_line" "$non_goals" "checklist non-goals"
require_text "$harness_non_goals_line" "$non_goals" "harness non-goals"

tmp_check="$OUT_PATH.tmp"
trap 'rm -f "$tmp_check"' EXIT

{
  printf 'GPU terrain transparent fixture scene harness check\n'
  printf 'scene_checklist=%s\n' "$(relative_path "$CHECKLIST_PATH")"
  printf 'scene_harness=%s\n' "$(relative_path "$HARNESS_PATH")"
  printf 'fixture=%s\n' "$fixture"
  printf 'material=%s\n' "$material"
  printf 'scene_checklist_status=%s\n' "$scene_status"
  printf 'scene_harness_status=%s\n' "$harness_status"
  printf 'runtime_behavior=%s\n' "$runtime_behavior"
  printf 'ordinary_world_visibility=%s\n' "$ordinary_visibility"
  printf 'env_on_expected=%s\n' "$env_expected"
  printf 'overlay_env_on_expected=%s\n' "$overlay_env_expected"
  printf 'overlay_metadata_expected=%s\n' "$overlay_metadata_expected"
  printf 'roles=5\n'
  printf 'transparent_fixture_overlay_roles=5\n'
  printf 'transparent_fixture_overlay_blocks=5\n'
  printf 'overlay_geometry_active=0\n'
  printf 'overlay_chunk_data_mutation=no\n'
  printf 'future_gates=blocked_until_implementation\n'
  printf 'workload_gates=blocked_until_fixture\n'
  printf 'non_goals %s\n' "$non_goals"
  printf 'summary transparent_fixture_scene_harness_check_status=pass transparent_fixture_scene_harness_status=%s transparent_fixture_scene_checklist_status=%s transparent_fixture_smoke_plan_status=%s fixture=%s material=%s roles=5 transparent_fixture_overlay_roles=5 transparent_fixture_overlay_blocks=5 env_on_expected=%s overlay_env_on_expected=%s overlay_metadata_expected=%s\n' \
    "$harness_status" \
    "$scene_status" \
    "$summary_smoke_status" \
    "$fixture" \
    "$material" \
    "$env_expected" \
    "$overlay_env_expected" \
    "$overlay_metadata_expected"
} > "$tmp_check"

mv "$tmp_check" "$OUT_PATH"
cat "$OUT_PATH"
