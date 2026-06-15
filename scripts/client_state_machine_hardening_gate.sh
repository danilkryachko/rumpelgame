#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/client_state_machine_hardening"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

SUMMARY_PATH="$OUT_DIR/client-state-machine-hardening-summary.txt"
DESIGN_DOC="${RUMPELMC_CLIENT_STATE_MACHINE_DOC:-"$ROOT_DIR/docs/CLIENT_STATE_MACHINE_HARDENING.md"}"
PROTOCOL_DOC="${RUMPELMC_CLIENT_STATE_MACHINE_PROTOCOL_DOC:-"$ROOT_DIR/docs/PROTOCOL.md"}"
CLIENT_SOURCE="${RUMPELMC_CLIENT_STATE_MACHINE_SOURCE:-"$ROOT_DIR/client/rust_ext/src/lib.rs"}"
NETWORKING_SUMMARY="${RUMPELMC_CLIENT_STATE_MACHINE_NETWORKING_SUMMARY:-"$ROOT_DIR/logs/networking_robustness_current/networking-robustness-summary.txt"}"
RECONNECT_SMOKE_SCRIPT="${RUMPELMC_CLIENT_STATE_MACHINE_RECONNECT_SMOKE_SCRIPT:-"$ROOT_DIR/scripts/client_reconnect_smoke.sh"}"
RECONNECT_SMOKE_SUMMARY="${RUMPELMC_CLIENT_STATE_MACHINE_RECONNECT_SMOKE_SUMMARY:-"$ROOT_DIR/logs/client_reconnect_smoke_current/client-reconnect-smoke-summary.txt"}"
RUN_RUST_TESTS="${RUMPELMC_CLIENT_STATE_MACHINE_RUN_RUST_TESTS:-1}"
RUN_RECONNECT_SMOKE="${RUMPELMC_CLIENT_STATE_MACHINE_RUN_RECONNECT_SMOKE:-0}"

mkdir -p "$OUT_DIR"

fail() {
  echo "client_state_machine_hardening_gate: $*" >&2
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

for path in "$DESIGN_DOC" "$PROTOCOL_DOC" "$CLIENT_SOURCE" "$NETWORKING_SUMMARY" "$RECONNECT_SMOKE_SCRIPT"; do
  test -s "$path" || fail "missing required input $path"
done

for token in \
  'State Contract' \
  'Transition Contract' \
  'Current Runtime Wiring' \
  'Deferred Work' \
  'Compatibility Rules' \
  'Reader-thread receive errors' \
  'Automatic retry/backoff' \
  'Live Reconnect Smoke' \
  'Do not change packet schema or framing'; do
  require_token "$DESIGN_DOC" "$token"
done

require_token "$PROTOCOL_DOC" 'Reconnect, slow-client timeout, overload, and backpressure behavior are policy work'
require_token "$CLIENT_SOURCE" 'enum ClientLifecycleState'
require_token "$CLIENT_SOURCE" 'Connecting'
require_token "$CLIENT_SOURCE" 'WaitingChunks'
require_token "$CLIENT_SOURCE" 'Spawning'
require_token "$CLIENT_SOURCE" 'Active'
require_token "$CLIENT_SOURCE" 'Reconnecting'
require_token "$CLIENT_SOURCE" 'Shutdown'
require_token "$CLIENT_SOURCE" 'enum ClientLifecycleEvent'
require_token "$CLIENT_SOURCE" 'fn client_lifecycle_transition'
require_token "$CLIENT_SOURCE" 'fn record_client_lifecycle_event'
require_token "$CLIENT_SOURCE" 'ClientLifecycleEvent::ConnectSucceeded'
require_token "$CLIENT_SOURCE" 'ClientLifecycleEvent::ConnectFailed'
require_token "$CLIENT_SOURCE" 'ClientLifecycleEvent::StartupChunkReady'
require_token "$CLIENT_SOURCE" 'ClientLifecycleEvent::SpawnComplete'
require_token "$CLIENT_SOURCE" 'ClientLifecycleEvent::NetworkError'
require_token "$CLIENT_SOURCE" 'ClientLifecycleEvent::ShutdownRequested'
require_token "$CLIENT_SOURCE" 'enum NetworkReaderEvent'
require_token "$CLIENT_SOURCE" 'fn record_network_reader_error'
require_token "$CLIENT_SOURCE" 'fn client_lifecycle_allows_outbound'
require_token "$CLIENT_SOURCE" 'client_state={}'
require_token "$CLIENT_SOURCE" 'reconnect_successes={}'
require_token "$CLIENT_SOURCE" 'network_reader_errors={}'
require_token "$CLIENT_SOURCE" 'client_lifecycle_connects_waits_spawns_and_becomes_active'
require_token "$CLIENT_SOURCE" 'client_lifecycle_reconnects_from_connect_and_network_errors'
require_token "$CLIENT_SOURCE" 'client_lifecycle_rebootstrap_returns_to_active'
require_token "$CLIENT_SOURCE" 'client_lifecycle_shutdown_is_terminal'
require_token "$CLIENT_SOURCE" 'client_lifecycle_rejects_out_of_order_startup_events'
require_token "$CLIENT_SOURCE" 'client_lifecycle_outbound_is_active_only'
require_token "$RECONNECT_SMOKE_SCRIPT" 'client_reconnect_smoke status=pass'

networking_status="$(field_metric status "$NETWORKING_SUMMARY")"
networking_protocol_change="$(field_metric active_protocol_change "$NETWORKING_SUMMARY")"
case "$RUN_RECONNECT_SMOKE" in
  0) ;;
  1)
    reconnect_smoke_dir="$(dirname "$RECONNECT_SMOKE_SUMMARY")"
    "$RECONNECT_SMOKE_SCRIPT" "$reconnect_smoke_dir" > "$OUT_DIR/reconnect-smoke-run.txt" 2>&1 || {
      cat "$OUT_DIR/reconnect-smoke-run.txt" >&2 || true
      fail "live reconnect smoke failed"
    }
    ;;
  *)
    fail "unsupported RUMPELMC_CLIENT_STATE_MACHINE_RUN_RECONNECT_SMOKE=$RUN_RECONNECT_SMOKE"
    ;;
esac
reconnect_smoke_status="deferred"
reconnect_smoke_client_state="missing"
reconnect_smoke_reader_errors="0"
reconnect_smoke_successes="0"
reconnect_smoke_protocol_change="0"
if [ -s "$RECONNECT_SMOKE_SUMMARY" ]; then
  reconnect_smoke_status="$(field_metric status "$RECONNECT_SMOKE_SUMMARY")"
  reconnect_smoke_client_state="$(field_metric client_state "$RECONNECT_SMOKE_SUMMARY")"
  reconnect_smoke_reader_errors="$(field_metric network_reader_errors "$RECONNECT_SMOKE_SUMMARY")"
  reconnect_smoke_successes="$(field_metric reconnect_successes "$RECONNECT_SMOKE_SUMMARY")"
  reconnect_smoke_protocol_change="$(field_metric active_protocol_change "$RECONNECT_SMOKE_SUMMARY")"
fi
proto_diff_count="$(git -C "$ROOT_DIR" diff --name-only -- api/schema/packets.proto server/pkg/api/packets.pb.go | awk 'END { print NR + 0 }')"

client_lifecycle_tests="skipped"
if [ "$RUN_RUST_TESTS" = "1" ]; then
  if (cd "$ROOT_DIR/client/rust_ext" && cargo test --lib client_lifecycle > "$OUT_DIR/cargo-test-client-lifecycle.txt" 2>&1); then
    client_lifecycle_tests="pass"
  else
    cat "$OUT_DIR/cargo-test-client-lifecycle.txt" >&2 || true
    client_lifecycle_tests="fail"
  fi
fi

awk \
  -v networking_status="${networking_status:-missing}" \
  -v networking_protocol_change="${networking_protocol_change:-1}" \
  -v reconnect_smoke_status="${reconnect_smoke_status:-deferred}" \
  -v reconnect_smoke_client_state="${reconnect_smoke_client_state:-missing}" \
  -v reconnect_smoke_reader_errors="${reconnect_smoke_reader_errors:-0}" \
  -v reconnect_smoke_successes="${reconnect_smoke_successes:-0}" \
  -v reconnect_smoke_protocol_change="${reconnect_smoke_protocol_change:-0}" \
  -v reconnect_smoke_required="$RUN_RECONNECT_SMOKE" \
  -v proto_diff_count="$proto_diff_count" \
  -v client_lifecycle_tests="$client_lifecycle_tests" \
  -v design_doc="$DESIGN_DOC" \
  -v networking_summary="$NETWORKING_SUMMARY" \
  -v reconnect_smoke_summary="$RECONNECT_SMOKE_SUMMARY" '
  BEGIN {
    status = "pass"
    reason = "ok"
    reconnect_ok = reconnect_smoke_status == "pass" &&
      reconnect_smoke_client_state == "active" &&
      reconnect_smoke_reader_errors + 0 >= 1 &&
      reconnect_smoke_successes + 0 >= 1 &&
      reconnect_smoke_protocol_change + 0 == 0
    state_machine_status = reconnect_ok ? "runtime_guarded" : "unit_guarded"
    runtime_reconnect = reconnect_ok ? "live_rebootstrap_guarded" : "deferred"
    state_telemetry = reconnect_ok ? "live_marker_guarded" : "source_guarded"
    active_protocol_change = proto_diff_count + 0

    networking_ok = networking_status == "pass" && networking_protocol_change + 0 == 0
    tests_ok = client_lifecycle_tests == "pass" || client_lifecycle_tests == "skipped"

    if (active_protocol_change != 0) {
      status = "fail"
      reason = "protocol_diff_present"
    } else if (!networking_ok) {
      status = "fail"
      reason = "networking_robustness_gate_not_clean"
    } else if (reconnect_smoke_required == "1" && !reconnect_ok) {
      status = "fail"
      reason = "reconnect_smoke_failed"
    } else if (!tests_ok) {
      status = "fail"
      reason = "client_lifecycle_tests_failed"
    }

    printf("client_state_machine_hardening status=%s reason=%s state_machine_status=%s active_protocol_change=%d client_lifecycle_tests=%s runtime_reconnect=%s state_telemetry=%s reconnect_smoke_status=%s reconnect_smoke_client_state=%s reconnect_smoke_reader_errors=%d reconnect_smoke_successes=%d networking_status=%s networking_protocol_change=%d design_doc=%s networking_summary=%s reconnect_smoke_summary=%s\n", status, reason, state_machine_status, active_protocol_change, client_lifecycle_tests, runtime_reconnect, state_telemetry, reconnect_smoke_status, reconnect_smoke_client_state, reconnect_smoke_reader_errors, reconnect_smoke_successes, networking_status, networking_protocol_change, design_doc, networking_summary, reconnect_smoke_summary)
    if (status != "pass") {
      exit 1
    }
  }
' > "$SUMMARY_PATH" || {
  cat "$SUMMARY_PATH" >&2 || true
  fail "client state machine hardening gate failed"
}

cat "$SUMMARY_PATH"
echo "Client state machine hardening artifacts: $OUT_DIR"
