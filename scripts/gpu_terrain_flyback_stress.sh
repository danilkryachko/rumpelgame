#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/gpu_terrain_visual_smoke/flyback_stress"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

MOTION_NAME="${RUMPELMC_FLYBACK_STRESS_MOTION:-chunk_fly_out_back}"
EXPECTED_CURRENT_CHUNK="${RUMPELMC_FLYBACK_STRESS_EXPECTED_CHUNK:-0,0}"
MIN_MOTION_STEPS="${RUMPELMC_FLYBACK_STRESS_MIN_STEPS:-13}"
MIN_MOTION_CHUNKS="${RUMPELMC_FLYBACK_STRESS_MIN_CHUNKS:-7}"
MOTION_STEP_SEC="${RUMPELMC_FLYBACK_STRESS_STEP_SEC:-0.55}"
MOTION_SETTLE_SEC="${RUMPELMC_FLYBACK_STRESS_SETTLE_SEC:-4.0}"
MAX_GROUND_DISTANCE="${RUMPELMC_FLYBACK_STRESS_MAX_GROUND_DISTANCE:-24.0}"

fail() {
  echo "gpu_terrain_flyback_stress: $*" >&2
  exit 1
}

metric() {
  key="$1"
  marker_path="$2"
  sed -n "s/.*$key=\([0-9][0-9]*\).*/\1/p" "$marker_path" | sed -n '1p'
}

float_metric() {
  key="$1"
  marker_path="$2"
  sed -n "s/.*$key=\(-\{0,1\}[0-9][0-9]*\.[0-9][0-9]*\).*/\1/p" "$marker_path" | sed -n '1p'
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

require_float_between() {
  marker_path="$1"
  key="$2"
  min_value="$3"
  max_value="$4"
  value="$(float_metric "$key" "$marker_path")"
  test -n "$value" || fail "missing $key in $marker_path"
  awk -v key="$key" -v value="$value" -v min_value="$min_value" -v max_value="$max_value" '
    BEGIN {
      if (value < min_value || value > max_value) {
        printf("gpu_terrain_flyback_stress: %s=%.3f outside %.3f..%.3f\n", key, value, min_value, max_value) > "/dev/stderr"
        exit 1
      }
    }
  '
}

write_summary() {
  summary_path="$OUT_DIR/flyback-stress-summary.txt"
  {
    printf 'GPU terrain flyback stress summary motion=%s expected_chunk=%s grace_sec=%s\n' \
      "$MOTION_NAME" "$EXPECTED_CURRENT_CHUNK" "${RUMPELMC_CLIENT_CHUNK_UNLOAD_GRACE_SEC:-default}"
    printf 'flyback_return current_chunk_loaded=%s current_chunk_submeshes=%s current_chunk_collision=%s ground_hit=%s ground_distance=%s ground_y=%s motion_steps=%s motion_chunks=%s terrain_samples=%s smoke_err=%s gpu_upload_fail=%s\n' \
      "$(metric current_chunk_loaded "$marker_path")" \
      "$(metric current_chunk_submeshes "$marker_path")" \
      "$(metric current_chunk_collision "$marker_path")" \
      "$(metric ground_hit "$marker_path")" \
      "$(float_metric ground_distance "$marker_path")" \
      "$(float_metric ground_y "$marker_path")" \
      "$(metric motion_steps "$marker_path")" \
      "$(metric motion_chunks "$marker_path")" \
      "$(metric terrain_samples "$marker_path")" \
      "$(metric smoke_err "$marker_path")" \
      "$(metric gpu_upload_fail "$marker_path")"
  } > "$summary_path"
  cat "$summary_path"
}

mkdir -p "$OUT_DIR"

echo "==> GPU terrain flyback stress"
RUMPELMC_MOVEMENT_STRESS_MOTION="$MOTION_NAME" \
RUMPELMC_MOVEMENT_STRESS_EXPECTED_CHUNK="$EXPECTED_CURRENT_CHUNK" \
RUMPELMC_MOVEMENT_STRESS_MIN_CHUNKS="$MIN_MOTION_CHUNKS" \
RUMPELMC_MOVEMENT_STRESS_STEP_SEC="$MOTION_STEP_SEC" \
RUMPELMC_MOVEMENT_STRESS_SETTLE_SEC="$MOTION_SETTLE_SEC" \
RUMPELMC_MOVEMENT_STRESS_BUDGET_MODE="${RUMPELMC_FLYBACK_STRESS_BUDGET_MODE:-report}" \
RUMPELMC_MOVEMENT_STRESS_PROCESS_WALL_BUDGET_MODE="${RUMPELMC_FLYBACK_STRESS_PROCESS_WALL_BUDGET_MODE:-report}" \
RUMPELMC_MOVEMENT_STRESS_GPU_COMPOSITOR_BUDGET_MODE="${RUMPELMC_FLYBACK_STRESS_GPU_COMPOSITOR_BUDGET_MODE:-report}" \
RUMPELMC_MOVEMENT_STRESS_GPU_TIMESTAMP_BUDGET_MODE="${RUMPELMC_FLYBACK_STRESS_GPU_TIMESTAMP_BUDGET_MODE:-report}" \
sh "$ROOT_DIR/scripts/gpu_terrain_movement_stress.sh" "$OUT_DIR"

marker_path="$OUT_DIR/gpu-terrain-movement-stress.png.txt"
test -s "$marker_path" || fail "missing marker $marker_path"
grep -q "motion=\"$MOTION_NAME\"" "$marker_path" || fail "unexpected motion in $marker_path"
grep -q "current_chunk=\"$EXPECTED_CURRENT_CHUNK\"" "$marker_path" || fail "unexpected final chunk in $marker_path"
grep -q "smoke_err=0" "$marker_path" || fail "smoke_err is not 0 in $marker_path"
require_metric_ge "$marker_path" motion_steps "$MIN_MOTION_STEPS"
require_metric_ge "$marker_path" motion_chunks "$MIN_MOTION_CHUNKS"
require_metric_eq "$marker_path" current_chunk_loaded 1
require_metric_ge "$marker_path" current_chunk_submeshes 1
require_metric_ge "$marker_path" current_chunk_collision 1
require_metric_eq "$marker_path" ground_hit 1
require_float_between "$marker_path" ground_distance 0.5 "$MAX_GROUND_DISTANCE"
require_metric_eq "$marker_path" gpu_upload_fail 0
write_summary

echo "GPU terrain flyback stress artifacts: $OUT_DIR"
