#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/server_session_monitoring_contract_current"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

SUMMARY_PATH="$OUT_DIR/server-session-monitoring-contract-summary.txt"
METRICS_PATH="$OUT_DIR/server-session-monitoring-metrics.txt"
RUN_LOG="$OUT_DIR/server-scalability-pass-run.txt"
DESIGN_DOC="${RUMPELMC_SERVER_SESSION_MONITORING_DOC:-"$ROOT_DIR/docs/SERVER_SESSION_MONITORING_CONTRACT.md"}"
SCALABILITY_SCRIPT="${RUMPELMC_SERVER_SESSION_MONITORING_SCALABILITY_SCRIPT:-"$ROOT_DIR/scripts/server_scalability_pass_gate.sh"}"
SCALABILITY_SUMMARY="${RUMPELMC_SERVER_SESSION_MONITORING_SCALABILITY_SUMMARY:-"$ROOT_DIR/logs/server_scalability_pass_current/server-scalability-pass-summary.txt"}"
LIFECYCLE_SUMMARY="${RUMPELMC_SERVER_SESSION_MONITORING_LIFECYCLE_SUMMARY:-"$ROOT_DIR/logs/server_connection_lifecycle_current/server-connection-lifecycle-summary.txt"}"
OBSERVABILITY_SUMMARY="${RUMPELMC_SERVER_SESSION_MONITORING_OBSERVABILITY_SUMMARY:-"$ROOT_DIR/logs/observability_logs_cleanup_current/observability-logs-cleanup-summary.txt"}"
RUN_SCALABILITY="${RUMPELMC_SERVER_SESSION_MONITORING_RUN_SCALABILITY:-1}"

mkdir -p "$OUT_DIR"

fail() {
  echo "server_session_monitoring_contract_gate: $*" >&2
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

relative_path() {
  path="$1"
  case "$path" in
    "$ROOT_DIR"/*) printf '%s\n' "${path#"$ROOT_DIR"/}" ;;
    */logs/*) printf 'logs/%s\n' "${path#*/logs/}" ;;
    *) printf '%s\n' "$path" ;;
  esac
}

case "$RUN_SCALABILITY" in
  0|1) ;;
  *) fail "RUMPELMC_SERVER_SESSION_MONITORING_RUN_SCALABILITY must be 0 or 1" ;;
esac

test -x "$SCALABILITY_SCRIPT" || fail "missing executable scalability script $SCALABILITY_SCRIPT"
test -s "$DESIGN_DOC" || fail "missing design doc $DESIGN_DOC"

for token in \
  'Monitoring Contract' \
  'Session Metrics' \
  'Metrics Export' \
  'Trust Boundary' \
  'Compatibility Rules'; do
  require_token "$DESIGN_DOC" "$token"
done

if [ "$RUN_SCALABILITY" = "1" ]; then
  scalability_out_dir="$(dirname -- "$SCALABILITY_SUMMARY")"
  sh "$SCALABILITY_SCRIPT" "$scalability_out_dir" > "$RUN_LOG" 2>&1 || {
    cat "$RUN_LOG" >&2 || true
    fail "server scalability pass gate failed"
  }
fi

for path in "$SCALABILITY_SUMMARY" "$LIFECYCLE_SUMMARY" "$OBSERVABILITY_SUMMARY"; do
  test -s "$path" || fail "missing required input $path"
done

scalability_status="$(field_metric status "$SCALABILITY_SUMMARY")"
scalability_guard="$(field_metric scalability_status "$SCALABILITY_SUMMARY")"
resource_profile_status="$(field_metric resource_profile_status "$SCALABILITY_SUMMARY")"
admission_policy="$(field_metric admission_policy "$SCALABILITY_SUMMARY")"
disconnect_cleanup_status="$(field_metric disconnect_cleanup_status "$SCALABILITY_SUMMARY")"
live_load_status="$(field_metric live_load_status "$SCALABILITY_SUMMARY")"
live_detail_status="$(field_metric live_detail_status "$SCALABILITY_SUMMARY")"
live_detail_clients="$(field_metric live_detail_clients "$SCALABILITY_SUMMARY")"
live_resource_samples="$(field_metric live_resource_samples "$SCALABILITY_SUMMARY")"
live_resource_rss_kb_max="$(field_metric live_resource_rss_kb_max "$SCALABILITY_SUMMARY")"
live_resource_cpu_pct_max="$(field_metric live_resource_cpu_pct_max "$SCALABILITY_SUMMARY")"
broader_live_status="$(field_metric broader_live_load_status "$SCALABILITY_SUMMARY")"
broader_live_clients="$(field_metric broader_live_clients "$SCALABILITY_SUMMARY")"
broader_live_resource_samples="$(field_metric broader_live_resource_samples "$SCALABILITY_SUMMARY")"
broader_live_resource_rss_kb_max="$(field_metric broader_live_resource_rss_kb_max "$SCALABILITY_SUMMARY")"
broader_live_resource_cpu_pct_max="$(field_metric broader_live_resource_cpu_pct_max "$SCALABILITY_SUMMARY")"
repeat_smoke_status="$(field_metric repeat_smoke_status "$SCALABILITY_SUMMARY")"
repeat_smoke_repeats="$(field_metric repeat_smoke_repeats "$SCALABILITY_SUMMARY")"
repeat_smoke_clients="$(field_metric repeat_smoke_clients "$SCALABILITY_SUMMARY")"
repeat_smoke_resource_samples="$(field_metric repeat_smoke_resource_samples "$SCALABILITY_SUMMARY")"
repeat_smoke_max_rss_kb="$(field_metric repeat_smoke_max_rss_kb "$SCALABILITY_SUMMARY")"
repeat_smoke_max_cpu_pct="$(field_metric repeat_smoke_max_cpu_pct "$SCALABILITY_SUMMARY")"
admission_limit_status="$(field_metric admission_limit_smoke_status "$SCALABILITY_SUMMARY")"
admission_matrix_status="$(field_metric admission_matrix_status "$SCALABILITY_SUMMARY")"
admission_matrix_limits_checked="$(field_metric admission_matrix_limits_checked "$SCALABILITY_SUMMARY")"
admission_matrix_total_rejected="$(field_metric admission_matrix_total_rejected "$SCALABILITY_SUMMARY")"
scalability_lifecycle_status="$(field_metric connection_lifecycle_status "$SCALABILITY_SUMMARY")"
scalability_close_failures="$(field_metric connection_lifecycle_close_failures "$SCALABILITY_SUMMARY")"
scalability_accept_failures="$(field_metric connection_lifecycle_accept_failures "$SCALABILITY_SUMMARY")"
scalability_missing_active_client_fields="$(field_metric connection_lifecycle_missing_active_client_fields "$SCALABILITY_SUMMARY")"
active_protocol_change="$(field_metric active_protocol_change "$SCALABILITY_SUMMARY")"

lifecycle_status="$(field_metric status "$LIFECYCLE_SUMMARY")"
connected_clients="$(field_metric connected_clients "$LIFECYCLE_SUMMARY")"
rejected_clients="$(field_metric rejected_clients "$LIFECYCLE_SUMMARY")"
disconnected_clients="$(field_metric disconnected_clients "$LIFECYCLE_SUMMARY")"
packet_error_disconnects="$(field_metric packet_error_disconnects "$LIFECYCLE_SUMMARY")"
eof_disconnects="$(field_metric eof_disconnects "$LIFECYCLE_SUMMARY")"
timeout_disconnects="$(field_metric timeout_disconnects "$LIFECYCLE_SUMMARY")"
close_failures="$(field_metric close_failures "$LIFECYCLE_SUMMARY")"
accept_failures="$(field_metric accept_failures "$LIFECYCLE_SUMMARY")"
max_active_clients="$(field_metric max_logged_active_clients "$LIFECYCLE_SUMMARY")"
max_configured_clients="$(field_metric max_logged_max_clients "$LIFECYCLE_SUMMARY")"
missing_active_client_fields="$(field_metric missing_active_client_fields "$LIFECYCLE_SUMMARY")"

observability_status="$(field_metric status "$OBSERVABILITY_SUMMARY")"
observability_error_scan="$(field_metric error_scan "$OBSERVABILITY_SUMMARY")"
observability_index="$(field_metric index "$OBSERVABILITY_SUMMARY")"

test -s "$observability_index" || fail "missing observability index $observability_index"

scalability_rel="$(relative_path "$SCALABILITY_SUMMARY")"
lifecycle_rel="$(relative_path "$LIFECYCLE_SUMMARY")"
index_scalability_status="missing"
index_lifecycle_status="missing"
if grep -F "path=$scalability_rel " "$observability_index" >/dev/null 2>&1; then
  index_scalability_status="present"
fi
if grep -F "path=$lifecycle_rel " "$observability_index" >/dev/null 2>&1; then
  index_lifecycle_status="present"
fi

{
  printf 'server_session_connected_clients %s\n' "${connected_clients:-0}"
  printf 'server_session_rejected_clients %s\n' "${rejected_clients:-0}"
  printf 'server_session_disconnected_clients %s\n' "${disconnected_clients:-0}"
  printf 'server_session_packet_error_disconnects %s\n' "${packet_error_disconnects:-0}"
  printf 'server_session_eof_disconnects %s\n' "${eof_disconnects:-0}"
  printf 'server_session_timeout_disconnects %s\n' "${timeout_disconnects:-0}"
  printf 'server_session_close_failures %s\n' "${close_failures:-0}"
  printf 'server_session_accept_failures %s\n' "${accept_failures:-0}"
  printf 'server_session_max_active_clients %s\n' "${max_active_clients:-0}"
  printf 'server_session_max_configured_clients %s\n' "${max_configured_clients:-0}"
  printf 'server_session_missing_active_client_fields %s\n' "${missing_active_client_fields:-0}"
  printf 'server_session_live_detail_clients %s\n' "${live_detail_clients:-0}"
  printf 'server_session_live_resource_samples %s\n' "${live_resource_samples:-0}"
  printf 'server_session_live_resource_rss_kb_max %s\n' "${live_resource_rss_kb_max:-0}"
  printf 'server_session_live_resource_cpu_pct_max %s\n' "${live_resource_cpu_pct_max:-0}"
  printf 'server_session_broader_live_clients %s\n' "${broader_live_clients:-0}"
  printf 'server_session_broader_live_resource_samples %s\n' "${broader_live_resource_samples:-0}"
  printf 'server_session_broader_live_resource_rss_kb_max %s\n' "${broader_live_resource_rss_kb_max:-0}"
  printf 'server_session_broader_live_resource_cpu_pct_max %s\n' "${broader_live_resource_cpu_pct_max:-0}"
  printf 'server_session_repeat_smoke_repeats %s\n' "${repeat_smoke_repeats:-0}"
  printf 'server_session_repeat_smoke_clients %s\n' "${repeat_smoke_clients:-0}"
  printf 'server_session_repeat_smoke_resource_samples %s\n' "${repeat_smoke_resource_samples:-0}"
  printf 'server_session_repeat_smoke_max_rss_kb %s\n' "${repeat_smoke_max_rss_kb:-0}"
  printf 'server_session_repeat_smoke_max_cpu_pct %s\n' "${repeat_smoke_max_cpu_pct:-0}"
  printf 'server_session_admission_matrix_limits_checked %s\n' "${admission_matrix_limits_checked:-0}"
  printf 'server_session_admission_matrix_total_rejected %s\n' "${admission_matrix_total_rejected:-0}"
} > "$METRICS_PATH"

awk \
  -v scalability_status="${scalability_status:-missing}" \
  -v scalability_guard="${scalability_guard:-missing}" \
  -v resource_profile_status="${resource_profile_status:-missing}" \
  -v admission_policy="${admission_policy:-missing}" \
  -v disconnect_cleanup_status="${disconnect_cleanup_status:-missing}" \
  -v live_load_status="${live_load_status:-missing}" \
  -v live_detail_status="${live_detail_status:-missing}" \
  -v live_detail_clients="${live_detail_clients:-0}" \
  -v live_resource_samples="${live_resource_samples:-0}" \
  -v live_resource_rss_kb_max="${live_resource_rss_kb_max:-0}" \
  -v live_resource_cpu_pct_max="${live_resource_cpu_pct_max:-0}" \
  -v broader_live_status="${broader_live_status:-missing}" \
  -v broader_live_clients="${broader_live_clients:-0}" \
  -v broader_live_resource_samples="${broader_live_resource_samples:-0}" \
  -v broader_live_resource_rss_kb_max="${broader_live_resource_rss_kb_max:-0}" \
  -v broader_live_resource_cpu_pct_max="${broader_live_resource_cpu_pct_max:-0}" \
  -v repeat_smoke_status="${repeat_smoke_status:-missing}" \
  -v repeat_smoke_repeats="${repeat_smoke_repeats:-0}" \
  -v repeat_smoke_clients="${repeat_smoke_clients:-0}" \
  -v repeat_smoke_resource_samples="${repeat_smoke_resource_samples:-0}" \
  -v repeat_smoke_max_rss_kb="${repeat_smoke_max_rss_kb:-0}" \
  -v repeat_smoke_max_cpu_pct="${repeat_smoke_max_cpu_pct:-0}" \
  -v admission_limit_status="${admission_limit_status:-missing}" \
  -v admission_matrix_status="${admission_matrix_status:-missing}" \
  -v admission_matrix_limits_checked="${admission_matrix_limits_checked:-0}" \
  -v admission_matrix_total_rejected="${admission_matrix_total_rejected:-0}" \
  -v scalability_lifecycle_status="${scalability_lifecycle_status:-missing}" \
  -v scalability_close_failures="${scalability_close_failures:-1}" \
  -v scalability_accept_failures="${scalability_accept_failures:-1}" \
  -v scalability_missing_active_client_fields="${scalability_missing_active_client_fields:-1}" \
  -v active_protocol_change="${active_protocol_change:-1}" \
  -v lifecycle_status="${lifecycle_status:-missing}" \
  -v connected_clients="${connected_clients:-0}" \
  -v rejected_clients="${rejected_clients:-0}" \
  -v disconnected_clients="${disconnected_clients:-0}" \
  -v packet_error_disconnects="${packet_error_disconnects:-0}" \
  -v eof_disconnects="${eof_disconnects:-0}" \
  -v timeout_disconnects="${timeout_disconnects:-0}" \
  -v close_failures="${close_failures:-1}" \
  -v accept_failures="${accept_failures:-1}" \
  -v max_active_clients="${max_active_clients:-0}" \
  -v max_configured_clients="${max_configured_clients:-0}" \
  -v missing_active_client_fields="${missing_active_client_fields:-1}" \
  -v observability_status="${observability_status:-missing}" \
  -v observability_error_scan="${observability_error_scan:-dirty}" \
  -v index_scalability_status="$index_scalability_status" \
  -v index_lifecycle_status="$index_lifecycle_status" \
  -v metrics_path="$METRICS_PATH" \
  -v scalability_summary="$SCALABILITY_SUMMARY" \
  -v lifecycle_summary="$LIFECYCLE_SUMMARY" \
  -v observability_summary="$OBSERVABILITY_SUMMARY" \
  -v observability_index="$observability_index" '
  BEGIN {
    status = "pass"
    reason = "ok"
    monitoring_contract = "export_ready"
    metrics_export = "present"

    scalability_ok = scalability_status == "pass" &&
      scalability_guard == "repeat_live_guarded" &&
      resource_profile_status == "repeat_live_guarded" &&
      admission_policy == "matrix_live_guarded" &&
      disconnect_cleanup_status == "lifecycle_summary_guarded" &&
      live_load_status == "pass" &&
      live_detail_status == "pass" &&
      live_detail_clients + 0 >= 2 &&
      live_resource_samples + 0 > 0 &&
      broader_live_status == "pass" &&
      broader_live_clients + 0 >= 6 &&
      broader_live_resource_samples + 0 > 0 &&
      repeat_smoke_status == "pass" &&
      repeat_smoke_repeats + 0 >= 3 &&
      repeat_smoke_clients + 0 >= 6 &&
      repeat_smoke_resource_samples + 0 > 0 &&
      admission_limit_status == "pass" &&
      admission_matrix_status == "pass" &&
      admission_matrix_limits_checked + 0 >= 3 &&
      admission_matrix_total_rejected + 0 >= 3 &&
      scalability_lifecycle_status == "pass" &&
      scalability_close_failures + 0 == 0 &&
      scalability_accept_failures + 0 == 0 &&
      scalability_missing_active_client_fields + 0 == 0 &&
      active_protocol_change + 0 == 0

    lifecycle_ok = lifecycle_status == "pass" &&
      connected_clients + 0 > 0 &&
      rejected_clients + 0 > 0 &&
      disconnected_clients + 0 > 0 &&
      packet_error_disconnects + 0 == disconnected_clients + 0 &&
      close_failures + 0 == 0 &&
      accept_failures + 0 == 0 &&
      max_active_clients + 0 > 0 &&
      missing_active_client_fields + 0 == 0

    observability_ok = observability_status == "pass" &&
      observability_error_scan == "clean" &&
      index_scalability_status == "present" &&
      index_lifecycle_status == "present"

    if (!scalability_ok) {
      status = "fail"
      reason = "scalability_session_evidence_not_exportable"
      monitoring_contract = "fail"
    } else if (!lifecycle_ok) {
      status = "fail"
      reason = "connection_lifecycle_evidence_not_exportable"
      monitoring_contract = "fail"
    } else if (!observability_ok) {
      status = "fail"
      reason = "observability_index_missing_session_artifacts"
      monitoring_contract = "fail"
    }

    printf("server_session_monitoring_contract status=%s reason=%s monitoring_contract=%s metrics_export=%s scalability_status=%s scalability_guard=%s resource_profile_status=%s admission_policy=%s disconnect_cleanup_status=%s lifecycle_status=%s connected_clients=%d rejected_clients=%d disconnected_clients=%d packet_error_disconnects=%d eof_disconnects=%d timeout_disconnects=%d close_failures=%d accept_failures=%d max_active_clients=%d max_configured_clients=%d missing_active_client_fields=%d live_detail_clients=%d live_resource_samples=%d live_resource_rss_kb_max=%d live_resource_cpu_pct_max=%s broader_live_clients=%d broader_live_resource_samples=%d broader_live_resource_rss_kb_max=%d broader_live_resource_cpu_pct_max=%s repeat_smoke_repeats=%d repeat_smoke_clients=%d repeat_smoke_resource_samples=%d repeat_smoke_max_rss_kb=%d repeat_smoke_max_cpu_pct=%s admission_matrix_limits_checked=%d admission_matrix_total_rejected=%d observability_status=%s observability_error_scan=%s index_scalability_status=%s index_lifecycle_status=%s metrics=%s scalability_summary=%s lifecycle_summary=%s observability_summary=%s observability_index=%s\n", status, reason, monitoring_contract, metrics_export, scalability_status, scalability_guard, resource_profile_status, admission_policy, disconnect_cleanup_status, lifecycle_status, connected_clients + 0, rejected_clients + 0, disconnected_clients + 0, packet_error_disconnects + 0, eof_disconnects + 0, timeout_disconnects + 0, close_failures + 0, accept_failures + 0, max_active_clients + 0, max_configured_clients + 0, missing_active_client_fields + 0, live_detail_clients + 0, live_resource_samples + 0, live_resource_rss_kb_max + 0, live_resource_cpu_pct_max, broader_live_clients + 0, broader_live_resource_samples + 0, broader_live_resource_rss_kb_max + 0, broader_live_resource_cpu_pct_max, repeat_smoke_repeats + 0, repeat_smoke_clients + 0, repeat_smoke_resource_samples + 0, repeat_smoke_max_rss_kb + 0, repeat_smoke_max_cpu_pct, admission_matrix_limits_checked + 0, admission_matrix_total_rejected + 0, observability_status, observability_error_scan, index_scalability_status, index_lifecycle_status, metrics_path, scalability_summary, lifecycle_summary, observability_summary, observability_index)
    if (status != "pass") {
      exit 1
    }
  }
' > "$SUMMARY_PATH" || {
  cat "$SUMMARY_PATH" >&2 || true
  fail "server session monitoring contract failed"
}

cat "$SUMMARY_PATH"
echo "Server session monitoring contract artifacts: $OUT_DIR"
