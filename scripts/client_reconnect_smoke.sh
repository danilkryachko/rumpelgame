#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/client_reconnect_smoke"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

GODOT_BIN="${GODOT_BIN:-/opt/homebrew/bin/godot}"
TIMEOUT_BIN="${TIMEOUT_BIN:-/opt/homebrew/bin/timeout}"
GODOT_TIMEOUT_SEC="${GODOT_TIMEOUT_SEC:-90}"
GODOT_QUIT_AFTER_FRAMES="${GODOT_QUIT_AFTER_FRAMES:-30000}"
SMOKE_DELAY_SEC="${RUMPELMC_CLIENT_RECONNECT_SMOKE_DELAY_SEC:-7.0}"
SERVER_KILL_AFTER_SEC="${RUMPELMC_CLIENT_RECONNECT_SMOKE_KILL_AFTER_SEC:-2.0}"
SERVER_RESTART_AFTER_SEC="${RUMPELMC_CLIENT_RECONNECT_SMOKE_RESTART_AFTER_SEC:-1.0}"
RECONNECT_CYCLES="${RUMPELMC_CLIENT_RECONNECT_SMOKE_CYCLES:-1}"
SERVER_DIR="$ROOT_DIR/server"
SERVER_BINARY="$SERVER_DIR/server"
SMOKE_PORT=25565
SMOKE_DB="$OUT_DIR/rocksdb"
INITIAL_SERVER_LOG="$OUT_DIR/server-initial.log"
RESTART_SERVER_LOG="$OUT_DIR/server-restart-1.log"
GODOT_LOG="$OUT_DIR/godot.log"
SUMMARY_PATH="$OUT_DIR/client-reconnect-smoke-summary.txt"
SERVER_PID=""
GODOT_PID=""
RESTART_SERVER_LOGS=""

mkdir -p "$OUT_DIR"

. "$ROOT_DIR/scripts/godot_rust_ext_profile.sh"

fail() {
  echo "client_reconnect_smoke: $*" >&2
  exit 1
}

metric() {
  key="$1"
  marker_path="$2"
  sed -n "s/.*$key=\([0-9][0-9]*\).*/\1/p" "$marker_path" | sed -n '1p'
}

text_metric() {
  key="$1"
  marker_path="$2"
  sed -n "s/.*$key=\([^ ]*\).*/\1/p" "$marker_path" | sed -n '1p'
}

require_metric_ge() {
  marker_path="$1"
  key="$2"
  min_value="$3"
  value="$(metric "$key" "$marker_path")"
  test -n "$value" || fail "missing $key in $marker_path"
  if [ "$value" -lt "$min_value" ]; then
    fail "$key=$value is below $min_value in $marker_path"
  fi
}

require_text_metric_eq() {
  marker_path="$1"
  key="$2"
  expected="$3"
  value="$(text_metric "$key" "$marker_path")"
  test -n "$value" || fail "missing $key in $marker_path"
  if [ "$value" != "$expected" ]; then
    fail "$key=$value, expected $expected in $marker_path"
  fi
}

require_positive_int() {
  name="$1"
  value="$2"
  case "$value" in
    ''|*[!0-9]*)
      fail "$name must be a positive integer, got $value"
      ;;
  esac
  if [ "$value" -lt 1 ]; then
    fail "$name must be >= 1, got $value"
  fi
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

cleanup_godot() {
  if [ -n "$GODOT_PID" ] && kill -0 "$GODOT_PID" 2>/dev/null; then
    kill "$GODOT_PID" 2>/dev/null || true
    wait "$GODOT_PID" 2>/dev/null || true
    GODOT_PID=""
  fi
}

cleanup_all() {
  cleanup_godot
  cleanup_server
}

start_server() {
  log_path="$1"
  rm -f "$log_path"
  (
    cd "$SERVER_DIR"
    exec env RUMPELMC_SERVER_CHUNK_ENCODING=rle \
      RUMPELMC_SERVER_ADDRESS=":$SMOKE_PORT" \
      RUMPELMC_SERVER_ROCKSDB_PATH="$SMOKE_DB" \
      RUMPELMC_SERVER_BOOTSTRAP_RADIUS=0 \
      RUMPELMC_SERVER_CHUNKS_PER_UPDATE=64 \
      "$SERVER_BINARY" > "$log_path" 2>&1
  ) &
  SERVER_PID="$!"
  wait_for_server "$log_path"
}

listener="$(listener_pid || true)"
if [ -n "$listener" ]; then
  fail "port $SMOKE_PORT is already in use; stop the existing server before reconnect smoke"
fi
require_positive_int RUMPELMC_CLIENT_RECONNECT_SMOKE_CYCLES "$RECONNECT_CYCLES"
trap cleanup_all EXIT HUP INT TERM

(
  cd "$SERVER_DIR"
  go build -o ./server ./cmd/server
  sign_server_binary_if_possible
)

rm -f "$INITIAL_SERVER_LOG" "$OUT_DIR"/server-restart-*.log "$GODOT_LOG" "$SUMMARY_PATH"
rm -rf "$SMOKE_DB"

start_server "$INITIAL_SERVER_LOG"

prepare_godot_rust_ext_profile "$ROOT_DIR"
trap 'cleanup_all; restore_godot_rust_ext_profile' EXIT HUP INT TERM

screenshot_path="$OUT_DIR/client-reconnect-smoke.png"
marker_path="$screenshot_path.txt"
rm -f "$screenshot_path" "$marker_path"

(
  cd "$ROOT_DIR"
  "$TIMEOUT_BIN" "$GODOT_TIMEOUT_SEC" /usr/bin/env \
    RUMPELMC_GPU_TERRAIN_RENDER=1 \
    RUMPELMC_VISUAL_SMOKE_PATH="$screenshot_path" \
    RUMPELMC_VISUAL_SMOKE_DELAY_SEC="$SMOKE_DELAY_SEC" \
    RUMPELMC_VISUAL_SMOKE_FRAME_SAMPLE_SEC=1.0 \
    RUMPELMC_VISUAL_SMOKE_FORCE_UNCAPPED=0 \
    RUMPELMC_VISUAL_SMOKE_HIDE_HUD=1 \
    RUMPELMC_VISUAL_SMOKE_DISABLE_PLAYER_INPUT=1 \
    "$GODOT_BIN" --disable-vsync --max-fps 0 --path client --quit-after "$GODOT_QUIT_AFTER_FRAMES"
) > "$GODOT_LOG" 2>&1 &
GODOT_PID="$!"

cycle=1
while [ "$cycle" -le "$RECONNECT_CYCLES" ]; do
  sleep "$SERVER_KILL_AFTER_SEC"
  cleanup_server
  sleep "$SERVER_RESTART_AFTER_SEC"
  restart_log="$OUT_DIR/server-restart-$cycle.log"
  start_server "$restart_log"
  if [ -z "$RESTART_SERVER_LOGS" ]; then
    RESTART_SERVER_LOGS="$restart_log"
  else
    RESTART_SERVER_LOGS="$RESTART_SERVER_LOGS,$restart_log"
  fi
  cycle=$((cycle + 1))
done

set +e
wait "$GODOT_PID"
godot_rc=$?
GODOT_PID=""
set -e
if [ "$godot_rc" -ne 0 ]; then
  cat "$GODOT_LOG" >&2 || true
  fail "Godot reconnect smoke failed with exit code $godot_rc"
fi

test -s "$screenshot_path" || fail "missing screenshot $screenshot_path"
test -s "$marker_path" || fail "missing marker $marker_path"
grep -q "Visual smoke screenshot saved" "$marker_path" || fail "missing visual smoke summary in $marker_path"
require_godot_rust_ext_marker_profile "$marker_path"
require_text_metric_eq "$marker_path" client_state active
require_metric_ge "$marker_path" lifecycle_transitions 4
require_metric_ge "$marker_path" reconnect_events 1
require_metric_ge "$marker_path" reconnect_attempts 1
require_metric_ge "$marker_path" reconnect_successes "$RECONNECT_CYCLES"
require_metric_ge "$marker_path" network_reader_errors "$RECONNECT_CYCLES"
require_metric_ge "$marker_path" current_chunk_loaded 1
last_network_error="$(text_metric last_network_error "$marker_path")"
test -n "$last_network_error" || fail "missing last_network_error in $marker_path"

{
  printf 'client_reconnect_smoke status=pass client_state=active reconnect_cycles=%s lifecycle_transitions=%s reconnect_events=%s reconnect_attempts=%s reconnect_successes=%s network_reader_errors=%s current_chunk_loaded=%s last_network_error=%s active_protocol_change=0 initial_server_log=%s restart_server_log=%s restart_server_logs=%s godot_log=%s marker=%s\n' \
    "$RECONNECT_CYCLES" \
    "$(metric lifecycle_transitions "$marker_path")" \
    "$(metric reconnect_events "$marker_path")" \
    "$(metric reconnect_attempts "$marker_path")" \
    "$(metric reconnect_successes "$marker_path")" \
    "$(metric network_reader_errors "$marker_path")" \
    "$(metric current_chunk_loaded "$marker_path")" \
    "$last_network_error" \
    "$INITIAL_SERVER_LOG" \
    "$RESTART_SERVER_LOG" \
    "$RESTART_SERVER_LOGS" \
    "$GODOT_LOG" \
    "$marker_path"
} > "$SUMMARY_PATH"

cat "$SUMMARY_PATH"
