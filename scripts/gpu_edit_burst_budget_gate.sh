#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/gpu_edit_burst_budget_gate_current"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

SUMMARY_PATH="$OUT_DIR/gpu-edit-burst-budget-summary.txt"
CASES_PATH="$OUT_DIR/gpu-edit-burst-budget-cases.txt"

REPEATED_EDIT_BENCHMARK_SUMMARY="${RUMPELMC_EDIT_BURST_BUDGET_REPEATED_EDIT_BENCHMARK_SUMMARY:-"$ROOT_DIR/logs/gpu_terrain_repeated_edit_benchmark_current/gpu-terrain-repeated-edit-benchmark-summary.txt"}"
BORDER_EDIT_BENCHMARK_SUMMARY="${RUMPELMC_EDIT_BURST_BUDGET_BORDER_EDIT_BENCHMARK_SUMMARY:-"$ROOT_DIR/logs/gpu_terrain_border_edit_benchmark_current/gpu-terrain-border-edit-benchmark-summary.txt"}"
PARTIAL_DIRTY_EDGE_MATRIX_SUMMARY="${RUMPELMC_EDIT_BURST_BUDGET_PARTIAL_DIRTY_EDGE_MATRIX_SUMMARY:-"$ROOT_DIR/logs/gpu_terrain_partial_dirty_edge_matrix_current/gpu-terrain-partial-dirty-edge-matrix-summary.txt"}"
COLLISION_REFRESH_COST_AUDIT_SUMMARY="${RUMPELMC_EDIT_BURST_BUDGET_COLLISION_REFRESH_COST_AUDIT_SUMMARY:-"$ROOT_DIR/logs/gpu_collision_refresh_cost_audit_current/gpu-collision-refresh-cost-audit-summary.txt"}"
SHADOW_PROXY_REFRESH_COST_AUDIT_SUMMARY="${RUMPELMC_EDIT_BURST_BUDGET_SHADOW_PROXY_REFRESH_COST_AUDIT_SUMMARY:-"$ROOT_DIR/logs/gpu_shadow_proxy_refresh_cost_audit_current/gpu-shadow-proxy-refresh-cost-audit-summary.txt"}"
UPLOAD_BUDGET_SUMMARY="${RUMPELMC_EDIT_BURST_BUDGET_UPLOAD_BUDGET_SUMMARY:-"$ROOT_DIR/logs/gpu_terrain_upload_budget_current/gpu-terrain-upload-budget-summary.txt"}"

TARGET_FPS="${RUMPELMC_EDIT_BURST_BUDGET_TARGET_FPS:-150}"
MAX_QUEUE_MS="${RUMPELMC_EDIT_BURST_BUDGET_MAX_QUEUE_MS:-}"
MAX_PROCESS_MS="${RUMPELMC_EDIT_BURST_BUDGET_MAX_PROCESS_MS:-}"
MAX_SUBMIT_MS="${RUMPELMC_EDIT_BURST_BUDGET_MAX_SUBMIT_MS:-}"
MIN_REPEATED_CASES="${RUMPELMC_EDIT_BURST_BUDGET_MIN_REPEATED_CASES:-2}"
MIN_BORDER_CASES="${RUMPELMC_EDIT_BURST_BUDGET_MIN_BORDER_CASES:-3}"
MIN_PARTIAL_MATRIX_CASES="${RUMPELMC_EDIT_BURST_BUDGET_MIN_PARTIAL_MATRIX_CASES:-8}"
MIN_COLLISION_CASES="${RUMPELMC_EDIT_BURST_BUDGET_MIN_COLLISION_CASES:-18}"
MIN_SHADOW_CASES="${RUMPELMC_EDIT_BURST_BUDGET_MIN_SHADOW_CASES:-18}"
MIN_PRESSURE_DIRTY_BLOCKS="${RUMPELMC_EDIT_BURST_BUDGET_MIN_PRESSURE_DIRTY_BLOCKS:-512}"
MIN_EDGE_NEIGHBOR_SUBCHUNKS="${RUMPELMC_EDIT_BURST_BUDGET_MIN_EDGE_NEIGHBOR_SUBCHUNKS:-4}"
MIN_PARTIAL_SAVED_SUBCHUNKS="${RUMPELMC_EDIT_BURST_BUDGET_MIN_PARTIAL_SAVED_SUBCHUNKS:-2}"

mkdir -p "$OUT_DIR"
: > "$CASES_PATH"

fail() {
  echo "gpu_edit_burst_budget_gate: $*" >&2
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

field_first() {
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

frame_budget_ms() {
  awk -v fps="$TARGET_FPS" '
    BEGIN {
      if (fps !~ /^-?[0-9]+([.][0-9]+)?$/ || fps <= 0.0) {
        fps = 150.0
      }
      printf("%.3f\n", 1000.0 / fps)
    }
  '
}

numeric_ge() {
  value="$1"
  min_value="$2"
  awk -v value="$value" -v min_value="$min_value" '
    BEGIN {
      exit !(value ~ /^-?[0-9]+([.][0-9]+)?$/ && value + 0 >= min_value + 0)
    }
  '
}

numeric_le() {
  value="$1"
  max_value="$2"
  awk -v value="$value" -v max_value="$max_value" '
    BEGIN {
      exit !(value ~ /^-?[0-9]+([.][0-9]+)?$/ && value + 0 <= max_value + 0)
    }
  '
}

numeric_eq() {
  value="$1"
  expected="$2"
  awk -v value="$value" -v expected="$expected" '
    BEGIN {
      exit !(value ~ /^-?[0-9]+([.][0-9]+)?$/ && value + 0 == expected + 0)
    }
  '
}

max2() {
  left="$1"
  right="$2"
  awk -v left="$left" -v right="$right" '
    BEGIN {
      left_ok = left ~ /^-?[0-9]+([.][0-9]+)?$/
      right_ok = right ~ /^-?[0-9]+([.][0-9]+)?$/
      if (left_ok && right_ok) {
        printf("%.3f\n", left + 0 > right + 0 ? left + 0 : right + 0)
      } else if (left_ok) {
        printf("%.3f\n", left + 0)
      } else if (right_ok) {
        printf("%.3f\n", right + 0)
      } else {
        print "n/a"
      }
    }
  '
}

sum2() {
  left="$1"
  right="$2"
  awk -v left="$left" -v right="$right" '
    BEGIN {
      total = 0
      seen = 0
      if (left ~ /^-?[0-9]+([.][0-9]+)?$/) {
        total += left + 0
        seen = 1
      }
      if (right ~ /^-?[0-9]+([.][0-9]+)?$/) {
        total += right + 0
        seen = 1
      }
      if (seen) {
        printf("%.3f\n", total)
      } else {
        print "n/a"
      }
    }
  '
}

append_reason() {
  current="$1"
  next="$2"
  if [ "$current" = "ok" ]; then
    printf '%s\n' "$next"
  else
    printf '%s,%s\n' "$current" "$next"
  fi
}

case "$MIN_REPEATED_CASES$MIN_BORDER_CASES$MIN_PARTIAL_MATRIX_CASES$MIN_COLLISION_CASES$MIN_SHADOW_CASES" in
  *[!0-9]*) fail "case minimums must be nonnegative integers" ;;
esac

budget_ms="$(frame_budget_ms)"
if [ -z "$MAX_QUEUE_MS" ]; then
  MAX_QUEUE_MS="$budget_ms"
fi
if [ -z "$MAX_PROCESS_MS" ]; then
  MAX_PROCESS_MS="$budget_ms"
fi
if [ -z "$MAX_SUBMIT_MS" ]; then
  MAX_SUBMIT_MS="$budget_ms"
fi

source_count=0
pass_sources=0
fail_sources=0
aggregate_reason="ok"
max_terrain_queue_ms="n/a"
max_process_wall_p95_ms="n/a"
max_gpu_compositor_submit_ms="n/a"
max_dirty_blocks="n/a"
max_dirty_edge_neighbor_subchunks="n/a"
max_dirty_partial_saved_subchunks="n/a"
max_partial_edge_neighbor_subchunks="n/a"
max_partial_saved_subchunks="n/a"
max_collision_refresh_rebuilt="n/a"
max_collision_q_max="n/a"
max_collision_phase_total_ms="n/a"
max_collision_phase_component_ms="n/a"
max_shadow_proxy_refresh_reuse="n/a"
max_proxy_shadow="n/a"
max_proxy_shadow_only="n/a"
max_compact_shadow_proxy="n/a"
max_compact_shadow_normals_saved="n/a"
gpu_upload_fail_total="0"
ground_misses_total="0"
default_runtime_change_allowed="0"
visible_quality_change_allowed="0"
scheduler_change_allowed="0"
requires_external_profiler_before_default="0"
requires_mac_windows_validation="0"
external_profile_status="not_indexed"

record_case() {
  label="$1"
  path="$(normalize_path "$2")"
  min_cases="$3"
  rel_path="$(relative_path "$path")"

  source_count=$((source_count + 1))
  reason="ok"
  source_status="missing"
  root_token="missing"
  case_count="n/a"
  pass_cases="n/a"
  terrain_queue_ms="n/a"
  process_wall_ms="n/a"
  submit_ms="n/a"
  upload_fail="n/a"
  ground_misses="n/a"
  default_allowed="n/a"
  visible_allowed="n/a"
  scheduler_allowed="n/a"
  requires_profiler="n/a"
  requires_platform_validation="n/a"
  source_external_profile_status="n/a"
  dirty_blocks="n/a"
  dirty_edge_neighbor_subchunks="n/a"
  dirty_partial_saved_subchunks="n/a"
  partial_edge_neighbor_subchunks="n/a"
  partial_saved_subchunks="n/a"
  collision_refresh_rebuilt="n/a"
  collision_q_max="n/a"
  collision_phase_total_ms="n/a"
  collision_phase_component_ms="n/a"
  shadow_proxy_refresh_reuse="n/a"
  proxy_shadow="n/a"
  proxy_shadow_only="n/a"
  compact_shadow_proxy="n/a"
  compact_shadow_normals_saved="n/a"

  if [ ! -s "$path" ]; then
    reason="$(append_reason "$reason" "missing_summary")"
  else
    root_token="$(awk '{ print $1; exit }' "$path")"
    source_status="$(field_metric status "$path")"
    case_count="$(field_first "$path" case_count)"
    pass_cases="$(field_first "$path" pass_cases)"
    terrain_queue_ms="$(field_first "$path" max_terrain_queue_ms terrain_queue_max_ms)"
    process_wall_ms="$(field_first "$path" max_process_wall_p95_ms process_wall_p95_ms)"
    submit_ms="$(field_first "$path" max_gpu_compositor_submit_ms gpu_compositor_submit_max_ms)"
    upload_fail="$(field_first "$path" gpu_upload_fail max_upload_fail upload_fail_total movement_upload_fail)"
    ground_misses="$(field_first "$path" ground_misses)"
    default_allowed="$(field_first "$path" default_runtime_change_allowed)"
    visible_allowed="$(field_first "$path" visible_quality_change_allowed)"
    scheduler_allowed="$(field_first "$path" scheduler_change_allowed)"
    requires_profiler="$(field_first "$path" requires_external_profiler_before_default)"
    requires_platform_validation="$(field_first "$path" requires_mac_windows_validation)"
    source_external_profile_status="$(field_first "$path" external_profile_status)"
    dirty_blocks="$(field_first "$path" max_dirty_blocks dirty_blocks)"
    dirty_edge_neighbor_subchunks="$(field_first "$path" max_dirty_edge_neighbor_subchunks dirty_edge_neighbor_subchunks)"
    dirty_partial_saved_subchunks="$(field_first "$path" max_dirty_partial_saved_subchunks dirty_partial_saved_subchunks)"
    partial_edge_neighbor_subchunks="$(field_first "$path" max_partial_edge_neighbor_subchunks)"
    partial_saved_subchunks="$(field_first "$path" max_partial_saved_subchunks)"
    collision_refresh_rebuilt="$(field_first "$path" max_collision_refresh_rebuilt collision_refresh_rebuilt)"
    collision_q_max="$(field_first "$path" max_collision_q_max collision_q_max)"
    collision_phase_total_ms="$(field_first "$path" max_collision_phase_total_ms collision_phase_total_ms)"
    collision_phase_component_ms="$(field_first "$path" max_collision_phase_component_ms collision_phase_component_ms)"
    shadow_proxy_refresh_reuse="$(field_first "$path" max_proxy_refresh_reuse proxy_refresh_reuse)"
    proxy_shadow="$(field_first "$path" max_proxy_shadow proxy_shadow)"
    proxy_shadow_only="$(field_first "$path" max_proxy_shadow_only proxy_shadow_only)"
    compact_shadow_proxy="$(field_first "$path" max_compact_shadow_proxy compact_shadow_proxy)"
    compact_shadow_normals_saved="$(field_first "$path" max_compact_shadow_normals_saved compact_shadow_normals_saved)"

    if [ "$source_status" != "pass" ]; then
      reason="$(append_reason "$reason" "source_status")"
    fi
    if [ "$min_cases" != "0" ] && ! numeric_ge "$case_count" "$min_cases"; then
      reason="$(append_reason "$reason" "case_count")"
    fi
    if [ "$case_count" != "n/a" ] && ! numeric_eq "$pass_cases" "$case_count"; then
      reason="$(append_reason "$reason" "failed_cases")"
    fi
    if [ "$terrain_queue_ms" != "n/a" ] && ! numeric_le "$terrain_queue_ms" "$MAX_QUEUE_MS"; then
      reason="$(append_reason "$reason" "terrain_queue_budget")"
    fi
    if [ "$process_wall_ms" != "n/a" ] && ! numeric_le "$process_wall_ms" "$MAX_PROCESS_MS"; then
      reason="$(append_reason "$reason" "process_wall_budget")"
    fi
    if [ "$submit_ms" != "n/a" ] && ! numeric_le "$submit_ms" "$MAX_SUBMIT_MS"; then
      reason="$(append_reason "$reason" "gpu_compositor_submit_budget")"
    fi
    if [ "$upload_fail" != "n/a" ] && ! numeric_eq "$upload_fail" 0; then
      reason="$(append_reason "$reason" "gpu_upload_fail")"
    fi
    if [ "$ground_misses" != "n/a" ] && ! numeric_eq "$ground_misses" 0; then
      reason="$(append_reason "$reason" "ground_misses")"
    fi
    if [ "$default_allowed" != "n/a" ] && ! numeric_eq "$default_allowed" 0; then
      reason="$(append_reason "$reason" "default_runtime_change_allowed")"
    fi
    if [ "$visible_allowed" != "n/a" ] && ! numeric_eq "$visible_allowed" 0; then
      reason="$(append_reason "$reason" "visible_quality_change_allowed")"
    fi
    if [ "$scheduler_allowed" != "n/a" ] && ! numeric_eq "$scheduler_allowed" 0; then
      reason="$(append_reason "$reason" "scheduler_change_allowed")"
    fi

    case "$label" in
      repeated_edit_benchmark)
        single_edge_runs="$(field_first "$path" single_edge_runs)"
        corner_edge_runs="$(field_first "$path" corner_edge_runs)"
        repeated_min_edge="$(field_first "$path" min_dirty_edge_neighbor_subchunks)"
        repeated_min_saved="$(field_first "$path" min_dirty_partial_saved_subchunks)"
        if ! numeric_ge "$single_edge_runs" 3; then
          reason="$(append_reason "$reason" "single_edge_runs")"
        fi
        if ! numeric_ge "$corner_edge_runs" 3; then
          reason="$(append_reason "$reason" "corner_edge_runs")"
        fi
        if ! numeric_ge "$repeated_min_edge" "$MIN_EDGE_NEIGHBOR_SUBCHUNKS"; then
          reason="$(append_reason "$reason" "repeated_edge_neighbors")"
        fi
        if ! numeric_ge "$repeated_min_saved" "$MIN_PARTIAL_SAVED_SUBCHUNKS"; then
          reason="$(append_reason "$reason" "repeated_partial_savings")"
        fi
        ;;
      border_edit_benchmark)
        if ! numeric_ge "$dirty_blocks" "$MIN_PRESSURE_DIRTY_BLOCKS"; then
          reason="$(append_reason "$reason" "pressure_dirty_blocks")"
        fi
        if ! numeric_ge "$dirty_edge_neighbor_subchunks" "$MIN_EDGE_NEIGHBOR_SUBCHUNKS"; then
          reason="$(append_reason "$reason" "border_edge_neighbors")"
        fi
        if ! numeric_ge "$dirty_partial_saved_subchunks" "$MIN_PARTIAL_SAVED_SUBCHUNKS"; then
          reason="$(append_reason "$reason" "border_partial_savings")"
        fi
        ;;
      partial_dirty_edge_matrix)
        full_partial_disabled="$(field_first "$path" full_partial_disabled)"
        single_edge_cases="$(field_first "$path" single_edge_cases)"
        corner_edge_cases="$(field_first "$path" corner_edge_cases)"
        if ! numeric_eq "$full_partial_disabled" 1; then
          reason="$(append_reason "$reason" "full_partial_enabled")"
        fi
        if ! numeric_ge "$single_edge_cases" 4; then
          reason="$(append_reason "$reason" "single_edge_matrix_cases")"
        fi
        if ! numeric_ge "$corner_edge_cases" 4; then
          reason="$(append_reason "$reason" "corner_edge_matrix_cases")"
        fi
        if ! numeric_ge "$partial_edge_neighbor_subchunks" "$MIN_EDGE_NEIGHBOR_SUBCHUNKS"; then
          reason="$(append_reason "$reason" "partial_matrix_edge_neighbors")"
        fi
        if ! numeric_ge "$partial_saved_subchunks" "$MIN_PARTIAL_SAVED_SUBCHUNKS"; then
          reason="$(append_reason "$reason" "partial_matrix_savings")"
        fi
        ;;
      collision_refresh_cost_audit)
        matrix_case_count="$(field_first "$path" matrix_case_count)"
        pressure_case_count="$(field_first "$path" pressure_case_count)"
        collision_missing="$(field_first "$path" collision_refresh_missing refresh_missing_cases)"
        collision_q_dup="$(field_first "$path" collision_q_dup queue_duplicate_cases)"
        collision_q_stale="$(field_first "$path" collision_q_stale queue_stale_cases)"
        collision_q_missing="$(field_first "$path" collision_q_missing queue_missing_cases)"
        phase_budget_cases="$(field_first "$path" phase_budget_cases)"
        if ! numeric_ge "$matrix_case_count" 16; then
          reason="$(append_reason "$reason" "collision_matrix_cases")"
        fi
        if ! numeric_ge "$pressure_case_count" 2; then
          reason="$(append_reason "$reason" "collision_pressure_cases")"
        fi
        if ! numeric_ge "$collision_refresh_rebuilt" 1; then
          reason="$(append_reason "$reason" "collision_refresh_rebuilt")"
        fi
        if [ "$collision_missing" != "n/a" ] && ! numeric_eq "$collision_missing" 0; then
          reason="$(append_reason "$reason" "collision_refresh_missing")"
        fi
        if [ "$collision_q_dup" != "n/a" ] && ! numeric_eq "$collision_q_dup" 0; then
          reason="$(append_reason "$reason" "collision_q_dup")"
        fi
        if [ "$collision_q_stale" != "n/a" ] && ! numeric_eq "$collision_q_stale" 0; then
          reason="$(append_reason "$reason" "collision_q_stale")"
        fi
        if [ "$collision_q_missing" != "n/a" ] && ! numeric_eq "$collision_q_missing" 0; then
          reason="$(append_reason "$reason" "collision_q_missing")"
        fi
        if [ "$phase_budget_cases" != "n/a" ] && ! numeric_eq "$phase_budget_cases" 0; then
          reason="$(append_reason "$reason" "collision_phase_budget_cases")"
        fi
        ;;
      shadow_proxy_refresh_cost_audit)
        matrix_case_count="$(field_first "$path" matrix_case_count)"
        pressure_case_count="$(field_first "$path" pressure_case_count)"
        native_shadow_active_cases="$(field_first "$path" native_shadow_active_cases)"
        native_shadow_requested_cases="$(field_first "$path" native_shadow_requested_cases)"
        shadow_path_changed_cases="$(field_first "$path" shadow_path_changed_cases)"
        shadow_mode_changed_cases="$(field_first "$path" shadow_mode_changed_cases)"
        shadow_mesh_changed_cases="$(field_first "$path" shadow_mesh_changed_cases)"
        terrain_queue_budget_cases="$(field_first "$path" terrain_queue_budget_cases)"
        process_wall_budget_cases="$(field_first "$path" process_wall_budget_cases)"
        submit_budget_cases="$(field_first "$path" submit_budget_cases)"
        if ! numeric_ge "$matrix_case_count" 16; then
          reason="$(append_reason "$reason" "shadow_matrix_cases")"
        fi
        if ! numeric_ge "$pressure_case_count" 2; then
          reason="$(append_reason "$reason" "shadow_pressure_cases")"
        fi
        if ! numeric_ge "$shadow_proxy_refresh_reuse" 1; then
          reason="$(append_reason "$reason" "shadow_proxy_refresh_reuse")"
        fi
        if ! numeric_ge "$proxy_shadow" 1; then
          reason="$(append_reason "$reason" "proxy_shadow")"
        fi
        if ! numeric_ge "$compact_shadow_proxy" "$proxy_shadow"; then
          reason="$(append_reason "$reason" "compact_shadow_proxy")"
        fi
        if ! numeric_ge "$compact_shadow_normals_saved" 1; then
          reason="$(append_reason "$reason" "compact_shadow_savings")"
        fi
        if [ "$native_shadow_requested_cases" != "n/a" ] && ! numeric_eq "$native_shadow_requested_cases" 0; then
          reason="$(append_reason "$reason" "native_shadow_requested")"
        fi
        if [ "$native_shadow_active_cases" != "n/a" ] && ! numeric_eq "$native_shadow_active_cases" 0; then
          reason="$(append_reason "$reason" "native_shadow_active")"
        fi
        if [ "$shadow_path_changed_cases" != "n/a" ] && ! numeric_eq "$shadow_path_changed_cases" 0; then
          reason="$(append_reason "$reason" "shadow_path_changed")"
        fi
        if [ "$shadow_mode_changed_cases" != "n/a" ] && ! numeric_eq "$shadow_mode_changed_cases" 0; then
          reason="$(append_reason "$reason" "shadow_mode_changed")"
        fi
        if [ "$shadow_mesh_changed_cases" != "n/a" ] && ! numeric_eq "$shadow_mesh_changed_cases" 0; then
          reason="$(append_reason "$reason" "shadow_mesh_changed")"
        fi
        if [ "$terrain_queue_budget_cases" != "n/a" ] && ! numeric_eq "$terrain_queue_budget_cases" 0; then
          reason="$(append_reason "$reason" "shadow_terrain_queue_budget_cases")"
        fi
        if [ "$process_wall_budget_cases" != "n/a" ] && ! numeric_eq "$process_wall_budget_cases" 0; then
          reason="$(append_reason "$reason" "shadow_process_wall_budget_cases")"
        fi
        if [ "$submit_budget_cases" != "n/a" ] && ! numeric_eq "$submit_budget_cases" 0; then
          reason="$(append_reason "$reason" "shadow_submit_budget_cases")"
        fi
        ;;
      upload_budget)
        movement_upload_fail="$(field_first "$path" movement_upload_fail)"
        in_place_upload_fail="$(field_first "$path" in_place_upload_fail)"
        movement_budget_status="$(field_first "$path" movement_budget_status)"
        in_place_status="$(field_first "$path" in_place_status)"
        in_place_enabled="$(field_first "$path" in_place_enabled)"
        if [ "$movement_budget_status" != "pass" ]; then
          reason="$(append_reason "$reason" "movement_upload_budget_status")"
        fi
        if [ "$in_place_status" != "pass" ]; then
          reason="$(append_reason "$reason" "in_place_upload_budget_status")"
        fi
        if ! numeric_eq "$movement_upload_fail" 0; then
          reason="$(append_reason "$reason" "movement_upload_fail")"
        fi
        if ! numeric_eq "$in_place_upload_fail" 0; then
          reason="$(append_reason "$reason" "in_place_upload_fail")"
        fi
        if ! numeric_eq "$in_place_enabled" 1; then
          reason="$(append_reason "$reason" "in_place_upload_missing")"
        fi
        ;;
    esac
  fi

  if [ "$reason" = "ok" ]; then
    case_status="pass"
    pass_sources=$((pass_sources + 1))
  else
    case_status="fail"
    fail_sources=$((fail_sources + 1))
    aggregate_reason="$(append_reason "$aggregate_reason" "$label:$reason")"
  fi

  max_terrain_queue_ms="$(max2 "$max_terrain_queue_ms" "$terrain_queue_ms")"
  max_process_wall_p95_ms="$(max2 "$max_process_wall_p95_ms" "$process_wall_ms")"
  max_gpu_compositor_submit_ms="$(max2 "$max_gpu_compositor_submit_ms" "$submit_ms")"
  max_dirty_blocks="$(max2 "$max_dirty_blocks" "$dirty_blocks")"
  max_dirty_edge_neighbor_subchunks="$(max2 "$max_dirty_edge_neighbor_subchunks" "$dirty_edge_neighbor_subchunks")"
  max_dirty_partial_saved_subchunks="$(max2 "$max_dirty_partial_saved_subchunks" "$dirty_partial_saved_subchunks")"
  max_partial_edge_neighbor_subchunks="$(max2 "$max_partial_edge_neighbor_subchunks" "$partial_edge_neighbor_subchunks")"
  max_partial_saved_subchunks="$(max2 "$max_partial_saved_subchunks" "$partial_saved_subchunks")"
  max_collision_refresh_rebuilt="$(max2 "$max_collision_refresh_rebuilt" "$collision_refresh_rebuilt")"
  max_collision_q_max="$(max2 "$max_collision_q_max" "$collision_q_max")"
  max_collision_phase_total_ms="$(max2 "$max_collision_phase_total_ms" "$collision_phase_total_ms")"
  max_collision_phase_component_ms="$(max2 "$max_collision_phase_component_ms" "$collision_phase_component_ms")"
  max_shadow_proxy_refresh_reuse="$(max2 "$max_shadow_proxy_refresh_reuse" "$shadow_proxy_refresh_reuse")"
  max_proxy_shadow="$(max2 "$max_proxy_shadow" "$proxy_shadow")"
  max_proxy_shadow_only="$(max2 "$max_proxy_shadow_only" "$proxy_shadow_only")"
  max_compact_shadow_proxy="$(max2 "$max_compact_shadow_proxy" "$compact_shadow_proxy")"
  max_compact_shadow_normals_saved="$(max2 "$max_compact_shadow_normals_saved" "$compact_shadow_normals_saved")"
  gpu_upload_fail_total="$(sum2 "$gpu_upload_fail_total" "$upload_fail")"
  ground_misses_total="$(sum2 "$ground_misses_total" "$ground_misses")"

  if [ "$default_allowed" != "n/a" ] && ! numeric_eq "$default_allowed" 0; then
    default_runtime_change_allowed="$default_allowed"
  fi
  if [ "$visible_allowed" != "n/a" ] && ! numeric_eq "$visible_allowed" 0; then
    visible_quality_change_allowed="$visible_allowed"
  fi
  if [ "$scheduler_allowed" != "n/a" ] && ! numeric_eq "$scheduler_allowed" 0; then
    scheduler_change_allowed="$scheduler_allowed"
  fi
  if [ "$requires_profiler" = "1" ]; then
    requires_external_profiler_before_default="1"
  fi
  if [ "$requires_platform_validation" = "1" ]; then
    requires_mac_windows_validation="1"
  fi
  if [ "$source_external_profile_status" = "pending_external_profiler" ]; then
    external_profile_status="pending_external_profiler"
  fi

  printf 'gpu_edit_burst_budget_source label=%s status=%s reason=%s root=%s source_status=%s case_count=%s pass_cases=%s terrain_queue_max_ms=%s process_wall_p95_ms=%s gpu_compositor_submit_max_ms=%s gpu_upload_fail=%s ground_misses=%s dirty_blocks=%s dirty_edge_neighbor_subchunks=%s dirty_partial_saved_subchunks=%s partial_edge_neighbor_subchunks=%s partial_saved_subchunks=%s collision_refresh_rebuilt=%s collision_q_max=%s collision_phase_total_ms=%s collision_phase_component_ms=%s shadow_proxy_refresh_reuse=%s proxy_shadow=%s proxy_shadow_only=%s compact_shadow_proxy=%s compact_shadow_normals_saved=%s default_runtime_change_allowed=%s visible_quality_change_allowed=%s scheduler_change_allowed=%s requires_external_profiler_before_default=%s requires_mac_windows_validation=%s external_profile_status=%s summary=%s\n' \
    "$label" "$case_status" "$reason" "$root_token" "$source_status" "$case_count" "$pass_cases" \
    "$terrain_queue_ms" "$process_wall_ms" "$submit_ms" "$upload_fail" "$ground_misses" \
    "$dirty_blocks" "$dirty_edge_neighbor_subchunks" "$dirty_partial_saved_subchunks" \
    "$partial_edge_neighbor_subchunks" "$partial_saved_subchunks" "$collision_refresh_rebuilt" "$collision_q_max" \
    "$collision_phase_total_ms" "$collision_phase_component_ms" "$shadow_proxy_refresh_reuse" "$proxy_shadow" "$proxy_shadow_only" \
    "$compact_shadow_proxy" "$compact_shadow_normals_saved" "$default_allowed" "$visible_allowed" "$scheduler_allowed" \
    "$requires_profiler" "$requires_platform_validation" "$source_external_profile_status" "$rel_path" >> "$CASES_PATH"
}

record_case repeated_edit_benchmark "$REPEATED_EDIT_BENCHMARK_SUMMARY" "$MIN_REPEATED_CASES"
record_case border_edit_benchmark "$BORDER_EDIT_BENCHMARK_SUMMARY" "$MIN_BORDER_CASES"
record_case partial_dirty_edge_matrix "$PARTIAL_DIRTY_EDGE_MATRIX_SUMMARY" "$MIN_PARTIAL_MATRIX_CASES"
record_case collision_refresh_cost_audit "$COLLISION_REFRESH_COST_AUDIT_SUMMARY" "$MIN_COLLISION_CASES"
record_case shadow_proxy_refresh_cost_audit "$SHADOW_PROXY_REFRESH_COST_AUDIT_SUMMARY" "$MIN_SHADOW_CASES"
record_case upload_budget "$UPLOAD_BUDGET_SUMMARY" 0

if ! numeric_eq "$gpu_upload_fail_total" 0; then
  aggregate_reason="$(append_reason "$aggregate_reason" "gpu_upload_fail")"
fi
if ! numeric_eq "$ground_misses_total" 0; then
  aggregate_reason="$(append_reason "$aggregate_reason" "ground_misses")"
fi
if ! numeric_eq "$default_runtime_change_allowed" 0; then
  aggregate_reason="$(append_reason "$aggregate_reason" "default_runtime_change_allowed")"
fi
if ! numeric_eq "$visible_quality_change_allowed" 0; then
  aggregate_reason="$(append_reason "$aggregate_reason" "visible_quality_change_allowed")"
fi
if ! numeric_eq "$scheduler_change_allowed" 0; then
  aggregate_reason="$(append_reason "$aggregate_reason" "scheduler_change_allowed")"
fi

status="pass"
if [ "$aggregate_reason" != "ok" ]; then
  status="fail"
fi

{
  printf 'gpu_edit_burst_budget_gate status=%s reason=%s source_count=%s pass_sources=%s fail_sources=%s target_fps=%s queue_budget_ms=%s process_budget_ms=%s submit_budget_ms=%s max_terrain_queue_ms=%s max_process_wall_p95_ms=%s max_gpu_compositor_submit_ms=%s max_dirty_blocks=%s max_dirty_edge_neighbor_subchunks=%s max_dirty_partial_saved_subchunks=%s max_partial_edge_neighbor_subchunks=%s max_partial_saved_subchunks=%s max_collision_refresh_rebuilt=%s max_collision_q_max=%s max_collision_phase_total_ms=%s max_collision_phase_component_ms=%s max_shadow_proxy_refresh_reuse=%s max_proxy_shadow=%s max_proxy_shadow_only=%s max_compact_shadow_proxy=%s max_compact_shadow_normals_saved=%s gpu_upload_fail=%s ground_misses=%s default_runtime_change_allowed=%s visible_quality_change_allowed=%s scheduler_change_allowed=%s external_profile_status=%s requires_external_profiler_before_default=%s requires_mac_windows_validation=%s repeated_edit_benchmark_summary=%s border_edit_benchmark_summary=%s partial_dirty_edge_matrix_summary=%s collision_refresh_cost_audit_summary=%s shadow_proxy_refresh_cost_audit_summary=%s upload_budget_summary=%s cases=%s\n' \
    "$status" "$aggregate_reason" "$source_count" "$pass_sources" "$fail_sources" "$TARGET_FPS" "$MAX_QUEUE_MS" "$MAX_PROCESS_MS" "$MAX_SUBMIT_MS" \
    "$max_terrain_queue_ms" "$max_process_wall_p95_ms" "$max_gpu_compositor_submit_ms" \
    "$max_dirty_blocks" "$max_dirty_edge_neighbor_subchunks" "$max_dirty_partial_saved_subchunks" \
    "$max_partial_edge_neighbor_subchunks" "$max_partial_saved_subchunks" \
    "$max_collision_refresh_rebuilt" "$max_collision_q_max" "$max_collision_phase_total_ms" "$max_collision_phase_component_ms" \
    "$max_shadow_proxy_refresh_reuse" "$max_proxy_shadow" "$max_proxy_shadow_only" "$max_compact_shadow_proxy" "$max_compact_shadow_normals_saved" \
    "$gpu_upload_fail_total" "$ground_misses_total" "$default_runtime_change_allowed" "$visible_quality_change_allowed" "$scheduler_change_allowed" \
    "$external_profile_status" "$requires_external_profiler_before_default" "$requires_mac_windows_validation" \
    "$(relative_path "$(normalize_path "$REPEATED_EDIT_BENCHMARK_SUMMARY")")" \
    "$(relative_path "$(normalize_path "$BORDER_EDIT_BENCHMARK_SUMMARY")")" \
    "$(relative_path "$(normalize_path "$PARTIAL_DIRTY_EDGE_MATRIX_SUMMARY")")" \
    "$(relative_path "$(normalize_path "$COLLISION_REFRESH_COST_AUDIT_SUMMARY")")" \
    "$(relative_path "$(normalize_path "$SHADOW_PROXY_REFRESH_COST_AUDIT_SUMMARY")")" \
    "$(relative_path "$(normalize_path "$UPLOAD_BUDGET_SUMMARY")")" \
    "$(relative_path "$CASES_PATH")"
} > "$SUMMARY_PATH"

cat "$SUMMARY_PATH"
if [ "$status" != "pass" ]; then
  fail "edit burst budget gate failed"
fi
