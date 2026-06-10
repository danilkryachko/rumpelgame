#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
CAPTURE="${RUMPELMC_COMPACT_PROXY_BENCH_CAPTURE:-0}"
if [ "$CAPTURE" = "1" ]; then
  OUT_DIR="${1:-"$ROOT_DIR/logs/gpu_terrain_visual_smoke/compact_proxy_benchmark"}"
else
  OUT_DIR="${1:-"$ROOT_DIR/logs/gpu_terrain_visual_smoke/parity"}"
fi
GODOT_BIN="${GODOT_BIN:-/opt/homebrew/bin/godot}"
TIMEOUT_BIN="${TIMEOUT_BIN:-/opt/homebrew/bin/timeout}"
GODOT_TIMEOUT_SEC="${GODOT_TIMEOUT_SEC:-90}"
GODOT_QUIT_AFTER_FRAMES="${GODOT_QUIT_AFTER_FRAMES:-8000}"
SMOKE_DELAY_SEC="${SMOKE_DELAY_SEC:-3.0}"
SMOKE_POSE="${SMOKE_POSE:-lighting_shadow}"
COLLISION_SMOKE_POSE="${RUMPELMC_COMPACT_PROXY_BENCH_COLLISION_POSE:-default}"
SHADOW_DISABLED_SMOKE_POSE="${RUMPELMC_COMPACT_PROXY_BENCH_SHADOW_DISABLED_POSE:-default}"
FULL_MARKER="${RUMPELMC_COMPACT_PROXY_BENCH_FULL_MARKER:-}"
COMPACT_MARKER="${RUMPELMC_COMPACT_PROXY_BENCH_COMPACT_MARKER:-}"
COLLISION_MARKER="${RUMPELMC_COMPACT_PROXY_BENCH_COLLISION_MARKER:-}"
SHADOW_DISABLED_MARKER="${RUMPELMC_COMPACT_PROXY_BENCH_SHADOW_DISABLED_MARKER:-}"

mkdir -p "$OUT_DIR"

fail() {
  echo "gpu_terrain_compact_proxy_benchmark: $*" >&2
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

mesh_avg_ms() {
  marker_path="$1"
  sed -n 's/.* mesh [0-9][0-9]*\.[0-9][0-9]*\/\([0-9][0-9]*\.[0-9][0-9]*\)\/[0-9][0-9]*\.[0-9][0-9]*ms .*/\1/p' "$marker_path" | sed -n '1p'
}

mesh_max_ms() {
  marker_path="$1"
  sed -n 's/.* mesh [0-9][0-9]*\.[0-9][0-9]*\/[0-9][0-9]*\.[0-9][0-9]*\/\([0-9][0-9]*\.[0-9][0-9]*\)ms .*/\1/p' "$marker_path" | sed -n '1p'
}

collision_avg_ms() {
  marker_path="$1"
  sed -n 's/.* coll [0-9][0-9]*\.[0-9][0-9]*\/\([0-9][0-9]*\.[0-9][0-9]*\)\/[0-9][0-9]*\.[0-9][0-9]*ms .*/\1/p' "$marker_path" | sed -n '1p'
}

normal_total() {
  marker_path="$1"
  sed -n 's/.* normals last=[0-9][0-9]* total=\([0-9][0-9]*\).*/\1/p' "$marker_path" | sed -n '1p'
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

validate_shadow_marker() {
  marker_path="$1"
  expected_shadow_mesh="$2"
  screenshot_path="${marker_path%.txt}"

  test -s "$screenshot_path" || fail "missing screenshot $screenshot_path"
  test -s "$marker_path" || fail "missing marker $marker_path"
  grep -q "Visual smoke screenshot saved" "$marker_path" || fail "missing smoke summary in $marker_path"
  grep -q "pose=\"$SMOKE_POSE\"" "$marker_path" || fail "unexpected pose in $marker_path"
  grep -q "shadow_path=godot_proxy" "$marker_path" || fail "unexpected shadow path in $marker_path"
  grep -q "shadow_mode=conservative" "$marker_path" || fail "unexpected shadow mode in $marker_path"
  grep -q "shadow_mesh=$expected_shadow_mesh" "$marker_path" || fail "unexpected shadow mesh in $marker_path"
  grep -q "current_chunk=\"0,0\"" "$marker_path" || fail "unexpected current chunk in $marker_path"
  grep -q "smoke_err=0" "$marker_path" || fail "smoke_err is not 0 in $marker_path"
  if [ "$CAPTURE" = "1" ]; then
    require_godot_rust_ext_marker_profile "$marker_path"
  fi
  require_metric_ge "$marker_path" "terrain_samples" 1
  require_metric_ge "$marker_path" "gpu_frames" 1
  require_metric_ge "$marker_path" "gpu_subchunks" 1
  require_metric_ge "$marker_path" "gpu_faces" 1
  require_metric_ge "$marker_path" "proxy_coll" 1
  require_metric_ge "$marker_path" "proxy_shadow" 1
  require_metric_ge "$marker_path" "proxy_both" 1
  require_metric_ge "$marker_path" "fast_proxy" 1
  require_metric_eq "$marker_path" "compact_collision_proxy" 0
  require_metric_eq "$marker_path" "compact_collision_normals_saved" 0
}

validate_collision_marker() {
  marker_path="$1"
  screenshot_path="${marker_path%.txt}"

  test -s "$screenshot_path" || fail "missing screenshot $screenshot_path"
  test -s "$marker_path" || fail "missing marker $marker_path"
  grep -q "Visual smoke screenshot saved" "$marker_path" || fail "missing smoke summary in $marker_path"
  grep -q "pose=\"$COLLISION_SMOKE_POSE\"" "$marker_path" || fail "unexpected pose in $marker_path"
  grep -q "shadow_path=diagnostic_no_shadow_proxy" "$marker_path" || fail "unexpected shadow path in $marker_path"
  grep -q "shadow_mode=collision_only" "$marker_path" || fail "unexpected shadow mode in $marker_path"
  grep -q "shadow_mesh=full" "$marker_path" || fail "unexpected shadow mesh in $marker_path"
  grep -q "current_chunk=\"0,0\"" "$marker_path" || fail "unexpected current chunk in $marker_path"
  grep -q "smoke_err=0" "$marker_path" || fail "smoke_err is not 0 in $marker_path"
  if [ "$CAPTURE" = "1" ]; then
    require_godot_rust_ext_marker_profile "$marker_path"
  fi
  require_metric_ge "$marker_path" "terrain_samples" 1
  require_metric_ge "$marker_path" "gpu_frames" 1
  require_metric_ge "$marker_path" "gpu_subchunks" 1
  require_metric_ge "$marker_path" "gpu_faces" 1
  require_metric_ge "$marker_path" "proxy_coll" 1
  require_metric_eq "$marker_path" "proxy_shadow" 0
  require_metric_eq "$marker_path" "proxy_both" 0
  require_metric_eq "$marker_path" "proxy_shadow_only" 0
  require_metric_eq "$marker_path" "compact_shadow_proxy" 0
  require_metric_eq "$marker_path" "compact_shadow_normals_saved" 0
  require_metric_ge "$marker_path" "fast_proxy" 1
  require_metric_eq "$marker_path" "compact_collision_proxy" "$(metric "fast_proxy" "$marker_path")"
  require_metric_ge \
    "$marker_path" \
    "compact_collision_normals_saved" \
    "$(metric "compact_collision_proxy" "$marker_path")"
}

validate_shadow_disabled_marker() {
  marker_path="$1"
  screenshot_path="${marker_path%.txt}"

  test -s "$screenshot_path" || fail "missing screenshot $screenshot_path"
  test -s "$marker_path" || fail "missing marker $marker_path"
  grep -q "Visual smoke screenshot saved" "$marker_path" || fail "missing smoke summary in $marker_path"
  grep -q "pose=\"$SHADOW_DISABLED_SMOKE_POSE\"" "$marker_path" || fail "unexpected pose in $marker_path"
  grep -q "shadow_path=scene_shadows_disabled" "$marker_path" || fail "unexpected shadow path in $marker_path"
  grep -q "shadow_mode=conservative" "$marker_path" || fail "unexpected shadow mode in $marker_path"
  grep -q "shadow_mesh=full" "$marker_path" || fail "unexpected shadow mesh in $marker_path"
  grep -q "current_chunk=\"0,0\"" "$marker_path" || fail "unexpected current chunk in $marker_path"
  grep -q "smoke_err=0" "$marker_path" || fail "smoke_err is not 0 in $marker_path"
  if [ "$CAPTURE" = "1" ]; then
    require_godot_rust_ext_marker_profile "$marker_path"
  fi
  require_metric_ge "$marker_path" "terrain_samples" 1
  require_metric_ge "$marker_path" "gpu_frames" 1
  require_metric_ge "$marker_path" "gpu_subchunks" 1
  require_metric_ge "$marker_path" "gpu_faces" 1
  require_metric_ge "$marker_path" "proxy_coll" 1
  require_metric_eq "$marker_path" "proxy_shadow" 0
  require_metric_eq "$marker_path" "proxy_both" 0
  require_metric_eq "$marker_path" "proxy_shadow_only" 0
  require_metric_eq "$marker_path" "compact_shadow_proxy" 0
  require_metric_eq "$marker_path" "compact_shadow_normals_saved" 0
  require_metric_ge "$marker_path" "fast_proxy" 1
  require_metric_eq "$marker_path" "compact_collision_proxy" "$(metric "fast_proxy" "$marker_path")"
  require_metric_ge \
    "$marker_path" \
    "compact_collision_normals_saved" \
    "$(metric "compact_collision_proxy" "$marker_path")"
}

run_shadow_case() {
  shadow_mesh="$1"
  screenshot_path="$OUT_DIR/gpu-terrain-$shadow_mesh.png"
  marker_path="$screenshot_path.txt"

  rm -f "$screenshot_path" "$marker_path"

  echo "==> GPU terrain compact proxy benchmark: shadow_mesh=$shadow_mesh"
  (
    cd "$ROOT_DIR"
    "$TIMEOUT_BIN" "$GODOT_TIMEOUT_SEC" /usr/bin/env \
      RUMPELMC_GPU_TERRAIN_RENDER=1 \
      RUMPELMC_GPU_TERRAIN_SHADOW_PROXY_CHUNK_DISTANCE= \
      RUMPELMC_GPU_TERRAIN_SHADOW_PROXY_MODE=conservative \
      RUMPELMC_GPU_TERRAIN_SHADOW_PROXY_MESH="$shadow_mesh" \
      RUMPELMC_VISUAL_SMOKE_POSE="$SMOKE_POSE" \
      RUMPELMC_VISUAL_SMOKE_PATH="$screenshot_path" \
      RUMPELMC_VISUAL_SMOKE_DELAY_SEC="$SMOKE_DELAY_SEC" \
      RUMPELMC_VISUAL_SMOKE_HIDE_HUD=1 \
      RUMPELMC_VISUAL_SMOKE_DISABLE_PLAYER_INPUT=1 \
      "$GODOT_BIN" --path client --quit-after "$GODOT_QUIT_AFTER_FRAMES"
  )

  validate_shadow_marker "$marker_path" "$shadow_mesh"
  if [ "$shadow_mesh" = "full" ]; then
    require_metric_eq "$marker_path" "compact_shadow_proxy" 0
    require_metric_eq "$marker_path" "compact_shadow_normals_saved" 0
  else
    require_metric_ge "$marker_path" "compact_shadow_proxy" 1
    require_metric_ge "$marker_path" "compact_shadow_normals_saved" "$(metric "compact_shadow_proxy" "$marker_path")"
  fi
}

run_collision_case() {
  screenshot_path="$OUT_DIR/gpu-terrain-collision-only.png"
  marker_path="$screenshot_path.txt"

  rm -f "$screenshot_path" "$marker_path"

  echo "==> GPU terrain compact proxy benchmark: shadow_mode=collision_only"
  (
    cd "$ROOT_DIR"
    "$TIMEOUT_BIN" "$GODOT_TIMEOUT_SEC" /usr/bin/env \
      RUMPELMC_GPU_TERRAIN_RENDER=1 \
      RUMPELMC_GPU_TERRAIN_SHADOW_PROXY_CHUNK_DISTANCE= \
      RUMPELMC_GPU_TERRAIN_SHADOW_PROXY_MODE=collision_only \
      RUMPELMC_GPU_TERRAIN_SHADOW_PROXY_MESH=full \
      RUMPELMC_VISUAL_SMOKE_POSE="$COLLISION_SMOKE_POSE" \
      RUMPELMC_VISUAL_SMOKE_PATH="$screenshot_path" \
      RUMPELMC_VISUAL_SMOKE_DELAY_SEC="$SMOKE_DELAY_SEC" \
      RUMPELMC_VISUAL_SMOKE_HIDE_HUD=1 \
      RUMPELMC_VISUAL_SMOKE_DISABLE_PLAYER_INPUT=1 \
      "$GODOT_BIN" --path client --quit-after "$GODOT_QUIT_AFTER_FRAMES"
  )

  validate_collision_marker "$marker_path"
}

run_shadow_disabled_case() {
  screenshot_path="$OUT_DIR/gpu-terrain-shadow-disabled.png"
  marker_path="$screenshot_path.txt"

  rm -f "$screenshot_path" "$marker_path"

  echo "==> GPU terrain compact proxy benchmark: shadow_radius=0"
  (
    cd "$ROOT_DIR"
    "$TIMEOUT_BIN" "$GODOT_TIMEOUT_SEC" /usr/bin/env \
      RUMPELMC_GPU_TERRAIN_RENDER=1 \
      RUMPELMC_GPU_TERRAIN_SHADOW_PROXY_CHUNK_DISTANCE=0 \
      RUMPELMC_GPU_TERRAIN_SHADOW_PROXY_MODE=conservative \
      RUMPELMC_GPU_TERRAIN_SHADOW_PROXY_MESH=full \
      RUMPELMC_VISUAL_SMOKE_POSE="$SHADOW_DISABLED_SMOKE_POSE" \
      RUMPELMC_VISUAL_SMOKE_PATH="$screenshot_path" \
      RUMPELMC_VISUAL_SMOKE_DELAY_SEC="$SMOKE_DELAY_SEC" \
      RUMPELMC_VISUAL_SMOKE_HIDE_HUD=1 \
      RUMPELMC_VISUAL_SMOKE_DISABLE_PLAYER_INPUT=1 \
      "$GODOT_BIN" --path client --quit-after "$GODOT_QUIT_AFTER_FRAMES"
  )

  validate_shadow_disabled_marker "$marker_path"
}

print_row() {
  label="$1"
  marker_path="$2"
  printf '%-14s cpu_proxy=%s shadow_only=%s compact_shadow_proxy=%s shadow_normals_saved=%s compact_collision_proxy=%s collision_normals_saved=%s normals_total=%s mesh_avg_ms=%s mesh_max_ms=%s coll_avg_ms=%s gpu_frames=%s avg_luma=%s terrain_samples=%s\n' \
    "$label" \
    "$(metric "cpu_proxy" "$marker_path")" \
    "$(metric "proxy_shadow_only" "$marker_path")" \
    "$(metric "compact_shadow_proxy" "$marker_path")" \
    "$(metric "compact_shadow_normals_saved" "$marker_path")" \
    "$(metric "compact_collision_proxy" "$marker_path")" \
    "$(metric "compact_collision_normals_saved" "$marker_path")" \
    "$(normal_total "$marker_path")" \
    "$(mesh_avg_ms "$marker_path")" \
    "$(mesh_max_ms "$marker_path")" \
    "$(collision_avg_ms "$marker_path")" \
    "$(metric "gpu_frames" "$marker_path")" \
    "$(float_metric "avg_luma" "$marker_path")" \
    "$(metric "terrain_samples" "$marker_path")"
}

if [ "$CAPTURE" = "1" ]; then
  prepare_godot_rust_ext_profile "$ROOT_DIR"
  run_shadow_case full
  run_shadow_case compact
  run_shadow_disabled_case
  run_collision_case
  full_marker="$OUT_DIR/gpu-terrain-full.png.txt"
  compact_marker="$OUT_DIR/gpu-terrain-compact.png.txt"
  shadow_disabled_marker="$OUT_DIR/gpu-terrain-shadow-disabled.png.txt"
  collision_marker="$OUT_DIR/gpu-terrain-collision-only.png.txt"
else
  if [ -z "$FULL_MARKER" ]; then
    FULL_MARKER="$OUT_DIR/gpu-terrain-lighting-shadow-parity.png.txt"
  fi
  if [ -z "$COMPACT_MARKER" ]; then
    COMPACT_MARKER="$OUT_DIR/gpu-terrain-compact-lighting-shadow-parity.png.txt"
  fi
  if [ -z "$COLLISION_MARKER" ]; then
    COLLISION_MARKER="$OUT_DIR/gpu-terrain-collision-only-parity.png.txt"
  fi
  if [ -z "$SHADOW_DISABLED_MARKER" ]; then
    SHADOW_DISABLED_MARKER="$OUT_DIR/gpu-terrain-shadow-disabled-parity.png.txt"
  fi
  full_marker="$FULL_MARKER"
  compact_marker="$COMPACT_MARKER"
  shadow_disabled_marker="$SHADOW_DISABLED_MARKER"
  collision_marker="$COLLISION_MARKER"
  validate_shadow_marker "$full_marker" full
  validate_shadow_marker "$compact_marker" compact
  validate_shadow_disabled_marker "$shadow_disabled_marker"
  validate_collision_marker "$collision_marker"
  require_metric_eq "$full_marker" "compact_shadow_proxy" 0
  require_metric_eq "$full_marker" "compact_shadow_normals_saved" 0
  require_metric_ge "$compact_marker" "compact_shadow_proxy" 1
  require_metric_ge "$compact_marker" "compact_shadow_normals_saved" "$(metric "compact_shadow_proxy" "$compact_marker")"
fi

echo
echo "Compact proxy benchmark summary:"
print_row full "$full_marker"
print_row compact "$compact_marker"
print_row shadow_disabled "$shadow_disabled_marker"
print_row collision_only "$collision_marker"

full_normals="$(normal_total "$full_marker")"
compact_normals="$(normal_total "$compact_marker")"
if [ -n "$full_normals" ] && [ -n "$compact_normals" ] && [ "$full_normals" -gt 0 ]; then
  awk -v full="$full_normals" -v compact="$compact_normals" '
    BEGIN {
      saved = full - compact
      pct = saved * 100.0 / full
      printf("shadow_normal_total_delta=%d shadow_normal_total_reduction=%.1f%%\n", saved, pct)
    }
  '
fi

print_collision_payload_reduction() {
  label="$1"
  marker_path="$2"
  collision_normals="$(normal_total "$marker_path")"
  collision_normals_saved="$(metric "compact_collision_normals_saved" "$marker_path")"
  if [ -n "$collision_normals" ] && [ -n "$collision_normals_saved" ]; then
    awk -v label="$label" -v normals="$collision_normals" -v saved="$collision_normals_saved" '
    BEGIN {
      baseline = normals + saved
      pct = 0.0
      if (baseline > 0) {
        pct = saved * 100.0 / baseline
      }
      printf("%s_collision_normal_payload_saved=%d %s_collision_normal_payload_reduction=%.1f%%\n", label, saved, label, pct)
    }
  '
  fi
}

print_collision_payload_reduction shadow_disabled "$shadow_disabled_marker"
print_collision_payload_reduction collision_only "$collision_marker"
