#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/gpu_repack_activation_preflight"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

SUMMARY_PATH="$OUT_DIR/gpu-repack-activation-preflight-summary.txt"
UPLOAD_PRESSURE_SUMMARY="${RUMPELMC_GPU_REPACK_PREFLIGHT_UPLOAD_PRESSURE_SUMMARY:-"$ROOT_DIR/logs/gpu_terrain_upload_pressure_smoke/gpu-upload-pressure-summary.txt"}"
LOAD_SCALING_SUMMARY="${RUMPELMC_GPU_REPACK_PREFLIGHT_LOAD_SCALING_SUMMARY:-"$ROOT_DIR/logs/gpu_terrain_load_scaling_radius16_summary_check/gpu-terrain-load-scaling-summary.txt"}"
MIN_FRAGMENTATION_TO_ACTIVATE="${RUMPELMC_GPU_REPACK_PREFLIGHT_MIN_FRAGMENTATION_TO_ACTIVATE:-10.0}"

mkdir -p "$OUT_DIR"

fail() {
  echo "gpu_repack_activation_preflight: $*" >&2
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

test -s "$UPLOAD_PRESSURE_SUMMARY" || fail "missing upload pressure summary $UPLOAD_PRESSURE_SUMMARY"
test -s "$LOAD_SCALING_SUMMARY" || fail "missing load scaling summary $LOAD_SCALING_SUMMARY"

upload_status="$(field_metric status "$UPLOAD_PRESSURE_SUMMARY")"
load_status="$(field_metric status "$LOAD_SCALING_SUMMARY")"
upload_fail="$(field_metric gpu_upload_fail "$UPLOAD_PRESSURE_SUMMARY")"
capacity_fail="$(field_metric gpu_upload_fail_capacity "$UPLOAD_PRESSURE_SUMMARY")"
fragmented_fail="$(field_metric gpu_upload_fail_fragmented "$UPLOAD_PRESSURE_SUMMARY")"
fragmentation_pct="$(field_metric max_gpu_fragmentation_pct "$UPLOAD_PRESSURE_SUMMARY")"
max_effective_draws="$(field_metric max_gpu_effective_draws "$UPLOAD_PRESSURE_SUMMARY")"
max_load_draws="$(field_metric max_gpu_draws "$LOAD_SCALING_SUMMARY")"
max_load_subchunks="$(field_metric max_gpu_subchunks "$LOAD_SCALING_SUMMARY")"
max_load_faces="$(field_metric max_gpu_faces "$LOAD_SCALING_SUMMARY")"

awk \
  -v upload_status="${upload_status:-fail}" \
  -v load_status="${load_status:-fail}" \
  -v upload_fail="${upload_fail:-0}" \
  -v capacity_fail="${capacity_fail:-0}" \
  -v fragmented_fail="${fragmented_fail:-0}" \
  -v fragmentation_pct="${fragmentation_pct:-0}" \
  -v max_effective_draws="${max_effective_draws:-0}" \
  -v max_load_draws="${max_load_draws:-0}" \
  -v max_load_subchunks="${max_load_subchunks:-0}" \
  -v max_load_faces="${max_load_faces:-0}" \
  -v min_fragmentation="$MIN_FRAGMENTATION_TO_ACTIVATE" \
  -v upload_summary="$UPLOAD_PRESSURE_SUMMARY" \
  -v load_summary="$LOAD_SCALING_SUMMARY" '
  BEGIN {
    status = "deferred"
    active_allowed = 0
    reason = "no_fragmentation_pressure"
    if (upload_status != "pass" || load_status != "pass") {
      status = "blocked"
      reason = "missing_clean_prerequisite"
    } else if (upload_fail > 0 || capacity_fail > 0 || fragmented_fail > 0) {
      status = "needs_design_review"
      reason = "upload_failure_pressure"
    } else if (fragmentation_pct + 0 >= min_fragmentation + 0) {
      status = "needs_design_review"
      reason = "fragmentation_pressure"
    }
    printf("gpu_repack_activation_preflight status=%s active_repack_allowed=%d reason=%s min_fragmentation_to_activate=%.1f upload_status=%s load_status=%s gpu_upload_fail=%d gpu_upload_fail_capacity=%d gpu_upload_fail_fragmented=%d max_gpu_fragmentation_pct=%.1f max_gpu_effective_draws=%d max_load_gpu_draws=%d max_load_gpu_subchunks=%d max_load_gpu_faces=%d upload_summary=%s load_summary=%s\n", status, active_allowed, reason, min_fragmentation, upload_status, load_status, upload_fail, capacity_fail, fragmented_fail, fragmentation_pct, max_effective_draws, max_load_draws, max_load_subchunks, max_load_faces, upload_summary, load_summary)
    if (status == "blocked") {
      exit 1
    }
  }
' > "$SUMMARY_PATH" || {
  cat "$SUMMARY_PATH" >&2 || true
  fail "GPU repack activation preflight failed"
}

cat "$SUMMARY_PATH"
echo "GPU repack activation preflight artifacts: $OUT_DIR"
