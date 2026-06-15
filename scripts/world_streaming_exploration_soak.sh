#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/world_streaming_exploration_soak"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

SUMMARY_PATH="$OUT_DIR/world-streaming-exploration-soak-summary.txt"
REPEATS="${RUMPELMC_EXPLORATION_SOAK_REPEATS:-3}"
MOTION="${RUMPELMC_EXPLORATION_SOAK_MOTION:-chunk_walk_extended}"
EXPECTED_CHUNK="${RUMPELMC_EXPLORATION_SOAK_EXPECTED_CHUNK:-11,8}"
MIN_CHUNKS="${RUMPELMC_EXPLORATION_SOAK_MIN_CHUNKS:-12}"
STEP_SEC="${RUMPELMC_EXPLORATION_SOAK_STEP_SEC:-0.45}"
SETTLE_SEC="${RUMPELMC_EXPLORATION_SOAK_SETTLE_SEC:-8.0}"
TARGET_FPS="${RUMPELMC_EXPLORATION_SOAK_TARGET_FPS:-150}"
BUDGET_MODE="${RUMPELMC_EXPLORATION_SOAK_BUDGET_MODE:-report}"
PROCESS_WALL_BUDGET_MODE="${RUMPELMC_EXPLORATION_SOAK_PROCESS_WALL_BUDGET_MODE:-report}"
GPU_COMPOSITOR_BUDGET_MODE="${RUMPELMC_EXPLORATION_SOAK_GPU_COMPOSITOR_BUDGET_MODE:-report}"
GPU_TIMESTAMP_BUDGET_MODE="${RUMPELMC_EXPLORATION_SOAK_GPU_TIMESTAMP_BUDGET_MODE:-report}"

mkdir -p "$OUT_DIR"

fail() {
  echo "world_streaming_exploration_soak: $*" >&2
  exit 1
}

listener_pid() {
  if command -v lsof >/dev/null 2>&1; then
    lsof -tiTCP:25565 -sTCP:LISTEN 2>/dev/null | sed -n '1p'
  fi
}

wait_for_port_clear() {
  tries=0
  while [ "$tries" -lt 10 ]; do
    pid="$(listener_pid || true)"
    if [ -z "$pid" ]; then
      return 0
    fi
    tries=$((tries + 1))
    sleep 1
  done
  fail "port 25565 is still listening after cleanup"
}

cleanup_server() {
  pid="$(listener_pid || true)"
  if [ -n "$pid" ]; then
    kill "$pid" 2>/dev/null || true
    wait_for_port_clear
  fi
}

sign_server_binary_if_possible() {
  if command -v codesign >/dev/null 2>&1; then
    codesign -s - --force ./server >/dev/null 2>&1 || true
  fi
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

append_run_summary() {
  index="$1"
  run_dir="$2"
  summary="$run_dir/movement-stress-summary.txt"
  marker="$run_dir/gpu-terrain-movement-stress.png.txt"

  test -s "$summary" || fail "missing movement summary for run $index: $summary"
  test -s "$marker" || fail "missing movement marker for run $index: $marker"

  motion_steps="$(field_metric motion_steps "$marker")"
  motion_chunks="$(field_metric motion_chunks "$marker")"
  current_chunk="$(field_metric current_chunk "$marker")"
  gpu_upload_fail="$(field_metric gpu_upload_fail "$marker")"
  gpu_effective_draws="$(line_metric movement_terrain_queue gpu_effective_draws "$summary")"
  terrain_queue_max="$(line_metric movement_terrain_queue max_ms "$summary")"
  process_wall_p95="$(line_metric movement_terrain_queue process_wall_p95_ms "$summary")"
  gpu_compositor_submit_max="$(line_metric movement_terrain_queue gpu_compositor_submit_max_ms "$summary")"
  packet_queue_max_drain="$(line_metric movement_packet_queue max_drain "$summary")"
  packet_queue_lag_max="$(line_metric movement_packet_queue lag_max_ms "$summary")"
  packet_queue_drained="$(line_metric movement_packet_queue drained "$summary")"
  chunk_unload_total="$(line_metric movement_chunk_unload unloaded "$summary")"
  chunk_unload_neighbor_refreshes="$(line_metric movement_chunk_unload neighbor_refreshes "$summary")"
  chunk_unload_max="$(line_metric movement_chunk_unload max_unloaded "$summary")"
  popin_missing_chunks="$(line_metric movement_popin missing_chunks "$summary")"
  popin_collision_missing_chunks="$(line_metric movement_popin collision_missing_chunks "$summary")"
  popin_missing_max="$(line_metric movement_popin missing_max "$summary")"
  popin_collision_missing_max="$(line_metric movement_popin collision_missing_max "$summary")"
  current_render_ready="$(line_metric movement_readiness current_render_ready "$summary")"
  current_collision_ready="$(line_metric movement_readiness current_collision_ready "$summary")"
  ground_misses="$(line_metric movement_readiness ground_misses "$summary")"

  printf 'exploration_soak_run index=%s status=pass motion=%s motion_steps=%s motion_chunks=%s current_chunk=%s terrain_queue_max_ms=%s process_wall_p95_ms=%s gpu_compositor_submit_max_ms=%s gpu_effective_draws=%s gpu_upload_fail=%s packet_queue_max_drain=%s packet_queue_drained=%s packet_queue_lag_max_ms=%s chunk_unload_total=%s chunk_unload_neighbor_refreshes=%s chunk_unload_max=%s popin_missing_chunks=%s popin_collision_missing_chunks=%s popin_missing_max=%s popin_collision_missing_max=%s current_render_ready=%s current_collision_ready=%s ground_misses=%s summary=%s marker=%s\n' \
    "$index" "$MOTION" "${motion_steps:-0}" "${motion_chunks:-0}" "${current_chunk:-n/a}" \
    "${terrain_queue_max:-0}" "${process_wall_p95:-0}" "${gpu_compositor_submit_max:-0}" \
    "${gpu_effective_draws:-0}" "${gpu_upload_fail:-0}" "${packet_queue_max_drain:-0}" \
    "${packet_queue_drained:-0}" "${packet_queue_lag_max:-0}" "${chunk_unload_total:-0}" \
    "${chunk_unload_neighbor_refreshes:-0}" "${chunk_unload_max:-0}" "${popin_missing_chunks:-0}" \
    "${popin_collision_missing_chunks:-0}" "${popin_missing_max:-0}" "${popin_collision_missing_max:-0}" \
    "${current_render_ready:-0}" "${current_collision_ready:-0}" "${ground_misses:-0}" \
    "$summary" "$marker" >> "$SUMMARY_PATH"
}

write_final_summary() {
  tmp_summary="$SUMMARY_PATH.tmp"
  awk \
    -v repeats="$REPEATS" \
    -v motion="$MOTION" \
    -v expected_chunk="$EXPECTED_CHUNK" \
    -v min_chunks="$MIN_CHUNKS" \
    -v target_fps="$TARGET_FPS" \
    -v budget_mode="$BUDGET_MODE" '
    function value_of(key,   i, prefix, value) {
      prefix = key "="
      for (i = 1; i <= NF; i++) {
        if (index($i, prefix) == 1) {
          value = substr($i, length(prefix) + 1)
          gsub(/^"/, "", value)
          gsub(/"$/, "", value)
          return value
        }
      }
      return ""
    }
    /^exploration_soak_run / {
      run_count++
      gpu_upload_fail += value_of("gpu_upload_fail") + 0
      ground_misses += value_of("ground_misses") + 0
      if (value_of("current_render_ready") + 0 == 0) render_not_ready++
      if (value_of("current_collision_ready") + 0 == 0) collision_not_ready++
      if (value_of("terrain_queue_max_ms") + 0 > max_terrain_queue) max_terrain_queue = value_of("terrain_queue_max_ms") + 0
      if (value_of("process_wall_p95_ms") + 0 > max_process_wall_p95) max_process_wall_p95 = value_of("process_wall_p95_ms") + 0
      if (value_of("gpu_compositor_submit_max_ms") + 0 > max_gpu_submit) max_gpu_submit = value_of("gpu_compositor_submit_max_ms") + 0
      if (value_of("gpu_effective_draws") + 0 > max_gpu_effective_draws) max_gpu_effective_draws = value_of("gpu_effective_draws") + 0
      if (value_of("packet_queue_max_drain") + 0 > max_packet_queue_drain) max_packet_queue_drain = value_of("packet_queue_max_drain") + 0
      if (value_of("packet_queue_lag_max_ms") + 0 > max_packet_queue_lag) max_packet_queue_lag = value_of("packet_queue_lag_max_ms") + 0
      if (value_of("chunk_unload_total") + 0 > max_chunk_unload_total) max_chunk_unload_total = value_of("chunk_unload_total") + 0
      if (value_of("chunk_unload_neighbor_refreshes") + 0 > max_chunk_unload_neighbor_refreshes) max_chunk_unload_neighbor_refreshes = value_of("chunk_unload_neighbor_refreshes") + 0
      if (value_of("popin_missing_chunks") + 0 > max_popin_missing_chunks) max_popin_missing_chunks = value_of("popin_missing_chunks") + 0
      if (value_of("popin_collision_missing_chunks") + 0 > max_popin_collision_missing_chunks) max_popin_collision_missing_chunks = value_of("popin_collision_missing_chunks") + 0
    }
    END {
      status = "pass"
      if (run_count != repeats || gpu_upload_fail > 0 || ground_misses > 0 || render_not_ready > 0 || collision_not_ready > 0) {
        status = "fail"
      }
      printf("exploration_soak status=%s repeats=%s completed_runs=%d motion=%s expected_chunk=%s min_chunks=%s target_fps=%s budget_mode=%s max_terrain_queue_ms=%.3f max_process_wall_p95_ms=%.3f max_gpu_compositor_submit_ms=%.3f max_gpu_effective_draws=%d max_packet_queue_drain=%d max_packet_queue_lag_ms=%.3f max_chunk_unload_total=%d max_chunk_unload_neighbor_refreshes=%d max_popin_missing_chunks=%d max_popin_collision_missing_chunks=%d gpu_upload_fail=%d ground_misses=%d render_not_ready_runs=%d collision_not_ready_runs=%d\n", status, repeats, run_count, motion, expected_chunk, min_chunks, target_fps, budget_mode, max_terrain_queue, max_process_wall_p95, max_gpu_submit, max_gpu_effective_draws, max_packet_queue_drain, max_packet_queue_lag, max_chunk_unload_total, max_chunk_unload_neighbor_refreshes, max_popin_missing_chunks, max_popin_collision_missing_chunks, gpu_upload_fail, ground_misses, render_not_ready, collision_not_ready)
    }
  ' "$SUMMARY_PATH" > "$tmp_summary"
  sed -n '1p' "$tmp_summary" > "$tmp_summary.with-runs"
  sed -n '2,$p' "$SUMMARY_PATH" >> "$tmp_summary.with-runs"
  mv "$tmp_summary.with-runs" "$SUMMARY_PATH"
  rm -f "$tmp_summary"
}

case "$REPEATS" in
  ''|*[!0-9]*) fail "RUMPELMC_EXPLORATION_SOAK_REPEATS must be a positive integer" ;;
esac
if [ "$REPEATS" -lt 1 ]; then
  fail "RUMPELMC_EXPLORATION_SOAK_REPEATS must be >= 1"
fi

listener="$(listener_pid || true)"
if [ -n "$listener" ]; then
  fail "port 25565 is already in use; stop the existing server before exploration soak"
fi
trap cleanup_server EXIT HUP INT TERM

if [ "${RUMPELMC_EXPLORATION_SOAK_BUILD_SERVER:-1}" = "1" ]; then
  (
    cd "$ROOT_DIR/server"
    go build -o ./server ./cmd/server
    sign_server_binary_if_possible
  )
fi

rm -f "$SUMMARY_PATH"
printf 'exploration_soak status=running repeats=%s motion=%s expected_chunk=%s min_chunks=%s target_fps=%s budget_mode=%s\n' \
  "$REPEATS" "$MOTION" "$EXPECTED_CHUNK" "$MIN_CHUNKS" "$TARGET_FPS" "$BUDGET_MODE" > "$SUMMARY_PATH"

index=1
while [ "$index" -le "$REPEATS" ]; do
  run_dir="$OUT_DIR/run-$index"
  rm -rf "$run_dir"
  mkdir -p "$run_dir"
  echo "==> world streaming exploration soak: run $index/$REPEATS motion=$MOTION"
  RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE="${RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE:-1}" \
    RUMPELMC_GODOT_RUST_EXT_PROFILE="${RUMPELMC_GODOT_RUST_EXT_PROFILE:-release}" \
    RUMPELMC_SERVER_CHUNK_STREAM_METRICS=1 \
    RUMPELMC_MOVEMENT_STRESS_MOTION="$MOTION" \
    RUMPELMC_MOVEMENT_STRESS_EXPECTED_CHUNK="$EXPECTED_CHUNK" \
    RUMPELMC_MOVEMENT_STRESS_MIN_CHUNKS="$MIN_CHUNKS" \
    RUMPELMC_MOVEMENT_STRESS_STEP_SEC="$STEP_SEC" \
    RUMPELMC_MOVEMENT_STRESS_SETTLE_SEC="$SETTLE_SEC" \
    RUMPELMC_MOVEMENT_STRESS_TARGET_FPS="$TARGET_FPS" \
    RUMPELMC_MOVEMENT_STRESS_BUDGET_MODE="$BUDGET_MODE" \
    RUMPELMC_MOVEMENT_STRESS_PROCESS_WALL_BUDGET_MODE="$PROCESS_WALL_BUDGET_MODE" \
    RUMPELMC_MOVEMENT_STRESS_GPU_COMPOSITOR_BUDGET_MODE="$GPU_COMPOSITOR_BUDGET_MODE" \
    RUMPELMC_MOVEMENT_STRESS_GPU_TIMESTAMP_BUDGET_MODE="$GPU_TIMESTAMP_BUDGET_MODE" \
    /bin/sh "$ROOT_DIR/scripts/gpu_terrain_movement_stress.sh" "$run_dir" > "$run_dir/run.log" 2>&1
  append_run_summary "$index" "$run_dir"
  index=$((index + 1))
done

write_final_summary
cat "$SUMMARY_PATH"
grep -q '^exploration_soak status=pass ' "$SUMMARY_PATH" || fail "soak summary did not pass"
echo "World streaming exploration soak artifacts: $OUT_DIR"
