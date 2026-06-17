#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/gpu_terrain_pressure_dirty_compare_current"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

SUMMARY_PATH="$OUT_DIR/gpu-terrain-pressure-dirty-compare-summary.txt"

SERVER_VIEW_DISTANCE="${RUMPELMC_PRESSURE_DIRTY_SERVER_VIEW_DISTANCE:-16}"
CLIENT_KEEP_CHUNK_DISTANCE="${RUMPELMC_PRESSURE_DIRTY_CLIENT_KEEP_CHUNK_DISTANCE:-$SERVER_VIEW_DISTANCE}"
SERVER_CHUNKS_PER_UPDATE="${RUMPELMC_PRESSURE_DIRTY_SERVER_CHUNKS_PER_UPDATE:-64}"
SMOKE_DELAY_SEC="${RUMPELMC_PRESSURE_DIRTY_SMOKE_DELAY_SEC:-20.0}"
TARGET_FPS="${RUMPELMC_PRESSURE_DIRTY_TARGET_FPS:-150}"
TERRAIN_PRESSURE_FIXTURE="${RUMPELMC_PRESSURE_DIRTY_TERRAIN_PRESSURE_FIXTURE:-chunk_disc}"
TERRAIN_PRESSURE_FIXTURE_CHUNK_RADIUS="${RUMPELMC_PRESSURE_DIRTY_TERRAIN_PRESSURE_FIXTURE_CHUNK_RADIUS:-15}"
TERRAIN_PRESSURE_FIXTURE_LOCAL_X="${RUMPELMC_PRESSURE_DIRTY_TERRAIN_PRESSURE_FIXTURE_LOCAL_X:-31}"
TERRAIN_PRESSURE_FIXTURE_LOCAL_Z="${RUMPELMC_PRESSURE_DIRTY_TERRAIN_PRESSURE_FIXTURE_LOCAL_Z:-31}"
TERRAIN_PRESSURE_FIXTURE_WAIT_SEC="${RUMPELMC_PRESSURE_DIRTY_TERRAIN_PRESSURE_FIXTURE_WAIT_SEC:-90.0}"
TERRAIN_PRESSURE_FIXTURE_QUEUE_SETTLE_SEC="${RUMPELMC_PRESSURE_DIRTY_TERRAIN_PRESSURE_FIXTURE_QUEUE_SETTLE_SEC:-90.0}"
TERRAIN_PRESSURE_FIXTURE_MAX_QUEUE="${RUMPELMC_PRESSURE_DIRTY_TERRAIN_PRESSURE_FIXTURE_MAX_QUEUE:-16}"
MIN_FIXTURE_BLOCKS="${RUMPELMC_PRESSURE_DIRTY_MIN_FIXTURE_BLOCKS:-512}"
MIN_DIRTY_BLOCKS="${RUMPELMC_PRESSURE_DIRTY_MIN_DIRTY_BLOCKS:-512}"
MIN_PARTIAL_SAVED_SUBCHUNKS="${RUMPELMC_PRESSURE_DIRTY_MIN_PARTIAL_SAVED_SUBCHUNKS:-1}"
MIN_EDGE_NEIGHBOR_SUBCHUNKS="${RUMPELMC_PRESSURE_DIRTY_MIN_EDGE_NEIGHBOR_SUBCHUNKS:-1}"
MAX_TERRAIN_QUEUE_MS="${RUMPELMC_PRESSURE_DIRTY_MAX_TERRAIN_QUEUE_MS:-6.667}"
MAX_PROCESS_WALL_P95_MS="${RUMPELMC_PRESSURE_DIRTY_MAX_PROCESS_WALL_P95_MS:-6.667}"
MAX_GPU_COMPOSITOR_SUBMIT_MS="${RUMPELMC_PRESSURE_DIRTY_MAX_GPU_COMPOSITOR_SUBMIT_MS:-6.667}"
GODOT_TIMEOUT_SEC="${GODOT_TIMEOUT_SEC:-900}"
GODOT_QUIT_AFTER_FRAMES="${GODOT_QUIT_AFTER_FRAMES:-42000}"

mkdir -p "$OUT_DIR"

fail() {
  echo "gpu_terrain_pressure_dirty_compare: $*" >&2
  exit 1
}

relative_path() {
  path="$1"
  case "$path" in
    "$ROOT_DIR"/*) printf '%s\n' "${path#$ROOT_DIR/}" ;;
    *) printf '%s\n' "$path" ;;
  esac
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

require_port_free() {
  pid="$(listener_pid || true)"
  test -z "$pid" || fail "port 25565 is already in use by pid $pid; stop the existing server before pressure dirty compare"
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

cleanup_lanes() {
  stop_server_from_log "$OUT_DIR/full/pressure/run.log"
  stop_server_from_log "$OUT_DIR/partial/pressure/run.log"
}

trap cleanup_lanes EXIT HUP INT TERM

case_field() {
  label="$1"
  key="$2"
  path="$3"
  awk -v label="$label" -v key="$key" '
    $1 == label {
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

require_case_field() {
  label="$1"
  key="$2"
  path="$3"
  value="$(case_field "$label" "$key" "$path")"
  test -n "$value" || fail "missing $label $key in $(relative_path "$path")"
  printf '%s\n' "$value"
}

run_lane() {
  lane="$1"
  partial_flag="$2"
  lane_dir="$OUT_DIR/$lane"
  rocksdb_path="$OUT_DIR/$lane-rocksdb"
  rm -rf "$lane_dir" "$rocksdb_path"
  mkdir -p "$lane_dir"

  require_port_free
  echo "==> GPU terrain pressure dirty compare: $lane partial_dirty=$partial_flag"
  set +e
  RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE="${RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE:-1}" \
    RUMPELMC_GODOT_RUST_EXT_PROFILE="${RUMPELMC_GODOT_RUST_EXT_PROFILE:-release}" \
    RUMPELMC_GPU_TERRAIN_PARTIAL_DIRTY_UPLOAD="$partial_flag" \
    RUMPELMC_SERVER_ROCKSDB_PATH="$rocksdb_path" \
    RUMPELMC_WORKLOAD_MATRIX_CASE_SET=pressure \
    RUMPELMC_WORKLOAD_MATRIX_SERVER_VIEW_DISTANCE="$SERVER_VIEW_DISTANCE" \
    RUMPELMC_WORKLOAD_MATRIX_CLIENT_KEEP_CHUNK_DISTANCE="$CLIENT_KEEP_CHUNK_DISTANCE" \
    RUMPELMC_WORKLOAD_MATRIX_SERVER_CHUNKS_PER_UPDATE="$SERVER_CHUNKS_PER_UPDATE" \
    RUMPELMC_WORKLOAD_MATRIX_SMOKE_DELAY_SEC="$SMOKE_DELAY_SEC" \
    RUMPELMC_WORKLOAD_MATRIX_TARGET_FPS="$TARGET_FPS" \
    RUMPELMC_WORKLOAD_MATRIX_TERRAIN_PRESSURE_FIXTURE="$TERRAIN_PRESSURE_FIXTURE" \
    RUMPELMC_WORKLOAD_MATRIX_TERRAIN_PRESSURE_FIXTURE_CHUNK_RADIUS="$TERRAIN_PRESSURE_FIXTURE_CHUNK_RADIUS" \
    RUMPELMC_WORKLOAD_MATRIX_TERRAIN_PRESSURE_FIXTURE_LOCAL_X="$TERRAIN_PRESSURE_FIXTURE_LOCAL_X" \
    RUMPELMC_WORKLOAD_MATRIX_TERRAIN_PRESSURE_FIXTURE_LOCAL_Z="$TERRAIN_PRESSURE_FIXTURE_LOCAL_Z" \
    RUMPELMC_WORKLOAD_MATRIX_TERRAIN_PRESSURE_FIXTURE_WAIT_SEC="$TERRAIN_PRESSURE_FIXTURE_WAIT_SEC" \
    RUMPELMC_WORKLOAD_MATRIX_TERRAIN_PRESSURE_FIXTURE_QUEUE_SETTLE_SEC="$TERRAIN_PRESSURE_FIXTURE_QUEUE_SETTLE_SEC" \
    RUMPELMC_WORKLOAD_MATRIX_TERRAIN_PRESSURE_FIXTURE_MAX_QUEUE="$TERRAIN_PRESSURE_FIXTURE_MAX_QUEUE" \
    GODOT_TIMEOUT_SEC="$GODOT_TIMEOUT_SEC" \
    GODOT_QUIT_AFTER_FRAMES="$GODOT_QUIT_AFTER_FRAMES" \
    /bin/sh "$ROOT_DIR/scripts/gpu_terrain_workload_matrix.sh" "$lane_dir" > "$lane_dir/run.log" 2>&1
  status="$?"
  set -e
  stop_server_from_log "$lane_dir/pressure/run.log"
  if [ "$status" -ne 0 ]; then
    cat "$lane_dir/run.log" >&2 || true
    fail "$lane pressure workload failed"
  fi
  wait_for_port_clear
}

run_lane full 0
run_lane partial 1

full_summary="$OUT_DIR/full/workload-matrix-summary.txt"
partial_summary="$OUT_DIR/partial/workload-matrix-summary.txt"
test -s "$full_summary" || fail "missing full summary $full_summary"
test -s "$partial_summary" || fail "missing partial summary $partial_summary"

full_fixture="$(require_case_field pressure terrain_pressure_fixture "$full_summary")"
full_fixture_blocks="$(require_case_field pressure terrain_pressure_fixture_blocks "$full_summary")"
full_dirty_observed="$(require_case_field pressure terrain_pressure_fixture_dirty_observed "$full_summary")"
full_dirty_blocks="$(require_case_field pressure dirty_blocks "$full_summary")"
full_dirty_rebuild_subchunks="$(require_case_field pressure dirty_rebuild_subchunks "$full_summary")"
full_dirty_partial_subchunks="$(require_case_field pressure dirty_partial_subchunks "$full_summary")"
full_dirty_partial_saved_subchunks="$(require_case_field pressure dirty_partial_saved_subchunks "$full_summary")"
full_dirty_edge_neighbor_subchunks="$(require_case_field pressure dirty_edge_neighbor_subchunks "$full_summary")"
full_upload_fail="$(require_case_field pressure gpu_upload_fail "$full_summary")"
full_upload_fail_capacity="$(require_case_field pressure gpu_upload_fail_capacity "$full_summary")"
full_upload_fail_fragmented="$(require_case_field pressure gpu_upload_fail_fragmented "$full_summary")"
full_queue_ms="$(require_case_field pressure terrain_queue_max_ms "$full_summary")"
full_process_p95_ms="$(require_case_field pressure process_wall_p95_ms "$full_summary")"
full_submit_ms="$(require_case_field pressure gpu_compositor_submit_max_ms "$full_summary")"
full_collision="$(require_case_field pressure current_chunk_collision "$full_summary")"
full_ground_misses="$(require_case_field pressure ground_misses "$full_summary")"
full_terrain_samples="$(require_case_field pressure terrain_samples "$full_summary")"

partial_fixture="$(require_case_field pressure terrain_pressure_fixture "$partial_summary")"
partial_fixture_blocks="$(require_case_field pressure terrain_pressure_fixture_blocks "$partial_summary")"
partial_dirty_observed="$(require_case_field pressure terrain_pressure_fixture_dirty_observed "$partial_summary")"
partial_dirty_blocks="$(require_case_field pressure dirty_blocks "$partial_summary")"
partial_dirty_rebuild_subchunks="$(require_case_field pressure dirty_rebuild_subchunks "$partial_summary")"
partial_dirty_partial_subchunks="$(require_case_field pressure dirty_partial_subchunks "$partial_summary")"
partial_dirty_partial_saved_subchunks="$(require_case_field pressure dirty_partial_saved_subchunks "$partial_summary")"
partial_dirty_edge_chunks="$(require_case_field pressure dirty_edge_chunks "$partial_summary")"
partial_dirty_edge_neighbor_chunks="$(require_case_field pressure dirty_edge_neighbor_chunks "$partial_summary")"
partial_dirty_edge_neighbor_subchunks="$(require_case_field pressure dirty_edge_neighbor_subchunks "$partial_summary")"
partial_dirty_last_edges="$(require_case_field pressure dirty_last_edges "$partial_summary")"
partial_dirty_last_bounds="$(require_case_field pressure dirty_last_bounds "$partial_summary")"
partial_upload_fail="$(require_case_field pressure gpu_upload_fail "$partial_summary")"
partial_upload_fail_capacity="$(require_case_field pressure gpu_upload_fail_capacity "$partial_summary")"
partial_upload_fail_fragmented="$(require_case_field pressure gpu_upload_fail_fragmented "$partial_summary")"
partial_queue_ms="$(require_case_field pressure terrain_queue_max_ms "$partial_summary")"
partial_process_p95_ms="$(require_case_field pressure process_wall_p95_ms "$partial_summary")"
partial_submit_ms="$(require_case_field pressure gpu_compositor_submit_max_ms "$partial_summary")"
partial_collision="$(require_case_field pressure current_chunk_collision "$partial_summary")"
partial_ground_misses="$(require_case_field pressure ground_misses "$partial_summary")"
partial_terrain_samples="$(require_case_field pressure terrain_samples "$partial_summary")"

awk \
  -v expected_fixture="$TERRAIN_PRESSURE_FIXTURE" \
  -v min_fixture_blocks="$MIN_FIXTURE_BLOCKS" \
  -v min_dirty_blocks="$MIN_DIRTY_BLOCKS" \
  -v min_partial_saved="$MIN_PARTIAL_SAVED_SUBCHUNKS" \
  -v min_edge_neighbor_subchunks="$MIN_EDGE_NEIGHBOR_SUBCHUNKS" \
  -v max_queue="$MAX_TERRAIN_QUEUE_MS" \
  -v max_process="$MAX_PROCESS_WALL_P95_MS" \
  -v max_submit="$MAX_GPU_COMPOSITOR_SUBMIT_MS" \
  -v target_fps="$TARGET_FPS" \
  -v local_x="$TERRAIN_PRESSURE_FIXTURE_LOCAL_X" \
  -v local_z="$TERRAIN_PRESSURE_FIXTURE_LOCAL_Z" \
  -v full_fixture="$full_fixture" \
  -v full_fixture_blocks="$full_fixture_blocks" \
  -v full_dirty_observed="$full_dirty_observed" \
  -v full_dirty_blocks="$full_dirty_blocks" \
  -v full_dirty_rebuild_subchunks="$full_dirty_rebuild_subchunks" \
  -v full_dirty_partial_subchunks="$full_dirty_partial_subchunks" \
  -v full_dirty_partial_saved_subchunks="$full_dirty_partial_saved_subchunks" \
  -v full_dirty_edge_neighbor_subchunks="$full_dirty_edge_neighbor_subchunks" \
  -v full_upload_fail="$full_upload_fail" \
  -v full_upload_fail_capacity="$full_upload_fail_capacity" \
  -v full_upload_fail_fragmented="$full_upload_fail_fragmented" \
  -v full_queue_ms="$full_queue_ms" \
  -v full_process_p95_ms="$full_process_p95_ms" \
  -v full_submit_ms="$full_submit_ms" \
  -v full_collision="$full_collision" \
  -v full_ground_misses="$full_ground_misses" \
  -v full_terrain_samples="$full_terrain_samples" \
  -v partial_fixture="$partial_fixture" \
  -v partial_fixture_blocks="$partial_fixture_blocks" \
  -v partial_dirty_observed="$partial_dirty_observed" \
  -v partial_dirty_blocks="$partial_dirty_blocks" \
  -v partial_dirty_rebuild_subchunks="$partial_dirty_rebuild_subchunks" \
  -v partial_dirty_partial_subchunks="$partial_dirty_partial_subchunks" \
  -v partial_dirty_partial_saved_subchunks="$partial_dirty_partial_saved_subchunks" \
  -v partial_dirty_edge_chunks="$partial_dirty_edge_chunks" \
  -v partial_dirty_edge_neighbor_chunks="$partial_dirty_edge_neighbor_chunks" \
  -v partial_dirty_edge_neighbor_subchunks="$partial_dirty_edge_neighbor_subchunks" \
  -v partial_dirty_last_edges="$partial_dirty_last_edges" \
  -v partial_dirty_last_bounds="$partial_dirty_last_bounds" \
  -v partial_upload_fail="$partial_upload_fail" \
  -v partial_upload_fail_capacity="$partial_upload_fail_capacity" \
  -v partial_upload_fail_fragmented="$partial_upload_fail_fragmented" \
  -v partial_queue_ms="$partial_queue_ms" \
  -v partial_process_p95_ms="$partial_process_p95_ms" \
  -v partial_submit_ms="$partial_submit_ms" \
  -v partial_collision="$partial_collision" \
  -v partial_ground_misses="$partial_ground_misses" \
  -v partial_terrain_samples="$partial_terrain_samples" \
  -v full_summary="$full_summary" \
  -v partial_summary="$partial_summary" '
  function set_fail(why) {
    if (status == "pass") {
      status = "fail"
      reason = why
    }
  }
  BEGIN {
    status = "pass"
    reason = "pressure_dirty_compare_within_budget"
    full_upload_fail_total = full_upload_fail + full_upload_fail_capacity + full_upload_fail_fragmented
    partial_upload_fail_total = partial_upload_fail + partial_upload_fail_capacity + partial_upload_fail_fragmented

    if (full_fixture != expected_fixture || partial_fixture != expected_fixture) {
      set_fail("unexpected_pressure_fixture")
    } else if (full_fixture_blocks + 0 < min_fixture_blocks || partial_fixture_blocks + 0 < min_fixture_blocks) {
      set_fail("fixture_pressure_too_low")
    } else if (full_dirty_observed + 0 != 1 || partial_dirty_observed + 0 != 1) {
      set_fail("fixture_dirty_not_observed")
    } else if (full_dirty_blocks + 0 < min_dirty_blocks || partial_dirty_blocks + 0 < min_dirty_blocks) {
      set_fail("dirty_pressure_too_low")
    } else if (full_dirty_rebuild_subchunks + 0 <= 0 || partial_dirty_rebuild_subchunks + 0 <= 0) {
      set_fail("dirty_rebuild_missing")
    } else if (full_dirty_partial_subchunks + 0 != 0 || full_dirty_partial_saved_subchunks + 0 != 0) {
      set_fail("full_lane_partial_not_disabled")
    } else if (partial_dirty_partial_subchunks + 0 <= 0) {
      set_fail("partial_lane_missing_partial_subchunks")
    } else if (partial_dirty_partial_saved_subchunks + 0 < min_partial_saved + 0) {
      set_fail("partial_lane_missing_saved_subchunks")
    } else if (partial_dirty_edge_chunks + 0 <= 0 || partial_dirty_edge_neighbor_chunks + 0 <= 0 || partial_dirty_edge_neighbor_subchunks + 0 < min_edge_neighbor_subchunks + 0) {
      set_fail("partial_lane_missing_edge_refresh")
    } else if (partial_dirty_last_edges == "none") {
      set_fail("partial_lane_missing_edge_label")
    } else if (full_upload_fail_total > 0 || partial_upload_fail_total > 0) {
      set_fail("upload_failure")
    } else if (full_queue_ms + 0.0 > max_queue + 0.0 || partial_queue_ms + 0.0 > max_queue + 0.0) {
      set_fail("terrain_queue_budget")
    } else if (full_process_p95_ms + 0.0 > max_process + 0.0 || partial_process_p95_ms + 0.0 > max_process + 0.0) {
      set_fail("process_wall_budget")
    } else if (full_submit_ms + 0.0 > max_submit + 0.0 || partial_submit_ms + 0.0 > max_submit + 0.0) {
      set_fail("gpu_submit_budget")
    } else if (full_collision + 0 <= 0 || partial_collision + 0 <= 0) {
      set_fail("current_collision_missing")
    } else if (full_ground_misses + 0 != 0 || partial_ground_misses + 0 != 0) {
      set_fail("ground_misses")
    } else if (full_terrain_samples + 0 <= 0 || partial_terrain_samples + 0 <= 0) {
      set_fail("terrain_samples_missing")
    }

    printf("gpu_terrain_pressure_dirty_compare status=%s reason=%s target_fps=%s local_x=%s local_z=%s expected_fixture=%s min_fixture_blocks=%d min_dirty_blocks=%d min_partial_saved_subchunks=%d min_edge_neighbor_subchunks=%d max_terrain_queue_ms=%.3f max_process_wall_p95_ms=%.3f max_gpu_compositor_submit_ms=%.3f ", status, reason, target_fps, local_x, local_z, expected_fixture, min_fixture_blocks, min_dirty_blocks, min_partial_saved, min_edge_neighbor_subchunks, max_queue, max_process, max_submit)
    printf("full_fixture=%s full_fixture_blocks=%d full_dirty_observed=%d full_dirty_blocks=%d full_dirty_rebuild_subchunks=%d full_dirty_partial_subchunks=%d full_dirty_partial_saved_subchunks=%d full_dirty_edge_neighbor_subchunks=%d full_upload_fail=%d full_upload_fail_capacity=%d full_upload_fail_fragmented=%d full_terrain_queue_max_ms=%.3f full_process_wall_p95_ms=%.3f full_gpu_compositor_submit_max_ms=%.3f full_current_chunk_collision=%d full_ground_misses=%d full_terrain_samples=%d ", full_fixture, full_fixture_blocks, full_dirty_observed, full_dirty_blocks, full_dirty_rebuild_subchunks, full_dirty_partial_subchunks, full_dirty_partial_saved_subchunks, full_dirty_edge_neighbor_subchunks, full_upload_fail, full_upload_fail_capacity, full_upload_fail_fragmented, full_queue_ms, full_process_p95_ms, full_submit_ms, full_collision, full_ground_misses, full_terrain_samples)
    printf("partial_fixture=%s partial_fixture_blocks=%d partial_dirty_observed=%d partial_dirty_blocks=%d partial_dirty_rebuild_subchunks=%d partial_dirty_partial_subchunks=%d partial_dirty_partial_saved_subchunks=%d partial_dirty_edge_chunks=%d partial_dirty_edge_neighbor_chunks=%d partial_dirty_edge_neighbor_subchunks=%d partial_dirty_last_edges=%s partial_dirty_last_bounds=%s partial_upload_fail=%d partial_upload_fail_capacity=%d partial_upload_fail_fragmented=%d partial_terrain_queue_max_ms=%.3f partial_process_wall_p95_ms=%.3f partial_gpu_compositor_submit_max_ms=%.3f partial_current_chunk_collision=%d partial_ground_misses=%d partial_terrain_samples=%d full_summary=%s partial_summary=%s\n", partial_fixture, partial_fixture_blocks, partial_dirty_observed, partial_dirty_blocks, partial_dirty_rebuild_subchunks, partial_dirty_partial_subchunks, partial_dirty_partial_saved_subchunks, partial_dirty_edge_chunks, partial_dirty_edge_neighbor_chunks, partial_dirty_edge_neighbor_subchunks, partial_dirty_last_edges, partial_dirty_last_bounds, partial_upload_fail, partial_upload_fail_capacity, partial_upload_fail_fragmented, partial_queue_ms, partial_process_p95_ms, partial_submit_ms, partial_collision, partial_ground_misses, partial_terrain_samples, full_summary, partial_summary)
    if (status != "pass") {
      exit 1
    }
  }
' > "$SUMMARY_PATH" || {
  cat "$SUMMARY_PATH" >&2 || true
  fail "pressure dirty compare failed"
}

cat "$SUMMARY_PATH"
echo "GPU terrain pressure dirty compare artifacts: $OUT_DIR"
