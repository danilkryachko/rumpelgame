#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/gpu_shadow_xctrace_attach_current"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

GODOT_BIN="${GODOT_BIN:-/opt/homebrew/bin/godot}"
XCTRACE_BIN="${XCTRACE_BIN:-$(command -v xctrace 2>/dev/null || command -v xcrun 2>/dev/null || true)}"
RADIUS="${RUMPELMC_SHADOW_XCTRACE_RADIUS:-scene}"
SHADOW_MESH="${RUMPELMC_SHADOW_XCTRACE_MESH:-compact}"
RECORD_SEC="${RUMPELMC_SHADOW_XCTRACE_RECORD_SEC:-10}"
SMOKE_DELAY_SEC="${RUMPELMC_SHADOW_XCTRACE_SMOKE_DELAY_SEC:-25}"
QUIT_AFTER_FRAMES="${RUMPELMC_SHADOW_XCTRACE_QUIT_AFTER_FRAMES:-8000}"
ATTACH_DELAY_SEC="${RUMPELMC_SHADOW_XCTRACE_ATTACH_DELAY_SEC:-2}"
EXPORT_TABLES="${RUMPELMC_SHADOW_XCTRACE_EXPORT_TABLES:-1}"
GPU_SHADOW_PASS_MS="${RUMPELMC_SHADOW_XCTRACE_GPU_SHADOW_PASS_MS:-}"
PLAN_ARTIFACT_ROOT="${RUMPELMC_SHADOW_XCTRACE_PLAN_ARTIFACT_ROOT:-logs/gpu_shadow_radius_matrix_wide}"
EXPECTED_GPU_PROFILER_BREADCRUMB="1381256515"
EXPECTED_GPU_PROFILER_SHADER="rumpel_gpu_terrain_render_shader"
EXPECTED_GPU_PROFILER_PIPELINE="rumpel_gpu_terrain_compositor_pipeline"
PROFILER_MARKER_XML_PATTERN="rumpel_gpu_terrain|1381256515|52544D43|52544d43|RTMC"

SUMMARY_PATH="$OUT_DIR/shadow-xctrace-attach-capture-summary.txt"
TRACE_PATH="$OUT_DIR/shadow-xctrace-attach.trace"
MARKER_PATH="$OUT_DIR/gpu-terrain-$SHADOW_MESH.png.txt"
SCREENSHOT_PATH="${MARKER_PATH%.txt}"
GODOT_LOG="$OUT_DIR/godot.log"
XCTRACE_LOG="$OUT_DIR/xctrace.log"
COMMAND_BUFFERS_XML="$OUT_DIR/metal-command-buffer-submissions.xml"
ENCODERS_XML="$OUT_DIR/metal-application-encoders-list.xml"
TRACE_TOC_XML="$OUT_DIR/trace-toc.xml"
COMMAND_BUFFERS_COMPLETED_XML="$OUT_DIR/metal-command-buffer-completed.xml"
GPU_INTERVALS_XML="$OUT_DIR/metal-gpu-intervals.xml"
COMMAND_BUFFER_FRAME_ASSIGNMENT_XML="$OUT_DIR/metal-command-buffer-frame-assignment.xml"
GPU_SUBMISSION_TO_COMMAND_BUFFER_ID_XML="$OUT_DIR/metal-gpu-submission-to-command-buffer-id.xml"
APPLICATION_EVENT_INTERVAL_XML="$OUT_DIR/metal-application-event-interval.xml"
OBJECT_LABEL_XML="$OUT_DIR/metal-object-label.xml"
SHADER_LIST_XML="$OUT_DIR/metal-shader-profiler-shader-list.xml"
RESULT_ROW_PATH="$OUT_DIR/shadow-xctrace-result-row.txt"

mkdir -p "$OUT_DIR"

fail() {
  echo "gpu_terrain_shadow_xctrace_attach_capture: $*" >&2
  exit 1
}

listener_pid() {
  if command -v lsof >/dev/null 2>&1; then
    lsof -tiTCP:25565 -sTCP:LISTEN 2>/dev/null | sed -n '1p'
  fi
}

wait_for_port_clear() {
  tries=0
  while [ "$tries" -lt 10 ]; do
    pid="$(listener_pid || true)"
    if [ -z "$pid" ]; then
      return 0
    fi
    tries=$((tries + 1))
    sleep 1
  done
  fail "port 25565 is still listening after xctrace capture cleanup"
}

relative_path() {
  path="$1"
  case "$path" in
    "$ROOT_DIR"/*) printf '%s\n' "${path#$ROOT_DIR/}" ;;
    *) printf '%s\n' "$path" ;;
  esac
}

validate_positive_decimal() {
  value="$1"
  case "$value" in
    ''|*[!0-9.]*|.*|*.) return 1 ;;
  esac
  printf '%s\n' "$value" | awk '
    /^[0-9]+(\.[0-9]+)?$/ && $1 + 0 > 0 { found = 1 }
    END { exit found ? 0 : 1 }
  '
}

validate_positive_integer() {
  value="$1"
  case "$value" in
    ''|*[!0-9]*) return 1 ;;
  esac
  [ "$value" -gt 0 ]
}

marker_value() {
  key="$1"
  path="$2"
  awk -v key="$key" '
    {
      for (i = 1; i <= NF; i++) {
        if ($i ~ ("^" key "=")) {
          sub("^[^=]*=", "", $i)
          gsub(/^"/, "", $i)
          gsub(/"$/, "", $i)
          print $i
          exit
        }
      }
    }
  ' "$path"
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

run_xctrace() {
  if [ "$(basename "$XCTRACE_BIN")" = "xcrun" ]; then
    xcrun xctrace "$@"
  else
    "$XCTRACE_BIN" "$@"
  fi
}

export_xctrace_xml() {
  xpath="$1"
  output="$2"
  label="$3"
  run_xctrace export \
    --input "$TRACE_PATH" \
    --xpath "$xpath" \
    --output "$output" > /dev/null 2>&1 || fail "failed to export $label"
  test -s "$output" || fail "empty $label export"
  xml_export_count=$((xml_export_count + 1))
}

try_export_xctrace_xml() {
  xpath="$1"
  output="$2"
  label="$3"
  if run_xctrace export \
    --input "$TRACE_PATH" \
    --xpath "$xpath" \
    --output "$output" > /dev/null 2>&1 && test -s "$output"; then
    xml_export_count=$((xml_export_count + 1))
    xml_optional_export_count=$((xml_optional_export_count + 1))
  else
    rm -f "$output"
    xml_optional_export_failures="$(append_csv "$xml_optional_export_failures" "$label")"
  fi
}

scan_profiler_marker_xml() {
  profiler_marker_xml_status="missing"
  profiler_marker_xml_matches=0
  profiler_marker_xml_files="none"
  for xml_path in "$@"; do
    test -s "$xml_path" || continue
    if grep -Eq "$PROFILER_MARKER_XML_PATTERN" "$xml_path"; then
      profiler_marker_xml_matches=$((profiler_marker_xml_matches + 1))
      profiler_marker_xml_files="$(
        append_csv "$profiler_marker_xml_files" "$(relative_path "$xml_path")"
      )"
    fi
  done
  if [ "$profiler_marker_xml_matches" -gt 0 ]; then
    profiler_marker_xml_status="present"
  fi
}

validate_radius() {
  case "$RADIUS" in
    scene) return 0 ;;
    ''|*[!0-9]*)
      fail "RUMPELMC_SHADOW_XCTRACE_RADIUS must be scene or a positive integer"
      ;;
  esac
  if [ "$RADIUS" -lt 1 ]; then
    fail "RUMPELMC_SHADOW_XCTRACE_RADIUS=0 is reserved for the shadow-disabled control"
  fi
}

radius_env_value() {
  if [ "$RADIUS" = "scene" ]; then
    printf '%s\n' ""
  else
    printf '%s\n' "$RADIUS"
  fi
}

plan_priority() {
  case "$RADIUS" in
    scene) printf '%s\n' "1" ;;
    2) printf '%s\n' "2" ;;
    1) printf '%s\n' "3" ;;
    *) printf '%s\n' "4" ;;
  esac
}

plan_artifact() {
  if [ "$RADIUS" = "scene" ]; then
    printf '%s/scene\n' "$PLAN_ARTIFACT_ROOT"
  else
    printf '%s/radius-%s\n' "$PLAN_ARTIFACT_ROOT" "$RADIUS"
  fi
}

cleanup() {
  if [ "${godot_pid:-}" ]; then
    if kill -0 "$godot_pid" 2>/dev/null; then
      kill "$godot_pid" 2>/dev/null || true
    fi
  fi
  pid="$(listener_pid || true)"
  if [ -n "$pid" ]; then
    kill "$pid" 2>/dev/null || true
    wait_for_port_clear
  fi
  restore_godot_rust_ext_profile
}

case "$SHADOW_MESH" in
  full|compact) ;;
  *) fail "RUMPELMC_SHADOW_XCTRACE_MESH must be full or compact" ;;
esac
case "$EXPORT_TABLES" in
  0|1) ;;
  *) fail "RUMPELMC_SHADOW_XCTRACE_EXPORT_TABLES must be 0 or 1" ;;
esac
validate_positive_integer "$RECORD_SEC" || fail "RUMPELMC_SHADOW_XCTRACE_RECORD_SEC must be a positive integer"
case "$SMOKE_DELAY_SEC" in
  ''|*[!0-9.]*) fail "RUMPELMC_SHADOW_XCTRACE_SMOKE_DELAY_SEC must be numeric" ;;
esac
validate_positive_integer "$QUIT_AFTER_FRAMES" || fail "RUMPELMC_SHADOW_XCTRACE_QUIT_AFTER_FRAMES must be a positive integer"
case "$ATTACH_DELAY_SEC" in
  ''|*[!0-9.]*) fail "RUMPELMC_SHADOW_XCTRACE_ATTACH_DELAY_SEC must be numeric" ;;
esac
if [ -n "$GPU_SHADOW_PASS_MS" ] && ! validate_positive_decimal "$GPU_SHADOW_PASS_MS"; then
  fail "RUMPELMC_SHADOW_XCTRACE_GPU_SHADOW_PASS_MS must be a positive decimal"
fi
validate_radius
test -n "$XCTRACE_BIN" || fail "xctrace/xcrun was not found"
test -x "$GODOT_BIN" || fail "missing Godot binary $GODOT_BIN"
if [ -n "$(listener_pid || true)" ]; then
  fail "port 25565 is already in use; stop the existing server before xctrace capture"
fi

. "$ROOT_DIR/scripts/godot_rust_ext_profile.sh"
prepare_godot_rust_ext_profile "$ROOT_DIR"
trap cleanup EXIT HUP INT TERM

rm -rf "$TRACE_PATH"
rm -f "$MARKER_PATH" "$SCREENSHOT_PATH" "$GODOT_LOG" "$XCTRACE_LOG" \
  "$COMMAND_BUFFERS_XML" "$ENCODERS_XML" "$TRACE_TOC_XML" \
  "$COMMAND_BUFFERS_COMPLETED_XML" "$GPU_INTERVALS_XML" \
  "$COMMAND_BUFFER_FRAME_ASSIGNMENT_XML" "$GPU_SUBMISSION_TO_COMMAND_BUFFER_ID_XML" \
  "$APPLICATION_EVENT_INTERVAL_XML" "$OBJECT_LABEL_XML" "$SHADER_LIST_XML" \
  "$RESULT_ROW_PATH" "$SUMMARY_PATH"

radius_env="$(radius_env_value)"
minimal_path="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin"
(
  cd "$ROOT_DIR"
  exec env -i \
    HOME="${HOME:-/tmp}" \
    TMPDIR="${TMPDIR:-/tmp}" \
    LANG="${LANG:-C.UTF-8}" \
    LC_ALL="${LC_ALL:-C.UTF-8}" \
    PATH="$minimal_path" \
    RUMPELMC_GPU_TERRAIN_RENDER=1 \
    RUMPELMC_GPU_TERRAIN_SHADOW_PROXY_CHUNK_DISTANCE="$radius_env" \
    RUMPELMC_GPU_TERRAIN_SHADOW_PROXY_MODE=conservative \
    RUMPELMC_GPU_TERRAIN_SHADOW_PROXY_MESH="$SHADOW_MESH" \
    RUMPELMC_VISUAL_SMOKE_POSE=lighting_shadow \
    RUMPELMC_VISUAL_SMOKE_PATH="$SCREENSHOT_PATH" \
    RUMPELMC_VISUAL_SMOKE_DELAY_SEC="$SMOKE_DELAY_SEC" \
    RUMPELMC_VISUAL_SMOKE_HIDE_HUD=1 \
    RUMPELMC_VISUAL_SMOKE_DISABLE_PLAYER_INPUT=1 \
    "$GODOT_BIN" --disable-vsync --max-fps 0 --path client --quit-after "$QUIT_AFTER_FRAMES"
) > "$GODOT_LOG" 2>&1 &
godot_pid="$!"

sleep "$ATTACH_DELAY_SEC"
if ! kill -0 "$godot_pid" 2>/dev/null; then
  cat "$GODOT_LOG" >&2 || true
  fail "Godot exited before xctrace attach"
fi

run_xctrace record \
  --template 'Metal System Trace' \
  --output "$TRACE_PATH" \
  --time-limit "${RECORD_SEC}s" \
  --attach "$godot_pid" \
  --no-prompt > "$XCTRACE_LOG" 2>&1 || {
    cat "$XCTRACE_LOG" >&2 || true
    fail "xctrace attach capture failed"
  }

grep -q "Attaching to: godot" "$XCTRACE_LOG" || {
  cat "$XCTRACE_LOG" >&2 || true
  fail "xctrace did not attach to the Godot process"
}

wait "$godot_pid" || {
  cat "$GODOT_LOG" >&2 || true
  fail "Godot workload failed"
}
godot_pid=""

test -d "$TRACE_PATH" || fail "missing trace output $TRACE_PATH"
test -s "$MARKER_PATH" || fail "missing marker $MARKER_PATH"
grep -q "Visual smoke screenshot saved" "$MARKER_PATH" || fail "missing visual smoke marker"
grep -q "shadow_path=godot_proxy" "$MARKER_PATH" || fail "unexpected shadow path"
grep -q "shadow_mesh=$SHADOW_MESH" "$MARKER_PATH" || fail "unexpected shadow mesh"
grep -q "smoke_err=0" "$MARKER_PATH" || fail "visual smoke failed"
grep -q "gpu_upload_fail=0" "$MARKER_PATH" || fail "GPU upload failure present"
grep -q "rust_ext_profile=release" "$MARKER_PATH" || fail "release Rust marker missing"
gpu_profiler_breadcrumb="$(marker_value gpu_profiler_breadcrumb "$MARKER_PATH")"
gpu_profiler_shader="$(marker_value gpu_profiler_shader "$MARKER_PATH")"
gpu_profiler_pipeline="$(marker_value gpu_profiler_pipeline "$MARKER_PATH")"
validate_positive_integer "$gpu_profiler_breadcrumb" || fail "missing GPU profiler breadcrumb marker"
if [ "$gpu_profiler_breadcrumb" != "$EXPECTED_GPU_PROFILER_BREADCRUMB" ]; then
  fail "unexpected GPU profiler breadcrumb marker $gpu_profiler_breadcrumb"
fi
if [ "$gpu_profiler_shader" != "$EXPECTED_GPU_PROFILER_SHADER" ]; then
  fail "unexpected GPU profiler shader marker $gpu_profiler_shader"
fi
if [ "$gpu_profiler_pipeline" != "$EXPECTED_GPU_PROFILER_PIPELINE" ]; then
  fail "unexpected GPU profiler pipeline marker $gpu_profiler_pipeline"
fi

export_status="skipped"
command_buffer_export_summary="skipped"
encoder_export_summary="skipped"
xml_export_count=0
xml_optional_export_count=0
xml_optional_export_status="skipped"
xml_optional_export_failures="none"
profiler_marker_xml_status="skipped"
profiler_marker_xml_matches=0
profiler_marker_xml_files="none"
if [ "$EXPORT_TABLES" = "1" ]; then
  export_xctrace_xml '/trace-toc/run[@number="1"]/data/table[@schema="metal-application-command-buffer-submissions"]' \
    "$COMMAND_BUFFERS_XML" "command buffer submissions"
  export_xctrace_xml '/trace-toc/run[@number="1"]/data/table[@schema="metal-application-encoders-list"]' \
    "$ENCODERS_XML" "encoder list"
  try_export_xctrace_xml '/trace-toc' \
    "$TRACE_TOC_XML" "trace-toc"
  try_export_xctrace_xml '/trace-toc/run[@number="1"]/data/table[@schema="metal-command-buffer-completed"]' \
    "$COMMAND_BUFFERS_COMPLETED_XML" "command_buffer_completed"
  try_export_xctrace_xml '/trace-toc/run[@number="1"]/data/table[@schema="metal-gpu-intervals"]' \
    "$GPU_INTERVALS_XML" "gpu_intervals"
  try_export_xctrace_xml '/trace-toc/run[@number="1"]/data/table[@schema="metal-command-buffer-frame-assignment"]' \
    "$COMMAND_BUFFER_FRAME_ASSIGNMENT_XML" "command_buffer_frame_assignment"
  try_export_xctrace_xml '/trace-toc/run[@number="1"]/data/table[@schema="metal-gpu-submission-to-command-buffer-id"]' \
    "$GPU_SUBMISSION_TO_COMMAND_BUFFER_ID_XML" "gpu_submission_to_command_buffer_id"
  try_export_xctrace_xml '/trace-toc/run[@number="1"]/data/table[@schema="metal-application-event-interval"]' \
    "$APPLICATION_EVENT_INTERVAL_XML" "application_event_interval"
  try_export_xctrace_xml '/trace-toc/run[@number="1"]/data/table[@schema="metal-object-label"]' \
    "$OBJECT_LABEL_XML" "object_label"
  try_export_xctrace_xml '/trace-toc/run[@number="1"]/data/table[@schema="metal-shader-profiler-shader-list"]' \
    "$SHADER_LIST_XML" "shader_profiler_shader_list"
  export_status="written"
  command_buffer_export_summary="$(relative_path "$COMMAND_BUFFERS_XML")"
  encoder_export_summary="$(relative_path "$ENCODERS_XML")"
  xml_optional_export_status="written"
  if [ "$xml_optional_export_failures" != "none" ]; then
    xml_optional_export_status="partial"
  fi
  scan_profiler_marker_xml \
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
fi

result_row_status="manual_gpu_shadow_pass_ms_required"
if [ -n "$GPU_SHADOW_PASS_MS" ]; then
  printf 'external_profile_status=captured priority=%s radius=%s artifact=%s profiler_tool=xcode_metal profiler_artifact=%s gpu_shadow_pass_ms=%s\n' \
    "$(plan_priority)" \
    "$RADIUS" \
    "$(plan_artifact)" \
    "$(relative_path "$TRACE_PATH")" \
    "$GPU_SHADOW_PASS_MS" > "$RESULT_ROW_PATH"
  result_row_status="candidate_written"
fi

{
  printf 'shadow_xctrace_attach_capture status=pass trace_status=captured trace_env_sanitized=1 result_row_status=%s radius=%s shadow_mesh=%s profiler_tool=xcode_metal profiler_artifact=%s marker=%s command_buffer_export=%s encoder_export=%s export_status=%s xml_export_count=%s xml_optional_export_count=%s xml_optional_export_status=%s xml_optional_export_failures=%s profiler_marker_xml_status=%s profiler_marker_xml_matches=%s profiler_marker_xml_files=%s gpu_profiler_breadcrumb=%s gpu_profiler_shader=%s gpu_profiler_pipeline=%s gpu_shadow_pass_ms_status=%s\n' \
    "$result_row_status" \
    "$RADIUS" \
    "$SHADOW_MESH" \
    "$(relative_path "$TRACE_PATH")" \
    "$(relative_path "$MARKER_PATH")" \
    "$command_buffer_export_summary" \
    "$encoder_export_summary" \
    "$export_status" \
    "$xml_export_count" \
    "$xml_optional_export_count" \
    "$xml_optional_export_status" \
    "$xml_optional_export_failures" \
    "$profiler_marker_xml_status" \
    "$profiler_marker_xml_matches" \
    "$profiler_marker_xml_files" \
    "$gpu_profiler_breadcrumb" \
    "$gpu_profiler_shader" \
    "$gpu_profiler_pipeline" \
    "$(if [ -n "$GPU_SHADOW_PASS_MS" ]; then printf 'provided'; else printf 'missing'; fi)"
  printf 'plan_match priority=%s artifact=%s result_row=%s\n' \
    "$(plan_priority)" \
    "$(plan_artifact)" \
    "$(relative_path "$RESULT_ROW_PATH")"
  printf 'trust_boundary generated_trace_requires_manual_review=1 exported_metal_tables_are_not_profiler_result_rows=1 xml_marker_scan_is_navigation_only=1 candidate_row_requires_explicit_gpu_shadow_pass_ms=1\n'
} > "$SUMMARY_PATH"

cat "$SUMMARY_PATH"
