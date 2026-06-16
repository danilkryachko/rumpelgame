#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
CHECKLIST_PATH="${1:-"$ROOT_DIR/logs/gpu_transparent_fixture_plan/transparent-fixture-scene-checklist.txt"}"
case "$CHECKLIST_PATH" in
  /*) ;;
  *) CHECKLIST_PATH="$ROOT_DIR/$CHECKLIST_PATH" ;;
esac
OUT_PATH="${2:-"$(dirname -- "$CHECKLIST_PATH")/transparent-fixture-scene-harness.txt"}"
case "$OUT_PATH" in
  /*) ;;
  *) OUT_PATH="$ROOT_DIR/$OUT_PATH" ;;
esac

fail() {
  echo "gpu_terrain_transparent_fixture_scene_harness: $*" >&2
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
mkdir -p "$(dirname -- "$OUT_PATH")"

fixture_line="$(required_line "$CHECKLIST_PATH" "fixture=gpu-transparent-depth-collision")"
material_line="$(required_line "$CHECKLIST_PATH" "material=transparent_test_glass")"
scene_status_line="$(required_line "$CHECKLIST_PATH" "scene_checklist_status=contract_ready")"
runtime_line="$(required_line "$CHECKLIST_PATH" "runtime_behavior=unchanged")"
ordinary_line="$(required_line "$CHECKLIST_PATH" "ordinary_world_visibility=absent")"
env_expected_line="$(required_line "$CHECKLIST_PATH" "env_on_expected=1/0/1")"
overlay_env_expected_line="$(required_line "$CHECKLIST_PATH" "overlay_env_on_expected=1/0/1")"
overlay_metadata_expected_line="$(required_line "$CHECKLIST_PATH" "overlay_metadata_expected=5/5")"
camera_line="$(required_line "$CHECKLIST_PATH" "camera fixed=required")"
light_line="$(required_line "$CHECKLIST_PATH" "light fixed=required")"
chunk_line="$(required_line "$CHECKLIST_PATH" "chunk fixed=required")"
front_line="$(required_line "$CHECKLIST_PATH" "block_role=front_transparent")"
behind_line="$(required_line "$CHECKLIST_PATH" "block_role=behind_wall_transparent")"
occluder_line="$(required_line "$CHECKLIST_PATH" "block_role=opaque_depth_occluder")"
adjacent_line="$(required_line "$CHECKLIST_PATH" "block_role=adjacent_same_material_pair")"
collision_line="$(required_line "$CHECKLIST_PATH" "block_role=collision_probe")"
overlay_metadata_line="$(required_line "$CHECKLIST_PATH" "overlay_metadata overlay_id=transparent_test_glass")"
env_off_line="$(required_line "$CHECKLIST_PATH" "assertion=env_off_current status=required")"
env_on_line="$(required_line "$CHECKLIST_PATH" "assertion=env_on_fallback_current status=required")"
future_active_line="$(required_line "$CHECKLIST_PATH" "assertion=future_active_path status=blocked_until_implementation")"
workload_line="$(required_line "$CHECKLIST_PATH" "assertion=future_workload_markers status=blocked_until_fixture")"
non_goals_line="$(required_line "$CHECKLIST_PATH" "non_goals")"
summary_line="$(required_line "$CHECKLIST_PATH" "summary transparent_fixture_scene_checklist_status=")"

fixture="${fixture_line#fixture=}"
material="${material_line#material=}"
scene_status="${scene_status_line#scene_checklist_status=}"
runtime_behavior="${runtime_line#runtime_behavior=}"
ordinary_visibility="${ordinary_line#ordinary_world_visibility=}"
env_expected="${env_expected_line#env_on_expected=}"
overlay_env_expected="${overlay_env_expected_line#overlay_env_on_expected=}"
overlay_metadata_expected="${overlay_metadata_expected_line#overlay_metadata_expected=}"
summary_scene_status="$(required_token "transparent_fixture_scene_checklist_status" "$summary_line" "scene checklist summary")"
summary_smoke_status="$(required_token "transparent_fixture_smoke_plan_status" "$summary_line" "scene checklist summary")"
summary_fixture="$(required_token "fixture" "$summary_line" "scene checklist summary")"
summary_material="$(required_token "material" "$summary_line" "scene checklist summary")"
summary_env_expected="$(required_token "env_on_expected" "$summary_line" "scene checklist summary")"
summary_overlay_env_expected="$(required_token "overlay_env_on_expected" "$summary_line" "scene checklist summary")"
summary_overlay_metadata_expected="$(required_token "overlay_metadata_expected" "$summary_line" "scene checklist summary")"

test "$fixture" = "gpu-transparent-depth-collision" || fail "unexpected fixture=$fixture"
test "$material" = "transparent_test_glass" || fail "unexpected material=$material"
test "$scene_status" = "contract_ready" || fail "unexpected scene_checklist_status=$scene_status"
test "$runtime_behavior" = "unchanged" || fail "unexpected runtime_behavior=$runtime_behavior"
test "$ordinary_visibility" = "absent" || fail "unexpected ordinary_world_visibility=$ordinary_visibility"
test "$env_expected" = "1/0/1" || fail "unexpected env_on_expected=$env_expected"
test "$overlay_env_expected" = "1/0/1" || fail "unexpected overlay_env_on_expected=$overlay_env_expected"
test "$overlay_metadata_expected" = "5/5" || fail "unexpected overlay_metadata_expected=$overlay_metadata_expected"
test "$summary_scene_status" = "$scene_status" || fail "summary scene checklist status does not match"
test "$summary_smoke_status" = "contract_ready" || fail "unexpected transparent_fixture_smoke_plan_status=$summary_smoke_status"
test "$summary_fixture" = "$fixture" || fail "summary fixture does not match"
test "$summary_material" = "$material" || fail "summary material does not match"
test "$summary_env_expected" = "$env_expected" || fail "summary env_on_expected does not match"
test "$summary_overlay_env_expected" = "$overlay_env_expected" || fail "summary overlay_env_on_expected does not match"
test "$summary_overlay_metadata_expected" = "$overlay_metadata_expected" || fail "summary overlay_metadata_expected does not match"

for token in position=fixture_camera_static look_at=fixture_center; do
  require_text "$camera_line" "$token" "camera"
done
for token in source=fixture_sun_static shadows=unchanged; do
  require_text "$light_line" "$token" "light"
done
for token in origin=fixture_chunk_0_0_0 worldgen=absent protocol=absent storage=absent; do
  require_text "$chunk_line" "$token" "chunk"
done
for token in "material=$material" relation=in_front_of_opaque_terrain expected_visible=required expected_collision=solid; do
  require_text "$front_line" "$token" "front transparent role"
done
for token in "material=$material" relation=behind_opaque_wall expected_opaque_occlusion=required; do
  require_text "$behind_line" "$token" "behind wall transparent role"
done
for token in material=current_opaque_block relation=in_front_of_transparent expected_depth_write=required; do
  require_text "$occluder_line" "$token" "opaque depth occluder role"
done
for token in "material=$material" relation=neighbor_pair expected_same_material_seam=hidden_or_explicit; do
  require_text "$adjacent_line" "$token" "adjacent same-material role"
done
for token in "material=$material" relation=ray_or_ground_path expected_collision_solidity=explicit; do
  require_text "$collision_line" "$token" "collision probe role"
done
for token in transparent_fixture_overlay_roles=5 transparent_fixture_overlay_blocks=5 geometry_active=0 chunk_data_mutation=no; do
  require_text "$overlay_metadata_line" "$token" "overlay metadata"
done
require_text "$env_off_line" "expected=ordinary_opaque_markers_unchanged" "env-off assertion"
for token in transparent_requested=1 transparent_active=0 transparent_fallback=1 transparent_fixture_overlay_requested=1 transparent_fixture_overlay_active=0 transparent_fixture_overlay_fallback=1 transparent_blocks=0 transparent_faces=0 transparent_draws=0 transparent_subchunks=0 gpu_upload_fail=0 smoke_err=0 terrain_samples=nonzero; do
  require_text "$env_on_line" "$token" "env-on fallback assertion"
done
for token in transparent_active=1 transparent_fallback=0 gpu_upload_fail=0 opaque_depth_occlusion=required collision_solidity=required opaque_adjacent_faces_visible=required; do
  require_text "$future_active_line" "$token" "future active assertion"
done
for token in transparent_blocks=blocked_until_fixture transparent_faces=blocked_until_fixture transparent_draws=blocked_until_fixture transparent_subchunks=blocked_until_fixture; do
  require_text "$workload_line" "$token" "future workload assertion"
done
require_text "$non_goals_line" "shader_alpha=no transparent_pass=no sorting=no block_id=no asset=no protocol=no storage=no worldgen=no" "non-goals"

tmp_harness="$OUT_PATH.tmp"
trap 'rm -f "$tmp_harness"' EXIT

{
  printf 'GPU terrain transparent fixture scene harness\n'
  printf 'scene_checklist=%s\n' "$(relative_path "$CHECKLIST_PATH")"
  printf 'fixture=%s\n' "$fixture"
  printf 'material=%s\n' "$material"
  printf 'scene_harness_status=contract_ready\n'
  printf 'scene_checklist_status=%s\n' "$scene_status"
  printf 'runtime_behavior=%s\n' "$runtime_behavior"
  printf 'ordinary_world_visibility=%s\n' "$ordinary_visibility"
  printf 'env_on_expected=%s\n' "$env_expected"
  printf 'overlay_env_on_expected=%s\n' "$overlay_env_expected"
  printf 'overlay_metadata_expected=%s\n' "$overlay_metadata_expected"
  printf 'fixture_scene status=blocked_until_scene_harness camera=fixture_camera_static light=fixture_sun_static chunk=fixture_chunk_0_0_0\n'
  printf 'role_check=front_transparent status=blocked_until_scene_harness material=%s expected_visible=required expected_collision=solid\n' "$material"
  printf 'role_check=behind_wall_transparent status=blocked_until_scene_harness material=%s expected_opaque_occlusion=required\n' "$material"
  printf 'role_check=opaque_depth_occluder status=blocked_until_scene_harness material=current_opaque_block expected_depth_write=required\n'
  printf 'role_check=adjacent_same_material_pair status=blocked_until_scene_harness material=%s expected_same_material_seam=hidden_or_explicit\n' "$material"
  printf 'role_check=collision_probe status=blocked_until_scene_harness material=%s expected_collision_solidity=explicit\n' "$material"
  printf 'overlay_metadata status=contract_ready overlay_id=transparent_test_glass transparent_fixture_overlay_roles=5 transparent_fixture_overlay_blocks=5 geometry_active=0 chunk_data_mutation=no\n'
  printf 'assertion=env_off_current status=required expected=ordinary_opaque_markers_unchanged\n'
  printf 'assertion=env_on_fallback_current status=required transparent_requested=1 transparent_active=0 transparent_fallback=1 transparent_fixture_overlay_requested=1 transparent_fixture_overlay_active=0 transparent_fixture_overlay_fallback=1 transparent_blocks=0 transparent_faces=0 transparent_draws=0 transparent_subchunks=0 gpu_upload_fail=0 smoke_err=0 terrain_samples=nonzero\n'
  printf 'assertion=future_active_path status=blocked_until_implementation transparent_active=1 transparent_fallback=0 gpu_upload_fail=0 opaque_depth_occlusion=required collision_solidity=required opaque_adjacent_faces_visible=required\n'
  printf 'assertion=future_workload_markers status=blocked_until_fixture transparent_blocks=blocked_until_fixture transparent_faces=blocked_until_fixture transparent_draws=blocked_until_fixture transparent_subchunks=blocked_until_fixture\n'
  printf 'non_goals shader_alpha=no transparent_pass=no sorting=no block_id=no asset=no protocol=no storage=no worldgen=no\n'
  printf 'command_generate_scene_checklist=sh scripts/gpu_terrain_transparent_fixture_scene_checklist.sh logs/gpu_transparent_fixture_plan/transparent-fixture-smoke-plan.txt %s\n' "$(relative_path "$CHECKLIST_PATH")"
  printf 'command_generate_scene_harness=sh scripts/gpu_terrain_transparent_fixture_scene_harness.sh %s %s\n' \
    "$(relative_path "$CHECKLIST_PATH")" \
    "$(relative_path "$OUT_PATH")"
  printf 'summary transparent_fixture_scene_harness_status=contract_ready transparent_fixture_scene_checklist_status=%s transparent_fixture_smoke_plan_status=%s fixture=%s material=%s roles=5 transparent_fixture_overlay_roles=5 transparent_fixture_overlay_blocks=5 env_on_expected=%s overlay_env_on_expected=%s overlay_metadata_expected=%s\n' \
    "$scene_status" \
    "$summary_smoke_status" \
    "$fixture" \
    "$material" \
    "$env_expected" \
    "$overlay_env_expected" \
    "$overlay_metadata_expected"
} > "$tmp_harness"

mv "$tmp_harness" "$OUT_PATH"
cat "$OUT_PATH"
