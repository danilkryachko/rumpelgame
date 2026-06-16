#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/server_slow_reader_smoke"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

SERVER_DIR="$ROOT_DIR/server"
SERVER_BINARY="$SERVER_DIR/server"
SMOKE_PORT="${RUMPELMC_SERVER_SLOW_READER_SMOKE_PORT:-25567}"
SMOKE_ADDR="127.0.0.1:$SMOKE_PORT"
SMOKE_DB="$OUT_DIR/rocksdb"
SERVER_LOG="$OUT_DIR/server.log"
CLIENT_LOG="$OUT_DIR/client.log"
SUMMARY_PATH="$OUT_DIR/server-slow-reader-smoke-summary.txt"
BUILD_SERVER="${RUMPELMC_SERVER_SLOW_READER_SMOKE_BUILD_SERVER:-1}"
WRITE_TIMEOUT_MS="${RUMPELMC_SERVER_SLOW_READER_WRITE_TIMEOUT_MS:-150}"
FAST_CLIENTS="${RUMPELMC_SERVER_SLOW_READER_FAST_CLIENTS:-1}"
SERVER_PID=""

mkdir -p "$OUT_DIR"

fail() {
  echo "server_slow_reader_smoke: $*" >&2
  exit 1
}

sign_server_binary_if_possible() {
  if command -v codesign >/dev/null 2>&1; then
    codesign -s - --force "$SERVER_BINARY" >/dev/null 2>&1 || true
  fi
}

listener_pid() {
  if command -v lsof >/dev/null 2>&1; then
    lsof -tiTCP:"$SMOKE_PORT" -sTCP:LISTEN 2>/dev/null | sed -n '1p'
  fi
}

wait_for_server() {
  tries=0
  while [ "$tries" -lt 30 ]; do
    pid="$(listener_pid || true)"
    if [ -n "$pid" ]; then
      return 0
    fi
    tries=$((tries + 1))
    sleep 1
  done
  cat "$SERVER_LOG" >&2 || true
  fail "server did not start listening on port $SMOKE_PORT"
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
  fail "port $SMOKE_PORT is still listening after cleanup"
}

cleanup_server() {
  if [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
    wait_for_port_clear
  fi
}

wait_for_slow_timeout_log() {
  tries=0
  while [ "$tries" -lt 30 ]; do
    if grep -Eq 'Failed to (handle initial client packet|send initial chunks) packet_error_class=timeout: .*i/o timeout' "$SERVER_LOG" 2>/dev/null; then
      return 0
    fi
    tries=$((tries + 1))
    sleep 0.25
  done
  return 1
}

listener="$(listener_pid || true)"
if [ -n "$listener" ]; then
  fail "port $SMOKE_PORT is already in use; choose another RUMPELMC_SERVER_SLOW_READER_SMOKE_PORT"
fi
trap cleanup_server EXIT HUP INT TERM

case "$BUILD_SERVER" in
  0) ;;
  1)
    (
      cd "$SERVER_DIR"
      go build -o ./server ./cmd/server
      sign_server_binary_if_possible
    )
    ;;
  *)
    fail "unsupported RUMPELMC_SERVER_SLOW_READER_SMOKE_BUILD_SERVER=$BUILD_SERVER"
    ;;
esac
case "$FAST_CLIENTS" in
  ''|*[!0-9]*) fail "unsupported RUMPELMC_SERVER_SLOW_READER_FAST_CLIENTS=$FAST_CLIENTS" ;;
esac
if [ "$FAST_CLIENTS" -lt 1 ]; then
  fail "RUMPELMC_SERVER_SLOW_READER_FAST_CLIENTS must be at least 1"
fi

rm -f "$SERVER_LOG" "$CLIENT_LOG" "$SUMMARY_PATH"
rm -rf "$SMOKE_DB"

(
  cd "$SERVER_DIR"
  exec env RUMPELMC_SERVER_CHUNK_ENCODING=raw \
    RUMPELMC_SERVER_ADDRESS=":$SMOKE_PORT" \
    RUMPELMC_SERVER_ROCKSDB_PATH="$SMOKE_DB" \
    RUMPELMC_SERVER_VIEW_DISTANCE=16 \
    RUMPELMC_SERVER_BOOTSTRAP_RADIUS=full \
    RUMPELMC_SERVER_CHUNKS_PER_UPDATE=256 \
    RUMPELMC_SERVER_CLIENT_WRITE_TIMEOUT_MS="$WRITE_TIMEOUT_MS" \
    "$SERVER_BINARY" > "$SERVER_LOG" 2>&1
) &
SERVER_PID="$!"

wait_for_server

set +e
(
  cd "$SERVER_DIR"
  go run ./cmd/slow_reader_smoke -addr "$SMOKE_ADDR" -timeout 5s -slow-lead 250ms -post-fast-wait 750ms -fast-clients "$FAST_CLIENTS"
) > "$CLIENT_LOG" 2>&1
rc=$?
set -e

if [ "$rc" -ne 0 ]; then
  cat "$CLIENT_LOG" >&2 || true
  cat "$SERVER_LOG" >&2 || true
  fail "slow-reader smoke failed with exit code $rc"
fi

summary="$(grep '^server_slow_reader_smoke status=pass ' "$CLIENT_LOG" | tail -n 1 || true)"
if [ -z "$summary" ]; then
  cat "$CLIENT_LOG" >&2 || true
  fail "missing passing slow-reader smoke summary"
fi

if ! wait_for_slow_timeout_log; then
  cat "$CLIENT_LOG" >&2 || true
  cat "$SERVER_LOG" >&2 || true
  fail "missing slow-reader write timeout evidence in server log"
fi

printf '%s slow_timeout_observed=1 slow_timeout_class=timeout write_timeout_ms=%s server_log=%s client_log=%s\n' "$summary" "$WRITE_TIMEOUT_MS" "$SERVER_LOG" "$CLIENT_LOG" > "$SUMMARY_PATH"
cat "$SUMMARY_PATH"
