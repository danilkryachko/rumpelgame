#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/gpu_chunk_unload_churn_diagnosis_current"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

SUMMARY_PATH="$OUT_DIR/gpu-chunk-unload-churn-diagnosis-summary.txt"
CHUNK_BOUNDARY_SUMMARY="${RUMPELMC_GPU_CHUNK_UNLOAD_CHURN_CHUNK_BOUNDARY_SUMMARY:-"$ROOT_DIR/logs/gpu_terrain_chunk_boundary_stress_current/chunk-boundary-stress-summary.txt"}"
DEFAULT_CONTROL_SUMMARY="${RUMPELMC_GPU_CHUNK_UNLOAD_DEFAULT_SUMMARY:-"$ROOT_DIR/logs/world_streaming_high_pressure_suite_teleport_unload_churn_check/world-load-suite-summary.txt"}"
IMMEDIATE_CONTROL_SUMMARY="${RUMPELMC_GPU_CHUNK_UNLOAD_IMMEDIATE_SUMMARY:-"$ROOT_DIR/logs/world_streaming_high_pressure_suite_teleport_unload_churn_grace0_check/world-load-suite-summary.txt"}"
REQUIRE_CONTROLS="${RUMPELMC_GPU_CHUNK_UNLOAD_REQUIRE_CONTROLS:-0}"

fail() {
  echo "gpu_chunk_unload_churn_diagnosis: $*" >&2
  exit 1
}

normalize_path() {
  path="$1"
  case "$path" in
    /*) printf '%s\n' "$path" ;;
    *) printf '%s\n' "$ROOT_DIR/$path" ;;
  esac
}

case "$REQUIRE_CONTROLS" in
  0|1) ;;
  *) fail "RUMPELMC_GPU_CHUNK_UNLOAD_REQUIRE_CONTROLS must be 0 or 1" ;;
esac

mkdir -p "$OUT_DIR"

CHUNK_BOUNDARY_SUMMARY="$(normalize_path "$CHUNK_BOUNDARY_SUMMARY")"
DEFAULT_CONTROL_SUMMARY="$(normalize_path "$DEFAULT_CONTROL_SUMMARY")"
IMMEDIATE_CONTROL_SUMMARY="$(normalize_path "$IMMEDIATE_CONTROL_SUMMARY")"

if [ ! -s "$CHUNK_BOUNDARY_SUMMARY" ]; then
  printf 'gpu_chunk_unload_churn_diagnosis status=fail reason=missing_chunk_boundary_summary chunk_boundary_summary=%s default_control_summary=%s immediate_control_summary=%s controls_required=%s\n' \
    "$CHUNK_BOUNDARY_SUMMARY" "$DEFAULT_CONTROL_SUMMARY" "$IMMEDIATE_CONTROL_SUMMARY" "$REQUIRE_CONTROLS" > "$SUMMARY_PATH"
  cat "$SUMMARY_PATH" >&2
  fail "missing chunk-boundary summary $CHUNK_BOUNDARY_SUMMARY"
fi

DEFAULT_CONTROL_PRESENT=0
DEFAULT_CONTROL_INPUT="/dev/null"
if [ -s "$DEFAULT_CONTROL_SUMMARY" ]; then
  DEFAULT_CONTROL_PRESENT=1
  DEFAULT_CONTROL_INPUT="$DEFAULT_CONTROL_SUMMARY"
fi

IMMEDIATE_CONTROL_PRESENT=0
IMMEDIATE_CONTROL_INPUT="/dev/null"
if [ -s "$IMMEDIATE_CONTROL_SUMMARY" ]; then
  IMMEDIATE_CONTROL_PRESENT=1
  IMMEDIATE_CONTROL_INPUT="$IMMEDIATE_CONTROL_SUMMARY"
fi

awk \
  -v chunk_boundary_summary="$CHUNK_BOUNDARY_SUMMARY" \
  -v default_control_summary="$DEFAULT_CONTROL_SUMMARY" \
  -v immediate_control_summary="$IMMEDIATE_CONTROL_SUMMARY" \
  -v default_control_present="$DEFAULT_CONTROL_PRESENT" \
  -v immediate_control_present="$IMMEDIATE_CONTROL_PRESENT" \
  -v controls_required="$REQUIRE_CONTROLS" '
  function reset_fields(  i) {
    for (i in f) {
      delete f[i]
    }
  }
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
  function text(value) {
    return value == "" ? "n/a" : value
  }
  function set_fail(why) {
    if (status == "pass") {
      status = "fail"
      reason = why
    }
  }
  function control_status_default() {
    if (default_control_present + 0 == 0) return "missing"
    if (!default_top_seen || default_top_status != "pass") return "fail"
    if (!default_case_seen || default_case_status != "pass") return "fail"
    if (default_unload_total + 0 != 0 || default_neighbor_refreshes + 0 != 0 || default_unload_max + 0 != 0) return "fail"
    if (default_grace_kept + 0 <= 0 || default_gpu_upload_fail + 0 != 0 || default_ground_misses + 0 != 0) return "fail"
    if (default_render_ready + 0 == 0 || default_collision_ready + 0 == 0) return "fail"
    return "pass"
  }
  function control_status_immediate() {
    if (immediate_control_present + 0 == 0) return "missing"
    if (!immediate_top_seen || immediate_top_status != "pass") return "fail"
    if (!immediate_case_seen || immediate_case_status != "pass") return "fail"
    if (immediate_unload_total + 0 <= 0 || immediate_neighbor_refreshes + 0 <= 0 || immediate_unload_max + 0 <= 0) return "fail"
    if (immediate_grace_kept + 0 != 0 || immediate_gpu_upload_fail + 0 != 0 || immediate_ground_misses + 0 != 0) return "fail"
    if (immediate_render_ready + 0 == 0 || immediate_collision_ready + 0 == 0) return "fail"
    return "pass"
  }
  BEGIN {
    status = "pass"
    reason = "default_grace_absorbs_churn"
  }
  FILENAME == chunk_boundary_summary && $1 == "chunk_boundary_stress" {
    cb_seen = 1
    cb_status = value_of("status")
    cb_reason = value_of("reason")
    cb_completed_cases = value_of("completed_cases")
    cb_expected_cases = value_of("expected_cases")
    cb_movement_cases = value_of("movement_cases")
    cb_workload_cases = value_of("workload_cases")
    cb_missing_cases = value_of("missing_cases")
    cb_require_no_unload = value_of("require_no_unload")
    cb_max_chunk_unload_total = value_of("max_chunk_unload_total")
    cb_max_chunk_unload_grace_kept = value_of("max_chunk_unload_grace_kept")
    cb_max_chunk_unload_neighbor_refreshes = value_of("max_chunk_unload_neighbor_refreshes")
    cb_max_chunk_unload = value_of("max_chunk_unload")
    cb_max_popin_missing_chunks = value_of("max_popin_missing_chunks")
    cb_max_popin_collision_missing_chunks = value_of("max_popin_collision_missing_chunks")
    cb_gpu_upload_fail = value_of("gpu_upload_fail")
    cb_gpu_upload_fail_capacity = value_of("gpu_upload_fail_capacity")
    cb_gpu_upload_fail_fragmented = value_of("gpu_upload_fail_fragmented")
    cb_ground_misses = value_of("ground_misses")
    cb_render_not_ready_cases = value_of("render_not_ready_cases")
    cb_collision_not_ready_cases = value_of("collision_not_ready_cases")
    cb_failed_cases = value_of("failed_cases")
    cb_max_terrain_queue_ms = value_of("max_terrain_queue_ms")
    cb_max_process_wall_p95_ms = value_of("max_process_wall_p95_ms")
    cb_max_gpu_compositor_submit_ms = value_of("max_gpu_compositor_submit_ms")
    cb_max_packet_queue_lag_ms = value_of("max_packet_queue_lag_ms")
  }
  FILENAME == chunk_boundary_summary && $1 == "chunk_boundary_case" {
    label = value_of("label")
    if (label == "fast-turn") has_fast_turn = 1
    if (label == "teleport-snap") has_teleport_snap = 1
    case_rows[++case_count] = sprintf("chunk_unload_churn_case label=%s status=%s motion=%s chunk_unload_total=%s chunk_unload_grace_kept=%s chunk_unload_neighbor_refreshes=%s chunk_unload_max=%s popin_missing_chunks=%s popin_collision_missing_chunks=%s current_render_ready=%s current_collision_ready=%s ground_misses=%s gpu_upload_fail=%s", label, value_of("status"), value_of("motion"), value_of("chunk_unload_total"), value_of("chunk_unload_grace_kept"), value_of("chunk_unload_neighbor_refreshes"), value_of("chunk_unload_max"), value_of("popin_missing_chunks"), value_of("popin_collision_missing_chunks"), value_of("current_render_ready"), value_of("current_collision_ready"), value_of("ground_misses"), value_of("gpu_upload_fail"))
  }
  FILENAME == default_control_summary && $1 == "world_load_suite" {
    default_top_seen = 1
    default_top_status = value_of("status")
  }
  FILENAME == default_control_summary && $1 == "world_load_suite_case" && value_of("label") == "teleport-snap" {
    default_case_seen = 1
    default_case_status = value_of("status")
    default_unload_total = value_of("chunk_unload_total")
    default_grace_kept = value_of("chunk_unload_grace_kept")
    default_neighbor_refreshes = value_of("chunk_unload_neighbor_refreshes")
    default_unload_max = value_of("chunk_unload_max")
    default_gpu_upload_fail = value_of("gpu_upload_fail")
    default_ground_misses = value_of("readiness_ground_misses")
    default_render_ready = value_of("current_render_ready")
    default_collision_ready = value_of("current_collision_ready")
    default_terrain_queue_ms = value_of("terrain_queue_max_ms")
  }
  FILENAME == immediate_control_summary && $1 == "world_load_suite" {
    immediate_top_seen = 1
    immediate_top_status = value_of("status")
  }
  FILENAME == immediate_control_summary && $1 == "world_load_suite_case" && value_of("label") == "teleport-snap" {
    immediate_case_seen = 1
    immediate_case_status = value_of("status")
    immediate_unload_total = value_of("chunk_unload_total")
    immediate_grace_kept = value_of("chunk_unload_grace_kept")
    immediate_neighbor_refreshes = value_of("chunk_unload_neighbor_refreshes")
    immediate_unload_max = value_of("chunk_unload_max")
    immediate_gpu_upload_fail = value_of("gpu_upload_fail")
    immediate_ground_misses = value_of("readiness_ground_misses")
    immediate_render_ready = value_of("current_render_ready")
    immediate_collision_ready = value_of("current_collision_ready")
    immediate_terrain_queue_ms = value_of("terrain_queue_max_ms")
  }
  END {
    default_control_status = control_status_default()
    immediate_control_status = control_status_immediate()
    controls_present = (default_control_present + 0) + (immediate_control_present + 0)
    controls_missing = 2 - controls_present

    if (!cb_seen) {
      set_fail("missing_chunk_boundary_root")
    } else if (cb_status != "pass") {
      set_fail("chunk_boundary_status")
    } else if (cb_require_no_unload != "1") {
      set_fail("chunk_boundary_no_unload_not_required")
    } else if (has_fast_turn + 0 == 0 || has_teleport_snap + 0 == 0 || cb_movement_cases + 0 < 4) {
      set_fail("missing_required_movement_cases")
    } else if (cb_completed_cases + 0 != cb_expected_cases + 0 || cb_missing_cases + 0 != 0 || cb_failed_cases + 0 != 0) {
      set_fail("chunk_boundary_case_coverage")
    } else if (cb_max_chunk_unload_total + 0 != 0 || cb_max_chunk_unload_neighbor_refreshes + 0 != 0 || cb_max_chunk_unload + 0 != 0) {
      set_fail("unexpected_default_unload")
    } else if (cb_max_chunk_unload_grace_kept + 0 <= 0) {
      set_fail("missing_grace_absorption")
    } else if (cb_gpu_upload_fail + 0 != 0 || cb_gpu_upload_fail_capacity + 0 != 0 || cb_gpu_upload_fail_fragmented + 0 != 0) {
      set_fail("gpu_upload_fail")
    } else if (cb_ground_misses + 0 != 0) {
      set_fail("ground_misses")
    } else if (cb_render_not_ready_cases + 0 != 0 || cb_collision_not_ready_cases + 0 != 0) {
      set_fail("current_readiness")
    } else if (controls_required + 0 == 1 && (default_control_status == "missing" || immediate_control_status == "missing")) {
      set_fail("controls_required_missing")
    } else if (default_control_status == "fail") {
      set_fail("default_control_failed")
    } else if (immediate_control_status == "fail") {
      set_fail("immediate_control_failed")
    }

    printf("gpu_chunk_unload_churn_diagnosis status=%s reason=%s chunk_boundary_status=%s chunk_boundary_reason=%s expected_cases=%s completed_cases=%s movement_cases=%s workload_cases=%s missing_cases=%s require_no_unload=%s has_fast_turn=%d has_teleport_snap=%d max_chunk_unload_total=%s max_chunk_unload_grace_kept=%s max_chunk_unload_neighbor_refreshes=%s max_chunk_unload=%s max_popin_missing_chunks=%s max_popin_collision_missing_chunks=%s max_terrain_queue_ms=%s max_process_wall_p95_ms=%s max_gpu_compositor_submit_ms=%s max_packet_queue_lag_ms=%s gpu_upload_fail=%s gpu_upload_fail_capacity=%s gpu_upload_fail_fragmented=%s ground_misses=%s render_not_ready_cases=%s collision_not_ready_cases=%s default_control_status=%s immediate_control_status=%s controls_required=%s controls_present=%d controls_missing=%d default_control_chunk_unload_total=%s default_control_grace_kept=%s default_control_neighbor_refreshes=%s default_control_chunk_unload_max=%s immediate_control_chunk_unload_total=%s immediate_control_grace_kept=%s immediate_control_neighbor_refreshes=%s immediate_control_chunk_unload_max=%s default_runtime_change_allowed=0 policy_change_allowed=0 candidate_policy_status=deferred popin_budget_status=report_only local_fps_status=report_only godot_gpu_timestamp_status=report_only external_profile_status=pending_external_profiler requires_external_profiler_before_default=1 requires_mac_windows_validation=1 chunk_boundary_summary=%s default_control_summary=%s immediate_control_summary=%s\n", status, reason, text(cb_status), text(cb_reason), text(cb_expected_cases), text(cb_completed_cases), text(cb_movement_cases), text(cb_workload_cases), text(cb_missing_cases), text(cb_require_no_unload), has_fast_turn + 0, has_teleport_snap + 0, text(cb_max_chunk_unload_total), text(cb_max_chunk_unload_grace_kept), text(cb_max_chunk_unload_neighbor_refreshes), text(cb_max_chunk_unload), text(cb_max_popin_missing_chunks), text(cb_max_popin_collision_missing_chunks), text(cb_max_terrain_queue_ms), text(cb_max_process_wall_p95_ms), text(cb_max_gpu_compositor_submit_ms), text(cb_max_packet_queue_lag_ms), text(cb_gpu_upload_fail), text(cb_gpu_upload_fail_capacity), text(cb_gpu_upload_fail_fragmented), text(cb_ground_misses), text(cb_render_not_ready_cases), text(cb_collision_not_ready_cases), default_control_status, immediate_control_status, controls_required, controls_present, controls_missing, text(default_unload_total), text(default_grace_kept), text(default_neighbor_refreshes), text(default_unload_max), text(immediate_unload_total), text(immediate_grace_kept), text(immediate_neighbor_refreshes), text(immediate_unload_max), chunk_boundary_summary, default_control_summary, immediate_control_summary)
    for (i = 1; i <= case_count; i++) {
      print case_rows[i]
    }
    printf("chunk_unload_churn_control name=default_teleport status=%s present=%d top_status=%s case_status=%s chunk_unload_total=%s chunk_unload_grace_kept=%s chunk_unload_neighbor_refreshes=%s chunk_unload_max=%s terrain_queue_max_ms=%s gpu_upload_fail=%s ground_misses=%s current_render_ready=%s current_collision_ready=%s summary=%s\n", default_control_status, default_control_present + 0, text(default_top_status), text(default_case_status), text(default_unload_total), text(default_grace_kept), text(default_neighbor_refreshes), text(default_unload_max), text(default_terrain_queue_ms), text(default_gpu_upload_fail), text(default_ground_misses), text(default_render_ready), text(default_collision_ready), default_control_summary)
    printf("chunk_unload_churn_control name=immediate_teleport status=%s present=%d top_status=%s case_status=%s chunk_unload_total=%s chunk_unload_grace_kept=%s chunk_unload_neighbor_refreshes=%s chunk_unload_max=%s terrain_queue_max_ms=%s gpu_upload_fail=%s ground_misses=%s current_render_ready=%s current_collision_ready=%s summary=%s\n", immediate_control_status, immediate_control_present + 0, text(immediate_top_status), text(immediate_case_status), text(immediate_unload_total), text(immediate_grace_kept), text(immediate_neighbor_refreshes), text(immediate_unload_max), text(immediate_terrain_queue_ms), text(immediate_gpu_upload_fail), text(immediate_ground_misses), text(immediate_render_ready), text(immediate_collision_ready), immediate_control_summary)
    if (status != "pass") {
      exit 1
    }
  }
' "$CHUNK_BOUNDARY_SUMMARY" "$DEFAULT_CONTROL_INPUT" "$IMMEDIATE_CONTROL_INPUT" > "$SUMMARY_PATH" || {
  cat "$SUMMARY_PATH" >&2 || true
  fail "chunk unload churn diagnosis did not pass"
}

cat "$SUMMARY_PATH"
echo "GPU chunk unload churn diagnosis artifacts: $OUT_DIR"
