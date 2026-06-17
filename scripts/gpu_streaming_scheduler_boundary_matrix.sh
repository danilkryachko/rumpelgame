#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/gpu_streaming_scheduler_boundary_matrix_current"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

SUMMARY_PATH="$OUT_DIR/gpu-streaming-scheduler-boundary-matrix-summary.txt"
CASES_PATH="$OUT_DIR/gpu-streaming-scheduler-boundary-matrix-cases.txt"
PROTOTYPE_SUMMARY="${RUMPELMC_STREAMING_SCHEDULER_BOUNDARY_MATRIX_PROTOTYPE_SUMMARY:-"$ROOT_DIR/logs/gpu_streaming_scheduler_prototype_current/gpu-streaming-scheduler-prototype-summary.txt"}"
SOURCE_ROOT="${RUMPELMC_STREAMING_SCHEDULER_BOUNDARY_MATRIX_SOURCE_ROOT:-"$OUT_DIR"}"
RUN_WORKLOADS="${RUMPELMC_STREAMING_SCHEDULER_BOUNDARY_MATRIX_RUN_WORKLOADS:-0}"
MODES="${RUMPELMC_STREAMING_SCHEDULER_BOUNDARY_MATRIX_MODES:-nearest directional_tie_preview directional_tie}"
CASES="${RUMPELMC_STREAMING_SCHEDULER_BOUNDARY_MATRIX_CASES:-fast-turn teleport-snap}"
TARGET_FPS="${RUMPELMC_STREAMING_SCHEDULER_BOUNDARY_MATRIX_TARGET_FPS:-150}"
BUDGET_MODE="${RUMPELMC_STREAMING_SCHEDULER_BOUNDARY_MATRIX_BUDGET_MODE:-report}"
PROCESS_WALL_BUDGET_MODE="${RUMPELMC_STREAMING_SCHEDULER_BOUNDARY_MATRIX_PROCESS_WALL_BUDGET_MODE:-report}"
GPU_COMPOSITOR_BUDGET_MODE="${RUMPELMC_STREAMING_SCHEDULER_BOUNDARY_MATRIX_GPU_COMPOSITOR_BUDGET_MODE:-report}"
GPU_TIMESTAMP_BUDGET_MODE="${RUMPELMC_STREAMING_SCHEDULER_BOUNDARY_MATRIX_GPU_TIMESTAMP_BUDGET_MODE:-report}"
MAX_RELATIVE_BUDGET_REGRESSION_PCT="${RUMPELMC_STREAMING_SCHEDULER_BOUNDARY_MATRIX_MAX_RELATIVE_BUDGET_REGRESSION_PCT:-50}"
MAX_ABSOLUTE_BUDGET_REGRESSION_MS="${RUMPELMC_STREAMING_SCHEDULER_BOUNDARY_MATRIX_MAX_ABSOLUTE_BUDGET_REGRESSION_MS:-0.500}"
REQUIRE_RUNTIME_SIGNAL="${RUMPELMC_STREAMING_SCHEDULER_BOUNDARY_MATRIX_REQUIRE_RUNTIME_SIGNAL:-0}"

fail() {
  echo "gpu_streaming_scheduler_boundary_matrix: $*" >&2
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

mode_active_expected() {
  case "$1" in
    nearest|directional_tie_preview) printf '0\n' ;;
    directional_tie) printf '1\n' ;;
    *) fail "unsupported scheduler mode $1" ;;
  esac
}

run_or_find_mode() {
  mode="$1"
  mode_dir="$SOURCE_ROOT/$mode"
  if [ "$RUN_WORKLOADS" = "1" ]; then
    mode_dir="$OUT_DIR/$mode"
    rm -rf "$mode_dir"
    mkdir -p "$mode_dir"
    echo "==> GPU streaming scheduler boundary matrix mode=$mode cases=$CASES" >&2
    set +e
    RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE="${RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE:-1}" \
      RUMPELMC_GODOT_RUST_EXT_PROFILE="${RUMPELMC_GODOT_RUST_EXT_PROFILE:-release}" \
      RUMPELMC_CLIENT_STREAMING_SCHEDULER="$mode" \
      RUMPELMC_CHUNK_BOUNDARY_CASES="$CASES" \
      RUMPELMC_CHUNK_BOUNDARY_TARGET_FPS="$TARGET_FPS" \
      RUMPELMC_CHUNK_BOUNDARY_BUDGET_MODE="$BUDGET_MODE" \
      RUMPELMC_CHUNK_BOUNDARY_PROCESS_WALL_BUDGET_MODE="$PROCESS_WALL_BUDGET_MODE" \
      RUMPELMC_CHUNK_BOUNDARY_GPU_COMPOSITOR_BUDGET_MODE="$GPU_COMPOSITOR_BUDGET_MODE" \
      RUMPELMC_CHUNK_BOUNDARY_GPU_TIMESTAMP_BUDGET_MODE="$GPU_TIMESTAMP_BUDGET_MODE" \
      RUMPELMC_CHUNK_BOUNDARY_REQUIRE_NO_UNLOAD=1 \
      /bin/sh "$ROOT_DIR/scripts/gpu_terrain_chunk_boundary_stress.sh" "$mode_dir" > "$mode_dir/run.log" 2>&1
    lane_exit_code="$?"
    set -e
    printf '%s\n' "$lane_exit_code" > "$mode_dir/boundary-exit-code.txt"
  fi
  printf '%s\n' "$mode_dir"
}

write_mode_cases() {
  mode="$1"
  mode_dir="$(run_or_find_mode "$mode")"
  summary="$mode_dir/chunk-boundary-stress-summary.txt"
  lane_exit_code_path="$mode_dir/boundary-exit-code.txt"
  lane_exit_code="0"
  expected_active="$(mode_active_expected "$mode")"
  if [ -s "$lane_exit_code_path" ]; then
    lane_exit_code="$(sed -n '1p' "$lane_exit_code_path")"
  fi

  if [ ! -s "$summary" ]; then
    for case_name in $CASES; do
      printf 'streaming_scheduler_boundary_case mode=%s label=%s status=fail reason=missing_artifact scheduler_mode=missing scheduler_active=0 expected_scheduler_active=%s scheduler_direction_x=0 scheduler_direction_z=0 preview_mismatch=0 mesh_directional_ties=0 collision_directional_ties=0 fifo_fallbacks=0 motion=missing expected_chunk=missing current_chunk=missing motion_steps=0 motion_chunks=0 current_render_ready=0 current_collision_ready=0 ground_misses=0 terrain_samples=0 gpu_upload_fail=0 chunk_unload_total=0 chunk_unload_neighbor_refreshes=0 chunk_unload_max=0 popin_missing_chunks=0 popin_collision_missing_chunks=0 terrain_queue_max_ms=0.000 process_wall_p95_ms=0.000 gpu_compositor_submit_max_ms=0.000 gpu_effective_draws=0 packet_queue_lag_max_ms=0.000 lane_exit_code=%s summary=%s\n' \
        "$mode" "$case_name" "$expected_active" "$lane_exit_code" "$(relative_path "$summary")" >> "$CASES_PATH"
    done
    return 0
  fi

  awk \
    -v mode="$mode" \
    -v expected_active="$expected_active" \
    -v cases="$CASES" \
    -v lane_exit_code="$lane_exit_code" \
    -v summary="$(relative_path "$summary")" '
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
    function emit_missing(label) {
      printf("streaming_scheduler_boundary_case mode=%s label=%s status=fail reason=missing_case scheduler_mode=missing scheduler_active=0 expected_scheduler_active=%d scheduler_direction_x=0 scheduler_direction_z=0 preview_mismatch=0 mesh_directional_ties=0 collision_directional_ties=0 fifo_fallbacks=0 motion=missing expected_chunk=missing current_chunk=missing motion_steps=0 motion_chunks=0 current_render_ready=0 current_collision_ready=0 ground_misses=0 terrain_samples=0 gpu_upload_fail=0 chunk_unload_total=0 chunk_unload_neighbor_refreshes=0 chunk_unload_max=0 popin_missing_chunks=0 popin_collision_missing_chunks=0 terrain_queue_max_ms=0.000 process_wall_p95_ms=0.000 gpu_compositor_submit_max_ms=0.000 gpu_effective_draws=0 packet_queue_lag_max_ms=0.000 lane_exit_code=%s summary=%s\n", mode, label, expected_active, lane_exit_code, summary)
    }
    BEGIN {
      split(cases, requested, " ")
      for (i in requested) {
        requested_seen[requested[i]] = 0
      }
    }
    $1 == "chunk_boundary_case" {
      label = value_of("label")
      if (!(label in requested_seen)) {
        next
      }
      requested_seen[label] = 1
      source_status = value_of("status")
      scheduler_mode = value_of("stream_scheduler_mode")
      scheduler_active = value_of("stream_scheduler_active") + 0
      scheduler_direction_x = value_of("stream_scheduler_direction_x") + 0
      scheduler_direction_z = value_of("stream_scheduler_direction_z") + 0
      preview_mismatch = value_of("stream_scheduler_preview_mismatch") + 0
      mesh_ties = value_of("mesh_scheduler_directional_ties") + 0
      collision_ties = value_of("collision_scheduler_directional_ties") + 0
      fifo_fallbacks = value_of("stream_scheduler_fifo_fallbacks") + 0
      motion = value_of("motion")
      expected_chunk = value_of("expected_chunk")
      current_chunk = value_of("current_chunk")
      motion_steps = value_of("motion_steps") + 0
      motion_chunks = value_of("motion_chunks") + 0
      render_ready = value_of("current_render_ready") + 0
      collision_ready = value_of("current_collision_ready") + 0
      ground_misses = value_of("ground_misses") + 0
      gpu_upload_fail = value_of("gpu_upload_fail") + 0
      chunk_unload_total = value_of("chunk_unload_total") + 0
      chunk_unload_neighbor_refreshes = value_of("chunk_unload_neighbor_refreshes") + 0
      chunk_unload_max = value_of("chunk_unload_max") + 0
      popin_missing = value_of("popin_missing_chunks") + 0
      popin_collision_missing = value_of("popin_collision_missing_chunks") + 0
      terrain_queue = value_of("terrain_queue_max_ms") + 0.0
      process_wall = value_of("process_wall_p95_ms") + 0.0
      gpu_submit = value_of("gpu_compositor_submit_max_ms") + 0.0
      gpu_draws = value_of("gpu_effective_draws") + 0
      packet_lag = value_of("packet_queue_lag_max_ms") + 0.0

      status = "pass"
      reason = "ok"
      if (source_status != "pass") {
        status = "fail"; reason = "source_case_status"
      } else if (scheduler_mode != mode || scheduler_active != expected_active) {
        status = "fail"; reason = "scheduler_mode"
      } else if (motion_steps <= 0 || motion_chunks <= 0) {
        status = "fail"; reason = "motion_coverage"
      } else if (render_ready == 0 || collision_ready == 0) {
        status = "fail"; reason = "current_readiness"
      } else if (ground_misses != 0) {
        status = "fail"; reason = "ground_misses"
      } else if (gpu_upload_fail != 0) {
        status = "fail"; reason = "upload_fail"
      } else if (chunk_unload_total != 0 || chunk_unload_neighbor_refreshes != 0 || chunk_unload_max != 0) {
        status = "fail"; reason = "unexpected_unload"
      } else if (lane_exit_code + 0 != 0) {
        status = "fail"; reason = "lane_exit_code"
      }

      printf("streaming_scheduler_boundary_case mode=%s label=%s status=%s reason=%s scheduler_mode=%s scheduler_active=%d expected_scheduler_active=%d scheduler_direction_x=%d scheduler_direction_z=%d preview_mismatch=%d mesh_directional_ties=%d collision_directional_ties=%d fifo_fallbacks=%d motion=%s expected_chunk=%s current_chunk=%s motion_steps=%d motion_chunks=%d current_render_ready=%d current_collision_ready=%d ground_misses=%d terrain_samples=n/a gpu_upload_fail=%d chunk_unload_total=%d chunk_unload_neighbor_refreshes=%d chunk_unload_max=%d popin_missing_chunks=%d popin_collision_missing_chunks=%d terrain_queue_max_ms=%.3f process_wall_p95_ms=%.3f gpu_compositor_submit_max_ms=%.3f gpu_effective_draws=%d packet_queue_lag_max_ms=%.3f lane_exit_code=%s summary=%s\n", mode, label, status, reason, scheduler_mode, scheduler_active, expected_active, scheduler_direction_x, scheduler_direction_z, preview_mismatch, mesh_ties, collision_ties, fifo_fallbacks, motion, expected_chunk, current_chunk, motion_steps, motion_chunks, render_ready, collision_ready, ground_misses, gpu_upload_fail, chunk_unload_total, chunk_unload_neighbor_refreshes, chunk_unload_max, popin_missing, popin_collision_missing, terrain_queue, process_wall, gpu_submit, gpu_draws, packet_lag, lane_exit_code, summary)
    }
    END {
      for (i in requested_seen) {
        if (requested_seen[i] == 0) {
          emit_missing(i)
        }
      }
    }
  ' "$summary" >> "$CASES_PATH"
}

case "$RUN_WORKLOADS" in
  0|1) ;;
  *) fail "RUMPELMC_STREAMING_SCHEDULER_BOUNDARY_MATRIX_RUN_WORKLOADS must be 0 or 1" ;;
esac
case "$REQUIRE_RUNTIME_SIGNAL" in
  0|1) ;;
  *) fail "RUMPELMC_STREAMING_SCHEDULER_BOUNDARY_MATRIX_REQUIRE_RUNTIME_SIGNAL must be 0 or 1" ;;
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
  write_mode_cases "$mode"
done

expected_modes_count=$(set -- $MODES; printf '%s\n' "$#")
expected_case_count=$(set -- $CASES; printf '%s\n' "$#")
expected_cases=$((expected_modes_count * expected_case_count))

awk \
  -v modes="$MODES" \
  -v cases="$CASES" \
  -v expected_cases="$expected_cases" \
  -v max_relative_budget_regression_pct="$MAX_RELATIVE_BUDGET_REGRESSION_PCT" \
  -v max_absolute_budget_regression_ms="$MAX_ABSOLUTE_BUDGET_REGRESSION_MS" \
  -v require_runtime_signal="$REQUIRE_RUNTIME_SIGNAL" \
  -v prototype_summary="$(relative_path "$PROTOTYPE_SUMMARY")" \
  -v case_rows="$(relative_path "$CASES_PATH")" \
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
    split(cases, expected_labels, " ")
    for (i in expected_modes) mode_seen[expected_modes[i]] = 0
    for (i in expected_labels) label_seen[expected_labels[i]] = 0
  }
  $1 == "streaming_scheduler_boundary_case" {
    case_count++
    mode = value_of("mode")
    label = value_of("label")
    status = value_of("status")
    mode_seen[mode] = 1
    label_seen[label] = 1
    case_seen[mode SUBSEP label] = 1
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

    queue_by_case[mode SUBSEP label] = queue
    process_by_case[mode SUBSEP label] = process
    submit_by_case[mode SUBSEP label] = submit
  }
  END {
    for (i in expected_modes) {
      mode = expected_modes[i]
      if (mode_seen[mode] != 1) missing_modes++
      for (j in expected_labels) {
        label = expected_labels[j]
        if (case_seen[mode SUBSEP label] != 1) missing_cases++
      }
    }
    for (i in expected_labels) {
      label = expected_labels[i]
      if (label_seen[label] != 1) missing_labels++
      base_key = "nearest" SUBSEP label
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
        key = mode SUBSEP label
        if (case_seen[key] != 1) continue
        if (queue_by_case[key] > budget_allowed(base_queue) || process_by_case[key] > budget_allowed(base_process) || submit_by_case[key] > budget_allowed(base_submit)) {
          regression_cases++
          if (mode == "directional_tie") active_regression_cases++
          if (mode == "directional_tie_preview") preview_regression_cases++
        }
      }
    }

    boundary_harness_status = "complete"
    if (baseline_failed_cases > 0 || preview_failed_cases > 0 || preview_regression_cases > 0 || missing_modes > 0 || missing_labels > 0 || missing_cases > 0) {
      boundary_harness_status = "partial"
    }

    candidate_scheduler_status = "boundary_runtime_healthy"
    if (boundary_harness_status == "partial") {
      candidate_scheduler_status = "defer_boundary_harness_unstable"
    } else if (active_failed_cases > 0 || active_regression_cases > 0) {
      candidate_scheduler_status = "reject_boundary_runtime_regression"
    } else if (runtime_signal + 0 == 0) {
      candidate_scheduler_status = "defer_no_runtime_signal"
    } else {
      candidate_scheduler_status = "defer_external_profiler_required"
    }

    status = "pass"
    reason = "ok"
    if (case_count != expected_cases || missing_modes > 0 || missing_labels > 0 || missing_cases > 0) {
      status = "fail"; reason = "missing_cases"
    } else if (baseline_failed_cases > 0 || preview_failed_cases > 0) {
      status = "fail"; reason = "baseline_or_preview_failed"
    } else if (preview_regression_cases > 0) {
      status = "fail"; reason = "preview_budget_regression"
    } else if (baseline_pass_cases == 0 || preview_pass_cases == 0) {
      status = "fail"; reason = "missing_baseline_or_preview_pass"
    } else if (require_runtime_signal + 0 == 1 && runtime_signal + 0 == 0) {
      status = "fail"; reason = "missing_runtime_signal"
    }

    printf("gpu_streaming_scheduler_boundary_matrix status=%s reason=%s boundary_harness_status=%s modes=\"%s\" cases=\"%s\" expected_cases=%d completed_cases=%d failed_cases=%d baseline_pass_cases=%d preview_pass_cases=%d active_pass_cases=%d baseline_failed_cases=%d preview_failed_cases=%d active_failed_cases=%d missing_modes=%d missing_labels=%d missing_cases=%d regression_cases=%d preview_regression_cases=%d active_regression_cases=%d run_workloads=%s target_fps=%s max_relative_budget_regression_pct=%s max_absolute_budget_regression_ms=%s require_runtime_signal=%s runtime_signal=%d max_stream_scheduler_preview_mismatch=%d max_mesh_scheduler_directional_ties=%d max_collision_scheduler_directional_ties=%d max_stream_scheduler_fifo_fallbacks=%d max_popin_missing_chunks=%d max_popin_collision_missing_chunks=%d max_terrain_queue_ms=%.3f max_process_wall_p95_ms=%.3f max_gpu_compositor_submit_ms=%.3f max_packet_queue_lag_ms=%.3f scheduler_change_allowed=0 default_runtime_change_allowed=0 candidate_scheduler_status=%s external_profile_status=pending_external_profiler requires_external_profiler_before_default=1 requires_mac_windows_validation=1 prototype_summary=%s source_root=%s case_rows=%s\n", status, reason, boundary_harness_status, modes, cases, expected_cases, case_count, failed_cases, baseline_pass_cases, preview_pass_cases, active_pass_cases, baseline_failed_cases, preview_failed_cases, active_failed_cases, missing_modes, missing_labels, missing_cases, regression_cases, preview_regression_cases, active_regression_cases, run_workloads, target_fps, max_relative_budget_regression_pct, max_absolute_budget_regression_ms, require_runtime_signal, runtime_signal, max_stream_scheduler_preview_mismatch, max_mesh_scheduler_directional_ties, max_collision_scheduler_directional_ties, max_stream_scheduler_fifo_fallbacks, max_popin_missing_chunks, max_popin_collision_missing_chunks, max_terrain_queue_ms, max_process_wall_p95_ms, max_gpu_compositor_submit_ms, max_packet_queue_lag_ms, candidate_scheduler_status, prototype_summary, source_root, case_rows)
  }
' "$CASES_PATH" > "$SUMMARY_PATH"

cat "$SUMMARY_PATH"
cat "$CASES_PATH"
grep -q '^gpu_streaming_scheduler_boundary_matrix status=pass ' "$SUMMARY_PATH" || fail "streaming scheduler boundary matrix did not pass"
echo "GPU streaming scheduler boundary matrix artifacts: $OUT_DIR"
