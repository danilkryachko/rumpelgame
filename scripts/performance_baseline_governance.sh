#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
CURRENT_SUMMARY="${1:-"$ROOT_DIR/logs/gpu_terrain_report_v2_current/gpu-terrain-report-v2-summary.txt"}"
case "$CURRENT_SUMMARY" in
  /*) ;;
  *) CURRENT_SUMMARY="$ROOT_DIR/$CURRENT_SUMMARY" ;;
esac
BASELINE_FILE="${2:-"$ROOT_DIR/docs/performance_baselines/gpu_terrain_world_streaming.baseline"}"
case "$BASELINE_FILE" in
  /*) ;;
  *) BASELINE_FILE="$ROOT_DIR/$BASELINE_FILE" ;;
esac
OUT_PATH="${3:-"$ROOT_DIR/logs/performance_baseline_governance_current/performance-baseline-governance-summary.txt"}"
case "$OUT_PATH" in
  /*) ;;
  *) OUT_PATH="$ROOT_DIR/$OUT_PATH" ;;
esac

fail() {
  echo "performance_baseline_governance: $*" >&2
  exit 1
}

relative_path() {
  path="$1"
  case "$path" in
    "$ROOT_DIR"/*) printf '%s\n' "${path#$ROOT_DIR/}" ;;
    *) printf '%s\n' "$path" ;;
  esac
}

field_metric() {
  key="$1"
  path="$2"
  awk -v key="$key" '
    {
      prefix = key "="
      for (i = 1; i <= NF; i++) {
        if (index($i, prefix) == 1) {
          value = substr($i, length(prefix) + 1)
          gsub(/^"/, "", value)
          gsub(/"$/, "", value)
          print value
          exit
        }
      }
    }
  ' "$path"
}

require_field() {
  key="$1"
  path="$2"
  value="$(field_metric "$key" "$path")"
  test -n "$value" || fail "missing $key in $(relative_path "$path")"
  printf '%s\n' "$value"
}

test -s "$CURRENT_SUMMARY" || fail "missing current summary $CURRENT_SUMMARY"
test -s "$BASELINE_FILE" || fail "missing baseline file $BASELINE_FILE"
mkdir -p "$(dirname -- "$OUT_PATH")"

baseline_id="$(require_field baseline_id "$BASELINE_FILE")"
baseline_status="$(require_field baseline_status "$BASELINE_FILE")"
required_report_v2_status="$(require_field required_report_v2_status "$BASELINE_FILE")"
required_scoped_status="$(require_field required_scoped_status "$BASELINE_FILE")"
required_resource_status="$(require_field required_resource_status "$BASELINE_FILE")"
required_memory_status="$(require_field required_memory_status "$BASELINE_FILE")"
required_legacy_error_scan="$(require_field required_legacy_error_scan "$BASELINE_FILE")"
min_effective_draws="$(require_field min_historical_gpu_effective_draws "$BASELINE_FILE")"
max_upload_fail="$(require_field max_historical_gpu_upload_fail "$BASELINE_FILE")"
max_fragmentation_pct="$(require_field max_historical_gpu_fragmentation_pct "$BASELINE_FILE")"
max_draw_cmd_occupancy_pct="$(require_field max_historical_draw_cmd_occupancy_pct "$BASELINE_FILE")"
warning_max_frame_p95_ms="$(require_field warning_max_frame_p95_ms "$BASELINE_FILE")"
warning_max_gpu_us="$(require_field warning_max_gpu_compositor_gpu_max_us "$BASELINE_FILE")"

report_v2_status="$(require_field status "$CURRENT_SUMMARY")"
scoped_status="$(require_field scoped_status "$CURRENT_SUMMARY")"
resource_status="$(require_field resource_status "$CURRENT_SUMMARY")"
memory_status="$(require_field memory_status "$CURRENT_SUMMARY")"
legacy_error_scan="$(require_field legacy_error_scan "$CURRENT_SUMMARY")"
historical_effective_draws="$(require_field historical_gpu_effective_draws "$CURRENT_SUMMARY")"
historical_upload_fail="$(require_field historical_gpu_upload_fail "$CURRENT_SUMMARY")"
historical_fragmentation_pct="$(require_field historical_gpu_fragmentation_pct "$CURRENT_SUMMARY")"
historical_draw_cmd_occupancy_pct="$(require_field historical_draw_cmd_occupancy_pct "$CURRENT_SUMMARY")"
warning_frame_p95_ms="$(require_field warning_frame_p95_ms "$CURRENT_SUMMARY")"
warning_gpu_us="$(require_field warning_gpu_compositor_gpu_max_us "$CURRENT_SUMMARY")"

awk \
  -v baseline_id="$baseline_id" \
  -v baseline_status="$baseline_status" \
  -v required_report_v2_status="$required_report_v2_status" \
  -v required_scoped_status="$required_scoped_status" \
  -v required_resource_status="$required_resource_status" \
  -v required_memory_status="$required_memory_status" \
  -v required_legacy_error_scan="$required_legacy_error_scan" \
  -v min_effective_draws="$min_effective_draws" \
  -v max_upload_fail="$max_upload_fail" \
  -v max_fragmentation_pct="$max_fragmentation_pct" \
  -v max_draw_cmd_occupancy_pct="$max_draw_cmd_occupancy_pct" \
  -v warning_max_frame_p95_ms="$warning_max_frame_p95_ms" \
  -v warning_max_gpu_us="$warning_max_gpu_us" \
  -v report_v2_status="$report_v2_status" \
  -v scoped_status="$scoped_status" \
  -v resource_status="$resource_status" \
  -v memory_status="$memory_status" \
  -v legacy_error_scan="$legacy_error_scan" \
  -v historical_effective_draws="$historical_effective_draws" \
  -v historical_upload_fail="$historical_upload_fail" \
  -v historical_fragmentation_pct="$historical_fragmentation_pct" \
  -v historical_draw_cmd_occupancy_pct="$historical_draw_cmd_occupancy_pct" \
  -v warning_frame_p95_ms="$warning_frame_p95_ms" \
  -v warning_gpu_us="$warning_gpu_us" \
  -v current_summary="$(relative_path "$CURRENT_SUMMARY")" \
  -v baseline_file="$(relative_path "$BASELINE_FILE")" '
  BEGIN {
    status = "pass"
    reason = "within_baseline"
    warning_status = "ok"
    if (baseline_status != "accepted") {
      status = "fail"
      reason = "baseline_not_accepted"
    } else if (report_v2_status != required_report_v2_status || scoped_status != required_scoped_status || resource_status != required_resource_status || memory_status != required_memory_status || legacy_error_scan != required_legacy_error_scan) {
      status = "fail"
      reason = "required_status_mismatch"
    } else if (historical_effective_draws + 0 < min_effective_draws + 0) {
      status = "fail"
      reason = "coverage_below_baseline"
    } else if (historical_upload_fail + 0 > max_upload_fail + 0) {
      status = "fail"
      reason = "upload_fail_regression"
    } else if (historical_fragmentation_pct + 0.0 > max_fragmentation_pct + 0.0) {
      status = "fail"
      reason = "fragmentation_regression"
    } else if (historical_draw_cmd_occupancy_pct + 0.0 > max_draw_cmd_occupancy_pct + 0.0) {
      status = "fail"
      reason = "draw_command_occupancy_regression"
    }
    if (warning_frame_p95_ms + 0.0 > warning_max_frame_p95_ms + 0.0 || warning_gpu_us + 0.0 > warning_max_gpu_us + 0.0) {
      warning_status = "warn"
    }
    printf("performance_baseline_governance status=%s reason=%s warning_status=%s baseline_id=%s report_v2_status=%s scoped_status=%s resource_status=%s memory_status=%s legacy_error_scan=%s historical_gpu_effective_draws=%s min_historical_gpu_effective_draws=%s historical_gpu_upload_fail=%s max_historical_gpu_upload_fail=%s historical_gpu_fragmentation_pct=%s max_historical_gpu_fragmentation_pct=%s historical_draw_cmd_occupancy_pct=%s max_historical_draw_cmd_occupancy_pct=%s warning_frame_p95_ms=%s warning_max_frame_p95_ms=%s warning_gpu_compositor_gpu_max_us=%s warning_max_gpu_compositor_gpu_max_us=%s current_summary=%s baseline_file=%s\n", status, reason, warning_status, baseline_id, report_v2_status, scoped_status, resource_status, memory_status, legacy_error_scan, historical_effective_draws, min_effective_draws, historical_upload_fail, max_upload_fail, historical_fragmentation_pct, max_fragmentation_pct, historical_draw_cmd_occupancy_pct, max_draw_cmd_occupancy_pct, warning_frame_p95_ms, warning_max_frame_p95_ms, warning_gpu_us, warning_max_gpu_us, current_summary, baseline_file)
    if (status != "pass") {
      exit 1
    }
  }
' > "$OUT_PATH" || {
  cat "$OUT_PATH" >&2 || true
  fail "performance baseline governance failed"
}

cat "$OUT_PATH"
