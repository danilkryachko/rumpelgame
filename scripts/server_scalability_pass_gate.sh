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
WORLDGEN_QUALITY_SUMMARY="${RUMPELMC_SERVER_SCALABILITY_WORLDGEN_QUALITY_SUMMARY:-"$ROOT_DIR/logs/world_generation_quality_current/world-generation-quality-summary.txt"}"
RUN_GO_TESTS="${RUMPELMC_SERVER_SCALABILITY_RUN_GO_TESTS:-1}"

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

for path in "$DESIGN_DOC" "$PROTOCOL_DOC" "$SERVER_SOURCE" "$SERVER_TEST" "$WORLDGEN_QUALITY_SUMMARY"; do
  test -s "$path" || fail "missing required input $path"
done

for token in \
  'per-client sent-chunk state isolation' \
  'Scalability Gaps' \
  'Live slow-client handling evidence' \
  'Do not change `api/schema/packets.proto`' \
  'Live multi-client load'; do
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
require_token "$SERVER_TEST" "TestSendChunksAroundKeepsPerClientSentStateIndependent"
require_token "$SERVER_TEST" "second client sent chunks changed after first client progress"
require_token "$SERVER_TEST" "TestHandleClientPacketBroadcastsBlockUpdateToInterestedClients"
require_token "$SERVER_TEST" "TestBroadcastDisconnectsFailedInterestedClient"
require_token "$SERVER_TEST" "TestSendChunkToSessionSetsAndClearsWriteDeadline"

worldgen_quality_status="$(field_metric status "$WORLDGEN_QUALITY_SUMMARY")"
worldgen_runtime_quality="$(field_metric runtime_quality_pass "$WORLDGEN_QUALITY_SUMMARY")"
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
  -v network_tests="$network_tests" \
  -v design_doc="$DESIGN_DOC" \
  -v worldgen_quality_summary="$WORLDGEN_QUALITY_SUMMARY" '
  BEGIN {
    status = "pass"
    reason = "ok"
    scalability_status = "unit_guarded"
    multi_client_sent_state = "guarded"
    block_edit_fanout = "interested_clients_guarded"
    slow_client_write_timeout = "guarded"
    disconnect_cleanup_status = "failed_broadcast_guarded"
    live_load_status = "deferred"
    active_protocol_change = proto_diff_count + 0

    deps_ok = worldgen_quality_status == "pass" && worldgen_runtime_quality == "deferred"
    tests_ok = network_tests == "pass" || network_tests == "skipped"

    if (active_protocol_change != 0) {
      status = "fail"
      reason = "protocol_diff_present"
    } else if (!deps_ok) {
      status = "fail"
      reason = "worldgen_quality_gate_not_clean"
    } else if (!tests_ok) {
      status = "fail"
      reason = "network_tests_failed"
    }

    printf("server_scalability_pass status=%s reason=%s scalability_status=%s multi_client_sent_state=%s block_edit_fanout=%s slow_client_write_timeout=%s active_protocol_change=%d disconnect_cleanup_status=%s live_load_status=%s network_tests=%s worldgen_quality_status=%s worldgen_runtime_quality=%s design_doc=%s worldgen_quality_summary=%s\n", status, reason, scalability_status, multi_client_sent_state, block_edit_fanout, slow_client_write_timeout, active_protocol_change, disconnect_cleanup_status, live_load_status, network_tests, worldgen_quality_status, worldgen_runtime_quality, design_doc, worldgen_quality_summary)
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
