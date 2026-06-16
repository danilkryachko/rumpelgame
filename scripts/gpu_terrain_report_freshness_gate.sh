#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/gpu_terrain_report_freshness_current"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

LOG_DIR="${RUMPELMC_GPU_REPORT_FRESHNESS_LOG_DIR:-"$ROOT_DIR/logs"}"
case "$LOG_DIR" in
  /*) ;;
  *) LOG_DIR="$ROOT_DIR/$LOG_DIR" ;;
esac

REPORT_PATH="${RUMPELMC_GPU_REPORT_FRESHNESS_REPORT_PATH:-"$ROOT_DIR/logs/gpu-terrain-report.txt"}"
case "$REPORT_PATH" in
  /*) ;;
  *) REPORT_PATH="$ROOT_DIR/$REPORT_PATH" ;;
esac

SUMMARY_PATH="$OUT_DIR/gpu-terrain-report-freshness-summary.txt"
CHECK_PATH="$OUT_DIR/gpu-terrain-report-freshness-check.txt"
REFRESH_REPORT="${RUMPELMC_GPU_REPORT_FRESHNESS_REFRESH:-1}"

fail() {
  echo "gpu_terrain_report_freshness_gate: $*" >&2
  exit 1
}

relative_path() {
  path="$1"
  case "$path" in
    "$ROOT_DIR"/*) printf '%s\n' "${path#$ROOT_DIR/}" ;;
    *) printf '%s\n' "$path" ;;
  esac
}

report_metric_value() {
  label="$1"
  awk -v label="$label" '
    index($0, "- " label ": `") == 1 {
      split($0, parts, "`")
      print parts[4]
      exit
    }
  ' "$REPORT_PATH"
}

require_report_metric() {
  label="$1"
  value="$(report_metric_value "$label")"
  test -n "$value" || fail "missing report metric $label in $(relative_path "$REPORT_PATH")"
  test "$value" != "n/a" || fail "report metric $label is n/a in $(relative_path "$REPORT_PATH")"
  printf '%s\n' "$value"
}

assert_zero() {
  name="$1"
  value="$2"
  awk -v value="$value" 'BEGIN { exit !((value + 0) == 0) }' \
    || fail "$name=$value, expected 0"
}

assert_positive() {
  name="$1"
  value="$2"
  awk -v value="$value" 'BEGIN { exit !((value + 0) > 0) }' \
    || fail "$name=$value, expected positive"
}

mkdir -p "$OUT_DIR"
test -d "$LOG_DIR" || fail "missing log dir $(relative_path "$LOG_DIR")"
test -f "$ROOT_DIR/scripts/gpu_terrain_report.sh" || fail "missing gpu terrain report script"

if [ "$REFRESH_REPORT" = "1" ]; then
  sh "$ROOT_DIR/scripts/gpu_terrain_report.sh" "$LOG_DIR" "$REPORT_PATH" >/dev/null
fi

test -s "$REPORT_PATH" || fail "missing report $(relative_path "$REPORT_PATH")"
grep -q '^# GPU Terrain Report$' "$REPORT_PATH" \
  || fail "report header missing in $(relative_path "$REPORT_PATH")"
grep -q 'Aggregate caveat: aggregate values scan all matching historical summaries under the log dir' "$REPORT_PATH" \
  || fail "aggregate caveat missing in $(relative_path "$REPORT_PATH")"

current_commit="$(git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null || printf 'unknown')"
report_commit="$(sed -n 's/^Git commit: `\([^`]*\)`.*/\1/p' "$REPORT_PATH" | sed -n '1p')"
generated_at="$(sed -n 's/^Generated: `\([^`]*\)`.*/\1/p' "$REPORT_PATH" | sed -n '1p')"

test -n "$report_commit" || fail "missing report commit in $(relative_path "$REPORT_PATH")"
test "$report_commit" = "$current_commit" \
  || fail "stale report commit $report_commit, current commit $current_commit"
test -n "$generated_at" || fail "missing generated timestamp in $(relative_path "$REPORT_PATH")"

if grep -q 'No error patterns found in summary and marker files.' "$REPORT_PATH"; then
  report_error_scan="clean"
else
  report_error_scan="dirty"
fi
test "$report_error_scan" = "clean" || fail "report error scan is dirty"

upload_fail="$(require_report_metric 'sum `gpu_upload_fail`')"
upload_fail_capacity="$(require_report_metric 'sum `gpu_upload_fail_capacity`')"
upload_fail_fragmented="$(require_report_metric 'sum `gpu_upload_fail_fragmented`')"
effective_draws="$(require_report_metric 'max `gpu_effective_draws`')"
draw_cmd_occupancy="$(require_report_metric 'max `gpu_draw_cmd_occupancy_pct`')"
terrain_queue_gpu_uploads="$(require_report_metric 'max `terrain_queue_gpu_uploads` max component')"
terrain_queue_gpu_upload_kb="$(require_report_metric 'max `terrain_queue_gpu_upload_kb` max component')"

assert_zero gpu_upload_fail "$upload_fail"
assert_zero gpu_upload_fail_capacity "$upload_fail_capacity"
assert_zero gpu_upload_fail_fragmented "$upload_fail_fragmented"
assert_positive gpu_effective_draws "$effective_draws"

{
  printf 'GPU terrain report freshness check\n'
  printf 'log_dir=%s\n' "$(relative_path "$LOG_DIR")"
  printf 'report=%s\n' "$(relative_path "$REPORT_PATH")"
  printf 'refresh_report=%s\n' "$REFRESH_REPORT"
  printf 'current_commit=%s\n' "$current_commit"
  printf 'report_commit=%s\n' "$report_commit"
  printf 'generated_at=%s\n' "$generated_at"
  printf 'report_error_scan=%s\n' "$report_error_scan"
  printf 'gpu_upload_fail=%s\n' "$upload_fail"
  printf 'gpu_upload_fail_capacity=%s\n' "$upload_fail_capacity"
  printf 'gpu_upload_fail_fragmented=%s\n' "$upload_fail_fragmented"
  printf 'gpu_effective_draws=%s\n' "$effective_draws"
  printf 'gpu_draw_cmd_occupancy_pct=%s\n' "$draw_cmd_occupancy"
  printf 'terrain_queue_gpu_uploads=%s\n' "$terrain_queue_gpu_uploads"
  printf 'terrain_queue_gpu_upload_kb=%s\n' "$terrain_queue_gpu_upload_kb"
} > "$CHECK_PATH"

{
  printf 'gpu_terrain_report_freshness status=pass reason=ok freshness_status=current report_error_scan=%s current_commit=%s report_commit=%s generated_at=%s gpu_upload_fail=%s gpu_upload_fail_capacity=%s gpu_upload_fail_fragmented=%s gpu_effective_draws=%s gpu_draw_cmd_occupancy_pct=%s terrain_queue_gpu_uploads=%s terrain_queue_gpu_upload_kb=%s report=%s check=%s\n' \
    "$report_error_scan" \
    "$current_commit" \
    "$report_commit" \
    "$generated_at" \
    "$upload_fail" \
    "$upload_fail_capacity" \
    "$upload_fail_fragmented" \
    "$effective_draws" \
    "$draw_cmd_occupancy" \
    "$terrain_queue_gpu_uploads" \
    "$terrain_queue_gpu_upload_kb" \
    "$(relative_path "$REPORT_PATH")" \
    "$(relative_path "$CHECK_PATH")"
} > "$SUMMARY_PATH"

cat "$SUMMARY_PATH"
