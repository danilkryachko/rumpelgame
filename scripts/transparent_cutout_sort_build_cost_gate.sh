#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/transparent_cutout_sort_build_cost_current"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

SUMMARY_PATH="$OUT_DIR/transparent-cutout-sort-build-cost-summary.txt"
FIXTURE_ACCEPTANCE="${RUMPELMC_TRANSPARENT_CUTOUT_COST_FIXTURE_ACCEPTANCE:-"$ROOT_DIR/logs/gpu_transparent_cutout_fixture_scene_smoke_current/transparent-cutout-fixture-acceptance-summary.txt"}"
PRESSURE_SUMMARY="${RUMPELMC_TRANSPARENT_CUTOUT_COST_PRESSURE_SUMMARY:-"$ROOT_DIR/logs/gpu_terrain_cutout_pressure_load_scaling_current/gpu-terrain-cutout-pressure-load-scaling-summary.txt"}"
REPORT_PATH="${RUMPELMC_TRANSPARENT_CUTOUT_COST_REPORT_PATH:-"$OUT_DIR/gpu-terrain-transparent-cutout-cost-report.txt"}"

case "$FIXTURE_ACCEPTANCE" in
  /*) ;;
  *) FIXTURE_ACCEPTANCE="$ROOT_DIR/$FIXTURE_ACCEPTANCE" ;;
esac
case "$PRESSURE_SUMMARY" in
  /*) ;;
  *) PRESSURE_SUMMARY="$ROOT_DIR/$PRESSURE_SUMMARY" ;;
esac
case "$REPORT_PATH" in
  /*) ;;
  *) REPORT_PATH="$ROOT_DIR/$REPORT_PATH" ;;
esac

mkdir -p "$OUT_DIR"

fail() {
  echo "transparent_cutout_sort_build_cost_gate: $*" >&2
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

require_field() {
  key="$1"
  path="$2"
  value="$(field_metric "$key" "$path")"
  test -n "$value" || fail "missing $key in $(relative_path "$path")"
  printf '%s\n' "$value"
}

require_int_ge() {
  key="$1"
  value="$2"
  min_value="$3"
  case "$value" in
    ''|*[!0-9]*) fail "$key=$value is not an integer" ;;
  esac
  if [ "$value" -lt "$min_value" ]; then
    fail "$key=$value is below $min_value"
  fi
}

require_eq() {
  key="$1"
  value="$2"
  expected="$3"
  test "$value" = "$expected" || fail "$key=$value, expected $expected"
}

test -s "$FIXTURE_ACCEPTANCE" || fail "missing fixture acceptance $(relative_path "$FIXTURE_ACCEPTANCE")"
test -s "$PRESSURE_SUMMARY" || fail "missing cutout pressure summary $(relative_path "$PRESSURE_SUMMARY")"

fixture_status="$(require_field transparent_cutout_fixture_acceptance_status "$FIXTURE_ACCEPTANCE")"
fixture_policy="$(require_field transparent_sort_policy "$FIXTURE_ACCEPTANCE")"
fixture_sort_active="$(require_field transparent_sort_active "$FIXTURE_ACCEPTANCE")"
fixture_sort_keys="$(require_field transparent_sort_keys "$FIXTURE_ACCEPTANCE")"
fixture_sort_ms="$(require_field transparent_sort_ms "$FIXTURE_ACCEPTANCE")"
fixture_build_source="$(require_field transparent_build_cost_source "$FIXTURE_ACCEPTANCE")"
fixture_build_faces="$(require_field transparent_build_faces "$FIXTURE_ACCEPTANCE")"
fixture_build_subchunks="$(require_field transparent_build_subchunks "$FIXTURE_ACCEPTANCE")"
fixture_build_envelope_ms="$(require_field transparent_build_envelope_ms "$FIXTURE_ACCEPTANCE")"
fixture_build_uploads="$(require_field transparent_build_uploads "$FIXTURE_ACCEPTANCE")"
fixture_build_upload_bytes="$(require_field transparent_build_upload_bytes "$FIXTURE_ACCEPTANCE")"
fixture_build_upload_faces="$(require_field transparent_build_upload_faces "$FIXTURE_ACCEPTANCE")"
fixture_build_upload_face_bytes="$(require_field transparent_build_upload_face_bytes "$FIXTURE_ACCEPTANCE")"

pressure_status="$(require_field status "$PRESSURE_SUMMARY")"
pressure_policy="$(require_field transparent_sort_policy "$PRESSURE_SUMMARY")"
pressure_sort_active="$(require_field transparent_sort_active "$PRESSURE_SUMMARY")"
pressure_sort_keys="$(require_field transparent_sort_keys "$PRESSURE_SUMMARY")"
pressure_sort_ms="$(require_field transparent_sort_ms "$PRESSURE_SUMMARY")"
pressure_build_source="$(require_field transparent_build_cost_source "$PRESSURE_SUMMARY")"
pressure_build_faces="$(require_field transparent_build_faces "$PRESSURE_SUMMARY")"
pressure_build_subchunks="$(require_field transparent_build_subchunks "$PRESSURE_SUMMARY")"
pressure_build_envelope_ms="$(require_field transparent_build_envelope_ms "$PRESSURE_SUMMARY")"
pressure_build_uploads="$(require_field transparent_build_uploads "$PRESSURE_SUMMARY")"
pressure_build_upload_bytes="$(require_field transparent_build_upload_bytes "$PRESSURE_SUMMARY")"
pressure_build_upload_faces="$(require_field transparent_build_upload_faces "$PRESSURE_SUMMARY")"
pressure_build_upload_face_bytes="$(require_field transparent_build_upload_face_bytes "$PRESSURE_SUMMARY")"
pressure_transparent_faces="$(require_field transparent_faces "$PRESSURE_SUMMARY")"
pressure_transparent_subchunks="$(require_field transparent_subchunks "$PRESSURE_SUMMARY")"

require_eq fixture_status "$fixture_status" pass
require_eq pressure_status "$pressure_status" pass
require_eq fixture_policy "$fixture_policy" opaque_depth_alpha_test_no_sort
require_eq pressure_policy "$pressure_policy" opaque_depth_alpha_test_no_sort
require_eq fixture_sort_active "$fixture_sort_active" 0
require_eq pressure_sort_active "$pressure_sort_active" 0
require_eq fixture_sort_keys "$fixture_sort_keys" 0
require_eq pressure_sort_keys "$pressure_sort_keys" 0
require_eq fixture_sort_ms "$fixture_sort_ms" 0.000
require_eq pressure_sort_ms "$pressure_sort_ms" 0.000
require_eq fixture_build_source "$fixture_build_source" cutout_in_opaque_mesh_phase
require_eq pressure_build_source "$pressure_build_source" cutout_in_opaque_mesh_phase
require_int_ge fixture_build_faces "$fixture_build_faces" 17
require_int_ge fixture_build_subchunks "$fixture_build_subchunks" 2
require_int_ge fixture_build_uploads "$fixture_build_uploads" 1
require_int_ge fixture_build_upload_bytes "$fixture_build_upload_bytes" 1
require_int_ge fixture_build_upload_faces "$fixture_build_upload_faces" 17
require_int_ge fixture_build_upload_face_bytes "$fixture_build_upload_face_bytes" 272
require_int_ge pressure_build_faces "$pressure_build_faces" "$pressure_transparent_faces"
require_int_ge pressure_build_subchunks "$pressure_build_subchunks" "$pressure_transparent_subchunks"
require_int_ge pressure_build_uploads "$pressure_build_uploads" 1
require_int_ge pressure_build_upload_bytes "$pressure_build_upload_bytes" 1
require_int_ge pressure_build_upload_faces "$pressure_build_upload_faces" 500
require_int_ge pressure_build_upload_face_bytes "$pressure_build_upload_face_bytes" 1
if [ "$fixture_build_upload_bytes" -lt "$fixture_build_upload_face_bytes" ]; then
  fail "fixture transparent build upload payload is smaller than cutout-face bytes"
fi
if [ "$pressure_build_upload_bytes" -lt "$pressure_build_upload_face_bytes" ]; then
  fail "pressure transparent build upload payload is smaller than cutout-face bytes"
fi

case "$fixture_build_envelope_ms" in
  ''|*[!0-9.]*)
    fail "fixture transparent_build_envelope_ms=$fixture_build_envelope_ms is not a decimal"
    ;;
esac
case "$pressure_build_envelope_ms" in
  ''|*[!0-9.]*)
    fail "pressure transparent_build_envelope_ms=$pressure_build_envelope_ms is not a decimal"
    ;;
esac

tmp_summary="$SUMMARY_PATH.tmp"
trap 'rm -f "$tmp_summary"' EXIT HUP INT TERM
printf 'transparent_cutout_sort_build_cost status=pass reason=cutout_sort_zero_build_envelope_tracked runtime_contract=default_off_cutout_only transparent_sort_policy=opaque_depth_alpha_test_no_sort transparent_sort_active=0 transparent_sort_keys=0 transparent_sort_ms=0.000 transparent_build_cost_source=cutout_in_opaque_mesh_phase fixture_build_faces=%s fixture_build_subchunks=%s fixture_build_envelope_ms=%s fixture_build_uploads=%s fixture_build_upload_bytes=%s fixture_build_upload_faces=%s fixture_build_upload_face_bytes=%s pressure_build_faces=%s pressure_build_subchunks=%s pressure_build_envelope_ms=%s pressure_build_uploads=%s pressure_build_upload_bytes=%s pressure_build_upload_faces=%s pressure_build_upload_face_bytes=%s default_runtime_change_allowed=0 requires_external_profiler_before_default=1 requires_mac_windows_validation=1 fixture_acceptance=%s pressure_summary=%s\n' \
  "$fixture_build_faces" \
  "$fixture_build_subchunks" \
  "$fixture_build_envelope_ms" \
  "$fixture_build_uploads" \
  "$fixture_build_upload_bytes" \
  "$fixture_build_upload_faces" \
  "$fixture_build_upload_face_bytes" \
  "$pressure_build_faces" \
  "$pressure_build_subchunks" \
  "$pressure_build_envelope_ms" \
  "$pressure_build_uploads" \
  "$pressure_build_upload_bytes" \
  "$pressure_build_upload_faces" \
  "$pressure_build_upload_face_bytes" \
  "$(relative_path "$FIXTURE_ACCEPTANCE")" \
  "$(relative_path "$PRESSURE_SUMMARY")" > "$tmp_summary"
mv "$tmp_summary" "$SUMMARY_PATH"

sh "$ROOT_DIR/scripts/gpu_terrain_report.sh" "$OUT_DIR" "$REPORT_PATH" >/dev/null
grep -F "transparent_cutout_sort_build_cost status=pass" "$REPORT_PATH" >/dev/null \
  || fail "aggregate report did not surface transparent cutout sort/build cost summary"

cat "$SUMMARY_PATH"
echo "Transparent cutout sort/build cost artifacts: $OUT_DIR"
