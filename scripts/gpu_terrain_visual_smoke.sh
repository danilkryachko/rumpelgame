#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/gpu_terrain_visual_smoke"}"
GODOT_BIN="${GODOT_BIN:-/opt/homebrew/bin/godot}"
TIMEOUT_BIN="${TIMEOUT_BIN:-/opt/homebrew/bin/timeout}"
GODOT_TIMEOUT_SEC="${GODOT_TIMEOUT_SEC:-90}"
GODOT_QUIT_AFTER_FRAMES="${GODOT_QUIT_AFTER_FRAMES:-480}"
SMOKE_DELAY_SEC="${SMOKE_DELAY_SEC:-6.0}"

mkdir -p "$OUT_DIR"

run_case() {
  name="$1"
  gpu_flag="$2"
  screenshot_path="$OUT_DIR/$name.png"
  marker_path="$screenshot_path.txt"

  rm -f "$screenshot_path" "$marker_path"

  echo "==> Godot visual smoke: $name"
  (
    cd "$ROOT_DIR"
    "$TIMEOUT_BIN" "$GODOT_TIMEOUT_SEC" /usr/bin/env \
      RUMPELMC_GPU_TERRAIN_RENDER="$gpu_flag" \
      RUMPELMC_VISUAL_SMOKE_PATH="$screenshot_path" \
      RUMPELMC_VISUAL_SMOKE_DELAY_SEC="$SMOKE_DELAY_SEC" \
      RUMPELMC_VISUAL_SMOKE_HIDE_HUD=1 \
      RUMPELMC_VISUAL_SMOKE_DISABLE_PLAYER_INPUT=1 \
      "$GODOT_BIN" --path client --quit-after "$GODOT_QUIT_AFTER_FRAMES"
  )

  test -s "$screenshot_path"
  test -s "$marker_path"
  grep -q "Visual smoke screenshot saved" "$marker_path"
  grep -q "current_chunk=\"0,0\"" "$marker_path"
  grep -q "smoke_err=0" "$marker_path"
  grep -Eq "terrain_samples=[1-9][0-9]*" "$marker_path"
  if [ "$gpu_flag" = "1" ]; then
    grep -Eq "gpu_frames=[1-9][0-9]*" "$marker_path"
  fi

  cat "$marker_path"

  if command -v sips >/dev/null 2>&1; then
    sips -g pixelWidth -g pixelHeight "$screenshot_path"
  fi
}

run_case "cpu-arraymesh" "0"
run_case "gpu-terrain" "1"

echo "Visual smoke artifacts: $OUT_DIR"
