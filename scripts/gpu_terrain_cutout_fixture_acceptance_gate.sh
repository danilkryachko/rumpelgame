#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
INPUT_PATH="${1:-"$ROOT_DIR/logs/gpu_transparent_cutout_fixture_scene_smoke_current/transparent-cutout-fixture-scene-smoke-summary.txt"}"
case "$INPUT_PATH" in
  /*) ;;
  *) INPUT_PATH="$ROOT_DIR/$INPUT_PATH" ;;
esac

if [ -d "$INPUT_PATH" ]; then
  RUN_DIR="$INPUT_PATH"
  SCENE_SUMMARY="$RUN_DIR/transparent-cutout-fixture-scene-smoke-summary.txt"
else
  SCENE_SUMMARY="$INPUT_PATH"
  RUN_DIR="$(dirname -- "$SCENE_SUMMARY")"
fi

OUT_PATH="${2:-"$RUN_DIR/transparent-cutout-fixture-acceptance-summary.txt"}"
case "$OUT_PATH" in
  /*) ;;
  *) OUT_PATH="$ROOT_DIR/$OUT_PATH" ;;
esac

REPORT_PATH="${RUMPELMC_CUTOUT_FIXTURE_ACCEPTANCE_REPORT_PATH:-"$RUN_DIR/gpu-terrain-cutout-fixture-report.txt"}"
case "$REPORT_PATH" in
  /*) ;;
  *) REPORT_PATH="$ROOT_DIR/$REPORT_PATH" ;;
esac

RUST_SOURCE="${RUMPELMC_CUTOUT_FIXTURE_RUST_SOURCE:-"$ROOT_DIR/client/rust_ext/src/lib.rs"}"
GPU_TERRAIN_SOURCE="${RUMPELMC_CUTOUT_FIXTURE_GPU_TERRAIN_SOURCE:-"$ROOT_DIR/client/rust_ext/src/gpu_terrain.rs"}"
SHADER_SOURCE="${RUMPELMC_CUTOUT_FIXTURE_SHADER_SOURCE:-"$ROOT_DIR/client/shaders/gpu_terrain_render.glsl"}"
DESIGN_DOC="${RUMPELMC_CUTOUT_FIXTURE_DESIGN_DOC:-"$ROOT_DIR/docs/GPU_TRANSPARENT_PATH.md"}"

fail() {
  echo "gpu_terrain_cutout_fixture_acceptance_gate: $*" >&2
  exit 1
}

relative_path() {
  path="$1"
  case "$path" in
    "$ROOT_DIR"/*) printf '%s\n' "${path#$ROOT_DIR/}" ;;
    *) printf '%s\n' "$path" ;;
  esac
}

line_token() {
  key="$1"
  line="$2"
  printf '%s\n' "$line" | awk -v key="$key" '
    BEGIN { prefix = key "=" }
    {
      for (i = 1; i <= NF; i++) {
        if (index($i, prefix) == 1) {
          print substr($i, length(prefix) + 1)
          exit
        }
      }
    }
  '
}

required_line() {
  file_path="$1"
  pattern="$2"
  line="$(grep -F -- "$pattern" "$file_path" || true)"
  line="$(printf '%s\n' "$line" | sed -n '1p')"
  test -n "$line" || fail "missing line in $(relative_path "$file_path"): $pattern"
  printf '%s\n' "$line"
}

required_token() {
  key="$1"
  line="$2"
  row_label="$3"
  value="$(line_token "$key" "$line")"
  test -n "$value" || fail "missing $key in $row_label row: $line"
  printf '%s\n' "$value"
}

require_metric_eq() {
  key="$1"
  actual="$2"
  expected="$3"
  test "$actual" = "$expected" || fail "$key=$actual, expected $expected"
}

require_metric_ge() {
  key="$1"
  actual="$2"
  min_value="$3"
  case "$actual" in
    ''|*[!0-9]*) fail "$key=$actual is not an integer" ;;
  esac
  if [ "$actual" -lt "$min_value" ]; then
    fail "$key=$actual is below $min_value"
  fi
}

require_source_token() {
  file_path="$1"
  token="$2"
  test -s "$file_path" || fail "missing required source $(relative_path "$file_path")"
  grep -Fq "$token" "$file_path" || fail "missing token '$token' in $(relative_path "$file_path")"
}

test -s "$SCENE_SUMMARY" || fail "missing cutout fixture scene summary $(relative_path "$SCENE_SUMMARY")"
mkdir -p "$(dirname -- "$OUT_PATH")"

scene_line="$(required_line "$SCENE_SUMMARY" "summary transparent_cutout_fixture_scene_smoke_status=pass")"
scene_status="$(required_token transparent_cutout_fixture_scene_smoke_status "$scene_line" "cutout fixture scene")"
cutout_fixture="$(required_token cutout_fixture "$scene_line" "cutout fixture scene")"
cutout_fixture_roles="$(required_token cutout_fixture_roles "$scene_line" "cutout fixture scene")"
cutout_fixture_blocks="$(required_token cutout_fixture_blocks "$scene_line" "cutout fixture scene")"
cutout_fixture_leaf_blocks="$(required_token cutout_fixture_leaf_blocks "$scene_line" "cutout fixture scene")"
cutout_fixture_opaque_blocks="$(required_token cutout_fixture_opaque_blocks "$scene_line" "cutout fixture scene")"
cutout_fixture_dirty_observed="$(required_token cutout_fixture_dirty_observed "$scene_line" "cutout fixture scene")"
cutout_fixture_collision_hits="$(required_token cutout_fixture_collision_hits "$scene_line" "cutout fixture scene")"
cutout_fixture_collision_misses="$(required_token cutout_fixture_collision_misses "$scene_line" "cutout fixture scene")"
cutout_fixture_occlusion_probe_hit="$(required_token cutout_fixture_occlusion_probe_hit "$scene_line" "cutout fixture scene")"
cutout_fixture_queue_drained="$(required_token cutout_fixture_queue_drained "$scene_line" "cutout fixture scene")"
cutout_fixture_adjacent_pair_blocks="$(required_token cutout_fixture_adjacent_pair_blocks "$scene_line" "cutout fixture scene")"
cutout_fixture_adjacent_pair_block_id="$(required_token cutout_fixture_adjacent_pair_block_id "$scene_line" "cutout fixture scene")"
cutout_fixture_adjacent_pair_same_material="$(required_token cutout_fixture_adjacent_pair_same_material "$scene_line" "cutout fixture scene")"
cutout_fixture_adjacent_pair_neighbor="$(required_token cutout_fixture_adjacent_pair_neighbor "$scene_line" "cutout fixture scene")"
cutout_fixture_adjacent_pair_collision_hits="$(required_token cutout_fixture_adjacent_pair_collision_hits "$scene_line" "cutout fixture scene")"
transparent_requested="$(required_token transparent_requested "$scene_line" "cutout fixture scene")"
transparent_active="$(required_token transparent_active "$scene_line" "cutout fixture scene")"
transparent_fallback="$(required_token transparent_fallback "$scene_line" "cutout fixture scene")"
transparent_blocks="$(required_token transparent_blocks "$scene_line" "cutout fixture scene")"
transparent_faces="$(required_token transparent_faces "$scene_line" "cutout fixture scene")"
transparent_draws="$(required_token transparent_draws "$scene_line" "cutout fixture scene")"
transparent_subchunks="$(required_token transparent_subchunks "$scene_line" "cutout fixture scene")"
transparent_cutout_uploads="$(required_token transparent_cutout_uploads "$scene_line" "cutout fixture scene")"
transparent_cutout_upload_bytes="$(required_token transparent_cutout_upload_bytes "$scene_line" "cutout fixture scene")"
transparent_cutout_upload_faces="$(required_token transparent_cutout_upload_faces "$scene_line" "cutout fixture scene")"
transparent_cutout_upload_face_bytes="$(required_token transparent_cutout_upload_face_bytes "$scene_line" "cutout fixture scene")"
gpu_upload_fail="$(required_token gpu_upload_fail "$scene_line" "cutout fixture scene")"

require_metric_eq scene_status "$scene_status" pass
require_metric_eq cutout_fixture "$cutout_fixture" roles
require_metric_eq cutout_fixture_roles "$cutout_fixture_roles" 5
require_metric_eq cutout_fixture_blocks "$cutout_fixture_blocks" 5
require_metric_eq cutout_fixture_leaf_blocks "$cutout_fixture_leaf_blocks" 4
require_metric_eq cutout_fixture_opaque_blocks "$cutout_fixture_opaque_blocks" 1
require_metric_eq cutout_fixture_dirty_observed "$cutout_fixture_dirty_observed" 1
require_metric_eq cutout_fixture_collision_hits "$cutout_fixture_collision_hits" 5
require_metric_eq cutout_fixture_collision_misses "$cutout_fixture_collision_misses" 0
require_metric_eq cutout_fixture_occlusion_probe_hit "$cutout_fixture_occlusion_probe_hit" 1
require_metric_eq cutout_fixture_queue_drained "$cutout_fixture_queue_drained" 1
require_metric_eq cutout_fixture_adjacent_pair_blocks "$cutout_fixture_adjacent_pair_blocks" 2
require_metric_eq cutout_fixture_adjacent_pair_block_id "$cutout_fixture_adjacent_pair_block_id" 5
require_metric_eq cutout_fixture_adjacent_pair_same_material "$cutout_fixture_adjacent_pair_same_material" 1
require_metric_eq cutout_fixture_adjacent_pair_neighbor "$cutout_fixture_adjacent_pair_neighbor" 1
require_metric_eq cutout_fixture_adjacent_pair_collision_hits "$cutout_fixture_adjacent_pair_collision_hits" 2
require_metric_eq transparent_requested "$transparent_requested" 1
require_metric_eq transparent_active "$transparent_active" 1
require_metric_eq transparent_fallback "$transparent_fallback" 0
require_metric_eq transparent_blocks "$transparent_blocks" 4
require_metric_eq transparent_faces "$transparent_faces" 17
require_metric_eq transparent_draws "$transparent_draws" 2
require_metric_eq transparent_subchunks "$transparent_subchunks" 2
require_metric_ge transparent_cutout_uploads "$transparent_cutout_uploads" 1
require_metric_ge transparent_cutout_upload_bytes "$transparent_cutout_upload_bytes" 1
require_metric_ge transparent_cutout_upload_faces "$transparent_cutout_upload_faces" 17
require_metric_ge transparent_cutout_upload_face_bytes "$transparent_cutout_upload_face_bytes" 272
if [ "$transparent_cutout_upload_bytes" -lt "$transparent_cutout_upload_face_bytes" ]; then
  fail "transparent_cutout_upload_bytes=$transparent_cutout_upload_bytes is below transparent_cutout_upload_face_bytes=$transparent_cutout_upload_face_bytes"
fi
require_metric_eq gpu_upload_fail "$gpu_upload_fail" 0

require_source_token "$RUST_SOURCE" "const GPU_TERRAIN_TRANSPARENT_IMPLEMENTED: bool = false;"
require_source_token "$RUST_SOURCE" "const GPU_TERRAIN_CUTOUT_PROTOTYPE_IMPLEMENTED: bool = true;"
require_source_token "$GPU_TERRAIN_SOURCE" "fn cutout_prototype_keeps_same_material_adjacent_seam_faces_visible()"
require_source_token "$GPU_TERRAIN_SOURCE" "assert_eq!(cutout_batch.face_count(), 8);"
require_source_token "$GPU_TERRAIN_SOURCE" "assert_eq!(cutout_batch.cutout_face_count(), 8);"
require_source_token "$GPU_TERRAIN_SOURCE" "pub fn cutout_byte_len(&self) -> usize"
require_source_token "$SHADER_SOURCE" "PACKED_FACE_CUTOUT_ALPHA_TEST"
require_source_token "$SHADER_SOURCE" "CUTOUT_ALPHA_THRESHOLD"
require_source_token "$SHADER_SOURCE" "discard;"
require_source_token "$DESIGN_DOC" "There is no alpha blending, no transparent pass, and no transparent sorting in this slice."

tmp_summary="$OUT_PATH.tmp"
trap 'rm -f "$tmp_summary"' EXIT HUP INT TERM
{
  printf 'GPU terrain cutout fixture acceptance\n'
  printf 'scene_summary=%s\n' "$(relative_path "$SCENE_SUMMARY")"
  printf 'report=%s\n' "$(relative_path "$REPORT_PATH")"
  printf 'runtime_contract=default_off_cutout_only\n'
  printf 'implementation_gate=false\n'
  printf 'blended_transparency_status=deferred\n'
  printf 'split_buffers_status=deferred\n'
  printf 'transparent_sorting_status=deferred\n'
  printf 'same_material_seam_policy=cutout_pair_visible_faces\n'
  printf 'default_runtime_change_allowed=0\n'
  printf 'requires_external_profiler_before_default=1\n'
  printf 'requires_mac_windows_validation=1\n'
  printf 'summary transparent_cutout_fixture_acceptance_status=pass scene_smoke_status=pass runtime_contract=default_off_cutout_only cutout_fixture=%s cutout_fixture_roles=%s cutout_fixture_blocks=%s cutout_fixture_leaf_blocks=%s cutout_fixture_opaque_blocks=%s cutout_fixture_collision_hits=%s cutout_fixture_occlusion_probe_hit=%s cutout_fixture_adjacent_pair_blocks=%s cutout_fixture_adjacent_pair_block_id=%s cutout_fixture_adjacent_pair_same_material=%s cutout_fixture_adjacent_pair_neighbor=%s cutout_fixture_adjacent_pair_collision_hits=%s same_material_seam_policy=cutout_pair_visible_faces transparent_requested=%s transparent_active=%s transparent_fallback=%s transparent_blocks=%s transparent_faces=%s transparent_draws=%s transparent_subchunks=%s transparent_cutout_uploads=%s transparent_cutout_upload_bytes=%s transparent_cutout_upload_faces=%s transparent_cutout_upload_face_bytes=%s gpu_upload_fail=%s default_runtime_change_allowed=0 requires_external_profiler_before_default=1 requires_mac_windows_validation=1 report=%s scene_summary=%s\n' \
    "$cutout_fixture" \
    "$cutout_fixture_roles" \
    "$cutout_fixture_blocks" \
    "$cutout_fixture_leaf_blocks" \
    "$cutout_fixture_opaque_blocks" \
    "$cutout_fixture_collision_hits" \
    "$cutout_fixture_occlusion_probe_hit" \
    "$cutout_fixture_adjacent_pair_blocks" \
    "$cutout_fixture_adjacent_pair_block_id" \
    "$cutout_fixture_adjacent_pair_same_material" \
    "$cutout_fixture_adjacent_pair_neighbor" \
    "$cutout_fixture_adjacent_pair_collision_hits" \
    "$transparent_requested" \
    "$transparent_active" \
    "$transparent_fallback" \
    "$transparent_blocks" \
    "$transparent_faces" \
    "$transparent_draws" \
    "$transparent_subchunks" \
    "$transparent_cutout_uploads" \
    "$transparent_cutout_upload_bytes" \
    "$transparent_cutout_upload_faces" \
    "$transparent_cutout_upload_face_bytes" \
    "$gpu_upload_fail" \
    "$(relative_path "$REPORT_PATH")" \
    "$(relative_path "$SCENE_SUMMARY")"
  printf 'summary transparent_cutout_seam_culling_status=pass runtime_contract=default_off_cutout_only adjacent_pair_blocks=%s adjacent_pair_block_id=%s adjacent_pair_same_material=%s adjacent_pair_neighbor=%s adjacent_pair_collision_hits=%s transparent_faces=%s transparent_draws=%s transparent_subchunks=%s transparent_cutout_uploads=%s transparent_cutout_upload_bytes=%s transparent_cutout_upload_faces=%s transparent_cutout_upload_face_bytes=%s same_material_seam_policy=cutout_pair_visible_faces default_runtime_change_allowed=0 requires_external_profiler_before_default=1 requires_mac_windows_validation=1\n' \
    "$cutout_fixture_adjacent_pair_blocks" \
    "$cutout_fixture_adjacent_pair_block_id" \
    "$cutout_fixture_adjacent_pair_same_material" \
    "$cutout_fixture_adjacent_pair_neighbor" \
    "$cutout_fixture_adjacent_pair_collision_hits" \
    "$transparent_faces" \
    "$transparent_draws" \
    "$transparent_subchunks" \
    "$transparent_cutout_uploads" \
    "$transparent_cutout_upload_bytes" \
    "$transparent_cutout_upload_faces" \
    "$transparent_cutout_upload_face_bytes"
} > "$tmp_summary"
mv "$tmp_summary" "$OUT_PATH"

sh "$ROOT_DIR/scripts/gpu_terrain_report.sh" "$RUN_DIR" "$REPORT_PATH" >/dev/null
required_line "$REPORT_PATH" "## Selected Cutout Fixture Scene Smoke Summary" >/dev/null
required_line "$REPORT_PATH" "## Selected Cutout Fixture Acceptance Summary" >/dev/null
required_line "$REPORT_PATH" "transparent_cutout_fixture_scene_smoke_status=pass" >/dev/null
required_line "$REPORT_PATH" "transparent_cutout_fixture_acceptance_status=pass" >/dev/null
required_line "$REPORT_PATH" "transparent_cutout_seam_culling_status=pass" >/dev/null

cat "$OUT_PATH"
echo "GPU terrain cutout fixture acceptance artifacts: $RUN_DIR"
