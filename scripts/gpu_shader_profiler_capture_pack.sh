#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/gpu_shader_profiler_capture_pack_current"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

SUMMARY_PATH="$OUT_DIR/shader-profiler-capture-pack.txt"
MANIFEST_PATH="$OUT_DIR/shader-profiler-manifest.txt"
FRAGMENT_SOURCE="$OUT_DIR/shader-fragment-source.tmp.glsl"
SHADER_PATH="${RUMPELMC_SHADER_PROFILER_SHADER_PATH:-"$ROOT_DIR/client/shaders/gpu_terrain_render.glsl"}"
MOVEMENT_SUMMARY="${RUMPELMC_SHADER_PROFILER_MOVEMENT_SUMMARY:-"$ROOT_DIR/logs/gpu_shader_atlas_offset_current/movement-stress-summary.txt"}"
MARKER_PATH="${RUMPELMC_SHADER_PROFILER_MARKER_PATH:-"$(dirname -- "$MOVEMENT_SUMMARY")/gpu-terrain-movement-stress.png.txt"}"

fail() {
  echo "gpu_shader_profiler_capture_pack: $*" >&2
  exit 1
}

relative_path() {
  path="$1"
  case "$path" in
    "$ROOT_DIR"/*) printf '%s\n' "${path#$ROOT_DIR/}" ;;
    *) printf '%s\n' "$path" ;;
  esac
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

row_metric() {
  row="$1"
  key="$2"
  path="$3"
  awk -v row="$row" -v key="$key" '
    $1 == row {
      prefix = key "="
      for (i = 2; i <= NF; i++) {
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

require_metric_eq() {
  key="$1"
  path="$2"
  expected="$3"
  value="$(field_metric "$key" "$path")"
  test -n "$value" || fail "missing $key in $path"
  test "$value" = "$expected" || fail "$key expected $expected, got $value in $path"
}

require_metric_positive() {
  key="$1"
  path="$2"
  value="$(field_metric "$key" "$path")"
  test -n "$value" || fail "missing $key in $path"
  awk -v key="$key" -v value="$value" 'BEGIN { if ((value + 0.0) <= 0.0) exit 1 }' \
    || fail "$key must be positive, got $value in $path"
  printf '%s\n' "$value"
}

require_row_metric_eq() {
  row="$1"
  key="$2"
  path="$3"
  expected="$4"
  value="$(row_metric "$row" "$key" "$path")"
  test -n "$value" || fail "missing $row $key in $path"
  test "$value" = "$expected" || fail "$row $key expected $expected, got $value in $path"
}

require_row_metric_positive() {
  row="$1"
  key="$2"
  path="$3"
  value="$(row_metric "$row" "$key" "$path")"
  test -n "$value" || fail "missing $row $key in $path"
  awk -v row="$row" -v key="$key" -v value="$value" 'BEGIN { if ((value + 0.0) <= 0.0) exit 1 }' \
    || fail "$row $key must be positive, got $value in $path"
  printf '%s\n' "$value"
}

require_contains() {
  path="$1"
  token="$2"
  test -s "$path" || fail "missing file $path"
  grep -Fq "$token" "$path" || fail "missing token '$token' in $path"
}

require_not_contains() {
  path="$1"
  token="$2"
  test -s "$path" || fail "missing file $path"
  if grep -Fq "$token" "$path"; then
    fail "unexpected token '$token' in $path"
  fi
}

mkdir -p "$OUT_DIR"
trap 'rm -f "$FRAGMENT_SOURCE"' EXIT

test -s "$SHADER_PATH" || fail "missing shader source $SHADER_PATH"
test -s "$MOVEMENT_SUMMARY" || fail "missing movement summary $MOVEMENT_SUMMARY"
test -s "$MARKER_PATH" || fail "missing movement marker $MARKER_PATH"

awk 'found { print } /^\/\/ -- FRAGMENT --/ { found = 1 }' "$SHADER_PATH" > "$FRAGMENT_SOURCE"
test -s "$FRAGMENT_SOURCE" || fail "failed to extract fragment source from $SHADER_PATH"

require_contains "$SHADER_PATH" 'layout(location = 0) out vec4 uv_tile_out;'
require_contains "$SHADER_PATH" 'layout(location = 1) out vec3 lighting_out;'
require_contains "$SHADER_PATH" 'layout(location = 0) in vec4 uv_tile_in;'
require_contains "$SHADER_PATH" 'layout(location = 1) in vec3 lighting_in;'
require_contains "$SHADER_PATH" 'const uint TRIANGLE_CORNER_INDICES[6]'
require_contains "$SHADER_PATH" 'vec2 atlas_tile_offset(uint tile)'
require_contains "$SHADER_PATH" 'uv_tile_out = vec4(face_uv(face_idx, corner_idx, extent), atlas_tile_offset(tile));'
require_contains "$SHADER_PATH" 'int(low & 32767u) - int(low & 32768u)'
require_contains "$SHADER_PATH" 'vec3 direction_to_light = terrain_push.light_direction_ambient.xyz;'
require_contains "$SHADER_PATH" 'return vec3(ambient) + light_color * diffuse * light_energy;'
require_contains "$FRAGMENT_SOURCE" 'vec2 atlas_uv(vec4 tile_uv_offset)'
require_contains "$FRAGMENT_SOURCE" 'vec2 tiled_uv = fract(tile_uv_offset.xy);'
require_not_contains "$FRAGMENT_SOURCE" 'mod('
require_not_contains "$FRAGMENT_SOURCE" 'floor('
require_not_contains "$FRAGMENT_SOURCE" 'terrain_push.atlas_layout.z'
require_not_contains "$SHADER_PATH" 'normalize(terrain_push.light_direction_ambient.xyz)'
require_not_contains "$SHADER_PATH" 'if (low >= 32768u)'
require_not_contains "$SHADER_PATH" 'uint corner_map[6]'

require_metric_eq smoke_err "$MARKER_PATH" "0"
require_metric_eq gpu_upload_fail "$MARKER_PATH" "0"
require_metric_eq save_err "$MARKER_PATH" "0"
terrain_samples="$(require_metric_positive terrain_samples "$MARKER_PATH")"
terrain_color_buckets="$(require_metric_positive terrain_color_buckets "$MARKER_PATH")"
gpu_effective_draws="$(require_metric_positive gpu_effective_draws "$MARKER_PATH")"
gpu_faces="$(require_metric_positive gpu_faces "$MARKER_PATH")"
require_row_metric_eq movement_terrain_queue budget_status "$MOVEMENT_SUMMARY" "pass"
terrain_queue_max_ms="$(require_row_metric_positive movement_terrain_queue max_ms "$MOVEMENT_SUMMARY")"
process_wall_p95_ms="$(require_row_metric_positive movement_terrain_queue process_wall_p95_ms "$MOVEMENT_SUMMARY")"
gpu_compositor_submit_max_ms="$(require_row_metric_positive movement_terrain_queue gpu_compositor_submit_max_ms "$MOVEMENT_SUMMARY")"
gpu_compositor_submit_max_parts_ms="$(row_metric movement_terrain_queue gpu_compositor_submit_max_parts_ms "$MOVEMENT_SUMMARY")"
test -n "$gpu_compositor_submit_max_parts_ms" || fail "missing compositor submit parts in $MOVEMENT_SUMMARY"

{
  printf 'shader_profiler_capture_pack status=pass reason=ready_for_external_profiler external_profile_status=pending_external_profiler capture_pack_status=pending_external_profiler source_summary=%s marker=%s shader=%s manifest=%s terrain_samples=%s terrain_color_buckets=%s gpu_effective_draws=%s gpu_faces=%s terrain_queue_max_ms=%s process_wall_p95_ms=%s gpu_compositor_submit_max_ms=%s gpu_compositor_submit_max_parts_ms=%s\n' \
    "$(relative_path "$MOVEMENT_SUMMARY")" \
    "$(relative_path "$MARKER_PATH")" \
    "$(relative_path "$SHADER_PATH")" \
    "$(relative_path "$MANIFEST_PATH")" \
    "$terrain_samples" \
    "$terrain_color_buckets" \
    "$gpu_effective_draws" \
    "$gpu_faces" \
    "$terrain_queue_max_ms" \
    "$process_wall_p95_ms" \
    "$gpu_compositor_submit_max_ms" \
    "$gpu_compositor_submit_max_parts_ms"
  printf 'shader_contract vertex_tile_offset=1 fragment_tile_index_math=0 branchless_signed_unpack=1 rust_sanitized_lighting=1 global_triangle_corner_indices=1 fragment_repeats_merged_face_uv=1 opaque_alpha=1\n'
  printf 'policy pending_capture_pack_is_not_evidence=1 local_fps_is_warning_only=1 godot_gpu_timestamp_is_warning_only=1 profiler_rows_required_before_claiming_gpu_time=1\n'
  printf 'command_generate_pack=sh scripts/gpu_shader_profiler_capture_pack.sh %s\n' "$(relative_path "$OUT_DIR")"
  printf 'command_shader_contract_test=cargo test --manifest-path client/rust_ext/Cargo.toml render_shader\n'
} > "$SUMMARY_PATH"

{
  printf 'shader_profiler_manifest status=prepared source_summary=%s marker=%s shader=%s\n' \
    "$(relative_path "$MOVEMENT_SUMMARY")" \
    "$(relative_path "$MARKER_PATH")" \
    "$(relative_path "$SHADER_PATH")"
  printf 'row=macos_metal_default priority=1 platform=macos backend=metal profiler_tool=xcode_metal_frame_capture capture_status=pending_external_profiler artifact=external_trace_required metric_targets=shader_time,vertex_stage,fragment_stage,draw_pass_time,counters source_summary=%s marker=%s\n' \
    "$(relative_path "$MOVEMENT_SUMMARY")" \
    "$(relative_path "$MARKER_PATH")"
  printf 'row=windows_gpu_default priority=2 platform=windows backend=vulkan_or_direct3d profiler_tool=pix_renderdoc_or_vendor capture_status=pending_external_profiler artifact=external_trace_required metric_targets=shader_time,occupancy,bandwidth,draw_pass_time,counters source_summary=%s marker=%s\n' \
    "$(relative_path "$MOVEMENT_SUMMARY")" \
    "$(relative_path "$MARKER_PATH")"
  printf 'row=macos_windows_compare priority=3 platform=cross_platform backend=metal_vs_windows_gpu profiler_tool=xcode_vs_pix_renderdoc_or_vendor capture_status=pending_external_profiler artifact=external_trace_required metric_targets=shader_stage_delta,draw_pass_delta,driver_submit_context source_summary=%s marker=%s\n' \
    "$(relative_path "$MOVEMENT_SUMMARY")" \
    "$(relative_path "$MARKER_PATH")"
} > "$MANIFEST_PATH"

cat "$SUMMARY_PATH"
