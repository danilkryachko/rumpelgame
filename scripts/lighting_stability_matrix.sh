#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/lighting_stability_matrix"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

SUMMARY_PATH="$OUT_DIR/lighting-stability-matrix-summary.txt"
PARITY_SUMMARY="${RUMPELMC_LIGHTING_STABILITY_PARITY_SUMMARY:-"$ROOT_DIR/logs/gpu_native_shadow_resource_lifecycle_parity_20260614/parity-summary.txt"}"
DEFAULT_MOVEMENT_SUMMARY="${RUMPELMC_LIGHTING_STABILITY_DEFAULT_MOVEMENT_SUMMARY:-"$ROOT_DIR/logs/gpu_lighting_marker_summary_retry_20260613/movement-stress-summary.txt"}"
LOW_ANGLE_MOVEMENT_SUMMARY="${RUMPELMC_LIGHTING_STABILITY_LOW_ANGLE_MOVEMENT_SUMMARY:-"$ROOT_DIR/logs/gpu_lighting_low_angle_smoke_20260613_retry/movement-stress-summary.txt"}"
LOAD_SCALING_SUMMARY="${RUMPELMC_LIGHTING_STABILITY_LOAD_SCALING_SUMMARY:-"$ROOT_DIR/logs/gpu_terrain_load_scaling_radius16_summary_check/gpu-terrain-load-scaling-summary.txt"}"
SHADOW_QUALITY_SUMMARY="${RUMPELMC_LIGHTING_STABILITY_SHADOW_QUALITY_SUMMARY:-"$ROOT_DIR/logs/shadow_quality_parity_program_current/shadow-quality-parity-summary.txt"}"

MAX_TERRAIN_QUEUE_MS="${RUMPELMC_LIGHTING_STABILITY_MAX_TERRAIN_QUEUE_MS:-6.667}"
MAX_AVG_LUMA_DELTA="${RUMPELMC_LIGHTING_STABILITY_MAX_AVG_LUMA_DELTA:-0.16}"
MAX_TERRAIN_LUMA_RANGE_DELTA="${RUMPELMC_LIGHTING_STABILITY_MAX_TERRAIN_LUMA_RANGE_DELTA:-0.12}"
MAX_COMPACT_DELTA="${RUMPELMC_LIGHTING_STABILITY_MAX_COMPACT_DELTA:-0.001}"
MIN_DENSE_SUBCHUNKS="${RUMPELMC_LIGHTING_STABILITY_MIN_DENSE_SUBCHUNKS:-2000}"
MIN_DENSE_DRAWS="${RUMPELMC_LIGHTING_STABILITY_MIN_DENSE_DRAWS:-2000}"

mkdir -p "$OUT_DIR"

fail() {
  echo "lighting_stability_matrix: $*" >&2
  exit 1
}

field_metric() {
  key="$1"
  path="$2"
  awk -v key="$key" '
    {
      prefix = key "="
      for (i = 1; i <= NF; i++) {
        if (index($i, prefix) == 1) {
          value = substr($i, length(prefix) + 1)
          gsub(/^"/, "", value)
          gsub(/"$/, "", value)
          print value
          exit
        }
      }
    }
  ' "$path"
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
          value = substr($i, length(prefix) + 1)
          gsub(/^"/, "", value)
          gsub(/"$/, "", value)
          print value
          exit
        }
      }
    }
  ' "$path"
}

pair_delta_metric() {
  pair_name="$1"
  metric_name="$2"
  path="$3"
  awk -v pair_name="$pair_name" -v metric_name="$metric_name" '
    $1 == "pair=" pair_name {
      metric_prefix = metric_name "="
      for (i = 1; i <= NF; i++) {
        if (index($i, metric_prefix) == 1 && i + 1 <= NF && index($(i + 1), "delta=") == 1) {
          print substr($(i + 1), length("delta=") + 1)
          exit
        }
      }
    }
  ' "$path"
}

test -s "$PARITY_SUMMARY" || fail "missing parity summary $PARITY_SUMMARY"
test -s "$DEFAULT_MOVEMENT_SUMMARY" || fail "missing default movement summary $DEFAULT_MOVEMENT_SUMMARY"
test -s "$LOW_ANGLE_MOVEMENT_SUMMARY" || fail "missing low-angle movement summary $LOW_ANGLE_MOVEMENT_SUMMARY"
test -s "$LOAD_SCALING_SUMMARY" || fail "missing load-scaling summary $LOAD_SCALING_SUMMARY"
test -s "$SHADOW_QUALITY_SUMMARY" || fail "missing shadow quality summary $SHADOW_QUALITY_SUMMARY"

default_budget_status="$(row_field_metric movement_terrain_queue budget_status "$DEFAULT_MOVEMENT_SUMMARY")"
default_terrain_queue_max="$(row_field_metric movement_terrain_queue max_ms "$DEFAULT_MOVEMENT_SUMMARY")"
default_process_wall_p95="$(row_field_metric movement_terrain_queue process_wall_p95_ms "$DEFAULT_MOVEMENT_SUMMARY")"
default_gpu_submit_max="$(row_field_metric movement_terrain_queue gpu_compositor_submit_max_ms "$DEFAULT_MOVEMENT_SUMMARY")"
default_gpu_effective_draws="$(row_field_metric movement_terrain_queue gpu_effective_draws "$DEFAULT_MOVEMENT_SUMMARY")"
default_light_dir="$(row_field_metric movement_terrain_queue gpu_light_dir "$DEFAULT_MOVEMENT_SUMMARY")"
default_light_energy="$(row_field_metric movement_terrain_queue gpu_light_energy "$DEFAULT_MOVEMENT_SUMMARY")"
default_light_ambient="$(row_field_metric movement_terrain_queue gpu_light_ambient "$DEFAULT_MOVEMENT_SUMMARY")"

low_angle_pose="$(field_metric smoke_pose "$LOW_ANGLE_MOVEMENT_SUMMARY")"
low_angle_variant="$(field_metric lighting_variant "$LOW_ANGLE_MOVEMENT_SUMMARY")"
low_angle_budget_status="$(row_field_metric movement_terrain_queue budget_status "$LOW_ANGLE_MOVEMENT_SUMMARY")"
low_angle_terrain_queue_max="$(row_field_metric movement_terrain_queue max_ms "$LOW_ANGLE_MOVEMENT_SUMMARY")"
low_angle_process_wall_p95="$(row_field_metric movement_terrain_queue process_wall_p95_ms "$LOW_ANGLE_MOVEMENT_SUMMARY")"
low_angle_gpu_submit_max="$(row_field_metric movement_terrain_queue gpu_compositor_submit_max_ms "$LOW_ANGLE_MOVEMENT_SUMMARY")"
low_angle_gpu_effective_draws="$(row_field_metric movement_terrain_queue gpu_effective_draws "$LOW_ANGLE_MOVEMENT_SUMMARY")"
low_angle_light_dir="$(row_field_metric movement_terrain_queue gpu_light_dir "$LOW_ANGLE_MOVEMENT_SUMMARY")"
low_angle_light_energy="$(row_field_metric movement_terrain_queue gpu_light_energy "$LOW_ANGLE_MOVEMENT_SUMMARY")"
low_angle_light_ambient="$(row_field_metric movement_terrain_queue gpu_light_ambient "$LOW_ANGLE_MOVEMENT_SUMMARY")"

lighting_shadow_delta="$(pair_delta_metric lighting_shadow avg_luma "$PARITY_SUMMARY")"
lighting_shadow_range_delta="$(pair_delta_metric lighting_shadow terrain_luma_range "$PARITY_SUMMARY")"
lighting_shadow_compact_delta="$(pair_delta_metric lighting_shadow_compact avg_luma "$PARITY_SUMMARY")"
lighting_low_angle_delta="$(pair_delta_metric lighting_low_angle avg_luma "$PARITY_SUMMARY")"
lighting_low_angle_range_delta="$(pair_delta_metric lighting_low_angle terrain_luma_range "$PARITY_SUMMARY")"
lighting_low_angle_compact_delta="$(pair_delta_metric lighting_low_angle_compact avg_luma "$PARITY_SUMMARY")"

load_status="$(field_metric status "$LOAD_SCALING_SUMMARY")"
load_subchunks="$(field_metric max_gpu_subchunks "$LOAD_SCALING_SUMMARY")"
load_draws="$(field_metric max_gpu_draws "$LOAD_SCALING_SUMMARY")"
load_faces="$(field_metric max_gpu_faces "$LOAD_SCALING_SUMMARY")"
load_upload_fail="$(field_metric gpu_upload_fail "$LOAD_SCALING_SUMMARY")"
shadow_quality_status="$(field_metric status "$SHADOW_QUALITY_SUMMARY")"

awk \
  -v default_budget_status="${default_budget_status:-fail}" \
  -v default_terrain_queue_max="${default_terrain_queue_max:-999}" \
  -v default_process_wall_p95="${default_process_wall_p95:-999}" \
  -v default_gpu_submit_max="${default_gpu_submit_max:-999}" \
  -v default_gpu_effective_draws="${default_gpu_effective_draws:-0}" \
  -v default_light_dir="${default_light_dir:-missing}" \
  -v default_light_energy="${default_light_energy:-0}" \
  -v default_light_ambient="${default_light_ambient:-0}" \
  -v low_angle_pose="${low_angle_pose:-missing}" \
  -v low_angle_variant="${low_angle_variant:-missing}" \
  -v low_angle_budget_status="${low_angle_budget_status:-fail}" \
  -v low_angle_terrain_queue_max="${low_angle_terrain_queue_max:-999}" \
  -v low_angle_process_wall_p95="${low_angle_process_wall_p95:-999}" \
  -v low_angle_gpu_submit_max="${low_angle_gpu_submit_max:-999}" \
  -v low_angle_gpu_effective_draws="${low_angle_gpu_effective_draws:-0}" \
  -v low_angle_light_dir="${low_angle_light_dir:-missing}" \
  -v low_angle_light_energy="${low_angle_light_energy:-0}" \
  -v low_angle_light_ambient="${low_angle_light_ambient:-0}" \
  -v max_terrain_queue_ms="$MAX_TERRAIN_QUEUE_MS" \
  -v lighting_shadow_delta="${lighting_shadow_delta:-999}" \
  -v lighting_shadow_range_delta="${lighting_shadow_range_delta:-999}" \
  -v lighting_shadow_compact_delta="${lighting_shadow_compact_delta:-999}" \
  -v lighting_low_angle_delta="${lighting_low_angle_delta:-999}" \
  -v lighting_low_angle_range_delta="${lighting_low_angle_range_delta:-999}" \
  -v lighting_low_angle_compact_delta="${lighting_low_angle_compact_delta:-999}" \
  -v max_avg_luma_delta="$MAX_AVG_LUMA_DELTA" \
  -v max_terrain_luma_range_delta="$MAX_TERRAIN_LUMA_RANGE_DELTA" \
  -v max_compact_delta="$MAX_COMPACT_DELTA" \
  -v load_status="${load_status:-fail}" \
  -v load_subchunks="${load_subchunks:-0}" \
  -v load_draws="${load_draws:-0}" \
  -v load_faces="${load_faces:-0}" \
  -v load_upload_fail="${load_upload_fail:-1}" \
  -v min_dense_subchunks="$MIN_DENSE_SUBCHUNKS" \
  -v min_dense_draws="$MIN_DENSE_DRAWS" \
  -v shadow_quality_status="${shadow_quality_status:-fail}" \
  -v parity_summary="$PARITY_SUMMARY" \
  -v default_movement_summary="$DEFAULT_MOVEMENT_SUMMARY" \
  -v low_angle_movement_summary="$LOW_ANGLE_MOVEMENT_SUMMARY" \
  -v load_scaling_summary="$LOAD_SCALING_SUMMARY" \
  -v shadow_quality_summary="$SHADOW_QUALITY_SUMMARY" '
  BEGIN {
    status = "pass"
    reason = "ok"
    ambient_variant_status = "deferred"
    ambient_variant_reason = "no_existing_ambient_variant"

    if (!(default_budget_status == "pass" && default_terrain_queue_max + 0 <= max_terrain_queue_ms + 0 && default_gpu_effective_draws + 0 > 0 && default_light_dir != "missing")) {
      status = "fail"
      reason = "default_movement_not_clean"
    } else if (!(low_angle_pose == "lighting_low_angle" && low_angle_variant == "low_angle" && low_angle_budget_status == "pass" && low_angle_terrain_queue_max + 0 <= max_terrain_queue_ms + 0 && low_angle_gpu_effective_draws + 0 > 0 && low_angle_light_dir != "missing")) {
      status = "fail"
      reason = "low_angle_movement_not_clean"
    } else if (default_light_dir == low_angle_light_dir || default_light_energy == low_angle_light_energy) {
      status = "fail"
      reason = "lighting_variant_not_distinct"
    } else if (lighting_shadow_delta + 0 > max_avg_luma_delta + 0 || lighting_shadow_range_delta + 0 > max_terrain_luma_range_delta + 0) {
      status = "fail"
      reason = "lighting_shadow_visual_delta"
    } else if (lighting_shadow_compact_delta + 0 > max_compact_delta + 0) {
      status = "fail"
      reason = "lighting_shadow_compact_delta"
    } else if (lighting_low_angle_delta + 0 > max_avg_luma_delta + 0 || lighting_low_angle_range_delta + 0 > max_terrain_luma_range_delta + 0) {
      status = "fail"
      reason = "lighting_low_angle_visual_delta"
    } else if (lighting_low_angle_compact_delta + 0 > max_compact_delta + 0) {
      status = "fail"
      reason = "lighting_low_angle_compact_delta"
    } else if (!(load_status == "pass" && load_subchunks + 0 >= min_dense_subchunks + 0 && load_draws + 0 >= min_dense_draws + 0 && load_upload_fail + 0 == 0)) {
      status = "fail"
      reason = "dense_load_not_clean"
    } else if (shadow_quality_status != "pass") {
      status = "fail"
      reason = "shadow_quality_not_clean"
    }

    printf("lighting_stability_matrix status=%s reason=%s default_light_dir=%s default_light_energy=%.3f default_light_ambient=%.3f default_terrain_queue_max_ms=%.3f default_process_wall_p95_ms=%.3f default_gpu_submit_max_ms=%.3f default_gpu_effective_draws=%d low_angle_light_dir=%s low_angle_light_energy=%.3f low_angle_light_ambient=%.3f low_angle_terrain_queue_max_ms=%.3f low_angle_process_wall_p95_ms=%.3f low_angle_gpu_submit_max_ms=%.3f low_angle_gpu_effective_draws=%d ambient_variant_status=%s ambient_variant_reason=%s lighting_shadow_avg_luma_delta=%.4f lighting_shadow_luma_range_delta=%.4f lighting_shadow_compact_delta=%.4f lighting_low_angle_avg_luma_delta=%.4f lighting_low_angle_luma_range_delta=%.4f lighting_low_angle_compact_delta=%.4f dense_status=%s dense_subchunks=%d dense_draws=%d dense_faces=%d dense_upload_fail=%d shadow_quality_status=%s parity_summary=%s default_movement_summary=%s low_angle_movement_summary=%s load_scaling_summary=%s shadow_quality_summary=%s\n", status, reason, default_light_dir, default_light_energy, default_light_ambient, default_terrain_queue_max, default_process_wall_p95, default_gpu_submit_max, default_gpu_effective_draws, low_angle_light_dir, low_angle_light_energy, low_angle_light_ambient, low_angle_terrain_queue_max, low_angle_process_wall_p95, low_angle_gpu_submit_max, low_angle_gpu_effective_draws, ambient_variant_status, ambient_variant_reason, lighting_shadow_delta, lighting_shadow_range_delta, lighting_shadow_compact_delta, lighting_low_angle_delta, lighting_low_angle_range_delta, lighting_low_angle_compact_delta, load_status, load_subchunks, load_draws, load_faces, load_upload_fail, shadow_quality_status, parity_summary, default_movement_summary, low_angle_movement_summary, load_scaling_summary, shadow_quality_summary)
    if (status != "pass") {
      exit 1
    }
  }
' > "$SUMMARY_PATH" || {
  cat "$SUMMARY_PATH" >&2 || true
  fail "lighting stability matrix failed"
}

cat "$SUMMARY_PATH"
echo "Lighting stability artifacts: $OUT_DIR"
