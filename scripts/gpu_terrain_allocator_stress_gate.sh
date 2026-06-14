#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
LOG_DIR="${1:-"$ROOT_DIR/logs/week2_gpu_allocator_telemetry_20260614"}"
case "$LOG_DIR" in
  /*) ;;
  *) LOG_DIR="$ROOT_DIR/$LOG_DIR" ;;
esac
OUT_PATH="${2:-"$LOG_DIR/gpu-allocator-stress-gate-summary.txt"}"
case "$OUT_PATH" in
  /*) ;;
  *) OUT_PATH="$ROOT_DIR/$OUT_PATH" ;;
esac
REPORT_PATH="${RUMPELMC_ALLOCATOR_STRESS_REPORT_PATH:-"$LOG_DIR/gpu-terrain-report.txt"}"
case "$REPORT_PATH" in
  /*) ;;
  *) REPORT_PATH="$ROOT_DIR/$REPORT_PATH" ;;
esac

MAX_UPLOAD_FAIL="${RUMPELMC_ALLOCATOR_STRESS_MAX_UPLOAD_FAIL:-0}"
MAX_UPLOAD_FAIL_CAPACITY="${RUMPELMC_ALLOCATOR_STRESS_MAX_UPLOAD_FAIL_CAPACITY:-0}"
MAX_UPLOAD_FAIL_FRAGMENTED="${RUMPELMC_ALLOCATOR_STRESS_MAX_UPLOAD_FAIL_FRAGMENTED:-0}"
MIN_FREE_FACES="${RUMPELMC_ALLOCATOR_STRESS_MIN_FREE_FACES:-1}"
MIN_LARGEST_FREE="${RUMPELMC_ALLOCATOR_STRESS_MIN_LARGEST_FREE:-1}"
MAX_FRAGMENTATION_PCT="${RUMPELMC_ALLOCATOR_STRESS_MAX_FRAGMENTATION_PCT:-1.0}"

fail() {
  echo "gpu_terrain_allocator_stress_gate: $*" >&2
  exit 1
}

relative_path() {
  path="$1"
  case "$path" in
    "$ROOT_DIR"/*) printf '%s\n' "${path#$ROOT_DIR/}" ;;
    *) printf '%s\n' "$path" ;;
  esac
}

metric_value() {
  label="$1"
  awk -v label="$label" '
    index($0, "- " label ": `") == 1 {
      split($0, parts, "`")
      print parts[4]
      exit
    }
  ' "$REPORT_PATH"
}

require_metric() {
  label="$1"
  value="$(metric_value "$label")"
  test -n "$value" || fail "missing report metric $label in $(relative_path "$REPORT_PATH")"
  test "$value" != "n/a" || fail "report metric $label is n/a in $(relative_path "$REPORT_PATH")"
  printf '%s\n' "$value"
}

assert_int_le() {
  name="$1"
  value="$2"
  max="$3"
  awk -v value="$value" -v max="$max" 'BEGIN { exit !((value + 0) <= (max + 0)) }' \
    || fail "$name=$value exceeds $max"
}

assert_float_le() {
  name="$1"
  value="$2"
  max="$3"
  awk -v value="$value" -v max="$max" 'BEGIN { exit !((value + 0.0) <= (max + 0.0)) }' \
    || fail "$name=$value exceeds $max"
}

assert_int_ge() {
  name="$1"
  value="$2"
  min="$3"
  awk -v value="$value" -v min="$min" 'BEGIN { exit !((value + 0) >= (min + 0)) }' \
    || fail "$name=$value is below $min"
}

test -d "$LOG_DIR" || fail "missing log dir $LOG_DIR"
mkdir -p "$(dirname -- "$OUT_PATH")"
sh "$ROOT_DIR/scripts/gpu_terrain_report.sh" "$LOG_DIR" "$REPORT_PATH" >/dev/null
test -s "$REPORT_PATH" || fail "missing report $(relative_path "$REPORT_PATH")"
grep -q "No error patterns found in summary and marker files." "$REPORT_PATH" \
  || fail "report error scan is not clean in $(relative_path "$REPORT_PATH")"

upload_fail="$(require_metric 'sum `gpu_upload_fail`')"
upload_fail_capacity="$(require_metric 'sum `gpu_upload_fail_capacity`')"
upload_fail_fragmented="$(require_metric 'sum `gpu_upload_fail_fragmented`')"
free_ranges="$(require_metric 'max `gpu_free_ranges`')"
free_faces="$(require_metric 'max `gpu_free_faces`')"
largest_free="$(require_metric 'max `gpu_largest_free`')"
fragmented_free_faces="$(require_metric 'max `gpu_fragmented_free_faces`')"
fragmentation_pct="$(require_metric 'max `gpu_fragmentation_pct`')"
terrain_queue_max_ms="$(require_metric 'max `terrain_queue_max_ms`')"

assert_int_le gpu_upload_fail "$upload_fail" "$MAX_UPLOAD_FAIL"
assert_int_le gpu_upload_fail_capacity "$upload_fail_capacity" "$MAX_UPLOAD_FAIL_CAPACITY"
assert_int_le gpu_upload_fail_fragmented "$upload_fail_fragmented" "$MAX_UPLOAD_FAIL_FRAGMENTED"
assert_int_ge gpu_free_faces "$free_faces" "$MIN_FREE_FACES"
assert_int_ge gpu_largest_free "$largest_free" "$MIN_LARGEST_FREE"
assert_float_le gpu_fragmentation_pct "$fragmentation_pct" "$MAX_FRAGMENTATION_PCT"

{
  printf 'GPU terrain allocator stress gate\n'
  printf 'log_dir=%s\n' "$(relative_path "$LOG_DIR")"
  printf 'report=%s\n' "$(relative_path "$REPORT_PATH")"
  printf 'thresholds max_upload_fail=%s max_upload_fail_capacity=%s max_upload_fail_fragmented=%s min_free_faces=%s min_largest_free=%s max_fragmentation_pct=%s\n' \
    "$MAX_UPLOAD_FAIL" \
    "$MAX_UPLOAD_FAIL_CAPACITY" \
    "$MAX_UPLOAD_FAIL_FRAGMENTED" \
    "$MIN_FREE_FACES" \
    "$MIN_LARGEST_FREE" \
    "$MAX_FRAGMENTATION_PCT"
  printf 'summary allocator_stress_gate_status=pass gpu_upload_fail=%s gpu_upload_fail_capacity=%s gpu_upload_fail_fragmented=%s gpu_free_ranges=%s gpu_free_faces=%s gpu_largest_free=%s gpu_fragmented_free_faces=%s gpu_fragmentation_pct=%s terrain_queue_max_ms=%s\n' \
    "$upload_fail" \
    "$upload_fail_capacity" \
    "$upload_fail_fragmented" \
    "$free_ranges" \
    "$free_faces" \
    "$largest_free" \
    "$fragmented_free_faces" \
    "$fragmentation_pct" \
    "$terrain_queue_max_ms"
} > "$OUT_PATH"

cat "$OUT_PATH"
