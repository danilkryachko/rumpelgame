#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/gpu_terrain_visual_smoke/movement_stress"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac
GODOT_BIN="${GODOT_BIN:-/opt/homebrew/bin/godot}"
TIMEOUT_BIN="${TIMEOUT_BIN:-/opt/homebrew/bin/timeout}"
GODOT_TIMEOUT_SEC="${GODOT_TIMEOUT_SEC:-120}"
GODOT_QUIT_AFTER_FRAMES="${GODOT_QUIT_AFTER_FRAMES:-8000}"
SMOKE_DELAY_SEC="${SMOKE_DELAY_SEC:-5.0}"
FRAME_SAMPLE_SEC="${RUMPELMC_MOVEMENT_STRESS_FRAME_SAMPLE_SEC:-5.0}"
MOTION_NAME="${RUMPELMC_MOVEMENT_STRESS_MOTION:-chunk_walk}"
MOTION_STEP_SEC="${RUMPELMC_MOVEMENT_STRESS_STEP_SEC:-0.55}"
MOTION_SETTLE_SEC="${RUMPELMC_MOVEMENT_STRESS_SETTLE_SEC:-4.0}"
MIN_MOTION_CHUNKS="${RUMPELMC_MOVEMENT_STRESS_MIN_CHUNKS:-4}"
EXPECTED_CURRENT_CHUNK="${RUMPELMC_MOVEMENT_STRESS_EXPECTED_CHUNK:-3,2}"
TARGET_FPS="${RUMPELMC_MOVEMENT_STRESS_TARGET_FPS:-150}"
BUDGET_MODE="${RUMPELMC_MOVEMENT_STRESS_BUDGET_MODE:-enforce}"
PROCESS_WALL_BUDGET_MODE="${RUMPELMC_MOVEMENT_STRESS_PROCESS_WALL_BUDGET_MODE:-enforce}"
GPU_COMPOSITOR_BUDGET_MODE="${RUMPELMC_MOVEMENT_STRESS_GPU_COMPOSITOR_BUDGET_MODE:-enforce}"
GPU_TIMESTAMP_BUDGET_MODE="${RUMPELMC_MOVEMENT_STRESS_GPU_TIMESTAMP_BUDGET_MODE:-report}"

mkdir -p "$OUT_DIR"

fail() {
  echo "gpu_terrain_movement_stress: $*" >&2
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

text_metric() {
  key="$1"
  marker_path="$2"
  sed -n "s/.*$key=\([^ ]*\).*/\1/p" "$marker_path" | sed -n '1p'
}

perf_triplet_value() {
  key="$1"
  marker_path="$2"
  index="$3"
  sed -n "s/.*$key=\([0-9][0-9]*\.[0-9][0-9]*\)\/\([0-9][0-9]*\.[0-9][0-9]*\)\/\([0-9][0-9]*\.[0-9][0-9]*\).*/\1 \2 \3/p" "$marker_path" \
    | awk -v index="$index" '{print $index}' \
    | sed -n '1p'
}

perf_count_triplet_value() {
  key="$1"
  marker_path="$2"
  index="$3"
  sed -n "s/.*$key=\([0-9][0-9]*\)\/\([0-9][0-9]*\.[0-9][0-9]*\)\/\([0-9][0-9]*\).*/\1 \2 \3/p" "$marker_path" \
    | awk -v index="$index" '{print $index}' \
    | sed -n '1p'
}

perf_pair_value() {
  key="$1"
  marker_path="$2"
  index="$3"
  sed -n "s/.*$key=\([0-9][0-9]*\.[0-9][0-9]*\)\/\([0-9][0-9]*\.[0-9][0-9]*\).*/\1 \2/p" "$marker_path" \
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

mesh_triplet_value() {
  marker_path="$1"
  index="$2"
  sed -n 's/.* mesh \([0-9][0-9]*\.[0-9][0-9]*\)\/\([0-9][0-9]*\.[0-9][0-9]*\)\/\([0-9][0-9]*\.[0-9][0-9]*\)ms .*/\1 \2 \3/p' "$marker_path" \
    | awk -v index="$index" '{print $index}' \
    | sed -n '1p'
}

collision_triplet_value() {
  marker_path="$1"
  index="$2"
  sed -n 's/.* coll \([0-9][0-9]*\.[0-9][0-9]*\)\/\([0-9][0-9]*\.[0-9][0-9]*\)\/\([0-9][0-9]*\.[0-9][0-9]*\)ms .*/\1 \2 \3/p' "$marker_path" \
    | awk -v index="$index" '{print $index}' \
    | sed -n '1p'
}

frame_budget_ms() {
  awk -v fps="$TARGET_FPS" '
    BEGIN {
      if (fps <= 0.0) {
        fps = 150.0
      }
      printf("%.3f\n", 1000.0 / fps)
    }
  '
}

write_summary() {
  summary_path="$OUT_DIR/movement-stress-summary.txt"
  budget_ms="$(frame_budget_ms)"
  terrain_queue_avg="$(perf_triplet_value terrain_queue_work_ms "$marker_path" 2)"
  terrain_queue_max="$(perf_triplet_value terrain_queue_work_ms "$marker_path" 3)"
  terrain_queue_max_mesh="$(default_float "$(perf_pair_value terrain_queue_work_max_parts "$marker_path" 1)")"
  terrain_queue_max_coll="$(default_float "$(perf_pair_value terrain_queue_work_max_parts "$marker_path" 2)")"
  terrain_queue_uploads_avg="$(default_float "$(perf_count_triplet_value terrain_queue_gpu_uploads "$marker_path" 2)")"
  terrain_queue_uploads_max="$(default_float "$(perf_count_triplet_value terrain_queue_gpu_uploads "$marker_path" 3)")"
  terrain_queue_upload_kb_avg="$(default_float "$(perf_triplet_value terrain_queue_gpu_upload_kb "$marker_path" 2)")"
  terrain_queue_upload_kb_max="$(default_float "$(perf_triplet_value terrain_queue_gpu_upload_kb "$marker_path" 3)")"
  mesh_avg="$(mesh_triplet_value "$marker_path" 2)"
  mesh_max="$(mesh_triplet_value "$marker_path" 3)"
  coll_avg="$(collision_triplet_value "$marker_path" 2)"
  coll_max="$(collision_triplet_value "$marker_path" 3)"
  compositor_submit_avg="$(default_float "$(perf_triplet_value gpu_compositor_submit_ms "$marker_path" 2)")"
  compositor_submit_max="$(default_float "$(perf_triplet_value gpu_compositor_submit_ms "$marker_path" 3)")"
  compositor_submit_max_setup="$(default_float "$(perf_quad_value gpu_compositor_submit_max_parts "$marker_path" 1)")"
  compositor_submit_max_target="$(default_float "$(perf_quad_value gpu_compositor_submit_max_parts "$marker_path" 2)")"
  compositor_submit_max_constants="$(default_float "$(perf_quad_value gpu_compositor_submit_max_parts "$marker_path" 3)")"
  compositor_submit_max_draw="$(default_float "$(perf_quad_value gpu_compositor_submit_max_parts "$marker_path" 4)")"
  compositor_gpu_avg="$(default_float "$(perf_triplet_value gpu_compositor_gpu_ms "$marker_path" 2)")"
  compositor_gpu_max="$(default_float "$(perf_triplet_value gpu_compositor_gpu_ms "$marker_path" 3)")"
  compositor_gpu_us_avg="$(default_float "$(perf_triplet_value gpu_compositor_gpu_us "$marker_path" 2)")"
  compositor_gpu_us_max="$(default_float "$(perf_triplet_value gpu_compositor_gpu_us "$marker_path" 3)")"
  compositor_gpu_samples="$(metric gpu_compositor_gpu_samples "$marker_path")"
  gpu_effective_draws="$(metric gpu_effective_draws "$marker_path")"
  gpu_draw_repeat="$(metric gpu_draw_repeat "$marker_path")"
  gpu_draw_cmd_bytes="$(metric gpu_draw_cmd_bytes "$marker_path")"
  gpu_draw_cmd_capacity_bytes="$(metric gpu_draw_cmd_capacity_bytes "$marker_path")"
  gpu_draw_cmd_stride="$(metric gpu_draw_cmd_stride "$marker_path")"
  gpu_scene_target_create="$(metric gpu_scene_target_create "$marker_path")"
  gpu_scene_target_reuse="$(metric gpu_scene_target_reuse "$marker_path")"
  gpu_scene_target_replace="$(metric gpu_scene_target_replace "$marker_path")"
  gpu_uniform_set_create="$(metric gpu_uniform_set_create "$marker_path")"
  gpu_atlas_texture_create="$(metric gpu_atlas_texture_create "$marker_path")"
  gpu_atlas_sampler_create="$(metric gpu_atlas_sampler_create "$marker_path")"
  gpu_push_constant_bytes="$(metric gpu_push_constant_bytes "$marker_path")"
  gpu_cull="$(text_metric gpu_cull "$marker_path")"
  gpu_front_face="$(text_metric gpu_front_face "$marker_path")"
  frame_p95="$(float_metric frame_p95_ms "$marker_path")"
  fps_p05="$(float_metric fps_p05 "$marker_path")"
  process_wall_p95="$(float_metric process_wall_p95_ms "$marker_path")"
  test -n "$terrain_queue_avg" || fail "missing terrain_queue_work_ms in $marker_path"
  test -n "$mesh_avg" || fail "missing mesh triplet in $marker_path"
  test -n "$coll_avg" || fail "missing coll triplet in $marker_path"
  test -n "$process_wall_p95" || fail "missing process_wall_p95_ms in $marker_path"
  awk \
    -v budget="$budget_ms" \
    -v terrain_queue_avg="$terrain_queue_avg" \
    -v terrain_queue_max="$terrain_queue_max" \
    -v terrain_queue_max_mesh="$terrain_queue_max_mesh" \
    -v terrain_queue_max_coll="$terrain_queue_max_coll" \
    -v terrain_queue_uploads_avg="$terrain_queue_uploads_avg" \
    -v terrain_queue_uploads_max="$terrain_queue_uploads_max" \
    -v terrain_queue_upload_kb_avg="$terrain_queue_upload_kb_avg" \
    -v terrain_queue_upload_kb_max="$terrain_queue_upload_kb_max" \
    -v mesh_avg="$mesh_avg" \
    -v mesh_max="$mesh_max" \
    -v coll_avg="$coll_avg" \
    -v coll_max="$coll_max" \
    -v compositor_submit_avg="$compositor_submit_avg" \
    -v compositor_submit_max="$compositor_submit_max" \
    -v compositor_submit_max_setup="$compositor_submit_max_setup" \
    -v compositor_submit_max_target="$compositor_submit_max_target" \
    -v compositor_submit_max_constants="$compositor_submit_max_constants" \
    -v compositor_submit_max_draw="$compositor_submit_max_draw" \
    -v compositor_gpu_avg="$compositor_gpu_avg" \
    -v compositor_gpu_max="$compositor_gpu_max" \
    -v compositor_gpu_us_avg="$compositor_gpu_us_avg" \
    -v compositor_gpu_us_max="$compositor_gpu_us_max" \
    -v compositor_gpu_samples="${compositor_gpu_samples:-0}" \
    -v gpu_effective_draws="${gpu_effective_draws:-0}" \
    -v gpu_draw_repeat="${gpu_draw_repeat:-1}" \
    -v gpu_draw_cmd_bytes="${gpu_draw_cmd_bytes:-0}" \
    -v gpu_draw_cmd_capacity_bytes="${gpu_draw_cmd_capacity_bytes:-0}" \
    -v gpu_draw_cmd_stride="${gpu_draw_cmd_stride:-0}" \
    -v gpu_scene_target_create="${gpu_scene_target_create:-0}" \
    -v gpu_scene_target_reuse="${gpu_scene_target_reuse:-0}" \
    -v gpu_scene_target_replace="${gpu_scene_target_replace:-0}" \
    -v gpu_uniform_set_create="${gpu_uniform_set_create:-0}" \
    -v gpu_atlas_texture_create="${gpu_atlas_texture_create:-0}" \
    -v gpu_atlas_sampler_create="${gpu_atlas_sampler_create:-0}" \
    -v gpu_push_constant_bytes="${gpu_push_constant_bytes:-0}" \
    -v gpu_cull="${gpu_cull:-n/a}" \
    -v gpu_front_face="${gpu_front_face:-n/a}" \
    -v frame_p95="$frame_p95" \
    -v fps_p05="$fps_p05" \
    -v process_wall_p95="$process_wall_p95" '
      BEGIN {
        status = "pass"
        over = terrain_queue_max - budget
        if (over > 0.0) {
          status = "fail"
        }
        printf("GPU terrain movement stress summary target_fps=%.0f budget_ms=%.3f\n", 1000.0 / budget, budget)
        printf("movement_terrain_queue avg_ms=%.3f max_ms=%.3f max_mesh_ms=%.3f max_coll_ms=%.3f budget_status=%s over_ms=%.3f queue_uploads_avg=%.2f queue_uploads_max=%.0f queue_upload_kb_avg=%.1f queue_upload_kb_max=%.1f mesh_avg_ms=%.3f mesh_max_ms=%.3f coll_avg_ms=%.3f coll_max_ms=%.3f gpu_effective_draws=%d gpu_draw_repeat=%d gpu_draw_cmd_bytes=%d gpu_draw_cmd_capacity_bytes=%d gpu_draw_cmd_stride=%d gpu_scene_target_create=%d gpu_scene_target_reuse=%d gpu_scene_target_replace=%d gpu_uniform_set_create=%d gpu_atlas_texture_create=%d gpu_atlas_sampler_create=%d gpu_push_constant_bytes=%d gpu_cull=%s gpu_front_face=%s gpu_compositor_submit_avg_ms=%.3f gpu_compositor_submit_max_ms=%.3f gpu_compositor_submit_max_parts_ms=%.3f/%.3f/%.3f/%.3f gpu_compositor_gpu_samples=%d gpu_compositor_gpu_avg_ms=%.3f gpu_compositor_gpu_max_ms=%.3f gpu_compositor_gpu_avg_us=%.1f gpu_compositor_gpu_max_us=%.1f process_wall_p95_ms=%.3f frame_p95_ms=%.3f fps_p05=%.1f\n", terrain_queue_avg, terrain_queue_max, terrain_queue_max_mesh, terrain_queue_max_coll, status, over, terrain_queue_uploads_avg, terrain_queue_uploads_max, terrain_queue_upload_kb_avg, terrain_queue_upload_kb_max, mesh_avg, mesh_max, coll_avg, coll_max, gpu_effective_draws, gpu_draw_repeat, gpu_draw_cmd_bytes, gpu_draw_cmd_capacity_bytes, gpu_draw_cmd_stride, gpu_scene_target_create, gpu_scene_target_reuse, gpu_scene_target_replace, gpu_uniform_set_create, gpu_atlas_texture_create, gpu_atlas_sampler_create, gpu_push_constant_bytes, gpu_cull, gpu_front_face, compositor_submit_avg, compositor_submit_max, compositor_submit_max_setup, compositor_submit_max_target, compositor_submit_max_constants, compositor_submit_max_draw, compositor_gpu_samples, compositor_gpu_avg, compositor_gpu_max, compositor_gpu_us_avg, compositor_gpu_us_max, process_wall_p95, frame_p95, fps_p05)
      }
    ' > "$summary_path"
  cat "$summary_path"
}

enforce_terrain_queue_budget() {
  budget_ms="$(frame_budget_ms)"
  terrain_queue_max="$(perf_triplet_value terrain_queue_work_ms "$marker_path" 3)"
  test -n "$terrain_queue_max" || fail "missing terrain_queue_work_ms in $marker_path"
  awk -v terrain_queue_max="$terrain_queue_max" -v budget="$budget_ms" '
    BEGIN {
      if (terrain_queue_max > budget) {
        printf("gpu_terrain_movement_stress: terrain_queue_max_ms %.3f exceeds %.3f\n", terrain_queue_max, budget) > "/dev/stderr"
        exit 1
      }
    }
  '
}

enforce_process_wall_budget() {
  budget_ms="$(frame_budget_ms)"
  p95_ms="$(float_metric process_wall_p95_ms "$marker_path")"
  test -n "$p95_ms" || fail "missing process_wall_p95_ms in $marker_path"
  awk -v p95="$p95_ms" -v budget="$budget_ms" '
    BEGIN {
      if (p95 > budget) {
        printf("gpu_terrain_movement_stress: process_wall_p95_ms %.3f exceeds %.3f\n", p95, budget) > "/dev/stderr"
        exit 1
      }
    }
  '
}

enforce_gpu_compositor_budget() {
  budget_ms="$(frame_budget_ms)"
  max_ms="$(perf_triplet_value gpu_compositor_submit_ms "$marker_path" 3)"
  test -n "$max_ms" || fail "missing gpu_compositor_submit_ms in $marker_path"
  awk -v max_ms="$max_ms" -v budget="$budget_ms" '
    BEGIN {
      if (max_ms > budget) {
        printf("gpu_terrain_movement_stress: gpu_compositor_submit_max_ms %.3f exceeds %.3f\n", max_ms, budget) > "/dev/stderr"
        exit 1
      }
    }
  '
}

enforce_gpu_timestamp_budget() {
  budget_ms="$(frame_budget_ms)"
  max_ms="$(perf_triplet_value gpu_compositor_gpu_ms "$marker_path" 3)"
  test -n "$max_ms" || fail "missing gpu_compositor_gpu_ms in $marker_path"
  awk -v max_ms="$max_ms" -v budget="$budget_ms" '
    BEGIN {
      if (max_ms > budget) {
        printf("gpu_terrain_movement_stress: gpu_compositor_gpu_max_ms %.3f exceeds %.3f\n", max_ms, budget) > "/dev/stderr"
        exit 1
      }
    }
  '
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

prepare_godot_rust_ext_profile "$ROOT_DIR"

echo "==> GPU terrain movement stress"
(
  cd "$ROOT_DIR"
  "$TIMEOUT_BIN" "$GODOT_TIMEOUT_SEC" /usr/bin/env \
    RUMPELMC_GPU_TERRAIN_RENDER=1 \
    RUMPELMC_GPU_TERRAIN_PARTIAL_DIRTY_UPLOAD="${RUMPELMC_GPU_TERRAIN_PARTIAL_DIRTY_UPLOAD:-1}" \
    RUMPELMC_GPU_TERRAIN_SHADOW_PROXY_MODE=conservative \
    RUMPELMC_GPU_TERRAIN_SHADOW_PROXY_MESH=compact \
    RUMPELMC_VISUAL_SMOKE_MOTION="$MOTION_NAME" \
    RUMPELMC_VISUAL_SMOKE_MOTION_STEP_SEC="$MOTION_STEP_SEC" \
    RUMPELMC_VISUAL_SMOKE_MOTION_SETTLE_SEC="$MOTION_SETTLE_SEC" \
    RUMPELMC_VISUAL_SMOKE_BLOCK_EDIT="${RUMPELMC_VISUAL_SMOKE_BLOCK_EDIT:-}" \
    RUMPELMC_VISUAL_SMOKE_BLOCK_EDIT_X="${RUMPELMC_VISUAL_SMOKE_BLOCK_EDIT_X:-}" \
    RUMPELMC_VISUAL_SMOKE_BLOCK_EDIT_Y="${RUMPELMC_VISUAL_SMOKE_BLOCK_EDIT_Y:-}" \
    RUMPELMC_VISUAL_SMOKE_BLOCK_EDIT_Z="${RUMPELMC_VISUAL_SMOKE_BLOCK_EDIT_Z:-}" \
    RUMPELMC_VISUAL_SMOKE_BLOCK_EDIT_ID="${RUMPELMC_VISUAL_SMOKE_BLOCK_EDIT_ID:-}" \
    RUMPELMC_VISUAL_SMOKE_BLOCK_EDIT_WAIT_SEC="${RUMPELMC_VISUAL_SMOKE_BLOCK_EDIT_WAIT_SEC:-}" \
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
grep -q "motion=\"$MOTION_NAME\"" "$marker_path" || fail "unexpected motion in $marker_path"
grep -q "current_chunk=\"$EXPECTED_CURRENT_CHUNK\"" "$marker_path" || fail "movement did not finish in chunk $EXPECTED_CURRENT_CHUNK"
grep -q "smoke_err=0" "$marker_path" || fail "smoke_err is not 0 in $marker_path"
require_godot_rust_ext_marker_profile "$marker_path"
require_metric_ge "$marker_path" "motion_steps" 4
require_metric_ge "$marker_path" "motion_chunks" "$MIN_MOTION_CHUNKS"
require_metric_ge "$marker_path" "frame_samples" 10
require_metric_ge "$marker_path" "terrain_samples" 1
require_metric_ge "$marker_path" "queue_max" 1
require_metric_ge "$marker_path" "queue_enq" 1
require_metric_ge "$marker_path" "queue_drained" 1
require_metric_ge "$marker_path" "queue_stale" 0
require_metric_ge "$marker_path" "queue_missing" 0
require_metric_ge "$marker_path" "proxy_refresh_reuse" 0
require_metric_ge "$marker_path" "gpu_frames" 1
require_metric_ge "$marker_path" "gpu_subchunks" 1
require_metric_ge "$marker_path" "gpu_uploads" 1
require_metric_eq "$marker_path" "gpu_upload_fail" 0
require_metric_eq "$marker_path" "gpu_upload_fail_capacity" 0
require_metric_eq "$marker_path" "gpu_upload_fail_fragmented" 0
test -n "$(perf_triplet_value terrain_queue_work_ms "$marker_path" 3)" || fail "missing terrain_queue_work_ms in $marker_path"

write_summary
case "$BUDGET_MODE" in
  report|"") ;;
  enforce)
    enforce_terrain_queue_budget
    ;;
  *)
    fail "unsupported RUMPELMC_MOVEMENT_STRESS_BUDGET_MODE=$BUDGET_MODE"
    ;;
esac
case "$PROCESS_WALL_BUDGET_MODE" in
  report|"") ;;
  enforce)
    enforce_process_wall_budget
    ;;
  *)
    fail "unsupported RUMPELMC_MOVEMENT_STRESS_PROCESS_WALL_BUDGET_MODE=$PROCESS_WALL_BUDGET_MODE"
    ;;
esac
case "$GPU_COMPOSITOR_BUDGET_MODE" in
  report|"") ;;
  enforce)
    enforce_gpu_compositor_budget
    ;;
  *)
    fail "unsupported RUMPELMC_MOVEMENT_STRESS_GPU_COMPOSITOR_BUDGET_MODE=$GPU_COMPOSITOR_BUDGET_MODE"
    ;;
esac
case "$GPU_TIMESTAMP_BUDGET_MODE" in
  report|"") ;;
  enforce)
    enforce_gpu_timestamp_budget
    ;;
  *)
    fail "unsupported RUMPELMC_MOVEMENT_STRESS_GPU_TIMESTAMP_BUDGET_MODE=$GPU_TIMESTAMP_BUDGET_MODE"
    ;;
esac

cat "$marker_path"

if command -v sips >/dev/null 2>&1; then
  sips -g pixelWidth -g pixelHeight "$screenshot_path"
fi

echo "GPU terrain movement stress artifacts: $OUT_DIR"
