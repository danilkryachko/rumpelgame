#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SMOKE_PLAN_PATH="${1:-"$ROOT_DIR/logs/gpu_transparent_fixture_plan/transparent-fixture-smoke-plan.txt"}"
case "$SMOKE_PLAN_PATH" in
  /*) ;;
  *) SMOKE_PLAN_PATH="$ROOT_DIR/$SMOKE_PLAN_PATH" ;;
esac
OUT_PATH="${2:-"$(dirname -- "$SMOKE_PLAN_PATH")/transparent-fixture-scene-checklist.txt"}"
case "$OUT_PATH" in
  /*) ;;
  *) OUT_PATH="$ROOT_DIR/$OUT_PATH" ;;
esac

fail() {
  echo "gpu_terrain_transparent_fixture_scene_checklist: $*" >&2
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

test -s "$SMOKE_PLAN_PATH" || fail "missing transparent fixture smoke plan $SMOKE_PLAN_PATH"
mkdir -p "$(dirname -- "$OUT_PATH")"

fixture_line="$(required_line "$SMOKE_PLAN_PATH" "fixture=gpu-transparent-depth-collision")"
material_line="$(required_line "$SMOKE_PLAN_PATH" "material=transparent_test_glass")"
smoke_status_line="$(required_line "$SMOKE_PLAN_PATH" "smoke_plan_status=contract_ready")"
runtime_line="$(required_line "$SMOKE_PLAN_PATH" "runtime_behavior=unchanged")"
ordinary_line="$(required_line "$SMOKE_PLAN_PATH" "ordinary_world_visibility=absent")"
pack_status_line="$(required_line "$SMOKE_PLAN_PATH" "pack_status=pass")"
env_expected_line="$(required_line "$SMOKE_PLAN_PATH" "env_on_expected=1/0/1")"
overlay_env_expected_line="$(required_line "$SMOKE_PLAN_PATH" "overlay_env_on_expected=1/0/1")"
overlay_metadata_expected_line="$(required_line "$SMOKE_PLAN_PATH" "overlay_metadata_expected=5/5")"
env_off_line="$(required_line "$SMOKE_PLAN_PATH" "step=env_off_current status=required")"
env_on_line="$(required_line "$SMOKE_PLAN_PATH" "step=env_on_fallback_current status=required")"
overlay_metadata_line="$(required_line "$SMOKE_PLAN_PATH" "step=client_overlay_metadata status=required")"
fixture_scene_line="$(required_line "$SMOKE_PLAN_PATH" "step=future_fixture_scene status=required")"
workload_line="$(required_line "$SMOKE_PLAN_PATH" "step=future_workload_markers status=blocked_until_fixture")"
future_active_line="$(required_line "$SMOKE_PLAN_PATH" "step=future_active_gate status=blocked_until_implementation")"
non_goals_line="$(required_line "$SMOKE_PLAN_PATH" "step=non_goals status=enforced")"
summary_line="$(required_line "$SMOKE_PLAN_PATH" "summary transparent_fixture_smoke_plan_status=")"

fixture="${fixture_line#fixture=}"
material="${material_line#material=}"
smoke_status="${smoke_status_line#smoke_plan_status=}"
runtime_behavior="${runtime_line#runtime_behavior=}"
ordinary_visibility="${ordinary_line#ordinary_world_visibility=}"
pack_status="${pack_status_line#pack_status=}"
env_expected="${env_expected_line#env_on_expected=}"
overlay_env_expected="${overlay_env_expected_line#overlay_env_on_expected=}"
overlay_metadata_expected="${overlay_metadata_expected_line#overlay_metadata_expected=}"
summary_smoke_status="$(required_token "transparent_fixture_smoke_plan_status" "$summary_line" "smoke summary")"
summary_pack_status="$(required_token "transparent_fixture_pack_status" "$summary_line" "smoke summary")"
summary_plan_status="$(required_token "fixture_plan_status" "$summary_line" "smoke summary")"
summary_harness_status="$(required_token "transparent_fixture_harness_status" "$summary_line" "smoke summary")"
summary_env_expected="$(required_token "env_on_expected" "$summary_line" "smoke summary")"
summary_overlay_env_expected="$(required_token "overlay_env_on_expected" "$summary_line" "smoke summary")"
summary_overlay_metadata_expected="$(required_token "overlay_metadata_expected" "$summary_line" "smoke summary")"

test "$fixture" = "gpu-transparent-depth-collision" || fail "unexpected fixture=$fixture"
test "$material" = "transparent_test_glass" || fail "unexpected material=$material"
test "$smoke_status" = "contract_ready" || fail "unexpected smoke_plan_status=$smoke_status"
test "$runtime_behavior" = "unchanged" || fail "unexpected runtime_behavior=$runtime_behavior"
test "$ordinary_visibility" = "absent" || fail "unexpected ordinary_world_visibility=$ordinary_visibility"
test "$pack_status" = "pass" || fail "unexpected pack_status=$pack_status"
test "$env_expected" = "1/0/1" || fail "unexpected env_on_expected=$env_expected"
test "$overlay_env_expected" = "1/0/1" || fail "unexpected overlay_env_on_expected=$overlay_env_expected"
test "$overlay_metadata_expected" = "5/5" || fail "unexpected overlay_metadata_expected=$overlay_metadata_expected"
test "$summary_smoke_status" = "$smoke_status" || fail "summary smoke status does not match"
test "$summary_pack_status" = "$pack_status" || fail "summary pack status does not match"
test "$summary_plan_status" = "contract_ready" || fail "unexpected fixture_plan_status=$summary_plan_status"
test "$summary_harness_status" = "contract_ready" || fail "unexpected transparent_fixture_harness_status=$summary_harness_status"
test "$summary_env_expected" = "$env_expected" || fail "summary env_on_expected does not match"
test "$summary_overlay_env_expected" = "$overlay_env_expected" || fail "summary overlay_env_on_expected does not match"
test "$summary_overlay_metadata_expected" = "$overlay_metadata_expected" || fail "summary overlay_metadata_expected does not match"

for token in fixed_camera=required fixed_light=required depth_occluder=required adjacent_same_material_pair=required collision_probe=required; do
  require_text "$fixture_scene_line" "$token" "future fixture scene"
done
for token in transparent_blocks=blocked_until_fixture transparent_faces=blocked_until_fixture transparent_draws=blocked_until_fixture transparent_subchunks=blocked_until_fixture; do
  require_text "$workload_line" "$token" "future workload markers"
done
for token in transparent_active=1 transparent_fallback=0 gpu_upload_fail=0 opaque_depth_occlusion=required collision_solidity=required opaque_adjacent_faces_visible=required; do
  require_text "$future_active_line" "$token" "future active gate"
done
require_text "$env_off_line" "expected=ordinary_opaque_markers_unchanged" "env-off gate"
for token in transparent_requested=1 transparent_active=0 transparent_fallback=1 transparent_fixture_overlay_requested=1 transparent_fixture_overlay_active=0 transparent_fixture_overlay_fallback=1 transparent_blocks=0 transparent_faces=0 transparent_draws=0 transparent_subchunks=0 gpu_upload_fail=0 smoke_err=0 terrain_samples=nonzero; do
  require_text "$env_on_line" "$token" "env-on fallback gate"
done
for token in overlay_id=transparent_test_glass transparent_fixture_overlay_roles=5 transparent_fixture_overlay_blocks=5 geometry_active=0 chunk_data_mutation=no; do
  require_text "$overlay_metadata_line" "$token" "overlay metadata"
done
require_text "$non_goals_line" "shader_alpha=no transparent_pass=no sorting=no block_id=no asset=no protocol=no storage=no worldgen=no" "non-goals"

tmp_checklist="$OUT_PATH.tmp"
trap 'rm -f "$tmp_checklist"' EXIT

{
  printf 'GPU terrain transparent fixture scene checklist\n'
  printf 'smoke_plan=%s\n' "$(relative_path "$SMOKE_PLAN_PATH")"
  printf 'fixture=%s\n' "$fixture"
  printf 'material=%s\n' "$material"
  printf 'scene_checklist_status=contract_ready\n'
  printf 'runtime_behavior=%s\n' "$runtime_behavior"
  printf 'ordinary_world_visibility=%s\n' "$ordinary_visibility"
  printf 'env_on_expected=%s\n' "$env_expected"
  printf 'overlay_env_on_expected=%s\n' "$overlay_env_expected"
  printf 'overlay_metadata_expected=%s\n' "$overlay_metadata_expected"
  printf 'camera fixed=required position=fixture_camera_static look_at=fixture_center\n'
  printf 'light fixed=required source=fixture_sun_static shadows=unchanged\n'
  printf 'chunk fixed=required origin=fixture_chunk_0_0_0 worldgen=absent protocol=absent storage=absent\n'
  printf 'block_role=front_transparent material=%s relation=in_front_of_opaque_terrain expected_visible=required expected_collision=solid\n' "$material"
  printf 'block_role=behind_wall_transparent material=%s relation=behind_opaque_wall expected_opaque_occlusion=required\n' "$material"
  printf 'block_role=opaque_depth_occluder material=current_opaque_block relation=in_front_of_transparent expected_depth_write=required\n'
  printf 'block_role=adjacent_same_material_pair material=%s relation=neighbor_pair expected_same_material_seam=hidden_or_explicit\n' "$material"
  printf 'block_role=collision_probe material=%s relation=ray_or_ground_path expected_collision_solidity=explicit\n' "$material"
  printf 'overlay_metadata overlay_id=transparent_test_glass transparent_fixture_overlay_roles=5 transparent_fixture_overlay_blocks=5 geometry_active=0 chunk_data_mutation=no\n'
  printf 'assertion=env_off_current status=required expected=ordinary_opaque_markers_unchanged\n'
  printf 'assertion=env_on_fallback_current status=required transparent_requested=1 transparent_active=0 transparent_fallback=1 transparent_fixture_overlay_requested=1 transparent_fixture_overlay_active=0 transparent_fixture_overlay_fallback=1 transparent_blocks=0 transparent_faces=0 transparent_draws=0 transparent_subchunks=0 gpu_upload_fail=0 smoke_err=0 terrain_samples=nonzero\n'
  printf 'assertion=future_active_path status=blocked_until_implementation transparent_active=1 transparent_fallback=0 gpu_upload_fail=0 opaque_depth_occlusion=required collision_solidity=required opaque_adjacent_faces_visible=required\n'
  printf 'assertion=future_workload_markers status=blocked_until_fixture transparent_blocks=blocked_until_fixture transparent_faces=blocked_until_fixture transparent_draws=blocked_until_fixture transparent_subchunks=blocked_until_fixture\n'
  printf 'non_goals shader_alpha=no transparent_pass=no sorting=no block_id=no asset=no protocol=no storage=no worldgen=no\n'
  printf 'summary transparent_fixture_scene_checklist_status=contract_ready transparent_fixture_smoke_plan_status=%s fixture=%s material=%s env_on_expected=%s overlay_env_on_expected=%s overlay_metadata_expected=%s\n' \
    "$summary_smoke_status" \
    "$fixture" \
    "$material" \
    "$env_expected" \
    "$overlay_env_expected" \
    "$overlay_metadata_expected"
} > "$tmp_checklist"

mv "$tmp_checklist" "$OUT_PATH"
cat "$OUT_PATH"
