#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/block_edit_persisted_visual_smoke"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

GODOT_BIN="${GODOT_BIN:-/opt/homebrew/bin/godot}"
TIMEOUT_BIN="${TIMEOUT_BIN:-/opt/homebrew/bin/timeout}"
GODOT_TIMEOUT_SEC="${GODOT_TIMEOUT_SEC:-120}"
GODOT_QUIT_AFTER_FRAMES="${GODOT_QUIT_AFTER_FRAMES:-30000}"
SMOKE_DELAY_SEC="${RUMPELMC_BLOCK_EDIT_PERSISTED_VISUAL_DELAY_SEC:-7.0}"
FRAME_SAMPLE_SEC="${RUMPELMC_BLOCK_EDIT_PERSISTED_VISUAL_FRAME_SAMPLE_SEC:-1.0}"
SERVER_DIR="$ROOT_DIR/server"
SERVER_BINARY="$SERVER_DIR/server"
SMOKE_BINARY="$OUT_DIR/persisted_reload_smoke"
SMOKE_PORT=25565
SMOKE_ADDR="127.0.0.1:$SMOKE_PORT"
SUMMARY_PATH="$OUT_DIR/block-edit-persisted-visual-smoke-summary.txt"
BUILD_SERVER="${RUMPELMC_BLOCK_EDIT_PERSISTED_VISUAL_BUILD_SERVER:-1}"
SCENARIOS="${RUMPELMC_BLOCK_EDIT_PERSISTED_VISUAL_SCENARIOS:-place_reload destroy_after_reload edge_place}"
DEFAULT_EDIT_X="${RUMPELMC_BLOCK_EDIT_PERSISTED_VISUAL_X:-1}"
DEFAULT_EDIT_Y="${RUMPELMC_BLOCK_EDIT_PERSISTED_VISUAL_Y:-64}"
DEFAULT_EDIT_Z="${RUMPELMC_BLOCK_EDIT_PERSISTED_VISUAL_Z:-1}"
DEFAULT_EDIT_BLOCK_ID="${RUMPELMC_BLOCK_EDIT_PERSISTED_VISUAL_BLOCK_ID:-4}"
DEFAULT_EXPECTED_CHUNK="${RUMPELMC_BLOCK_EDIT_PERSISTED_VISUAL_EXPECTED_CHUNK:-0,0}"
EDGE_EDIT_X="${RUMPELMC_BLOCK_EDIT_PERSISTED_VISUAL_EDGE_X:-31}"
EDGE_EDIT_Y="${RUMPELMC_BLOCK_EDIT_PERSISTED_VISUAL_EDGE_Y:-64}"
EDGE_EDIT_Z="${RUMPELMC_BLOCK_EDIT_PERSISTED_VISUAL_EDGE_Z:-31}"
EDGE_EDIT_BLOCK_ID="${RUMPELMC_BLOCK_EDIT_PERSISTED_VISUAL_EDGE_BLOCK_ID:-4}"
EDGE_EXPECTED_CHUNK="${RUMPELMC_BLOCK_EDIT_PERSISTED_VISUAL_EDGE_EXPECTED_CHUNK:-0,0}"
SMOKE_DB=""
GODOT_LOG=""
SCREENSHOT_PATH=""
MARKER_PATH=""
EDIT_X=""
EDIT_Y=""
EDIT_Z=""
EDIT_BLOCK_ID=""
EXPECTED_CURRENT_CHUNK=""
SERVER_PID=""
CASE_SUMMARIES=""
CASE_COUNT=0
PLACE_RELOAD_STATUS="deferred"
DESTROY_AFTER_RELOAD_STATUS="deferred"
EDGE_PLACE_STATUS="deferred"

mkdir -p "$OUT_DIR"

. "$ROOT_DIR/scripts/godot_rust_ext_profile.sh"

fail() {
  echo "block_edit_persisted_visual_smoke: $*" >&2
  exit 1
}

metric() {
  key="$1"
  marker_path="$2"
  sed -n "s/.*$key=\([0-9][0-9]*\).*/\1/p" "$marker_path" | sed -n '1p'
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

require_metric_eq() {
  marker_path="$1"
  key="$2"
  expected="$3"
  value="$(metric "$key" "$marker_path")"
  test -n "$value" || fail "missing $key in $marker_path"
  if [ "$value" -ne "$expected" ]; then
    fail "$key=$value, expected $expected in $marker_path"
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

cleanup_all() {
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

run_godot_visual_smoke() {
  rm -f "$SCREENSHOT_PATH" "$MARKER_PATH" "$GODOT_LOG"
  set +e
  (
    cd "$ROOT_DIR"
    "$TIMEOUT_BIN" "$GODOT_TIMEOUT_SEC" /usr/bin/env \
      RUMPELMC_GPU_TERRAIN_RENDER=1 \
      RUMPELMC_VISUAL_SMOKE_POSE="${RUMPELMC_BLOCK_EDIT_PERSISTED_VISUAL_POSE:-}" \
      RUMPELMC_VISUAL_SMOKE_MOTION=none \
      RUMPELMC_VISUAL_SMOKE_PATH="$SCREENSHOT_PATH" \
      RUMPELMC_VISUAL_SMOKE_DELAY_SEC="$SMOKE_DELAY_SEC" \
      RUMPELMC_VISUAL_SMOKE_FRAME_SAMPLE_SEC="$FRAME_SAMPLE_SEC" \
      RUMPELMC_VISUAL_SMOKE_FORCE_UNCAPPED=0 \
      RUMPELMC_VISUAL_SMOKE_HIDE_HUD=1 \
      RUMPELMC_VISUAL_SMOKE_DISABLE_PLAYER_INPUT=1 \
      "$GODOT_BIN" --disable-vsync --max-fps 0 --path client --quit-after "$GODOT_QUIT_AFTER_FRAMES"
  ) > "$GODOT_LOG" 2>&1
  godot_rc=$?
  set -e
  if [ "$godot_rc" -ne 0 ]; then
    cat "$GODOT_LOG" >&2 || true
    fail "Godot persisted visual smoke failed with exit code $godot_rc"
  fi
}

validate_visual_marker() {
  test -s "$SCREENSHOT_PATH" || fail "missing screenshot $SCREENSHOT_PATH"
  test -s "$MARKER_PATH" || fail "missing marker $MARKER_PATH"
  grep -q "Visual smoke screenshot saved" "$MARKER_PATH" || fail "missing visual smoke summary in $MARKER_PATH"
  grep -q "motion=\"none\"" "$MARKER_PATH" || fail "unexpected motion in $MARKER_PATH"
  grep -q "current_chunk=\"$EXPECTED_CURRENT_CHUNK\"" "$MARKER_PATH" || fail "visual smoke did not load expected chunk $EXPECTED_CURRENT_CHUNK"
  grep -q "smoke_err=0" "$MARKER_PATH" || fail "smoke_err is not 0 in $MARKER_PATH"
  require_godot_rust_ext_marker_profile "$MARKER_PATH"
  grep -q "block_edit=\"none\"" "$MARKER_PATH" || fail "unexpected block edit action in $MARKER_PATH"
  require_metric_ge "$MARKER_PATH" current_chunk_loaded 1
  require_metric_ge "$MARKER_PATH" current_chunk_submeshes 1
  require_metric_ge "$MARKER_PATH" current_chunk_collision 1
  require_metric_ge "$MARKER_PATH" terrain_samples 1
  require_metric_ge "$MARKER_PATH" gpu_frames 1
  require_metric_ge "$MARKER_PATH" gpu_uploads 1
  require_metric_eq "$MARKER_PATH" gpu_upload_fail 0
  require_metric_eq "$MARKER_PATH" gpu_upload_fail_capacity 0
  require_metric_eq "$MARKER_PATH" gpu_upload_fail_fragmented 0
}

configure_case() {
  case_name="$1"
  edit_x="$2"
  edit_y="$3"
  edit_z="$4"
  edit_block_id="$5"
  expected_chunk="$6"

  EDIT_X="$edit_x"
  EDIT_Y="$edit_y"
  EDIT_Z="$edit_z"
  EDIT_BLOCK_ID="$edit_block_id"
  EXPECTED_CURRENT_CHUNK="$expected_chunk"
  SMOKE_DB="$OUT_DIR/rocksdb-$case_name"
  GODOT_LOG="$OUT_DIR/godot-$case_name.log"
  SCREENSHOT_PATH="$OUT_DIR/block-edit-persisted-visual-$case_name.png"
  MARKER_PATH="$SCREENSHOT_PATH.txt"
}

append_case_summary() {
  line="$1"
  if [ -z "$CASE_SUMMARIES" ]; then
    CASE_SUMMARIES="$line"
  else
    CASE_SUMMARIES="$CASE_SUMMARIES
$line"
  fi
  CASE_COUNT=$((CASE_COUNT + 1))
}

visual_case_metrics() {
  printf 'current_chunk_loaded=%s current_chunk_submeshes=%s current_chunk_collision=%s terrain_samples=%s gpu_frames=%s gpu_uploads=%s gpu_upload_fail=%s screenshot=%s marker=%s godot_log=%s' \
    "$(metric current_chunk_loaded "$MARKER_PATH")" \
    "$(metric current_chunk_submeshes "$MARKER_PATH")" \
    "$(metric current_chunk_collision "$MARKER_PATH")" \
    "$(metric terrain_samples "$MARKER_PATH")" \
    "$(metric gpu_frames "$MARKER_PATH")" \
    "$(metric gpu_uploads "$MARKER_PATH")" \
    "$(metric gpu_upload_fail "$MARKER_PATH")" \
    "$SCREENSHOT_PATH" \
    "$MARKER_PATH" \
    "$GODOT_LOG"
}

run_place_reload_visual_case() {
  case_name="$1"
  edit_x="$2"
  edit_y="$3"
  edit_z="$4"
  edit_block_id="$5"
  expected_chunk="$6"
  configure_case "$case_name" "$edit_x" "$edit_y" "$edit_z" "$edit_block_id" "$expected_chunk"

  rm -f "$OUT_DIR"/client-"$case_name"-*.log "$OUT_DIR"/server-"$case_name"-*.log
  rm -rf "$SMOKE_DB"

  place_server_log="$OUT_DIR/server-$case_name-place.log"
  verify_server_log="$OUT_DIR/server-$case_name-verify-place.log"
  start_server "$place_server_log"
  place_summary="$(run_phase "$case_name-place" -action place -want-before 0 -block-id "$EDIT_BLOCK_ID")"
  cleanup_server

  start_server "$verify_server_log"
  verify_place_summary="$(run_phase "$case_name-verify-place" -action expect -want-block "$EDIT_BLOCK_ID" -block-id "$EDIT_BLOCK_ID")"
  run_godot_visual_smoke
  validate_visual_marker
  cleanup_server

  case "$case_name" in
    place_reload) PLACE_RELOAD_STATUS="pass" ;;
    edge_place) EDGE_PLACE_STATUS="pass" ;;
  esac

  append_case_summary "$(printf 'scenario_%s status=pass kind=place_reload block_x=%s block_y=%s block_z=%s block_id=%s expected_chunk=%s %s place_server_log=%s verify_server_log=%s phase_place=\"%s\" phase_verify_place=\"%s\"' \
    "$case_name" \
    "$EDIT_X" \
    "$EDIT_Y" \
    "$EDIT_Z" \
    "$EDIT_BLOCK_ID" \
    "$EXPECTED_CURRENT_CHUNK" \
    "$(visual_case_metrics)" \
    "$place_server_log" \
    "$verify_server_log" \
    "$place_summary" \
    "$verify_place_summary")"
}

run_destroy_after_reload_visual_case() {
  case_name="destroy_after_reload"
  configure_case "$case_name" "$DEFAULT_EDIT_X" "$DEFAULT_EDIT_Y" "$DEFAULT_EDIT_Z" "$DEFAULT_EDIT_BLOCK_ID" "$DEFAULT_EXPECTED_CHUNK"

  rm -f "$OUT_DIR"/client-"$case_name"-*.log "$OUT_DIR"/server-"$case_name"-*.log
  rm -rf "$SMOKE_DB"

  place_server_log="$OUT_DIR/server-$case_name-place.log"
  destroy_server_log="$OUT_DIR/server-$case_name-destroy.log"
  verify_destroy_server_log="$OUT_DIR/server-$case_name-verify-destroy.log"

  start_server "$place_server_log"
  place_summary="$(run_phase "$case_name-place" -action place -want-before 0 -block-id "$EDIT_BLOCK_ID")"
  cleanup_server

  start_server "$destroy_server_log"
  verify_before_destroy_summary="$(run_phase "$case_name-verify-before-destroy" -action expect -want-block "$EDIT_BLOCK_ID" -block-id "$EDIT_BLOCK_ID")"
  destroy_summary="$(run_phase "$case_name-destroy" -action destroy -want-before "$EDIT_BLOCK_ID" -block-id "$EDIT_BLOCK_ID")"
  cleanup_server

  start_server "$verify_destroy_server_log"
  verify_destroy_summary="$(run_phase "$case_name-verify-destroy" -action expect -want-block 0 -block-id "$EDIT_BLOCK_ID")"
  run_godot_visual_smoke
  validate_visual_marker
  cleanup_server

  DESTROY_AFTER_RELOAD_STATUS="pass"
  append_case_summary "$(printf 'scenario_%s status=pass kind=destroy_after_reload block_x=%s block_y=%s block_z=%s block_id=%s final_block_id=0 expected_chunk=%s %s place_server_log=%s destroy_server_log=%s verify_destroy_server_log=%s phase_place=\"%s\" phase_verify_before_destroy=\"%s\" phase_destroy=\"%s\" phase_verify_destroy=\"%s\"' \
    "$case_name" \
    "$EDIT_X" \
    "$EDIT_Y" \
    "$EDIT_Z" \
    "$EDIT_BLOCK_ID" \
    "$EXPECTED_CURRENT_CHUNK" \
    "$(visual_case_metrics)" \
    "$place_server_log" \
    "$destroy_server_log" \
    "$verify_destroy_server_log" \
    "$place_summary" \
    "$verify_before_destroy_summary" \
    "$destroy_summary" \
    "$verify_destroy_summary")"
}

listener="$(listener_pid || true)"
if [ -n "$listener" ]; then
  fail "port $SMOKE_PORT is already in use; stop the existing server before persisted visual smoke"
fi
trap 'cleanup_all; restore_godot_rust_ext_profile' EXIT HUP INT TERM

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
    fail "unsupported RUMPELMC_BLOCK_EDIT_PERSISTED_VISUAL_BUILD_SERVER=$BUILD_SERVER"
    ;;
esac

(
  cd "$SERVER_DIR"
  go build -o "$SMOKE_BINARY" ./cmd/persisted_reload_smoke
)

prepare_godot_rust_ext_profile "$ROOT_DIR"

rm -f "$SUMMARY_PATH" "$OUT_DIR"/client-*.log "$OUT_DIR"/server-*.log "$OUT_DIR"/godot-*.log "$OUT_DIR"/block-edit-persisted-visual-*.png "$OUT_DIR"/block-edit-persisted-visual-*.png.txt

for scenario in $SCENARIOS; do
  case "$scenario" in
    place_reload)
      run_place_reload_visual_case "$scenario" "$DEFAULT_EDIT_X" "$DEFAULT_EDIT_Y" "$DEFAULT_EDIT_Z" "$DEFAULT_EDIT_BLOCK_ID" "$DEFAULT_EXPECTED_CHUNK"
      ;;
    destroy_after_reload)
      run_destroy_after_reload_visual_case
      ;;
    edge_place)
      run_place_reload_visual_case "$scenario" "$EDGE_EDIT_X" "$EDGE_EDIT_Y" "$EDGE_EDIT_Z" "$EDGE_EDIT_BLOCK_ID" "$EDGE_EXPECTED_CHUNK"
      ;;
    *)
      fail "unsupported RUMPELMC_BLOCK_EDIT_PERSISTED_VISUAL_SCENARIOS entry: $scenario"
      ;;
  esac
done

if [ "$CASE_COUNT" -lt 1 ]; then
  fail "no persisted visual smoke scenarios ran"
fi

{
  printf 'block_edit_persisted_visual_smoke status=pass scenarios=%s place_reload_status=%s destroy_after_reload_status=%s edge_place_status=%s visual_status=pass visual_collision_gpu_path=godot_persisted_reload_guarded protocol_change=0 scenario_list="%s"\n' \
    "$CASE_COUNT" \
    "$PLACE_RELOAD_STATUS" \
    "$DESTROY_AFTER_RELOAD_STATUS" \
    "$EDGE_PLACE_STATUS" \
    "$SCENARIOS"
  printf '%s\n' "$CASE_SUMMARIES"
} > "$SUMMARY_PATH"

cat "$SUMMARY_PATH"
