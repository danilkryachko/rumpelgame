#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/gpu_world_interaction_checkpoint_current"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

SUMMARY_PATH="$OUT_DIR/gpu-world-interaction-checkpoint-summary.txt"
CASES_PATH="$OUT_DIR/gpu-world-interaction-checkpoint-sources.txt"

REPEATED_EDIT_BENCHMARK_SUMMARY="${RUMPELMC_WORLD_INTERACTION_CHECKPOINT_REPEATED_EDIT_BENCHMARK_SUMMARY:-"$ROOT_DIR/logs/gpu_terrain_repeated_edit_benchmark_current/gpu-terrain-repeated-edit-benchmark-summary.txt"}"
BORDER_EDIT_BENCHMARK_SUMMARY="${RUMPELMC_WORLD_INTERACTION_CHECKPOINT_BORDER_EDIT_BENCHMARK_SUMMARY:-"$ROOT_DIR/logs/gpu_terrain_border_edit_benchmark_current/gpu-terrain-border-edit-benchmark-summary.txt"}"
PARTIAL_DIRTY_EDGE_MATRIX_SUMMARY="${RUMPELMC_WORLD_INTERACTION_CHECKPOINT_PARTIAL_DIRTY_EDGE_MATRIX_SUMMARY:-"$ROOT_DIR/logs/gpu_terrain_partial_dirty_edge_matrix_current/gpu-terrain-partial-dirty-edge-matrix-summary.txt"}"
COLLISION_REFRESH_COST_AUDIT_SUMMARY="${RUMPELMC_WORLD_INTERACTION_CHECKPOINT_COLLISION_REFRESH_COST_AUDIT_SUMMARY:-"$ROOT_DIR/logs/gpu_collision_refresh_cost_audit_current/gpu-collision-refresh-cost-audit-summary.txt"}"
SHADOW_PROXY_REFRESH_COST_AUDIT_SUMMARY="${RUMPELMC_WORLD_INTERACTION_CHECKPOINT_SHADOW_PROXY_REFRESH_COST_AUDIT_SUMMARY:-"$ROOT_DIR/logs/gpu_shadow_proxy_refresh_cost_audit_current/gpu-shadow-proxy-refresh-cost-audit-summary.txt"}"
EDIT_BURST_BUDGET_SUMMARY="${RUMPELMC_WORLD_INTERACTION_CHECKPOINT_EDIT_BURST_BUDGET_SUMMARY:-"$ROOT_DIR/logs/gpu_edit_burst_budget_gate_current/gpu-edit-burst-budget-summary.txt"}"
EDIT_VISUAL_PARITY_SUMMARY="${RUMPELMC_WORLD_INTERACTION_CHECKPOINT_EDIT_VISUAL_PARITY_SUMMARY:-"$ROOT_DIR/logs/gpu_edit_visual_parity_gate_current/gpu-edit-visual-parity-summary.txt"}"
UPLOAD_BUDGET_SUMMARY="${RUMPELMC_WORLD_INTERACTION_CHECKPOINT_UPLOAD_BUDGET_SUMMARY:-"$ROOT_DIR/logs/gpu_terrain_upload_budget_current/gpu-terrain-upload-budget-summary.txt"}"

mkdir -p "$OUT_DIR"

fail() {
  echo "gpu_world_interaction_checkpoint: $*" >&2
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

require_status() {
  label="$1"
  path="$2"
  expected="$3"
  test -s "$path" || fail "missing $label summary $path"
  value="$(field_metric status "$path")"
  test -n "$value" || fail "missing status in $(relative_path "$path")"
  if [ "$value" != "$expected" ]; then
    fail "$label status=$value, expected $expected"
  fi
}

require_text_metric() {
  label="$1"
  path="$2"
  key="$3"
  expected="$4"
  value="$(field_metric "$key" "$path")"
  test -n "$value" || fail "missing $key in $(relative_path "$path")"
  if [ "$value" != "$expected" ]; then
    fail "$label $key=$value, expected $expected"
  fi
}

require_number_eq() {
  label="$1"
  path="$2"
  key="$3"
  expected="$4"
  value="$(field_metric "$key" "$path")"
  test -n "$value" || fail "missing $key in $(relative_path "$path")"
  awk -v value="$value" -v expected="$expected" -v label="$label" -v key="$key" -v path="$(relative_path "$path")" '
    BEGIN {
      if (value + 0 != expected + 0) {
        printf("gpu_world_interaction_checkpoint: %s %s=%s, expected %s in %s\n", label, key, value, expected, path) > "/dev/stderr"
        exit 1
      }
    }
  '
}

require_number_ge() {
  label="$1"
  path="$2"
  key="$3"
  minimum="$4"
  value="$(field_metric "$key" "$path")"
  test -n "$value" || fail "missing $key in $(relative_path "$path")"
  awk -v value="$value" -v minimum="$minimum" -v label="$label" -v key="$key" -v path="$(relative_path "$path")" '
    BEGIN {
      if (value + 0 < minimum + 0) {
        printf("gpu_world_interaction_checkpoint: %s %s=%s below %s in %s\n", label, key, value, minimum, path) > "/dev/stderr"
        exit 1
      }
    }
  '
}

metric_or_na() {
  key="$1"
  path="$2"
  value="$(field_metric "$key" "$path")"
  if [ -n "$value" ]; then
    printf '%s\n' "$value"
  else
    printf 'n/a\n'
  fi
}

max_metric() {
  key="$1"
  shift
  awk -v key="$key" '
    BEGIN {
      prefix = key "="
      found = 0
      max_value = 0.0
      max_text = "n/a"
    }
    {
      for (i = 1; i <= NF; i++) {
        if (index($i, prefix) == 1) {
          raw = substr($i, length(prefix) + 1)
          gsub(/^"/, "", raw)
          gsub(/"$/, "", raw)
          if (match(raw, /^-?[0-9]+([.][0-9]+)?/)) {
            text = substr(raw, RSTART, RLENGTH)
            value = text + 0.0
            if (!found || value > max_value) {
              max_value = value
              max_text = text
              found = 1
            }
          }
        }
      }
    }
    END {
      print max_text
    }
  ' "$@"
}

append_source() {
  id="$1"
  category="$2"
  path="$3"
  root_token="$(awk '{ print $1; exit }' "$path")"
  status="$(metric_or_na status "$path")"
  max_terrain_queue_ms="$(metric_or_na max_terrain_queue_ms "$path")"
  max_process_wall_p95_ms="$(metric_or_na max_process_wall_p95_ms "$path")"
  max_gpu_compositor_submit_ms="$(metric_or_na max_gpu_compositor_submit_ms "$path")"
  gpu_upload_fail="$(metric_or_na gpu_upload_fail "$path")"
  max_upload_fail="$(metric_or_na max_upload_fail "$path")"
  ground_misses="$(metric_or_na ground_misses "$path")"
  default_runtime_change_allowed="$(metric_or_na default_runtime_change_allowed "$path")"
  visible_quality_change_allowed="$(metric_or_na visible_quality_change_allowed "$path")"
  scheduler_change_allowed="$(metric_or_na scheduler_change_allowed "$path")"
  requires_external_profiler_before_default="$(metric_or_na requires_external_profiler_before_default "$path")"
  requires_mac_windows_validation="$(metric_or_na requires_mac_windows_validation "$path")"
  external_profile_status="$(metric_or_na external_profile_status "$path")"

  printf 'source=%s category=%s status=%s path=%s root=%s max_terrain_queue_ms=%s max_process_wall_p95_ms=%s max_gpu_compositor_submit_ms=%s gpu_upload_fail=%s max_upload_fail=%s ground_misses=%s default_runtime_change_allowed=%s visible_quality_change_allowed=%s scheduler_change_allowed=%s requires_external_profiler_before_default=%s requires_mac_windows_validation=%s external_profile_status=%s\n' \
    "$id" \
    "$category" \
    "$status" \
    "$(relative_path "$path")" \
    "$root_token" \
    "$max_terrain_queue_ms" \
    "$max_process_wall_p95_ms" \
    "$max_gpu_compositor_submit_ms" \
    "$gpu_upload_fail" \
    "$max_upload_fail" \
    "$ground_misses" \
    "$default_runtime_change_allowed" \
    "$visible_quality_change_allowed" \
    "$scheduler_change_allowed" \
    "$requires_external_profiler_before_default" \
    "$requires_mac_windows_validation" \
    "$external_profile_status" \
    >> "$CASES_PATH"
}

REPEATED_EDIT_BENCHMARK_SUMMARY="$(normalize_path "$REPEATED_EDIT_BENCHMARK_SUMMARY")"
BORDER_EDIT_BENCHMARK_SUMMARY="$(normalize_path "$BORDER_EDIT_BENCHMARK_SUMMARY")"
PARTIAL_DIRTY_EDGE_MATRIX_SUMMARY="$(normalize_path "$PARTIAL_DIRTY_EDGE_MATRIX_SUMMARY")"
COLLISION_REFRESH_COST_AUDIT_SUMMARY="$(normalize_path "$COLLISION_REFRESH_COST_AUDIT_SUMMARY")"
SHADOW_PROXY_REFRESH_COST_AUDIT_SUMMARY="$(normalize_path "$SHADOW_PROXY_REFRESH_COST_AUDIT_SUMMARY")"
EDIT_BURST_BUDGET_SUMMARY="$(normalize_path "$EDIT_BURST_BUDGET_SUMMARY")"
EDIT_VISUAL_PARITY_SUMMARY="$(normalize_path "$EDIT_VISUAL_PARITY_SUMMARY")"
UPLOAD_BUDGET_SUMMARY="$(normalize_path "$UPLOAD_BUDGET_SUMMARY")"

require_status repeated_edit_benchmark "$REPEATED_EDIT_BENCHMARK_SUMMARY" pass
require_status border_edit_benchmark "$BORDER_EDIT_BENCHMARK_SUMMARY" pass
require_status partial_dirty_edge_matrix "$PARTIAL_DIRTY_EDGE_MATRIX_SUMMARY" pass
require_status collision_refresh_cost_audit "$COLLISION_REFRESH_COST_AUDIT_SUMMARY" pass
require_status shadow_proxy_refresh_cost_audit "$SHADOW_PROXY_REFRESH_COST_AUDIT_SUMMARY" pass
require_status edit_burst_budget "$EDIT_BURST_BUDGET_SUMMARY" pass
require_status edit_visual_parity "$EDIT_VISUAL_PARITY_SUMMARY" pass
require_status upload_budget "$UPLOAD_BUDGET_SUMMARY" pass

for path in \
  "$REPEATED_EDIT_BENCHMARK_SUMMARY" \
  "$BORDER_EDIT_BENCHMARK_SUMMARY" \
  "$PARTIAL_DIRTY_EDGE_MATRIX_SUMMARY" \
  "$COLLISION_REFRESH_COST_AUDIT_SUMMARY" \
  "$SHADOW_PROXY_REFRESH_COST_AUDIT_SUMMARY" \
  "$EDIT_BURST_BUDGET_SUMMARY" \
  "$EDIT_VISUAL_PARITY_SUMMARY"; do
  require_number_eq "$(relative_path "$path")" "$path" default_runtime_change_allowed 0
  require_number_eq "$(relative_path "$path")" "$path" visible_quality_change_allowed 0
  require_number_eq "$(relative_path "$path")" "$path" requires_external_profiler_before_default 1
  require_number_eq "$(relative_path "$path")" "$path" requires_mac_windows_validation 1
done

for path in \
  "$REPEATED_EDIT_BENCHMARK_SUMMARY" \
  "$BORDER_EDIT_BENCHMARK_SUMMARY" \
  "$PARTIAL_DIRTY_EDGE_MATRIX_SUMMARY" \
  "$EDIT_BURST_BUDGET_SUMMARY"; do
  require_number_eq "$(relative_path "$path")" "$path" scheduler_change_allowed 0
done

require_number_eq repeated_edit_benchmark "$REPEATED_EDIT_BENCHMARK_SUMMARY" gpu_upload_fail 0
require_number_eq border_edit_benchmark "$BORDER_EDIT_BENCHMARK_SUMMARY" gpu_upload_fail 0
require_number_eq partial_dirty_edge_matrix "$PARTIAL_DIRTY_EDGE_MATRIX_SUMMARY" gpu_upload_fail 0
require_number_eq collision_refresh_cost_audit "$COLLISION_REFRESH_COST_AUDIT_SUMMARY" gpu_upload_fail 0
require_number_eq shadow_proxy_refresh_cost_audit "$SHADOW_PROXY_REFRESH_COST_AUDIT_SUMMARY" gpu_upload_fail 0
require_number_eq edit_burst_budget "$EDIT_BURST_BUDGET_SUMMARY" gpu_upload_fail 0
require_number_eq edit_visual_parity "$EDIT_VISUAL_PARITY_SUMMARY" gpu_upload_fail 0
require_number_eq upload_budget "$UPLOAD_BUDGET_SUMMARY" max_upload_fail 0

require_number_eq border_edit_benchmark "$BORDER_EDIT_BENCHMARK_SUMMARY" ground_misses 0
require_number_eq collision_refresh_cost_audit "$COLLISION_REFRESH_COST_AUDIT_SUMMARY" ground_misses 0
require_number_eq shadow_proxy_refresh_cost_audit "$SHADOW_PROXY_REFRESH_COST_AUDIT_SUMMARY" ground_misses 0
require_number_eq edit_burst_budget "$EDIT_BURST_BUDGET_SUMMARY" ground_misses 0
require_number_eq edit_visual_parity "$EDIT_VISUAL_PARITY_SUMMARY" ground_misses 0

require_number_ge repeated_edit_benchmark "$REPEATED_EDIT_BENCHMARK_SUMMARY" single_edge_runs 3
require_number_ge repeated_edit_benchmark "$REPEATED_EDIT_BENCHMARK_SUMMARY" corner_edge_runs 3
require_number_ge border_edit_benchmark "$BORDER_EDIT_BENCHMARK_SUMMARY" max_dirty_blocks 512
require_number_eq partial_dirty_edge_matrix "$PARTIAL_DIRTY_EDGE_MATRIX_SUMMARY" case_count 8
require_number_eq partial_dirty_edge_matrix "$PARTIAL_DIRTY_EDGE_MATRIX_SUMMARY" single_edge_cases 4
require_number_eq partial_dirty_edge_matrix "$PARTIAL_DIRTY_EDGE_MATRIX_SUMMARY" corner_edge_cases 4
require_number_ge collision_refresh_cost_audit "$COLLISION_REFRESH_COST_AUDIT_SUMMARY" case_count 18
require_number_ge shadow_proxy_refresh_cost_audit "$SHADOW_PROXY_REFRESH_COST_AUDIT_SUMMARY" case_count 18
require_number_eq edit_burst_budget "$EDIT_BURST_BUDGET_SUMMARY" source_count 6
require_number_eq edit_burst_budget "$EDIT_BURST_BUDGET_SUMMARY" pass_sources 6
require_number_eq edit_visual_parity "$EDIT_VISUAL_PARITY_SUMMARY" case_count 8
require_number_eq edit_visual_parity "$EDIT_VISUAL_PARITY_SUMMARY" pass_cases 8
require_number_eq edit_visual_parity "$EDIT_VISUAL_PARITY_SUMMARY" marker_count 16
require_number_eq edit_visual_parity "$EDIT_VISUAL_PARITY_SUMMARY" visual_delta_failures 0
require_number_eq edit_visual_parity "$EDIT_VISUAL_PARITY_SUMMARY" block_edit_dirty_observed_failures 0
require_text_metric upload_budget "$UPLOAD_BUDGET_SUMMARY" movement_budget_status pass
require_text_metric upload_budget "$UPLOAD_BUDGET_SUMMARY" in_place_status pass
require_number_eq upload_budget "$UPLOAD_BUDGET_SUMMARY" in_place_enabled 1
require_number_ge upload_budget "$UPLOAD_BUDGET_SUMMARY" in_place_uploads 1

: > "$CASES_PATH"
append_source repeated_edit_benchmark dirty_runtime "$REPEATED_EDIT_BENCHMARK_SUMMARY"
append_source border_edit_benchmark dirty_runtime "$BORDER_EDIT_BENCHMARK_SUMMARY"
append_source partial_dirty_edge_matrix dirty_correctness "$PARTIAL_DIRTY_EDGE_MATRIX_SUMMARY"
append_source collision_refresh_cost_audit collision "$COLLISION_REFRESH_COST_AUDIT_SUMMARY"
append_source shadow_proxy_refresh_cost_audit shadow "$SHADOW_PROXY_REFRESH_COST_AUDIT_SUMMARY"
append_source edit_burst_budget budget "$EDIT_BURST_BUDGET_SUMMARY"
append_source edit_visual_parity visual "$EDIT_VISUAL_PARITY_SUMMARY"
append_source upload_budget upload "$UPLOAD_BUDGET_SUMMARY"

source_count=8
pass_sources=8
max_terrain_queue_ms="$(max_metric max_terrain_queue_ms "$REPEATED_EDIT_BENCHMARK_SUMMARY" "$BORDER_EDIT_BENCHMARK_SUMMARY" "$PARTIAL_DIRTY_EDGE_MATRIX_SUMMARY" "$COLLISION_REFRESH_COST_AUDIT_SUMMARY" "$SHADOW_PROXY_REFRESH_COST_AUDIT_SUMMARY" "$EDIT_BURST_BUDGET_SUMMARY")"
max_process_wall_p95_ms="$(max_metric max_process_wall_p95_ms "$REPEATED_EDIT_BENCHMARK_SUMMARY" "$BORDER_EDIT_BENCHMARK_SUMMARY" "$PARTIAL_DIRTY_EDGE_MATRIX_SUMMARY" "$COLLISION_REFRESH_COST_AUDIT_SUMMARY" "$SHADOW_PROXY_REFRESH_COST_AUDIT_SUMMARY" "$EDIT_BURST_BUDGET_SUMMARY")"
max_gpu_compositor_submit_ms="$(max_metric max_gpu_compositor_submit_ms "$REPEATED_EDIT_BENCHMARK_SUMMARY" "$BORDER_EDIT_BENCHMARK_SUMMARY" "$PARTIAL_DIRTY_EDGE_MATRIX_SUMMARY" "$COLLISION_REFRESH_COST_AUDIT_SUMMARY" "$SHADOW_PROXY_REFRESH_COST_AUDIT_SUMMARY" "$EDIT_BURST_BUDGET_SUMMARY")"
max_dirty_blocks="$(max_metric max_dirty_blocks "$BORDER_EDIT_BENCHMARK_SUMMARY" "$EDIT_BURST_BUDGET_SUMMARY")"
max_dirty_edge_neighbor_subchunks="$(max_metric max_dirty_edge_neighbor_subchunks "$BORDER_EDIT_BENCHMARK_SUMMARY" "$EDIT_BURST_BUDGET_SUMMARY")"
max_dirty_partial_saved_subchunks="$(max_metric max_dirty_partial_saved_subchunks "$BORDER_EDIT_BENCHMARK_SUMMARY" "$EDIT_BURST_BUDGET_SUMMARY")"
max_partial_edge_neighbor_subchunks="$(max_metric max_partial_edge_neighbor_subchunks "$PARTIAL_DIRTY_EDGE_MATRIX_SUMMARY" "$EDIT_BURST_BUDGET_SUMMARY")"
max_partial_saved_subchunks="$(max_metric max_partial_saved_subchunks "$PARTIAL_DIRTY_EDGE_MATRIX_SUMMARY" "$EDIT_BURST_BUDGET_SUMMARY")"
max_collision_refresh_rebuilt="$(max_metric max_collision_refresh_rebuilt "$COLLISION_REFRESH_COST_AUDIT_SUMMARY" "$EDIT_BURST_BUDGET_SUMMARY")"
max_collision_phase_total_ms="$(max_metric max_collision_phase_total_ms "$COLLISION_REFRESH_COST_AUDIT_SUMMARY" "$EDIT_BURST_BUDGET_SUMMARY")"
max_collision_phase_component_ms="$(max_metric max_collision_phase_component_ms "$COLLISION_REFRESH_COST_AUDIT_SUMMARY" "$EDIT_BURST_BUDGET_SUMMARY")"
max_proxy_shadow="$(max_metric max_proxy_shadow "$SHADOW_PROXY_REFRESH_COST_AUDIT_SUMMARY" "$EDIT_BURST_BUDGET_SUMMARY")"
max_compact_shadow_proxy="$(max_metric max_compact_shadow_proxy "$SHADOW_PROXY_REFRESH_COST_AUDIT_SUMMARY" "$EDIT_BURST_BUDGET_SUMMARY")"
max_compact_shadow_normals_saved="$(max_metric max_compact_shadow_normals_saved "$SHADOW_PROXY_REFRESH_COST_AUDIT_SUMMARY" "$EDIT_BURST_BUDGET_SUMMARY")"
max_proxy_refresh_reuse="$(max_metric max_proxy_refresh_reuse "$SHADOW_PROXY_REFRESH_COST_AUDIT_SUMMARY" "$EDIT_BURST_BUDGET_SUMMARY")"
max_avg_luma_delta="$(field_metric max_avg_luma_delta "$EDIT_VISUAL_PARITY_SUMMARY")"
max_terrain_luma_range_delta="$(field_metric max_terrain_luma_range_delta "$EDIT_VISUAL_PARITY_SUMMARY")"
max_terrain_samples_delta="$(field_metric max_terrain_samples_delta "$EDIT_VISUAL_PARITY_SUMMARY")"
max_terrain_color_bucket_delta="$(field_metric max_terrain_color_bucket_delta "$EDIT_VISUAL_PARITY_SUMMARY")"
max_uploads_per_frame="$(field_metric max_uploads_per_frame "$UPLOAD_BUDGET_SUMMARY")"
max_upload_kb_per_frame="$(field_metric max_upload_kb_per_frame "$UPLOAD_BUDGET_SUMMARY")"
max_upload_fail="$(field_metric max_upload_fail "$UPLOAD_BUDGET_SUMMARY")"

{
  printf 'gpu_world_interaction_checkpoint status=pass reason=ok checkpoint_status=local_complete_external_pending local_world_interaction_status=pass rollout_status=defer_defaults source_count=%s pass_sources=%s fail_sources=0 runtime_edit_status=pass dirty_correctness_status=pass collision_refresh_status=pass shadow_proxy_status=pass edit_burst_budget_status=pass edit_visual_parity_status=pass upload_budget_status=pass max_terrain_queue_ms=%s max_process_wall_p95_ms=%s max_gpu_compositor_submit_ms=%s max_dirty_blocks=%s max_dirty_edge_neighbor_subchunks=%s max_dirty_partial_saved_subchunks=%s max_partial_edge_neighbor_subchunks=%s max_partial_saved_subchunks=%s max_collision_refresh_rebuilt=%s max_collision_phase_total_ms=%s max_collision_phase_component_ms=%s max_proxy_shadow=%s max_compact_shadow_proxy=%s max_compact_shadow_normals_saved=%s max_proxy_refresh_reuse=%s max_avg_luma_delta=%s max_terrain_luma_range_delta=%s max_terrain_samples_delta=%s max_terrain_color_bucket_delta=%s max_uploads_per_frame=%s max_upload_kb_per_frame=%s gpu_upload_fail=0 max_upload_fail=%s ground_misses=0 default_runtime_change_allowed=0 visible_quality_change_allowed=0 scheduler_change_allowed=0 requires_external_profiler_before_default=1 requires_mac_windows_validation=1 external_profile_status=pending_external_profiler mac_windows_validation_status=pending_external_validation profiler_scope=macos_metal_and_windows_gpu_profiler required_next_step=cross_platform_profiler_validation sources_path=%s repeated_edit_benchmark_summary=%s border_edit_benchmark_summary=%s partial_dirty_edge_matrix_summary=%s collision_refresh_cost_audit_summary=%s shadow_proxy_refresh_cost_audit_summary=%s edit_burst_budget_summary=%s edit_visual_parity_summary=%s upload_budget_summary=%s\n' \
    "$source_count" \
    "$pass_sources" \
    "$max_terrain_queue_ms" \
    "$max_process_wall_p95_ms" \
    "$max_gpu_compositor_submit_ms" \
    "$max_dirty_blocks" \
    "$max_dirty_edge_neighbor_subchunks" \
    "$max_dirty_partial_saved_subchunks" \
    "$max_partial_edge_neighbor_subchunks" \
    "$max_partial_saved_subchunks" \
    "$max_collision_refresh_rebuilt" \
    "$max_collision_phase_total_ms" \
    "$max_collision_phase_component_ms" \
    "$max_proxy_shadow" \
    "$max_compact_shadow_proxy" \
    "$max_compact_shadow_normals_saved" \
    "$max_proxy_refresh_reuse" \
    "$max_avg_luma_delta" \
    "$max_terrain_luma_range_delta" \
    "$max_terrain_samples_delta" \
    "$max_terrain_color_bucket_delta" \
    "$max_uploads_per_frame" \
    "$max_upload_kb_per_frame" \
    "$max_upload_fail" \
    "$(relative_path "$CASES_PATH")" \
    "$(relative_path "$REPEATED_EDIT_BENCHMARK_SUMMARY")" \
    "$(relative_path "$BORDER_EDIT_BENCHMARK_SUMMARY")" \
    "$(relative_path "$PARTIAL_DIRTY_EDGE_MATRIX_SUMMARY")" \
    "$(relative_path "$COLLISION_REFRESH_COST_AUDIT_SUMMARY")" \
    "$(relative_path "$SHADOW_PROXY_REFRESH_COST_AUDIT_SUMMARY")" \
    "$(relative_path "$EDIT_BURST_BUDGET_SUMMARY")" \
    "$(relative_path "$EDIT_VISUAL_PARITY_SUMMARY")" \
    "$(relative_path "$UPLOAD_BUDGET_SUMMARY")"
} > "$SUMMARY_PATH"

cat "$SUMMARY_PATH"
