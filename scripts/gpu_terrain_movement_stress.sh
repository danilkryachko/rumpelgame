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
GODOT_QUIT_AFTER_FRAMES="${GODOT_QUIT_AFTER_FRAMES:-30000}"
SMOKE_DELAY_SEC="${SMOKE_DELAY_SEC:-5.0}"
FRAME_SAMPLE_SEC="${RUMPELMC_MOVEMENT_STRESS_FRAME_SAMPLE_SEC:-5.0}"
SMOKE_POSE="${RUMPELMC_VISUAL_SMOKE_POSE:-}"
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

require_positive_float() {
  key="$1"
  value="$2"
  test -n "$value" || fail "missing $key in $marker_path"
  awk -v key="$key" -v value="$value" '
    BEGIN {
      if (value <= 0.0) {
        printf("gpu_terrain_movement_stress: %s %.3f must be positive\n", key, value) > "/dev/stderr"
        exit 1
      }
    }
  '
}

require_startup_timing_order() {
  packet_ms="$1"
  chunk_inserted_ms="$2"
  chunk_loaded_ms="$3"
  mesh_queued_ms="$4"
  mesh_dispatched_ms="$5"
  first_mesh_ms="$6"
  collision_ms="$7"
  player_spawn_ms="$8"
  awk \
    -v packet_ms="$packet_ms" \
    -v chunk_inserted_ms="$chunk_inserted_ms" \
    -v chunk_loaded_ms="$chunk_loaded_ms" \
    -v mesh_queued_ms="$mesh_queued_ms" \
    -v mesh_dispatched_ms="$mesh_dispatched_ms" \
    -v first_mesh_ms="$first_mesh_ms" \
    -v collision_ms="$collision_ms" \
    -v player_spawn_ms="$player_spawn_ms" '
    BEGIN {
      if (packet_ms > chunk_inserted_ms || chunk_inserted_ms > chunk_loaded_ms || chunk_loaded_ms > mesh_queued_ms || mesh_queued_ms > mesh_dispatched_ms || mesh_dispatched_ms > first_mesh_ms || first_mesh_ms > collision_ms || collision_ms > player_spawn_ms) {
        printf("gpu_terrain_movement_stress: startup timings out of order packet_ms=%.3f chunk_inserted_ms=%.3f chunk_loaded_ms=%.3f mesh_queued_ms=%.3f mesh_dispatched_ms=%.3f first_mesh_ms=%.3f collision_ms=%.3f player_spawn_ms=%.3f\n", packet_ms, chunk_inserted_ms, chunk_loaded_ms, mesh_queued_ms, mesh_dispatched_ms, first_mesh_ms, collision_ms, player_spawn_ms) > "/dev/stderr"
        exit 1
      }
    }
  '
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
  gpu_push_constant_updates="$(metric gpu_push_constant_updates "$marker_path")"
  gpu_push_constant_total_bytes="$(metric gpu_push_constant_total_bytes "$marker_path")"
  gpu_push_constant_avg_bytes="$(default_float "$(float_metric gpu_push_constant_avg_bytes "$marker_path")")"
  gpu_push_constant_camera_bytes="$(metric gpu_push_constant_camera_bytes "$marker_path")"
  gpu_push_constant_lighting_bytes="$(metric gpu_push_constant_lighting_bytes "$marker_path")"
  gpu_push_constant_atlas_bytes="$(metric gpu_push_constant_atlas_bytes "$marker_path")"
  gpu_light_dir="$(text_metric gpu_light_dir "$marker_path")"
  gpu_light_color="$(text_metric gpu_light_color "$marker_path")"
  gpu_light_energy="$(float_metric gpu_light_energy "$marker_path")"
  gpu_light_ambient="$(float_metric gpu_light_ambient "$marker_path")"
  native_shadow_requested="$(metric native_shadow_requested "$marker_path")"
  native_shadow_active="$(metric native_shadow_active "$marker_path")"
  native_shadow_fallback="$(metric native_shadow_fallback "$marker_path")"
  native_shadow_implemented="$(metric native_shadow_implemented "$marker_path")"
  native_shadow_resource_status="$(text_metric native_shadow_resource_status "$marker_path")"
  native_shadow_resource_width="$(metric native_shadow_resource_width "$marker_path")"
  native_shadow_resource_height="$(metric native_shadow_resource_height "$marker_path")"
  native_shadow_resource_layers="$(metric native_shadow_resource_layers "$marker_path")"
  native_shadow_resource_bytes_per_texel="$(metric native_shadow_resource_bytes_per_texel "$marker_path")"
  native_shadow_resource_bytes="$(metric native_shadow_resource_bytes "$marker_path")"
  native_shadow_resource_format="$(text_metric native_shadow_resource_format "$marker_path")"
  native_shadow_resource_usage="$(text_metric native_shadow_resource_usage "$marker_path")"
  native_shadow_pass_load_op="$(text_metric native_shadow_pass_load_op "$marker_path")"
  native_shadow_pass_store_op="$(text_metric native_shadow_pass_store_op "$marker_path")"
  native_shadow_pass_clear_depth_milli="$(metric native_shadow_pass_clear_depth_milli "$marker_path")"
  native_shadow_sampler_filter="$(text_metric native_shadow_sampler_filter "$marker_path")"
  native_shadow_sampler_address="$(text_metric native_shadow_sampler_address "$marker_path")"
  native_shadow_sampler_compare_op="$(text_metric native_shadow_sampler_compare_op "$marker_path")"
  native_shadow_sampler_compare_enabled="$(metric native_shadow_sampler_compare_enabled "$marker_path")"
  native_shadow_depth_bias_constant_milli="$(metric native_shadow_depth_bias_constant_milli "$marker_path")"
  native_shadow_depth_bias_slope_milli="$(metric native_shadow_depth_bias_slope_milli "$marker_path")"
  native_shadow_depth_bias_clamp_milli="$(metric native_shadow_depth_bias_clamp_milli "$marker_path")"
  native_shadow_viewport_x_px="$(metric native_shadow_viewport_x_px "$marker_path")"
  native_shadow_viewport_y_px="$(metric native_shadow_viewport_y_px "$marker_path")"
  native_shadow_viewport_width_px="$(metric native_shadow_viewport_width_px "$marker_path")"
  native_shadow_viewport_height_px="$(metric native_shadow_viewport_height_px "$marker_path")"
  native_shadow_viewport_min_depth_milli="$(metric native_shadow_viewport_min_depth_milli "$marker_path")"
  native_shadow_viewport_max_depth_milli="$(metric native_shadow_viewport_max_depth_milli "$marker_path")"
  native_shadow_pipeline_depth_test_enabled="$(metric native_shadow_pipeline_depth_test_enabled "$marker_path")"
  native_shadow_pipeline_depth_write_enabled="$(metric native_shadow_pipeline_depth_write_enabled "$marker_path")"
  native_shadow_pipeline_cull_mode="$(text_metric native_shadow_pipeline_cull_mode "$marker_path")"
  native_shadow_pipeline_front_face="$(text_metric native_shadow_pipeline_front_face "$marker_path")"
  native_shadow_draw_source="$(text_metric native_shadow_draw_source "$marker_path")"
  native_shadow_draw_primitive="$(text_metric native_shadow_draw_primitive "$marker_path")"
  native_shadow_draw_face_stride_bytes="$(metric native_shadow_draw_face_stride_bytes "$marker_path")"
  native_shadow_draw_command_stride_bytes="$(metric native_shadow_draw_command_stride_bytes "$marker_path")"
  native_shadow_draw_indirect_enabled="$(metric native_shadow_draw_indirect_enabled "$marker_path")"
  native_shadow_uniform_set_index="$(metric native_shadow_uniform_set_index "$marker_path")"
  native_shadow_face_buffer_binding="$(metric native_shadow_face_buffer_binding "$marker_path")"
  native_shadow_push_constant_bytes="$(metric native_shadow_push_constant_bytes "$marker_path")"
  native_shadow_texture_sampling_enabled="$(metric native_shadow_texture_sampling_enabled "$marker_path")"
  native_shadow_resource_creates="$(metric native_shadow_resource_creates "$marker_path")"
  native_shadow_resource_reuses="$(metric native_shadow_resource_reuses "$marker_path")"
  native_shadow_resource_replaces="$(metric native_shadow_resource_replaces "$marker_path")"
  native_shadow_resource_releases="$(metric native_shadow_resource_releases "$marker_path")"
  native_shadow_covered_chunks="$(metric native_shadow_covered_chunks "$marker_path")"
  native_shadow_covered_subchunks="$(metric native_shadow_covered_subchunks "$marker_path")"
  smoke_pose="$(text_metric pose "$marker_path")"
  lighting_variant="$(text_metric lighting_variant "$marker_path")"
  gpu_cull="$(text_metric gpu_cull "$marker_path")"
  gpu_front_face="$(text_metric gpu_front_face "$marker_path")"
  startup_chunk_packet_ms="$(float_metric startup_chunk_packet_ms "$marker_path")"
  startup_packet_read_work_ms="$(float_metric startup_packet_read_work_ms "$marker_path")"
  startup_packet_decode_work_ms="$(float_metric startup_packet_decode_work_ms "$marker_path")"
  startup_packet_reader_elapsed_ms="$(float_metric startup_packet_reader_elapsed_ms "$marker_path")"
  startup_packet_queue_lag_ms="$(float_metric startup_packet_queue_lag_ms "$marker_path")"
  startup_chunk_decode_work_ms="$(float_metric startup_chunk_decode_work_ms "$marker_path")"
  startup_chunk_inserted_ms="$(float_metric startup_chunk_inserted_ms "$marker_path")"
  startup_chunk_loaded_ms="$(float_metric startup_chunk_loaded_ms "$marker_path")"
  startup_mesh_queued_ms="$(float_metric startup_mesh_queued_ms "$marker_path")"
  startup_mesh_dispatched_ms="$(float_metric startup_mesh_dispatched_ms "$marker_path")"
  startup_first_mesh_ms="$(float_metric startup_first_mesh_ms "$marker_path")"
  startup_first_mesh_work_ms="$(float_metric startup_first_mesh_work_ms "$marker_path")"
  startup_first_mesh_phase_ms="$(text_metric startup_first_mesh_phase_ms "$marker_path")"
  startup_first_mesh_collision_work_ms="$(float_metric startup_first_mesh_collision_work_ms "$marker_path")"
  startup_collision_ms="$(float_metric startup_collision_ms "$marker_path")"
  startup_player_spawn_ms="$(float_metric startup_player_spawn_ms "$marker_path")"
  frame_p95="$(float_metric frame_p95_ms "$marker_path")"
  fps_p05="$(float_metric fps_p05 "$marker_path")"
  process_wall_p95="$(float_metric process_wall_p95_ms "$marker_path")"
  test -n "$terrain_queue_avg" || fail "missing terrain_queue_work_ms in $marker_path"
  test -n "$mesh_avg" || fail "missing mesh triplet in $marker_path"
  test -n "$coll_avg" || fail "missing coll triplet in $marker_path"
  test -n "$process_wall_p95" || fail "missing process_wall_p95_ms in $marker_path"
  test -n "$gpu_light_dir" || fail "missing gpu_light_dir in $marker_path"
  test -n "$gpu_light_color" || fail "missing gpu_light_color in $marker_path"
  test -n "$gpu_light_energy" || fail "missing gpu_light_energy in $marker_path"
  test -n "$gpu_light_ambient" || fail "missing gpu_light_ambient in $marker_path"
  test -n "$native_shadow_resource_status" || fail "missing native_shadow_resource_status in $marker_path"
  test -n "$native_shadow_resource_width" || fail "missing native_shadow_resource_width in $marker_path"
  test -n "$native_shadow_resource_height" || fail "missing native_shadow_resource_height in $marker_path"
  test -n "$native_shadow_resource_layers" || fail "missing native_shadow_resource_layers in $marker_path"
  test -n "$native_shadow_resource_bytes_per_texel" || fail "missing native_shadow_resource_bytes_per_texel in $marker_path"
  test -n "$native_shadow_resource_bytes" || fail "missing native_shadow_resource_bytes in $marker_path"
  test -n "$native_shadow_resource_format" || fail "missing native_shadow_resource_format in $marker_path"
  test -n "$native_shadow_resource_usage" || fail "missing native_shadow_resource_usage in $marker_path"
  test -n "$native_shadow_pass_load_op" || fail "missing native_shadow_pass_load_op in $marker_path"
  test -n "$native_shadow_pass_store_op" || fail "missing native_shadow_pass_store_op in $marker_path"
  test -n "$native_shadow_pass_clear_depth_milli" || fail "missing native_shadow_pass_clear_depth_milli in $marker_path"
  test -n "$native_shadow_sampler_filter" || fail "missing native_shadow_sampler_filter in $marker_path"
  test -n "$native_shadow_sampler_address" || fail "missing native_shadow_sampler_address in $marker_path"
  test -n "$native_shadow_sampler_compare_op" || fail "missing native_shadow_sampler_compare_op in $marker_path"
  test -n "$native_shadow_sampler_compare_enabled" || fail "missing native_shadow_sampler_compare_enabled in $marker_path"
  test -n "$native_shadow_depth_bias_constant_milli" || fail "missing native_shadow_depth_bias_constant_milli in $marker_path"
  test -n "$native_shadow_depth_bias_slope_milli" || fail "missing native_shadow_depth_bias_slope_milli in $marker_path"
  test -n "$native_shadow_depth_bias_clamp_milli" || fail "missing native_shadow_depth_bias_clamp_milli in $marker_path"
  test -n "$native_shadow_viewport_x_px" || fail "missing native_shadow_viewport_x_px in $marker_path"
  test -n "$native_shadow_viewport_y_px" || fail "missing native_shadow_viewport_y_px in $marker_path"
  test -n "$native_shadow_viewport_width_px" || fail "missing native_shadow_viewport_width_px in $marker_path"
  test -n "$native_shadow_viewport_height_px" || fail "missing native_shadow_viewport_height_px in $marker_path"
  test -n "$native_shadow_viewport_min_depth_milli" || fail "missing native_shadow_viewport_min_depth_milli in $marker_path"
  test -n "$native_shadow_viewport_max_depth_milli" || fail "missing native_shadow_viewport_max_depth_milli in $marker_path"
  test -n "$native_shadow_pipeline_depth_test_enabled" || fail "missing native_shadow_pipeline_depth_test_enabled in $marker_path"
  test -n "$native_shadow_pipeline_depth_write_enabled" || fail "missing native_shadow_pipeline_depth_write_enabled in $marker_path"
  test -n "$native_shadow_pipeline_cull_mode" || fail "missing native_shadow_pipeline_cull_mode in $marker_path"
  test -n "$native_shadow_pipeline_front_face" || fail "missing native_shadow_pipeline_front_face in $marker_path"
  test -n "$native_shadow_draw_source" || fail "missing native_shadow_draw_source in $marker_path"
  test -n "$native_shadow_draw_primitive" || fail "missing native_shadow_draw_primitive in $marker_path"
  test -n "$native_shadow_draw_face_stride_bytes" || fail "missing native_shadow_draw_face_stride_bytes in $marker_path"
  test -n "$native_shadow_draw_command_stride_bytes" || fail "missing native_shadow_draw_command_stride_bytes in $marker_path"
  test -n "$native_shadow_draw_indirect_enabled" || fail "missing native_shadow_draw_indirect_enabled in $marker_path"
  test -n "$native_shadow_uniform_set_index" || fail "missing native_shadow_uniform_set_index in $marker_path"
  test -n "$native_shadow_face_buffer_binding" || fail "missing native_shadow_face_buffer_binding in $marker_path"
  test -n "$native_shadow_push_constant_bytes" || fail "missing native_shadow_push_constant_bytes in $marker_path"
  test -n "$native_shadow_texture_sampling_enabled" || fail "missing native_shadow_texture_sampling_enabled in $marker_path"
  require_positive_float startup_chunk_packet_ms "$startup_chunk_packet_ms"
  test -n "$startup_packet_read_work_ms" || fail "missing startup_packet_read_work_ms in $marker_path"
  test -n "$startup_packet_decode_work_ms" || fail "missing startup_packet_decode_work_ms in $marker_path"
  test -n "$startup_packet_reader_elapsed_ms" || fail "missing startup_packet_reader_elapsed_ms in $marker_path"
  test -n "$startup_packet_queue_lag_ms" || fail "missing startup_packet_queue_lag_ms in $marker_path"
  test -n "$startup_chunk_decode_work_ms" || fail "missing startup_chunk_decode_work_ms in $marker_path"
  require_positive_float startup_chunk_inserted_ms "$startup_chunk_inserted_ms"
  require_positive_float startup_chunk_loaded_ms "$startup_chunk_loaded_ms"
  require_positive_float startup_mesh_queued_ms "$startup_mesh_queued_ms"
  require_positive_float startup_mesh_dispatched_ms "$startup_mesh_dispatched_ms"
  require_positive_float startup_first_mesh_ms "$startup_first_mesh_ms"
  require_positive_float startup_first_mesh_work_ms "$startup_first_mesh_work_ms"
  test -n "$startup_first_mesh_phase_ms" || fail "missing startup_first_mesh_phase_ms in $marker_path"
  require_positive_float startup_collision_ms "$startup_collision_ms"
  require_positive_float startup_player_spawn_ms "$startup_player_spawn_ms"
  require_startup_timing_order "$startup_chunk_packet_ms" "$startup_chunk_inserted_ms" "$startup_chunk_loaded_ms" "$startup_mesh_queued_ms" "$startup_mesh_dispatched_ms" "$startup_first_mesh_ms" "$startup_collision_ms" "$startup_player_spawn_ms"
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
    -v gpu_push_constant_updates="${gpu_push_constant_updates:-0}" \
    -v gpu_push_constant_total_bytes="${gpu_push_constant_total_bytes:-0}" \
    -v gpu_push_constant_avg_bytes="$gpu_push_constant_avg_bytes" \
    -v gpu_push_constant_camera_bytes="${gpu_push_constant_camera_bytes:-0}" \
    -v gpu_push_constant_lighting_bytes="${gpu_push_constant_lighting_bytes:-0}" \
    -v gpu_push_constant_atlas_bytes="${gpu_push_constant_atlas_bytes:-0}" \
    -v gpu_light_dir="${gpu_light_dir:-n/a}" \
    -v gpu_light_color="${gpu_light_color:-n/a}" \
    -v gpu_light_energy="${gpu_light_energy:-0}" \
    -v gpu_light_ambient="${gpu_light_ambient:-0}" \
    -v native_shadow_requested="${native_shadow_requested:-0}" \
    -v native_shadow_active="${native_shadow_active:-0}" \
    -v native_shadow_fallback="${native_shadow_fallback:-0}" \
    -v native_shadow_implemented="${native_shadow_implemented:-0}" \
    -v native_shadow_resource_status="${native_shadow_resource_status:-n/a}" \
    -v native_shadow_resource_width="${native_shadow_resource_width:-0}" \
    -v native_shadow_resource_height="${native_shadow_resource_height:-0}" \
    -v native_shadow_resource_layers="${native_shadow_resource_layers:-0}" \
    -v native_shadow_resource_bytes_per_texel="${native_shadow_resource_bytes_per_texel:-0}" \
    -v native_shadow_resource_bytes="${native_shadow_resource_bytes:-0}" \
    -v native_shadow_resource_format="${native_shadow_resource_format:-n/a}" \
    -v native_shadow_resource_usage="${native_shadow_resource_usage:-n/a}" \
    -v native_shadow_pass_load_op="${native_shadow_pass_load_op:-n/a}" \
    -v native_shadow_pass_store_op="${native_shadow_pass_store_op:-n/a}" \
    -v native_shadow_pass_clear_depth_milli="${native_shadow_pass_clear_depth_milli:-0}" \
    -v native_shadow_sampler_filter="${native_shadow_sampler_filter:-n/a}" \
    -v native_shadow_sampler_address="${native_shadow_sampler_address:-n/a}" \
    -v native_shadow_sampler_compare_op="${native_shadow_sampler_compare_op:-n/a}" \
    -v native_shadow_sampler_compare_enabled="${native_shadow_sampler_compare_enabled:-0}" \
    -v native_shadow_depth_bias_constant_milli="${native_shadow_depth_bias_constant_milli:-0}" \
    -v native_shadow_depth_bias_slope_milli="${native_shadow_depth_bias_slope_milli:-0}" \
    -v native_shadow_depth_bias_clamp_milli="${native_shadow_depth_bias_clamp_milli:-0}" \
    -v native_shadow_viewport_x_px="${native_shadow_viewport_x_px:-0}" \
    -v native_shadow_viewport_y_px="${native_shadow_viewport_y_px:-0}" \
    -v native_shadow_viewport_width_px="${native_shadow_viewport_width_px:-0}" \
    -v native_shadow_viewport_height_px="${native_shadow_viewport_height_px:-0}" \
    -v native_shadow_viewport_min_depth_milli="${native_shadow_viewport_min_depth_milli:-0}" \
    -v native_shadow_viewport_max_depth_milli="${native_shadow_viewport_max_depth_milli:-0}" \
    -v native_shadow_pipeline_depth_test_enabled="${native_shadow_pipeline_depth_test_enabled:-0}" \
    -v native_shadow_pipeline_depth_write_enabled="${native_shadow_pipeline_depth_write_enabled:-0}" \
    -v native_shadow_pipeline_cull_mode="${native_shadow_pipeline_cull_mode:-n/a}" \
    -v native_shadow_pipeline_front_face="${native_shadow_pipeline_front_face:-n/a}" \
    -v native_shadow_draw_source="${native_shadow_draw_source:-n/a}" \
    -v native_shadow_draw_primitive="${native_shadow_draw_primitive:-n/a}" \
    -v native_shadow_draw_face_stride_bytes="${native_shadow_draw_face_stride_bytes:-0}" \
    -v native_shadow_draw_command_stride_bytes="${native_shadow_draw_command_stride_bytes:-0}" \
    -v native_shadow_draw_indirect_enabled="${native_shadow_draw_indirect_enabled:-0}" \
    -v native_shadow_uniform_set_index="${native_shadow_uniform_set_index:-0}" \
    -v native_shadow_face_buffer_binding="${native_shadow_face_buffer_binding:-0}" \
    -v native_shadow_push_constant_bytes="${native_shadow_push_constant_bytes:-0}" \
    -v native_shadow_texture_sampling_enabled="${native_shadow_texture_sampling_enabled:-0}" \
    -v native_shadow_resource_creates="${native_shadow_resource_creates:-0}" \
    -v native_shadow_resource_reuses="${native_shadow_resource_reuses:-0}" \
    -v native_shadow_resource_replaces="${native_shadow_resource_replaces:-0}" \
    -v native_shadow_resource_releases="${native_shadow_resource_releases:-0}" \
    -v native_shadow_covered_chunks="${native_shadow_covered_chunks:-0}" \
    -v native_shadow_covered_subchunks="${native_shadow_covered_subchunks:-0}" \
    -v smoke_pose="${smoke_pose:-n/a}" \
    -v lighting_variant="${lighting_variant:-n/a}" \
    -v gpu_cull="${gpu_cull:-n/a}" \
    -v gpu_front_face="${gpu_front_face:-n/a}" \
    -v startup_chunk_packet_ms="$startup_chunk_packet_ms" \
    -v startup_packet_read_work_ms="${startup_packet_read_work_ms:-0}" \
    -v startup_packet_decode_work_ms="${startup_packet_decode_work_ms:-0}" \
    -v startup_packet_reader_elapsed_ms="${startup_packet_reader_elapsed_ms:-0}" \
    -v startup_packet_queue_lag_ms="${startup_packet_queue_lag_ms:-0}" \
    -v startup_chunk_decode_work_ms="${startup_chunk_decode_work_ms:-0}" \
    -v startup_chunk_inserted_ms="$startup_chunk_inserted_ms" \
    -v startup_chunk_loaded_ms="$startup_chunk_loaded_ms" \
    -v startup_mesh_queued_ms="$startup_mesh_queued_ms" \
    -v startup_mesh_dispatched_ms="$startup_mesh_dispatched_ms" \
    -v startup_first_mesh_ms="$startup_first_mesh_ms" \
    -v startup_first_mesh_work_ms="$startup_first_mesh_work_ms" \
    -v startup_first_mesh_phase_ms="$startup_first_mesh_phase_ms" \
    -v startup_first_mesh_collision_work_ms="${startup_first_mesh_collision_work_ms:-0}" \
    -v startup_collision_ms="$startup_collision_ms" \
    -v startup_player_spawn_ms="$startup_player_spawn_ms" \
    -v frame_p95="$frame_p95" \
    -v fps_p05="$fps_p05" \
    -v process_wall_p95="$process_wall_p95" '
      BEGIN {
        status = "pass"
        over = terrain_queue_max - budget
        if (over > 0.0) {
          status = "fail"
        }
        printf("GPU terrain movement stress summary target_fps=%.0f budget_ms=%.3f smoke_pose=%s lighting_variant=%s\n", 1000.0 / budget, budget, smoke_pose, lighting_variant)
        printf("movement_terrain_queue avg_ms=%.3f max_ms=%.3f max_mesh_ms=%.3f max_coll_ms=%.3f budget_status=%s over_ms=%.3f queue_uploads_avg=%.2f queue_uploads_max=%.0f queue_upload_kb_avg=%.1f queue_upload_kb_max=%.1f mesh_avg_ms=%.3f mesh_max_ms=%.3f coll_avg_ms=%.3f coll_max_ms=%.3f gpu_effective_draws=%d gpu_draw_repeat=%d gpu_draw_cmd_bytes=%d gpu_draw_cmd_capacity_bytes=%d gpu_draw_cmd_stride=%d gpu_scene_target_create=%d gpu_scene_target_reuse=%d gpu_scene_target_replace=%d gpu_uniform_set_create=%d gpu_atlas_texture_create=%d gpu_atlas_sampler_create=%d gpu_push_constant_bytes=%d gpu_push_constant_updates=%d gpu_push_constant_total_bytes=%d gpu_push_constant_avg_bytes=%.1f gpu_push_constant_camera_bytes=%d gpu_push_constant_lighting_bytes=%d gpu_push_constant_atlas_bytes=%d gpu_light_dir=%s gpu_light_color=%s gpu_light_energy=%.3f gpu_light_ambient=%.3f gpu_cull=%s gpu_front_face=%s gpu_compositor_submit_avg_ms=%.3f gpu_compositor_submit_max_ms=%.3f gpu_compositor_submit_max_parts_ms=%.3f/%.3f/%.3f/%.3f gpu_compositor_gpu_samples=%d gpu_compositor_gpu_avg_ms=%.3f gpu_compositor_gpu_max_ms=%.3f gpu_compositor_gpu_avg_us=%.1f gpu_compositor_gpu_max_us=%.1f process_wall_p95_ms=%.3f frame_p95_ms=%.3f fps_p05=%.1f\n", terrain_queue_avg, terrain_queue_max, terrain_queue_max_mesh, terrain_queue_max_coll, status, over, terrain_queue_uploads_avg, terrain_queue_uploads_max, terrain_queue_upload_kb_avg, terrain_queue_upload_kb_max, mesh_avg, mesh_max, coll_avg, coll_max, gpu_effective_draws, gpu_draw_repeat, gpu_draw_cmd_bytes, gpu_draw_cmd_capacity_bytes, gpu_draw_cmd_stride, gpu_scene_target_create, gpu_scene_target_reuse, gpu_scene_target_replace, gpu_uniform_set_create, gpu_atlas_texture_create, gpu_atlas_sampler_create, gpu_push_constant_bytes, gpu_push_constant_updates, gpu_push_constant_total_bytes, gpu_push_constant_avg_bytes, gpu_push_constant_camera_bytes, gpu_push_constant_lighting_bytes, gpu_push_constant_atlas_bytes, gpu_light_dir, gpu_light_color, gpu_light_energy, gpu_light_ambient, gpu_cull, gpu_front_face, compositor_submit_avg, compositor_submit_max, compositor_submit_max_setup, compositor_submit_max_target, compositor_submit_max_constants, compositor_submit_max_draw, compositor_gpu_samples, compositor_gpu_avg, compositor_gpu_max, compositor_gpu_us_avg, compositor_gpu_us_max, process_wall_p95, frame_p95, fps_p05)
        printf("movement_native_shadow requested=%d active=%d fallback=%d implemented=%d resource_status=%s resource_width=%d resource_height=%d resource_layers=%d resource_bytes_per_texel=%d resource_bytes=%d resource_format=%s resource_usage=%s pass_load_op=%s pass_store_op=%s pass_clear_depth_milli=%d sampler_filter=%s sampler_address=%s sampler_compare_op=%s sampler_compare_enabled=%d depth_bias_constant_milli=%d depth_bias_slope_milli=%d depth_bias_clamp_milli=%d viewport_x_px=%d viewport_y_px=%d viewport_width_px=%d viewport_height_px=%d viewport_min_depth_milli=%d viewport_max_depth_milli=%d pipeline_depth_test_enabled=%d pipeline_depth_write_enabled=%d pipeline_cull_mode=%s pipeline_front_face=%s draw_source=%s draw_primitive=%s draw_face_stride_bytes=%d draw_command_stride_bytes=%d draw_indirect_enabled=%d uniform_set_index=%d face_buffer_binding=%d push_constant_bytes=%d texture_sampling_enabled=%d resource_creates=%d resource_reuses=%d resource_replaces=%d resource_releases=%d covered_chunks=%d covered_subchunks=%d native_shadow_requested=%d native_shadow_active=%d native_shadow_fallback=%d native_shadow_implemented=%d native_shadow_resource_width=%d native_shadow_resource_height=%d native_shadow_resource_layers=%d native_shadow_resource_bytes_per_texel=%d native_shadow_resource_bytes=%d native_shadow_pass_clear_depth_milli=%d native_shadow_sampler_compare_enabled=%d native_shadow_depth_bias_constant_milli=%d native_shadow_depth_bias_slope_milli=%d native_shadow_depth_bias_clamp_milli=%d native_shadow_viewport_x_px=%d native_shadow_viewport_y_px=%d native_shadow_viewport_width_px=%d native_shadow_viewport_height_px=%d native_shadow_viewport_min_depth_milli=%d native_shadow_viewport_max_depth_milli=%d native_shadow_pipeline_depth_test_enabled=%d native_shadow_pipeline_depth_write_enabled=%d native_shadow_draw_face_stride_bytes=%d native_shadow_draw_command_stride_bytes=%d native_shadow_draw_indirect_enabled=%d native_shadow_uniform_set_index=%d native_shadow_face_buffer_binding=%d native_shadow_push_constant_bytes=%d native_shadow_texture_sampling_enabled=%d native_shadow_resource_creates=%d native_shadow_resource_reuses=%d native_shadow_resource_replaces=%d native_shadow_resource_releases=%d native_shadow_covered_chunks=%d native_shadow_covered_subchunks=%d\n", native_shadow_requested, native_shadow_active, native_shadow_fallback, native_shadow_implemented, native_shadow_resource_status, native_shadow_resource_width, native_shadow_resource_height, native_shadow_resource_layers, native_shadow_resource_bytes_per_texel, native_shadow_resource_bytes, native_shadow_resource_format, native_shadow_resource_usage, native_shadow_pass_load_op, native_shadow_pass_store_op, native_shadow_pass_clear_depth_milli, native_shadow_sampler_filter, native_shadow_sampler_address, native_shadow_sampler_compare_op, native_shadow_sampler_compare_enabled, native_shadow_depth_bias_constant_milli, native_shadow_depth_bias_slope_milli, native_shadow_depth_bias_clamp_milli, native_shadow_viewport_x_px, native_shadow_viewport_y_px, native_shadow_viewport_width_px, native_shadow_viewport_height_px, native_shadow_viewport_min_depth_milli, native_shadow_viewport_max_depth_milli, native_shadow_pipeline_depth_test_enabled, native_shadow_pipeline_depth_write_enabled, native_shadow_pipeline_cull_mode, native_shadow_pipeline_front_face, native_shadow_draw_source, native_shadow_draw_primitive, native_shadow_draw_face_stride_bytes, native_shadow_draw_command_stride_bytes, native_shadow_draw_indirect_enabled, native_shadow_uniform_set_index, native_shadow_face_buffer_binding, native_shadow_push_constant_bytes, native_shadow_texture_sampling_enabled, native_shadow_resource_creates, native_shadow_resource_reuses, native_shadow_resource_replaces, native_shadow_resource_releases, native_shadow_covered_chunks, native_shadow_covered_subchunks, native_shadow_requested, native_shadow_active, native_shadow_fallback, native_shadow_implemented, native_shadow_resource_width, native_shadow_resource_height, native_shadow_resource_layers, native_shadow_resource_bytes_per_texel, native_shadow_resource_bytes, native_shadow_pass_clear_depth_milli, native_shadow_sampler_compare_enabled, native_shadow_depth_bias_constant_milli, native_shadow_depth_bias_slope_milli, native_shadow_depth_bias_clamp_milli, native_shadow_viewport_x_px, native_shadow_viewport_y_px, native_shadow_viewport_width_px, native_shadow_viewport_height_px, native_shadow_viewport_min_depth_milli, native_shadow_viewport_max_depth_milli, native_shadow_pipeline_depth_test_enabled, native_shadow_pipeline_depth_write_enabled, native_shadow_draw_face_stride_bytes, native_shadow_draw_command_stride_bytes, native_shadow_draw_indirect_enabled, native_shadow_uniform_set_index, native_shadow_face_buffer_binding, native_shadow_push_constant_bytes, native_shadow_texture_sampling_enabled, native_shadow_resource_creates, native_shadow_resource_reuses, native_shadow_resource_replaces, native_shadow_resource_releases, native_shadow_covered_chunks, native_shadow_covered_subchunks)
        printf("movement_startup packet_ms=%.3f packet_read_work_ms=%.3f packet_decode_work_ms=%.3f packet_reader_elapsed_ms=%.3f packet_queue_lag_ms=%.3f chunk_decode_work_ms=%.3f chunk_inserted_ms=%.3f chunk_loaded_ms=%.3f mesh_queued_ms=%.3f mesh_dispatched_ms=%.3f first_mesh_ms=%.3f first_mesh_work_ms=%.3f first_mesh_phase_ms=%s first_mesh_collision_work_ms=%.3f collision_ms=%.3f player_spawn_ms=%.3f\n", startup_chunk_packet_ms, startup_packet_read_work_ms, startup_packet_decode_work_ms, startup_packet_reader_elapsed_ms, startup_packet_queue_lag_ms, startup_chunk_decode_work_ms, startup_chunk_inserted_ms, startup_chunk_loaded_ms, startup_mesh_queued_ms, startup_mesh_dispatched_ms, startup_first_mesh_ms, startup_first_mesh_work_ms, startup_first_mesh_phase_ms, startup_first_mesh_collision_work_ms, startup_collision_ms, startup_player_spawn_ms)
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

env_flag_is_true() {
  value="$1"
  normalized="$(
    printf '%s\n' "$value" \
      | awk '{ gsub(/^[[:space:]]+|[[:space:]]+$/, ""); print tolower($0); exit }'
  )"
  case "$normalized" in
    1|true|yes|on) return 0 ;;
    *) return 1 ;;
  esac
}

require_transparent_fallback_marker_if_requested() {
  marker_path="$1"
  if ! env_flag_is_true "${RUMPELMC_GPU_TERRAIN_TRANSPARENT:-}"; then
    return 0
  fi

  require_metric_eq "$marker_path" "transparent_requested" 1
  require_metric_eq "$marker_path" "transparent_active" 0
  require_metric_eq "$marker_path" "transparent_fallback" 1
  require_metric_eq "$marker_path" "transparent_blocks" 0
  require_metric_eq "$marker_path" "transparent_faces" 0
  require_metric_eq "$marker_path" "transparent_draws" 0
  require_metric_eq "$marker_path" "transparent_subchunks" 0

  if env_flag_is_true "${RUMPELMC_GPU_TERRAIN_TRANSPARENT_FIXTURE_OVERLAY:-}"; then
    require_metric_eq "$marker_path" "transparent_fixture_overlay_requested" 1
    require_metric_eq "$marker_path" "transparent_fixture_overlay_active" 0
    require_metric_eq "$marker_path" "transparent_fixture_overlay_fallback" 1
    require_metric_eq "$marker_path" "transparent_fixture_overlay_roles" 5
    require_metric_eq "$marker_path" "transparent_fixture_overlay_blocks" 5
  fi
}

require_native_shadow_fallback_marker_if_requested() {
  marker_path="$1"
  if ! env_flag_is_true "${RUMPELMC_GPU_TERRAIN_NATIVE_SHADOW:-}"; then
    return 0
  fi

  require_metric_eq "$marker_path" "native_shadow_requested" 1
  require_metric_eq "$marker_path" "native_shadow_active" 0
  require_metric_eq "$marker_path" "native_shadow_fallback" 1
  require_metric_eq "$marker_path" "native_shadow_implemented" 0
  test "$(text_metric native_shadow_resource_status "$marker_path")" = "disabled" \
    || fail "native shadow fallback unexpectedly prepared resources in $marker_path"
  require_metric_eq "$marker_path" "native_shadow_resource_radius" 0
  require_metric_eq "$marker_path" "native_shadow_resource_map" 0
  require_metric_eq "$marker_path" "native_shadow_resource_width" 0
  require_metric_eq "$marker_path" "native_shadow_resource_height" 0
  require_metric_eq "$marker_path" "native_shadow_resource_layers" 0
  require_metric_eq "$marker_path" "native_shadow_resource_bytes_per_texel" 0
  require_metric_eq "$marker_path" "native_shadow_resource_bytes" 0
  test "$(text_metric native_shadow_pass_load_op "$marker_path")" = "none" \
    || fail "native shadow fallback unexpectedly prepared pass load op in $marker_path"
  test "$(text_metric native_shadow_pass_store_op "$marker_path")" = "none" \
    || fail "native shadow fallback unexpectedly prepared pass store op in $marker_path"
  require_metric_eq "$marker_path" "native_shadow_pass_clear_depth_milli" 0
  test "$(text_metric native_shadow_sampler_filter "$marker_path")" = "none" \
    || fail "native shadow fallback unexpectedly prepared sampler filter in $marker_path"
  test "$(text_metric native_shadow_sampler_address "$marker_path")" = "none" \
    || fail "native shadow fallback unexpectedly prepared sampler address in $marker_path"
  test "$(text_metric native_shadow_sampler_compare_op "$marker_path")" = "none" \
    || fail "native shadow fallback unexpectedly prepared sampler compare op in $marker_path"
  require_metric_eq "$marker_path" "native_shadow_sampler_compare_enabled" 0
  require_metric_eq "$marker_path" "native_shadow_depth_bias_constant_milli" 0
  require_metric_eq "$marker_path" "native_shadow_depth_bias_slope_milli" 0
  require_metric_eq "$marker_path" "native_shadow_depth_bias_clamp_milli" 0
  require_metric_eq "$marker_path" "native_shadow_viewport_x_px" 0
  require_metric_eq "$marker_path" "native_shadow_viewport_y_px" 0
  require_metric_eq "$marker_path" "native_shadow_viewport_width_px" 0
  require_metric_eq "$marker_path" "native_shadow_viewport_height_px" 0
  require_metric_eq "$marker_path" "native_shadow_viewport_min_depth_milli" 0
  require_metric_eq "$marker_path" "native_shadow_viewport_max_depth_milli" 0
  require_metric_eq "$marker_path" "native_shadow_pipeline_depth_test_enabled" 0
  require_metric_eq "$marker_path" "native_shadow_pipeline_depth_write_enabled" 0
  test "$(text_metric native_shadow_pipeline_cull_mode "$marker_path")" = "none" \
    || fail "native shadow fallback unexpectedly prepared pipeline cull mode in $marker_path"
  test "$(text_metric native_shadow_pipeline_front_face "$marker_path")" = "none" \
    || fail "native shadow fallback unexpectedly prepared pipeline front face in $marker_path"
  test "$(text_metric native_shadow_draw_source "$marker_path")" = "none" \
    || fail "native shadow fallback unexpectedly prepared draw source in $marker_path"
  test "$(text_metric native_shadow_draw_primitive "$marker_path")" = "none" \
    || fail "native shadow fallback unexpectedly prepared draw primitive in $marker_path"
  require_metric_eq "$marker_path" "native_shadow_draw_face_stride_bytes" 0
  require_metric_eq "$marker_path" "native_shadow_draw_command_stride_bytes" 0
  require_metric_eq "$marker_path" "native_shadow_draw_indirect_enabled" 0
  require_metric_eq "$marker_path" "native_shadow_uniform_set_index" 0
  require_metric_eq "$marker_path" "native_shadow_face_buffer_binding" 0
  require_metric_eq "$marker_path" "native_shadow_push_constant_bytes" 0
  require_metric_eq "$marker_path" "native_shadow_texture_sampling_enabled" 0
  require_metric_eq "$marker_path" "native_shadow_resource_creates" 0
  require_metric_eq "$marker_path" "native_shadow_resource_replaces" 0
  require_metric_eq "$marker_path" "native_shadow_resource_releases" 0
  require_metric_eq "$marker_path" "native_shadow_covered_chunks" 0
  require_metric_eq "$marker_path" "native_shadow_covered_subchunks" 0
  grep -q "shadow_path=godot_proxy" "$marker_path" || fail "native shadow fallback did not keep godot_proxy in $marker_path"
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
    RUMPELMC_VISUAL_SMOKE_POSE="$SMOKE_POSE" \
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
if [ -n "$SMOKE_POSE" ]; then
  grep -q "pose=\"$SMOKE_POSE\"" "$marker_path" || fail "unexpected pose in $marker_path"
fi
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
require_native_shadow_fallback_marker_if_requested "$marker_path"
require_transparent_fallback_marker_if_requested "$marker_path"
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
