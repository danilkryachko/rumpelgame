#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/cave_height_generator_matrix"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

SUMMARY_PATH="$OUT_DIR/cave-height-generator-matrix-summary.txt"
RAW_SUMMARY_PATH="$OUT_DIR/cave-height-generator-matrix-raw.txt"
CAVE_HEIGHT_CMD="${RUMPELMC_CAVE_HEIGHT_MATRIX_CMD:-"$ROOT_DIR/server/cmd/cave_height_generator_matrix/main.go"}"
GENERATOR_SOURCE="${RUMPELMC_CAVE_HEIGHT_MATRIX_GENERATOR_SOURCE:-"$ROOT_DIR/server/pkg/world/generator.go"}"
GENERATOR_TEST="${RUMPELMC_CAVE_HEIGHT_MATRIX_GENERATOR_TEST:-"$ROOT_DIR/server/pkg/world/generator_test.go"}"
CHUNK_ENCODING_TEST="${RUMPELMC_CAVE_HEIGHT_MATRIX_CHUNK_ENCODING_TEST:-"$ROOT_DIR/server/pkg/world/chunk_encoding_test.go"}"
SERVER_CMD_TEST="${RUMPELMC_CAVE_HEIGHT_MATRIX_SERVER_CMD_TEST:-"$ROOT_DIR/server/cmd/server/main_test.go"}"
EXPECTED_HASH="${RUMPELMC_CAVE_HEIGHT_MATRIX_EXPECTED_HASH:-b68d1ca3e6471015c317c4b1d750dcddc59a8481f4cc2d26e394730d55fd7541}"
RUN_GO_TESTS="${RUMPELMC_CAVE_HEIGHT_MATRIX_RUN_GO_TESTS:-1}"

mkdir -p "$OUT_DIR"

fail() {
  echo "cave_height_generator_matrix_gate: $*" >&2
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

for path in "$CAVE_HEIGHT_CMD" "$GENERATOR_SOURCE" "$GENERATOR_TEST" "$CHUNK_ENCODING_TEST" "$SERVER_CMD_TEST"; do
  test -s "$path" || fail "missing required input $path"
done

require_token "$CAVE_HEIGHT_CMD" "cave_height_generator_matrix status=pass"
require_token "$CAVE_HEIGHT_CMD" "surface_preserved"
require_token "$CAVE_HEIGHT_CMD" "protocol_change=0"
require_token "$GENERATOR_SOURCE" "GeneratorVersionCaveHeightV1"
require_token "$GENERATOR_SOURCE" "func (g WorldGenerator) generateCaveHeightV1"
require_token "$GENERATOR_SOURCE" "func (g WorldGenerator) carveCaveHeightV1Column"
require_token "$GENERATOR_TEST" "TestConfiguredCaveHeightV1GeneratorIsDeterministicForSeedDimensionAndCoordinates"
require_token "$GENERATOR_TEST" "TestConfiguredCaveHeightV1GeneratorChangesWithSeedAndDimension"
require_token "$GENERATOR_TEST" "stableCaveHeightV1ChunkSHA256"
require_token "$CHUNK_ENCODING_TEST" "TestEncodeSerializedChunkRLERoundTripsCaveHeightV1Chunk"
require_token "$SERVER_CMD_TEST" "TestConfiguredWorldGeneratorConfigAcceptsCaveHeightV1"

if ! (cd "$ROOT_DIR/server" && go run ./cmd/cave_height_generator_matrix > "$RAW_SUMMARY_PATH" 2>"$OUT_DIR/cave-height-generator-matrix.err"); then
  cat "$OUT_DIR/cave-height-generator-matrix.err" >&2 || true
  fail "cave height generator matrix command failed"
fi

status="$(field_metric status "$RAW_SUMMARY_PATH")"
generator_version="$(field_metric generator_version "$RAW_SUMMARY_PATH")"
chunk_hash="$(field_metric chunk_hash "$RAW_SUMMARY_PATH")"
carved_air="$(field_metric carved_air "$RAW_SUMMARY_PATH")"
byte_diff="$(field_metric byte_diff "$RAW_SUMMARY_PATH")"
surface_columns="$(field_metric surface_columns "$RAW_SUMMARY_PATH")"
surface_preserved="$(field_metric surface_preserved "$RAW_SUMMARY_PATH")"
active_default_change="$(field_metric active_default_change "$RAW_SUMMARY_PATH")"
active_serialization_change="$(field_metric active_serialization_change "$RAW_SUMMARY_PATH")"
protocol_change="$(field_metric protocol_change "$RAW_SUMMARY_PATH")"
proto_diff_count="$(git -C "$ROOT_DIR" diff --name-only -- api/schema/packets.proto server/pkg/api/packets.pb.go | awk 'END { print NR + 0 }')"

world_tests="skipped"
if [ "$RUN_GO_TESTS" = "1" ]; then
  if (cd "$ROOT_DIR/server" && go test ./pkg/world ./cmd/server ./cmd/cave_height_generator_matrix > "$OUT_DIR/go-test-cave-height.txt" 2>&1); then
    world_tests="pass"
  else
    cat "$OUT_DIR/go-test-cave-height.txt" >&2 || true
    world_tests="fail"
  fi
fi

awk \
  -v raw_status="${status:-missing}" \
  -v generator_version="${generator_version:-missing}" \
  -v chunk_hash="${chunk_hash:-missing}" \
  -v expected_hash="$EXPECTED_HASH" \
  -v carved_air="${carved_air:-0}" \
  -v byte_diff="${byte_diff:-0}" \
  -v surface_columns="${surface_columns:-0}" \
  -v surface_preserved="${surface_preserved:-0}" \
  -v active_default_change="${active_default_change:-1}" \
  -v active_serialization_change="${active_serialization_change:-1}" \
  -v protocol_change="${protocol_change:-1}" \
  -v proto_diff_count="$proto_diff_count" \
  -v world_tests="$world_tests" \
  -v raw_summary="$RAW_SUMMARY_PATH" '
  BEGIN {
    status = "pass"
    reason = "ok"
    matrix_status = "guarded"
    chunk_bytes = "guarded"
    surface_status = "guarded"
    carved_ok = carved_air + 0 == 34728 &&
      byte_diff + 0 == 69456
    surface_ok = surface_columns + 0 == 1024 &&
      surface_preserved + 0 == 1024
    clean_contract = active_default_change + 0 == 0 &&
      active_serialization_change + 0 == 0 &&
      protocol_change + 0 == 0 &&
      proto_diff_count + 0 == 0
    tests_ok = world_tests == "pass" || world_tests == "skipped"

    if (raw_status != "pass" || generator_version != "cave_height_v1") {
      status = "fail"
      reason = "matrix_command_not_clean"
    } else if (chunk_hash != expected_hash || !carved_ok) {
      status = "fail"
      reason = "cave_height_signature_changed"
    } else if (!surface_ok) {
      status = "fail"
      reason = "surface_not_preserved"
    } else if (!clean_contract) {
      status = "fail"
      reason = "default_serialization_or_protocol_diff_present"
    } else if (!tests_ok) {
      status = "fail"
      reason = "world_tests_failed"
    }

    printf("cave_height_generator_matrix status=%s reason=%s matrix_status=%s chunk_bytes=%s surface_status=%s generator_version=%s chunk_hash=%s carved_air=%d byte_diff=%d surface_columns=%d surface_preserved=%d active_default_change=%d active_serialization_change=%d protocol_change=%d proto_diff_count=%d world_tests=%s raw_summary=%s\n", status, reason, matrix_status, chunk_bytes, surface_status, generator_version, chunk_hash, carved_air, byte_diff, surface_columns, surface_preserved, active_default_change, active_serialization_change, protocol_change, proto_diff_count, world_tests, raw_summary)
    if (status != "pass") {
      exit 1
    }
  }
' > "$SUMMARY_PATH" || {
  cat "$SUMMARY_PATH" >&2 || true
  fail "cave height generator matrix gate failed"
}

cat "$SUMMARY_PATH"
echo "Cave height generator matrix artifacts: $OUT_DIR"
