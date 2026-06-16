#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/gpu_terrain_in_place_upload_gate"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

RUN_DIR="$OUT_DIR/run"
RUN_LOG="$OUT_DIR/run.log"
SUMMARY_PATH="$OUT_DIR/gpu-in-place-upload-summary.txt"
DB_PATH="${RUMPELMC_IN_PLACE_UPLOAD_ROCKSDB_PATH:-"$OUT_DIR/server-rocksdb"}"
USES_DEFAULT_DB_PATH=1
if [ -n "${RUMPELMC_IN_PLACE_UPLOAD_ROCKSDB_PATH:-}" ]; then
  USES_DEFAULT_DB_PATH=0
fi

ACTION="${RUMPELMC_IN_PLACE_UPLOAD_ACTION:-place}"
EDIT_X="${RUMPELMC_IN_PLACE_UPLOAD_X:-127}"
EDIT_Y="${RUMPELMC_IN_PLACE_UPLOAD_Y:-63}"
EDIT_Z="${RUMPELMC_IN_PLACE_UPLOAD_Z:-80}"
EDIT_BLOCK_ID="${RUMPELMC_IN_PLACE_UPLOAD_BLOCK_ID:-4}"
EXPECTED_EDGES="${RUMPELMC_IN_PLACE_UPLOAD_EXPECTED_EDGES:-pos_x}"
EXPECTED_BOUNDS="${RUMPELMC_IN_PLACE_UPLOAD_EXPECTED_BOUNDS:-31,63,16:31,63,16}"
MIN_IN_PLACE_UPLOADS="${RUMPELMC_IN_PLACE_UPLOAD_MIN_UPLOADS:-1}"
MIN_IN_PLACE_MISSES="${RUMPELMC_IN_PLACE_UPLOAD_MIN_MISSES:-0}"

fail() {
  echo "gpu_terrain_in_place_upload_gate: $*" >&2
  exit 1
}

metric() {
  key="$1"
  marker_path="$2"
  sed -n "s/.*$key=\([0-9][0-9]*\).*/\1/p" "$marker_path" | sed -n '1p'
}

float_metric() {
  key="$1"
  marker_path="$2"
  sed -n "s/.*$key=\([0-9][0-9]*\.[0-9][0-9]*\).*/\1/p" "$marker_path" | sed -n '1p'
}

text_metric() {
  key="$1"
  marker_path="$2"
  sed -n "s/.*$key=\([^ ]*\).*/\1/p" "$marker_path" | sed -n '1p'
}

perf_triplet_value() {
  key="$1"
  marker_path="$2"
  index="$3"
  sed -n "s/.*$key=\([0-9][0-9]*\.[0-9][0-9]*\)\/\([0-9][0-9]*\.[0-9][0-9]*\)\/\([0-9][0-9]*\.[0-9][0-9]*\).*/\1 \2 \3/p" "$marker_path" \
    | awk -v index="$index" '{print $index}' \
    | sed -n '1p'
}

perf_count_triplet_value() {
  key="$1"
  marker_path="$2"
  index="$3"
  sed -n "s/.*$key=\([0-9][0-9]*\)\/\([0-9][0-9]*\.[0-9][0-9]*\)\/\([0-9][0-9]*\).*/\1 \2 \3/p" "$marker_path" \
    | awk -v index="$index" '{print $index}' \
    | sed -n '1p'
}

listener_pid() {
  if command -v lsof >/dev/null 2>&1; then
    lsof -tiTCP:25565 -sTCP:LISTEN 2>/dev/null | sed -n '1p'
  fi
}

wait_for_port_clear() {
  tries=0
  while [ "$tries" -lt 10 ]; do
    pid="$(listener_pid || true)"
    if [ -z "$pid" ]; then
      return 0
    fi
    tries=$((tries + 1))
    sleep 1
  done
  fail "port 25565 is still listening after cleanup"
}

stop_server_from_log() {
  log_path="$1"
  test -f "$log_path" || return 0
  pid="$(sed -n 's/.*Go server started with PID: \([0-9][0-9]*\).*/\1/p' "$log_path" | tail -n 1)"
  if [ -n "$pid" ]; then
    kill "$pid" 2>/dev/null || true
    wait_for_port_clear
  fi
}

cleanup() {
  stop_server_from_log "$RUN_LOG"
}

require_positive_integer() {
  name="$1"
  value="$2"
  case "$value" in
    ''|*[!0-9]*) fail "$name must be a non-negative integer, got $value" ;;
  esac
}

require_metric_ge() {
  marker_path="$1"
  key="$2"
  min_value="$3"
  value="$(metric "$key" "$marker_path")"
  test -n "$value" || fail "missing $key in $marker_path"
  if [ "$value" -lt "$min_value" ]; then
    fail "$key=$value is below $min_value in $marker_path"
  fi
}

require_metric_eq() {
  marker_path="$1"
  key="$2"
  expected="$3"
  value="$(metric "$key" "$marker_path")"
  test -n "$value" || fail "missing $key in $marker_path"
  if [ "$value" -ne "$expected" ]; then
    fail "$key=$value, expected $expected in $marker_path"
  fi
}

require_count_triplet_ge() {
  marker_path="$1"
  key="$2"
  index="$3"
  min_value="$4"
  value="$(perf_count_triplet_value "$key" "$marker_path" "$index")"
  test -n "$value" || fail "missing $key in $marker_path"
  case "$value" in
    *.*) value="${value%%.*}" ;;
  esac
  if [ "$value" -lt "$min_value" ]; then
    fail "$key index $index value $value is below $min_value in $marker_path"
  fi
}

default_float() {
  value="$1"
  if [ -n "$value" ]; then
    printf '%s\n' "$value"
  else
    printf '0.000\n'
  fi
}

write_summary() {
  marker_path="$RUN_DIR/gpu-terrain-movement-stress.png.txt"
  block_summary="$RUN_DIR/block-edit-stress-summary.txt"

  gpu_in_place_upload_enabled="$(metric gpu_in_place_upload_enabled "$marker_path")"
  gpu_in_place_uploads="$(metric gpu_in_place_uploads "$marker_path")"
  gpu_in_place_upload_misses="$(metric gpu_in_place_upload_misses "$marker_path")"
  gpu_uploads="$(metric gpu_uploads "$marker_path")"
  gpu_upload_fail="$(metric gpu_upload_fail "$marker_path")"
  gpu_upload_fail_capacity="$(metric gpu_upload_fail_capacity "$marker_path")"
  gpu_upload_fail_fragmented="$(metric gpu_upload_fail_fragmented "$marker_path")"
  gpu_upload_fail_injected="$(metric gpu_upload_fail_injected "$marker_path")"
  gpu_upload_retry_policy="$(text_metric gpu_upload_retry_policy "$marker_path")"
  gpu_upload_retry_attempts="$(metric gpu_upload_retry_attempts "$marker_path")"
  gpu_upload_retry_success="$(metric gpu_upload_retry_success "$marker_path")"
  gpu_upload_retry_giveups="$(metric gpu_upload_retry_giveups "$marker_path")"
  gpu_upload_backoff_active="$(metric gpu_upload_backoff_active "$marker_path")"
  gpu_upload_backoff_frames="$(metric gpu_upload_backoff_frames "$marker_path")"
  gpu_upload_backoff_max_frames="$(metric gpu_upload_backoff_max_frames "$marker_path")"
  gpu_upload_ms_max="$(default_float "$(perf_triplet_value gpu_upload_ms "$marker_path" 3)")"
  gpu_upload_stage_ms_max="$(default_float "$(perf_triplet_value gpu_upload_stage_ms "$marker_path" 3)")"
  gpu_upload_update_ms_max="$(default_float "$(perf_triplet_value gpu_upload_update_ms "$marker_path" 3)")"
  gpu_draw_patch_ms_max="$(default_float "$(perf_triplet_value gpu_draw_patch_ms "$marker_path" 3)")"
  terrain_queue_max_ms="$(default_float "$(perf_triplet_value terrain_queue_work_ms "$marker_path" 3)")"
  terrain_queue_new_slot_uploads_max="$(default_float "$(perf_count_triplet_value terrain_queue_gpu_upload_new_slots "$marker_path" 3)")"
  terrain_queue_replace_slot_uploads_max="$(default_float "$(perf_count_triplet_value terrain_queue_gpu_upload_replace_slots "$marker_path" 3)")"
  terrain_queue_new_slot_upload_kb_max="$(default_float "$(perf_triplet_value terrain_queue_gpu_upload_new_slot_kb "$marker_path" 3)")"
  terrain_queue_replace_slot_upload_kb_max="$(default_float "$(perf_triplet_value terrain_queue_gpu_upload_replace_slot_kb "$marker_path" 3)")"
  process_wall_p95_ms="$(default_float "$(float_metric process_wall_p95_ms "$marker_path")")"
  gpu_compositor_submit_max_ms="$(default_float "$(perf_triplet_value gpu_compositor_submit_ms "$marker_path" 3)")"
  dirty_partial_saved_subchunks="$(metric dirty_partial_saved_subchunks "$marker_path")"
  dirty_last_rebuild_subchunks="$(metric dirty_last_rebuild_subchunks "$marker_path")"
  current_chunk_loaded="$(metric current_chunk_loaded "$marker_path")"
  current_chunk_collision="$(metric current_chunk_collision "$marker_path")"

  {
    printf 'gpu_in_place_upload status=pass action=%s x=%s y=%s z=%s block_id=%s expected_edges=%s expected_bounds=%s isolated_db=%s gpu_in_place_upload_enabled=%s gpu_in_place_uploads=%s gpu_in_place_upload_misses=%s gpu_uploads=%s gpu_upload_fail=%s gpu_upload_fail_capacity=%s gpu_upload_fail_fragmented=%s gpu_upload_fail_injected=%s gpu_upload_retry_policy=%s gpu_upload_retry_attempts=%s gpu_upload_retry_success=%s gpu_upload_retry_giveups=%s gpu_upload_backoff_active=%s gpu_upload_backoff_frames=%s gpu_upload_backoff_max_frames=%s gpu_upload_ms_max=%s gpu_upload_stage_ms_max=%s gpu_upload_update_ms_max=%s gpu_draw_patch_ms_max=%s terrain_queue_max_ms=%s terrain_queue_new_slot_uploads_max=%s terrain_queue_replace_slot_uploads_max=%s terrain_queue_new_slot_upload_kb_max=%s terrain_queue_replace_slot_upload_kb_max=%s process_wall_p95_ms=%s gpu_compositor_submit_max_ms=%s dirty_partial_saved_subchunks=%s dirty_last_rebuild_subchunks=%s current_chunk_loaded=%s current_chunk_collision=%s marker=%s block_summary=%s run_log=%s\n' \
      "$ACTION" "$EDIT_X" "$EDIT_Y" "$EDIT_Z" "$EDIT_BLOCK_ID" "$EXPECTED_EDGES" "$EXPECTED_BOUNDS" "$DB_PATH" \
      "$gpu_in_place_upload_enabled" "$gpu_in_place_uploads" "$gpu_in_place_upload_misses" "$gpu_uploads" \
      "$gpu_upload_fail" "$gpu_upload_fail_capacity" "$gpu_upload_fail_fragmented" "$gpu_upload_fail_injected" \
      "$gpu_upload_retry_policy" "$gpu_upload_retry_attempts" "$gpu_upload_retry_success" "$gpu_upload_retry_giveups" \
      "$gpu_upload_backoff_active" "$gpu_upload_backoff_frames" "$gpu_upload_backoff_max_frames" \
      "$gpu_upload_ms_max" "$gpu_upload_stage_ms_max" "$gpu_upload_update_ms_max" "$gpu_draw_patch_ms_max" \
      "$terrain_queue_max_ms" "$terrain_queue_new_slot_uploads_max" "$terrain_queue_replace_slot_uploads_max" \
      "$terrain_queue_new_slot_upload_kb_max" "$terrain_queue_replace_slot_upload_kb_max" \
      "$process_wall_p95_ms" "$gpu_compositor_submit_max_ms" \
      "$dirty_partial_saved_subchunks" "$dirty_last_rebuild_subchunks" "$current_chunk_loaded" "$current_chunk_collision" \
      "$marker_path" "$block_summary" "$RUN_LOG"
  } > "$SUMMARY_PATH"
  cat "$SUMMARY_PATH"
}

require_positive_integer RUMPELMC_IN_PLACE_UPLOAD_MIN_UPLOADS "$MIN_IN_PLACE_UPLOADS"
require_positive_integer RUMPELMC_IN_PLACE_UPLOAD_MIN_MISSES "$MIN_IN_PLACE_MISSES"

mkdir -p "$OUT_DIR"
rm -rf "$RUN_DIR"
rm -f "$RUN_LOG" "$SUMMARY_PATH"
if [ "$USES_DEFAULT_DB_PATH" -eq 1 ]; then
  rm -rf "$DB_PATH"
fi
mkdir -p "$RUN_DIR" "$DB_PATH"

if [ -n "$(listener_pid || true)" ]; then
  fail "port 25565 is already in use; stop the existing server before in-place upload gate"
fi
trap cleanup EXIT HUP INT TERM

echo "==> GPU terrain in-place upload gate"
run_rc=0
RUMPELMC_SERVER_ROCKSDB_PATH="$DB_PATH" \
RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE="${RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE:-1}" \
RUMPELMC_GODOT_RUST_EXT_PROFILE="${RUMPELMC_GODOT_RUST_EXT_PROFILE:-release}" \
RUMPELMC_GPU_TERRAIN_IN_PLACE_SUBCHUNK_UPLOAD="${RUMPELMC_GPU_TERRAIN_IN_PLACE_SUBCHUNK_UPLOAD:-1}" \
RUMPELMC_GPU_TERRAIN_PARTIAL_DIRTY_UPLOAD="${RUMPELMC_GPU_TERRAIN_PARTIAL_DIRTY_UPLOAD:-1}" \
RUMPELMC_BLOCK_EDIT_STRESS_ACTION="$ACTION" \
RUMPELMC_BLOCK_EDIT_STRESS_X="$EDIT_X" \
RUMPELMC_BLOCK_EDIT_STRESS_Y="$EDIT_Y" \
RUMPELMC_BLOCK_EDIT_STRESS_Z="$EDIT_Z" \
RUMPELMC_BLOCK_EDIT_STRESS_BLOCK_ID="$EDIT_BLOCK_ID" \
RUMPELMC_BLOCK_EDIT_STRESS_EXPECTED_EDGES="$EXPECTED_EDGES" \
RUMPELMC_BLOCK_EDIT_STRESS_EXPECTED_EDGES_EXACT=1 \
RUMPELMC_BLOCK_EDIT_STRESS_EXPECTED_BOUNDS="$EXPECTED_BOUNDS" \
RUMPELMC_BLOCK_EDIT_STRESS_MIN_PARTIAL_CHUNKS=1 \
RUMPELMC_BLOCK_EDIT_STRESS_MIN_PARTIAL_SUBCHUNKS=1 \
RUMPELMC_BLOCK_EDIT_STRESS_MIN_PARTIAL_SAVED_SUBCHUNKS=1 \
RUMPELMC_BLOCK_EDIT_STRESS_MIN_EDGE_NEIGHBOR_CHUNKS=1 \
RUMPELMC_BLOCK_EDIT_STRESS_MIN_EDGE_NEIGHBOR_SUBCHUNKS=2 \
RUMPELMC_BLOCK_EDIT_STRESS_MIN_LAST_EDGE_NEIGHBOR_CHUNKS=1 \
RUMPELMC_BLOCK_EDIT_STRESS_MIN_LAST_EDGE_NEIGHBOR_SUBCHUNKS=2 \
GODOT_QUIT_AFTER_FRAMES="${GODOT_QUIT_AFTER_FRAMES:-36000}" \
GODOT_TIMEOUT_SEC="${GODOT_TIMEOUT_SEC:-300}" \
SMOKE_DELAY_SEC="${SMOKE_DELAY_SEC:-8.0}" \
sh "$ROOT_DIR/scripts/gpu_terrain_block_edit_stress.sh" "$RUN_DIR" > "$RUN_LOG" 2>&1 || run_rc=$?

cleanup
if [ "$run_rc" -ne 0 ]; then
  tail -n 80 "$RUN_LOG" >&2 || true
  fail "block edit stress failed with exit code $run_rc"
fi

marker_path="$RUN_DIR/gpu-terrain-movement-stress.png.txt"
test -s "$marker_path" || fail "missing marker $marker_path"
test -s "$RUN_DIR/block-edit-stress-summary.txt" || fail "missing block edit summary"
grep -q "smoke_err=0" "$marker_path" || fail "smoke_err is not 0 in $marker_path"
require_metric_eq "$marker_path" gpu_in_place_upload_enabled 1
require_metric_ge "$marker_path" gpu_in_place_uploads "$MIN_IN_PLACE_UPLOADS"
require_metric_ge "$marker_path" gpu_in_place_upload_misses "$MIN_IN_PLACE_MISSES"
require_metric_eq "$marker_path" gpu_upload_fail 0
require_metric_eq "$marker_path" gpu_upload_fail_capacity 0
require_metric_eq "$marker_path" gpu_upload_fail_fragmented 0
require_metric_eq "$marker_path" gpu_upload_fail_injected 0
grep -q "gpu_upload_retry_policy=none" "$marker_path" || fail "gpu_upload_retry_policy is not none in $marker_path"
require_metric_eq "$marker_path" gpu_upload_retry_attempts 0
require_metric_eq "$marker_path" gpu_upload_retry_success 0
require_metric_eq "$marker_path" gpu_upload_retry_giveups 0
require_metric_eq "$marker_path" gpu_upload_backoff_active 0
require_metric_eq "$marker_path" gpu_upload_backoff_frames 0
require_metric_eq "$marker_path" gpu_upload_backoff_max_frames 0
require_metric_eq "$marker_path" block_edit_dirty_observed 1
require_metric_ge "$marker_path" dirty_partial_saved_subchunks 1
require_metric_ge "$marker_path" dirty_last_rebuild_subchunks 1
require_metric_eq "$marker_path" current_chunk_loaded 1
require_metric_ge "$marker_path" current_chunk_collision 1
test -n "$(perf_triplet_value gpu_upload_ms "$marker_path" 3)" || fail "missing gpu_upload_ms in $marker_path"
test -n "$(perf_triplet_value gpu_upload_update_ms "$marker_path" 3)" || fail "missing gpu_upload_update_ms in $marker_path"
test -n "$(perf_triplet_value terrain_queue_gpu_upload_new_slot_kb "$marker_path" 3)" || fail "missing terrain_queue_gpu_upload_new_slot_kb in $marker_path"
test -n "$(perf_triplet_value terrain_queue_gpu_upload_replace_slot_kb "$marker_path" 3)" || fail "missing terrain_queue_gpu_upload_replace_slot_kb in $marker_path"
require_count_triplet_ge "$marker_path" terrain_queue_gpu_upload_new_slots 3 1
require_count_triplet_ge "$marker_path" terrain_queue_gpu_upload_replace_slots 3 1

write_summary
wait_for_port_clear

echo "GPU terrain in-place upload artifacts: $OUT_DIR"
