#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
INPUT_PATH="${1:-"$ROOT_DIR/logs/gpu_transparent_cutout_prototype_current/block-edit-stress-summary.txt"}"
case "$INPUT_PATH" in
  /*) ;;
  *) INPUT_PATH="$ROOT_DIR/$INPUT_PATH" ;;
esac

if [ -d "$INPUT_PATH" ]; then
  RUN_DIR="$INPUT_PATH"
  SMOKE_SUMMARY="$RUN_DIR/block-edit-stress-summary.txt"
else
  SMOKE_SUMMARY="$INPUT_PATH"
  RUN_DIR="$(dirname -- "$SMOKE_SUMMARY")"
fi

OUT_PATH="${2:-"$RUN_DIR/transparent-cutout-prototype-acceptance-summary.txt"}"
case "$OUT_PATH" in
  /*) ;;
  *) OUT_PATH="$ROOT_DIR/$OUT_PATH" ;;
esac

REPORT_LOG_DIR="${RUMPELMC_TRANSPARENT_CUTOUT_PROTOTYPE_REPORT_LOG_DIR:-"$RUN_DIR"}"
case "$REPORT_LOG_DIR" in
  /*) ;;
  *) REPORT_LOG_DIR="$ROOT_DIR/$REPORT_LOG_DIR" ;;
esac

REPORT_PATH="${RUMPELMC_TRANSPARENT_CUTOUT_PROTOTYPE_REPORT_PATH:-"$RUN_DIR/gpu-terrain-cutout-prototype-report.txt"}"
case "$REPORT_PATH" in
  /*) ;;
  *) REPORT_PATH="$ROOT_DIR/$REPORT_PATH" ;;
esac

RUST_SOURCE="${RUMPELMC_TRANSPARENT_CUTOUT_PROTOTYPE_RUST_SOURCE:-"$ROOT_DIR/client/rust_ext/src/lib.rs"}"
SHADER_SOURCE="${RUMPELMC_TRANSPARENT_CUTOUT_PROTOTYPE_SHADER_SOURCE:-"$ROOT_DIR/client/shaders/gpu_terrain_render.glsl"}"
DESIGN_DOC="${RUMPELMC_TRANSPARENT_CUTOUT_PROTOTYPE_DESIGN_DOC:-"$ROOT_DIR/docs/GPU_TRANSPARENT_PATH.md"}"
EXPECTED_ACTION="${RUMPELMC_TRANSPARENT_CUTOUT_PROTOTYPE_ACTION:-place}"
EXPECTED_BLOCK_ID="${RUMPELMC_TRANSPARENT_CUTOUT_PROTOTYPE_BLOCK_ID:-5}"

fail() {
  echo "gpu_terrain_cutout_prototype_acceptance_gate: $*" >&2
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

test -s "$SMOKE_SUMMARY" || fail "missing cutout prototype smoke summary $(relative_path "$SMOKE_SUMMARY")"
test -d "$REPORT_LOG_DIR" || fail "missing report log dir $(relative_path "$REPORT_LOG_DIR")"
mkdir -p "$(dirname -- "$OUT_PATH")"

summary_line="$(required_line "$SMOKE_SUMMARY" "GPU terrain block edit stress summary action=")"
transparent_line="$(required_line "$SMOKE_SUMMARY" "block_edit_transparent transparent_requested=")"

action="$(required_token action "$summary_line" "block-edit summary")"
block_id="$(required_token block_id "$summary_line" "block-edit summary")"
transparent_requested="$(required_token transparent_requested "$transparent_line" "block-edit transparent")"
transparent_active="$(required_token transparent_active "$transparent_line" "block-edit transparent")"
transparent_fallback="$(required_token transparent_fallback "$transparent_line" "block-edit transparent")"
transparent_blocks="$(required_token transparent_blocks "$transparent_line" "block-edit transparent")"
transparent_faces="$(required_token transparent_faces "$transparent_line" "block-edit transparent")"
transparent_draws="$(required_token transparent_draws "$transparent_line" "block-edit transparent")"
transparent_subchunks="$(required_token transparent_subchunks "$transparent_line" "block-edit transparent")"
transparent_cutout_uploads="$(required_token transparent_cutout_uploads "$transparent_line" "block-edit transparent")"
transparent_cutout_upload_bytes="$(required_token transparent_cutout_upload_bytes "$transparent_line" "block-edit transparent")"
transparent_cutout_upload_faces="$(required_token transparent_cutout_upload_faces "$transparent_line" "block-edit transparent")"
transparent_cutout_upload_face_bytes="$(required_token transparent_cutout_upload_face_bytes "$transparent_line" "block-edit transparent")"
transparent_sort_policy="$(required_token transparent_sort_policy "$transparent_line" "block-edit transparent")"
transparent_sort_active="$(required_token transparent_sort_active "$transparent_line" "block-edit transparent")"
transparent_sort_keys="$(required_token transparent_sort_keys "$transparent_line" "block-edit transparent")"
transparent_sort_ms="$(required_token transparent_sort_ms "$transparent_line" "block-edit transparent")"
transparent_build_cost_source="$(required_token transparent_build_cost_source "$transparent_line" "block-edit transparent")"
transparent_build_faces="$(required_token transparent_build_faces "$transparent_line" "block-edit transparent")"
transparent_build_subchunks="$(required_token transparent_build_subchunks "$transparent_line" "block-edit transparent")"
transparent_build_envelope_ms="$(required_token transparent_build_envelope_ms "$transparent_line" "block-edit transparent")"
transparent_build_uploads="$(required_token transparent_build_uploads "$transparent_line" "block-edit transparent")"
transparent_build_upload_bytes="$(required_token transparent_build_upload_bytes "$transparent_line" "block-edit transparent")"
transparent_build_upload_faces="$(required_token transparent_build_upload_faces "$transparent_line" "block-edit transparent")"
transparent_build_upload_face_bytes="$(required_token transparent_build_upload_face_bytes "$transparent_line" "block-edit transparent")"
gpu_upload_fail="$(required_token gpu_upload_fail "$transparent_line" "block-edit transparent")"

require_metric_eq action "$action" "$EXPECTED_ACTION"
require_metric_eq block_id "$block_id" "$EXPECTED_BLOCK_ID"
require_metric_eq transparent_requested "$transparent_requested" 1
require_metric_eq transparent_active "$transparent_active" 1
require_metric_eq transparent_fallback "$transparent_fallback" 0
require_metric_ge transparent_blocks "$transparent_blocks" 1
require_metric_ge transparent_faces "$transparent_faces" 1
require_metric_ge transparent_draws "$transparent_draws" 1
require_metric_ge transparent_subchunks "$transparent_subchunks" 1
require_metric_ge transparent_cutout_uploads "$transparent_cutout_uploads" 1
require_metric_ge transparent_cutout_upload_bytes "$transparent_cutout_upload_bytes" 1
require_metric_ge transparent_cutout_upload_faces "$transparent_cutout_upload_faces" 1
require_metric_ge transparent_cutout_upload_face_bytes "$transparent_cutout_upload_face_bytes" 1
if [ "$transparent_cutout_upload_bytes" -lt "$transparent_cutout_upload_face_bytes" ]; then
  fail "transparent_cutout_upload_bytes=$transparent_cutout_upload_bytes is below transparent_cutout_upload_face_bytes=$transparent_cutout_upload_face_bytes"
fi
require_metric_eq transparent_sort_policy "$transparent_sort_policy" opaque_depth_alpha_test_no_sort
require_metric_eq transparent_sort_active "$transparent_sort_active" 0
require_metric_eq transparent_sort_keys "$transparent_sort_keys" 0
require_metric_eq transparent_sort_ms "$transparent_sort_ms" 0.000
require_metric_eq transparent_build_cost_source "$transparent_build_cost_source" cutout_in_opaque_mesh_phase
require_metric_ge transparent_build_faces "$transparent_build_faces" 1
require_metric_ge transparent_build_subchunks "$transparent_build_subchunks" 1
case "$transparent_build_envelope_ms" in
  ''|*[!0-9.]*)
    fail "transparent_build_envelope_ms=$transparent_build_envelope_ms is not a decimal"
    ;;
esac
require_metric_ge transparent_build_uploads "$transparent_build_uploads" 1
require_metric_ge transparent_build_upload_bytes "$transparent_build_upload_bytes" 1
require_metric_ge transparent_build_upload_faces "$transparent_build_upload_faces" 1
require_metric_ge transparent_build_upload_face_bytes "$transparent_build_upload_face_bytes" 1
if [ "$transparent_build_upload_bytes" -lt "$transparent_build_upload_face_bytes" ]; then
  fail "transparent_build_upload_bytes=$transparent_build_upload_bytes is below transparent_build_upload_face_bytes=$transparent_build_upload_face_bytes"
fi
require_metric_eq gpu_upload_fail "$gpu_upload_fail" 0

require_source_token "$RUST_SOURCE" "const GPU_TERRAIN_TRANSPARENT_IMPLEMENTED: bool = false;"
require_source_token "$RUST_SOURCE" "RUMPELMC_GPU_TERRAIN_CUTOUT_PROTOTYPE"
require_source_token "$RUST_SOURCE" "transparent_cutout_uploads"
require_source_token "$RUST_SOURCE" "opaque_depth_alpha_test_no_sort"
require_source_token "$RUST_SOURCE" "cutout_in_opaque_mesh_phase"
require_source_token "$SHADER_SOURCE" "PACKED_FACE_CUTOUT_ALPHA_TEST"
require_source_token "$SHADER_SOURCE" "CUTOUT_ALPHA_THRESHOLD"
require_source_token "$SHADER_SOURCE" "discard;"
require_source_token "$DESIGN_DOC" "There is no alpha blending, no transparent pass, and no transparent sorting in this slice."

tmp_summary="$OUT_PATH.tmp"
trap 'rm -f "$tmp_summary"' EXIT HUP INT TERM
{
  printf 'GPU terrain cutout prototype acceptance\n'
  printf 'smoke_summary=%s\n' "$(relative_path "$SMOKE_SUMMARY")"
  printf 'report=%s\n' "$(relative_path "$REPORT_PATH")"
  printf 'runtime_contract=default_off_cutout_only\n'
  printf 'implementation_gate=false\n'
  printf 'blended_transparency_status=deferred\n'
  printf 'split_buffers_status=deferred\n'
  printf 'transparent_sorting_status=deferred\n'
  printf 'default_runtime_change_allowed=0\n'
  printf 'requires_external_profiler_before_default=1\n'
  printf 'requires_mac_windows_validation=1\n'
  printf 'action=%s\n' "$action"
  printf 'block_id=%s\n' "$block_id"
  printf 'summary transparent_cutout_prototype_acceptance_status=pass runtime_contract=default_off_cutout_only action=%s block_id=%s transparent_requested=%s transparent_active=%s transparent_fallback=%s transparent_blocks=%s transparent_faces=%s transparent_draws=%s transparent_subchunks=%s transparent_cutout_uploads=%s transparent_cutout_upload_bytes=%s transparent_cutout_upload_faces=%s transparent_cutout_upload_face_bytes=%s transparent_sort_policy=%s transparent_sort_active=%s transparent_sort_keys=%s transparent_sort_ms=%s transparent_build_cost_source=%s transparent_build_faces=%s transparent_build_subchunks=%s transparent_build_envelope_ms=%s transparent_build_uploads=%s transparent_build_upload_bytes=%s transparent_build_upload_faces=%s transparent_build_upload_face_bytes=%s gpu_upload_fail=%s default_runtime_change_allowed=0 report=%s smoke_summary=%s\n' \
    "$action" \
    "$block_id" \
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
    "$transparent_sort_policy" \
    "$transparent_sort_active" \
    "$transparent_sort_keys" \
    "$transparent_sort_ms" \
    "$transparent_build_cost_source" \
    "$transparent_build_faces" \
    "$transparent_build_subchunks" \
    "$transparent_build_envelope_ms" \
    "$transparent_build_uploads" \
    "$transparent_build_upload_bytes" \
    "$transparent_build_upload_faces" \
    "$transparent_build_upload_face_bytes" \
    "$gpu_upload_fail" \
    "$(relative_path "$REPORT_PATH")" \
    "$(relative_path "$SMOKE_SUMMARY")"
} > "$tmp_summary"
mv "$tmp_summary" "$OUT_PATH"

sh "$ROOT_DIR/scripts/gpu_terrain_report.sh" "$REPORT_LOG_DIR" "$REPORT_PATH" >/dev/null
required_line "$REPORT_PATH" "## Selected Transparent Cutout Prototype Acceptance Summary" >/dev/null
required_line "$REPORT_PATH" "Source: \`$OUT_PATH\`" >/dev/null
required_line "$REPORT_PATH" "transparent_cutout_prototype_acceptance_status=pass" >/dev/null

cat "$OUT_PATH"
echo "GPU terrain cutout prototype acceptance artifacts: $RUN_DIR"
