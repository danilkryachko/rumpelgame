#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/dirty_update_mass_edit_runtime"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

SUMMARY_PATH="$OUT_DIR/dirty-update-mass-edit-runtime-summary.txt"
case "$(basename "$OUT_DIR")" in
  *_current)
    ARTIFACT_DIR="${RUMPELMC_DIRTY_MASS_RUNTIME_ARTIFACT_DIR:-"$ROOT_DIR/logs/dirty_update_mass_edit_runtime_artifacts"}"
    ;;
  *)
    ARTIFACT_DIR="${RUMPELMC_DIRTY_MASS_RUNTIME_ARTIFACT_DIR:-"$OUT_DIR/artifacts"}"
    ;;
esac
case "$ARTIFACT_DIR" in
  /*) ;;
  *) ARTIFACT_DIR="$ROOT_DIR/$ARTIFACT_DIR" ;;
esac

RUN_DIR="$ARTIFACT_DIR/mass_edit"
RUN_LOG="$OUT_DIR/mass-edit-run.log"
DEFAULT_EDIT_SEQUENCE="place:96:64:64:1,destroy:96:64:64:0,place:127:64:95:2,destroy:127:64:95:0,place:96:80:95:3,destroy:96:80:95:0,place:127:80:64:4,destroy:127:80:64:0,place:112:96:80:5,destroy:112:96:80:0,place:112:112:80:4,destroy:112:112:80:0"
EDIT_SEQUENCE="${RUMPELMC_DIRTY_MASS_RUNTIME_SEQUENCE:-$DEFAULT_EDIT_SEQUENCE}"
EDIT_COUNT="${RUMPELMC_DIRTY_MASS_RUNTIME_EDIT_COUNT:-12}"
TARGET_FPS="${RUMPELMC_DIRTY_MASS_RUNTIME_TARGET_FPS:-100}"
EDIT_WAIT_SEC="${RUMPELMC_DIRTY_MASS_RUNTIME_EDIT_WAIT_SEC:-3.0}"
MIN_PLACE_ACTIONS="${RUMPELMC_DIRTY_MASS_RUNTIME_MIN_PLACE_ACTIONS:-6}"
MIN_DESTROY_ACTIONS="${RUMPELMC_DIRTY_MASS_RUNTIME_MIN_DESTROY_ACTIONS:-6}"
MIN_DIRTY_BLOCKS="${RUMPELMC_DIRTY_MASS_RUNTIME_MIN_DIRTY_BLOCKS:-8}"
MIN_CHUNK_REPLACE="${RUMPELMC_DIRTY_MASS_RUNTIME_MIN_CHUNK_REPLACE:-8}"
MIN_EDGE_NEIGHBOR_SUBCHUNKS="${RUMPELMC_DIRTY_MASS_RUNTIME_MIN_EDGE_NEIGHBOR_SUBCHUNKS:-12}"
MIN_PARTIAL_SUBCHUNKS="${RUMPELMC_DIRTY_MASS_RUNTIME_MIN_PARTIAL_SUBCHUNKS:-8}"
MIN_PARTIAL_SAVED_SUBCHUNKS="${RUMPELMC_DIRTY_MASS_RUNTIME_MIN_PARTIAL_SAVED_SUBCHUNKS:-8}"
MAX_TERRAIN_QUEUE_MS="${RUMPELMC_DIRTY_MASS_RUNTIME_MAX_TERRAIN_QUEUE_MS:-8.000}"
MAX_GPU_COMPOSITOR_SUBMIT_MS="${RUMPELMC_DIRTY_MASS_RUNTIME_MAX_GPU_COMPOSITOR_SUBMIT_MS:-1.000}"
MAX_PROCESS_WALL_P95_MS="${RUMPELMC_DIRTY_MASS_RUNTIME_MAX_PROCESS_WALL_P95_MS:-1.000}"

fail() {
  echo "dirty_update_mass_edit_runtime_smoke: $*" >&2
  exit 1
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
  stop_server_from_log "$RUN_LOG"
}

trap cleanup EXIT

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
        printf("dirty_update_mass_edit_runtime_smoke: %s must be positive, got %.3f\n", name, value) > "/dev/stderr"
        exit 1
      }
    }
  '
}

require_float_le() {
  name="$1"
  value="$2"
  max_value="$3"
  test -n "$value" || fail "missing $name"
  awk -v name="$name" -v value="$value" -v max_value="$max_value" '
    BEGIN {
      if (value > max_value) {
        printf("dirty_update_mass_edit_runtime_smoke: %s %.3f exceeds %.3f\n", name, value, max_value) > "/dev/stderr"
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

sequence_action_count() {
  action="$1"
  printf '%s\n' "$EDIT_SEQUENCE" | awk -F, -v action="$action" '
    BEGIN { count = 0 }
    {
      for (i = 1; i <= NF; i++) {
        split($i, parts, ":")
        if (parts[1] == action) {
          count++
        }
      }
    }
    END { print count }
  '
}

mkdir -p "$OUT_DIR" "$ARTIFACT_DIR"
rm -rf "$RUN_DIR" "$OUT_DIR/mass_edit"
rm -f "$SUMMARY_PATH" "$RUN_LOG"

require_int_ge RUMPELMC_DIRTY_MASS_RUNTIME_EDIT_COUNT "$EDIT_COUNT" 1
PLACE_ACTIONS="$(sequence_action_count place)"
DESTROY_ACTIONS="$(sequence_action_count destroy)"
BREAK_ACTIONS="$(sequence_action_count break)"
TOGGLE_ACTIONS="$(sequence_action_count toggle)"
DESTROY_OR_BREAK_ACTIONS=$((DESTROY_ACTIONS + BREAK_ACTIONS))
require_int_ge RUMPELMC_DIRTY_MASS_RUNTIME_MIN_PLACE_ACTIONS "$PLACE_ACTIONS" "$MIN_PLACE_ACTIONS"
require_int_ge RUMPELMC_DIRTY_MASS_RUNTIME_MIN_DESTROY_ACTIONS "$DESTROY_OR_BREAK_ACTIONS" "$MIN_DESTROY_ACTIONS"

proto_diff_count="$(git -C "$ROOT_DIR" diff --name-only -- api/schema/packets.proto server/pkg/api/packets.pb.go | awk 'END { print NR + 0 }')"
if [ "$proto_diff_count" -ne 0 ]; then
  fail "protocol diff present"
fi

if ! RUMPELMC_GPU_TERRAIN_PARTIAL_DIRTY_UPLOAD=1 \
  RUMPELMC_MOVEMENT_STRESS_TARGET_FPS="$TARGET_FPS" \
  RUMPELMC_VISUAL_SMOKE_BLOCK_EDIT=sequence \
  RUMPELMC_VISUAL_SMOKE_BLOCK_EDIT_SEQUENCE="$EDIT_SEQUENCE" \
  RUMPELMC_VISUAL_SMOKE_BLOCK_EDIT_WAIT_SEC="$EDIT_WAIT_SEC" \
  sh "$ROOT_DIR/scripts/gpu_terrain_movement_stress.sh" "$RUN_DIR" > "$RUN_LOG" 2>&1; then
  cat "$RUN_LOG" >&2 || true
  fail "mass-edit movement stress failed"
fi

stop_server_from_log "$RUN_LOG"

MARKER_PATH="$RUN_DIR/gpu-terrain-movement-stress.png.txt"
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
require_float_le terrain_queue_max_ms "$terrain_queue_max" "$MAX_TERRAIN_QUEUE_MS"
require_float_le gpu_compositor_submit_max_ms "$gpu_compositor_submit_max" "$MAX_GPU_COMPOSITOR_SUBMIT_MS"
require_float_le process_wall_p95_ms "$process_wall_p95" "$MAX_PROCESS_WALL_P95_MS"

{
  printf 'dirty_update_mass_edit_runtime status=pass runtime_mass_edit=godot_guarded runtime_mass_budget=godot_guarded mass_edit_count=%s place_actions=%s destroy_actions=%s break_actions=%s toggle_actions=%s target_fps=%s active_protocol_change=0 sequence="%s" marker=%s run_summary=%s\n' \
    "$EDIT_COUNT" \
    "$PLACE_ACTIONS" \
    "$DESTROY_ACTIONS" \
    "$BREAK_ACTIONS" \
    "$TOGGLE_ACTIONS" \
    "$TARGET_FPS" \
    "$EDIT_SEQUENCE" \
    "$MARKER_PATH" \
    "$RUN_DIR/movement-stress-summary.txt"
  printf 'mass_edit budget_status=pass terrain_queue_budget_ms=%s gpu_compositor_submit_budget_ms=%s process_wall_p95_budget_ms=%s dirty_blocks=%s chunk_replace=%s dirty_edge_neighbor_subchunks=%s dirty_partial_subchunks=%s dirty_partial_saved_subchunks=%s current_chunk_collision=%s terrain_queue_max_ms=%s gpu_compositor_submit_max_ms=%s process_wall_p95_ms=%s gpu_upload_fail=0\n' \
    "$MAX_TERRAIN_QUEUE_MS" \
    "$MAX_GPU_COMPOSITOR_SUBMIT_MS" \
    "$MAX_PROCESS_WALL_P95_MS" \
    "$(metric dirty_blocks "$MARKER_PATH")" \
    "$(metric chunk_replace "$MARKER_PATH")" \
    "$(metric dirty_edge_neighbor_subchunks "$MARKER_PATH")" \
    "$(metric dirty_partial_subchunks "$MARKER_PATH")" \
    "$(metric dirty_partial_saved_subchunks "$MARKER_PATH")" \
    "$(metric current_chunk_collision "$MARKER_PATH")" \
    "$terrain_queue_max" \
    "$gpu_compositor_submit_max" \
    "$process_wall_p95"
} > "$SUMMARY_PATH"

cat "$SUMMARY_PATH"
