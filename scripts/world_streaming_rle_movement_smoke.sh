#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/world_streaming_rle_movement_smoke"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

RUN_LOG="$OUT_DIR/run.log"
SUMMARY_PATH="$OUT_DIR/world-streaming-rle-summary.txt"
MARKER_PATH="$OUT_DIR/gpu-terrain-movement-stress.png.txt"
BUILD_SERVER="${RUMPELMC_WORLD_STREAMING_SMOKE_BUILD_SERVER:-1}"

mkdir -p "$OUT_DIR"

fail() {
  echo "world_streaming_rle_movement_smoke: $*" >&2
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

listener="$(listener_pid || true)"
if [ -n "$listener" ]; then
  fail "port 25565 is already in use; stop the existing server before RLE movement smoke"
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
    fail "unsupported RUMPELMC_WORLD_STREAMING_SMOKE_BUILD_SERVER=$BUILD_SERVER"
    ;;
esac

rm -f "$RUN_LOG" "$SUMMARY_PATH"

set +e
RUMPELMC_SERVER_CHUNK_ENCODING=rle \
  RUMPELMC_SERVER_CHUNK_STREAM_METRICS=1 \
  RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE="${RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE:-1}" \
  RUMPELMC_GODOT_RUST_EXT_PROFILE="${RUMPELMC_GODOT_RUST_EXT_PROFILE:-release}" \
  "$ROOT_DIR/scripts/gpu_terrain_movement_stress.sh" "$OUT_DIR" > "$RUN_LOG" 2>&1
rc=$?
set -e

if [ "$rc" -ne 0 ]; then
  cat "$RUN_LOG" >&2 || true
  fail "movement stress failed with exit code $rc"
fi

test -s "$MARKER_PATH" || fail "missing movement marker $MARKER_PATH"
grep -q "smoke_err=0" "$MARKER_PATH" || fail "smoke_err is not 0 in $MARKER_PATH"
grep -q 'motion="chunk_walk"' "$MARKER_PATH" || fail "movement marker did not run chunk_walk"
grep -q 'current_chunk="3,2"' "$MARKER_PATH" || fail "movement did not finish at chunk 3,2"
grep -q "Chunk received .* blocks=1048576" "$RUN_LOG" || fail "RLE chunks were not decoded to full block payloads"
grep -q "Chunk stream batch" "$RUN_LOG" || fail "missing chunk stream batch metrics in $RUN_LOG"

awk '
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
      printf("invalid stream metric totals batches=%d chunks=%d raw=%d payload=%d wire=%d\n", batches, chunks, raw, payload, wire) > "/dev/stderr"
      exit 1
    }
    if (payload >= raw) {
      printf("payload did not shrink raw=%d payload=%d\n", raw, payload) > "/dev/stderr"
      exit 1
    }
    if (wire >= raw) {
      printf("wire did not shrink raw=%d wire=%d\n", raw, wire) > "/dev/stderr"
      exit 1
    }
    if (payload * 100 >= raw) {
      printf("payload is not below 1%% of raw raw=%d payload=%d\n", raw, payload) > "/dev/stderr"
      exit 1
    }
    if (wire * 100 >= raw) {
      printf("wire is not below 1%% of raw raw=%d wire=%d\n", raw, wire) > "/dev/stderr"
      exit 1
    }
    printf("world_streaming_rle_movement status=pass batches=%d chunks=%d raw_bytes=%d payload_bytes=%d wire_bytes=%d payload_pct=%.6f wire_pct=%.6f marker=%s run_log=%s\n", batches, chunks, raw, payload, wire, payload * 100.0 / raw, wire * 100.0 / raw, marker_path, run_log)
  }
' marker_path="$MARKER_PATH" run_log="$RUN_LOG" "$RUN_LOG" > "$SUMMARY_PATH"

cat "$SUMMARY_PATH"
