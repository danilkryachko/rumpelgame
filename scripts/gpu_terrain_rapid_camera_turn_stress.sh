#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/gpu_terrain_rapid_camera_turn_stress"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

RUN_DIR="$OUT_DIR/movement"
SUMMARY_PATH="$OUT_DIR/rapid-camera-turn-stress-summary.txt"
SOURCE_SUMMARY="${RUMPELMC_RAPID_CAMERA_TURN_SOURCE_SUMMARY:-}"
SOURCE_MARKER="${RUMPELMC_RAPID_CAMERA_TURN_SOURCE_MARKER:-}"
MOTION_NAME="${RUMPELMC_RAPID_CAMERA_TURN_MOTION:-chunk_fast_turn}"
EXPECTED_CURRENT_CHUNK="${RUMPELMC_RAPID_CAMERA_TURN_EXPECTED_CHUNK:-2,2}"
MIN_MOTION_STEPS="${RUMPELMC_RAPID_CAMERA_TURN_MIN_STEPS:-8}"
MIN_MOTION_CHUNKS="${RUMPELMC_RAPID_CAMERA_TURN_MIN_CHUNKS:-1}"
MAX_MOTION_CHUNKS="${RUMPELMC_RAPID_CAMERA_TURN_MAX_CHUNKS:-1}"
MOTION_STEP_SEC="${RUMPELMC_RAPID_CAMERA_TURN_STEP_SEC:-0.08}"
MOTION_SETTLE_SEC="${RUMPELMC_RAPID_CAMERA_TURN_SETTLE_SEC:-4.0}"
TARGET_FPS="${RUMPELMC_RAPID_CAMERA_TURN_TARGET_FPS:-150}"
BUDGET_MODE="${RUMPELMC_RAPID_CAMERA_TURN_BUDGET_MODE:-enforce}"
PROCESS_WALL_BUDGET_MODE="${RUMPELMC_RAPID_CAMERA_TURN_PROCESS_WALL_BUDGET_MODE:-enforce}"
GPU_COMPOSITOR_BUDGET_MODE="${RUMPELMC_RAPID_CAMERA_TURN_GPU_COMPOSITOR_BUDGET_MODE:-enforce}"
GPU_TIMESTAMP_BUDGET_MODE="${RUMPELMC_RAPID_CAMERA_TURN_GPU_TIMESTAMP_BUDGET_MODE:-report}"

fail() {
  echo "gpu_terrain_rapid_camera_turn_stress: $*" >&2
  exit 1
}

field_metric() {
  key="$1"
  path="$2"
  awk -v key="$key" '
    {
      prefix = key "="
      for (i = 1; i <= NF; i++) {
        if (index($i, prefix) == 1) {
          value = substr($i, length(prefix) + 1)
          gsub(/^"/, "", value)
          gsub(/"$/, "", value)
          print value
          exit
        }
      }
    }
  ' "$path"
}

line_metric() {
  line_name="$1"
  key="$2"
  path="$3"
  awk -v line_name="$line_name" -v key="$key" '
    $1 == line_name {
      prefix = key "="
      for (i = 1; i <= NF; i++) {
        if (index($i, prefix) == 1) {
          value = substr($i, length(prefix) + 1)
          gsub(/^"/, "", value)
          gsub(/"$/, "", value)
          print value
          exit
        }
      }
    }
  ' "$path"
}

case "$MIN_MOTION_STEPS:$MIN_MOTION_CHUNKS:$MAX_MOTION_CHUNKS" in
  *[!0-9:]*|:*|*:|*::*)
    fail "RUMPELMC_RAPID_CAMERA_TURN_MIN/MAX thresholds must be non-negative integers"
    ;;
esac

mkdir -p "$OUT_DIR"

if [ -n "$SOURCE_SUMMARY" ]; then
  case "$SOURCE_SUMMARY" in
    /*) ;;
    *) SOURCE_SUMMARY="$ROOT_DIR/$SOURCE_SUMMARY" ;;
  esac
  test -s "$SOURCE_SUMMARY" || fail "missing source summary $SOURCE_SUMMARY"
  if [ -z "$SOURCE_MARKER" ]; then
    SOURCE_MARKER="$(dirname -- "$SOURCE_SUMMARY")/gpu-terrain-movement-stress.png.txt"
  fi
  case "$SOURCE_MARKER" in
    /*) ;;
    *) SOURCE_MARKER="$ROOT_DIR/$SOURCE_MARKER" ;;
  esac
  movement_summary="$SOURCE_SUMMARY"
  marker_path="$SOURCE_MARKER"
  echo "==> GPU terrain rapid camera-turn stress reusing $movement_summary"
else
  rm -rf "$RUN_DIR"
  mkdir -p "$RUN_DIR"
  echo "==> GPU terrain rapid camera-turn stress motion=$MOTION_NAME"
  RUMPELMC_MOVEMENT_STRESS_MOTION="$MOTION_NAME" \
  RUMPELMC_MOVEMENT_STRESS_EXPECTED_CHUNK="$EXPECTED_CURRENT_CHUNK" \
  RUMPELMC_MOVEMENT_STRESS_MIN_CHUNKS="$MIN_MOTION_CHUNKS" \
  RUMPELMC_MOVEMENT_STRESS_STEP_SEC="$MOTION_STEP_SEC" \
  RUMPELMC_MOVEMENT_STRESS_SETTLE_SEC="$MOTION_SETTLE_SEC" \
  RUMPELMC_MOVEMENT_STRESS_TARGET_FPS="$TARGET_FPS" \
  RUMPELMC_MOVEMENT_STRESS_BUDGET_MODE="$BUDGET_MODE" \
  RUMPELMC_MOVEMENT_STRESS_PROCESS_WALL_BUDGET_MODE="$PROCESS_WALL_BUDGET_MODE" \
  RUMPELMC_MOVEMENT_STRESS_GPU_COMPOSITOR_BUDGET_MODE="$GPU_COMPOSITOR_BUDGET_MODE" \
  RUMPELMC_MOVEMENT_STRESS_GPU_TIMESTAMP_BUDGET_MODE="$GPU_TIMESTAMP_BUDGET_MODE" \
  /bin/sh "$ROOT_DIR/scripts/gpu_terrain_movement_stress.sh" "$RUN_DIR"
  movement_summary="$RUN_DIR/movement-stress-summary.txt"
  marker_path="$RUN_DIR/gpu-terrain-movement-stress.png.txt"
fi

test -s "$movement_summary" || fail "missing movement summary $movement_summary"
test -s "$marker_path" || fail "missing movement marker $marker_path"

motion="$(field_metric motion "$marker_path")"
motion_steps="$(field_metric motion_steps "$marker_path")"
motion_chunks="$(field_metric motion_chunks "$marker_path")"
current_chunk="$(field_metric current_chunk "$marker_path")"
current_chunk_loaded="$(field_metric current_chunk_loaded "$marker_path")"
current_chunk_submeshes="$(field_metric current_chunk_submeshes "$marker_path")"
current_chunk_collision="$(field_metric current_chunk_collision "$marker_path")"
ground_misses="$(field_metric ground_misses "$marker_path")"
terrain_samples="$(field_metric terrain_samples "$marker_path")"
smoke_err="$(field_metric smoke_err "$marker_path")"
gpu_upload_fail="$(field_metric gpu_upload_fail "$marker_path")"
gpu_upload_fail_capacity="$(field_metric gpu_upload_fail_capacity "$marker_path")"
gpu_upload_fail_fragmented="$(field_metric gpu_upload_fail_fragmented "$marker_path")"
gpu_upload_fail_injected="$(field_metric gpu_upload_fail_injected "$marker_path")"

terrain_queue_max="$(line_metric movement_terrain_queue max_ms "$movement_summary")"
process_wall_p95="$(line_metric movement_terrain_queue process_wall_p95_ms "$movement_summary")"
gpu_compositor_submit_max="$(line_metric movement_terrain_queue gpu_compositor_submit_max_ms "$movement_summary")"
gpu_effective_draws="$(line_metric movement_terrain_queue gpu_effective_draws "$movement_summary")"
frame_p95="$(line_metric movement_terrain_queue frame_p95_ms "$movement_summary")"
fps_p05="$(line_metric movement_terrain_queue fps_p05 "$movement_summary")"
packet_queue_max_drain="$(line_metric movement_packet_queue max_drain "$movement_summary")"
packet_queue_drained="$(line_metric movement_packet_queue drained "$movement_summary")"
packet_queue_lag_max="$(line_metric movement_packet_queue lag_max_ms "$movement_summary")"
packet_queue_decode_work_max="$(line_metric movement_packet_queue decode_work_max_ms "$movement_summary")"
chunk_unload_total="$(line_metric movement_chunk_unload unloaded "$movement_summary")"
chunk_unload_grace_kept="$(line_metric movement_chunk_unload grace_kept "$movement_summary")"
chunk_unload_neighbor_refreshes="$(line_metric movement_chunk_unload neighbor_refreshes "$movement_summary")"
chunk_unload_max="$(line_metric movement_chunk_unload max_unloaded "$movement_summary")"
popin_missing_chunks="$(line_metric movement_popin missing_chunks "$movement_summary")"
popin_collision_missing_chunks="$(line_metric movement_popin collision_missing_chunks "$movement_summary")"
popin_missing_max="$(line_metric movement_popin missing_max "$movement_summary")"
popin_collision_missing_max="$(line_metric movement_popin collision_missing_max "$movement_summary")"
current_render_ready="$(line_metric movement_readiness current_render_ready "$movement_summary")"
current_collision_ready="$(line_metric movement_readiness current_collision_ready "$movement_summary")"

awk \
  -v motion="${motion:-}" \
  -v expected_motion="$MOTION_NAME" \
  -v motion_steps="${motion_steps:-0}" \
  -v min_steps="$MIN_MOTION_STEPS" \
  -v motion_chunks="${motion_chunks:-0}" \
  -v min_chunks="$MIN_MOTION_CHUNKS" \
  -v max_chunks="$MAX_MOTION_CHUNKS" \
  -v current_chunk="${current_chunk:-}" \
  -v expected_chunk="$EXPECTED_CURRENT_CHUNK" \
  -v current_chunk_loaded="${current_chunk_loaded:-0}" \
  -v current_chunk_submeshes="${current_chunk_submeshes:-0}" \
  -v current_chunk_collision="${current_chunk_collision:-0}" \
  -v current_render_ready="${current_render_ready:-0}" \
  -v current_collision_ready="${current_collision_ready:-0}" \
  -v ground_misses="${ground_misses:-0}" \
  -v terrain_samples="${terrain_samples:-0}" \
  -v smoke_err="${smoke_err:-1}" \
  -v gpu_upload_fail="${gpu_upload_fail:-0}" \
  -v gpu_upload_fail_capacity="${gpu_upload_fail_capacity:-0}" \
  -v gpu_upload_fail_fragmented="${gpu_upload_fail_fragmented:-0}" \
  -v gpu_upload_fail_injected="${gpu_upload_fail_injected:-0}" \
  -v terrain_queue_max="${terrain_queue_max:-0}" \
  -v process_wall_p95="${process_wall_p95:-0}" \
  -v gpu_compositor_submit_max="${gpu_compositor_submit_max:-0}" \
  -v gpu_effective_draws="${gpu_effective_draws:-0}" \
  -v frame_p95="${frame_p95:-0}" \
  -v fps_p05="${fps_p05:-0}" \
  -v packet_queue_max_drain="${packet_queue_max_drain:-0}" \
  -v packet_queue_drained="${packet_queue_drained:-0}" \
  -v packet_queue_lag_max="${packet_queue_lag_max:-0}" \
  -v packet_queue_decode_work_max="${packet_queue_decode_work_max:-0}" \
  -v chunk_unload_total="${chunk_unload_total:-0}" \
  -v chunk_unload_grace_kept="${chunk_unload_grace_kept:-0}" \
  -v chunk_unload_neighbor_refreshes="${chunk_unload_neighbor_refreshes:-0}" \
  -v chunk_unload_max="${chunk_unload_max:-0}" \
  -v popin_missing_chunks="${popin_missing_chunks:-0}" \
  -v popin_collision_missing_chunks="${popin_collision_missing_chunks:-0}" \
  -v popin_missing_max="${popin_missing_max:-0}" \
  -v popin_collision_missing_max="${popin_collision_missing_max:-0}" \
  -v target_fps="$TARGET_FPS" \
  -v movement_summary="$movement_summary" \
  -v marker_path="$marker_path" '
  BEGIN {
    budget_ms = 1000.0 / (target_fps + 0.0)
    status = "pass"
    reason = "ok"
    if (motion != expected_motion) {
      status = "fail"; reason = "wrong_motion"
    } else if (motion_steps + 0 < min_steps + 0) {
      status = "fail"; reason = "motion_steps"
    } else if (motion_chunks + 0 < min_chunks + 0 || motion_chunks + 0 > max_chunks + 0) {
      status = "fail"; reason = "motion_chunks"
    } else if (current_chunk != expected_chunk) {
      status = "fail"; reason = "current_chunk"
    } else if (current_chunk_loaded + 0 == 0 || current_render_ready + 0 == 0 || current_collision_ready + 0 == 0 || current_chunk_submeshes + 0 < 1 || current_chunk_collision + 0 < 1) {
      status = "fail"; reason = "current_readiness"
    } else if (ground_misses + 0 != 0 || terrain_samples + 0 <= 0 || smoke_err + 0 != 0) {
      status = "fail"; reason = "visual_or_ground"
    } else if (gpu_upload_fail + 0 != 0 || gpu_upload_fail_capacity + 0 != 0 || gpu_upload_fail_fragmented + 0 != 0 || gpu_upload_fail_injected + 0 != 0) {
      status = "fail"; reason = "upload_fail"
    } else if (chunk_unload_total + 0 != 0 || chunk_unload_neighbor_refreshes + 0 != 0 || chunk_unload_max + 0 != 0) {
      status = "fail"; reason = "unexpected_unload"
    } else if (terrain_queue_max + 0.0 > budget_ms || process_wall_p95 + 0.0 > budget_ms || gpu_compositor_submit_max + 0.0 > budget_ms) {
      status = "fail"; reason = "cpu_budget"
    }

    printf("rapid_camera_turn_stress status=%s reason=%s motion=%s expected_chunk=%s current_chunk=%s min_motion_steps=%d motion_steps=%d min_motion_chunks=%d max_motion_chunks=%d motion_chunks=%d target_fps=%s budget_ms=%.3f terrain_queue_max_ms=%.3f process_wall_p95_ms=%.3f gpu_compositor_submit_max_ms=%.3f gpu_effective_draws=%d frame_p95_ms=%.3f fps_p05=%.3f packet_queue_max_drain=%d packet_queue_drained=%d packet_queue_lag_max_ms=%.3f packet_queue_decode_work_max_ms=%.3f chunk_unload_total=%d chunk_unload_grace_kept=%d chunk_unload_neighbor_refreshes=%d chunk_unload_max=%d popin_missing_chunks=%d popin_collision_missing_chunks=%d popin_missing_max=%d popin_collision_missing_max=%d current_chunk_loaded=%d current_render_ready=%d current_chunk_submeshes=%d current_collision_ready=%d current_chunk_collision=%d ground_misses=%d terrain_samples=%d smoke_err=%d gpu_upload_fail=%d gpu_upload_fail_capacity=%d gpu_upload_fail_fragmented=%d gpu_upload_fail_injected=%d movement_summary=%s marker=%s\n", status, reason, motion, expected_chunk, current_chunk, min_steps, motion_steps, min_chunks, max_chunks, motion_chunks, target_fps, budget_ms, terrain_queue_max, process_wall_p95, gpu_compositor_submit_max, gpu_effective_draws, frame_p95, fps_p05, packet_queue_max_drain, packet_queue_drained, packet_queue_lag_max, packet_queue_decode_work_max, chunk_unload_total, chunk_unload_grace_kept, chunk_unload_neighbor_refreshes, chunk_unload_max, popin_missing_chunks, popin_collision_missing_chunks, popin_missing_max, popin_collision_missing_max, current_chunk_loaded, current_render_ready, current_chunk_submeshes, current_collision_ready, current_chunk_collision, ground_misses, terrain_samples, smoke_err, gpu_upload_fail, gpu_upload_fail_capacity, gpu_upload_fail_fragmented, gpu_upload_fail_injected, movement_summary, marker_path)
    if (status != "pass") {
      exit 1
    }
  }
' > "$SUMMARY_PATH" || {
  cat "$SUMMARY_PATH" >&2 || true
  fail "rapid camera-turn stress summary did not pass"
}

cat "$SUMMARY_PATH"
echo "GPU terrain rapid camera-turn stress artifacts: $OUT_DIR"
