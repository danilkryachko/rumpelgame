#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/dirty_update_persisted_reload_runtime"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

SUMMARY_PATH="$OUT_DIR/dirty-update-persisted-reload-runtime-summary.txt"
case "$(basename "$OUT_DIR")" in
  *_current)
    ARTIFACT_DIR="${RUMPELMC_DIRTY_PERSISTED_RUNTIME_ARTIFACT_DIR:-"$ROOT_DIR/logs/dirty_update_persisted_reload_runtime_artifacts"}"
    ;;
  *)
    ARTIFACT_DIR="${RUMPELMC_DIRTY_PERSISTED_RUNTIME_ARTIFACT_DIR:-"$OUT_DIR/artifacts"}"
    ;;
esac
case "$ARTIFACT_DIR" in
  /*) ;;
  *) ARTIFACT_DIR="$ROOT_DIR/$ARTIFACT_DIR" ;;
esac

SERVER_DIR="$ROOT_DIR/server"
SERVER_BINARY="$SERVER_DIR/server"
SMOKE_BINARY="$OUT_DIR/persisted_reload_smoke"
SMOKE_PORT=25565
SMOKE_ADDR="127.0.0.1:$SMOKE_PORT"
RUN_DIR="$ARTIFACT_DIR/persisted_dirty"
SMOKE_DB="$RUN_DIR/rocksdb"
BUILD_SERVER="${RUMPELMC_DIRTY_PERSISTED_RUNTIME_BUILD_SERVER:-1}"
SEED_X="${RUMPELMC_DIRTY_PERSISTED_RUNTIME_SEED_X:-96}"
SEED_Y="${RUMPELMC_DIRTY_PERSISTED_RUNTIME_SEED_Y:-64}"
SEED_Z="${RUMPELMC_DIRTY_PERSISTED_RUNTIME_SEED_Z:-64}"
SEED_BLOCK_ID="${RUMPELMC_DIRTY_PERSISTED_RUNTIME_SEED_BLOCK_ID:-4}"
EDIT_SEQUENCE="${RUMPELMC_DIRTY_PERSISTED_RUNTIME_SEQUENCE:-toggle:96:64:64:1,toggle:127:64:95:1,toggle:112:80:80:1,toggle:112:96:80:1}"
EDIT_COUNT="${RUMPELMC_DIRTY_PERSISTED_RUNTIME_EDIT_COUNT:-4}"
SOAK_CYCLES="${RUMPELMC_DIRTY_PERSISTED_RUNTIME_SOAK_CYCLES:-3}"
MIN_SOAK_CYCLES="${RUMPELMC_DIRTY_PERSISTED_RUNTIME_MIN_SOAK_CYCLES:-3}"
VERIFY_FINAL_AIR_COORDS="${RUMPELMC_DIRTY_PERSISTED_RUNTIME_VERIFY_FINAL_AIR_COORDS:-96:64:64 127:64:95 112:80:80 112:96:80}"
TARGET_FPS="${RUMPELMC_DIRTY_PERSISTED_RUNTIME_TARGET_FPS:-100}"
EDIT_WAIT_SEC="${RUMPELMC_DIRTY_PERSISTED_RUNTIME_EDIT_WAIT_SEC:-3.0}"
MIN_DIRTY_BLOCKS="${RUMPELMC_DIRTY_PERSISTED_RUNTIME_MIN_DIRTY_BLOCKS:-4}"
MIN_CHUNK_REPLACE="${RUMPELMC_DIRTY_PERSISTED_RUNTIME_MIN_CHUNK_REPLACE:-8}"
MIN_EDGE_NEIGHBOR_SUBCHUNKS="${RUMPELMC_DIRTY_PERSISTED_RUNTIME_MIN_EDGE_NEIGHBOR_SUBCHUNKS:-8}"
MIN_PARTIAL_SUBCHUNKS="${RUMPELMC_DIRTY_PERSISTED_RUNTIME_MIN_PARTIAL_SUBCHUNKS:-4}"
MIN_PARTIAL_SAVED_SUBCHUNKS="${RUMPELMC_DIRTY_PERSISTED_RUNTIME_MIN_PARTIAL_SAVED_SUBCHUNKS:-4}"
SERVER_PID=""
FINAL_VERIFY_COUNT=0
FINAL_VERIFY_SUMMARIES=""
PERSISTED_DIRTY_CYCLE_SUMMARIES=""
RELOAD_CYCLES=0
SOAK_DIRTY_BLOCKS=0
SOAK_CHUNK_REPLACE=0
SOAK_EDGE_NEIGHBOR_SUBCHUNKS=0
SOAK_PARTIAL_SUBCHUNKS=0
SOAK_PARTIAL_SAVED_SUBCHUNKS=0
SOAK_CURRENT_CHUNK_COLLISION=0
SOAK_TERRAIN_QUEUE_MAX="0.000"
SOAK_GPU_COMPOSITOR_SUBMIT_MAX="0.000"
SOAK_PROCESS_WALL_P95_MAX="0.000"
LAST_GODOT_RUN_DIR=""
LAST_GODOT_RUN_LOG=""
LAST_MARKER_PATH=""

fail() {
  echo "dirty_update_persisted_reload_runtime_smoke: $*" >&2
  exit 1
}

listener_pid() {
  if command -v lsof >/dev/null 2>&1; then
    lsof -tiTCP:"$SMOKE_PORT" -sTCP:LISTEN 2>/dev/null | sed -n '1p'
  fi
}

wait_for_server() {
  log_path="$1"
  tries=0
  while [ "$tries" -lt 30 ]; do
    pid="$(listener_pid || true)"
    if [ -n "$pid" ]; then
      return 0
    fi
    tries=$((tries + 1))
    sleep 1
  done
  cat "$log_path" >&2 || true
  fail "server did not start listening on port $SMOKE_PORT"
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
  fail "port $SMOKE_PORT is still listening after cleanup"
}

cleanup_server() {
  if [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
    SERVER_PID=""
    wait_for_port_clear
  fi
}

cleanup_all() {
  cleanup_server
}

trap cleanup_all EXIT HUP INT TERM

sign_server_binary_if_possible() {
  if command -v codesign >/dev/null 2>&1; then
    codesign -s - --force "$SERVER_BINARY" >/dev/null 2>&1 || true
  fi
}

start_server() {
  label="$1"
  log_path="$OUT_DIR/server-$label.log"
  rm -f "$log_path"
  (
    cd "$SERVER_DIR"
    exec env RUMPELMC_SERVER_CHUNK_ENCODING=rle \
      RUMPELMC_SERVER_ADDRESS="$SMOKE_ADDR" \
      RUMPELMC_SERVER_ROCKSDB_PATH="$SMOKE_DB" \
      RUMPELMC_SERVER_BOOTSTRAP_RADIUS=0 \
      RUMPELMC_SERVER_CHUNKS_PER_UPDATE=64 \
      RUMPELMC_SERVER_CLIENT_WRITE_TIMEOUT_MS=2000 \
      "$SERVER_BINARY" > "$log_path" 2>&1
  ) &
  SERVER_PID="$!"
  wait_for_server "$log_path"
}

run_phase() {
  label="$1"
  x="$2"
  y="$3"
  z="$4"
  shift 4
  log_path="$OUT_DIR/client-$label.log"
  set +e
  "$SMOKE_BINARY" -addr "$SMOKE_ADDR" -timeout 3s -x "$x" -y "$y" -z "$z" "$@" > "$log_path" 2>&1
  rc=$?
  set -e
  if [ "$rc" -ne 0 ]; then
    cat "$log_path" >&2 || true
    fail "$label phase failed with exit code $rc"
  fi
  summary="$(grep '^server_persisted_reload_smoke status=pass ' "$log_path" | tail -n 1 || true)"
  if [ -z "$summary" ]; then
    cat "$log_path" >&2 || true
    fail "missing passing $label phase summary"
  fi
  printf '%s\n' "$summary"
}

append_final_verify_summary() {
  line="$1"
  if [ -z "$FINAL_VERIFY_SUMMARIES" ]; then
    FINAL_VERIFY_SUMMARIES="$line"
  else
    FINAL_VERIFY_SUMMARIES="$FINAL_VERIFY_SUMMARIES
$line"
  fi
  FINAL_VERIFY_COUNT=$((FINAL_VERIFY_COUNT + 1))
}

append_persisted_dirty_cycle_summary() {
  line="$1"
  if [ -z "$PERSISTED_DIRTY_CYCLE_SUMMARIES" ]; then
    PERSISTED_DIRTY_CYCLE_SUMMARIES="$line"
  else
    PERSISTED_DIRTY_CYCLE_SUMMARIES="$PERSISTED_DIRTY_CYCLE_SUMMARIES
$line"
  fi
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

perf_triplet_value() {
  key="$1"
  marker_path="$2"
  index="$3"
  sed -n "s/.*$key=\([0-9][0-9]*\.[0-9][0-9]*\)\/\([0-9][0-9]*\.[0-9][0-9]*\)\/\([0-9][0-9]*\.[0-9][0-9]*\).*/\1 \2 \3/p" "$marker_path" \
    | awk -v index="$index" '{print $index}' \
    | sed -n '1p'
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

require_positive_float() {
  name="$1"
  value="$2"
  test -n "$value" || fail "missing $name"
  awk -v name="$name" -v value="$value" '
    BEGIN {
      if (value <= 0.0) {
        printf("dirty_update_persisted_reload_runtime_smoke: %s must be positive, got %.3f\n", name, value) > "/dev/stderr"
        exit 1
      }
    }
  '
}

require_int_ge() {
  name="$1"
  value="$2"
  min_value="$3"
  case "$value" in
    ''|*[!0-9]*) fail "$name must be an integer, got $value" ;;
  esac
  if [ "$value" -lt "$min_value" ]; then
    fail "$name=$value is below $min_value"
  fi
}

float_max() {
  current="$1"
  candidate="$2"
  awk -v current="$current" -v candidate="$candidate" '
    BEGIN {
      if (candidate > current) {
        printf("%.3f", candidate)
      } else {
        printf("%.3f", current)
      }
    }
  '
}

validate_and_accumulate_marker() {
  cycle="$1"
  marker_path="$2"
  run_dir="$3"
  test -s "$marker_path" || fail "missing marker $marker_path"
  grep -q 'block_edit="sequence"' "$marker_path" || fail "missing sequence block edit marker"
  require_metric_eq "$marker_path" block_edit_dirty_observed 1
  require_metric_eq "$marker_path" block_edit_count "$EDIT_COUNT"
  require_metric_ge "$marker_path" dirty_blocks "$MIN_DIRTY_BLOCKS"
  require_metric_ge "$marker_path" chunk_replace "$MIN_CHUNK_REPLACE"
  require_metric_ge "$marker_path" dirty_edge_neighbor_subchunks "$MIN_EDGE_NEIGHBOR_SUBCHUNKS"
  require_metric_ge "$marker_path" dirty_partial_subchunks "$MIN_PARTIAL_SUBCHUNKS"
  require_metric_ge "$marker_path" dirty_partial_saved_subchunks "$MIN_PARTIAL_SAVED_SUBCHUNKS"
  require_metric_ge "$marker_path" current_chunk_collision 1
  require_metric_eq "$marker_path" gpu_upload_fail 0

  cycle_dirty_blocks="$(metric dirty_blocks "$marker_path")"
  cycle_chunk_replace="$(metric chunk_replace "$marker_path")"
  cycle_edge_neighbor_subchunks="$(metric dirty_edge_neighbor_subchunks "$marker_path")"
  cycle_partial_subchunks="$(metric dirty_partial_subchunks "$marker_path")"
  cycle_partial_saved_subchunks="$(metric dirty_partial_saved_subchunks "$marker_path")"
  cycle_current_chunk_collision="$(metric current_chunk_collision "$marker_path")"
  cycle_terrain_queue_max="$(perf_triplet_value terrain_queue_work_ms "$marker_path" 3)"
  cycle_gpu_compositor_submit_max="$(perf_triplet_value gpu_compositor_submit_ms "$marker_path" 3)"
  cycle_process_wall_p95="$(float_metric process_wall_p95_ms "$marker_path")"
  require_positive_float terrain_queue_max_ms "$cycle_terrain_queue_max"
  require_positive_float gpu_compositor_submit_max_ms "$cycle_gpu_compositor_submit_max"
  require_positive_float process_wall_p95_ms "$cycle_process_wall_p95"

  SOAK_DIRTY_BLOCKS=$((SOAK_DIRTY_BLOCKS + cycle_dirty_blocks))
  SOAK_CHUNK_REPLACE=$((SOAK_CHUNK_REPLACE + cycle_chunk_replace))
  SOAK_EDGE_NEIGHBOR_SUBCHUNKS=$((SOAK_EDGE_NEIGHBOR_SUBCHUNKS + cycle_edge_neighbor_subchunks))
  SOAK_PARTIAL_SUBCHUNKS=$((SOAK_PARTIAL_SUBCHUNKS + cycle_partial_subchunks))
  SOAK_PARTIAL_SAVED_SUBCHUNKS=$((SOAK_PARTIAL_SAVED_SUBCHUNKS + cycle_partial_saved_subchunks))
  SOAK_CURRENT_CHUNK_COLLISION=$((SOAK_CURRENT_CHUNK_COLLISION + cycle_current_chunk_collision))
  SOAK_TERRAIN_QUEUE_MAX="$(float_max "$SOAK_TERRAIN_QUEUE_MAX" "$cycle_terrain_queue_max")"
  SOAK_GPU_COMPOSITOR_SUBMIT_MAX="$(float_max "$SOAK_GPU_COMPOSITOR_SUBMIT_MAX" "$cycle_gpu_compositor_submit_max")"
  SOAK_PROCESS_WALL_P95_MAX="$(float_max "$SOAK_PROCESS_WALL_P95_MAX" "$cycle_process_wall_p95")"

  append_persisted_dirty_cycle_summary "$(printf 'persisted_dirty_cycle cycle=%s dirty_blocks=%s chunk_replace=%s dirty_edge_neighbor_subchunks=%s dirty_partial_subchunks=%s dirty_partial_saved_subchunks=%s current_chunk_collision=%s terrain_queue_max_ms=%s gpu_compositor_submit_max_ms=%s process_wall_p95_ms=%s gpu_upload_fail=0 marker=%s run_summary=%s' \
    "$cycle" \
    "$cycle_dirty_blocks" \
    "$cycle_chunk_replace" \
    "$cycle_edge_neighbor_subchunks" \
    "$cycle_partial_subchunks" \
    "$cycle_partial_saved_subchunks" \
    "$cycle_current_chunk_collision" \
    "$cycle_terrain_queue_max" \
    "$cycle_gpu_compositor_submit_max" \
    "$cycle_process_wall_p95" \
    "$marker_path" \
    "$run_dir/movement-stress-summary.txt")"
}

run_godot_dirty_after_reload() {
  cycle="$1"
  LAST_GODOT_RUN_DIR="$RUN_DIR/godot_dirty_cycle_$cycle"
  LAST_GODOT_RUN_LOG="$OUT_DIR/godot-dirty-cycle-$cycle.log"
  LAST_MARKER_PATH="$LAST_GODOT_RUN_DIR/gpu-terrain-movement-stress.png.txt"
  rm -rf "$LAST_GODOT_RUN_DIR"
  if ! RUMPELMC_GPU_TERRAIN_PARTIAL_DIRTY_UPLOAD=1 \
    RUMPELMC_MOVEMENT_STRESS_TARGET_FPS="$TARGET_FPS" \
    RUMPELMC_VISUAL_SMOKE_BLOCK_EDIT=sequence \
    RUMPELMC_VISUAL_SMOKE_BLOCK_EDIT_SEQUENCE="$EDIT_SEQUENCE" \
    RUMPELMC_VISUAL_SMOKE_BLOCK_EDIT_WAIT_SEC="$EDIT_WAIT_SEC" \
    sh "$ROOT_DIR/scripts/gpu_terrain_movement_stress.sh" "$LAST_GODOT_RUN_DIR" > "$LAST_GODOT_RUN_LOG" 2>&1; then
    cat "$LAST_GODOT_RUN_LOG" >&2 || true
    fail "Godot dirty update after reload cycle $cycle failed"
  fi
}

mkdir -p "$OUT_DIR" "$ARTIFACT_DIR"
rm -rf "$RUN_DIR" "$OUT_DIR/persisted_dirty"
rm -f "$SUMMARY_PATH" "$OUT_DIR"/client-*.log "$OUT_DIR"/server-*.log "$OUT_DIR"/godot-dirty-*.log

require_int_ge RUMPELMC_DIRTY_PERSISTED_RUNTIME_EDIT_COUNT "$EDIT_COUNT" 1
require_int_ge RUMPELMC_DIRTY_PERSISTED_RUNTIME_SOAK_CYCLES "$SOAK_CYCLES" "$MIN_SOAK_CYCLES"

proto_diff_count="$(git -C "$ROOT_DIR" diff --name-only -- api/schema/packets.proto server/pkg/api/packets.pb.go | awk 'END { print NR + 0 }')"
if [ "$proto_diff_count" -ne 0 ]; then
  fail "protocol diff present"
fi

listener="$(listener_pid || true)"
if [ -n "$listener" ]; then
  fail "port $SMOKE_PORT is already in use; stop the existing server before persisted dirty runtime smoke"
fi

case "$BUILD_SERVER" in
  0) ;;
  1)
    (
      cd "$SERVER_DIR"
      go build -o ./server ./cmd/server
      sign_server_binary_if_possible
    )
    ;;
  *) fail "unsupported RUMPELMC_DIRTY_PERSISTED_RUNTIME_BUILD_SERVER=$BUILD_SERVER" ;;
esac

(
  cd "$SERVER_DIR"
  go build -o "$SMOKE_BINARY" ./cmd/persisted_reload_smoke
)

start_server "seed-place"
seed_place_summary="$(run_phase seed-place "$SEED_X" "$SEED_Y" "$SEED_Z" -action place -want-before 0 -block-id "$SEED_BLOCK_ID")"
cleanup_server

start_server "reload-before-dirty"
RELOAD_CYCLES=$((RELOAD_CYCLES + 1))
verify_seed_summary="$(run_phase verify-seed "$SEED_X" "$SEED_Y" "$SEED_Z" -action expect -want-block "$SEED_BLOCK_ID" -block-id "$SEED_BLOCK_ID")"

cycle=1
while [ "$cycle" -le "$SOAK_CYCLES" ]; do
  run_godot_dirty_after_reload "$cycle"
  validate_and_accumulate_marker "$cycle" "$LAST_MARKER_PATH" "$LAST_GODOT_RUN_DIR"
  cleanup_server

  start_server "reload-after-dirty-$cycle"
  RELOAD_CYCLES=$((RELOAD_CYCLES + 1))
  for coord in $VERIFY_FINAL_AIR_COORDS; do
    old_ifs="$IFS"
    IFS=:
    set -- $coord
    IFS="$old_ifs"
    x="${1:-}"
    y="${2:-}"
    z="${3:-}"
    test -n "$x" && test -n "$y" && test -n "$z" || fail "malformed final verify coord: $coord"
    final_summary="$(run_phase "verify-final-air-$cycle-$FINAL_VERIFY_COUNT" "$x" "$y" "$z" -action expect -want-block 0 -block-id "$SEED_BLOCK_ID")"
    append_final_verify_summary "$(printf 'phase_verify_final_air cycle=%s coord=%s summary="%s"' "$cycle" "$coord" "$final_summary")"
  done
  cycle=$((cycle + 1))
done
cleanup_server

{
  printf 'dirty_update_persisted_reload_runtime status=pass runtime_persisted_dirty=godot_guarded soak_status=pass soak_cycles=%s reload_cycles=%s dirty_after_reload=pass final_reload=pass final_verify_count=%s mass_edit_count=%s target_fps=%s active_protocol_change=0 sequence="%s" db_path=%s last_marker=%s last_run_summary=%s\n' \
    "$SOAK_CYCLES" \
    "$RELOAD_CYCLES" \
    "$FINAL_VERIFY_COUNT" \
    "$EDIT_COUNT" \
    "$TARGET_FPS" \
    "$EDIT_SEQUENCE" \
    "$SMOKE_DB" \
    "$LAST_MARKER_PATH" \
    "$LAST_GODOT_RUN_DIR/movement-stress-summary.txt"
  printf 'persisted_dirty seed_block_id=%s soak_dirty_blocks=%s soak_chunk_replace=%s soak_edge_neighbor_subchunks=%s soak_partial_subchunks=%s soak_partial_saved_subchunks=%s soak_current_chunk_collision=%s terrain_queue_max_ms=%s gpu_compositor_submit_max_ms=%s process_wall_p95_ms=%s gpu_upload_fail=0\n' \
    "$SEED_BLOCK_ID" \
    "$SOAK_DIRTY_BLOCKS" \
    "$SOAK_CHUNK_REPLACE" \
    "$SOAK_EDGE_NEIGHBOR_SUBCHUNKS" \
    "$SOAK_PARTIAL_SUBCHUNKS" \
    "$SOAK_PARTIAL_SAVED_SUBCHUNKS" \
    "$SOAK_CURRENT_CHUNK_COLLISION" \
    "$SOAK_TERRAIN_QUEUE_MAX" \
    "$SOAK_GPU_COMPOSITOR_SUBMIT_MAX" \
    "$SOAK_PROCESS_WALL_P95_MAX"
  printf '%s\n' "$PERSISTED_DIRTY_CYCLE_SUMMARIES"
  printf 'phase_seed_place %s\n' "$seed_place_summary"
  printf 'phase_verify_seed %s\n' "$verify_seed_summary"
  printf '%s\n' "$FINAL_VERIFY_SUMMARIES"
} > "$SUMMARY_PATH"

cat "$SUMMARY_PATH"
