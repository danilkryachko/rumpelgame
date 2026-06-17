#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/gpu_stress_artifact_index_current"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

SUMMARY_PATH="$OUT_DIR/gpu-stress-artifact-index-summary.txt"
INDEX_PATH="$OUT_DIR/gpu-stress-artifact-index.txt"

RAPID_CAMERA_TURN_SUMMARY="${RUMPELMC_GPU_STRESS_INDEX_RAPID_CAMERA_TURN_SUMMARY:-"$ROOT_DIR/logs/gpu_terrain_rapid_camera_turn_stress_current/rapid-camera-turn-stress-summary.txt"}"
RAPID_CAMERA_TURN_MOVEMENT_SUMMARY="${RUMPELMC_GPU_STRESS_INDEX_RAPID_CAMERA_TURN_MOVEMENT_SUMMARY:-"$ROOT_DIR/logs/gpu_terrain_rapid_camera_turn_stress_current/movement/movement-stress-summary.txt"}"
CHUNK_BOUNDARY_SUMMARY="${RUMPELMC_GPU_STRESS_INDEX_CHUNK_BOUNDARY_SUMMARY:-"$ROOT_DIR/logs/gpu_terrain_chunk_boundary_stress_current/chunk-boundary-stress-summary.txt"}"
CHUNK_BOUNDARY_SUITE_SUMMARY="${RUMPELMC_GPU_STRESS_INDEX_CHUNK_BOUNDARY_SUITE_SUMMARY:-"$ROOT_DIR/logs/gpu_terrain_chunk_boundary_stress_current/high-pressure-suite/world-load-suite-summary.txt"}"
CHUNK_UNLOAD_CHURN_SUMMARY="${RUMPELMC_GPU_STRESS_INDEX_CHUNK_UNLOAD_CHURN_SUMMARY:-"$ROOT_DIR/logs/gpu_chunk_unload_churn_diagnosis_current/gpu-chunk-unload-churn-diagnosis-summary.txt"}"
REPEATED_EDIT_BENCHMARK_SUMMARY="${RUMPELMC_GPU_STRESS_INDEX_REPEATED_EDIT_BENCHMARK_SUMMARY:-"$ROOT_DIR/logs/gpu_terrain_repeated_edit_benchmark_current/gpu-terrain-repeated-edit-benchmark-summary.txt"}"
BORDER_EDIT_BENCHMARK_SUMMARY="${RUMPELMC_GPU_STRESS_INDEX_BORDER_EDIT_BENCHMARK_SUMMARY:-"$ROOT_DIR/logs/gpu_terrain_border_edit_benchmark_current/gpu-terrain-border-edit-benchmark-summary.txt"}"
PARTIAL_DIRTY_EDGE_MATRIX_SUMMARY="${RUMPELMC_GPU_STRESS_INDEX_PARTIAL_DIRTY_EDGE_MATRIX_SUMMARY:-"$ROOT_DIR/logs/gpu_terrain_partial_dirty_edge_matrix_current/gpu-terrain-partial-dirty-edge-matrix-summary.txt"}"
COLLISION_REFRESH_COST_AUDIT_SUMMARY="${RUMPELMC_GPU_STRESS_INDEX_COLLISION_REFRESH_COST_AUDIT_SUMMARY:-"$ROOT_DIR/logs/gpu_collision_refresh_cost_audit_current/gpu-collision-refresh-cost-audit-summary.txt"}"
SHADOW_PROXY_REFRESH_COST_AUDIT_SUMMARY="${RUMPELMC_GPU_STRESS_INDEX_SHADOW_PROXY_REFRESH_COST_AUDIT_SUMMARY:-"$ROOT_DIR/logs/gpu_shadow_proxy_refresh_cost_audit_current/gpu-shadow-proxy-refresh-cost-audit-summary.txt"}"
EDIT_BURST_BUDGET_SUMMARY="${RUMPELMC_GPU_STRESS_INDEX_EDIT_BURST_BUDGET_SUMMARY:-"$ROOT_DIR/logs/gpu_edit_burst_budget_gate_current/gpu-edit-burst-budget-summary.txt"}"
EDIT_VISUAL_PARITY_SUMMARY="${RUMPELMC_GPU_STRESS_INDEX_EDIT_VISUAL_PARITY_SUMMARY:-"$ROOT_DIR/logs/gpu_edit_visual_parity_gate_current/gpu-edit-visual-parity-summary.txt"}"
WORLD_INTERACTION_CHECKPOINT_SUMMARY="${RUMPELMC_GPU_STRESS_INDEX_WORLD_INTERACTION_CHECKPOINT_SUMMARY:-"$ROOT_DIR/logs/gpu_world_interaction_checkpoint_current/gpu-world-interaction-checkpoint-summary.txt"}"
MACOS_METAL_CAPTURE_PACK_SUMMARY="${RUMPELMC_GPU_STRESS_INDEX_MACOS_METAL_CAPTURE_PACK_SUMMARY:-"$ROOT_DIR/logs/gpu_macos_metal_capture_pack_current/gpu-macos-metal-capture-pack-summary.txt"}"
STREAMING_PRIORITY_AUDIT_SUMMARY="${RUMPELMC_GPU_STRESS_INDEX_STREAMING_PRIORITY_AUDIT_SUMMARY:-"$ROOT_DIR/logs/gpu_streaming_priority_audit_current/gpu-streaming-priority-audit-summary.txt"}"
STREAMING_SCHEDULER_PROTOTYPE_SUMMARY="${RUMPELMC_GPU_STRESS_INDEX_STREAMING_SCHEDULER_PROTOTYPE_SUMMARY:-"$ROOT_DIR/logs/gpu_streaming_scheduler_prototype_current/gpu-streaming-scheduler-prototype-summary.txt"}"
STREAMING_SCHEDULER_WORKLOAD_MATRIX_SUMMARY="${RUMPELMC_GPU_STRESS_INDEX_STREAMING_SCHEDULER_WORKLOAD_MATRIX_SUMMARY:-"$ROOT_DIR/logs/gpu_streaming_scheduler_workload_matrix_current/gpu-streaming-scheduler-workload-matrix-summary.txt"}"
STREAMING_SCHEDULER_TIE_PROBE_SUMMARY="${RUMPELMC_GPU_STRESS_INDEX_STREAMING_SCHEDULER_TIE_PROBE_SUMMARY:-"$ROOT_DIR/logs/gpu_streaming_scheduler_tie_probe_current/gpu-streaming-scheduler-tie-probe-summary.txt"}"
STREAMING_SCHEDULER_DECISION_CHECKPOINT_SUMMARY="${RUMPELMC_GPU_STRESS_INDEX_STREAMING_SCHEDULER_DECISION_CHECKPOINT_SUMMARY:-"$ROOT_DIR/logs/gpu_streaming_scheduler_decision_checkpoint_current/gpu-streaming-scheduler-decision-checkpoint-summary.txt"}"
STREAMING_SCHEDULER_BOUNDARY_MATRIX_SUMMARY="${RUMPELMC_GPU_STRESS_INDEX_STREAMING_SCHEDULER_BOUNDARY_MATRIX_SUMMARY:-"$ROOT_DIR/logs/gpu_streaming_scheduler_boundary_matrix_current/gpu-streaming-scheduler-boundary-matrix-summary.txt"}"
UPLOAD_FAILURE_FALLBACK_SUMMARY="${RUMPELMC_GPU_STRESS_INDEX_UPLOAD_FAILURE_FALLBACK_SUMMARY:-"$ROOT_DIR/logs/gpu_upload_failure_fallback_current/gpu-upload-failure-fallback-summary.txt"}"
LOAD_SCALING_SUMMARY="${RUMPELMC_GPU_STRESS_INDEX_LOAD_SCALING_SUMMARY:-"$ROOT_DIR/logs/gpu_terrain_load_scaling_radius16_summary_check/gpu-terrain-load-scaling-summary.txt"}"
RESIDENT_SET_GROWTH_SUMMARY="${RUMPELMC_GPU_STRESS_INDEX_RESIDENT_SET_GROWTH_SUMMARY:-"$ROOT_DIR/logs/gpu_terrain_load_scaling_radius16_summary_check/resident-set-growth/resident-set-growth-summary.txt"}"
MASS_CHUNK_LOAD_SUMMARY="${RUMPELMC_GPU_STRESS_INDEX_MASS_CHUNK_LOAD_SUMMARY:-"$ROOT_DIR/logs/gpu_terrain_mass_chunk_load_current/gpu-terrain-mass-chunk-load-summary.txt"}"
BUFFER_RESIDENCY_BUDGET_SUMMARY="${RUMPELMC_GPU_STRESS_INDEX_BUFFER_RESIDENCY_BUDGET_SUMMARY:-"$ROOT_DIR/logs/gpu_buffer_residency_budget_current/gpu-buffer-residency-budget-summary.txt"}"
UPLOAD_BUDGET_SUMMARY="${RUMPELMC_GPU_STRESS_INDEX_UPLOAD_BUDGET_SUMMARY:-"$ROOT_DIR/logs/gpu_terrain_upload_budget_current/gpu-terrain-upload-budget-summary.txt"}"
UPLOAD_STAGE_POOL_LOAD_SCALING_SUMMARY="${RUMPELMC_GPU_STRESS_INDEX_UPLOAD_STAGE_POOL_LOAD_SCALING_SUMMARY:-"$ROOT_DIR/logs/gpu_terrain_upload_stage_pool_load_scaling_current/gpu-terrain-upload-stage-pool-load-scaling-summary.txt"}"
GROUPED_DRAWS_SUMMARY="${RUMPELMC_GPU_STRESS_INDEX_GROUPED_DRAWS_SUMMARY:-"$ROOT_DIR/logs/gpu_terrain_grouped_draws_current/gpu-terrain-grouped-draws-summary.txt"}"
CUTOUT_PRESSURE_SUMMARY="${RUMPELMC_GPU_STRESS_INDEX_CUTOUT_PRESSURE_SUMMARY:-"$ROOT_DIR/logs/gpu_terrain_cutout_pressure_load_scaling_current/gpu-terrain-cutout-pressure-load-scaling-summary.txt"}"
CUTOUT_FIXTURE_ACCEPTANCE_SUMMARY="${RUMPELMC_GPU_STRESS_INDEX_CUTOUT_FIXTURE_ACCEPTANCE_SUMMARY:-"$ROOT_DIR/logs/gpu_transparent_cutout_fixture_scene_smoke_current/transparent-cutout-fixture-acceptance-summary.txt"}"
TRANSPARENT_SORT_BUILD_COST_SUMMARY="${RUMPELMC_GPU_STRESS_INDEX_TRANSPARENT_SORT_BUILD_COST_SUMMARY:-"$ROOT_DIR/logs/transparent_cutout_sort_build_cost_current/transparent-cutout-sort-build-cost-summary.txt"}"
SHADER_PROFILER_CAPTURE_PACK="${RUMPELMC_GPU_STRESS_INDEX_SHADER_PROFILER_CAPTURE_PACK:-"$ROOT_DIR/logs/gpu_shader_profiler_capture_pack_current/shader-profiler-capture-pack.txt"}"
EXPLORATION_SOAK_SUMMARY="${RUMPELMC_GPU_STRESS_INDEX_EXPLORATION_SOAK_SUMMARY:-"$ROOT_DIR/logs/world_streaming_exploration_soak_smoke/world-streaming-exploration-soak-summary.txt"}"
UPLOAD_PRESSURE_SUMMARY="${RUMPELMC_GPU_STRESS_INDEX_UPLOAD_PRESSURE_SUMMARY:-"$ROOT_DIR/logs/gpu_terrain_upload_pressure_smoke/gpu-upload-pressure-summary.txt"}"
RESOURCE_LIFECYCLE_SUMMARY="${RUMPELMC_GPU_STRESS_INDEX_RESOURCE_LIFECYCLE_SUMMARY:-"$ROOT_DIR/logs/gpu_terrain_upload_pressure_smoke/gpu-resource-lifecycle-audit-summary.txt"}"
MEMORY_BUDGET_SUMMARY="${RUMPELMC_GPU_STRESS_INDEX_MEMORY_BUDGET_SUMMARY:-"$ROOT_DIR/logs/gpu_terrain_memory_budget_current/gpu-terrain-memory-budget-summary.txt"}"
REPORT_V2_SUMMARY="${RUMPELMC_GPU_STRESS_INDEX_REPORT_V2_SUMMARY:-"$ROOT_DIR/logs/gpu_terrain_report_v2_current/gpu-terrain-report-v2-summary.txt"}"
BASELINE_GOVERNANCE_SUMMARY="${RUMPELMC_GPU_STRESS_INDEX_BASELINE_GOVERNANCE_SUMMARY:-"$ROOT_DIR/logs/performance_baseline_governance_current/performance-baseline-governance-summary.txt"}"
TEST_STRATEGY_SUMMARY="${RUMPELMC_GPU_STRESS_INDEX_TEST_STRATEGY_SUMMARY:-"$ROOT_DIR/logs/test_strategy_gate_current/test-strategy-gate-summary.txt"}"
EXTERNAL_PROFILING_CAMPAIGN_SUMMARY="${RUMPELMC_GPU_STRESS_INDEX_EXTERNAL_PROFILING_CAMPAIGN_SUMMARY:-"$ROOT_DIR/logs/external_profiling_campaign_current/external-profiling-campaign-summary.txt"}"

mkdir -p "$OUT_DIR"

fail() {
  echo "gpu_stress_artifact_index: $*" >&2
  exit 1
}

relative_path() {
  path="$1"
  case "$path" in
    "$ROOT_DIR"/*) printf '%s\n' "${path#$ROOT_DIR/}" ;;
    *) printf '%s\n' "$path" ;;
  esac
}

normalize_path() {
  path="$1"
  case "$path" in
    /*) printf '%s\n' "$path" ;;
    *) printf '%s\n' "$ROOT_DIR/$path" ;;
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

field_first() {
  path="$1"
  shift
  for key in "$@"; do
    value="$(field_metric "$key" "$path")"
    if [ -n "$value" ]; then
      printf '%s\n' "$value"
      return
    fi
  done
  printf 'n/a\n'
}

field_max() {
  path="$1"
  shift
  awk -v keys="$*" '
    BEGIN {
      split(keys, key_list, " ")
      for (i in key_list) {
        wanted[key_list[i]] = 1
      }
      seen = 0
      max_value = 0
    }
    {
      for (i = 1; i <= NF; i++) {
        pos = index($i, "=")
        if (pos > 0) {
          key = substr($i, 1, pos - 1)
          value = substr($i, pos + 1)
          gsub(/^"/, "", value)
          gsub(/"$/, "", value)
          if (wanted[key] && value ~ /^-?[0-9]+([.][0-9]+)?$/) {
            if (!seen || value + 0 > max_value) {
              max_value = value + 0
              seen = 1
            }
          }
        }
      }
    }
    END {
      if (seen) {
        printf("%.3f\n", max_value)
      } else {
        print "n/a"
      }
    }
  ' "$path"
}

file_mtime() {
  path="$1"
  stat -f '%m' "$path" 2>/dev/null || stat -c '%Y' "$path" 2>/dev/null || printf '0'
}

record_artifact() {
  id="$1"
  category="$2"
  required="$3"
  status_key="$4"
  expected_status="$5"
  source_path="$(normalize_path "$6")"
  rel_path="$(relative_path "$source_path")"

  if [ ! -s "$source_path" ]; then
    printf 'gpu_artifact id=%s category=%s required=%s status=missing expected_status=%s path=%s bytes=0 mtime=0 root=missing gpu_subchunks=n/a gpu_draws=n/a gpu_faces=n/a draw_cmd_occupancy_pct=n/a configured_buffer_bytes=n/a configured_buffer_budget_pct=n/a active_face_bytes=n/a active_face_budget_pct=n/a logical_draw_records=n/a submitted_draw_records=n/a draw_cmd_headroom_bytes=n/a residency_pressure_class=n/a residency_proof_status=n/a allocator_evidence_status=n/a priority_proof_status=n/a source_priority_contract_status=n/a runtime_priority_status=n/a scheduler_change_allowed=n/a candidate_scheduler_status=n/a terrain_queue_max_ms=n/a process_wall_p95_ms=n/a gpu_compositor_submit_max_ms=n/a gpu_upload_fail=n/a expected_gpu_upload_fail=n/a expected_gpu_upload_fail_injected=n/a upload_fallback_shadow_path=n/a ground_misses=n/a packet_queue_lag_ms=n/a chunk_unload_total=n/a current_chunk_collision=n/a collision_refresh_rebuilt=n/a collision_q_max=n/a collision_phase_total_ms=n/a collision_phase_component_ms=n/a shadow_proxy_refresh_reuse=n/a proxy_shadow=n/a proxy_shadow_only=n/a compact_shadow_proxy=n/a compact_shadow_normals_saved=n/a transparent_active=n/a transparent_fallback=n/a transparent_sort_active=n/a transparent_sort_ms=n/a transparent_cutout_uploads=n/a transparent_build_envelope_ms=n/a stage_pool_reuses=n/a grouped_saved_records=n/a default_runtime_change_allowed=n/a requires_external_profiler_before_default=n/a requires_mac_windows_validation=n/a external_profile_status=n/a caveat=missing_required_or_optional\n' \
      "$id" "$category" "$required" "$expected_status" "$rel_path" >> "$INDEX_PATH"
    return
  fi

  root_token="$(awk '{ print $1; exit }' "$source_path")"
  status_value="$(field_metric "$status_key" "$source_path")"
  if [ -z "$status_value" ]; then
    status_value="missing"
  fi
  bytes="$(wc -c < "$source_path" | tr -d ' ')"
  mtime="$(file_mtime "$source_path")"
  gpu_subchunks="$(field_first "$source_path" max_gpu_subchunks gpu_subchunks baseline_max_gpu_subchunks pooled_max_gpu_subchunks baseline_subchunks grouped_subchunks transparent_subchunks)"
  gpu_draws="$(field_first "$source_path" max_gpu_draws max_logical_draw_records max_submitted_draw_records gpu_draws gpu_effective_draws max_gpu_effective_draws baseline_max_gpu_draws baseline_draws grouped_logical_records grouped_draws transparent_draws)"
  gpu_faces="$(field_first "$source_path" max_gpu_faces gpu_faces baseline_max_gpu_faces pooled_max_gpu_faces baseline_faces grouped_faces transparent_faces pressure_build_faces)"
  draw_cmd_occupancy_pct="$(field_first "$source_path" max_draw_cmd_occupancy_pct gpu_draw_cmd_occupancy_pct baseline_draw_cmd_occupancy_pct pooled_draw_cmd_occupancy_pct)"
  configured_buffer_bytes="$(field_first "$source_path" configured_buffer_bytes configured_terrain_buffer_bytes)"
  configured_buffer_budget_pct="$(field_first "$source_path" configured_buffer_budget_pct)"
  active_face_bytes="$(field_first "$source_path" active_face_bytes active_terrain_bytes)"
  active_face_budget_pct="$(field_first "$source_path" active_face_budget_pct)"
  logical_draw_records="$(field_first "$source_path" max_logical_draw_records grouped_logical_records)"
  submitted_draw_records="$(field_first "$source_path" max_submitted_draw_records grouped_draws)"
  draw_cmd_headroom_bytes="$(field_first "$source_path" min_draw_cmd_headroom_bytes gpu_draw_cmd_headroom_bytes)"
  residency_pressure_class="$(field_first "$source_path" residency_pressure_class)"
  residency_proof_status="$(field_first "$source_path" residency_proof_status)"
  allocator_evidence_status="$(field_first "$source_path" allocator_evidence_status)"
  priority_proof_status="$(field_first "$source_path" priority_proof_status)"
  source_priority_contract_status="$(field_first "$source_path" source_priority_contract_status)"
  runtime_priority_status="$(field_first "$source_path" runtime_priority_status)"
  scheduler_change_allowed="$(field_first "$source_path" scheduler_change_allowed)"
  candidate_scheduler_status="$(field_first "$source_path" candidate_scheduler_status)"
  terrain_queue_max_ms="$(field_first "$source_path" max_terrain_queue_ms terrain_queue_max_ms baseline_terrain_queue_max_ms grouped_terrain_queue_max_ms pooled_terrain_queue_max_ms)"
  process_wall_p95_ms="$(field_first "$source_path" max_process_wall_p95_ms process_wall_p95_ms baseline_process_wall_p95_ms grouped_process_wall_p95_ms pooled_process_wall_p95_ms)"
  gpu_compositor_submit_max_ms="$(field_first "$source_path" max_gpu_compositor_submit_ms gpu_compositor_submit_max_ms baseline_gpu_compositor_submit_max_ms grouped_gpu_compositor_submit_max_ms pooled_gpu_compositor_submit_max_ms)"
  gpu_upload_fail="$(field_first "$source_path" gpu_upload_fail upload_fail_total max_upload_fail load_gpu_upload_fail movement_upload_fail baseline_upload_fail grouped_upload_fail pooled_upload_fail)"
  expected_gpu_upload_fail="n/a"
  expected_gpu_upload_fail_injected="n/a"
  upload_fallback_shadow_path="n/a"
  ground_misses="$(field_first "$source_path" ground_misses readiness_ground_misses baseline_ground_misses grouped_ground_misses)"
  packet_queue_lag_ms="$(field_first "$source_path" packet_queue_lag_max_ms max_packet_queue_lag_ms)"
  chunk_unload_total="$(field_first "$source_path" chunk_unload_total max_chunk_unload_total)"
  current_chunk_collision="$(field_first "$source_path" current_chunk_collision baseline_current_chunk_collision grouped_current_chunk_collision)"
  collision_refresh_rebuilt="$(field_first "$source_path" max_collision_refresh_rebuilt collision_refresh_rebuilt)"
  collision_q_max="$(field_first "$source_path" max_collision_q_max collision_q_max)"
  collision_phase_total_ms="$(field_first "$source_path" max_collision_phase_total_ms collision_phase_total_ms)"
  collision_phase_component_ms="$(field_first "$source_path" max_collision_phase_component_ms collision_phase_component_ms)"
  shadow_proxy_refresh_reuse="$(field_first "$source_path" max_proxy_refresh_reuse proxy_refresh_reuse)"
  proxy_shadow="$(field_first "$source_path" max_proxy_shadow proxy_shadow)"
  proxy_shadow_only="$(field_first "$source_path" max_proxy_shadow_only proxy_shadow_only)"
  compact_shadow_proxy="$(field_first "$source_path" max_compact_shadow_proxy compact_shadow_proxy)"
  compact_shadow_normals_saved="$(field_first "$source_path" max_compact_shadow_normals_saved compact_shadow_normals_saved)"
  transparent_active="$(field_first "$source_path" transparent_active)"
  transparent_fallback="$(field_first "$source_path" transparent_fallback)"
  transparent_sort_active="$(field_first "$source_path" transparent_sort_active max_transparent_sort_active)"
  transparent_sort_ms="$(field_first "$source_path" transparent_sort_ms max_transparent_sort_ms)"
  transparent_cutout_uploads="$(field_first "$source_path" transparent_cutout_uploads max_transparent_cutout_uploads pressure_build_uploads fixture_build_uploads)"
  transparent_build_envelope_ms="$(field_first "$source_path" transparent_build_envelope_ms max_transparent_build_envelope_ms pressure_build_envelope_ms fixture_build_envelope_ms)"
  stage_pool_reuses="$(field_first "$source_path" pooled_stage_pba_reuses gpu_upload_stage_pba_reuses)"
  grouped_saved_records="$(field_first "$source_path" grouped_saved_records gpu_draw_grouped_saved_records)"
  default_runtime_change_allowed="$(field_first "$source_path" default_runtime_change_allowed)"
  requires_external_profiler_before_default="$(field_first "$source_path" requires_external_profiler_before_default)"
  requires_mac_windows_validation="$(field_first "$source_path" requires_mac_windows_validation)"
  external_profile_status="$(field_first "$source_path" external_profile_status)"

  case "$id" in
    mass_chunk_load)
      terrain_queue_max_ms="$(field_first "$source_path" terrain_queue_max_ms max_terrain_queue_ms)"
      process_wall_p95_ms="$(field_first "$source_path" process_wall_p95_ms max_process_wall_p95_ms)"
      gpu_compositor_submit_max_ms="$(field_first "$source_path" gpu_compositor_submit_max_ms max_gpu_compositor_submit_ms)"
      ;;
    upload_stage_pool_load_scaling)
      terrain_queue_max_ms="$(field_max "$source_path" baseline_terrain_queue_max_ms pooled_terrain_queue_max_ms)"
      process_wall_p95_ms="$(field_max "$source_path" baseline_process_wall_p95_ms pooled_process_wall_p95_ms)"
      gpu_compositor_submit_max_ms="$(field_max "$source_path" baseline_gpu_compositor_submit_max_ms pooled_gpu_compositor_submit_max_ms)"
      ;;
    grouped_draws)
      terrain_queue_max_ms="$(field_max "$source_path" baseline_terrain_queue_max_ms grouped_terrain_queue_max_ms)"
      process_wall_p95_ms="$(field_max "$source_path" baseline_process_wall_p95_ms grouped_process_wall_p95_ms)"
      gpu_compositor_submit_max_ms="$(field_max "$source_path" baseline_gpu_compositor_submit_max_ms grouped_gpu_compositor_submit_max_ms)"
      ;;
    upload_failure_fallback)
      expected_gpu_upload_fail="$(field_first "$source_path" gpu_upload_fail)"
      expected_gpu_upload_fail_injected="$(field_first "$source_path" gpu_upload_fail_injected)"
      upload_fallback_shadow_path="$(field_first "$source_path" shadow_path)"
      gpu_upload_fail="0"
      ;;
  esac

  caveat="local_summary"
  if [ "$external_profile_status" = "pending_external_profiler" ]; then
    caveat="pending_external_profiler"
  elif [ "$requires_mac_windows_validation" = "1" ]; then
    caveat="needs_mac_windows_validation"
  fi

  printf 'gpu_artifact id=%s category=%s required=%s status=%s expected_status=%s path=%s bytes=%s mtime=%s root=%s gpu_subchunks=%s gpu_draws=%s gpu_faces=%s draw_cmd_occupancy_pct=%s configured_buffer_bytes=%s configured_buffer_budget_pct=%s active_face_bytes=%s active_face_budget_pct=%s logical_draw_records=%s submitted_draw_records=%s draw_cmd_headroom_bytes=%s residency_pressure_class=%s residency_proof_status=%s allocator_evidence_status=%s priority_proof_status=%s source_priority_contract_status=%s runtime_priority_status=%s scheduler_change_allowed=%s candidate_scheduler_status=%s terrain_queue_max_ms=%s process_wall_p95_ms=%s gpu_compositor_submit_max_ms=%s gpu_upload_fail=%s expected_gpu_upload_fail=%s expected_gpu_upload_fail_injected=%s upload_fallback_shadow_path=%s ground_misses=%s packet_queue_lag_ms=%s chunk_unload_total=%s current_chunk_collision=%s collision_refresh_rebuilt=%s collision_q_max=%s collision_phase_total_ms=%s collision_phase_component_ms=%s shadow_proxy_refresh_reuse=%s proxy_shadow=%s proxy_shadow_only=%s compact_shadow_proxy=%s compact_shadow_normals_saved=%s transparent_active=%s transparent_fallback=%s transparent_sort_active=%s transparent_sort_ms=%s transparent_cutout_uploads=%s transparent_build_envelope_ms=%s stage_pool_reuses=%s grouped_saved_records=%s default_runtime_change_allowed=%s requires_external_profiler_before_default=%s requires_mac_windows_validation=%s external_profile_status=%s caveat=%s\n' \
    "$id" "$category" "$required" "$status_value" "$expected_status" "$rel_path" "$bytes" "$mtime" "$root_token" \
    "$gpu_subchunks" "$gpu_draws" "$gpu_faces" "$draw_cmd_occupancy_pct" "$configured_buffer_bytes" "$configured_buffer_budget_pct" "$active_face_bytes" "$active_face_budget_pct" "$logical_draw_records" "$submitted_draw_records" "$draw_cmd_headroom_bytes" "$residency_pressure_class" "$residency_proof_status" "$allocator_evidence_status" "$priority_proof_status" "$source_priority_contract_status" "$runtime_priority_status" "$scheduler_change_allowed" "$candidate_scheduler_status" "$terrain_queue_max_ms" "$process_wall_p95_ms" "$gpu_compositor_submit_max_ms" \
    "$gpu_upload_fail" "$expected_gpu_upload_fail" "$expected_gpu_upload_fail_injected" "$upload_fallback_shadow_path" "$ground_misses" "$packet_queue_lag_ms" "$chunk_unload_total" "$current_chunk_collision" "$collision_refresh_rebuilt" "$collision_q_max" "$collision_phase_total_ms" "$collision_phase_component_ms" \
    "$shadow_proxy_refresh_reuse" "$proxy_shadow" "$proxy_shadow_only" "$compact_shadow_proxy" "$compact_shadow_normals_saved" \
    "$transparent_active" "$transparent_fallback" "$transparent_sort_active" "$transparent_sort_ms" "$transparent_cutout_uploads" "$transparent_build_envelope_ms" \
    "$stage_pool_reuses" "$grouped_saved_records" "$default_runtime_change_allowed" "$requires_external_profiler_before_default" "$requires_mac_windows_validation" "$external_profile_status" "$caveat" >> "$INDEX_PATH"
}

: > "$INDEX_PATH"

record_artifact rapid_camera_turn streaming 1 status pass "$RAPID_CAMERA_TURN_SUMMARY"
record_artifact rapid_camera_turn_movement_source streaming 1 budget_status pass "$RAPID_CAMERA_TURN_MOVEMENT_SUMMARY"
record_artifact chunk_boundary streaming 1 status pass "$CHUNK_BOUNDARY_SUMMARY"
record_artifact chunk_boundary_suite_source streaming 1 status pass "$CHUNK_BOUNDARY_SUITE_SUMMARY"
record_artifact chunk_unload_churn_diagnosis streaming 1 status pass "$CHUNK_UNLOAD_CHURN_SUMMARY"
record_artifact repeated_edit_benchmark world_interaction 1 status pass "$REPEATED_EDIT_BENCHMARK_SUMMARY"
record_artifact border_edit_benchmark world_interaction 1 status pass "$BORDER_EDIT_BENCHMARK_SUMMARY"
record_artifact partial_dirty_edge_matrix world_interaction 1 status pass "$PARTIAL_DIRTY_EDGE_MATRIX_SUMMARY"
record_artifact collision_refresh_cost_audit world_interaction 1 status pass "$COLLISION_REFRESH_COST_AUDIT_SUMMARY"
record_artifact shadow_proxy_refresh_cost_audit world_interaction 1 status pass "$SHADOW_PROXY_REFRESH_COST_AUDIT_SUMMARY"
record_artifact edit_burst_budget world_interaction 1 status pass "$EDIT_BURST_BUDGET_SUMMARY"
record_artifact edit_visual_parity world_interaction 1 status pass "$EDIT_VISUAL_PARITY_SUMMARY"
record_artifact world_interaction_checkpoint world_interaction 1 status pass "$WORLD_INTERACTION_CHECKPOINT_SUMMARY"
record_artifact macos_metal_capture_pack external_profiler 1 status pass "$MACOS_METAL_CAPTURE_PACK_SUMMARY"
record_artifact streaming_priority_audit streaming 1 status pass "$STREAMING_PRIORITY_AUDIT_SUMMARY"
record_artifact streaming_scheduler_prototype streaming 1 status pass "$STREAMING_SCHEDULER_PROTOTYPE_SUMMARY"
record_artifact streaming_scheduler_workload_matrix streaming 1 status pass "$STREAMING_SCHEDULER_WORKLOAD_MATRIX_SUMMARY"
record_artifact streaming_scheduler_tie_probe streaming 1 status pass "$STREAMING_SCHEDULER_TIE_PROBE_SUMMARY"
record_artifact streaming_scheduler_decision_checkpoint streaming 1 status pass "$STREAMING_SCHEDULER_DECISION_CHECKPOINT_SUMMARY"
record_artifact streaming_scheduler_boundary_matrix streaming 0 status pass "$STREAMING_SCHEDULER_BOUNDARY_MATRIX_SUMMARY"
record_artifact upload_failure_fallback streaming 1 status pass "$UPLOAD_FAILURE_FALLBACK_SUMMARY"
record_artifact load_scaling residency 1 status pass "$LOAD_SCALING_SUMMARY"
record_artifact resident_set_growth_source residency 1 status pass "$RESIDENT_SET_GROWTH_SUMMARY"
record_artifact mass_chunk_load residency 1 status pass "$MASS_CHUNK_LOAD_SUMMARY"
record_artifact buffer_residency_budget residency 1 status pass "$BUFFER_RESIDENCY_BUDGET_SUMMARY"
record_artifact upload_budget upload 1 status pass "$UPLOAD_BUDGET_SUMMARY"
record_artifact upload_stage_pool_load_scaling upload 1 status pass "$UPLOAD_STAGE_POOL_LOAD_SCALING_SUMMARY"
record_artifact grouped_draws draw_submission 1 status pass "$GROUPED_DRAWS_SUMMARY"
record_artifact cutout_pressure transparent 1 status pass "$CUTOUT_PRESSURE_SUMMARY"
record_artifact cutout_fixture_acceptance transparent 1 transparent_cutout_fixture_acceptance_status pass "$CUTOUT_FIXTURE_ACCEPTANCE_SUMMARY"
record_artifact transparent_sort_build_cost transparent 1 status pass "$TRANSPARENT_SORT_BUILD_COST_SUMMARY"
record_artifact shader_profiler_capture_pack external_profiler 0 status pass "$SHADER_PROFILER_CAPTURE_PACK"
record_artifact exploration_soak streaming_governance 0 status pass "$EXPLORATION_SOAK_SUMMARY"
record_artifact upload_pressure upload_governance 0 status pass "$UPLOAD_PRESSURE_SUMMARY"
record_artifact resource_lifecycle resource_governance 0 resource_lifecycle_audit_status pass "$RESOURCE_LIFECYCLE_SUMMARY"
record_artifact memory_budget memory_governance 0 status pass "$MEMORY_BUDGET_SUMMARY"
record_artifact report_v2 report_governance 0 status pass "$REPORT_V2_SUMMARY"
record_artifact baseline_governance report_governance 0 status pass "$BASELINE_GOVERNANCE_SUMMARY"
record_artifact test_strategy governance 0 status pass "$TEST_STRATEGY_SUMMARY"
record_artifact external_profiling_campaign external_profiler 0 status pass "$EXTERNAL_PROFILING_CAMPAIGN_SUMMARY"

awk \
  -v index_path="$INDEX_PATH" '
  function reset_fields(  i) {
    for (i in f) {
      delete f[i]
    }
  }
  function parse_fields(  i, pair, pos, key, value) {
    reset_fields()
    for (i = 2; i <= NF; i++) {
      pair = $i
      pos = index(pair, "=")
      if (pos > 0) {
        key = substr(pair, 1, pos - 1)
        value = substr(pair, pos + 1)
        f[key] = value
      }
    }
  }
  function is_number(value) {
    return value ~ /^-?[0-9]+([.][0-9]+)?$/
  }
  function max_update(key, target) {
    if (is_number(f[key])) {
      if (!(target in max_seen) || f[key] + 0 > max_value[target]) {
        max_value[target] = f[key] + 0
        max_seen[target] = 1
      }
    }
  }
  function max_text(target) {
    if (target in max_seen) {
      return sprintf("%.3f", max_value[target])
    }
    return "n/a"
  }
  function min_update(key, target) {
    if (is_number(f[key])) {
      if (!(target in min_seen) || f[key] + 0 < min_value[target]) {
        min_value[target] = f[key] + 0
        min_seen[target] = 1
      }
    }
  }
  function min_text(target) {
    if (target in min_seen) {
      return sprintf("%.3f", min_value[target])
    }
    return "n/a"
  }
  $1 == "gpu_artifact" {
    parse_fields()
    artifact_count++
    if (f["status"] == "pass") {
      pass_count++
    }
    if (f["status"] == "missing") {
      missing_count++
    }
    if (f["required"] + 0 == 1) {
      required_count++
      if (f["status"] == "pass") {
        required_pass_count++
      } else if (f["status"] == "missing") {
        required_missing_count++
      } else {
        required_bad_status_count++
      }
      if (is_number(f["gpu_upload_fail"]) && f["gpu_upload_fail"] + 0 != 0) {
        upload_fail_violations++
      }
      if (is_number(f["ground_misses"]) && f["ground_misses"] + 0 != 0) {
        ground_miss_violations++
      }
    }
    if (f["default_runtime_change_allowed"] != "" && f["default_runtime_change_allowed"] != "n/a" && f["default_runtime_change_allowed"] != "0") {
      default_change_violations++
    }
    if (f["scheduler_change_allowed"] != "" && f["scheduler_change_allowed"] != "n/a" && f["scheduler_change_allowed"] != "0") {
      scheduler_change_violations++
    }
    if (f["external_profile_status"] == "pending_external_profiler") {
      pending_external_count++
    }
    if (f["requires_external_profiler_before_default"] == "1") {
      requires_external_profiler_count++
    }
    if (f["requires_mac_windows_validation"] == "1") {
      requires_mac_windows_validation_count++
    }
    if (f["residency_pressure_class"] == "high") {
      high_residency_pressure_count++
    } else if (f["residency_pressure_class"] == "moderate") {
      moderate_residency_pressure_count++
    } else if (f["residency_pressure_class"] == "low") {
      low_residency_pressure_count++
    }
    max_update("gpu_subchunks", "gpu_subchunks")
    max_update("gpu_draws", "gpu_draws")
    max_update("gpu_faces", "gpu_faces")
    max_update("draw_cmd_occupancy_pct", "draw_cmd_occupancy_pct")
    max_update("configured_buffer_bytes", "configured_buffer_bytes")
    max_update("configured_buffer_budget_pct", "configured_buffer_budget_pct")
    max_update("active_face_bytes", "active_face_bytes")
    max_update("active_face_budget_pct", "active_face_budget_pct")
    max_update("logical_draw_records", "logical_draw_records")
    max_update("submitted_draw_records", "submitted_draw_records")
    min_update("draw_cmd_headroom_bytes", "draw_cmd_headroom_bytes")
    max_update("terrain_queue_max_ms", "terrain_queue_max_ms")
    max_update("process_wall_p95_ms", "process_wall_p95_ms")
    max_update("gpu_compositor_submit_max_ms", "gpu_compositor_submit_max_ms")
    max_update("packet_queue_lag_ms", "packet_queue_lag_ms")
    max_update("collision_refresh_rebuilt", "collision_refresh_rebuilt")
    max_update("collision_q_max", "collision_q_max")
    max_update("collision_phase_total_ms", "collision_phase_total_ms")
    max_update("collision_phase_component_ms", "collision_phase_component_ms")
    max_update("shadow_proxy_refresh_reuse", "shadow_proxy_refresh_reuse")
    max_update("proxy_shadow", "proxy_shadow")
    max_update("proxy_shadow_only", "proxy_shadow_only")
    max_update("compact_shadow_proxy", "compact_shadow_proxy")
    max_update("compact_shadow_normals_saved", "compact_shadow_normals_saved")
    max_update("transparent_cutout_uploads", "transparent_cutout_uploads")
    max_update("transparent_build_envelope_ms", "transparent_build_envelope_ms")
    max_update("stage_pool_reuses", "stage_pool_reuses")
    max_update("grouped_saved_records", "grouped_saved_records")
  }
  END {
    status = "pass"
    reason = "ok"
    if (required_missing_count + 0 != 0) {
      status = "fail"
      reason = "missing_required_artifacts"
    } else if (required_bad_status_count + 0 != 0) {
      status = "fail"
      reason = "required_artifact_status"
    } else if (upload_fail_violations + 0 != 0) {
      status = "fail"
      reason = "gpu_upload_fail"
    } else if (ground_miss_violations + 0 != 0) {
      status = "fail"
      reason = "ground_misses"
    } else if (default_change_violations + 0 != 0) {
      status = "fail"
      reason = "unexpected_default_runtime_change"
    } else if (scheduler_change_violations + 0 != 0) {
      status = "fail"
      reason = "unexpected_scheduler_change"
    }
    external_profiler_status = pending_external_count + 0 > 0 ? "pending_external_profiler" : "not_indexed"
    mac_windows_validation_status = requires_mac_windows_validation_count + 0 > 0 ? "pending_external_validation" : "not_required_by_index"
    residency_pressure_class = high_residency_pressure_count + 0 > 0 ? "high" : (moderate_residency_pressure_count + 0 > 0 ? "moderate" : (low_residency_pressure_count + 0 > 0 ? "low" : "n/a"))
    printf("gpu_stress_artifact_index status=%s reason=%s artifact_count=%d pass_count=%d missing_count=%d required_count=%d required_pass_count=%d required_missing_count=%d required_bad_status_count=%d upload_fail_violations=%d ground_miss_violations=%d default_change_violations=%d scheduler_change_violations=%d pending_external_count=%d requires_external_profiler_count=%d requires_mac_windows_validation_count=%d external_profiler_status=%s mac_windows_validation_status=%s local_fps_status=report_only godot_gpu_timestamp_status=report_only residency_pressure_class=%s high_residency_pressure_count=%d moderate_residency_pressure_count=%d low_residency_pressure_count=%d max_configured_buffer_bytes=%s max_configured_buffer_budget_pct=%s max_active_face_bytes=%s max_active_face_budget_pct=%s max_logical_draw_records=%s max_submitted_draw_records=%s min_draw_cmd_headroom_bytes=%s max_gpu_subchunks=%s max_gpu_draws=%s max_gpu_faces=%s max_draw_cmd_occupancy_pct=%s max_terrain_queue_ms=%s max_process_wall_p95_ms=%s max_gpu_compositor_submit_ms=%s max_packet_queue_lag_ms=%s max_collision_refresh_rebuilt=%s max_collision_q_max=%s max_collision_phase_total_ms=%s max_collision_phase_component_ms=%s max_shadow_proxy_refresh_reuse=%s max_proxy_shadow=%s max_proxy_shadow_only=%s max_compact_shadow_proxy=%s max_compact_shadow_normals_saved=%s max_transparent_cutout_uploads=%s max_transparent_build_envelope_ms=%s max_stage_pool_reuses=%s max_grouped_saved_records=%s index=%s\n", status, reason, artifact_count, pass_count, missing_count, required_count, required_pass_count, required_missing_count, required_bad_status_count, upload_fail_violations, ground_miss_violations, default_change_violations, scheduler_change_violations, pending_external_count, requires_external_profiler_count, requires_mac_windows_validation_count, external_profiler_status, mac_windows_validation_status, residency_pressure_class, high_residency_pressure_count, moderate_residency_pressure_count, low_residency_pressure_count, max_text("configured_buffer_bytes"), max_text("configured_buffer_budget_pct"), max_text("active_face_bytes"), max_text("active_face_budget_pct"), max_text("logical_draw_records"), max_text("submitted_draw_records"), min_text("draw_cmd_headroom_bytes"), max_text("gpu_subchunks"), max_text("gpu_draws"), max_text("gpu_faces"), max_text("draw_cmd_occupancy_pct"), max_text("terrain_queue_max_ms"), max_text("process_wall_p95_ms"), max_text("gpu_compositor_submit_max_ms"), max_text("packet_queue_lag_ms"), max_text("collision_refresh_rebuilt"), max_text("collision_q_max"), max_text("collision_phase_total_ms"), max_text("collision_phase_component_ms"), max_text("shadow_proxy_refresh_reuse"), max_text("proxy_shadow"), max_text("proxy_shadow_only"), max_text("compact_shadow_proxy"), max_text("compact_shadow_normals_saved"), max_text("transparent_cutout_uploads"), max_text("transparent_build_envelope_ms"), max_text("stage_pool_reuses"), max_text("grouped_saved_records"), index_path)
    if (status != "pass") {
      exit 1
    }
  }
' "$INDEX_PATH" > "$SUMMARY_PATH" || {
  cat "$SUMMARY_PATH" >&2 || true
  fail "GPU stress artifact index failed"
}

cat "$SUMMARY_PATH"
echo "GPU stress artifact index: $INDEX_PATH"
