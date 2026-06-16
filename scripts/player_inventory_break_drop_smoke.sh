#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/player_inventory_break_drop_smoke"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

SERVER_DIR="$ROOT_DIR/server"
SERVER_BINARY="$SERVER_DIR/server"
SMOKE_BINARY="$OUT_DIR/player_inventory_reconnect_smoke"
SMOKE_PORT="${RUMPELMC_PLAYER_INVENTORY_BREAK_DROP_SMOKE_PORT:-25571}"
SMOKE_ADDR="127.0.0.1:$SMOKE_PORT"
SMOKE_DB="$OUT_DIR/rocksdb"
SUMMARY_PATH="$OUT_DIR/player-inventory-break-drop-smoke-summary.txt"
BUILD_SERVER="${RUMPELMC_PLAYER_INVENTORY_BREAK_DROP_SMOKE_BUILD_SERVER:-1}"
PLAYER_ID="${RUMPELMC_PLAYER_INVENTORY_BREAK_DROP_SMOKE_PLAYER_ID:-break_drop_player}"
SELECTED_SLOT="${RUMPELMC_PLAYER_INVENTORY_BREAK_DROP_SMOKE_SLOT:-0}"
DESTROYED_BLOCK_ID="${RUMPELMC_PLAYER_INVENTORY_BREAK_DROP_SMOKE_BLOCK_ID:-1}"
EXPECTED_COUNT="${RUMPELMC_PLAYER_INVENTORY_BREAK_DROP_SMOKE_EXPECTED_COUNT:-9}"
SERVER_PID=""

mkdir -p "$OUT_DIR"

fail() {
  echo "player_inventory_break_drop_smoke: $*" >&2
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
      RUMPELMC_SERVER_INVENTORY_MODE=counted \
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
  "$SMOKE_BINARY" -addr "$SMOKE_ADDR" -timeout 3s -player-id "$PLAYER_ID" -slot "$SELECTED_SLOT" "$@" > "$log_path" 2>&1
  rc=$?
  set -e
  if [ "$rc" -ne 0 ]; then
    cat "$log_path" >&2 || true
    fail "$label phase failed with exit code $rc"
  fi
  summary="$(grep '^player_inventory_reconnect_smoke status=pass ' "$log_path" | tail -n 1 || true)"
  if [ -z "$summary" ]; then
    cat "$log_path" >&2 || true
    fail "missing passing $label phase summary"
  fi
  printf '%s\n' "$summary"
}

listener="$(listener_pid || true)"
if [ -n "$listener" ]; then
  fail "port $SMOKE_PORT is already in use; choose another RUMPELMC_PLAYER_INVENTORY_BREAK_DROP_SMOKE_PORT"
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
    fail "unsupported RUMPELMC_PLAYER_INVENTORY_BREAK_DROP_SMOKE_BUILD_SERVER=$BUILD_SERVER"
    ;;
esac

(
  cd "$SERVER_DIR"
  go build -o "$SMOKE_BINARY" ./cmd/player_inventory_reconnect_smoke
)

rm -f "$SUMMARY_PATH"
rm -rf "$SMOKE_DB"

start_server "destroy"
destroy_summary="$(run_phase destroy -action destroy-expect -expect-count "$EXPECTED_COUNT")"
cleanup_server

start_server "verify-restart"
verify_restart_summary="$(run_phase verify-restart -action expect -expect-count "$EXPECTED_COUNT")"
cleanup_server

{
  printf 'player_inventory_break_drop_smoke status=pass break_drop_inventory=live_server_guarded phases=2 destroy_status=pass verify_restart_status=pass player_id=%s selected_slot=%s destroyed_block_id=%s expected_count=%s server_restarts=1 protocol_change=0 db_path=%s\n' \
    "$PLAYER_ID" "$SELECTED_SLOT" "$DESTROYED_BLOCK_ID" "$EXPECTED_COUNT" "$SMOKE_DB"
  printf 'phase_destroy %s\n' "$destroy_summary"
  printf 'phase_verify_restart %s\n' "$verify_restart_summary"
} > "$SUMMARY_PATH"

cat "$SUMMARY_PATH"
