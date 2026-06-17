#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/gpu_terrain_upload_failure_fallback_gate"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

RUN_DIR="$OUT_DIR/run"
RUN_LOG="$OUT_DIR/run.log"
SUMMARY_PATH="$OUT_DIR/gpu-upload-failure-fallback-summary.txt"
DB_PATH="$OUT_DIR/server-rocksdb"
MIN_GPU_UPLOAD_FAILURES="${RUMPELMC_UPLOAD_FAILURE_FALLBACK_MIN_FAILURES:-1}"

fail() {
  echo "gpu_terrain_upload_failure_fallback_gate: $*" >&2
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

row_field_metric() {
  row="$1"
  key="$2"
  path="$3"
  awk -v row="$row" -v key="$key" '
    $1 == row {
      prefix = key "="
      for (i = 1; i <= NF; i++) {
        if (index($i, prefix) == 1) {
          print substr($i, length(prefix) + 1)
          exit
        }
      }
    }
  ' "$path"
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

require_row_field_eq() {
  row="$1"
  key="$2"
  path="$3"
  expected="$4"
  value="$(row_field_metric "$row" "$key" "$path")"
  test -n "$value" || fail "missing $key in $row row of $path"
  if [ "$value" != "$expected" ]; then
    fail "$row $key=$value, expected $expected in $path"
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

stop_server_from_log() {
  log_path="$1"
  test -f "$log_path" || return 0
  pid="$(sed -n 's/.*Go server started with PID: \([0-9][0-9]*\).*/\1/p' "$log_path" | tail -n 1)"
  if [ -n "$pid" ]; then
    kill "$pid" 2>/dev/null || true
    wait_for_port_clear
  fi
}

cleanup() {
  stop_server_from_log "$RUN_LOG"
}

write_summary() {
  marker_path="$RUN_DIR/gpu-terrain-movement-stress.png.txt"
  movement_summary="$RUN_DIR/movement-stress-summary.txt"

  gpu_upload_fail="$(metric gpu_upload_fail "$marker_path")"
  gpu_upload_fail_capacity="$(metric gpu_upload_fail_capacity "$marker_path")"
  gpu_upload_fail_fragmented="$(metric gpu_upload_fail_fragmented "$marker_path")"
  gpu_upload_fail_injected="$(metric gpu_upload_fail_injected "$marker_path")"
  gpu_uploads="$(metric gpu_uploads "$marker_path")"
  gpu_subchunks="$(metric gpu_subchunks "$marker_path")"
  gpu_frames="$(metric gpu_frames "$marker_path")"
  mesh_visible="$(metric mesh_visible "$marker_path")"
  mesh_shadow_double="$(metric mesh_shadow_double "$marker_path")"
  shadow_path="$(text_metric shadow_path "$marker_path")"
  current_chunk_loaded="$(metric current_chunk_loaded "$marker_path")"
  current_chunk_submeshes="$(metric current_chunk_submeshes "$marker_path")"
  current_chunk_collision="$(metric current_chunk_collision "$marker_path")"
  ground_misses="$(metric ground_misses "$marker_path")"
  terrain_samples="$(metric terrain_samples "$marker_path")"
  current_render_ready="$(row_field_metric movement_readiness current_render_ready "$movement_summary")"
  current_collision_ready="$(row_field_metric movement_readiness current_collision_ready "$movement_summary")"

  {
    printf 'gpu_upload_failure_fallback status=pass injection=1 min_gpu_upload_failures=%s gpu_upload_fail=%s gpu_upload_fail_capacity=%s gpu_upload_fail_fragmented=%s gpu_upload_fail_injected=%s gpu_uploads=%s gpu_subchunks=%s gpu_frames=%s mesh_visible=%s mesh_shadow_double=%s shadow_path=%s current_chunk_loaded=%s current_render_ready=%s current_chunk_submeshes=%s current_collision_ready=%s current_chunk_collision=%s ground_misses=%s terrain_samples=%s marker=%s movement_summary=%s run_log=%s\n' \
      "$MIN_GPU_UPLOAD_FAILURES" \
      "$gpu_upload_fail" "$gpu_upload_fail_capacity" "$gpu_upload_fail_fragmented" "$gpu_upload_fail_injected" \
      "$gpu_uploads" "$gpu_subchunks" "$gpu_frames" "$mesh_visible" "$mesh_shadow_double" "$shadow_path" \
      "$current_chunk_loaded" "$current_render_ready" "$current_chunk_submeshes" \
      "$current_collision_ready" "$current_chunk_collision" "$ground_misses" "$terrain_samples" \
      "$marker_path" "$movement_summary" "$RUN_LOG"
  } > "$SUMMARY_PATH"
  cat "$SUMMARY_PATH"
}

case "$MIN_GPU_UPLOAD_FAILURES" in
  ''|*[!0-9]*) fail "RUMPELMC_UPLOAD_FAILURE_FALLBACK_MIN_FAILURES must be an integer" ;;
esac
if [ "$MIN_GPU_UPLOAD_FAILURES" -lt 1 ]; then
  fail "RUMPELMC_UPLOAD_FAILURE_FALLBACK_MIN_FAILURES must be at least 1"
fi

mkdir -p "$OUT_DIR"
rm -rf "$RUN_DIR" "$DB_PATH"
rm -f "$RUN_LOG" "$SUMMARY_PATH"
mkdir -p "$RUN_DIR" "$DB_PATH"

if [ -n "$(listener_pid || true)" ]; then
  fail "port 25565 is already in use; stop the existing server before upload failure fallback gate"
fi
trap cleanup EXIT HUP INT TERM

echo "==> GPU terrain upload failure fallback gate"
run_rc=0
RUMPELMC_SERVER_ROCKSDB_PATH="$DB_PATH" \
RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE="${RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE:-1}" \
RUMPELMC_GODOT_RUST_EXT_PROFILE="${RUMPELMC_GODOT_RUST_EXT_PROFILE:-release}" \
RUMPELMC_GPU_TERRAIN_UPLOAD_FAILURE_INJECTION=1 \
RUMPELMC_MOVEMENT_STRESS_GPU_UPLOAD_FAILURE_MODE=injected \
RUMPELMC_MOVEMENT_STRESS_MIN_GPU_UPLOAD_FAILURES="$MIN_GPU_UPLOAD_FAILURES" \
RUMPELMC_MOVEMENT_STRESS_BUDGET_MODE=report \
GODOT_QUIT_AFTER_FRAMES="${GODOT_QUIT_AFTER_FRAMES:-30000}" \
GODOT_TIMEOUT_SEC="${GODOT_TIMEOUT_SEC:-180}" \
SMOKE_DELAY_SEC="${SMOKE_DELAY_SEC:-5.0}" \
sh "$ROOT_DIR/scripts/gpu_terrain_movement_stress.sh" "$RUN_DIR" > "$RUN_LOG" 2>&1 || run_rc=$?

cleanup
if [ "$run_rc" -ne 0 ]; then
  tail -n 100 "$RUN_LOG" >&2 || true
  fail "movement stress failed with exit code $run_rc"
fi

marker_path="$RUN_DIR/gpu-terrain-movement-stress.png.txt"
movement_summary="$RUN_DIR/movement-stress-summary.txt"
test -s "$marker_path" || fail "missing marker $marker_path"
test -s "$movement_summary" || fail "missing movement summary $movement_summary"

grep -q "smoke_err=0" "$marker_path" || fail "smoke_err is not 0 in $marker_path"
require_metric_ge "$marker_path" terrain_samples 1
require_metric_ge "$marker_path" gpu_upload_fail "$MIN_GPU_UPLOAD_FAILURES"
require_metric_ge "$marker_path" gpu_upload_fail_injected "$MIN_GPU_UPLOAD_FAILURES"
require_metric_eq "$marker_path" gpu_upload_fail_capacity 0
require_metric_eq "$marker_path" gpu_upload_fail_fragmented 0
require_metric_eq "$marker_path" gpu_uploads 0
require_metric_eq "$marker_path" gpu_subchunks 0
test "$(text_metric shadow_path "$marker_path")" = "arraymesh" \
  || fail "upload failure fallback did not keep shadow_path=arraymesh in $marker_path"
require_metric_ge "$marker_path" mesh_visible 1
require_metric_ge "$marker_path" mesh_shadow_double 1
require_metric_eq "$marker_path" current_chunk_loaded 1
require_metric_ge "$marker_path" current_chunk_submeshes 1
require_metric_ge "$marker_path" current_chunk_collision 1
require_metric_eq "$marker_path" ground_misses 0
grep -q "gpu_upload_retry_policy=none" "$marker_path" || fail "gpu_upload_retry_policy is not none in $marker_path"
require_metric_eq "$marker_path" gpu_upload_retry_attempts 0
require_metric_eq "$marker_path" gpu_upload_retry_success 0
require_metric_eq "$marker_path" gpu_upload_retry_giveups 0
require_metric_eq "$marker_path" gpu_upload_backoff_active 0
require_metric_eq "$marker_path" gpu_upload_backoff_frames 0
require_metric_eq "$marker_path" gpu_upload_backoff_max_frames 0
require_row_field_eq movement_readiness current_render_ready "$movement_summary" 1
require_row_field_eq movement_readiness current_collision_ready "$movement_summary" 1

write_summary
wait_for_port_clear

echo "GPU terrain upload failure fallback artifacts: $OUT_DIR"
