#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
LOG_DIR="${1:-"$ROOT_DIR/logs/gpu_terrain_upload_pressure_smoke"}"
case "$LOG_DIR" in
  /*) ;;
  *) LOG_DIR="$ROOT_DIR/$LOG_DIR" ;;
esac
OUT_PATH="${2:-"$LOG_DIR/gpu-resource-lifecycle-audit-summary.txt"}"
case "$OUT_PATH" in
  /*) ;;
  *) OUT_PATH="$ROOT_DIR/$OUT_PATH" ;;
esac
REPORT_PATH="${RUMPELMC_RESOURCE_LIFECYCLE_REPORT_PATH:-"$LOG_DIR/gpu-resource-lifecycle-report.txt"}"
case "$REPORT_PATH" in
  /*) ;;
  *) REPORT_PATH="$ROOT_DIR/$REPORT_PATH" ;;
esac

MAX_UPLOAD_FAIL="${RUMPELMC_RESOURCE_LIFECYCLE_MAX_UPLOAD_FAIL:-0}"
MAX_SCENE_TARGET_REPLACE="${RUMPELMC_RESOURCE_LIFECYCLE_MAX_SCENE_TARGET_REPLACE:-0}"
MIN_SCENE_TARGET_CREATE="${RUMPELMC_RESOURCE_LIFECYCLE_MIN_SCENE_TARGET_CREATE:-1}"
MIN_SCENE_TARGET_REUSE="${RUMPELMC_RESOURCE_LIFECYCLE_MIN_SCENE_TARGET_REUSE:-1}"
MIN_UNIFORM_SET_CREATE="${RUMPELMC_RESOURCE_LIFECYCLE_MIN_UNIFORM_SET_CREATE:-1}"
MIN_ATLAS_TEXTURE_CREATE="${RUMPELMC_RESOURCE_LIFECYCLE_MIN_ATLAS_TEXTURE_CREATE:-1}"
MIN_ATLAS_SAMPLER_CREATE="${RUMPELMC_RESOURCE_LIFECYCLE_MIN_ATLAS_SAMPLER_CREATE:-1}"
MAX_NATIVE_SHADOW_ERRORS="${RUMPELMC_RESOURCE_LIFECYCLE_MAX_NATIVE_SHADOW_ERRORS:-0}"

fail() {
  echo "gpu_resource_lifecycle_audit: $*" >&2
  exit 1
}

relative_path() {
  path="$1"
  case "$path" in
    "$ROOT_DIR"/*) printf '%s\n' "${path#$ROOT_DIR/}" ;;
    *) printf '%s\n' "$path" ;;
  esac
}

metric_value() {
  label="$1"
  awk -v label="$label" '
    index($0, "- " label ": `") == 1 {
      split($0, parts, "`")
      print parts[4]
      exit
    }
  ' "$REPORT_PATH"
}

require_metric() {
  label="$1"
  value="$(metric_value "$label")"
  test -n "$value" || fail "missing report metric $label in $(relative_path "$REPORT_PATH")"
  test "$value" != "n/a" || fail "report metric $label is n/a in $(relative_path "$REPORT_PATH")"
  printf '%s\n' "$value"
}

metric_or_zero() {
  label="$1"
  value="$(metric_value "$label")"
  if [ -z "$value" ] || [ "$value" = "n/a" ]; then
    printf '0\n'
  else
    printf '%s\n' "$value"
  fi
}

assert_int_le() {
  name="$1"
  value="$2"
  max="$3"
  awk -v value="$value" -v max="$max" 'BEGIN { exit !((value + 0) <= (max + 0)) }' \
    || fail "$name=$value exceeds $max"
}

assert_int_ge() {
  name="$1"
  value="$2"
  min="$3"
  awk -v value="$value" -v min="$min" 'BEGIN { exit !((value + 0) >= (min + 0)) }' \
    || fail "$name=$value is below $min"
}

test -d "$LOG_DIR" || fail "missing log dir $LOG_DIR"
mkdir -p "$(dirname -- "$OUT_PATH")"
sh "$ROOT_DIR/scripts/gpu_terrain_report.sh" "$LOG_DIR" "$REPORT_PATH" >/dev/null
test -s "$REPORT_PATH" || fail "missing report $(relative_path "$REPORT_PATH")"
grep -q "No error patterns found in summary and marker files." "$REPORT_PATH" \
  || fail "report error scan is not clean in $(relative_path "$REPORT_PATH")"

scene_target_create="$(require_metric 'max `gpu_scene_target_create`')"
scene_target_reuse="$(require_metric 'max `gpu_scene_target_reuse`')"
scene_target_replace="$(require_metric 'max `gpu_scene_target_replace`')"
uniform_set_create="$(require_metric 'max `gpu_uniform_set_create`')"
atlas_texture_create="$(require_metric 'max `gpu_atlas_texture_create`')"
atlas_sampler_create="$(require_metric 'max `gpu_atlas_sampler_create`')"
upload_fail="$(require_metric 'sum `gpu_upload_fail`')"
upload_fail_capacity="$(require_metric 'sum `gpu_upload_fail_capacity`')"
upload_fail_fragmented="$(require_metric 'sum `gpu_upload_fail_fragmented`')"
native_shadow_active="$(metric_or_zero 'max `native_shadow_active`')"
native_shadow_framebuffer_bind_errors="$(metric_or_zero 'max `native_shadow_framebuffer_bind_error_count`')"
native_shadow_framebuffer_descriptor_errors="$(metric_or_zero 'max `native_shadow_framebuffer_descriptor_error_count`')"
native_shadow_pass_descriptor_errors="$(metric_or_zero 'max `native_shadow_pass_descriptor_error_count`')"
native_shadow_pass_lifecycle_errors="$(metric_or_zero 'max `native_shadow_pass_lifecycle_error_count`')"
native_shadow_command_record_errors="$(metric_or_zero 'max `native_shadow_command_buffer_record_error_count`')"
native_shadow_command_submit_errors="$(metric_or_zero 'max `native_shadow_command_buffer_submit_error_count`')"
native_shadow_command_errors="$(metric_or_zero 'max `native_shadow_command_buffer_error_count`')"

assert_int_ge gpu_scene_target_create "$scene_target_create" "$MIN_SCENE_TARGET_CREATE"
assert_int_ge gpu_scene_target_reuse "$scene_target_reuse" "$MIN_SCENE_TARGET_REUSE"
assert_int_le gpu_scene_target_replace "$scene_target_replace" "$MAX_SCENE_TARGET_REPLACE"
assert_int_ge gpu_uniform_set_create "$uniform_set_create" "$MIN_UNIFORM_SET_CREATE"
assert_int_ge gpu_atlas_texture_create "$atlas_texture_create" "$MIN_ATLAS_TEXTURE_CREATE"
assert_int_ge gpu_atlas_sampler_create "$atlas_sampler_create" "$MIN_ATLAS_SAMPLER_CREATE"
assert_int_le gpu_upload_fail "$upload_fail" "$MAX_UPLOAD_FAIL"
assert_int_le gpu_upload_fail_capacity "$upload_fail_capacity" "$MAX_UPLOAD_FAIL"
assert_int_le gpu_upload_fail_fragmented "$upload_fail_fragmented" "$MAX_UPLOAD_FAIL"
assert_int_le native_shadow_framebuffer_bind_error_count "$native_shadow_framebuffer_bind_errors" "$MAX_NATIVE_SHADOW_ERRORS"
assert_int_le native_shadow_framebuffer_descriptor_error_count "$native_shadow_framebuffer_descriptor_errors" "$MAX_NATIVE_SHADOW_ERRORS"
assert_int_le native_shadow_pass_descriptor_error_count "$native_shadow_pass_descriptor_errors" "$MAX_NATIVE_SHADOW_ERRORS"
assert_int_le native_shadow_pass_lifecycle_error_count "$native_shadow_pass_lifecycle_errors" "$MAX_NATIVE_SHADOW_ERRORS"
assert_int_le native_shadow_command_buffer_record_error_count "$native_shadow_command_record_errors" "$MAX_NATIVE_SHADOW_ERRORS"
assert_int_le native_shadow_command_buffer_submit_error_count "$native_shadow_command_submit_errors" "$MAX_NATIVE_SHADOW_ERRORS"
assert_int_le native_shadow_command_buffer_error_count "$native_shadow_command_errors" "$MAX_NATIVE_SHADOW_ERRORS"

{
  printf 'GPU resource lifecycle audit\n'
  printf 'log_dir=%s\n' "$(relative_path "$LOG_DIR")"
  printf 'report=%s\n' "$(relative_path "$REPORT_PATH")"
  printf 'thresholds max_upload_fail=%s max_scene_target_replace=%s min_scene_target_create=%s min_scene_target_reuse=%s min_uniform_set_create=%s min_atlas_texture_create=%s min_atlas_sampler_create=%s max_native_shadow_errors=%s\n' \
    "$MAX_UPLOAD_FAIL" \
    "$MAX_SCENE_TARGET_REPLACE" \
    "$MIN_SCENE_TARGET_CREATE" \
    "$MIN_SCENE_TARGET_REUSE" \
    "$MIN_UNIFORM_SET_CREATE" \
    "$MIN_ATLAS_TEXTURE_CREATE" \
    "$MIN_ATLAS_SAMPLER_CREATE" \
    "$MAX_NATIVE_SHADOW_ERRORS"
  printf 'summary resource_lifecycle_audit_status=pass gpu_scene_target_create=%s gpu_scene_target_reuse=%s gpu_scene_target_replace=%s gpu_uniform_set_create=%s gpu_atlas_texture_create=%s gpu_atlas_sampler_create=%s gpu_upload_fail=%s gpu_upload_fail_capacity=%s gpu_upload_fail_fragmented=%s native_shadow_active=%s native_shadow_framebuffer_bind_error_count=%s native_shadow_framebuffer_descriptor_error_count=%s native_shadow_pass_descriptor_error_count=%s native_shadow_pass_lifecycle_error_count=%s native_shadow_command_buffer_record_error_count=%s native_shadow_command_buffer_submit_error_count=%s native_shadow_command_buffer_error_count=%s\n' \
    "$scene_target_create" \
    "$scene_target_reuse" \
    "$scene_target_replace" \
    "$uniform_set_create" \
    "$atlas_texture_create" \
    "$atlas_sampler_create" \
    "$upload_fail" \
    "$upload_fail_capacity" \
    "$upload_fail_fragmented" \
    "$native_shadow_active" \
    "$native_shadow_framebuffer_bind_errors" \
    "$native_shadow_framebuffer_descriptor_errors" \
    "$native_shadow_pass_descriptor_errors" \
    "$native_shadow_pass_lifecycle_errors" \
    "$native_shadow_command_record_errors" \
    "$native_shadow_command_submit_errors" \
    "$native_shadow_command_errors"
} > "$OUT_PATH"

cat "$OUT_PATH"
