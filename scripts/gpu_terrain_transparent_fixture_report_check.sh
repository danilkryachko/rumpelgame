#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
REPORT_PATH="${1:-"$ROOT_DIR/logs/gpu-terrain-report.txt"}"
case "$REPORT_PATH" in
  /*) ;;
  *) REPORT_PATH="$ROOT_DIR/$REPORT_PATH" ;;
esac
FIXTURE_DIR="${2:-"$ROOT_DIR/logs/gpu_transparent_fixture_plan"}"
case "$FIXTURE_DIR" in
  /*) ;;
  *) FIXTURE_DIR="$ROOT_DIR/$FIXTURE_DIR" ;;
esac
OUT_PATH="${3:-"$(dirname -- "$REPORT_PATH")/transparent-fixture-report-check.txt"}"
case "$OUT_PATH" in
  /*) ;;
  *) OUT_PATH="$ROOT_DIR/$OUT_PATH" ;;
esac

PLAN_PATH="$FIXTURE_DIR/transparent-fixture-plan.txt"
HARNESS_PATH="$FIXTURE_DIR/transparent-fixture-harness.txt"
CHECK_PATH="$FIXTURE_DIR/transparent-fixture-check.txt"
SCENE_CHECKLIST_PATH="$FIXTURE_DIR/transparent-fixture-scene-checklist.txt"
SCENE_HARNESS_PATH="$FIXTURE_DIR/transparent-fixture-scene-harness.txt"
SCENE_HARNESS_CHECK_PATH="$FIXTURE_DIR/transparent-fixture-scene-harness-check.txt"

fail() {
  echo "gpu_terrain_transparent_fixture_report_check: $*" >&2
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

required_exact_line() {
  file_path="$1"
  pattern="$2"
  line="$(awk -v pattern="$pattern" '$0 == pattern { print; exit }' "$file_path")"
  test -n "$line" || fail "missing exact line in $(relative_path "$file_path"): $pattern"
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

require_source() {
  label="$1"
  path="$2"
  required_line "$REPORT_PATH" "## $label" >/dev/null
  required_line "$REPORT_PATH" "Source: \`$path\`" >/dev/null
}

test -s "$REPORT_PATH" || fail "missing GPU terrain report $REPORT_PATH"
test -d "$FIXTURE_DIR" || fail "missing transparent fixture dir $FIXTURE_DIR"
test -s "$PLAN_PATH" || fail "missing transparent fixture plan $PLAN_PATH"
test -s "$HARNESS_PATH" || fail "missing transparent fixture harness $HARNESS_PATH"
test -s "$CHECK_PATH" || fail "missing transparent fixture check $CHECK_PATH"
test -s "$SCENE_CHECKLIST_PATH" || fail "missing transparent fixture scene checklist $SCENE_CHECKLIST_PATH"
test -s "$SCENE_HARNESS_PATH" || fail "missing transparent fixture scene harness $SCENE_HARNESS_PATH"
test -s "$SCENE_HARNESS_CHECK_PATH" || fail "missing transparent fixture scene harness check $SCENE_HARNESS_CHECK_PATH"
mkdir -p "$(dirname -- "$OUT_PATH")"

require_source "Selected Transparent Fixture Plan" "$PLAN_PATH"
require_source "Selected Transparent Fixture Harness" "$HARNESS_PATH"
require_source "Selected Transparent Fixture Check" "$CHECK_PATH"
require_source "Selected Transparent Fixture Scene Checklist" "$SCENE_CHECKLIST_PATH"
require_source "Selected Transparent Fixture Scene Harness" "$SCENE_HARNESS_PATH"
require_source "Selected Transparent Fixture Scene Harness Check" "$SCENE_HARNESS_CHECK_PATH"

plan_summary_line="$(required_line "$REPORT_PATH" "summary fixture_plan_status=")"
harness_summary_line="$(required_line "$REPORT_PATH" "summary transparent_fixture_harness_status=")"
check_summary_line="$(required_line "$REPORT_PATH" "summary transparent_fixture_check_status=")"
scene_check_summary_line="$(required_line "$REPORT_PATH" "summary transparent_fixture_scene_harness_check_status=")"

fixture_line="$(required_exact_line "$REPORT_PATH" "fixture=gpu-transparent-depth-collision")"
material_line="$(required_exact_line "$REPORT_PATH" "material=transparent_test_glass")"
plan_status_line="$(required_exact_line "$REPORT_PATH" "plan_status=pending_fixture_harness")"
harness_status_line="$(required_exact_line "$REPORT_PATH" "harness_status=placeholder")"
runtime_line="$(required_exact_line "$REPORT_PATH" "runtime_behavior=unchanged")"
ordinary_line="$(required_exact_line "$REPORT_PATH" "ordinary_world_visibility=absent")"
rollback_line="$(required_exact_line "$REPORT_PATH" "opaque_path_rollback=required")"
env_expected_line="$(required_exact_line "$REPORT_PATH" "env_on_expected=1/0/1")"
future_active_line="$(required_exact_line "$REPORT_PATH" "future_active_expected=1/0/0")"
fallback_guard_line="$(required_exact_line "$REPORT_PATH" "fallback_guard=present")"
contract_tokens_line="$(required_exact_line "$REPORT_PATH" "contract_tokens=21")"

test "${fixture_line#fixture=}" = "gpu-transparent-depth-collision" || fail "unexpected fixture line: $fixture_line"
test "${material_line#material=}" = "transparent_test_glass" || fail "unexpected material line: $material_line"
test "${plan_status_line#plan_status=}" = "pending_fixture_harness" || fail "unexpected plan status line: $plan_status_line"
test "${harness_status_line#harness_status=}" = "placeholder" || fail "unexpected harness status line: $harness_status_line"
test "${runtime_line#runtime_behavior=}" = "unchanged" || fail "unexpected runtime line: $runtime_line"
test "${ordinary_line#ordinary_world_visibility=}" = "absent" || fail "unexpected ordinary-world line: $ordinary_line"
test "${rollback_line#opaque_path_rollback=}" = "required" || fail "unexpected rollback line: $rollback_line"
test "${env_expected_line#env_on_expected=}" = "1/0/1" || fail "unexpected env-on line: $env_expected_line"
test "${future_active_line#future_active_expected=}" = "1/0/0" || fail "unexpected future-active line: $future_active_line"
test "${fallback_guard_line#fallback_guard=}" = "present" || fail "unexpected fallback guard line: $fallback_guard_line"
test "${contract_tokens_line#contract_tokens=}" = "21" || fail "unexpected contract token line: $contract_tokens_line"

plan_status="$(required_token "fixture_plan_status" "$plan_summary_line" "plan summary")"
plan_tokens="$(required_token "contract_tokens" "$plan_summary_line" "plan summary")"
plan_fallback_guard="$(required_token "fallback_guard" "$plan_summary_line" "plan summary")"
harness_status="$(required_token "transparent_fixture_harness_status" "$harness_summary_line" "harness summary")"
harness_plan_status="$(required_token "fixture_plan_status" "$harness_summary_line" "harness summary")"
harness_runtime="$(required_token "runtime_behavior" "$harness_summary_line" "harness summary")"
harness_env_expected="$(required_token "env_on_expected" "$harness_summary_line" "harness summary")"
check_status="$(required_token "transparent_fixture_check_status" "$check_summary_line" "check summary")"
check_plan_status="$(required_token "fixture_plan_status" "$check_summary_line" "check summary")"
check_harness_status="$(required_token "transparent_fixture_harness_status" "$check_summary_line" "check summary")"
check_env_expected="$(required_token "env_on_expected" "$check_summary_line" "check summary")"
scene_check_status="$(required_token "transparent_fixture_scene_harness_check_status" "$scene_check_summary_line" "scene harness-check summary")"
scene_check_harness_status="$(required_token "transparent_fixture_scene_harness_status" "$scene_check_summary_line" "scene harness-check summary")"
scene_check_scene_status="$(required_token "transparent_fixture_scene_checklist_status" "$scene_check_summary_line" "scene harness-check summary")"
scene_check_roles="$(required_token "roles" "$scene_check_summary_line" "scene harness-check summary")"
scene_check_env_expected="$(required_token "env_on_expected" "$scene_check_summary_line" "scene harness-check summary")"

test "$plan_status" = "pending_fixture_harness" || fail "unexpected fixture_plan_status=$plan_status"
test "$plan_tokens" = "21" || fail "unexpected contract_tokens=$plan_tokens"
test "$plan_fallback_guard" = "present" || fail "unexpected fallback_guard=$plan_fallback_guard"
test "$harness_status" = "placeholder" || fail "unexpected transparent_fixture_harness_status=$harness_status"
test "$harness_plan_status" = "$plan_status" || fail "harness fixture_plan_status does not match plan"
test "$harness_runtime" = "unchanged" || fail "unexpected harness runtime_behavior=$harness_runtime"
test "$harness_env_expected" = "1/0/1" || fail "unexpected harness env_on_expected=$harness_env_expected"
test "$check_status" = "pass" || fail "unexpected transparent_fixture_check_status=$check_status"
test "$check_plan_status" = "$plan_status" || fail "check fixture_plan_status does not match plan"
test "$check_harness_status" = "$harness_status" || fail "check harness status does not match harness"
test "$check_env_expected" = "$harness_env_expected" || fail "check env_on_expected does not match harness"
test "$scene_check_status" = "pass" || fail "unexpected transparent_fixture_scene_harness_check_status=$scene_check_status"
test "$scene_check_harness_status" = "$harness_status" || fail "scene harness-check status does not match harness"
test "$scene_check_scene_status" = "pending_scene_harness" || fail "unexpected scene checklist status=$scene_check_scene_status"
test "$scene_check_roles" = "5" || fail "unexpected scene roles=$scene_check_roles"
test "$scene_check_env_expected" = "$harness_env_expected" || fail "scene harness-check env_on_expected does not match harness"

tmp_check="$OUT_PATH.tmp"
trap 'rm -f "$tmp_check"' EXIT

{
  printf 'GPU terrain transparent fixture report check\n'
  printf 'report=%s\n' "$(relative_path "$REPORT_PATH")"
  printf 'fixture_dir=%s\n' "$(relative_path "$FIXTURE_DIR")"
  printf 'plan=%s\n' "$(relative_path "$PLAN_PATH")"
  printf 'harness=%s\n' "$(relative_path "$HARNESS_PATH")"
  printf 'check=%s\n' "$(relative_path "$CHECK_PATH")"
  printf 'scene_checklist=%s\n' "$(relative_path "$SCENE_CHECKLIST_PATH")"
  printf 'scene_harness=%s\n' "$(relative_path "$SCENE_HARNESS_PATH")"
  printf 'scene_harness_check=%s\n' "$(relative_path "$SCENE_HARNESS_CHECK_PATH")"
  printf 'report_sections=plan/harness/check/scene_checklist/scene_harness/scene_harness_check\n'
  printf 'transparent_fixture_check_status=%s\n' "$check_status"
  printf 'transparent_fixture_scene_harness_check_status=%s\n' "$scene_check_status"
  printf 'fixture_plan_status=%s\n' "$plan_status"
  printf 'transparent_fixture_harness_status=%s\n' "$harness_status"
  printf 'env_on_expected=%s\n' "$check_env_expected"
  printf 'future_active_expected=1/0/0\n'
  printf 'summary transparent_fixture_report_check_status=pass transparent_fixture_check_status=%s transparent_fixture_scene_harness_check_status=%s fixture_plan_status=%s transparent_fixture_harness_status=%s env_on_expected=%s\n' \
    "$check_status" \
    "$scene_check_status" \
    "$plan_status" \
    "$harness_status" \
    "$check_env_expected"
} > "$tmp_check"

mv "$tmp_check" "$OUT_PATH"
cat "$OUT_PATH"
