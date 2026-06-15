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

SUMMARY_PATH="$OUT_DIR/shadow-xctrace-attach-capture-summary.txt"
TRACE_PATH="$OUT_DIR/shadow-xctrace-attach.trace"
MARKER_PATH="$OUT_DIR/gpu-terrain-$SHADOW_MESH.png.txt"
SCREENSHOT_PATH="${MARKER_PATH%.txt}"
GODOT_LOG="$OUT_DIR/godot.log"
XCTRACE_LOG="$OUT_DIR/xctrace.log"
COMMAND_BUFFERS_XML="$OUT_DIR/metal-command-buffer-submissions.xml"
ENCODERS_XML="$OUT_DIR/metal-application-encoders-list.xml"
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

run_xctrace() {
  if [ "$(basename "$XCTRACE_BIN")" = "xcrun" ]; then
    xcrun xctrace "$@"
  else
    "$XCTRACE_BIN" "$@"
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
  "$COMMAND_BUFFERS_XML" "$ENCODERS_XML" "$RESULT_ROW_PATH" "$SUMMARY_PATH"

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

export_status="skipped"
command_buffer_export_summary="skipped"
encoder_export_summary="skipped"
if [ "$EXPORT_TABLES" = "1" ]; then
  run_xctrace export \
    --input "$TRACE_PATH" \
    --xpath '/trace-toc/run[@number="1"]/data/table[@schema="metal-application-command-buffer-submissions"]' \
    --output "$COMMAND_BUFFERS_XML" > /dev/null 2>&1 || fail "failed to export command buffer submissions"
  run_xctrace export \
    --input "$TRACE_PATH" \
    --xpath '/trace-toc/run[@number="1"]/data/table[@schema="metal-application-encoders-list"]' \
    --output "$ENCODERS_XML" > /dev/null 2>&1 || fail "failed to export encoder list"
  test -s "$COMMAND_BUFFERS_XML" || fail "empty command buffer export"
  test -s "$ENCODERS_XML" || fail "empty encoder export"
  export_status="written"
  command_buffer_export_summary="$(relative_path "$COMMAND_BUFFERS_XML")"
  encoder_export_summary="$(relative_path "$ENCODERS_XML")"
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
  printf 'shadow_xctrace_attach_capture status=pass trace_status=captured trace_env_sanitized=1 result_row_status=%s radius=%s shadow_mesh=%s profiler_tool=xcode_metal profiler_artifact=%s marker=%s command_buffer_export=%s encoder_export=%s export_status=%s gpu_shadow_pass_ms_status=%s\n' \
    "$result_row_status" \
    "$RADIUS" \
    "$SHADOW_MESH" \
    "$(relative_path "$TRACE_PATH")" \
    "$(relative_path "$MARKER_PATH")" \
    "$command_buffer_export_summary" \
    "$encoder_export_summary" \
    "$export_status" \
    "$(if [ -n "$GPU_SHADOW_PASS_MS" ]; then printf 'provided'; else printf 'missing'; fi)"
  printf 'plan_match priority=%s artifact=%s result_row=%s\n' \
    "$(plan_priority)" \
    "$(plan_artifact)" \
    "$(relative_path "$RESULT_ROW_PATH")"
  printf 'trust_boundary generated_trace_requires_manual_review=1 exported_metal_tables_are_not_profiler_result_rows=1 candidate_row_requires_explicit_gpu_shadow_pass_ms=1\n'
} > "$SUMMARY_PATH"

cat "$SUMMARY_PATH"
