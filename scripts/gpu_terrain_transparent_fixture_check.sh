#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
PLAN_PATH="${1:-"$ROOT_DIR/logs/gpu_transparent_fixture_plan/transparent-fixture-plan.txt"}"
case "$PLAN_PATH" in
  /*) ;;
  *) PLAN_PATH="$ROOT_DIR/$PLAN_PATH" ;;
esac
HARNESS_PATH="${2:-"$(dirname -- "$PLAN_PATH")/transparent-fixture-harness.txt"}"
case "$HARNESS_PATH" in
  /*) ;;
  *) HARNESS_PATH="$ROOT_DIR/$HARNESS_PATH" ;;
esac
OUT_PATH="${3:-"$(dirname -- "$HARNESS_PATH")/transparent-fixture-check.txt"}"
case "$OUT_PATH" in
  /*) ;;
  *) OUT_PATH="$ROOT_DIR/$OUT_PATH" ;;
esac

fail() {
  echo "gpu_terrain_transparent_fixture_check: $*" >&2
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

test -s "$PLAN_PATH" || fail "missing transparent fixture plan $PLAN_PATH"
test -s "$HARNESS_PATH" || fail "missing transparent fixture harness $HARNESS_PATH"
mkdir -p "$(dirname -- "$OUT_PATH")"

plan_fixture_line="$(required_line "$PLAN_PATH" "fixture=gpu-transparent-depth-collision")"
plan_material_line="$(required_line "$PLAN_PATH" "material=transparent_test_glass")"
plan_runtime_line="$(required_line "$PLAN_PATH" "runtime_behavior=unchanged")"
plan_ordinary_line="$(required_line "$PLAN_PATH" "ordinary_world_visibility=absent")"
plan_rollback_line="$(required_line "$PLAN_PATH" "opaque_path_rollback=required")"
plan_env_on_line="$(required_line "$PLAN_PATH" "step=env_on_fallback_gate status=current_expected")"
plan_future_markers_line="$(required_line "$PLAN_PATH" "step=future_workload_markers status=required")"
plan_future_active_line="$(required_line "$PLAN_PATH" "step=future_active_gate status=blocked_until_implementation")"
plan_non_goals_line="$(required_line "$PLAN_PATH" "step=non_goals status=enforced")"
plan_summary_line="$(required_line "$PLAN_PATH" "summary fixture_plan_status=")"

fixture="${plan_fixture_line#fixture=}"
material="${plan_material_line#material=}"
runtime_behavior="${plan_runtime_line#runtime_behavior=}"
ordinary_visibility="${plan_ordinary_line#ordinary_world_visibility=}"
rollback_status="${plan_rollback_line#opaque_path_rollback=}"
plan_status="$(required_token "fixture_plan_status" "$plan_summary_line" "plan summary")"
contract_tokens="$(required_token "contract_tokens" "$plan_summary_line" "plan summary")"
fallback_guard="$(required_token "fallback_guard" "$plan_summary_line" "plan summary")"
requested="$(required_token "transparent_requested" "$plan_env_on_line" "plan env-on")"
active="$(required_token "transparent_active" "$plan_env_on_line" "plan env-on")"
fallback="$(required_token "transparent_fallback" "$plan_env_on_line" "plan env-on")"
future_active="$(required_token "transparent_active" "$plan_future_active_line" "plan future-active")"
future_fallback="$(required_token "transparent_fallback" "$plan_future_active_line" "plan future-active")"
future_upload_fail="$(required_token "gpu_upload_fail" "$plan_future_active_line" "plan future-active")"

test "$fixture" = "gpu-transparent-depth-collision" || fail "unexpected plan fixture=$fixture"
test "$material" = "transparent_test_glass" || fail "unexpected plan material=$material"
test "$runtime_behavior" = "unchanged" || fail "unexpected plan runtime_behavior=$runtime_behavior"
test "$ordinary_visibility" = "absent" || fail "unexpected plan ordinary_world_visibility=$ordinary_visibility"
test "$rollback_status" = "required" || fail "unexpected plan opaque_path_rollback=$rollback_status"
test "$plan_status" = "pending_fixture_harness" || fail "unexpected fixture_plan_status=$plan_status"
test "$fallback_guard" = "present" || fail "unexpected fallback_guard=$fallback_guard"
test "$requested" = "1" || fail "unexpected transparent_requested=$requested"
test "$active" = "0" || fail "unexpected transparent_active=$active"
test "$fallback" = "1" || fail "unexpected transparent_fallback=$fallback"
test "$future_active" = "1" || fail "unexpected future transparent_active=$future_active"
test "$future_fallback" = "0" || fail "unexpected future transparent_fallback=$future_fallback"
test "$future_upload_fail" = "0" || fail "unexpected future gpu_upload_fail=$future_upload_fail"
case "$contract_tokens" in
  ''|*[!0-9]*) fail "contract_tokens must be numeric: $contract_tokens" ;;
esac
test "$contract_tokens" -ge 21 || fail "contract_tokens too low: $contract_tokens"

for marker in transparent_blocks=pending transparent_faces=pending transparent_draws=pending transparent_subchunks=pending; do
  require_text "$plan_future_markers_line" "$marker" "plan future workload"
done
non_goals="shader_alpha=no transparent_pass=no sorting=no block_id=no asset=no protocol=no storage=no worldgen=no"
require_text "$plan_non_goals_line" "$non_goals" "plan non-goals"

harness_fixture_line="$(required_line "$HARNESS_PATH" "fixture=gpu-transparent-depth-collision")"
harness_material_line="$(required_line "$HARNESS_PATH" "material=transparent_test_glass")"
harness_status_line="$(required_line "$HARNESS_PATH" "harness_status=placeholder")"
harness_runtime_line="$(required_line "$HARNESS_PATH" "runtime_behavior=unchanged")"
harness_ordinary_line="$(required_line "$HARNESS_PATH" "ordinary_world_visibility=absent")"
harness_rollback_line="$(required_line "$HARNESS_PATH" "opaque_path_rollback=required")"
harness_consume_line="$(required_line "$HARNESS_PATH" "step=consume_plan status=present")"
harness_env_off_line="$(required_line "$HARNESS_PATH" "step=env_off_gate status=placeholder")"
harness_env_on_line="$(required_line "$HARNESS_PATH" "step=env_on_fallback_gate status=placeholder")"
harness_future_markers_line="$(required_line "$HARNESS_PATH" "step=future_workload_markers status=blocked_until_fixture")"
harness_future_active_line="$(required_line "$HARNESS_PATH" "step=future_active_gate status=blocked_until_implementation")"
harness_non_goals_line="$(required_line "$HARNESS_PATH" "step=non_goals status=enforced")"
harness_summary_line="$(required_line "$HARNESS_PATH" "summary transparent_fixture_harness_status=")"

test "${harness_fixture_line#fixture=}" = "$fixture" || fail "harness fixture does not match plan"
test "${harness_material_line#material=}" = "$material" || fail "harness material does not match plan"
test "${harness_status_line#harness_status=}" = "placeholder" || fail "unexpected harness_status"
test "${harness_runtime_line#runtime_behavior=}" = "$runtime_behavior" || fail "harness runtime_behavior does not match plan"
test "${harness_ordinary_line#ordinary_world_visibility=}" = "$ordinary_visibility" || fail "harness ordinary_world_visibility does not match plan"
test "${harness_rollback_line#opaque_path_rollback=}" = "$rollback_status" || fail "harness opaque_path_rollback does not match plan"

harness_plan_status="$(required_token "fixture_plan_status" "$harness_consume_line" "harness consume")"
harness_tokens="$(required_token "contract_tokens" "$harness_consume_line" "harness consume")"
harness_fallback_guard="$(required_token "fallback_guard" "$harness_consume_line" "harness consume")"
harness_requested="$(required_token "expected_transparent_requested" "$harness_env_on_line" "harness env-on")"
harness_active="$(required_token "expected_transparent_active" "$harness_env_on_line" "harness env-on")"
harness_fallback="$(required_token "expected_transparent_fallback" "$harness_env_on_line" "harness env-on")"
harness_future_active="$(required_token "transparent_active" "$harness_future_active_line" "harness future-active")"
harness_future_fallback="$(required_token "transparent_fallback" "$harness_future_active_line" "harness future-active")"
harness_future_upload_fail="$(required_token "gpu_upload_fail" "$harness_future_active_line" "harness future-active")"
harness_summary_status="$(required_token "transparent_fixture_harness_status" "$harness_summary_line" "harness summary")"
harness_summary_plan_status="$(required_token "fixture_plan_status" "$harness_summary_line" "harness summary")"
harness_summary_runtime="$(required_token "runtime_behavior" "$harness_summary_line" "harness summary")"
harness_env_expected="$(required_token "env_on_expected" "$harness_summary_line" "harness summary")"

test "$harness_plan_status" = "$plan_status" || fail "harness fixture_plan_status does not match plan"
test "$harness_tokens" = "$contract_tokens" || fail "harness contract_tokens does not match plan"
test "$harness_fallback_guard" = "$fallback_guard" || fail "harness fallback_guard does not match plan"
test "$harness_requested" = "$requested" || fail "harness transparent_requested does not match plan"
test "$harness_active" = "$active" || fail "harness transparent_active does not match plan"
test "$harness_fallback" = "$fallback" || fail "harness transparent_fallback does not match plan"
test "$harness_future_active" = "$future_active" || fail "harness future transparent_active does not match plan"
test "$harness_future_fallback" = "$future_fallback" || fail "harness future transparent_fallback does not match plan"
test "$harness_future_upload_fail" = "$future_upload_fail" || fail "harness future gpu_upload_fail does not match plan"
test "$harness_summary_status" = "placeholder" || fail "unexpected transparent_fixture_harness_status=$harness_summary_status"
test "$harness_summary_plan_status" = "$plan_status" || fail "harness summary fixture_plan_status does not match plan"
test "$harness_summary_runtime" = "$runtime_behavior" || fail "harness summary runtime_behavior does not match plan"
test "$harness_env_expected" = "$requested/$active/$fallback" || fail "unexpected harness env_on_expected=$harness_env_expected"
require_text "$harness_env_off_line" "expected=ordinary_opaque_markers_unchanged" "harness env-off"
for marker in transparent_blocks=pending transparent_faces=pending transparent_draws=pending transparent_subchunks=pending; do
  require_text "$harness_future_markers_line" "$marker" "harness future workload"
done
require_text "$harness_non_goals_line" "$non_goals" "harness non-goals"

tmp_check="$OUT_PATH.tmp"
trap 'rm -f "$tmp_check"' EXIT

{
  printf 'GPU terrain transparent fixture check\n'
  printf 'plan=%s\n' "$(relative_path "$PLAN_PATH")"
  printf 'harness=%s\n' "$(relative_path "$HARNESS_PATH")"
  printf 'fixture=%s\n' "$fixture"
  printf 'material=%s\n' "$material"
  printf 'plan_status=%s\n' "$plan_status"
  printf 'harness_status=%s\n' "$harness_summary_status"
  printf 'runtime_behavior=%s\n' "$runtime_behavior"
  printf 'ordinary_world_visibility=%s\n' "$ordinary_visibility"
  printf 'opaque_path_rollback=%s\n' "$rollback_status"
  printf 'env_on_expected=%s/%s/%s\n' "$requested" "$active" "$fallback"
  printf 'future_active_expected=%s/%s/%s\n' "$future_active" "$future_fallback" "$future_upload_fail"
  printf 'fallback_guard=%s\n' "$fallback_guard"
  printf 'contract_tokens=%s\n' "$contract_tokens"
  printf 'summary transparent_fixture_check_status=pass fixture_plan_status=%s transparent_fixture_harness_status=%s env_on_expected=%s/%s/%s\n' \
    "$plan_status" \
    "$harness_summary_status" \
    "$requested" \
    "$active" \
    "$fallback"
} > "$tmp_check"

mv "$tmp_check" "$OUT_PATH"
cat "$OUT_PATH"
