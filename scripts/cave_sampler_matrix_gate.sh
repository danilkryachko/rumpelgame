#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/cave_sampler_matrix"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

SUMMARY_PATH="$OUT_DIR/cave-sampler-matrix-summary.txt"
RAW_SUMMARY_PATH="$OUT_DIR/cave-sampler-matrix-raw.txt"
CAVE_CMD="${RUMPELMC_CAVE_MATRIX_CMD:-"$ROOT_DIR/server/cmd/cave_sampler_matrix/main.go"}"
CAVE_SOURCE="${RUMPELMC_CAVE_MATRIX_SOURCE:-"$ROOT_DIR/server/pkg/world/cave.go"}"
CAVE_TEST="${RUMPELMC_CAVE_MATRIX_TEST:-"$ROOT_DIR/server/pkg/world/cave_test.go"}"
EXPECTED_HASH="${RUMPELMC_CAVE_MATRIX_EXPECTED_HASH:-f265ead2a700736c1e9b13056004af9c5c242d083c74c56d48e2cc76d1dfeeee}"
RUN_GO_TESTS="${RUMPELMC_CAVE_MATRIX_RUN_GO_TESTS:-1}"

mkdir -p "$OUT_DIR"

fail() {
  echo "cave_sampler_matrix_gate: $*" >&2
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

for path in "$CAVE_CMD" "$CAVE_SOURCE" "$CAVE_TEST"; do
  test -s "$path" || fail "missing required input $path"
done

require_token "$CAVE_CMD" "cave_sampler_matrix status=pass"
require_token "$CAVE_CMD" "sample_hash"
require_token "$CAVE_CMD" "protocol_change=0"
require_token "$CAVE_SOURCE" "CaveAlgorithmVersionV1"
require_token "$CAVE_SOURCE" "func (g WorldGenerator) SampleCave"
require_token "$CAVE_SOURCE" "func DeterministicCaveID"
require_token "$CAVE_TEST" "TestCaveSamplerV1StableVector"
require_token "$CAVE_TEST" "TestCaveSamplerDoesNotChangeGeneratedChunkBytes"

if ! (cd "$ROOT_DIR/server" && go run ./cmd/cave_sampler_matrix > "$RAW_SUMMARY_PATH" 2>"$OUT_DIR/cave-sampler-matrix.err"); then
  cat "$OUT_DIR/cave-sampler-matrix.err" >&2 || true
  fail "cave sampler matrix command failed"
fi

status="$(field_metric status "$RAW_SUMMARY_PATH")"
algorithm_version="$(field_metric algorithm_version "$RAW_SUMMARY_PATH")"
generator_version="$(field_metric generator_version "$RAW_SUMMARY_PATH")"
samples="$(field_metric samples "$RAW_SUMMARY_PATH")"
solid="$(field_metric solid "$RAW_SUMMARY_PATH")"
open="$(field_metric open "$RAW_SUMMARY_PATH")"
sample_hash="$(field_metric sample_hash "$RAW_SUMMARY_PATH")"
active_worldgen_change="$(field_metric active_worldgen_change "$RAW_SUMMARY_PATH")"
active_serialization_change="$(field_metric active_serialization_change "$RAW_SUMMARY_PATH")"
protocol_change="$(field_metric protocol_change "$RAW_SUMMARY_PATH")"
proto_diff_count="$(git -C "$ROOT_DIR" diff --name-only -- api/schema/packets.proto server/pkg/api/packets.pb.go | awk 'END { print NR + 0 }')"
chunk_diff_count="$(git -C "$ROOT_DIR" diff --name-only -- server/pkg/world/chunk.go | awk 'END { print NR + 0 }')"

world_tests="skipped"
if [ "$RUN_GO_TESTS" = "1" ]; then
  if (cd "$ROOT_DIR/server" && go test ./pkg/world ./cmd/cave_sampler_matrix > "$OUT_DIR/go-test-cave.txt" 2>&1); then
    world_tests="pass"
  else
    cat "$OUT_DIR/go-test-cave.txt" >&2 || true
    world_tests="fail"
  fi
fi

awk \
  -v raw_status="${status:-missing}" \
  -v algorithm_version="${algorithm_version:-missing}" \
  -v generator_version="${generator_version:-missing}" \
  -v samples="${samples:-0}" \
  -v solid="${solid:-0}" \
  -v open="${open:-0}" \
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
      solid + 0 == 8 &&
      open + 0 == 4
    clean_contract = active_worldgen_change + 0 == 0 &&
      active_serialization_change + 0 == 0 &&
      protocol_change + 0 == 0 &&
      proto_diff_count + 0 == 0 &&
      chunk_diff_count + 0 == 0
    tests_ok = world_tests == "pass" || world_tests == "skipped"

    if (raw_status != "pass" || algorithm_version != "cave_v1" || generator_version != "height_v1") {
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

    printf("cave_sampler_matrix status=%s reason=%s matrix_status=%s metadata_runtime=%s algorithm_version=%s generator_version=%s samples=%d solid=%d open=%d sample_hash=%s active_worldgen_change=%d active_serialization_change=%d protocol_change=%d proto_diff_count=%d chunk_diff_count=%d world_tests=%s raw_summary=%s\n", status, reason, matrix_status, metadata_runtime, algorithm_version, generator_version, samples, solid, open, sample_hash, active_worldgen_change, active_serialization_change, protocol_change, proto_diff_count, chunk_diff_count, world_tests, raw_summary)
    if (status != "pass") {
      exit 1
    }
  }
' > "$SUMMARY_PATH" || {
  cat "$SUMMARY_PATH" >&2 || true
  fail "cave sampler matrix gate failed"
}

cat "$SUMMARY_PATH"
echo "Cave sampler matrix artifacts: $OUT_DIR"
