#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/gpu_terrain_upload_stage_pool_load_scaling_current"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

BASELINE_DIR="$OUT_DIR/baseline-load-scaling"
POOLED_DIR="$OUT_DIR/pooled-load-scaling"
BASELINE_DB="$OUT_DIR/baseline-rocksdb"
POOLED_DB="$OUT_DIR/pooled-rocksdb"
BASELINE_LOG="$OUT_DIR/baseline-load-scaling.log"
POOLED_LOG="$OUT_DIR/pooled-load-scaling.log"
SUMMARY_PATH="$OUT_DIR/gpu-terrain-upload-stage-pool-load-scaling-summary.txt"

BASELINE_SUMMARY="${RUMPELMC_GPU_STAGE_POOL_LOAD_BASELINE_SUMMARY:-}"
POOLED_SUMMARY="${RUMPELMC_GPU_STAGE_POOL_LOAD_POOLED_SUMMARY:-}"
MIN_GPU_SUBCHUNKS="${RUMPELMC_GPU_STAGE_POOL_LOAD_MIN_GPU_SUBCHUNKS:-2000}"
MIN_GPU_DRAWS="${RUMPELMC_GPU_STAGE_POOL_LOAD_MIN_GPU_DRAWS:-2000}"
MIN_GPU_FACES="${RUMPELMC_GPU_STAGE_POOL_LOAD_MIN_GPU_FACES:-3000}"
MIN_DRAW_CMD_OCCUPANCY_PCT="${RUMPELMC_GPU_STAGE_POOL_LOAD_MIN_DRAW_CMD_OCCUPANCY_PCT:-25.0}"
MAX_TERRAIN_QUEUE_MS="${RUMPELMC_GPU_STAGE_POOL_LOAD_MAX_TERRAIN_QUEUE_MS:-6.667}"
MAX_PROCESS_WALL_P95_MS="${RUMPELMC_GPU_STAGE_POOL_LOAD_MAX_PROCESS_WALL_P95_MS:-6.667}"
MAX_GPU_COMPOSITOR_SUBMIT_MS="${RUMPELMC_GPU_STAGE_POOL_LOAD_MAX_GPU_COMPOSITOR_SUBMIT_MS:-6.667}"
MIN_REUSES="${RUMPELMC_GPU_STAGE_POOL_LOAD_MIN_REUSES:-1}"
CASE_SET="${RUMPELMC_GPU_STAGE_POOL_LOAD_CASE_SET:-pressure}"
SERVER_VIEW_DISTANCE="${RUMPELMC_GPU_STAGE_POOL_LOAD_SERVER_VIEW_DISTANCE:-16}"
CLIENT_KEEP_CHUNK_DISTANCE="${RUMPELMC_GPU_STAGE_POOL_LOAD_CLIENT_KEEP_CHUNK_DISTANCE:-$SERVER_VIEW_DISTANCE}"
SERVER_CHUNKS_PER_UPDATE="${RUMPELMC_GPU_STAGE_POOL_LOAD_SERVER_CHUNKS_PER_UPDATE:-64}"
SMOKE_DELAY_SEC="${RUMPELMC_GPU_STAGE_POOL_LOAD_SMOKE_DELAY_SEC:-20.0}"
TERRAIN_PRESSURE_FIXTURE="${RUMPELMC_GPU_STAGE_POOL_LOAD_TERRAIN_PRESSURE_FIXTURE:-chunk_disc}"
TERRAIN_PRESSURE_FIXTURE_CHUNK_COLUMNS="${RUMPELMC_GPU_STAGE_POOL_LOAD_TERRAIN_PRESSURE_FIXTURE_CHUNK_COLUMNS:-28}"
TERRAIN_PRESSURE_FIXTURE_CHUNK_ROWS="${RUMPELMC_GPU_STAGE_POOL_LOAD_TERRAIN_PRESSURE_FIXTURE_CHUNK_ROWS:-24}"
TERRAIN_PRESSURE_FIXTURE_CHUNK_RADIUS="${RUMPELMC_GPU_STAGE_POOL_LOAD_TERRAIN_PRESSURE_FIXTURE_CHUNK_RADIUS:-15}"
TERRAIN_PRESSURE_FIXTURE_WAIT_SEC="${RUMPELMC_GPU_STAGE_POOL_LOAD_TERRAIN_PRESSURE_FIXTURE_WAIT_SEC:-90.0}"
TERRAIN_PRESSURE_FIXTURE_QUEUE_SETTLE_SEC="${RUMPELMC_GPU_STAGE_POOL_LOAD_TERRAIN_PRESSURE_FIXTURE_QUEUE_SETTLE_SEC:-90.0}"
TERRAIN_PRESSURE_FIXTURE_MAX_QUEUE="${RUMPELMC_GPU_STAGE_POOL_LOAD_TERRAIN_PRESSURE_FIXTURE_MAX_QUEUE:-16}"
MIN_TERRAIN_PRESSURE_FIXTURE_BLOCKS="${RUMPELMC_GPU_STAGE_POOL_LOAD_MIN_TERRAIN_PRESSURE_FIXTURE_BLOCKS:-512}"

fail() {
  echo "gpu_terrain_upload_stage_pool_load_scaling_gate: $*" >&2
  exit 1
}

relative_path() {
  path="$1"
  case "$path" in
    "$ROOT_DIR"/*) printf '%s\n' "${path#$ROOT_DIR/}" ;;
    *) printf '%s\n' "$path" ;;
  esac
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

require_field() {
  key="$1"
  path="$2"
  value="$(field_metric "$key" "$path")"
  test -n "$value" || fail "missing $key in $(relative_path "$path")"
  printf '%s\n' "$value"
}

require_positive_integer() {
  name="$1"
  value="$2"
  case "$value" in
    ''|*[!0-9]*) fail "$name must be an integer" ;;
  esac
  if [ "$value" -lt 1 ]; then
    fail "$name must be at least 1"
  fi
}

listener_pid() {
  if command -v lsof >/dev/null 2>&1; then
    lsof -tiTCP:25565 -sTCP:LISTEN 2>/dev/null | sed -n '1p'
  fi
}

cleanup_port() {
  pid="$(listener_pid || true)"
  if [ -n "$pid" ]; then
    kill "$pid" 2>/dev/null || true
  fi
}

run_load_scaling() {
  pool_enabled="$1"
  run_dir="$2"
  db_path="$3"
  log_path="$4"
  run_rc=0
  RUMPELMC_SERVER_ROCKSDB_PATH="$db_path" \
  RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE="${RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE:-1}" \
  RUMPELMC_GODOT_RUST_EXT_PROFILE="${RUMPELMC_GODOT_RUST_EXT_PROFILE:-release}" \
  RUMPELMC_GPU_TERRAIN_UPLOAD_STAGE_POOL="$pool_enabled" \
  RUMPELMC_RESIDENT_SET_CASE_SET="$CASE_SET" \
  RUMPELMC_RESIDENT_SET_SERVER_VIEW_DISTANCE="$SERVER_VIEW_DISTANCE" \
  RUMPELMC_RESIDENT_SET_CLIENT_KEEP_CHUNK_DISTANCE="$CLIENT_KEEP_CHUNK_DISTANCE" \
  RUMPELMC_RESIDENT_SET_SERVER_CHUNKS_PER_UPDATE="$SERVER_CHUNKS_PER_UPDATE" \
  RUMPELMC_RESIDENT_SET_SMOKE_DELAY_SEC="$SMOKE_DELAY_SEC" \
  RUMPELMC_RESIDENT_SET_TERRAIN_PRESSURE_FIXTURE="$TERRAIN_PRESSURE_FIXTURE" \
  RUMPELMC_RESIDENT_SET_TERRAIN_PRESSURE_FIXTURE_CHUNK_COLUMNS="$TERRAIN_PRESSURE_FIXTURE_CHUNK_COLUMNS" \
  RUMPELMC_RESIDENT_SET_TERRAIN_PRESSURE_FIXTURE_CHUNK_ROWS="$TERRAIN_PRESSURE_FIXTURE_CHUNK_ROWS" \
  RUMPELMC_RESIDENT_SET_TERRAIN_PRESSURE_FIXTURE_CHUNK_RADIUS="$TERRAIN_PRESSURE_FIXTURE_CHUNK_RADIUS" \
  RUMPELMC_RESIDENT_SET_TERRAIN_PRESSURE_FIXTURE_WAIT_SEC="$TERRAIN_PRESSURE_FIXTURE_WAIT_SEC" \
  RUMPELMC_RESIDENT_SET_TERRAIN_PRESSURE_FIXTURE_QUEUE_SETTLE_SEC="$TERRAIN_PRESSURE_FIXTURE_QUEUE_SETTLE_SEC" \
  RUMPELMC_RESIDENT_SET_TERRAIN_PRESSURE_FIXTURE_MAX_QUEUE="$TERRAIN_PRESSURE_FIXTURE_MAX_QUEUE" \
  GODOT_QUIT_AFTER_FRAMES="${GODOT_QUIT_AFTER_FRAMES:-36000}" \
  GODOT_TIMEOUT_SEC="${GODOT_TIMEOUT_SEC:-600}" \
  sh "$ROOT_DIR/scripts/gpu_terrain_load_scaling.sh" "$run_dir" > "$log_path" 2>&1 || run_rc=$?
  cleanup_port
  if [ "$run_rc" -ne 0 ]; then
    tail -n 120 "$log_path" >&2 || true
    fail "load-scaling gate failed with exit code $run_rc for stage pool=$pool_enabled"
  fi
}

write_summary() {
  baseline_status="$(require_field status "$BASELINE_SUMMARY")"
  baseline_source_status="$(require_field source_status "$BASELINE_SUMMARY")"
  baseline_case_set="$(require_field source_case_set "$BASELINE_SUMMARY")"
  baseline_terrain_pressure_fixture="$(require_field terrain_pressure_fixture "$BASELINE_SUMMARY")"
  baseline_subchunks="$(require_field max_gpu_subchunks "$BASELINE_SUMMARY")"
  baseline_draws="$(require_field max_gpu_draws "$BASELINE_SUMMARY")"
  baseline_faces="$(require_field max_gpu_faces "$BASELINE_SUMMARY")"
  baseline_occupancy="$(require_field gpu_draw_cmd_occupancy_pct "$BASELINE_SUMMARY")"
  baseline_queue="$(require_field max_terrain_queue_ms "$BASELINE_SUMMARY")"
  baseline_process="$(require_field max_process_wall_p95_ms "$BASELINE_SUMMARY")"
  baseline_submit="$(require_field max_gpu_compositor_submit_ms "$BASELINE_SUMMARY")"
  baseline_uploads="$(require_field max_gpu_uploads "$BASELINE_SUMMARY")"
  baseline_upload_fail="$(require_field gpu_upload_fail "$BASELINE_SUMMARY")"
  baseline_upload_fail_capacity="$(require_field gpu_upload_fail_capacity "$BASELINE_SUMMARY")"
  baseline_upload_fail_fragmented="$(require_field gpu_upload_fail_fragmented "$BASELINE_SUMMARY")"
  baseline_stage_enabled="$(require_field gpu_upload_stage_pool_enabled "$BASELINE_SUMMARY")"
  baseline_stage_entries="$(require_field gpu_upload_stage_pool_entries "$BASELINE_SUMMARY")"
  baseline_stage_bytes="$(require_field gpu_upload_stage_pool_bytes "$BASELINE_SUMMARY")"
  baseline_stage_creates="$(require_field gpu_upload_stage_pba_creates "$BASELINE_SUMMARY")"
  baseline_stage_reuses="$(require_field gpu_upload_stage_pba_reuses "$BASELINE_SUMMARY")"
  baseline_terrain_pressure_fixture_blocks="$(require_field terrain_pressure_fixture_blocks "$BASELINE_SUMMARY")"
  baseline_terrain_pressure_fixture_dirty_observed="$(require_field terrain_pressure_fixture_dirty_observed "$BASELINE_SUMMARY")"

  pooled_status="$(require_field status "$POOLED_SUMMARY")"
  pooled_source_status="$(require_field source_status "$POOLED_SUMMARY")"
  pooled_case_set="$(require_field source_case_set "$POOLED_SUMMARY")"
  pooled_terrain_pressure_fixture="$(require_field terrain_pressure_fixture "$POOLED_SUMMARY")"
  pooled_subchunks="$(require_field max_gpu_subchunks "$POOLED_SUMMARY")"
  pooled_draws="$(require_field max_gpu_draws "$POOLED_SUMMARY")"
  pooled_faces="$(require_field max_gpu_faces "$POOLED_SUMMARY")"
  pooled_occupancy="$(require_field gpu_draw_cmd_occupancy_pct "$POOLED_SUMMARY")"
  pooled_queue="$(require_field max_terrain_queue_ms "$POOLED_SUMMARY")"
  pooled_process="$(require_field max_process_wall_p95_ms "$POOLED_SUMMARY")"
  pooled_submit="$(require_field max_gpu_compositor_submit_ms "$POOLED_SUMMARY")"
  pooled_uploads="$(require_field max_gpu_uploads "$POOLED_SUMMARY")"
  pooled_upload_fail="$(require_field gpu_upload_fail "$POOLED_SUMMARY")"
  pooled_upload_fail_capacity="$(require_field gpu_upload_fail_capacity "$POOLED_SUMMARY")"
  pooled_upload_fail_fragmented="$(require_field gpu_upload_fail_fragmented "$POOLED_SUMMARY")"
  pooled_stage_enabled="$(require_field gpu_upload_stage_pool_enabled "$POOLED_SUMMARY")"
  pooled_stage_entries="$(require_field gpu_upload_stage_pool_entries "$POOLED_SUMMARY")"
  pooled_stage_bytes="$(require_field gpu_upload_stage_pool_bytes "$POOLED_SUMMARY")"
  pooled_stage_creates="$(require_field gpu_upload_stage_pba_creates "$POOLED_SUMMARY")"
  pooled_stage_reuses="$(require_field gpu_upload_stage_pba_reuses "$POOLED_SUMMARY")"
  pooled_terrain_pressure_fixture_blocks="$(require_field terrain_pressure_fixture_blocks "$POOLED_SUMMARY")"
  pooled_terrain_pressure_fixture_dirty_observed="$(require_field terrain_pressure_fixture_dirty_observed "$POOLED_SUMMARY")"

  awk \
    -v baseline_status="$baseline_status" \
    -v baseline_source_status="$baseline_source_status" \
    -v baseline_case_set="$baseline_case_set" \
    -v baseline_terrain_pressure_fixture="$baseline_terrain_pressure_fixture" \
    -v baseline_subchunks="$baseline_subchunks" \
    -v baseline_draws="$baseline_draws" \
    -v baseline_faces="$baseline_faces" \
    -v baseline_occupancy="$baseline_occupancy" \
    -v baseline_queue="$baseline_queue" \
    -v baseline_process="$baseline_process" \
    -v baseline_submit="$baseline_submit" \
    -v baseline_uploads="$baseline_uploads" \
    -v baseline_upload_fail="$baseline_upload_fail" \
    -v baseline_upload_fail_capacity="$baseline_upload_fail_capacity" \
    -v baseline_upload_fail_fragmented="$baseline_upload_fail_fragmented" \
    -v baseline_stage_enabled="$baseline_stage_enabled" \
    -v baseline_stage_entries="$baseline_stage_entries" \
    -v baseline_stage_bytes="$baseline_stage_bytes" \
    -v baseline_stage_creates="$baseline_stage_creates" \
    -v baseline_stage_reuses="$baseline_stage_reuses" \
    -v baseline_terrain_pressure_fixture_blocks="$baseline_terrain_pressure_fixture_blocks" \
    -v baseline_terrain_pressure_fixture_dirty_observed="$baseline_terrain_pressure_fixture_dirty_observed" \
    -v pooled_status="$pooled_status" \
    -v pooled_source_status="$pooled_source_status" \
    -v pooled_case_set="$pooled_case_set" \
    -v pooled_terrain_pressure_fixture="$pooled_terrain_pressure_fixture" \
    -v pooled_subchunks="$pooled_subchunks" \
    -v pooled_draws="$pooled_draws" \
    -v pooled_faces="$pooled_faces" \
    -v pooled_occupancy="$pooled_occupancy" \
    -v pooled_queue="$pooled_queue" \
    -v pooled_process="$pooled_process" \
    -v pooled_submit="$pooled_submit" \
    -v pooled_uploads="$pooled_uploads" \
    -v pooled_upload_fail="$pooled_upload_fail" \
    -v pooled_upload_fail_capacity="$pooled_upload_fail_capacity" \
    -v pooled_upload_fail_fragmented="$pooled_upload_fail_fragmented" \
    -v pooled_stage_enabled="$pooled_stage_enabled" \
    -v pooled_stage_entries="$pooled_stage_entries" \
    -v pooled_stage_bytes="$pooled_stage_bytes" \
    -v pooled_stage_creates="$pooled_stage_creates" \
    -v pooled_stage_reuses="$pooled_stage_reuses" \
    -v pooled_terrain_pressure_fixture_blocks="$pooled_terrain_pressure_fixture_blocks" \
    -v pooled_terrain_pressure_fixture_dirty_observed="$pooled_terrain_pressure_fixture_dirty_observed" \
    -v min_subchunks="$MIN_GPU_SUBCHUNKS" \
    -v min_draws="$MIN_GPU_DRAWS" \
    -v min_faces="$MIN_GPU_FACES" \
    -v min_occupancy="$MIN_DRAW_CMD_OCCUPANCY_PCT" \
    -v max_queue="$MAX_TERRAIN_QUEUE_MS" \
    -v max_process="$MAX_PROCESS_WALL_P95_MS" \
    -v max_submit="$MAX_GPU_COMPOSITOR_SUBMIT_MS" \
    -v min_reuses="$MIN_REUSES" \
    -v required_case_set="$CASE_SET" \
    -v required_terrain_pressure_fixture="$TERRAIN_PRESSURE_FIXTURE" \
    -v min_terrain_pressure_fixture_blocks="$MIN_TERRAIN_PRESSURE_FIXTURE_BLOCKS" \
    -v baseline_summary="$BASELINE_SUMMARY" \
    -v pooled_summary="$POOLED_SUMMARY" '
    function set_fail(why) {
      if (status == "pass") {
        status = "fail"
        reason = why
      }
    }
    function require_pressure(prefix, run_status, source_status, case_set, terrain_pressure_fixture, subchunks, draws, faces, occupancy, queue, process, submit, upload_fail, upload_fail_capacity, upload_fail_fragmented, terrain_pressure_fixture_blocks, terrain_pressure_fixture_dirty_observed) {
      if (run_status != "pass" || source_status != "pass") {
        set_fail(prefix "_prerequisite")
      } else if (required_case_set != "" && case_set != required_case_set) {
        set_fail(prefix "_case_set")
      } else if (required_terrain_pressure_fixture != "none" && terrain_pressure_fixture != required_terrain_pressure_fixture) {
        set_fail(prefix "_terrain_pressure_fixture")
      } else if (required_terrain_pressure_fixture != "none" && terrain_pressure_fixture_blocks + 0 < min_terrain_pressure_fixture_blocks + 0) {
        set_fail(prefix "_terrain_pressure_fixture_blocks")
      } else if (required_terrain_pressure_fixture != "none" && terrain_pressure_fixture_dirty_observed + 0 != 1) {
        set_fail(prefix "_terrain_pressure_fixture_dirty_missing")
      } else if (subchunks + 0 < min_subchunks + 0) {
        set_fail(prefix "_subchunk_pressure")
      } else if (draws + 0 < min_draws + 0) {
        set_fail(prefix "_draw_pressure")
      } else if (faces + 0 < min_faces + 0) {
        set_fail(prefix "_face_pressure")
      } else if (occupancy + 0.0 < min_occupancy + 0.0) {
        set_fail(prefix "_draw_command_occupancy")
      } else if (queue + 0.0 > max_queue + 0.0) {
        set_fail(prefix "_terrain_queue_budget")
      } else if (process + 0.0 > max_process + 0.0) {
        set_fail(prefix "_process_wall_budget")
      } else if (submit + 0.0 > max_submit + 0.0) {
        set_fail(prefix "_gpu_submit_budget")
      } else if (upload_fail + upload_fail_capacity + upload_fail_fragmented > 0) {
        set_fail(prefix "_upload_failure")
      }
    }
    BEGIN {
      status = "pass"
      reason = "stage_pool_load_scaling_within_budget"
      require_pressure("baseline", baseline_status, baseline_source_status, baseline_case_set, baseline_terrain_pressure_fixture, baseline_subchunks, baseline_draws, baseline_faces, baseline_occupancy, baseline_queue, baseline_process, baseline_submit, baseline_upload_fail, baseline_upload_fail_capacity, baseline_upload_fail_fragmented, baseline_terrain_pressure_fixture_blocks, baseline_terrain_pressure_fixture_dirty_observed)
      require_pressure("pooled", pooled_status, pooled_source_status, pooled_case_set, pooled_terrain_pressure_fixture, pooled_subchunks, pooled_draws, pooled_faces, pooled_occupancy, pooled_queue, pooled_process, pooled_submit, pooled_upload_fail, pooled_upload_fail_capacity, pooled_upload_fail_fragmented, pooled_terrain_pressure_fixture_blocks, pooled_terrain_pressure_fixture_dirty_observed)

      if (baseline_stage_enabled + 0 != 0 || baseline_stage_creates + 0 != 0 || baseline_stage_reuses + 0 != 0) {
        set_fail("baseline_stage_pool_not_disabled")
      } else if (baseline_uploads + 0 <= 0) {
        set_fail("baseline_uploads_missing")
      } else if (pooled_stage_enabled + 0 != 1) {
        set_fail("pooled_stage_pool_not_enabled")
      } else if (pooled_stage_entries + 0 < 1 || pooled_stage_bytes + 0 < 1) {
        set_fail("pooled_stage_pool_empty")
      } else if (pooled_stage_creates + 0 < 1) {
        set_fail("pooled_stage_pool_no_creates")
      } else if (pooled_stage_reuses + 0 < min_reuses + 0) {
        set_fail("pooled_stage_pool_reuse_budget")
      } else if (pooled_uploads + 0 <= 0 || pooled_stage_creates + 0 >= pooled_uploads + 0) {
        set_fail("pooled_stage_pool_create_churn")
      }

      printf("gpu_upload_stage_pool_load_scaling status=%s reason=%s min_gpu_subchunks=%d min_gpu_draws=%d min_gpu_faces=%d min_draw_cmd_occupancy_pct=%.1f max_terrain_queue_ms=%.3f max_process_wall_p95_ms=%.3f max_gpu_compositor_submit_ms=%.3f min_reuses=%d ", status, reason, min_subchunks, min_draws, min_faces, min_occupancy, max_queue, max_process, max_submit, min_reuses)
      printf("workload_case_set=%s workload_terrain_pressure_fixture=%s min_terrain_pressure_fixture_blocks=%d ", required_case_set, required_terrain_pressure_fixture, min_terrain_pressure_fixture_blocks)
      printf("baseline_status=%s baseline_source_status=%s baseline_case_set=%s baseline_terrain_pressure_fixture=%s baseline_terrain_pressure_fixture_blocks=%d baseline_terrain_pressure_fixture_dirty_observed=%d baseline_max_gpu_subchunks=%d baseline_max_gpu_draws=%d baseline_max_gpu_faces=%d baseline_draw_cmd_occupancy_pct=%.3f baseline_terrain_queue_max_ms=%.3f baseline_process_wall_p95_ms=%.3f baseline_gpu_compositor_submit_max_ms=%.3f baseline_uploads=%d baseline_upload_fail=%d baseline_upload_fail_capacity=%d baseline_upload_fail_fragmented=%d baseline_stage_pool_enabled=%d baseline_stage_pool_entries=%d baseline_stage_pool_bytes=%d baseline_stage_pba_creates=%d baseline_stage_pba_reuses=%d ", baseline_status, baseline_source_status, baseline_case_set, baseline_terrain_pressure_fixture, baseline_terrain_pressure_fixture_blocks, baseline_terrain_pressure_fixture_dirty_observed, baseline_subchunks, baseline_draws, baseline_faces, baseline_occupancy, baseline_queue, baseline_process, baseline_submit, baseline_uploads, baseline_upload_fail, baseline_upload_fail_capacity, baseline_upload_fail_fragmented, baseline_stage_enabled, baseline_stage_entries, baseline_stage_bytes, baseline_stage_creates, baseline_stage_reuses)
      printf("pooled_status=%s pooled_source_status=%s pooled_case_set=%s pooled_terrain_pressure_fixture=%s pooled_terrain_pressure_fixture_blocks=%d pooled_terrain_pressure_fixture_dirty_observed=%d pooled_max_gpu_subchunks=%d pooled_max_gpu_draws=%d pooled_max_gpu_faces=%d pooled_draw_cmd_occupancy_pct=%.3f pooled_terrain_queue_max_ms=%.3f pooled_process_wall_p95_ms=%.3f pooled_gpu_compositor_submit_max_ms=%.3f pooled_uploads=%d pooled_upload_fail=%d pooled_upload_fail_capacity=%d pooled_upload_fail_fragmented=%d pooled_stage_pool_enabled=%d pooled_stage_pool_entries=%d pooled_stage_pool_bytes=%d pooled_stage_pba_creates=%d pooled_stage_pba_reuses=%d baseline_summary=%s pooled_summary=%s\n", pooled_status, pooled_source_status, pooled_case_set, pooled_terrain_pressure_fixture, pooled_terrain_pressure_fixture_blocks, pooled_terrain_pressure_fixture_dirty_observed, pooled_subchunks, pooled_draws, pooled_faces, pooled_occupancy, pooled_queue, pooled_process, pooled_submit, pooled_uploads, pooled_upload_fail, pooled_upload_fail_capacity, pooled_upload_fail_fragmented, pooled_stage_enabled, pooled_stage_entries, pooled_stage_bytes, pooled_stage_creates, pooled_stage_reuses, baseline_summary, pooled_summary)
      if (status != "pass") {
        exit 1
      }
    }
  ' > "$SUMMARY_PATH" || {
    cat "$SUMMARY_PATH" >&2 || true
    fail "GPU upload stage pool load-scaling gate failed"
  }

  cat "$SUMMARY_PATH"
}

require_positive_integer RUMPELMC_GPU_STAGE_POOL_LOAD_MIN_REUSES "$MIN_REUSES"
require_positive_integer RUMPELMC_GPU_STAGE_POOL_LOAD_SERVER_VIEW_DISTANCE "$SERVER_VIEW_DISTANCE"
require_positive_integer RUMPELMC_GPU_STAGE_POOL_LOAD_CLIENT_KEEP_CHUNK_DISTANCE "$CLIENT_KEEP_CHUNK_DISTANCE"
require_positive_integer RUMPELMC_GPU_STAGE_POOL_LOAD_SERVER_CHUNKS_PER_UPDATE "$SERVER_CHUNKS_PER_UPDATE"
require_positive_integer RUMPELMC_GPU_STAGE_POOL_LOAD_TERRAIN_PRESSURE_FIXTURE_CHUNK_COLUMNS "$TERRAIN_PRESSURE_FIXTURE_CHUNK_COLUMNS"
require_positive_integer RUMPELMC_GPU_STAGE_POOL_LOAD_TERRAIN_PRESSURE_FIXTURE_CHUNK_ROWS "$TERRAIN_PRESSURE_FIXTURE_CHUNK_ROWS"
require_positive_integer RUMPELMC_GPU_STAGE_POOL_LOAD_TERRAIN_PRESSURE_FIXTURE_CHUNK_RADIUS "$TERRAIN_PRESSURE_FIXTURE_CHUNK_RADIUS"
require_positive_integer RUMPELMC_GPU_STAGE_POOL_LOAD_TERRAIN_PRESSURE_FIXTURE_MAX_QUEUE "$TERRAIN_PRESSURE_FIXTURE_MAX_QUEUE"
require_positive_integer RUMPELMC_GPU_STAGE_POOL_LOAD_MIN_TERRAIN_PRESSURE_FIXTURE_BLOCKS "$MIN_TERRAIN_PRESSURE_FIXTURE_BLOCKS"

mkdir -p "$OUT_DIR"
if [ -z "$BASELINE_SUMMARY" ]; then
  rm -rf "$BASELINE_DIR" "$BASELINE_DB"
  rm -f "$BASELINE_LOG"
fi
if [ -z "$POOLED_SUMMARY" ]; then
  rm -rf "$POOLED_DIR" "$POOLED_DB"
  rm -f "$POOLED_LOG"
fi
rm -f "$SUMMARY_PATH"

if [ -z "$BASELINE_SUMMARY" ] || [ -z "$POOLED_SUMMARY" ]; then
  if [ -n "$(listener_pid || true)" ]; then
    fail "port 25565 is already in use; stop the existing server before upload stage-pool load-scaling gate"
  fi
fi

trap cleanup_port EXIT HUP INT TERM

if [ -z "$BASELINE_SUMMARY" ]; then
  echo "==> GPU upload stage-pool load-scaling baseline"
  run_load_scaling 0 "$BASELINE_DIR" "$BASELINE_DB" "$BASELINE_LOG"
  BASELINE_SUMMARY="$BASELINE_DIR/gpu-terrain-load-scaling-summary.txt"
fi
if [ -z "$POOLED_SUMMARY" ]; then
  echo "==> GPU upload stage-pool load-scaling pooled"
  run_load_scaling 1 "$POOLED_DIR" "$POOLED_DB" "$POOLED_LOG"
  POOLED_SUMMARY="$POOLED_DIR/gpu-terrain-load-scaling-summary.txt"
fi

test -s "$BASELINE_SUMMARY" || fail "missing baseline summary $BASELINE_SUMMARY"
test -s "$POOLED_SUMMARY" || fail "missing pooled summary $POOLED_SUMMARY"

write_summary
echo "GPU upload stage-pool load-scaling artifacts: $OUT_DIR"
