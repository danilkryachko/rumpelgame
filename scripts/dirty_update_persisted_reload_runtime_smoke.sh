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
GODOT_RUN_DIR="$RUN_DIR/godot_dirty"
GODOT_RUN_LOG="$OUT_DIR/godot-dirty-run.log"
BUILD_SERVER="${RUMPELMC_DIRTY_PERSISTED_RUNTIME_BUILD_SERVER:-1}"
SEED_X="${RUMPELMC_DIRTY_PERSISTED_RUNTIME_SEED_X:-96}"
SEED_Y="${RUMPELMC_DIRTY_PERSISTED_RUNTIME_SEED_Y:-64}"
SEED_Z="${RUMPELMC_DIRTY_PERSISTED_RUNTIME_SEED_Z:-64}"
SEED_BLOCK_ID="${RUMPELMC_DIRTY_PERSISTED_RUNTIME_SEED_BLOCK_ID:-4}"
EDIT_SEQUENCE="${RUMPELMC_DIRTY_PERSISTED_RUNTIME_SEQUENCE:-toggle:96:64:64:1,toggle:127:64:95:1,toggle:112:80:80:1,toggle:112:96:80:1}"
EDIT_COUNT="${RUMPELMC_DIRTY_PERSISTED_RUNTIME_EDIT_COUNT:-4}"
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
      RUMPELMC_SERVER_ADDRESS=":$SMOKE_PORT" \
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

run_godot_dirty_after_reload() {
  rm -rf "$GODOT_RUN_DIR"
  if ! RUMPELMC_GPU_TERRAIN_PARTIAL_DIRTY_UPLOAD=1 \
    RUMPELMC_MOVEMENT_STRESS_TARGET_FPS="$TARGET_FPS" \
    RUMPELMC_VISUAL_SMOKE_BLOCK_EDIT=sequence \
    RUMPELMC_VISUAL_SMOKE_BLOCK_EDIT_SEQUENCE="$EDIT_SEQUENCE" \
    RUMPELMC_VISUAL_SMOKE_BLOCK_EDIT_WAIT_SEC="$EDIT_WAIT_SEC" \
    sh "$ROOT_DIR/scripts/gpu_terrain_movement_stress.sh" "$GODOT_RUN_DIR" > "$GODOT_RUN_LOG" 2>&1; then
    cat "$GODOT_RUN_LOG" >&2 || true
    fail "Godot dirty update after reload failed"
  fi
}

mkdir -p "$OUT_DIR" "$ARTIFACT_DIR"
rm -rf "$RUN_DIR" "$OUT_DIR/persisted_dirty"
rm -f "$SUMMARY_PATH" "$OUT_DIR"/client-*.log "$OUT_DIR"/server-*.log "$GODOT_RUN_LOG"

require_int_ge RUMPELMC_DIRTY_PERSISTED_RUNTIME_EDIT_COUNT "$EDIT_COUNT" 1

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
verify_seed_summary="$(run_phase verify-seed "$SEED_X" "$SEED_Y" "$SEED_Z" -action expect -want-block "$SEED_BLOCK_ID" -block-id "$SEED_BLOCK_ID")"
run_godot_dirty_after_reload
cleanup_server

MARKER_PATH="$GODOT_RUN_DIR/gpu-terrain-movement-stress.png.txt"
test -s "$MARKER_PATH" || fail "missing marker $MARKER_PATH"
grep -q 'block_edit="sequence"' "$MARKER_PATH" || fail "missing sequence block edit marker"
require_metric_eq "$MARKER_PATH" block_edit_dirty_observed 1
require_metric_eq "$MARKER_PATH" block_edit_count "$EDIT_COUNT"
require_metric_ge "$MARKER_PATH" dirty_blocks "$MIN_DIRTY_BLOCKS"
require_metric_ge "$MARKER_PATH" chunk_replace "$MIN_CHUNK_REPLACE"
require_metric_ge "$MARKER_PATH" dirty_edge_neighbor_subchunks "$MIN_EDGE_NEIGHBOR_SUBCHUNKS"
require_metric_ge "$MARKER_PATH" dirty_partial_subchunks "$MIN_PARTIAL_SUBCHUNKS"
require_metric_ge "$MARKER_PATH" dirty_partial_saved_subchunks "$MIN_PARTIAL_SAVED_SUBCHUNKS"
require_metric_ge "$MARKER_PATH" current_chunk_collision 1
require_metric_eq "$MARKER_PATH" gpu_upload_fail 0

terrain_queue_max="$(perf_triplet_value terrain_queue_work_ms "$MARKER_PATH" 3)"
gpu_compositor_submit_max="$(perf_triplet_value gpu_compositor_submit_ms "$MARKER_PATH" 3)"
process_wall_p95="$(float_metric process_wall_p95_ms "$MARKER_PATH")"
require_positive_float terrain_queue_max_ms "$terrain_queue_max"
require_positive_float gpu_compositor_submit_max_ms "$gpu_compositor_submit_max"
require_positive_float process_wall_p95_ms "$process_wall_p95"

start_server "reload-after-dirty"
for coord in $VERIFY_FINAL_AIR_COORDS; do
  old_ifs="$IFS"
  IFS=:
  set -- $coord
  IFS="$old_ifs"
  x="${1:-}"
  y="${2:-}"
  z="${3:-}"
  test -n "$x" && test -n "$y" && test -n "$z" || fail "malformed final verify coord: $coord"
  final_summary="$(run_phase "verify-final-air-$FINAL_VERIFY_COUNT" "$x" "$y" "$z" -action expect -want-block 0 -block-id "$SEED_BLOCK_ID")"
  append_final_verify_summary "$(printf 'phase_verify_final_air coord=%s summary="%s"' "$coord" "$final_summary")"
done
cleanup_server

{
  printf 'dirty_update_persisted_reload_runtime status=pass runtime_persisted_dirty=godot_guarded reload_cycles=2 dirty_after_reload=pass final_reload=pass final_verify_count=%s mass_edit_count=%s target_fps=%s active_protocol_change=0 sequence="%s" db_path=%s marker=%s run_summary=%s\n' \
    "$FINAL_VERIFY_COUNT" \
    "$EDIT_COUNT" \
    "$TARGET_FPS" \
    "$EDIT_SEQUENCE" \
    "$SMOKE_DB" \
    "$MARKER_PATH" \
    "$GODOT_RUN_DIR/movement-stress-summary.txt"
  printf 'persisted_dirty seed_block_id=%s dirty_blocks=%s chunk_replace=%s dirty_edge_neighbor_subchunks=%s dirty_partial_subchunks=%s dirty_partial_saved_subchunks=%s current_chunk_collision=%s terrain_queue_max_ms=%s gpu_compositor_submit_max_ms=%s process_wall_p95_ms=%s gpu_upload_fail=0\n' \
    "$SEED_BLOCK_ID" \
    "$(metric dirty_blocks "$MARKER_PATH")" \
    "$(metric chunk_replace "$MARKER_PATH")" \
    "$(metric dirty_edge_neighbor_subchunks "$MARKER_PATH")" \
    "$(metric dirty_partial_subchunks "$MARKER_PATH")" \
    "$(metric dirty_partial_saved_subchunks "$MARKER_PATH")" \
    "$(metric current_chunk_collision "$MARKER_PATH")" \
    "$terrain_queue_max" \
    "$gpu_compositor_submit_max" \
    "$process_wall_p95"
  printf 'phase_seed_place %s\n' "$seed_place_summary"
  printf 'phase_verify_seed %s\n' "$verify_seed_summary"
  printf '%s\n' "$FINAL_VERIFY_SUMMARIES"
} > "$SUMMARY_PATH"

cat "$SUMMARY_PATH"
