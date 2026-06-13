#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/gpu_terrain_visual_smoke/parity"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac
GODOT_BIN="${GODOT_BIN:-/opt/homebrew/bin/godot}"
TIMEOUT_BIN="${TIMEOUT_BIN:-/opt/homebrew/bin/timeout}"
GODOT_TIMEOUT_SEC="${GODOT_TIMEOUT_SEC:-90}"
GODOT_QUIT_AFTER_FRAMES="${GODOT_QUIT_AFTER_FRAMES:-2000}"
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

. "$ROOT_DIR/scripts/godot_rust_ext_profile.sh"

mkdir -p "$OUT_DIR"

fail() {
  echo "gpu_terrain_parity_smoke: $*" >&2
  exit 1
}

metric() {
  key="$1"
  marker_path="$2"
  awk -v key="$key" '
    {
      for (i = 1; i <= NF; i++) {
        split($i, kv, "=")
        if (kv[1] == key && match(kv[2], /^[0-9][0-9]*/)) {
          print substr(kv[2], RSTART, RLENGTH)
          exit
        }
      }
    }
  ' "$marker_path"
}

float_metric() {
  key="$1"
  marker_path="$2"
  awk -v key="$key" '
    {
      for (i = 1; i <= NF; i++) {
        split($i, kv, "=")
        if (kv[1] == key && match(kv[2], /^[0-9][0-9]*\.[0-9][0-9]*/)) {
          print substr(kv[2], RSTART, RLENGTH)
          exit
        }
      }
    }
  ' "$marker_path"
}

text_metric() {
  key="$1"
  marker_path="$2"
  awk -v key="$key" '
    {
      for (i = 1; i <= NF; i++) {
        split($i, kv, "=")
        if (kv[1] == key) {
          gsub(/^"/, "", kv[2])
          gsub(/"$/, "", kv[2])
          print kv[2]
          exit
        }
      }
    }
  ' "$marker_path"
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

require_text_metric_eq() {
  marker_path="$1"
  key="$2"
  expected="$3"
  value="$(text_metric "$key" "$marker_path")"
  test -n "$value" || fail "missing $key in $marker_path"
  if [ "$value" != "$expected" ]; then
    fail "$key=$value, expected $expected in $marker_path"
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
  expected_pose="$2"
  expected_shadow_mode="$3"
  expected_shadow_mesh="$4"
  expected_shadow_path="$5"
  screenshot_path="${marker_path%.txt}"

  test -s "$screenshot_path" || fail "missing screenshot $screenshot_path"
  test -s "$marker_path" || fail "missing marker $marker_path"
  grep -q "Visual smoke screenshot saved" "$marker_path" || fail "missing smoke summary in $marker_path"
  grep -q "pose=\"$expected_pose\"" "$marker_path" || fail "unexpected pose in $marker_path"
  grep -q "shadow_path=$expected_shadow_path" "$marker_path" || fail "unexpected shadow path in $marker_path"
  grep -q "shadow_mode=$expected_shadow_mode" "$marker_path" || fail "unexpected shadow mode in $marker_path"
  grep -q "shadow_mesh=$expected_shadow_mesh" "$marker_path" || fail "unexpected shadow mesh in $marker_path"
  grep -q "current_chunk=\"0,0\"" "$marker_path" || fail "unexpected current chunk in $marker_path"
  grep -q "smoke_err=0" "$marker_path" || fail "smoke_err is not 0 in $marker_path"
  if [ "$VALIDATE_ONLY" != "1" ]; then
    require_godot_rust_ext_marker_profile "$marker_path"
  fi
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
  require_metric_ge "$marker_path" "proxy_coll" 1
  require_metric_ge "$marker_path" "proxy_shadow" 0
  require_metric_ge "$marker_path" "proxy_both" 0
  require_metric_ge "$marker_path" "proxy_shadow_only" 0
  require_metric_ge "$marker_path" "compact_shadow_normals_saved" 0
  require_metric_ge "$marker_path" "compact_collision_proxy" 0
  require_metric_ge "$marker_path" "compact_collision_normals_saved" 0
  require_metric_eq "$marker_path" "proxy_coll" "$(metric "collision" "$marker_path")"
}

validate_native_shadow_fallback_marker() {
  marker_path="$1"

  validate_common_marker "$marker_path" "default" "conservative" "compact" "godot_proxy"
  require_metric_eq "$marker_path" "native_shadow_requested" 1
  require_metric_eq "$marker_path" "native_shadow_active" 0
  require_metric_eq "$marker_path" "native_shadow_fallback" 1
  require_metric_ge "$marker_path" "gpu_frames" 1
  require_metric_ge "$marker_path" "gpu_subchunks" 1
  require_metric_ge "$marker_path" "gpu_faces" 1
  require_metric_ge "$marker_path" "proxy_shadow" 1
  require_metric_ge "$marker_path" "proxy_both" 1
  require_metric_ge "$marker_path" "compact_shadow_proxy" 1
  require_metric_ge \
    "$marker_path" \
    "compact_shadow_normals_saved" \
    "$(metric "compact_shadow_proxy" "$marker_path")"
  require_metric_eq "$marker_path" "compact_collision_proxy" 0
  require_metric_eq "$marker_path" "compact_collision_normals_saved" 0
}

run_case() {
  name="$1"
  gpu_flag="$2"
  shadow_radius="$3"
  pose="$4"
  shadow_mode="$5"
  shadow_mesh="$6"
  native_shadow="${7:-0}"
  screenshot_path="$OUT_DIR/$name.png"
  marker_path="$screenshot_path.txt"
  expected_shadow_mesh="$shadow_mesh"
  if [ "$shadow_mesh" = "" ] || [ "$shadow_mesh" = "default" ]; then
    expected_shadow_mesh="compact"
  fi
  expected_shadow_path="godot_proxy"
  if [ "$gpu_flag" != "1" ]; then
    expected_shadow_path="arraymesh"
  elif [ "$shadow_mode" = "collision_only" ]; then
    expected_shadow_path="diagnostic_no_shadow_proxy"
  elif [ "$shadow_radius" = "0" ]; then
    expected_shadow_path="scene_shadows_disabled"
  fi

  rm -f "$screenshot_path" "$marker_path"

  echo "==> Godot terrain parity smoke: $name"
  (
    cd "$ROOT_DIR"
    "$TIMEOUT_BIN" "$GODOT_TIMEOUT_SEC" /usr/bin/env \
      RUMPELMC_GPU_TERRAIN_RENDER="$gpu_flag" \
      RUMPELMC_GPU_TERRAIN_SHADOW_PROXY_CHUNK_DISTANCE="$shadow_radius" \
      RUMPELMC_GPU_TERRAIN_SHADOW_PROXY_MODE="$shadow_mode" \
      RUMPELMC_GPU_TERRAIN_SHADOW_PROXY_MESH="$shadow_mesh" \
      RUMPELMC_GPU_TERRAIN_NATIVE_SHADOW="$native_shadow" \
      RUMPELMC_VISUAL_SMOKE_POSE="$pose" \
      RUMPELMC_VISUAL_SMOKE_PATH="$screenshot_path" \
      RUMPELMC_VISUAL_SMOKE_DELAY_SEC="$SMOKE_DELAY_SEC" \
      RUMPELMC_VISUAL_SMOKE_HIDE_HUD=1 \
      RUMPELMC_VISUAL_SMOKE_DISABLE_PLAYER_INPUT=1 \
      "$GODOT_BIN" --path client --quit-after "$GODOT_QUIT_AFTER_FRAMES"
  )

  validate_common_marker "$marker_path" "$pose" "$shadow_mode" "$expected_shadow_mesh" "$expected_shadow_path"
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
  shadow_disabled_marker="$OUT_DIR/gpu-terrain-shadow-disabled-parity.png.txt"
  collision_only_marker="$OUT_DIR/gpu-terrain-collision-only-parity.png.txt"
  compact_shadow_marker="$OUT_DIR/gpu-terrain-compact-shadow-parity.png.txt"
  native_fallback_marker="$OUT_DIR/gpu-terrain-native-shadow-fallback-parity.png.txt"
  compact_lighting_shadow_marker="$OUT_DIR/gpu-terrain-compact-lighting-shadow-parity.png.txt"
  low_angle_cpu_marker="$OUT_DIR/cpu-arraymesh-lighting-low-angle-parity.png.txt"
  low_angle_gpu_marker="$OUT_DIR/gpu-terrain-lighting-low-angle-parity.png.txt"
  compact_low_angle_marker="$OUT_DIR/gpu-terrain-compact-lighting-low-angle-parity.png.txt"
  texture_stand_cpu_marker="$OUT_DIR/cpu-arraymesh-texture-stand-parity.png.txt"
  texture_stand_gpu_marker="$OUT_DIR/gpu-terrain-texture-stand-parity.png.txt"

  validate_common_marker "$cpu_marker" "default" "conservative" "full" "arraymesh"
  validate_common_marker "$gpu_marker" "default" "conservative" "compact" "godot_proxy"
  validate_common_marker "$radius_marker" "default" "conservative" "full" "godot_proxy"
  validate_pose_pair_with_mesh "$cpu_marker" "$gpu_marker" "default" "full" "compact"

  require_metric_absent "$cpu_marker" "gpu_frames"
  require_metric_absent "$cpu_marker" "gpu_subchunks"
  require_metric_eq "$cpu_marker" "fast_proxy" 0
  require_metric_eq "$cpu_marker" "proxy_shadow" 0
  require_metric_eq "$cpu_marker" "proxy_both" 0
  require_metric_eq "$cpu_marker" "proxy_shadow_only" 0
  require_metric_eq "$cpu_marker" "compact_shadow_proxy" 0
  require_metric_eq "$cpu_marker" "compact_shadow_normals_saved" 0
  require_metric_eq "$cpu_marker" "compact_collision_proxy" 0
  require_metric_eq "$cpu_marker" "compact_collision_normals_saved" 0

  require_metric_ge "$gpu_marker" "gpu_frames" 1
  require_metric_ge "$gpu_marker" "gpu_subchunks" 1
  require_metric_ge "$gpu_marker" "gpu_faces" 1
  require_metric_ge "$gpu_marker" "fast_proxy" 1
  require_metric_ge "$gpu_marker" "compact_shadow_proxy" 1
  require_metric_ge \
    "$gpu_marker" \
    "compact_shadow_normals_saved" \
    "$(metric "compact_shadow_proxy" "$gpu_marker")"
  require_metric_ge "$gpu_marker" "proxy_shadow" 1
  require_metric_ge "$gpu_marker" "proxy_both" 1
  require_metric_eq "$gpu_marker" "compact_collision_proxy" 0
  require_metric_eq "$gpu_marker" "compact_collision_normals_saved" 0

  if [ -s "$native_fallback_marker" ]; then
    validate_native_shadow_fallback_marker "$native_fallback_marker"
    validate_visual_metric_pair "$gpu_marker" "$native_fallback_marker" "native_shadow_fallback"
  elif [ "$VALIDATE_ONLY" != "1" ]; then
    fail "missing native shadow fallback marker $native_fallback_marker"
  fi

  require_metric_ge "$radius_marker" "gpu_frames" 1
  require_metric_ge "$radius_marker" "gpu_subchunks" 1
  require_metric_eq "$radius_marker" "cpu_proxy" "$(metric "collision" "$radius_marker")"
  require_metric_eq "$radius_marker" "proxy_shadow" "$(metric "collision" "$radius_marker")"
  require_metric_eq "$radius_marker" "proxy_both" "$(metric "collision" "$radius_marker")"
  require_metric_eq "$radius_marker" "proxy_shadow_only" 0
  require_metric_eq "$radius_marker" "compact_shadow_proxy" 0
  require_metric_eq "$radius_marker" "compact_shadow_normals_saved" 0
  require_metric_eq "$radius_marker" "compact_collision_proxy" 0
  require_metric_eq "$radius_marker" "compact_collision_normals_saved" 0
  require_metric_ge "$radius_marker" "fast_proxy" 1

  validate_common_marker "$shadow_disabled_marker" "default" "conservative" "full" "scene_shadows_disabled"
  require_metric_ge "$shadow_disabled_marker" "gpu_frames" 1
  require_metric_ge "$shadow_disabled_marker" "gpu_subchunks" 1
  require_metric_eq "$shadow_disabled_marker" "cpu_proxy" "$(metric "collision" "$shadow_disabled_marker")"
  require_metric_eq "$shadow_disabled_marker" "proxy_shadow" 0
  require_metric_eq "$shadow_disabled_marker" "proxy_both" 0
  require_metric_eq "$shadow_disabled_marker" "proxy_shadow_only" 0
  require_metric_eq "$shadow_disabled_marker" "compact_shadow_proxy" 0
  require_metric_eq "$shadow_disabled_marker" "compact_shadow_normals_saved" 0
  require_metric_eq "$shadow_disabled_marker" "compact_collision_proxy" "$(metric "fast_proxy" "$shadow_disabled_marker")"
  require_metric_ge \
    "$shadow_disabled_marker" \
    "compact_collision_normals_saved" \
    "$(metric "compact_collision_proxy" "$shadow_disabled_marker")"
  require_metric_eq "$shadow_disabled_marker" "mesh_visible" 0
  require_metric_eq "$shadow_disabled_marker" "mesh_shadow_off" "$(metric "cpu_proxy" "$shadow_disabled_marker")"
  require_metric_eq "$shadow_disabled_marker" "mesh_shadow_double" 0
  require_metric_eq "$shadow_disabled_marker" "mesh_shadow_only" 0
  require_metric_ge "$shadow_disabled_marker" "fast_proxy" 1

  validate_common_marker "$collision_only_marker" "default" "collision_only" "full" "diagnostic_no_shadow_proxy"
  require_metric_ge "$collision_only_marker" "gpu_frames" 1
  require_metric_ge "$collision_only_marker" "gpu_subchunks" 1
  require_metric_eq "$collision_only_marker" "cpu_proxy" "$(metric "collision" "$collision_only_marker")"
  require_metric_eq "$collision_only_marker" "proxy_shadow" 0
  require_metric_eq "$collision_only_marker" "proxy_both" 0
  require_metric_eq "$collision_only_marker" "proxy_shadow_only" 0
  require_metric_eq "$collision_only_marker" "compact_shadow_proxy" 0
  require_metric_eq "$collision_only_marker" "compact_shadow_normals_saved" 0
  require_metric_eq "$collision_only_marker" "compact_collision_proxy" "$(metric "fast_proxy" "$collision_only_marker")"
  require_metric_ge \
    "$collision_only_marker" \
    "compact_collision_normals_saved" \
    "$(metric "compact_collision_proxy" "$collision_only_marker")"
  require_metric_eq "$collision_only_marker" "mesh_visible" 0
  require_metric_eq "$collision_only_marker" "mesh_shadow_off" "$(metric "cpu_proxy" "$collision_only_marker")"
  require_metric_eq "$collision_only_marker" "mesh_shadow_double" 0
  require_metric_eq "$collision_only_marker" "mesh_shadow_only" 0
  require_metric_ge "$collision_only_marker" "fast_proxy" 1

  validate_common_marker "$compact_shadow_marker" "default" "conservative" "compact" "godot_proxy"
  require_metric_ge "$compact_shadow_marker" "gpu_frames" 1
  require_metric_ge "$compact_shadow_marker" "gpu_subchunks" 1
  require_metric_ge "$compact_shadow_marker" "gpu_faces" 1
  require_metric_ge "$compact_shadow_marker" "proxy_shadow" 1
  require_metric_ge "$compact_shadow_marker" "proxy_both" 1
  require_metric_ge "$compact_shadow_marker" "proxy_shadow_only" 1
  require_metric_ge "$compact_shadow_marker" "compact_shadow_proxy" 1
  require_metric_ge \
    "$compact_shadow_marker" \
    "compact_shadow_normals_saved" \
    "$(metric "compact_shadow_proxy" "$compact_shadow_marker")"
  require_metric_eq "$compact_shadow_marker" "compact_collision_proxy" 0
  require_metric_eq "$compact_shadow_marker" "compact_collision_normals_saved" 0
  require_metric_ge "$compact_shadow_marker" "fast_proxy" 1

  validate_pose_pair \
    "$OUT_DIR/cpu-arraymesh-atlas-depth-parity.png.txt" \
    "$OUT_DIR/gpu-terrain-atlas-depth-parity.png.txt" \
    "atlas_depth"

  validate_pose_pair \
    "$OUT_DIR/cpu-arraymesh-lighting-shadow-parity.png.txt" \
    "$OUT_DIR/gpu-terrain-lighting-shadow-parity.png.txt" \
    "lighting_shadow"

  validate_compact_shadow_pose_pair \
    "$OUT_DIR/gpu-terrain-lighting-shadow-parity.png.txt" \
    "$compact_lighting_shadow_marker" \
    "lighting_shadow"

  validate_pose_pair "$low_angle_cpu_marker" "$low_angle_gpu_marker" "lighting_low_angle"
  require_text_metric_eq "$low_angle_cpu_marker" "lighting_variant" "low_angle"
  require_text_metric_eq "$low_angle_gpu_marker" "lighting_variant" "low_angle"

  validate_compact_shadow_pose_pair \
    "$low_angle_gpu_marker" \
    "$compact_low_angle_marker" \
    "lighting_low_angle"
  require_text_metric_eq "$compact_low_angle_marker" "lighting_variant" "low_angle"

  validate_pose_pair "$texture_stand_cpu_marker" "$texture_stand_gpu_marker" "texture_stand"
  require_metric_eq "$texture_stand_cpu_marker" "texture_stand" 1
  require_metric_eq "$texture_stand_gpu_marker" "texture_stand" 1
}

validate_pose_pair() {
  cpu_marker="$1"
  gpu_marker="$2"
  pose="$3"

  validate_pose_pair_with_mesh "$cpu_marker" "$gpu_marker" "$pose" "full" "full"
}

validate_pose_pair_with_mesh() {
  cpu_marker="$1"
  gpu_marker="$2"
  pose="$3"
  expected_cpu_shadow_mesh="$4"
  expected_gpu_shadow_mesh="$5"

  validate_common_marker "$cpu_marker" "$pose" "conservative" "$expected_cpu_shadow_mesh" "arraymesh"
  validate_common_marker "$gpu_marker" "$pose" "conservative" "$expected_gpu_shadow_mesh" "godot_proxy"

  require_metric_absent "$cpu_marker" "gpu_frames"
  require_metric_absent "$cpu_marker" "gpu_subchunks"
  require_metric_eq "$cpu_marker" "fast_proxy" 0
  require_metric_eq "$cpu_marker" "compact_shadow_proxy" 0
  require_metric_eq "$cpu_marker" "compact_shadow_normals_saved" 0
  require_metric_eq "$cpu_marker" "compact_collision_proxy" 0
  require_metric_eq "$cpu_marker" "compact_collision_normals_saved" 0
  require_metric_ge "$gpu_marker" "gpu_frames" 1
  require_metric_ge "$gpu_marker" "gpu_subchunks" 1
  require_metric_ge "$gpu_marker" "gpu_faces" 1
  require_metric_ge "$gpu_marker" "fast_proxy" 1
  require_metric_eq "$gpu_marker" "compact_collision_proxy" 0
  require_metric_eq "$gpu_marker" "compact_collision_normals_saved" 0
  if [ "$expected_gpu_shadow_mesh" = "compact" ]; then
    require_metric_ge "$gpu_marker" "compact_shadow_proxy" 1
    require_metric_ge \
      "$gpu_marker" \
      "compact_shadow_normals_saved" \
      "$(metric "compact_shadow_proxy" "$gpu_marker")"
  else
    require_metric_eq "$gpu_marker" "compact_shadow_proxy" 0
    require_metric_eq "$gpu_marker" "compact_shadow_normals_saved" 0
  fi

  validate_visual_metric_pair "$cpu_marker" "$gpu_marker" "$pose"
}

validate_visual_metric_pair() {
  left_marker="$1"
  right_marker="$2"
  label="$3"

  left_luma="$(float_metric "avg_luma" "$left_marker")"
  right_luma="$(float_metric "avg_luma" "$right_marker")"
  test -n "$left_luma" || fail "missing left avg_luma for $label"
  test -n "$right_luma" || fail "missing right avg_luma for $label"
  require_float_delta_le "$left_luma" "$right_luma" "$MAX_AVG_LUMA_DELTA" "$label avg_luma"

  left_luma_range="$(float_metric "terrain_luma_range" "$left_marker")"
  right_luma_range="$(float_metric "terrain_luma_range" "$right_marker")"
  test -n "$left_luma_range" || fail "missing left terrain_luma_range for $label"
  test -n "$right_luma_range" || fail "missing right terrain_luma_range for $label"
  require_float_delta_le \
    "$left_luma_range" \
    "$right_luma_range" \
    "$MAX_TERRAIN_LUMA_RANGE_DELTA" \
    "$label terrain_luma_range"

  left_terrain_samples="$(metric "terrain_samples" "$left_marker")"
  right_terrain_samples="$(metric "terrain_samples" "$right_marker")"
  require_int_delta_percent_le \
    "$left_terrain_samples" \
    "$right_terrain_samples" \
    "$MAX_TERRAIN_SAMPLE_DELTA_PERCENT" \
    "$MIN_TERRAIN_SAMPLE_DELTA" \
    "$label terrain_samples"

  left_terrain_color_buckets="$(metric "terrain_color_buckets" "$left_marker")"
  right_terrain_color_buckets="$(metric "terrain_color_buckets" "$right_marker")"
  require_int_delta_percent_le \
    "$left_terrain_color_buckets" \
    "$right_terrain_color_buckets" \
    "$MAX_TERRAIN_COLOR_BUCKET_DELTA_PERCENT" \
    "$MIN_TERRAIN_COLOR_BUCKET_DELTA" \
    "$label terrain_color_buckets"

  left_terrain_chroma_samples="$(metric "terrain_chroma_samples" "$left_marker")"
  right_terrain_chroma_samples="$(metric "terrain_chroma_samples" "$right_marker")"
  require_int_delta_percent_le \
    "$left_terrain_chroma_samples" \
    "$right_terrain_chroma_samples" \
    "$MAX_TERRAIN_SAMPLE_DELTA_PERCENT" \
    "$MIN_TERRAIN_SAMPLE_DELTA" \
    "$label terrain_chroma_samples"
}

abs_float_delta_value() {
  left="$1"
  right="$2"
  awk -v left="$left" -v right="$right" '
    BEGIN {
      delta = left - right
      if (delta < 0) {
        delta = -delta
      }
      printf("%.4f", delta)
    }
  '
}

abs_int_delta_value() {
  left="$1"
  right="$2"
  delta=$((left - right))
  if [ "$delta" -lt 0 ]; then
    delta=$((-delta))
  fi
  echo "$delta"
}

value_or_na() {
  value="$1"
  if [ -n "$value" ]; then
    echo "$value"
  else
    echo "n/a"
  fi
}

append_case_summary() {
  append_case_summary_path="$1"
  append_case_name="$2"
  append_case_marker_path="$3"

  smoke_err="$(metric "smoke_err" "$append_case_marker_path")"
  terrain_samples="$(metric "terrain_samples" "$append_case_marker_path")"
  terrain_color_buckets="$(metric "terrain_color_buckets" "$append_case_marker_path")"
  terrain_luma_range="$(float_metric "terrain_luma_range" "$append_case_marker_path")"
  gpu_frames="$(value_or_na "$(metric "gpu_frames" "$append_case_marker_path")")"
  gpu_subchunks="$(value_or_na "$(metric "gpu_subchunks" "$append_case_marker_path")")"
  shadow_path="$(text_metric "shadow_path" "$append_case_marker_path")"
  shadow_mode="$(text_metric "shadow_mode" "$append_case_marker_path")"
  shadow_mesh="$(text_metric "shadow_mesh" "$append_case_marker_path")"
  native_shadow_requested="$(value_or_na "$(metric "native_shadow_requested" "$append_case_marker_path")")"
  native_shadow_active="$(value_or_na "$(metric "native_shadow_active" "$append_case_marker_path")")"
  native_shadow_fallback="$(value_or_na "$(metric "native_shadow_fallback" "$append_case_marker_path")")"

  printf '%s\n' \
    "case=$append_case_name marker=$append_case_marker_path smoke_err=$smoke_err terrain_samples=$terrain_samples terrain_color_buckets=$terrain_color_buckets terrain_luma_range=$terrain_luma_range gpu_frames=$gpu_frames gpu_subchunks=$gpu_subchunks shadow_path=$shadow_path shadow_mode=$shadow_mode shadow_mesh=$shadow_mesh native_shadow_requested=$native_shadow_requested native_shadow_active=$native_shadow_active native_shadow_fallback=$native_shadow_fallback" \
    >> "$append_case_summary_path"
}

append_visual_pair_summary() {
  append_pair_summary_path="$1"
  append_pair_name="$2"
  append_pair_left_marker="$3"
  append_pair_right_marker="$4"
  append_pair_left_name="$5"
  append_pair_right_name="$6"

  left_luma="$(float_metric "avg_luma" "$append_pair_left_marker")"
  right_luma="$(float_metric "avg_luma" "$append_pair_right_marker")"
  luma_delta="$(abs_float_delta_value "$left_luma" "$right_luma")"
  left_luma_range="$(float_metric "terrain_luma_range" "$append_pair_left_marker")"
  right_luma_range="$(float_metric "terrain_luma_range" "$append_pair_right_marker")"
  luma_range_delta="$(abs_float_delta_value "$left_luma_range" "$right_luma_range")"
  left_terrain_samples="$(metric "terrain_samples" "$append_pair_left_marker")"
  right_terrain_samples="$(metric "terrain_samples" "$append_pair_right_marker")"
  terrain_samples_delta="$(abs_int_delta_value "$left_terrain_samples" "$right_terrain_samples")"
  left_terrain_color_buckets="$(metric "terrain_color_buckets" "$append_pair_left_marker")"
  right_terrain_color_buckets="$(metric "terrain_color_buckets" "$append_pair_right_marker")"
  terrain_color_buckets_delta="$(abs_int_delta_value "$left_terrain_color_buckets" "$right_terrain_color_buckets")"
  left_terrain_chroma_samples="$(metric "terrain_chroma_samples" "$append_pair_left_marker")"
  right_terrain_chroma_samples="$(metric "terrain_chroma_samples" "$append_pair_right_marker")"
  terrain_chroma_samples_delta="$(abs_int_delta_value "$left_terrain_chroma_samples" "$right_terrain_chroma_samples")"

  printf '%s\n' \
    "pair=$append_pair_name left=$append_pair_left_name right=$append_pair_right_name avg_luma=$left_luma/$right_luma delta=$luma_delta terrain_luma_range=$left_luma_range/$right_luma_range delta=$luma_range_delta terrain_samples=$left_terrain_samples/$right_terrain_samples delta=$terrain_samples_delta terrain_color_buckets=$left_terrain_color_buckets/$right_terrain_color_buckets delta=$terrain_color_buckets_delta terrain_chroma_samples=$left_terrain_chroma_samples/$right_terrain_chroma_samples delta=$terrain_chroma_samples_delta" \
    >> "$append_pair_summary_path"
}

write_parity_summary() {
  parity_summary_path="$OUT_DIR/parity-summary.txt"
  parity_summary_tmp_path="$parity_summary_path.tmp"
  native_fallback_marker="$OUT_DIR/gpu-terrain-native-shadow-fallback-parity.png.txt"
  case_count=16
  if [ -s "$native_fallback_marker" ]; then
    case_count=17
  fi

  {
    echo "# GPU Terrain Parity Summary"
    echo "generated_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    echo "out_dir=$OUT_DIR"
    echo "validate_only=$VALIDATE_ONLY"
    echo "case_count=$case_count"
    echo "thresholds max_avg_luma_delta=$MAX_AVG_LUMA_DELTA max_terrain_luma_range_delta=$MAX_TERRAIN_LUMA_RANGE_DELTA max_terrain_sample_delta_percent=$MAX_TERRAIN_SAMPLE_DELTA_PERCENT min_terrain_sample_delta=$MIN_TERRAIN_SAMPLE_DELTA max_terrain_color_bucket_delta_percent=$MAX_TERRAIN_COLOR_BUCKET_DELTA_PERCENT min_terrain_color_bucket_delta=$MIN_TERRAIN_COLOR_BUCKET_DELTA"
    echo
  } > "$parity_summary_tmp_path"

  append_case_summary "$parity_summary_tmp_path" "cpu-arraymesh-parity" "$OUT_DIR/cpu-arraymesh-parity.png.txt"
  append_case_summary "$parity_summary_tmp_path" "gpu-terrain-parity" "$OUT_DIR/gpu-terrain-parity.png.txt"
  append_case_summary "$parity_summary_tmp_path" "gpu-terrain-radius1-parity" "$OUT_DIR/gpu-terrain-radius1-parity.png.txt"
  append_case_summary "$parity_summary_tmp_path" "gpu-terrain-shadow-disabled-parity" "$OUT_DIR/gpu-terrain-shadow-disabled-parity.png.txt"
  append_case_summary "$parity_summary_tmp_path" "gpu-terrain-collision-only-parity" "$OUT_DIR/gpu-terrain-collision-only-parity.png.txt"
  append_case_summary "$parity_summary_tmp_path" "gpu-terrain-compact-shadow-parity" "$OUT_DIR/gpu-terrain-compact-shadow-parity.png.txt"
  if [ -s "$native_fallback_marker" ]; then
    append_case_summary "$parity_summary_tmp_path" "gpu-terrain-native-shadow-fallback-parity" "$native_fallback_marker"
  fi
  append_case_summary "$parity_summary_tmp_path" "cpu-arraymesh-atlas-depth-parity" "$OUT_DIR/cpu-arraymesh-atlas-depth-parity.png.txt"
  append_case_summary "$parity_summary_tmp_path" "gpu-terrain-atlas-depth-parity" "$OUT_DIR/gpu-terrain-atlas-depth-parity.png.txt"
  append_case_summary "$parity_summary_tmp_path" "cpu-arraymesh-lighting-shadow-parity" "$OUT_DIR/cpu-arraymesh-lighting-shadow-parity.png.txt"
  append_case_summary "$parity_summary_tmp_path" "gpu-terrain-lighting-shadow-parity" "$OUT_DIR/gpu-terrain-lighting-shadow-parity.png.txt"
  append_case_summary "$parity_summary_tmp_path" "gpu-terrain-compact-lighting-shadow-parity" "$OUT_DIR/gpu-terrain-compact-lighting-shadow-parity.png.txt"
  append_case_summary "$parity_summary_tmp_path" "cpu-arraymesh-lighting-low-angle-parity" "$OUT_DIR/cpu-arraymesh-lighting-low-angle-parity.png.txt"
  append_case_summary "$parity_summary_tmp_path" "gpu-terrain-lighting-low-angle-parity" "$OUT_DIR/gpu-terrain-lighting-low-angle-parity.png.txt"
  append_case_summary "$parity_summary_tmp_path" "gpu-terrain-compact-lighting-low-angle-parity" "$OUT_DIR/gpu-terrain-compact-lighting-low-angle-parity.png.txt"
  append_case_summary "$parity_summary_tmp_path" "cpu-arraymesh-texture-stand-parity" "$OUT_DIR/cpu-arraymesh-texture-stand-parity.png.txt"
  append_case_summary "$parity_summary_tmp_path" "gpu-terrain-texture-stand-parity" "$OUT_DIR/gpu-terrain-texture-stand-parity.png.txt"

  echo >> "$parity_summary_tmp_path"
  append_visual_pair_summary "$parity_summary_tmp_path" "default" "$OUT_DIR/cpu-arraymesh-parity.png.txt" "$OUT_DIR/gpu-terrain-parity.png.txt" "cpu-arraymesh" "gpu-terrain"
  if [ -s "$native_fallback_marker" ]; then
    append_visual_pair_summary "$parity_summary_tmp_path" "native_shadow_fallback" "$OUT_DIR/gpu-terrain-parity.png.txt" "$native_fallback_marker" "gpu-terrain" "gpu-native-shadow-fallback"
  fi
  append_visual_pair_summary "$parity_summary_tmp_path" "atlas_depth" "$OUT_DIR/cpu-arraymesh-atlas-depth-parity.png.txt" "$OUT_DIR/gpu-terrain-atlas-depth-parity.png.txt" "cpu-arraymesh" "gpu-terrain"
  append_visual_pair_summary "$parity_summary_tmp_path" "lighting_shadow" "$OUT_DIR/cpu-arraymesh-lighting-shadow-parity.png.txt" "$OUT_DIR/gpu-terrain-lighting-shadow-parity.png.txt" "cpu-arraymesh" "gpu-terrain"
  append_visual_pair_summary "$parity_summary_tmp_path" "lighting_shadow_compact" "$OUT_DIR/gpu-terrain-lighting-shadow-parity.png.txt" "$OUT_DIR/gpu-terrain-compact-lighting-shadow-parity.png.txt" "gpu-full-shadow" "gpu-compact-shadow"
  append_visual_pair_summary "$parity_summary_tmp_path" "lighting_low_angle" "$OUT_DIR/cpu-arraymesh-lighting-low-angle-parity.png.txt" "$OUT_DIR/gpu-terrain-lighting-low-angle-parity.png.txt" "cpu-arraymesh" "gpu-terrain"
  append_visual_pair_summary "$parity_summary_tmp_path" "lighting_low_angle_compact" "$OUT_DIR/gpu-terrain-lighting-low-angle-parity.png.txt" "$OUT_DIR/gpu-terrain-compact-lighting-low-angle-parity.png.txt" "gpu-full-shadow" "gpu-compact-shadow"
  append_visual_pair_summary "$parity_summary_tmp_path" "texture_stand" "$OUT_DIR/cpu-arraymesh-texture-stand-parity.png.txt" "$OUT_DIR/gpu-terrain-texture-stand-parity.png.txt" "cpu-arraymesh" "gpu-terrain"

  mv "$parity_summary_tmp_path" "$parity_summary_path"
  echo "Terrain parity summary written: $parity_summary_path"
}

validate_compact_shadow_pose_pair() {
  full_marker="$1"
  compact_marker="$2"
  pose="$3"

  validate_common_marker "$full_marker" "$pose" "conservative" "full" "godot_proxy"
  validate_common_marker "$compact_marker" "$pose" "conservative" "compact" "godot_proxy"

  require_metric_ge "$full_marker" "gpu_frames" 1
  require_metric_ge "$full_marker" "gpu_subchunks" 1
  require_metric_ge "$full_marker" "gpu_faces" 1
  require_metric_ge "$full_marker" "fast_proxy" 1
  require_metric_eq "$full_marker" "compact_shadow_proxy" 0
  require_metric_eq "$full_marker" "compact_shadow_normals_saved" 0
  require_metric_eq "$full_marker" "compact_collision_proxy" 0
  require_metric_eq "$full_marker" "compact_collision_normals_saved" 0

  require_metric_ge "$compact_marker" "gpu_frames" 1
  require_metric_ge "$compact_marker" "gpu_subchunks" 1
  require_metric_ge "$compact_marker" "gpu_faces" 1
  require_metric_ge "$compact_marker" "fast_proxy" 1
  require_metric_eq "$compact_marker" "compact_collision_proxy" 0
  require_metric_eq "$compact_marker" "compact_collision_normals_saved" 0
  require_metric_ge "$compact_marker" "proxy_shadow" 1
  require_metric_ge "$compact_marker" "proxy_both" 1
  require_metric_ge "$compact_marker" "proxy_shadow_only" 1
  require_metric_ge "$compact_marker" "compact_shadow_proxy" 1
  require_metric_ge \
    "$compact_marker" \
    "compact_shadow_normals_saved" \
    "$(metric "compact_shadow_proxy" "$compact_marker")"

  validate_visual_metric_pair "$full_marker" "$compact_marker" "$pose compact"
}

if [ "$VALIDATE_ONLY" != "1" ]; then
  prepare_godot_rust_ext_profile "$ROOT_DIR"
  run_case "cpu-arraymesh-parity" "0" "" "default" "conservative" "full"
  run_case "gpu-terrain-parity" "1" "" "default" "conservative" ""
  run_case "gpu-terrain-radius1-parity" "1" "1" "default" "conservative" "full"
  run_case "gpu-terrain-shadow-disabled-parity" "1" "0" "default" "conservative" "full"
  run_case "gpu-terrain-collision-only-parity" "1" "" "default" "collision_only" "full"
  run_case "gpu-terrain-compact-shadow-parity" "1" "" "default" "conservative" "compact"
  run_case "gpu-terrain-native-shadow-fallback-parity" "1" "" "default" "conservative" "" "1"
  run_case "cpu-arraymesh-atlas-depth-parity" "0" "" "atlas_depth" "conservative" "full"
  run_case "gpu-terrain-atlas-depth-parity" "1" "" "atlas_depth" "conservative" "full"
  run_case "cpu-arraymesh-lighting-shadow-parity" "0" "" "lighting_shadow" "conservative" "full"
  run_case "gpu-terrain-lighting-shadow-parity" "1" "" "lighting_shadow" "conservative" "full"
  run_case "gpu-terrain-compact-lighting-shadow-parity" "1" "" "lighting_shadow" "conservative" "compact"
  run_case "cpu-arraymesh-lighting-low-angle-parity" "0" "" "lighting_low_angle" "conservative" "full"
  run_case "gpu-terrain-lighting-low-angle-parity" "1" "" "lighting_low_angle" "conservative" "full"
  run_case "gpu-terrain-compact-lighting-low-angle-parity" "1" "" "lighting_low_angle" "conservative" "compact"
  run_case "cpu-arraymesh-texture-stand-parity" "0" "" "texture_stand" "conservative" "full"
  run_case "gpu-terrain-texture-stand-parity" "1" "" "texture_stand" "conservative" "full"
fi

validate_parity_markers
write_parity_summary

echo "Terrain parity smoke passed: $OUT_DIR"
