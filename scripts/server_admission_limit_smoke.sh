#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/server_admission_limit_smoke"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

SERVER_DIR="$ROOT_DIR/server"
SERVER_BINARY="$SERVER_DIR/server"
SMOKE_PORT="${RUMPELMC_SERVER_ADMISSION_LIMIT_SMOKE_PORT:-25569}"
SMOKE_ADDR="127.0.0.1:$SMOKE_PORT"
SMOKE_DB="$OUT_DIR/rocksdb"
SERVER_LOG="$OUT_DIR/server.log"
CLIENT_LOG="$OUT_DIR/client.log"
SUMMARY_PATH="$OUT_DIR/server-admission-limit-smoke-summary.txt"
BUILD_SERVER="${RUMPELMC_SERVER_ADMISSION_LIMIT_SMOKE_BUILD_SERVER:-1}"
MAX_CLIENTS="${RUMPELMC_SERVER_ADMISSION_LIMIT_SMOKE_MAX_CLIENTS:-1}"
SERVER_PID=""

mkdir -p "$OUT_DIR"

fail() {
  echo "server_admission_limit_smoke: $*" >&2
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

wait_for_rejection_log() {
  tries=0
  while [ "$tries" -lt 30 ]; do
    if grep -Eq 'admission_result=rejected .*active_clients=1 max_clients=1' "$SERVER_LOG" 2>/dev/null; then
      return 0
    fi
    tries=$((tries + 1))
    sleep 0.25
  done
  return 1
}

listener="$(listener_pid || true)"
if [ -n "$listener" ]; then
  fail "port $SMOKE_PORT is already in use; choose another RUMPELMC_SERVER_ADMISSION_LIMIT_SMOKE_PORT"
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
    fail "unsupported RUMPELMC_SERVER_ADMISSION_LIMIT_SMOKE_BUILD_SERVER=$BUILD_SERVER"
    ;;
esac

rm -f "$SERVER_LOG" "$CLIENT_LOG" "$SUMMARY_PATH"
rm -rf "$SMOKE_DB"

(
  cd "$SERVER_DIR"
  exec env RUMPELMC_SERVER_CHUNK_ENCODING=rle \
    RUMPELMC_SERVER_ADDRESS=":$SMOKE_PORT" \
    RUMPELMC_SERVER_ROCKSDB_PATH="$SMOKE_DB" \
    RUMPELMC_SERVER_BOOTSTRAP_RADIUS=0 \
    RUMPELMC_SERVER_CHUNKS_PER_UPDATE=64 \
    RUMPELMC_SERVER_CLIENT_WRITE_TIMEOUT_MS=2000 \
    RUMPELMC_SERVER_MAX_CLIENTS="$MAX_CLIENTS" \
    "$SERVER_BINARY" > "$SERVER_LOG" 2>&1
) &
SERVER_PID="$!"

wait_for_server

set +e
(
  cd "$SERVER_DIR"
  go run ./cmd/admission_limit_smoke -addr "$SMOKE_ADDR" -timeout 3s
) > "$CLIENT_LOG" 2>&1
rc=$?
set -e

if [ "$rc" -ne 0 ]; then
  cat "$CLIENT_LOG" >&2 || true
  cat "$SERVER_LOG" >&2 || true
  fail "admission-limit smoke failed with exit code $rc"
fi

summary="$(grep '^server_admission_limit_smoke status=pass ' "$CLIENT_LOG" | tail -n 1 || true)"
if [ -z "$summary" ]; then
  cat "$CLIENT_LOG" >&2 || true
  fail "missing passing admission-limit smoke summary"
fi

if ! wait_for_rejection_log; then
  cat "$CLIENT_LOG" >&2 || true
  cat "$SERVER_LOG" >&2 || true
  fail "missing admission rejection evidence in server log"
fi

printf '%s admission_rejection_log=1 server_log=%s client_log=%s\n' "$summary" "$SERVER_LOG" "$CLIENT_LOG" > "$SUMMARY_PATH"
cat "$SUMMARY_PATH"
