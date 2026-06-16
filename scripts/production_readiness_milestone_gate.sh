#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/production_readiness_milestone"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

SUMMARY_PATH="$OUT_DIR/production-readiness-milestone-summary.txt"
REPORT_PATH="$OUT_DIR/production-readiness-milestone-report.txt"
DESIGN_DOC="${RUMPELMC_PRODUCTION_READINESS_DOC:-"$ROOT_DIR/docs/PRODUCTION_READINESS_MILESTONE.md"}"
EXPLORATION_SUMMARY="${RUMPELMC_PRODUCTION_EXPLORATION_SUMMARY:-"$ROOT_DIR/logs/world_streaming_exploration_soak_smoke/world-streaming-exploration-soak-summary.txt"}"
RESIDENT_SUMMARY="${RUMPELMC_PRODUCTION_RESIDENT_SUMMARY:-"$ROOT_DIR/logs/world_streaming_resident_set_growth_radius16_check/resident-set-growth-summary.txt"}"
LOAD_SCALING_SUMMARY="${RUMPELMC_PRODUCTION_LOAD_SCALING_SUMMARY:-"$ROOT_DIR/logs/gpu_terrain_load_scaling_radius16_summary_check/gpu-terrain-load-scaling-summary.txt"}"
UPLOAD_SUMMARY="${RUMPELMC_PRODUCTION_UPLOAD_SUMMARY:-"$ROOT_DIR/logs/gpu_terrain_upload_pressure_smoke/gpu-upload-pressure-summary.txt"}"
MEMORY_SUMMARY="${RUMPELMC_PRODUCTION_MEMORY_SUMMARY:-"$ROOT_DIR/logs/gpu_terrain_memory_budget_current/gpu-terrain-memory-budget-summary.txt"}"
RESOURCE_SUMMARY="${RUMPELMC_PRODUCTION_RESOURCE_SUMMARY:-"$ROOT_DIR/logs/gpu_terrain_upload_pressure_smoke/gpu-resource-lifecycle-audit-summary.txt"}"
BASELINE_SUMMARY="${RUMPELMC_PRODUCTION_BASELINE_SUMMARY:-"$ROOT_DIR/logs/performance_baseline_governance_current/performance-baseline-governance-summary.txt"}"
SECURITY_SUMMARY="${RUMPELMC_PRODUCTION_SECURITY_SUMMARY:-"$ROOT_DIR/logs/security_data_integrity_review_current/security-data-integrity-review-summary.txt"}"
OBSERVABILITY_SUMMARY="${RUMPELMC_PRODUCTION_OBSERVABILITY_SUMMARY:-"$ROOT_DIR/logs/observability_logs_cleanup_current/observability-logs-cleanup-summary.txt"}"
ARCH_SUMMARY="${RUMPELMC_PRODUCTION_ARCH_SUMMARY:-"$ROOT_DIR/logs/architecture_documentation_refresh_current/architecture-documentation-refresh-summary.txt"}"
HANDOFF_SUMMARY="${RUMPELMC_PRODUCTION_HANDOFF_SUMMARY:-"$ROOT_DIR/logs/automated_handoff_discipline_current/automated-handoff-discipline-summary.txt"}"
RC_SUMMARY="${RUMPELMC_PRODUCTION_RC_SUMMARY:-"$ROOT_DIR/logs/release_candidate_gate_current/release-candidate-gate-summary.txt"}"
EXTERNAL_PROFILING_SUMMARY="${RUMPELMC_PRODUCTION_EXTERNAL_PROFILING_SUMMARY:-"$ROOT_DIR/logs/external_profiling_campaign_current/external-profiling-campaign-summary.txt"}"
NATIVE_SHADOW_SUMMARY="${RUMPELMC_PRODUCTION_NATIVE_SHADOW_SUMMARY:-"$ROOT_DIR/logs/gpu_native_shadow_prototype_preflight_current/gpu-native-shadow-prototype-preflight-summary.txt"}"
SHADOW_RETIREMENT_SUMMARY="${RUMPELMC_PRODUCTION_SHADOW_RETIREMENT_SUMMARY:-"$ROOT_DIR/logs/shadow_proxy_retirement_plan_current/shadow-proxy-retirement-summary.txt"}"
TRANSPARENT_PREFLIGHT_SUMMARY="${RUMPELMC_PRODUCTION_TRANSPARENT_PREFLIGHT_SUMMARY:-"$ROOT_DIR/logs/transparent_active_path_preflight_current/transparent-active-path-preflight-summary.txt"}"
TRANSPARENT_ACCEPTANCE_SUMMARY="${RUMPELMC_PRODUCTION_TRANSPARENT_ACCEPTANCE_SUMMARY:-"$ROOT_DIR/logs/transparent_fixture_acceptance_suite_current/transparent-fixture-acceptance-suite-summary.txt"}"

mkdir -p "$OUT_DIR"

fail() {
  echo "production_readiness_milestone_gate: $*" >&2
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

require_token() {
  path="$1"
  token="$2"
  test -s "$path" || fail "missing file $path"
  grep -Fq "$token" "$path" || fail "missing token '$token' in $path"
}

for path in \
  "$DESIGN_DOC" \
  "$EXPLORATION_SUMMARY" \
  "$RESIDENT_SUMMARY" \
  "$LOAD_SCALING_SUMMARY" \
  "$UPLOAD_SUMMARY" \
  "$MEMORY_SUMMARY" \
  "$RESOURCE_SUMMARY" \
  "$BASELINE_SUMMARY" \
  "$SECURITY_SUMMARY" \
  "$OBSERVABILITY_SUMMARY" \
  "$ARCH_SUMMARY" \
  "$HANDOFF_SUMMARY" \
  "$RC_SUMMARY" \
  "$EXTERNAL_PROFILING_SUMMARY" \
  "$NATIVE_SHADOW_SUMMARY" \
  "$SHADOW_RETIREMENT_SUMMARY" \
  "$TRANSPARENT_PREFLIGHT_SUMMARY" \
  "$TRANSPARENT_ACCEPTANCE_SUMMARY"; do
  test -s "$path" || fail "missing required input $path"
done

for token in \
  'Technical Brief' \
  'Milestone Verdict' \
  'Deferred Release Blockers' \
  'Compatibility Rules'; do
  require_token "$DESIGN_DOC" "$token"
done

exploration_status="$(field_metric status "$EXPLORATION_SUMMARY")"
exploration_gpu_upload_fail="$(field_metric gpu_upload_fail "$EXPLORATION_SUMMARY")"
exploration_ground_misses="$(field_metric ground_misses "$EXPLORATION_SUMMARY")"
resident_status="$(field_metric status "$RESIDENT_SUMMARY")"
resident_gpu_draws="$(field_metric max_gpu_draws "$RESIDENT_SUMMARY")"
resident_gpu_upload_fail="$(field_metric gpu_upload_fail "$RESIDENT_SUMMARY")"
load_status="$(field_metric status "$LOAD_SCALING_SUMMARY")"
load_draws="$(field_metric max_gpu_draws "$LOAD_SCALING_SUMMARY")"
load_subchunks="$(field_metric max_gpu_subchunks "$LOAD_SCALING_SUMMARY")"
upload_status="$(field_metric status "$UPLOAD_SUMMARY")"
upload_effective_draws="$(field_metric max_gpu_effective_draws "$UPLOAD_SUMMARY")"
upload_fail="$(field_metric gpu_upload_fail "$UPLOAD_SUMMARY")"
memory_status="$(field_metric status "$MEMORY_SUMMARY")"
memory_fragmentation="$(field_metric max_gpu_fragmentation_pct "$MEMORY_SUMMARY")"
memory_upload_fail="$(field_metric gpu_upload_fail "$MEMORY_SUMMARY")"
resource_status="$(field_metric resource_lifecycle_audit_status "$RESOURCE_SUMMARY")"
resource_scene_replace="$(field_metric gpu_scene_target_replace "$RESOURCE_SUMMARY")"
resource_upload_fail="$(field_metric gpu_upload_fail "$RESOURCE_SUMMARY")"
baseline_status="$(field_metric status "$BASELINE_SUMMARY")"
baseline_warning_status="$(field_metric warning_status "$BASELINE_SUMMARY")"
security_status="$(field_metric status "$SECURITY_SUMMARY")"
security_protocol_change="$(field_metric active_protocol_change "$SECURITY_SUMMARY")"
security_storage_package_smoke="$(field_metric storage_package_smoke "$SECURITY_SUMMARY")"
security_packet_error_monitoring="$(field_metric packet_error_monitoring "$SECURITY_SUMMARY")"
security_server_session_monitoring="$(field_metric server_session_monitoring "$SECURITY_SUMMARY")"
security_storage_config="$(field_metric storage_config "$SECURITY_SUMMARY")"
security_storage_backend_policy="$(field_metric storage_backend_policy "$SECURITY_SUMMARY")"
security_block_edit_validation="$(field_metric block_edit_validation "$SECURITY_SUMMARY")"
security_block_edit_save_failure_rollback="$(field_metric block_edit_save_failure_rollback "$SECURITY_SUMMARY")"
security_unknown_packet_policy="$(field_metric unknown_packet_policy "$SECURITY_SUMMARY")"
security_nil_packet_policy="$(field_metric nil_packet_policy "$SECURITY_SUMMARY")"
security_nil_position_policy="$(field_metric nil_position_policy "$SECURITY_SUMMARY")"
security_nil_block_action_policy="$(field_metric nil_block_action_policy "$SECURITY_SUMMARY")"
security_conflict_semantics="$(field_metric conflict_semantics "$SECURITY_SUMMARY")"
security_overload_status="$(field_metric overload_status "$SECURITY_SUMMARY")"
security_local_server_exposure="$(field_metric local_server_exposure "$SECURITY_SUMMARY")"
security_smoke_bind_exposure="$(field_metric smoke_bind_exposure "$SECURITY_SUMMARY")"
observability_status="$(field_metric status "$OBSERVABILITY_SUMMARY")"
observability_error_scan="$(field_metric error_scan "$OBSERVABILITY_SUMMARY")"
arch_status="$(field_metric status "$ARCH_SUMMARY")"
arch_runtime_change="$(field_metric runtime_change "$ARCH_SUMMARY")"
handoff_status="$(field_metric status "$HANDOFF_SUMMARY")"
handoff_quality_inputs="$(field_metric quality_inputs "$HANDOFF_SUMMARY")"
handoff_gpu_report_freshness="$(field_metric observability_gpu_report_freshness "$HANDOFF_SUMMARY")"
rc_status="$(field_metric status "$RC_SUMMARY")"
rc_live_checks="$(field_metric live_checks "$RC_SUMMARY")"
rc_test_gpu_report_freshness="$(field_metric test_gpu_report_freshness "$RC_SUMMARY")"
rc_security_deterministic_property_tests="$(field_metric security_deterministic_property_tests "$RC_SUMMARY")"
rc_security_storage_package_smoke="$(field_metric security_storage_package_smoke "$RC_SUMMARY")"
rc_security_packet_error_monitoring="$(field_metric security_packet_error_monitoring "$RC_SUMMARY")"
rc_security_server_session_monitoring="$(field_metric security_server_session_monitoring "$RC_SUMMARY")"
rc_security_storage_config="$(field_metric security_storage_config "$RC_SUMMARY")"
rc_security_storage_backend_policy="$(field_metric security_storage_backend_policy "$RC_SUMMARY")"
rc_security_block_edit_validation="$(field_metric security_block_edit_validation "$RC_SUMMARY")"
rc_security_block_edit_save_failure_rollback="$(field_metric security_block_edit_save_failure_rollback "$RC_SUMMARY")"
rc_security_unknown_packet_policy="$(field_metric security_unknown_packet_policy "$RC_SUMMARY")"
rc_security_nil_packet_policy="$(field_metric security_nil_packet_policy "$RC_SUMMARY")"
rc_security_nil_position_policy="$(field_metric security_nil_position_policy "$RC_SUMMARY")"
rc_security_nil_block_action_policy="$(field_metric security_nil_block_action_policy "$RC_SUMMARY")"
rc_security_conflict_semantics="$(field_metric security_conflict_semantics "$RC_SUMMARY")"
rc_security_overload_status="$(field_metric security_overload_status "$RC_SUMMARY")"
rc_security_local_server_exposure="$(field_metric security_local_server_exposure "$RC_SUMMARY")"
rc_security_smoke_bind_exposure="$(field_metric security_smoke_bind_exposure "$RC_SUMMARY")"
external_status="$(field_metric status "$EXTERNAL_PROFILING_SUMMARY")"
external_capture_readiness="$(field_metric capture_readiness "$EXTERNAL_PROFILING_SUMMARY")"
external_profile_status="$(field_metric external_profile_status "$EXTERNAL_PROFILING_SUMMARY")"
external_rc_test_gpu_report_freshness="$(field_metric rc_test_gpu_report_freshness "$EXTERNAL_PROFILING_SUMMARY")"
external_rc_security_storage_package_smoke="$(field_metric rc_security_storage_package_smoke "$EXTERNAL_PROFILING_SUMMARY")"
external_rc_security_packet_error_monitoring="$(field_metric rc_security_packet_error_monitoring "$EXTERNAL_PROFILING_SUMMARY")"
external_rc_security_server_session_monitoring="$(field_metric rc_security_server_session_monitoring "$EXTERNAL_PROFILING_SUMMARY")"
external_rc_security_storage_config="$(field_metric rc_security_storage_config "$EXTERNAL_PROFILING_SUMMARY")"
external_rc_security_storage_backend_policy="$(field_metric rc_security_storage_backend_policy "$EXTERNAL_PROFILING_SUMMARY")"
external_rc_security_block_edit_validation="$(field_metric rc_security_block_edit_validation "$EXTERNAL_PROFILING_SUMMARY")"
external_rc_security_block_edit_save_failure_rollback="$(field_metric rc_security_block_edit_save_failure_rollback "$EXTERNAL_PROFILING_SUMMARY")"
external_rc_security_unknown_packet_policy="$(field_metric rc_security_unknown_packet_policy "$EXTERNAL_PROFILING_SUMMARY")"
external_rc_security_nil_packet_policy="$(field_metric rc_security_nil_packet_policy "$EXTERNAL_PROFILING_SUMMARY")"
external_rc_security_nil_position_policy="$(field_metric rc_security_nil_position_policy "$EXTERNAL_PROFILING_SUMMARY")"
external_rc_security_nil_block_action_policy="$(field_metric rc_security_nil_block_action_policy "$EXTERNAL_PROFILING_SUMMARY")"
external_rc_security_conflict_semantics="$(field_metric rc_security_conflict_semantics "$EXTERNAL_PROFILING_SUMMARY")"
external_rc_security_overload_status="$(field_metric rc_security_overload_status "$EXTERNAL_PROFILING_SUMMARY")"
external_rc_security_local_server_exposure="$(field_metric rc_security_local_server_exposure "$EXTERNAL_PROFILING_SUMMARY")"
external_rc_security_smoke_bind_exposure="$(field_metric rc_security_smoke_bind_exposure "$EXTERNAL_PROFILING_SUMMARY")"
native_shadow_status="$(field_metric status "$NATIVE_SHADOW_SUMMARY")"
native_shadow_allowed="$(field_metric active_prototype_allowed "$NATIVE_SHADOW_SUMMARY")"
shadow_retirement_status="$(field_metric status "$SHADOW_RETIREMENT_SUMMARY")"
shadow_retirement_allowed="$(field_metric retirement_allowed "$SHADOW_RETIREMENT_SUMMARY")"
transparent_status="$(field_metric status "$TRANSPARENT_PREFLIGHT_SUMMARY")"
transparent_allowed="$(field_metric active_path_allowed "$TRANSPARENT_PREFLIGHT_SUMMARY")"
transparent_acceptance_status="$(field_metric status "$TRANSPARENT_ACCEPTANCE_SUMMARY")"

{
  printf 'production_readiness_milestone_report status=prepared\n'
  printf 'row=stable_streaming status=%s source=%s gpu_upload_fail=%s ground_misses=%s\n' "$exploration_status" "$EXPLORATION_SUMMARY" "$exploration_gpu_upload_fail" "$exploration_ground_misses"
  printf 'row=high_resident_set status=%s resident_draws=%s resident_subchunks=%s source=%s\n' "$resident_status" "$resident_gpu_draws" "$load_subchunks" "$RESIDENT_SUMMARY"
  printf 'row=predictable_performance status=%s baseline_warning_status=%s source=%s\n' "$baseline_status" "$baseline_warning_status" "$BASELINE_SUMMARY"
  printf 'row=resource_upload_health upload_status=%s memory_status=%s resource_status=%s upload_fail=%s fragmentation_pct=%s scene_target_replace=%s\n' "$upload_status" "$memory_status" "$resource_status" "$upload_fail" "$memory_fragmentation" "$resource_scene_replace"
  printf 'row=storage_protocol_integrity status=%s active_protocol_change=%s storage_package_smoke=%s packet_error_monitoring=%s server_session_monitoring=%s storage_config=%s storage_backend_policy=%s block_edit_validation=%s block_edit_save_failure_rollback=%s unknown_packet_policy=%s nil_packet_policy=%s nil_position_policy=%s nil_block_action_policy=%s conflict_semantics=%s overload_status=%s local_server_exposure=%s smoke_bind_exposure=%s source=%s\n' "$security_status" "$security_protocol_change" "$security_storage_package_smoke" "$security_packet_error_monitoring" "$security_server_session_monitoring" "$security_storage_config" "$security_storage_backend_policy" "$security_block_edit_validation" "$security_block_edit_save_failure_rollback" "$security_unknown_packet_policy" "$security_nil_packet_policy" "$security_nil_position_policy" "$security_nil_block_action_policy" "$security_conflict_semantics" "$security_overload_status" "$security_local_server_exposure" "$security_smoke_bind_exposure" "$SECURITY_SUMMARY"
  printf 'row=docs_reproducible_gates observability_status=%s architecture_status=%s handoff_status=%s handoff_gpu_report_freshness=%s rc_status=%s rc_test_gpu_report_freshness=%s rc_security_deterministic_property_tests=%s rc_security_storage_package_smoke=%s rc_security_packet_error_monitoring=%s rc_security_server_session_monitoring=%s rc_security_storage_config=%s rc_security_storage_backend_policy=%s rc_security_block_edit_validation=%s rc_security_block_edit_save_failure_rollback=%s rc_security_unknown_packet_policy=%s rc_security_nil_packet_policy=%s rc_security_nil_position_policy=%s rc_security_nil_block_action_policy=%s rc_security_conflict_semantics=%s rc_security_overload_status=%s rc_security_local_server_exposure=%s rc_security_smoke_bind_exposure=%s\n' "$observability_status" "$arch_status" "$handoff_status" "$handoff_gpu_report_freshness" "$rc_status" "$rc_test_gpu_report_freshness" "$rc_security_deterministic_property_tests" "$rc_security_storage_package_smoke" "$rc_security_packet_error_monitoring" "$rc_security_server_session_monitoring" "$rc_security_storage_config" "$rc_security_storage_backend_policy" "$rc_security_block_edit_validation" "$rc_security_block_edit_save_failure_rollback" "$rc_security_unknown_packet_policy" "$rc_security_nil_packet_policy" "$rc_security_nil_position_policy" "$rc_security_nil_block_action_policy" "$rc_security_conflict_semantics" "$rc_security_overload_status" "$rc_security_local_server_exposure" "$rc_security_smoke_bind_exposure"
  printf 'row=external_profiler status=%s capture_readiness=%s external_profile_status=%s rc_test_gpu_report_freshness=%s rc_security_storage_package_smoke=%s rc_security_packet_error_monitoring=%s rc_security_server_session_monitoring=%s rc_security_storage_config=%s rc_security_storage_backend_policy=%s rc_security_block_edit_validation=%s rc_security_block_edit_save_failure_rollback=%s rc_security_unknown_packet_policy=%s rc_security_nil_packet_policy=%s rc_security_nil_position_policy=%s rc_security_nil_block_action_policy=%s rc_security_conflict_semantics=%s rc_security_overload_status=%s rc_security_local_server_exposure=%s rc_security_smoke_bind_exposure=%s source=%s\n' "$external_status" "$external_capture_readiness" "$external_profile_status" "$external_rc_test_gpu_report_freshness" "$external_rc_security_storage_package_smoke" "$external_rc_security_packet_error_monitoring" "$external_rc_security_server_session_monitoring" "$external_rc_security_storage_config" "$external_rc_security_storage_backend_policy" "$external_rc_security_block_edit_validation" "$external_rc_security_block_edit_save_failure_rollback" "$external_rc_security_unknown_packet_policy" "$external_rc_security_nil_packet_policy" "$external_rc_security_nil_position_policy" "$external_rc_security_nil_block_action_policy" "$external_rc_security_conflict_semantics" "$external_rc_security_overload_status" "$external_rc_security_local_server_exposure" "$external_rc_security_smoke_bind_exposure" "$EXTERNAL_PROFILING_SUMMARY"
  printf 'row=native_shadow_direction status=%s active_prototype_allowed=%s shadow_retirement_status=%s retirement_allowed=%s\n' "$native_shadow_status" "$native_shadow_allowed" "$shadow_retirement_status" "$shadow_retirement_allowed"
  printf 'row=transparent_direction preflight_status=%s active_path_allowed=%s acceptance_status=%s\n' "$transparent_status" "$transparent_allowed" "$transparent_acceptance_status"
  printf 'row=live_release_checks status=%s note=live_rc_required_for_milestone\n' "$rc_live_checks"
} > "$REPORT_PATH"

awk \
  -v exploration_status="${exploration_status:-missing}" \
  -v exploration_gpu_upload_fail="${exploration_gpu_upload_fail:-1}" \
  -v exploration_ground_misses="${exploration_ground_misses:-1}" \
  -v resident_status="${resident_status:-missing}" \
  -v resident_gpu_draws="${resident_gpu_draws:-0}" \
  -v resident_gpu_upload_fail="${resident_gpu_upload_fail:-1}" \
  -v load_status="${load_status:-missing}" \
  -v load_draws="${load_draws:-0}" \
  -v load_subchunks="${load_subchunks:-0}" \
  -v upload_status="${upload_status:-missing}" \
  -v upload_effective_draws="${upload_effective_draws:-0}" \
  -v upload_fail="${upload_fail:-1}" \
  -v memory_status="${memory_status:-missing}" \
  -v memory_fragmentation="${memory_fragmentation:-999}" \
  -v memory_upload_fail="${memory_upload_fail:-1}" \
  -v resource_status="${resource_status:-missing}" \
  -v resource_scene_replace="${resource_scene_replace:-1}" \
  -v resource_upload_fail="${resource_upload_fail:-1}" \
  -v baseline_status="${baseline_status:-missing}" \
  -v baseline_warning_status="${baseline_warning_status:-missing}" \
  -v security_status="${security_status:-missing}" \
  -v security_protocol_change="${security_protocol_change:-1}" \
  -v security_storage_package_smoke="${security_storage_package_smoke:-missing}" \
  -v security_packet_error_monitoring="${security_packet_error_monitoring:-missing}" \
  -v security_server_session_monitoring="${security_server_session_monitoring:-missing}" \
  -v security_storage_config="${security_storage_config:-missing}" \
  -v security_storage_backend_policy="${security_storage_backend_policy:-missing}" \
  -v security_block_edit_validation="${security_block_edit_validation:-missing}" \
  -v security_block_edit_save_failure_rollback="${security_block_edit_save_failure_rollback:-missing}" \
  -v security_unknown_packet_policy="${security_unknown_packet_policy:-missing}" \
  -v security_nil_packet_policy="${security_nil_packet_policy:-missing}" \
  -v security_nil_position_policy="${security_nil_position_policy:-missing}" \
  -v security_nil_block_action_policy="${security_nil_block_action_policy:-missing}" \
  -v security_conflict_semantics="${security_conflict_semantics:-missing}" \
  -v security_overload_status="${security_overload_status:-missing}" \
  -v security_local_server_exposure="${security_local_server_exposure:-missing}" \
  -v security_smoke_bind_exposure="${security_smoke_bind_exposure:-missing}" \
  -v observability_status="${observability_status:-missing}" \
  -v observability_error_scan="${observability_error_scan:-dirty}" \
  -v arch_status="${arch_status:-missing}" \
  -v arch_runtime_change="${arch_runtime_change:-changed}" \
  -v handoff_status="${handoff_status:-missing}" \
  -v handoff_quality_inputs="${handoff_quality_inputs:-missing}" \
  -v handoff_gpu_report_freshness="${handoff_gpu_report_freshness:-missing}" \
  -v rc_status="${rc_status:-missing}" \
  -v rc_live_checks="${rc_live_checks:-missing}" \
  -v rc_test_gpu_report_freshness="${rc_test_gpu_report_freshness:-missing}" \
  -v rc_security_deterministic_property_tests="${rc_security_deterministic_property_tests:-missing}" \
  -v rc_security_storage_package_smoke="${rc_security_storage_package_smoke:-missing}" \
  -v rc_security_packet_error_monitoring="${rc_security_packet_error_monitoring:-missing}" \
  -v rc_security_server_session_monitoring="${rc_security_server_session_monitoring:-missing}" \
  -v rc_security_storage_config="${rc_security_storage_config:-missing}" \
  -v rc_security_storage_backend_policy="${rc_security_storage_backend_policy:-missing}" \
  -v rc_security_block_edit_validation="${rc_security_block_edit_validation:-missing}" \
  -v rc_security_block_edit_save_failure_rollback="${rc_security_block_edit_save_failure_rollback:-missing}" \
  -v rc_security_unknown_packet_policy="${rc_security_unknown_packet_policy:-missing}" \
  -v rc_security_nil_packet_policy="${rc_security_nil_packet_policy:-missing}" \
  -v rc_security_nil_position_policy="${rc_security_nil_position_policy:-missing}" \
  -v rc_security_nil_block_action_policy="${rc_security_nil_block_action_policy:-missing}" \
  -v rc_security_conflict_semantics="${rc_security_conflict_semantics:-missing}" \
  -v rc_security_overload_status="${rc_security_overload_status:-missing}" \
  -v rc_security_local_server_exposure="${rc_security_local_server_exposure:-missing}" \
  -v rc_security_smoke_bind_exposure="${rc_security_smoke_bind_exposure:-missing}" \
  -v external_status="${external_status:-missing}" \
  -v external_capture_readiness="${external_capture_readiness:-missing}" \
  -v external_profile_status="${external_profile_status:-missing}" \
  -v external_rc_test_gpu_report_freshness="${external_rc_test_gpu_report_freshness:-missing}" \
  -v external_rc_security_storage_package_smoke="${external_rc_security_storage_package_smoke:-missing}" \
  -v external_rc_security_packet_error_monitoring="${external_rc_security_packet_error_monitoring:-missing}" \
  -v external_rc_security_server_session_monitoring="${external_rc_security_server_session_monitoring:-missing}" \
  -v external_rc_security_storage_config="${external_rc_security_storage_config:-missing}" \
  -v external_rc_security_storage_backend_policy="${external_rc_security_storage_backend_policy:-missing}" \
  -v external_rc_security_block_edit_validation="${external_rc_security_block_edit_validation:-missing}" \
  -v external_rc_security_block_edit_save_failure_rollback="${external_rc_security_block_edit_save_failure_rollback:-missing}" \
  -v external_rc_security_unknown_packet_policy="${external_rc_security_unknown_packet_policy:-missing}" \
  -v external_rc_security_nil_packet_policy="${external_rc_security_nil_packet_policy:-missing}" \
  -v external_rc_security_nil_position_policy="${external_rc_security_nil_position_policy:-missing}" \
  -v external_rc_security_nil_block_action_policy="${external_rc_security_nil_block_action_policy:-missing}" \
  -v external_rc_security_conflict_semantics="${external_rc_security_conflict_semantics:-missing}" \
  -v external_rc_security_overload_status="${external_rc_security_overload_status:-missing}" \
  -v external_rc_security_local_server_exposure="${external_rc_security_local_server_exposure:-missing}" \
  -v external_rc_security_smoke_bind_exposure="${external_rc_security_smoke_bind_exposure:-missing}" \
  -v native_shadow_status="${native_shadow_status:-missing}" \
  -v native_shadow_allowed="${native_shadow_allowed:-1}" \
  -v shadow_retirement_status="${shadow_retirement_status:-missing}" \
  -v shadow_retirement_allowed="${shadow_retirement_allowed:-1}" \
  -v transparent_status="${transparent_status:-missing}" \
  -v transparent_allowed="${transparent_allowed:-1}" \
  -v transparent_acceptance_status="${transparent_acceptance_status:-missing}" \
  -v report_path="$REPORT_PATH" \
  -v rc_summary="$RC_SUMMARY" \
  -v external_summary="$EXTERNAL_PROFILING_SUMMARY" '
  BEGIN {
    status = "pass"
    reason = "milestone_reached"
    production_readiness = "rc_evidence_ready"
    stable_streaming = "pass"
    high_resident_set = "pass"
    predictable_performance = "pass"
    resource_upload_health = "pass"
    storage_protocol_integrity = "pass"
    docs_reproducible_gates = "pass"
    external_profiler = external_profile_status
    native_shadow_direction = "deferred_implementation_gate"
    transparent_direction = "deferred_implementation_gate"

    if (!(exploration_status == "pass" && exploration_gpu_upload_fail + 0 == 0 && exploration_ground_misses + 0 == 0)) {
      status = "fail"
      reason = "stable_streaming_not_clean"
      stable_streaming = "fail"
    } else if (!(resident_status == "pass" && resident_gpu_draws + 0 >= 2000 && resident_gpu_upload_fail + 0 == 0 && load_status == "pass" && load_draws + 0 >= 2000 && load_subchunks + 0 >= 2000)) {
      status = "fail"
      reason = "high_resident_set_not_clean"
      high_resident_set = "fail"
    } else if (!(baseline_status == "pass" && baseline_warning_status == "ok")) {
      status = "fail"
      reason = "performance_baseline_not_clean"
      predictable_performance = "fail"
    } else if (!(upload_status == "pass" && upload_effective_draws + 0 >= 20000 && upload_fail + 0 == 0 && memory_status == "pass" && memory_upload_fail + 0 == 0 && memory_fragmentation + 0 <= 1.0 && resource_status == "pass" && resource_scene_replace + 0 == 0 && resource_upload_fail + 0 == 0)) {
      status = "fail"
      reason = "resource_upload_health_not_clean"
      resource_upload_health = "fail"
    } else if (!(security_status == "pass" && security_protocol_change + 0 == 0 && security_storage_package_smoke == "guarded" && security_packet_error_monitoring == "export_ready" && security_server_session_monitoring == "export_ready" && security_storage_config == "path_guarded" && security_storage_backend_policy == "approved_only_guarded" && security_block_edit_validation == "y_bounds_guarded" && security_block_edit_save_failure_rollback == "guarded" && security_unknown_packet_policy == "ignored_guarded" && security_nil_packet_policy == "ignored_guarded" && security_nil_position_policy == "ignored_guarded" && security_nil_block_action_policy == "ignored_guarded" && security_conflict_semantics == "last_write_wins_guarded" && security_overload_status == "admission_matrix_guarded" && security_local_server_exposure == "loopback_enforced" && security_smoke_bind_exposure == "loopback_guarded")) {
      status = "fail"
      reason = "storage_protocol_integrity_not_clean"
      storage_protocol_integrity = "fail"
    } else if (!(observability_status == "pass" && observability_error_scan == "clean" && arch_status == "pass" && arch_runtime_change == "none" && handoff_status == "pass" && handoff_quality_inputs == "present" && handoff_gpu_report_freshness == "guarded" && rc_status == "pass" && rc_live_checks == "full" && rc_test_gpu_report_freshness == "guarded" && rc_security_deterministic_property_tests == "guarded" && rc_security_storage_package_smoke == "guarded" && rc_security_packet_error_monitoring == "export_ready" && rc_security_server_session_monitoring == "export_ready" && rc_security_storage_config == "path_guarded" && rc_security_storage_backend_policy == "approved_only_guarded" && rc_security_block_edit_validation == "y_bounds_guarded" && rc_security_block_edit_save_failure_rollback == "guarded" && rc_security_unknown_packet_policy == "ignored_guarded" && rc_security_nil_packet_policy == "ignored_guarded" && rc_security_nil_position_policy == "ignored_guarded" && rc_security_nil_block_action_policy == "ignored_guarded" && rc_security_conflict_semantics == "last_write_wins_guarded" && rc_security_overload_status == "admission_matrix_guarded" && rc_security_local_server_exposure == "loopback_enforced" && rc_security_smoke_bind_exposure == "loopback_guarded")) {
      status = "fail"
      reason = "docs_or_gates_not_clean"
      docs_reproducible_gates = "fail"
    } else if (!(external_status == "pass" && external_profile_status == "pending_external_profiler" && external_capture_readiness == "live_rc_ready_for_external_capture" && external_rc_test_gpu_report_freshness == "guarded" && external_rc_security_storage_package_smoke == "guarded" && external_rc_security_packet_error_monitoring == "export_ready" && external_rc_security_server_session_monitoring == "export_ready" && external_rc_security_storage_config == "path_guarded" && external_rc_security_storage_backend_policy == "approved_only_guarded" && external_rc_security_block_edit_validation == "y_bounds_guarded" && external_rc_security_block_edit_save_failure_rollback == "guarded" && external_rc_security_unknown_packet_policy == "ignored_guarded" && external_rc_security_nil_packet_policy == "ignored_guarded" && external_rc_security_nil_position_policy == "ignored_guarded" && external_rc_security_nil_block_action_policy == "ignored_guarded" && external_rc_security_conflict_semantics == "last_write_wins_guarded" && external_rc_security_overload_status == "admission_matrix_guarded" && external_rc_security_local_server_exposure == "loopback_enforced" && external_rc_security_smoke_bind_exposure == "loopback_guarded")) {
      status = "fail"
      reason = "external_profiler_state_unexpected"
    } else if (!(native_shadow_status == "deferred" && native_shadow_allowed + 0 == 0 && shadow_retirement_status == "deferred" && shadow_retirement_allowed + 0 == 0)) {
      status = "fail"
      reason = "native_shadow_deferred_state_unexpected"
    } else if (!(transparent_status == "deferred" && transparent_allowed + 0 == 0 && transparent_acceptance_status == "pass")) {
      status = "fail"
      reason = "transparent_deferred_state_unexpected"
    }

    printf("production_readiness_milestone status=%s reason=%s production_readiness=%s stable_streaming=%s high_resident_set=%s predictable_performance=%s resource_upload_health=%s storage_protocol_integrity=%s docs_reproducible_gates=%s handoff_gpu_report_freshness=%s external_profiler=%s external_capture_readiness=%s external_rc_test_gpu_report_freshness=%s external_rc_security_storage_package_smoke=%s external_rc_security_packet_error_monitoring=%s external_rc_security_server_session_monitoring=%s external_rc_security_storage_config=%s external_rc_security_storage_backend_policy=%s external_rc_security_block_edit_validation=%s external_rc_security_block_edit_save_failure_rollback=%s external_rc_security_unknown_packet_policy=%s external_rc_security_nil_packet_policy=%s external_rc_security_nil_position_policy=%s external_rc_security_nil_block_action_policy=%s external_rc_security_conflict_semantics=%s external_rc_security_overload_status=%s external_rc_security_local_server_exposure=%s external_rc_security_smoke_bind_exposure=%s native_shadow_direction=%s transparent_direction=%s live_release_checks=%s rc_test_gpu_report_freshness=%s rc_security_deterministic_property_tests=%s security_storage_package_smoke=%s security_packet_error_monitoring=%s security_server_session_monitoring=%s security_storage_config=%s security_storage_backend_policy=%s security_block_edit_validation=%s security_block_edit_save_failure_rollback=%s security_unknown_packet_policy=%s security_nil_packet_policy=%s security_nil_position_policy=%s security_nil_block_action_policy=%s security_conflict_semantics=%s security_overload_status=%s security_local_server_exposure=%s security_smoke_bind_exposure=%s rc_security_storage_package_smoke=%s rc_security_packet_error_monitoring=%s rc_security_server_session_monitoring=%s rc_security_storage_config=%s rc_security_storage_backend_policy=%s rc_security_block_edit_validation=%s rc_security_block_edit_save_failure_rollback=%s rc_security_unknown_packet_policy=%s rc_security_nil_packet_policy=%s rc_security_nil_position_policy=%s rc_security_nil_block_action_policy=%s rc_security_conflict_semantics=%s rc_security_overload_status=%s rc_security_local_server_exposure=%s rc_security_smoke_bind_exposure=%s resident_gpu_draws=%d resident_gpu_subchunks=%d upload_effective_draws=%d memory_fragmentation_pct=%.3f report=%s rc_summary=%s external_summary=%s\n", status, reason, production_readiness, stable_streaming, high_resident_set, predictable_performance, resource_upload_health, storage_protocol_integrity, docs_reproducible_gates, handoff_gpu_report_freshness, external_profiler, external_capture_readiness, external_rc_test_gpu_report_freshness, external_rc_security_storage_package_smoke, external_rc_security_packet_error_monitoring, external_rc_security_server_session_monitoring, external_rc_security_storage_config, external_rc_security_storage_backend_policy, external_rc_security_block_edit_validation, external_rc_security_block_edit_save_failure_rollback, external_rc_security_unknown_packet_policy, external_rc_security_nil_packet_policy, external_rc_security_nil_position_policy, external_rc_security_nil_block_action_policy, external_rc_security_conflict_semantics, external_rc_security_overload_status, external_rc_security_local_server_exposure, external_rc_security_smoke_bind_exposure, native_shadow_direction, transparent_direction, rc_live_checks, rc_test_gpu_report_freshness, rc_security_deterministic_property_tests, security_storage_package_smoke, security_packet_error_monitoring, security_server_session_monitoring, security_storage_config, security_storage_backend_policy, security_block_edit_validation, security_block_edit_save_failure_rollback, security_unknown_packet_policy, security_nil_packet_policy, security_nil_position_policy, security_nil_block_action_policy, security_conflict_semantics, security_overload_status, security_local_server_exposure, security_smoke_bind_exposure, rc_security_storage_package_smoke, rc_security_packet_error_monitoring, rc_security_server_session_monitoring, rc_security_storage_config, rc_security_storage_backend_policy, rc_security_block_edit_validation, rc_security_block_edit_save_failure_rollback, rc_security_unknown_packet_policy, rc_security_nil_packet_policy, rc_security_nil_position_policy, rc_security_nil_block_action_policy, rc_security_conflict_semantics, rc_security_overload_status, rc_security_local_server_exposure, rc_security_smoke_bind_exposure, resident_gpu_draws, load_subchunks, upload_effective_draws, memory_fragmentation, report_path, rc_summary, external_summary)
    if (status != "pass") {
      exit 1
    }
  }
' > "$SUMMARY_PATH" || {
  cat "$SUMMARY_PATH" >&2 || true
  fail "production readiness milestone gate failed"
}

cat "$SUMMARY_PATH"
echo "Production readiness milestone artifacts: $OUT_DIR"
