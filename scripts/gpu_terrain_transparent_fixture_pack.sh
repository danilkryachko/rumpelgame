#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
PACK_DIR="${1:-"$ROOT_DIR/logs/gpu_transparent_fixture_plan"}"
case "$PACK_DIR" in
  /*) ;;
  *) PACK_DIR="$ROOT_DIR/$PACK_DIR" ;;
esac
LOG_DIR="${2:-"$ROOT_DIR/logs"}"
case "$LOG_DIR" in
  /*) ;;
  *) LOG_DIR="$ROOT_DIR/$LOG_DIR" ;;
esac
OUT_PATH="${3:-"$PACK_DIR/transparent-fixture-pack.txt"}"
case "$OUT_PATH" in
  /*) ;;
  *) OUT_PATH="$ROOT_DIR/$OUT_PATH" ;;
esac

CONTRACT_PATH="$ROOT_DIR/docs/GPU_TRANSPARENT_PATH.md"
PLAN_PATH="$PACK_DIR/transparent-fixture-plan.txt"
HARNESS_PATH="$PACK_DIR/transparent-fixture-harness.txt"
CHECK_PATH="$PACK_DIR/transparent-fixture-check.txt"
SMOKE_PLAN_PATH="$PACK_DIR/transparent-fixture-smoke-plan.txt"
SCENE_CHECKLIST_PATH="$PACK_DIR/transparent-fixture-scene-checklist.txt"
SCENE_HARNESS_PATH="$PACK_DIR/transparent-fixture-scene-harness.txt"
SCENE_HARNESS_CHECK_PATH="$PACK_DIR/transparent-fixture-scene-harness-check.txt"
ACCEPTANCE_CHECK_PATH="$PACK_DIR/transparent-fixture-acceptance-check.txt"
DEFAULT_OFF_CHECK_PATH="$PACK_DIR/transparent-fixture-default-off-check.txt"
FINAL_REPORT_CHECK_PATH="$PACK_DIR/transparent-fixture-final-report-check.txt"
SCENE_IMPLEMENTATION_CHECKLIST_PATH="$PACK_DIR/transparent-fixture-scene-implementation-checklist.txt"
SCENE_IMPLEMENTATION_GATE_CHECK_PATH="$PACK_DIR/transparent-fixture-scene-implementation-gate-check.txt"
REPORT_PATH="$PACK_DIR/gpu-terrain-transparent-fixture-report.txt"
REPORT_CHECK_PATH="$PACK_DIR/transparent-fixture-report-check.txt"

fail() {
  echo "gpu_terrain_transparent_fixture_pack: $*" >&2
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

test -s "$CONTRACT_PATH" || fail "missing transparent contract $CONTRACT_PATH"
if [ "$LOG_DIR" = "$PACK_DIR" ]; then
  mkdir -p "$PACK_DIR"
fi
test -d "$LOG_DIR" || fail "missing log dir $LOG_DIR"
report_source="$(find "$LOG_DIR" \( -name '*summary.txt' -o -name '*.png.txt' \) -type f -print | sed -n '1p')"
test -n "$report_source" || fail "missing report source summaries under $LOG_DIR"
mkdir -p "$PACK_DIR"
mkdir -p "$(dirname -- "$OUT_PATH")"

sh "$ROOT_DIR/scripts/gpu_terrain_transparent_fixture_plan.sh" \
  "$CONTRACT_PATH" \
  "$PLAN_PATH" >/dev/null
sh "$ROOT_DIR/scripts/gpu_terrain_transparent_fixture_harness.sh" \
  "$PLAN_PATH" \
  "$HARNESS_PATH" >/dev/null
sh "$ROOT_DIR/scripts/gpu_terrain_transparent_fixture_check.sh" \
  "$PLAN_PATH" \
  "$HARNESS_PATH" \
  "$CHECK_PATH" >/dev/null

plan_summary_line="$(required_line "$PLAN_PATH" "summary fixture_plan_status=")"
harness_summary_line="$(required_line "$HARNESS_PATH" "summary transparent_fixture_harness_status=")"
check_summary_line="$(required_line "$CHECK_PATH" "summary transparent_fixture_check_status=")"

plan_status="$(required_token "fixture_plan_status" "$plan_summary_line" "plan summary")"
contract_tokens="$(required_token "contract_tokens" "$plan_summary_line" "plan summary")"
harness_status="$(required_token "transparent_fixture_harness_status" "$harness_summary_line" "harness summary")"
harness_env_expected="$(required_token "env_on_expected" "$harness_summary_line" "harness summary")"
harness_overlay_env_expected="$(required_token "overlay_env_on_expected" "$harness_summary_line" "harness summary")"
harness_overlay_metadata_expected="$(required_token "overlay_metadata_expected" "$harness_summary_line" "harness summary")"
check_status="$(required_token "transparent_fixture_check_status" "$check_summary_line" "check summary")"
check_plan_status="$(required_token "fixture_plan_status" "$check_summary_line" "check summary")"
check_harness_status="$(required_token "transparent_fixture_harness_status" "$check_summary_line" "check summary")"
check_env_expected="$(required_token "env_on_expected" "$check_summary_line" "check summary")"
check_overlay_env_expected="$(required_token "overlay_env_on_expected" "$check_summary_line" "check summary")"
check_overlay_metadata_expected="$(required_token "overlay_metadata_expected" "$check_summary_line" "check summary")"

test "$plan_status" = "contract_ready" || fail "unexpected fixture_plan_status=$plan_status"
test "$harness_status" = "contract_ready" || fail "unexpected transparent_fixture_harness_status=$harness_status"
test "$check_status" = "pass" || fail "unexpected transparent_fixture_check_status=$check_status"
test "$check_plan_status" = "$plan_status" || fail "check fixture_plan_status does not match plan"
test "$check_harness_status" = "$harness_status" || fail "check harness status does not match harness"
test "$check_env_expected" = "$harness_env_expected" || fail "check env_on_expected does not match harness"
test "$check_overlay_env_expected" = "$harness_overlay_env_expected" || fail "check overlay_env_on_expected does not match harness"
test "$check_overlay_metadata_expected" = "$harness_overlay_metadata_expected" || fail "check overlay_metadata_expected does not match harness"
test "$harness_env_expected" = "1/0/1" || fail "unexpected env_on_expected=$harness_env_expected"
test "$harness_overlay_env_expected" = "1/0/1" || fail "unexpected overlay_env_on_expected=$harness_overlay_env_expected"
test "$harness_overlay_metadata_expected" = "5/5" || fail "unexpected overlay_metadata_expected=$harness_overlay_metadata_expected"
case "$contract_tokens" in
  ''|*[!0-9]*) fail "contract_tokens must be numeric: $contract_tokens" ;;
esac
test "$contract_tokens" -ge 26 || fail "contract_tokens too low: $contract_tokens"

tmp_pack="$OUT_PATH.tmp"
tmp_smoke="$SMOKE_PLAN_PATH.tmp"
trap 'rm -f "$tmp_pack" "$tmp_smoke"' EXIT
{
  printf 'GPU terrain transparent fixture smoke plan\n'
  printf 'pack=%s\n' "$(relative_path "$OUT_PATH")"
  printf 'plan=%s\n' "$(relative_path "$PLAN_PATH")"
  printf 'harness=%s\n' "$(relative_path "$HARNESS_PATH")"
  printf 'check=%s\n' "$(relative_path "$CHECK_PATH")"
  printf 'report_check=%s\n' "$(relative_path "$REPORT_CHECK_PATH")"
  printf 'fixture=gpu-transparent-depth-collision\n'
  printf 'material=transparent_test_glass\n'
  printf 'smoke_plan_status=contract_ready\n'
  printf 'runtime_behavior=unchanged\n'
  printf 'ordinary_world_visibility=absent\n'
  printf 'pack_status=pass\n'
  printf 'env_on_expected=%s\n' "$harness_env_expected"
  printf 'overlay_env_on_expected=%s\n' "$harness_overlay_env_expected"
  printf 'overlay_metadata_expected=%s\n' "$harness_overlay_metadata_expected"
  printf 'step=env_off_current status=required expected=ordinary_opaque_markers_unchanged command="sh scripts/gpu_terrain_movement_stress.sh logs/gpu_transparent_fixture_env_off_capture"\n'
  printf 'step=env_on_fallback_current status=required transparent_requested=1 transparent_active=0 transparent_fallback=1 transparent_fixture_overlay_requested=1 transparent_fixture_overlay_active=0 transparent_fixture_overlay_fallback=1 transparent_blocks=0 transparent_faces=0 transparent_draws=0 transparent_subchunks=0 gpu_upload_fail=0 smoke_err=0 terrain_samples=nonzero command="RUMPELMC_GPU_TERRAIN_TRANSPARENT=1 RUMPELMC_GPU_TERRAIN_TRANSPARENT_FIXTURE_OVERLAY=1 sh scripts/gpu_terrain_movement_stress.sh logs/gpu_transparent_fixture_fallback_capture"\n'
  printf 'step=client_overlay_metadata status=required overlay_id=transparent_test_glass transparent_fixture_overlay_roles=5 transparent_fixture_overlay_blocks=5 geometry_active=0 chunk_data_mutation=no\n'
  printf 'step=future_fixture_scene status=required fixed_camera=required fixed_light=required depth_occluder=required adjacent_same_material_pair=required collision_probe=required\n'
  printf 'step=future_workload_markers status=blocked_until_fixture transparent_blocks=blocked_until_fixture transparent_faces=blocked_until_fixture transparent_draws=blocked_until_fixture transparent_subchunks=blocked_until_fixture\n'
  printf 'step=future_active_gate status=blocked_until_implementation transparent_active=1 transparent_fallback=0 gpu_upload_fail=0 opaque_depth_occlusion=required collision_solidity=required opaque_adjacent_faces_visible=required\n'
  printf 'step=non_goals status=enforced shader_alpha=no transparent_pass=no sorting=no block_id=no asset=no protocol=no storage=no worldgen=no\n'
  printf 'summary transparent_fixture_smoke_plan_status=contract_ready transparent_fixture_pack_status=pass fixture_plan_status=%s transparent_fixture_harness_status=%s env_on_expected=%s overlay_env_on_expected=%s overlay_metadata_expected=%s\n' \
    "$plan_status" \
    "$harness_status" \
    "$harness_env_expected" \
    "$harness_overlay_env_expected" \
    "$harness_overlay_metadata_expected"
} > "$tmp_smoke"
mv "$tmp_smoke" "$SMOKE_PLAN_PATH"

sh "$ROOT_DIR/scripts/gpu_terrain_transparent_fixture_scene_checklist.sh" \
  "$SMOKE_PLAN_PATH" \
  "$SCENE_CHECKLIST_PATH" >/dev/null
sh "$ROOT_DIR/scripts/gpu_terrain_transparent_fixture_scene_harness.sh" \
  "$SCENE_CHECKLIST_PATH" \
  "$SCENE_HARNESS_PATH" >/dev/null
sh "$ROOT_DIR/scripts/gpu_terrain_transparent_fixture_scene_harness_check.sh" \
  "$SCENE_CHECKLIST_PATH" \
  "$SCENE_HARNESS_PATH" \
  "$SCENE_HARNESS_CHECK_PATH" >/dev/null

scene_harness_check_summary_line="$(required_line "$SCENE_HARNESS_CHECK_PATH" "summary transparent_fixture_scene_harness_check_status=")"
scene_harness_check_status="$(required_token "transparent_fixture_scene_harness_check_status" "$scene_harness_check_summary_line" "scene harness-check summary")"
scene_harness_check_harness_status="$(required_token "transparent_fixture_scene_harness_status" "$scene_harness_check_summary_line" "scene harness-check summary")"
scene_harness_check_scene_status="$(required_token "transparent_fixture_scene_checklist_status" "$scene_harness_check_summary_line" "scene harness-check summary")"
scene_harness_check_roles="$(required_token "roles" "$scene_harness_check_summary_line" "scene harness-check summary")"
scene_harness_check_env_expected="$(required_token "env_on_expected" "$scene_harness_check_summary_line" "scene harness-check summary")"
scene_harness_check_overlay_env_expected="$(required_token "overlay_env_on_expected" "$scene_harness_check_summary_line" "scene harness-check summary")"
scene_harness_check_overlay_metadata_expected="$(required_token "overlay_metadata_expected" "$scene_harness_check_summary_line" "scene harness-check summary")"
scene_harness_check_overlay_roles="$(required_token "transparent_fixture_overlay_roles" "$scene_harness_check_summary_line" "scene harness-check summary")"
scene_harness_check_overlay_blocks="$(required_token "transparent_fixture_overlay_blocks" "$scene_harness_check_summary_line" "scene harness-check summary")"

test "$scene_harness_check_status" = "pass" || fail "unexpected transparent_fixture_scene_harness_check_status=$scene_harness_check_status"
test "$scene_harness_check_harness_status" = "contract_ready" || fail "unexpected scene harness status=$scene_harness_check_harness_status"
test "$scene_harness_check_scene_status" = "contract_ready" || fail "unexpected scene checklist status=$scene_harness_check_scene_status"
test "$scene_harness_check_roles" = "5" || fail "unexpected scene roles=$scene_harness_check_roles"
test "$scene_harness_check_env_expected" = "$harness_env_expected" || fail "scene env_on_expected does not match harness"
test "$scene_harness_check_overlay_env_expected" = "$harness_overlay_env_expected" || fail "scene overlay_env_on_expected does not match harness"
test "$scene_harness_check_overlay_metadata_expected" = "$harness_overlay_metadata_expected" || fail "scene overlay_metadata_expected does not match harness"
test "$scene_harness_check_overlay_roles" = "5" || fail "unexpected scene overlay roles=$scene_harness_check_overlay_roles"
test "$scene_harness_check_overlay_blocks" = "5" || fail "unexpected scene overlay blocks=$scene_harness_check_overlay_blocks"

sh "$ROOT_DIR/scripts/gpu_terrain_report.sh" \
  "$LOG_DIR" \
  "$REPORT_PATH" >/dev/null
sh "$ROOT_DIR/scripts/gpu_terrain_transparent_fixture_report_check.sh" \
  "$REPORT_PATH" \
  "$PACK_DIR" \
  "$REPORT_CHECK_PATH" >/dev/null

report_check_summary_line="$(required_line "$REPORT_CHECK_PATH" "summary transparent_fixture_report_check_status=")"
report_check_status="$(required_token "transparent_fixture_report_check_status" "$report_check_summary_line" "report-check summary")"
report_check_check_status="$(required_token "transparent_fixture_check_status" "$report_check_summary_line" "report-check summary")"
report_check_plan_status="$(required_token "fixture_plan_status" "$report_check_summary_line" "report-check summary")"
report_check_harness_status="$(required_token "transparent_fixture_harness_status" "$report_check_summary_line" "report-check summary")"
report_check_scene_harness_check_status="$(required_token "transparent_fixture_scene_harness_check_status" "$report_check_summary_line" "report-check summary")"
report_check_env_expected="$(required_token "env_on_expected" "$report_check_summary_line" "report-check summary")"
report_check_overlay_env_expected="$(required_token "overlay_env_on_expected" "$report_check_summary_line" "report-check summary")"
report_check_overlay_metadata_expected="$(required_token "overlay_metadata_expected" "$report_check_summary_line" "report-check summary")"

test "$report_check_status" = "pass" || fail "unexpected transparent_fixture_report_check_status=$report_check_status"
test "$report_check_check_status" = "$check_status" || fail "report-check status does not match check"
test "$report_check_plan_status" = "$plan_status" || fail "report-check fixture_plan_status does not match plan"
test "$report_check_harness_status" = "$harness_status" || fail "report-check harness status does not match harness"
test "$report_check_scene_harness_check_status" = "$scene_harness_check_status" || fail "report-check scene harness-check status does not match"
test "$report_check_env_expected" = "$harness_env_expected" || fail "report-check env_on_expected does not match harness"
test "$report_check_overlay_env_expected" = "$harness_overlay_env_expected" || fail "report-check overlay_env_on_expected does not match harness"
test "$report_check_overlay_metadata_expected" = "$harness_overlay_metadata_expected" || fail "report-check overlay_metadata_expected does not match harness"

{
  printf 'GPU terrain transparent fixture pack\n'
  printf 'pack_dir=%s\n' "$(relative_path "$PACK_DIR")"
  printf 'log_dir=%s\n' "$(relative_path "$LOG_DIR")"
  printf 'plan=%s\n' "$(relative_path "$PLAN_PATH")"
  printf 'harness=%s\n' "$(relative_path "$HARNESS_PATH")"
  printf 'check=%s\n' "$(relative_path "$CHECK_PATH")"
  printf 'smoke_plan=%s\n' "$(relative_path "$SMOKE_PLAN_PATH")"
  printf 'scene_checklist=%s\n' "$(relative_path "$SCENE_CHECKLIST_PATH")"
  printf 'scene_harness=%s\n' "$(relative_path "$SCENE_HARNESS_PATH")"
  printf 'scene_harness_check=%s\n' "$(relative_path "$SCENE_HARNESS_CHECK_PATH")"
  printf 'acceptance_check=%s\n' "$(relative_path "$ACCEPTANCE_CHECK_PATH")"
  printf 'report=%s\n' "$(relative_path "$REPORT_PATH")"
  printf 'report_check=%s\n' "$(relative_path "$REPORT_CHECK_PATH")"
  printf 'steps=plan/harness/check/report/report_check\n'
  printf 'scene_steps=smoke_plan/scene_checklist/scene_harness/scene_harness_check\n'
  printf 'fixture_plan_status=%s\n' "$plan_status"
  printf 'transparent_fixture_harness_status=%s\n' "$harness_status"
  printf 'transparent_fixture_check_status=%s\n' "$check_status"
  printf 'transparent_fixture_scene_harness_check_status=%s\n' "$scene_harness_check_status"
  printf 'transparent_fixture_report_check_status=%s\n' "$report_check_status"
  printf 'env_on_expected=%s\n' "$harness_env_expected"
  printf 'overlay_env_on_expected=%s\n' "$harness_overlay_env_expected"
  printf 'overlay_metadata_expected=%s\n' "$harness_overlay_metadata_expected"
  printf 'contract_tokens=%s\n' "$contract_tokens"
  printf 'runtime_behavior=unchanged\n'
  printf 'ordinary_world_visibility=absent\n'
  printf 'summary transparent_fixture_pack_status=pass transparent_fixture_report_check_status=%s transparent_fixture_check_status=%s transparent_fixture_scene_harness_check_status=%s fixture_plan_status=%s transparent_fixture_harness_status=%s env_on_expected=%s overlay_env_on_expected=%s overlay_metadata_expected=%s\n' \
    "$report_check_status" \
    "$check_status" \
    "$scene_harness_check_status" \
    "$plan_status" \
    "$harness_status" \
    "$harness_env_expected" \
    "$harness_overlay_env_expected" \
    "$harness_overlay_metadata_expected"
} > "$tmp_pack"

mv "$tmp_pack" "$OUT_PATH"

sh "$ROOT_DIR/scripts/gpu_terrain_transparent_fixture_acceptance_check.sh" \
  "$OUT_PATH" \
  "$ACCEPTANCE_CHECK_PATH" >/dev/null

acceptance_summary_line="$(required_line "$ACCEPTANCE_CHECK_PATH" "summary transparent_fixture_acceptance_status=")"
acceptance_status="$(required_token "transparent_fixture_acceptance_status" "$acceptance_summary_line" "acceptance-check summary")"
acceptance_pack_status="$(required_token "transparent_fixture_pack_status" "$acceptance_summary_line" "acceptance-check summary")"
acceptance_report_check_status="$(required_token "transparent_fixture_report_check_status" "$acceptance_summary_line" "acceptance-check summary")"
acceptance_check_status="$(required_token "transparent_fixture_check_status" "$acceptance_summary_line" "acceptance-check summary")"
acceptance_scene_harness_check_status="$(required_token "transparent_fixture_scene_harness_check_status" "$acceptance_summary_line" "acceptance-check summary")"
acceptance_plan_status="$(required_token "fixture_plan_status" "$acceptance_summary_line" "acceptance-check summary")"
acceptance_harness_status="$(required_token "transparent_fixture_harness_status" "$acceptance_summary_line" "acceptance-check summary")"
acceptance_env_expected="$(required_token "env_on_expected" "$acceptance_summary_line" "acceptance-check summary")"
acceptance_overlay_env_expected="$(required_token "overlay_env_on_expected" "$acceptance_summary_line" "acceptance-check summary")"
acceptance_overlay_metadata_expected="$(required_token "overlay_metadata_expected" "$acceptance_summary_line" "acceptance-check summary")"

test "$acceptance_status" = "pass" || fail "unexpected transparent_fixture_acceptance_status=$acceptance_status"
test "$acceptance_pack_status" = "pass" || fail "unexpected acceptance pack status=$acceptance_pack_status"
test "$acceptance_report_check_status" = "$report_check_status" || fail "acceptance report-check status does not match"
test "$acceptance_check_status" = "$check_status" || fail "acceptance check status does not match"
test "$acceptance_scene_harness_check_status" = "$scene_harness_check_status" || fail "acceptance scene harness-check status does not match"
test "$acceptance_plan_status" = "$plan_status" || fail "acceptance fixture_plan_status does not match plan"
test "$acceptance_harness_status" = "$harness_status" || fail "acceptance harness status does not match harness"
test "$acceptance_env_expected" = "$harness_env_expected" || fail "acceptance env_on_expected does not match harness"
test "$acceptance_overlay_env_expected" = "$harness_overlay_env_expected" || fail "acceptance overlay_env_on_expected does not match harness"
test "$acceptance_overlay_metadata_expected" = "$harness_overlay_metadata_expected" || fail "acceptance overlay_metadata_expected does not match harness"

sh "$ROOT_DIR/scripts/gpu_terrain_report.sh" \
  "$LOG_DIR" \
  "$REPORT_PATH" >/dev/null
required_line "$REPORT_PATH" "## Selected Transparent Fixture Acceptance Check" >/dev/null
required_line "$REPORT_PATH" "Source: \`$ACCEPTANCE_CHECK_PATH\`" >/dev/null

{
  printf 'GPU terrain transparent fixture pack\n'
  printf 'pack_dir=%s\n' "$(relative_path "$PACK_DIR")"
  printf 'log_dir=%s\n' "$(relative_path "$LOG_DIR")"
  printf 'plan=%s\n' "$(relative_path "$PLAN_PATH")"
  printf 'harness=%s\n' "$(relative_path "$HARNESS_PATH")"
  printf 'check=%s\n' "$(relative_path "$CHECK_PATH")"
  printf 'smoke_plan=%s\n' "$(relative_path "$SMOKE_PLAN_PATH")"
  printf 'scene_checklist=%s\n' "$(relative_path "$SCENE_CHECKLIST_PATH")"
  printf 'scene_harness=%s\n' "$(relative_path "$SCENE_HARNESS_PATH")"
  printf 'scene_harness_check=%s\n' "$(relative_path "$SCENE_HARNESS_CHECK_PATH")"
  printf 'acceptance_check=%s\n' "$(relative_path "$ACCEPTANCE_CHECK_PATH")"
  printf 'report=%s\n' "$(relative_path "$REPORT_PATH")"
  printf 'report_check=%s\n' "$(relative_path "$REPORT_CHECK_PATH")"
  printf 'steps=plan/harness/check/report/report_check\n'
  printf 'scene_steps=smoke_plan/scene_checklist/scene_harness/scene_harness_check\n'
  printf 'acceptance_steps=acceptance_check/report_refresh\n'
  printf 'fixture_plan_status=%s\n' "$plan_status"
  printf 'transparent_fixture_harness_status=%s\n' "$harness_status"
  printf 'transparent_fixture_check_status=%s\n' "$check_status"
  printf 'transparent_fixture_scene_harness_check_status=%s\n' "$scene_harness_check_status"
  printf 'transparent_fixture_acceptance_status=%s\n' "$acceptance_status"
  printf 'transparent_fixture_report_check_status=%s\n' "$report_check_status"
  printf 'env_on_expected=%s\n' "$harness_env_expected"
  printf 'overlay_env_on_expected=%s\n' "$harness_overlay_env_expected"
  printf 'overlay_metadata_expected=%s\n' "$harness_overlay_metadata_expected"
  printf 'contract_tokens=%s\n' "$contract_tokens"
  printf 'runtime_behavior=unchanged\n'
  printf 'ordinary_world_visibility=absent\n'
  printf 'summary transparent_fixture_pack_status=pass transparent_fixture_acceptance_status=%s transparent_fixture_report_check_status=%s transparent_fixture_check_status=%s transparent_fixture_scene_harness_check_status=%s fixture_plan_status=%s transparent_fixture_harness_status=%s env_on_expected=%s overlay_env_on_expected=%s overlay_metadata_expected=%s\n' \
    "$acceptance_status" \
    "$report_check_status" \
    "$check_status" \
    "$scene_harness_check_status" \
    "$plan_status" \
    "$harness_status" \
    "$harness_env_expected" \
    "$harness_overlay_env_expected" \
    "$harness_overlay_metadata_expected"
} > "$tmp_pack"
mv "$tmp_pack" "$OUT_PATH"

sh "$ROOT_DIR/scripts/gpu_terrain_transparent_fixture_default_off_check.sh" \
  "$OUT_PATH" \
  "$DEFAULT_OFF_CHECK_PATH" >/dev/null

default_off_summary_line="$(required_line "$DEFAULT_OFF_CHECK_PATH" "summary transparent_fixture_default_off_status=")"
default_off_status="$(required_token "transparent_fixture_default_off_status" "$default_off_summary_line" "default-off check summary")"
default_off_acceptance_status="$(required_token "transparent_fixture_acceptance_status" "$default_off_summary_line" "default-off check summary")"
default_off_gate="$(required_token "transparent_implementation_gate" "$default_off_summary_line" "default-off check summary")"
default_off_env_expected="$(required_token "env_on_expected" "$default_off_summary_line" "default-off check summary")"
default_off_overlay_env_expected="$(required_token "overlay_env_on_expected" "$default_off_summary_line" "default-off check summary")"
default_off_overlay_metadata_expected="$(required_token "overlay_metadata_expected" "$default_off_summary_line" "default-off check summary")"
default_off_future_active="$(required_token "future_active_expected" "$default_off_summary_line" "default-off check summary")"

test "$default_off_status" = "pass" || fail "unexpected transparent_fixture_default_off_status=$default_off_status"
test "$default_off_acceptance_status" = "$acceptance_status" || fail "default-off acceptance status does not match"
test "$default_off_gate" = "false" || fail "unexpected default-off implementation gate=$default_off_gate"
test "$default_off_env_expected" = "$harness_env_expected" || fail "default-off env_on_expected does not match harness"
test "$default_off_overlay_env_expected" = "$harness_overlay_env_expected" || fail "default-off overlay_env_on_expected does not match harness"
test "$default_off_overlay_metadata_expected" = "$harness_overlay_metadata_expected" || fail "default-off overlay_metadata_expected does not match harness"
test "$default_off_future_active" = "1/0/0" || fail "unexpected default-off future active triplet=$default_off_future_active"

sh "$ROOT_DIR/scripts/gpu_terrain_report.sh" \
  "$LOG_DIR" \
  "$REPORT_PATH" >/dev/null
required_line "$REPORT_PATH" "## Selected Transparent Fixture Default-Off Check" >/dev/null
required_line "$REPORT_PATH" "Source: \`$DEFAULT_OFF_CHECK_PATH\`" >/dev/null

{
  printf 'GPU terrain transparent fixture pack\n'
  printf 'pack_dir=%s\n' "$(relative_path "$PACK_DIR")"
  printf 'log_dir=%s\n' "$(relative_path "$LOG_DIR")"
  printf 'plan=%s\n' "$(relative_path "$PLAN_PATH")"
  printf 'harness=%s\n' "$(relative_path "$HARNESS_PATH")"
  printf 'check=%s\n' "$(relative_path "$CHECK_PATH")"
  printf 'smoke_plan=%s\n' "$(relative_path "$SMOKE_PLAN_PATH")"
  printf 'scene_checklist=%s\n' "$(relative_path "$SCENE_CHECKLIST_PATH")"
  printf 'scene_harness=%s\n' "$(relative_path "$SCENE_HARNESS_PATH")"
  printf 'scene_harness_check=%s\n' "$(relative_path "$SCENE_HARNESS_CHECK_PATH")"
  printf 'acceptance_check=%s\n' "$(relative_path "$ACCEPTANCE_CHECK_PATH")"
  printf 'default_off_check=%s\n' "$(relative_path "$DEFAULT_OFF_CHECK_PATH")"
  printf 'report=%s\n' "$(relative_path "$REPORT_PATH")"
  printf 'report_check=%s\n' "$(relative_path "$REPORT_CHECK_PATH")"
  printf 'final_report_check=%s\n' "$(relative_path "$FINAL_REPORT_CHECK_PATH")"
  printf 'steps=plan/harness/check/report/report_check\n'
  printf 'scene_steps=smoke_plan/scene_checklist/scene_harness/scene_harness_check\n'
  printf 'acceptance_steps=acceptance_check/report_refresh\n'
  printf 'default_off_steps=default_off_check/report_refresh\n'
  printf 'fixture_plan_status=%s\n' "$plan_status"
  printf 'transparent_fixture_harness_status=%s\n' "$harness_status"
  printf 'transparent_fixture_check_status=%s\n' "$check_status"
  printf 'transparent_fixture_scene_harness_check_status=%s\n' "$scene_harness_check_status"
  printf 'transparent_fixture_acceptance_status=%s\n' "$acceptance_status"
  printf 'transparent_fixture_default_off_status=%s\n' "$default_off_status"
  printf 'transparent_fixture_report_check_status=%s\n' "$report_check_status"
  printf 'env_on_expected=%s\n' "$harness_env_expected"
  printf 'overlay_env_on_expected=%s\n' "$harness_overlay_env_expected"
  printf 'overlay_metadata_expected=%s\n' "$harness_overlay_metadata_expected"
  printf 'contract_tokens=%s\n' "$contract_tokens"
  printf 'runtime_behavior=unchanged\n'
  printf 'ordinary_world_visibility=absent\n'
  printf 'summary transparent_fixture_pack_status=pass transparent_fixture_acceptance_status=%s transparent_fixture_default_off_status=%s transparent_fixture_report_check_status=%s transparent_fixture_check_status=%s transparent_fixture_scene_harness_check_status=%s fixture_plan_status=%s transparent_fixture_harness_status=%s env_on_expected=%s overlay_env_on_expected=%s overlay_metadata_expected=%s\n' \
    "$acceptance_status" \
    "$default_off_status" \
    "$report_check_status" \
    "$check_status" \
    "$scene_harness_check_status" \
    "$plan_status" \
    "$harness_status" \
    "$harness_env_expected" \
    "$harness_overlay_env_expected" \
    "$harness_overlay_metadata_expected"
} > "$tmp_pack"

mv "$tmp_pack" "$OUT_PATH"

sh "$ROOT_DIR/scripts/gpu_terrain_transparent_fixture_final_report_check.sh" \
  "$OUT_PATH" \
  "$FINAL_REPORT_CHECK_PATH" >/dev/null

final_report_summary_line="$(required_line "$FINAL_REPORT_CHECK_PATH" "summary transparent_fixture_final_report_check_status=")"
final_report_status="$(required_token "transparent_fixture_final_report_check_status" "$final_report_summary_line" "final-report check summary")"
final_report_pack_status="$(required_token "transparent_fixture_pack_status" "$final_report_summary_line" "final-report check summary")"
final_report_acceptance_status="$(required_token "transparent_fixture_acceptance_status" "$final_report_summary_line" "final-report check summary")"
final_report_default_off_status="$(required_token "transparent_fixture_default_off_status" "$final_report_summary_line" "final-report check summary")"
final_report_env_expected="$(required_token "env_on_expected" "$final_report_summary_line" "final-report check summary")"
final_report_overlay_env_expected="$(required_token "overlay_env_on_expected" "$final_report_summary_line" "final-report check summary")"
final_report_overlay_metadata_expected="$(required_token "overlay_metadata_expected" "$final_report_summary_line" "final-report check summary")"

test "$final_report_status" = "pass" || fail "unexpected transparent_fixture_final_report_check_status=$final_report_status"
test "$final_report_pack_status" = "pass" || fail "final-report pack status does not match"
test "$final_report_acceptance_status" = "$acceptance_status" || fail "final-report acceptance status does not match"
test "$final_report_default_off_status" = "$default_off_status" || fail "final-report default-off status does not match"
test "$final_report_env_expected" = "$harness_env_expected" || fail "final-report env_on_expected does not match harness"
test "$final_report_overlay_env_expected" = "$harness_overlay_env_expected" || fail "final-report overlay_env_on_expected does not match harness"
test "$final_report_overlay_metadata_expected" = "$harness_overlay_metadata_expected" || fail "final-report overlay_metadata_expected does not match harness"

sh "$ROOT_DIR/scripts/gpu_terrain_report.sh" \
  "$LOG_DIR" \
  "$REPORT_PATH" >/dev/null
required_line "$REPORT_PATH" "## Selected Transparent Fixture Final Report Check" >/dev/null
required_line "$REPORT_PATH" "Source: \`$FINAL_REPORT_CHECK_PATH\`" >/dev/null

{
  printf 'GPU terrain transparent fixture pack\n'
  printf 'pack_dir=%s\n' "$(relative_path "$PACK_DIR")"
  printf 'log_dir=%s\n' "$(relative_path "$LOG_DIR")"
  printf 'plan=%s\n' "$(relative_path "$PLAN_PATH")"
  printf 'harness=%s\n' "$(relative_path "$HARNESS_PATH")"
  printf 'check=%s\n' "$(relative_path "$CHECK_PATH")"
  printf 'smoke_plan=%s\n' "$(relative_path "$SMOKE_PLAN_PATH")"
  printf 'scene_checklist=%s\n' "$(relative_path "$SCENE_CHECKLIST_PATH")"
  printf 'scene_harness=%s\n' "$(relative_path "$SCENE_HARNESS_PATH")"
  printf 'scene_harness_check=%s\n' "$(relative_path "$SCENE_HARNESS_CHECK_PATH")"
  printf 'acceptance_check=%s\n' "$(relative_path "$ACCEPTANCE_CHECK_PATH")"
  printf 'default_off_check=%s\n' "$(relative_path "$DEFAULT_OFF_CHECK_PATH")"
  printf 'report=%s\n' "$(relative_path "$REPORT_PATH")"
  printf 'report_check=%s\n' "$(relative_path "$REPORT_CHECK_PATH")"
  printf 'final_report_check=%s\n' "$(relative_path "$FINAL_REPORT_CHECK_PATH")"
  printf 'steps=plan/harness/check/report/report_check\n'
  printf 'scene_steps=smoke_plan/scene_checklist/scene_harness/scene_harness_check\n'
  printf 'acceptance_steps=acceptance_check/report_refresh\n'
  printf 'default_off_steps=default_off_check/report_refresh\n'
  printf 'final_report_steps=final_report_check/report_refresh\n'
  printf 'fixture_plan_status=%s\n' "$plan_status"
  printf 'transparent_fixture_harness_status=%s\n' "$harness_status"
  printf 'transparent_fixture_check_status=%s\n' "$check_status"
  printf 'transparent_fixture_scene_harness_check_status=%s\n' "$scene_harness_check_status"
  printf 'transparent_fixture_acceptance_status=%s\n' "$acceptance_status"
  printf 'transparent_fixture_default_off_status=%s\n' "$default_off_status"
  printf 'transparent_fixture_final_report_check_status=%s\n' "$final_report_status"
  printf 'transparent_fixture_report_check_status=%s\n' "$report_check_status"
  printf 'env_on_expected=%s\n' "$harness_env_expected"
  printf 'overlay_env_on_expected=%s\n' "$harness_overlay_env_expected"
  printf 'overlay_metadata_expected=%s\n' "$harness_overlay_metadata_expected"
  printf 'contract_tokens=%s\n' "$contract_tokens"
  printf 'runtime_behavior=unchanged\n'
  printf 'ordinary_world_visibility=absent\n'
  printf 'summary transparent_fixture_pack_status=pass transparent_fixture_acceptance_status=%s transparent_fixture_default_off_status=%s transparent_fixture_final_report_check_status=%s transparent_fixture_report_check_status=%s transparent_fixture_check_status=%s transparent_fixture_scene_harness_check_status=%s fixture_plan_status=%s transparent_fixture_harness_status=%s env_on_expected=%s overlay_env_on_expected=%s overlay_metadata_expected=%s\n' \
    "$acceptance_status" \
    "$default_off_status" \
    "$final_report_status" \
    "$report_check_status" \
    "$check_status" \
    "$scene_harness_check_status" \
    "$plan_status" \
    "$harness_status" \
    "$harness_env_expected" \
    "$harness_overlay_env_expected" \
    "$harness_overlay_metadata_expected"
} > "$tmp_pack"

mv "$tmp_pack" "$OUT_PATH"

sh "$ROOT_DIR/scripts/gpu_terrain_transparent_fixture_final_report_check.sh" \
  "$OUT_PATH" \
  "$FINAL_REPORT_CHECK_PATH" >/dev/null

sh "$ROOT_DIR/scripts/gpu_terrain_transparent_fixture_scene_implementation_checklist.sh" \
  "$OUT_PATH" \
  "$SCENE_IMPLEMENTATION_CHECKLIST_PATH" >/dev/null

scene_implementation_summary_line="$(required_line "$SCENE_IMPLEMENTATION_CHECKLIST_PATH" "summary transparent_fixture_scene_implementation_checklist_status=")"
scene_implementation_status="$(required_token "transparent_fixture_scene_implementation_checklist_status" "$scene_implementation_summary_line" "scene implementation checklist summary")"
scene_implementation_pack_status="$(required_token "transparent_fixture_pack_status" "$scene_implementation_summary_line" "scene implementation checklist summary")"
scene_implementation_final_report_status="$(required_token "transparent_fixture_final_report_check_status" "$scene_implementation_summary_line" "scene implementation checklist summary")"
scene_implementation_default_off_status="$(required_token "transparent_fixture_default_off_status" "$scene_implementation_summary_line" "scene implementation checklist summary")"
scene_implementation_gate="$(required_token "transparent_implementation_gate" "$scene_implementation_summary_line" "scene implementation checklist summary")"
scene_implementation_env_expected="$(required_token "env_on_expected" "$scene_implementation_summary_line" "scene implementation checklist summary")"
scene_implementation_overlay_env_expected="$(required_token "overlay_env_on_expected" "$scene_implementation_summary_line" "scene implementation checklist summary")"
scene_implementation_overlay_metadata_expected="$(required_token "overlay_metadata_expected" "$scene_implementation_summary_line" "scene implementation checklist summary")"
scene_implementation_future_active="$(required_token "future_active_expected" "$scene_implementation_summary_line" "scene implementation checklist summary")"

test "$scene_implementation_status" = "implementation_contract_ready" || fail "unexpected transparent_fixture_scene_implementation_checklist_status=$scene_implementation_status"
test "$scene_implementation_pack_status" = "pass" || fail "scene implementation pack status does not match"
test "$scene_implementation_final_report_status" = "$final_report_status" || fail "scene implementation final-report status does not match"
test "$scene_implementation_default_off_status" = "$default_off_status" || fail "scene implementation default-off status does not match"
test "$scene_implementation_gate" = "false" || fail "unexpected scene implementation gate=$scene_implementation_gate"
test "$scene_implementation_env_expected" = "$harness_env_expected" || fail "scene implementation env_on_expected does not match harness"
test "$scene_implementation_overlay_env_expected" = "$harness_overlay_env_expected" || fail "scene implementation overlay_env_on_expected does not match harness"
test "$scene_implementation_overlay_metadata_expected" = "$harness_overlay_metadata_expected" || fail "scene implementation overlay_metadata_expected does not match harness"
test "$scene_implementation_future_active" = "1/0/0" || fail "unexpected scene implementation future active triplet=$scene_implementation_future_active"

sh "$ROOT_DIR/scripts/gpu_terrain_report.sh" \
  "$LOG_DIR" \
  "$REPORT_PATH" >/dev/null
required_line "$REPORT_PATH" "## Selected Transparent Fixture Final Report Check" >/dev/null
required_line "$REPORT_PATH" "Source: \`$FINAL_REPORT_CHECK_PATH\`" >/dev/null
required_line "$REPORT_PATH" "## Selected Transparent Fixture Scene Implementation Checklist" >/dev/null
required_line "$REPORT_PATH" "Source: \`$SCENE_IMPLEMENTATION_CHECKLIST_PATH\`" >/dev/null

{
  printf 'GPU terrain transparent fixture pack\n'
  printf 'pack_dir=%s\n' "$(relative_path "$PACK_DIR")"
  printf 'log_dir=%s\n' "$(relative_path "$LOG_DIR")"
  printf 'plan=%s\n' "$(relative_path "$PLAN_PATH")"
  printf 'harness=%s\n' "$(relative_path "$HARNESS_PATH")"
  printf 'check=%s\n' "$(relative_path "$CHECK_PATH")"
  printf 'smoke_plan=%s\n' "$(relative_path "$SMOKE_PLAN_PATH")"
  printf 'scene_checklist=%s\n' "$(relative_path "$SCENE_CHECKLIST_PATH")"
  printf 'scene_harness=%s\n' "$(relative_path "$SCENE_HARNESS_PATH")"
  printf 'scene_harness_check=%s\n' "$(relative_path "$SCENE_HARNESS_CHECK_PATH")"
  printf 'acceptance_check=%s\n' "$(relative_path "$ACCEPTANCE_CHECK_PATH")"
  printf 'default_off_check=%s\n' "$(relative_path "$DEFAULT_OFF_CHECK_PATH")"
  printf 'report=%s\n' "$(relative_path "$REPORT_PATH")"
  printf 'report_check=%s\n' "$(relative_path "$REPORT_CHECK_PATH")"
  printf 'final_report_check=%s\n' "$(relative_path "$FINAL_REPORT_CHECK_PATH")"
  printf 'scene_implementation_checklist=%s\n' "$(relative_path "$SCENE_IMPLEMENTATION_CHECKLIST_PATH")"
  printf 'steps=plan/harness/check/report/report_check\n'
  printf 'scene_steps=smoke_plan/scene_checklist/scene_harness/scene_harness_check\n'
  printf 'acceptance_steps=acceptance_check/report_refresh\n'
  printf 'default_off_steps=default_off_check/report_refresh\n'
  printf 'final_report_steps=final_report_check/report_refresh\n'
  printf 'scene_implementation_steps=scene_implementation_checklist/report_refresh\n'
  printf 'fixture_plan_status=%s\n' "$plan_status"
  printf 'transparent_fixture_harness_status=%s\n' "$harness_status"
  printf 'transparent_fixture_check_status=%s\n' "$check_status"
  printf 'transparent_fixture_scene_harness_check_status=%s\n' "$scene_harness_check_status"
  printf 'transparent_fixture_acceptance_status=%s\n' "$acceptance_status"
  printf 'transparent_fixture_default_off_status=%s\n' "$default_off_status"
  printf 'transparent_fixture_final_report_check_status=%s\n' "$final_report_status"
  printf 'transparent_fixture_scene_implementation_checklist_status=%s\n' "$scene_implementation_status"
  printf 'transparent_fixture_report_check_status=%s\n' "$report_check_status"
  printf 'env_on_expected=%s\n' "$harness_env_expected"
  printf 'overlay_env_on_expected=%s\n' "$harness_overlay_env_expected"
  printf 'overlay_metadata_expected=%s\n' "$harness_overlay_metadata_expected"
  printf 'contract_tokens=%s\n' "$contract_tokens"
  printf 'runtime_behavior=unchanged\n'
  printf 'ordinary_world_visibility=absent\n'
  printf 'summary transparent_fixture_pack_status=pass transparent_fixture_acceptance_status=%s transparent_fixture_default_off_status=%s transparent_fixture_final_report_check_status=%s transparent_fixture_scene_implementation_checklist_status=%s transparent_fixture_report_check_status=%s transparent_fixture_check_status=%s transparent_fixture_scene_harness_check_status=%s fixture_plan_status=%s transparent_fixture_harness_status=%s env_on_expected=%s overlay_env_on_expected=%s overlay_metadata_expected=%s\n' \
    "$acceptance_status" \
    "$default_off_status" \
    "$final_report_status" \
    "$scene_implementation_status" \
    "$report_check_status" \
    "$check_status" \
    "$scene_harness_check_status" \
    "$plan_status" \
    "$harness_status" \
    "$harness_env_expected" \
    "$harness_overlay_env_expected" \
    "$harness_overlay_metadata_expected"
} > "$tmp_pack"

mv "$tmp_pack" "$OUT_PATH"

sh "$ROOT_DIR/scripts/gpu_terrain_transparent_fixture_scene_implementation_checklist.sh" \
  "$OUT_PATH" \
  "$SCENE_IMPLEMENTATION_CHECKLIST_PATH" >/dev/null

sh "$ROOT_DIR/scripts/gpu_terrain_transparent_fixture_scene_implementation_gate_check.sh" \
  "$SCENE_IMPLEMENTATION_CHECKLIST_PATH" \
  "$SCENE_IMPLEMENTATION_GATE_CHECK_PATH" >/dev/null

scene_implementation_gate_summary_line="$(required_line "$SCENE_IMPLEMENTATION_GATE_CHECK_PATH" "summary transparent_fixture_scene_implementation_gate_check_status=")"
scene_implementation_gate_status="$(required_token "transparent_fixture_scene_implementation_gate_check_status" "$scene_implementation_gate_summary_line" "scene implementation gate-check summary")"
scene_implementation_gate_checklist_status="$(required_token "transparent_fixture_scene_implementation_checklist_status" "$scene_implementation_gate_summary_line" "scene implementation gate-check summary")"
scene_implementation_gate_pack_status="$(required_token "transparent_fixture_pack_status" "$scene_implementation_gate_summary_line" "scene implementation gate-check summary")"
scene_implementation_gate_flag="$(required_token "transparent_implementation_gate" "$scene_implementation_gate_summary_line" "scene implementation gate-check summary")"
scene_implementation_gate_env_expected="$(required_token "env_on_expected" "$scene_implementation_gate_summary_line" "scene implementation gate-check summary")"
scene_implementation_gate_overlay_env_expected="$(required_token "overlay_env_on_expected" "$scene_implementation_gate_summary_line" "scene implementation gate-check summary")"
scene_implementation_gate_overlay_metadata_expected="$(required_token "overlay_metadata_expected" "$scene_implementation_gate_summary_line" "scene implementation gate-check summary")"
scene_implementation_gate_future_active="$(required_token "future_active_expected" "$scene_implementation_gate_summary_line" "scene implementation gate-check summary")"

test "$scene_implementation_gate_status" = "pass" || fail "unexpected transparent_fixture_scene_implementation_gate_check_status=$scene_implementation_gate_status"
test "$scene_implementation_gate_checklist_status" = "$scene_implementation_status" || fail "scene implementation gate-check checklist status does not match"
test "$scene_implementation_gate_pack_status" = "pass" || fail "scene implementation gate-check pack status does not match"
test "$scene_implementation_gate_flag" = "false" || fail "unexpected scene implementation gate-check flag=$scene_implementation_gate_flag"
test "$scene_implementation_gate_env_expected" = "$harness_env_expected" || fail "scene implementation gate-check env_on_expected does not match harness"
test "$scene_implementation_gate_overlay_env_expected" = "$harness_overlay_env_expected" || fail "scene implementation gate-check overlay_env_on_expected does not match harness"
test "$scene_implementation_gate_overlay_metadata_expected" = "$harness_overlay_metadata_expected" || fail "scene implementation gate-check overlay_metadata_expected does not match harness"
test "$scene_implementation_gate_future_active" = "1/0/0" || fail "unexpected scene implementation gate-check future active triplet=$scene_implementation_gate_future_active"

sh "$ROOT_DIR/scripts/gpu_terrain_report.sh" \
  "$LOG_DIR" \
  "$REPORT_PATH" >/dev/null
required_line "$REPORT_PATH" "## Selected Transparent Fixture Scene Implementation Checklist" >/dev/null
required_line "$REPORT_PATH" "Source: \`$SCENE_IMPLEMENTATION_CHECKLIST_PATH\`" >/dev/null
required_line "$REPORT_PATH" "## Selected Transparent Fixture Scene Implementation Gate Check" >/dev/null
required_line "$REPORT_PATH" "Source: \`$SCENE_IMPLEMENTATION_GATE_CHECK_PATH\`" >/dev/null

{
  printf 'GPU terrain transparent fixture pack\n'
  printf 'pack_dir=%s\n' "$(relative_path "$PACK_DIR")"
  printf 'log_dir=%s\n' "$(relative_path "$LOG_DIR")"
  printf 'plan=%s\n' "$(relative_path "$PLAN_PATH")"
  printf 'harness=%s\n' "$(relative_path "$HARNESS_PATH")"
  printf 'check=%s\n' "$(relative_path "$CHECK_PATH")"
  printf 'smoke_plan=%s\n' "$(relative_path "$SMOKE_PLAN_PATH")"
  printf 'scene_checklist=%s\n' "$(relative_path "$SCENE_CHECKLIST_PATH")"
  printf 'scene_harness=%s\n' "$(relative_path "$SCENE_HARNESS_PATH")"
  printf 'scene_harness_check=%s\n' "$(relative_path "$SCENE_HARNESS_CHECK_PATH")"
  printf 'acceptance_check=%s\n' "$(relative_path "$ACCEPTANCE_CHECK_PATH")"
  printf 'default_off_check=%s\n' "$(relative_path "$DEFAULT_OFF_CHECK_PATH")"
  printf 'report=%s\n' "$(relative_path "$REPORT_PATH")"
  printf 'report_check=%s\n' "$(relative_path "$REPORT_CHECK_PATH")"
  printf 'final_report_check=%s\n' "$(relative_path "$FINAL_REPORT_CHECK_PATH")"
  printf 'scene_implementation_checklist=%s\n' "$(relative_path "$SCENE_IMPLEMENTATION_CHECKLIST_PATH")"
  printf 'scene_implementation_gate_check=%s\n' "$(relative_path "$SCENE_IMPLEMENTATION_GATE_CHECK_PATH")"
  printf 'steps=plan/harness/check/report/report_check\n'
  printf 'scene_steps=smoke_plan/scene_checklist/scene_harness/scene_harness_check\n'
  printf 'acceptance_steps=acceptance_check/report_refresh\n'
  printf 'default_off_steps=default_off_check/report_refresh\n'
  printf 'final_report_steps=final_report_check/report_refresh\n'
  printf 'scene_implementation_steps=scene_implementation_checklist/report_refresh\n'
  printf 'scene_implementation_gate_steps=scene_implementation_gate_check/report_refresh\n'
  printf 'fixture_plan_status=%s\n' "$plan_status"
  printf 'transparent_fixture_harness_status=%s\n' "$harness_status"
  printf 'transparent_fixture_check_status=%s\n' "$check_status"
  printf 'transparent_fixture_scene_harness_check_status=%s\n' "$scene_harness_check_status"
  printf 'transparent_fixture_acceptance_status=%s\n' "$acceptance_status"
  printf 'transparent_fixture_default_off_status=%s\n' "$default_off_status"
  printf 'transparent_fixture_final_report_check_status=%s\n' "$final_report_status"
  printf 'transparent_fixture_scene_implementation_checklist_status=%s\n' "$scene_implementation_status"
  printf 'transparent_fixture_scene_implementation_gate_check_status=%s\n' "$scene_implementation_gate_status"
  printf 'transparent_fixture_report_check_status=%s\n' "$report_check_status"
  printf 'env_on_expected=%s\n' "$harness_env_expected"
  printf 'overlay_env_on_expected=%s\n' "$harness_overlay_env_expected"
  printf 'overlay_metadata_expected=%s\n' "$harness_overlay_metadata_expected"
  printf 'contract_tokens=%s\n' "$contract_tokens"
  printf 'runtime_behavior=unchanged\n'
  printf 'ordinary_world_visibility=absent\n'
  printf 'summary transparent_fixture_pack_status=pass transparent_fixture_acceptance_status=%s transparent_fixture_default_off_status=%s transparent_fixture_final_report_check_status=%s transparent_fixture_scene_implementation_checklist_status=%s transparent_fixture_scene_implementation_gate_check_status=%s transparent_fixture_report_check_status=%s transparent_fixture_check_status=%s transparent_fixture_scene_harness_check_status=%s fixture_plan_status=%s transparent_fixture_harness_status=%s env_on_expected=%s overlay_env_on_expected=%s overlay_metadata_expected=%s\n' \
    "$acceptance_status" \
    "$default_off_status" \
    "$final_report_status" \
    "$scene_implementation_status" \
    "$scene_implementation_gate_status" \
    "$report_check_status" \
    "$check_status" \
    "$scene_harness_check_status" \
    "$plan_status" \
    "$harness_status" \
    "$harness_env_expected" \
    "$harness_overlay_env_expected" \
    "$harness_overlay_metadata_expected"
} > "$tmp_pack"

mv "$tmp_pack" "$OUT_PATH"

sh "$ROOT_DIR/scripts/gpu_terrain_transparent_fixture_scene_implementation_checklist.sh" \
  "$OUT_PATH" \
  "$SCENE_IMPLEMENTATION_CHECKLIST_PATH" >/dev/null

sh "$ROOT_DIR/scripts/gpu_terrain_transparent_fixture_scene_implementation_gate_check.sh" \
  "$SCENE_IMPLEMENTATION_CHECKLIST_PATH" \
  "$SCENE_IMPLEMENTATION_GATE_CHECK_PATH" >/dev/null

sh "$ROOT_DIR/scripts/gpu_terrain_report.sh" \
  "$LOG_DIR" \
  "$REPORT_PATH" >/dev/null
required_line "$REPORT_PATH" "## Selected Transparent Fixture Scene Implementation Gate Check" >/dev/null
required_line "$REPORT_PATH" "Source: \`$SCENE_IMPLEMENTATION_GATE_CHECK_PATH\`" >/dev/null
cat "$OUT_PATH"
