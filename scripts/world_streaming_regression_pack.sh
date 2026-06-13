#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/world_streaming_regression_pack"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

BOOTSTRAP_DIR="$OUT_DIR/bootstrap"
BATCH_DIR="$OUT_DIR/batch"
ENCODING_DIR="$OUT_DIR/encoding"
RLE_DIR="$OUT_DIR/rle"
SUMMARY_PATH="$OUT_DIR/world-streaming-regression-summary.txt"

BOOTSTRAP_SUMMARY="$BOOTSTRAP_DIR/world-streaming-bootstrap-compare-summary.txt"
BATCH_SUMMARY="$BATCH_DIR/world-streaming-batch-compare-summary.txt"
ENCODING_SUMMARY="$ENCODING_DIR/world-streaming-encoding-compare-summary.txt"
RLE_SUMMARY="$RLE_DIR/world-streaming-rle-summary.txt"

mkdir -p "$OUT_DIR"

fail() {
  echo "world_streaming_regression_pack: $*" >&2
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

require_pass_summary() {
  label="$1"
  path="$2"
  test -s "$path" || fail "missing $label summary $path"
  grep -q "status=pass" "$path" || fail "$label summary did not pass: $path"
}

listener="$(listener_pid || true)"
if [ -n "$listener" ]; then
  fail "port 25565 is already in use; stop the existing server before regression pack"
fi
trap cleanup_server EXIT HUP INT TERM

(
  cd "$ROOT_DIR/server"
  go build -o ./server ./cmd/server
  sign_server_binary_if_possible
)

rm -rf "$BOOTSTRAP_DIR" "$BATCH_DIR" "$ENCODING_DIR" "$RLE_DIR"
rm -f "$SUMMARY_PATH"

RUMPELMC_WORLD_STREAMING_BOOTSTRAP_COMPARE_BUILD_SERVER=0 \
  RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE="${RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE:-1}" \
  RUMPELMC_GODOT_RUST_EXT_PROFILE="${RUMPELMC_GODOT_RUST_EXT_PROFILE:-release}" \
  /bin/sh "$ROOT_DIR/scripts/world_streaming_bootstrap_compare.sh" "$BOOTSTRAP_DIR"

RUMPELMC_WORLD_STREAMING_BATCH_COMPARE_BUILD_SERVER=0 \
  RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE="${RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE:-1}" \
  RUMPELMC_GODOT_RUST_EXT_PROFILE="${RUMPELMC_GODOT_RUST_EXT_PROFILE:-release}" \
  /bin/sh "$ROOT_DIR/scripts/world_streaming_batch_compare.sh" "$BATCH_DIR"

RUMPELMC_WORLD_STREAMING_COMPARE_BUILD_SERVER=0 \
  RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE="${RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE:-1}" \
  RUMPELMC_GODOT_RUST_EXT_PROFILE="${RUMPELMC_GODOT_RUST_EXT_PROFILE:-release}" \
  /bin/sh "$ROOT_DIR/scripts/world_streaming_chunk_encoding_compare.sh" "$ENCODING_DIR"

RUMPELMC_WORLD_STREAMING_SMOKE_BUILD_SERVER=0 \
  RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE="${RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE:-1}" \
  RUMPELMC_GODOT_RUST_EXT_PROFILE="${RUMPELMC_GODOT_RUST_EXT_PROFILE:-release}" \
  /bin/sh "$ROOT_DIR/scripts/world_streaming_rle_movement_smoke.sh" "$RLE_DIR"

require_pass_summary bootstrap "$BOOTSTRAP_SUMMARY"
require_pass_summary batch "$BATCH_SUMMARY"
require_pass_summary encoding "$ENCODING_SUMMARY"
require_pass_summary rle "$RLE_SUMMARY"

bootstrap_candidate_first_chunks="$(metric candidate_first_chunks "$BOOTSTRAP_SUMMARY")"
bootstrap_candidate_startup_player_spawn="$(metric candidate_startup_player_spawn_ms "$BOOTSTRAP_SUMMARY")"
batch_candidate_chunks="$(metric candidate_chunks "$BATCH_SUMMARY")"
batch_candidate_batches="$(metric candidate_batches "$BATCH_SUMMARY")"
batch_candidate_startup_player_spawn="$(metric candidate_startup_player_spawn_ms "$BATCH_SUMMARY")"
encoding_rle_chunks="$(metric rle_chunks "$ENCODING_SUMMARY")"
encoding_rle_wire_pct="$(metric rle_wire_pct "$ENCODING_SUMMARY")"
encoding_rle_startup_player_spawn="$(metric rle_startup_player_spawn_ms "$ENCODING_SUMMARY")"
rle_chunks="$(metric chunks "$RLE_SUMMARY")"
rle_wire_pct="$(metric wire_pct "$RLE_SUMMARY")"
rle_startup_player_spawn="$(metric startup_player_spawn_ms "$RLE_SUMMARY")"

test -n "$bootstrap_candidate_first_chunks" || fail "missing bootstrap candidate_first_chunks"
test -n "$batch_candidate_chunks" || fail "missing batch candidate_chunks"
test -n "$encoding_rle_chunks" || fail "missing encoding rle_chunks"
test -n "$rle_chunks" || fail "missing rle chunks"

awk \
  -v bootstrap_candidate_first_chunks="$bootstrap_candidate_first_chunks" \
  -v bootstrap_candidate_startup_player_spawn="$bootstrap_candidate_startup_player_spawn" \
  -v batch_candidate_chunks="$batch_candidate_chunks" \
  -v batch_candidate_batches="$batch_candidate_batches" \
  -v batch_candidate_startup_player_spawn="$batch_candidate_startup_player_spawn" \
  -v encoding_rle_chunks="$encoding_rle_chunks" \
  -v encoding_rle_wire_pct="$encoding_rle_wire_pct" \
  -v encoding_rle_startup_player_spawn="$encoding_rle_startup_player_spawn" \
  -v rle_chunks="$rle_chunks" \
  -v rle_wire_pct="$rle_wire_pct" \
  -v rle_startup_player_spawn="$rle_startup_player_spawn" \
  -v bootstrap_summary="$BOOTSTRAP_SUMMARY" \
  -v batch_summary="$BATCH_SUMMARY" \
  -v encoding_summary="$ENCODING_SUMMARY" \
  -v rle_summary="$RLE_SUMMARY" '
  BEGIN {
    printf("world_streaming_regression status=pass bootstrap_candidate_first_chunks=%d bootstrap_candidate_startup_player_spawn_ms=%.3f batch_candidate_chunks=%d batch_candidate_batches=%d batch_candidate_startup_player_spawn_ms=%.3f encoding_rle_chunks=%d encoding_rle_wire_pct=%.6f encoding_rle_startup_player_spawn_ms=%.3f rle_chunks=%d rle_wire_pct=%.6f rle_startup_player_spawn_ms=%.3f bootstrap_summary=%s batch_summary=%s encoding_summary=%s rle_summary=%s\n", bootstrap_candidate_first_chunks, bootstrap_candidate_startup_player_spawn, batch_candidate_chunks, batch_candidate_batches, batch_candidate_startup_player_spawn, encoding_rle_chunks, encoding_rle_wire_pct, encoding_rle_startup_player_spawn, rle_chunks, rle_wire_pct, rle_startup_player_spawn, bootstrap_summary, batch_summary, encoding_summary, rle_summary)
  }
' > "$SUMMARY_PATH"

cat "$SUMMARY_PATH"
