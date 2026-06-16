#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/server_persisted_reload_smoke"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

SERVER_DIR="$ROOT_DIR/server"
SERVER_BINARY="$SERVER_DIR/server"
SMOKE_BINARY="$OUT_DIR/persisted_reload_smoke"
SMOKE_PORT="${RUMPELMC_SERVER_PERSISTED_RELOAD_SMOKE_PORT:-25568}"
SMOKE_ADDR="127.0.0.1:$SMOKE_PORT"
SMOKE_DB="$OUT_DIR/rocksdb"
SUMMARY_PATH="$OUT_DIR/server-persisted-reload-smoke-summary.txt"
BUILD_SERVER="${RUMPELMC_SERVER_PERSISTED_RELOAD_SMOKE_BUILD_SERVER:-1}"
EDIT_X="${RUMPELMC_SERVER_PERSISTED_RELOAD_SMOKE_X:-1}"
EDIT_Y="${RUMPELMC_SERVER_PERSISTED_RELOAD_SMOKE_Y:-64}"
EDIT_Z="${RUMPELMC_SERVER_PERSISTED_RELOAD_SMOKE_Z:-1}"
EDIT_BLOCK_ID="${RUMPELMC_SERVER_PERSISTED_RELOAD_SMOKE_BLOCK_ID:-4}"
SERVER_PID=""

mkdir -p "$OUT_DIR"

fail() {
  echo "server_persisted_reload_smoke: $*" >&2
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
  log_path="$1"
  tries=0
  while [ "$tries" -lt 30 ]; do
    pid="$(listener_pid || true)"
    if [ -n "$pid" ]; then
      return 0
    fi
    tries=$((tries + 1))
    sleep 1
  done
  cat "$log_path" >&2 || true
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
    SERVER_PID=""
    wait_for_port_clear
  fi
}

start_server() {
  label="$1"
  log_path="$OUT_DIR/server-$label.log"
  rm -f "$log_path"
  (
    cd "$SERVER_DIR"
    exec env RUMPELMC_SERVER_CHUNK_ENCODING=rle \
      RUMPELMC_SERVER_ADDRESS="$SMOKE_ADDR" \
      RUMPELMC_SERVER_ROCKSDB_PATH="$SMOKE_DB" \
      RUMPELMC_SERVER_BOOTSTRAP_RADIUS=0 \
      RUMPELMC_SERVER_CHUNKS_PER_UPDATE=64 \
      RUMPELMC_SERVER_CLIENT_WRITE_TIMEOUT_MS=2000 \
      "$SERVER_BINARY" > "$log_path" 2>&1
  ) &
  SERVER_PID="$!"
  wait_for_server "$log_path"
}

run_phase() {
  label="$1"
  shift
  log_path="$OUT_DIR/client-$label.log"
  set +e
  "$SMOKE_BINARY" -addr "$SMOKE_ADDR" -timeout 3s -x "$EDIT_X" -y "$EDIT_Y" -z "$EDIT_Z" "$@" > "$log_path" 2>&1
  rc=$?
  set -e
  if [ "$rc" -ne 0 ]; then
    cat "$log_path" >&2 || true
    fail "$label phase failed with exit code $rc"
  fi
  summary="$(grep '^server_persisted_reload_smoke status=pass ' "$log_path" | tail -n 1 || true)"
  if [ -z "$summary" ]; then
    cat "$log_path" >&2 || true
    fail "missing passing $label phase summary"
  fi
  printf '%s\n' "$summary"
}

listener="$(listener_pid || true)"
if [ -n "$listener" ]; then
  fail "port $SMOKE_PORT is already in use; choose another RUMPELMC_SERVER_PERSISTED_RELOAD_SMOKE_PORT"
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
    fail "unsupported RUMPELMC_SERVER_PERSISTED_RELOAD_SMOKE_BUILD_SERVER=$BUILD_SERVER"
    ;;
esac

(
  cd "$SERVER_DIR"
  go build -o "$SMOKE_BINARY" ./cmd/persisted_reload_smoke
)

rm -f "$SUMMARY_PATH"
rm -rf "$SMOKE_DB"

start_server "place"
place_summary="$(run_phase place -action place -want-before 0 -block-id "$EDIT_BLOCK_ID")"
cleanup_server

start_server "verify-place"
verify_place_summary="$(run_phase verify-place -action expect -want-block "$EDIT_BLOCK_ID" -block-id "$EDIT_BLOCK_ID")"
cleanup_server

start_server "destroy"
destroy_summary="$(run_phase destroy -action destroy -want-before "$EDIT_BLOCK_ID" -block-id "$EDIT_BLOCK_ID")"
cleanup_server

start_server "verify-destroy"
verify_destroy_summary="$(run_phase verify-destroy -action expect -want-block 0 -block-id "$EDIT_BLOCK_ID")"
cleanup_server

{
  printf 'server_persisted_reload_smoke status=pass phases=4 place_status=pass verify_place_status=pass destroy_status=pass verify_destroy_status=pass block_x=%s block_y=%s block_z=%s block_id=%s protocol_change=0 db_path=%s\n' \
    "$EDIT_X" "$EDIT_Y" "$EDIT_Z" "$EDIT_BLOCK_ID" "$SMOKE_DB"
  printf 'phase_place %s\n' "$place_summary"
  printf 'phase_verify_place %s\n' "$verify_place_summary"
  printf 'phase_destroy %s\n' "$destroy_summary"
  printf 'phase_verify_destroy %s\n' "$verify_destroy_summary"
} > "$SUMMARY_PATH"

cat "$SUMMARY_PATH"
