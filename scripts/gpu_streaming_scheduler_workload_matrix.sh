#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/gpu_streaming_scheduler_workload_matrix_current"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

SUMMARY_PATH="$OUT_DIR/gpu-streaming-scheduler-workload-matrix-summary.txt"
CASES_PATH="$OUT_DIR/gpu-streaming-scheduler-workload-matrix-cases.txt"
PROTOTYPE_SUMMARY="${RUMPELMC_STREAMING_SCHEDULER_MATRIX_PROTOTYPE_SUMMARY:-"$ROOT_DIR/logs/gpu_streaming_scheduler_prototype_current/gpu-streaming-scheduler-prototype-summary.txt"}"
SOURCE_ROOT="${RUMPELMC_STREAMING_SCHEDULER_MATRIX_SOURCE_ROOT:-"$OUT_DIR"}"
RUN_WORKLOADS="${RUMPELMC_STREAMING_SCHEDULER_MATRIX_RUN_WORKLOADS:-0}"
MODES="${RUMPELMC_STREAMING_SCHEDULER_MATRIX_MODES:-nearest directional_tie_preview directional_tie}"
MOTIONS="${RUMPELMC_STREAMING_SCHEDULER_MATRIX_MOTIONS:-chunk_walk_extended chunk_spiral chunk_fly_snap_back}"
TARGET_FPS="${RUMPELMC_STREAMING_SCHEDULER_MATRIX_TARGET_FPS:-150}"
BUDGET_MODE="${RUMPELMC_STREAMING_SCHEDULER_MATRIX_BUDGET_MODE:-enforce}"
PROCESS_WALL_BUDGET_MODE="${RUMPELMC_STREAMING_SCHEDULER_MATRIX_PROCESS_WALL_BUDGET_MODE:-enforce}"
GPU_COMPOSITOR_BUDGET_MODE="${RUMPELMC_STREAMING_SCHEDULER_MATRIX_GPU_COMPOSITOR_BUDGET_MODE:-enforce}"
GPU_TIMESTAMP_BUDGET_MODE="${RUMPELMC_STREAMING_SCHEDULER_MATRIX_GPU_TIMESTAMP_BUDGET_MODE:-report}"
MAX_RELATIVE_BUDGET_REGRESSION_PCT="${RUMPELMC_STREAMING_SCHEDULER_MATRIX_MAX_RELATIVE_BUDGET_REGRESSION_PCT:-50}"
MAX_ABSOLUTE_BUDGET_REGRESSION_MS="${RUMPELMC_STREAMING_SCHEDULER_MATRIX_MAX_ABSOLUTE_BUDGET_REGRESSION_MS:-0.500}"
REQUIRE_RUNTIME_SIGNAL="${RUMPELMC_STREAMING_SCHEDULER_MATRIX_REQUIRE_RUNTIME_SIGNAL:-0}"

fail() {
  echo "gpu_streaming_scheduler_workload_matrix: $*" >&2
  exit 1
}

normalize_path() {
  path="$1"
  case "$path" in
    /*) printf '%s\n' "$path" ;;
    *) printf '%s\n' "$ROOT_DIR/$path" ;;
  esac
}

relative_path() {
  path="$1"
  case "$path" in
    "$ROOT_DIR"/*) printf '%s\n' "${path#$ROOT_DIR/}" ;;
    *) printf '%s\n' "$path" ;;
  esac
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

mode_active_expected() {
  case "$1" in
    nearest|directional_tie_preview) printf '0\n' ;;
    directional_tie) printf '1\n' ;;
    *) fail "unsupported scheduler mode $1" ;;
  esac
}

motion_config() {
  case "$1" in
    chunk_walk_extended) printf '11,8 12 0.45 5.0\n' ;;
    chunk_spiral) printf '0,2 8 0.28 5.0\n' ;;
    chunk_fly_snap_back) printf '0,0 8 0.08 0.65\n' ;;
    chunk_fast_turn) printf '2,2 1 0.08 4.0\n' ;;
    *) fail "unsupported scheduler workload motion $1" ;;
  esac
}

run_or_find_case() {
  mode="$1"
  motion="$2"
  case_dir="$SOURCE_ROOT/$mode/$motion"
  if [ "$RUN_WORKLOADS" = "1" ]; then
    case_dir="$OUT_DIR/$mode/$motion"
    rm -rf "$case_dir"
    mkdir -p "$case_dir"
    set -- $(motion_config "$motion")
    expected_chunk="$1"
    min_chunks="$2"
    step_sec="$3"
    settle_sec="$4"
    echo "==> GPU streaming scheduler matrix mode=$mode motion=$motion" >&2
    set +e
    RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE="${RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE:-1}" \
      RUMPELMC_GODOT_RUST_EXT_PROFILE="${RUMPELMC_GODOT_RUST_EXT_PROFILE:-release}" \
      RUMPELMC_CLIENT_STREAMING_SCHEDULER="$mode" \
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
    lane_exit_code="$?"
    set -e
    printf '%s\n' "$lane_exit_code" > "$case_dir/movement-exit-code.txt"
  fi
  printf '%s\n' "$case_dir"
}

write_case() {
  mode="$1"
  motion="$2"
  case_dir="$(run_or_find_case "$mode" "$motion")"
  summary="$case_dir/movement-stress-summary.txt"
  marker="$case_dir/gpu-terrain-movement-stress.png.txt"
  lane_exit_code_path="$case_dir/movement-exit-code.txt"
  lane_exit_code="0"
  if [ -s "$lane_exit_code_path" ]; then
    lane_exit_code="$(sed -n '1p' "$lane_exit_code_path")"
  fi
  if [ ! -s "$summary" ] || [ ! -s "$marker" ]; then
    printf 'streaming_scheduler_matrix_case mode=%s motion=%s status=fail reason=missing_artifact scheduler_mode=missing scheduler_active=0 expected_scheduler_active=%s scheduler_direction_x=0 scheduler_direction_z=0 preview_mismatch=0 mesh_directional_ties=0 collision_directional_ties=0 fifo_fallbacks=0 motion_steps=0 motion_chunks=0 expected_chunk=missing current_chunk=missing current_chunk_loaded=0 current_render_ready=0 current_chunk_submeshes=0 current_collision_ready=0 current_chunk_collision=0 ground_misses=0 terrain_samples=0 smoke_err=1 gpu_upload_fail=0 gpu_upload_fail_capacity=0 gpu_upload_fail_fragmented=0 gpu_upload_fail_injected=0 chunk_unload_total=0 chunk_unload_neighbor_refreshes=0 chunk_unload_max=0 popin_missing_chunks=0 popin_collision_missing_chunks=0 popin_missing_max=0 popin_collision_missing_max=0 terrain_queue_max_ms=0.000 process_wall_p95_ms=0.000 gpu_compositor_submit_max_ms=0.000 gpu_effective_draws=0 packet_queue_lag_max_ms=0.000 lane_exit_code=%s summary=%s marker=%s\n' \
      "$mode" "$motion" "$(mode_active_expected "$mode")" "$lane_exit_code" "$(relative_path "$summary")" "$(relative_path "$marker")" >> "$CASES_PATH"
    return 0
  fi

  set -- $(motion_config "$motion")
  expected_chunk="$1"
  min_chunks="$2"
  expected_active="$(mode_active_expected "$mode")"

  marker_motion="$(field_metric motion "$marker")"
  motion_steps="$(field_metric motion_steps "$marker")"
  motion_chunks="$(field_metric motion_chunks "$marker")"
  current_chunk="$(field_metric current_chunk "$marker")"
  current_chunk_loaded="$(field_metric current_chunk_loaded "$marker")"
  current_chunk_submeshes="$(field_metric current_chunk_submeshes "$marker")"
  current_chunk_collision="$(field_metric current_chunk_collision "$marker")"
  terrain_samples="$(field_metric terrain_samples "$marker")"
  smoke_err="$(field_metric smoke_err "$marker")"
  gpu_upload_fail="$(field_metric gpu_upload_fail "$marker")"
  gpu_upload_fail_capacity="$(field_metric gpu_upload_fail_capacity "$marker")"
  gpu_upload_fail_fragmented="$(field_metric gpu_upload_fail_fragmented "$marker")"
  gpu_upload_fail_injected="$(field_metric gpu_upload_fail_injected "$marker")"

  terrain_queue_max="$(line_metric movement_terrain_queue max_ms "$summary")"
  process_wall_p95="$(line_metric movement_terrain_queue process_wall_p95_ms "$summary")"
  gpu_submit_max="$(line_metric movement_terrain_queue gpu_compositor_submit_max_ms "$summary")"
  gpu_effective_draws="$(line_metric movement_terrain_queue gpu_effective_draws "$summary")"
  packet_lag_max="$(line_metric movement_packet_queue lag_max_ms "$summary")"
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

  scheduler_mode="$(line_metric movement_stream_scheduler mode "$summary")"
  scheduler_active="$(line_metric movement_stream_scheduler active "$summary")"
  preview_mismatch="$(line_metric movement_stream_scheduler preview_mismatch "$summary")"
  scheduler_direction_x="$(line_metric movement_stream_scheduler direction_x "$summary")"
  scheduler_direction_z="$(line_metric movement_stream_scheduler direction_z "$summary")"
  mesh_directional_ties="$(line_metric movement_stream_scheduler mesh_directional_ties "$summary")"
  collision_directional_ties="$(line_metric movement_stream_scheduler collision_directional_ties "$summary")"
  fifo_fallbacks="$(line_metric movement_stream_scheduler fifo_fallbacks "$summary")"

  awk \
    -v requested_mode="$mode" \
    -v motion="$motion" \
    -v marker_motion="${marker_motion:-}" \
    -v expected_chunk="$expected_chunk" \
    -v min_chunks="$min_chunks" \
    -v motion_steps="${motion_steps:-0}" \
    -v motion_chunks="${motion_chunks:-0}" \
    -v current_chunk="${current_chunk:-}" \
    -v current_chunk_loaded="${current_chunk_loaded:-0}" \
    -v current_chunk_submeshes="${current_chunk_submeshes:-0}" \
    -v current_chunk_collision="${current_chunk_collision:-0}" \
    -v terrain_samples="${terrain_samples:-0}" \
    -v smoke_err="${smoke_err:-1}" \
    -v gpu_upload_fail="${gpu_upload_fail:-0}" \
    -v gpu_upload_fail_capacity="${gpu_upload_fail_capacity:-0}" \
    -v gpu_upload_fail_fragmented="${gpu_upload_fail_fragmented:-0}" \
    -v gpu_upload_fail_injected="${gpu_upload_fail_injected:-0}" \
    -v terrain_queue_max="${terrain_queue_max:-0}" \
    -v process_wall_p95="${process_wall_p95:-0}" \
    -v gpu_submit_max="${gpu_submit_max:-0}" \
    -v gpu_effective_draws="${gpu_effective_draws:-0}" \
    -v packet_lag_max="${packet_lag_max:-0}" \
    -v chunk_unload_total="${chunk_unload_total:-0}" \
    -v chunk_unload_neighbor_refreshes="${chunk_unload_neighbor_refreshes:-0}" \
    -v chunk_unload_max="${chunk_unload_max:-0}" \
    -v popin_missing_chunks="${popin_missing_chunks:-0}" \
    -v popin_collision_missing_chunks="${popin_collision_missing_chunks:-0}" \
    -v popin_missing_max="${popin_missing_max:-0}" \
    -v popin_collision_missing_max="${popin_collision_missing_max:-0}" \
    -v current_render_ready="${current_render_ready:-0}" \
    -v current_collision_ready="${current_collision_ready:-0}" \
    -v ground_misses="${ground_misses:-0}" \
    -v scheduler_mode="${scheduler_mode:-}" \
    -v scheduler_active="${scheduler_active:-0}" \
    -v expected_active="$expected_active" \
    -v preview_mismatch="${preview_mismatch:-0}" \
    -v scheduler_direction_x="${scheduler_direction_x:-0}" \
    -v scheduler_direction_z="${scheduler_direction_z:-0}" \
    -v mesh_directional_ties="${mesh_directional_ties:-0}" \
    -v collision_directional_ties="${collision_directional_ties:-0}" \
    -v fifo_fallbacks="${fifo_fallbacks:-0}" \
    -v lane_exit_code="${lane_exit_code:-0}" \
    -v summary="$(relative_path "$summary")" \
    -v marker="$(relative_path "$marker")" '
    BEGIN {
      status = "pass"
      reason = "ok"
      if (marker_motion != motion) {
        status = "fail"; reason = "wrong_motion"
      } else if (motion_chunks + 0 < min_chunks + 0 || motion_steps + 0 <= 0) {
        status = "fail"; reason = "motion_coverage"
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
      } else if (scheduler_mode != requested_mode || scheduler_active + 0 != expected_active + 0) {
        status = "fail"; reason = "scheduler_mode"
      } else if (lane_exit_code + 0 != 0) {
        status = "fail"; reason = "lane_exit_code"
      }
      printf("streaming_scheduler_matrix_case mode=%s motion=%s status=%s reason=%s scheduler_mode=%s scheduler_active=%d expected_scheduler_active=%d scheduler_direction_x=%d scheduler_direction_z=%d preview_mismatch=%d mesh_directional_ties=%d collision_directional_ties=%d fifo_fallbacks=%d motion_steps=%d motion_chunks=%d expected_chunk=%s current_chunk=%s current_chunk_loaded=%d current_render_ready=%d current_chunk_submeshes=%d current_collision_ready=%d current_chunk_collision=%d ground_misses=%d terrain_samples=%d smoke_err=%d gpu_upload_fail=%d gpu_upload_fail_capacity=%d gpu_upload_fail_fragmented=%d gpu_upload_fail_injected=%d chunk_unload_total=%d chunk_unload_neighbor_refreshes=%d chunk_unload_max=%d popin_missing_chunks=%d popin_collision_missing_chunks=%d popin_missing_max=%d popin_collision_missing_max=%d terrain_queue_max_ms=%.3f process_wall_p95_ms=%.3f gpu_compositor_submit_max_ms=%.3f gpu_effective_draws=%d packet_queue_lag_max_ms=%.3f lane_exit_code=%d summary=%s marker=%s\n", requested_mode, motion, status, reason, scheduler_mode, scheduler_active, expected_active, scheduler_direction_x, scheduler_direction_z, preview_mismatch, mesh_directional_ties, collision_directional_ties, fifo_fallbacks, motion_steps, motion_chunks, expected_chunk, current_chunk, current_chunk_loaded, current_render_ready, current_chunk_submeshes, current_collision_ready, current_chunk_collision, ground_misses, terrain_samples, smoke_err, gpu_upload_fail, gpu_upload_fail_capacity, gpu_upload_fail_fragmented, gpu_upload_fail_injected, chunk_unload_total, chunk_unload_neighbor_refreshes, chunk_unload_max, popin_missing_chunks, popin_collision_missing_chunks, popin_missing_max, popin_collision_missing_max, terrain_queue_max, process_wall_p95, gpu_submit_max, gpu_effective_draws, packet_lag_max, lane_exit_code, summary, marker)
    }
  ' >> "$CASES_PATH"
}

case "$RUN_WORKLOADS" in
  0|1) ;;
  *) fail "RUMPELMC_STREAMING_SCHEDULER_MATRIX_RUN_WORKLOADS must be 0 or 1" ;;
esac
case "$REQUIRE_RUNTIME_SIGNAL" in
  0|1) ;;
  *) fail "RUMPELMC_STREAMING_SCHEDULER_MATRIX_REQUIRE_RUNTIME_SIGNAL must be 0 or 1" ;;
esac

mkdir -p "$OUT_DIR"
PROTOTYPE_SUMMARY="$(normalize_path "$PROTOTYPE_SUMMARY")"
SOURCE_ROOT="$(normalize_path "$SOURCE_ROOT")"
test -s "$PROTOTYPE_SUMMARY" || fail "missing scheduler prototype summary $PROTOTYPE_SUMMARY"
test "$(field_metric status "$PROTOTYPE_SUMMARY")" = "pass" || fail "scheduler prototype summary did not pass"
test "$(field_metric default_scheduler_mode "$PROTOTYPE_SUMMARY")" = "nearest" || fail "scheduler default is no longer nearest"
test "$(field_metric stream_scheduler_active_default "$PROTOTYPE_SUMMARY")" = "0" || fail "scheduler default is active"

: > "$CASES_PATH"
for mode in $MODES; do
  mode_active_expected "$mode" >/dev/null
  for motion in $MOTIONS; do
    motion_config "$motion" >/dev/null
    write_case "$mode" "$motion"
  done
done

expected_modes_count=$(set -- $MODES; printf '%s\n' "$#")
expected_motions_count=$(set -- $MOTIONS; printf '%s\n' "$#")
expected_cases=$((expected_modes_count * expected_motions_count))

awk \
  -v modes="$MODES" \
  -v motions="$MOTIONS" \
  -v expected_cases="$expected_cases" \
  -v max_relative_budget_regression_pct="$MAX_RELATIVE_BUDGET_REGRESSION_PCT" \
  -v max_absolute_budget_regression_ms="$MAX_ABSOLUTE_BUDGET_REGRESSION_MS" \
  -v require_runtime_signal="$REQUIRE_RUNTIME_SIGNAL" \
  -v prototype_summary="$(relative_path "$PROTOTYPE_SUMMARY")" \
  -v cases_path="$(relative_path "$CASES_PATH")" \
  -v run_workloads="$RUN_WORKLOADS" \
  -v source_root="$(relative_path "$SOURCE_ROOT")" \
  -v target_fps="$TARGET_FPS" '
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
  function max_value(current, candidate,   value) {
    value = candidate + 0
    if (value > current) return value
    return current
  }
  function budget_allowed(base) {
    return (base + 0.0) * (1.0 + (max_relative_budget_regression_pct + 0.0) / 100.0) + (max_absolute_budget_regression_ms + 0.0)
  }
  BEGIN {
    split(modes, expected_modes, " ")
    split(motions, expected_motions, " ")
    for (i in expected_modes) {
      mode_seen[expected_modes[i]] = 0
    }
    for (i in expected_motions) {
      motion_seen[expected_motions[i]] = 0
    }
  }
  $1 == "streaming_scheduler_matrix_case" {
    case_count++
    mode = value_of("mode")
    motion = value_of("motion")
    status = value_of("status")
    mode_seen[mode] = 1
    motion_seen[motion] = 1
    case_seen[mode SUBSEP motion] = 1
    if (status != "pass") failed_cases++
    if (status != "pass" && mode == "nearest") baseline_failed_cases++
    if (status != "pass" && mode == "directional_tie_preview") preview_failed_cases++
    if (status != "pass" && mode == "directional_tie") active_failed_cases++
    if (status == "pass" && mode == "nearest") baseline_pass_cases++
    if (status == "pass" && mode == "directional_tie_preview") preview_pass_cases++
    if (status == "pass" && mode == "directional_tie") active_pass_cases++

    queue = value_of("terrain_queue_max_ms") + 0.0
    process = value_of("process_wall_p95_ms") + 0.0
    submit = value_of("gpu_compositor_submit_max_ms") + 0.0
    packet_lag = value_of("packet_queue_lag_max_ms") + 0.0
    preview_mismatch = value_of("preview_mismatch") + 0
    mesh_ties = value_of("mesh_directional_ties") + 0
    collision_ties = value_of("collision_directional_ties") + 0
    fifo_fallbacks = value_of("fifo_fallbacks") + 0
    popin_missing = value_of("popin_missing_chunks") + 0
    popin_collision_missing = value_of("popin_collision_missing_chunks") + 0

    max_terrain_queue_ms = max_value(max_terrain_queue_ms, queue)
    max_process_wall_p95_ms = max_value(max_process_wall_p95_ms, process)
    max_gpu_compositor_submit_ms = max_value(max_gpu_compositor_submit_ms, submit)
    max_packet_queue_lag_ms = max_value(max_packet_queue_lag_ms, packet_lag)
    max_stream_scheduler_preview_mismatch = max_value(max_stream_scheduler_preview_mismatch, preview_mismatch)
    max_mesh_scheduler_directional_ties = max_value(max_mesh_scheduler_directional_ties, mesh_ties)
    max_collision_scheduler_directional_ties = max_value(max_collision_scheduler_directional_ties, collision_ties)
    max_stream_scheduler_fifo_fallbacks = max_value(max_stream_scheduler_fifo_fallbacks, fifo_fallbacks)
    max_popin_missing_chunks = max_value(max_popin_missing_chunks, popin_missing)
    max_popin_collision_missing_chunks = max_value(max_popin_collision_missing_chunks, popin_collision_missing)
    runtime_signal += preview_mismatch + mesh_ties + collision_ties

    queue_by_case[mode SUBSEP motion] = queue
    process_by_case[mode SUBSEP motion] = process
    submit_by_case[mode SUBSEP motion] = submit
  }
  END {
    for (i in expected_modes) {
      mode = expected_modes[i]
      if (mode_seen[mode] != 1) missing_modes++
      for (j in expected_motions) {
        motion = expected_motions[j]
        if (case_seen[mode SUBSEP motion] != 1) missing_cases++
      }
    }
    for (i in expected_motions) {
      motion = expected_motions[i]
      if (motion_seen[motion] != 1) missing_motions++
      base_key = "nearest" SUBSEP motion
      if (case_seen[base_key] != 1) {
        regression_cases++
        continue
      }
      base_queue = queue_by_case[base_key]
      base_process = process_by_case[base_key]
      base_submit = submit_by_case[base_key]
      for (j in expected_modes) {
        mode = expected_modes[j]
        if (mode == "nearest") continue
        key = mode SUBSEP motion
        if (case_seen[key] != 1) continue
        if (queue_by_case[key] > budget_allowed(base_queue) || process_by_case[key] > budget_allowed(base_process) || submit_by_case[key] > budget_allowed(base_submit)) {
          regression_cases++
          if (mode == "directional_tie") active_regression_cases++
          if (mode == "directional_tie_preview") preview_regression_cases++
        }
      }
    }

    matrix_harness_status = "complete"
    if (baseline_failed_cases > 0 || preview_failed_cases > 0 || preview_regression_cases > 0) {
      matrix_harness_status = "partial"
    }

    candidate_scheduler_status = "matrix_runtime_healthy"
    if (matrix_harness_status == "partial") {
      candidate_scheduler_status = "defer_matrix_harness_unstable"
    } else if (active_failed_cases > 0 || active_regression_cases > 0) {
      candidate_scheduler_status = "reject_runtime_regression"
    } else if (runtime_signal + 0 == 0) {
      candidate_scheduler_status = "defer_no_runtime_signal"
    } else {
      candidate_scheduler_status = "defer_external_profiler_required"
    }

    status = "pass"
    reason = "ok"
    if (case_count != expected_cases || missing_modes > 0 || missing_motions > 0 || missing_cases > 0) {
      status = "fail"; reason = "missing_cases"
    } else if (baseline_pass_cases == 0 || preview_pass_cases == 0) {
      status = "fail"; reason = "missing_baseline_or_preview_pass"
    } else if (require_runtime_signal + 0 == 1 && runtime_signal + 0 == 0) {
      status = "fail"; reason = "missing_runtime_signal"
    }

    printf("gpu_streaming_scheduler_workload_matrix status=%s reason=%s matrix_harness_status=%s modes=\"%s\" motions=\"%s\" expected_cases=%d completed_cases=%d failed_cases=%d baseline_pass_cases=%d preview_pass_cases=%d active_pass_cases=%d baseline_failed_cases=%d preview_failed_cases=%d active_failed_cases=%d missing_modes=%d missing_motions=%d missing_cases=%d regression_cases=%d preview_regression_cases=%d active_regression_cases=%d run_workloads=%s target_fps=%s max_relative_budget_regression_pct=%s max_absolute_budget_regression_ms=%s require_runtime_signal=%s runtime_signal=%d max_stream_scheduler_preview_mismatch=%d max_mesh_scheduler_directional_ties=%d max_collision_scheduler_directional_ties=%d max_stream_scheduler_fifo_fallbacks=%d max_popin_missing_chunks=%d max_popin_collision_missing_chunks=%d max_terrain_queue_ms=%.3f max_process_wall_p95_ms=%.3f max_gpu_compositor_submit_ms=%.3f max_packet_queue_lag_ms=%.3f scheduler_change_allowed=0 default_runtime_change_allowed=0 candidate_scheduler_status=%s external_profile_status=pending_external_profiler requires_external_profiler_before_default=1 requires_mac_windows_validation=1 prototype_summary=%s source_root=%s cases=%s\n", status, reason, matrix_harness_status, modes, motions, expected_cases, case_count, failed_cases, baseline_pass_cases, preview_pass_cases, active_pass_cases, baseline_failed_cases, preview_failed_cases, active_failed_cases, missing_modes, missing_motions, missing_cases, regression_cases, preview_regression_cases, active_regression_cases, run_workloads, target_fps, max_relative_budget_regression_pct, max_absolute_budget_regression_ms, require_runtime_signal, runtime_signal, max_stream_scheduler_preview_mismatch, max_mesh_scheduler_directional_ties, max_collision_scheduler_directional_ties, max_stream_scheduler_fifo_fallbacks, max_popin_missing_chunks, max_popin_collision_missing_chunks, max_terrain_queue_ms, max_process_wall_p95_ms, max_gpu_compositor_submit_ms, max_packet_queue_lag_ms, candidate_scheduler_status, prototype_summary, source_root, cases_path)
  }
' "$CASES_PATH" > "$SUMMARY_PATH"

cat "$SUMMARY_PATH"
cat "$CASES_PATH"
grep -q '^gpu_streaming_scheduler_workload_matrix status=pass ' "$SUMMARY_PATH" || fail "streaming scheduler workload matrix did not pass"
echo "GPU streaming scheduler workload matrix artifacts: $OUT_DIR"
