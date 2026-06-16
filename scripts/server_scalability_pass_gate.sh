#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/server_scalability_pass"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

SUMMARY_PATH="$OUT_DIR/server-scalability-pass-summary.txt"
DESIGN_DOC="${RUMPELMC_SERVER_SCALABILITY_DOC:-"$ROOT_DIR/docs/SERVER_SCALABILITY_PASS.md"}"
PROTOCOL_DOC="${RUMPELMC_SERVER_SCALABILITY_PROTOCOL_DOC:-"$ROOT_DIR/docs/PROTOCOL.md"}"
SERVER_SOURCE="${RUMPELMC_SERVER_SCALABILITY_SOURCE:-"$ROOT_DIR/server/pkg/network/server.go"}"
SERVER_TEST="${RUMPELMC_SERVER_SCALABILITY_TEST:-"$ROOT_DIR/server/pkg/network/server_test.go"}"
LIVE_SMOKE_SCRIPT="${RUMPELMC_SERVER_SCALABILITY_LIVE_SMOKE_SCRIPT:-"$ROOT_DIR/scripts/server_multi_client_smoke.sh"}"
ADMISSION_LIMIT_SMOKE_SCRIPT="${RUMPELMC_SERVER_SCALABILITY_ADMISSION_LIMIT_SMOKE_SCRIPT:-"$ROOT_DIR/scripts/server_admission_limit_smoke.sh"}"
CONNECTION_LIFECYCLE_SUMMARY_SCRIPT="${RUMPELMC_SERVER_SCALABILITY_CONNECTION_LIFECYCLE_SUMMARY_SCRIPT:-"$ROOT_DIR/scripts/server_connection_lifecycle_summary.sh"}"
LIVE_SMOKE_SUMMARY="${RUMPELMC_SERVER_SCALABILITY_LIVE_SMOKE_SUMMARY:-"$ROOT_DIR/logs/server_multi_client_smoke_current/server-multi-client-smoke-summary.txt"}"
BROADER_LIVE_SMOKE_SUMMARY="${RUMPELMC_SERVER_SCALABILITY_BROADER_LIVE_SMOKE_SUMMARY:-"$ROOT_DIR/logs/server_multi_client_load_current/server-multi-client-smoke-summary.txt"}"
ADMISSION_LIMIT_SMOKE_SUMMARY="${RUMPELMC_SERVER_SCALABILITY_ADMISSION_LIMIT_SMOKE_SUMMARY:-"$ROOT_DIR/logs/server_admission_limit_smoke_current/server-admission-limit-smoke-summary.txt"}"
CONNECTION_LIFECYCLE_SUMMARY="${RUMPELMC_SERVER_SCALABILITY_CONNECTION_LIFECYCLE_SUMMARY:-"$ROOT_DIR/logs/server_connection_lifecycle_current/server-connection-lifecycle-summary.txt"}"
WORLDGEN_QUALITY_SUMMARY="${RUMPELMC_SERVER_SCALABILITY_WORLDGEN_QUALITY_SUMMARY:-"$ROOT_DIR/logs/world_generation_quality_current/world-generation-quality-summary.txt"}"
RUN_GO_TESTS="${RUMPELMC_SERVER_SCALABILITY_RUN_GO_TESTS:-1}"
RUN_LIVE_SMOKE="${RUMPELMC_SERVER_SCALABILITY_RUN_LIVE_SMOKE:-0}"
RUN_BROADER_LIVE_SMOKE="${RUMPELMC_SERVER_SCALABILITY_RUN_BROADER_LIVE_SMOKE:-0}"
RUN_ADMISSION_LIMIT_SMOKE="${RUMPELMC_SERVER_SCALABILITY_RUN_ADMISSION_LIMIT_SMOKE:-0}"
RUN_CONNECTION_LIFECYCLE_SUMMARY="${RUMPELMC_SERVER_SCALABILITY_RUN_CONNECTION_LIFECYCLE_SUMMARY:-1}"
BROADER_LIVE_SMOKE_CLIENTS="${RUMPELMC_SERVER_SCALABILITY_BROADER_LIVE_SMOKE_CLIENTS:-6}"

mkdir -p "$OUT_DIR"

fail() {
  echo "server_scalability_pass_gate: $*" >&2
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

CONNECTION_LIFECYCLE_LOG_ARGS=""
append_connection_lifecycle_log() {
  summary_path="$1"
  if [ -s "$summary_path" ]; then
    log_path="$(field_metric server_log "$summary_path")"
    if [ -n "$log_path" ] && [ -s "$log_path" ]; then
      CONNECTION_LIFECYCLE_LOG_ARGS="$CONNECTION_LIFECYCLE_LOG_ARGS $log_path"
    fi
  fi
}

for path in "$DESIGN_DOC" "$PROTOCOL_DOC" "$SERVER_SOURCE" "$SERVER_TEST" "$LIVE_SMOKE_SCRIPT" "$ADMISSION_LIMIT_SMOKE_SCRIPT" "$CONNECTION_LIFECYCLE_SUMMARY_SCRIPT" "$WORLDGEN_QUALITY_SUMMARY"; do
  test -s "$path" || fail "missing required input $path"
done

for token in \
  'per-client sent-chunk state isolation' \
  'Scalability Gaps' \
  'Broader slow-client handling evidence' \
  'Broader Live Multi-Client Load Smoke' \
  'Do not change `api/schema/packets.proto`' \
  'Live Multi-Client Smoke'; do
  require_token "$DESIGN_DOC" "$token"
done

require_token "$PROTOCOL_DOC" "Preserve wire compatibility unless the task explicitly changes it."
require_token "$SERVER_SOURCE" "go s.handleConnection(conn)"
require_token "$SERVER_SOURCE" "defer conn.Close()"
require_token "$SERVER_SOURCE" "clientChunkStreamState"
require_token "$SERVER_SOURCE" "sentChunks: make(map[world.ChunkCoord]bool)"
require_token "$SERVER_SOURCE" "forgetFarSentChunks"
require_token "$SERVER_SOURCE" "broadcastChunkUpdate"
require_token "$SERVER_SOURCE" "disconnectClient"
require_token "$SERVER_SOURCE" "SetWriteDeadline"
require_token "$SERVER_SOURCE" "maxClientsEnv"
require_token "$SERVER_SOURCE" "tryRegisterClient"
require_token "$SERVER_SOURCE" "admission_result=rejected"
require_token "$SERVER_TEST" "TestSendChunksAroundKeepsPerClientSentStateIndependent"
require_token "$SERVER_TEST" "second client sent chunks changed after first client progress"
require_token "$SERVER_TEST" "TestHandleClientPacketBroadcastsBlockUpdateToInterestedClients"
require_token "$SERVER_TEST" "TestBroadcastDisconnectsFailedInterestedClient"
require_token "$SERVER_TEST" "TestSendChunkToSessionSetsAndClearsWriteDeadline"
require_token "$SERVER_TEST" "TestConfiguredMaxClientsParsesSupportedValues"
require_token "$SERVER_TEST" "TestTryRegisterClientHonorsMaxClients"
require_token "$SERVER_TEST" "TestHandleConnectionRejectsWhenMaxClientsReached"
require_token "$LIVE_SMOKE_SCRIPT" "server_multi_client_smoke status=pass"
require_token "$LIVE_SMOKE_SCRIPT" "server_resource_samples="
require_token "$ADMISSION_LIMIT_SMOKE_SCRIPT" "server_admission_limit_smoke status=pass"
require_token "$ADMISSION_LIMIT_SMOKE_SCRIPT" "admission_result=rejected"
require_token "$CONNECTION_LIFECYCLE_SUMMARY_SCRIPT" "server_connection_lifecycle status="

case "$RUN_LIVE_SMOKE" in
  0) ;;
  1)
    "$LIVE_SMOKE_SCRIPT" "$OUT_DIR/live_multi_client_smoke" > "$OUT_DIR/live-smoke-run.txt" 2>&1 || {
      cat "$OUT_DIR/live-smoke-run.txt" >&2 || true
      fail "live multi-client smoke failed"
    }
    LIVE_SMOKE_SUMMARY="$OUT_DIR/live_multi_client_smoke/server-multi-client-smoke-summary.txt"
    ;;
  *)
    fail "unsupported RUMPELMC_SERVER_SCALABILITY_RUN_LIVE_SMOKE=$RUN_LIVE_SMOKE"
    ;;
esac
case "$RUN_BROADER_LIVE_SMOKE" in
  0) ;;
  1)
    broader_smoke_dir="$(dirname "$BROADER_LIVE_SMOKE_SUMMARY")"
    RUMPELMC_SERVER_MULTI_CLIENT_SMOKE_CLIENTS="$BROADER_LIVE_SMOKE_CLIENTS" \
      "$LIVE_SMOKE_SCRIPT" "$broader_smoke_dir" > "$OUT_DIR/broader-live-smoke-run.txt" 2>&1 || {
        cat "$OUT_DIR/broader-live-smoke-run.txt" >&2 || true
        fail "broader live multi-client smoke failed"
      }
    ;;
  *)
    fail "unsupported RUMPELMC_SERVER_SCALABILITY_RUN_BROADER_LIVE_SMOKE=$RUN_BROADER_LIVE_SMOKE"
    ;;
esac
case "$RUN_ADMISSION_LIMIT_SMOKE" in
  0) ;;
  1)
    admission_smoke_dir="$(dirname "$ADMISSION_LIMIT_SMOKE_SUMMARY")"
    "$ADMISSION_LIMIT_SMOKE_SCRIPT" "$admission_smoke_dir" > "$OUT_DIR/admission-limit-smoke-run.txt" 2>&1 || {
      cat "$OUT_DIR/admission-limit-smoke-run.txt" >&2 || true
      fail "admission-limit smoke failed"
    }
    ;;
  *)
    fail "unsupported RUMPELMC_SERVER_SCALABILITY_RUN_ADMISSION_LIMIT_SMOKE=$RUN_ADMISSION_LIMIT_SMOKE"
    ;;
esac

worldgen_quality_status="$(field_metric status "$WORLDGEN_QUALITY_SUMMARY")"
worldgen_runtime_quality="$(field_metric runtime_quality_pass "$WORLDGEN_QUALITY_SUMMARY")"
live_load_status="deferred"
live_resource_samples="0"
live_resource_rss_kb_max="0"
live_resource_cpu_pct_max="0"
if [ -s "$LIVE_SMOKE_SUMMARY" ]; then
  live_load_status="$(field_metric status "$LIVE_SMOKE_SUMMARY")"
  live_resource_samples="$(field_metric server_resource_samples "$LIVE_SMOKE_SUMMARY")"
  live_resource_rss_kb_max="$(field_metric server_rss_kb_max "$LIVE_SMOKE_SUMMARY")"
  live_resource_cpu_pct_max="$(field_metric server_cpu_pct_max "$LIVE_SMOKE_SUMMARY")"
fi
broader_live_load_status="deferred"
broader_live_clients="0"
broader_live_initial_chunks="0"
broader_live_fanout_updates="0"
broader_live_resource_samples="0"
broader_live_resource_rss_kb_max="0"
broader_live_resource_cpu_pct_max="0"
if [ -s "$BROADER_LIVE_SMOKE_SUMMARY" ]; then
  broader_live_load_status="$(field_metric status "$BROADER_LIVE_SMOKE_SUMMARY")"
  broader_live_clients="$(field_metric clients "$BROADER_LIVE_SMOKE_SUMMARY")"
  broader_live_initial_chunks="$(field_metric initial_chunks "$BROADER_LIVE_SMOKE_SUMMARY")"
  broader_live_fanout_updates="$(field_metric fanout_updates "$BROADER_LIVE_SMOKE_SUMMARY")"
  broader_live_resource_samples="$(field_metric server_resource_samples "$BROADER_LIVE_SMOKE_SUMMARY")"
  broader_live_resource_rss_kb_max="$(field_metric server_rss_kb_max "$BROADER_LIVE_SMOKE_SUMMARY")"
  broader_live_resource_cpu_pct_max="$(field_metric server_cpu_pct_max "$BROADER_LIVE_SMOKE_SUMMARY")"
fi
admission_limit_status="deferred"
admission_limit_max_clients="0"
admission_limit_attempted_clients="0"
admission_limit_admitted_clients="0"
admission_limit_rejected_clients="0"
admission_limit_close_observed="0"
admission_limit_rejection_log="0"
if [ -s "$ADMISSION_LIMIT_SMOKE_SUMMARY" ]; then
  admission_limit_status="$(field_metric status "$ADMISSION_LIMIT_SMOKE_SUMMARY")"
  admission_limit_max_clients="$(field_metric max_clients "$ADMISSION_LIMIT_SMOKE_SUMMARY")"
  admission_limit_attempted_clients="$(field_metric attempted_clients "$ADMISSION_LIMIT_SMOKE_SUMMARY")"
  admission_limit_admitted_clients="$(field_metric admitted_clients "$ADMISSION_LIMIT_SMOKE_SUMMARY")"
  admission_limit_rejected_clients="$(field_metric rejected_clients "$ADMISSION_LIMIT_SMOKE_SUMMARY")"
  admission_limit_close_observed="$(field_metric rejected_close_observed "$ADMISSION_LIMIT_SMOKE_SUMMARY")"
  admission_limit_rejection_log="$(field_metric admission_rejection_log "$ADMISSION_LIMIT_SMOKE_SUMMARY")"
fi
case "$RUN_CONNECTION_LIFECYCLE_SUMMARY" in
  0) ;;
  1)
    append_connection_lifecycle_log "$LIVE_SMOKE_SUMMARY"
    append_connection_lifecycle_log "$BROADER_LIVE_SMOKE_SUMMARY"
    append_connection_lifecycle_log "$ADMISSION_LIMIT_SMOKE_SUMMARY"
    if [ -n "$CONNECTION_LIFECYCLE_LOG_ARGS" ]; then
      connection_lifecycle_dir="$(dirname "$CONNECTION_LIFECYCLE_SUMMARY")"
      "$CONNECTION_LIFECYCLE_SUMMARY_SCRIPT" "$connection_lifecycle_dir" $CONNECTION_LIFECYCLE_LOG_ARGS > "$OUT_DIR/connection-lifecycle-summary-run.txt" 2>&1 || {
        cat "$OUT_DIR/connection-lifecycle-summary-run.txt" >&2 || true
        fail "connection lifecycle summary failed"
      }
    fi
    ;;
  *)
    fail "unsupported RUMPELMC_SERVER_SCALABILITY_RUN_CONNECTION_LIFECYCLE_SUMMARY=$RUN_CONNECTION_LIFECYCLE_SUMMARY"
    ;;
esac
connection_lifecycle_status="deferred"
connection_lifecycle_connected="0"
connection_lifecycle_rejected="0"
connection_lifecycle_disconnected="0"
connection_lifecycle_close_failures="0"
connection_lifecycle_accept_failures="0"
if [ -s "$CONNECTION_LIFECYCLE_SUMMARY" ]; then
  connection_lifecycle_status="$(field_metric status "$CONNECTION_LIFECYCLE_SUMMARY")"
  connection_lifecycle_connected="$(field_metric connected_clients "$CONNECTION_LIFECYCLE_SUMMARY")"
  connection_lifecycle_rejected="$(field_metric rejected_clients "$CONNECTION_LIFECYCLE_SUMMARY")"
  connection_lifecycle_disconnected="$(field_metric disconnected_clients "$CONNECTION_LIFECYCLE_SUMMARY")"
  connection_lifecycle_close_failures="$(field_metric close_failures "$CONNECTION_LIFECYCLE_SUMMARY")"
  connection_lifecycle_accept_failures="$(field_metric accept_failures "$CONNECTION_LIFECYCLE_SUMMARY")"
fi
proto_diff_count="$(git -C "$ROOT_DIR" diff --name-only -- api/schema/packets.proto server/pkg/api/packets.pb.go | awk 'END { print NR + 0 }')"

network_tests="skipped"
if [ "$RUN_GO_TESTS" = "1" ]; then
  if (cd "$ROOT_DIR/server" && go test ./pkg/network > "$OUT_DIR/go-test-network.txt" 2>&1); then
    network_tests="pass"
  else
    cat "$OUT_DIR/go-test-network.txt" >&2 || true
    network_tests="fail"
  fi
fi

awk \
  -v worldgen_quality_status="${worldgen_quality_status:-missing}" \
  -v worldgen_runtime_quality="${worldgen_runtime_quality:-active}" \
  -v proto_diff_count="$proto_diff_count" \
  -v live_load_status="${live_load_status:-missing}" \
  -v live_resource_samples="${live_resource_samples:-0}" \
  -v live_resource_rss_kb_max="${live_resource_rss_kb_max:-0}" \
  -v live_resource_cpu_pct_max="${live_resource_cpu_pct_max:-0}" \
  -v live_required="$RUN_LIVE_SMOKE" \
  -v broader_live_load_status="${broader_live_load_status:-deferred}" \
  -v broader_live_clients="${broader_live_clients:-0}" \
  -v broader_live_initial_chunks="${broader_live_initial_chunks:-0}" \
  -v broader_live_fanout_updates="${broader_live_fanout_updates:-0}" \
  -v broader_live_resource_samples="${broader_live_resource_samples:-0}" \
  -v broader_live_resource_rss_kb_max="${broader_live_resource_rss_kb_max:-0}" \
  -v broader_live_resource_cpu_pct_max="${broader_live_resource_cpu_pct_max:-0}" \
  -v broader_live_required="$RUN_BROADER_LIVE_SMOKE" \
  -v broader_live_min_clients="$BROADER_LIVE_SMOKE_CLIENTS" \
  -v admission_limit_status="${admission_limit_status:-deferred}" \
  -v admission_limit_max_clients="${admission_limit_max_clients:-0}" \
  -v admission_limit_attempted_clients="${admission_limit_attempted_clients:-0}" \
  -v admission_limit_admitted_clients="${admission_limit_admitted_clients:-0}" \
  -v admission_limit_rejected_clients="${admission_limit_rejected_clients:-0}" \
  -v admission_limit_close_observed="${admission_limit_close_observed:-0}" \
  -v admission_limit_rejection_log="${admission_limit_rejection_log:-0}" \
  -v admission_limit_required="$RUN_ADMISSION_LIMIT_SMOKE" \
  -v connection_lifecycle_status="${connection_lifecycle_status:-deferred}" \
  -v connection_lifecycle_connected="${connection_lifecycle_connected:-0}" \
  -v connection_lifecycle_rejected="${connection_lifecycle_rejected:-0}" \
  -v connection_lifecycle_disconnected="${connection_lifecycle_disconnected:-0}" \
  -v connection_lifecycle_close_failures="${connection_lifecycle_close_failures:-0}" \
  -v connection_lifecycle_accept_failures="${connection_lifecycle_accept_failures:-0}" \
  -v network_tests="$network_tests" \
  -v design_doc="$DESIGN_DOC" \
  -v live_smoke_summary="$LIVE_SMOKE_SUMMARY" \
  -v broader_live_smoke_summary="$BROADER_LIVE_SMOKE_SUMMARY" \
  -v admission_limit_smoke_summary="$ADMISSION_LIMIT_SMOKE_SUMMARY" \
  -v connection_lifecycle_summary="$CONNECTION_LIFECYCLE_SUMMARY" \
  -v worldgen_quality_summary="$WORLDGEN_QUALITY_SUMMARY" '
  BEGIN {
    status = "pass"
    reason = "ok"
    broader_live_ok = broader_live_load_status == "pass" &&
      broader_live_clients + 0 >= broader_live_min_clients + 0 &&
      broader_live_initial_chunks + 0 == broader_live_clients + 0 &&
      broader_live_fanout_updates + 0 == broader_live_clients + 0
    live_resource_ok = live_load_status == "pass" &&
      live_resource_samples + 0 >= 1 &&
      live_resource_rss_kb_max + 0 > 0
    broader_live_resource_ok = broader_live_ok &&
      broader_live_resource_samples + 0 >= 1 &&
      broader_live_resource_rss_kb_max + 0 > 0
    resource_profile_status = broader_live_resource_ok ? "broader_live_guarded" : (live_resource_ok ? "live_guarded" : "deferred")
    scalability_status = broader_live_ok ? "broader_live_guarded" : "unit_guarded"
    multi_client_sent_state = "guarded"
    block_edit_fanout = "interested_clients_guarded"
    slow_client_write_timeout = "guarded"
    connection_lifecycle_ok = connection_lifecycle_status == "pass" &&
      connection_lifecycle_connected + 0 >= 1 &&
      connection_lifecycle_disconnected + 0 >= 1 &&
      connection_lifecycle_close_failures + 0 == 0 &&
      connection_lifecycle_accept_failures + 0 == 0
    disconnect_cleanup_status = connection_lifecycle_ok ? "lifecycle_summary_guarded" : "failed_broadcast_guarded"
    admission_limit_ok = admission_limit_status == "pass" &&
      admission_limit_max_clients + 0 == 1 &&
      admission_limit_attempted_clients + 0 == 2 &&
      admission_limit_admitted_clients + 0 == 1 &&
      admission_limit_rejected_clients + 0 == 1 &&
      admission_limit_close_observed + 0 == 1 &&
      admission_limit_rejection_log + 0 == 1
    admission_policy = admission_limit_ok ? "live_guarded" : "unit_guarded"
    active_protocol_change = proto_diff_count + 0

    deps_ok = worldgen_quality_status == "pass" && worldgen_runtime_quality == "deferred"
    tests_ok = network_tests == "pass" || network_tests == "skipped"
    live_ok = live_load_status == "pass" || live_required != "1"
    broader_required_ok = broader_live_ok || broader_live_required != "1"
    admission_required_ok = admission_limit_ok || admission_limit_required != "1"

    if (active_protocol_change != 0) {
      status = "fail"
      reason = "protocol_diff_present"
    } else if (!live_ok) {
      status = "fail"
      reason = "live_multi_client_smoke_failed"
    } else if (!broader_required_ok) {
      status = "fail"
      reason = "broader_live_multi_client_smoke_failed"
    } else if (broader_live_ok && !broader_live_resource_ok) {
      status = "fail"
      reason = "broader_live_resource_profile_missing"
    } else if (!admission_required_ok) {
      status = "fail"
      reason = "admission_limit_smoke_failed"
    } else if (connection_lifecycle_status != "deferred" && !connection_lifecycle_ok) {
      status = "fail"
      reason = "connection_lifecycle_summary_failed"
    } else if (!deps_ok) {
      status = "fail"
      reason = "worldgen_quality_gate_not_clean"
    } else if (!tests_ok) {
      status = "fail"
      reason = "network_tests_failed"
    }

    printf("server_scalability_pass status=%s reason=%s scalability_status=%s resource_profile_status=%s multi_client_sent_state=%s block_edit_fanout=%s slow_client_write_timeout=%s admission_policy=%s active_protocol_change=%d disconnect_cleanup_status=%s live_load_status=%s live_resource_samples=%d live_resource_rss_kb_max=%d live_resource_cpu_pct_max=%.1f broader_live_load_status=%s broader_live_clients=%d broader_live_initial_chunks=%d broader_live_fanout_updates=%d broader_live_resource_samples=%d broader_live_resource_rss_kb_max=%d broader_live_resource_cpu_pct_max=%.1f admission_limit_smoke_status=%s admission_limit_max_clients=%d admission_limit_attempted_clients=%d admission_limit_admitted_clients=%d admission_limit_rejected_clients=%d admission_limit_rejection_log=%d connection_lifecycle_status=%s connection_lifecycle_connected=%d connection_lifecycle_rejected=%d connection_lifecycle_disconnected=%d connection_lifecycle_close_failures=%d connection_lifecycle_accept_failures=%d network_tests=%s worldgen_quality_status=%s worldgen_runtime_quality=%s design_doc=%s live_smoke_summary=%s broader_live_smoke_summary=%s admission_limit_smoke_summary=%s connection_lifecycle_summary=%s worldgen_quality_summary=%s\n", status, reason, scalability_status, resource_profile_status, multi_client_sent_state, block_edit_fanout, slow_client_write_timeout, admission_policy, active_protocol_change, disconnect_cleanup_status, live_load_status, live_resource_samples, live_resource_rss_kb_max, live_resource_cpu_pct_max, broader_live_load_status, broader_live_clients, broader_live_initial_chunks, broader_live_fanout_updates, broader_live_resource_samples, broader_live_resource_rss_kb_max, broader_live_resource_cpu_pct_max, admission_limit_status, admission_limit_max_clients, admission_limit_attempted_clients, admission_limit_admitted_clients, admission_limit_rejected_clients, admission_limit_rejection_log, connection_lifecycle_status, connection_lifecycle_connected, connection_lifecycle_rejected, connection_lifecycle_disconnected, connection_lifecycle_close_failures, connection_lifecycle_accept_failures, network_tests, worldgen_quality_status, worldgen_runtime_quality, design_doc, live_smoke_summary, broader_live_smoke_summary, admission_limit_smoke_summary, connection_lifecycle_summary, worldgen_quality_summary)
    if (status != "pass") {
      exit 1
    }
  }
' > "$SUMMARY_PATH" || {
  cat "$SUMMARY_PATH" >&2 || true
  fail "server scalability pass gate failed"
}

cat "$SUMMARY_PATH"
echo "Server scalability pass artifacts: $OUT_DIR"
