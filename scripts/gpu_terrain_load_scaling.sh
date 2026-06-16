#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/gpu_terrain_load_scaling"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

SUMMARY_PATH="$OUT_DIR/gpu-terrain-load-scaling-summary.txt"
SOURCE_SUMMARY="${RUMPELMC_GPU_LOAD_SCALING_SOURCE_SUMMARY:-}"
MIN_GPU_SUBCHUNKS="${RUMPELMC_GPU_LOAD_SCALING_MIN_GPU_SUBCHUNKS:-2000}"
MIN_GPU_DRAWS="${RUMPELMC_GPU_LOAD_SCALING_MIN_GPU_DRAWS:-2000}"
MIN_GPU_FACES="${RUMPELMC_GPU_LOAD_SCALING_MIN_GPU_FACES:-3000}"
MIN_DRAW_CMD_OCCUPANCY_PCT="${RUMPELMC_GPU_LOAD_SCALING_MIN_DRAW_CMD_OCCUPANCY_PCT:-25.0}"

mkdir -p "$OUT_DIR"

fail() {
  echo "gpu_terrain_load_scaling: $*" >&2
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

if [ -z "$SOURCE_SUMMARY" ]; then
  resident_dir="$OUT_DIR/resident-set-growth"
  RUMPELMC_RESIDENT_SET_MIN_GPU_DRAWS="$MIN_GPU_DRAWS" \
    /bin/sh "$ROOT_DIR/scripts/world_streaming_resident_set_growth.sh" "$resident_dir"
  SOURCE_SUMMARY="$resident_dir/resident-set-growth-summary.txt"
fi

test -s "$SOURCE_SUMMARY" || fail "missing resident-set summary $SOURCE_SUMMARY"

status="$(field_metric status "$SOURCE_SUMMARY")"
source_case_set="$(field_metric case_set "$SOURCE_SUMMARY")"
terrain_pressure_fixture="$(field_metric terrain_pressure_fixture "$SOURCE_SUMMARY")"
max_subchunks="$(field_metric max_gpu_subchunks "$SOURCE_SUMMARY")"
max_draws="$(field_metric max_gpu_draws "$SOURCE_SUMMARY")"
max_faces="$(field_metric max_gpu_faces "$SOURCE_SUMMARY")"
draw_cmd_bytes="$(field_metric max_gpu_draw_cmd_bytes "$SOURCE_SUMMARY")"
draw_cmd_capacity_bytes="$(field_metric max_gpu_draw_cmd_capacity_bytes "$SOURCE_SUMMARY")"
terrain_queue_max="$(field_metric max_terrain_queue_ms "$SOURCE_SUMMARY")"
process_wall_p95="$(field_metric max_process_wall_p95_ms "$SOURCE_SUMMARY")"
gpu_submit_max="$(field_metric max_gpu_compositor_submit_ms "$SOURCE_SUMMARY")"
gpu_uploads="$(field_metric max_gpu_uploads "$SOURCE_SUMMARY")"
gpu_upload_fail="$(field_metric gpu_upload_fail "$SOURCE_SUMMARY")"
gpu_upload_fail_capacity="$(field_metric gpu_upload_fail_capacity "$SOURCE_SUMMARY")"
gpu_upload_fail_fragmented="$(field_metric gpu_upload_fail_fragmented "$SOURCE_SUMMARY")"
gpu_upload_stage_pool_enabled="$(field_metric max_gpu_upload_stage_pool_enabled "$SOURCE_SUMMARY")"
gpu_upload_stage_pool_entries="$(field_metric max_gpu_upload_stage_pool_entries "$SOURCE_SUMMARY")"
gpu_upload_stage_pool_bytes="$(field_metric max_gpu_upload_stage_pool_bytes "$SOURCE_SUMMARY")"
gpu_upload_stage_pba_creates="$(field_metric max_gpu_upload_stage_pba_creates "$SOURCE_SUMMARY")"
gpu_upload_stage_pba_reuses="$(field_metric max_gpu_upload_stage_pba_reuses "$SOURCE_SUMMARY")"
terrain_pressure_fixture_block_id="$(field_metric max_terrain_pressure_fixture_block_id "$SOURCE_SUMMARY")"
terrain_pressure_fixture_blocks="$(field_metric max_terrain_pressure_fixture_blocks "$SOURCE_SUMMARY")"
terrain_pressure_fixture_dirty_observed="$(field_metric max_terrain_pressure_fixture_dirty_observed "$SOURCE_SUMMARY")"
transparent_requested="$(field_metric max_transparent_requested "$SOURCE_SUMMARY")"
transparent_active="$(field_metric max_transparent_active "$SOURCE_SUMMARY")"
transparent_fallback="$(field_metric max_transparent_fallback "$SOURCE_SUMMARY")"
transparent_blocks="$(field_metric max_transparent_blocks "$SOURCE_SUMMARY")"
transparent_faces="$(field_metric max_transparent_faces "$SOURCE_SUMMARY")"
transparent_draws="$(field_metric max_transparent_draws "$SOURCE_SUMMARY")"
transparent_subchunks="$(field_metric max_transparent_subchunks "$SOURCE_SUMMARY")"

awk \
  -v status="${status:-fail}" \
  -v source_case_set="${source_case_set:-unknown}" \
  -v terrain_pressure_fixture="${terrain_pressure_fixture:-none}" \
  -v max_subchunks="${max_subchunks:-0}" \
  -v max_draws="${max_draws:-0}" \
  -v max_faces="${max_faces:-0}" \
  -v draw_cmd_bytes="${draw_cmd_bytes:-0}" \
  -v draw_cmd_capacity_bytes="${draw_cmd_capacity_bytes:-0}" \
  -v terrain_queue_max="${terrain_queue_max:-0}" \
  -v process_wall_p95="${process_wall_p95:-0}" \
  -v gpu_submit_max="${gpu_submit_max:-0}" \
  -v gpu_uploads="${gpu_uploads:-0}" \
  -v gpu_upload_fail="${gpu_upload_fail:-0}" \
  -v gpu_upload_fail_capacity="${gpu_upload_fail_capacity:-0}" \
  -v gpu_upload_fail_fragmented="${gpu_upload_fail_fragmented:-0}" \
  -v gpu_upload_stage_pool_enabled="${gpu_upload_stage_pool_enabled:-0}" \
  -v gpu_upload_stage_pool_entries="${gpu_upload_stage_pool_entries:-0}" \
  -v gpu_upload_stage_pool_bytes="${gpu_upload_stage_pool_bytes:-0}" \
  -v gpu_upload_stage_pba_creates="${gpu_upload_stage_pba_creates:-0}" \
  -v gpu_upload_stage_pba_reuses="${gpu_upload_stage_pba_reuses:-0}" \
  -v terrain_pressure_fixture_block_id="${terrain_pressure_fixture_block_id:-0}" \
  -v terrain_pressure_fixture_blocks="${terrain_pressure_fixture_blocks:-0}" \
  -v terrain_pressure_fixture_dirty_observed="${terrain_pressure_fixture_dirty_observed:-0}" \
  -v transparent_requested="${transparent_requested:-0}" \
  -v transparent_active="${transparent_active:-0}" \
  -v transparent_fallback="${transparent_fallback:-0}" \
  -v transparent_blocks="${transparent_blocks:-0}" \
  -v transparent_faces="${transparent_faces:-0}" \
  -v transparent_draws="${transparent_draws:-0}" \
  -v transparent_subchunks="${transparent_subchunks:-0}" \
  -v min_subchunks="$MIN_GPU_SUBCHUNKS" \
  -v min_draws="$MIN_GPU_DRAWS" \
  -v min_faces="$MIN_GPU_FACES" \
  -v min_occupancy="$MIN_DRAW_CMD_OCCUPANCY_PCT" \
  -v source_summary="$SOURCE_SUMMARY" '
  BEGIN {
    occupancy = 0.0
    headroom = draw_cmd_capacity_bytes - draw_cmd_bytes
    if (draw_cmd_capacity_bytes > 0) {
      occupancy = (draw_cmd_bytes / draw_cmd_capacity_bytes) * 100.0
    }
    gate_status = "pass"
    if (status != "pass" || max_subchunks < min_subchunks || max_draws < min_draws || max_faces < min_faces || occupancy < min_occupancy || gpu_upload_fail > 0 || gpu_upload_fail_capacity > 0 || gpu_upload_fail_fragmented > 0) {
      gate_status = "fail"
    }
    printf("gpu_terrain_load_scaling status=%s source_status=%s source_case_set=%s terrain_pressure_fixture=%s terrain_pressure_fixture_block_id=%d min_gpu_subchunks=%d min_gpu_draws=%d min_gpu_faces=%d min_draw_cmd_occupancy_pct=%.1f max_gpu_subchunks=%d max_gpu_draws=%d max_gpu_faces=%d max_gpu_draw_cmd_bytes=%d max_gpu_draw_cmd_capacity_bytes=%d gpu_draw_cmd_occupancy_pct=%.3f gpu_draw_cmd_headroom_bytes=%d max_terrain_queue_ms=%.3f max_process_wall_p95_ms=%.3f max_gpu_compositor_submit_ms=%.3f max_gpu_uploads=%d gpu_upload_fail=%d gpu_upload_fail_capacity=%d gpu_upload_fail_fragmented=%d gpu_upload_stage_pool_enabled=%d gpu_upload_stage_pool_entries=%d gpu_upload_stage_pool_bytes=%d gpu_upload_stage_pba_creates=%d gpu_upload_stage_pba_reuses=%d terrain_pressure_fixture_blocks=%d terrain_pressure_fixture_dirty_observed=%d transparent_requested=%d transparent_active=%d transparent_fallback=%d transparent_blocks=%d transparent_faces=%d transparent_draws=%d transparent_subchunks=%d source_summary=%s\n", gate_status, status, source_case_set, terrain_pressure_fixture, terrain_pressure_fixture_block_id, min_subchunks, min_draws, min_faces, min_occupancy, max_subchunks, max_draws, max_faces, draw_cmd_bytes, draw_cmd_capacity_bytes, occupancy, headroom, terrain_queue_max, process_wall_p95, gpu_submit_max, gpu_uploads, gpu_upload_fail, gpu_upload_fail_capacity, gpu_upload_fail_fragmented, gpu_upload_stage_pool_enabled, gpu_upload_stage_pool_entries, gpu_upload_stage_pool_bytes, gpu_upload_stage_pba_creates, gpu_upload_stage_pba_reuses, terrain_pressure_fixture_blocks, terrain_pressure_fixture_dirty_observed, transparent_requested, transparent_active, transparent_fallback, transparent_blocks, transparent_faces, transparent_draws, transparent_subchunks, source_summary)
    if (gate_status != "pass") {
      exit 1
    }
  }
' > "$SUMMARY_PATH" || {
  cat "$SUMMARY_PATH" >&2 || true
  fail "GPU terrain load scaling gate failed"
}

cat "$SUMMARY_PATH"
echo "GPU terrain load scaling artifacts: $OUT_DIR"
