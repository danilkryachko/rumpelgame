#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/gpu_streaming_scheduler_decision_checkpoint_current"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

SUMMARY_PATH="$OUT_DIR/gpu-streaming-scheduler-decision-checkpoint-summary.txt"
PROTOTYPE_SUMMARY="${RUMPELMC_STREAMING_SCHEDULER_DECISION_PROTOTYPE_SUMMARY:-"$ROOT_DIR/logs/gpu_streaming_scheduler_prototype_current/gpu-streaming-scheduler-prototype-summary.txt"}"
WORKLOAD_MATRIX_SUMMARY="${RUMPELMC_STREAMING_SCHEDULER_DECISION_WORKLOAD_MATRIX_SUMMARY:-"$ROOT_DIR/logs/gpu_streaming_scheduler_workload_matrix_current/gpu-streaming-scheduler-workload-matrix-summary.txt"}"
CHUNK_BOUNDARY_SUMMARY="${RUMPELMC_STREAMING_SCHEDULER_DECISION_CHUNK_BOUNDARY_SUMMARY:-"$ROOT_DIR/logs/gpu_terrain_chunk_boundary_stress_current/chunk-boundary-stress-summary.txt"}"
BUFFER_RESIDENCY_BUDGET_SUMMARY="${RUMPELMC_STREAMING_SCHEDULER_DECISION_BUFFER_RESIDENCY_BUDGET_SUMMARY:-"$ROOT_DIR/logs/gpu_buffer_residency_budget_current/gpu-buffer-residency-budget-summary.txt"}"
BOUNDARY_MATRIX_SUMMARY="${RUMPELMC_STREAMING_SCHEDULER_DECISION_BOUNDARY_MATRIX_SUMMARY:-"$ROOT_DIR/logs/gpu_streaming_scheduler_boundary_matrix_current/gpu-streaming-scheduler-boundary-matrix-summary.txt"}"

mkdir -p "$OUT_DIR"

fail() {
  echo "gpu_streaming_scheduler_decision_checkpoint: $*" >&2
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

optional_field() {
  key="$1"
  path="$2"
  if [ -s "$path" ]; then
    value="$(field_metric "$key" "$path")"
    if [ -n "$value" ]; then
      printf '%s\n' "$value"
      return
    fi
  fi
  printf 'n/a\n'
}

require_field() {
  label="$1"
  key="$2"
  expected="$3"
  path="$4"
  value="$(field_metric "$key" "$path")"
  test -n "$value" || fail "missing $key in $(relative_path "$path")"
  test "$value" = "$expected" || fail "$label $key=$value, expected $expected"
  printf '%s\n' "$value"
}

PROTOTYPE_SUMMARY="$(normalize_path "$PROTOTYPE_SUMMARY")"
WORKLOAD_MATRIX_SUMMARY="$(normalize_path "$WORKLOAD_MATRIX_SUMMARY")"
CHUNK_BOUNDARY_SUMMARY="$(normalize_path "$CHUNK_BOUNDARY_SUMMARY")"
BUFFER_RESIDENCY_BUDGET_SUMMARY="$(normalize_path "$BUFFER_RESIDENCY_BUDGET_SUMMARY")"
BOUNDARY_MATRIX_SUMMARY="$(normalize_path "$BOUNDARY_MATRIX_SUMMARY")"

test -s "$PROTOTYPE_SUMMARY" || fail "missing scheduler prototype summary $PROTOTYPE_SUMMARY"
test -s "$WORKLOAD_MATRIX_SUMMARY" || fail "missing scheduler workload matrix summary $WORKLOAD_MATRIX_SUMMARY"
test -s "$CHUNK_BOUNDARY_SUMMARY" || fail "missing chunk-boundary summary $CHUNK_BOUNDARY_SUMMARY"
test -s "$BUFFER_RESIDENCY_BUDGET_SUMMARY" || fail "missing buffer residency budget summary $BUFFER_RESIDENCY_BUDGET_SUMMARY"

prototype_status="$(require_field prototype status pass "$PROTOTYPE_SUMMARY")"
prototype_default_scheduler="$(require_field prototype default_scheduler_mode nearest "$PROTOTYPE_SUMMARY")"
prototype_default_active="$(require_field prototype stream_scheduler_active_default 0 "$PROTOTYPE_SUMMARY")"
prototype_scheduler_change_allowed="$(require_field prototype scheduler_change_allowed 0 "$PROTOTYPE_SUMMARY")"

workload_status="$(require_field workload_matrix status pass "$WORKLOAD_MATRIX_SUMMARY")"
workload_scheduler_change_allowed="$(require_field workload_matrix scheduler_change_allowed 0 "$WORKLOAD_MATRIX_SUMMARY")"
workload_default_runtime_change_allowed="$(require_field workload_matrix default_runtime_change_allowed 0 "$WORKLOAD_MATRIX_SUMMARY")"
workload_requires_profiler="$(require_field workload_matrix requires_external_profiler_before_default 1 "$WORKLOAD_MATRIX_SUMMARY")"
workload_requires_validation="$(require_field workload_matrix requires_mac_windows_validation 1 "$WORKLOAD_MATRIX_SUMMARY")"

chunk_boundary_status="$(require_field chunk_boundary status pass "$CHUNK_BOUNDARY_SUMMARY")"
chunk_boundary_upload_fail="$(require_field chunk_boundary gpu_upload_fail 0 "$CHUNK_BOUNDARY_SUMMARY")"
chunk_boundary_ground_misses="$(require_field chunk_boundary ground_misses 0 "$CHUNK_BOUNDARY_SUMMARY")"
chunk_boundary_unload_total="$(require_field chunk_boundary max_chunk_unload_total 0 "$CHUNK_BOUNDARY_SUMMARY")"
chunk_boundary_unload_refreshes="$(require_field chunk_boundary max_chunk_unload_neighbor_refreshes 0 "$CHUNK_BOUNDARY_SUMMARY")"
chunk_boundary_render_not_ready="$(require_field chunk_boundary render_not_ready_cases 0 "$CHUNK_BOUNDARY_SUMMARY")"
chunk_boundary_collision_not_ready="$(require_field chunk_boundary collision_not_ready_cases 0 "$CHUNK_BOUNDARY_SUMMARY")"

residency_status="$(require_field buffer_residency status pass "$BUFFER_RESIDENCY_BUDGET_SUMMARY")"
residency_requires_profiler="$(require_field buffer_residency requires_external_profiler_before_default 1 "$BUFFER_RESIDENCY_BUDGET_SUMMARY")"
residency_requires_validation="$(require_field buffer_residency requires_mac_windows_validation 1 "$BUFFER_RESIDENCY_BUDGET_SUMMARY")"

workload_harness_status="$(field_metric matrix_harness_status "$WORKLOAD_MATRIX_SUMMARY")"
workload_candidate_status="$(field_metric candidate_scheduler_status "$WORKLOAD_MATRIX_SUMMARY")"
workload_runtime_signal="$(field_metric runtime_signal "$WORKLOAD_MATRIX_SUMMARY")"
workload_failed_cases="$(field_metric failed_cases "$WORKLOAD_MATRIX_SUMMARY")"
workload_baseline_pass_cases="$(field_metric baseline_pass_cases "$WORKLOAD_MATRIX_SUMMARY")"
workload_preview_pass_cases="$(field_metric preview_pass_cases "$WORKLOAD_MATRIX_SUMMARY")"
workload_active_pass_cases="$(field_metric active_pass_cases "$WORKLOAD_MATRIX_SUMMARY")"
workload_queue_max="$(field_metric max_terrain_queue_ms "$WORKLOAD_MATRIX_SUMMARY")"
workload_process_max="$(field_metric max_process_wall_p95_ms "$WORKLOAD_MATRIX_SUMMARY")"
workload_submit_max="$(field_metric max_gpu_compositor_submit_ms "$WORKLOAD_MATRIX_SUMMARY")"
workload_packet_lag_max="$(field_metric max_packet_queue_lag_ms "$WORKLOAD_MATRIX_SUMMARY")"
workload_preview_mismatch_max="$(field_metric max_stream_scheduler_preview_mismatch "$WORKLOAD_MATRIX_SUMMARY")"
workload_mesh_ties_max="$(field_metric max_mesh_scheduler_directional_ties "$WORKLOAD_MATRIX_SUMMARY")"
workload_collision_ties_max="$(field_metric max_collision_scheduler_directional_ties "$WORKLOAD_MATRIX_SUMMARY")"
workload_fifo_fallbacks_max="$(field_metric max_stream_scheduler_fifo_fallbacks "$WORKLOAD_MATRIX_SUMMARY")"

boundary_matrix_status="missing"
boundary_harness_status="missing"
boundary_candidate_status="missing"
boundary_runtime_signal="0"
boundary_matrix_path="missing"
if [ -s "$BOUNDARY_MATRIX_SUMMARY" ]; then
  boundary_matrix_status="$(optional_field status "$BOUNDARY_MATRIX_SUMMARY")"
  boundary_harness_status="$(optional_field boundary_harness_status "$BOUNDARY_MATRIX_SUMMARY")"
  boundary_candidate_status="$(optional_field candidate_scheduler_status "$BOUNDARY_MATRIX_SUMMARY")"
  boundary_runtime_signal="$(optional_field runtime_signal "$BOUNDARY_MATRIX_SUMMARY")"
  boundary_matrix_path="$(relative_path "$BOUNDARY_MATRIX_SUMMARY")"
fi

chunk_boundary_queue_max="$(field_metric max_terrain_queue_ms "$CHUNK_BOUNDARY_SUMMARY")"
chunk_boundary_process_max="$(field_metric max_process_wall_p95_ms "$CHUNK_BOUNDARY_SUMMARY")"
chunk_boundary_submit_max="$(field_metric max_gpu_compositor_submit_ms "$CHUNK_BOUNDARY_SUMMARY")"
chunk_boundary_packet_lag_max="$(field_metric max_packet_queue_lag_ms "$CHUNK_BOUNDARY_SUMMARY")"
residency_pressure_class="$(field_metric residency_pressure_class "$BUFFER_RESIDENCY_BUDGET_SUMMARY")"
residency_proof_status="$(field_metric residency_proof_status "$BUFFER_RESIDENCY_BUDGET_SUMMARY")"
allocator_evidence_status="$(field_metric allocator_evidence_status "$BUFFER_RESIDENCY_BUDGET_SUMMARY")"
configured_buffer_bytes="$(field_metric configured_buffer_bytes "$BUFFER_RESIDENCY_BUDGET_SUMMARY")"
configured_buffer_budget_pct="$(field_metric configured_buffer_budget_pct "$BUFFER_RESIDENCY_BUDGET_SUMMARY")"
active_face_bytes="$(field_metric active_face_bytes "$BUFFER_RESIDENCY_BUDGET_SUMMARY")"
active_face_budget_pct="$(field_metric active_face_budget_pct "$BUFFER_RESIDENCY_BUDGET_SUMMARY")"

decision_status="defer_external_profiler_required"
if [ "$workload_harness_status" != "complete" ]; then
  decision_status="defer_matrix_harness_unstable"
elif [ "$workload_candidate_status" = "reject_runtime_regression" ]; then
  decision_status="reject_runtime_regression"
elif [ "$workload_runtime_signal" = "0" ]; then
  decision_status="defer_no_runtime_signal"
fi
if [ "$boundary_matrix_status" = "fail" ] || [ "$boundary_harness_status" = "partial" ]; then
  decision_status="defer_boundary_harness_unstable"
fi

{
  printf 'gpu_streaming_scheduler_decision_checkpoint status=pass reason=ok prototype_status=%s prototype_default_scheduler=%s prototype_default_active=%s prototype_scheduler_change_allowed=%s workload_matrix_status=%s workload_matrix_harness_status=%s workload_candidate_scheduler_status=%s workload_failed_cases=%s workload_baseline_pass_cases=%s workload_preview_pass_cases=%s workload_active_pass_cases=%s workload_runtime_signal=%s workload_preview_mismatch_max=%s workload_mesh_directional_ties_max=%s workload_collision_directional_ties_max=%s workload_fifo_fallbacks_max=%s workload_max_terrain_queue_ms=%s workload_max_process_wall_p95_ms=%s workload_max_gpu_compositor_submit_ms=%s workload_max_packet_queue_lag_ms=%s chunk_boundary_status=%s chunk_boundary_upload_fail=%s chunk_boundary_ground_misses=%s chunk_boundary_unload_total=%s chunk_boundary_unload_neighbor_refreshes=%s chunk_boundary_render_not_ready_cases=%s chunk_boundary_collision_not_ready_cases=%s chunk_boundary_max_terrain_queue_ms=%s chunk_boundary_max_process_wall_p95_ms=%s chunk_boundary_max_gpu_compositor_submit_ms=%s chunk_boundary_max_packet_queue_lag_ms=%s residency_status=%s residency_pressure_class=%s residency_proof_status=%s allocator_evidence_status=%s configured_buffer_bytes=%s configured_buffer_budget_pct=%s active_face_bytes=%s active_face_budget_pct=%s boundary_matrix_status=%s boundary_harness_status=%s boundary_candidate_scheduler_status=%s boundary_runtime_signal=%s scheduler_change_allowed=0 default_runtime_change_allowed=0 decision_status=%s candidate_scheduler_status=%s external_profile_status=pending_external_profiler requires_external_profiler_before_default=1 requires_mac_windows_validation=1 workload_scheduler_change_allowed=%s workload_default_runtime_change_allowed=%s workload_requires_external_profiler_before_default=%s workload_requires_mac_windows_validation=%s residency_requires_external_profiler_before_default=%s residency_requires_mac_windows_validation=%s prototype_summary=%s workload_matrix_summary=%s chunk_boundary_summary=%s buffer_residency_budget_summary=%s boundary_matrix_summary=%s\n' \
    "$prototype_status" "$prototype_default_scheduler" "$prototype_default_active" "$prototype_scheduler_change_allowed" \
    "$workload_status" "$workload_harness_status" "$workload_candidate_status" "$workload_failed_cases" \
    "$workload_baseline_pass_cases" "$workload_preview_pass_cases" "$workload_active_pass_cases" "$workload_runtime_signal" \
    "$workload_preview_mismatch_max" "$workload_mesh_ties_max" "$workload_collision_ties_max" "$workload_fifo_fallbacks_max" \
    "$workload_queue_max" "$workload_process_max" "$workload_submit_max" "$workload_packet_lag_max" \
    "$chunk_boundary_status" "$chunk_boundary_upload_fail" "$chunk_boundary_ground_misses" "$chunk_boundary_unload_total" \
    "$chunk_boundary_unload_refreshes" "$chunk_boundary_render_not_ready" "$chunk_boundary_collision_not_ready" \
    "$chunk_boundary_queue_max" "$chunk_boundary_process_max" "$chunk_boundary_submit_max" "$chunk_boundary_packet_lag_max" \
    "$residency_status" "$residency_pressure_class" "$residency_proof_status" "$allocator_evidence_status" \
    "$configured_buffer_bytes" "$configured_buffer_budget_pct" "$active_face_bytes" "$active_face_budget_pct" \
    "$boundary_matrix_status" "$boundary_harness_status" "$boundary_candidate_status" "$boundary_runtime_signal" \
    "$decision_status" "$decision_status" "$workload_scheduler_change_allowed" "$workload_default_runtime_change_allowed" \
    "$workload_requires_profiler" "$workload_requires_validation" "$residency_requires_profiler" "$residency_requires_validation" \
    "$(relative_path "$PROTOTYPE_SUMMARY")" "$(relative_path "$WORKLOAD_MATRIX_SUMMARY")" "$(relative_path "$CHUNK_BOUNDARY_SUMMARY")" \
    "$(relative_path "$BUFFER_RESIDENCY_BUDGET_SUMMARY")" "$boundary_matrix_path"
} > "$SUMMARY_PATH"

cat "$SUMMARY_PATH"
