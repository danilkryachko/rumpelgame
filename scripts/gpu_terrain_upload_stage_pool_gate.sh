#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/gpu_terrain_upload_stage_pool_current"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

MOVEMENT_BASELINE_DIR="$OUT_DIR/movement-baseline"
MOVEMENT_POOLED_DIR="$OUT_DIR/movement-pooled"
IN_PLACE_BASELINE_DIR="$OUT_DIR/in-place-baseline"
IN_PLACE_POOLED_DIR="$OUT_DIR/in-place-pooled"
MOVEMENT_BASELINE_LOG="$OUT_DIR/movement-baseline.log"
MOVEMENT_POOLED_LOG="$OUT_DIR/movement-pooled.log"
IN_PLACE_BASELINE_LOG="$OUT_DIR/in-place-baseline.log"
IN_PLACE_POOLED_LOG="$OUT_DIR/in-place-pooled.log"
MOVEMENT_BASELINE_DB="$OUT_DIR/movement-baseline-rocksdb"
MOVEMENT_POOLED_DB="$OUT_DIR/movement-pooled-rocksdb"
IN_PLACE_BASELINE_DB="$OUT_DIR/in-place-baseline-rocksdb"
IN_PLACE_POOLED_DB="$OUT_DIR/in-place-pooled-rocksdb"
SUMMARY_PATH="$OUT_DIR/gpu-terrain-upload-stage-pool-summary.txt"
MIN_REUSES="${RUMPELMC_UPLOAD_STAGE_POOL_MIN_REUSES:-1}"

fail() {
  echo "gpu_terrain_upload_stage_pool_gate: $*" >&2
  exit 1
}

metric() {
  key="$1"
  marker_path="$2"
  sed -n "s/.*$key=\([0-9][0-9]*\).*/\1/p" "$marker_path" | sed -n '1p'
}

require_positive_integer() {
  name="$1"
  value="$2"
  case "$value" in
    ''|*[!0-9]*) fail "$name must be an integer" ;;
  esac
  if [ "$value" -lt 1 ]; then
    fail "$name must be at least 1"
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

listener_pid() {
  if command -v lsof >/dev/null 2>&1; then
    lsof -tiTCP:25565 -sTCP:LISTEN 2>/dev/null | sed -n '1p'
  fi
}

cleanup_pid_from_log() {
  log_path="$1"
  if [ -s "$log_path" ]; then
    pid="$(sed -n '
      s/.*Started local server PID \([0-9][0-9]*\).*/\1/p
      s/.*Go server started with PID: \([0-9][0-9]*\).*/\1/p
    ' "$log_path" | tail -n 1)"
    if [ -n "${pid:-}" ]; then
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
    fi
  fi
}

cleanup_port() {
  pid="$(listener_pid || true)"
  if [ -n "$pid" ]; then
    kill "$pid" 2>/dev/null || true
  fi
}

cleanup() {
  cleanup_pid_from_log "$MOVEMENT_BASELINE_LOG"
  cleanup_pid_from_log "$MOVEMENT_POOLED_LOG"
  cleanup_pid_from_log "$IN_PLACE_BASELINE_LOG"
  cleanup_pid_from_log "$IN_PLACE_POOLED_LOG"
  cleanup_port
}

run_movement() {
  pool_enabled="$1"
  run_dir="$2"
  db_path="$3"
  log_path="$4"
  run_rc=0
  RUMPELMC_SERVER_ROCKSDB_PATH="$db_path" \
  RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE="${RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE:-1}" \
  RUMPELMC_GODOT_RUST_EXT_PROFILE="${RUMPELMC_GODOT_RUST_EXT_PROFILE:-release}" \
  RUMPELMC_GPU_TERRAIN_UPLOAD_STAGE_POOL="$pool_enabled" \
  GODOT_QUIT_AFTER_FRAMES="${GODOT_QUIT_AFTER_FRAMES:-30000}" \
  GODOT_TIMEOUT_SEC="${GODOT_TIMEOUT_SEC:-240}" \
  SMOKE_DELAY_SEC="${SMOKE_DELAY_SEC:-5.0}" \
  sh "$ROOT_DIR/scripts/gpu_terrain_movement_stress.sh" "$run_dir" > "$log_path" 2>&1 || run_rc=$?
  cleanup_pid_from_log "$log_path"
  cleanup_port
  if [ "$run_rc" -ne 0 ]; then
    tail -n 100 "$log_path" >&2 || true
    fail "movement stress failed with exit code $run_rc for stage pool=$pool_enabled"
  fi
}

run_in_place() {
  pool_enabled="$1"
  run_dir="$2"
  db_path="$3"
  log_path="$4"
  run_rc=0
  RUMPELMC_IN_PLACE_UPLOAD_ROCKSDB_PATH="$db_path" \
  RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE="${RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE:-1}" \
  RUMPELMC_GODOT_RUST_EXT_PROFILE="${RUMPELMC_GODOT_RUST_EXT_PROFILE:-release}" \
  RUMPELMC_GPU_TERRAIN_UPLOAD_STAGE_POOL="$pool_enabled" \
  GODOT_QUIT_AFTER_FRAMES="${GODOT_QUIT_AFTER_FRAMES:-36000}" \
  GODOT_TIMEOUT_SEC="${GODOT_TIMEOUT_SEC:-300}" \
  SMOKE_DELAY_SEC="${SMOKE_DELAY_SEC:-8.0}" \
  sh "$ROOT_DIR/scripts/gpu_terrain_in_place_upload_gate.sh" "$run_dir" > "$log_path" 2>&1 || run_rc=$?
  cleanup_pid_from_log "$log_path"
  cleanup_port
  if [ "$run_rc" -ne 0 ]; then
    tail -n 100 "$log_path" >&2 || true
    fail "in-place upload gate failed with exit code $run_rc for stage pool=$pool_enabled"
  fi
}

require_clean_upload_policy() {
  marker_path="$1"
  require_metric_eq "$marker_path" gpu_upload_fail 0
  require_metric_eq "$marker_path" gpu_upload_fail_capacity 0
  require_metric_eq "$marker_path" gpu_upload_fail_fragmented 0
  require_metric_eq "$marker_path" gpu_upload_fail_injected 0
  grep -q "gpu_upload_retry_policy=none" "$marker_path" || fail "gpu_upload_retry_policy is not none in $marker_path"
  require_metric_eq "$marker_path" gpu_upload_retry_attempts 0
  require_metric_eq "$marker_path" gpu_upload_retry_success 0
  require_metric_eq "$marker_path" gpu_upload_retry_giveups 0
  require_metric_eq "$marker_path" gpu_upload_backoff_active 0
  require_metric_eq "$marker_path" gpu_upload_backoff_frames 0
  require_metric_eq "$marker_path" gpu_upload_backoff_max_frames 0
}

require_stage_pool_disabled() {
  marker_path="$1"
  require_metric_eq "$marker_path" gpu_upload_stage_pool_enabled 0
  require_metric_eq "$marker_path" gpu_upload_stage_pba_creates 0
  require_metric_eq "$marker_path" gpu_upload_stage_pba_reuses 0
  require_clean_upload_policy "$marker_path"
}

require_stage_pool_pooled() {
  marker_path="$1"
  require_metric_eq "$marker_path" gpu_upload_stage_pool_enabled 1
  require_metric_ge "$marker_path" gpu_upload_stage_pool_entries 1
  require_metric_ge "$marker_path" gpu_upload_stage_pool_bytes 1
  require_metric_ge "$marker_path" gpu_upload_stage_pba_creates 1
  require_metric_ge "$marker_path" gpu_upload_stage_pba_reuses "$MIN_REUSES"
  require_clean_upload_policy "$marker_path"

  pooled_uploads="$(metric gpu_uploads "$marker_path")"
  pooled_creates="$(metric gpu_upload_stage_pba_creates "$marker_path")"
  if [ "$pooled_uploads" -le "$pooled_creates" ]; then
    fail "pooled stage creates=$pooled_creates did not stay below uploads=$pooled_uploads in $marker_path"
  fi
}

require_in_place_marker() {
  marker_path="$1"
  require_metric_eq "$marker_path" gpu_in_place_upload_enabled 1
  require_metric_ge "$marker_path" gpu_in_place_uploads 1
}

write_summary() {
  movement_baseline_marker="$MOVEMENT_BASELINE_DIR/gpu-terrain-movement-stress.png.txt"
  movement_pooled_marker="$MOVEMENT_POOLED_DIR/gpu-terrain-movement-stress.png.txt"
  in_place_baseline_marker="$IN_PLACE_BASELINE_DIR/run/gpu-terrain-movement-stress.png.txt"
  in_place_pooled_marker="$IN_PLACE_POOLED_DIR/run/gpu-terrain-movement-stress.png.txt"

  {
    printf 'gpu_upload_stage_pool status=pass min_reuses=%s baseline_uploads=%s baseline_stage_pool_enabled=%s baseline_stage_pba_creates=%s baseline_stage_pba_reuses=%s pooled_uploads=%s pooled_stage_pool_enabled=%s pooled_stage_pool_entries=%s pooled_stage_pool_bytes=%s pooled_stage_pba_creates=%s pooled_stage_pba_reuses=%s movement_baseline_uploads=%s movement_baseline_stage_pool_enabled=%s movement_baseline_stage_pba_creates=%s movement_baseline_stage_pba_reuses=%s movement_pooled_uploads=%s movement_pooled_stage_pool_enabled=%s movement_pooled_stage_pool_entries=%s movement_pooled_stage_pool_bytes=%s movement_pooled_stage_pba_creates=%s movement_pooled_stage_pba_reuses=%s in_place_baseline_uploads=%s in_place_baseline_in_place_uploads=%s in_place_baseline_stage_pool_enabled=%s in_place_baseline_stage_pba_creates=%s in_place_baseline_stage_pba_reuses=%s in_place_pooled_uploads=%s in_place_pooled_in_place_uploads=%s in_place_pooled_stage_pool_enabled=%s in_place_pooled_stage_pool_entries=%s in_place_pooled_stage_pool_bytes=%s in_place_pooled_stage_pba_creates=%s in_place_pooled_stage_pba_reuses=%s movement_baseline_marker=%s movement_pooled_marker=%s in_place_baseline_marker=%s in_place_pooled_marker=%s movement_baseline_log=%s movement_pooled_log=%s in_place_baseline_log=%s in_place_pooled_log=%s\n' \
      "$MIN_REUSES" \
      "$(metric gpu_uploads "$movement_baseline_marker")" \
      "$(metric gpu_upload_stage_pool_enabled "$movement_baseline_marker")" \
      "$(metric gpu_upload_stage_pba_creates "$movement_baseline_marker")" \
      "$(metric gpu_upload_stage_pba_reuses "$movement_baseline_marker")" \
      "$(metric gpu_uploads "$movement_pooled_marker")" \
      "$(metric gpu_upload_stage_pool_enabled "$movement_pooled_marker")" \
      "$(metric gpu_upload_stage_pool_entries "$movement_pooled_marker")" \
      "$(metric gpu_upload_stage_pool_bytes "$movement_pooled_marker")" \
      "$(metric gpu_upload_stage_pba_creates "$movement_pooled_marker")" \
      "$(metric gpu_upload_stage_pba_reuses "$movement_pooled_marker")" \
      "$(metric gpu_uploads "$movement_baseline_marker")" \
      "$(metric gpu_upload_stage_pool_enabled "$movement_baseline_marker")" \
      "$(metric gpu_upload_stage_pba_creates "$movement_baseline_marker")" \
      "$(metric gpu_upload_stage_pba_reuses "$movement_baseline_marker")" \
      "$(metric gpu_uploads "$movement_pooled_marker")" \
      "$(metric gpu_upload_stage_pool_enabled "$movement_pooled_marker")" \
      "$(metric gpu_upload_stage_pool_entries "$movement_pooled_marker")" \
      "$(metric gpu_upload_stage_pool_bytes "$movement_pooled_marker")" \
      "$(metric gpu_upload_stage_pba_creates "$movement_pooled_marker")" \
      "$(metric gpu_upload_stage_pba_reuses "$movement_pooled_marker")" \
      "$(metric gpu_uploads "$in_place_baseline_marker")" \
      "$(metric gpu_in_place_uploads "$in_place_baseline_marker")" \
      "$(metric gpu_upload_stage_pool_enabled "$in_place_baseline_marker")" \
      "$(metric gpu_upload_stage_pba_creates "$in_place_baseline_marker")" \
      "$(metric gpu_upload_stage_pba_reuses "$in_place_baseline_marker")" \
      "$(metric gpu_uploads "$in_place_pooled_marker")" \
      "$(metric gpu_in_place_uploads "$in_place_pooled_marker")" \
      "$(metric gpu_upload_stage_pool_enabled "$in_place_pooled_marker")" \
      "$(metric gpu_upload_stage_pool_entries "$in_place_pooled_marker")" \
      "$(metric gpu_upload_stage_pool_bytes "$in_place_pooled_marker")" \
      "$(metric gpu_upload_stage_pba_creates "$in_place_pooled_marker")" \
      "$(metric gpu_upload_stage_pba_reuses "$in_place_pooled_marker")" \
      "$movement_baseline_marker" "$movement_pooled_marker" \
      "$in_place_baseline_marker" "$in_place_pooled_marker" \
      "$MOVEMENT_BASELINE_LOG" "$MOVEMENT_POOLED_LOG" \
      "$IN_PLACE_BASELINE_LOG" "$IN_PLACE_POOLED_LOG"
  } > "$SUMMARY_PATH"
  cat "$SUMMARY_PATH"
}

require_positive_integer RUMPELMC_UPLOAD_STAGE_POOL_MIN_REUSES "$MIN_REUSES"

mkdir -p "$OUT_DIR"
rm -rf "$MOVEMENT_BASELINE_DIR" "$MOVEMENT_POOLED_DIR" "$IN_PLACE_BASELINE_DIR" "$IN_PLACE_POOLED_DIR" \
  "$MOVEMENT_BASELINE_DB" "$MOVEMENT_POOLED_DB" "$IN_PLACE_BASELINE_DB" "$IN_PLACE_POOLED_DB" \
  "$OUT_DIR/baseline" "$OUT_DIR/pooled" "$OUT_DIR/baseline-rocksdb" "$OUT_DIR/pooled-rocksdb"
rm -f "$MOVEMENT_BASELINE_LOG" "$MOVEMENT_POOLED_LOG" "$IN_PLACE_BASELINE_LOG" "$IN_PLACE_POOLED_LOG" \
  "$OUT_DIR/baseline.log" "$OUT_DIR/pooled.log" "$SUMMARY_PATH"
mkdir -p "$MOVEMENT_BASELINE_DIR" "$MOVEMENT_POOLED_DIR" "$IN_PLACE_BASELINE_DIR" "$IN_PLACE_POOLED_DIR" \
  "$MOVEMENT_BASELINE_DB" "$MOVEMENT_POOLED_DB" "$IN_PLACE_BASELINE_DB" "$IN_PLACE_POOLED_DB"

if [ -n "$(listener_pid || true)" ]; then
  fail "port 25565 is already in use; stop the existing server before upload stage pool gate"
fi
trap cleanup EXIT HUP INT TERM

echo "==> GPU terrain upload stage pool gate"
run_movement 0 "$MOVEMENT_BASELINE_DIR" "$MOVEMENT_BASELINE_DB" "$MOVEMENT_BASELINE_LOG"
run_movement 1 "$MOVEMENT_POOLED_DIR" "$MOVEMENT_POOLED_DB" "$MOVEMENT_POOLED_LOG"
run_in_place 0 "$IN_PLACE_BASELINE_DIR" "$IN_PLACE_BASELINE_DB" "$IN_PLACE_BASELINE_LOG"
run_in_place 1 "$IN_PLACE_POOLED_DIR" "$IN_PLACE_POOLED_DB" "$IN_PLACE_POOLED_LOG"

movement_baseline_marker="$MOVEMENT_BASELINE_DIR/gpu-terrain-movement-stress.png.txt"
movement_pooled_marker="$MOVEMENT_POOLED_DIR/gpu-terrain-movement-stress.png.txt"
in_place_baseline_marker="$IN_PLACE_BASELINE_DIR/run/gpu-terrain-movement-stress.png.txt"
in_place_pooled_marker="$IN_PLACE_POOLED_DIR/run/gpu-terrain-movement-stress.png.txt"
test -s "$movement_baseline_marker" || fail "missing marker $movement_baseline_marker"
test -s "$movement_pooled_marker" || fail "missing marker $movement_pooled_marker"
test -s "$in_place_baseline_marker" || fail "missing marker $in_place_baseline_marker"
test -s "$in_place_pooled_marker" || fail "missing marker $in_place_pooled_marker"

require_stage_pool_disabled "$movement_baseline_marker"
require_stage_pool_pooled "$movement_pooled_marker"
require_stage_pool_disabled "$in_place_baseline_marker"
require_in_place_marker "$in_place_baseline_marker"
require_stage_pool_pooled "$in_place_pooled_marker"
require_in_place_marker "$in_place_pooled_marker"

write_summary
echo "GPU terrain upload stage pool artifacts: $OUT_DIR"
