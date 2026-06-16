#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/networking_robustness"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

SUMMARY_PATH="$OUT_DIR/networking-robustness-summary.txt"
DESIGN_DOC="${RUMPELMC_NETWORKING_ROBUSTNESS_DOC:-"$ROOT_DIR/docs/NETWORKING_ROBUSTNESS_PROGRAM.md"}"
PROTOCOL_DOC="${RUMPELMC_NETWORKING_ROBUSTNESS_PROTOCOL_DOC:-"$ROOT_DIR/docs/PROTOCOL.md"}"
SERVER_SOURCE="${RUMPELMC_NETWORKING_ROBUSTNESS_SERVER_SOURCE:-"$ROOT_DIR/server/pkg/network/server.go"}"
SERVER_TEST="${RUMPELMC_NETWORKING_ROBUSTNESS_SERVER_TEST:-"$ROOT_DIR/server/pkg/network/framing_test.go"}"
SERVER_SESSION_TEST="${RUMPELMC_NETWORKING_ROBUSTNESS_SERVER_SESSION_TEST:-"$ROOT_DIR/server/pkg/network/server_test.go"}"
CLIENT_SOURCE="${RUMPELMC_NETWORKING_ROBUSTNESS_CLIENT_SOURCE:-"$ROOT_DIR/client/rust_ext/src/network.rs"}"
CLIENT_RUNTIME_SOURCE="${RUMPELMC_NETWORKING_ROBUSTNESS_CLIENT_RUNTIME_SOURCE:-"$ROOT_DIR/client/rust_ext/src/lib.rs"}"
SERVER_SCALABILITY_SUMMARY="${RUMPELMC_NETWORKING_ROBUSTNESS_SERVER_SCALABILITY_SUMMARY:-"$ROOT_DIR/logs/server_scalability_pass_current/server-scalability-pass-summary.txt"}"
SLOW_READER_SMOKE_SCRIPT="${RUMPELMC_NETWORKING_ROBUSTNESS_SLOW_READER_SMOKE_SCRIPT:-"$ROOT_DIR/scripts/server_slow_reader_smoke.sh"}"
SLOW_READER_SMOKE_SUMMARY="${RUMPELMC_NETWORKING_ROBUSTNESS_SLOW_READER_SMOKE_SUMMARY:-"$ROOT_DIR/logs/server_slow_reader_smoke_current/server-slow-reader-smoke-summary.txt"}"
SLOW_READER_MATRIX_SCRIPT="${RUMPELMC_NETWORKING_ROBUSTNESS_SLOW_READER_MATRIX_SCRIPT:-"$ROOT_DIR/scripts/server_slow_reader_matrix_smoke.sh"}"
SLOW_READER_MATRIX_SUMMARY="${RUMPELMC_NETWORKING_ROBUSTNESS_SLOW_READER_MATRIX_SUMMARY:-"$ROOT_DIR/logs/server_slow_reader_matrix_current/server-slow-reader-matrix-summary.txt"}"
RECONNECT_SMOKE_SCRIPT="${RUMPELMC_NETWORKING_ROBUSTNESS_RECONNECT_SMOKE_SCRIPT:-"$ROOT_DIR/scripts/client_reconnect_smoke.sh"}"
RECONNECT_SMOKE_SUMMARY="${RUMPELMC_NETWORKING_ROBUSTNESS_RECONNECT_SMOKE_SUMMARY:-"$ROOT_DIR/logs/client_reconnect_smoke_current/client-reconnect-smoke-summary.txt"}"
RECONNECT_SOAK_SCRIPT="${RUMPELMC_NETWORKING_ROBUSTNESS_RECONNECT_SOAK_SCRIPT:-"$ROOT_DIR/scripts/client_reconnect_soak.sh"}"
RECONNECT_SOAK_SUMMARY="${RUMPELMC_NETWORKING_ROBUSTNESS_RECONNECT_SOAK_SUMMARY:-"$ROOT_DIR/logs/client_reconnect_soak_current/client-reconnect-soak-summary.txt"}"
PACKET_ERROR_SUMMARY_SCRIPT="${RUMPELMC_NETWORKING_ROBUSTNESS_PACKET_ERROR_SUMMARY_SCRIPT:-"$ROOT_DIR/scripts/packet_error_class_summary.sh"}"
PACKET_ERROR_ALERT_SCRIPT="${RUMPELMC_NETWORKING_ROBUSTNESS_PACKET_ERROR_ALERT_SCRIPT:-"$ROOT_DIR/scripts/packet_error_alert_threshold_gate.sh"}"
PACKET_ERROR_ALERT_SUMMARY="${RUMPELMC_NETWORKING_ROBUSTNESS_PACKET_ERROR_ALERT_SUMMARY:-"$ROOT_DIR/logs/packet_error_alert_threshold_current/packet-error-alert-threshold-summary.txt"}"
PACKET_ERROR_SUMMARY_DIR="${RUMPELMC_NETWORKING_ROBUSTNESS_PACKET_ERROR_SUMMARY_DIR:-"$OUT_DIR"}"
case "$PACKET_ERROR_SUMMARY_DIR" in
  /*) ;;
  *) PACKET_ERROR_SUMMARY_DIR="$ROOT_DIR/$PACKET_ERROR_SUMMARY_DIR" ;;
esac
PACKET_ERROR_SUMMARY="$PACKET_ERROR_SUMMARY_DIR/packet-error-class-summary.txt"
RUN_GO_TESTS="${RUMPELMC_NETWORKING_ROBUSTNESS_RUN_GO_TESTS:-1}"
RUN_RUST_TESTS="${RUMPELMC_NETWORKING_ROBUSTNESS_RUN_RUST_TESTS:-1}"
RUN_SLOW_READER_SMOKE="${RUMPELMC_NETWORKING_ROBUSTNESS_RUN_SLOW_READER_SMOKE:-0}"
RUN_SLOW_READER_MATRIX="${RUMPELMC_NETWORKING_ROBUSTNESS_RUN_SLOW_READER_MATRIX:-0}"
RUN_RECONNECT_SMOKE="${RUMPELMC_NETWORKING_ROBUSTNESS_RUN_RECONNECT_SMOKE:-0}"
RUN_RECONNECT_SOAK="${RUMPELMC_NETWORKING_ROBUSTNESS_RUN_RECONNECT_SOAK:-0}"

mkdir -p "$OUT_DIR"

fail() {
  echo "networking_robustness_gate: $*" >&2
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

for path in "$DESIGN_DOC" "$PROTOCOL_DOC" "$SERVER_SOURCE" "$SERVER_TEST" "$SERVER_SESSION_TEST" "$CLIENT_SOURCE" "$CLIENT_RUNTIME_SOURCE" "$SERVER_SCALABILITY_SUMMARY" "$SLOW_READER_SMOKE_SCRIPT" "$SLOW_READER_MATRIX_SCRIPT" "$RECONNECT_SMOKE_SCRIPT" "$RECONNECT_SOAK_SCRIPT" "$PACKET_ERROR_SUMMARY_SCRIPT" "$PACKET_ERROR_ALERT_SCRIPT"; do
  test -s "$path" || fail "missing required input $path"
done

for token in \
  'Current Robustness Contract' \
  'Added Client Guards' \
  'Session/Stale Packet Policy' \
  'Existing Server Guards' \
  'Deferred Robustness Work' \
  'Compatibility Rules' \
  'Live Reconnect Smoke' \
  'Repeated Reconnect Soak' \
  'Live Slow-Reader Smoke' \
  'Slow-Reader Load Matrix' \
  'Packet Error Alert Thresholds' \
  'Sustained max-client sizing'; do
  require_token "$DESIGN_DOC" "$token"
done

require_token "$PROTOCOL_DOC" 'Readers must consume exactly the advertised payload length before decoding.'
require_token "$PROTOCOL_DOC" 'Error handling for malformed, partial, or unknown packets.'

require_token "$SERVER_SOURCE" 'const maxPacketSize = 16 * 1024 * 1024'
require_token "$SERVER_SOURCE" 'io.ReadFull(conn, lenBuf)'
require_token "$SERVER_SOURCE" 'io.ReadFull(conn, dataBuf)'
require_token "$SERVER_SOURCE" 'packet too large'
require_token "$SERVER_SOURCE" 'func writeFull(writer io.Writer, data []byte) error'
require_token "$SERVER_SOURCE" 'io.ErrShortWrite'
require_token "$SERVER_SOURCE" 'SetWriteDeadline'
require_token "$SERVER_SOURCE" 'disconnectClient'
require_token "$SERVER_SOURCE" 'func classifyNetworkError'
require_token "$SERVER_SOURCE" 'packet_error_class='
require_token "$SERVER_TEST" 'TestReceivePacketReturnsOnShortFrame'
require_token "$SERVER_TEST" 'TestReceivePacketReturnsOnShortPayload'
require_token "$SERVER_TEST" 'TestReceivePacketRejectsOversizedLength'
require_token "$SERVER_TEST" 'TestReceivePacketRejectsMalformedPayload'
require_token "$SERVER_TEST" 'TestReceivePacketAcceptsEmptyPayloadFrame'
require_token "$SERVER_TEST" 'TestReceivePacketConsumesExactFrameBoundaries'
require_token "$SERVER_TEST" 'TestNetworkErrorClassification'
require_token "$SERVER_TEST" 'TestWriteFullClassifiesZeroByteWriteAsShortWrite'
require_token "$SERVER_TEST" 'TestHandleConnectionLogsPacketErrorClassForMalformedInitialPacket'
require_token "$SERVER_TEST" 'TestReceiveInitialClientPacketTreatsTimeoutProbeAsNoPacket'
require_token "$SERVER_SESSION_TEST" 'TestConfiguredClientWriteTimeoutParsesSupportedValues'
require_token "$SERVER_SESSION_TEST" 'TestHandleInitialClientPacketIgnoresNilPacket'
require_token "$SERVER_SESSION_TEST" 'TestHandleClientPacketIgnoresNilPacket'
require_token "$SERVER_SESSION_TEST" 'TestHandleInitialClientPacketIgnoresNilPosition'
require_token "$SERVER_SESSION_TEST" 'TestHandleClientPacketIgnoresNilPosition'
require_token "$SERVER_SESSION_TEST" 'TestSendChunkToSessionSetsAndClearsWriteDeadline'
require_token "$SERVER_SESSION_TEST" 'TestBroadcastDisconnectsFailedInterestedClient'
require_token "$SERVER_SESSION_TEST" 'TestHandleClientPacketIgnoresEmptyPayload'
require_token "$SERVER_SESSION_TEST" 'TestHandleClientPacketIgnoresNilBlockAction'
require_token "$SLOW_READER_SMOKE_SCRIPT" 'server_slow_reader_smoke status=pass'
require_token "$SLOW_READER_SMOKE_SCRIPT" 'packet_error_class=timeout'
require_token "$SLOW_READER_MATRIX_SCRIPT" 'server_slow_reader_matrix status='
require_token "$RECONNECT_SMOKE_SCRIPT" 'client_reconnect_smoke status=pass'
require_token "$RECONNECT_SOAK_SCRIPT" 'client_reconnect_soak status=pass'
require_token "$PACKET_ERROR_ALERT_SCRIPT" 'packet_error_alert_threshold status='
require_token "$PACKET_ERROR_ALERT_SCRIPT" 'protocol_error_threshold_exceeded'

require_token "$CLIENT_SOURCE" 'const MAX_PACKET_LENGTH: usize = 16 * 1024 * 1024;'
require_token "$CLIENT_SOURCE" 'self.stream.read_exact(&mut len_buf)?;'
require_token "$CLIENT_SOURCE" 'self.stream.read_exact(&mut data_buf)?;'
require_token "$CLIENT_SOURCE" 'Packet::decode(&data_buf[..])'
require_token "$CLIENT_SOURCE" 'receive_rejects_oversized_packet_length'
require_token "$CLIENT_SOURCE" 'receive_returns_unexpected_eof_on_short_length_prefix'
require_token "$CLIENT_SOURCE" 'receive_returns_unexpected_eof_on_short_payload'
require_token "$CLIENT_SOURCE" 'receive_rejects_malformed_payload'
require_token "$CLIENT_RUNTIME_SOURCE" 'fn drain_network_reader_events'
require_token "$CLIENT_RUNTIME_SOURCE" 'network_session_id'
require_token "$CLIENT_RUNTIME_SOURCE" 'network_stale_events={}'
require_token "$CLIENT_RUNTIME_SOURCE" 'network_reader_drain_discards_stale_session_events'
require_token "$CLIENT_RUNTIME_SOURCE" 'network_reader_drain_resets_current_session_packets_on_error'

server_scalability_status="$(field_metric status "$SERVER_SCALABILITY_SUMMARY")"
server_scalability_repeat_status="$(field_metric scalability_status "$SERVER_SCALABILITY_SUMMARY")"
server_scalability_resource_profile_status="$(field_metric resource_profile_status "$SERVER_SCALABILITY_SUMMARY")"
server_scalability_protocol_change="$(field_metric active_protocol_change "$SERVER_SCALABILITY_SUMMARY")"
server_scalability_slow_client="$(field_metric slow_client_write_timeout "$SERVER_SCALABILITY_SUMMARY")"
server_scalability_live_load="$(field_metric live_load_status "$SERVER_SCALABILITY_SUMMARY")"
server_scalability_admission_policy="$(field_metric admission_policy "$SERVER_SCALABILITY_SUMMARY")"
server_scalability_multi_client_sent_state="$(field_metric multi_client_sent_state "$SERVER_SCALABILITY_SUMMARY")"
server_scalability_block_edit_fanout="$(field_metric block_edit_fanout "$SERVER_SCALABILITY_SUMMARY")"
server_scalability_conflict_semantics="$(field_metric conflict_semantics "$SERVER_SCALABILITY_SUMMARY")"
server_scalability_chunk_request_ordering="$(field_metric chunk_request_ordering "$SERVER_SCALABILITY_SUMMARY")"
server_scalability_worldgen_biome_atlas_tile_identity="$(field_metric worldgen_biome_atlas_tile_identity "$SERVER_SCALABILITY_SUMMARY")"
server_scalability_worldgen_biome_atlas_block_texture_usage="$(field_metric worldgen_biome_atlas_block_texture_usage "$SERVER_SCALABILITY_SUMMARY")"
server_scalability_nil_sent_state_policy="$(field_metric nil_sent_state_policy "$SERVER_SCALABILITY_SUMMARY")"
server_scalability_view_distance_config="$(field_metric view_distance_config "$SERVER_SCALABILITY_SUMMARY")"
server_scalability_disconnect_cleanup_status="$(field_metric disconnect_cleanup_status "$SERVER_SCALABILITY_SUMMARY")"
server_scalability_connection_lifecycle_status="$(field_metric connection_lifecycle_status "$SERVER_SCALABILITY_SUMMARY")"
server_scalability_connection_lifecycle_packet_error_disconnects="$(field_metric connection_lifecycle_packet_error_disconnects "$SERVER_SCALABILITY_SUMMARY")"
server_scalability_connection_lifecycle_eof_disconnects="$(field_metric connection_lifecycle_eof_disconnects "$SERVER_SCALABILITY_SUMMARY")"
server_scalability_connection_lifecycle_timeout_disconnects="$(field_metric connection_lifecycle_timeout_disconnects "$SERVER_SCALABILITY_SUMMARY")"
server_scalability_connection_lifecycle_close_failures="$(field_metric connection_lifecycle_close_failures "$SERVER_SCALABILITY_SUMMARY")"
server_scalability_connection_lifecycle_accept_failures="$(field_metric connection_lifecycle_accept_failures "$SERVER_SCALABILITY_SUMMARY")"
server_scalability_connection_lifecycle_missing_active_client_fields="$(field_metric connection_lifecycle_missing_active_client_fields "$SERVER_SCALABILITY_SUMMARY")"
case "$RUN_SLOW_READER_SMOKE" in
  0) ;;
  1)
    slow_reader_smoke_dir="$(dirname "$SLOW_READER_SMOKE_SUMMARY")"
    "$SLOW_READER_SMOKE_SCRIPT" "$slow_reader_smoke_dir" > "$OUT_DIR/slow-reader-smoke-run.txt" 2>&1 || {
      cat "$OUT_DIR/slow-reader-smoke-run.txt" >&2 || true
      fail "live slow-reader smoke failed"
    }
    ;;
  *)
    fail "unsupported RUMPELMC_NETWORKING_ROBUSTNESS_RUN_SLOW_READER_SMOKE=$RUN_SLOW_READER_SMOKE"
    ;;
esac
case "$RUN_SLOW_READER_MATRIX" in
  0) ;;
  1)
    slow_reader_matrix_dir="$(dirname "$SLOW_READER_MATRIX_SUMMARY")"
    "$SLOW_READER_MATRIX_SCRIPT" "$slow_reader_matrix_dir" > "$OUT_DIR/slow-reader-matrix-run.txt" 2>&1 || {
      cat "$OUT_DIR/slow-reader-matrix-run.txt" >&2 || true
      fail "slow-reader matrix failed"
    }
    ;;
  *)
    fail "unsupported RUMPELMC_NETWORKING_ROBUSTNESS_RUN_SLOW_READER_MATRIX=$RUN_SLOW_READER_MATRIX"
    ;;
esac
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
    fail "unsupported RUMPELMC_NETWORKING_ROBUSTNESS_RUN_RECONNECT_SMOKE=$RUN_RECONNECT_SMOKE"
    ;;
esac
case "$RUN_RECONNECT_SOAK" in
  0) ;;
  1)
    reconnect_soak_dir="$(dirname "$RECONNECT_SOAK_SUMMARY")"
    "$RECONNECT_SOAK_SCRIPT" "$reconnect_soak_dir" > "$OUT_DIR/reconnect-soak-run.txt" 2>&1 || {
      cat "$OUT_DIR/reconnect-soak-run.txt" >&2 || true
      fail "repeated reconnect soak failed"
    }
    ;;
  *)
    fail "unsupported RUMPELMC_NETWORKING_ROBUSTNESS_RUN_RECONNECT_SOAK=$RUN_RECONNECT_SOAK"
    ;;
esac
test -s "$SLOW_READER_SMOKE_SUMMARY" || fail "missing required input $SLOW_READER_SMOKE_SUMMARY"
test -s "$SLOW_READER_MATRIX_SUMMARY" || fail "missing required input $SLOW_READER_MATRIX_SUMMARY"
test -s "$RECONNECT_SMOKE_SUMMARY" || fail "missing required input $RECONNECT_SMOKE_SUMMARY"
test -s "$RECONNECT_SOAK_SUMMARY" || fail "missing required input $RECONNECT_SOAK_SUMMARY"

slow_reader_smoke_status="missing"
slow_reader_timeout_observed="0"
slow_reader_timeout_class="missing"
slow_reader_smoke_status="$(field_metric status "$SLOW_READER_SMOKE_SUMMARY")"
slow_reader_timeout_observed="$(field_metric slow_timeout_observed "$SLOW_READER_SMOKE_SUMMARY")"
slow_reader_timeout_class="$(field_metric slow_timeout_class "$SLOW_READER_SMOKE_SUMMARY")"
slow_reader_matrix_status="missing"
slow_reader_matrix_counts_checked="0"
slow_reader_matrix_passed_counts="0"
slow_reader_matrix_max_fast_clients="0"
slow_reader_matrix_total_fast_clients="0"
slow_reader_matrix_total_fast_bootstrap_chunks="0"
slow_reader_matrix_total_slow_timeouts="0"
slow_reader_matrix_protocol_change="0"
slow_reader_matrix_status="$(field_metric status "$SLOW_READER_MATRIX_SUMMARY")"
slow_reader_matrix_counts_checked="$(field_metric counts_checked "$SLOW_READER_MATRIX_SUMMARY")"
slow_reader_matrix_passed_counts="$(field_metric passed_counts "$SLOW_READER_MATRIX_SUMMARY")"
slow_reader_matrix_max_fast_clients="$(field_metric max_fast_clients "$SLOW_READER_MATRIX_SUMMARY")"
slow_reader_matrix_total_fast_clients="$(field_metric total_fast_clients "$SLOW_READER_MATRIX_SUMMARY")"
slow_reader_matrix_total_fast_bootstrap_chunks="$(field_metric total_fast_bootstrap_chunks "$SLOW_READER_MATRIX_SUMMARY")"
slow_reader_matrix_total_slow_timeouts="$(field_metric total_slow_timeouts "$SLOW_READER_MATRIX_SUMMARY")"
slow_reader_matrix_protocol_change="$(field_metric protocol_change "$SLOW_READER_MATRIX_SUMMARY")"
reconnect_smoke_status="missing"
reconnect_smoke_client_state="missing"
reconnect_smoke_reader_errors="0"
reconnect_smoke_successes="0"
reconnect_smoke_protocol_change="0"
reconnect_smoke_status="$(field_metric status "$RECONNECT_SMOKE_SUMMARY")"
reconnect_smoke_client_state="$(field_metric client_state "$RECONNECT_SMOKE_SUMMARY")"
reconnect_smoke_reader_errors="$(field_metric network_reader_errors "$RECONNECT_SMOKE_SUMMARY")"
reconnect_smoke_successes="$(field_metric reconnect_successes "$RECONNECT_SMOKE_SUMMARY")"
reconnect_smoke_protocol_change="$(field_metric active_protocol_change "$RECONNECT_SMOKE_SUMMARY")"
reconnect_soak_status="missing"
reconnect_soak_client_state="missing"
reconnect_soak_cycles="0"
reconnect_soak_reader_errors="0"
reconnect_soak_successes="0"
reconnect_soak_protocol_change="0"
reconnect_soak_status="$(field_metric status "$RECONNECT_SOAK_SUMMARY")"
reconnect_soak_client_state="$(field_metric client_state "$RECONNECT_SOAK_SUMMARY")"
reconnect_soak_cycles="$(field_metric reconnect_cycles "$RECONNECT_SOAK_SUMMARY")"
reconnect_soak_reader_errors="$(field_metric network_reader_errors "$RECONNECT_SOAK_SUMMARY")"
reconnect_soak_successes="$(field_metric reconnect_successes "$RECONNECT_SOAK_SUMMARY")"
reconnect_soak_protocol_change="$(field_metric active_protocol_change "$RECONNECT_SOAK_SUMMARY")"

packet_error_fixture="$OUT_DIR/packet-error-class-fixture.log"
cat > "$packet_error_fixture" <<'EOF'
Client disconnected packet_error_class=eof: read packet length: EOF
Client disconnected packet_error_class=short_frame: read packet payload: unexpected EOF
Client disconnected packet_error_class=oversized_frame: packet too large: 16777217 bytes
Client disconnected packet_error_class=malformed_protobuf: malformed protobuf
Client disconnected packet_error_class=timeout: i/o timeout
Client disconnected packet_error_class=short_write: short write
Client disconnected packet_error_class=encode_error: packet encode
Client disconnected packet_error_class=other: closed pipe
EOF
if "$PACKET_ERROR_SUMMARY_SCRIPT" "$PACKET_ERROR_SUMMARY_DIR" "$packet_error_fixture" > "$OUT_DIR/packet-error-class-summary-run.txt" 2>&1; then
  packet_error_summary_status="$(field_metric status "$PACKET_ERROR_SUMMARY")"
  packet_error_summary_events="$(field_metric classified_events "$PACKET_ERROR_SUMMARY")"
  packet_error_summary_unknown="$(field_metric unknown_classes "$PACKET_ERROR_SUMMARY")"
else
  cat "$OUT_DIR/packet-error-class-summary-run.txt" >&2 || true
  fail "packet error class summary self-check failed"
fi
packet_error_alert_dir="$(dirname "$PACKET_ERROR_ALERT_SUMMARY")"
if "$PACKET_ERROR_ALERT_SCRIPT" "$packet_error_alert_dir" > "$OUT_DIR/packet-error-alert-threshold-run.txt" 2>&1; then
  packet_error_alert_status="$(field_metric status "$PACKET_ERROR_ALERT_SUMMARY")"
  packet_error_alert_guard="$(field_metric alert_status "$PACKET_ERROR_ALERT_SUMMARY")"
  packet_error_alert_protocol_errors="$(field_metric protocol_errors "$PACKET_ERROR_ALERT_SUMMARY")"
  packet_error_alert_write_errors="$(field_metric write_errors "$PACKET_ERROR_ALERT_SUMMARY")"
  packet_error_alert_unknown_classes="$(field_metric unknown_classes "$PACKET_ERROR_ALERT_SUMMARY")"
else
  cat "$OUT_DIR/packet-error-alert-threshold-run.txt" >&2 || true
  fail "packet error alert threshold gate failed"
fi
proto_diff_count="$(git -C "$ROOT_DIR" diff --name-only -- api/schema/packets.proto server/pkg/api/packets.pb.go | awk 'END { print NR + 0 }')"

server_boundary_tests="skipped"
if [ "$RUN_GO_TESTS" = "1" ]; then
  if (cd "$ROOT_DIR/server" && go test ./pkg/network > "$OUT_DIR/go-test-network.txt" 2>&1); then
    server_boundary_tests="pass"
  else
    cat "$OUT_DIR/go-test-network.txt" >&2 || true
    server_boundary_tests="fail"
  fi
fi

client_boundary_tests="skipped"
if [ "$RUN_RUST_TESTS" = "1" ]; then
  if (
    cd "$ROOT_DIR/client/rust_ext" &&
      cargo test --lib network::tests::receive > "$OUT_DIR/cargo-test-network.txt" 2>&1 &&
      cargo test --lib network_reader_drain > "$OUT_DIR/cargo-test-network-reader-drain.txt" 2>&1
  ); then
    client_boundary_tests="pass"
  else
    cat "$OUT_DIR/cargo-test-network.txt" >&2 || true
    cat "$OUT_DIR/cargo-test-network-reader-drain.txt" >&2 || true
    client_boundary_tests="fail"
  fi
fi

awk \
  -v server_scalability_status="${server_scalability_status:-missing}" \
  -v server_scalability_repeat_status="${server_scalability_repeat_status:-missing}" \
  -v server_scalability_resource_profile_status="${server_scalability_resource_profile_status:-missing}" \
  -v server_scalability_protocol_change="${server_scalability_protocol_change:-1}" \
  -v server_scalability_slow_client="${server_scalability_slow_client:-deferred}" \
  -v server_scalability_live_load="${server_scalability_live_load:-deferred}" \
  -v server_scalability_admission_policy="${server_scalability_admission_policy:-deferred}" \
  -v server_scalability_multi_client_sent_state="${server_scalability_multi_client_sent_state:-missing}" \
  -v server_scalability_block_edit_fanout="${server_scalability_block_edit_fanout:-missing}" \
  -v server_scalability_conflict_semantics="${server_scalability_conflict_semantics:-missing}" \
  -v server_scalability_chunk_request_ordering="${server_scalability_chunk_request_ordering:-missing}" \
  -v server_scalability_worldgen_biome_atlas_tile_identity="${server_scalability_worldgen_biome_atlas_tile_identity:-missing}" \
  -v server_scalability_worldgen_biome_atlas_block_texture_usage="${server_scalability_worldgen_biome_atlas_block_texture_usage:-missing}" \
  -v server_scalability_nil_sent_state_policy="${server_scalability_nil_sent_state_policy:-missing}" \
  -v server_scalability_view_distance_config="${server_scalability_view_distance_config:-missing}" \
  -v server_scalability_disconnect_cleanup_status="${server_scalability_disconnect_cleanup_status:-missing}" \
  -v server_scalability_connection_lifecycle_status="${server_scalability_connection_lifecycle_status:-missing}" \
  -v server_scalability_connection_lifecycle_packet_error_disconnects="${server_scalability_connection_lifecycle_packet_error_disconnects:-0}" \
  -v server_scalability_connection_lifecycle_eof_disconnects="${server_scalability_connection_lifecycle_eof_disconnects:-0}" \
  -v server_scalability_connection_lifecycle_timeout_disconnects="${server_scalability_connection_lifecycle_timeout_disconnects:-0}" \
  -v server_scalability_connection_lifecycle_close_failures="${server_scalability_connection_lifecycle_close_failures:-0}" \
  -v server_scalability_connection_lifecycle_accept_failures="${server_scalability_connection_lifecycle_accept_failures:-0}" \
  -v server_scalability_connection_lifecycle_missing_active_client_fields="${server_scalability_connection_lifecycle_missing_active_client_fields:-0}" \
  -v slow_reader_smoke_status="${slow_reader_smoke_status:-missing}" \
  -v slow_reader_timeout_observed="${slow_reader_timeout_observed:-0}" \
  -v slow_reader_timeout_class="${slow_reader_timeout_class:-missing}" \
  -v slow_reader_matrix_status="${slow_reader_matrix_status:-missing}" \
  -v slow_reader_matrix_counts_checked="${slow_reader_matrix_counts_checked:-0}" \
  -v slow_reader_matrix_passed_counts="${slow_reader_matrix_passed_counts:-0}" \
  -v slow_reader_matrix_max_fast_clients="${slow_reader_matrix_max_fast_clients:-0}" \
  -v slow_reader_matrix_total_fast_clients="${slow_reader_matrix_total_fast_clients:-0}" \
  -v slow_reader_matrix_total_fast_bootstrap_chunks="${slow_reader_matrix_total_fast_bootstrap_chunks:-0}" \
  -v slow_reader_matrix_total_slow_timeouts="${slow_reader_matrix_total_slow_timeouts:-0}" \
  -v slow_reader_matrix_protocol_change="${slow_reader_matrix_protocol_change:-0}" \
  -v reconnect_smoke_status="${reconnect_smoke_status:-missing}" \
  -v reconnect_smoke_client_state="${reconnect_smoke_client_state:-missing}" \
  -v reconnect_smoke_reader_errors="${reconnect_smoke_reader_errors:-0}" \
  -v reconnect_smoke_successes="${reconnect_smoke_successes:-0}" \
  -v reconnect_smoke_protocol_change="${reconnect_smoke_protocol_change:-0}" \
  -v reconnect_soak_status="${reconnect_soak_status:-missing}" \
  -v reconnect_soak_client_state="${reconnect_soak_client_state:-missing}" \
  -v reconnect_soak_cycles="${reconnect_soak_cycles:-0}" \
  -v reconnect_soak_reader_errors="${reconnect_soak_reader_errors:-0}" \
  -v reconnect_soak_successes="${reconnect_soak_successes:-0}" \
  -v reconnect_soak_protocol_change="${reconnect_soak_protocol_change:-0}" \
  -v packet_error_summary_status="${packet_error_summary_status:-missing}" \
  -v packet_error_summary_events="${packet_error_summary_events:-0}" \
  -v packet_error_summary_unknown="${packet_error_summary_unknown:-1}" \
  -v packet_error_summary="$PACKET_ERROR_SUMMARY" \
  -v packet_error_alert_status="${packet_error_alert_status:-missing}" \
  -v packet_error_alert_guard="${packet_error_alert_guard:-missing}" \
  -v packet_error_alert_protocol_errors="${packet_error_alert_protocol_errors:-1}" \
  -v packet_error_alert_write_errors="${packet_error_alert_write_errors:-1}" \
  -v packet_error_alert_unknown_classes="${packet_error_alert_unknown_classes:-1}" \
  -v packet_error_alert_summary="$PACKET_ERROR_ALERT_SUMMARY" \
  -v proto_diff_count="$proto_diff_count" \
  -v server_boundary_tests="$server_boundary_tests" \
  -v client_boundary_tests="$client_boundary_tests" \
  -v design_doc="$DESIGN_DOC" \
  -v server_scalability_summary="$SERVER_SCALABILITY_SUMMARY" \
  -v slow_reader_smoke_summary="$SLOW_READER_SMOKE_SUMMARY" \
  -v slow_reader_matrix_summary="$SLOW_READER_MATRIX_SUMMARY" \
  -v reconnect_smoke_summary="$RECONNECT_SMOKE_SUMMARY" \
  -v reconnect_soak_summary="$RECONNECT_SOAK_SUMMARY" '
  BEGIN {
    status = "pass"
    reason = "ok"
    robustness_status = "unit_guarded"
    reconnect_ok = reconnect_smoke_status == "pass" &&
      reconnect_smoke_client_state == "active" &&
      reconnect_smoke_reader_errors + 0 >= 1 &&
      reconnect_smoke_successes + 0 >= 1 &&
      reconnect_smoke_protocol_change + 0 == 0
    reconnect_soak_ok = reconnect_soak_status == "pass" &&
      reconnect_soak_client_state == "active" &&
      reconnect_soak_cycles + 0 >= 2 &&
      reconnect_soak_reader_errors + 0 >= reconnect_soak_cycles + 0 &&
      reconnect_soak_successes + 0 >= reconnect_soak_cycles + 0 &&
      reconnect_soak_protocol_change + 0 == 0
    reconnect_status = reconnect_soak_ok ? "repeated_live_rebootstrap_guarded" : (reconnect_ok ? "live_rebootstrap_guarded" : "deferred")
    stale_packet_policy = client_boundary_tests == "pass" ? "session_guarded" : "source_guarded"
    unknown_packet_policy = "ignored_guarded"
    nil_packet_policy = "ignored_guarded"
    nil_position_policy = "ignored_guarded"
    nil_block_action_policy = "ignored_guarded"
    empty_payload_frame = server_boundary_tests == "pass" ? "decode_guarded" : "source_guarded"
    packet_error_classification = server_boundary_tests == "pass" ? "unit_guarded" : "source_guarded"
    packet_error_summary_ok = packet_error_summary_status == "pass" && packet_error_summary_events + 0 == 8 && packet_error_summary_unknown + 0 == 0
    packet_error_aggregation = packet_error_summary_ok ? "parser_guarded" : "fail"
    packet_error_alert_ok = packet_error_alert_status == "pass" &&
      packet_error_alert_guard == "threshold_guarded" &&
      packet_error_alert_protocol_errors + 0 == 0 &&
      packet_error_alert_write_errors + 0 == 0 &&
      packet_error_alert_unknown_classes + 0 == 0
    packet_error_alerts = packet_error_alert_ok ? "threshold_guarded" : "fail"
    slow_reader_ok = slow_reader_smoke_status == "pass" && slow_reader_timeout_observed + 0 == 1 && slow_reader_timeout_class == "timeout"
    slow_reader_matrix_ok = slow_reader_matrix_status == "pass" &&
      slow_reader_matrix_counts_checked + 0 >= 2 &&
      slow_reader_matrix_passed_counts + 0 == slow_reader_matrix_counts_checked + 0 &&
      slow_reader_matrix_max_fast_clients + 0 >= 2 &&
      slow_reader_matrix_total_fast_clients + 0 == slow_reader_matrix_total_fast_bootstrap_chunks + 0 &&
      slow_reader_matrix_total_slow_timeouts + 0 == slow_reader_matrix_counts_checked + 0 &&
      slow_reader_matrix_protocol_change + 0 == 0
    slow_client_status = slow_reader_matrix_ok ? "load_matrix_guarded" : (slow_reader_ok ? "live_guarded" : (server_scalability_slow_client == "guarded" ? "unit_guarded" : "deferred"))
    scalability_status = server_scalability_repeat_status
    resource_profile_status = server_scalability_resource_profile_status
    multi_client_live_status = server_scalability_live_load
    multi_client_sent_state = server_scalability_multi_client_sent_state
    block_edit_fanout = server_scalability_block_edit_fanout
    conflict_semantics = server_scalability_conflict_semantics
    chunk_request_ordering = server_scalability_chunk_request_ordering
    worldgen_biome_atlas_tile_identity = server_scalability_worldgen_biome_atlas_tile_identity
    worldgen_biome_atlas_block_texture_usage = server_scalability_worldgen_biome_atlas_block_texture_usage
    nil_sent_state_policy = server_scalability_nil_sent_state_policy
    view_distance_config = server_scalability_view_distance_config
    disconnect_cleanup_status = server_scalability_disconnect_cleanup_status
    connection_lifecycle_status = server_scalability_connection_lifecycle_status
    connection_lifecycle_packet_error_disconnects = server_scalability_connection_lifecycle_packet_error_disconnects
    connection_lifecycle_eof_disconnects = server_scalability_connection_lifecycle_eof_disconnects
    connection_lifecycle_timeout_disconnects = server_scalability_connection_lifecycle_timeout_disconnects
    connection_lifecycle_close_failures = server_scalability_connection_lifecycle_close_failures
    connection_lifecycle_accept_failures = server_scalability_connection_lifecycle_accept_failures
    connection_lifecycle_missing_active_client_fields = server_scalability_connection_lifecycle_missing_active_client_fields
    overload_status = server_scalability_admission_policy == "matrix_live_guarded" ? "admission_matrix_guarded" : (server_scalability_admission_policy == "live_guarded" ? "admission_live_guarded" : (server_scalability_admission_policy == "unit_guarded" ? "admission_unit_guarded" : "deferred"))
    active_protocol_change = proto_diff_count + 0

    scalability_ok = server_scalability_status == "pass" &&
      scalability_status == "repeat_live_guarded" &&
      resource_profile_status == "repeat_live_guarded" &&
      server_scalability_protocol_change + 0 == 0 &&
      multi_client_sent_state == "guarded" &&
      block_edit_fanout == "interested_clients_guarded" &&
      conflict_semantics == "last_write_wins_guarded" &&
      chunk_request_ordering == "guarded" &&
      worldgen_biome_atlas_tile_identity == "guarded" &&
      worldgen_biome_atlas_block_texture_usage == "guarded" &&
      nil_sent_state_policy == "empty_guarded" &&
      view_distance_config == "guarded" &&
      disconnect_cleanup_status == "lifecycle_summary_guarded" &&
      connection_lifecycle_status == "pass" &&
      connection_lifecycle_close_failures + 0 == 0 &&
      connection_lifecycle_accept_failures + 0 == 0 &&
      connection_lifecycle_missing_active_client_fields + 0 == 0
    server_tests_ok = server_boundary_tests == "pass" || server_boundary_tests == "skipped"
    client_tests_ok = client_boundary_tests == "pass" || client_boundary_tests == "skipped"

    if (active_protocol_change != 0) {
      status = "fail"
      reason = "protocol_diff_present"
    } else if (!scalability_ok) {
      status = "fail"
      reason = "server_scalability_gate_not_clean"
    } else if (!slow_reader_ok) {
      status = "fail"
      reason = "slow_reader_smoke_failed"
    } else if (!slow_reader_matrix_ok) {
      status = "fail"
      reason = "slow_reader_matrix_failed"
    } else if (!reconnect_ok) {
      status = "fail"
      reason = "reconnect_smoke_failed"
    } else if (!reconnect_soak_ok) {
      status = "fail"
      reason = "reconnect_soak_failed"
    } else if (!server_tests_ok) {
      status = "fail"
      reason = "server_boundary_tests_failed"
    } else if (!client_tests_ok) {
      status = "fail"
      reason = "client_boundary_tests_failed"
    } else if (!packet_error_summary_ok) {
      status = "fail"
      reason = "packet_error_summary_failed"
    } else if (!packet_error_alert_ok) {
      status = "fail"
      reason = "packet_error_alert_threshold_failed"
    }

    printf("networking_robustness status=%s reason=%s robustness_status=%s active_protocol_change=%d server_boundary_tests=%s client_boundary_tests=%s stale_packet_policy=%s unknown_packet_policy=%s nil_packet_policy=%s nil_position_policy=%s nil_block_action_policy=%s nil_sent_state_policy=%s view_distance_config=%s disconnect_cleanup_status=%s connection_lifecycle_status=%s connection_lifecycle_packet_error_disconnects=%d connection_lifecycle_eof_disconnects=%d connection_lifecycle_timeout_disconnects=%d connection_lifecycle_close_failures=%d connection_lifecycle_accept_failures=%d connection_lifecycle_missing_active_client_fields=%d empty_payload_frame=%s packet_error_classification=%s packet_error_aggregation=%s packet_error_alerts=%s reconnect_status=%s reconnect_smoke_status=%s reconnect_smoke_client_state=%s reconnect_smoke_reader_errors=%d reconnect_smoke_successes=%d reconnect_soak_status=%s reconnect_soak_cycles=%d reconnect_soak_reader_errors=%d reconnect_soak_successes=%d slow_client_status=%s slow_reader_smoke_status=%s slow_reader_timeout_observed=%d slow_reader_timeout_class=%s slow_reader_matrix_status=%s slow_reader_matrix_counts_checked=%d slow_reader_matrix_max_fast_clients=%d slow_reader_matrix_total_fast_clients=%d slow_reader_matrix_total_fast_bootstrap_chunks=%d slow_reader_matrix_total_slow_timeouts=%d scalability_status=%s resource_profile_status=%s multi_client_live_status=%s multi_client_sent_state=%s block_edit_fanout=%s conflict_semantics=%s chunk_request_ordering=%s worldgen_biome_atlas_tile_identity=%s worldgen_biome_atlas_block_texture_usage=%s overload_status=%s server_scalability_admission_policy=%s server_scalability_status=%s server_scalability_protocol_change=%d design_doc=%s packet_error_summary=%s packet_error_alert_summary=%s server_scalability_summary=%s slow_reader_smoke_summary=%s slow_reader_matrix_summary=%s reconnect_smoke_summary=%s reconnect_soak_summary=%s\n", status, reason, robustness_status, active_protocol_change, server_boundary_tests, client_boundary_tests, stale_packet_policy, unknown_packet_policy, nil_packet_policy, nil_position_policy, nil_block_action_policy, nil_sent_state_policy, view_distance_config, disconnect_cleanup_status, connection_lifecycle_status, connection_lifecycle_packet_error_disconnects, connection_lifecycle_eof_disconnects, connection_lifecycle_timeout_disconnects, connection_lifecycle_close_failures, connection_lifecycle_accept_failures, connection_lifecycle_missing_active_client_fields, empty_payload_frame, packet_error_classification, packet_error_aggregation, packet_error_alerts, reconnect_status, reconnect_smoke_status, reconnect_smoke_client_state, reconnect_smoke_reader_errors, reconnect_smoke_successes, reconnect_soak_status, reconnect_soak_cycles, reconnect_soak_reader_errors, reconnect_soak_successes, slow_client_status, slow_reader_smoke_status, slow_reader_timeout_observed, slow_reader_timeout_class, slow_reader_matrix_status, slow_reader_matrix_counts_checked, slow_reader_matrix_max_fast_clients, slow_reader_matrix_total_fast_clients, slow_reader_matrix_total_fast_bootstrap_chunks, slow_reader_matrix_total_slow_timeouts, scalability_status, resource_profile_status, multi_client_live_status, multi_client_sent_state, block_edit_fanout, conflict_semantics, chunk_request_ordering, worldgen_biome_atlas_tile_identity, worldgen_biome_atlas_block_texture_usage, overload_status, server_scalability_admission_policy, server_scalability_status, server_scalability_protocol_change, design_doc, packet_error_summary, packet_error_alert_summary, server_scalability_summary, slow_reader_smoke_summary, slow_reader_matrix_summary, reconnect_smoke_summary, reconnect_soak_summary)
    if (status != "pass") {
      exit 1
    }
  }
' > "$SUMMARY_PATH" || {
  cat "$SUMMARY_PATH" >&2 || true
  fail "networking robustness gate failed"
}

cat "$SUMMARY_PATH"
echo "Networking robustness artifacts: $OUT_DIR"
