#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/world_streaming_resident_set_growth"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

WORKLOAD_DIR="$OUT_DIR/workload"
SUMMARY_PATH="$OUT_DIR/resident-set-growth-summary.txt"
SERVER_VIEW_DISTANCE="${RUMPELMC_RESIDENT_SET_SERVER_VIEW_DISTANCE:-16}"
CLIENT_KEEP_CHUNK_DISTANCE="${RUMPELMC_RESIDENT_SET_CLIENT_KEEP_CHUNK_DISTANCE:-$SERVER_VIEW_DISTANCE}"
SMOKE_DELAY_SEC="${RUMPELMC_RESIDENT_SET_SMOKE_DELAY_SEC:-20.0}"
TARGET_FPS="${RUMPELMC_RESIDENT_SET_TARGET_FPS:-150}"
MIN_GPU_DRAWS="${RUMPELMC_RESIDENT_SET_MIN_GPU_DRAWS:-1500}"
SERVER_CHUNKS_PER_UPDATE="${RUMPELMC_RESIDENT_SET_SERVER_CHUNKS_PER_UPDATE:-${RUMPELMC_WORKLOAD_MATRIX_SERVER_CHUNKS_PER_UPDATE:-64}}"
CASE_SET="${RUMPELMC_RESIDENT_SET_CASE_SET:-heavy}"
TERRAIN_PRESSURE_FIXTURE="${RUMPELMC_RESIDENT_SET_TERRAIN_PRESSURE_FIXTURE:-none}"
TERRAIN_PRESSURE_FIXTURE_CHUNK_COLUMNS="${RUMPELMC_RESIDENT_SET_TERRAIN_PRESSURE_FIXTURE_CHUNK_COLUMNS:-16}"
TERRAIN_PRESSURE_FIXTURE_CHUNK_ROWS="${RUMPELMC_RESIDENT_SET_TERRAIN_PRESSURE_FIXTURE_CHUNK_ROWS:-12}"
TERRAIN_PRESSURE_FIXTURE_CHUNK_RADIUS="${RUMPELMC_RESIDENT_SET_TERRAIN_PRESSURE_FIXTURE_CHUNK_RADIUS:-15}"
TERRAIN_PRESSURE_FIXTURE_BLOCK_ID="${RUMPELMC_RESIDENT_SET_TERRAIN_PRESSURE_FIXTURE_BLOCK_ID:-1}"
TERRAIN_PRESSURE_FIXTURE_WAIT_SEC="${RUMPELMC_RESIDENT_SET_TERRAIN_PRESSURE_FIXTURE_WAIT_SEC:-20.0}"
TERRAIN_PRESSURE_FIXTURE_QUEUE_SETTLE_SEC="${RUMPELMC_RESIDENT_SET_TERRAIN_PRESSURE_FIXTURE_QUEUE_SETTLE_SEC:-30.0}"
TERRAIN_PRESSURE_FIXTURE_MAX_QUEUE="${RUMPELMC_RESIDENT_SET_TERRAIN_PRESSURE_FIXTURE_MAX_QUEUE:-16}"
GODOT_TIMEOUT_SEC="${GODOT_TIMEOUT_SEC:-480}"
GODOT_QUIT_AFTER_FRAMES="${GODOT_QUIT_AFTER_FRAMES:-36000}"

mkdir -p "$OUT_DIR"

fail() {
  echo "world_streaming_resident_set_growth: $*" >&2
  exit 1
}

RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE="${RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE:-1}" \
  RUMPELMC_GODOT_RUST_EXT_PROFILE="${RUMPELMC_GODOT_RUST_EXT_PROFILE:-release}" \
  RUMPELMC_WORKLOAD_MATRIX_CASE_SET="$CASE_SET" \
  RUMPELMC_WORKLOAD_MATRIX_SERVER_VIEW_DISTANCE="$SERVER_VIEW_DISTANCE" \
  RUMPELMC_WORKLOAD_MATRIX_CLIENT_KEEP_CHUNK_DISTANCE="$CLIENT_KEEP_CHUNK_DISTANCE" \
  RUMPELMC_WORKLOAD_MATRIX_SERVER_CHUNKS_PER_UPDATE="$SERVER_CHUNKS_PER_UPDATE" \
  RUMPELMC_WORKLOAD_MATRIX_SMOKE_DELAY_SEC="$SMOKE_DELAY_SEC" \
  RUMPELMC_WORKLOAD_MATRIX_TARGET_FPS="$TARGET_FPS" \
  RUMPELMC_WORKLOAD_MATRIX_TERRAIN_PRESSURE_FIXTURE="$TERRAIN_PRESSURE_FIXTURE" \
  RUMPELMC_WORKLOAD_MATRIX_TERRAIN_PRESSURE_FIXTURE_CHUNK_COLUMNS="$TERRAIN_PRESSURE_FIXTURE_CHUNK_COLUMNS" \
  RUMPELMC_WORKLOAD_MATRIX_TERRAIN_PRESSURE_FIXTURE_CHUNK_ROWS="$TERRAIN_PRESSURE_FIXTURE_CHUNK_ROWS" \
  RUMPELMC_WORKLOAD_MATRIX_TERRAIN_PRESSURE_FIXTURE_CHUNK_RADIUS="$TERRAIN_PRESSURE_FIXTURE_CHUNK_RADIUS" \
  RUMPELMC_WORKLOAD_MATRIX_TERRAIN_PRESSURE_FIXTURE_BLOCK_ID="$TERRAIN_PRESSURE_FIXTURE_BLOCK_ID" \
  RUMPELMC_WORKLOAD_MATRIX_TERRAIN_PRESSURE_FIXTURE_WAIT_SEC="$TERRAIN_PRESSURE_FIXTURE_WAIT_SEC" \
  RUMPELMC_WORKLOAD_MATRIX_TERRAIN_PRESSURE_FIXTURE_QUEUE_SETTLE_SEC="$TERRAIN_PRESSURE_FIXTURE_QUEUE_SETTLE_SEC" \
  RUMPELMC_WORKLOAD_MATRIX_TERRAIN_PRESSURE_FIXTURE_MAX_QUEUE="$TERRAIN_PRESSURE_FIXTURE_MAX_QUEUE" \
  GODOT_TIMEOUT_SEC="$GODOT_TIMEOUT_SEC" \
  GODOT_QUIT_AFTER_FRAMES="$GODOT_QUIT_AFTER_FRAMES" \
  /bin/sh "$ROOT_DIR/scripts/gpu_terrain_workload_matrix.sh" "$WORKLOAD_DIR"

matrix_summary="$WORKLOAD_DIR/workload-matrix-summary.txt"
test -s "$matrix_summary" || fail "missing workload matrix summary $matrix_summary"

awk \
  -v min_gpu_draws="$MIN_GPU_DRAWS" \
  -v server_view_distance="$SERVER_VIEW_DISTANCE" \
  -v client_keep_chunk_distance="$CLIENT_KEEP_CHUNK_DISTANCE" \
  -v case_set="$CASE_SET" \
  -v server_chunks_per_update="$SERVER_CHUNKS_PER_UPDATE" \
  -v terrain_pressure_fixture="$TERRAIN_PRESSURE_FIXTURE" \
  -v smoke_delay_sec="$SMOKE_DELAY_SEC" \
  -v target_fps="$TARGET_FPS" \
  -v matrix_summary="$matrix_summary" '
  $1 == "GPU" || NF == 0 { next }
  {
    for (i = 1; i <= NF; i++) {
      split($i, kv, "=")
      key = kv[1]
      value = kv[2] + 0
      if (key == "gpu_subchunks" && value > max_subchunks) max_subchunks = value
      if (key == "gpu_draws" && value > max_draws) max_draws = value
      if (key == "gpu_faces" && value > max_faces) max_faces = value
      if (key == "gpu_draw_cmd_bytes" && value > max_draw_cmd_bytes) max_draw_cmd_bytes = value
      if (key == "gpu_draw_cmd_capacity_bytes" && value > max_draw_cmd_capacity_bytes) max_draw_cmd_capacity_bytes = value
      if (key == "terrain_queue_max_ms" && value > max_queue) max_queue = value
      if (key == "process_wall_p95_ms" && value > max_process) max_process = value
      if (key == "gpu_compositor_submit_max_ms" && value > max_submit) max_submit = value
      if (key == "gpu_uploads" && value > max_uploads) max_uploads = value
      if (key == "gpu_upload_fail") upload_fail += value
      if (key == "gpu_upload_fail_capacity") upload_fail_capacity += value
      if (key == "gpu_upload_fail_fragmented") upload_fail_fragmented += value
      if (key == "gpu_upload_stage_pool_enabled" && value > max_stage_pool_enabled) max_stage_pool_enabled = value
      if (key == "gpu_upload_stage_pool_entries" && value > max_stage_pool_entries) max_stage_pool_entries = value
      if (key == "gpu_upload_stage_pool_bytes" && value > max_stage_pool_bytes) max_stage_pool_bytes = value
      if (key == "gpu_upload_stage_pba_creates" && value > max_stage_pba_creates) max_stage_pba_creates = value
      if (key == "gpu_upload_stage_pba_reuses" && value > max_stage_pba_reuses) max_stage_pba_reuses = value
      if (key == "terrain_pressure_fixture_block_id" && value > max_terrain_pressure_fixture_block_id) max_terrain_pressure_fixture_block_id = value
      if (key == "terrain_pressure_fixture_blocks" && value > max_terrain_pressure_fixture_blocks) max_terrain_pressure_fixture_blocks = value
      if (key == "terrain_pressure_fixture_dirty_observed" && value > max_terrain_pressure_fixture_dirty_observed) max_terrain_pressure_fixture_dirty_observed = value
      if (key == "transparent_requested" && value > max_transparent_requested) max_transparent_requested = value
      if (key == "transparent_active" && value > max_transparent_active) max_transparent_active = value
      if (key == "transparent_fallback" && value > max_transparent_fallback) max_transparent_fallback = value
      if (key == "transparent_blocks" && value > max_transparent_blocks) max_transparent_blocks = value
      if (key == "transparent_faces" && value > max_transparent_faces) max_transparent_faces = value
      if (key == "transparent_draws" && value > max_transparent_draws) max_transparent_draws = value
      if (key == "transparent_subchunks" && value > max_transparent_subchunks) max_transparent_subchunks = value
    }
  }
  END {
    status = "pass"
    if (max_draws < min_gpu_draws || upload_fail > 0 || upload_fail_capacity > 0 || upload_fail_fragmented > 0) {
      status = "fail"
    }
    printf("resident_set_growth status=%s server_view_distance=%s client_keep_chunk_distance=%s case_set=%s server_chunks_per_update=%s terrain_pressure_fixture=%s smoke_delay_sec=%s target_fps=%s min_gpu_draws=%d max_gpu_subchunks=%d max_gpu_draws=%d max_gpu_faces=%d max_gpu_draw_cmd_bytes=%d max_gpu_draw_cmd_capacity_bytes=%d max_terrain_queue_ms=%.3f max_process_wall_p95_ms=%.3f max_gpu_compositor_submit_ms=%.3f max_gpu_uploads=%d gpu_upload_fail=%d gpu_upload_fail_capacity=%d gpu_upload_fail_fragmented=%d max_gpu_upload_stage_pool_enabled=%d max_gpu_upload_stage_pool_entries=%d max_gpu_upload_stage_pool_bytes=%d max_gpu_upload_stage_pba_creates=%d max_gpu_upload_stage_pba_reuses=%d max_terrain_pressure_fixture_block_id=%d max_terrain_pressure_fixture_blocks=%d max_terrain_pressure_fixture_dirty_observed=%d max_transparent_requested=%d max_transparent_active=%d max_transparent_fallback=%d max_transparent_blocks=%d max_transparent_faces=%d max_transparent_draws=%d max_transparent_subchunks=%d matrix_summary=%s\n", status, server_view_distance, client_keep_chunk_distance, case_set, server_chunks_per_update, terrain_pressure_fixture, smoke_delay_sec, target_fps, min_gpu_draws, max_subchunks, max_draws, max_faces, max_draw_cmd_bytes, max_draw_cmd_capacity_bytes, max_queue, max_process, max_submit, max_uploads, upload_fail, upload_fail_capacity, upload_fail_fragmented, max_stage_pool_enabled, max_stage_pool_entries, max_stage_pool_bytes, max_stage_pba_creates, max_stage_pba_reuses, max_terrain_pressure_fixture_block_id, max_terrain_pressure_fixture_blocks, max_terrain_pressure_fixture_dirty_observed, max_transparent_requested, max_transparent_active, max_transparent_fallback, max_transparent_blocks, max_transparent_faces, max_transparent_draws, max_transparent_subchunks, matrix_summary)
    if (status != "pass") {
      exit 1
    }
  }
' "$matrix_summary" > "$SUMMARY_PATH" || {
  cat "$SUMMARY_PATH" >&2 || true
  fail "resident set growth gate failed"
}

cat "$SUMMARY_PATH"
echo "Resident set growth artifacts: $OUT_DIR"
