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
sh "$ROOT_DIR/scripts/gpu_terrain_report.sh" \
  "$LOG_DIR" \
  "$REPORT_PATH" >/dev/null
sh "$ROOT_DIR/scripts/gpu_terrain_transparent_fixture_report_check.sh" \
  "$REPORT_PATH" \
  "$PACK_DIR" \
  "$REPORT_CHECK_PATH" >/dev/null

plan_summary_line="$(required_line "$PLAN_PATH" "summary fixture_plan_status=")"
harness_summary_line="$(required_line "$HARNESS_PATH" "summary transparent_fixture_harness_status=")"
check_summary_line="$(required_line "$CHECK_PATH" "summary transparent_fixture_check_status=")"
report_check_summary_line="$(required_line "$REPORT_CHECK_PATH" "summary transparent_fixture_report_check_status=")"

plan_status="$(required_token "fixture_plan_status" "$plan_summary_line" "plan summary")"
contract_tokens="$(required_token "contract_tokens" "$plan_summary_line" "plan summary")"
harness_status="$(required_token "transparent_fixture_harness_status" "$harness_summary_line" "harness summary")"
harness_env_expected="$(required_token "env_on_expected" "$harness_summary_line" "harness summary")"
check_status="$(required_token "transparent_fixture_check_status" "$check_summary_line" "check summary")"
check_plan_status="$(required_token "fixture_plan_status" "$check_summary_line" "check summary")"
check_harness_status="$(required_token "transparent_fixture_harness_status" "$check_summary_line" "check summary")"
check_env_expected="$(required_token "env_on_expected" "$check_summary_line" "check summary")"
report_check_status="$(required_token "transparent_fixture_report_check_status" "$report_check_summary_line" "report-check summary")"
report_check_check_status="$(required_token "transparent_fixture_check_status" "$report_check_summary_line" "report-check summary")"
report_check_plan_status="$(required_token "fixture_plan_status" "$report_check_summary_line" "report-check summary")"
report_check_harness_status="$(required_token "transparent_fixture_harness_status" "$report_check_summary_line" "report-check summary")"
report_check_env_expected="$(required_token "env_on_expected" "$report_check_summary_line" "report-check summary")"

test "$plan_status" = "pending_fixture_harness" || fail "unexpected fixture_plan_status=$plan_status"
test "$harness_status" = "placeholder" || fail "unexpected transparent_fixture_harness_status=$harness_status"
test "$check_status" = "pass" || fail "unexpected transparent_fixture_check_status=$check_status"
test "$report_check_status" = "pass" || fail "unexpected transparent_fixture_report_check_status=$report_check_status"
test "$check_plan_status" = "$plan_status" || fail "check fixture_plan_status does not match plan"
test "$check_harness_status" = "$harness_status" || fail "check harness status does not match harness"
test "$check_env_expected" = "$harness_env_expected" || fail "check env_on_expected does not match harness"
test "$report_check_check_status" = "$check_status" || fail "report-check status does not match check"
test "$report_check_plan_status" = "$plan_status" || fail "report-check fixture_plan_status does not match plan"
test "$report_check_harness_status" = "$harness_status" || fail "report-check harness status does not match harness"
test "$report_check_env_expected" = "$harness_env_expected" || fail "report-check env_on_expected does not match harness"
test "$harness_env_expected" = "1/0/1" || fail "unexpected env_on_expected=$harness_env_expected"
case "$contract_tokens" in
  ''|*[!0-9]*) fail "contract_tokens must be numeric: $contract_tokens" ;;
esac
test "$contract_tokens" -ge 21 || fail "contract_tokens too low: $contract_tokens"

tmp_pack="$OUT_PATH.tmp"
trap 'rm -f "$tmp_pack"' EXIT

{
  printf 'GPU terrain transparent fixture pack\n'
  printf 'pack_dir=%s\n' "$(relative_path "$PACK_DIR")"
  printf 'log_dir=%s\n' "$(relative_path "$LOG_DIR")"
  printf 'plan=%s\n' "$(relative_path "$PLAN_PATH")"
  printf 'harness=%s\n' "$(relative_path "$HARNESS_PATH")"
  printf 'check=%s\n' "$(relative_path "$CHECK_PATH")"
  printf 'report=%s\n' "$(relative_path "$REPORT_PATH")"
  printf 'report_check=%s\n' "$(relative_path "$REPORT_CHECK_PATH")"
  printf 'steps=plan/harness/check/report/report_check\n'
  printf 'fixture_plan_status=%s\n' "$plan_status"
  printf 'transparent_fixture_harness_status=%s\n' "$harness_status"
  printf 'transparent_fixture_check_status=%s\n' "$check_status"
  printf 'transparent_fixture_report_check_status=%s\n' "$report_check_status"
  printf 'env_on_expected=%s\n' "$harness_env_expected"
  printf 'contract_tokens=%s\n' "$contract_tokens"
  printf 'runtime_behavior=unchanged\n'
  printf 'ordinary_world_visibility=absent\n'
  printf 'summary transparent_fixture_pack_status=pass transparent_fixture_report_check_status=%s transparent_fixture_check_status=%s fixture_plan_status=%s transparent_fixture_harness_status=%s env_on_expected=%s\n' \
    "$report_check_status" \
    "$check_status" \
    "$plan_status" \
    "$harness_status" \
    "$harness_env_expected"
} > "$tmp_pack"

mv "$tmp_pack" "$OUT_PATH"
cat "$OUT_PATH"
