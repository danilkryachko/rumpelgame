#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/world_streaming_chunk_encoding_compare"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

RAW_DIR="$OUT_DIR/raw"
RLE_DIR="$OUT_DIR/rle"
RAW_LOG="$RAW_DIR/run.log"
RAW_SUMMARY="$RAW_DIR/world-streaming-raw-summary.txt"
RLE_SUMMARY="$RLE_DIR/world-streaming-rle-summary.txt"
COMPARE_SUMMARY="$OUT_DIR/world-streaming-encoding-compare-summary.txt"
BUILD_SERVER="${RUMPELMC_WORLD_STREAMING_COMPARE_BUILD_SERVER:-1}"

mkdir -p "$RAW_DIR" "$RLE_DIR"

fail() {
  echo "world_streaming_chunk_encoding_compare: $*" >&2
  exit 1
}

sign_server_binary_if_possible() {
  if command -v codesign >/dev/null 2>&1; then
    codesign -s - --force ./server >/dev/null 2>&1 || true
  fi
}

listener_pid() {
  if command -v lsof >/dev/null 2>&1; then
    lsof -tiTCP:25565 -sTCP:LISTEN 2>/dev/null | sed -n '1p'
  fi
}

wait_for_port_clear() {
  tries=0
  while [ "$tries" -lt 10 ]; do
    pid="$(listener_pid || true)"
    if [ -z "$pid" ]; then
      return 0
    fi
    tries=$((tries + 1))
    sleep 1
  done
  fail "port 25565 is still listening after cleanup"
}

cleanup_server() {
  pid="$(listener_pid || true)"
  if [ -n "$pid" ]; then
    kill "$pid" 2>/dev/null || true
    wait_for_port_clear
  fi
}

metric() {
  key="$1"
  path="$2"
  awk -v key="$key" '
    {
      prefix = key "="
      for (i = 1; i <= NF; i++) {
        if (index($i, prefix) == 1) {
          value = substr($i, length(prefix) + 1)
          gsub(/[^0-9.].*/, "", value)
          print value
          exit
        }
      }
    }
  ' "$path"
}

summarize_stream_metrics() {
  encoding="$1"
  run_log="$2"
  marker_path="$3"
  summary_path="$4"

  test -s "$marker_path" || fail "missing movement marker $marker_path"
  grep -q "smoke_err=0" "$marker_path" || fail "smoke_err is not 0 in $marker_path"
  grep -q 'motion="chunk_walk"' "$marker_path" || fail "movement marker did not run chunk_walk"
  grep -q 'current_chunk="3,2"' "$marker_path" || fail "movement did not finish at chunk 3,2"
  grep -q "Chunk received .* blocks=1048576" "$run_log" || fail "$encoding chunks were not decoded to full block payloads"
  grep -q "Chunk stream batch" "$run_log" || fail "missing chunk stream batch metrics in $run_log"

  awk -v encoding="$encoding" -v marker_path="$marker_path" -v run_log="$run_log" '
    /Chunk stream batch/ {
      for (i = 1; i <= NF; i++) {
        split($i, a, "=")
        if (a[1] == "chunks") chunks += a[2]
        if (a[1] == "raw_bytes") raw += a[2]
        if (a[1] == "payload_bytes") payload += a[2]
        if (a[1] == "wire_bytes") wire += a[2]
      }
      batches++
    }
    END {
      if (batches < 1 || chunks < 1 || raw < 1 || payload < 1 || wire < 1) {
        printf("invalid stream metric totals encoding=%s batches=%d chunks=%d raw=%d payload=%d wire=%d\n", encoding, batches, chunks, raw, payload, wire) > "/dev/stderr"
        exit 1
      }
      if (encoding == "raw" && payload != raw) {
        printf("raw payload should equal raw bytes raw=%d payload=%d\n", raw, payload) > "/dev/stderr"
        exit 1
      }
      if (encoding == "rle" && payload * 100 >= raw) {
        printf("rle payload is not below 1%% of raw raw=%d payload=%d\n", raw, payload) > "/dev/stderr"
        exit 1
      }
      if (encoding == "rle" && wire * 100 >= raw) {
        printf("rle wire is not below 1%% of raw raw=%d wire=%d\n", raw, wire) > "/dev/stderr"
        exit 1
      }
      printf("world_streaming_%s_movement status=pass batches=%d chunks=%d raw_bytes=%d payload_bytes=%d wire_bytes=%d payload_pct=%.6f wire_pct=%.6f marker=%s run_log=%s\n", encoding, batches, chunks, raw, payload, wire, payload * 100.0 / raw, wire * 100.0 / raw, marker_path, run_log)
    }
  ' "$run_log" > "$summary_path"
}

listener="$(listener_pid || true)"
if [ -n "$listener" ]; then
  fail "port 25565 is already in use; stop the existing server before encoding compare"
fi
trap cleanup_server EXIT HUP INT TERM

case "$BUILD_SERVER" in
  0) ;;
  1)
    (
      cd "$ROOT_DIR/server"
      go build -o ./server ./cmd/server
      sign_server_binary_if_possible
    )
    ;;
  *)
    fail "unsupported RUMPELMC_WORLD_STREAMING_COMPARE_BUILD_SERVER=$BUILD_SERVER"
    ;;
esac

rm -f "$RAW_LOG" "$RAW_SUMMARY" "$RLE_SUMMARY" "$COMPARE_SUMMARY"

set +e
RUMPELMC_SERVER_CHUNK_ENCODING=raw \
  RUMPELMC_SERVER_CHUNK_STREAM_METRICS=1 \
  RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE="${RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE:-1}" \
  RUMPELMC_GODOT_RUST_EXT_PROFILE="${RUMPELMC_GODOT_RUST_EXT_PROFILE:-release}" \
  /bin/sh "$ROOT_DIR/scripts/gpu_terrain_movement_stress.sh" "$RAW_DIR" > "$RAW_LOG" 2>&1
rc=$?
set -e
if [ "$rc" -ne 0 ]; then
  cat "$RAW_LOG" >&2 || true
  fail "raw movement stress failed with exit code $rc"
fi
cleanup_server

RUMPELMC_WORLD_STREAMING_SMOKE_BUILD_SERVER=0 \
  RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE="${RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE:-1}" \
  RUMPELMC_GODOT_RUST_EXT_PROFILE="${RUMPELMC_GODOT_RUST_EXT_PROFILE:-release}" \
  /bin/sh "$ROOT_DIR/scripts/world_streaming_rle_movement_smoke.sh" "$RLE_DIR"

summarize_stream_metrics raw "$RAW_LOG" "$RAW_DIR/gpu-terrain-movement-stress.png.txt" "$RAW_SUMMARY"

raw_chunks="$(metric chunks "$RAW_SUMMARY")"
raw_raw_bytes="$(metric raw_bytes "$RAW_SUMMARY")"
raw_payload_bytes="$(metric payload_bytes "$RAW_SUMMARY")"
raw_wire_bytes="$(metric wire_bytes "$RAW_SUMMARY")"
rle_chunks="$(metric chunks "$RLE_SUMMARY")"
rle_raw_bytes="$(metric raw_bytes "$RLE_SUMMARY")"
rle_payload_bytes="$(metric payload_bytes "$RLE_SUMMARY")"
rle_wire_bytes="$(metric wire_bytes "$RLE_SUMMARY")"

test -n "$raw_chunks" || fail "missing raw chunks in $RAW_SUMMARY"
test -n "$rle_chunks" || fail "missing rle chunks in $RLE_SUMMARY"
awk \
  -v raw_chunks="$raw_chunks" \
  -v raw_raw="$raw_raw_bytes" \
  -v raw_payload="$raw_payload_bytes" \
  -v raw_wire="$raw_wire_bytes" \
  -v rle_chunks="$rle_chunks" \
  -v rle_raw="$rle_raw_bytes" \
  -v rle_payload="$rle_payload_bytes" \
  -v rle_wire="$rle_wire_bytes" \
  -v raw_summary="$RAW_SUMMARY" \
  -v rle_summary="$RLE_SUMMARY" '
  BEGIN {
    if (rle_payload * raw_raw >= raw_payload * rle_raw) {
      printf("rle normalized payload did not shrink raw_payload/raw=%d/%d rle_payload/raw=%d/%d\n", raw_payload, raw_raw, rle_payload, rle_raw) > "/dev/stderr"
      exit 1
    }
    if (rle_wire * raw_raw >= raw_wire * rle_raw) {
      printf("rle normalized wire did not shrink raw_wire/raw=%d/%d rle_wire/raw=%d/%d\n", raw_wire, raw_raw, rle_wire, rle_raw) > "/dev/stderr"
      exit 1
    }
    printf("world_streaming_encoding_compare status=pass raw_chunks=%d rle_chunks=%d raw_raw_bytes=%d rle_raw_bytes=%d raw_payload_bytes=%d rle_payload_bytes=%d raw_wire_bytes=%d rle_wire_bytes=%d raw_payload_pct=%.6f rle_payload_pct=%.6f raw_wire_pct=%.6f rle_wire_pct=%.6f raw_summary=%s rle_summary=%s\n", raw_chunks, rle_chunks, raw_raw, rle_raw, raw_payload, rle_payload, raw_wire, rle_wire, raw_payload * 100.0 / raw_raw, rle_payload * 100.0 / rle_raw, raw_wire * 100.0 / raw_raw, rle_wire * 100.0 / rle_raw, raw_summary, rle_summary)
  }
' > "$COMPARE_SUMMARY"

cat "$RAW_SUMMARY"
cat "$RLE_SUMMARY"
cat "$COMPARE_SUMMARY"
