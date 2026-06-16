#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/resource_distribution_matrix"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

SUMMARY_PATH="$OUT_DIR/resource-distribution-matrix-summary.txt"
RAW_SUMMARY_PATH="$OUT_DIR/resource-distribution-matrix-raw.txt"
RESOURCE_CMD="${RUMPELMC_RESOURCE_MATRIX_CMD:-"$ROOT_DIR/server/cmd/resource_distribution_matrix/main.go"}"
RESOURCE_SOURCE="${RUMPELMC_RESOURCE_MATRIX_SOURCE:-"$ROOT_DIR/server/pkg/world/resource.go"}"
RESOURCE_TEST="${RUMPELMC_RESOURCE_MATRIX_TEST:-"$ROOT_DIR/server/pkg/world/resource_test.go"}"
EXPECTED_HASH="${RUMPELMC_RESOURCE_MATRIX_EXPECTED_HASH:-f2beb912cffae722b9ea0322c68caa58a853c3c953fa4a0a80e618b42924e430}"
RUN_GO_TESTS="${RUMPELMC_RESOURCE_MATRIX_RUN_GO_TESTS:-1}"

mkdir -p "$OUT_DIR"

fail() {
  echo "resource_distribution_matrix_gate: $*" >&2
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

for path in "$RESOURCE_CMD" "$RESOURCE_SOURCE" "$RESOURCE_TEST"; do
  test -s "$path" || fail "missing required input $path"
done

require_token "$RESOURCE_CMD" "resource_distribution_matrix status=pass"
require_token "$RESOURCE_CMD" "sample_hash"
require_token "$RESOURCE_CMD" "protocol_change=0"
require_token "$RESOURCE_SOURCE" "ResourceAlgorithmVersionV1"
require_token "$RESOURCE_SOURCE" "func (g WorldGenerator) SampleResource"
require_token "$RESOURCE_SOURCE" "func DeterministicResourceID"
require_token "$RESOURCE_TEST" "TestResourceSamplerV1StableVector"
require_token "$RESOURCE_TEST" "TestResourceSamplerDoesNotChangeGeneratedChunkBytes"

if ! (cd "$ROOT_DIR/server" && go run ./cmd/resource_distribution_matrix > "$RAW_SUMMARY_PATH" 2>"$OUT_DIR/resource-distribution-matrix.err"); then
  cat "$OUT_DIR/resource-distribution-matrix.err" >&2 || true
  fail "resource distribution matrix command failed"
fi

status="$(field_metric status "$RAW_SUMMARY_PATH")"
algorithm_version="$(field_metric algorithm_version "$RAW_SUMMARY_PATH")"
generator_version="$(field_metric generator_version "$RAW_SUMMARY_PATH")"
samples="$(field_metric samples "$RAW_SUMMARY_PATH")"
none="$(field_metric none "$RAW_SUMMARY_PATH")"
coal="$(field_metric coal "$RAW_SUMMARY_PATH")"
copper="$(field_metric copper "$RAW_SUMMARY_PATH")"
iron="$(field_metric iron "$RAW_SUMMARY_PATH")"
sample_hash="$(field_metric sample_hash "$RAW_SUMMARY_PATH")"
active_worldgen_change="$(field_metric active_worldgen_change "$RAW_SUMMARY_PATH")"
active_serialization_change="$(field_metric active_serialization_change "$RAW_SUMMARY_PATH")"
protocol_change="$(field_metric protocol_change "$RAW_SUMMARY_PATH")"
proto_diff_count="$(git -C "$ROOT_DIR" diff --name-only -- api/schema/packets.proto server/pkg/api/packets.pb.go | awk 'END { print NR + 0 }')"
chunk_diff_count="$(git -C "$ROOT_DIR" diff --name-only -- server/pkg/world/chunk.go | awk 'END { print NR + 0 }')"

world_tests="skipped"
if [ "$RUN_GO_TESTS" = "1" ]; then
  if (cd "$ROOT_DIR/server" && go test ./pkg/world ./cmd/resource_distribution_matrix > "$OUT_DIR/go-test-resource.txt" 2>&1); then
    world_tests="pass"
  else
    cat "$OUT_DIR/go-test-resource.txt" >&2 || true
    world_tests="fail"
  fi
fi

awk \
  -v raw_status="${status:-missing}" \
  -v algorithm_version="${algorithm_version:-missing}" \
  -v generator_version="${generator_version:-missing}" \
  -v samples="${samples:-0}" \
  -v none="${none:-0}" \
  -v coal="${coal:-0}" \
  -v copper="${copper:-0}" \
  -v iron="${iron:-0}" \
  -v sample_hash="${sample_hash:-missing}" \
  -v expected_hash="$EXPECTED_HASH" \
  -v active_worldgen_change="${active_worldgen_change:-1}" \
  -v active_serialization_change="${active_serialization_change:-1}" \
  -v protocol_change="${protocol_change:-1}" \
  -v proto_diff_count="$proto_diff_count" \
  -v chunk_diff_count="$chunk_diff_count" \
  -v world_tests="$world_tests" \
  -v raw_summary="$RAW_SUMMARY_PATH" '
  BEGIN {
    status = "pass"
    reason = "ok"
    matrix_status = "guarded"
    metadata_runtime = "matrix_only"
    counts_ok = samples + 0 == 12 &&
      none + 0 == 6 &&
      coal + 0 == 3 &&
      copper + 0 == 1 &&
      iron + 0 == 2
    clean_contract = active_worldgen_change + 0 == 0 &&
      active_serialization_change + 0 == 0 &&
      protocol_change + 0 == 0 &&
      proto_diff_count + 0 == 0 &&
      chunk_diff_count + 0 == 0
    tests_ok = world_tests == "pass" || world_tests == "skipped"

    if (raw_status != "pass" || algorithm_version != "resource_v1" || generator_version != "height_v1") {
      status = "fail"
      reason = "matrix_command_not_clean"
    } else if (!counts_ok || sample_hash != expected_hash) {
      status = "fail"
      reason = "matrix_signature_changed"
    } else if (!clean_contract) {
      status = "fail"
      reason = "worldgen_serialization_or_protocol_diff_present"
    } else if (!tests_ok) {
      status = "fail"
      reason = "world_tests_failed"
    }

    printf("resource_distribution_matrix status=%s reason=%s matrix_status=%s metadata_runtime=%s algorithm_version=%s generator_version=%s samples=%d none=%d coal=%d copper=%d iron=%d sample_hash=%s active_worldgen_change=%d active_serialization_change=%d protocol_change=%d proto_diff_count=%d chunk_diff_count=%d world_tests=%s raw_summary=%s\n", status, reason, matrix_status, metadata_runtime, algorithm_version, generator_version, samples, none, coal, copper, iron, sample_hash, active_worldgen_change, active_serialization_change, protocol_change, proto_diff_count, chunk_diff_count, world_tests, raw_summary)
    if (status != "pass") {
      exit 1
    }
  }
' > "$SUMMARY_PATH" || {
  cat "$SUMMARY_PATH" >&2 || true
  fail "resource distribution matrix gate failed"
}

cat "$SUMMARY_PATH"
echo "Resource distribution matrix artifacts: $OUT_DIR"
