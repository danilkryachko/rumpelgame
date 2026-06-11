#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/gpu_terrain_pacing_matrix"}"
GODOT_BIN="${GODOT_BIN:-/opt/homebrew/bin/godot}"
TIMEOUT_BIN="${TIMEOUT_BIN:-/opt/homebrew/bin/timeout}"
GODOT_TIMEOUT_SEC="${GODOT_TIMEOUT_SEC:-120}"
GODOT_QUIT_AFTER_FRAMES="${GODOT_QUIT_AFTER_FRAMES:-8000}"
SMOKE_DELAY_SEC="${SMOKE_DELAY_SEC:-6.0}"
FRAME_SAMPLE_SEC="${RUMPELMC_PACING_MATRIX_FRAME_SAMPLE_SEC:-3.0}"
SMOKE_POSE="${RUMPELMC_PACING_MATRIX_POSE:-lighting_shadow}"
MAX_FPS_CASES="${RUMPELMC_PACING_MATRIX_MAX_FPS_CASES:-30 0 150 240}"

mkdir -p "$OUT_DIR"

fail() {
  echo "gpu_terrain_pacing_matrix: $*" >&2
  exit 1
}

. "$ROOT_DIR/scripts/godot_rust_ext_profile.sh"

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

require_marker() {
  marker_path="$1"
  expected_max_fps="$2"
  test -s "$marker_path" || fail "missing marker $marker_path"
  grep -q "Visual smoke screenshot saved" "$marker_path" || fail "missing smoke summary in $marker_path"
  grep -q "pose=\"$SMOKE_POSE\"" "$marker_path" || fail "unexpected pose in $marker_path"
  grep -q "smoke_err=0" "$marker_path" || fail "smoke_err is not 0 in $marker_path"
  require_godot_rust_ext_marker_profile "$marker_path"
  actual_max_fps="$(metric engine_max_fps "$marker_path")"
  test "$actual_max_fps" = "$expected_max_fps" || fail "engine_max_fps=$actual_max_fps, expected $expected_max_fps in $marker_path"
  test "$(metric vsync_mode "$marker_path")" = "0" || fail "vsync_mode is not disabled in $marker_path"
  test -n "$(float_metric fps_avg "$marker_path")" || fail "missing fps_avg in $marker_path"
  test -n "$(float_metric screen_refresh_hz "$marker_path")" || fail "missing screen_refresh_hz in $marker_path"
}

run_case() {
  max_fps="$1"
  name="gpu-maxfps-$max_fps"
  screenshot_path="$OUT_DIR/$name.png"
  marker_path="$screenshot_path.txt"

  rm -f "$marker_path" "$screenshot_path"

  echo "==> GPU terrain pacing matrix: max_fps=$max_fps"
  (
    cd "$ROOT_DIR"
    "$TIMEOUT_BIN" "$GODOT_TIMEOUT_SEC" /usr/bin/env \
      RUMPELMC_GPU_TERRAIN_RENDER=1 \
      RUMPELMC_GPU_TERRAIN_SHADOW_PROXY_MODE=conservative \
      RUMPELMC_GPU_TERRAIN_SHADOW_PROXY_MESH=compact \
      RUMPELMC_VISUAL_SMOKE_FORCE_UNCAPPED=1 \
      RUMPELMC_VISUAL_SMOKE_MAX_FPS="$max_fps" \
      RUMPELMC_VISUAL_SMOKE_POSE="$SMOKE_POSE" \
      RUMPELMC_VISUAL_SMOKE_PATH="$screenshot_path" \
      RUMPELMC_VISUAL_SMOKE_DELAY_SEC="$SMOKE_DELAY_SEC" \
      RUMPELMC_VISUAL_SMOKE_FRAME_SAMPLE_SEC="$FRAME_SAMPLE_SEC" \
      RUMPELMC_VISUAL_SMOKE_HIDE_HUD=1 \
      RUMPELMC_VISUAL_SMOKE_DISABLE_PLAYER_INPUT=1 \
      "$GODOT_BIN" --disable-vsync --max-fps 0 --path client --quit-after "$GODOT_QUIT_AFTER_FRAMES"
  )

  require_marker "$marker_path" "$max_fps"
}

print_case() {
  max_fps="$1"
  marker_path="$OUT_DIR/gpu-maxfps-$max_fps.png.txt"
  printf 'max_fps=%s fps_avg=%s fps_p05=%s frame_avg_ms=%s frame_p95_ms=%s process_wall_avg_ms=%s post_draw_wait_ms=%s engine_max_fps=%s vsync_mode=%s screen_refresh_hz=%s gpu_frames=%s gpu_subchunks=%s gpu_draws=%s gpu_faces=%s\n' \
    "$max_fps" \
    "$(float_metric fps_avg "$marker_path")" \
    "$(float_metric fps_p05 "$marker_path")" \
    "$(float_metric frame_avg_ms "$marker_path")" \
    "$(float_metric frame_p95_ms "$marker_path")" \
    "$(float_metric process_wall_avg_ms "$marker_path")" \
    "$(float_metric post_draw_wait_ms "$marker_path")" \
    "$(metric engine_max_fps "$marker_path")" \
    "$(metric vsync_mode "$marker_path")" \
    "$(float_metric screen_refresh_hz "$marker_path")" \
    "$(metric gpu_frames "$marker_path")" \
    "$(metric gpu_subchunks "$marker_path")" \
    "$(metric gpu_draws "$marker_path")" \
    "$(metric gpu_faces "$marker_path")"
}

prepare_godot_rust_ext_profile "$ROOT_DIR"
for max_fps in $MAX_FPS_CASES; do
  run_case "$max_fps"
done

summary_path="$OUT_DIR/pacing-matrix-summary.txt"
{
  echo "GPU terrain pacing matrix summary"
  for max_fps in $MAX_FPS_CASES; do
    print_case "$max_fps"
  done
} | tee "$summary_path"

echo "GPU terrain pacing matrix artifacts: $OUT_DIR"
