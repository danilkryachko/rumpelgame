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
CLIENT_SOURCE="${RUMPELMC_NETWORKING_ROBUSTNESS_CLIENT_SOURCE:-"$ROOT_DIR/client/rust_ext/src/network.rs"}"
SERVER_SCALABILITY_SUMMARY="${RUMPELMC_NETWORKING_ROBUSTNESS_SERVER_SCALABILITY_SUMMARY:-"$ROOT_DIR/logs/server_scalability_pass_current/server-scalability-pass-summary.txt"}"
RUN_GO_TESTS="${RUMPELMC_NETWORKING_ROBUSTNESS_RUN_GO_TESTS:-1}"
RUN_RUST_TESTS="${RUMPELMC_NETWORKING_ROBUSTNESS_RUN_RUST_TESTS:-1}"

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

for path in "$DESIGN_DOC" "$PROTOCOL_DOC" "$SERVER_SOURCE" "$SERVER_TEST" "$CLIENT_SOURCE" "$SERVER_SCALABILITY_SUMMARY"; do
  test -s "$path" || fail "missing required input $path"
done

for token in \
  'Current Robustness Contract' \
  'Added Client Guards' \
  'Existing Server Guards' \
  'Deferred Robustness Work' \
  'Compatibility Rules' \
  'Client reconnect state machine' \
  'Slow-client send timeout' \
  'Server overload/admission behavior'; do
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
require_token "$SERVER_TEST" 'TestReceivePacketReturnsOnShortFrame'
require_token "$SERVER_TEST" 'TestReceivePacketRejectsOversizedLength'
require_token "$SERVER_TEST" 'TestReceivePacketRejectsMalformedPayload'

require_token "$CLIENT_SOURCE" 'const MAX_PACKET_LENGTH: usize = 16 * 1024 * 1024;'
require_token "$CLIENT_SOURCE" 'self.stream.read_exact(&mut len_buf)?;'
require_token "$CLIENT_SOURCE" 'self.stream.read_exact(&mut data_buf)?;'
require_token "$CLIENT_SOURCE" 'Packet::decode(&data_buf[..])'
require_token "$CLIENT_SOURCE" 'receive_rejects_oversized_packet_length'
require_token "$CLIENT_SOURCE" 'receive_returns_unexpected_eof_on_short_length_prefix'
require_token "$CLIENT_SOURCE" 'receive_returns_unexpected_eof_on_short_payload'
require_token "$CLIENT_SOURCE" 'receive_rejects_malformed_payload'

server_scalability_status="$(field_metric status "$SERVER_SCALABILITY_SUMMARY")"
server_scalability_protocol_change="$(field_metric active_protocol_change "$SERVER_SCALABILITY_SUMMARY")"
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
  if (cd "$ROOT_DIR/client/rust_ext" && cargo test --lib network::tests::receive > "$OUT_DIR/cargo-test-network.txt" 2>&1); then
    client_boundary_tests="pass"
  else
    cat "$OUT_DIR/cargo-test-network.txt" >&2 || true
    client_boundary_tests="fail"
  fi
fi

awk \
  -v server_scalability_status="${server_scalability_status:-missing}" \
  -v server_scalability_protocol_change="${server_scalability_protocol_change:-1}" \
  -v proto_diff_count="$proto_diff_count" \
  -v server_boundary_tests="$server_boundary_tests" \
  -v client_boundary_tests="$client_boundary_tests" \
  -v design_doc="$DESIGN_DOC" \
  -v server_scalability_summary="$SERVER_SCALABILITY_SUMMARY" '
  BEGIN {
    status = "pass"
    reason = "ok"
    robustness_status = "unit_guarded"
    reconnect_status = "deferred"
    slow_client_status = "deferred"
    overload_status = "deferred"
    active_protocol_change = proto_diff_count + 0

    scalability_ok = server_scalability_status == "pass" && server_scalability_protocol_change + 0 == 0
    server_tests_ok = server_boundary_tests == "pass" || server_boundary_tests == "skipped"
    client_tests_ok = client_boundary_tests == "pass" || client_boundary_tests == "skipped"

    if (active_protocol_change != 0) {
      status = "fail"
      reason = "protocol_diff_present"
    } else if (!scalability_ok) {
      status = "fail"
      reason = "server_scalability_gate_not_clean"
    } else if (!server_tests_ok) {
      status = "fail"
      reason = "server_boundary_tests_failed"
    } else if (!client_tests_ok) {
      status = "fail"
      reason = "client_boundary_tests_failed"
    }

    printf("networking_robustness status=%s reason=%s robustness_status=%s active_protocol_change=%d server_boundary_tests=%s client_boundary_tests=%s reconnect_status=%s slow_client_status=%s overload_status=%s server_scalability_status=%s server_scalability_protocol_change=%d design_doc=%s server_scalability_summary=%s\n", status, reason, robustness_status, active_protocol_change, server_boundary_tests, client_boundary_tests, reconnect_status, slow_client_status, overload_status, server_scalability_status, server_scalability_protocol_change, design_doc, server_scalability_summary)
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
