#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/gpu_terrain_workload_matrix"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

TARGET_FPS="${RUMPELMC_WORKLOAD_MATRIX_TARGET_FPS:-150}"
MAX_RESIDENT_SETTLE_SEC="${RUMPELMC_WORKLOAD_MATRIX_MAX_RESIDENT_SETTLE_SEC:-30.0}"
EXTENDED_SETTLE_SEC="${RUMPELMC_WORKLOAD_MATRIX_EXTENDED_SETTLE_SEC:-45.0}"
SERVER_CHUNKS_PER_UPDATE="${RUMPELMC_WORKLOAD_MATRIX_SERVER_CHUNKS_PER_UPDATE:-64}"
REPEAT_COUNT="${RUMPELMC_WORKLOAD_MATRIX_REPEAT_COUNT:-1}"
SMOKE_DELAY_SEC="${RUMPELMC_WORKLOAD_MATRIX_SMOKE_DELAY_SEC:-5.0}"
CASE_SET="${RUMPELMC_WORKLOAD_MATRIX_CASE_SET:-standard}"
if [ "$CASE_SET" = "heavy" ]; then
  SERVER_VIEW_DISTANCE="${RUMPELMC_WORKLOAD_MATRIX_SERVER_VIEW_DISTANCE:-12}"
  CLIENT_KEEP_CHUNK_DISTANCE="${RUMPELMC_WORKLOAD_MATRIX_CLIENT_KEEP_CHUNK_DISTANCE:-$SERVER_VIEW_DISTANCE}"
else
  SERVER_VIEW_DISTANCE="${RUMPELMC_WORKLOAD_MATRIX_SERVER_VIEW_DISTANCE:-}"
  CLIENT_KEEP_CHUNK_DISTANCE="${RUMPELMC_WORKLOAD_MATRIX_CLIENT_KEEP_CHUNK_DISTANCE:-}"
fi

mkdir -p "$OUT_DIR"

fail() {
  echo "gpu_terrain_workload_matrix: $*" >&2
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

case_summary_float() {
  label="$1"
  key="$2"
  summary_path="$3"
  sed -n "/^$label /s/.*$key=\([0-9][0-9]*\.[0-9][0-9]*\).*/\1/p" "$summary_path" | sed -n '1p'
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

matrix_labels() {
  printf 'short\nlong\nlong-filled\nmax-resident\n'
  if [ "$CASE_SET" = "heavy" ]; then
    printf 'extended\nextended-filled\n'
  fi
}

run_case() {
  label="$1"
  motion="$2"
  expected_chunk="$3"
  min_chunks="$4"
  step_sec="$5"
  settle_sec="$6"
  case_dir="$OUT_DIR/$label"

  rm -rf "$case_dir"
  mkdir -p "$case_dir"
  echo "==> GPU terrain workload matrix: $label motion=$motion"
  RUMPELMC_MOVEMENT_STRESS_MOTION="$motion" \
    RUMPELMC_MOVEMENT_STRESS_EXPECTED_CHUNK="$expected_chunk" \
    RUMPELMC_MOVEMENT_STRESS_MIN_CHUNKS="$min_chunks" \
    RUMPELMC_MOVEMENT_STRESS_STEP_SEC="$step_sec" \
    RUMPELMC_MOVEMENT_STRESS_SETTLE_SEC="$settle_sec" \
    RUMPELMC_MOVEMENT_STRESS_TARGET_FPS="$TARGET_FPS" \
    RUMPELMC_SERVER_VIEW_DISTANCE="$SERVER_VIEW_DISTANCE" \
	    RUMPELMC_SERVER_CHUNKS_PER_UPDATE="$SERVER_CHUNKS_PER_UPDATE" \
	    RUMPELMC_CLIENT_KEEP_CHUNK_DISTANCE="$CLIENT_KEEP_CHUNK_DISTANCE" \
	    SMOKE_DELAY_SEC="$SMOKE_DELAY_SEC" \
	    /bin/sh "$ROOT_DIR/scripts/gpu_terrain_movement_stress.sh" "$case_dir" > "$case_dir/run.log" 2>&1
}

summary_line() {
  label="$1"
  marker_path="$2"
  summary_path="$3"
  run_log_path="$4"

  test -s "$marker_path" || fail "missing marker $marker_path"
  test -s "$summary_path" || fail "missing summary $summary_path"

  motion_steps="$(metric motion_steps "$marker_path")"
  motion_chunks="$(metric motion_chunks "$marker_path")"
  gpu_subchunks="$(metric gpu_subchunks "$marker_path")"
  gpu_draws="$(metric gpu_draws "$marker_path")"
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
  gpu_push_constant_updates="$(metric gpu_push_constant_updates "$marker_path")"
  gpu_push_constant_total_bytes="$(metric gpu_push_constant_total_bytes "$marker_path")"
  gpu_push_constant_avg_bytes="$(default_float "$(float_metric gpu_push_constant_avg_bytes "$marker_path")")"
  gpu_push_constant_camera_bytes="$(metric gpu_push_constant_camera_bytes "$marker_path")"
  gpu_push_constant_lighting_bytes="$(metric gpu_push_constant_lighting_bytes "$marker_path")"
  gpu_push_constant_atlas_bytes="$(metric gpu_push_constant_atlas_bytes "$marker_path")"
  gpu_faces="$(metric gpu_faces "$marker_path")"
  cpu_proxy="$(metric cpu_proxy "$marker_path")"
  gpu_upload_fail="$(metric gpu_upload_fail "$marker_path")"
  gpu_upload_fail_capacity="$(metric gpu_upload_fail_capacity "$marker_path")"
  gpu_upload_fail_fragmented="$(metric gpu_upload_fail_fragmented "$marker_path")"
  gpu_free_ranges="$(metric gpu_free_ranges "$marker_path")"
  gpu_free_faces="$(metric gpu_free_faces "$marker_path")"
  gpu_largest_free="$(metric gpu_largest_free "$marker_path")"
  gpu_fragmented_free_faces="$(metric gpu_fragmented_free_faces "$marker_path")"
  gpu_fragmentation_pct="$(default_float "$(float_metric gpu_fragmentation_pct "$marker_path")")"
  terrain_samples="$(metric terrain_samples "$marker_path")"
  queue_avg="$(default_float "$(perf_triplet_value terrain_queue_work_ms "$marker_path" 2)")"
  queue_max="$(default_float "$(perf_triplet_value terrain_queue_work_ms "$marker_path" 3)")"
  process_wall_p95="$(default_float "$(float_metric process_wall_p95_ms "$marker_path")")"
  compositor_submit_avg="$(default_float "$(perf_triplet_value gpu_compositor_submit_ms "$marker_path" 2)")"
  compositor_submit_max="$(default_float "$(perf_triplet_value gpu_compositor_submit_ms "$marker_path" 3)")"
  compositor_submit_max_setup="$(default_float "$(perf_quad_value gpu_compositor_submit_max_parts "$marker_path" 1)")"
  compositor_submit_max_target="$(default_float "$(perf_quad_value gpu_compositor_submit_max_parts "$marker_path" 2)")"
  compositor_submit_max_constants="$(default_float "$(perf_quad_value gpu_compositor_submit_max_parts "$marker_path" 3)")"
  compositor_submit_max_draw="$(default_float "$(perf_quad_value gpu_compositor_submit_max_parts "$marker_path" 4)")"
  compositor_gpu_samples="$(metric gpu_compositor_gpu_samples "$marker_path")"
  compositor_gpu_us_max="$(default_float "$(perf_triplet_value gpu_compositor_gpu_us "$marker_path" 3)")"
  frame_p95="$(default_float "$(float_metric frame_p95_ms "$marker_path")")"
  fps_p05="$(default_float "$(float_metric fps_p05 "$marker_path")")"
  server_reused=0
  if grep -q "Go server is already running" "$run_log_path"; then
    server_reused=1
  fi

  awk \
    -v label="$label" \
    -v server_reused="$server_reused" \
    -v motion_steps="${motion_steps:-0}" \
    -v motion_chunks="${motion_chunks:-0}" \
    -v gpu_subchunks="${gpu_subchunks:-0}" \
    -v gpu_draws="${gpu_draws:-0}" \
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
    -v gpu_push_constant_updates="${gpu_push_constant_updates:-0}" \
    -v gpu_push_constant_total_bytes="${gpu_push_constant_total_bytes:-0}" \
    -v gpu_push_constant_avg_bytes="$gpu_push_constant_avg_bytes" \
    -v gpu_push_constant_camera_bytes="${gpu_push_constant_camera_bytes:-0}" \
    -v gpu_push_constant_lighting_bytes="${gpu_push_constant_lighting_bytes:-0}" \
    -v gpu_push_constant_atlas_bytes="${gpu_push_constant_atlas_bytes:-0}" \
    -v gpu_faces="${gpu_faces:-0}" \
    -v cpu_proxy="${cpu_proxy:-0}" \
    -v gpu_upload_fail="${gpu_upload_fail:-0}" \
    -v gpu_upload_fail_capacity="${gpu_upload_fail_capacity:-0}" \
    -v gpu_upload_fail_fragmented="${gpu_upload_fail_fragmented:-0}" \
    -v gpu_free_ranges="${gpu_free_ranges:-0}" \
    -v gpu_free_faces="${gpu_free_faces:-0}" \
    -v gpu_largest_free="${gpu_largest_free:-0}" \
    -v gpu_fragmented_free_faces="${gpu_fragmented_free_faces:-0}" \
    -v gpu_fragmentation_pct="$gpu_fragmentation_pct" \
    -v terrain_samples="${terrain_samples:-0}" \
    -v queue_avg="$queue_avg" \
    -v queue_max="$queue_max" \
    -v process_wall_p95="$process_wall_p95" \
    -v compositor_submit_avg="$compositor_submit_avg" \
    -v compositor_submit_max="$compositor_submit_max" \
    -v compositor_submit_max_setup="$compositor_submit_max_setup" \
    -v compositor_submit_max_target="$compositor_submit_max_target" \
    -v compositor_submit_max_constants="$compositor_submit_max_constants" \
    -v compositor_submit_max_draw="$compositor_submit_max_draw" \
    -v compositor_gpu_samples="${compositor_gpu_samples:-0}" \
    -v compositor_gpu_us_max="$compositor_gpu_us_max" \
    -v frame_p95="$frame_p95" \
    -v fps_p05="$fps_p05" '
      BEGIN {
        printf("%s server_reused=%d motion_steps=%d motion_chunks=%d gpu_subchunks=%d gpu_draws=%d gpu_draw_cmd_bytes=%d gpu_draw_cmd_capacity_bytes=%d gpu_draw_cmd_stride=%d gpu_scene_target_create=%d gpu_scene_target_reuse=%d gpu_scene_target_replace=%d gpu_uniform_set_create=%d gpu_atlas_texture_create=%d gpu_atlas_sampler_create=%d gpu_push_constant_bytes=%d gpu_push_constant_updates=%d gpu_push_constant_total_bytes=%d gpu_push_constant_avg_bytes=%.1f gpu_push_constant_camera_bytes=%d gpu_push_constant_lighting_bytes=%d gpu_push_constant_atlas_bytes=%d gpu_faces=%d cpu_proxy=%d gpu_upload_fail=%d gpu_upload_fail_capacity=%d gpu_upload_fail_fragmented=%d gpu_free_ranges=%d gpu_free_faces=%d gpu_largest_free=%d gpu_fragmented_free_faces=%d gpu_fragmentation_pct=%.1f terrain_samples=%d terrain_queue_avg_ms=%.3f terrain_queue_max_ms=%.3f process_wall_p95_ms=%.3f gpu_compositor_submit_avg_ms=%.3f gpu_compositor_submit_max_ms=%.3f gpu_compositor_submit_max_parts_ms=%.3f/%.3f/%.3f/%.3f gpu_compositor_gpu_samples=%d gpu_compositor_gpu_max_us=%.1f frame_p95_ms=%.3f fps_p05=%.1f\n", label, server_reused, motion_steps, motion_chunks, gpu_subchunks, gpu_draws, gpu_draw_cmd_bytes, gpu_draw_cmd_capacity_bytes, gpu_draw_cmd_stride, gpu_scene_target_create, gpu_scene_target_reuse, gpu_scene_target_replace, gpu_uniform_set_create, gpu_atlas_texture_create, gpu_atlas_sampler_create, gpu_push_constant_bytes, gpu_push_constant_updates, gpu_push_constant_total_bytes, gpu_push_constant_avg_bytes, gpu_push_constant_camera_bytes, gpu_push_constant_lighting_bytes, gpu_push_constant_atlas_bytes, gpu_faces, cpu_proxy, gpu_upload_fail, gpu_upload_fail_capacity, gpu_upload_fail_fragmented, gpu_free_ranges, gpu_free_faces, gpu_largest_free, gpu_fragmented_free_faces, gpu_fragmentation_pct, terrain_samples, queue_avg, queue_max, process_wall_p95, compositor_submit_avg, compositor_submit_max, compositor_submit_max_setup, compositor_submit_max_target, compositor_submit_max_constants, compositor_submit_max_draw, compositor_gpu_samples, compositor_gpu_us_max, frame_p95, fps_p05)
      }
    '
}

repeat_metric_line() {
  label="$1"
  key="$2"
  shift 2

  values=""
  for summary_path in "$@"; do
    value="$(case_summary_float "$label" "$key" "$summary_path")"
    if [ -n "$value" ]; then
      values="$values $value"
    fi
  done
  test -n "$values" || return

  # shellcheck disable=SC2086
  awk -v label="$label" -v key="$key" '
    BEGIN {
      count = 0
      min = 0.0
      max = 0.0
      sum = 0.0
      for (i = 1; i < ARGC; i++) {
        value = ARGV[i] + 0.0
        ARGV[i] = ""
        if (count == 0 || value < min) {
          min = value
        }
        if (count == 0 || value > max) {
          max = value
        }
        sum += value
        count++
      }
      if (count > 0) {
        printf("%s_%s count=%d min=%.3f avg=%.3f max=%.3f\n", label, key, count, min, sum / count, max)
      }
    }
  ' $values
}

case "$REPEAT_COUNT" in
  ''|*[!0-9]*)
    fail "RUMPELMC_WORKLOAD_MATRIX_REPEAT_COUNT must be a positive integer"
    ;;
esac
case "$CASE_SET" in
  standard|heavy) ;;
  *)
    fail "RUMPELMC_WORKLOAD_MATRIX_CASE_SET must be standard or heavy"
    ;;
esac
if [ "$REPEAT_COUNT" -le 0 ]; then
  fail "RUMPELMC_WORKLOAD_MATRIX_REPEAT_COUNT must be greater than 0"
fi
if [ "$REPEAT_COUNT" -gt 1 ]; then
  run_index=1
  while [ "$run_index" -le "$REPEAT_COUNT" ]; do
    run_dir="$OUT_DIR/run-$run_index"
    rm -rf "$run_dir"
    RUMPELMC_WORKLOAD_MATRIX_REPEAT_COUNT=1 "$0" "$run_dir"
    run_index=$((run_index + 1))
  done

  repeat_summary_path="$OUT_DIR/workload-repeat-summary.txt"
  {
    printf 'GPU terrain workload repeat summary repeats=%s target_fps=%s server_view_distance=%s client_keep_distance=%s server_chunks_per_update=%s case_set=%s\n' "$REPEAT_COUNT" "$TARGET_FPS" "${SERVER_VIEW_DISTANCE:-default}" "${CLIENT_KEEP_CHUNK_DISTANCE:-default}" "$SERVER_CHUNKS_PER_UPDATE" "$CASE_SET"
    for label in $(matrix_labels); do
      repeat_metric_line "$label" gpu_compositor_submit_max_ms "$OUT_DIR"/run-*/workload-matrix-summary.txt
      repeat_metric_line "$label" terrain_queue_max_ms "$OUT_DIR"/run-*/workload-matrix-summary.txt
      repeat_metric_line "$label" process_wall_p95_ms "$OUT_DIR"/run-*/workload-matrix-summary.txt
    done
  } | tee "$repeat_summary_path"

  echo "GPU terrain workload repeat artifacts: $OUT_DIR"
  exit 0
fi

run_case short chunk_walk 3,2 4 0.55 4.0
run_case long chunk_walk_long 7,5 8 0.55 4.0
run_case long-filled chunk_walk_long 7,5 8 0.55 12.0
run_case max-resident chunk_walk_long 7,5 8 0.55 "$MAX_RESIDENT_SETTLE_SEC"
if [ "$CASE_SET" = "heavy" ]; then
  run_case extended chunk_walk_extended 11,8 12 0.55 8.0
  run_case extended-filled chunk_walk_extended 11,8 12 0.55 "$EXTENDED_SETTLE_SEC"
fi

summary_path="$OUT_DIR/workload-matrix-summary.txt"
{
  printf 'GPU terrain workload matrix target_fps=%s server_view_distance=%s client_keep_distance=%s server_chunks_per_update=%s case_set=%s\n' "$TARGET_FPS" "${SERVER_VIEW_DISTANCE:-default}" "${CLIENT_KEEP_CHUNK_DISTANCE:-default}" "$SERVER_CHUNKS_PER_UPDATE" "$CASE_SET"
  summary_line short "$OUT_DIR/short/gpu-terrain-movement-stress.png.txt" "$OUT_DIR/short/movement-stress-summary.txt" "$OUT_DIR/short/run.log"
  summary_line long "$OUT_DIR/long/gpu-terrain-movement-stress.png.txt" "$OUT_DIR/long/movement-stress-summary.txt" "$OUT_DIR/long/run.log"
  summary_line long-filled "$OUT_DIR/long-filled/gpu-terrain-movement-stress.png.txt" "$OUT_DIR/long-filled/movement-stress-summary.txt" "$OUT_DIR/long-filled/run.log"
  summary_line max-resident "$OUT_DIR/max-resident/gpu-terrain-movement-stress.png.txt" "$OUT_DIR/max-resident/movement-stress-summary.txt" "$OUT_DIR/max-resident/run.log"
  if [ "$CASE_SET" = "heavy" ]; then
    summary_line extended "$OUT_DIR/extended/gpu-terrain-movement-stress.png.txt" "$OUT_DIR/extended/movement-stress-summary.txt" "$OUT_DIR/extended/run.log"
    summary_line extended-filled "$OUT_DIR/extended-filled/gpu-terrain-movement-stress.png.txt" "$OUT_DIR/extended-filled/movement-stress-summary.txt" "$OUT_DIR/extended-filled/run.log"
  fi
} | tee "$summary_path"

echo "GPU terrain workload matrix artifacts: $OUT_DIR"
