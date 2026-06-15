#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/world_streaming_high_pressure_suite"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

CASES="${RUMPELMC_WORLD_LOAD_SUITE_CASES:-startup-cold startup-warm long-move spiral fast-turn teleport-snap high-view high-resident}"
SUMMARY_PATH="$OUT_DIR/world-load-suite-summary.txt"
TARGET_FPS="${RUMPELMC_WORLD_LOAD_SUITE_TARGET_FPS:-150}"
BUDGET_MODE="${RUMPELMC_WORLD_LOAD_SUITE_BUDGET_MODE:-report}"
PROCESS_WALL_BUDGET_MODE="${RUMPELMC_WORLD_LOAD_SUITE_PROCESS_WALL_BUDGET_MODE:-report}"
GPU_COMPOSITOR_BUDGET_MODE="${RUMPELMC_WORLD_LOAD_SUITE_GPU_COMPOSITOR_BUDGET_MODE:-report}"
GPU_TIMESTAMP_BUDGET_MODE="${RUMPELMC_WORLD_LOAD_SUITE_GPU_TIMESTAMP_BUDGET_MODE:-report}"
SERVER_CHUNK_ORDER="${RUMPELMC_SERVER_CHUNK_ORDER:-nearest}"

mkdir -p "$OUT_DIR"

fail() {
  echo "world_streaming_high_pressure_suite: $*" >&2
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

append_movement_summary() {
  label="$1"
  motion="$2"
  case_dir="$3"
  summary="$case_dir/movement-stress-summary.txt"
  marker="$case_dir/gpu-terrain-movement-stress.png.txt"

  test -s "$summary" || fail "missing movement summary for $label: $summary"
  test -s "$marker" || fail "missing movement marker for $label: $marker"

  terrain_queue_max="$(line_metric movement_terrain_queue max_ms "$summary")"
  process_wall_p95="$(line_metric movement_terrain_queue process_wall_p95_ms "$summary")"
  compositor_submit_max="$(line_metric movement_terrain_queue gpu_compositor_submit_max_ms "$summary")"
  queue_upload_kb_max="$(line_metric movement_terrain_queue queue_upload_kb_max "$summary")"
  gpu_effective_draws="$(line_metric movement_terrain_queue gpu_effective_draws "$summary")"
  startup_packet="$(line_metric movement_startup packet_ms "$summary")"
  startup_queue_lag="$(line_metric movement_startup packet_queue_lag_ms "$summary")"
  startup_chunk_decode="$(line_metric movement_startup chunk_decode_work_ms "$summary")"
  startup_first_mesh_work="$(line_metric movement_startup first_mesh_work_ms "$summary")"
  startup_collision_work="$(line_metric movement_startup first_mesh_collision_work_ms "$summary")"
  startup_player_spawn="$(line_metric movement_startup player_spawn_ms "$summary")"
  packet_queue_max_drain="$(line_metric movement_packet_queue max_drain "$summary")"
  packet_queue_drained="$(line_metric movement_packet_queue drained "$summary")"
  packet_queue_lag_max="$(line_metric movement_packet_queue lag_max_ms "$summary")"
  packet_queue_decode_work_max="$(line_metric movement_packet_queue decode_work_max_ms "$summary")"
  chunk_unload_total="$(line_metric movement_chunk_unload unloaded "$summary")"
  chunk_unload_grace_kept="$(line_metric movement_chunk_unload grace_kept "$summary")"
  chunk_unload_neighbor_refreshes="$(line_metric movement_chunk_unload neighbor_refreshes "$summary")"
  chunk_unload_max="$(line_metric movement_chunk_unload max_unloaded "$summary")"
  chunk_unload_max_grace_kept="$(line_metric movement_chunk_unload max_grace_kept "$summary")"
  popin_missing_chunks="$(line_metric movement_popin missing_chunks "$summary")"
  popin_collision_missing_chunks="$(line_metric movement_popin collision_missing_chunks "$summary")"
  popin_missing_max="$(line_metric movement_popin missing_max "$summary")"
  popin_collision_missing_max="$(line_metric movement_popin collision_missing_max "$summary")"
  popin_probe_radius="$(line_metric movement_popin probe_radius "$summary")"
  current_render_ready="$(line_metric movement_readiness current_render_ready "$summary")"
  current_collision_ready="$(line_metric movement_readiness current_collision_ready "$summary")"
  readiness_ground_misses="$(line_metric movement_readiness ground_misses "$summary")"
  motion_steps="$(field_metric motion_steps "$marker")"
  motion_chunks="$(field_metric motion_chunks "$marker")"
  current_chunk="$(field_metric current_chunk "$marker")"
  gpu_upload_fail="$(field_metric gpu_upload_fail "$marker")"
  terrain_samples="$(field_metric terrain_samples "$marker")"

  printf 'world_load_suite_case label=%s type=movement status=pass motion=%s motion_steps=%s motion_chunks=%s current_chunk=%s terrain_samples=%s terrain_queue_max_ms=%s process_wall_p95_ms=%s gpu_compositor_submit_max_ms=%s queue_upload_kb_max=%s gpu_effective_draws=%s gpu_upload_fail=%s packet_queue_max_drain=%s packet_queue_drained=%s packet_queue_lag_max_ms=%s packet_queue_decode_work_max_ms=%s chunk_unload_total=%s chunk_unload_grace_kept=%s chunk_unload_neighbor_refreshes=%s chunk_unload_max=%s chunk_unload_max_grace_kept=%s popin_missing_chunks=%s popin_collision_missing_chunks=%s popin_missing_max=%s popin_collision_missing_max=%s popin_probe_radius=%s current_render_ready=%s current_collision_ready=%s readiness_ground_misses=%s startup_packet_ms=%s startup_packet_queue_lag_ms=%s startup_chunk_decode_work_ms=%s startup_first_mesh_work_ms=%s startup_first_mesh_collision_work_ms=%s startup_player_spawn_ms=%s summary=%s marker=%s\n' \
    "$label" "$motion" "${motion_steps:-0}" "${motion_chunks:-0}" "${current_chunk:-n/a}" "${terrain_samples:-0}" \
    "${terrain_queue_max:-0}" "${process_wall_p95:-0}" "${compositor_submit_max:-0}" "${queue_upload_kb_max:-0}" \
    "${gpu_effective_draws:-0}" "${gpu_upload_fail:-0}" "${packet_queue_max_drain:-0}" "${packet_queue_drained:-0}" \
    "${packet_queue_lag_max:-0}" "${packet_queue_decode_work_max:-0}" "${chunk_unload_total:-0}" \
    "${chunk_unload_grace_kept:-0}" "${chunk_unload_neighbor_refreshes:-0}" "${chunk_unload_max:-0}" \
    "${chunk_unload_max_grace_kept:-0}" "${popin_missing_chunks:-0}" "${popin_collision_missing_chunks:-0}" \
    "${popin_missing_max:-0}" "${popin_collision_missing_max:-0}" "${popin_probe_radius:-0}" \
    "${current_render_ready:-0}" "${current_collision_ready:-0}" "${readiness_ground_misses:-0}" \
    "${startup_packet:-0}" "${startup_queue_lag:-0}" \
    "${startup_chunk_decode:-0}" "${startup_first_mesh_work:-0}" "${startup_collision_work:-0}" "${startup_player_spawn:-0}" \
    "$summary" "$marker" >> "$SUMMARY_PATH"
}

run_movement_case() {
  label="$1"
  motion="$2"
  expected_chunk="$3"
  min_chunks="$4"
  step_sec="$5"
  settle_sec="$6"
  server_view_distance="$7"
  client_keep_distance="$8"
  case_dir="$OUT_DIR/$label"

  rm -rf "$case_dir"
  mkdir -p "$case_dir"
  echo "==> world load suite: $label motion=$motion"
  RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE="${RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE:-1}" \
    RUMPELMC_GODOT_RUST_EXT_PROFILE="${RUMPELMC_GODOT_RUST_EXT_PROFILE:-release}" \
    RUMPELMC_SERVER_CHUNK_STREAM_METRICS=1 \
    RUMPELMC_SERVER_VIEW_DISTANCE="$server_view_distance" \
    RUMPELMC_CLIENT_KEEP_CHUNK_DISTANCE="$client_keep_distance" \
    RUMPELMC_MOVEMENT_STRESS_MOTION="$motion" \
    RUMPELMC_MOVEMENT_STRESS_EXPECTED_CHUNK="$expected_chunk" \
    RUMPELMC_MOVEMENT_STRESS_MIN_CHUNKS="$min_chunks" \
    RUMPELMC_MOVEMENT_STRESS_STEP_SEC="$step_sec" \
    RUMPELMC_MOVEMENT_STRESS_SETTLE_SEC="$settle_sec" \
    RUMPELMC_MOVEMENT_STRESS_TARGET_FPS="$TARGET_FPS" \
    RUMPELMC_MOVEMENT_STRESS_BUDGET_MODE="$BUDGET_MODE" \
    RUMPELMC_MOVEMENT_STRESS_PROCESS_WALL_BUDGET_MODE="$PROCESS_WALL_BUDGET_MODE" \
    RUMPELMC_MOVEMENT_STRESS_GPU_COMPOSITOR_BUDGET_MODE="$GPU_COMPOSITOR_BUDGET_MODE" \
    RUMPELMC_MOVEMENT_STRESS_GPU_TIMESTAMP_BUDGET_MODE="$GPU_TIMESTAMP_BUDGET_MODE" \
    /bin/sh "$ROOT_DIR/scripts/gpu_terrain_movement_stress.sh" "$case_dir" > "$case_dir/run.log" 2>&1
  append_movement_summary "$label" "$motion" "$case_dir"
}

append_workload_summary() {
  label="$1"
  case_dir="$2"
  summary="$case_dir/workload-matrix-summary.txt"
  test -s "$summary" || fail "missing workload summary for $label: $summary"

  awk -v label="$label" -v summary="$summary" '
    $1 == "GPU" || NF == 0 { next }
    {
      for (i = 1; i <= NF; i++) {
        split($i, kv, "=")
        key = kv[1]
        value = kv[2] + 0
        if (key == "gpu_subchunks" && value > max_subchunks) max_subchunks = value
        if (key == "gpu_draws" && value > max_draws) max_draws = value
        if (key == "gpu_faces" && value > max_faces) max_faces = value
        if (key == "terrain_queue_max_ms" && value > max_queue) max_queue = value
        if (key == "process_wall_p95_ms" && value > max_process) max_process = value
        if (key == "gpu_compositor_submit_max_ms" && value > max_submit) max_submit = value
        if (key == "gpu_upload_fail") upload_fail += value
        if (key == "gpu_upload_fail_capacity") upload_fail_capacity += value
        if (key == "gpu_upload_fail_fragmented") upload_fail_fragmented += value
      }
    }
    END {
      printf("world_load_suite_case label=%s type=workload status=pass max_gpu_subchunks=%d max_gpu_draws=%d max_gpu_faces=%d max_terrain_queue_ms=%.3f max_process_wall_p95_ms=%.3f max_gpu_compositor_submit_ms=%.3f gpu_upload_fail=%d gpu_upload_fail_capacity=%d gpu_upload_fail_fragmented=%d summary=%s\n", label, max_subchunks, max_draws, max_faces, max_queue, max_process, max_submit, upload_fail, upload_fail_capacity, upload_fail_fragmented, summary)
    }
  ' "$summary" >> "$SUMMARY_PATH"
}

run_workload_case() {
  label="$1"
  case_set="$2"
  server_view_distance="$3"
  client_keep_distance="$4"
  case_dir="$OUT_DIR/$label"

  rm -rf "$case_dir"
  mkdir -p "$case_dir"
  echo "==> world load suite: $label workload case_set=$case_set"
  RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE="${RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE:-1}" \
    RUMPELMC_GODOT_RUST_EXT_PROFILE="${RUMPELMC_GODOT_RUST_EXT_PROFILE:-release}" \
    RUMPELMC_WORKLOAD_MATRIX_CASE_SET="$case_set" \
    RUMPELMC_WORKLOAD_MATRIX_TARGET_FPS="$TARGET_FPS" \
    RUMPELMC_WORKLOAD_MATRIX_SERVER_VIEW_DISTANCE="$server_view_distance" \
    RUMPELMC_WORKLOAD_MATRIX_CLIENT_KEEP_CHUNK_DISTANCE="$client_keep_distance" \
    /bin/sh "$ROOT_DIR/scripts/gpu_terrain_workload_matrix.sh" "$case_dir" > "$case_dir/run.log" 2>&1
  append_workload_summary "$label" "$case_dir"
}

run_case() {
  case_name="$1"
  case "$case_name" in
    startup-cold)
      cleanup_server
      run_movement_case startup-cold chunk_walk 3,2 4 0.55 4.0 "" ""
      ;;
    startup-warm)
      run_movement_case startup-warm chunk_walk 3,2 4 0.55 4.0 "" ""
      ;;
    long-move)
      run_movement_case long-move chunk_walk_extended 11,8 12 0.45 5.0 "" ""
      ;;
    spiral)
      run_movement_case spiral chunk_spiral 0,2 8 0.28 5.0 "" ""
      ;;
    fast-turn)
      run_movement_case fast-turn chunk_fast_turn 2,2 1 0.08 4.0 "" ""
      ;;
    teleport-snap)
      run_movement_case teleport-snap chunk_fly_snap_back 0,0 8 0.08 0.65 "" ""
      ;;
    high-view)
      run_movement_case high-view chunk_walk_long 7,5 8 0.35 8.0 14 14
      ;;
    high-resident)
      run_workload_case high-resident heavy 14 14
      ;;
    *)
      fail "unknown suite case $case_name"
      ;;
  esac
}

listener="$(listener_pid || true)"
if [ -n "$listener" ]; then
  fail "port 25565 is already in use; stop the existing server before high-pressure suite"
fi
trap cleanup_server EXIT HUP INT TERM

if [ "${RUMPELMC_WORLD_LOAD_SUITE_BUILD_SERVER:-1}" = "1" ]; then
  (
    cd "$ROOT_DIR/server"
    go build -o ./server ./cmd/server
    sign_server_binary_if_possible
  )
fi

rm -f "$SUMMARY_PATH"
printf 'world_load_suite status=running cases="%s" target_fps=%s server_chunk_order=%s budget_mode=%s process_wall_budget_mode=%s gpu_compositor_budget_mode=%s gpu_timestamp_budget_mode=%s\n' \
  "$CASES" "$TARGET_FPS" "$SERVER_CHUNK_ORDER" "$BUDGET_MODE" "$PROCESS_WALL_BUDGET_MODE" "$GPU_COMPOSITOR_BUDGET_MODE" "$GPU_TIMESTAMP_BUDGET_MODE" > "$SUMMARY_PATH"

for case_name in $CASES; do
  run_case "$case_name"
done

tmp_summary="$SUMMARY_PATH.tmp"
{
  printf 'world_load_suite status=pass cases="%s" target_fps=%s server_chunk_order=%s budget_mode=%s process_wall_budget_mode=%s gpu_compositor_budget_mode=%s gpu_timestamp_budget_mode=%s\n' \
    "$CASES" "$TARGET_FPS" "$SERVER_CHUNK_ORDER" "$BUDGET_MODE" "$PROCESS_WALL_BUDGET_MODE" "$GPU_COMPOSITOR_BUDGET_MODE" "$GPU_TIMESTAMP_BUDGET_MODE"
  sed -n '2,$p' "$SUMMARY_PATH"
} > "$tmp_summary"
mv "$tmp_summary" "$SUMMARY_PATH"

cat "$SUMMARY_PATH"
echo "World streaming high-pressure suite artifacts: $OUT_DIR"
