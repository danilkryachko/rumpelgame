#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/gpu_terrain_chunk_boundary_stress"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

SUMMARY_PATH="$OUT_DIR/chunk-boundary-stress-summary.txt"
SUITE_DIR="$OUT_DIR/high-pressure-suite"
SUITE_SUMMARY="$SUITE_DIR/world-load-suite-summary.txt"
SUITE_LOG="$OUT_DIR/high-pressure-suite.log"
SOURCE_SUITE_SUMMARY="${RUMPELMC_CHUNK_BOUNDARY_SOURCE_SUMMARY:-}"
CASES="${RUMPELMC_CHUNK_BOUNDARY_CASES:-long-move spiral fast-turn teleport-snap high-resident}"
TARGET_FPS="${RUMPELMC_CHUNK_BOUNDARY_TARGET_FPS:-150}"
BUDGET_MODE="${RUMPELMC_CHUNK_BOUNDARY_BUDGET_MODE:-report}"
PROCESS_WALL_BUDGET_MODE="${RUMPELMC_CHUNK_BOUNDARY_PROCESS_WALL_BUDGET_MODE:-report}"
GPU_COMPOSITOR_BUDGET_MODE="${RUMPELMC_CHUNK_BOUNDARY_GPU_COMPOSITOR_BUDGET_MODE:-report}"
GPU_TIMESTAMP_BUDGET_MODE="${RUMPELMC_CHUNK_BOUNDARY_GPU_TIMESTAMP_BUDGET_MODE:-report}"
REQUIRE_NO_UNLOAD="${RUMPELMC_CHUNK_BOUNDARY_REQUIRE_NO_UNLOAD:-1}"
MIN_GPU_SUBCHUNKS="${RUMPELMC_CHUNK_BOUNDARY_MIN_GPU_SUBCHUNKS:-900}"
MIN_GPU_DRAWS="${RUMPELMC_CHUNK_BOUNDARY_MIN_GPU_DRAWS:-900}"
MIN_GPU_FACES="${RUMPELMC_CHUNK_BOUNDARY_MIN_GPU_FACES:-1200}"

fail() {
  echo "gpu_terrain_chunk_boundary_stress: $*" >&2
  exit 1
}

case "$REQUIRE_NO_UNLOAD" in
  0|1) ;;
  *) fail "RUMPELMC_CHUNK_BOUNDARY_REQUIRE_NO_UNLOAD must be 0 or 1" ;;
esac
case "$MIN_GPU_SUBCHUNKS:$MIN_GPU_DRAWS:$MIN_GPU_FACES" in
  *[!0-9:]*|:*|*:|*::*)
    fail "RUMPELMC_CHUNK_BOUNDARY_MIN_GPU_* thresholds must be non-negative integers"
    ;;
esac

mkdir -p "$OUT_DIR"

set -- $CASES
CASE_COUNT="$#"
if [ "$CASE_COUNT" -lt 1 ]; then
  fail "RUMPELMC_CHUNK_BOUNDARY_CASES must include at least one movement case"
fi

echo "==> GPU terrain chunk-boundary stress cases=$CASES"
if [ -n "$SOURCE_SUITE_SUMMARY" ]; then
  case "$SOURCE_SUITE_SUMMARY" in
    /*) ;;
    *) SOURCE_SUITE_SUMMARY="$ROOT_DIR/$SOURCE_SUITE_SUMMARY" ;;
  esac
  SUITE_SUMMARY="$SOURCE_SUITE_SUMMARY"
  echo "==> GPU terrain chunk-boundary stress reusing source summary $SUITE_SUMMARY"
else
  rm -rf "$SUITE_DIR"
  if ! RUMPELMC_WORLD_LOAD_SUITE_CASES="$CASES" \
    RUMPELMC_WORLD_LOAD_SUITE_TARGET_FPS="$TARGET_FPS" \
    RUMPELMC_WORLD_LOAD_SUITE_BUDGET_MODE="$BUDGET_MODE" \
    RUMPELMC_WORLD_LOAD_SUITE_PROCESS_WALL_BUDGET_MODE="$PROCESS_WALL_BUDGET_MODE" \
    RUMPELMC_WORLD_LOAD_SUITE_GPU_COMPOSITOR_BUDGET_MODE="$GPU_COMPOSITOR_BUDGET_MODE" \
    RUMPELMC_WORLD_LOAD_SUITE_GPU_TIMESTAMP_BUDGET_MODE="$GPU_TIMESTAMP_BUDGET_MODE" \
    /bin/sh "$ROOT_DIR/scripts/world_streaming_high_pressure_suite.sh" "$SUITE_DIR" > "$SUITE_LOG" 2>&1; then
    tail -n 80 "$SUITE_LOG" >&2 || true
    fail "world streaming high-pressure suite failed; see $SUITE_LOG"
  fi
fi

test -s "$SUITE_SUMMARY" || fail "missing suite summary $SUITE_SUMMARY"
grep -q '^world_load_suite status=pass ' "$SUITE_SUMMARY" || fail "suite summary did not pass"

case_lines_path="$SUMMARY_PATH.cases.tmp"
aggregate_path="$SUMMARY_PATH.aggregate.tmp"
trap 'rm -f "$case_lines_path" "$aggregate_path"' EXIT HUP INT TERM

awk \
  -v cases="$CASES" \
  -v expected_count="$CASE_COUNT" \
  -v target_fps="$TARGET_FPS" \
  -v budget_mode="$BUDGET_MODE" \
  -v process_wall_budget_mode="$PROCESS_WALL_BUDGET_MODE" \
  -v gpu_compositor_budget_mode="$GPU_COMPOSITOR_BUDGET_MODE" \
  -v gpu_timestamp_budget_mode="$GPU_TIMESTAMP_BUDGET_MODE" \
  -v require_no_unload="$REQUIRE_NO_UNLOAD" \
  -v min_gpu_subchunks="$MIN_GPU_SUBCHUNKS" \
  -v min_gpu_draws="$MIN_GPU_DRAWS" \
  -v min_gpu_faces="$MIN_GPU_FACES" \
  -v suite_summary="$SUITE_SUMMARY" \
  -v aggregate_path="$aggregate_path" '
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
  function expected_chunk_for(label) {
    if (label == "startup-cold" || label == "startup-warm") return "3,2"
    if (label == "long-move") return "11,8"
    if (label == "spiral") return "0,2"
    if (label == "fast-turn") return "2,2"
    if (label == "teleport-snap") return "0,0"
    if (label == "high-view") return "7,5"
    return ""
  }
  function min_chunks_for(label) {
    if (label == "startup-cold" || label == "startup-warm") return 4
    if (label == "long-move") return 12
    if (label == "spiral") return 8
    if (label == "fast-turn") return 1
    if (label == "teleport-snap") return 8
    if (label == "high-view") return 8
    return 0
  }
  function max_value(current, candidate) {
    candidate += 0
    if (!current_found || candidate > current) {
      current_found = 1
      return candidate
    }
    return current
  }
  BEGIN {
    split(cases, requested, " ")
    for (i in requested) {
      requested_seen[requested[i]] = 0
    }
  }
  $1 == "world_load_suite_case" {
    label = value_of("label")
    if (!(label in requested_seen)) {
      next
    }
    requested_seen[label] = 1
    type = value_of("type")
    status = value_of("status")
    terrain_queue_max = value_of("terrain_queue_max_ms") + 0.0
    if (terrain_queue_max == 0.0) {
      terrain_queue_max = value_of("max_terrain_queue_ms") + 0.0
    }
    process_wall_p95 = value_of("process_wall_p95_ms") + 0.0
    if (process_wall_p95 == 0.0) {
      process_wall_p95 = value_of("max_process_wall_p95_ms") + 0.0
    }
    gpu_submit_max = value_of("gpu_compositor_submit_max_ms") + 0.0
    if (gpu_submit_max == 0.0) {
      gpu_submit_max = value_of("max_gpu_compositor_submit_ms") + 0.0
    }
    upload_fail = value_of("gpu_upload_fail") + 0
    upload_fail_capacity = value_of("gpu_upload_fail_capacity") + 0
    upload_fail_fragmented = value_of("gpu_upload_fail_fragmented") + 0

    case_count++
    if (status != "pass") failed_cases++
    gpu_upload_fail += upload_fail
    gpu_upload_fail_capacity += upload_fail_capacity
    gpu_upload_fail_fragmented += upload_fail_fragmented

    current_found = max_terrain_queue_found
    max_terrain_queue = max_value(max_terrain_queue, terrain_queue_max)
    max_terrain_queue_found = current_found
    current_found = max_process_wall_found
    max_process_wall = max_value(max_process_wall, process_wall_p95)
    max_process_wall_found = current_found
    current_found = max_gpu_submit_found
    max_gpu_submit = max_value(max_gpu_submit, gpu_submit_max)
    max_gpu_submit_found = current_found

    if (type == "movement") {
      motion = value_of("motion")
      motion_steps = value_of("motion_steps") + 0
      motion_chunks = value_of("motion_chunks") + 0
      current_chunk = value_of("current_chunk")
      gpu_draws = value_of("gpu_effective_draws") + 0
      packet_drain = value_of("packet_queue_max_drain") + 0
      packet_drained = value_of("packet_queue_drained") + 0
      packet_lag = value_of("packet_queue_lag_max_ms") + 0.0
      packet_decode_work = value_of("packet_queue_decode_work_max_ms") + 0.0
      unload_total = value_of("chunk_unload_total") + 0
      unload_grace_kept = value_of("chunk_unload_grace_kept") + 0
      unload_neighbor_refreshes = value_of("chunk_unload_neighbor_refreshes") + 0
      unload_max = value_of("chunk_unload_max") + 0
      popin_missing = value_of("popin_missing_chunks") + 0
      popin_collision_missing = value_of("popin_collision_missing_chunks") + 0
      popin_missing_max = value_of("popin_missing_max") + 0
      popin_collision_missing_max = value_of("popin_collision_missing_max") + 0
      render_ready = value_of("current_render_ready") + 0
      collision_ready = value_of("current_collision_ready") + 0
      ground_misses_case = value_of("readiness_ground_misses") + 0
      expected_chunk = expected_chunk_for(label)
      min_chunks = min_chunks_for(label)

      movement_cases++
      if (motion_steps <= 0) missing_motion_steps++
      if (expected_chunk != "" && current_chunk != expected_chunk) expected_chunk_failures++
      if (min_chunks > 0 && motion_chunks < min_chunks) min_chunk_failures++
      if (render_ready == 0) render_not_ready_cases++
      if (collision_ready == 0) collision_not_ready_cases++
      ground_misses += ground_misses_case
      chunk_unload_total += unload_total
      chunk_unload_neighbor_refreshes += unload_neighbor_refreshes
      chunk_unload_grace_kept += unload_grace_kept
      if (gpu_draws > max_gpu_effective_draws) max_gpu_effective_draws = gpu_draws
      if (packet_drain > max_packet_drain) max_packet_drain = packet_drain
      if (packet_drained > max_packet_drained) max_packet_drained = packet_drained
      if (packet_lag > max_packet_lag) max_packet_lag = packet_lag
      if (packet_decode_work > max_packet_decode_work) max_packet_decode_work = packet_decode_work
      if (unload_total > max_chunk_unload_total) max_chunk_unload_total = unload_total
      if (unload_grace_kept > max_chunk_unload_grace_kept) max_chunk_unload_grace_kept = unload_grace_kept
      if (unload_neighbor_refreshes > max_chunk_unload_neighbor_refreshes) max_chunk_unload_neighbor_refreshes = unload_neighbor_refreshes
      if (unload_max > max_chunk_unload) max_chunk_unload = unload_max
      if (popin_missing > max_popin_missing_chunks) max_popin_missing_chunks = popin_missing
      if (popin_collision_missing > max_popin_collision_missing_chunks) max_popin_collision_missing_chunks = popin_collision_missing
      if (popin_missing_max > max_popin_missing_max) max_popin_missing_max = popin_missing_max
      if (popin_collision_missing_max > max_popin_collision_missing_max) max_popin_collision_missing_max = popin_collision_missing_max

      printf("chunk_boundary_case label=%s type=%s status=%s motion=%s expected_chunk=%s current_chunk=%s min_chunks=%d motion_steps=%d motion_chunks=%d terrain_queue_max_ms=%.3f process_wall_p95_ms=%.3f gpu_compositor_submit_max_ms=%.3f gpu_effective_draws=%d gpu_upload_fail=%d packet_queue_max_drain=%d packet_queue_drained=%d packet_queue_lag_max_ms=%.3f packet_queue_decode_work_max_ms=%.3f chunk_unload_total=%d chunk_unload_grace_kept=%d chunk_unload_neighbor_refreshes=%d chunk_unload_max=%d popin_missing_chunks=%d popin_collision_missing_chunks=%d popin_missing_max=%d popin_collision_missing_max=%d current_render_ready=%d current_collision_ready=%d ground_misses=%d\n", label, type, status, motion, expected_chunk, current_chunk, min_chunks, motion_steps, motion_chunks, terrain_queue_max, process_wall_p95, gpu_submit_max, gpu_draws, upload_fail, packet_drain, packet_drained, packet_lag, packet_decode_work, unload_total, unload_grace_kept, unload_neighbor_refreshes, unload_max, popin_missing, popin_collision_missing, popin_missing_max, popin_collision_missing_max, render_ready, collision_ready, ground_misses_case)
    } else if (type == "workload") {
      gpu_subchunks = value_of("max_gpu_subchunks") + 0
      gpu_draws = value_of("max_gpu_draws") + 0
      gpu_faces = value_of("max_gpu_faces") + 0
      workload_cases++
      if (gpu_subchunks > max_gpu_subchunks) max_gpu_subchunks = gpu_subchunks
      if (gpu_draws > max_gpu_draws) max_gpu_draws = gpu_draws
      if (gpu_faces > max_gpu_faces) max_gpu_faces = gpu_faces
      printf("chunk_boundary_residency_case label=%s type=%s status=%s max_gpu_subchunks=%d max_gpu_draws=%d max_gpu_faces=%d max_terrain_queue_ms=%.3f max_process_wall_p95_ms=%.3f max_gpu_compositor_submit_ms=%.3f gpu_upload_fail=%d gpu_upload_fail_capacity=%d gpu_upload_fail_fragmented=%d\n", label, type, status, gpu_subchunks, gpu_draws, gpu_faces, terrain_queue_max, process_wall_p95, gpu_submit_max, upload_fail, upload_fail_capacity, upload_fail_fragmented)
    } else {
      unknown_type_cases++
    }
  }
  END {
    for (i in requested_seen) {
      if (requested_seen[i] == 0) missing_cases++
    }
    status = "pass"
    if (case_count != expected_count || missing_cases > 0 || unknown_type_cases > 0 || failed_cases > 0 || missing_motion_steps > 0 || expected_chunk_failures > 0 || min_chunk_failures > 0 || gpu_upload_fail > 0 || gpu_upload_fail_capacity > 0 || gpu_upload_fail_fragmented > 0 || ground_misses > 0 || render_not_ready_cases > 0 || collision_not_ready_cases > 0) {
      status = "fail"
    }
    if (require_no_unload == 1 && (chunk_unload_total > 0 || chunk_unload_neighbor_refreshes > 0)) {
      status = "fail"
    }
    if (workload_cases > 0 && (max_gpu_subchunks < min_gpu_subchunks || max_gpu_draws < min_gpu_draws || max_gpu_faces < min_gpu_faces)) {
      status = "fail"
    }
    printf("chunk_boundary_stress status=%s cases=\"%s\" expected_cases=%d completed_cases=%d movement_cases=%d workload_cases=%d missing_cases=%d target_fps=%s budget_mode=%s process_wall_budget_mode=%s gpu_compositor_budget_mode=%s gpu_timestamp_budget_mode=%s require_no_unload=%s min_gpu_subchunks=%d min_gpu_draws=%d min_gpu_faces=%d max_gpu_subchunks=%d max_gpu_draws=%d max_gpu_faces=%d max_gpu_effective_draws=%d max_terrain_queue_ms=%.3f max_process_wall_p95_ms=%.3f max_gpu_compositor_submit_ms=%.3f max_packet_queue_drain=%d max_packet_queue_drained=%d max_packet_queue_lag_ms=%.3f max_packet_queue_decode_work_ms=%.3f max_chunk_unload_total=%d max_chunk_unload_grace_kept=%d max_chunk_unload_neighbor_refreshes=%d max_chunk_unload=%d max_popin_missing_chunks=%d max_popin_collision_missing_chunks=%d max_popin_missing_max=%d max_popin_collision_missing_max=%d gpu_upload_fail=%d gpu_upload_fail_capacity=%d gpu_upload_fail_fragmented=%d ground_misses=%d render_not_ready_cases=%d collision_not_ready_cases=%d unknown_type_cases=%d failed_cases=%d expected_chunk_failures=%d min_chunk_failures=%d missing_motion_steps=%d suite_summary=%s\n", status, cases, expected_count, case_count, movement_cases, workload_cases, missing_cases, target_fps, budget_mode, process_wall_budget_mode, gpu_compositor_budget_mode, gpu_timestamp_budget_mode, require_no_unload, min_gpu_subchunks, min_gpu_draws, min_gpu_faces, max_gpu_subchunks, max_gpu_draws, max_gpu_faces, max_gpu_effective_draws, max_terrain_queue, max_process_wall, max_gpu_submit, max_packet_drain, max_packet_drained, max_packet_lag, max_packet_decode_work, max_chunk_unload_total, max_chunk_unload_grace_kept, max_chunk_unload_neighbor_refreshes, max_chunk_unload, max_popin_missing_chunks, max_popin_collision_missing_chunks, max_popin_missing_max, max_popin_collision_missing_max, gpu_upload_fail, gpu_upload_fail_capacity, gpu_upload_fail_fragmented, ground_misses, render_not_ready_cases, collision_not_ready_cases, unknown_type_cases, failed_cases, expected_chunk_failures, min_chunk_failures, missing_motion_steps, suite_summary) > aggregate_path
  }
' "$SUITE_SUMMARY" > "$case_lines_path"

cat "$aggregate_path" "$case_lines_path" > "$SUMMARY_PATH"
cat "$SUMMARY_PATH"
grep -q '^chunk_boundary_stress status=pass ' "$SUMMARY_PATH" || fail "chunk-boundary stress summary did not pass"

echo "GPU terrain chunk-boundary stress artifacts: $OUT_DIR"
