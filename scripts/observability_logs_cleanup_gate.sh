#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/observability_logs_cleanup"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

SUMMARY_PATH="$OUT_DIR/observability-logs-cleanup-summary.txt"
INDEX_PATH="$OUT_DIR/observability-artifact-index.txt"
ERROR_SCAN_PATH="$OUT_DIR/observability-error-scan.txt"
CURRENT_SUMMARY_LIST="$OUT_DIR/current-summary-files.txt"
DESIGN_DOC="${RUMPELMC_OBSERVABILITY_DOC:-"$ROOT_DIR/docs/OBSERVABILITY_LOGS_CLEANUP.md"}"
HUD_SOURCE="${RUMPELMC_OBSERVABILITY_HUD_SOURCE:-"$ROOT_DIR/client/hud.gd"}"
TOOLING_SUMMARY="${RUMPELMC_OBSERVABILITY_TOOLING_SUMMARY:-"$ROOT_DIR/logs/tooling_debug_overlay_current/tooling-debug-overlay-summary.txt"}"
GPU_REPORT_FRESHNESS_DIR="${RUMPELMC_OBSERVABILITY_GPU_REPORT_FRESHNESS_DIR:-"$ROOT_DIR/logs/gpu_terrain_report_freshness_current"}"
GPU_REPORT_FRESHNESS_SUMMARY="${RUMPELMC_OBSERVABILITY_GPU_REPORT_FRESHNESS_SUMMARY:-"$GPU_REPORT_FRESHNESS_DIR/gpu-terrain-report-freshness-summary.txt"}"

mkdir -p "$OUT_DIR"

fail() {
  echo "observability_logs_cleanup_gate: $*" >&2
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

require_token() {
  path="$1"
  token="$2"
  test -s "$path" || fail "missing file $path"
  grep -Fq "$token" "$path" || fail "missing token '$token' in $path"
}

test -s "$DESIGN_DOC" || fail "missing design doc $DESIGN_DOC"
test -s "$HUD_SOURCE" || fail "missing HUD source $HUD_SOURCE"
test -s "$TOOLING_SUMMARY" || fail "missing tooling summary $TOOLING_SUMMARY"

for token in \
  'Run ID Contract' \
  'Summary Naming' \
  'Error Scan Policy' \
  'Generated Index' \
  'GPU Report Freshness' \
  'Deferred Work' \
  'Compatibility Rules' \
  'Do not delete old log directories'; do
  require_token "$DESIGN_DOC" "$token"
done

for token in \
  'const RUN_ID_ENV = "RUMPELMC_RUN_ID"' \
  'func observability_run_id() -> String:' \
  'func sanitize_observability_token(value: String) -> String:' \
  'run_id=%s' \
  'overlay=\"%s\"' \
  'perf=\"%s\"'; do
  require_token "$HUD_SOURCE" "$token"
done

tooling_status="$(field_metric status "$TOOLING_SUMMARY")"
tooling_protocol_change="$(field_metric active_protocol_change "$TOOLING_SUMMARY")"
tooling_scene_change="$(field_metric active_scene_resource_change "$TOOLING_SUMMARY")"

if [ "${RUMPELMC_OBSERVABILITY_RUN_GPU_REPORT_FRESHNESS:-1}" = "1" ]; then
  sh "$ROOT_DIR/scripts/gpu_terrain_report_freshness_gate.sh" "$GPU_REPORT_FRESHNESS_DIR" >/dev/null
fi

test -s "$GPU_REPORT_FRESHNESS_SUMMARY" || fail "missing GPU report freshness summary $GPU_REPORT_FRESHNESS_SUMMARY"
gpu_report_status="$(field_metric status "$GPU_REPORT_FRESHNESS_SUMMARY")"
gpu_report_freshness="$(field_metric freshness_status "$GPU_REPORT_FRESHNESS_SUMMARY")"
gpu_report_error_scan="$(field_metric report_error_scan "$GPU_REPORT_FRESHNESS_SUMMARY")"

find "$ROOT_DIR/logs" -maxdepth 3 -path '*current/*summary.txt' -type f | sort > "$CURRENT_SUMMARY_LIST"
summary_count="$(awk 'END { print NR + 0 }' "$CURRENT_SUMMARY_LIST")"
test "$summary_count" -gt 0 || fail "no current summary files found"

: > "$INDEX_PATH"
: > "$ERROR_SCAN_PATH"
bad_status_count=0
bad_name_count=0

while IFS= read -r path; do
  rel_path="${path#"$ROOT_DIR/"}"
  base_name="$(basename "$path")"
  dir_name="$(basename "$(dirname "$path")")"
  root_token="$(awk '{ print $1; exit }' "$path")"
  status_value="$(field_metric status "$path")"
  bytes="$(wc -c < "$path" | tr -d ' ')"

  case "$base_name" in
    *-summary.txt) ;;
    *) bad_name_count=$((bad_name_count + 1)) ;;
  esac

  case "$dir_name" in
    *_current) ;;
    *) bad_name_count=$((bad_name_count + 1)) ;;
  esac

  case "$status_value" in
    pass|deferred) ;;
    *)
      if [ "$path" != "$SUMMARY_PATH" ]; then
        bad_status_count=$((bad_status_count + 1))
      fi
      ;;
  esac

  printf 'artifact path=%s root=%s status=%s bytes=%s\n' "$rel_path" "$root_token" "${status_value:-missing}" "$bytes" >> "$INDEX_PATH"

  grep -nE 'ERROR|SCRIPT ERROR|panic|ObjectDB|leaked|gpu_upload_fail=[1-9][0-9]*|gpu_upload_fail_capacity=[1-9][0-9]*|gpu_upload_fail_fragmented=[1-9][0-9]*' "$path" >> "$ERROR_SCAN_PATH" 2>/dev/null || true
done < "$CURRENT_SUMMARY_LIST"

error_count="$(awk 'END { print NR + 0 }' "$ERROR_SCAN_PATH")"

awk \
  -v tooling_status="${tooling_status:-missing}" \
  -v tooling_protocol_change="${tooling_protocol_change:-1}" \
  -v tooling_scene_change="${tooling_scene_change:-1}" \
  -v summary_count="$summary_count" \
  -v bad_status_count="$bad_status_count" \
  -v bad_name_count="$bad_name_count" \
  -v error_count="$error_count" \
  -v gpu_report_status="${gpu_report_status:-missing}" \
  -v gpu_report_freshness="${gpu_report_freshness:-missing}" \
  -v gpu_report_error_scan="${gpu_report_error_scan:-missing}" \
  -v index_path="$INDEX_PATH" \
  -v error_scan_path="$ERROR_SCAN_PATH" \
  -v tooling_summary="$TOOLING_SUMMARY" \
  -v gpu_report_freshness_summary="$GPU_REPORT_FRESHNESS_SUMMARY" '
  BEGIN {
    status = "pass"
    reason = "ok"
    observability_status = "indexed"
    run_id_status = "wired"
    summary_lane = "current"
    error_scan = error_count + 0 == 0 ? "clean" : "dirty"
    gpu_report_freshness_status = gpu_report_status == "pass" && gpu_report_freshness == "current" && gpu_report_error_scan == "clean" ? "guarded" : "not_guarded"

    tooling_ok = tooling_status == "pass" && tooling_protocol_change + 0 == 0 && tooling_scene_change + 0 == 0

    if (!tooling_ok) {
      status = "fail"
      reason = "tooling_overlay_not_clean"
    } else if (gpu_report_freshness_status != "guarded") {
      status = "fail"
      reason = "gpu_report_freshness_not_clean"
    } else if (summary_count + 0 < 20) {
      status = "fail"
      reason = "too_few_current_summaries"
    } else if (bad_status_count + 0 != 0) {
      status = "fail"
      reason = "bad_current_summary_status"
    } else if (bad_name_count + 0 != 0) {
      status = "fail"
      reason = "bad_current_summary_name"
    } else if (error_count + 0 != 0) {
      status = "fail"
      reason = "current_error_scan_not_clean"
    }

    printf("observability_logs_cleanup status=%s reason=%s observability_status=%s run_id_status=%s summary_lane=%s summary_count=%d bad_status_count=%d bad_name_count=%d error_scan=%s error_count=%d tooling_status=%s tooling_protocol_change=%d tooling_scene_change=%d gpu_report_freshness=%s gpu_report_error_scan=%s index=%s error_scan_path=%s tooling_summary=%s gpu_report_freshness_summary=%s\n", status, reason, observability_status, run_id_status, summary_lane, summary_count, bad_status_count, bad_name_count, error_scan, error_count, tooling_status, tooling_protocol_change, tooling_scene_change, gpu_report_freshness_status, gpu_report_error_scan, index_path, error_scan_path, tooling_summary, gpu_report_freshness_summary)
    if (status != "pass") {
      exit 1
    }
  }
' > "$SUMMARY_PATH" || {
  cat "$SUMMARY_PATH" >&2 || true
  fail "observability logs cleanup gate failed"
}

cat "$SUMMARY_PATH"
echo "Observability logs cleanup artifacts: $OUT_DIR"
