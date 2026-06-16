#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/gpu_edge_dirty_compare"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

ACTION="${RUMPELMC_EDGE_DIRTY_COMPARE_ACTION:-toggle}"
EDIT_X="${RUMPELMC_EDGE_DIRTY_COMPARE_X:-127}"
EDIT_Y="${RUMPELMC_EDGE_DIRTY_COMPARE_Y:-64}"
EDIT_Z="${RUMPELMC_EDGE_DIRTY_COMPARE_Z:-95}"
EDIT_BLOCK_ID="${RUMPELMC_EDGE_DIRTY_COMPARE_BLOCK_ID:-1}"
EXPECTED_EDGES="${RUMPELMC_EDGE_DIRTY_COMPARE_EXPECTED_EDGES:-pos_x,pos_z}"
EXPECTED_BOUNDS="${RUMPELMC_EDGE_DIRTY_COMPARE_EXPECTED_BOUNDS:-31,64,31:31,64,31}"

FULL_DIR="$OUT_DIR/full"
PARTIAL_DIR="$OUT_DIR/partial"
SUMMARY_PATH="$OUT_DIR/edge-dirty-compare-summary.txt"
FULL_LOG="$FULL_DIR/run.log"
PARTIAL_LOG="$PARTIAL_DIR/run.log"

fail() {
  echo "gpu_terrain_edge_dirty_compare: $*" >&2
  exit 1
}

metric() {
  key="$1"
  marker_path="$2"
  sed -n "s/.*$key=\([0-9][0-9]*\).*/\1/p" "$marker_path" | sed -n '1p'
}

text_metric() {
  key="$1"
  marker_path="$2"
  sed -n "s/.*$key=\([^ ]*\).*/\1/p" "$marker_path" | sed -n '1p'
}

float_metric() {
  key="$1"
  marker_path="$2"
  sed -n "s/.*$key=\([0-9][0-9]*\.[0-9][0-9]*\).*/\1/p" "$marker_path" | sed -n '1p'
}

perf_triplet_value() {
  key="$1"
  marker_path="$2"
  index="$3"
  sed -n "s/.*$key=\([0-9][0-9]*\.[0-9][0-9]*\)\/\([0-9][0-9]*\.[0-9][0-9]*\)\/\([0-9][0-9]*\.[0-9][0-9]*\).*/\1 \2 \3/p" "$marker_path" \
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
  fail "port 25565 is still listening after smoke cleanup"
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
  stop_server_from_log "$PARTIAL_LOG"
  stop_server_from_log "$FULL_LOG"
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

require_metric_same() {
  left_marker="$1"
  right_marker="$2"
  key="$3"
  left="$(metric "$key" "$left_marker")"
  right="$(metric "$key" "$right_marker")"
  test -n "$left" || fail "missing $key in $left_marker"
  test -n "$right" || fail "missing $key in $right_marker"
  if [ "$left" -ne "$right" ]; then
    fail "$key differs: full=$left partial=$right"
  fi
}

require_text_metric_eq() {
  marker_path="$1"
  key="$2"
  expected="$3"
  value="$(text_metric "$key" "$marker_path")"
  test -n "$value" || fail "missing $key in $marker_path"
  if [ "$value" != "$expected" ]; then
    fail "$key=$value, expected $expected in $marker_path"
  fi
}

run_full_rebuild() {
  echo "==> Edge dirty compare: full rebuild control"
  mkdir -p "$FULL_DIR"
  if ! RUMPELMC_GPU_TERRAIN_PARTIAL_DIRTY_UPLOAD=0 \
    RUMPELMC_BLOCK_EDIT_STRESS_ACTION="$ACTION" \
    RUMPELMC_BLOCK_EDIT_STRESS_X="$EDIT_X" \
    RUMPELMC_BLOCK_EDIT_STRESS_Y="$EDIT_Y" \
    RUMPELMC_BLOCK_EDIT_STRESS_Z="$EDIT_Z" \
    RUMPELMC_BLOCK_EDIT_STRESS_BLOCK_ID="$EDIT_BLOCK_ID" \
    RUMPELMC_BLOCK_EDIT_STRESS_EXPECTED_EDGES="$EXPECTED_EDGES" \
    RUMPELMC_BLOCK_EDIT_STRESS_EXPECTED_BOUNDS="$EXPECTED_BOUNDS" \
    RUMPELMC_BLOCK_EDIT_STRESS_MIN_PARTIAL_CHUNKS=0 \
    RUMPELMC_BLOCK_EDIT_STRESS_MIN_PARTIAL_SUBCHUNKS=0 \
    RUMPELMC_BLOCK_EDIT_STRESS_MIN_PARTIAL_SAVED_SUBCHUNKS=0 \
    RUMPELMC_BLOCK_EDIT_STRESS_MIN_EDGE_NEIGHBOR_CHUNKS=0 \
    RUMPELMC_BLOCK_EDIT_STRESS_MIN_EDGE_NEIGHBOR_SUBCHUNKS=0 \
    RUMPELMC_BLOCK_EDIT_STRESS_MIN_LAST_EDGE_NEIGHBOR_CHUNKS=0 \
    RUMPELMC_BLOCK_EDIT_STRESS_MIN_LAST_EDGE_NEIGHBOR_SUBCHUNKS=0 \
    RUMPELMC_BLOCK_EDIT_STRESS_MIN_CURRENT_CHUNK_COLLISION=1 \
    RUMPELMC_BLOCK_EDIT_STRESS_MIN_COLLISION_REFRESH_REBUILT=1 \
    RUMPELMC_BLOCK_EDIT_STRESS_MIN_LAST_COLLISION_REFRESH_REBUILT=1 \
    RUMPELMC_BLOCK_EDIT_STRESS_MIN_MESH_SHADOW_ONLY=1 \
    RUMPELMC_BLOCK_EDIT_STRESS_MIN_PROXY_SHADOW=1 \
    RUMPELMC_BLOCK_EDIT_STRESS_MIN_PROXY_SHADOW_ONLY=1 \
    RUMPELMC_BLOCK_EDIT_STRESS_MIN_COMPACT_SHADOW_PROXY=1 \
    RUMPELMC_BLOCK_EDIT_STRESS_MIN_PROXY_REFRESH_REUSE=1 \
    sh "$ROOT_DIR/scripts/gpu_terrain_block_edit_stress.sh" "$FULL_DIR" > "$FULL_LOG" 2>&1; then
    cat "$FULL_LOG"
    fail "full rebuild control failed"
  fi
  cat "$FULL_DIR/block-edit-stress-summary.txt"
  stop_server_from_log "$FULL_LOG"
}

run_partial_dirty() {
  echo "==> Edge dirty compare: partial dirty candidate"
  mkdir -p "$PARTIAL_DIR"
  if ! RUMPELMC_GPU_TERRAIN_PARTIAL_DIRTY_UPLOAD=1 \
    RUMPELMC_BLOCK_EDIT_STRESS_ACTION="$ACTION" \
    RUMPELMC_BLOCK_EDIT_STRESS_X="$EDIT_X" \
    RUMPELMC_BLOCK_EDIT_STRESS_Y="$EDIT_Y" \
    RUMPELMC_BLOCK_EDIT_STRESS_Z="$EDIT_Z" \
    RUMPELMC_BLOCK_EDIT_STRESS_BLOCK_ID="$EDIT_BLOCK_ID" \
    RUMPELMC_BLOCK_EDIT_STRESS_EXPECTED_EDGES="$EXPECTED_EDGES" \
    RUMPELMC_BLOCK_EDIT_STRESS_EXPECTED_BOUNDS="$EXPECTED_BOUNDS" \
    RUMPELMC_BLOCK_EDIT_STRESS_MIN_PARTIAL_CHUNKS=1 \
    RUMPELMC_BLOCK_EDIT_STRESS_MIN_PARTIAL_SUBCHUNKS=1 \
    RUMPELMC_BLOCK_EDIT_STRESS_MIN_PARTIAL_SAVED_SUBCHUNKS=1 \
    RUMPELMC_BLOCK_EDIT_STRESS_MIN_EDGE_NEIGHBOR_CHUNKS=1 \
    RUMPELMC_BLOCK_EDIT_STRESS_MIN_EDGE_NEIGHBOR_SUBCHUNKS=1 \
    RUMPELMC_BLOCK_EDIT_STRESS_MIN_LAST_EDGE_NEIGHBOR_CHUNKS=1 \
    RUMPELMC_BLOCK_EDIT_STRESS_MIN_LAST_EDGE_NEIGHBOR_SUBCHUNKS=1 \
    RUMPELMC_BLOCK_EDIT_STRESS_MIN_CURRENT_CHUNK_COLLISION=1 \
    RUMPELMC_BLOCK_EDIT_STRESS_MIN_COLLISION_REFRESH_REBUILT=1 \
    RUMPELMC_BLOCK_EDIT_STRESS_MIN_LAST_COLLISION_REFRESH_REBUILT=1 \
    RUMPELMC_BLOCK_EDIT_STRESS_MIN_MESH_SHADOW_ONLY=1 \
    RUMPELMC_BLOCK_EDIT_STRESS_MIN_PROXY_SHADOW=1 \
    RUMPELMC_BLOCK_EDIT_STRESS_MIN_PROXY_SHADOW_ONLY=1 \
    RUMPELMC_BLOCK_EDIT_STRESS_MIN_COMPACT_SHADOW_PROXY=1 \
    RUMPELMC_BLOCK_EDIT_STRESS_MIN_PROXY_REFRESH_REUSE=1 \
    sh "$ROOT_DIR/scripts/gpu_terrain_block_edit_stress.sh" "$PARTIAL_DIR" > "$PARTIAL_LOG" 2>&1; then
    cat "$PARTIAL_LOG"
    fail "partial dirty candidate failed"
  fi
  cat "$PARTIAL_DIR/block-edit-stress-summary.txt"
  stop_server_from_log "$PARTIAL_LOG"
}

write_summary() {
  full_marker="$FULL_DIR/gpu-terrain-movement-stress.png.txt"
  partial_marker="$PARTIAL_DIR/gpu-terrain-movement-stress.png.txt"
  full_queue_max="$(perf_triplet_value terrain_queue_work_ms "$full_marker" 3)"
  partial_queue_max="$(perf_triplet_value terrain_queue_work_ms "$partial_marker" 3)"
  full_submit_max="$(perf_triplet_value gpu_compositor_submit_ms "$full_marker" 3)"
  partial_submit_max="$(perf_triplet_value gpu_compositor_submit_ms "$partial_marker" 3)"
  full_process_p95="$(float_metric process_wall_p95_ms "$full_marker")"
  partial_process_p95="$(float_metric process_wall_p95_ms "$partial_marker")"
  queue_delta="$(awk -v partial="$partial_queue_max" -v full="$full_queue_max" 'BEGIN { printf("%.3f", partial - full) }')"

  {
    printf 'GPU terrain edge dirty compare summary action=%s x=%s y=%s z=%s block_id=%s expected_edges=%s expected_bounds=%s\n' \
      "$ACTION" "$EDIT_X" "$EDIT_Y" "$EDIT_Z" "$EDIT_BLOCK_ID" "$EXPECTED_EDGES" "$EXPECTED_BOUNDS"
    printf 'full dirty_blocks=%s dirty_last_rebuild_subchunks=%s dirty_edge_neighbor_subchunks=%s dirty_partial_subchunks=%s dirty_partial_saved_subchunks=%s current_chunk_collision=%s collision_refresh_last_rebuilt=%s proxy_shadow=%s compact_shadow_proxy=%s proxy_refresh_reuse=%s terrain_queue_max_ms=%s process_wall_p95_ms=%s gpu_compositor_submit_max_ms=%s gpu_upload_fail=%s\n' \
      "$(metric dirty_blocks "$full_marker")" \
      "$(metric dirty_last_rebuild_subchunks "$full_marker")" \
      "$(metric dirty_edge_neighbor_subchunks "$full_marker")" \
      "$(metric dirty_partial_subchunks "$full_marker")" \
      "$(metric dirty_partial_saved_subchunks "$full_marker")" \
      "$(metric current_chunk_collision "$full_marker")" \
      "$(metric collision_refresh_last_rebuilt "$full_marker")" \
      "$(metric proxy_shadow "$full_marker")" \
      "$(metric compact_shadow_proxy "$full_marker")" \
      "$(metric proxy_refresh_reuse "$full_marker")" \
      "$full_queue_max" \
      "$full_process_p95" \
      "$full_submit_max" \
      "$(metric gpu_upload_fail "$full_marker")"
    printf 'partial dirty_blocks=%s dirty_last_rebuild_subchunks=%s dirty_edge_neighbor_subchunks=%s dirty_partial_subchunks=%s dirty_partial_saved_subchunks=%s current_chunk_collision=%s collision_refresh_last_rebuilt=%s proxy_shadow=%s compact_shadow_proxy=%s proxy_refresh_reuse=%s terrain_queue_max_ms=%s process_wall_p95_ms=%s gpu_compositor_submit_max_ms=%s gpu_upload_fail=%s\n' \
      "$(metric dirty_blocks "$partial_marker")" \
      "$(metric dirty_last_rebuild_subchunks "$partial_marker")" \
      "$(metric dirty_edge_neighbor_subchunks "$partial_marker")" \
      "$(metric dirty_partial_subchunks "$partial_marker")" \
      "$(metric dirty_partial_saved_subchunks "$partial_marker")" \
      "$(metric current_chunk_collision "$partial_marker")" \
      "$(metric collision_refresh_last_rebuilt "$partial_marker")" \
      "$(metric proxy_shadow "$partial_marker")" \
      "$(metric compact_shadow_proxy "$partial_marker")" \
      "$(metric proxy_refresh_reuse "$partial_marker")" \
      "$partial_queue_max" \
      "$partial_process_p95" \
      "$partial_submit_max" \
      "$(metric gpu_upload_fail "$partial_marker")"
    printf 'comparison dirty_blocks_match=1 dirty_last_rebuild_subchunks_match=1 partial_saved_subchunks_delta=%s partial_edge_neighbor_subchunks=%s terrain_queue_delta_ms=%s\n' \
      "$(metric dirty_partial_saved_subchunks "$partial_marker")" \
      "$(metric dirty_edge_neighbor_subchunks "$partial_marker")" \
      "$queue_delta"
  } > "$SUMMARY_PATH"
  cat "$SUMMARY_PATH"
}

mkdir -p "$OUT_DIR"
rm -rf "$FULL_DIR" "$PARTIAL_DIR"

if [ -n "$(listener_pid || true)" ]; then
  fail "port 25565 is already in use; stop the existing server before compare"
fi
trap cleanup EXIT INT TERM

run_full_rebuild
run_partial_dirty

full_marker="$FULL_DIR/gpu-terrain-movement-stress.png.txt"
partial_marker="$PARTIAL_DIR/gpu-terrain-movement-stress.png.txt"
test -s "$full_marker" || fail "missing full marker $full_marker"
test -s "$partial_marker" || fail "missing partial marker $partial_marker"

require_text_metric_eq "$full_marker" dirty_last_edges "$EXPECTED_EDGES"
require_text_metric_eq "$partial_marker" dirty_last_edges "$EXPECTED_EDGES"
require_text_metric_eq "$full_marker" dirty_last_bounds "$EXPECTED_BOUNDS"
require_text_metric_eq "$partial_marker" dirty_last_bounds "$EXPECTED_BOUNDS"
require_metric_same "$full_marker" "$partial_marker" dirty_blocks
require_metric_same "$full_marker" "$partial_marker" dirty_last_blocks
require_metric_same "$full_marker" "$partial_marker" dirty_last_changed_subchunks
require_metric_same "$full_marker" "$partial_marker" dirty_last_rebuild_subchunks
require_metric_eq "$full_marker" dirty_partial_subchunks 0
require_metric_eq "$full_marker" dirty_partial_saved_subchunks 0
require_metric_eq "$full_marker" dirty_edge_neighbor_subchunks 0
require_metric_ge "$partial_marker" dirty_partial_subchunks 1
require_metric_ge "$partial_marker" dirty_partial_saved_subchunks 1
require_metric_ge "$partial_marker" dirty_edge_neighbor_subchunks 1
require_metric_eq "$full_marker" gpu_upload_fail 0
require_metric_eq "$partial_marker" gpu_upload_fail 0

write_summary
wait_for_port_clear

echo "GPU terrain edge dirty compare artifacts: $OUT_DIR"
