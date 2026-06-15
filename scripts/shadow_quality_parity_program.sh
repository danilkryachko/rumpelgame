#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/shadow_quality_parity_program"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

SUMMARY_PATH="$OUT_DIR/shadow-quality-parity-summary.txt"
PARITY_SUMMARY="${RUMPELMC_SHADOW_QUALITY_PARITY_SUMMARY:-"$ROOT_DIR/logs/gpu_native_shadow_resource_lifecycle_parity_20260614/parity-summary.txt"}"
NATIVE_PREFLIGHT_SUMMARY="${RUMPELMC_SHADOW_QUALITY_NATIVE_PREFLIGHT_SUMMARY:-"$ROOT_DIR/logs/gpu_native_shadow_prototype_preflight_current/gpu-native-shadow-prototype-preflight-summary.txt"}"
RADIUS_MATRIX_SUMMARY="${RUMPELMC_SHADOW_QUALITY_RADIUS_MATRIX_SUMMARY:-"$ROOT_DIR/logs/gpu_shadow_radius_matrix_wide/shadow-radius-matrix-summary.txt"}"
PROFILER_CAPTURE_PACK="${RUMPELMC_SHADOW_QUALITY_PROFILER_CAPTURE_PACK:-"$ROOT_DIR/logs/gpu_shadow_radius_matrix_wide/shadow-radius-profiler-capture-pack.txt"}"
REPORT_V2_SUMMARY="${RUMPELMC_SHADOW_QUALITY_REPORT_V2_SUMMARY:-"$ROOT_DIR/logs/gpu_terrain_report_v2_current/gpu-terrain-report-v2-summary.txt"}"

MAX_AVG_LUMA_DELTA="${RUMPELMC_SHADOW_QUALITY_MAX_AVG_LUMA_DELTA:-0.16}"
MAX_TERRAIN_LUMA_RANGE_DELTA="${RUMPELMC_SHADOW_QUALITY_MAX_TERRAIN_LUMA_RANGE_DELTA:-0.12}"
MAX_NATIVE_FALLBACK_DELTA="${RUMPELMC_SHADOW_QUALITY_MAX_NATIVE_FALLBACK_DELTA:-0.001}"
MIN_PARITY_CASES="${RUMPELMC_SHADOW_QUALITY_MIN_PARITY_CASES:-17}"
MIN_RADIUS_ROWS="${RUMPELMC_SHADOW_QUALITY_MIN_RADIUS_ROWS:-4}"
MIN_USABLE_RADIUS_ROWS="${RUMPELMC_SHADOW_QUALITY_MIN_USABLE_RADIUS_ROWS:-3}"

mkdir -p "$OUT_DIR"

fail() {
  echo "shadow_quality_parity_program: $*" >&2
  exit 1
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

case_field_metric() {
  case_name="$1"
  key="$2"
  path="$3"
  awk -v case_name="$case_name" -v key="$key" '
    $1 == "case=" case_name {
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

pair_delta_metric() {
  pair_name="$1"
  metric_name="$2"
  path="$3"
  awk -v pair_name="$pair_name" -v metric_name="$metric_name" '
    $1 == "pair=" pair_name {
      metric_prefix = metric_name "="
      for (i = 1; i <= NF; i++) {
        if (index($i, metric_prefix) == 1 && i + 1 <= NF && index($(i + 1), "delta=") == 1) {
          print substr($(i + 1), length("delta=") + 1)
          exit
        }
      }
    }
  ' "$path"
}

test -s "$PARITY_SUMMARY" || fail "missing parity summary $PARITY_SUMMARY"
test -s "$NATIVE_PREFLIGHT_SUMMARY" || fail "missing native shadow preflight summary $NATIVE_PREFLIGHT_SUMMARY"
test -s "$RADIUS_MATRIX_SUMMARY" || fail "missing shadow radius matrix summary $RADIUS_MATRIX_SUMMARY"
test -s "$PROFILER_CAPTURE_PACK" || fail "missing profiler capture pack $PROFILER_CAPTURE_PACK"
test -s "$REPORT_V2_SUMMARY" || fail "missing GPU report V2 summary $REPORT_V2_SUMMARY"

case_count="$(field_metric case_count "$PARITY_SUMMARY")"
native_case_requested="$(case_field_metric gpu-terrain-native-shadow-fallback-parity native_shadow_requested "$PARITY_SUMMARY")"
native_case_active="$(case_field_metric gpu-terrain-native-shadow-fallback-parity native_shadow_active "$PARITY_SUMMARY")"
native_case_fallback="$(case_field_metric gpu-terrain-native-shadow-fallback-parity native_shadow_fallback "$PARITY_SUMMARY")"
native_case_implemented="$(case_field_metric gpu-terrain-native-shadow-fallback-parity native_shadow_implemented "$PARITY_SUMMARY")"
native_case_resource_status="$(case_field_metric gpu-terrain-native-shadow-fallback-parity native_shadow_resource_status "$PARITY_SUMMARY")"
native_case_shadow_path="$(case_field_metric gpu-terrain-native-shadow-fallback-parity shadow_path "$PARITY_SUMMARY")"
native_case_gpu_frames="$(case_field_metric gpu-terrain-native-shadow-fallback-parity gpu_frames "$PARITY_SUMMARY")"
native_case_gpu_subchunks="$(case_field_metric gpu-terrain-native-shadow-fallback-parity gpu_subchunks "$PARITY_SUMMARY")"

native_delta="$(pair_delta_metric native_shadow_fallback avg_luma "$PARITY_SUMMARY")"
native_luma_range_delta="$(pair_delta_metric native_shadow_fallback terrain_luma_range "$PARITY_SUMMARY")"
lighting_shadow_delta="$(pair_delta_metric lighting_shadow avg_luma "$PARITY_SUMMARY")"
lighting_shadow_range_delta="$(pair_delta_metric lighting_shadow terrain_luma_range "$PARITY_SUMMARY")"
lighting_shadow_compact_delta="$(pair_delta_metric lighting_shadow_compact avg_luma "$PARITY_SUMMARY")"
lighting_low_angle_delta="$(pair_delta_metric lighting_low_angle avg_luma "$PARITY_SUMMARY")"
lighting_low_angle_range_delta="$(pair_delta_metric lighting_low_angle terrain_luma_range "$PARITY_SUMMARY")"
lighting_low_angle_compact_delta="$(pair_delta_metric lighting_low_angle_compact avg_luma "$PARITY_SUMMARY")"

preflight_status="$(field_metric status "$NATIVE_PREFLIGHT_SUMMARY")"
preflight_allowed="$(field_metric active_prototype_allowed "$NATIVE_PREFLIGHT_SUMMARY")"
preflight_reason="$(field_metric reason "$NATIVE_PREFLIGHT_SUMMARY")"

report_v2_status="$(field_metric status "$REPORT_V2_SUMMARY")"
warning_fps_p05="$(field_metric warning_fps_p05 "$REPORT_V2_SUMMARY")"
warning_frame_p95_ms="$(field_metric warning_frame_p95_ms "$REPORT_V2_SUMMARY")"

radius_stats="$(
  awk '
    $1 ~ /^radius=/ {
      rows++
      if ($2 == "status=pass") pass_rows++
      for (i = 1; i <= NF; i++) {
        split($i, kv, "=")
        if (kv[1] == "shadow_normal_total_savings_evidence" && kv[2] == "usable") usable_rows++
        if (kv[1] == "shadow_normal_total_savings_evidence" && kv[2] == "rejected") rejected_rows++
        if (kv[1] == "compact_shadow_proxy" && kv[2] + 0 > max_compact_shadow_proxy) max_compact_shadow_proxy = kv[2] + 0
        if (kv[1] == "compact_shadow_normals_saved" && kv[2] + 0 > max_compact_shadow_normals_saved) max_compact_shadow_normals_saved = kv[2] + 0
        if (kv[1] == "full_cpu_proxy" && kv[2] + 0 > max_full_cpu_proxy) max_full_cpu_proxy = kv[2] + 0
        if (kv[1] == "compact_cpu_proxy" && kv[2] + 0 > max_compact_cpu_proxy) max_compact_cpu_proxy = kv[2] + 0
        if (kv[1] == "full_mesh_max_ms" && kv[2] + 0 > max_full_mesh_ms) max_full_mesh_ms = kv[2] + 0
        if (kv[1] == "compact_mesh_max_ms" && kv[2] + 0 > max_compact_mesh_ms) max_compact_mesh_ms = kv[2] + 0
      }
    }
    END {
      printf("rows=%d pass_rows=%d usable_rows=%d rejected_rows=%d max_compact_shadow_proxy=%d max_compact_shadow_normals_saved=%d max_full_cpu_proxy=%d max_compact_cpu_proxy=%d max_full_mesh_ms=%.2f max_compact_mesh_ms=%.2f\n", rows, pass_rows, usable_rows, rejected_rows, max_compact_shadow_proxy, max_compact_shadow_normals_saved, max_full_cpu_proxy, max_compact_cpu_proxy, max_full_mesh_ms, max_compact_mesh_ms)
    }
  ' "$RADIUS_MATRIX_SUMMARY"
)"

capture_pack_status="$(field_metric capture_pack_status "$PROFILER_CAPTURE_PACK")"
capture_pack_rows="$(field_metric rows "$PROFILER_CAPTURE_PACK")"

awk \
  -v case_count="${case_count:-0}" \
  -v min_parity_cases="$MIN_PARITY_CASES" \
  -v native_case_requested="${native_case_requested:-missing}" \
  -v native_case_active="${native_case_active:-missing}" \
  -v native_case_fallback="${native_case_fallback:-missing}" \
  -v native_case_implemented="${native_case_implemented:-missing}" \
  -v native_case_resource_status="${native_case_resource_status:-missing}" \
  -v native_case_shadow_path="${native_case_shadow_path:-missing}" \
  -v native_case_gpu_frames="${native_case_gpu_frames:-0}" \
  -v native_case_gpu_subchunks="${native_case_gpu_subchunks:-0}" \
  -v native_delta="${native_delta:-999}" \
  -v native_luma_range_delta="${native_luma_range_delta:-999}" \
  -v lighting_shadow_delta="${lighting_shadow_delta:-999}" \
  -v lighting_shadow_range_delta="${lighting_shadow_range_delta:-999}" \
  -v lighting_shadow_compact_delta="${lighting_shadow_compact_delta:-999}" \
  -v lighting_low_angle_delta="${lighting_low_angle_delta:-999}" \
  -v lighting_low_angle_range_delta="${lighting_low_angle_range_delta:-999}" \
  -v lighting_low_angle_compact_delta="${lighting_low_angle_compact_delta:-999}" \
  -v max_avg_luma_delta="$MAX_AVG_LUMA_DELTA" \
  -v max_terrain_luma_range_delta="$MAX_TERRAIN_LUMA_RANGE_DELTA" \
  -v max_native_fallback_delta="$MAX_NATIVE_FALLBACK_DELTA" \
  -v preflight_status="${preflight_status:-blocked}" \
  -v preflight_allowed="${preflight_allowed:-1}" \
  -v preflight_reason="${preflight_reason:-unknown}" \
  -v radius_stats="$radius_stats" \
  -v min_radius_rows="$MIN_RADIUS_ROWS" \
  -v min_usable_radius_rows="$MIN_USABLE_RADIUS_ROWS" \
  -v capture_pack_status="${capture_pack_status:-missing}" \
  -v capture_pack_rows="${capture_pack_rows:-0}" \
  -v report_v2_status="${report_v2_status:-fail}" \
  -v warning_fps_p05="${warning_fps_p05:-0}" \
  -v warning_frame_p95_ms="${warning_frame_p95_ms:-0}" \
  -v parity_summary="$PARITY_SUMMARY" \
  -v native_preflight_summary="$NATIVE_PREFLIGHT_SUMMARY" \
  -v radius_matrix_summary="$RADIUS_MATRIX_SUMMARY" \
  -v profiler_capture_pack="$PROFILER_CAPTURE_PACK" \
  -v report_v2_summary="$REPORT_V2_SUMMARY" '
  function stat_value(key,   parts, i, kv) {
    split(radius_stats, parts, " ")
    for (i in parts) {
      split(parts[i], kv, "=")
      if (kv[1] == key) {
        return kv[2]
      }
    }
    return 0
  }
  BEGIN {
    radius_rows = stat_value("rows") + 0
    radius_pass_rows = stat_value("pass_rows") + 0
    radius_usable_rows = stat_value("usable_rows") + 0
    radius_rejected_rows = stat_value("rejected_rows") + 0
    max_compact_shadow_proxy = stat_value("max_compact_shadow_proxy") + 0
    max_compact_shadow_normals_saved = stat_value("max_compact_shadow_normals_saved") + 0
    max_full_cpu_proxy = stat_value("max_full_cpu_proxy") + 0
    max_compact_cpu_proxy = stat_value("max_compact_cpu_proxy") + 0
    max_full_mesh_ms = stat_value("max_full_mesh_ms") + 0
    max_compact_mesh_ms = stat_value("max_compact_mesh_ms") + 0

    status = "pass"
    reason = "ok"
    active_native_comparison = "deferred"

    if (case_count + 0 < min_parity_cases + 0) {
      status = "fail"
      reason = "missing_parity_cases"
    } else if (!(native_case_requested == "1" && native_case_active == "0" && native_case_fallback == "1" && native_case_implemented == "0" && native_case_resource_status == "disabled" && native_case_shadow_path == "godot_proxy" && native_case_gpu_frames + 0 > 0 && native_case_gpu_subchunks + 0 > 0)) {
      status = "fail"
      reason = "native_fallback_case_not_clean"
    } else if (native_delta + 0 > max_native_fallback_delta + 0 || native_luma_range_delta + 0 > max_native_fallback_delta + 0) {
      status = "fail"
      reason = "native_fallback_visual_delta"
    } else if (lighting_shadow_delta + 0 > max_avg_luma_delta + 0 || lighting_shadow_range_delta + 0 > max_terrain_luma_range_delta + 0) {
      status = "fail"
      reason = "lighting_shadow_delta"
    } else if (lighting_shadow_compact_delta + 0 > max_native_fallback_delta + 0) {
      status = "fail"
      reason = "compact_shadow_delta"
    } else if (lighting_low_angle_delta + 0 > max_avg_luma_delta + 0 || lighting_low_angle_range_delta + 0 > max_terrain_luma_range_delta + 0) {
      status = "fail"
      reason = "low_angle_delta"
    } else if (lighting_low_angle_compact_delta + 0 > max_native_fallback_delta + 0) {
      status = "fail"
      reason = "low_angle_compact_delta"
    } else if (!(preflight_status == "deferred" && preflight_allowed + 0 == 0)) {
      status = "fail"
      reason = "native_preflight_not_deferred"
    } else if (radius_rows < min_radius_rows || radius_pass_rows != radius_rows || radius_usable_rows < min_usable_radius_rows) {
      status = "fail"
      reason = "shadow_radius_matrix_not_clean"
    } else if (!(capture_pack_status == "pending_external_profiler" && capture_pack_rows + 0 >= radius_rows)) {
      status = "fail"
      reason = "profiler_capture_pack_not_pending"
    } else if (report_v2_status != "pass") {
      status = "fail"
      reason = "report_v2_not_clean"
    }

    printf("shadow_quality_parity_program status=%s reason=%s active_native_comparison=%s active_native_reason=%s parity_case_count=%d native_fallback_avg_luma_delta=%.4f native_fallback_luma_range_delta=%.4f lighting_shadow_avg_luma_delta=%.4f lighting_shadow_luma_range_delta=%.4f lighting_shadow_compact_delta=%.4f lighting_low_angle_avg_luma_delta=%.4f lighting_low_angle_luma_range_delta=%.4f lighting_low_angle_compact_delta=%.4f radius_rows=%d radius_usable_rows=%d radius_rejected_rows=%d max_compact_shadow_proxy=%d max_compact_shadow_normals_saved=%d max_full_cpu_proxy=%d max_compact_cpu_proxy=%d max_full_mesh_ms=%.2f max_compact_mesh_ms=%.2f profiler_status=%s profiler_rows=%d fps_status=warning_only warning_fps_p05=%.3f warning_frame_p95_ms=%.3f parity_summary=%s native_preflight_summary=%s radius_matrix_summary=%s profiler_capture_pack=%s report_v2_summary=%s\n", status, reason, active_native_comparison, preflight_reason, case_count, native_delta, native_luma_range_delta, lighting_shadow_delta, lighting_shadow_range_delta, lighting_shadow_compact_delta, lighting_low_angle_delta, lighting_low_angle_range_delta, lighting_low_angle_compact_delta, radius_rows, radius_usable_rows, radius_rejected_rows, max_compact_shadow_proxy, max_compact_shadow_normals_saved, max_full_cpu_proxy, max_compact_cpu_proxy, max_full_mesh_ms, max_compact_mesh_ms, capture_pack_status, capture_pack_rows, warning_fps_p05, warning_frame_p95_ms, parity_summary, native_preflight_summary, radius_matrix_summary, profiler_capture_pack, report_v2_summary)
    if (status != "pass") {
      exit 1
    }
  }
' > "$SUMMARY_PATH" || {
  cat "$SUMMARY_PATH" >&2 || true
  fail "shadow quality parity program failed"
}

cat "$SUMMARY_PATH"
echo "Shadow quality parity artifacts: $OUT_DIR"
