#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/shadow_proxy_retirement_plan"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

SUMMARY_PATH="$OUT_DIR/shadow-proxy-retirement-summary.txt"
SHADOW_QUALITY_SUMMARY="${RUMPELMC_SHADOW_PROXY_RETIREMENT_QUALITY_SUMMARY:-"$ROOT_DIR/logs/shadow_quality_parity_program_current/shadow-quality-parity-summary.txt"}"
NATIVE_PREFLIGHT_SUMMARY="${RUMPELMC_SHADOW_PROXY_RETIREMENT_NATIVE_PREFLIGHT_SUMMARY:-"$ROOT_DIR/logs/gpu_native_shadow_prototype_preflight_current/gpu-native-shadow-prototype-preflight-summary.txt"}"
RADIUS_MATRIX_SUMMARY="${RUMPELMC_SHADOW_PROXY_RETIREMENT_RADIUS_MATRIX_SUMMARY:-"$ROOT_DIR/logs/gpu_shadow_radius_matrix_wide/shadow-radius-matrix-summary.txt"}"
PROFILER_CAPTURE_PACK="${RUMPELMC_SHADOW_PROXY_RETIREMENT_PROFILER_CAPTURE_PACK:-"$ROOT_DIR/logs/gpu_shadow_radius_matrix_wide/shadow-radius-profiler-capture-pack.txt"}"

mkdir -p "$OUT_DIR"

fail() {
  echo "shadow_proxy_retirement_plan: $*" >&2
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

test -s "$SHADOW_QUALITY_SUMMARY" || fail "missing shadow quality summary $SHADOW_QUALITY_SUMMARY"
test -s "$NATIVE_PREFLIGHT_SUMMARY" || fail "missing native-shadow preflight summary $NATIVE_PREFLIGHT_SUMMARY"
test -s "$RADIUS_MATRIX_SUMMARY" || fail "missing shadow radius matrix summary $RADIUS_MATRIX_SUMMARY"
test -s "$PROFILER_CAPTURE_PACK" || fail "missing profiler capture pack $PROFILER_CAPTURE_PACK"

quality_status="$(field_metric status "$SHADOW_QUALITY_SUMMARY")"
active_native_comparison="$(field_metric active_native_comparison "$SHADOW_QUALITY_SUMMARY")"
quality_profiler_status="$(field_metric profiler_status "$SHADOW_QUALITY_SUMMARY")"
native_fallback_delta="$(field_metric native_fallback_avg_luma_delta "$SHADOW_QUALITY_SUMMARY")"
lighting_shadow_delta="$(field_metric lighting_shadow_avg_luma_delta "$SHADOW_QUALITY_SUMMARY")"
radius_rows="$(field_metric radius_rows "$SHADOW_QUALITY_SUMMARY")"
radius_usable_rows="$(field_metric radius_usable_rows "$SHADOW_QUALITY_SUMMARY")"
max_compact_shadow_proxy="$(field_metric max_compact_shadow_proxy "$SHADOW_QUALITY_SUMMARY")"
max_compact_shadow_normals_saved="$(field_metric max_compact_shadow_normals_saved "$SHADOW_QUALITY_SUMMARY")"
preflight_status="$(field_metric status "$NATIVE_PREFLIGHT_SUMMARY")"
preflight_allowed="$(field_metric active_prototype_allowed "$NATIVE_PREFLIGHT_SUMMARY")"
preflight_reason="$(field_metric reason "$NATIVE_PREFLIGHT_SUMMARY")"
preflight_readiness_fields="$(field_metric fallback_readiness_fields "$NATIVE_PREFLIGHT_SUMMARY")"
preflight_readiness_status="$(field_metric fallback_readiness_status "$NATIVE_PREFLIGHT_SUMMARY")"
preflight_readiness_errors="$(field_metric fallback_readiness_errors "$NATIVE_PREFLIGHT_SUMMARY")"
capture_pack_status="$(field_metric capture_pack_status "$PROFILER_CAPTURE_PACK")"

radius_current_proxy="$(
  awk '
    $1 ~ /^radius=/ {
      for (i = 1; i <= NF; i++) {
        split($i, kv, "=")
        if (kv[1] == "full_cpu_proxy" && kv[2] + 0 > max_full_cpu_proxy) max_full_cpu_proxy = kv[2] + 0
        if (kv[1] == "compact_cpu_proxy" && kv[2] + 0 > max_compact_cpu_proxy) max_compact_cpu_proxy = kv[2] + 0
        if (kv[1] == "compact_shadow_proxy" && kv[2] + 0 > max_compact_shadow_proxy) max_compact_shadow_proxy = kv[2] + 0
        if (kv[1] == "compact_shadow_normals_saved" && kv[2] + 0 > max_compact_shadow_normals_saved) max_compact_shadow_normals_saved = kv[2] + 0
      }
    }
    END {
      printf("max_full_cpu_proxy=%d max_compact_cpu_proxy=%d max_compact_shadow_proxy=%d max_compact_shadow_normals_saved=%d\n", max_full_cpu_proxy, max_compact_cpu_proxy, max_compact_shadow_proxy, max_compact_shadow_normals_saved)
    }
  ' "$RADIUS_MATRIX_SUMMARY"
)"

awk \
  -v quality_status="${quality_status:-fail}" \
  -v active_native_comparison="${active_native_comparison:-missing}" \
  -v quality_profiler_status="${quality_profiler_status:-missing}" \
  -v native_fallback_delta="${native_fallback_delta:-999}" \
  -v lighting_shadow_delta="${lighting_shadow_delta:-999}" \
  -v radius_rows="${radius_rows:-0}" \
  -v radius_usable_rows="${radius_usable_rows:-0}" \
  -v max_compact_shadow_proxy="${max_compact_shadow_proxy:-0}" \
  -v max_compact_shadow_normals_saved="${max_compact_shadow_normals_saved:-0}" \
  -v preflight_status="${preflight_status:-blocked}" \
  -v preflight_allowed="${preflight_allowed:-1}" \
  -v preflight_reason="${preflight_reason:-unknown}" \
  -v preflight_readiness_fields="${preflight_readiness_fields:-missing}" \
  -v preflight_readiness_status="${preflight_readiness_status:-missing}" \
  -v preflight_readiness_errors="${preflight_readiness_errors:-999}" \
  -v capture_pack_status="${capture_pack_status:-missing}" \
  -v radius_current_proxy="$radius_current_proxy" \
  -v shadow_quality_summary="$SHADOW_QUALITY_SUMMARY" \
  -v native_preflight_summary="$NATIVE_PREFLIGHT_SUMMARY" \
  -v radius_matrix_summary="$RADIUS_MATRIX_SUMMARY" \
  -v profiler_capture_pack="$PROFILER_CAPTURE_PACK" '
  function stat_value(key,   parts, i, kv) {
    split(radius_current_proxy, parts, " ")
    for (i in parts) {
      split(parts[i], kv, "=")
      if (kv[1] == key) {
        return kv[2]
      }
    }
    return 0
  }
  BEGIN {
    max_full_cpu_proxy = stat_value("max_full_cpu_proxy") + 0
    max_compact_cpu_proxy = stat_value("max_compact_cpu_proxy") + 0
    max_radius_compact_shadow_proxy = stat_value("max_compact_shadow_proxy") + 0
    max_radius_compact_shadow_normals_saved = stat_value("max_compact_shadow_normals_saved") + 0

    status = "deferred"
    retirement_allowed = 0
    reason = "native_shadow_not_active"
    requires_active_native_capture = 1
    requires_external_profiler = 1
    requires_rollback = 1

    if (quality_status != "pass") {
      status = "blocked"
      reason = "shadow_quality_not_clean"
    } else if (!(active_native_comparison == "deferred" && preflight_status == "deferred" && preflight_allowed + 0 == 0)) {
      status = "needs_manual_review"
      reason = "active_native_state_changed"
    } else if (!(preflight_readiness_fields == "present" && preflight_readiness_status == "disabled_clean" && preflight_readiness_errors + 0 == 0)) {
      status = "blocked"
      reason = "native_preflight_readiness_not_clean"
    } else if (!(quality_profiler_status == "pending_external_profiler" && capture_pack_status == "pending_external_profiler")) {
      status = "blocked"
      reason = "profiler_state_not_pending"
    } else if (max_full_cpu_proxy <= 0 || max_compact_cpu_proxy <= 0 || max_radius_compact_shadow_proxy <= 0 || max_radius_compact_shadow_normals_saved <= 0) {
      status = "blocked"
      reason = "current_proxy_evidence_missing"
    }

    printf("shadow_proxy_retirement_plan status=%s retirement_allowed=%d reason=%s active_native_comparison=%s native_preflight_status=%s native_preflight_reason=%s native_preflight_readiness_fields=%s native_preflight_readiness_status=%s native_preflight_readiness_errors=%d requires_active_native_capture=%d requires_external_profiler=%d requires_godot_proxy_rollback=%d quality_status=%s profiler_status=%s native_fallback_avg_luma_delta=%.4f lighting_shadow_avg_luma_delta=%.4f radius_rows=%d radius_usable_rows=%d max_full_cpu_proxy=%d max_compact_cpu_proxy=%d max_compact_shadow_proxy=%d max_compact_shadow_normals_saved=%d shadow_quality_summary=%s native_preflight_summary=%s radius_matrix_summary=%s profiler_capture_pack=%s\n", status, retirement_allowed, reason, active_native_comparison, preflight_status, preflight_reason, preflight_readiness_fields, preflight_readiness_status, preflight_readiness_errors, requires_active_native_capture, requires_external_profiler, requires_rollback, quality_status, quality_profiler_status, native_fallback_delta, lighting_shadow_delta, radius_rows, radius_usable_rows, max_full_cpu_proxy, max_compact_cpu_proxy, max_radius_compact_shadow_proxy, max_radius_compact_shadow_normals_saved, shadow_quality_summary, native_preflight_summary, radius_matrix_summary, profiler_capture_pack)
    if (status == "blocked") {
      exit 1
    }
  }
' > "$SUMMARY_PATH" || {
  cat "$SUMMARY_PATH" >&2 || true
  fail "shadow proxy retirement plan failed"
}

cat "$SUMMARY_PATH"
echo "Shadow proxy retirement artifacts: $OUT_DIR"
