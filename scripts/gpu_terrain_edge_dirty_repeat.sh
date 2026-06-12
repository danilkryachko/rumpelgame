#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/gpu_edge_dirty_repeat"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

REPEATS="${RUMPELMC_EDGE_DIRTY_REPEAT_COUNT:-3}"
ACTION="${RUMPELMC_EDGE_DIRTY_REPEAT_ACTION:-toggle}"
EDIT_X="${RUMPELMC_EDGE_DIRTY_REPEAT_X:-127}"
EDIT_Y="${RUMPELMC_EDGE_DIRTY_REPEAT_Y:-64}"
EDIT_Z="${RUMPELMC_EDGE_DIRTY_REPEAT_Z:-95}"
EDIT_BLOCK_ID="${RUMPELMC_EDGE_DIRTY_REPEAT_BLOCK_ID:-1}"
EXPECTED_EDGES="${RUMPELMC_EDGE_DIRTY_REPEAT_EXPECTED_EDGES:-pos_x,pos_z}"
EXPECTED_BOUNDS="${RUMPELMC_EDGE_DIRTY_REPEAT_EXPECTED_BOUNDS:-31,64,31:31,64,31}"
MIN_EDGE_NEIGHBOR_CHUNKS="${RUMPELMC_EDGE_DIRTY_REPEAT_MIN_EDGE_NEIGHBOR_CHUNKS:-2}"
MIN_EDGE_NEIGHBOR_SUBCHUNKS="${RUMPELMC_EDGE_DIRTY_REPEAT_MIN_EDGE_NEIGHBOR_SUBCHUNKS:-4}"
MIN_LAST_EDGE_NEIGHBOR_CHUNKS="${RUMPELMC_EDGE_DIRTY_REPEAT_MIN_LAST_EDGE_NEIGHBOR_CHUNKS:-2}"
MIN_LAST_EDGE_NEIGHBOR_SUBCHUNKS="${RUMPELMC_EDGE_DIRTY_REPEAT_MIN_LAST_EDGE_NEIGHBOR_SUBCHUNKS:-4}"
TARGET_FPS="${RUMPELMC_EDGE_DIRTY_REPEAT_TARGET_FPS:-150}"
SUMMARY_PATH="$OUT_DIR/edge-dirty-repeat-summary.txt"

fail() {
  echo "gpu_terrain_edge_dirty_repeat: $*" >&2
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
  for log_path in "$OUT_DIR"/run-*/run.log; do
    stop_server_from_log "$log_path"
  done
}

frame_budget_ms() {
  awk -v fps="$TARGET_FPS" '
    BEGIN {
      if (fps <= 0.0) {
        fps = 150.0
      }
      printf("%.3f\n", 1000.0 / fps)
    }
  '
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

require_float_le_budget() {
  label="$1"
  value="$2"
  budget="$3"
  awk -v label="$label" -v value="$value" -v budget="$budget" '
    BEGIN {
      if (value > budget) {
        printf("gpu_terrain_edge_dirty_repeat: %s %.3f exceeds %.3f\n", label, value, budget) > "/dev/stderr"
        exit 1
      }
    }
  '
}

run_once() {
  index="$1"
  run_dir="$OUT_DIR/run-$index"
  run_log="$run_dir/run.log"
  rm -rf "$run_dir"
  mkdir -p "$run_dir"

  echo "==> Edge dirty repeat run $index/$REPEATS" >&2
  if ! RUMPELMC_GPU_TERRAIN_PARTIAL_DIRTY_UPLOAD=1 \
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
    RUMPELMC_BLOCK_EDIT_STRESS_MIN_EDGE_NEIGHBOR_CHUNKS="$MIN_EDGE_NEIGHBOR_CHUNKS" \
    RUMPELMC_BLOCK_EDIT_STRESS_MIN_EDGE_NEIGHBOR_SUBCHUNKS="$MIN_EDGE_NEIGHBOR_SUBCHUNKS" \
    RUMPELMC_BLOCK_EDIT_STRESS_MIN_LAST_EDGE_NEIGHBOR_CHUNKS="$MIN_LAST_EDGE_NEIGHBOR_CHUNKS" \
    RUMPELMC_BLOCK_EDIT_STRESS_MIN_LAST_EDGE_NEIGHBOR_SUBCHUNKS="$MIN_LAST_EDGE_NEIGHBOR_SUBCHUNKS" \
    RUMPELMC_BLOCK_EDIT_STRESS_MIN_CURRENT_CHUNK_COLLISION=1 \
    RUMPELMC_BLOCK_EDIT_STRESS_MIN_COLLISION_REFRESH_REBUILT=1 \
    RUMPELMC_BLOCK_EDIT_STRESS_MIN_LAST_COLLISION_REFRESH_REBUILT=1 \
    RUMPELMC_BLOCK_EDIT_STRESS_MIN_MESH_SHADOW_ONLY=1 \
    RUMPELMC_BLOCK_EDIT_STRESS_MIN_PROXY_SHADOW=1 \
    RUMPELMC_BLOCK_EDIT_STRESS_MIN_PROXY_SHADOW_ONLY=1 \
    RUMPELMC_BLOCK_EDIT_STRESS_MIN_COMPACT_SHADOW_PROXY=1 \
    RUMPELMC_BLOCK_EDIT_STRESS_MIN_PROXY_REFRESH_REUSE=1 \
    RUMPELMC_MOVEMENT_STRESS_TARGET_FPS="$TARGET_FPS" \
    sh "$ROOT_DIR/scripts/gpu_terrain_block_edit_stress.sh" "$run_dir" > "$run_log" 2>&1; then
    cat "$run_log" >&2
    fail "repeat run $index failed"
  fi

  stop_server_from_log "$run_log"

  marker_path="$run_dir/gpu-terrain-movement-stress.png.txt"
  test -s "$marker_path" || fail "missing marker $marker_path"
  require_text_metric_eq "$marker_path" dirty_last_edges "$EXPECTED_EDGES"
  require_text_metric_eq "$marker_path" dirty_last_bounds "$EXPECTED_BOUNDS"
  require_metric_ge "$marker_path" dirty_blocks 1
  require_metric_ge "$marker_path" dirty_partial_subchunks 1
  require_metric_ge "$marker_path" dirty_partial_saved_subchunks 1
  require_metric_ge "$marker_path" dirty_edge_neighbor_subchunks 1
  require_metric_ge "$marker_path" current_chunk_collision 1
  require_metric_ge "$marker_path" collision_refresh_last_rebuilt 1
  require_metric_ge "$marker_path" proxy_shadow 1
  require_metric_eq "$marker_path" gpu_upload_fail 0

  queue_max="$(perf_triplet_value terrain_queue_work_ms "$marker_path" 3)"
  compositor_max="$(perf_triplet_value gpu_compositor_submit_ms "$marker_path" 3)"
  process_wall_p95="$(float_metric process_wall_p95_ms "$marker_path")"
  test -n "$queue_max" || fail "missing terrain_queue_work_ms in $marker_path"
  test -n "$compositor_max" || fail "missing gpu_compositor_submit_ms in $marker_path"
  test -n "$process_wall_p95" || fail "missing process_wall_p95_ms in $marker_path"

  budget_ms="$(frame_budget_ms)"
  require_float_le_budget "terrain_queue_max_ms" "$queue_max" "$budget_ms"
  require_float_le_budget "gpu_compositor_submit_max_ms" "$compositor_max" "$budget_ms"
  require_float_le_budget "process_wall_p95_ms" "$process_wall_p95" "$budget_ms"

  printf 'run=%s dirty_blocks=%s dirty_last_rebuild_subchunks=%s dirty_edge_neighbor_subchunks=%s dirty_partial_subchunks=%s dirty_partial_saved_subchunks=%s current_chunk_collision=%s collision_refresh_last_rebuilt=%s proxy_shadow=%s compact_shadow_proxy=%s proxy_refresh_reuse=%s terrain_queue_max_ms=%s gpu_compositor_submit_max_ms=%s process_wall_p95_ms=%s gpu_upload_fail=%s status=pass\n' \
    "$index" \
    "$(metric dirty_blocks "$marker_path")" \
    "$(metric dirty_last_rebuild_subchunks "$marker_path")" \
    "$(metric dirty_edge_neighbor_subchunks "$marker_path")" \
    "$(metric dirty_partial_subchunks "$marker_path")" \
    "$(metric dirty_partial_saved_subchunks "$marker_path")" \
    "$(metric current_chunk_collision "$marker_path")" \
    "$(metric collision_refresh_last_rebuilt "$marker_path")" \
    "$(metric proxy_shadow "$marker_path")" \
    "$(metric compact_shadow_proxy "$marker_path")" \
    "$(metric proxy_refresh_reuse "$marker_path")" \
    "$queue_max" \
    "$compositor_max" \
    "$process_wall_p95" \
    "$(metric gpu_upload_fail "$marker_path")"
}

write_summary() {
  tmp_path="$SUMMARY_PATH.tmp"
  aggregate_path="$SUMMARY_PATH.aggregate"
  budget_ms="$(frame_budget_ms)"
  {
    printf 'GPU terrain edge dirty repeat summary repeats=%s target_fps=%s budget_ms=%s action=%s x=%s y=%s z=%s block_id=%s expected_edges=%s expected_bounds=%s\n' \
      "$REPEATS" "$TARGET_FPS" "$budget_ms" "$ACTION" "$EDIT_X" "$EDIT_Y" "$EDIT_Z" "$EDIT_BLOCK_ID" "$EXPECTED_EDGES" "$EXPECTED_BOUNDS"
    i=1
    while [ "$i" -le "$REPEATS" ]; do
      run_once "$i"
      i=$((i + 1))
    done
  } > "$tmp_path"

  awk '
    /^run=/ {
      runs += 1
      for (i = 1; i <= NF; i++) {
        split($i, kv, "=")
        key = kv[1]
        value = kv[2] + 0.0
        if (key == "terrain_queue_max_ms") {
          if (!queue_seen || value < queue_min) queue_min = value
          if (!queue_seen || value > queue_max) queue_max = value
          queue_seen = 1
        } else if (key == "gpu_compositor_submit_max_ms") {
          if (!submit_seen || value < submit_min) submit_min = value
          if (!submit_seen || value > submit_max) submit_max = value
          submit_seen = 1
        } else if (key == "process_wall_p95_ms") {
          if (!process_seen || value < process_min) process_min = value
          if (!process_seen || value > process_max) process_max = value
          process_seen = 1
        } else if (key == "dirty_edge_neighbor_subchunks") {
          if (!edge_seen || value < edge_min) edge_min = value
          if (!edge_seen || value > edge_max) edge_max = value
          edge_seen = 1
        } else if (key == "dirty_partial_saved_subchunks") {
          if (!saved_seen || value < saved_min) saved_min = value
          if (!saved_seen || value > saved_max) saved_max = value
          saved_seen = 1
        }
      }
    }
    END {
      if (runs > 0) {
        printf("aggregate runs=%d dirty_edge_neighbor_subchunks_min=%.0f dirty_edge_neighbor_subchunks_max=%.0f dirty_partial_saved_subchunks_min=%.0f dirty_partial_saved_subchunks_max=%.0f terrain_queue_max_ms_min=%.3f terrain_queue_max_ms_max=%.3f gpu_compositor_submit_max_ms_min=%.3f gpu_compositor_submit_max_ms_max=%.3f process_wall_p95_ms_min=%.3f process_wall_p95_ms_max=%.3f status=pass\n", runs, edge_min, edge_max, saved_min, saved_max, queue_min, queue_max, submit_min, submit_max, process_min, process_max)
      }
    }
  ' "$tmp_path" > "$aggregate_path"
  cat "$aggregate_path" >> "$tmp_path"
  rm -f "$aggregate_path"

  mv "$tmp_path" "$SUMMARY_PATH"
  cat "$SUMMARY_PATH"
}

case "$REPEATS" in
  ''|*[!0-9]*) fail "RUMPELMC_EDGE_DIRTY_REPEAT_COUNT must be a positive integer" ;;
esac
if [ "$REPEATS" -lt 1 ]; then
  fail "RUMPELMC_EDGE_DIRTY_REPEAT_COUNT must be at least 1"
fi

mkdir -p "$OUT_DIR"
if [ -n "$(listener_pid || true)" ]; then
  fail "port 25565 is already in use; stop the existing server before repeat"
fi
trap cleanup EXIT INT TERM

write_summary
wait_for_port_clear

echo "GPU terrain edge dirty repeat artifacts: $OUT_DIR"
