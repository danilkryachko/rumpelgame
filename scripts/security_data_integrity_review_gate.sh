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
STORAGE_DOC="${RUMPELMC_SECURITY_REVIEW_STORAGE_DOC:-"$ROOT_DIR/docs/STORAGE.md"}"
SERVER_CMD_SOURCE="${RUMPELMC_SECURITY_REVIEW_SERVER_CMD_SOURCE:-"$ROOT_DIR/server/cmd/server/main.go"}"
SERVER_NETWORK_SOURCE="${RUMPELMC_SECURITY_REVIEW_SERVER_NETWORK_SOURCE:-"$ROOT_DIR/server/pkg/network/server.go"}"
SERVER_API_TEST="${RUMPELMC_SECURITY_REVIEW_SERVER_API_TEST:-"$ROOT_DIR/server/pkg/api/packets_compat_test.go"}"
SERVER_WORLD_SOURCE="${RUMPELMC_SECURITY_REVIEW_SERVER_WORLD_SOURCE:-"$ROOT_DIR/server/pkg/world/world.go"}"
SERVER_NETWORK_TEST="${RUMPELMC_SECURITY_REVIEW_SERVER_NETWORK_TEST:-"$ROOT_DIR/server/pkg/network/framing_test.go"}"
SERVER_NETWORK_BEHAVIOR_TEST="${RUMPELMC_SECURITY_REVIEW_SERVER_NETWORK_BEHAVIOR_TEST:-"$ROOT_DIR/server/pkg/network/server_test.go"}"
SERVER_STORAGE_SOURCE="${RUMPELMC_SECURITY_REVIEW_SERVER_STORAGE_SOURCE:-"$ROOT_DIR/server/pkg/storage/rocksdb.go"}"
SERVER_STORAGE_TEST="${RUMPELMC_SECURITY_REVIEW_SERVER_STORAGE_TEST:-"$ROOT_DIR/server/pkg/storage/rocksdb_test.go"}"
SERVER_WORLD_TEST="${RUMPELMC_SECURITY_REVIEW_SERVER_WORLD_TEST:-"$ROOT_DIR/server/pkg/world/chunk_encoding_test.go"}"
SERVER_WORLD_BEHAVIOR_TEST="${RUMPELMC_SECURITY_REVIEW_SERVER_WORLD_BEHAVIOR_TEST:-"$ROOT_DIR/server/pkg/world/world_test.go"}"
CLIENT_MAIN_SOURCE="${RUMPELMC_SECURITY_REVIEW_CLIENT_MAIN_SOURCE:-"$ROOT_DIR/client/main.gd"}"
CLIENT_NETWORK_SOURCE="${RUMPELMC_SECURITY_REVIEW_CLIENT_NETWORK_SOURCE:-"$ROOT_DIR/client/rust_ext/src/network.rs"}"
CLIENT_RUNTIME_SOURCE="${RUMPELMC_SECURITY_REVIEW_CLIENT_RUNTIME_SOURCE:-"$ROOT_DIR/client/rust_ext/src/lib.rs"}"
NETWORKING_SUMMARY="${RUMPELMC_SECURITY_REVIEW_NETWORKING_SUMMARY:-"$ROOT_DIR/logs/networking_robustness_current/networking-robustness-summary.txt"}"
PERSISTENCE_SUMMARY="${RUMPELMC_SECURITY_REVIEW_PERSISTENCE_SUMMARY:-"$ROOT_DIR/logs/block_edit_persistence_current/block-edit-persistence-summary.txt"}"
ARCH_SUMMARY="${RUMPELMC_SECURITY_REVIEW_ARCH_SUMMARY:-"$ROOT_DIR/logs/architecture_documentation_refresh_current/architecture-documentation-refresh-summary.txt"}"
OBSERVABILITY_SUMMARY="${RUMPELMC_SECURITY_REVIEW_OBSERVABILITY_SUMMARY:-"$ROOT_DIR/logs/observability_logs_cleanup_current/observability-logs-cleanup-summary.txt"}"
STORAGE_SMOKE_SUMMARY="${RUMPELMC_SECURITY_REVIEW_STORAGE_SMOKE_SUMMARY:-"$ROOT_DIR/logs/storage_package_smoke_current/storage-package-smoke-summary.txt"}"
PACKET_ERROR_MONITORING_SUMMARY="${RUMPELMC_SECURITY_REVIEW_PACKET_ERROR_MONITORING_SUMMARY:-"$ROOT_DIR/logs/packet_error_monitoring_contract_current/packet-error-monitoring-contract-summary.txt"}"
SERVER_SESSION_MONITORING_SUMMARY="${RUMPELMC_SECURITY_REVIEW_SERVER_SESSION_MONITORING_SUMMARY:-"$ROOT_DIR/logs/server_session_monitoring_contract_current/server-session-monitoring-contract-summary.txt"}"
RUN_GO_TESTS="${RUMPELMC_SECURITY_REVIEW_RUN_GO_TESTS:-1}"
RUN_RUST_TESTS="${RUMPELMC_SECURITY_REVIEW_RUN_RUST_TESTS:-1}"
RUN_STORAGE_SMOKE="${RUMPELMC_SECURITY_REVIEW_RUN_STORAGE_SMOKE:-1}"
RUN_PACKET_ERROR_MONITORING="${RUMPELMC_SECURITY_REVIEW_RUN_PACKET_ERROR_MONITORING:-1}"
RUN_SERVER_SESSION_MONITORING="${RUMPELMC_SECURITY_REVIEW_RUN_SERVER_SESSION_MONITORING:-1}"
UNAPPROVED_DB_SCAN="$OUT_DIR/unapproved-database-reference-scan.txt"

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

scan_unapproved_database_references() {
  pattern='(^|[^[:alnum:]_])(sqlite|mysql|mariadb|mongodb|dynamodb|redis|badger|bolt|leveldb|duckdb|cockroach|surreal|tidb)([^[:alnum:]_]|$)'
  : > "$UNAPPROVED_DB_SCAN"

  (cd "$ROOT_DIR" && git ls-files --cached --others --exclude-standard -- server client api) |
    while IFS= read -r relpath; do
      path="$ROOT_DIR/$relpath"
      test -f "$path" || continue
      case "$relpath" in
        *.bmp|*.db|*.ico|*.import|*.jpeg|*.jpg|*.png|*.rocksdb|*.trace|*.uid|*.webp|*.zip) continue ;;
      esac
      grep -EInH "$pattern" "$path" || true
    done > "$UNAPPROVED_DB_SCAN"

  if [ -s "$UNAPPROVED_DB_SCAN" ]; then
    cat "$UNAPPROVED_DB_SCAN" >&2 || true
    fail "unapproved database engine reference in runtime source"
  fi
}

case "$RUN_STORAGE_SMOKE" in
  0|1) ;;
  *) fail "RUMPELMC_SECURITY_REVIEW_RUN_STORAGE_SMOKE must be 0 or 1" ;;
esac

case "$RUN_PACKET_ERROR_MONITORING" in
  0|1) ;;
  *) fail "RUMPELMC_SECURITY_REVIEW_RUN_PACKET_ERROR_MONITORING must be 0 or 1" ;;
esac

case "$RUN_SERVER_SESSION_MONITORING" in
  0|1) ;;
  *) fail "RUMPELMC_SECURITY_REVIEW_RUN_SERVER_SESSION_MONITORING must be 0 or 1" ;;
esac

if [ "$RUN_STORAGE_SMOKE" = "1" ]; then
  STORAGE_SMOKE_OUT_DIR="$(dirname -- "$STORAGE_SMOKE_SUMMARY")"
  sh "$ROOT_DIR/scripts/storage_package_smoke.sh" "$STORAGE_SMOKE_OUT_DIR" > "$OUT_DIR/storage-package-smoke-check.txt" 2>&1 || {
    cat "$OUT_DIR/storage-package-smoke-check.txt" >&2 || true
    fail "storage package smoke failed"
  }
fi

if [ "$RUN_PACKET_ERROR_MONITORING" = "1" ]; then
  PACKET_ERROR_MONITORING_OUT_DIR="$(dirname -- "$PACKET_ERROR_MONITORING_SUMMARY")"
  sh "$ROOT_DIR/scripts/packet_error_monitoring_contract_gate.sh" "$PACKET_ERROR_MONITORING_OUT_DIR" > "$OUT_DIR/packet-error-monitoring-contract-check.txt" 2>&1 || {
    cat "$OUT_DIR/packet-error-monitoring-contract-check.txt" >&2 || true
    fail "packet error monitoring contract failed"
  }
fi

if [ "$RUN_SERVER_SESSION_MONITORING" = "1" ]; then
  SERVER_SESSION_MONITORING_OUT_DIR="$(dirname -- "$SERVER_SESSION_MONITORING_SUMMARY")"
  sh "$ROOT_DIR/scripts/server_session_monitoring_contract_gate.sh" "$SERVER_SESSION_MONITORING_OUT_DIR" > "$OUT_DIR/server-session-monitoring-contract-check.txt" 2>&1 || {
    cat "$OUT_DIR/server-session-monitoring-contract-check.txt" >&2 || true
    fail "server session monitoring contract failed"
  }
fi

for path in \
  "$DESIGN_DOC" \
  "$STORAGE_DOC" \
  "$SERVER_CMD_SOURCE" \
  "$SERVER_NETWORK_SOURCE" \
  "$SERVER_API_TEST" \
  "$SERVER_WORLD_SOURCE" \
  "$SERVER_NETWORK_TEST" \
  "$SERVER_NETWORK_BEHAVIOR_TEST" \
  "$SERVER_STORAGE_SOURCE" \
  "$SERVER_STORAGE_TEST" \
  "$SERVER_WORLD_TEST" \
  "$SERVER_WORLD_BEHAVIOR_TEST" \
  "$CLIENT_MAIN_SOURCE" \
  "$CLIENT_NETWORK_SOURCE" \
  "$CLIENT_RUNTIME_SOURCE" \
  "$NETWORKING_SUMMARY" \
  "$PERSISTENCE_SUMMARY" \
  "$ARCH_SUMMARY" \
  "$OBSERVABILITY_SUMMARY" \
  "$STORAGE_SMOKE_SUMMARY" \
  "$PACKET_ERROR_MONITORING_SUMMARY" \
  "$SERVER_SESSION_MONITORING_SUMMARY"; do
  test -s "$path" || fail "missing required input $path"
done

scan_unapproved_database_references

for token in \
  'Reviewed Boundaries' \
  'Packet Framing' \
  'Chunk Serialization' \
  'Storage Integrity' \
  'Block Edit Boundary' \
  'Local-Only Threat Model' \
  'MCP Review Notes' \
  'Deferred Work' \
  'Compatibility Rules'; do
  require_token "$DESIGN_DOC" "$token"
done

for token in \
  'Ownership Boundary' \
  'RocksDB owns current server chunk persistence' \
  'RUMPELMC_SERVER_ROCKSDB_PATH' \
  'empty RocksDB chunk store paths are rejected' \
  'no PostgreSQL runtime chunk persistence path' \
  'Adding PostgreSQL-backed persistence requires a separate storage design'; do
  require_token "$STORAGE_DOC" "$token"
done

for token in \
  'func configuredServerAddress' \
  'func isLoopbackAddress' \
  'RUMPELMC_SERVER_ADDRESS' \
  'net.SplitHostPort' \
  'IsLoopback' \
  'return "127.0.0.1:25565"'; do
  require_token "$SERVER_CMD_SOURCE" "$token"
done

for token in \
  'func defaultRocksDBPath' \
  'RUMPELMC_SERVER_ROCKSDB_PATH' \
  'dbPath := defaultRocksDBPath()' \
  'storage.OpenRocksChunkStore(dbPath)'; do
  require_token "$SERVER_CMD_SOURCE" "$token"
done

require_token "$CLIENT_MAIN_SOURCE" 'const SERVER_HOST = "127.0.0.1"'
require_token "$CLIENT_RUNTIME_SOURCE" 'const SERVER_ADDRESS: &str = "127.0.0.1:25565";'
wildcard_bind_pattern='RUMPELMC_SERVER_ADDRESS="'
wildcard_bind_pattern="${wildcard_bind_pattern}:"
if grep -R -F "$wildcard_bind_pattern" "$ROOT_DIR/scripts" >/dev/null 2>&1; then
  fail "server smoke scripts must bind explicit loopback addresses"
fi

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
  'SetBlockGlobal' \
  'block y coordinate' \
  'ChunkHeight'; do
  require_token "$SERVER_WORLD_SOURCE" "$token"
done

for token in \
  'create RocksDB parent directory' \
  'open RocksDB chunk store' \
  'errEmptyRocksStorePath' \
  'load RocksDB chunk' \
  'decode RocksDB chunk' \
  'save RocksDB chunk' \
  'errRocksChunkStoreClosed' \
  'ensureOpen'; do
  require_token "$SERVER_STORAGE_SOURCE" "$token"
done

require_token "$SERVER_NETWORK_TEST" 'TestReceivePacketConsumesExactFrameBoundaries'
require_token "$SERVER_API_TEST" 'TestPacketWireCompatibility'
require_token "$SERVER_API_TEST" 'empty packet has zero wire bytes'
require_token "$SERVER_NETWORK_BEHAVIOR_TEST" 'TestHandleClientPacketRejectsOutOfRangeBlockAction'
require_token "$SERVER_STORAGE_TEST" 'TestOpenRocksChunkStoreCreatesMissingParentDirectory'
require_token "$SERVER_STORAGE_TEST" 'TestOpenRocksChunkStoreRejectsFilePath'
require_token "$SERVER_STORAGE_TEST" 'TestOpenRocksChunkStoreRejectsFileParentPath'
require_token "$SERVER_STORAGE_TEST" 'TestOpenRocksChunkStoreRejectsEmptyPathBeforeCAPI'
require_token "$SERVER_STORAGE_TEST" 'TestRocksChunkStoreConcurrentSaveLoadDistinctChunks'
require_token "$SERVER_STORAGE_TEST" 'TestRocksChunkStoreRejectsOperationsAfterClose'
require_token "$SERVER_STORAGE_TEST" 'TestRocksChunkStoreRejectsNilChunkSave'
require_token "$SERVER_STORAGE_TEST" 'want open context'
require_token "$SERVER_STORAGE_TEST" 'want chunk decode context'
require_token "$SERVER_WORLD_TEST" 'TestEncodeSerializedChunkRLERoundTripsRepresentativeRunPatterns'
require_token "$SERVER_WORLD_TEST" 'TestEncodeSerializedChunkRLERoundTripsHeightV1Chunk'
require_token "$SERVER_WORLD_TEST" 'TestEncodeSerializedChunkRLERoundTripsBiomeHeightV1Chunk'
require_token "$SERVER_WORLD_TEST" 'TestEncodeSerializedChunkRLERoundTripsCaveHeightV1Chunk'
require_token "$SERVER_WORLD_TEST" 'TestEncodeSerializedChunkRLERoundTripsBiomeCaveHeightV1Chunk'
require_token "$SERVER_WORLD_BEHAVIOR_TEST" 'TestSetBlockGlobalRejectsOutOfRangeYWithoutSave'
require_token "$SERVER_WORLD_BEHAVIOR_TEST" 'TestSetBlockGlobalRollsBackInMemoryBlockOnSaveError'
require_token "$SERVER_WORLD_BEHAVIOR_TEST" 'TestHeightV1EditedChunkPersistsThroughStoreReload'
require_token "$CLIENT_RUNTIME_SOURCE" 'decode_serialized_chunk_rle_accepts_representative_runs'
require_token "$ROOT_DIR/server/cmd/server/main_test.go" 'TestConfiguredServerAddressRejectsNonLoopbackOverrides'
require_token "$ROOT_DIR/server/cmd/server/main_test.go" 'TestDefaultRocksDBPathUsesExplicitOverride'
require_token "$ROOT_DIR/server/cmd/server/main_test.go" 'TestDefaultRocksDBPathIgnoresPostgreSQLEnvironment'

networking_status="$(field_metric status "$NETWORKING_SUMMARY")"
networking_protocol_change="$(field_metric active_protocol_change "$NETWORKING_SUMMARY")"
networking_packet_error_classification="$(field_metric packet_error_classification "$NETWORKING_SUMMARY")"
networking_packet_error_aggregation="$(field_metric packet_error_aggregation "$NETWORKING_SUMMARY")"
networking_packet_error_alerts="$(field_metric packet_error_alerts "$NETWORKING_SUMMARY")"
networking_unknown_packet_policy="$(field_metric unknown_packet_policy "$NETWORKING_SUMMARY")"
networking_nil_packet_policy="$(field_metric nil_packet_policy "$NETWORKING_SUMMARY")"
networking_nil_position_policy="$(field_metric nil_position_policy "$NETWORKING_SUMMARY")"
networking_nil_block_action_policy="$(field_metric nil_block_action_policy "$NETWORKING_SUMMARY")"
networking_conflict_semantics="$(field_metric conflict_semantics "$NETWORKING_SUMMARY")"
networking_worldgen_biome_atlas_tile_identity="$(field_metric worldgen_biome_atlas_tile_identity "$NETWORKING_SUMMARY")"
networking_worldgen_biome_atlas_block_texture_usage="$(field_metric worldgen_biome_atlas_block_texture_usage "$NETWORKING_SUMMARY")"
networking_overload_status="$(field_metric overload_status "$NETWORKING_SUMMARY")"
networking_reconnect_status="$(field_metric reconnect_status "$NETWORKING_SUMMARY")"
networking_reconnect_smoke_status="$(field_metric reconnect_smoke_status "$NETWORKING_SUMMARY")"
networking_reconnect_smoke_client_state="$(field_metric reconnect_smoke_client_state "$NETWORKING_SUMMARY")"
networking_reconnect_smoke_reader_errors="$(field_metric reconnect_smoke_reader_errors "$NETWORKING_SUMMARY")"
networking_reconnect_smoke_successes="$(field_metric reconnect_smoke_successes "$NETWORKING_SUMMARY")"
networking_reconnect_soak_status="$(field_metric reconnect_soak_status "$NETWORKING_SUMMARY")"
networking_reconnect_soak_cycles="$(field_metric reconnect_soak_cycles "$NETWORKING_SUMMARY")"
networking_reconnect_soak_reader_errors="$(field_metric reconnect_soak_reader_errors "$NETWORKING_SUMMARY")"
networking_reconnect_soak_successes="$(field_metric reconnect_soak_successes "$NETWORKING_SUMMARY")"
networking_slow_client_status="$(field_metric slow_client_status "$NETWORKING_SUMMARY")"
networking_slow_reader_smoke_status="$(field_metric slow_reader_smoke_status "$NETWORKING_SUMMARY")"
networking_slow_reader_timeout_observed="$(field_metric slow_reader_timeout_observed "$NETWORKING_SUMMARY")"
networking_slow_reader_timeout_class="$(field_metric slow_reader_timeout_class "$NETWORKING_SUMMARY")"
networking_slow_reader_matrix_status="$(field_metric slow_reader_matrix_status "$NETWORKING_SUMMARY")"
networking_slow_reader_matrix_counts_checked="$(field_metric slow_reader_matrix_counts_checked "$NETWORKING_SUMMARY")"
networking_slow_reader_matrix_max_fast_clients="$(field_metric slow_reader_matrix_max_fast_clients "$NETWORKING_SUMMARY")"
networking_slow_reader_matrix_total_fast_clients="$(field_metric slow_reader_matrix_total_fast_clients "$NETWORKING_SUMMARY")"
networking_slow_reader_matrix_total_fast_bootstrap_chunks="$(field_metric slow_reader_matrix_total_fast_bootstrap_chunks "$NETWORKING_SUMMARY")"
networking_slow_reader_matrix_total_slow_timeouts="$(field_metric slow_reader_matrix_total_slow_timeouts "$NETWORKING_SUMMARY")"
persistence_status="$(field_metric status "$PERSISTENCE_SUMMARY")"
persistence_protocol_change="$(field_metric active_protocol_change "$PERSISTENCE_SUMMARY")"
persistence_save_failure_rollback="$(field_metric save_failure_rollback "$PERSISTENCE_SUMMARY")"
arch_status="$(field_metric status "$ARCH_SUMMARY")"
arch_runtime_change="$(field_metric runtime_change "$ARCH_SUMMARY")"
observability_status="$(field_metric status "$OBSERVABILITY_SUMMARY")"
observability_error_scan="$(field_metric error_scan "$OBSERVABILITY_SUMMARY")"
observability_gpu_report_freshness="$(field_metric gpu_report_freshness "$OBSERVABILITY_SUMMARY")"
observability_gpu_report_error_scan="$(field_metric gpu_report_error_scan "$OBSERVABILITY_SUMMARY")"
storage_smoke_status="$(field_metric status "$STORAGE_SMOKE_SUMMARY")"
storage_smoke_guard="$(field_metric smoke_status "$STORAGE_SMOKE_SUMMARY")"
storage_smoke_external_secret_required="$(field_metric external_secret_required "$STORAGE_SMOKE_SUMMARY")"
storage_smoke_database_env_policy="$(field_metric database_env_policy "$STORAGE_SMOKE_SUMMARY")"
storage_smoke_approved_databases="$(field_metric approved_databases "$STORAGE_SMOKE_SUMMARY")"
packet_error_monitoring_status="$(field_metric status "$PACKET_ERROR_MONITORING_SUMMARY")"
packet_error_monitoring_contract="$(field_metric monitoring_contract "$PACKET_ERROR_MONITORING_SUMMARY")"
packet_error_monitoring_metrics_export="$(field_metric metrics_export "$PACKET_ERROR_MONITORING_SUMMARY")"
packet_error_monitoring_unknown_classes="$(field_metric unknown_classes "$PACKET_ERROR_MONITORING_SUMMARY")"
packet_error_monitoring_protocol_errors="$(field_metric protocol_errors "$PACKET_ERROR_MONITORING_SUMMARY")"
packet_error_monitoring_write_errors="$(field_metric write_errors "$PACKET_ERROR_MONITORING_SUMMARY")"
server_session_monitoring_status="$(field_metric status "$SERVER_SESSION_MONITORING_SUMMARY")"
server_session_monitoring_contract="$(field_metric monitoring_contract "$SERVER_SESSION_MONITORING_SUMMARY")"
server_session_monitoring_metrics_export="$(field_metric metrics_export "$SERVER_SESSION_MONITORING_SUMMARY")"
server_session_monitoring_close_failures="$(field_metric close_failures "$SERVER_SESSION_MONITORING_SUMMARY")"
server_session_monitoring_accept_failures="$(field_metric accept_failures "$SERVER_SESSION_MONITORING_SUMMARY")"
server_session_monitoring_missing_active_client_fields="$(field_metric missing_active_client_fields "$SERVER_SESSION_MONITORING_SUMMARY")"
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

  if [ "$rust_packet_tests" = "pass" ] && (cd "$ROOT_DIR/client/rust_ext" && cargo test --lib decode_ > "$OUT_DIR/cargo-test-chunk-decode.txt" 2>&1); then
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
  -v networking_unknown_packet_policy="${networking_unknown_packet_policy:-missing}" \
  -v networking_nil_packet_policy="${networking_nil_packet_policy:-missing}" \
  -v networking_nil_position_policy="${networking_nil_position_policy:-missing}" \
  -v networking_nil_block_action_policy="${networking_nil_block_action_policy:-missing}" \
  -v networking_conflict_semantics="${networking_conflict_semantics:-missing}" \
  -v networking_worldgen_biome_atlas_tile_identity="${networking_worldgen_biome_atlas_tile_identity:-missing}" \
  -v networking_worldgen_biome_atlas_block_texture_usage="${networking_worldgen_biome_atlas_block_texture_usage:-missing}" \
  -v networking_overload_status="${networking_overload_status:-missing}" \
  -v networking_reconnect_status="${networking_reconnect_status:-missing}" \
  -v networking_reconnect_smoke_status="${networking_reconnect_smoke_status:-missing}" \
  -v networking_reconnect_smoke_client_state="${networking_reconnect_smoke_client_state:-missing}" \
  -v networking_reconnect_smoke_reader_errors="${networking_reconnect_smoke_reader_errors:-0}" \
  -v networking_reconnect_smoke_successes="${networking_reconnect_smoke_successes:-0}" \
  -v networking_reconnect_soak_status="${networking_reconnect_soak_status:-missing}" \
  -v networking_reconnect_soak_cycles="${networking_reconnect_soak_cycles:-0}" \
  -v networking_reconnect_soak_reader_errors="${networking_reconnect_soak_reader_errors:-0}" \
  -v networking_reconnect_soak_successes="${networking_reconnect_soak_successes:-0}" \
  -v networking_slow_client_status="${networking_slow_client_status:-missing}" \
  -v networking_slow_reader_smoke_status="${networking_slow_reader_smoke_status:-missing}" \
  -v networking_slow_reader_timeout_observed="${networking_slow_reader_timeout_observed:-0}" \
  -v networking_slow_reader_timeout_class="${networking_slow_reader_timeout_class:-missing}" \
  -v networking_slow_reader_matrix_status="${networking_slow_reader_matrix_status:-missing}" \
  -v networking_slow_reader_matrix_counts_checked="${networking_slow_reader_matrix_counts_checked:-0}" \
  -v networking_slow_reader_matrix_max_fast_clients="${networking_slow_reader_matrix_max_fast_clients:-0}" \
  -v networking_slow_reader_matrix_total_fast_clients="${networking_slow_reader_matrix_total_fast_clients:-0}" \
  -v networking_slow_reader_matrix_total_fast_bootstrap_chunks="${networking_slow_reader_matrix_total_fast_bootstrap_chunks:-0}" \
  -v networking_slow_reader_matrix_total_slow_timeouts="${networking_slow_reader_matrix_total_slow_timeouts:-0}" \
  -v persistence_status="${persistence_status:-missing}" \
  -v persistence_protocol_change="${persistence_protocol_change:-1}" \
  -v persistence_save_failure_rollback="${persistence_save_failure_rollback:-missing}" \
  -v arch_status="${arch_status:-missing}" \
  -v arch_runtime_change="${arch_runtime_change:-unknown}" \
  -v observability_status="${observability_status:-missing}" \
  -v observability_error_scan="${observability_error_scan:-dirty}" \
  -v observability_gpu_report_freshness="${observability_gpu_report_freshness:-missing}" \
  -v observability_gpu_report_error_scan="${observability_gpu_report_error_scan:-dirty}" \
  -v storage_smoke_status="${storage_smoke_status:-missing}" \
  -v storage_smoke_guard="${storage_smoke_guard:-missing}" \
  -v storage_smoke_external_secret_required="${storage_smoke_external_secret_required:-1}" \
  -v storage_smoke_database_env_policy="${storage_smoke_database_env_policy:-missing}" \
  -v storage_smoke_approved_databases="${storage_smoke_approved_databases:-missing}" \
  -v packet_error_monitoring_status="${packet_error_monitoring_status:-missing}" \
  -v packet_error_monitoring_contract="${packet_error_monitoring_contract:-missing}" \
  -v packet_error_monitoring_metrics_export="${packet_error_monitoring_metrics_export:-missing}" \
  -v packet_error_monitoring_unknown_classes="${packet_error_monitoring_unknown_classes:-1}" \
  -v packet_error_monitoring_protocol_errors="${packet_error_monitoring_protocol_errors:-1}" \
  -v packet_error_monitoring_write_errors="${packet_error_monitoring_write_errors:-1}" \
  -v server_session_monitoring_status="${server_session_monitoring_status:-missing}" \
  -v server_session_monitoring_contract="${server_session_monitoring_contract:-missing}" \
  -v server_session_monitoring_metrics_export="${server_session_monitoring_metrics_export:-missing}" \
  -v server_session_monitoring_close_failures="${server_session_monitoring_close_failures:-1}" \
  -v server_session_monitoring_accept_failures="${server_session_monitoring_accept_failures:-1}" \
  -v server_session_monitoring_missing_active_client_fields="${server_session_monitoring_missing_active_client_fields:-1}" \
  -v proto_diff_count="$proto_diff_count" \
  -v go_integrity_tests="$go_integrity_tests" \
  -v rust_packet_tests="$rust_packet_tests" \
  -v rust_chunk_decode_tests="$rust_chunk_decode_tests" \
  -v networking_summary="$NETWORKING_SUMMARY" \
  -v persistence_summary="$PERSISTENCE_SUMMARY" \
  -v arch_summary="$ARCH_SUMMARY" \
  -v observability_summary="$OBSERVABILITY_SUMMARY" \
  -v storage_smoke_summary="$STORAGE_SMOKE_SUMMARY" \
  -v packet_error_monitoring_summary="$PACKET_ERROR_MONITORING_SUMMARY" \
  -v server_session_monitoring_summary="$SERVER_SESSION_MONITORING_SUMMARY" '
  BEGIN {
    status = "pass"
    reason = "ok"
    security_status = "reviewed"
    packet_boundary = "guarded"
    packet_error_monitoring = packet_error_monitoring_contract
    server_session_monitoring = server_session_monitoring_contract
    storage_integrity = "guarded"
    storage_package_smoke = "guarded"
    storage_config = "path_guarded"
    storage_backend_policy = "approved_only_guarded"
    storage_backend_ownership = "guarded"
    storage_concurrency = "guarded"
    storage_errors = "actionable_guarded"
    storage_lifecycle = "guarded"
    block_edit_validation = "y_bounds_guarded"
    block_edit_save_failure_rollback = persistence_save_failure_rollback
    chunk_decode = "guarded"
    deterministic_property_tests = "guarded"
    unknown_packet_policy = networking_unknown_packet_policy
    nil_packet_policy = networking_nil_packet_policy
    nil_position_policy = networking_nil_position_policy
    nil_block_action_policy = networking_nil_block_action_policy
    conflict_semantics = networking_conflict_semantics
    worldgen_biome_atlas_tile_identity = networking_worldgen_biome_atlas_tile_identity
    worldgen_biome_atlas_block_texture_usage = networking_worldgen_biome_atlas_block_texture_usage
    overload_status = networking_overload_status
    runtime_reconnect = networking_reconnect_status
    slow_client_status = networking_slow_client_status
    local_server_exposure = "loopback_enforced"
    smoke_bind_exposure = "loopback_guarded"
    active_protocol_change = proto_diff_count + 0

    reconnect_runtime_ok = networking_reconnect_status == "repeated_live_rebootstrap_guarded" &&
      networking_reconnect_smoke_status == "pass" &&
      networking_reconnect_smoke_client_state == "active" &&
      networking_reconnect_smoke_reader_errors + 0 >= 1 &&
      networking_reconnect_smoke_successes + 0 >= 1 &&
      networking_reconnect_soak_status == "pass" &&
      networking_reconnect_soak_cycles + 0 >= 2 &&
      networking_reconnect_soak_reader_errors + 0 >= networking_reconnect_soak_cycles + 0 &&
      networking_reconnect_soak_successes + 0 >= networking_reconnect_soak_cycles + 0
    slow_reader_runtime_ok = networking_slow_client_status == "load_matrix_guarded" &&
      networking_slow_reader_smoke_status == "pass" &&
      networking_slow_reader_timeout_observed + 0 == 1 &&
      networking_slow_reader_timeout_class == "timeout" &&
      networking_slow_reader_matrix_status == "pass" &&
      networking_slow_reader_matrix_counts_checked + 0 >= 2 &&
      networking_slow_reader_matrix_max_fast_clients + 0 >= 2 &&
      networking_slow_reader_matrix_total_fast_clients + 0 == networking_slow_reader_matrix_total_fast_bootstrap_chunks + 0 &&
      networking_slow_reader_matrix_total_slow_timeouts + 0 == networking_slow_reader_matrix_counts_checked + 0
    prereqs_ok = networking_status == "pass" && networking_protocol_change + 0 == 0 &&
      (networking_packet_error_classification == "unit_guarded" || networking_packet_error_classification == "source_guarded") &&
      networking_packet_error_aggregation == "parser_guarded" &&
      networking_packet_error_alerts == "threshold_guarded" &&
      networking_unknown_packet_policy == "ignored_guarded" &&
      networking_nil_packet_policy == "ignored_guarded" &&
      networking_nil_position_policy == "ignored_guarded" &&
      networking_nil_block_action_policy == "ignored_guarded" &&
      networking_conflict_semantics == "last_write_wins_guarded" &&
      networking_worldgen_biome_atlas_tile_identity == "guarded" &&
      networking_worldgen_biome_atlas_block_texture_usage == "guarded" &&
      networking_overload_status == "admission_matrix_guarded" &&
      reconnect_runtime_ok &&
      slow_reader_runtime_ok &&
      persistence_status == "pass" && persistence_protocol_change + 0 == 0 &&
      persistence_save_failure_rollback == "guarded" &&
      arch_status == "pass" && arch_runtime_change == "none" &&
      observability_status == "pass" && observability_error_scan == "clean" &&
      observability_gpu_report_freshness == "guarded" && observability_gpu_report_error_scan == "clean" &&
      packet_error_monitoring_status == "pass" &&
      packet_error_monitoring_contract == "export_ready" &&
      packet_error_monitoring_metrics_export == "present" &&
      packet_error_monitoring_unknown_classes + 0 == 0 &&
      packet_error_monitoring_protocol_errors + 0 == 0 &&
      packet_error_monitoring_write_errors + 0 == 0 &&
      server_session_monitoring_status == "pass" &&
      server_session_monitoring_contract == "export_ready" &&
      server_session_monitoring_metrics_export == "present" &&
      server_session_monitoring_close_failures + 0 == 0 &&
      server_session_monitoring_accept_failures + 0 == 0 &&
      server_session_monitoring_missing_active_client_fields + 0 == 0 &&
      storage_smoke_status == "pass" &&
      storage_smoke_guard == "guarded" &&
      storage_smoke_external_secret_required + 0 == 0 &&
      storage_smoke_database_env_policy == "postgres_env_ignored" &&
      storage_smoke_approved_databases == "postgresql_rocksdb"
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

    printf("security_data_integrity_review status=%s reason=%s security_status=%s packet_boundary=%s packet_error_classification=%s packet_error_aggregation=%s packet_error_alerts=%s packet_error_monitoring=%s server_session_monitoring=%s unknown_packet_policy=%s nil_packet_policy=%s nil_position_policy=%s nil_block_action_policy=%s storage_integrity=%s storage_package_smoke=%s storage_config=%s storage_backend_policy=%s storage_backend_ownership=%s storage_concurrency=%s storage_errors=%s storage_lifecycle=%s block_edit_validation=%s block_edit_save_failure_rollback=%s chunk_decode=%s deterministic_property_tests=%s conflict_semantics=%s worldgen_biome_atlas_tile_identity=%s worldgen_biome_atlas_block_texture_usage=%s overload_status=%s runtime_reconnect=%s reconnect_smoke_status=%s reconnect_smoke_client_state=%s reconnect_smoke_reader_errors=%d reconnect_smoke_successes=%d reconnect_soak_status=%s reconnect_soak_cycles=%d reconnect_soak_reader_errors=%d reconnect_soak_successes=%d slow_client_status=%s slow_reader_smoke_status=%s slow_reader_timeout_observed=%d slow_reader_timeout_class=%s slow_reader_matrix_status=%s slow_reader_matrix_counts_checked=%d slow_reader_matrix_max_fast_clients=%d slow_reader_matrix_total_fast_clients=%d slow_reader_matrix_total_fast_bootstrap_chunks=%d slow_reader_matrix_total_slow_timeouts=%d local_server_exposure=%s smoke_bind_exposure=%s active_protocol_change=%d go_integrity_tests=%s rust_packet_tests=%s rust_chunk_decode_tests=%s networking_status=%s persistence_status=%s arch_status=%s observability_status=%s observability_error_scan=%s observability_gpu_report_freshness=%s observability_gpu_report_error_scan=%s storage_smoke_status=%s storage_smoke_external_secret_required=%d storage_smoke_database_env_policy=%s storage_smoke_approved_databases=%s packet_error_monitoring_status=%s packet_error_monitoring_unknown_classes=%d packet_error_monitoring_protocol_errors=%d packet_error_monitoring_write_errors=%d server_session_monitoring_status=%s server_session_monitoring_close_failures=%d server_session_monitoring_accept_failures=%d server_session_monitoring_missing_active_client_fields=%d networking_summary=%s persistence_summary=%s arch_summary=%s observability_summary=%s storage_smoke_summary=%s packet_error_monitoring_summary=%s server_session_monitoring_summary=%s\n", status, reason, security_status, packet_boundary, networking_packet_error_classification, networking_packet_error_aggregation, networking_packet_error_alerts, packet_error_monitoring, server_session_monitoring, unknown_packet_policy, nil_packet_policy, nil_position_policy, nil_block_action_policy, storage_integrity, storage_package_smoke, storage_config, storage_backend_policy, storage_backend_ownership, storage_concurrency, storage_errors, storage_lifecycle, block_edit_validation, block_edit_save_failure_rollback, chunk_decode, deterministic_property_tests, conflict_semantics, worldgen_biome_atlas_tile_identity, worldgen_biome_atlas_block_texture_usage, overload_status, runtime_reconnect, networking_reconnect_smoke_status, networking_reconnect_smoke_client_state, networking_reconnect_smoke_reader_errors, networking_reconnect_smoke_successes, networking_reconnect_soak_status, networking_reconnect_soak_cycles, networking_reconnect_soak_reader_errors, networking_reconnect_soak_successes, slow_client_status, networking_slow_reader_smoke_status, networking_slow_reader_timeout_observed, networking_slow_reader_timeout_class, networking_slow_reader_matrix_status, networking_slow_reader_matrix_counts_checked, networking_slow_reader_matrix_max_fast_clients, networking_slow_reader_matrix_total_fast_clients, networking_slow_reader_matrix_total_fast_bootstrap_chunks, networking_slow_reader_matrix_total_slow_timeouts, local_server_exposure, smoke_bind_exposure, active_protocol_change, go_integrity_tests, rust_packet_tests, rust_chunk_decode_tests, networking_status, persistence_status, arch_status, observability_status, observability_error_scan, observability_gpu_report_freshness, observability_gpu_report_error_scan, storage_smoke_status, storage_smoke_external_secret_required, storage_smoke_database_env_policy, storage_smoke_approved_databases, packet_error_monitoring_status, packet_error_monitoring_unknown_classes, packet_error_monitoring_protocol_errors, packet_error_monitoring_write_errors, server_session_monitoring_status, server_session_monitoring_close_failures, server_session_monitoring_accept_failures, server_session_monitoring_missing_active_client_fields, networking_summary, persistence_summary, arch_summary, observability_summary, storage_smoke_summary, packet_error_monitoring_summary, server_session_monitoring_summary)
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
