#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
CAPTURE_DIR="${1:-"$ROOT_DIR/logs/gpu_shadow_xctrace_attach_current"}"
case "$CAPTURE_DIR" in
  /*) ;;
  *) CAPTURE_DIR="$ROOT_DIR/$CAPTURE_DIR" ;;
esac
PACKET_PATH="${2:-"$CAPTURE_DIR/shadow-xctrace-review-packet.txt"}"
case "$PACKET_PATH" in
  /*) ;;
  *) PACKET_PATH="$ROOT_DIR/$PACKET_PATH" ;;
esac

SUMMARY_PATH="$CAPTURE_DIR/shadow-xctrace-attach-capture-summary.txt"
EXPECTED_GPU_PROFILER_BREADCRUMB="1381256515"
EXPECTED_GPU_PROFILER_SHADER="rumpel_gpu_terrain_render_shader"
EXPECTED_GPU_PROFILER_PIPELINE="rumpel_gpu_terrain_compositor_pipeline"
PROFILER_MARKER_XML_PATTERN="rumpel_gpu_terrain|1381256515|52544D43|52544d43|RTMC"

TRACE_TOC_XML="$CAPTURE_DIR/trace-toc.xml"
COMMAND_BUFFERS_COMPLETED_XML="$CAPTURE_DIR/metal-command-buffer-completed.xml"
GPU_INTERVALS_XML="$CAPTURE_DIR/metal-gpu-intervals.xml"
COMMAND_BUFFER_FRAME_ASSIGNMENT_XML="$CAPTURE_DIR/metal-command-buffer-frame-assignment.xml"
GPU_SUBMISSION_TO_COMMAND_BUFFER_ID_XML="$CAPTURE_DIR/metal-gpu-submission-to-command-buffer-id.xml"
APPLICATION_EVENT_INTERVAL_XML="$CAPTURE_DIR/metal-application-event-interval.xml"
OBJECT_LABEL_XML="$CAPTURE_DIR/metal-object-label.xml"
SHADER_LIST_XML="$CAPTURE_DIR/metal-shader-profiler-shader-list.xml"
RESULT_ROW_PATH="$CAPTURE_DIR/shadow-xctrace-result-row.txt"

fail() {
  echo "gpu_terrain_shadow_xctrace_review_packet: $*" >&2
  exit 1
}

relative_path() {
  path="$1"
  case "$path" in
    "$ROOT_DIR"/*) printf '%s\n' "${path#$ROOT_DIR/}" ;;
    *) printf '%s\n' "$path" ;;
  esac
}

metric_path() {
  value="$1"
  case "$value" in
    ''|none|skipped) printf '%s\n' "" ;;
    /*) printf '%s\n' "$value" ;;
    *) printf '%s/%s\n' "$ROOT_DIR" "$value" ;;
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

require_metric() {
  key="$1"
  value="$(field_metric "$key" "$SUMMARY_PATH")"
  test -n "$value" || fail "missing $key in $SUMMARY_PATH"
  printf '%s\n' "$value"
}

validate_nonnegative_integer() {
  value="$1"
  case "$value" in
    ''|*[!0-9]*) return 1 ;;
  esac
  [ "$value" -ge 0 ]
}

append_csv() {
  current="$1"
  item="$2"
  if [ "$current" = "none" ]; then
    printf '%s\n' "$item"
  else
    printf '%s,%s\n' "$current" "$item"
  fi
}

scan_marker_xml() {
  scan_status="missing"
  scan_matches=0
  scan_files="none"
  for xml_path in "$@"; do
    test -s "$xml_path" || continue
    if grep -Eq "$PROFILER_MARKER_XML_PATTERN" "$xml_path"; then
      scan_matches=$((scan_matches + 1))
      scan_files="$(
        append_csv "$scan_files" "$(relative_path "$xml_path")"
      )"
    fi
  done
  if [ "$scan_matches" -gt 0 ]; then
    scan_status="present"
  fi
}

test -s "$SUMMARY_PATH" || fail "missing xctrace capture summary $SUMMARY_PATH"
mkdir -p "$(dirname -- "$PACKET_PATH")"

capture_status="$(require_metric status)"
trace_status="$(require_metric trace_status)"
trace_env_sanitized="$(require_metric trace_env_sanitized)"
result_row_status="$(require_metric result_row_status)"
radius="$(require_metric radius)"
shadow_mesh="$(require_metric shadow_mesh)"
profiler_tool="$(require_metric profiler_tool)"
profiler_artifact="$(require_metric profiler_artifact)"
marker="$(require_metric marker)"
command_buffer_export="$(require_metric command_buffer_export)"
encoder_export="$(require_metric encoder_export)"
export_status="$(require_metric export_status)"
xml_export_count="$(require_metric xml_export_count)"
xml_optional_export_count="$(require_metric xml_optional_export_count)"
xml_optional_export_status="$(require_metric xml_optional_export_status)"
xml_optional_export_failures="$(require_metric xml_optional_export_failures)"
summary_profiler_marker_xml_status="$(require_metric profiler_marker_xml_status)"
summary_profiler_marker_xml_matches="$(require_metric profiler_marker_xml_matches)"
summary_profiler_marker_xml_files="$(require_metric profiler_marker_xml_files)"
gpu_profiler_breadcrumb="$(require_metric gpu_profiler_breadcrumb)"
gpu_profiler_shader="$(require_metric gpu_profiler_shader)"
gpu_profiler_pipeline="$(require_metric gpu_profiler_pipeline)"
gpu_shadow_pass_ms_status="$(require_metric gpu_shadow_pass_ms_status)"

test "$capture_status" = "pass" || fail "capture summary is not pass: $capture_status"
test "$trace_status" = "captured" || fail "trace was not captured: $trace_status"
test "$trace_env_sanitized" = "1" || fail "trace environment was not sanitized"
test "$export_status" = "written" || fail "xctrace XML exports are required for review packets"
validate_nonnegative_integer "$xml_export_count" || fail "invalid xml_export_count=$xml_export_count"
validate_nonnegative_integer "$xml_optional_export_count" || fail "invalid xml_optional_export_count=$xml_optional_export_count"
validate_nonnegative_integer "$summary_profiler_marker_xml_matches" || fail "invalid profiler_marker_xml_matches=$summary_profiler_marker_xml_matches"

test "$gpu_profiler_breadcrumb" = "$EXPECTED_GPU_PROFILER_BREADCRUMB" || fail "unexpected GPU profiler breadcrumb $gpu_profiler_breadcrumb"
test "$gpu_profiler_shader" = "$EXPECTED_GPU_PROFILER_SHADER" || fail "unexpected GPU profiler shader $gpu_profiler_shader"
test "$gpu_profiler_pipeline" = "$EXPECTED_GPU_PROFILER_PIPELINE" || fail "unexpected GPU profiler pipeline $gpu_profiler_pipeline"

TRACE_PATH="$(metric_path "$profiler_artifact")"
MARKER_PATH="$(metric_path "$marker")"
COMMAND_BUFFERS_XML="$(metric_path "$command_buffer_export")"
ENCODERS_XML="$(metric_path "$encoder_export")"

test -d "$TRACE_PATH" || fail "missing trace directory $TRACE_PATH"
test -s "$MARKER_PATH" || fail "missing visual marker $MARKER_PATH"
test -s "$COMMAND_BUFFERS_XML" || fail "missing command-buffer XML export $COMMAND_BUFFERS_XML"
test -s "$ENCODERS_XML" || fail "missing encoder XML export $ENCODERS_XML"
grep -q "Visual smoke screenshot saved" "$MARKER_PATH" || fail "marker does not record visual smoke screenshot"
grep -q "shadow_path=godot_proxy" "$MARKER_PATH" || fail "marker does not record Godot proxy shadow path"
grep -q "smoke_err=0" "$MARKER_PATH" || fail "marker reports smoke error"
grep -q "gpu_upload_fail=0" "$MARKER_PATH" || fail "marker reports GPU upload failure"

known_xml_count=0
known_optional_xml_count=0
known_xml_files="none"
for xml_path in \
  "$COMMAND_BUFFERS_XML" \
  "$ENCODERS_XML" \
  "$TRACE_TOC_XML" \
  "$COMMAND_BUFFERS_COMPLETED_XML" \
  "$GPU_INTERVALS_XML" \
  "$COMMAND_BUFFER_FRAME_ASSIGNMENT_XML" \
  "$GPU_SUBMISSION_TO_COMMAND_BUFFER_ID_XML" \
  "$APPLICATION_EVENT_INTERVAL_XML" \
  "$OBJECT_LABEL_XML" \
  "$SHADER_LIST_XML"; do
  test -s "$xml_path" || continue
  known_xml_count=$((known_xml_count + 1))
  case "$xml_path" in
    "$COMMAND_BUFFERS_XML"|"$ENCODERS_XML") ;;
    *) known_optional_xml_count=$((known_optional_xml_count + 1)) ;;
  esac
  known_xml_files="$(
    append_csv "$known_xml_files" "$(relative_path "$xml_path")"
  )"
done

xml_file_count=0
xml_files="none"
for xml_path in "$CAPTURE_DIR"/*.xml; do
  test -f "$xml_path" || continue
  xml_file_count=$((xml_file_count + 1))
  xml_files="$(
    append_csv "$xml_files" "$(relative_path "$xml_path")"
  )"
done

test "$known_xml_count" -eq "$xml_export_count" || fail "known XML count $known_xml_count does not match summary xml_export_count=$xml_export_count"
test "$known_optional_xml_count" -eq "$xml_optional_export_count" || fail "known optional XML count $known_optional_xml_count does not match summary xml_optional_export_count=$xml_optional_export_count"

scan_marker_xml \
  "$COMMAND_BUFFERS_XML" \
  "$ENCODERS_XML" \
  "$TRACE_TOC_XML" \
  "$COMMAND_BUFFERS_COMPLETED_XML" \
  "$GPU_INTERVALS_XML" \
  "$COMMAND_BUFFER_FRAME_ASSIGNMENT_XML" \
  "$GPU_SUBMISSION_TO_COMMAND_BUFFER_ID_XML" \
  "$APPLICATION_EVENT_INTERVAL_XML" \
  "$OBJECT_LABEL_XML" \
  "$SHADER_LIST_XML"
known_profiler_marker_xml_status="$scan_status"
known_profiler_marker_xml_matches="$scan_matches"
known_profiler_marker_xml_files="$scan_files"

test "$known_profiler_marker_xml_status" = "$summary_profiler_marker_xml_status" || fail "computed marker XML status $known_profiler_marker_xml_status does not match summary $summary_profiler_marker_xml_status"
test "$known_profiler_marker_xml_matches" -eq "$summary_profiler_marker_xml_matches" || fail "computed marker XML matches $known_profiler_marker_xml_matches do not match summary $summary_profiler_marker_xml_matches"

scan_marker_xml "$CAPTURE_DIR"/*.xml
all_profiler_marker_xml_status="$scan_status"
all_profiler_marker_xml_matches="$scan_matches"
all_profiler_marker_xml_files="$scan_files"

candidate_row_status="missing"
if [ -s "$RESULT_ROW_PATH" ]; then
  candidate_row_status="present"
fi
if [ "$gpu_shadow_pass_ms_status" = "provided" ] && [ "$candidate_row_status" != "present" ]; then
  fail "gpu_shadow_pass_ms_status=provided but no candidate row exists"
fi

manual_gpu_shadow_pass_ms_required="1"
if [ "$gpu_shadow_pass_ms_status" = "provided" ]; then
  manual_gpu_shadow_pass_ms_required="0"
fi

{
  printf 'shadow_xctrace_review_packet status=pass capture_dir=%s source_summary=%s trace_status=%s trace_env_sanitized=%s radius=%s shadow_mesh=%s profiler_tool=%s profiler_artifact=%s marker=%s export_status=%s xml_export_count=%s known_xml_file_count=%s xml_file_count=%s xml_optional_export_count=%s known_optional_xml_file_count=%s xml_optional_export_status=%s xml_optional_export_failures=%s profiler_marker_xml_status=%s profiler_marker_xml_matches=%s profiler_marker_xml_files=%s all_profiler_marker_xml_status=%s all_profiler_marker_xml_matches=%s all_profiler_marker_xml_files=%s gpu_profiler_breadcrumb=%s gpu_profiler_shader=%s gpu_profiler_pipeline=%s gpu_shadow_pass_ms_status=%s result_row_status=%s candidate_row_status=%s manual_gpu_shadow_pass_ms_required=%s manual_review_next_step=open_trace_in_xcode_instruments review_packet_is_not_profiler_result=1\n' \
    "$(relative_path "$CAPTURE_DIR")" \
    "$(relative_path "$SUMMARY_PATH")" \
    "$trace_status" \
    "$trace_env_sanitized" \
    "$radius" \
    "$shadow_mesh" \
    "$profiler_tool" \
    "$(relative_path "$TRACE_PATH")" \
    "$(relative_path "$MARKER_PATH")" \
    "$export_status" \
    "$xml_export_count" \
    "$known_xml_count" \
    "$xml_file_count" \
    "$xml_optional_export_count" \
    "$known_optional_xml_count" \
    "$xml_optional_export_status" \
    "$xml_optional_export_failures" \
    "$known_profiler_marker_xml_status" \
    "$known_profiler_marker_xml_matches" \
    "$known_profiler_marker_xml_files" \
    "$all_profiler_marker_xml_status" \
    "$all_profiler_marker_xml_matches" \
    "$all_profiler_marker_xml_files" \
    "$gpu_profiler_breadcrumb" \
    "$gpu_profiler_shader" \
    "$gpu_profiler_pipeline" \
    "$gpu_shadow_pass_ms_status" \
    "$result_row_status" \
    "$candidate_row_status" \
    "$manual_gpu_shadow_pass_ms_required"
  printf 'review_artifacts trace=%s marker=%s command_buffer_export=%s encoder_export=%s known_xml_files=%s all_xml_files=%s packet=%s\n' \
    "$(relative_path "$TRACE_PATH")" \
    "$(relative_path "$MARKER_PATH")" \
    "$(relative_path "$COMMAND_BUFFERS_XML")" \
    "$(relative_path "$ENCODERS_XML")" \
    "$known_xml_files" \
    "$xml_files" \
    "$(relative_path "$PACKET_PATH")"
  printf 'trust_boundary review_packet_is_not_profiler_result=1 exported_metal_tables_are_not_profiler_result_rows=1 xml_marker_scan_is_navigation_only=1 manual_gpu_shadow_pass_ms_required=%s candidate_row_still_requires_results_checker=1\n' \
    "$manual_gpu_shadow_pass_ms_required"
  printf 'operator_steps=open_trace_identify_shadow_pass_record_positive_row_validate_results_then_campaign_gate\n'
} > "$PACKET_PATH"

cat "$PACKET_PATH"
