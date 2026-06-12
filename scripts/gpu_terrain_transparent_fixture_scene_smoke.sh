#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/gpu_transparent_fixture_scene_smoke"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac
GODOT_BIN="${GODOT_BIN:-/opt/homebrew/bin/godot}"
TIMEOUT_BIN="${TIMEOUT_BIN:-/opt/homebrew/bin/timeout}"
GODOT_TIMEOUT_SEC="${GODOT_TIMEOUT_SEC:-120}"
GODOT_QUIT_AFTER_FRAMES="${GODOT_QUIT_AFTER_FRAMES:-8000}"
SMOKE_DELAY_SEC="${SMOKE_DELAY_SEC:-5.0}"
FRAME_SAMPLE_SEC="${RUMPELMC_TRANSPARENT_FIXTURE_SCENE_FRAME_SAMPLE_SEC:-5.0}"

mkdir -p "$OUT_DIR"

fail() {
  echo "gpu_terrain_transparent_fixture_scene_smoke: $*" >&2
  exit 1
}

. "$ROOT_DIR/scripts/godot_rust_ext_profile.sh"

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

screenshot_path="$OUT_DIR/gpu-transparent-fixture-scene-smoke.png"
marker_path="$screenshot_path.txt"
rm -f "$screenshot_path" "$marker_path"

prepare_godot_rust_ext_profile "$ROOT_DIR"

echo "==> GPU transparent fixture scene smoke"
(
  cd "$ROOT_DIR"
  "$TIMEOUT_BIN" "$GODOT_TIMEOUT_SEC" /usr/bin/env \
    RUMPELMC_GPU_TERRAIN_RENDER=1 \
    RUMPELMC_GPU_TERRAIN_TRANSPARENT=1 \
    RUMPELMC_GPU_TERRAIN_PARTIAL_DIRTY_UPLOAD="${RUMPELMC_GPU_TERRAIN_PARTIAL_DIRTY_UPLOAD:-1}" \
    RUMPELMC_GPU_TERRAIN_SHADOW_PROXY_MODE=conservative \
    RUMPELMC_GPU_TERRAIN_SHADOW_PROXY_MESH=compact \
    RUMPELMC_VISUAL_SMOKE_POSE=transparent_fixture \
    RUMPELMC_VISUAL_SMOKE_PATH="$screenshot_path" \
    RUMPELMC_VISUAL_SMOKE_DELAY_SEC="$SMOKE_DELAY_SEC" \
    RUMPELMC_VISUAL_SMOKE_FRAME_SAMPLE_SEC="$FRAME_SAMPLE_SEC" \
    RUMPELMC_VISUAL_SMOKE_FORCE_UNCAPPED="${RUMPELMC_VISUAL_SMOKE_FORCE_UNCAPPED:-0}" \
    RUMPELMC_VISUAL_SMOKE_HIDE_HUD=1 \
    RUMPELMC_VISUAL_SMOKE_DISABLE_PLAYER_INPUT=1 \
    "$GODOT_BIN" --disable-vsync --max-fps 0 --path client --quit-after "$GODOT_QUIT_AFTER_FRAMES"
)

test -s "$screenshot_path" || fail "missing screenshot $screenshot_path"
test -s "$marker_path" || fail "missing marker $marker_path"
grep -q "Visual smoke screenshot saved" "$marker_path" || fail "missing smoke summary in $marker_path"
grep -q "pose=\"transparent_fixture\"" "$marker_path" || fail "unexpected pose in $marker_path"
grep -q "smoke_err=0" "$marker_path" || fail "smoke_err is not 0 in $marker_path"
require_godot_rust_ext_marker_profile "$marker_path"
require_metric_ge "$marker_path" "terrain_samples" 1
require_metric_ge "$marker_path" "terrain_color_buckets" 4
require_metric_ge "$marker_path" "frame_samples" 10
require_metric_ge "$marker_path" "gpu_frames" 1
require_metric_ge "$marker_path" "gpu_subchunks" 1
require_metric_ge "$marker_path" "gpu_uploads" 1
require_metric_eq "$marker_path" "gpu_upload_fail" 0
require_metric_eq "$marker_path" "transparent_requested" 1
require_metric_eq "$marker_path" "transparent_active" 0
require_metric_eq "$marker_path" "transparent_fallback" 1
require_metric_eq "$marker_path" "transparent_blocks" 0
require_metric_eq "$marker_path" "transparent_faces" 0
require_metric_eq "$marker_path" "transparent_draws" 0
require_metric_eq "$marker_path" "transparent_subchunks" 0

{
  printf 'GPU transparent fixture scene smoke summary\n'
  printf 'fixture=gpu-transparent-depth-collision\n'
  printf 'pose=transparent_fixture\n'
  printf 'screenshot=%s\n' "$screenshot_path"
  printf 'marker=%s\n' "$marker_path"
  printf 'summary transparent_fixture_scene_smoke_status=pass transparent_requested=1 transparent_active=0 transparent_fallback=1 transparent_blocks=0 transparent_faces=0 transparent_draws=0 transparent_subchunks=0 gpu_upload_fail=0\n'
} > "$OUT_DIR/transparent-fixture-scene-smoke-summary.txt"

cat "$OUT_DIR/transparent-fixture-scene-smoke-summary.txt"
cat "$marker_path"

if command -v sips >/dev/null 2>&1; then
  sips -g pixelWidth -g pixelHeight "$screenshot_path"
fi

echo "GPU transparent fixture scene smoke artifacts: $OUT_DIR"
