#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/gpu_terrain_upload_stage_pool_current"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

BASELINE_DIR="$OUT_DIR/baseline"
POOLED_DIR="$OUT_DIR/pooled"
BASELINE_LOG="$OUT_DIR/baseline.log"
POOLED_LOG="$OUT_DIR/pooled.log"
BASELINE_DB="$OUT_DIR/baseline-rocksdb"
POOLED_DB="$OUT_DIR/pooled-rocksdb"
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
    pid="$(sed -n 's/.*Started local server PID \([0-9][0-9]*\).*/\1/p' "$log_path" | tail -n 1)"
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
  cleanup_pid_from_log "$BASELINE_LOG"
  cleanup_pid_from_log "$POOLED_LOG"
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

write_summary() {
  baseline_marker="$BASELINE_DIR/gpu-terrain-movement-stress.png.txt"
  pooled_marker="$POOLED_DIR/gpu-terrain-movement-stress.png.txt"
  baseline_uploads="$(metric gpu_uploads "$baseline_marker")"
  pooled_uploads="$(metric gpu_uploads "$pooled_marker")"
  pooled_creates="$(metric gpu_upload_stage_pba_creates "$pooled_marker")"
  pooled_reuses="$(metric gpu_upload_stage_pba_reuses "$pooled_marker")"
  pooled_entries="$(metric gpu_upload_stage_pool_entries "$pooled_marker")"
  pooled_bytes="$(metric gpu_upload_stage_pool_bytes "$pooled_marker")"

  {
    printf 'gpu_upload_stage_pool status=pass min_reuses=%s baseline_uploads=%s baseline_stage_pool_enabled=%s baseline_stage_pba_creates=%s baseline_stage_pba_reuses=%s pooled_uploads=%s pooled_stage_pool_enabled=%s pooled_stage_pool_entries=%s pooled_stage_pool_bytes=%s pooled_stage_pba_creates=%s pooled_stage_pba_reuses=%s baseline_marker=%s pooled_marker=%s baseline_log=%s pooled_log=%s\n' \
      "$MIN_REUSES" \
      "$baseline_uploads" "$(metric gpu_upload_stage_pool_enabled "$baseline_marker")" \
      "$(metric gpu_upload_stage_pba_creates "$baseline_marker")" \
      "$(metric gpu_upload_stage_pba_reuses "$baseline_marker")" \
      "$pooled_uploads" "$(metric gpu_upload_stage_pool_enabled "$pooled_marker")" \
      "$pooled_entries" "$pooled_bytes" "$pooled_creates" "$pooled_reuses" \
      "$baseline_marker" "$pooled_marker" "$BASELINE_LOG" "$POOLED_LOG"
  } > "$SUMMARY_PATH"
  cat "$SUMMARY_PATH"
}

require_positive_integer RUMPELMC_UPLOAD_STAGE_POOL_MIN_REUSES "$MIN_REUSES"

mkdir -p "$OUT_DIR"
rm -rf "$BASELINE_DIR" "$POOLED_DIR" "$BASELINE_DB" "$POOLED_DB"
rm -f "$BASELINE_LOG" "$POOLED_LOG" "$SUMMARY_PATH"
mkdir -p "$BASELINE_DIR" "$POOLED_DIR" "$BASELINE_DB" "$POOLED_DB"

if [ -n "$(listener_pid || true)" ]; then
  fail "port 25565 is already in use; stop the existing server before upload stage pool gate"
fi
trap cleanup EXIT HUP INT TERM

echo "==> GPU terrain upload stage pool gate"
run_movement 0 "$BASELINE_DIR" "$BASELINE_DB" "$BASELINE_LOG"
run_movement 1 "$POOLED_DIR" "$POOLED_DB" "$POOLED_LOG"

baseline_marker="$BASELINE_DIR/gpu-terrain-movement-stress.png.txt"
pooled_marker="$POOLED_DIR/gpu-terrain-movement-stress.png.txt"
test -s "$baseline_marker" || fail "missing marker $baseline_marker"
test -s "$pooled_marker" || fail "missing marker $pooled_marker"

require_metric_eq "$baseline_marker" gpu_upload_stage_pool_enabled 0
require_metric_eq "$baseline_marker" gpu_upload_stage_pba_creates 0
require_metric_eq "$baseline_marker" gpu_upload_stage_pba_reuses 0
require_metric_eq "$baseline_marker" gpu_upload_fail 0
require_metric_eq "$baseline_marker" gpu_upload_fail_capacity 0
require_metric_eq "$baseline_marker" gpu_upload_fail_fragmented 0
require_metric_eq "$baseline_marker" gpu_upload_fail_injected 0

require_metric_eq "$pooled_marker" gpu_upload_stage_pool_enabled 1
require_metric_ge "$pooled_marker" gpu_upload_stage_pool_entries 1
require_metric_ge "$pooled_marker" gpu_upload_stage_pool_bytes 1
require_metric_ge "$pooled_marker" gpu_upload_stage_pba_creates 1
require_metric_ge "$pooled_marker" gpu_upload_stage_pba_reuses "$MIN_REUSES"
require_metric_eq "$pooled_marker" gpu_upload_fail 0
require_metric_eq "$pooled_marker" gpu_upload_fail_capacity 0
require_metric_eq "$pooled_marker" gpu_upload_fail_fragmented 0
require_metric_eq "$pooled_marker" gpu_upload_fail_injected 0
grep -q "gpu_upload_retry_policy=none" "$pooled_marker" || fail "pooled gpu_upload_retry_policy is not none"
require_metric_eq "$pooled_marker" gpu_upload_retry_attempts 0
require_metric_eq "$pooled_marker" gpu_upload_retry_success 0
require_metric_eq "$pooled_marker" gpu_upload_retry_giveups 0

pooled_uploads="$(metric gpu_uploads "$pooled_marker")"
pooled_creates="$(metric gpu_upload_stage_pba_creates "$pooled_marker")"
if [ "$pooled_uploads" -le "$pooled_creates" ]; then
  fail "pooled stage creates=$pooled_creates did not stay below uploads=$pooled_uploads"
fi

write_summary
echo "GPU terrain upload stage pool artifacts: $OUT_DIR"
