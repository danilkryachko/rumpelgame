#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/gpu_terrain_upload_pressure"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

FILL_DIR="$OUT_DIR/fill"
SUMMARY_PATH="$OUT_DIR/gpu-upload-pressure-summary.txt"
ALLOCATOR_SUMMARY_PATH="$OUT_DIR/gpu-upload-pressure-allocator-summary.txt"
SOURCE_FILL_SUMMARY="${RUMPELMC_GPU_UPLOAD_PRESSURE_SOURCE_FILL_SUMMARY:-}"
SOURCE_ALLOCATOR_SUMMARY="${RUMPELMC_GPU_UPLOAD_PRESSURE_SOURCE_ALLOCATOR_SUMMARY:-}"
REPEATS="${RUMPELMC_GPU_UPLOAD_PRESSURE_REPEATS:-1 2 4 8}"
REPORT_ONLY_REPEATS="${RUMPELMC_GPU_UPLOAD_PRESSURE_REPORT_ONLY_REPEATS-16}"
SERVER_VIEW_DISTANCE="${RUMPELMC_GPU_UPLOAD_PRESSURE_SERVER_VIEW_DISTANCE:-16}"
CLIENT_KEEP_CHUNK_DISTANCE="${RUMPELMC_GPU_UPLOAD_PRESSURE_CLIENT_KEEP_CHUNK_DISTANCE:-$SERVER_VIEW_DISTANCE}"
SETTLE_SEC="${RUMPELMC_GPU_UPLOAD_PRESSURE_SETTLE_SEC:-45.0}"
SMOKE_DELAY_SEC="${RUMPELMC_GPU_UPLOAD_PRESSURE_SMOKE_DELAY_SEC:-20.0}"

mkdir -p "$OUT_DIR"

fail() {
  echo "gpu_terrain_upload_pressure: $*" >&2
  exit 1
}

if [ -z "$SOURCE_FILL_SUMMARY" ]; then
  RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE="${RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE:-1}" \
    RUMPELMC_GODOT_RUST_EXT_PROFILE="${RUMPELMC_GODOT_RUST_EXT_PROFILE:-release}" \
    RUMPELMC_FILL_STRESS_REPEATS="$REPEATS" \
    RUMPELMC_FILL_STRESS_REPORT_ONLY_REPEATS="$REPORT_ONLY_REPEATS" \
    RUMPELMC_FILL_STRESS_SERVER_VIEW_DISTANCE="$SERVER_VIEW_DISTANCE" \
    RUMPELMC_FILL_STRESS_CLIENT_KEEP_CHUNK_DISTANCE="$CLIENT_KEEP_CHUNK_DISTANCE" \
    RUMPELMC_FILL_STRESS_SETTLE_SEC="$SETTLE_SEC" \
    RUMPELMC_FILL_STRESS_SMOKE_DELAY_SEC="$SMOKE_DELAY_SEC" \
    /bin/sh "$ROOT_DIR/scripts/gpu_terrain_fill_stress.sh" "$FILL_DIR"
  SOURCE_FILL_SUMMARY="$FILL_DIR/fill-stress-summary.txt"
fi

test -s "$SOURCE_FILL_SUMMARY" || fail "missing fill stress summary $SOURCE_FILL_SUMMARY"

if [ -z "$SOURCE_ALLOCATOR_SUMMARY" ]; then
  allocator_dir="$(dirname -- "$SOURCE_FILL_SUMMARY")"
  /bin/sh "$ROOT_DIR/scripts/gpu_terrain_allocator_stress_gate.sh" "$allocator_dir" "$ALLOCATOR_SUMMARY_PATH" >/dev/null
  SOURCE_ALLOCATOR_SUMMARY="$ALLOCATOR_SUMMARY_PATH"
fi

test -s "$SOURCE_ALLOCATOR_SUMMARY" || fail "missing allocator summary $SOURCE_ALLOCATOR_SUMMARY"

awk \
  -v fill_summary="$SOURCE_FILL_SUMMARY" \
  -v allocator_summary="$SOURCE_ALLOCATOR_SUMMARY" \
  -v repeats="$REPEATS" \
  -v report_only_repeats="$REPORT_ONLY_REPEATS" \
  -v server_view_distance="$SERVER_VIEW_DISTANCE" \
  -v client_keep_chunk_distance="$CLIENT_KEEP_CHUNK_DISTANCE" '
  function value_of(key,   i, prefix, value) {
    prefix = key "="
    for (i = 1; i <= NF; i++) {
      if (index($i, prefix) == 1) {
        value = substr($i, length(prefix) + 1)
        gsub(/^"/, "", value)
        gsub(/"$/, "", value)
        return value
      }
    }
    return ""
  }
  FILENAME == allocator_summary && $1 == "summary" {
    allocator_status = value_of("allocator_stress_gate_status")
    allocator_upload_fail = value_of("gpu_upload_fail") + 0
    allocator_capacity_fail = value_of("gpu_upload_fail_capacity") + 0
    allocator_fragmented_fail = value_of("gpu_upload_fail_fragmented") + 0
    allocator_fragmentation_pct = value_of("gpu_fragmentation_pct") + 0
    allocator_terrain_queue_max = value_of("terrain_queue_max_ms") + 0
  }
  FILENAME == fill_summary && $1 ~ /^repeat=/ {
    status = value_of("status")
    if (status == "pass") {
      pass_count++
      if (value_of("gpu_draw_repeat") + 0 > max_draw_repeat) max_draw_repeat = value_of("gpu_draw_repeat") + 0
      if (value_of("gpu_draws") + 0 > max_draws) max_draws = value_of("gpu_draws") + 0
      if (value_of("gpu_effective_draws") + 0 > max_effective_draws) max_effective_draws = value_of("gpu_effective_draws") + 0
      if (value_of("gpu_faces") + 0 > max_faces) max_faces = value_of("gpu_faces") + 0
      upload_fail += value_of("gpu_upload_fail") + 0
      upload_fail_capacity += value_of("gpu_upload_fail_capacity") + 0
      upload_fail_fragmented += value_of("gpu_upload_fail_fragmented") + 0
      if (value_of("gpu_free_ranges") + 0 > max_free_ranges) max_free_ranges = value_of("gpu_free_ranges") + 0
      if (value_of("gpu_fragmentation_pct") + 0 > max_fragmentation_pct) max_fragmentation_pct = value_of("gpu_fragmentation_pct") + 0
      if (value_of("terrain_queue_max_ms") + 0 > max_terrain_queue) max_terrain_queue = value_of("terrain_queue_max_ms") + 0
      if (value_of("process_wall_p95_ms") + 0 > max_process_wall_p95) max_process_wall_p95 = value_of("process_wall_p95_ms") + 0
      if (value_of("gpu_compositor_submit_max_ms") + 0 > max_gpu_submit) max_gpu_submit = value_of("gpu_compositor_submit_max_ms") + 0
    } else if (status == "failed") {
      failed_count++
    }
  }
  END {
    gate_status = "pass"
    if (pass_count == 0 || allocator_status != "pass" || upload_fail > 0 || upload_fail_capacity > 0 || upload_fail_fragmented > 0 || allocator_upload_fail > 0 || allocator_capacity_fail > 0 || allocator_fragmented_fail > 0) {
      gate_status = "fail"
    }
    printf("gpu_upload_pressure status=%s repeats=\"%s\" report_only_repeats=\"%s\" server_view_distance=%s client_keep_chunk_distance=%s pass_count=%d failed_report_only_count=%d max_draw_repeat=%d max_gpu_draws=%d max_gpu_effective_draws=%d max_gpu_faces=%d gpu_upload_fail=%d gpu_upload_fail_capacity=%d gpu_upload_fail_fragmented=%d max_gpu_free_ranges=%d max_gpu_fragmentation_pct=%.1f max_terrain_queue_ms=%.3f max_process_wall_p95_ms=%.3f max_gpu_compositor_submit_ms=%.3f allocator_status=%s allocator_fragmentation_pct=%.1f allocator_terrain_queue_max_ms=%.3f fill_summary=%s allocator_summary=%s\n", gate_status, repeats, report_only_repeats, server_view_distance, client_keep_chunk_distance, pass_count, failed_count, max_draw_repeat, max_draws, max_effective_draws, max_faces, upload_fail, upload_fail_capacity, upload_fail_fragmented, max_free_ranges, max_fragmentation_pct, max_terrain_queue, max_process_wall_p95, max_gpu_submit, allocator_status, allocator_fragmentation_pct, allocator_terrain_queue_max, fill_summary, allocator_summary)
    if (gate_status != "pass") {
      exit 1
    }
  }
' "$SOURCE_FILL_SUMMARY" "$SOURCE_ALLOCATOR_SUMMARY" > "$SUMMARY_PATH" || {
  cat "$SUMMARY_PATH" >&2 || true
  fail "GPU upload pressure gate failed"
}

cat "$SUMMARY_PATH"
echo "GPU upload pressure artifacts: $OUT_DIR"
