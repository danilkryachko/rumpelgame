#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/gpu_terrain_perf_baseline"}"
GODOT_BIN="${GODOT_BIN:-/opt/homebrew/bin/godot}"
TIMEOUT_BIN="${TIMEOUT_BIN:-/opt/homebrew/bin/timeout}"
GODOT_TIMEOUT_SEC="${GODOT_TIMEOUT_SEC:-120}"
GODOT_QUIT_AFTER_FRAMES="${GODOT_QUIT_AFTER_FRAMES:-8000}"
SMOKE_DELAY_SEC="${SMOKE_DELAY_SEC:-6.0}"
FRAME_SAMPLE_SEC="${RUMPELMC_PERF_BASELINE_FRAME_SAMPLE_SEC:-3.0}"
SMOKE_POSE="${RUMPELMC_PERF_BASELINE_POSE:-lighting_shadow}"
CAPTURE="${RUMPELMC_PERF_BASELINE_CAPTURE:-1}"
TARGET_FPS="${RUMPELMC_PERF_BASELINE_TARGET_FPS:-150}"
BUDGET_MODE="${RUMPELMC_PERF_BASELINE_BUDGET_MODE:-report}"
BUDGET_P95_MS="${RUMPELMC_PERF_BASELINE_FRAME_P95_BUDGET_MS:-}"

mkdir -p "$OUT_DIR"

fail() {
  echo "gpu_terrain_perf_baseline: $*" >&2
  exit 1
}

. "$ROOT_DIR/scripts/godot_rust_ext_profile.sh"

frame_budget_ms() {
  if [ -n "$BUDGET_P95_MS" ]; then
    printf '%s\n' "$BUDGET_P95_MS"
    return
  fi
  awk -v fps="$TARGET_FPS" '
    BEGIN {
      if (fps <= 0.0) {
        fps = 150.0
      }
      printf("%.3f\n", 1000.0 / fps)
    }
  '
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

perf_float() {
  float_metric "$1" "$2"
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

perf_triplet_value() {
  key="$1"
  marker_path="$2"
  index="$3"
  sed -n "s/.*$key=\([0-9][0-9]*\.[0-9][0-9]*\)\/\([0-9][0-9]*\.[0-9][0-9]*\)\/\([0-9][0-9]*\.[0-9][0-9]*\).*/\1 \2 \3/p" "$marker_path" \
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

require_marker() {
  marker_path="$1"
  test -s "$marker_path" || fail "missing marker $marker_path"
  grep -q "Visual smoke screenshot saved" "$marker_path" || fail "missing smoke summary in $marker_path"
  grep -q "pose=\"$SMOKE_POSE\"" "$marker_path" || fail "unexpected pose in $marker_path"
  grep -q "smoke_err=0" "$marker_path" || fail "smoke_err is not 0 in $marker_path"
  if [ "$CAPTURE" = "1" ]; then
    require_godot_rust_ext_marker_profile "$marker_path"
  fi
  samples="$(metric frame_samples "$marker_path")"
  test -n "$samples" || fail "missing frame_samples in $marker_path"
  if [ "$samples" -lt 10 ]; then
    fail "frame_samples=$samples is too low in $marker_path"
  fi
  test -n "$(float_metric frame_p95_ms "$marker_path")" || fail "missing frame_p95_ms in $marker_path"
  test -n "$(float_metric fps_p05 "$marker_path")" || fail "missing fps_p05 in $marker_path"
}

run_case() {
  name="$1"
  gpu_flag="$2"
  screenshot_path="$OUT_DIR/$name.png"
  marker_path="$screenshot_path.txt"

  rm -f "$marker_path" "$screenshot_path"

  echo "==> GPU terrain perf baseline: $name"
  (
    cd "$ROOT_DIR"
    "$TIMEOUT_BIN" "$GODOT_TIMEOUT_SEC" /usr/bin/env \
      RUMPELMC_GPU_TERRAIN_RENDER="$gpu_flag" \
      RUMPELMC_GPU_TERRAIN_SHADOW_PROXY_MODE=conservative \
      RUMPELMC_GPU_TERRAIN_SHADOW_PROXY_MESH=compact \
      RUMPELMC_VISUAL_SMOKE_POSE="$SMOKE_POSE" \
      RUMPELMC_VISUAL_SMOKE_PATH="$screenshot_path" \
      RUMPELMC_VISUAL_SMOKE_DELAY_SEC="$SMOKE_DELAY_SEC" \
      RUMPELMC_VISUAL_SMOKE_FRAME_SAMPLE_SEC="$FRAME_SAMPLE_SEC" \
      RUMPELMC_VISUAL_SMOKE_FORCE_UNCAPPED="${RUMPELMC_VISUAL_SMOKE_FORCE_UNCAPPED:-0}" \
      RUMPELMC_VISUAL_SMOKE_HIDE_HUD=1 \
      RUMPELMC_VISUAL_SMOKE_DISABLE_PLAYER_INPUT=1 \
      "$GODOT_BIN" --disable-vsync --max-fps 0 --path client --quit-after "$GODOT_QUIT_AFTER_FRAMES"
  )

  require_marker "$marker_path"
}

print_row() {
  label="$1"
  marker_path="$2"
  printf '%-12s frame_avg_ms=%s frame_p50_ms=%s frame_p95_ms=%s frame_p99_ms=%s frame_max_ms=%s fps_avg=%s fps_p05=%s fps_min=%s process_wall_avg_ms=%s process_wall_p95_ms=%s process_wall_max_ms=%s post_draw_wait_ms=%s image_read_ms=%s image_save_ms=%s image_metrics_ms=%s engine_max_fps=%s vsync_mode=%s screen_refresh_hz=%s mesh_avg_ms=%s mesh_max_ms=%s coll_avg_ms=%s cpu_proxy=%s gpu_subchunks=%s gpu_draws=%s gpu_faces=%s gpu_mem_mb=%s gpu_uploads=%s gpu_upload_fail=%s gpu_upload_fail_capacity=%s gpu_upload_fail_fragmented=%s gpu_free_ranges=%s gpu_largest_free=%s gpu_draw_rebuilds=%s gpu_draw_rebuild_ms=%s gpu_draw_patches=%s gpu_draw_patch_ms=%s terrain_samples=%s\n' \
    "$label" \
    "$(float_metric frame_avg_ms "$marker_path")" \
    "$(float_metric frame_p50_ms "$marker_path")" \
    "$(float_metric frame_p95_ms "$marker_path")" \
    "$(float_metric frame_p99_ms "$marker_path")" \
    "$(float_metric frame_max_ms "$marker_path")" \
    "$(float_metric fps_avg "$marker_path")" \
    "$(float_metric fps_p05 "$marker_path")" \
    "$(float_metric fps_min "$marker_path")" \
    "$(float_metric process_wall_avg_ms "$marker_path")" \
    "$(float_metric process_wall_p95_ms "$marker_path")" \
    "$(float_metric process_wall_max_ms "$marker_path")" \
    "$(float_metric post_draw_wait_ms "$marker_path")" \
    "$(float_metric image_read_ms "$marker_path")" \
    "$(float_metric image_save_ms "$marker_path")" \
    "$(float_metric image_metrics_ms "$marker_path")" \
    "$(metric engine_max_fps "$marker_path")" \
    "$(metric vsync_mode "$marker_path")" \
    "$(float_metric screen_refresh_hz "$marker_path")" \
    "$(mesh_triplet_value "$marker_path" 2)" \
    "$(mesh_triplet_value "$marker_path" 3)" \
    "$(collision_triplet_value "$marker_path" 2)" \
    "$(metric cpu_proxy "$marker_path")" \
    "$(metric gpu_subchunks "$marker_path")" \
    "$(metric gpu_draws "$marker_path")" \
    "$(metric gpu_faces "$marker_path")" \
    "$(perf_float gpu_mem "$marker_path")" \
    "$(metric gpu_uploads "$marker_path")" \
    "$(metric gpu_upload_fail "$marker_path")" \
    "$(metric gpu_upload_fail_capacity "$marker_path")" \
    "$(metric gpu_upload_fail_fragmented "$marker_path")" \
    "$(metric gpu_free_ranges "$marker_path")" \
    "$(metric gpu_largest_free "$marker_path")" \
    "$(metric gpu_draw_rebuilds "$marker_path")" \
    "$(perf_float gpu_draw_rebuild_ms "$marker_path")" \
    "$(metric gpu_draw_patches "$marker_path")" \
    "$(perf_float gpu_draw_patch_ms "$marker_path")" \
    "$(metric terrain_samples "$marker_path")"
}

terrain_work_line() {
  label="$1"
  marker_path="$2"
  budget_ms="$3"
  mesh_avg="$(default_float "$(mesh_triplet_value "$marker_path" 2)")"
  mesh_max="$(default_float "$(mesh_triplet_value "$marker_path" 3)")"
  coll_avg="$(default_float "$(collision_triplet_value "$marker_path" 2)")"
  coll_max="$(default_float "$(collision_triplet_value "$marker_path" 3)")"
  draw_rebuild_avg="$(default_float "$(perf_triplet_value gpu_draw_rebuild_ms "$marker_path" 2)")"
  draw_rebuild_max="$(default_float "$(perf_triplet_value gpu_draw_rebuild_ms "$marker_path" 3)")"
  draw_patch_avg="$(default_float "$(perf_triplet_value gpu_draw_patch_ms "$marker_path" 2)")"
  draw_patch_max="$(default_float "$(perf_triplet_value gpu_draw_patch_ms "$marker_path" 3)")"
  refresh_hz="$(default_float "$(float_metric screen_refresh_hz "$marker_path")")"
  awk \
    -v label="$label" \
    -v mesh_avg="$mesh_avg" \
    -v mesh_max="$mesh_max" \
    -v coll_avg="$coll_avg" \
    -v coll_max="$coll_max" \
    -v draw_rebuild_avg="$draw_rebuild_avg" \
    -v draw_rebuild_max="$draw_rebuild_max" \
    -v draw_patch_avg="$draw_patch_avg" \
    -v draw_patch_max="$draw_patch_max" \
    -v refresh_hz="$refresh_hz" \
    -v budget="$budget_ms" '
      BEGIN {
        avg = mesh_avg + coll_avg + draw_rebuild_avg + draw_patch_avg
        max = mesh_max + coll_max + draw_rebuild_max + draw_patch_max
        fps = 0.0
        if (avg > 0.0) {
          fps = 1000.0 / avg
        }
        status = "pass"
        over = avg - budget
        if (over > 0.0) {
          status = "fail"
        }
        printf("%s_terrain_work refresh_independent=1 avg_ms=%.3f max_ms=%.3f capacity_avg_fps=%.1f budget_status=%s budget_ms=%.3f over_ms=%.3f mesh_avg_ms=%.3f coll_avg_ms=%.3f draw_rebuild_avg_ms=%.3f draw_patch_avg_ms=%.3f screen_refresh_hz=%.3f\n", label, avg, max, fps, status, budget, over, mesh_avg, coll_avg, draw_rebuild_avg, draw_patch_avg, refresh_hz)
      }
    '
}

print_budget_status() {
  label="$1"
  marker_path="$2"
  budget_ms="$3"
  p95_ms="$(float_metric frame_p95_ms "$marker_path")"
  fps_p05="$(float_metric fps_p05 "$marker_path")"
  test -n "$p95_ms" || fail "missing frame_p95_ms in $marker_path"
  awk -v label="$label" -v p95="$p95_ms" -v fps_p05="$fps_p05" -v budget="$budget_ms" '
    BEGIN {
      status = "pass"
      over = p95 - budget
      if (over > 0.0) {
        status = "fail"
      }
      printf("%s_budget_status=%s frame_p95_ms=%.3f budget_ms=%.3f over_ms=%.3f fps_p05=%.1f\n", label, status, p95, budget, over, fps_p05)
    }
  '
}

enforce_budget() {
  label="$1"
  marker_path="$2"
  budget_ms="$3"
  p95_ms="$(float_metric frame_p95_ms "$marker_path")"
  test -n "$p95_ms" || fail "missing frame_p95_ms in $marker_path"
  awk -v label="$label" -v p95="$p95_ms" -v budget="$budget_ms" '
    BEGIN {
      if (p95 > budget) {
        printf("gpu_terrain_perf_baseline: %s frame_p95_ms %.3f exceeds %.3f\n", label, p95, budget) > "/dev/stderr"
        exit 1
      }
    }
  '
}

if [ "$CAPTURE" = "1" ]; then
  prepare_godot_rust_ext_profile "$ROOT_DIR"
  run_case cpu-arraymesh-baseline 0
  run_case gpu-terrain-baseline 1
fi

cpu_marker="$OUT_DIR/cpu-arraymesh-baseline.png.txt"
gpu_marker="$OUT_DIR/gpu-terrain-baseline.png.txt"
require_marker "$cpu_marker"
require_marker "$gpu_marker"

echo
echo "GPU terrain perf baseline summary:"
print_row cpu "$cpu_marker"
print_row gpu "$gpu_marker"

budget_ms="$(frame_budget_ms)"
summary_path="$OUT_DIR/perf-baseline-summary.txt"
{
  printf 'GPU terrain refresh-independent work summary target_fps=%s budget_ms=%s\n' "$TARGET_FPS" "$budget_ms"
  terrain_work_line cpu "$cpu_marker" "$budget_ms"
  terrain_work_line gpu "$gpu_marker" "$budget_ms"
} | tee "$summary_path"

print_budget_status cpu "$cpu_marker" "$budget_ms"
print_budget_status gpu "$gpu_marker" "$budget_ms"
case "$BUDGET_MODE" in
  report|"") ;;
  enforce)
    enforce_budget cpu "$cpu_marker" "$budget_ms"
    enforce_budget gpu "$gpu_marker" "$budget_ms"
    ;;
  *)
    fail "unsupported RUMPELMC_PERF_BASELINE_BUDGET_MODE=$BUDGET_MODE"
    ;;
esac

cpu_p95="$(float_metric frame_p95_ms "$cpu_marker")"
gpu_p95="$(float_metric frame_p95_ms "$gpu_marker")"
if [ -n "$cpu_p95" ] && [ -n "$gpu_p95" ]; then
  awk -v cpu="$cpu_p95" -v gpu="$gpu_p95" '
    BEGIN {
      delta = cpu - gpu
      pct = 0.0
      if (cpu > 0.0) {
        pct = delta * 100.0 / cpu
      }
      printf("frame_p95_delta_ms=%.3f frame_p95_delta_pct=%.1f%%\n", delta, pct)
    }
  '
fi
