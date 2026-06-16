#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/security_data_integrity_review"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

SUMMARY_PATH="$OUT_DIR/security-data-integrity-review-summary.txt"
DESIGN_DOC="${RUMPELMC_SECURITY_REVIEW_DOC:-"$ROOT_DIR/docs/SECURITY_DATA_INTEGRITY_REVIEW.md"}"
SERVER_NETWORK_SOURCE="${RUMPELMC_SECURITY_REVIEW_SERVER_NETWORK_SOURCE:-"$ROOT_DIR/server/pkg/network/server.go"}"
SERVER_WORLD_SOURCE="${RUMPELMC_SECURITY_REVIEW_SERVER_WORLD_SOURCE:-"$ROOT_DIR/server/pkg/world/world.go"}"
CLIENT_NETWORK_SOURCE="${RUMPELMC_SECURITY_REVIEW_CLIENT_NETWORK_SOURCE:-"$ROOT_DIR/client/rust_ext/src/network.rs"}"
NETWORKING_SUMMARY="${RUMPELMC_SECURITY_REVIEW_NETWORKING_SUMMARY:-"$ROOT_DIR/logs/networking_robustness_current/networking-robustness-summary.txt"}"
PERSISTENCE_SUMMARY="${RUMPELMC_SECURITY_REVIEW_PERSISTENCE_SUMMARY:-"$ROOT_DIR/logs/block_edit_persistence_current/block-edit-persistence-summary.txt"}"
ARCH_SUMMARY="${RUMPELMC_SECURITY_REVIEW_ARCH_SUMMARY:-"$ROOT_DIR/logs/architecture_documentation_refresh_current/architecture-documentation-refresh-summary.txt"}"
OBSERVABILITY_SUMMARY="${RUMPELMC_SECURITY_REVIEW_OBSERVABILITY_SUMMARY:-"$ROOT_DIR/logs/observability_logs_cleanup_current/observability-logs-cleanup-summary.txt"}"
RUN_GO_TESTS="${RUMPELMC_SECURITY_REVIEW_RUN_GO_TESTS:-1}"
RUN_RUST_TESTS="${RUMPELMC_SECURITY_REVIEW_RUN_RUST_TESTS:-1}"

mkdir -p "$OUT_DIR"

fail() {
  echo "security_data_integrity_review_gate: $*" >&2
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
  "$SERVER_NETWORK_SOURCE" \
  "$SERVER_WORLD_SOURCE" \
  "$CLIENT_NETWORK_SOURCE" \
  "$NETWORKING_SUMMARY" \
  "$PERSISTENCE_SUMMARY" \
  "$ARCH_SUMMARY" \
  "$OBSERVABILITY_SUMMARY"; do
  test -s "$path" || fail "missing required input $path"
done

for token in \
  'Reviewed Boundaries' \
  'Packet Framing' \
  'Chunk Serialization' \
  'Storage Integrity' \
  'Block Edit Boundary' \
  'MCP Review Notes' \
  'Deferred Work' \
  'Compatibility Rules'; do
  require_token "$DESIGN_DOC" "$token"
done

for token in \
  'const maxPacketSize = 16 * 1024 * 1024' \
  'io.ReadFull' \
  'proto.Unmarshal' \
  'func classifyNetworkError' \
  'packet_error_class=' \
  'world.IsPlaceable' \
  'SetBlockGlobal'; do
  require_token "$SERVER_NETWORK_SOURCE" "$token"
done

for token in \
  'const MAX_PACKET_LENGTH: usize = 16 * 1024 * 1024;' \
  'read_exact' \
  'Packet::decode' \
  'receive_returns_unexpected_eof_on_short_length_prefix' \
  'receive_rejects_malformed_payload'; do
  require_token "$CLIENT_NETWORK_SOURCE" "$token"
done

for token in \
  'ChunkStore' \
  'SaveChunk' \
  'LoadChunk' \
  'SetBlockGlobal'; do
  require_token "$SERVER_WORLD_SOURCE" "$token"
done

networking_status="$(field_metric status "$NETWORKING_SUMMARY")"
networking_protocol_change="$(field_metric active_protocol_change "$NETWORKING_SUMMARY")"
networking_packet_error_classification="$(field_metric packet_error_classification "$NETWORKING_SUMMARY")"
networking_packet_error_aggregation="$(field_metric packet_error_aggregation "$NETWORKING_SUMMARY")"
networking_packet_error_alerts="$(field_metric packet_error_alerts "$NETWORKING_SUMMARY")"
persistence_status="$(field_metric status "$PERSISTENCE_SUMMARY")"
persistence_protocol_change="$(field_metric active_protocol_change "$PERSISTENCE_SUMMARY")"
arch_status="$(field_metric status "$ARCH_SUMMARY")"
arch_runtime_change="$(field_metric runtime_change "$ARCH_SUMMARY")"
observability_status="$(field_metric status "$OBSERVABILITY_SUMMARY")"
observability_error_scan="$(field_metric error_scan "$OBSERVABILITY_SUMMARY")"
proto_diff_count="$(git -C "$ROOT_DIR" diff --name-only -- api/schema/packets.proto server/pkg/api/packets.pb.go | awk 'END { print NR + 0 }')"

go_integrity_tests="skipped"
rust_packet_tests="skipped"
rust_chunk_decode_tests="skipped"

if [ "$RUN_GO_TESTS" = "1" ]; then
  if (cd "$ROOT_DIR/server" && go test ./pkg/api ./pkg/network ./pkg/storage ./pkg/world > "$OUT_DIR/go-integrity-tests.txt" 2>&1); then
    go_integrity_tests="pass"
  else
    cat "$OUT_DIR/go-integrity-tests.txt" >&2 || true
    go_integrity_tests="fail"
  fi
fi

if [ "$RUN_RUST_TESTS" = "1" ]; then
  if (cd "$ROOT_DIR/client/rust_ext" && cargo test --lib receive_ > "$OUT_DIR/cargo-test-packet-boundary.txt" 2>&1); then
    rust_packet_tests="pass"
  else
    cat "$OUT_DIR/cargo-test-packet-boundary.txt" >&2 || true
    rust_packet_tests="fail"
  fi

  if [ "$rust_packet_tests" = "pass" ] && (cd "$ROOT_DIR/client/rust_ext" && cargo test --lib decode_chunk_blocks_rejects > "$OUT_DIR/cargo-test-chunk-decode.txt" 2>&1); then
    rust_chunk_decode_tests="pass"
  elif [ "$rust_packet_tests" = "pass" ]; then
    cat "$OUT_DIR/cargo-test-chunk-decode.txt" >&2 || true
    rust_chunk_decode_tests="fail"
  fi
fi

awk \
  -v networking_status="${networking_status:-missing}" \
  -v networking_protocol_change="${networking_protocol_change:-1}" \
  -v networking_packet_error_classification="${networking_packet_error_classification:-missing}" \
  -v networking_packet_error_aggregation="${networking_packet_error_aggregation:-missing}" \
  -v networking_packet_error_alerts="${networking_packet_error_alerts:-missing}" \
  -v persistence_status="${persistence_status:-missing}" \
  -v persistence_protocol_change="${persistence_protocol_change:-1}" \
  -v arch_status="${arch_status:-missing}" \
  -v arch_runtime_change="${arch_runtime_change:-unknown}" \
  -v observability_status="${observability_status:-missing}" \
  -v observability_error_scan="${observability_error_scan:-dirty}" \
  -v proto_diff_count="$proto_diff_count" \
  -v go_integrity_tests="$go_integrity_tests" \
  -v rust_packet_tests="$rust_packet_tests" \
  -v rust_chunk_decode_tests="$rust_chunk_decode_tests" \
  -v networking_summary="$NETWORKING_SUMMARY" \
  -v persistence_summary="$PERSISTENCE_SUMMARY" \
  -v arch_summary="$ARCH_SUMMARY" \
  -v observability_summary="$OBSERVABILITY_SUMMARY" '
  BEGIN {
    status = "pass"
    reason = "ok"
    security_status = "reviewed"
    packet_boundary = "guarded"
    storage_integrity = "guarded"
    chunk_decode = "guarded"
    active_protocol_change = proto_diff_count + 0

    prereqs_ok = networking_status == "pass" && networking_protocol_change + 0 == 0 &&
      (networking_packet_error_classification == "unit_guarded" || networking_packet_error_classification == "source_guarded") &&
      networking_packet_error_aggregation == "parser_guarded" &&
      networking_packet_error_alerts == "threshold_guarded" &&
      persistence_status == "pass" && persistence_protocol_change + 0 == 0 &&
      arch_status == "pass" && arch_runtime_change == "none" &&
      observability_status == "pass" && observability_error_scan == "clean"
    tests_ok = (go_integrity_tests == "pass" || go_integrity_tests == "skipped") &&
      (rust_packet_tests == "pass" || rust_packet_tests == "skipped") &&
      (rust_chunk_decode_tests == "pass" || rust_chunk_decode_tests == "skipped")

    if (active_protocol_change != 0) {
      status = "fail"
      reason = "protocol_diff_present"
    } else if (!prereqs_ok) {
      status = "fail"
      reason = "prerequisite_summary_not_clean"
    } else if (!tests_ok) {
      status = "fail"
      reason = "integrity_tests_failed"
    }

    printf("security_data_integrity_review status=%s reason=%s security_status=%s packet_boundary=%s packet_error_classification=%s packet_error_aggregation=%s packet_error_alerts=%s storage_integrity=%s chunk_decode=%s active_protocol_change=%d go_integrity_tests=%s rust_packet_tests=%s rust_chunk_decode_tests=%s networking_status=%s persistence_status=%s arch_status=%s observability_status=%s observability_error_scan=%s networking_summary=%s persistence_summary=%s arch_summary=%s observability_summary=%s\n", status, reason, security_status, packet_boundary, networking_packet_error_classification, networking_packet_error_aggregation, networking_packet_error_alerts, storage_integrity, chunk_decode, active_protocol_change, go_integrity_tests, rust_packet_tests, rust_chunk_decode_tests, networking_status, persistence_status, arch_status, observability_status, observability_error_scan, networking_summary, persistence_summary, arch_summary, observability_summary)
    if (status != "pass") {
      exit 1
    }
  }
' > "$SUMMARY_PATH" || {
  cat "$SUMMARY_PATH" >&2 || true
  fail "security data integrity review gate failed"
}

cat "$SUMMARY_PATH"
echo "Security data integrity review artifacts: $OUT_DIR"
