#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/gpu_terrain_grouped_draws_current"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

SUMMARY_PATH="$OUT_DIR/gpu-terrain-grouped-draws-summary.txt"

SERVER_VIEW_DISTANCE="${RUMPELMC_GROUPED_DRAWS_SERVER_VIEW_DISTANCE:-16}"
CLIENT_KEEP_CHUNK_DISTANCE="${RUMPELMC_GROUPED_DRAWS_CLIENT_KEEP_CHUNK_DISTANCE:-$SERVER_VIEW_DISTANCE}"
SERVER_CHUNKS_PER_UPDATE="${RUMPELMC_GROUPED_DRAWS_SERVER_CHUNKS_PER_UPDATE:-64}"
SMOKE_DELAY_SEC="${RUMPELMC_GROUPED_DRAWS_SMOKE_DELAY_SEC:-20.0}"
TARGET_FPS="${RUMPELMC_GROUPED_DRAWS_TARGET_FPS:-150}"
TERRAIN_PRESSURE_FIXTURE="${RUMPELMC_GROUPED_DRAWS_TERRAIN_PRESSURE_FIXTURE:-chunk_disc}"
TERRAIN_PRESSURE_FIXTURE_CHUNK_RADIUS="${RUMPELMC_GROUPED_DRAWS_TERRAIN_PRESSURE_FIXTURE_CHUNK_RADIUS:-15}"
TERRAIN_PRESSURE_FIXTURE_LOCAL_X="${RUMPELMC_GROUPED_DRAWS_TERRAIN_PRESSURE_FIXTURE_LOCAL_X:-16}"
TERRAIN_PRESSURE_FIXTURE_LOCAL_Z="${RUMPELMC_GROUPED_DRAWS_TERRAIN_PRESSURE_FIXTURE_LOCAL_Z:-16}"
TERRAIN_PRESSURE_FIXTURE_WAIT_SEC="${RUMPELMC_GROUPED_DRAWS_TERRAIN_PRESSURE_FIXTURE_WAIT_SEC:-90.0}"
TERRAIN_PRESSURE_FIXTURE_QUEUE_SETTLE_SEC="${RUMPELMC_GROUPED_DRAWS_TERRAIN_PRESSURE_FIXTURE_QUEUE_SETTLE_SEC:-90.0}"
TERRAIN_PRESSURE_FIXTURE_MAX_QUEUE="${RUMPELMC_GROUPED_DRAWS_TERRAIN_PRESSURE_FIXTURE_MAX_QUEUE:-16}"
MIN_FIXTURE_BLOCKS="${RUMPELMC_GROUPED_DRAWS_MIN_FIXTURE_BLOCKS:-512}"
MIN_GPU_SUBCHUNKS="${RUMPELMC_GROUPED_DRAWS_MIN_GPU_SUBCHUNKS:-512}"
MIN_GPU_FACES="${RUMPELMC_GROUPED_DRAWS_MIN_GPU_FACES:-512}"
MAX_SUBCHUNK_DELTA="${RUMPELMC_GROUPED_DRAWS_MAX_SUBCHUNK_DELTA:-16}"
MAX_FACE_DELTA="${RUMPELMC_GROUPED_DRAWS_MAX_FACE_DELTA:-128}"
MIN_SAVED_RECORDS="${RUMPELMC_GROUPED_DRAWS_MIN_SAVED_RECORDS:-1}"
MAX_TERRAIN_QUEUE_MS="${RUMPELMC_GROUPED_DRAWS_MAX_TERRAIN_QUEUE_MS:-6.667}"
MAX_PROCESS_WALL_P95_MS="${RUMPELMC_GROUPED_DRAWS_MAX_PROCESS_WALL_P95_MS:-6.667}"
MAX_GPU_COMPOSITOR_SUBMIT_MS="${RUMPELMC_GROUPED_DRAWS_MAX_GPU_COMPOSITOR_SUBMIT_MS:-6.667}"
GODOT_TIMEOUT_SEC="${GODOT_TIMEOUT_SEC:-900}"
GODOT_QUIT_AFTER_FRAMES="${GODOT_QUIT_AFTER_FRAMES:-42000}"

mkdir -p "$OUT_DIR"

fail() {
  echo "gpu_terrain_grouped_draws_gate: $*" >&2
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
  test -z "$pid" || fail "port 25565 is already in use by pid $pid; stop the existing server before grouped draws gate"
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
  stop_server_from_log "$OUT_DIR/baseline/pressure/run.log"
  stop_server_from_log "$OUT_DIR/grouped/pressure/run.log"
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
  grouped_flag="$2"
  lane_dir="$OUT_DIR/$lane"
  rocksdb_path="$OUT_DIR/$lane-rocksdb"
  rm -rf "$lane_dir" "$rocksdb_path"
  mkdir -p "$lane_dir"

  require_port_free
  echo "==> GPU terrain grouped draws gate: $lane grouped=$grouped_flag"
  set +e
  RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE="${RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE:-1}" \
    RUMPELMC_GODOT_RUST_EXT_PROFILE="${RUMPELMC_GODOT_RUST_EXT_PROFILE:-release}" \
    RUMPELMC_GPU_TERRAIN_GROUPED_DRAWS="$grouped_flag" \
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

run_lane baseline 0
run_lane grouped 1

baseline_summary="$OUT_DIR/baseline/workload-matrix-summary.txt"
grouped_summary="$OUT_DIR/grouped/workload-matrix-summary.txt"
test -s "$baseline_summary" || fail "missing baseline summary $baseline_summary"
test -s "$grouped_summary" || fail "missing grouped summary $grouped_summary"

baseline_fixture="$(require_case_field pressure terrain_pressure_fixture "$baseline_summary")"
baseline_server_reused="$(require_case_field pressure server_reused "$baseline_summary")"
baseline_fixture_blocks="$(require_case_field pressure terrain_pressure_fixture_blocks "$baseline_summary")"
baseline_subchunks="$(require_case_field pressure gpu_subchunks "$baseline_summary")"
baseline_draws="$(require_case_field pressure gpu_draws "$baseline_summary")"
baseline_faces="$(require_case_field pressure gpu_faces "$baseline_summary")"
baseline_cmd_bytes="$(require_case_field pressure gpu_draw_cmd_bytes "$baseline_summary")"
baseline_grouped_enabled="$(require_case_field pressure gpu_draw_grouped_enabled "$baseline_summary")"
baseline_logical_records="$(require_case_field pressure gpu_draw_records_logical "$baseline_summary")"
baseline_grouped_records="$(require_case_field pressure gpu_draw_records_grouped "$baseline_summary")"
baseline_saved_records="$(require_case_field pressure gpu_draw_grouped_saved_records "$baseline_summary")"
baseline_upload_fail="$(require_case_field pressure gpu_upload_fail "$baseline_summary")"
baseline_upload_fail_capacity="$(require_case_field pressure gpu_upload_fail_capacity "$baseline_summary")"
baseline_upload_fail_fragmented="$(require_case_field pressure gpu_upload_fail_fragmented "$baseline_summary")"
baseline_queue_ms="$(require_case_field pressure terrain_queue_max_ms "$baseline_summary")"
baseline_process_ms="$(require_case_field pressure process_wall_p95_ms "$baseline_summary")"
baseline_submit_ms="$(require_case_field pressure gpu_compositor_submit_max_ms "$baseline_summary")"
baseline_collision="$(require_case_field pressure current_chunk_collision "$baseline_summary")"
baseline_ground_misses="$(require_case_field pressure ground_misses "$baseline_summary")"
baseline_terrain_samples="$(require_case_field pressure terrain_samples "$baseline_summary")"

grouped_fixture="$(require_case_field pressure terrain_pressure_fixture "$grouped_summary")"
grouped_server_reused="$(require_case_field pressure server_reused "$grouped_summary")"
grouped_fixture_blocks="$(require_case_field pressure terrain_pressure_fixture_blocks "$grouped_summary")"
grouped_subchunks="$(require_case_field pressure gpu_subchunks "$grouped_summary")"
grouped_draws="$(require_case_field pressure gpu_draws "$grouped_summary")"
grouped_faces="$(require_case_field pressure gpu_faces "$grouped_summary")"
grouped_cmd_bytes="$(require_case_field pressure gpu_draw_cmd_bytes "$grouped_summary")"
grouped_grouped_enabled="$(require_case_field pressure gpu_draw_grouped_enabled "$grouped_summary")"
grouped_logical_records="$(require_case_field pressure gpu_draw_records_logical "$grouped_summary")"
grouped_grouped_records="$(require_case_field pressure gpu_draw_records_grouped "$grouped_summary")"
grouped_saved_records="$(require_case_field pressure gpu_draw_grouped_saved_records "$grouped_summary")"
grouped_upload_fail="$(require_case_field pressure gpu_upload_fail "$grouped_summary")"
grouped_upload_fail_capacity="$(require_case_field pressure gpu_upload_fail_capacity "$grouped_summary")"
grouped_upload_fail_fragmented="$(require_case_field pressure gpu_upload_fail_fragmented "$grouped_summary")"
grouped_queue_ms="$(require_case_field pressure terrain_queue_max_ms "$grouped_summary")"
grouped_process_ms="$(require_case_field pressure process_wall_p95_ms "$grouped_summary")"
grouped_submit_ms="$(require_case_field pressure gpu_compositor_submit_max_ms "$grouped_summary")"
grouped_collision="$(require_case_field pressure current_chunk_collision "$grouped_summary")"
grouped_ground_misses="$(require_case_field pressure ground_misses "$grouped_summary")"
grouped_terrain_samples="$(require_case_field pressure terrain_samples "$grouped_summary")"

awk \
  -v expected_fixture="$TERRAIN_PRESSURE_FIXTURE" \
  -v min_fixture_blocks="$MIN_FIXTURE_BLOCKS" \
  -v min_gpu_subchunks="$MIN_GPU_SUBCHUNKS" \
  -v min_gpu_faces="$MIN_GPU_FACES" \
  -v max_subchunk_delta="$MAX_SUBCHUNK_DELTA" \
  -v max_face_delta="$MAX_FACE_DELTA" \
  -v min_saved_records="$MIN_SAVED_RECORDS" \
  -v max_queue="$MAX_TERRAIN_QUEUE_MS" \
  -v max_process="$MAX_PROCESS_WALL_P95_MS" \
  -v max_submit="$MAX_GPU_COMPOSITOR_SUBMIT_MS" \
  -v baseline_fixture="$baseline_fixture" \
  -v baseline_server_reused="$baseline_server_reused" \
  -v baseline_fixture_blocks="$baseline_fixture_blocks" \
  -v baseline_subchunks="$baseline_subchunks" \
  -v baseline_draws="$baseline_draws" \
  -v baseline_faces="$baseline_faces" \
  -v baseline_cmd_bytes="$baseline_cmd_bytes" \
  -v baseline_grouped_enabled="$baseline_grouped_enabled" \
  -v baseline_logical_records="$baseline_logical_records" \
  -v baseline_grouped_records="$baseline_grouped_records" \
  -v baseline_saved_records="$baseline_saved_records" \
  -v baseline_upload_fail="$baseline_upload_fail" \
  -v baseline_upload_fail_capacity="$baseline_upload_fail_capacity" \
  -v baseline_upload_fail_fragmented="$baseline_upload_fail_fragmented" \
  -v baseline_queue_ms="$baseline_queue_ms" \
  -v baseline_process_ms="$baseline_process_ms" \
  -v baseline_submit_ms="$baseline_submit_ms" \
  -v baseline_collision="$baseline_collision" \
  -v baseline_ground_misses="$baseline_ground_misses" \
  -v baseline_terrain_samples="$baseline_terrain_samples" \
  -v grouped_fixture="$grouped_fixture" \
  -v grouped_server_reused="$grouped_server_reused" \
  -v grouped_fixture_blocks="$grouped_fixture_blocks" \
  -v grouped_subchunks="$grouped_subchunks" \
  -v grouped_draws="$grouped_draws" \
  -v grouped_faces="$grouped_faces" \
  -v grouped_cmd_bytes="$grouped_cmd_bytes" \
  -v grouped_grouped_enabled="$grouped_grouped_enabled" \
  -v grouped_logical_records="$grouped_logical_records" \
  -v grouped_grouped_records="$grouped_grouped_records" \
  -v grouped_saved_records="$grouped_saved_records" \
  -v grouped_upload_fail="$grouped_upload_fail" \
  -v grouped_upload_fail_capacity="$grouped_upload_fail_capacity" \
  -v grouped_upload_fail_fragmented="$grouped_upload_fail_fragmented" \
  -v grouped_queue_ms="$grouped_queue_ms" \
  -v grouped_process_ms="$grouped_process_ms" \
  -v grouped_submit_ms="$grouped_submit_ms" \
  -v grouped_collision="$grouped_collision" \
  -v grouped_ground_misses="$grouped_ground_misses" \
  -v grouped_terrain_samples="$grouped_terrain_samples" \
  -v baseline_summary="$baseline_summary" \
  -v grouped_summary="$grouped_summary" '
  function set_fail(why) {
    if (status == "pass") {
      status = "fail"
      reason = why
    }
  }
  BEGIN {
    status = "pass"
    reason = "grouped_draws_within_budget"
    baseline_upload_fail_total = baseline_upload_fail + baseline_upload_fail_capacity + baseline_upload_fail_fragmented
    grouped_upload_fail_total = grouped_upload_fail + grouped_upload_fail_capacity + grouped_upload_fail_fragmented
    subchunk_delta = baseline_subchunks > grouped_subchunks ? baseline_subchunks - grouped_subchunks : grouped_subchunks - baseline_subchunks
    face_delta = baseline_faces > grouped_faces ? baseline_faces - grouped_faces : grouped_faces - baseline_faces

    if (baseline_server_reused + 0 != 0 || grouped_server_reused + 0 != 0) {
      set_fail("server_reused")
    } else if (baseline_fixture != expected_fixture || grouped_fixture != expected_fixture) {
      set_fail("unexpected_pressure_fixture")
    } else if (baseline_fixture_blocks + 0 < min_fixture_blocks || grouped_fixture_blocks + 0 < min_fixture_blocks) {
      set_fail("fixture_pressure_too_low")
    } else if (baseline_subchunks + 0 < min_gpu_subchunks + 0 || grouped_subchunks + 0 < min_gpu_subchunks + 0 || baseline_faces + 0 < min_gpu_faces + 0 || grouped_faces + 0 < min_gpu_faces + 0) {
      set_fail("workload_pressure_too_low")
    } else if (baseline_grouped_enabled + 0 != 0 || grouped_grouped_enabled + 0 != 1) {
      set_fail("grouped_flag_mismatch")
    } else if (subchunk_delta + 0 > max_subchunk_delta + 0 || face_delta + 0 > max_face_delta + 0) {
      set_fail("workload_delta")
    } else if (baseline_logical_records + 0 != baseline_draws + 0 || baseline_grouped_records + 0 != baseline_draws + 0 || baseline_saved_records + 0 != 0) {
      set_fail("baseline_record_accounting")
    } else if (grouped_logical_records + 0 != baseline_logical_records + 0 || grouped_grouped_records + 0 != grouped_draws + 0) {
      set_fail("grouped_record_accounting")
    } else if (grouped_grouped_records + 0 >= baseline_draws + 0 || grouped_saved_records + 0 < min_saved_records + 0) {
      set_fail("grouped_records_not_reduced")
    } else if (grouped_cmd_bytes + 0 >= baseline_cmd_bytes + 0) {
      set_fail("draw_command_bytes_not_reduced")
    } else if (baseline_upload_fail_total > 0 || grouped_upload_fail_total > 0) {
      set_fail("upload_failure")
    } else if (baseline_queue_ms + 0.0 > max_queue + 0.0 || grouped_queue_ms + 0.0 > max_queue + 0.0) {
      set_fail("terrain_queue_budget")
    } else if (baseline_process_ms + 0.0 > max_process + 0.0 || grouped_process_ms + 0.0 > max_process + 0.0) {
      set_fail("process_wall_budget")
    } else if (baseline_submit_ms + 0.0 > max_submit + 0.0 || grouped_submit_ms + 0.0 > max_submit + 0.0) {
      set_fail("gpu_submit_budget")
    } else if (baseline_collision + 0 <= 0 || grouped_collision + 0 <= 0) {
      set_fail("current_collision_missing")
    } else if (baseline_ground_misses + 0 != 0 || grouped_ground_misses + 0 != 0) {
      set_fail("ground_misses")
    } else if (baseline_terrain_samples + 0 <= 0 || grouped_terrain_samples + 0 <= 0) {
      set_fail("terrain_samples_missing")
    }

    printf("gpu_terrain_grouped_draws status=%s reason=%s expected_fixture=%s min_fixture_blocks=%d min_gpu_subchunks=%d min_gpu_faces=%d max_subchunk_delta=%d max_face_delta=%d subchunk_delta=%d face_delta=%d min_saved_records=%d max_terrain_queue_ms=%.3f max_process_wall_p95_ms=%.3f max_gpu_compositor_submit_ms=%.3f ", status, reason, expected_fixture, min_fixture_blocks, min_gpu_subchunks, min_gpu_faces, max_subchunk_delta, max_face_delta, subchunk_delta, face_delta, min_saved_records, max_queue, max_process, max_submit)
    printf("baseline_fixture=%s baseline_fixture_blocks=%d baseline_subchunks=%d baseline_draws=%d baseline_faces=%d baseline_cmd_bytes=%d baseline_grouped_enabled=%d baseline_logical_records=%d baseline_grouped_records=%d baseline_saved_records=%d baseline_upload_fail=%d baseline_upload_fail_capacity=%d baseline_upload_fail_fragmented=%d baseline_terrain_queue_max_ms=%.3f baseline_process_wall_p95_ms=%.3f baseline_gpu_compositor_submit_max_ms=%.3f baseline_current_chunk_collision=%d baseline_ground_misses=%d baseline_terrain_samples=%d ", baseline_fixture, baseline_fixture_blocks, baseline_subchunks, baseline_draws, baseline_faces, baseline_cmd_bytes, baseline_grouped_enabled, baseline_logical_records, baseline_grouped_records, baseline_saved_records, baseline_upload_fail, baseline_upload_fail_capacity, baseline_upload_fail_fragmented, baseline_queue_ms, baseline_process_ms, baseline_submit_ms, baseline_collision, baseline_ground_misses, baseline_terrain_samples)
    printf("grouped_fixture=%s grouped_fixture_blocks=%d grouped_subchunks=%d grouped_draws=%d grouped_faces=%d grouped_cmd_bytes=%d grouped_grouped_enabled=%d grouped_logical_records=%d grouped_grouped_records=%d grouped_saved_records=%d grouped_upload_fail=%d grouped_upload_fail_capacity=%d grouped_upload_fail_fragmented=%d grouped_terrain_queue_max_ms=%.3f grouped_process_wall_p95_ms=%.3f grouped_gpu_compositor_submit_max_ms=%.3f grouped_current_chunk_collision=%d grouped_ground_misses=%d grouped_terrain_samples=%d baseline_summary=%s grouped_summary=%s\n", grouped_fixture, grouped_fixture_blocks, grouped_subchunks, grouped_draws, grouped_faces, grouped_cmd_bytes, grouped_grouped_enabled, grouped_logical_records, grouped_grouped_records, grouped_saved_records, grouped_upload_fail, grouped_upload_fail_capacity, grouped_upload_fail_fragmented, grouped_queue_ms, grouped_process_ms, grouped_submit_ms, grouped_collision, grouped_ground_misses, grouped_terrain_samples, baseline_summary, grouped_summary)
    if (status != "pass") {
      exit 1
    }
  }
' > "$SUMMARY_PATH" || {
  cat "$SUMMARY_PATH" >&2 || true
  fail "grouped draws compare failed"
}

cat "$SUMMARY_PATH"
echo "GPU terrain grouped draws artifacts: $OUT_DIR"
