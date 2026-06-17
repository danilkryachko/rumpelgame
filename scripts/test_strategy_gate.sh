#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/test_strategy_gate_current"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac
SUMMARY_PATH="$OUT_DIR/test-strategy-gate-summary.txt"

EXPLORATION_SOAK_SUMMARY="${RUMPELMC_TEST_STRATEGY_EXPLORATION_SOAK_SUMMARY:-"$ROOT_DIR/logs/world_streaming_exploration_soak_smoke/world-streaming-exploration-soak-summary.txt"}"
RAPID_CAMERA_TURN_SUMMARY="${RUMPELMC_TEST_STRATEGY_RAPID_CAMERA_TURN_SUMMARY:-"$ROOT_DIR/logs/gpu_terrain_rapid_camera_turn_stress_current/rapid-camera-turn-stress-summary.txt"}"
CHUNK_BOUNDARY_SUMMARY="${RUMPELMC_TEST_STRATEGY_CHUNK_BOUNDARY_SUMMARY:-"$ROOT_DIR/logs/gpu_terrain_chunk_boundary_stress_current/chunk-boundary-stress-summary.txt"}"
CHUNK_UNLOAD_CHURN_SUMMARY="${RUMPELMC_TEST_STRATEGY_CHUNK_UNLOAD_CHURN_SUMMARY:-"$ROOT_DIR/logs/gpu_chunk_unload_churn_diagnosis_current/gpu-chunk-unload-churn-diagnosis-summary.txt"}"
REPEATED_EDIT_BENCHMARK_SUMMARY="${RUMPELMC_TEST_STRATEGY_REPEATED_EDIT_BENCHMARK_SUMMARY:-"$ROOT_DIR/logs/gpu_terrain_repeated_edit_benchmark_current/gpu-terrain-repeated-edit-benchmark-summary.txt"}"
BORDER_EDIT_BENCHMARK_SUMMARY="${RUMPELMC_TEST_STRATEGY_BORDER_EDIT_BENCHMARK_SUMMARY:-"$ROOT_DIR/logs/gpu_terrain_border_edit_benchmark_current/gpu-terrain-border-edit-benchmark-summary.txt"}"
PARTIAL_DIRTY_EDGE_MATRIX_SUMMARY="${RUMPELMC_TEST_STRATEGY_PARTIAL_DIRTY_EDGE_MATRIX_SUMMARY:-"$ROOT_DIR/logs/gpu_terrain_partial_dirty_edge_matrix_current/gpu-terrain-partial-dirty-edge-matrix-summary.txt"}"
COLLISION_REFRESH_COST_AUDIT_SUMMARY="${RUMPELMC_TEST_STRATEGY_COLLISION_REFRESH_COST_AUDIT_SUMMARY:-"$ROOT_DIR/logs/gpu_collision_refresh_cost_audit_current/gpu-collision-refresh-cost-audit-summary.txt"}"
SHADOW_PROXY_REFRESH_COST_AUDIT_SUMMARY="${RUMPELMC_TEST_STRATEGY_SHADOW_PROXY_REFRESH_COST_AUDIT_SUMMARY:-"$ROOT_DIR/logs/gpu_shadow_proxy_refresh_cost_audit_current/gpu-shadow-proxy-refresh-cost-audit-summary.txt"}"
EDIT_BURST_BUDGET_SUMMARY="${RUMPELMC_TEST_STRATEGY_EDIT_BURST_BUDGET_SUMMARY:-"$ROOT_DIR/logs/gpu_edit_burst_budget_gate_current/gpu-edit-burst-budget-summary.txt"}"
STREAMING_PRIORITY_AUDIT_SUMMARY="${RUMPELMC_TEST_STRATEGY_STREAMING_PRIORITY_AUDIT_SUMMARY:-"$ROOT_DIR/logs/gpu_streaming_priority_audit_current/gpu-streaming-priority-audit-summary.txt"}"
STREAMING_SCHEDULER_PROTOTYPE_SUMMARY="${RUMPELMC_TEST_STRATEGY_STREAMING_SCHEDULER_PROTOTYPE_SUMMARY:-"$ROOT_DIR/logs/gpu_streaming_scheduler_prototype_current/gpu-streaming-scheduler-prototype-summary.txt"}"
STREAMING_SCHEDULER_WORKLOAD_MATRIX_SUMMARY="${RUMPELMC_TEST_STRATEGY_STREAMING_SCHEDULER_WORKLOAD_MATRIX_SUMMARY:-"$ROOT_DIR/logs/gpu_streaming_scheduler_workload_matrix_current/gpu-streaming-scheduler-workload-matrix-summary.txt"}"
STREAMING_SCHEDULER_TIE_PROBE_SUMMARY="${RUMPELMC_TEST_STRATEGY_STREAMING_SCHEDULER_TIE_PROBE_SUMMARY:-"$ROOT_DIR/logs/gpu_streaming_scheduler_tie_probe_current/gpu-streaming-scheduler-tie-probe-summary.txt"}"
STREAMING_SCHEDULER_DECISION_CHECKPOINT_SUMMARY="${RUMPELMC_TEST_STRATEGY_STREAMING_SCHEDULER_DECISION_CHECKPOINT_SUMMARY:-"$ROOT_DIR/logs/gpu_streaming_scheduler_decision_checkpoint_current/gpu-streaming-scheduler-decision-checkpoint-summary.txt"}"
LOAD_SCALING_SUMMARY="${RUMPELMC_TEST_STRATEGY_LOAD_SCALING_SUMMARY:-"$ROOT_DIR/logs/gpu_terrain_load_scaling_radius16_summary_check/gpu-terrain-load-scaling-summary.txt"}"
UPLOAD_PRESSURE_SUMMARY="${RUMPELMC_TEST_STRATEGY_UPLOAD_PRESSURE_SUMMARY:-"$ROOT_DIR/logs/gpu_terrain_upload_pressure_smoke/gpu-upload-pressure-summary.txt"}"
RESOURCE_LIFECYCLE_SUMMARY="${RUMPELMC_TEST_STRATEGY_RESOURCE_LIFECYCLE_SUMMARY:-"$ROOT_DIR/logs/gpu_terrain_upload_pressure_smoke/gpu-resource-lifecycle-audit-summary.txt"}"
MEMORY_BUDGET_SUMMARY="${RUMPELMC_TEST_STRATEGY_MEMORY_BUDGET_SUMMARY:-"$ROOT_DIR/logs/gpu_terrain_memory_budget_current/gpu-terrain-memory-budget-summary.txt"}"
BUFFER_RESIDENCY_BUDGET_SUMMARY="${RUMPELMC_TEST_STRATEGY_BUFFER_RESIDENCY_BUDGET_SUMMARY:-"$ROOT_DIR/logs/gpu_buffer_residency_budget_current/gpu-buffer-residency-budget-summary.txt"}"
REPORT_V2_SUMMARY="${RUMPELMC_TEST_STRATEGY_REPORT_V2_SUMMARY:-"$ROOT_DIR/logs/gpu_terrain_report_v2_current/gpu-terrain-report-v2-summary.txt"}"
BASELINE_GOVERNANCE_SUMMARY="${RUMPELMC_TEST_STRATEGY_BASELINE_GOVERNANCE_SUMMARY:-"$ROOT_DIR/logs/performance_baseline_governance_current/performance-baseline-governance-summary.txt"}"
GPU_STRESS_INDEX_SUMMARY="${RUMPELMC_TEST_STRATEGY_GPU_STRESS_INDEX_SUMMARY:-"$ROOT_DIR/logs/gpu_stress_artifact_index_current/gpu-stress-artifact-index-summary.txt"}"

mkdir -p "$OUT_DIR"

fail() {
  echo "test_strategy_gate: $*" >&2
  exit 1
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

require_status() {
  label="$1"
  path="$2"
  key="$3"
  expected="$4"
  test -s "$path" || fail "missing $label summary $path"
  value="$(field_metric "$key" "$path")"
  test -n "$value" || fail "missing $key in $(relative_path "$path")"
  if [ "$value" != "$expected" ]; then
    fail "$label $key=$value, expected $expected"
  fi
  printf '%s\n' "$value"
}

test -x "$ROOT_DIR/scripts/check.sh" || fail "missing executable scripts/check.sh"
test -x "$ROOT_DIR/scripts/diff_guard.sh" || fail "missing executable scripts/diff_guard.sh"
test -x "$ROOT_DIR/scripts/world_streaming_exploration_soak.sh" || fail "missing executable world streaming soak wrapper"
test -x "$ROOT_DIR/scripts/gpu_terrain_rapid_camera_turn_stress.sh" || fail "missing executable rapid camera-turn stress wrapper"
test -x "$ROOT_DIR/scripts/gpu_terrain_chunk_boundary_stress.sh" || fail "missing executable chunk boundary stress wrapper"
test -x "$ROOT_DIR/scripts/gpu_chunk_unload_churn_diagnosis.sh" || fail "missing executable GPU chunk unload churn diagnosis wrapper"
test -x "$ROOT_DIR/scripts/gpu_terrain_repeated_edit_benchmark.sh" || fail "missing executable repeated edit benchmark wrapper"
test -x "$ROOT_DIR/scripts/gpu_terrain_border_edit_benchmark.sh" || fail "missing executable border edit benchmark wrapper"
test -x "$ROOT_DIR/scripts/gpu_terrain_partial_dirty_edge_matrix.sh" || fail "missing executable partial dirty edge matrix wrapper"
test -x "$ROOT_DIR/scripts/gpu_collision_refresh_cost_audit.sh" || fail "missing executable collision refresh cost audit wrapper"
test -x "$ROOT_DIR/scripts/gpu_shadow_proxy_refresh_cost_audit.sh" || fail "missing executable shadow proxy refresh cost audit wrapper"
test -x "$ROOT_DIR/scripts/gpu_edit_burst_budget_gate.sh" || fail "missing executable edit burst budget gate"
test -x "$ROOT_DIR/scripts/gpu_streaming_priority_audit.sh" || fail "missing executable GPU streaming priority audit wrapper"
test -x "$ROOT_DIR/scripts/gpu_streaming_scheduler_prototype.sh" || fail "missing executable GPU streaming scheduler prototype wrapper"
test -x "$ROOT_DIR/scripts/gpu_streaming_scheduler_workload_matrix.sh" || fail "missing executable GPU streaming scheduler workload matrix wrapper"
test -x "$ROOT_DIR/scripts/gpu_streaming_scheduler_tie_probe.sh" || fail "missing executable GPU streaming scheduler tie probe wrapper"
test -x "$ROOT_DIR/scripts/gpu_streaming_scheduler_decision_checkpoint.sh" || fail "missing executable GPU streaming scheduler decision checkpoint wrapper"
test -x "$ROOT_DIR/scripts/gpu_streaming_scheduler_boundary_matrix.sh" || fail "missing executable GPU streaming scheduler boundary matrix wrapper"
test -x "$ROOT_DIR/scripts/gpu_terrain_load_scaling.sh" || fail "missing executable load scaling wrapper"
test -x "$ROOT_DIR/scripts/gpu_terrain_upload_pressure.sh" || fail "missing executable upload pressure wrapper"
test -x "$ROOT_DIR/scripts/gpu_resource_lifecycle_audit.sh" || fail "missing executable resource lifecycle audit"
test -x "$ROOT_DIR/scripts/gpu_terrain_memory_budget.sh" || fail "missing executable memory budget gate"
test -x "$ROOT_DIR/scripts/gpu_buffer_residency_budget.sh" || fail "missing executable buffer residency budget gate"
test -x "$ROOT_DIR/scripts/gpu_terrain_report_v2.sh" || fail "missing executable report V2 wrapper"
test -x "$ROOT_DIR/scripts/performance_baseline_governance.sh" || fail "missing executable baseline governance wrapper"
test -x "$ROOT_DIR/scripts/gpu_stress_artifact_index.sh" || fail "missing executable GPU stress artifact index"

exploration_status="$(require_status exploration_soak "$EXPLORATION_SOAK_SUMMARY" status pass)"
rapid_camera_turn_status="$(require_status rapid_camera_turn "$RAPID_CAMERA_TURN_SUMMARY" status pass)"
chunk_boundary_status="$(require_status chunk_boundary "$CHUNK_BOUNDARY_SUMMARY" status pass)"
chunk_unload_churn_status="$(require_status chunk_unload_churn "$CHUNK_UNLOAD_CHURN_SUMMARY" status pass)"
repeated_edit_benchmark_status="$(require_status repeated_edit_benchmark "$REPEATED_EDIT_BENCHMARK_SUMMARY" status pass)"
border_edit_benchmark_status="$(require_status border_edit_benchmark "$BORDER_EDIT_BENCHMARK_SUMMARY" status pass)"
partial_dirty_edge_matrix_status="$(require_status partial_dirty_edge_matrix "$PARTIAL_DIRTY_EDGE_MATRIX_SUMMARY" status pass)"
collision_refresh_cost_audit_status="$(require_status collision_refresh_cost_audit "$COLLISION_REFRESH_COST_AUDIT_SUMMARY" status pass)"
shadow_proxy_refresh_cost_audit_status="$(require_status shadow_proxy_refresh_cost_audit "$SHADOW_PROXY_REFRESH_COST_AUDIT_SUMMARY" status pass)"
edit_burst_budget_status="$(require_status edit_burst_budget "$EDIT_BURST_BUDGET_SUMMARY" status pass)"
streaming_priority_audit_status="$(require_status streaming_priority_audit "$STREAMING_PRIORITY_AUDIT_SUMMARY" status pass)"
streaming_scheduler_prototype_status="$(require_status streaming_scheduler_prototype "$STREAMING_SCHEDULER_PROTOTYPE_SUMMARY" status pass)"
streaming_scheduler_workload_matrix_status="$(require_status streaming_scheduler_workload_matrix "$STREAMING_SCHEDULER_WORKLOAD_MATRIX_SUMMARY" status pass)"
streaming_scheduler_tie_probe_status="$(require_status streaming_scheduler_tie_probe "$STREAMING_SCHEDULER_TIE_PROBE_SUMMARY" status pass)"
streaming_scheduler_decision_checkpoint_status="$(require_status streaming_scheduler_decision_checkpoint "$STREAMING_SCHEDULER_DECISION_CHECKPOINT_SUMMARY" status pass)"
load_status="$(require_status load_scaling "$LOAD_SCALING_SUMMARY" status pass)"
upload_status="$(require_status upload_pressure "$UPLOAD_PRESSURE_SUMMARY" status pass)"
resource_status="$(require_status resource_lifecycle "$RESOURCE_LIFECYCLE_SUMMARY" resource_lifecycle_audit_status pass)"
memory_status="$(require_status memory_budget "$MEMORY_BUDGET_SUMMARY" status pass)"
buffer_residency_status="$(require_status buffer_residency_budget "$BUFFER_RESIDENCY_BUDGET_SUMMARY" status pass)"
report_v2_status="$(require_status report_v2 "$REPORT_V2_SUMMARY" status pass)"
baseline_status="$(require_status baseline_governance "$BASELINE_GOVERNANCE_SUMMARY" status pass)"
gpu_stress_index_status="$(require_status gpu_stress_index "$GPU_STRESS_INDEX_SUMMARY" status pass)"

{
  printf 'test_strategy_gate status=pass fast_command="%s" full_command="%s" nightly_runtime_command="%s" nightly_summary_command="%s" exploration_soak_status=%s rapid_camera_turn_status=%s chunk_boundary_status=%s chunk_unload_churn_status=%s repeated_edit_benchmark_status=%s border_edit_benchmark_status=%s partial_dirty_edge_matrix_status=%s collision_refresh_cost_audit_status=%s shadow_proxy_refresh_cost_audit_status=%s edit_burst_budget_status=%s streaming_priority_audit_status=%s streaming_scheduler_prototype_status=%s streaming_scheduler_workload_matrix_status=%s streaming_scheduler_tie_probe_status=%s streaming_scheduler_decision_checkpoint_status=%s load_scaling_status=%s upload_pressure_status=%s resource_lifecycle_status=%s memory_budget_status=%s buffer_residency_budget_status=%s report_v2_status=%s baseline_governance_status=%s gpu_stress_index_status=%s exploration_soak_summary=%s rapid_camera_turn_summary=%s chunk_boundary_summary=%s chunk_unload_churn_summary=%s repeated_edit_benchmark_summary=%s border_edit_benchmark_summary=%s partial_dirty_edge_matrix_summary=%s collision_refresh_cost_audit_summary=%s shadow_proxy_refresh_cost_audit_summary=%s edit_burst_budget_summary=%s streaming_priority_audit_summary=%s streaming_scheduler_prototype_summary=%s streaming_scheduler_workload_matrix_summary=%s streaming_scheduler_tie_probe_summary=%s streaming_scheduler_decision_checkpoint_summary=%s load_scaling_summary=%s upload_pressure_summary=%s resource_lifecycle_summary=%s memory_budget_summary=%s buffer_residency_budget_summary=%s report_v2_summary=%s baseline_governance_summary=%s gpu_stress_index_summary=%s\n' \
    './scripts/check.sh fast' \
    './scripts/check.sh full && git diff --check && ./scripts/diff_guard.sh' \
    'RUMPELMC_EXPLORATION_SOAK_REPEATS=3 ./scripts/world_streaming_exploration_soak.sh logs/nightly/world_streaming_exploration_soak && ./scripts/gpu_terrain_rapid_camera_turn_stress.sh logs/nightly/gpu_terrain_rapid_camera_turn_stress && ./scripts/gpu_terrain_chunk_boundary_stress.sh logs/nightly/gpu_terrain_chunk_boundary_stress && RUMPELMC_STREAMING_SCHEDULER_MATRIX_RUN_WORKLOADS=1 ./scripts/gpu_streaming_scheduler_workload_matrix.sh logs/gpu_streaming_scheduler_workload_matrix_current && ./scripts/gpu_terrain_load_scaling.sh logs/nightly/gpu_terrain_load_scaling && ./scripts/gpu_terrain_upload_pressure.sh logs/nightly/gpu_terrain_upload_pressure && ./scripts/gpu_terrain_upload_stage_pool_load_scaling_gate.sh logs/gpu_terrain_upload_stage_pool_load_scaling_current && ./scripts/gpu_terrain_grouped_draws_gate.sh logs/gpu_terrain_grouped_draws_current && ./scripts/gpu_terrain_cutout_pressure_load_scaling_gate.sh logs/gpu_terrain_cutout_pressure_load_scaling_current' \
    './scripts/gpu_chunk_unload_churn_diagnosis.sh logs/gpu_chunk_unload_churn_diagnosis_current && ./scripts/gpu_terrain_repeated_edit_benchmark.sh logs/gpu_terrain_repeated_edit_benchmark_current && ./scripts/gpu_terrain_border_edit_benchmark.sh logs/gpu_terrain_border_edit_benchmark_current && ./scripts/gpu_terrain_partial_dirty_edge_matrix.sh logs/gpu_terrain_partial_dirty_edge_matrix_current && ./scripts/gpu_collision_refresh_cost_audit.sh logs/gpu_collision_refresh_cost_audit_current && ./scripts/gpu_shadow_proxy_refresh_cost_audit.sh logs/gpu_shadow_proxy_refresh_cost_audit_current && sh scripts/gpu_edit_burst_budget_gate.sh logs/gpu_edit_burst_budget_gate_current && ./scripts/gpu_resource_lifecycle_audit.sh logs/gpu_terrain_upload_pressure_smoke && ./scripts/gpu_terrain_memory_budget.sh logs/gpu_terrain_memory_budget_current && ./scripts/gpu_terrain_mass_chunk_load_gate.sh logs/gpu_terrain_mass_chunk_load_current && ./scripts/gpu_buffer_residency_budget.sh logs/gpu_buffer_residency_budget_current && ./scripts/gpu_streaming_priority_audit.sh logs/gpu_streaming_priority_audit_current && ./scripts/gpu_streaming_scheduler_prototype.sh logs/gpu_streaming_scheduler_prototype_current && ./scripts/gpu_streaming_scheduler_workload_matrix.sh logs/gpu_streaming_scheduler_workload_matrix_current && ./scripts/gpu_streaming_scheduler_tie_probe.sh logs/gpu_streaming_scheduler_tie_probe_current && ./scripts/gpu_streaming_scheduler_decision_checkpoint.sh logs/gpu_streaming_scheduler_decision_checkpoint_current && ./scripts/gpu_terrain_report_v2.sh logs/gpu_terrain_upload_pressure_smoke logs/gpu_terrain_report_v2_current && ./scripts/performance_baseline_governance.sh && ./scripts/gpu_stress_artifact_index.sh logs/gpu_stress_artifact_index_current' \
    "$exploration_status" \
    "$rapid_camera_turn_status" \
    "$chunk_boundary_status" \
    "$chunk_unload_churn_status" \
    "$repeated_edit_benchmark_status" \
    "$border_edit_benchmark_status" \
    "$partial_dirty_edge_matrix_status" \
    "$collision_refresh_cost_audit_status" \
    "$shadow_proxy_refresh_cost_audit_status" \
    "$edit_burst_budget_status" \
    "$streaming_priority_audit_status" \
    "$streaming_scheduler_prototype_status" \
    "$streaming_scheduler_workload_matrix_status" \
    "$streaming_scheduler_tie_probe_status" \
    "$streaming_scheduler_decision_checkpoint_status" \
    "$load_status" \
    "$upload_status" \
    "$resource_status" \
    "$memory_status" \
    "$buffer_residency_status" \
    "$report_v2_status" \
    "$baseline_status" \
    "$gpu_stress_index_status" \
    "$(relative_path "$EXPLORATION_SOAK_SUMMARY")" \
    "$(relative_path "$RAPID_CAMERA_TURN_SUMMARY")" \
    "$(relative_path "$CHUNK_BOUNDARY_SUMMARY")" \
    "$(relative_path "$CHUNK_UNLOAD_CHURN_SUMMARY")" \
    "$(relative_path "$REPEATED_EDIT_BENCHMARK_SUMMARY")" \
    "$(relative_path "$BORDER_EDIT_BENCHMARK_SUMMARY")" \
    "$(relative_path "$PARTIAL_DIRTY_EDGE_MATRIX_SUMMARY")" \
    "$(relative_path "$COLLISION_REFRESH_COST_AUDIT_SUMMARY")" \
    "$(relative_path "$SHADOW_PROXY_REFRESH_COST_AUDIT_SUMMARY")" \
    "$(relative_path "$EDIT_BURST_BUDGET_SUMMARY")" \
    "$(relative_path "$STREAMING_PRIORITY_AUDIT_SUMMARY")" \
    "$(relative_path "$STREAMING_SCHEDULER_PROTOTYPE_SUMMARY")" \
    "$(relative_path "$STREAMING_SCHEDULER_WORKLOAD_MATRIX_SUMMARY")" \
    "$(relative_path "$STREAMING_SCHEDULER_TIE_PROBE_SUMMARY")" \
    "$(relative_path "$STREAMING_SCHEDULER_DECISION_CHECKPOINT_SUMMARY")" \
    "$(relative_path "$LOAD_SCALING_SUMMARY")" \
    "$(relative_path "$UPLOAD_PRESSURE_SUMMARY")" \
    "$(relative_path "$RESOURCE_LIFECYCLE_SUMMARY")" \
    "$(relative_path "$MEMORY_BUDGET_SUMMARY")" \
    "$(relative_path "$BUFFER_RESIDENCY_BUDGET_SUMMARY")" \
    "$(relative_path "$REPORT_V2_SUMMARY")" \
    "$(relative_path "$BASELINE_GOVERNANCE_SUMMARY")" \
    "$(relative_path "$GPU_STRESS_INDEX_SUMMARY")"
} > "$SUMMARY_PATH"

cat "$SUMMARY_PATH"
