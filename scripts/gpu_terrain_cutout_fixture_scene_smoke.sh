#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/gpu_transparent_cutout_fixture_scene_smoke_current"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

GODOT_BIN="${GODOT_BIN:-/opt/homebrew/bin/godot}"
TIMEOUT_BIN="${TIMEOUT_BIN:-/opt/homebrew/bin/timeout}"
GODOT_TIMEOUT_SEC="${GODOT_TIMEOUT_SEC:-180}"
GODOT_QUIT_AFTER_FRAMES="${GODOT_QUIT_AFTER_FRAMES:-16000}"
SMOKE_DELAY_SEC="${SMOKE_DELAY_SEC:-6.0}"
FRAME_SAMPLE_SEC="${RUMPELMC_CUTOUT_FIXTURE_SCENE_FRAME_SAMPLE_SEC:-5.0}"
ROCKSDB_PATH="$OUT_DIR/rocksdb"
SUMMARY_PATH="$OUT_DIR/transparent-cutout-fixture-scene-smoke-summary.txt"
CLEANUP_SERVER_ON_EXIT=0

mkdir -p "$OUT_DIR"

fail() {
  echo "gpu_terrain_cutout_fixture_scene_smoke: $*" >&2
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

require_port_free() {
  if command -v lsof >/dev/null 2>&1 && lsof -nP -iTCP:25565 -sTCP:LISTEN >/dev/null 2>&1; then
    fail "port 25565 is already in use; refusing to reuse a server for this isolated cutout fixture smoke"
  fi
}

cleanup_isolated_server() {
  test "$CLEANUP_SERVER_ON_EXIT" = "1" || return 0
  command -v lsof >/dev/null 2>&1 || return 0
  for _ in 1 2 3; do
    pid="$(lsof -tiTCP:25565 -sTCP:LISTEN | sed -n '1p' || true)"
    test -n "$pid" || return 0
    kill "$pid" >/dev/null 2>&1 || true
    sleep 0.2
  done
  pid="$(lsof -tiTCP:25565 -sTCP:LISTEN | sed -n '1p' || true)"
  test -n "$pid" || return 0
  kill -9 "$pid" >/dev/null 2>&1 || true
}

cleanup() {
  cleanup_isolated_server
}

trap cleanup EXIT
trap 'cleanup; exit 1' HUP INT TERM

screenshot_path="$OUT_DIR/gpu-transparent-cutout-fixture-scene-smoke.png"
marker_path="$screenshot_path.txt"
rm -rf "$ROCKSDB_PATH"
rm -f "$screenshot_path" "$marker_path" "$SUMMARY_PATH"

prepare_godot_rust_ext_profile "$ROOT_DIR"
require_port_free
CLEANUP_SERVER_ON_EXIT=1

echo "==> GPU terrain cutout fixture scene smoke"
(
  cd "$ROOT_DIR"
  "$TIMEOUT_BIN" "$GODOT_TIMEOUT_SEC" /usr/bin/env \
    RUMPELMC_SERVER_ROCKSDB_PATH="$ROCKSDB_PATH" \
    RUMPELMC_GPU_TERRAIN_RENDER=1 \
    RUMPELMC_GPU_TERRAIN_CUTOUT_PROTOTYPE=1 \
    RUMPELMC_GPU_TERRAIN_PARTIAL_DIRTY_UPLOAD="${RUMPELMC_GPU_TERRAIN_PARTIAL_DIRTY_UPLOAD:-1}" \
    RUMPELMC_GPU_TERRAIN_SHADOW_PROXY_MODE=conservative \
    RUMPELMC_GPU_TERRAIN_SHADOW_PROXY_MESH=compact \
    RUMPELMC_VISUAL_SMOKE_POSE=cutout_fixture \
    RUMPELMC_VISUAL_SMOKE_CUTOUT_FIXTURE=roles \
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
grep -q "pose=\"cutout_fixture\"" "$marker_path" || fail "unexpected pose in $marker_path"
grep -q "cutout_fixture=\"roles\"" "$marker_path" || fail "missing cutout fixture marker in $marker_path"
grep -q "smoke_err=0" "$marker_path" || fail "smoke_err is not 0 in $marker_path"
require_godot_rust_ext_marker_profile "$marker_path"

require_metric_ge "$marker_path" "terrain_samples" 12
require_metric_ge "$marker_path" "terrain_color_buckets" 4
require_metric_ge "$marker_path" "frame_samples" 10
require_metric_ge "$marker_path" "gpu_frames" 1
require_metric_eq "$marker_path" "gpu_upload_fail" 0
require_metric_ge "$marker_path" "current_chunk_collision" 1
require_metric_eq "$marker_path" "ground_misses" 0

require_metric_eq "$marker_path" "cutout_fixture_roles" 5
require_metric_eq "$marker_path" "cutout_fixture_blocks" 5
require_metric_eq "$marker_path" "cutout_fixture_leaf_blocks" 4
require_metric_eq "$marker_path" "cutout_fixture_opaque_blocks" 1
require_metric_eq "$marker_path" "cutout_fixture_dirty_observed" 1
require_metric_eq "$marker_path" "cutout_fixture_collision_samples" 5
require_metric_eq "$marker_path" "cutout_fixture_collision_hits" 5
require_metric_eq "$marker_path" "cutout_fixture_collision_misses" 0
require_metric_eq "$marker_path" "cutout_fixture_occlusion_probe_hit" 1
require_metric_eq "$marker_path" "cutout_fixture_queue_drained" 1
require_metric_eq "$marker_path" "cutout_fixture_adjacent_pair_blocks" 2
require_metric_eq "$marker_path" "cutout_fixture_adjacent_pair_block_id" 5
require_metric_eq "$marker_path" "cutout_fixture_adjacent_pair_same_material" 1
require_metric_eq "$marker_path" "cutout_fixture_adjacent_pair_neighbor" 1
require_metric_eq "$marker_path" "cutout_fixture_adjacent_pair_collision_hits" 2

require_metric_eq "$marker_path" "transparent_requested" 1
require_metric_eq "$marker_path" "transparent_active" 1
require_metric_eq "$marker_path" "transparent_fallback" 0
require_metric_eq "$marker_path" "transparent_blocks" 4
require_metric_eq "$marker_path" "transparent_faces" 17
require_metric_eq "$marker_path" "transparent_draws" 2
require_metric_eq "$marker_path" "transparent_subchunks" 2

{
  printf 'GPU transparent cutout fixture scene smoke summary\n'
  printf 'fixture=gpu-cutout-depth-collision\n'
  printf 'pose=cutout_fixture\n'
  printf 'screenshot=%s\n' "$screenshot_path"
  printf 'marker=%s\n' "$marker_path"
  printf 'summary transparent_cutout_fixture_scene_smoke_status=pass cutout_fixture=roles cutout_fixture_roles=5 cutout_fixture_blocks=5 cutout_fixture_leaf_blocks=4 cutout_fixture_opaque_blocks=1 cutout_fixture_dirty_observed=1 cutout_fixture_collision_samples=5 cutout_fixture_collision_hits=5 cutout_fixture_collision_misses=0 cutout_fixture_occlusion_probe_hit=1 cutout_fixture_queue_drained=1 cutout_fixture_adjacent_pair_blocks=2 cutout_fixture_adjacent_pair_block_id=5 cutout_fixture_adjacent_pair_same_material=1 cutout_fixture_adjacent_pair_neighbor=1 cutout_fixture_adjacent_pair_collision_hits=2 transparent_requested=1 transparent_active=1 transparent_fallback=0 transparent_blocks=%s transparent_faces=%s transparent_draws=%s transparent_subchunks=%s gpu_upload_fail=0 same_material_seam_policy=cutout_pair_visible_faces default_runtime_change_allowed=0 requires_external_profiler_before_default=1 requires_mac_windows_validation=1\n' \
    "$(metric transparent_blocks "$marker_path")" \
    "$(metric transparent_faces "$marker_path")" \
    "$(metric transparent_draws "$marker_path")" \
    "$(metric transparent_subchunks "$marker_path")"
} > "$SUMMARY_PATH"

cat "$SUMMARY_PATH"
cat "$marker_path"

if command -v sips >/dev/null 2>&1; then
  sips -g pixelWidth -g pixelHeight "$screenshot_path"
fi

cleanup_isolated_server
echo "GPU terrain cutout fixture scene smoke artifacts: $OUT_DIR"
