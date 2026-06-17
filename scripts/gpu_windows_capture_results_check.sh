#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
MANIFEST_PATH="${1:-"$ROOT_DIR/logs/gpu_windows_capture_pack_current/gpu-windows-capture-manifest.txt"}"
RESULTS_PATH="${2:-"$(dirname -- "$MANIFEST_PATH")/gpu-windows-capture-results.txt"}"
OUT_PATH="${3:-"$(dirname -- "$RESULTS_PATH")/gpu-windows-capture-results-summary.txt"}"
ALLOW_PARTIAL="${RUMPELMC_WINDOWS_CAPTURE_RESULTS_ALLOW_PARTIAL:-0}"

case "$MANIFEST_PATH" in
  /*) ;;
  *) MANIFEST_PATH="$ROOT_DIR/$MANIFEST_PATH" ;;
esac
case "$RESULTS_PATH" in
  /*) ;;
  *) RESULTS_PATH="$ROOT_DIR/$RESULTS_PATH" ;;
esac
case "$OUT_PATH" in
  /*) ;;
  *) OUT_PATH="$ROOT_DIR/$OUT_PATH" ;;
esac

fail() {
  echo "gpu_windows_capture_results_check: $*" >&2
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

required_token() {
  key="$1"
  line="$2"
  value="$(line_token "$key" "$line")"
  test -n "$value" || fail "missing $key in row: $line"
  printf '%s\n' "$value"
}

optional_token() {
  key="$1"
  line="$2"
  fallback="$3"
  value="$(line_token "$key" "$line")"
  if [ -n "$value" ]; then
    printf '%s\n' "$value"
  else
    printf '%s\n' "$fallback"
  fi
}

validate_positive_decimal() {
  key="$1"
  value="$2"
  case "$value" in
    ''|*[!0-9.]*|*.*.*) fail "$key must be a positive decimal: $value" ;;
  esac
  awk -v value="$value" -v key="$key" 'BEGIN { if ((value + 0.0) <= 0.0) exit 1 }' \
    || fail "$key must be greater than zero: $value"
}

validate_nonnegative_decimal() {
  key="$1"
  value="$2"
  case "$value" in
    ''|*[!0-9.]*|*.*.*) fail "$key must be a nonnegative decimal: $value" ;;
  esac
}

validate_positive_integer() {
  key="$1"
  value="$2"
  case "$value" in
    ''|*[!0-9]*) fail "$key must be a positive integer: $value" ;;
  esac
  test "$value" -gt 0 || fail "$key must be greater than zero: $value"
}

validate_nonnegative_integer() {
  key="$1"
  value="$2"
  case "$value" in
    ''|*[!0-9]*) fail "$key must be a nonnegative integer: $value" ;;
  esac
}

validate_evidence_token() {
  key="$1"
  value="$2"
  case "$value" in
    ''|pending|todo|TODO|n/a|unknown|missing|placeholder|none|external_*_required)
      fail "$key must identify recorded external evidence, not $value"
      ;;
  esac
}

backend_allowed() {
  planned="$1"
  actual="$2"
  case "$planned" in
    direct3d12_or_vulkan)
      case "$actual" in direct3d12|d3d12|vulkan|direct3d12_or_vulkan) return 0 ;; esac
      ;;
    vulkan_or_direct3d11_or_direct3d12)
      case "$actual" in vulkan|direct3d11|d3d11|direct3d12|d3d12|vulkan_or_direct3d11_or_direct3d12) return 0 ;; esac
      ;;
    *)
      test "$actual" = "$planned" && return 0
      ;;
  esac
  return 1
}

tool_allowed() {
  planned="$1"
  actual="$2"
  case "$planned" in
    pix_gpu_capture|pix_timing_capture|renderdoc_frame_capture)
      test "$actual" = "$planned" && return 0
      ;;
    pix_renderdoc_or_vendor_shader_capture)
      case "$actual" in
        pix_renderdoc_or_vendor_shader_capture|pix_gpu_capture|pix_shader_capture|renderdoc_frame_capture|renderdoc_shader_capture|nvidia_nsight|amd_rgp|intel_gpa|vendor_shader_capture)
          return 0
          ;;
      esac
      ;;
    *)
      test "$actual" = "$planned" && return 0
      ;;
  esac
  return 1
}

require_nonplaceholder_field() {
  key="$1"
  line="$2"
  value="$(required_token "$key" "$line")"
  validate_evidence_token "$key" "$value"
  printf '%s\n' "$value"
}

test -s "$MANIFEST_PATH" || fail "missing Windows capture manifest $MANIFEST_PATH"
test -s "$RESULTS_PATH" || fail "missing Windows capture results $RESULTS_PATH"
mkdir -p "$(dirname -- "$OUT_PATH")"

tmp_plan_rows="$OUT_PATH.plan-rows.tmp"
tmp_plan_index="$OUT_PATH.plan-index.tmp"
tmp_result_rows="$OUT_PATH.result-rows.tmp"
tmp_result_lines="$OUT_PATH.result-lines.tmp"
tmp_seen_keys="$OUT_PATH.seen-keys.tmp"
tmp_summary="$OUT_PATH.tmp"
trap 'rm -f "$tmp_plan_rows" "$tmp_plan_index" "$tmp_result_rows" "$tmp_result_lines" "$tmp_seen_keys" "$tmp_summary"' EXIT

grep '^row=' "$MANIFEST_PATH" > "$tmp_plan_rows" || fail "manifest has no row entries: $MANIFEST_PATH"
grep '^external_profile_status=' "$RESULTS_PATH" > "$tmp_result_rows" || fail "results have no external_profile_status rows: $RESULTS_PATH"
: > "$tmp_plan_index"
: > "$tmp_result_lines"
: > "$tmp_seen_keys"

plan_count=0
while IFS= read -r line; do
  row="$(required_token row "$line")"
  priority="$(required_token priority "$line")"
  platform="$(required_token platform "$line")"
  backend="$(required_token backend "$line")"
  profiler_tool="$(required_token profiler_tool "$line")"
  capture_status="$(required_token capture_status "$line")"
  workload="$(required_token workload "$line")"
  required_metrics="$(required_token required_metrics "$line")"

  validate_positive_integer priority "$priority"
  test "$platform" = "windows" || fail "Windows manifest row must use platform=windows, got $platform"
  test "$capture_status" = "pending_external_profiler" || fail "manifest rows must remain pending before captured results are checked"
  printf '%s|%s|%s|%s|%s|%s\n' "$priority" "$row" "$backend" "$profiler_tool" "$workload" "$required_metrics" >> "$tmp_plan_index"
  plan_count=$((plan_count + 1))
done < "$tmp_plan_rows"

captured_count=0
pix_gpu_rows=0
pix_timing_rows=0
renderdoc_rows=0
shader_rows=0

while IFS= read -r line; do
  status="$(required_token external_profile_status "$line")"
  row="$(required_token row "$line")"
  priority="$(required_token priority "$line")"
  platform="$(required_token platform "$line")"
  backend="$(required_token backend "$line")"
  profiler_tool="$(required_token profiler_tool "$line")"
  profiler_artifact="$(require_nonplaceholder_field profiler_artifact "$line")"
  counter_evidence="$(require_nonplaceholder_field counter_evidence "$line")"
  machine_context="$(require_nonplaceholder_field machine_context "$line")"
  windows_version="$(require_nonplaceholder_field windows_version "$line")"
  gpu_vendor="$(require_nonplaceholder_field gpu_vendor "$line")"
  gpu_model="$(require_nonplaceholder_field gpu_model "$line")"
  driver_version="$(require_nonplaceholder_field driver_version "$line")"
  godot_version="$(require_nonplaceholder_field godot_version "$line")"
  rendering_driver="$(require_nonplaceholder_field rendering_driver "$line")"
  display_refresh_hz="$(required_token display_refresh_hz "$line")"
  gpu_pass_ms="$(required_token gpu_pass_ms "$line")"
  draw_count="$(required_token draw_count "$line")"

  test "$status" = "captured" || fail "result row must use external_profile_status=captured, got $status"
  test "$platform" = "windows" || fail "result row must use platform=windows, got $platform"
  validate_evidence_token profiler_tool "$profiler_tool"
  validate_positive_integer priority "$priority"
  validate_positive_decimal display_refresh_hz "$display_refresh_hz"
  validate_positive_decimal gpu_pass_ms "$gpu_pass_ms"
  validate_positive_integer draw_count "$draw_count"

  plan_match="$(awk -F '|' -v priority="$priority" -v row="$row" '$1 == priority && $2 == row { print; exit }' "$tmp_plan_index")"
  test -n "$plan_match" || fail "result row does not match Windows manifest: priority=$priority row=$row"
  planned_backend="$(printf '%s\n' "$plan_match" | awk -F '|' '{ print $3 }')"
  planned_tool="$(printf '%s\n' "$plan_match" | awk -F '|' '{ print $4 }')"
  workload="$(printf '%s\n' "$plan_match" | awk -F '|' '{ print $5 }')"
  required_metrics="$(printf '%s\n' "$plan_match" | awk -F '|' '{ print $6 }')"

  backend_allowed "$planned_backend" "$backend" || fail "backend=$backend is not allowed by manifest backend=$planned_backend for row=$row"
  tool_allowed "$planned_tool" "$profiler_tool" || fail "profiler_tool=$profiler_tool is not allowed by manifest profiler_tool=$planned_tool for row=$row"

  seen_key="${priority}|${row}"
  if grep -F -x -q "$seen_key" "$tmp_seen_keys"; then
    fail "duplicate captured row for priority=$priority row=$row"
  fi
  printf '%s\n' "$seen_key" >> "$tmp_seen_keys"

  event_timing_ms="$(optional_token event_timing_ms "$line" n/a)"
  resource_state_events="$(optional_token resource_state_events "$line" n/a)"
  pipeline_state_evidence="$(optional_token pipeline_state_evidence "$line" n/a)"
  gpu_timing_ms="$(optional_token gpu_timing_ms "$line" n/a)"
  cpu_gpu_overlap_ms="$(optional_token cpu_gpu_overlap_ms "$line" n/a)"
  memory_allocation_mb="$(optional_token memory_allocation_mb "$line" n/a)"
  timing_capture_span_ms="$(optional_token timing_capture_span_ms "$line" n/a)"
  draw_event_count="$(optional_token draw_event_count "$line" n/a)"
  texture_sampling_evidence="$(optional_token texture_sampling_evidence "$line" n/a)"
  buffer_update_events="$(optional_token buffer_update_events "$line" n/a)"
  resource_lifetime_events="$(optional_token resource_lifetime_events "$line" n/a)"
  shader_pass_ms="$(optional_token shader_pass_ms "$line" n/a)"
  vertex_stage_ms="$(optional_token vertex_stage_ms "$line" n/a)"
  fragment_stage_ms="$(optional_token fragment_stage_ms "$line" n/a)"
  shader_cost_evidence="$(optional_token shader_cost_evidence "$line" n/a)"

  case "$row" in
    pix_gpu_world_interaction)
      validate_positive_decimal event_timing_ms "$event_timing_ms"
      validate_positive_integer resource_state_events "$resource_state_events"
      validate_evidence_token pipeline_state_evidence "$pipeline_state_evidence"
      pix_gpu_rows=$((pix_gpu_rows + 1))
      ;;
    pix_timing_world_interaction)
      validate_positive_decimal gpu_timing_ms "$gpu_timing_ms"
      validate_nonnegative_decimal cpu_gpu_overlap_ms "$cpu_gpu_overlap_ms"
      validate_nonnegative_decimal memory_allocation_mb "$memory_allocation_mb"
      validate_positive_decimal timing_capture_span_ms "$timing_capture_span_ms"
      pix_timing_rows=$((pix_timing_rows + 1))
      ;;
    renderdoc_frame_world_interaction)
      validate_positive_integer draw_event_count "$draw_event_count"
      validate_evidence_token pipeline_state_evidence "$pipeline_state_evidence"
      validate_evidence_token texture_sampling_evidence "$texture_sampling_evidence"
      validate_nonnegative_integer buffer_update_events "$buffer_update_events"
      validate_nonnegative_integer resource_lifetime_events "$resource_lifetime_events"
      renderdoc_rows=$((renderdoc_rows + 1))
      ;;
    windows_shader_hot_path)
      validate_positive_decimal shader_pass_ms "$shader_pass_ms"
      validate_nonnegative_decimal vertex_stage_ms "$vertex_stage_ms"
      validate_nonnegative_decimal fragment_stage_ms "$fragment_stage_ms"
      validate_evidence_token shader_cost_evidence "$shader_cost_evidence"
      validate_evidence_token texture_sampling_evidence "$texture_sampling_evidence"
      shader_rows=$((shader_rows + 1))
      ;;
    *)
      fail "unknown Windows capture row: $row"
      ;;
  esac

  captured_count=$((captured_count + 1))
  printf '%s\trow=%s priority=%s platform=windows backend=%s workload=%s required_metrics=%s external_profile_status=captured profiler_tool=%s profiler_artifact=%s machine_context=%s windows_version=%s gpu_vendor=%s gpu_model=%s driver_version=%s godot_version=%s rendering_driver=%s display_refresh_hz=%s gpu_pass_ms=%s draw_count=%s counter_evidence=%s event_timing_ms=%s resource_state_events=%s pipeline_state_evidence=%s gpu_timing_ms=%s cpu_gpu_overlap_ms=%s memory_allocation_mb=%s timing_capture_span_ms=%s draw_event_count=%s texture_sampling_evidence=%s buffer_update_events=%s resource_lifetime_events=%s shader_pass_ms=%s vertex_stage_ms=%s fragment_stage_ms=%s shader_cost_evidence=%s\n' \
    "$priority" \
    "$row" \
    "$priority" \
    "$backend" \
    "$workload" \
    "$required_metrics" \
    "$profiler_tool" \
    "$profiler_artifact" \
    "$machine_context" \
    "$windows_version" \
    "$gpu_vendor" \
    "$gpu_model" \
    "$driver_version" \
    "$godot_version" \
    "$rendering_driver" \
    "$display_refresh_hz" \
    "$gpu_pass_ms" \
    "$draw_count" \
    "$counter_evidence" \
    "$event_timing_ms" \
    "$resource_state_events" \
    "$pipeline_state_evidence" \
    "$gpu_timing_ms" \
    "$cpu_gpu_overlap_ms" \
    "$memory_allocation_mb" \
    "$timing_capture_span_ms" \
    "$draw_event_count" \
    "$texture_sampling_evidence" \
    "$buffer_update_events" \
    "$resource_lifetime_events" \
    "$shader_pass_ms" \
    "$vertex_stage_ms" \
    "$fragment_stage_ms" \
    "$shader_cost_evidence"
done < "$tmp_result_rows" > "$tmp_result_lines"

missing_count=0
: > "$tmp_summary"
{
  printf 'GPU Windows capture results summary\n'
  printf 'manifest=%s\n' "$(relative_path "$MANIFEST_PATH")"
  printf 'results=%s\n' "$(relative_path "$RESULTS_PATH")"
  printf 'note=external_profile_status=captured rows are external profiler evidence; pending rows are rejected\n'
} >> "$tmp_summary"

sort -n -k1,1 "$tmp_result_lines" | cut -f2- >> "$tmp_summary"

while IFS='|' read -r priority row backend profiler_tool workload required_metrics; do
  if ! grep -F -x -q "${priority}|${row}" "$tmp_seen_keys"; then
    missing_count=$((missing_count + 1))
    printf 'missing row=%s priority=%s platform=windows backend=%s profiler_tool=%s workload=%s required_metrics=%s\n' \
      "$row" \
      "$priority" \
      "$backend" \
      "$profiler_tool" \
      "$workload" \
      "$required_metrics" >> "$tmp_summary"
  fi
done < "$tmp_plan_index"

metrics="$(
  awk '
    /^row=/ {
      for (i = 1; i <= NF; i++) {
        split($i, kv, "=")
        if (kv[1] == "gpu_pass_ms" && kv[2] + 0 > max_gpu_pass_ms) max_gpu_pass_ms = kv[2] + 0
        if (kv[1] == "draw_count" && kv[2] + 0 > max_draw_count) max_draw_count = kv[2] + 0
        if (kv[1] == "gpu_timing_ms" && kv[2] != "n/a" && kv[2] + 0 > max_gpu_timing_ms) max_gpu_timing_ms = kv[2] + 0
        if (kv[1] == "shader_pass_ms" && kv[2] != "n/a" && kv[2] + 0 > max_shader_pass_ms) max_shader_pass_ms = kv[2] + 0
        if (kv[1] == "vertex_stage_ms" && kv[2] != "n/a" && kv[2] + 0 > max_vertex_stage_ms) max_vertex_stage_ms = kv[2] + 0
        if (kv[1] == "fragment_stage_ms" && kv[2] != "n/a" && kv[2] + 0 > max_fragment_stage_ms) max_fragment_stage_ms = kv[2] + 0
      }
    }
    END {
      printf("max_windows_gpu_pass_ms=%.3f max_windows_draw_count=%.3f max_windows_gpu_timing_ms=%.3f max_windows_shader_pass_ms=%.3f max_windows_vertex_stage_ms=%.3f max_windows_fragment_stage_ms=%.3f\n", max_gpu_pass_ms, max_draw_count, max_gpu_timing_ms, max_shader_pass_ms, max_vertex_stage_ms, max_fragment_stage_ms)
    }
  ' "$tmp_summary"
)"

{
  printf 'gpu_windows_capture_results status=pass reason=windows_capture_rows_valid windows_capture_results_status=captured windows_gpu_capture_status=captured external_profile_status=captured planned_rows=%s captured_rows=%s missing_rows=%s windows_rows=%s pix_gpu_rows=%s pix_timing_rows=%s renderdoc_rows=%s shader_rows=%s allow_partial=%s default_runtime_change_allowed=0 requires_external_profiler_before_default=0 requires_mac_windows_validation=1 mac_windows_validation_status=windows_captured_macos_peer_required manifest=%s results=%s %s\n' \
    "$plan_count" \
    "$captured_count" \
    "$missing_count" \
    "$captured_count" \
    "$pix_gpu_rows" \
    "$pix_timing_rows" \
    "$renderdoc_rows" \
    "$shader_rows" \
    "$ALLOW_PARTIAL" \
    "$(relative_path "$MANIFEST_PATH")" \
    "$(relative_path "$RESULTS_PATH")" \
    "$metrics"
} >> "$tmp_summary"

test "$captured_count" -gt 0 || fail "results contain no captured rows"
if [ "$ALLOW_PARTIAL" != "1" ] && [ "$missing_count" -ne 0 ]; then
  fail "results missing $missing_count planned rows; set RUMPELMC_WINDOWS_CAPTURE_RESULTS_ALLOW_PARTIAL=1 for partial handoff validation"
fi

mv "$tmp_summary" "$OUT_PATH"
cat "$OUT_PATH"
