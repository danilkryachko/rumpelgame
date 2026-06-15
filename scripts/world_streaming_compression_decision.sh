#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/world_streaming_compression_decision"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

RUN_RUNTIME_COMPARE="${RUMPELMC_COMPRESSION_DECISION_RUNTIME:-1}"
GO_TEST_LOG="$OUT_DIR/go-test.log"
BENCH_LOG="$OUT_DIR/world-rle-bench.log"
COMPARE_DIR="$OUT_DIR/encoding_compare"
SUMMARY_PATH="$OUT_DIR/chunk-compression-decision-summary.txt"

mkdir -p "$OUT_DIR"

fail() {
  echo "world_streaming_compression_decision: $*" >&2
  exit 1
}

write_summary() {
  {
    printf 'chunk_compression_decision status=pass runtime_compare=%s go_test_log=%s bench_log=%s\n' \
      "$RUN_RUNTIME_COMPARE" "$GO_TEST_LOG" "$BENCH_LOG"
    awk '
      /^Benchmark(ChunkSerializeFlat|EncodeSerializedChunkRLEFlat|DecodeSerializedChunkRLEFlat)/ {
        ns = "0"
        bytes = "0"
        allocs = "0"
        for (i = 2; i < NF; i++) {
          if ($(i + 1) == "ns/op") ns = $i
          if ($(i + 1) == "B/op") bytes = $i
          if ($(i + 1) == "allocs/op") allocs = $i
        }
        printf("chunk_compression_benchmark name=%s ns_per_op=%s bytes_per_op=%s allocs_per_op=%s\n", $1, ns, bytes, allocs)
      }
    ' "$BENCH_LOG"
    if [ "$RUN_RUNTIME_COMPARE" = "1" ]; then
      compare_summary="$COMPARE_DIR/world-streaming-encoding-compare-summary.txt"
      test -s "$compare_summary" || fail "missing runtime compare summary $compare_summary"
      awk '{ printf("chunk_compression_runtime %s\n", $0) }' "$compare_summary"
    else
      printf 'chunk_compression_runtime status=skipped reason=RUMPELMC_COMPRESSION_DECISION_RUNTIME_0\n'
    fi
  } > "$SUMMARY_PATH"
}

(
  cd "$ROOT_DIR/server"
  go test ./pkg/api ./pkg/world ./pkg/network
) > "$GO_TEST_LOG" 2>&1 || {
  cat "$GO_TEST_LOG" >&2 || true
  fail "go compatibility tests failed"
}

(
  cd "$ROOT_DIR/server"
  go test ./pkg/world -bench 'Benchmark(ChunkSerializeFlat|EncodeSerializedChunkRLEFlat|DecodeSerializedChunkRLEFlat)' -benchmem -benchtime="${RUMPELMC_COMPRESSION_DECISION_BENCHTIME:-100ms}" -run '^$'
) > "$BENCH_LOG" 2>&1 || {
  cat "$BENCH_LOG" >&2 || true
  fail "world RLE benchmarks failed"
}

case "$RUN_RUNTIME_COMPARE" in
  0) ;;
  1)
    RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE="${RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE:-1}" \
      RUMPELMC_GODOT_RUST_EXT_PROFILE="${RUMPELMC_GODOT_RUST_EXT_PROFILE:-release}" \
      /bin/sh "$ROOT_DIR/scripts/world_streaming_chunk_encoding_compare.sh" "$COMPARE_DIR"
    ;;
  *)
    fail "unsupported RUMPELMC_COMPRESSION_DECISION_RUNTIME=$RUN_RUNTIME_COMPARE"
    ;;
esac

write_summary
cat "$SUMMARY_PATH"
echo "Chunk compression decision artifacts: $OUT_DIR"
