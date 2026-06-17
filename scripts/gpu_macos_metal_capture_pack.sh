#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/gpu_macos_metal_capture_pack_current"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

SUMMARY_PATH="$OUT_DIR/gpu-macos-metal-capture-pack-summary.txt"
MANIFEST_PATH="$OUT_DIR/gpu-macos-metal-capture-manifest.txt"
CHECKLIST_PATH="$OUT_DIR/gpu-macos-metal-capture-checklist.txt"

WORLD_INTERACTION_CHECKPOINT_SUMMARY="${RUMPELMC_MACOS_METAL_CAPTURE_WORLD_INTERACTION_CHECKPOINT_SUMMARY:-"$ROOT_DIR/logs/gpu_world_interaction_checkpoint_current/gpu-world-interaction-checkpoint-summary.txt"}"
SHADER_CAPTURE_PACK="${RUMPELMC_MACOS_METAL_CAPTURE_SHADER_CAPTURE_PACK:-"$ROOT_DIR/logs/gpu_shader_profiler_capture_pack_current/shader-profiler-capture-pack.txt"}"
EXTERNAL_PROFILING_CAMPAIGN_SUMMARY="${RUMPELMC_MACOS_METAL_CAPTURE_EXTERNAL_PROFILING_CAMPAIGN_SUMMARY:-"$ROOT_DIR/logs/external_profiling_campaign_current/external-profiling-campaign-summary.txt"}"
DESIGN_DOC="${RUMPELMC_MACOS_METAL_CAPTURE_DOC:-"$ROOT_DIR/docs/GPU_MACOS_METAL_CAPTURE_PACK.md"}"
GPU_PROFILING_DOC="${RUMPELMC_MACOS_METAL_CAPTURE_GPU_PROFILING_DOC:-"$ROOT_DIR/docs/GPU_PROFILING.md"}"

mkdir -p "$OUT_DIR"

fail() {
  echo "gpu_macos_metal_capture_pack: $*" >&2
  exit 1
}

normalize_path() {
  path="$1"
  case "$path" in
    /*) printf '%s\n' "$path" ;;
    *) printf '%s\n' "$ROOT_DIR/$path" ;;
  esac
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

metric_or() {
  key="$1"
  path="$2"
  fallback="$3"
  value="$(field_metric "$key" "$path")"
  if [ -n "$value" ]; then
    printf '%s\n' "$value"
  else
    printf '%s\n' "$fallback"
  fi
}

require_token() {
  path="$1"
  token="$2"
  test -s "$path" || fail "missing file $path"
  grep -Fq "$token" "$path" || fail "missing token '$token' in $(relative_path "$path")"
}

require_metric_eq() {
  label="$1"
  path="$2"
  key="$3"
  expected="$4"
  value="$(field_metric "$key" "$path")"
  test -n "$value" || fail "missing $key in $(relative_path "$path")"
  if [ "$value" != "$expected" ]; then
    fail "$label $key=$value, expected $expected in $(relative_path "$path")"
  fi
}

require_metric_positive() {
  label="$1"
  path="$2"
  key="$3"
  value="$(field_metric "$key" "$path")"
  test -n "$value" || fail "missing $key in $(relative_path "$path")"
  awk -v value="$value" -v label="$label" -v key="$key" -v path="$(relative_path "$path")" '
    BEGIN {
      if (value + 0.0 <= 0.0) {
        printf("gpu_macos_metal_capture_pack: %s %s=%s must be positive in %s\n", label, key, value, path) > "/dev/stderr"
        exit 1
      }
    }
  '
  printf '%s\n' "$value"
}

WORLD_INTERACTION_CHECKPOINT_SUMMARY="$(normalize_path "$WORLD_INTERACTION_CHECKPOINT_SUMMARY")"
SHADER_CAPTURE_PACK="$(normalize_path "$SHADER_CAPTURE_PACK")"
EXTERNAL_PROFILING_CAMPAIGN_SUMMARY="$(normalize_path "$EXTERNAL_PROFILING_CAMPAIGN_SUMMARY")"
DESIGN_DOC="$(normalize_path "$DESIGN_DOC")"
GPU_PROFILING_DOC="$(normalize_path "$GPU_PROFILING_DOC")"

test -s "$WORLD_INTERACTION_CHECKPOINT_SUMMARY" || fail "missing world interaction checkpoint $WORLD_INTERACTION_CHECKPOINT_SUMMARY"
test -s "$DESIGN_DOC" || fail "missing design doc $DESIGN_DOC"
test -s "$GPU_PROFILING_DOC" || fail "missing GPU profiling doc $GPU_PROFILING_DOC"

for token in \
  'macOS Metal capture pack' \
  'Xcode Metal frame capture' \
  'Metal System Trace' \
  'pending handoff state' \
  'not profiler evidence'; do
  require_token "$DESIGN_DOC" "$token"
done

for token in \
  'macOS Metal Workflow' \
  'Godot `RenderingDevice` timestamp samples currently report `0.0us`' \
  'Use the world interaction checkpoint' \
  'Use the macOS Metal capture pack'; do
  require_token "$GPU_PROFILING_DOC" "$token"
done

require_metric_eq world_interaction "$WORLD_INTERACTION_CHECKPOINT_SUMMARY" status pass
require_metric_eq world_interaction "$WORLD_INTERACTION_CHECKPOINT_SUMMARY" checkpoint_status local_complete_external_pending
require_metric_eq world_interaction "$WORLD_INTERACTION_CHECKPOINT_SUMMARY" local_world_interaction_status pass
require_metric_eq world_interaction "$WORLD_INTERACTION_CHECKPOINT_SUMMARY" rollout_status defer_defaults
require_metric_eq world_interaction "$WORLD_INTERACTION_CHECKPOINT_SUMMARY" gpu_upload_fail 0
require_metric_eq world_interaction "$WORLD_INTERACTION_CHECKPOINT_SUMMARY" ground_misses 0
require_metric_eq world_interaction "$WORLD_INTERACTION_CHECKPOINT_SUMMARY" default_runtime_change_allowed 0
require_metric_eq world_interaction "$WORLD_INTERACTION_CHECKPOINT_SUMMARY" visible_quality_change_allowed 0
require_metric_eq world_interaction "$WORLD_INTERACTION_CHECKPOINT_SUMMARY" scheduler_change_allowed 0
require_metric_eq world_interaction "$WORLD_INTERACTION_CHECKPOINT_SUMMARY" requires_external_profiler_before_default 1
require_metric_eq world_interaction "$WORLD_INTERACTION_CHECKPOINT_SUMMARY" requires_mac_windows_validation 1
require_metric_eq world_interaction "$WORLD_INTERACTION_CHECKPOINT_SUMMARY" external_profile_status pending_external_profiler

source_count="$(require_metric_positive world_interaction "$WORLD_INTERACTION_CHECKPOINT_SUMMARY" source_count)"
pass_sources="$(require_metric_positive world_interaction "$WORLD_INTERACTION_CHECKPOINT_SUMMARY" pass_sources)"
max_terrain_queue_ms="$(require_metric_positive world_interaction "$WORLD_INTERACTION_CHECKPOINT_SUMMARY" max_terrain_queue_ms)"
max_process_wall_p95_ms="$(require_metric_positive world_interaction "$WORLD_INTERACTION_CHECKPOINT_SUMMARY" max_process_wall_p95_ms)"
max_gpu_compositor_submit_ms="$(require_metric_positive world_interaction "$WORLD_INTERACTION_CHECKPOINT_SUMMARY" max_gpu_compositor_submit_ms)"
max_dirty_blocks="$(metric_or max_dirty_blocks "$WORLD_INTERACTION_CHECKPOINT_SUMMARY" n/a)"
max_compact_shadow_proxy="$(metric_or max_compact_shadow_proxy "$WORLD_INTERACTION_CHECKPOINT_SUMMARY" n/a)"
max_avg_luma_delta="$(metric_or max_avg_luma_delta "$WORLD_INTERACTION_CHECKPOINT_SUMMARY" n/a)"
max_uploads_per_frame="$(metric_or max_uploads_per_frame "$WORLD_INTERACTION_CHECKPOINT_SUMMARY" n/a)"
max_upload_kb_per_frame="$(metric_or max_upload_kb_per_frame "$WORLD_INTERACTION_CHECKPOINT_SUMMARY" n/a)"

shader_capture_pack_status="missing_optional"
shader_capture_pack_capture_status="missing_optional"
if [ -s "$SHADER_CAPTURE_PACK" ]; then
  require_metric_eq shader_capture_pack "$SHADER_CAPTURE_PACK" status pass
  shader_capture_pack_status="$(metric_or status "$SHADER_CAPTURE_PACK" missing)"
  shader_capture_pack_capture_status="$(metric_or capture_pack_status "$SHADER_CAPTURE_PACK" missing)"
fi

external_campaign_status="missing_optional"
external_campaign_profile_status="missing_optional"
if [ -s "$EXTERNAL_PROFILING_CAMPAIGN_SUMMARY" ]; then
  require_metric_eq external_profiling_campaign "$EXTERNAL_PROFILING_CAMPAIGN_SUMMARY" status pass
  external_campaign_status="$(metric_or status "$EXTERNAL_PROFILING_CAMPAIGN_SUMMARY" missing)"
  external_campaign_profile_status="$(metric_or external_profile_status "$EXTERNAL_PROFILING_CAMPAIGN_SUMMARY" missing)"
fi

{
  printf 'macos_metal_capture_manifest status=prepared capture_pack_status=pending_external_profiler world_interaction_summary=%s\n' \
    "$(relative_path "$WORLD_INTERACTION_CHECKPOINT_SUMMARY")"
  printf 'row=world_interaction_checkpoint priority=1 platform=macos backend=metal profiler_tool=xcode_metal_frame_capture capture_status=pending_external_profiler workload=world_interaction required_metrics=gpu_pass_time,draw_count,encoder_stage_time,buffer_updates,hardware_counters,counter_evidence source_summary=%s\n' \
    "$(relative_path "$WORLD_INTERACTION_CHECKPOINT_SUMMARY")"
  printf 'row=metal_system_trace_world_interaction priority=2 platform=macos backend=metal profiler_tool=instruments_metal_system_trace capture_status=pending_external_profiler workload=world_interaction required_metrics=cpu_gpu_overlap,command_buffer_timeline,memory_pressure,driver_waits,counter_evidence source_summary=%s\n' \
    "$(relative_path "$WORLD_INTERACTION_CHECKPOINT_SUMMARY")"
  printf 'row=world_upload_pressure priority=3 platform=macos backend=metal profiler_tool=xcode_metal_memory_report capture_status=pending_external_profiler workload=world_upload_pressure required_metrics=buffer_residency,resource_lifetime,upload_bytes,staging_cost,counter_evidence source_summary=%s\n' \
    "$(relative_path "$WORLD_INTERACTION_CHECKPOINT_SUMMARY")"
  printf 'row=shader_hot_path priority=4 platform=macos backend=metal profiler_tool=xcode_metal_shader_cost capture_status=pending_external_profiler workload=terrain_shader required_metrics=vertex_stage_ms,fragment_stage_ms,shader_cost,texture_sampling,counter_evidence source_summary=%s optional_shader_capture_pack=%s optional_shader_capture_status=%s\n' \
    "$(relative_path "$WORLD_INTERACTION_CHECKPOINT_SUMMARY")" \
    "$(relative_path "$SHADER_CAPTURE_PACK")" \
    "$shader_capture_pack_status"
  printf 'policy pending_capture_pack_is_not_evidence=1 local_fps_is_warning_only=1 godot_gpu_timestamp_is_warning_only=1 captured_rows_required_before_claiming_gpu_time=1 default_runtime_change_allowed=0 requires_windows_validation_before_default=1\n'
} > "$MANIFEST_PATH"

{
  printf 'macos_metal_capture_checklist status=prepared\n'
  printf 'step=run_release_checkpoint command="sh scripts/gpu_world_interaction_checkpoint.sh logs/gpu_world_interaction_checkpoint_current"\n'
  printf 'step=capture_frame tool=xcode_metal_frame_capture artifact=external_trace_required source_manifest=%s\n' "$(relative_path "$MANIFEST_PATH")"
  printf 'step=capture_system_trace tool=instruments_metal_system_trace artifact=external_trace_required source_manifest=%s\n' "$(relative_path "$MANIFEST_PATH")"
  printf 'step=record_machine_context fields=mac_model,chip,gpu,macos_version,xcode_version,godot_version,backend,display_refresh,driver_notes\n'
  printf 'step=record_profiler_rows requirement=external_profile_status=captured validation=future_results_checker_required\n'
  printf 'policy generated_pack_is_not_profiler_evidence=1 default_runtime_change_allowed=0 requires_mac_windows_validation=1\n'
} > "$CHECKLIST_PATH"

{
  printf 'gpu_macos_metal_capture_pack status=pass reason=ready_for_xcode_metal_capture capture_pack_status=pending_external_profiler macos_metal_capture_status=pending_external_profiler macos_metal_capture_rows=4 captured_rows=0 missing_rows=4 external_profile_status=pending_external_profiler local_world_interaction_status=pass checkpoint_status=local_complete_external_pending rollout_status=defer_defaults source_count=%s pass_sources=%s max_terrain_queue_ms=%s max_process_wall_p95_ms=%s max_gpu_compositor_submit_ms=%s max_dirty_blocks=%s max_compact_shadow_proxy=%s max_avg_luma_delta=%s max_uploads_per_frame=%s max_upload_kb_per_frame=%s gpu_upload_fail=0 ground_misses=0 default_runtime_change_allowed=0 visible_quality_change_allowed=0 scheduler_change_allowed=0 requires_external_profiler_before_default=1 requires_mac_windows_validation=1 mac_windows_validation_status=pending_external_validation profiler_scope=macos_metal_xcode_frame_capture_system_trace_shader_cost_and_memory_report metal_toolchain=xcode_metal_debugger_instruments_gpucapture_gpudebug_metalperftrace shader_capture_pack_status=%s shader_capture_pack_capture_status=%s external_campaign_status=%s external_campaign_profile_status=%s manifest=%s checklist=%s world_interaction_summary=%s shader_capture_pack=%s external_profiling_campaign_summary=%s\n' \
    "$source_count" \
    "$pass_sources" \
    "$max_terrain_queue_ms" \
    "$max_process_wall_p95_ms" \
    "$max_gpu_compositor_submit_ms" \
    "$max_dirty_blocks" \
    "$max_compact_shadow_proxy" \
    "$max_avg_luma_delta" \
    "$max_uploads_per_frame" \
    "$max_upload_kb_per_frame" \
    "$shader_capture_pack_status" \
    "$shader_capture_pack_capture_status" \
    "$external_campaign_status" \
    "$external_campaign_profile_status" \
    "$(relative_path "$MANIFEST_PATH")" \
    "$(relative_path "$CHECKLIST_PATH")" \
    "$(relative_path "$WORLD_INTERACTION_CHECKPOINT_SUMMARY")" \
    "$(relative_path "$SHADER_CAPTURE_PACK")" \
    "$(relative_path "$EXTERNAL_PROFILING_CAMPAIGN_SUMMARY")"
  printf 'policy pending_capture_pack_is_not_evidence=1 local_fps_is_warning_only=1 godot_gpu_timestamp_is_warning_only=1 profiler_rows_required_before_claiming_gpu_time=1 default_runtime_change_allowed=0\n'
  printf 'command_generate_pack=sh scripts/gpu_macos_metal_capture_pack.sh %s\n' "$(relative_path "$OUT_DIR")"
} > "$SUMMARY_PATH"

cat "$SUMMARY_PATH"
