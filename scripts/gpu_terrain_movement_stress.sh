#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/gpu_terrain_visual_smoke/movement_stress"}"
GODOT_BIN="${GODOT_BIN:-/opt/homebrew/bin/godot}"
TIMEOUT_BIN="${TIMEOUT_BIN:-/opt/homebrew/bin/timeout}"
GODOT_TIMEOUT_SEC="${GODOT_TIMEOUT_SEC:-120}"
GODOT_QUIT_AFTER_FRAMES="${GODOT_QUIT_AFTER_FRAMES:-8000}"
SMOKE_DELAY_SEC="${SMOKE_DELAY_SEC:-5.0}"
FRAME_SAMPLE_SEC="${RUMPELMC_MOVEMENT_STRESS_FRAME_SAMPLE_SEC:-5.0}"
MOTION_STEP_SEC="${RUMPELMC_MOVEMENT_STRESS_STEP_SEC:-0.55}"
MOTION_SETTLE_SEC="${RUMPELMC_MOVEMENT_STRESS_SETTLE_SEC:-4.0}"
MIN_MOTION_CHUNKS="${RUMPELMC_MOVEMENT_STRESS_MIN_CHUNKS:-4}"

mkdir -p "$OUT_DIR"

fail() {
  echo "gpu_terrain_movement_stress: $*" >&2
  exit 1
}

metric() {
  key="$1"
  marker_path="$2"
  sed -n "s/.*$key=\([0-9][0-9]*\).*/\1/p" "$marker_path" | sed -n '1p'
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

screenshot_path="$OUT_DIR/gpu-terrain-movement-stress.png"
marker_path="$screenshot_path.txt"
rm -f "$screenshot_path" "$marker_path"

echo "==> GPU terrain movement stress"
(
  cd "$ROOT_DIR"
  "$TIMEOUT_BIN" "$GODOT_TIMEOUT_SEC" /usr/bin/env \
    RUMPELMC_GPU_TERRAIN_RENDER=1 \
    RUMPELMC_GPU_TERRAIN_SHADOW_PROXY_MODE=conservative \
    RUMPELMC_GPU_TERRAIN_SHADOW_PROXY_MESH=compact \
    RUMPELMC_VISUAL_SMOKE_MOTION=chunk_walk \
    RUMPELMC_VISUAL_SMOKE_MOTION_STEP_SEC="$MOTION_STEP_SEC" \
    RUMPELMC_VISUAL_SMOKE_MOTION_SETTLE_SEC="$MOTION_SETTLE_SEC" \
    RUMPELMC_VISUAL_SMOKE_PATH="$screenshot_path" \
    RUMPELMC_VISUAL_SMOKE_DELAY_SEC="$SMOKE_DELAY_SEC" \
    RUMPELMC_VISUAL_SMOKE_FRAME_SAMPLE_SEC="$FRAME_SAMPLE_SEC" \
    RUMPELMC_VISUAL_SMOKE_HIDE_HUD=1 \
    RUMPELMC_VISUAL_SMOKE_DISABLE_PLAYER_INPUT=1 \
    "$GODOT_BIN" --path client --quit-after "$GODOT_QUIT_AFTER_FRAMES"
)

test -s "$screenshot_path" || fail "missing screenshot $screenshot_path"
test -s "$marker_path" || fail "missing marker $marker_path"
grep -q "Visual smoke screenshot saved" "$marker_path" || fail "missing smoke summary in $marker_path"
grep -q 'motion="chunk_walk"' "$marker_path" || fail "unexpected motion in $marker_path"
grep -q 'current_chunk="3,2"' "$marker_path" || fail "movement did not finish in chunk 3,2"
grep -q "smoke_err=0" "$marker_path" || fail "smoke_err is not 0 in $marker_path"
require_metric_ge "$marker_path" "motion_steps" 4
require_metric_ge "$marker_path" "motion_chunks" "$MIN_MOTION_CHUNKS"
require_metric_ge "$marker_path" "frame_samples" 10
require_metric_ge "$marker_path" "terrain_samples" 1
require_metric_ge "$marker_path" "queue_max" 1
require_metric_ge "$marker_path" "queue_enq" 1
require_metric_ge "$marker_path" "queue_drained" 1
require_metric_ge "$marker_path" "queue_stale" 0
require_metric_ge "$marker_path" "queue_missing" 0
require_metric_ge "$marker_path" "gpu_frames" 1
require_metric_ge "$marker_path" "gpu_subchunks" 1
require_metric_ge "$marker_path" "gpu_uploads" 1
require_metric_eq "$marker_path" "gpu_upload_fail" 0
require_metric_eq "$marker_path" "gpu_upload_fail_capacity" 0
require_metric_eq "$marker_path" "gpu_upload_fail_fragmented" 0

cat "$marker_path"

if command -v sips >/dev/null 2>&1; then
  sips -g pixelWidth -g pixelHeight "$screenshot_path"
fi

echo "GPU terrain movement stress artifacts: $OUT_DIR"
