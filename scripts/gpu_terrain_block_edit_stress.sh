#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/gpu_terrain_visual_smoke/block_edit_stress"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

ACTION="${RUMPELMC_BLOCK_EDIT_STRESS_ACTION:-toggle}"
EDIT_X="${RUMPELMC_BLOCK_EDIT_STRESS_X:-112}"
EDIT_Y="${RUMPELMC_BLOCK_EDIT_STRESS_Y:-64}"
EDIT_Z="${RUMPELMC_BLOCK_EDIT_STRESS_Z:-80}"
EDIT_BLOCK_ID="${RUMPELMC_BLOCK_EDIT_STRESS_BLOCK_ID:-1}"
EDIT_WAIT_SEC="${RUMPELMC_BLOCK_EDIT_STRESS_WAIT_SEC:-3.0}"
MOTION_NAME="${RUMPELMC_BLOCK_EDIT_STRESS_MOTION:-${RUMPELMC_MOVEMENT_STRESS_MOTION:-chunk_walk}}"
EXPECTED_CURRENT_CHUNK="${RUMPELMC_BLOCK_EDIT_STRESS_EXPECTED_CHUNK:-${RUMPELMC_MOVEMENT_STRESS_EXPECTED_CHUNK:-3,2}}"
MIN_MOTION_CHUNKS="${RUMPELMC_BLOCK_EDIT_STRESS_MIN_CHUNKS:-${RUMPELMC_MOVEMENT_STRESS_MIN_CHUNKS:-4}}"

fail() {
  echo "gpu_terrain_block_edit_stress: $*" >&2
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

write_summary() {
  summary_path="$OUT_DIR/block-edit-stress-summary.txt"
  {
    printf 'GPU terrain block edit stress summary action=%s x=%s y=%s z=%s block_id=%s motion=%s expected_chunk=%s\n' \
      "$ACTION" "$EDIT_X" "$EDIT_Y" "$EDIT_Z" "$EDIT_BLOCK_ID" "$MOTION_NAME" "$EXPECTED_CURRENT_CHUNK"
    printf 'block_edit_dirty chunk_replace=%s dirty_chunks=%s dirty_blocks=%s dirty_last_blocks=%s dirty_last_changed_subchunks=%s dirty_last_rebuild_subchunks=%s dirty_last_bounds=%s dirty_last_edges=%s gpu_upload_fail=%s block_edit_dirty_observed=%s\n' \
      "$(metric chunk_replace "$marker_path")" \
      "$(metric dirty_chunks "$marker_path")" \
      "$(metric dirty_blocks "$marker_path")" \
      "$(metric dirty_last_blocks "$marker_path")" \
      "$(metric dirty_last_changed_subchunks "$marker_path")" \
      "$(metric dirty_last_rebuild_subchunks "$marker_path")" \
      "$(text_metric dirty_last_bounds "$marker_path")" \
      "$(text_metric dirty_last_edges "$marker_path")" \
      "$(metric gpu_upload_fail "$marker_path")" \
      "$(metric block_edit_dirty_observed "$marker_path")"
  } > "$summary_path"
  cat "$summary_path"
}

mkdir -p "$OUT_DIR"

echo "==> GPU terrain block edit stress"
RUMPELMC_MOVEMENT_STRESS_MOTION="$MOTION_NAME" \
RUMPELMC_MOVEMENT_STRESS_EXPECTED_CHUNK="$EXPECTED_CURRENT_CHUNK" \
RUMPELMC_MOVEMENT_STRESS_MIN_CHUNKS="$MIN_MOTION_CHUNKS" \
RUMPELMC_VISUAL_SMOKE_BLOCK_EDIT="$ACTION" \
RUMPELMC_VISUAL_SMOKE_BLOCK_EDIT_X="$EDIT_X" \
RUMPELMC_VISUAL_SMOKE_BLOCK_EDIT_Y="$EDIT_Y" \
RUMPELMC_VISUAL_SMOKE_BLOCK_EDIT_Z="$EDIT_Z" \
RUMPELMC_VISUAL_SMOKE_BLOCK_EDIT_ID="$EDIT_BLOCK_ID" \
RUMPELMC_VISUAL_SMOKE_BLOCK_EDIT_WAIT_SEC="$EDIT_WAIT_SEC" \
sh "$ROOT_DIR/scripts/gpu_terrain_movement_stress.sh" "$OUT_DIR"

marker_path="$OUT_DIR/gpu-terrain-movement-stress.png.txt"
test -s "$marker_path" || fail "missing marker $marker_path"
grep -q "block_edit=\"$ACTION\"" "$marker_path" || fail "unexpected block edit action in $marker_path"
require_metric_eq "$marker_path" block_edit_dirty_observed 1
require_metric_ge "$marker_path" chunk_replace 1
require_metric_ge "$marker_path" dirty_chunks 1
require_metric_ge "$marker_path" dirty_blocks 1
require_metric_ge "$marker_path" dirty_last_blocks 1
require_metric_ge "$marker_path" dirty_last_changed_subchunks 1
require_metric_ge "$marker_path" dirty_last_rebuild_subchunks 1
require_metric_eq "$marker_path" gpu_upload_fail 0
write_summary

echo "GPU terrain block edit stress artifacts: $OUT_DIR"
