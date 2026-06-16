#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/gpu_streaming_priority_audit_current"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

SUMMARY_PATH="$OUT_DIR/gpu-streaming-priority-audit-summary.txt"
CHUNK_BOUNDARY_SUMMARY="${RUMPELMC_GPU_STREAMING_PRIORITY_CHUNK_BOUNDARY_SUMMARY:-"$ROOT_DIR/logs/gpu_terrain_chunk_boundary_stress_current/chunk-boundary-stress-summary.txt"}"
RAPID_CAMERA_TURN_SUMMARY="${RUMPELMC_GPU_STREAMING_PRIORITY_RAPID_CAMERA_TURN_SUMMARY:-"$ROOT_DIR/logs/gpu_terrain_rapid_camera_turn_stress_current/rapid-camera-turn-stress-summary.txt"}"
CHUNK_UNLOAD_SUMMARY="${RUMPELMC_GPU_STREAMING_PRIORITY_CHUNK_UNLOAD_SUMMARY:-"$ROOT_DIR/logs/gpu_chunk_unload_churn_diagnosis_current/gpu-chunk-unload-churn-diagnosis-summary.txt"}"
BUFFER_RESIDENCY_SUMMARY="${RUMPELMC_GPU_STREAMING_PRIORITY_BUFFER_RESIDENCY_SUMMARY:-"$ROOT_DIR/logs/gpu_buffer_residency_budget_current/gpu-buffer-residency-budget-summary.txt"}"
UPLOAD_FALLBACK_SUMMARY="${RUMPELMC_GPU_STREAMING_PRIORITY_UPLOAD_FALLBACK_SUMMARY:-"$ROOT_DIR/logs/gpu_upload_failure_fallback_current/gpu-upload-failure-fallback-summary.txt"}"
SOURCE_PATH="${RUMPELMC_GPU_STREAMING_PRIORITY_SOURCE:-"$ROOT_DIR/client/rust_ext/src/lib.rs"}"
CLIENT_SOURCE_PATH="${RUMPELMC_GPU_STREAMING_PRIORITY_CLIENT_SOURCE:-"$SOURCE_PATH"}"
SERVER_WORLD_SOURCE_PATH="${RUMPELMC_GPU_STREAMING_PRIORITY_SERVER_WORLD_SOURCE:-"$ROOT_DIR/server/pkg/world/world.go"}"
SERVER_WORLD_TEST_SOURCE_PATH="${RUMPELMC_GPU_STREAMING_PRIORITY_SERVER_WORLD_TEST_SOURCE:-"$ROOT_DIR/server/pkg/world/world_test.go"}"
SERVER_NETWORK_SOURCE_PATH="${RUMPELMC_GPU_STREAMING_PRIORITY_SERVER_NETWORK_SOURCE:-"$ROOT_DIR/server/pkg/network/server.go"}"
SERVER_NETWORK_TEST_SOURCE_PATH="${RUMPELMC_GPU_STREAMING_PRIORITY_SERVER_NETWORK_TEST_SOURCE:-"$ROOT_DIR/server/pkg/network/server_test.go"}"

MIN_MOVEMENT_CASES="${RUMPELMC_GPU_STREAMING_PRIORITY_MIN_MOVEMENT_CASES:-4}"
MIN_WORKLOAD_CASES="${RUMPELMC_GPU_STREAMING_PRIORITY_MIN_WORKLOAD_CASES:-1}"
MIN_RAPID_CURRENT_CHUNK_SUBMESHES="${RUMPELMC_GPU_STREAMING_PRIORITY_MIN_RAPID_CURRENT_CHUNK_SUBMESHES:-1}"
MIN_RAPID_CURRENT_CHUNK_COLLISION="${RUMPELMC_GPU_STREAMING_PRIORITY_MIN_RAPID_CURRENT_CHUNK_COLLISION:-1}"
MAX_TERRAIN_QUEUE_MS="${RUMPELMC_GPU_STREAMING_PRIORITY_MAX_TERRAIN_QUEUE_MS:-6.667}"
MAX_PROCESS_WALL_P95_MS="${RUMPELMC_GPU_STREAMING_PRIORITY_MAX_PROCESS_WALL_P95_MS:-6.667}"
MAX_GPU_COMPOSITOR_SUBMIT_MS="${RUMPELMC_GPU_STREAMING_PRIORITY_MAX_GPU_COMPOSITOR_SUBMIT_MS:-6.667}"
MAX_PACKET_QUEUE_LAG_MS="${RUMPELMC_GPU_STREAMING_PRIORITY_MAX_PACKET_QUEUE_LAG_MS:-33.334}"
MAX_UPLOAD_FAIL="${RUMPELMC_GPU_STREAMING_PRIORITY_MAX_UPLOAD_FAIL:-0}"
MAX_GROUND_MISSES="${RUMPELMC_GPU_STREAMING_PRIORITY_MAX_GROUND_MISSES:-0}"
MAX_CHUNK_UNLOAD="${RUMPELMC_GPU_STREAMING_PRIORITY_MAX_CHUNK_UNLOAD:-0}"
MAX_NOT_READY_CASES="${RUMPELMC_GPU_STREAMING_PRIORITY_MAX_NOT_READY_CASES:-0}"
MAX_EXPECTED_CHUNK_FAILURES="${RUMPELMC_GPU_STREAMING_PRIORITY_MAX_EXPECTED_CHUNK_FAILURES:-0}"
MIN_UPLOAD_FALLBACK_FAILURES="${RUMPELMC_GPU_STREAMING_PRIORITY_MIN_UPLOAD_FALLBACK_FAILURES:-1}"

fail() {
  echo "gpu_streaming_priority_audit: $*" >&2
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

field_or_missing() {
  key="$1"
  path="$2"
  value="$(field_metric "$key" "$path")"
  if [ -n "$value" ]; then
    printf '%s\n' "$value"
  else
    printf 'missing\n'
  fi
}

source_token_present_in() {
  path="$1"
  token="$2"
  if grep -Fq "$token" "$path"; then
    printf '1\n'
  else
    printf '0\n'
  fi
}

mkdir -p "$OUT_DIR"

CHUNK_BOUNDARY_SUMMARY="$(normalize_path "$CHUNK_BOUNDARY_SUMMARY")"
RAPID_CAMERA_TURN_SUMMARY="$(normalize_path "$RAPID_CAMERA_TURN_SUMMARY")"
CHUNK_UNLOAD_SUMMARY="$(normalize_path "$CHUNK_UNLOAD_SUMMARY")"
BUFFER_RESIDENCY_SUMMARY="$(normalize_path "$BUFFER_RESIDENCY_SUMMARY")"
UPLOAD_FALLBACK_SUMMARY="$(normalize_path "$UPLOAD_FALLBACK_SUMMARY")"
CLIENT_SOURCE_PATH="$(normalize_path "$CLIENT_SOURCE_PATH")"
SERVER_WORLD_SOURCE_PATH="$(normalize_path "$SERVER_WORLD_SOURCE_PATH")"
SERVER_WORLD_TEST_SOURCE_PATH="$(normalize_path "$SERVER_WORLD_TEST_SOURCE_PATH")"
SERVER_NETWORK_SOURCE_PATH="$(normalize_path "$SERVER_NETWORK_SOURCE_PATH")"
SERVER_NETWORK_TEST_SOURCE_PATH="$(normalize_path "$SERVER_NETWORK_TEST_SOURCE_PATH")"

for entry in \
  "chunk_boundary:$CHUNK_BOUNDARY_SUMMARY" \
  "rapid_camera_turn:$RAPID_CAMERA_TURN_SUMMARY" \
  "chunk_unload:$CHUNK_UNLOAD_SUMMARY" \
  "buffer_residency:$BUFFER_RESIDENCY_SUMMARY" \
  "upload_fallback:$UPLOAD_FALLBACK_SUMMARY" \
  "client_source:$CLIENT_SOURCE_PATH" \
  "server_world_source:$SERVER_WORLD_SOURCE_PATH" \
  "server_world_test_source:$SERVER_WORLD_TEST_SOURCE_PATH" \
  "server_network_source:$SERVER_NETWORK_SOURCE_PATH" \
  "server_network_test_source:$SERVER_NETWORK_TEST_SOURCE_PATH"; do
  label="${entry%%:*}"
  path="${entry#*:}"
  if [ ! -s "$path" ]; then
    printf 'gpu_streaming_priority_audit status=fail reason=missing_required_input missing_input=%s source_priority_contract_status=missing runtime_priority_status=missing upload_fallback_status=missing scheduler_change_allowed=0 default_runtime_change_allowed=0 candidate_scheduler_status=deferred chunk_boundary_summary=%s rapid_camera_turn_summary=%s chunk_unload_summary=%s buffer_residency_summary=%s upload_fallback_summary=%s client_source=%s server_world_source=%s server_world_test_source=%s server_network_source=%s server_network_test_source=%s\n' \
      "$label" "$CHUNK_BOUNDARY_SUMMARY" "$RAPID_CAMERA_TURN_SUMMARY" "$CHUNK_UNLOAD_SUMMARY" "$BUFFER_RESIDENCY_SUMMARY" "$UPLOAD_FALLBACK_SUMMARY" "$CLIENT_SOURCE_PATH" "$SERVER_WORLD_SOURCE_PATH" "$SERVER_WORLD_TEST_SOURCE_PATH" "$SERVER_NETWORK_SOURCE_PATH" "$SERVER_NETWORK_TEST_SOURCE_PATH" > "$SUMMARY_PATH"
    cat "$SUMMARY_PATH" >&2
    fail "missing required input $label at $path"
  fi
done

client_max_mesh_jobs="$(source_token_present_in "$CLIENT_SOURCE_PATH" 'const MAX_MESH_JOBS_PER_FRAME')"
client_max_collision_rebuilds="$(source_token_present_in "$CLIENT_SOURCE_PATH" 'const MAX_COLLISION_REFRESH_REBUILDS_PER_FRAME')"
client_pop_next_mesh_queue="$(source_token_present_in "$CLIENT_SOURCE_PATH" 'fn pop_next_mesh_queue_key(')"
client_collision_backpressure_fn="$(source_token_present_in "$CLIENT_SOURCE_PATH" 'fn should_process_mesh_queue_after_collision_refresh(')"
client_player_fifo="$(source_token_present_in "$CLIENT_SOURCE_PATH" 'fn mesh_queue_pop_prioritizes_player_chunk_with_fifo_ties()')"
client_initial_hint="$(source_token_present_in "$CLIENT_SOURCE_PATH" 'fn mesh_queue_uses_initial_chunk_hint_before_player_chunk_updates()')"
client_collision_backpressure_test="$(source_token_present_in "$CLIENT_SOURCE_PATH" 'fn mesh_queue_waits_when_collision_refresh_rebuilt_this_frame()')"
client_visible_render_wait="$(source_token_present_in "$CLIENT_SOURCE_PATH" 'fn gpu_visible_render_waits_for_flag_attachment_and_confirmed_frame()')"
client_upload_fallback_test="$(source_token_present_in "$CLIENT_SOURCE_PATH" 'fn gpu_upload_failure_recovery_keeps_cpu_fallback_until_slot_exists()')"
client_current_chunk_counts="$(source_token_present_in "$CLIENT_SOURCE_PATH" 'fn current_chunk_node_counts(&self) -> NodePerfCounts')"
client_popin_probe="$(source_token_present_in "$CLIENT_SOURCE_PATH" 'fn record_pop_in_probe(&mut self)')"
server_chunks_ordered="$(source_token_present_in "$SERVER_WORLD_SOURCE_PATH" 'func (w *World) ChunksAroundOrdered')"
server_direction_score="$(source_token_present_in "$SERVER_WORLD_SOURCE_PATH" 'func chunkDirectionScore')"
server_current_first_test="$(source_token_present_in "$SERVER_WORLD_TEST_SOURCE_PATH" 'func TestChunksAroundOrderedKeepsCurrentChunkFirst')"
server_direction_tiebreak_test="$(source_token_present_in "$SERVER_WORLD_TEST_SOURCE_PATH" 'func TestChunksAroundOrderedUsesDirectionTieBreak')"
server_bootstrap_default="$(source_token_present_in "$SERVER_NETWORK_SOURCE_PATH" 'const defaultBootstrapRadius')"
server_bootstrap_configured="$(source_token_present_in "$SERVER_NETWORK_SOURCE_PATH" 'func configuredBootstrapRadius')"
server_bootstrap_current_only_test="$(source_token_present_in "$SERVER_NETWORK_TEST_SOURCE_PATH" 'func TestConfiguredBootstrapRadiusAllowsCurrentChunkOnly')"
source_required_count=18
source_present_count=$((client_max_mesh_jobs + client_max_collision_rebuilds + client_pop_next_mesh_queue + client_collision_backpressure_fn + client_player_fifo + client_initial_hint + client_collision_backpressure_test + client_visible_render_wait + client_upload_fallback_test + client_current_chunk_counts + client_popin_probe + server_chunks_ordered + server_direction_score + server_current_first_test + server_direction_tiebreak_test + server_bootstrap_default + server_bootstrap_configured + server_bootstrap_current_only_test))

cb_status="$(field_or_missing status "$CHUNK_BOUNDARY_SUMMARY")"
cb_expected_cases="$(field_or_missing expected_cases "$CHUNK_BOUNDARY_SUMMARY")"
cb_completed_cases="$(field_or_missing completed_cases "$CHUNK_BOUNDARY_SUMMARY")"
cb_movement_cases="$(field_or_missing movement_cases "$CHUNK_BOUNDARY_SUMMARY")"
cb_workload_cases="$(field_or_missing workload_cases "$CHUNK_BOUNDARY_SUMMARY")"
cb_missing_cases="$(field_or_missing missing_cases "$CHUNK_BOUNDARY_SUMMARY")"
cb_failed_cases="$(field_or_missing failed_cases "$CHUNK_BOUNDARY_SUMMARY")"
cb_expected_chunk_failures="$(field_or_missing expected_chunk_failures "$CHUNK_BOUNDARY_SUMMARY")"
cb_render_not_ready_cases="$(field_or_missing render_not_ready_cases "$CHUNK_BOUNDARY_SUMMARY")"
cb_collision_not_ready_cases="$(field_or_missing collision_not_ready_cases "$CHUNK_BOUNDARY_SUMMARY")"
cb_ground_misses="$(field_or_missing ground_misses "$CHUNK_BOUNDARY_SUMMARY")"
cb_gpu_upload_fail="$(field_or_missing gpu_upload_fail "$CHUNK_BOUNDARY_SUMMARY")"
cb_gpu_upload_fail_capacity="$(field_or_missing gpu_upload_fail_capacity "$CHUNK_BOUNDARY_SUMMARY")"
cb_gpu_upload_fail_fragmented="$(field_or_missing gpu_upload_fail_fragmented "$CHUNK_BOUNDARY_SUMMARY")"
cb_max_chunk_unload_total="$(field_or_missing max_chunk_unload_total "$CHUNK_BOUNDARY_SUMMARY")"
cb_max_chunk_unload_neighbor_refreshes="$(field_or_missing max_chunk_unload_neighbor_refreshes "$CHUNK_BOUNDARY_SUMMARY")"
cb_max_chunk_unload="$(field_or_missing max_chunk_unload "$CHUNK_BOUNDARY_SUMMARY")"
cb_max_chunk_unload_grace_kept="$(field_or_missing max_chunk_unload_grace_kept "$CHUNK_BOUNDARY_SUMMARY")"
cb_max_popin_missing_chunks="$(field_or_missing max_popin_missing_chunks "$CHUNK_BOUNDARY_SUMMARY")"
cb_max_popin_collision_missing_chunks="$(field_or_missing max_popin_collision_missing_chunks "$CHUNK_BOUNDARY_SUMMARY")"
cb_max_terrain_queue_ms="$(field_or_missing max_terrain_queue_ms "$CHUNK_BOUNDARY_SUMMARY")"
cb_max_process_wall_p95_ms="$(field_or_missing max_process_wall_p95_ms "$CHUNK_BOUNDARY_SUMMARY")"
cb_max_gpu_compositor_submit_ms="$(field_or_missing max_gpu_compositor_submit_ms "$CHUNK_BOUNDARY_SUMMARY")"
cb_max_packet_queue_lag_ms="$(field_or_missing max_packet_queue_lag_ms "$CHUNK_BOUNDARY_SUMMARY")"

rapid_status="$(field_or_missing status "$RAPID_CAMERA_TURN_SUMMARY")"
rapid_current_chunk="$(field_or_missing current_chunk "$RAPID_CAMERA_TURN_SUMMARY")"
rapid_current_chunk_loaded="$(field_or_missing current_chunk_loaded "$RAPID_CAMERA_TURN_SUMMARY")"
rapid_current_render_ready="$(field_or_missing current_render_ready "$RAPID_CAMERA_TURN_SUMMARY")"
rapid_current_chunk_submeshes="$(field_or_missing current_chunk_submeshes "$RAPID_CAMERA_TURN_SUMMARY")"
rapid_current_collision_ready="$(field_or_missing current_collision_ready "$RAPID_CAMERA_TURN_SUMMARY")"
rapid_current_chunk_collision="$(field_or_missing current_chunk_collision "$RAPID_CAMERA_TURN_SUMMARY")"
rapid_ground_misses="$(field_or_missing ground_misses "$RAPID_CAMERA_TURN_SUMMARY")"
rapid_gpu_upload_fail="$(field_or_missing gpu_upload_fail "$RAPID_CAMERA_TURN_SUMMARY")"
rapid_gpu_upload_fail_capacity="$(field_or_missing gpu_upload_fail_capacity "$RAPID_CAMERA_TURN_SUMMARY")"
rapid_gpu_upload_fail_fragmented="$(field_or_missing gpu_upload_fail_fragmented "$RAPID_CAMERA_TURN_SUMMARY")"
rapid_gpu_upload_fail_injected="$(field_or_missing gpu_upload_fail_injected "$RAPID_CAMERA_TURN_SUMMARY")"
rapid_chunk_unload_total="$(field_or_missing chunk_unload_total "$RAPID_CAMERA_TURN_SUMMARY")"
rapid_chunk_unload_neighbor_refreshes="$(field_or_missing chunk_unload_neighbor_refreshes "$RAPID_CAMERA_TURN_SUMMARY")"
rapid_chunk_unload_max="$(field_or_missing chunk_unload_max "$RAPID_CAMERA_TURN_SUMMARY")"
rapid_popin_missing_chunks="$(field_or_missing popin_missing_chunks "$RAPID_CAMERA_TURN_SUMMARY")"
rapid_popin_collision_missing_chunks="$(field_or_missing popin_collision_missing_chunks "$RAPID_CAMERA_TURN_SUMMARY")"
rapid_terrain_queue_ms="$(field_or_missing terrain_queue_max_ms "$RAPID_CAMERA_TURN_SUMMARY")"
rapid_process_wall_ms="$(field_or_missing process_wall_p95_ms "$RAPID_CAMERA_TURN_SUMMARY")"
rapid_gpu_submit_ms="$(field_or_missing gpu_compositor_submit_max_ms "$RAPID_CAMERA_TURN_SUMMARY")"
rapid_packet_queue_lag_ms="$(field_or_missing packet_queue_lag_max_ms "$RAPID_CAMERA_TURN_SUMMARY")"

unload_status="$(field_or_missing status "$CHUNK_UNLOAD_SUMMARY")"
unload_policy_change_allowed="$(field_or_missing policy_change_allowed "$CHUNK_UNLOAD_SUMMARY")"
unload_candidate_policy_status="$(field_or_missing candidate_policy_status "$CHUNK_UNLOAD_SUMMARY")"
unload_default_runtime_change_allowed="$(field_or_missing default_runtime_change_allowed "$CHUNK_UNLOAD_SUMMARY")"
unload_max_chunk_unload_total="$(field_or_missing max_chunk_unload_total "$CHUNK_UNLOAD_SUMMARY")"
unload_max_chunk_unload_neighbor_refreshes="$(field_or_missing max_chunk_unload_neighbor_refreshes "$CHUNK_UNLOAD_SUMMARY")"
unload_max_chunk_unload="$(field_or_missing max_chunk_unload "$CHUNK_UNLOAD_SUMMARY")"
unload_max_packet_queue_lag_ms="$(field_or_missing max_packet_queue_lag_ms "$CHUNK_UNLOAD_SUMMARY")"

buffer_status="$(field_or_missing status "$BUFFER_RESIDENCY_SUMMARY")"
buffer_residency_pressure_class="$(field_or_missing residency_pressure_class "$BUFFER_RESIDENCY_SUMMARY")"
buffer_residency_proof_status="$(field_or_missing residency_proof_status "$BUFFER_RESIDENCY_SUMMARY")"
buffer_allocator_evidence_status="$(field_or_missing allocator_evidence_status "$BUFFER_RESIDENCY_SUMMARY")"
buffer_default_runtime_change_allowed="$(field_or_missing default_runtime_change_allowed "$BUFFER_RESIDENCY_SUMMARY")"
buffer_active_repack_allowed="$(field_or_missing active_repack_allowed "$BUFFER_RESIDENCY_SUMMARY")"
buffer_active_eviction_policy_change_allowed="$(field_or_missing active_eviction_policy_change_allowed "$BUFFER_RESIDENCY_SUMMARY")"
buffer_requires_external_profiler_before_default="$(field_or_missing requires_external_profiler_before_default "$BUFFER_RESIDENCY_SUMMARY")"
buffer_requires_mac_windows_validation="$(field_or_missing requires_mac_windows_validation "$BUFFER_RESIDENCY_SUMMARY")"
buffer_upload_fail_total="$(field_or_missing upload_fail_total "$BUFFER_RESIDENCY_SUMMARY")"
buffer_max_gpu_subchunks="$(field_or_missing max_gpu_subchunks "$BUFFER_RESIDENCY_SUMMARY")"
buffer_max_logical_draw_records="$(field_or_missing max_logical_draw_records "$BUFFER_RESIDENCY_SUMMARY")"
buffer_max_submitted_draw_records="$(field_or_missing max_submitted_draw_records "$BUFFER_RESIDENCY_SUMMARY")"
buffer_configured_buffer_budget_pct="$(field_or_missing configured_buffer_budget_pct "$BUFFER_RESIDENCY_SUMMARY")"
buffer_active_face_budget_pct="$(field_or_missing active_face_budget_pct "$BUFFER_RESIDENCY_SUMMARY")"

fallback_status="$(field_or_missing status "$UPLOAD_FALLBACK_SUMMARY")"
fallback_injection="$(field_or_missing injection "$UPLOAD_FALLBACK_SUMMARY")"
fallback_min_gpu_upload_failures="$(field_or_missing min_gpu_upload_failures "$UPLOAD_FALLBACK_SUMMARY")"
fallback_gpu_upload_fail="$(field_or_missing gpu_upload_fail "$UPLOAD_FALLBACK_SUMMARY")"
fallback_gpu_upload_fail_capacity="$(field_or_missing gpu_upload_fail_capacity "$UPLOAD_FALLBACK_SUMMARY")"
fallback_gpu_upload_fail_fragmented="$(field_or_missing gpu_upload_fail_fragmented "$UPLOAD_FALLBACK_SUMMARY")"
fallback_gpu_upload_fail_injected="$(field_or_missing gpu_upload_fail_injected "$UPLOAD_FALLBACK_SUMMARY")"
fallback_gpu_uploads="$(field_or_missing gpu_uploads "$UPLOAD_FALLBACK_SUMMARY")"
fallback_gpu_subchunks="$(field_or_missing gpu_subchunks "$UPLOAD_FALLBACK_SUMMARY")"
fallback_shadow_path="$(field_or_missing shadow_path "$UPLOAD_FALLBACK_SUMMARY")"
fallback_mesh_visible="$(field_or_missing mesh_visible "$UPLOAD_FALLBACK_SUMMARY")"
fallback_mesh_shadow_double="$(field_or_missing mesh_shadow_double "$UPLOAD_FALLBACK_SUMMARY")"
fallback_current_chunk_loaded="$(field_or_missing current_chunk_loaded "$UPLOAD_FALLBACK_SUMMARY")"
fallback_current_render_ready="$(field_or_missing current_render_ready "$UPLOAD_FALLBACK_SUMMARY")"
fallback_current_chunk_submeshes="$(field_or_missing current_chunk_submeshes "$UPLOAD_FALLBACK_SUMMARY")"
fallback_current_collision_ready="$(field_or_missing current_collision_ready "$UPLOAD_FALLBACK_SUMMARY")"
fallback_current_chunk_collision="$(field_or_missing current_chunk_collision "$UPLOAD_FALLBACK_SUMMARY")"
fallback_ground_misses="$(field_or_missing ground_misses "$UPLOAD_FALLBACK_SUMMARY")"
fallback_terrain_samples="$(field_or_missing terrain_samples "$UPLOAD_FALLBACK_SUMMARY")"

awk \
  -v source_present_count="$source_present_count" \
  -v source_required_count="$source_required_count" \
  -v client_max_mesh_jobs="$client_max_mesh_jobs" \
  -v client_max_collision_rebuilds="$client_max_collision_rebuilds" \
  -v client_pop_next_mesh_queue="$client_pop_next_mesh_queue" \
  -v client_collision_backpressure_fn="$client_collision_backpressure_fn" \
  -v client_player_fifo="$client_player_fifo" \
  -v client_initial_hint="$client_initial_hint" \
  -v client_collision_backpressure_test="$client_collision_backpressure_test" \
  -v client_visible_render_wait="$client_visible_render_wait" \
  -v client_upload_fallback_test="$client_upload_fallback_test" \
  -v client_current_chunk_counts="$client_current_chunk_counts" \
  -v client_popin_probe="$client_popin_probe" \
  -v server_chunks_ordered="$server_chunks_ordered" \
  -v server_direction_score="$server_direction_score" \
  -v server_current_first_test="$server_current_first_test" \
  -v server_direction_tiebreak_test="$server_direction_tiebreak_test" \
  -v server_bootstrap_default="$server_bootstrap_default" \
  -v server_bootstrap_configured="$server_bootstrap_configured" \
  -v server_bootstrap_current_only_test="$server_bootstrap_current_only_test" \
  -v cb_status="$cb_status" \
  -v cb_expected_cases="$cb_expected_cases" \
  -v cb_completed_cases="$cb_completed_cases" \
  -v cb_movement_cases="$cb_movement_cases" \
  -v cb_workload_cases="$cb_workload_cases" \
  -v cb_missing_cases="$cb_missing_cases" \
  -v cb_failed_cases="$cb_failed_cases" \
  -v cb_expected_chunk_failures="$cb_expected_chunk_failures" \
  -v cb_render_not_ready_cases="$cb_render_not_ready_cases" \
  -v cb_collision_not_ready_cases="$cb_collision_not_ready_cases" \
  -v cb_ground_misses="$cb_ground_misses" \
  -v cb_gpu_upload_fail="$cb_gpu_upload_fail" \
  -v cb_gpu_upload_fail_capacity="$cb_gpu_upload_fail_capacity" \
  -v cb_gpu_upload_fail_fragmented="$cb_gpu_upload_fail_fragmented" \
  -v cb_max_chunk_unload_total="$cb_max_chunk_unload_total" \
  -v cb_max_chunk_unload_neighbor_refreshes="$cb_max_chunk_unload_neighbor_refreshes" \
  -v cb_max_chunk_unload="$cb_max_chunk_unload" \
  -v cb_max_chunk_unload_grace_kept="$cb_max_chunk_unload_grace_kept" \
  -v cb_max_popin_missing_chunks="$cb_max_popin_missing_chunks" \
  -v cb_max_popin_collision_missing_chunks="$cb_max_popin_collision_missing_chunks" \
  -v cb_max_terrain_queue_ms="$cb_max_terrain_queue_ms" \
  -v cb_max_process_wall_p95_ms="$cb_max_process_wall_p95_ms" \
  -v cb_max_gpu_compositor_submit_ms="$cb_max_gpu_compositor_submit_ms" \
  -v cb_max_packet_queue_lag_ms="$cb_max_packet_queue_lag_ms" \
  -v rapid_status="$rapid_status" \
  -v rapid_current_chunk="$rapid_current_chunk" \
  -v rapid_current_chunk_loaded="$rapid_current_chunk_loaded" \
  -v rapid_current_render_ready="$rapid_current_render_ready" \
  -v rapid_current_chunk_submeshes="$rapid_current_chunk_submeshes" \
  -v rapid_current_collision_ready="$rapid_current_collision_ready" \
  -v rapid_current_chunk_collision="$rapid_current_chunk_collision" \
  -v rapid_ground_misses="$rapid_ground_misses" \
  -v rapid_gpu_upload_fail="$rapid_gpu_upload_fail" \
  -v rapid_gpu_upload_fail_capacity="$rapid_gpu_upload_fail_capacity" \
  -v rapid_gpu_upload_fail_fragmented="$rapid_gpu_upload_fail_fragmented" \
  -v rapid_gpu_upload_fail_injected="$rapid_gpu_upload_fail_injected" \
  -v rapid_chunk_unload_total="$rapid_chunk_unload_total" \
  -v rapid_chunk_unload_neighbor_refreshes="$rapid_chunk_unload_neighbor_refreshes" \
  -v rapid_chunk_unload_max="$rapid_chunk_unload_max" \
  -v rapid_popin_missing_chunks="$rapid_popin_missing_chunks" \
  -v rapid_popin_collision_missing_chunks="$rapid_popin_collision_missing_chunks" \
  -v rapid_terrain_queue_ms="$rapid_terrain_queue_ms" \
  -v rapid_process_wall_ms="$rapid_process_wall_ms" \
  -v rapid_gpu_submit_ms="$rapid_gpu_submit_ms" \
  -v rapid_packet_queue_lag_ms="$rapid_packet_queue_lag_ms" \
  -v unload_status="$unload_status" \
  -v unload_policy_change_allowed="$unload_policy_change_allowed" \
  -v unload_candidate_policy_status="$unload_candidate_policy_status" \
  -v unload_default_runtime_change_allowed="$unload_default_runtime_change_allowed" \
  -v unload_max_chunk_unload_total="$unload_max_chunk_unload_total" \
  -v unload_max_chunk_unload_neighbor_refreshes="$unload_max_chunk_unload_neighbor_refreshes" \
  -v unload_max_chunk_unload="$unload_max_chunk_unload" \
  -v unload_max_packet_queue_lag_ms="$unload_max_packet_queue_lag_ms" \
  -v buffer_status="$buffer_status" \
  -v buffer_residency_pressure_class="$buffer_residency_pressure_class" \
  -v buffer_residency_proof_status="$buffer_residency_proof_status" \
  -v buffer_allocator_evidence_status="$buffer_allocator_evidence_status" \
  -v buffer_default_runtime_change_allowed="$buffer_default_runtime_change_allowed" \
  -v buffer_active_repack_allowed="$buffer_active_repack_allowed" \
  -v buffer_active_eviction_policy_change_allowed="$buffer_active_eviction_policy_change_allowed" \
  -v buffer_requires_external_profiler_before_default="$buffer_requires_external_profiler_before_default" \
  -v buffer_requires_mac_windows_validation="$buffer_requires_mac_windows_validation" \
  -v buffer_upload_fail_total="$buffer_upload_fail_total" \
  -v buffer_max_gpu_subchunks="$buffer_max_gpu_subchunks" \
  -v buffer_max_logical_draw_records="$buffer_max_logical_draw_records" \
  -v buffer_max_submitted_draw_records="$buffer_max_submitted_draw_records" \
  -v buffer_configured_buffer_budget_pct="$buffer_configured_buffer_budget_pct" \
  -v buffer_active_face_budget_pct="$buffer_active_face_budget_pct" \
  -v fallback_status="$fallback_status" \
  -v fallback_injection="$fallback_injection" \
  -v fallback_min_gpu_upload_failures="$fallback_min_gpu_upload_failures" \
  -v fallback_gpu_upload_fail="$fallback_gpu_upload_fail" \
  -v fallback_gpu_upload_fail_capacity="$fallback_gpu_upload_fail_capacity" \
  -v fallback_gpu_upload_fail_fragmented="$fallback_gpu_upload_fail_fragmented" \
  -v fallback_gpu_upload_fail_injected="$fallback_gpu_upload_fail_injected" \
  -v fallback_gpu_uploads="$fallback_gpu_uploads" \
  -v fallback_gpu_subchunks="$fallback_gpu_subchunks" \
  -v fallback_shadow_path="$fallback_shadow_path" \
  -v fallback_mesh_visible="$fallback_mesh_visible" \
  -v fallback_mesh_shadow_double="$fallback_mesh_shadow_double" \
  -v fallback_current_chunk_loaded="$fallback_current_chunk_loaded" \
  -v fallback_current_render_ready="$fallback_current_render_ready" \
  -v fallback_current_chunk_submeshes="$fallback_current_chunk_submeshes" \
  -v fallback_current_collision_ready="$fallback_current_collision_ready" \
  -v fallback_current_chunk_collision="$fallback_current_chunk_collision" \
  -v fallback_ground_misses="$fallback_ground_misses" \
  -v fallback_terrain_samples="$fallback_terrain_samples" \
  -v min_movement_cases="$MIN_MOVEMENT_CASES" \
  -v min_workload_cases="$MIN_WORKLOAD_CASES" \
  -v min_rapid_current_chunk_submeshes="$MIN_RAPID_CURRENT_CHUNK_SUBMESHES" \
  -v min_rapid_current_chunk_collision="$MIN_RAPID_CURRENT_CHUNK_COLLISION" \
  -v max_terrain_queue_ms="$MAX_TERRAIN_QUEUE_MS" \
  -v max_process_wall_p95_ms="$MAX_PROCESS_WALL_P95_MS" \
  -v max_gpu_compositor_submit_ms="$MAX_GPU_COMPOSITOR_SUBMIT_MS" \
  -v max_packet_queue_lag_ms="$MAX_PACKET_QUEUE_LAG_MS" \
  -v max_upload_fail="$MAX_UPLOAD_FAIL" \
  -v max_ground_misses="$MAX_GROUND_MISSES" \
  -v max_chunk_unload="$MAX_CHUNK_UNLOAD" \
  -v max_not_ready_cases="$MAX_NOT_READY_CASES" \
  -v max_expected_chunk_failures="$MAX_EXPECTED_CHUNK_FAILURES" \
  -v min_upload_fallback_failures="$MIN_UPLOAD_FALLBACK_FAILURES" \
  -v chunk_boundary_summary="$CHUNK_BOUNDARY_SUMMARY" \
  -v rapid_camera_turn_summary="$RAPID_CAMERA_TURN_SUMMARY" \
  -v chunk_unload_summary="$CHUNK_UNLOAD_SUMMARY" \
  -v buffer_residency_summary="$BUFFER_RESIDENCY_SUMMARY" \
  -v upload_fallback_summary="$UPLOAD_FALLBACK_SUMMARY" \
  -v client_source="$CLIENT_SOURCE_PATH" \
  -v server_world_source="$SERVER_WORLD_SOURCE_PATH" \
  -v server_world_test_source="$SERVER_WORLD_TEST_SOURCE_PATH" \
  -v server_network_source="$SERVER_NETWORK_SOURCE_PATH" \
  -v server_network_test_source="$SERVER_NETWORK_TEST_SOURCE_PATH" '
  function missing(value) {
    return value == "" || value == "missing" || value == "n/a"
  }
  function nonzero(value) {
    return !missing(value) && value + 0 != 0
  }
  function over_budget(value, budget) {
    return missing(value) || value + 0 > budget + 0
  }
  function under_min(value, minimum) {
    return missing(value) || value + 0 < minimum + 0
  }
  function set_fail(why) {
    if (status == "pass") {
      status = "fail"
      reason = why
    }
  }
  BEGIN {
    status = "pass"
    reason = "current_priority_contracts_hold"
    source_priority_contract_status = source_present_count + 0 == source_required_count + 0 ? "pass" : "fail"
    runtime_priority_status = "pass"
    proof_status = buffer_residency_proof_status == "full" ? "full" : "partial"
    if (source_priority_contract_status != "pass") {
      set_fail("source_priority_contracts")
    } else if (cb_status != "pass" || rapid_status != "pass" || unload_status != "pass" || buffer_status != "pass" || fallback_status != "pass") {
      set_fail("source_summary_status")
    } else if (fallback_injection != "1") {
      set_fail("upload_fallback_injection")
    } else if (under_min(fallback_gpu_upload_fail, min_upload_fallback_failures) || under_min(fallback_gpu_upload_fail_injected, min_upload_fallback_failures) || fallback_gpu_upload_fail + 0 != fallback_gpu_upload_fail_injected + 0) {
      set_fail("upload_fallback_expected_failure")
    } else if (nonzero(fallback_gpu_upload_fail_capacity) || nonzero(fallback_gpu_upload_fail_fragmented) || nonzero(fallback_gpu_uploads) || nonzero(fallback_gpu_subchunks)) {
      set_fail("upload_fallback_gpu_path")
    } else if (fallback_shadow_path != "arraymesh" || under_min(fallback_mesh_visible, 1) || under_min(fallback_mesh_shadow_double, 1)) {
      set_fail("upload_fallback_cpu_visual_path")
    } else if (fallback_current_chunk_loaded + 0 != 1 || fallback_current_render_ready + 0 != 1 || fallback_current_collision_ready + 0 != 1 || under_min(fallback_current_chunk_submeshes, 1) || under_min(fallback_current_chunk_collision, 1)) {
      set_fail("upload_fallback_current_readiness")
    } else if (fallback_ground_misses + 0 > max_ground_misses + 0 || under_min(fallback_terrain_samples, 1)) {
      set_fail("upload_fallback_ground_readiness")
    } else if (cb_completed_cases + 0 != cb_expected_cases + 0 || nonzero(cb_missing_cases) || nonzero(cb_failed_cases)) {
      set_fail("chunk_boundary_case_coverage")
    } else if (under_min(cb_movement_cases, min_movement_cases) || under_min(cb_workload_cases, min_workload_cases)) {
      set_fail("chunk_boundary_case_mix")
    } else if (cb_expected_chunk_failures + 0 > max_expected_chunk_failures + 0) {
      set_fail("expected_chunk_failures")
    } else if (cb_render_not_ready_cases + 0 > max_not_ready_cases + 0 || cb_collision_not_ready_cases + 0 > max_not_ready_cases + 0) {
      set_fail("current_readiness")
    } else if (rapid_current_chunk_loaded + 0 != 1 || rapid_current_render_ready + 0 != 1 || rapid_current_collision_ready + 0 != 1) {
      set_fail("rapid_current_readiness")
    } else if (under_min(rapid_current_chunk_submeshes, min_rapid_current_chunk_submeshes) || under_min(rapid_current_chunk_collision, min_rapid_current_chunk_collision)) {
      set_fail("rapid_current_chunk_content")
    } else if (cb_ground_misses + 0 > max_ground_misses + 0 || rapid_ground_misses + 0 > max_ground_misses + 0) {
      set_fail("ground_misses")
    } else if (cb_gpu_upload_fail + 0 > max_upload_fail + 0 || cb_gpu_upload_fail_capacity + 0 > max_upload_fail + 0 || cb_gpu_upload_fail_fragmented + 0 > max_upload_fail + 0 || rapid_gpu_upload_fail + 0 > max_upload_fail + 0 || rapid_gpu_upload_fail_capacity + 0 > max_upload_fail + 0 || rapid_gpu_upload_fail_fragmented + 0 > max_upload_fail + 0 || rapid_gpu_upload_fail_injected + 0 > max_upload_fail + 0 || buffer_upload_fail_total + 0 > max_upload_fail + 0) {
      set_fail("gpu_upload_fail")
    } else if (cb_max_chunk_unload_total + 0 > max_chunk_unload + 0 || cb_max_chunk_unload_neighbor_refreshes + 0 > max_chunk_unload + 0 || cb_max_chunk_unload + 0 > max_chunk_unload + 0 || rapid_chunk_unload_total + 0 > max_chunk_unload + 0 || rapid_chunk_unload_neighbor_refreshes + 0 > max_chunk_unload + 0 || rapid_chunk_unload_max + 0 > max_chunk_unload + 0 || unload_max_chunk_unload_total + 0 > max_chunk_unload + 0 || unload_max_chunk_unload_neighbor_refreshes + 0 > max_chunk_unload + 0 || unload_max_chunk_unload + 0 > max_chunk_unload + 0) {
      set_fail("chunk_unload_budget")
    } else if (over_budget(cb_max_packet_queue_lag_ms, max_packet_queue_lag_ms) || over_budget(rapid_packet_queue_lag_ms, max_packet_queue_lag_ms) || over_budget(unload_max_packet_queue_lag_ms, max_packet_queue_lag_ms)) {
      set_fail("packet_queue_lag_budget")
    } else if (over_budget(cb_max_terrain_queue_ms, max_terrain_queue_ms) || over_budget(rapid_terrain_queue_ms, max_terrain_queue_ms)) {
      set_fail("terrain_queue_budget")
    } else if (over_budget(cb_max_process_wall_p95_ms, max_process_wall_p95_ms) || over_budget(rapid_process_wall_ms, max_process_wall_p95_ms)) {
      set_fail("process_wall_budget")
    } else if (over_budget(cb_max_gpu_compositor_submit_ms, max_gpu_compositor_submit_ms) || over_budget(rapid_gpu_submit_ms, max_gpu_compositor_submit_ms)) {
      set_fail("gpu_compositor_submit_budget")
    } else if (unload_default_runtime_change_allowed != "0" || unload_policy_change_allowed != "0" || unload_candidate_policy_status != "deferred") {
      set_fail("unload_policy_not_deferred")
    } else if (buffer_default_runtime_change_allowed != "0" || buffer_active_repack_allowed != "0" || buffer_active_eviction_policy_change_allowed != "0") {
      set_fail("buffer_policy_not_deferred")
    } else if (buffer_requires_external_profiler_before_default != "1" || buffer_requires_mac_windows_validation != "1") {
      set_fail("missing_external_validation_blocker")
    }
    if (status != "pass") {
      runtime_priority_status = "fail"
      if (reason == "source_priority_contracts") {
        runtime_priority_status = "not_checked"
      }
    }
    printf("gpu_streaming_priority_audit status=%s reason=%s source_priority_contract_status=%s runtime_priority_status=%s upload_fallback_status=%s priority_proof_status=%s source_contracts_present=%d source_contracts_required=%d scheduler_change_allowed=0 default_runtime_change_allowed=0 candidate_scheduler_status=deferred max_packet_queue_lag_ms=%s rapid_packet_queue_lag_ms=%s max_popin_missing_chunks=%s max_popin_collision_missing_chunks=%s rapid_popin_missing_chunks=%s rapid_popin_collision_missing_chunks=%s max_chunk_unload_total=%s max_chunk_unload_neighbor_refreshes=%s max_chunk_unload=%s rapid_chunk_unload_total=%s rapid_chunk_unload_neighbor_refreshes=%s rapid_chunk_unload_max=%s current_chunk=%s current_chunk_loaded=%s current_render_ready=%s current_chunk_submeshes=%s current_collision_ready=%s current_chunk_collision=%s max_terrain_queue_ms=%s rapid_terrain_queue_ms=%s max_process_wall_p95_ms=%s rapid_process_wall_p95_ms=%s max_gpu_compositor_submit_ms=%s rapid_gpu_compositor_submit_ms=%s gpu_upload_fail=%s rapid_gpu_upload_fail=%s buffer_upload_fail_total=%s upload_fallback_expected_failures=%s upload_fallback_injected_failures=%s upload_fallback_shadow_path=%s upload_fallback_mesh_visible=%s upload_fallback_mesh_shadow_double=%s ground_misses=%s rapid_ground_misses=%s residency_pressure_class=%s residency_proof_status=%s allocator_evidence_status=%s configured_buffer_budget_pct=%s active_face_budget_pct=%s max_gpu_subchunks=%s max_logical_draw_records=%s max_submitted_draw_records=%s unload_policy_change_allowed=%s unload_candidate_policy_status=%s active_repack_allowed=%s active_eviction_policy_change_allowed=%s local_fps_status=report_only godot_gpu_timestamp_status=report_only external_profile_status=pending_external_profiler requires_external_profiler_before_default=1 requires_mac_windows_validation=1 chunk_boundary_summary=%s rapid_camera_turn_summary=%s chunk_unload_summary=%s buffer_residency_summary=%s upload_fallback_summary=%s client_source=%s server_world_source=%s server_world_test_source=%s server_network_source=%s server_network_test_source=%s\n", status, reason, source_priority_contract_status, runtime_priority_status, fallback_status, proof_status, source_present_count, source_required_count, cb_max_packet_queue_lag_ms, rapid_packet_queue_lag_ms, cb_max_popin_missing_chunks, cb_max_popin_collision_missing_chunks, rapid_popin_missing_chunks, rapid_popin_collision_missing_chunks, cb_max_chunk_unload_total, cb_max_chunk_unload_neighbor_refreshes, cb_max_chunk_unload, rapid_chunk_unload_total, rapid_chunk_unload_neighbor_refreshes, rapid_chunk_unload_max, rapid_current_chunk, rapid_current_chunk_loaded, rapid_current_render_ready, rapid_current_chunk_submeshes, rapid_current_collision_ready, rapid_current_chunk_collision, cb_max_terrain_queue_ms, rapid_terrain_queue_ms, cb_max_process_wall_p95_ms, rapid_process_wall_ms, cb_max_gpu_compositor_submit_ms, rapid_gpu_submit_ms, cb_gpu_upload_fail, rapid_gpu_upload_fail, buffer_upload_fail_total, fallback_gpu_upload_fail, fallback_gpu_upload_fail_injected, fallback_shadow_path, fallback_mesh_visible, fallback_mesh_shadow_double, cb_ground_misses, rapid_ground_misses, buffer_residency_pressure_class, buffer_residency_proof_status, buffer_allocator_evidence_status, buffer_configured_buffer_budget_pct, buffer_active_face_budget_pct, buffer_max_gpu_subchunks, buffer_max_logical_draw_records, buffer_max_submitted_draw_records, unload_policy_change_allowed, unload_candidate_policy_status, buffer_active_repack_allowed, buffer_active_eviction_policy_change_allowed, chunk_boundary_summary, rapid_camera_turn_summary, chunk_unload_summary, buffer_residency_summary, upload_fallback_summary, client_source, server_world_source, server_world_test_source, server_network_source, server_network_test_source)
    printf("gpu_streaming_priority_source_contract status=%s present=%d required=%d client_max_mesh_jobs=%s client_max_collision_rebuilds=%s client_pop_next_mesh_queue=%s client_collision_backpressure_fn=%s client_player_fifo=%s client_initial_hint=%s client_collision_backpressure_test=%s client_visible_render_wait=%s client_upload_fallback_test=%s client_current_chunk_counts=%s client_popin_probe=%s server_chunks_ordered=%s server_direction_score=%s server_current_first_test=%s server_direction_tiebreak_test=%s server_bootstrap_default=%s server_bootstrap_configured=%s server_bootstrap_current_only_test=%s client_source=%s server_world_source=%s server_world_test_source=%s server_network_source=%s server_network_test_source=%s\n", source_priority_contract_status, source_present_count, source_required_count, client_max_mesh_jobs, client_max_collision_rebuilds, client_pop_next_mesh_queue, client_collision_backpressure_fn, client_player_fifo, client_initial_hint, client_collision_backpressure_test, client_visible_render_wait, client_upload_fallback_test, client_current_chunk_counts, client_popin_probe, server_chunks_ordered, server_direction_score, server_current_first_test, server_direction_tiebreak_test, server_bootstrap_default, server_bootstrap_configured, server_bootstrap_current_only_test, client_source, server_world_source, server_world_test_source, server_network_source, server_network_test_source)
    printf("gpu_streaming_priority_runtime name=chunk_boundary status=%s expected_cases=%s completed_cases=%s movement_cases=%s workload_cases=%s expected_chunk_failures=%s render_not_ready_cases=%s collision_not_ready_cases=%s ground_misses=%s gpu_upload_fail=%s max_packet_queue_lag_ms=%s max_chunk_unload_total=%s max_chunk_unload_neighbor_refreshes=%s max_chunk_unload=%s max_chunk_unload_grace_kept=%s max_popin_missing_chunks=%s max_popin_collision_missing_chunks=%s max_terrain_queue_ms=%s max_process_wall_p95_ms=%s max_gpu_compositor_submit_ms=%s summary=%s\n", cb_status, cb_expected_cases, cb_completed_cases, cb_movement_cases, cb_workload_cases, cb_expected_chunk_failures, cb_render_not_ready_cases, cb_collision_not_ready_cases, cb_ground_misses, cb_gpu_upload_fail, cb_max_packet_queue_lag_ms, cb_max_chunk_unload_total, cb_max_chunk_unload_neighbor_refreshes, cb_max_chunk_unload, cb_max_chunk_unload_grace_kept, cb_max_popin_missing_chunks, cb_max_popin_collision_missing_chunks, cb_max_terrain_queue_ms, cb_max_process_wall_p95_ms, cb_max_gpu_compositor_submit_ms, chunk_boundary_summary)
    printf("gpu_streaming_priority_runtime name=rapid_camera_turn status=%s current_chunk=%s current_chunk_loaded=%s current_render_ready=%s current_chunk_submeshes=%s current_collision_ready=%s current_chunk_collision=%s ground_misses=%s gpu_upload_fail=%s packet_queue_lag_ms=%s chunk_unload_total=%s chunk_unload_neighbor_refreshes=%s chunk_unload_max=%s popin_missing_chunks=%s popin_collision_missing_chunks=%s terrain_queue_ms=%s process_wall_p95_ms=%s gpu_compositor_submit_ms=%s summary=%s\n", rapid_status, rapid_current_chunk, rapid_current_chunk_loaded, rapid_current_render_ready, rapid_current_chunk_submeshes, rapid_current_collision_ready, rapid_current_chunk_collision, rapid_ground_misses, rapid_gpu_upload_fail, rapid_packet_queue_lag_ms, rapid_chunk_unload_total, rapid_chunk_unload_neighbor_refreshes, rapid_chunk_unload_max, rapid_popin_missing_chunks, rapid_popin_collision_missing_chunks, rapid_terrain_queue_ms, rapid_process_wall_ms, rapid_gpu_submit_ms, rapid_camera_turn_summary)
    printf("gpu_streaming_priority_runtime name=chunk_unload status=%s policy_change_allowed=%s candidate_policy_status=%s default_runtime_change_allowed=%s max_chunk_unload_total=%s max_chunk_unload_neighbor_refreshes=%s max_chunk_unload=%s max_packet_queue_lag_ms=%s summary=%s\n", unload_status, unload_policy_change_allowed, unload_candidate_policy_status, unload_default_runtime_change_allowed, unload_max_chunk_unload_total, unload_max_chunk_unload_neighbor_refreshes, unload_max_chunk_unload, unload_max_packet_queue_lag_ms, chunk_unload_summary)
    printf("gpu_streaming_priority_runtime name=buffer_residency status=%s residency_pressure_class=%s residency_proof_status=%s allocator_evidence_status=%s default_runtime_change_allowed=%s active_repack_allowed=%s active_eviction_policy_change_allowed=%s upload_fail_total=%s max_gpu_subchunks=%s max_logical_draw_records=%s max_submitted_draw_records=%s configured_buffer_budget_pct=%s active_face_budget_pct=%s requires_external_profiler_before_default=%s requires_mac_windows_validation=%s summary=%s\n", buffer_status, buffer_residency_pressure_class, buffer_residency_proof_status, buffer_allocator_evidence_status, buffer_default_runtime_change_allowed, buffer_active_repack_allowed, buffer_active_eviction_policy_change_allowed, buffer_upload_fail_total, buffer_max_gpu_subchunks, buffer_max_logical_draw_records, buffer_max_submitted_draw_records, buffer_configured_buffer_budget_pct, buffer_active_face_budget_pct, buffer_requires_external_profiler_before_default, buffer_requires_mac_windows_validation, buffer_residency_summary)
    printf("gpu_streaming_priority_runtime name=upload_fallback status=%s injection=%s min_gpu_upload_failures=%s gpu_upload_fail=%s gpu_upload_fail_capacity=%s gpu_upload_fail_fragmented=%s gpu_upload_fail_injected=%s gpu_uploads=%s gpu_subchunks=%s shadow_path=%s mesh_visible=%s mesh_shadow_double=%s current_chunk_loaded=%s current_render_ready=%s current_chunk_submeshes=%s current_collision_ready=%s current_chunk_collision=%s ground_misses=%s terrain_samples=%s summary=%s\n", fallback_status, fallback_injection, fallback_min_gpu_upload_failures, fallback_gpu_upload_fail, fallback_gpu_upload_fail_capacity, fallback_gpu_upload_fail_fragmented, fallback_gpu_upload_fail_injected, fallback_gpu_uploads, fallback_gpu_subchunks, fallback_shadow_path, fallback_mesh_visible, fallback_mesh_shadow_double, fallback_current_chunk_loaded, fallback_current_render_ready, fallback_current_chunk_submeshes, fallback_current_collision_ready, fallback_current_chunk_collision, fallback_ground_misses, fallback_terrain_samples, upload_fallback_summary)
    if (status != "pass") {
      exit 1
    }
  }
' > "$SUMMARY_PATH" || {
  cat "$SUMMARY_PATH" >&2 || true
  fail "streaming priority audit did not pass"
}

cat "$SUMMARY_PATH"
echo "GPU streaming priority audit artifacts: $OUT_DIR"
