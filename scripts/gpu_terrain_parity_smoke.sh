#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/gpu_terrain_visual_smoke/parity"}"
GODOT_BIN="${GODOT_BIN:-/opt/homebrew/bin/godot}"
TIMEOUT_BIN="${TIMEOUT_BIN:-/opt/homebrew/bin/timeout}"
GODOT_TIMEOUT_SEC="${GODOT_TIMEOUT_SEC:-90}"
GODOT_QUIT_AFTER_FRAMES="${GODOT_QUIT_AFTER_FRAMES:-800}"
SMOKE_DELAY_SEC="${SMOKE_DELAY_SEC:-4.0}"
MAX_AVG_LUMA_DELTA="${MAX_AVG_LUMA_DELTA:-0.16}"
MAX_TERRAIN_LUMA_RANGE_DELTA="${MAX_TERRAIN_LUMA_RANGE_DELTA:-0.12}"
MAX_TERRAIN_SAMPLE_DELTA_PERCENT="${MAX_TERRAIN_SAMPLE_DELTA_PERCENT:-35}"
MIN_TERRAIN_SAMPLE_DELTA="${MIN_TERRAIN_SAMPLE_DELTA:-64}"
MAX_TERRAIN_COLOR_BUCKET_DELTA_PERCENT="${MAX_TERRAIN_COLOR_BUCKET_DELTA_PERCENT:-70}"
MIN_TERRAIN_COLOR_BUCKET_DELTA="${MIN_TERRAIN_COLOR_BUCKET_DELTA:-8}"
MIN_TERRAIN_REGION_SAMPLES="${MIN_TERRAIN_REGION_SAMPLES:-8}"
MIN_TERRAIN_COLOR_BUCKETS="${MIN_TERRAIN_COLOR_BUCKETS:-4}"
MIN_TERRAIN_CHROMA_SAMPLES="${MIN_TERRAIN_CHROMA_SAMPLES:-8}"
MIN_TERRAIN_LUMA_RANGE="${MIN_TERRAIN_LUMA_RANGE:-0.06}"
VALIDATE_ONLY="${RUMPELMC_PARITY_SMOKE_VALIDATE_ONLY:-0}"

mkdir -p "$OUT_DIR"

fail() {
  echo "gpu_terrain_parity_smoke: $*" >&2
  exit 1
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

require_metric_absent() {
  marker_path="$1"
  key="$2"
  value="$(metric "$key" "$marker_path")"
  if [ -n "$value" ]; then
    fail "$key unexpectedly present as $value in $marker_path"
  fi
}

require_float_metric_ge() {
  marker_path="$1"
  key="$2"
  min_value="$3"
  value="$(float_metric "$key" "$marker_path")"
  test -n "$value" || fail "missing $key in $marker_path"
  awk -v value="$value" -v min_value="$min_value" -v key="$key" -v marker_path="$marker_path" '
    BEGIN {
      if (value + 0 < min_value + 0) {
        printf("gpu_terrain_parity_smoke: %s=%.4f is below %.4f in %s\n", key, value, min_value, marker_path) > "/dev/stderr"
        exit 1
      }
    }
  '
}

validate_common_marker() {
  marker_path="$1"
  screenshot_path="${marker_path%.txt}"

  test -s "$screenshot_path" || fail "missing screenshot $screenshot_path"
  test -s "$marker_path" || fail "missing marker $marker_path"
  grep -q "Visual smoke screenshot saved" "$marker_path" || fail "missing smoke summary in $marker_path"
  grep -q "current_chunk=\"0,0\"" "$marker_path" || fail "unexpected current chunk in $marker_path"
  grep -q "smoke_err=0" "$marker_path" || fail "smoke_err is not 0 in $marker_path"
  require_metric_ge "$marker_path" "terrain_samples" 1
  require_metric_ge "$marker_path" "lit_samples" 1
  require_metric_ge "$marker_path" "collision" 1
  require_metric_ge "$marker_path" "terrain_mid_samples" "$MIN_TERRAIN_REGION_SAMPLES"
  require_metric_ge "$marker_path" "terrain_bottom_samples" "$MIN_TERRAIN_REGION_SAMPLES"
  require_metric_ge "$marker_path" "terrain_left_samples" "$MIN_TERRAIN_REGION_SAMPLES"
  require_metric_ge "$marker_path" "terrain_right_samples" "$MIN_TERRAIN_REGION_SAMPLES"
  require_metric_ge "$marker_path" "terrain_color_buckets" "$MIN_TERRAIN_COLOR_BUCKETS"
  require_metric_ge "$marker_path" "terrain_chroma_samples" "$MIN_TERRAIN_CHROMA_SAMPLES"
  require_float_metric_ge "$marker_path" "terrain_luma_range" "$MIN_TERRAIN_LUMA_RANGE"
}

run_case() {
  name="$1"
  gpu_flag="$2"
  shadow_radius="$3"
  screenshot_path="$OUT_DIR/$name.png"
  marker_path="$screenshot_path.txt"

  rm -f "$screenshot_path" "$marker_path"

  echo "==> Godot terrain parity smoke: $name"
  (
    cd "$ROOT_DIR"
    "$TIMEOUT_BIN" "$GODOT_TIMEOUT_SEC" /usr/bin/env \
      RUMPELMC_GPU_TERRAIN_RENDER="$gpu_flag" \
      RUMPELMC_GPU_TERRAIN_SHADOW_PROXY_CHUNK_DISTANCE="$shadow_radius" \
      RUMPELMC_VISUAL_SMOKE_PATH="$screenshot_path" \
      RUMPELMC_VISUAL_SMOKE_DELAY_SEC="$SMOKE_DELAY_SEC" \
      RUMPELMC_VISUAL_SMOKE_HIDE_HUD=1 \
      RUMPELMC_VISUAL_SMOKE_DISABLE_PLAYER_INPUT=1 \
      "$GODOT_BIN" --path client --quit-after "$GODOT_QUIT_AFTER_FRAMES"
  )

  validate_common_marker "$marker_path"
  cat "$marker_path"
  if command -v sips >/dev/null 2>&1; then
    sips -g pixelWidth -g pixelHeight "$screenshot_path"
  fi
}

require_float_delta_le() {
  left="$1"
  right="$2"
  max_delta="$3"
  label="$4"
  awk -v left="$left" -v right="$right" -v max_delta="$max_delta" -v label="$label" '
    BEGIN {
      delta = left - right
      if (delta < 0) {
        delta = -delta
      }
      if (delta > max_delta) {
        printf("gpu_terrain_parity_smoke: %s delta %.4f exceeds %.4f (left=%.4f right=%.4f)\n", label, delta, max_delta, left, right) > "/dev/stderr"
        exit 1
      }
    }
  '
}

require_int_delta_percent_le() {
  left="$1"
  right="$2"
  percent="$3"
  min_delta="$4"
  label="$5"
  delta=$((left - right))
  if [ "$delta" -lt 0 ]; then
    delta=$((-delta))
  fi
  allowed=$((left * percent / 100))
  if [ "$allowed" -lt "$min_delta" ]; then
    allowed="$min_delta"
  fi
  if [ "$delta" -gt "$allowed" ]; then
    fail "$label delta $delta exceeds $allowed (left=$left right=$right)"
  fi
}

validate_parity_markers() {
  cpu_marker="$OUT_DIR/cpu-arraymesh-parity.png.txt"
  gpu_marker="$OUT_DIR/gpu-terrain-parity.png.txt"
  radius_marker="$OUT_DIR/gpu-terrain-radius1-parity.png.txt"

  validate_common_marker "$cpu_marker"
  validate_common_marker "$gpu_marker"
  validate_common_marker "$radius_marker"

  require_metric_absent "$cpu_marker" "gpu_frames"
  require_metric_absent "$cpu_marker" "gpu_subchunks"
  require_metric_eq "$cpu_marker" "fast_proxy" 0

  require_metric_ge "$gpu_marker" "gpu_frames" 1
  require_metric_ge "$gpu_marker" "gpu_subchunks" 1
  require_metric_ge "$gpu_marker" "gpu_faces" 1
  require_metric_ge "$gpu_marker" "fast_proxy" 1

  require_metric_ge "$radius_marker" "gpu_frames" 1
  require_metric_ge "$radius_marker" "gpu_subchunks" 1
  require_metric_eq "$radius_marker" "cpu_proxy" "$(metric "collision" "$radius_marker")"
  require_metric_ge "$radius_marker" "fast_proxy" 1

  cpu_luma="$(float_metric "avg_luma" "$cpu_marker")"
  gpu_luma="$(float_metric "avg_luma" "$gpu_marker")"
  test -n "$cpu_luma" || fail "missing CPU avg_luma"
  test -n "$gpu_luma" || fail "missing GPU avg_luma"
  require_float_delta_le "$cpu_luma" "$gpu_luma" "$MAX_AVG_LUMA_DELTA" "avg_luma"

  cpu_luma_range="$(float_metric "terrain_luma_range" "$cpu_marker")"
  gpu_luma_range="$(float_metric "terrain_luma_range" "$gpu_marker")"
  test -n "$cpu_luma_range" || fail "missing CPU terrain_luma_range"
  test -n "$gpu_luma_range" || fail "missing GPU terrain_luma_range"
  require_float_delta_le \
    "$cpu_luma_range" \
    "$gpu_luma_range" \
    "$MAX_TERRAIN_LUMA_RANGE_DELTA" \
    "terrain_luma_range"

  cpu_terrain_samples="$(metric "terrain_samples" "$cpu_marker")"
  gpu_terrain_samples="$(metric "terrain_samples" "$gpu_marker")"
  require_int_delta_percent_le \
    "$cpu_terrain_samples" \
    "$gpu_terrain_samples" \
    "$MAX_TERRAIN_SAMPLE_DELTA_PERCENT" \
    "$MIN_TERRAIN_SAMPLE_DELTA" \
    "terrain_samples"

  cpu_terrain_color_buckets="$(metric "terrain_color_buckets" "$cpu_marker")"
  gpu_terrain_color_buckets="$(metric "terrain_color_buckets" "$gpu_marker")"
  require_int_delta_percent_le \
    "$cpu_terrain_color_buckets" \
    "$gpu_terrain_color_buckets" \
    "$MAX_TERRAIN_COLOR_BUCKET_DELTA_PERCENT" \
    "$MIN_TERRAIN_COLOR_BUCKET_DELTA" \
    "terrain_color_buckets"

  cpu_terrain_chroma_samples="$(metric "terrain_chroma_samples" "$cpu_marker")"
  gpu_terrain_chroma_samples="$(metric "terrain_chroma_samples" "$gpu_marker")"
  require_int_delta_percent_le \
    "$cpu_terrain_chroma_samples" \
    "$gpu_terrain_chroma_samples" \
    "$MAX_TERRAIN_SAMPLE_DELTA_PERCENT" \
    "$MIN_TERRAIN_SAMPLE_DELTA" \
    "terrain_chroma_samples"
}

if [ "$VALIDATE_ONLY" != "1" ]; then
  run_case "cpu-arraymesh-parity" "0" ""
  run_case "gpu-terrain-parity" "1" ""
  run_case "gpu-terrain-radius1-parity" "1" "1"
fi

validate_parity_markers

echo "Terrain parity smoke passed: $OUT_DIR"
