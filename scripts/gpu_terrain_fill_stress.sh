#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/gpu_terrain_fill_stress"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

REPEATS="${RUMPELMC_FILL_STRESS_REPEATS:-1 2 4 8}"
SERVER_VIEW_DISTANCE="${RUMPELMC_FILL_STRESS_SERVER_VIEW_DISTANCE:-16}"
CLIENT_KEEP_CHUNK_DISTANCE="${RUMPELMC_FILL_STRESS_CLIENT_KEEP_CHUNK_DISTANCE:-$SERVER_VIEW_DISTANCE}"
SERVER_CHUNKS_PER_UPDATE="${RUMPELMC_FILL_STRESS_SERVER_CHUNKS_PER_UPDATE:-64}"
SMOKE_DELAY_SEC="${RUMPELMC_FILL_STRESS_SMOKE_DELAY_SEC:-20.0}"
MOTION_SETTLE_SEC="${RUMPELMC_FILL_STRESS_SETTLE_SEC:-45.0}"
GODOT_QUIT_AFTER_FRAMES="${GODOT_QUIT_AFTER_FRAMES:-52000}"
GODOT_TIMEOUT_SEC="${GODOT_TIMEOUT_SEC:-720}"

mkdir -p "$OUT_DIR"

fail() {
  echo "gpu_terrain_fill_stress: $*" >&2
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

perf_triplet_value() {
  key="$1"
  marker_path="$2"
  index="$3"
  sed -n "s/.*$key=\([0-9][0-9]*\.[0-9][0-9]*\)\/\([0-9][0-9]*\.[0-9][0-9]*\)\/\([0-9][0-9]*\.[0-9][0-9]*\).*/\1 \2 \3/p" "$marker_path" \
    | awk -v index="$index" '{print $index}' \
    | sed -n '1p'
}

perf_quad_value() {
  key="$1"
  marker_path="$2"
  index="$3"
  sed -n "s/.*$key=\([0-9][0-9]*\.[0-9][0-9]*\)\/\([0-9][0-9]*\.[0-9][0-9]*\)\/\([0-9][0-9]*\.[0-9][0-9]*\)\/\([0-9][0-9]*\.[0-9][0-9]*\).*/\1 \2 \3 \4/p" "$marker_path" \
    | awk -v index="$index" '{print $index}' \
    | sed -n '1p'
}

default_float() {
  value="$1"
  if [ -n "$value" ]; then
    printf '%s\n' "$value"
  else
    printf '0.000\n'
  fi
}

summary_line() {
  repeat="$1"
  marker_path="$2"

  gpu_draws="$(metric gpu_draws "$marker_path")"
  gpu_effective_draws="$(metric gpu_effective_draws "$marker_path")"
  gpu_draw_repeat="$(metric gpu_draw_repeat "$marker_path")"
  gpu_faces="$(metric gpu_faces "$marker_path")"
  gpu_upload_fail="$(metric gpu_upload_fail "$marker_path")"
  queue_max="$(default_float "$(perf_triplet_value terrain_queue_work_ms "$marker_path" 3)")"
  process_wall_p95="$(default_float "$(float_metric process_wall_p95_ms "$marker_path")")"
  compositor_submit_max="$(default_float "$(perf_triplet_value gpu_compositor_submit_ms "$marker_path" 3)")"
  compositor_submit_max_setup="$(default_float "$(perf_quad_value gpu_compositor_submit_max_parts "$marker_path" 1)")"
  compositor_submit_max_target="$(default_float "$(perf_quad_value gpu_compositor_submit_max_parts "$marker_path" 2)")"
  compositor_submit_max_constants="$(default_float "$(perf_quad_value gpu_compositor_submit_max_parts "$marker_path" 3)")"
  compositor_submit_max_draw="$(default_float "$(perf_quad_value gpu_compositor_submit_max_parts "$marker_path" 4)")"
  frame_p95="$(default_float "$(float_metric frame_p95_ms "$marker_path")")"
  fps_p05="$(default_float "$(float_metric fps_p05 "$marker_path")")"

  awk \
    -v repeat="$repeat" \
    -v gpu_draw_repeat="${gpu_draw_repeat:-0}" \
    -v gpu_draws="${gpu_draws:-0}" \
    -v gpu_effective_draws="${gpu_effective_draws:-0}" \
    -v gpu_faces="${gpu_faces:-0}" \
    -v gpu_upload_fail="${gpu_upload_fail:-0}" \
    -v queue_max="$queue_max" \
    -v process_wall_p95="$process_wall_p95" \
    -v compositor_submit_max="$compositor_submit_max" \
    -v compositor_submit_max_setup="$compositor_submit_max_setup" \
    -v compositor_submit_max_target="$compositor_submit_max_target" \
    -v compositor_submit_max_constants="$compositor_submit_max_constants" \
    -v compositor_submit_max_draw="$compositor_submit_max_draw" \
    -v frame_p95="$frame_p95" \
    -v fps_p05="$fps_p05" '
      BEGIN {
        printf("repeat=%s gpu_draw_repeat=%d gpu_draws=%d gpu_effective_draws=%d gpu_faces=%d gpu_upload_fail=%d terrain_queue_max_ms=%.3f process_wall_p95_ms=%.3f gpu_compositor_submit_max_ms=%.3f gpu_compositor_submit_max_parts_ms=%.3f/%.3f/%.3f/%.3f frame_p95_ms=%.3f fps_p05=%.1f\n", repeat, gpu_draw_repeat, gpu_draws, gpu_effective_draws, gpu_faces, gpu_upload_fail, queue_max, process_wall_p95, compositor_submit_max, compositor_submit_max_setup, compositor_submit_max_target, compositor_submit_max_constants, compositor_submit_max_draw, frame_p95, fps_p05)
      }
    '
}

summary_path="$OUT_DIR/fill-stress-summary.txt"
printf 'GPU terrain fill stress server_view_distance=%s client_keep_distance=%s server_chunks_per_update=%s repeats="%s"\n' "$SERVER_VIEW_DISTANCE" "$CLIENT_KEEP_CHUNK_DISTANCE" "$SERVER_CHUNKS_PER_UPDATE" "$REPEATS" | tee "$summary_path"
for repeat in $REPEATS; do
  case "$repeat" in
    ''|*[!0-9]*)
      fail "repeat value must be a positive integer: $repeat"
      ;;
  esac
  test "$repeat" -gt 0 || fail "repeat value must be greater than 0"
  case_dir="$OUT_DIR/repeat-$repeat"
  rm -rf "$case_dir"
  echo "==> GPU terrain fill stress: repeat=$repeat" >&2
  RUMPELMC_GPU_TERRAIN_COMPOSITOR_DRAW_REPEAT="$repeat" \
    RUMPELMC_SERVER_VIEW_DISTANCE="$SERVER_VIEW_DISTANCE" \
    RUMPELMC_CLIENT_KEEP_CHUNK_DISTANCE="$CLIENT_KEEP_CHUNK_DISTANCE" \
    RUMPELMC_SERVER_CHUNKS_PER_UPDATE="$SERVER_CHUNKS_PER_UPDATE" \
    RUMPELMC_MOVEMENT_STRESS_MOTION=chunk_walk_extended \
    RUMPELMC_MOVEMENT_STRESS_EXPECTED_CHUNK=11,8 \
    RUMPELMC_MOVEMENT_STRESS_MIN_CHUNKS=12 \
    RUMPELMC_MOVEMENT_STRESS_SETTLE_SEC="$MOTION_SETTLE_SEC" \
    RUMPELMC_MOVEMENT_STRESS_GPU_COMPOSITOR_BUDGET_MODE=report \
    SMOKE_DELAY_SEC="$SMOKE_DELAY_SEC" \
    GODOT_QUIT_AFTER_FRAMES="$GODOT_QUIT_AFTER_FRAMES" \
    GODOT_TIMEOUT_SEC="$GODOT_TIMEOUT_SEC" \
    "$ROOT_DIR/scripts/gpu_terrain_movement_stress.sh" "$case_dir" > "$case_dir.run.log" 2>&1
  marker_path="$case_dir/gpu-terrain-movement-stress.png.txt"
  test -s "$marker_path" || fail "missing marker $marker_path"
  summary_line "$repeat" "$marker_path" | tee -a "$summary_path"
done

echo "GPU terrain fill stress artifacts: $OUT_DIR"
