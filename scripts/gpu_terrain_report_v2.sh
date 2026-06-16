#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
LOG_DIR="${1:-"$ROOT_DIR/logs/gpu_terrain_upload_pressure_smoke"}"
case "$LOG_DIR" in
  /*) ;;
  *) LOG_DIR="$ROOT_DIR/$LOG_DIR" ;;
esac
OUT_DIR="${2:-"$LOG_DIR"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

SUMMARY_PATH="$OUT_DIR/gpu-terrain-report-v2-summary.txt"
REPORT_PATH="$OUT_DIR/gpu-terrain-report-v2.txt"
LEGACY_REPORT_PATH="${RUMPELMC_GPU_REPORT_V2_LEGACY_REPORT:-"$OUT_DIR/gpu-terrain-report-v2-legacy.txt"}"
case "$LEGACY_REPORT_PATH" in
  /*) ;;
  *) LEGACY_REPORT_PATH="$ROOT_DIR/$LEGACY_REPORT_PATH" ;;
esac
SCOPED_SUMMARY="${RUMPELMC_GPU_REPORT_V2_SCOPED_SUMMARY:-}"
RESOURCE_LIFECYCLE_SUMMARY="${RUMPELMC_GPU_REPORT_V2_RESOURCE_LIFECYCLE_SUMMARY:-"$ROOT_DIR/logs/gpu_terrain_upload_pressure_smoke/gpu-resource-lifecycle-audit-summary.txt"}"
MEMORY_BUDGET_SUMMARY="${RUMPELMC_GPU_REPORT_V2_MEMORY_BUDGET_SUMMARY:-"$ROOT_DIR/logs/gpu_terrain_memory_budget_current/gpu-terrain-memory-budget-summary.txt"}"
CHUNK_BOUNDARY_SUMMARY="${RUMPELMC_GPU_REPORT_V2_CHUNK_BOUNDARY_SUMMARY:-"$ROOT_DIR/logs/gpu_terrain_chunk_boundary_stress_current/chunk-boundary-stress-summary.txt"}"

mkdir -p "$OUT_DIR"

fail() {
  echo "gpu_terrain_report_v2: $*" >&2
  exit 1
}

relative_path() {
  path="$1"
  case "$path" in
    "$ROOT_DIR"/*) printf '%s\n' "${path#$ROOT_DIR/}" ;;
    *) printf '%s\n' "$path" ;;
  esac
}

latest_file() {
  name="$1"
  latest_path=""
  latest_mtime=0
  for path in $(find "$LOG_DIR" -name "$name" -type f -print); do
    mtime="$(stat -f '%m' "$path" 2>/dev/null || stat -c '%Y' "$path" 2>/dev/null || printf '0')"
    if [ "$mtime" -gt "$latest_mtime" ]; then
      latest_mtime="$mtime"
      latest_path="$path"
    fi
  done
  printf '%s\n' "$latest_path"
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

field_or_na() {
  key="$1"
  path="$2"
  value="$(field_metric "$key" "$path")"
  if [ -n "$value" ]; then
    printf '%s\n' "$value"
  else
    printf 'n/a\n'
  fi
}

field_or_na_first() {
  path="$1"
  shift
  for key in "$@"; do
    value="$(field_metric "$key" "$path")"
    if [ -n "$value" ]; then
      printf '%s\n' "$value"
      return
    fi
  done
  printf 'n/a\n'
}

report_metric_value() {
  label="$1"
  awk -v label="$label" '
    index($0, "- " label ": `") == 1 {
      split($0, parts, "`")
      print parts[4]
      exit
    }
  ' "$LEGACY_REPORT_PATH"
}

report_metric_or_na() {
  label="$1"
  value="$(report_metric_value "$label")"
  if [ -n "$value" ]; then
    printf '%s\n' "$value"
  else
    printf 'n/a\n'
  fi
}

test -d "$LOG_DIR" || fail "missing log dir $LOG_DIR"
if [ -z "$SCOPED_SUMMARY" ]; then
  for candidate in \
    "$LOG_DIR/gpu-upload-pressure-summary.txt" \
    "$LOG_DIR/gpu-terrain-memory-budget-summary.txt" \
    "$LOG_DIR/gpu-resource-lifecycle-audit-summary.txt" \
    "$LOG_DIR/fill-stress-summary.txt"; do
    if [ -s "$candidate" ]; then
      SCOPED_SUMMARY="$candidate"
      break
    fi
  done
fi
if [ -z "$SCOPED_SUMMARY" ]; then
  SCOPED_SUMMARY="$(latest_file movement-stress-summary.txt)"
fi
test -s "$SCOPED_SUMMARY" || fail "missing scoped summary; set RUMPELMC_GPU_REPORT_V2_SCOPED_SUMMARY"
test -s "$RESOURCE_LIFECYCLE_SUMMARY" || fail "missing resource lifecycle summary $RESOURCE_LIFECYCLE_SUMMARY"
test -s "$MEMORY_BUDGET_SUMMARY" || fail "missing memory budget summary $MEMORY_BUDGET_SUMMARY"
test -s "$CHUNK_BOUNDARY_SUMMARY" || fail "missing chunk-boundary summary $CHUNK_BOUNDARY_SUMMARY"

sh "$ROOT_DIR/scripts/gpu_terrain_report.sh" "$LOG_DIR" "$LEGACY_REPORT_PATH" >/dev/null
test -s "$LEGACY_REPORT_PATH" || fail "missing legacy report $(relative_path "$LEGACY_REPORT_PATH")"
if grep -q "No error patterns found in summary and marker files." "$LEGACY_REPORT_PATH"; then
  legacy_error_scan="clean"
else
  legacy_error_scan="dirty"
fi

scoped_status="$(field_or_na status "$SCOPED_SUMMARY")"
resource_status="$(field_or_na resource_lifecycle_audit_status "$RESOURCE_LIFECYCLE_SUMMARY")"
memory_status="$(field_or_na status "$MEMORY_BUDGET_SUMMARY")"
chunk_boundary_status="$(field_or_na status "$CHUNK_BOUNDARY_SUMMARY")"
scoped_gpu_upload_fail="$(field_or_na gpu_upload_fail "$SCOPED_SUMMARY")"
scoped_gpu_upload_fail_capacity="$(field_or_na gpu_upload_fail_capacity "$SCOPED_SUMMARY")"
scoped_gpu_upload_fail_fragmented="$(field_or_na gpu_upload_fail_fragmented "$SCOPED_SUMMARY")"
scoped_effective_draws="$(field_or_na max_gpu_effective_draws "$SCOPED_SUMMARY")"
scoped_faces="$(field_or_na max_gpu_faces "$SCOPED_SUMMARY")"
scoped_terrain_queue_ms="$(field_or_na max_terrain_queue_ms "$SCOPED_SUMMARY")"
scoped_transparent_blocks="$(field_or_na transparent_blocks "$SCOPED_SUMMARY")"
scoped_transparent_faces="$(field_or_na transparent_faces "$SCOPED_SUMMARY")"
scoped_transparent_draws="$(field_or_na transparent_draws "$SCOPED_SUMMARY")"
scoped_transparent_subchunks="$(field_or_na transparent_subchunks "$SCOPED_SUMMARY")"
scoped_transparent_cutout_uploads="$(field_or_na_first "$SCOPED_SUMMARY" transparent_cutout_uploads max_transparent_cutout_uploads)"
scoped_transparent_cutout_upload_bytes="$(field_or_na_first "$SCOPED_SUMMARY" transparent_cutout_upload_bytes max_transparent_cutout_upload_bytes)"
scoped_transparent_cutout_upload_faces="$(field_or_na_first "$SCOPED_SUMMARY" transparent_cutout_upload_faces max_transparent_cutout_upload_faces)"
scoped_transparent_cutout_upload_face_bytes="$(field_or_na_first "$SCOPED_SUMMARY" transparent_cutout_upload_face_bytes max_transparent_cutout_upload_face_bytes)"
scoped_transparent_sort_policy="$(field_or_na transparent_sort_policy "$SCOPED_SUMMARY")"
scoped_transparent_sort_active="$(field_or_na_first "$SCOPED_SUMMARY" transparent_sort_active max_transparent_sort_active)"
scoped_transparent_sort_keys="$(field_or_na_first "$SCOPED_SUMMARY" transparent_sort_keys max_transparent_sort_keys)"
scoped_transparent_sort_ms="$(field_or_na_first "$SCOPED_SUMMARY" transparent_sort_ms max_transparent_sort_ms)"
scoped_transparent_build_cost_source="$(field_or_na transparent_build_cost_source "$SCOPED_SUMMARY")"
scoped_transparent_build_faces="$(field_or_na_first "$SCOPED_SUMMARY" transparent_build_faces max_transparent_build_faces)"
scoped_transparent_build_subchunks="$(field_or_na_first "$SCOPED_SUMMARY" transparent_build_subchunks max_transparent_build_subchunks)"
scoped_transparent_build_envelope_ms="$(field_or_na_first "$SCOPED_SUMMARY" transparent_build_envelope_ms max_transparent_build_envelope_ms)"
scoped_transparent_build_uploads="$(field_or_na_first "$SCOPED_SUMMARY" transparent_build_uploads max_transparent_build_uploads)"
scoped_transparent_build_upload_bytes="$(field_or_na_first "$SCOPED_SUMMARY" transparent_build_upload_bytes max_transparent_build_upload_bytes)"
scoped_transparent_build_upload_faces="$(field_or_na_first "$SCOPED_SUMMARY" transparent_build_upload_faces max_transparent_build_upload_faces)"
scoped_transparent_build_upload_face_bytes="$(field_or_na_first "$SCOPED_SUMMARY" transparent_build_upload_face_bytes max_transparent_build_upload_face_bytes)"

historical_gpu_draws="$(report_metric_or_na 'max `gpu_draws`')"
historical_effective_draws="$(report_metric_or_na 'max `gpu_effective_draws`')"
historical_faces="$(report_metric_or_na 'max `gpu_faces`')"
historical_draw_cmd_occupancy="$(report_metric_or_na 'max `gpu_draw_cmd_occupancy_pct`')"
historical_upload_fail="$(report_metric_or_na 'sum `gpu_upload_fail`')"
historical_fragmentation="$(report_metric_or_na 'max `gpu_fragmentation_pct`')"
historical_terrain_queue_ms="$(report_metric_or_na 'max `terrain_queue_max_ms`')"
historical_transparent_blocks="$(report_metric_or_na 'max `transparent_blocks`')"
historical_transparent_faces="$(report_metric_or_na 'max `transparent_faces`')"
historical_transparent_draws="$(report_metric_or_na 'max `transparent_draws`')"
historical_transparent_subchunks="$(report_metric_or_na 'max `transparent_subchunks`')"
historical_transparent_cutout_uploads="$(report_metric_or_na 'max `transparent_cutout_uploads`')"
historical_transparent_cutout_upload_bytes="$(report_metric_or_na 'max `transparent_cutout_upload_bytes`')"
historical_transparent_cutout_upload_faces="$(report_metric_or_na 'max `transparent_cutout_upload_faces`')"
historical_transparent_cutout_upload_face_bytes="$(report_metric_or_na 'max `transparent_cutout_upload_face_bytes`')"
historical_transparent_sort_policy="$(report_metric_or_na 'latest `transparent_sort_policy`')"
historical_transparent_sort_active="$(report_metric_or_na 'max `transparent_sort_active`')"
historical_transparent_sort_keys="$(report_metric_or_na 'max `transparent_sort_keys`')"
historical_transparent_sort_ms="$(report_metric_or_na 'max `transparent_sort_ms`')"
historical_transparent_build_cost_source="$(report_metric_or_na 'latest `transparent_build_cost_source`')"
historical_transparent_build_faces="$(report_metric_or_na 'max `transparent_build_faces`')"
historical_transparent_build_subchunks="$(report_metric_or_na 'max `transparent_build_subchunks`')"
historical_transparent_build_envelope_ms="$(report_metric_or_na 'max `transparent_build_envelope_ms`')"
historical_transparent_build_uploads="$(report_metric_or_na 'max `transparent_build_uploads`')"
historical_transparent_build_upload_bytes="$(report_metric_or_na 'max `transparent_build_upload_bytes`')"
historical_transparent_build_upload_faces="$(report_metric_or_na 'max `transparent_build_upload_faces`')"
historical_transparent_build_upload_face_bytes="$(report_metric_or_na 'max `transparent_build_upload_face_bytes`')"
warning_frame_p95_ms="$(report_metric_or_na 'max `frame_p95_ms`')"
warning_fps_p05="$(report_metric_or_na 'max `fps_p05`')"
warning_gpu_us="$(report_metric_or_na 'max `gpu_compositor_gpu_max_us`')"

status="pass"
reason="ok"
if [ "$legacy_error_scan" != "clean" ]; then
  status="fail"
  reason="legacy_error_scan_dirty"
elif [ "$resource_status" != "pass" ] || [ "$memory_status" != "pass" ] || [ "$chunk_boundary_status" != "pass" ]; then
  status="fail"
  reason="gate_summary_failed"
elif [ "$scoped_status" != "pass" ] && [ "$scoped_status" != "deferred" ]; then
  status="fail"
  reason="scoped_status_failed"
fi

{
  printf 'gpu_terrain_report_v2 status=%s reason=%s scoped_status=%s resource_status=%s memory_status=%s chunk_boundary_status=%s legacy_error_scan=%s scoped_summary=%s resource_summary=%s memory_summary=%s chunk_boundary_summary=%s legacy_report=%s historical_gpu_draws=%s historical_gpu_effective_draws=%s historical_gpu_faces=%s historical_draw_cmd_occupancy_pct=%s historical_gpu_upload_fail=%s historical_gpu_fragmentation_pct=%s historical_transparent_blocks=%s historical_transparent_faces=%s historical_transparent_draws=%s historical_transparent_subchunks=%s historical_transparent_cutout_uploads=%s historical_transparent_cutout_upload_bytes=%s historical_transparent_cutout_upload_faces=%s historical_transparent_cutout_upload_face_bytes=%s historical_transparent_sort_policy=%s historical_transparent_sort_active=%s historical_transparent_sort_keys=%s historical_transparent_sort_ms=%s historical_transparent_build_cost_source=%s historical_transparent_build_faces=%s historical_transparent_build_subchunks=%s historical_transparent_build_envelope_ms=%s historical_transparent_build_uploads=%s historical_transparent_build_upload_bytes=%s historical_transparent_build_upload_faces=%s historical_transparent_build_upload_face_bytes=%s warning_frame_p95_ms=%s warning_fps_p05=%s warning_gpu_compositor_gpu_max_us=%s\n' \
    "$status" \
    "$reason" \
    "$scoped_status" \
    "$resource_status" \
    "$memory_status" \
    "$chunk_boundary_status" \
    "$legacy_error_scan" \
    "$(relative_path "$SCOPED_SUMMARY")" \
    "$(relative_path "$RESOURCE_LIFECYCLE_SUMMARY")" \
    "$(relative_path "$MEMORY_BUDGET_SUMMARY")" \
    "$(relative_path "$CHUNK_BOUNDARY_SUMMARY")" \
    "$(relative_path "$LEGACY_REPORT_PATH")" \
    "$historical_gpu_draws" \
    "$historical_effective_draws" \
    "$historical_faces" \
    "$historical_draw_cmd_occupancy" \
    "$historical_upload_fail" \
    "$historical_fragmentation" \
    "$historical_transparent_blocks" \
    "$historical_transparent_faces" \
    "$historical_transparent_draws" \
    "$historical_transparent_subchunks" \
    "$historical_transparent_cutout_uploads" \
    "$historical_transparent_cutout_upload_bytes" \
    "$historical_transparent_cutout_upload_faces" \
    "$historical_transparent_cutout_upload_face_bytes" \
    "$historical_transparent_sort_policy" \
    "$historical_transparent_sort_active" \
    "$historical_transparent_sort_keys" \
    "$historical_transparent_sort_ms" \
    "$historical_transparent_build_cost_source" \
    "$historical_transparent_build_faces" \
    "$historical_transparent_build_subchunks" \
    "$historical_transparent_build_envelope_ms" \
    "$historical_transparent_build_uploads" \
    "$historical_transparent_build_upload_bytes" \
    "$historical_transparent_build_upload_faces" \
    "$historical_transparent_build_upload_face_bytes" \
    "$warning_frame_p95_ms" \
    "$warning_fps_p05" \
    "$warning_gpu_us"
} > "$SUMMARY_PATH"

{
  printf '# GPU Terrain Report V2\n\n'
  printf 'Log dir: `%s`\n\n' "$(relative_path "$LOG_DIR")"
  printf 'Summary: `%s`\n' "$(relative_path "$SUMMARY_PATH")"
  printf 'Legacy aggregate report: `%s`\n\n' "$(relative_path "$LEGACY_REPORT_PATH")"

  printf '## Fresh Scoped Metrics\n\n'
  printf 'Source: `%s`\n\n' "$(relative_path "$SCOPED_SUMMARY")"
  printf -- '- status: `%s`\n' "$scoped_status"
  printf -- '- max_gpu_effective_draws: `%s`\n' "$scoped_effective_draws"
  printf -- '- max_gpu_faces: `%s`\n' "$scoped_faces"
  printf -- '- max_terrain_queue_ms: `%s`\n' "$scoped_terrain_queue_ms"
  printf -- '- transparent_blocks: `%s`\n' "$scoped_transparent_blocks"
  printf -- '- transparent_faces: `%s`\n' "$scoped_transparent_faces"
  printf -- '- transparent_draws: `%s`\n' "$scoped_transparent_draws"
  printf -- '- transparent_subchunks: `%s`\n' "$scoped_transparent_subchunks"
  printf -- '- transparent_cutout_uploads: `%s`\n' "$scoped_transparent_cutout_uploads"
  printf -- '- transparent_cutout_upload_bytes: `%s`\n' "$scoped_transparent_cutout_upload_bytes"
  printf -- '- transparent_cutout_upload_faces: `%s`\n' "$scoped_transparent_cutout_upload_faces"
  printf -- '- transparent_cutout_upload_face_bytes: `%s`\n' "$scoped_transparent_cutout_upload_face_bytes"
  printf -- '- transparent_sort_policy: `%s`\n' "$scoped_transparent_sort_policy"
  printf -- '- transparent_sort_active: `%s`\n' "$scoped_transparent_sort_active"
  printf -- '- transparent_sort_keys: `%s`\n' "$scoped_transparent_sort_keys"
  printf -- '- transparent_sort_ms: `%s`\n' "$scoped_transparent_sort_ms"
  printf -- '- transparent_build_cost_source: `%s`\n' "$scoped_transparent_build_cost_source"
  printf -- '- transparent_build_faces: `%s`\n' "$scoped_transparent_build_faces"
  printf -- '- transparent_build_subchunks: `%s`\n' "$scoped_transparent_build_subchunks"
  printf -- '- transparent_build_envelope_ms: `%s`\n' "$scoped_transparent_build_envelope_ms"
  printf -- '- transparent_build_uploads: `%s`\n' "$scoped_transparent_build_uploads"
  printf -- '- transparent_build_upload_bytes: `%s`\n' "$scoped_transparent_build_upload_bytes"
  printf -- '- transparent_build_upload_faces: `%s`\n' "$scoped_transparent_build_upload_faces"
  printf -- '- transparent_build_upload_face_bytes: `%s`\n' "$scoped_transparent_build_upload_face_bytes"
  printf -- '- gpu_upload_fail: `%s`\n' "$scoped_gpu_upload_fail"
  printf -- '- gpu_upload_fail_capacity: `%s`\n' "$scoped_gpu_upload_fail_capacity"
  printf -- '- gpu_upload_fail_fragmented: `%s`\n' "$scoped_gpu_upload_fail_fragmented"

  printf '\n## Fail Gates\n\n'
  printf -- '- resource_lifecycle_audit_status: `%s` from `%s`\n' "$resource_status" "$(relative_path "$RESOURCE_LIFECYCLE_SUMMARY")"
  printf -- '- memory_budget_status: `%s` from `%s`\n' "$memory_status" "$(relative_path "$MEMORY_BUDGET_SUMMARY")"
  printf -- '- chunk_boundary_status: `%s` from `%s`\n' "$chunk_boundary_status" "$(relative_path "$CHUNK_BOUNDARY_SUMMARY")"
  printf -- '- legacy_error_scan: `%s`\n' "$legacy_error_scan"
  printf -- '- v2_status: `%s` reason `%s`\n' "$status" "$reason"

  printf '\n## Historical Aggregate Metrics\n\n'
  printf 'Source: legacy `gpu_terrain_report.sh` aggregate over the whole log dir. These are not scoped to one fresh run.\n\n'
  printf -- '- max_gpu_draws: `%s`\n' "$historical_gpu_draws"
  printf -- '- max_gpu_effective_draws: `%s`\n' "$historical_effective_draws"
  printf -- '- max_gpu_faces: `%s`\n' "$historical_faces"
  printf -- '- max_gpu_draw_cmd_occupancy_pct: `%s`\n' "$historical_draw_cmd_occupancy"
  printf -- '- sum_gpu_upload_fail: `%s`\n' "$historical_upload_fail"
  printf -- '- max_gpu_fragmentation_pct: `%s`\n' "$historical_fragmentation"
  printf -- '- max_terrain_queue_ms: `%s`\n' "$historical_terrain_queue_ms"
  printf -- '- max_transparent_blocks: `%s`\n' "$historical_transparent_blocks"
  printf -- '- max_transparent_faces: `%s`\n' "$historical_transparent_faces"
  printf -- '- max_transparent_draws: `%s`\n' "$historical_transparent_draws"
  printf -- '- max_transparent_subchunks: `%s`\n' "$historical_transparent_subchunks"
  printf -- '- max_transparent_cutout_uploads: `%s`\n' "$historical_transparent_cutout_uploads"
  printf -- '- max_transparent_cutout_upload_bytes: `%s`\n' "$historical_transparent_cutout_upload_bytes"
  printf -- '- max_transparent_cutout_upload_faces: `%s`\n' "$historical_transparent_cutout_upload_faces"
  printf -- '- max_transparent_cutout_upload_face_bytes: `%s`\n' "$historical_transparent_cutout_upload_face_bytes"
  printf -- '- latest_transparent_sort_policy: `%s`\n' "$historical_transparent_sort_policy"
  printf -- '- max_transparent_sort_active: `%s`\n' "$historical_transparent_sort_active"
  printf -- '- max_transparent_sort_keys: `%s`\n' "$historical_transparent_sort_keys"
  printf -- '- max_transparent_sort_ms: `%s`\n' "$historical_transparent_sort_ms"
  printf -- '- latest_transparent_build_cost_source: `%s`\n' "$historical_transparent_build_cost_source"
  printf -- '- max_transparent_build_faces: `%s`\n' "$historical_transparent_build_faces"
  printf -- '- max_transparent_build_subchunks: `%s`\n' "$historical_transparent_build_subchunks"
  printf -- '- max_transparent_build_envelope_ms: `%s`\n' "$historical_transparent_build_envelope_ms"
  printf -- '- max_transparent_build_uploads: `%s`\n' "$historical_transparent_build_uploads"
  printf -- '- max_transparent_build_upload_bytes: `%s`\n' "$historical_transparent_build_upload_bytes"
  printf -- '- max_transparent_build_upload_faces: `%s`\n' "$historical_transparent_build_upload_faces"
  printf -- '- max_transparent_build_upload_face_bytes: `%s`\n' "$historical_transparent_build_upload_face_bytes"

  printf '\n## Warning-Only Local Signals\n\n'
  printf 'These remain warning-only on local macOS/Metal unless external profiler evidence validates them.\n\n'
  printf -- '- max_frame_p95_ms: `%s`\n' "$warning_frame_p95_ms"
  printf -- '- max_fps_p05: `%s`\n' "$warning_fps_p05"
  printf -- '- max_gpu_compositor_gpu_max_us: `%s`\n' "$warning_gpu_us"
} > "$REPORT_PATH"

cat "$SUMMARY_PATH"
echo "GPU terrain report V2 artifacts: $OUT_DIR"
if [ "$status" != "pass" ]; then
  exit 1
fi
