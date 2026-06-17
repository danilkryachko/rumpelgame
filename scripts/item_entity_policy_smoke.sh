#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/item_entity_policy"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

SERVER_DIR="$ROOT_DIR/server"
SERVER_BINARY="$SERVER_DIR/server"
SMOKE_BINARY="$OUT_DIR/player_inventory_reconnect_smoke"
SMOKE_PORT="${RUMPELMC_ITEM_ENTITY_POLICY_SMOKE_PORT:-25573}"
SMOKE_ADDR="127.0.0.1:$SMOKE_PORT"
MERGE_DB="$OUT_DIR/merge-rocksdb"
DESPAWN_DB="$OUT_DIR/despawn-rocksdb"
SUMMARY_PATH="$OUT_DIR/item-entity-policy-summary.txt"
BUILD_SERVER="${RUMPELMC_ITEM_ENTITY_POLICY_SMOKE_BUILD_SERVER:-1}"
PLAYER_ID="${RUMPELMC_ITEM_ENTITY_POLICY_SMOKE_PLAYER_ID:-item_entity_policy_player}"
SELECTED_SLOT="${RUMPELMC_ITEM_ENTITY_POLICY_SMOKE_SLOT:-0}"
POSITION_Y="${RUMPELMC_ITEM_ENTITY_POLICY_SMOKE_POSITION_Y:-65.5}"
FIRST_BLOCK_X="${RUMPELMC_ITEM_ENTITY_POLICY_SMOKE_FIRST_BLOCK_X:-1}"
FIRST_BLOCK_Y="${RUMPELMC_ITEM_ENTITY_POLICY_SMOKE_FIRST_BLOCK_Y:-60}"
FIRST_BLOCK_Z="${RUMPELMC_ITEM_ENTITY_POLICY_SMOKE_FIRST_BLOCK_Z:-1}"
SECOND_BLOCK_X="${RUMPELMC_ITEM_ENTITY_POLICY_SMOKE_SECOND_BLOCK_X:-2}"
SECOND_BLOCK_Y="${RUMPELMC_ITEM_ENTITY_POLICY_SMOKE_SECOND_BLOCK_Y:-60}"
SECOND_BLOCK_Z="${RUMPELMC_ITEM_ENTITY_POLICY_SMOKE_SECOND_BLOCK_Z:-1}"
MERGE_DESPAWN_MS="${RUMPELMC_ITEM_ENTITY_POLICY_MERGE_DESPAWN_MS:-300000}"
DESPAWN_MS="${RUMPELMC_ITEM_ENTITY_POLICY_DESPAWN_MS:-100}"
SERVER_PID=""

mkdir -p "$OUT_DIR"

fail() {
  echo "item_entity_policy_smoke: $*" >&2
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
  db_path="$2"
  despawn_ms="$3"
  log_path="$OUT_DIR/server-$label.log"
  rm -f "$log_path"
  (
    cd "$SERVER_DIR"
    exec env RUMPELMC_SERVER_CHUNK_ENCODING=rle \
      RUMPELMC_SERVER_ADDRESS="$SMOKE_ADDR" \
      RUMPELMC_SERVER_ROCKSDB_PATH="$db_path" \
      RUMPELMC_SERVER_INVENTORY_MODE=counted \
      RUMPELMC_SERVER_MINING_COOLDOWN_MS=0 \
      RUMPELMC_SERVER_ITEM_ENTITY_DESPAWN_MS="$despawn_ms" \
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
  fail "port $SMOKE_PORT is already in use; choose another RUMPELMC_ITEM_ENTITY_POLICY_SMOKE_PORT"
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
    fail "unsupported RUMPELMC_ITEM_ENTITY_POLICY_SMOKE_BUILD_SERVER=$BUILD_SERVER"
    ;;
esac

(
  cd "$SERVER_DIR"
  go build -o "$SMOKE_BINARY" ./cmd/player_inventory_reconnect_smoke
)

rm -f "$SUMMARY_PATH"
rm -rf "$MERGE_DB" "$DESPAWN_DB"

start_server "merge" "$MERGE_DB" "$MERGE_DESPAWN_MS"
merge_summary="$(run_phase merge -action destroy-merge-expect -position-y "$POSITION_Y" -block-x "$FIRST_BLOCK_X" -block-y "$FIRST_BLOCK_Y" -block-z "$FIRST_BLOCK_Z" -second-block-x "$SECOND_BLOCK_X" -second-block-y "$SECOND_BLOCK_Y" -second-block-z "$SECOND_BLOCK_Z" -expect-entity-count 1 -expect-item-count 2)"
cleanup_server

start_server "despawn-spawn" "$DESPAWN_DB" "$DESPAWN_MS"
despawn_spawn_summary="$(run_phase despawn-spawn -action destroy-drop-expect -position-y "$POSITION_Y" -block-x "$FIRST_BLOCK_X" -block-y "$FIRST_BLOCK_Y" -block-z "$FIRST_BLOCK_Z")"
cleanup_server

sleep 1

start_server "despawn-verify" "$DESPAWN_DB" "$DESPAWN_MS"
despawn_absent_summary="$(run_phase despawn-verify -action item-absent-expect -position-y "$POSITION_Y")"
cleanup_server

{
  printf 'item_entity_policy_smoke status=pass item_entity_policy=merge_despawn_guarded dropped_stack_merge=live_server_guarded despawn_restart=live_server_guarded phases=3 merge_status=pass despawn_spawn_status=pass despawn_absent_status=pass expected_merged_count=2 despawn_ms=%s server_restarts=1 protocol_change=0 merge_db_path=%s despawn_db_path=%s\n' \
    "$DESPAWN_MS" "$MERGE_DB" "$DESPAWN_DB"
  printf 'phase_merge %s\n' "$merge_summary"
  printf 'phase_despawn_spawn %s\n' "$despawn_spawn_summary"
  printf 'phase_despawn_absent %s\n' "$despawn_absent_summary"
} > "$SUMMARY_PATH"

cat "$SUMMARY_PATH"
