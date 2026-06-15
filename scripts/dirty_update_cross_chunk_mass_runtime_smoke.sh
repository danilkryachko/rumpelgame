#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/dirty_update_cross_chunk_mass_runtime"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

SUMMARY_PATH="$OUT_DIR/dirty-update-cross-chunk-mass-runtime-summary.txt"
case "$(basename "$OUT_DIR")" in
  *_current)
    ARTIFACT_DIR="${RUMPELMC_DIRTY_CROSS_MASS_RUNTIME_ARTIFACT_DIR:-"$ROOT_DIR/logs/dirty_update_cross_chunk_mass_runtime_artifacts"}"
    ;;
  *)
    ARTIFACT_DIR="${RUMPELMC_DIRTY_CROSS_MASS_RUNTIME_ARTIFACT_DIR:-"$OUT_DIR/artifacts"}"
    ;;
esac
case "$ARTIFACT_DIR" in
  /*) ;;
  *) ARTIFACT_DIR="$ROOT_DIR/$ARTIFACT_DIR" ;;
esac

MASS_RUNTIME_SMOKE_SCRIPT="${RUMPELMC_DIRTY_CROSS_MASS_RUNTIME_BASE_SCRIPT:-"$ROOT_DIR/scripts/dirty_update_mass_edit_runtime_smoke.sh"}"
INNER_OUT_DIR="$ARTIFACT_DIR/inner_summary"
INNER_SUMMARY="$INNER_OUT_DIR/dirty-update-mass-edit-runtime-summary.txt"
INNER_RUN_LOG="$OUT_DIR/cross-chunk-mass-run.log"
DEFAULT_EDIT_SEQUENCE="place:127:64:95:1,destroy:127:64:95:0,place:95:64:63:2,destroy:95:64:63:0,place:128:80:64:3,destroy:128:80:64:0,place:96:96:96:4,destroy:96:96:96:0"
EDIT_SEQUENCE="${RUMPELMC_DIRTY_CROSS_MASS_RUNTIME_SEQUENCE:-$DEFAULT_EDIT_SEQUENCE}"
EDIT_COUNT="${RUMPELMC_DIRTY_CROSS_MASS_RUNTIME_EDIT_COUNT:-8}"
TARGET_FPS="${RUMPELMC_DIRTY_CROSS_MASS_RUNTIME_TARGET_FPS:-100}"
MIN_CROSS_CHUNKS="${RUMPELMC_DIRTY_CROSS_MASS_RUNTIME_MIN_CROSS_CHUNKS:-4}"
MIN_PLACE_ACTIONS="${RUMPELMC_DIRTY_CROSS_MASS_RUNTIME_MIN_PLACE_ACTIONS:-4}"
MIN_DESTROY_ACTIONS="${RUMPELMC_DIRTY_CROSS_MASS_RUNTIME_MIN_DESTROY_ACTIONS:-4}"
MIN_DIRTY_BLOCKS="${RUMPELMC_DIRTY_CROSS_MASS_RUNTIME_MIN_DIRTY_BLOCKS:-8}"
MIN_CHUNK_REPLACE="${RUMPELMC_DIRTY_CROSS_MASS_RUNTIME_MIN_CHUNK_REPLACE:-8}"
MIN_EDGE_NEIGHBOR_SUBCHUNKS="${RUMPELMC_DIRTY_CROSS_MASS_RUNTIME_MIN_EDGE_NEIGHBOR_SUBCHUNKS:-8}"
MIN_PARTIAL_SUBCHUNKS="${RUMPELMC_DIRTY_CROSS_MASS_RUNTIME_MIN_PARTIAL_SUBCHUNKS:-8}"
MIN_PARTIAL_SAVED_SUBCHUNKS="${RUMPELMC_DIRTY_CROSS_MASS_RUNTIME_MIN_PARTIAL_SAVED_SUBCHUNKS:-8}"
MAX_TERRAIN_QUEUE_MS="${RUMPELMC_DIRTY_CROSS_MASS_RUNTIME_MAX_TERRAIN_QUEUE_MS:-8.000}"
MAX_GPU_COMPOSITOR_SUBMIT_MS="${RUMPELMC_DIRTY_CROSS_MASS_RUNTIME_MAX_GPU_COMPOSITOR_SUBMIT_MS:-1.000}"
MAX_PROCESS_WALL_P95_MS="${RUMPELMC_DIRTY_CROSS_MASS_RUNTIME_MAX_PROCESS_WALL_P95_MS:-1.000}"

fail() {
  echo "dirty_update_cross_chunk_mass_runtime_smoke: $*" >&2
  exit 1
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

require_token() {
  path="$1"
  token="$2"
  test -s "$path" || fail "missing file $path"
  grep -Fq "$token" "$path" || fail "missing token '$token' in $path"
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

sequence_cross_chunk_count() {
  printf '%s\n' "$EDIT_SEQUENCE" | awk -F, '
    {
      for (i = 1; i <= NF; i++) {
        split($i, parts, ":")
        if (parts[1] == "place" || parts[1] == "destroy" || parts[1] == "break" || parts[1] == "toggle") {
          chunk_x = int(parts[2] / 32)
          chunk_z = int(parts[4] / 32)
          chunks[chunk_x "," chunk_z] = 1
        }
      }
    }
    END {
      count = 0
      for (chunk in chunks) {
        count++
      }
      print count
    }
  '
}

mkdir -p "$OUT_DIR" "$ARTIFACT_DIR"
rm -rf "$INNER_OUT_DIR" "$ARTIFACT_DIR/mass_edit"
rm -f "$SUMMARY_PATH" "$INNER_RUN_LOG"

test -s "$MASS_RUNTIME_SMOKE_SCRIPT" || fail "missing base mass runtime smoke $MASS_RUNTIME_SMOKE_SCRIPT"
require_int_ge RUMPELMC_DIRTY_CROSS_MASS_RUNTIME_EDIT_COUNT "$EDIT_COUNT" 1

PLACE_ACTIONS="$(sequence_action_count place)"
DESTROY_ACTIONS="$(sequence_action_count destroy)"
BREAK_ACTIONS="$(sequence_action_count break)"
TOGGLE_ACTIONS="$(sequence_action_count toggle)"
DESTROY_OR_BREAK_ACTIONS=$((DESTROY_ACTIONS + BREAK_ACTIONS))
CROSS_CHUNK_COUNT="$(sequence_cross_chunk_count)"
require_int_ge RUMPELMC_DIRTY_CROSS_MASS_RUNTIME_MIN_CROSS_CHUNKS "$CROSS_CHUNK_COUNT" "$MIN_CROSS_CHUNKS"
require_int_ge RUMPELMC_DIRTY_CROSS_MASS_RUNTIME_MIN_PLACE_ACTIONS "$PLACE_ACTIONS" "$MIN_PLACE_ACTIONS"
require_int_ge RUMPELMC_DIRTY_CROSS_MASS_RUNTIME_MIN_DESTROY_ACTIONS "$DESTROY_OR_BREAK_ACTIONS" "$MIN_DESTROY_ACTIONS"

if ! RUMPELMC_DIRTY_MASS_RUNTIME_ARTIFACT_DIR="$ARTIFACT_DIR" \
  RUMPELMC_DIRTY_MASS_RUNTIME_SEQUENCE="$EDIT_SEQUENCE" \
  RUMPELMC_DIRTY_MASS_RUNTIME_EDIT_COUNT="$EDIT_COUNT" \
  RUMPELMC_DIRTY_MASS_RUNTIME_TARGET_FPS="$TARGET_FPS" \
  RUMPELMC_DIRTY_MASS_RUNTIME_MIN_PLACE_ACTIONS="$MIN_PLACE_ACTIONS" \
  RUMPELMC_DIRTY_MASS_RUNTIME_MIN_DESTROY_ACTIONS="$MIN_DESTROY_ACTIONS" \
  RUMPELMC_DIRTY_MASS_RUNTIME_MIN_DIRTY_BLOCKS="$MIN_DIRTY_BLOCKS" \
  RUMPELMC_DIRTY_MASS_RUNTIME_MIN_CHUNK_REPLACE="$MIN_CHUNK_REPLACE" \
  RUMPELMC_DIRTY_MASS_RUNTIME_MIN_EDGE_NEIGHBOR_SUBCHUNKS="$MIN_EDGE_NEIGHBOR_SUBCHUNKS" \
  RUMPELMC_DIRTY_MASS_RUNTIME_MIN_PARTIAL_SUBCHUNKS="$MIN_PARTIAL_SUBCHUNKS" \
  RUMPELMC_DIRTY_MASS_RUNTIME_MIN_PARTIAL_SAVED_SUBCHUNKS="$MIN_PARTIAL_SAVED_SUBCHUNKS" \
  RUMPELMC_DIRTY_MASS_RUNTIME_MAX_TERRAIN_QUEUE_MS="$MAX_TERRAIN_QUEUE_MS" \
  RUMPELMC_DIRTY_MASS_RUNTIME_MAX_GPU_COMPOSITOR_SUBMIT_MS="$MAX_GPU_COMPOSITOR_SUBMIT_MS" \
  RUMPELMC_DIRTY_MASS_RUNTIME_MAX_PROCESS_WALL_P95_MS="$MAX_PROCESS_WALL_P95_MS" \
  sh "$MASS_RUNTIME_SMOKE_SCRIPT" "$INNER_OUT_DIR" > "$INNER_RUN_LOG" 2>&1; then
  cat "$INNER_RUN_LOG" >&2 || true
  fail "base mass-edit runtime smoke failed"
fi

require_token "$INNER_SUMMARY" 'dirty_update_mass_edit_runtime status=pass'
require_token "$INNER_SUMMARY" 'runtime_mass_edit=godot_guarded'
require_token "$INNER_SUMMARY" 'runtime_mass_budget=godot_guarded'
require_token "$INNER_SUMMARY" 'budget_status=pass'
require_token "$INNER_SUMMARY" 'gpu_upload_fail=0'

inner_status="$(field_metric status "$INNER_SUMMARY")"
inner_protocol_change="$(field_metric active_protocol_change "$INNER_SUMMARY")"
inner_runtime_mass_edit="$(field_metric runtime_mass_edit "$INNER_SUMMARY")"
inner_runtime_mass_budget="$(field_metric runtime_mass_budget "$INNER_SUMMARY")"
dirty_blocks="$(field_metric dirty_blocks "$INNER_SUMMARY")"
chunk_replace="$(field_metric chunk_replace "$INNER_SUMMARY")"
dirty_edge_neighbor_subchunks="$(field_metric dirty_edge_neighbor_subchunks "$INNER_SUMMARY")"
dirty_partial_subchunks="$(field_metric dirty_partial_subchunks "$INNER_SUMMARY")"
dirty_partial_saved_subchunks="$(field_metric dirty_partial_saved_subchunks "$INNER_SUMMARY")"
current_chunk_collision="$(field_metric current_chunk_collision "$INNER_SUMMARY")"
terrain_queue_max="$(field_metric terrain_queue_max_ms "$INNER_SUMMARY")"
gpu_compositor_submit_max="$(field_metric gpu_compositor_submit_max_ms "$INNER_SUMMARY")"
process_wall_p95="$(field_metric process_wall_p95_ms "$INNER_SUMMARY")"
marker_path="$(field_metric marker "$INNER_SUMMARY")"
run_summary="$(field_metric run_summary "$INNER_SUMMARY")"

test "$inner_status" = "pass" || fail "inner status is $inner_status"
test "$inner_protocol_change" = "0" || fail "inner protocol change is $inner_protocol_change"
test "$inner_runtime_mass_edit" = "godot_guarded" || fail "inner runtime mass edit is $inner_runtime_mass_edit"
test "$inner_runtime_mass_budget" = "godot_guarded" || fail "inner runtime budget is $inner_runtime_mass_budget"

{
  printf 'dirty_update_cross_chunk_mass_runtime status=pass runtime_cross_chunk_mass_edit=godot_guarded cross_chunk_mass_budget=godot_guarded cross_chunk_count=%s mass_edit_count=%s place_actions=%s destroy_actions=%s break_actions=%s toggle_actions=%s target_fps=%s active_protocol_change=0 sequence="%s" marker=%s run_summary=%s source_summary=%s\n' \
    "$CROSS_CHUNK_COUNT" \
    "$EDIT_COUNT" \
    "$PLACE_ACTIONS" \
    "$DESTROY_ACTIONS" \
    "$BREAK_ACTIONS" \
    "$TOGGLE_ACTIONS" \
    "$TARGET_FPS" \
    "$EDIT_SEQUENCE" \
    "$marker_path" \
    "$run_summary" \
    "$INNER_SUMMARY"
  printf 'cross_chunk_mass budget_status=pass terrain_queue_budget_ms=%s gpu_compositor_submit_budget_ms=%s process_wall_p95_budget_ms=%s dirty_blocks=%s chunk_replace=%s dirty_edge_neighbor_subchunks=%s dirty_partial_subchunks=%s dirty_partial_saved_subchunks=%s current_chunk_collision=%s terrain_queue_max_ms=%s gpu_compositor_submit_max_ms=%s process_wall_p95_ms=%s gpu_upload_fail=0\n' \
    "$MAX_TERRAIN_QUEUE_MS" \
    "$MAX_GPU_COMPOSITOR_SUBMIT_MS" \
    "$MAX_PROCESS_WALL_P95_MS" \
    "$dirty_blocks" \
    "$chunk_replace" \
    "$dirty_edge_neighbor_subchunks" \
    "$dirty_partial_subchunks" \
    "$dirty_partial_saved_subchunks" \
    "$current_chunk_collision" \
    "$terrain_queue_max" \
    "$gpu_compositor_submit_max" \
    "$process_wall_p95"
} > "$SUMMARY_PATH"

cat "$SUMMARY_PATH"
