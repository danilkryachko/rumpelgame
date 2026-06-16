#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/gpu_streaming_scheduler_prototype_current"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

SUMMARY_PATH="$OUT_DIR/gpu-streaming-scheduler-prototype-summary.txt"
PRIORITY_AUDIT_SUMMARY="${RUMPELMC_GPU_STREAMING_SCHEDULER_PRIORITY_AUDIT_SUMMARY:-"$ROOT_DIR/logs/gpu_streaming_priority_audit_current/gpu-streaming-priority-audit-summary.txt"}"
CLIENT_SOURCE_PATH="${RUMPELMC_GPU_STREAMING_SCHEDULER_CLIENT_SOURCE:-"$ROOT_DIR/client/rust_ext/src/lib.rs"}"

mkdir -p "$OUT_DIR"

fail() {
  echo "gpu_streaming_scheduler_prototype: $*" >&2
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

source_token_present_in() {
  path="$1"
  token="$2"
  if grep -Fq "$token" "$path"; then
    printf '1\n'
  else
    printf '0\n'
  fi
}

PRIORITY_AUDIT_SUMMARY="$(normalize_path "$PRIORITY_AUDIT_SUMMARY")"
CLIENT_SOURCE_PATH="$(normalize_path "$CLIENT_SOURCE_PATH")"

if [ ! -s "$PRIORITY_AUDIT_SUMMARY" ]; then
  printf 'gpu_streaming_scheduler_prototype status=fail reason=missing_priority_audit source_contract_status=missing priority_audit_status=missing scheduler_change_allowed=0 default_runtime_change_allowed=0 candidate_scheduler_status=prototype_only priority_audit_summary=%s client_source=%s\n' \
    "$PRIORITY_AUDIT_SUMMARY" "$CLIENT_SOURCE_PATH" > "$SUMMARY_PATH"
  cat "$SUMMARY_PATH" >&2
  fail "missing priority audit summary $PRIORITY_AUDIT_SUMMARY"
fi

if [ ! -s "$CLIENT_SOURCE_PATH" ]; then
  printf 'gpu_streaming_scheduler_prototype status=fail reason=missing_client_source source_contract_status=missing priority_audit_status=%s scheduler_change_allowed=0 default_runtime_change_allowed=0 candidate_scheduler_status=prototype_only priority_audit_summary=%s client_source=%s\n' \
    "$(field_metric status "$PRIORITY_AUDIT_SUMMARY")" "$PRIORITY_AUDIT_SUMMARY" "$CLIENT_SOURCE_PATH" > "$SUMMARY_PATH"
  cat "$SUMMARY_PATH" >&2
  fail "missing client source $CLIENT_SOURCE_PATH"
fi

priority_status="$(field_metric status "$PRIORITY_AUDIT_SUMMARY")"
priority_scheduler_change_allowed="$(field_metric scheduler_change_allowed "$PRIORITY_AUDIT_SUMMARY")"
priority_default_runtime_change_allowed="$(field_metric default_runtime_change_allowed "$PRIORITY_AUDIT_SUMMARY")"
priority_runtime_status="$(field_metric runtime_priority_status "$PRIORITY_AUDIT_SUMMARY")"
priority_candidate_scheduler_status="$(field_metric candidate_scheduler_status "$PRIORITY_AUDIT_SUMMARY")"

client_env_const="$(source_token_present_in "$CLIENT_SOURCE_PATH" 'const CLIENT_STREAMING_SCHEDULER_ENV: &str = "RUMPELMC_CLIENT_STREAMING_SCHEDULER";')"
client_mode_enum="$(source_token_present_in "$CLIENT_SOURCE_PATH" 'enum ClientStreamingSchedulerMode')"
client_default_nearest="$(source_token_present_in "$CLIENT_SOURCE_PATH" 'Self::Nearest')"
client_preview_mode="$(source_token_present_in "$CLIENT_SOURCE_PATH" 'DirectionalTiePreview')"
client_active_mode="$(source_token_present_in "$CLIENT_SOURCE_PATH" 'DirectionalTie')"
client_pop_fn="$(source_token_present_in "$CLIENT_SOURCE_PATH" 'fn pop_next_streaming_queue_key(')"
client_direction_score="$(source_token_present_in "$CLIENT_SOURCE_PATH" 'fn subchunk_direction_score(')"
client_player_direction="$(source_token_present_in "$CLIENT_SOURCE_PATH" 'fn player_chunk_direction(')"
client_preview_test="$(source_token_present_in "$CLIENT_SOURCE_PATH" 'fn streaming_scheduler_preview_keeps_fifo_pop_and_reports_mismatch()')"
client_active_test="$(source_token_present_in "$CLIENT_SOURCE_PATH" 'fn streaming_scheduler_active_changes_only_equal_distance_ties()')"
client_no_direction_test="$(source_token_present_in "$CLIENT_SOURCE_PATH" 'fn streaming_scheduler_without_direction_falls_back_to_fifo()')"
client_backpressure_test="$(source_token_present_in "$CLIENT_SOURCE_PATH" 'fn mesh_queue_waits_when_collision_refresh_rebuilt_this_frame()')"
client_backpressure_fn="$(source_token_present_in "$CLIENT_SOURCE_PATH" 'fn should_process_mesh_queue_after_collision_refresh(collision_rebuilds: usize) -> bool')"
client_backpressure_body="$(source_token_present_in "$CLIENT_SOURCE_PATH" 'collision_rebuilds == 0')"
client_mesh_cap="$(source_token_present_in "$CLIENT_SOURCE_PATH" 'const MAX_MESH_JOBS_PER_FRAME: usize = 1;')"
client_collision_cap="$(source_token_present_in "$CLIENT_SOURCE_PATH" 'const MAX_COLLISION_REFRESH_REBUILDS_PER_FRAME: usize = 1;')"
client_perf_mode="$(source_token_present_in "$CLIENT_SOURCE_PATH" 'stream_scheduler_mode=')"
client_perf_active="$(source_token_present_in "$CLIENT_SOURCE_PATH" 'stream_scheduler_active=')"
client_perf_preview="$(source_token_present_in "$CLIENT_SOURCE_PATH" 'stream_scheduler_preview_mismatch=')"
client_perf_ties="$(source_token_present_in "$CLIENT_SOURCE_PATH" 'mesh_scheduler_directional_ties=')"
client_perf_collision_ties="$(source_token_present_in "$CLIENT_SOURCE_PATH" 'collision_scheduler_directional_ties=')"

source_required_count=21
source_present_count=$((client_env_const + client_mode_enum + client_default_nearest + client_preview_mode + client_active_mode + client_pop_fn + client_direction_score + client_player_direction + client_preview_test + client_active_test + client_no_direction_test + client_backpressure_test + client_backpressure_fn + client_backpressure_body + client_mesh_cap + client_collision_cap + client_perf_mode + client_perf_active + client_perf_preview + client_perf_ties + client_perf_collision_ties))

status="pass"
reason="prototype_default_off"
source_contract_status="pass"
if [ "$source_present_count" -ne "$source_required_count" ]; then
  status="fail"
  reason="source_contracts"
  source_contract_status="fail"
elif [ "$priority_status" != "pass" ]; then
  status="fail"
  reason="priority_audit_status"
elif [ "$priority_runtime_status" != "pass" ]; then
  status="fail"
  reason="runtime_priority_status"
elif [ "$priority_scheduler_change_allowed" != "0" ]; then
  status="fail"
  reason="priority_scheduler_change_allowed"
elif [ "$priority_default_runtime_change_allowed" != "0" ]; then
  status="fail"
  reason="priority_default_runtime_change_allowed"
elif [ "$priority_candidate_scheduler_status" != "deferred" ]; then
  status="fail"
  reason="priority_candidate_scheduler_status"
fi

{
  printf 'gpu_streaming_scheduler_prototype status=%s reason=%s source_contract_status=%s source_contracts_present=%d source_contracts_required=%d priority_audit_status=%s priority_runtime_status=%s priority_scheduler_change_allowed=%s priority_default_runtime_change_allowed=%s priority_candidate_scheduler_status=%s stream_scheduler_env=RUMPELMC_CLIENT_STREAMING_SCHEDULER default_scheduler_mode=nearest stream_scheduler_active_default=0 preview_selection_change_allowed=0 active_selection_changes_equal_distance_only=1 collision_backpressure_preserved=%s max_mesh_jobs_per_frame=1 max_collision_rebuilds_per_frame=1 scheduler_change_allowed=0 default_runtime_change_allowed=0 candidate_scheduler_status=prototype_only external_profile_status=pending_external_profiler requires_external_profiler_before_default=1 requires_mac_windows_validation=1 priority_audit_summary=%s client_source=%s\n' \
    "$status" "$reason" "$source_contract_status" "$source_present_count" "$source_required_count" "$priority_status" "$priority_runtime_status" "$priority_scheduler_change_allowed" "$priority_default_runtime_change_allowed" "$priority_candidate_scheduler_status" "$client_backpressure_body" "$(relative_path "$PRIORITY_AUDIT_SUMMARY")" "$(relative_path "$CLIENT_SOURCE_PATH")"
  printf 'gpu_streaming_scheduler_source_contract status=%s present=%d required=%d client_env_const=%s client_mode_enum=%s client_default_nearest=%s client_preview_mode=%s client_active_mode=%s client_pop_fn=%s client_direction_score=%s client_player_direction=%s client_preview_test=%s client_active_test=%s client_no_direction_test=%s client_backpressure_test=%s client_backpressure_fn=%s client_backpressure_body=%s client_mesh_cap=%s client_collision_cap=%s client_perf_mode=%s client_perf_active=%s client_perf_preview=%s client_perf_ties=%s client_perf_collision_ties=%s client_source=%s\n' \
    "$source_contract_status" "$source_present_count" "$source_required_count" "$client_env_const" "$client_mode_enum" "$client_default_nearest" "$client_preview_mode" "$client_active_mode" "$client_pop_fn" "$client_direction_score" "$client_player_direction" "$client_preview_test" "$client_active_test" "$client_no_direction_test" "$client_backpressure_test" "$client_backpressure_fn" "$client_backpressure_body" "$client_mesh_cap" "$client_collision_cap" "$client_perf_mode" "$client_perf_active" "$client_perf_preview" "$client_perf_ties" "$client_perf_collision_ties" "$(relative_path "$CLIENT_SOURCE_PATH")"
} > "$SUMMARY_PATH"

if [ "$status" != "pass" ]; then
  cat "$SUMMARY_PATH" >&2
  fail "streaming scheduler prototype preflight did not pass"
fi

cat "$SUMMARY_PATH"
echo "GPU streaming scheduler prototype artifacts: $OUT_DIR"
