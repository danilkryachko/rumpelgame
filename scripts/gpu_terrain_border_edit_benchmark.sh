#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/gpu_terrain_border_edit_benchmark_current"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

SUMMARY_PATH="$OUT_DIR/gpu-terrain-border-edit-benchmark-summary.txt"
CASES_PATH="$OUT_DIR/gpu-terrain-border-edit-benchmark-cases.txt"
REPEATED_EDIT_SUMMARY="${RUMPELMC_BORDER_EDIT_REPEATED_EDIT_SUMMARY:-"$ROOT_DIR/logs/gpu_terrain_repeated_edit_benchmark_current/gpu-terrain-repeated-edit-benchmark-summary.txt"}"
PRESSURE_DIRTY_SUMMARY="${RUMPELMC_BORDER_EDIT_PRESSURE_DIRTY_SUMMARY:-"$ROOT_DIR/logs/gpu_terrain_pressure_dirty_compare_current/gpu-terrain-pressure-dirty-compare-summary.txt"}"
MIN_REPEATED_RUNS="${RUMPELMC_BORDER_EDIT_MIN_REPEATED_RUNS:-3}"
MIN_PRESSURE_DIRTY_BLOCKS="${RUMPELMC_BORDER_EDIT_MIN_PRESSURE_DIRTY_BLOCKS:-512}"
TARGET_FPS="${RUMPELMC_BORDER_EDIT_TARGET_FPS:-150}"

mkdir -p "$OUT_DIR"

fail() {
  echo "gpu_terrain_border_edit_benchmark: $*" >&2
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

case_metric() {
  label="$1"
  key="$2"
  path="$3"
  awk -v label="$label" -v key="$key" '
    $1 == "gpu_repeated_edit_benchmark_case" {
      found_label = 0
      wanted = key "="
      for (i = 2; i <= NF; i++) {
        if ($i == "label=" label) {
          found_label = 1
        }
      }
      if (found_label) {
        for (i = 2; i <= NF; i++) {
          if (index($i, wanted) == 1) {
            value = substr($i, length(wanted) + 1)
            gsub(/^"/, "", value)
            gsub(/"$/, "", value)
            print value
            exit
          }
        }
      }
    }
  ' "$path"
}

require_non_empty() {
  req_label="$1"
  req_value="$2"
  test -n "$req_value" || fail "missing $req_label"
}

require_eq() {
  req_label="$1"
  req_value="$2"
  req_expected="$3"
  require_non_empty "$req_label" "$req_value"
  if [ "$req_value" != "$req_expected" ]; then
    fail "$req_label=$req_value, expected $req_expected"
  fi
}

require_numeric_ge() {
  req_label="$1"
  req_value="$2"
  req_min="$3"
  require_non_empty "$req_label" "$req_value"
  awk -v label="$req_label" -v value="$req_value" -v min_value="$req_min" '
    BEGIN {
      if (value + 0 < min_value + 0) {
        printf("gpu_terrain_border_edit_benchmark: %s %.3f below %.3f\n", label, value, min_value) > "/dev/stderr"
        exit 1
      }
    }
  '
}

require_numeric_le() {
  req_label="$1"
  req_value="$2"
  req_max="$3"
  require_non_empty "$req_label" "$req_value"
  awk -v label="$req_label" -v value="$req_value" -v max_value="$req_max" '
    BEGIN {
      if (value + 0 > max_value + 0) {
        printf("gpu_terrain_border_edit_benchmark: %s %.3f exceeds %.3f\n", label, value, max_value) > "/dev/stderr"
        exit 1
      }
    }
  '
}

max_value() {
  awk '
    BEGIN { seen = 0 }
    {
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^-?[0-9]+([.][0-9]+)?$/) {
          value = $i + 0
          if (!seen || value > max) {
            max = value
            seen = 1
          }
        }
      }
    }
    END {
      if (seen) {
        printf("%.3f\n", max)
      } else {
        print "0.000"
      }
    }
  '
}

min_value() {
  awk '
    BEGIN { seen = 0 }
    {
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^-?[0-9]+([.][0-9]+)?$/) {
          value = $i + 0
          if (!seen || value < min) {
            min = value
            seen = 1
          }
        }
      }
    }
    END {
      if (seen) {
        printf("%.3f\n", min)
      } else {
        print "0.000"
      }
    }
  '
}

frame_budget_ms() {
  awk -v fps="$TARGET_FPS" '
    BEGIN {
      if (fps <= 0.0) {
        fps = 150.0
      }
      printf("%.3f\n", 1000.0 / fps)
    }
  '
}

case "$MIN_REPEATED_RUNS" in
  ''|*[!0-9]*) fail "RUMPELMC_BORDER_EDIT_MIN_REPEATED_RUNS must be a positive integer" ;;
esac
if [ "$MIN_REPEATED_RUNS" -lt 1 ]; then
  fail "RUMPELMC_BORDER_EDIT_MIN_REPEATED_RUNS must be greater than zero"
fi
case "$MIN_PRESSURE_DIRTY_BLOCKS" in
  ''|*[!0-9]*) fail "RUMPELMC_BORDER_EDIT_MIN_PRESSURE_DIRTY_BLOCKS must be a positive integer" ;;
esac
if [ "$MIN_PRESSURE_DIRTY_BLOCKS" -lt 1 ]; then
  fail "RUMPELMC_BORDER_EDIT_MIN_PRESSURE_DIRTY_BLOCKS must be greater than zero"
fi

REPEATED_EDIT_SUMMARY="$(normalize_path "$REPEATED_EDIT_SUMMARY")"
PRESSURE_DIRTY_SUMMARY="$(normalize_path "$PRESSURE_DIRTY_SUMMARY")"
test -s "$REPEATED_EDIT_SUMMARY" || fail "missing repeated edit summary $(relative_path "$REPEATED_EDIT_SUMMARY")"
test -s "$PRESSURE_DIRTY_SUMMARY" || fail "missing pressure dirty summary $(relative_path "$PRESSURE_DIRTY_SUMMARY")"

budget_ms="$(frame_budget_ms)"

repeated_status="$(field_metric status "$REPEATED_EDIT_SUMMARY")"
repeated_case_count="$(field_metric case_count "$REPEATED_EDIT_SUMMARY")"
repeated_pass_cases="$(field_metric pass_cases "$REPEATED_EDIT_SUMMARY")"
single_edge_runs="$(field_metric single_edge_runs "$REPEATED_EDIT_SUMMARY")"
corner_edge_runs="$(field_metric corner_edge_runs "$REPEATED_EDIT_SUMMARY")"
repeated_min_edge_subchunks="$(field_metric min_dirty_edge_neighbor_subchunks "$REPEATED_EDIT_SUMMARY")"
repeated_min_saved_subchunks="$(field_metric min_dirty_partial_saved_subchunks "$REPEATED_EDIT_SUMMARY")"
repeated_queue_max="$(field_metric max_terrain_queue_ms "$REPEATED_EDIT_SUMMARY")"
repeated_process_max="$(field_metric max_process_wall_p95_ms "$REPEATED_EDIT_SUMMARY")"
repeated_submit_max="$(field_metric max_gpu_compositor_submit_ms "$REPEATED_EDIT_SUMMARY")"
repeated_upload_fail="$(field_metric gpu_upload_fail "$REPEATED_EDIT_SUMMARY")"
repeated_default_change="$(field_metric default_runtime_change_allowed "$REPEATED_EDIT_SUMMARY")"
repeated_visible_change="$(field_metric visible_quality_change_allowed "$REPEATED_EDIT_SUMMARY")"
repeated_cases="$(field_metric cases "$REPEATED_EDIT_SUMMARY")"
require_eq repeated_status "$repeated_status" pass
require_numeric_ge repeated_case_count "$repeated_case_count" 2
require_numeric_ge repeated_pass_cases "$repeated_pass_cases" 2
require_numeric_ge single_edge_runs "$single_edge_runs" "$MIN_REPEATED_RUNS"
require_numeric_ge corner_edge_runs "$corner_edge_runs" "$MIN_REPEATED_RUNS"
require_numeric_ge repeated_min_dirty_edge_neighbor_subchunks "$repeated_min_edge_subchunks" 4
require_numeric_ge repeated_min_dirty_partial_saved_subchunks "$repeated_min_saved_subchunks" 1
require_numeric_le repeated_terrain_queue_max_ms "$repeated_queue_max" "$budget_ms"
require_numeric_le repeated_process_wall_p95_ms "$repeated_process_max" "$budget_ms"
require_numeric_le repeated_gpu_compositor_submit_max_ms "$repeated_submit_max" "$budget_ms"
require_eq repeated_gpu_upload_fail "$repeated_upload_fail" 0
require_eq repeated_default_runtime_change_allowed "$repeated_default_change" 0
require_eq repeated_visible_quality_change_allowed "$repeated_visible_change" 0

REPEATED_CASES_PATH="$(normalize_path "$repeated_cases")"
test -s "$REPEATED_CASES_PATH" || fail "missing repeated edit cases $(relative_path "$REPEATED_CASES_PATH")"
single_edges="$(case_metric single_edge expected_edges "$REPEATED_CASES_PATH")"
single_bounds="$(case_metric single_edge expected_bounds "$REPEATED_CASES_PATH")"
single_status="$(case_metric single_edge status "$REPEATED_CASES_PATH")"
single_case_queue="$(case_metric single_edge max_terrain_queue_ms "$REPEATED_CASES_PATH")"
single_case_process="$(case_metric single_edge max_process_wall_p95_ms "$REPEATED_CASES_PATH")"
single_case_submit="$(case_metric single_edge max_gpu_compositor_submit_ms "$REPEATED_CASES_PATH")"
single_case_edge="$(case_metric single_edge dirty_edge_neighbor_subchunks_min "$REPEATED_CASES_PATH")"
single_case_saved="$(case_metric single_edge dirty_partial_saved_subchunks_min "$REPEATED_CASES_PATH")"
single_case_upload_fail="$(case_metric single_edge gpu_upload_fail "$REPEATED_CASES_PATH")"
corner_edges="$(case_metric corner_edge expected_edges "$REPEATED_CASES_PATH")"
corner_bounds="$(case_metric corner_edge expected_bounds "$REPEATED_CASES_PATH")"
corner_status="$(case_metric corner_edge status "$REPEATED_CASES_PATH")"
corner_case_queue="$(case_metric corner_edge max_terrain_queue_ms "$REPEATED_CASES_PATH")"
corner_case_process="$(case_metric corner_edge max_process_wall_p95_ms "$REPEATED_CASES_PATH")"
corner_case_submit="$(case_metric corner_edge max_gpu_compositor_submit_ms "$REPEATED_CASES_PATH")"
corner_case_edge="$(case_metric corner_edge dirty_edge_neighbor_subchunks_min "$REPEATED_CASES_PATH")"
corner_case_saved="$(case_metric corner_edge dirty_partial_saved_subchunks_min "$REPEATED_CASES_PATH")"
corner_case_upload_fail="$(case_metric corner_edge gpu_upload_fail "$REPEATED_CASES_PATH")"
require_eq single_edge_status "$single_status" pass
require_eq single_edge_expected_edges "$single_edges" pos_x
require_eq single_edge_expected_bounds "$single_bounds" "31,64,16:31,64,16"
require_eq single_edge_gpu_upload_fail "$single_case_upload_fail" 0
require_numeric_ge single_edge_neighbor_subchunks "$single_case_edge" 4
require_numeric_ge single_edge_saved_subchunks "$single_case_saved" 1
require_numeric_le single_edge_terrain_queue_max_ms "$single_case_queue" "$budget_ms"
require_numeric_le single_edge_process_wall_p95_ms "$single_case_process" "$budget_ms"
require_numeric_le single_edge_gpu_compositor_submit_max_ms "$single_case_submit" "$budget_ms"
require_eq corner_edge_status "$corner_status" pass
require_eq corner_edge_expected_edges "$corner_edges" pos_x,pos_z
require_eq corner_edge_expected_bounds "$corner_bounds" "31,64,31:31,64,31"
require_eq corner_edge_gpu_upload_fail "$corner_case_upload_fail" 0
require_numeric_ge corner_edge_neighbor_subchunks "$corner_case_edge" 8
require_numeric_ge corner_edge_saved_subchunks "$corner_case_saved" 1
require_numeric_le corner_edge_terrain_queue_max_ms "$corner_case_queue" "$budget_ms"
require_numeric_le corner_edge_process_wall_p95_ms "$corner_case_process" "$budget_ms"
require_numeric_le corner_edge_gpu_compositor_submit_max_ms "$corner_case_submit" "$budget_ms"

pressure_status="$(field_metric status "$PRESSURE_DIRTY_SUMMARY")"
pressure_fixture="$(field_metric expected_fixture "$PRESSURE_DIRTY_SUMMARY")"
pressure_local_x="$(field_metric local_x "$PRESSURE_DIRTY_SUMMARY")"
pressure_local_z="$(field_metric local_z "$PRESSURE_DIRTY_SUMMARY")"
full_dirty_blocks="$(field_metric full_dirty_blocks "$PRESSURE_DIRTY_SUMMARY")"
full_partial_subchunks="$(field_metric full_dirty_partial_subchunks "$PRESSURE_DIRTY_SUMMARY")"
full_saved_subchunks="$(field_metric full_dirty_partial_saved_subchunks "$PRESSURE_DIRTY_SUMMARY")"
full_edge_neighbor_subchunks="$(field_metric full_dirty_edge_neighbor_subchunks "$PRESSURE_DIRTY_SUMMARY")"
full_upload_fail="$(field_metric full_upload_fail "$PRESSURE_DIRTY_SUMMARY")"
full_upload_fail_capacity="$(field_metric full_upload_fail_capacity "$PRESSURE_DIRTY_SUMMARY")"
full_upload_fail_fragmented="$(field_metric full_upload_fail_fragmented "$PRESSURE_DIRTY_SUMMARY")"
full_queue_max="$(field_metric full_terrain_queue_max_ms "$PRESSURE_DIRTY_SUMMARY")"
full_process_max="$(field_metric full_process_wall_p95_ms "$PRESSURE_DIRTY_SUMMARY")"
full_submit_max="$(field_metric full_gpu_compositor_submit_max_ms "$PRESSURE_DIRTY_SUMMARY")"
full_collision="$(field_metric full_current_chunk_collision "$PRESSURE_DIRTY_SUMMARY")"
full_ground_misses="$(field_metric full_ground_misses "$PRESSURE_DIRTY_SUMMARY")"
full_terrain_samples="$(field_metric full_terrain_samples "$PRESSURE_DIRTY_SUMMARY")"
partial_dirty_blocks="$(field_metric partial_dirty_blocks "$PRESSURE_DIRTY_SUMMARY")"
partial_saved_subchunks="$(field_metric partial_dirty_partial_saved_subchunks "$PRESSURE_DIRTY_SUMMARY")"
partial_edge_chunks="$(field_metric partial_dirty_edge_chunks "$PRESSURE_DIRTY_SUMMARY")"
partial_edge_neighbor_chunks="$(field_metric partial_dirty_edge_neighbor_chunks "$PRESSURE_DIRTY_SUMMARY")"
partial_edge_neighbor_subchunks="$(field_metric partial_dirty_edge_neighbor_subchunks "$PRESSURE_DIRTY_SUMMARY")"
partial_last_edges="$(field_metric partial_dirty_last_edges "$PRESSURE_DIRTY_SUMMARY")"
partial_last_bounds="$(field_metric partial_dirty_last_bounds "$PRESSURE_DIRTY_SUMMARY")"
partial_upload_fail="$(field_metric partial_upload_fail "$PRESSURE_DIRTY_SUMMARY")"
partial_upload_fail_capacity="$(field_metric partial_upload_fail_capacity "$PRESSURE_DIRTY_SUMMARY")"
partial_upload_fail_fragmented="$(field_metric partial_upload_fail_fragmented "$PRESSURE_DIRTY_SUMMARY")"
partial_queue_max="$(field_metric partial_terrain_queue_max_ms "$PRESSURE_DIRTY_SUMMARY")"
partial_process_max="$(field_metric partial_process_wall_p95_ms "$PRESSURE_DIRTY_SUMMARY")"
partial_submit_max="$(field_metric partial_gpu_compositor_submit_max_ms "$PRESSURE_DIRTY_SUMMARY")"
partial_collision="$(field_metric partial_current_chunk_collision "$PRESSURE_DIRTY_SUMMARY")"
partial_ground_misses="$(field_metric partial_ground_misses "$PRESSURE_DIRTY_SUMMARY")"
partial_terrain_samples="$(field_metric partial_terrain_samples "$PRESSURE_DIRTY_SUMMARY")"
require_eq pressure_status "$pressure_status" pass
require_eq pressure_expected_fixture "$pressure_fixture" chunk_disc
require_eq pressure_local_x "$pressure_local_x" 31
require_eq pressure_local_z "$pressure_local_z" 31
require_numeric_ge full_dirty_blocks "$full_dirty_blocks" "$MIN_PRESSURE_DIRTY_BLOCKS"
require_eq full_dirty_partial_subchunks "$full_partial_subchunks" 0
require_eq full_dirty_partial_saved_subchunks "$full_saved_subchunks" 0
require_eq full_dirty_edge_neighbor_subchunks "$full_edge_neighbor_subchunks" 0
require_eq full_upload_fail "$full_upload_fail" 0
require_eq full_upload_fail_capacity "$full_upload_fail_capacity" 0
require_eq full_upload_fail_fragmented "$full_upload_fail_fragmented" 0
require_numeric_le full_terrain_queue_max_ms "$full_queue_max" "$budget_ms"
require_numeric_le full_process_wall_p95_ms "$full_process_max" "$budget_ms"
require_numeric_le full_gpu_compositor_submit_max_ms "$full_submit_max" "$budget_ms"
require_numeric_ge full_current_chunk_collision "$full_collision" 1
require_eq full_ground_misses "$full_ground_misses" 0
require_numeric_ge full_terrain_samples "$full_terrain_samples" 1
require_numeric_ge partial_dirty_blocks "$partial_dirty_blocks" "$MIN_PRESSURE_DIRTY_BLOCKS"
require_numeric_ge partial_dirty_partial_saved_subchunks "$partial_saved_subchunks" 1
require_numeric_ge partial_dirty_edge_chunks "$partial_edge_chunks" 1
require_numeric_ge partial_dirty_edge_neighbor_chunks "$partial_edge_neighbor_chunks" 1
require_numeric_ge partial_dirty_edge_neighbor_subchunks "$partial_edge_neighbor_subchunks" 1
require_eq partial_dirty_last_edges "$partial_last_edges" pos_x,pos_z
require_non_empty partial_dirty_last_bounds "$partial_last_bounds"
require_eq partial_upload_fail "$partial_upload_fail" 0
require_eq partial_upload_fail_capacity "$partial_upload_fail_capacity" 0
require_eq partial_upload_fail_fragmented "$partial_upload_fail_fragmented" 0
require_numeric_le partial_terrain_queue_max_ms "$partial_queue_max" "$budget_ms"
require_numeric_le partial_process_wall_p95_ms "$partial_process_max" "$budget_ms"
require_numeric_le partial_gpu_compositor_submit_max_ms "$partial_submit_max" "$budget_ms"
require_numeric_ge partial_current_chunk_collision "$partial_collision" 1
require_eq partial_ground_misses "$partial_ground_misses" 0
require_numeric_ge partial_terrain_samples "$partial_terrain_samples" 1

: > "$CASES_PATH"
printf 'gpu_border_edit_benchmark_case label=single_edge_border source=repeated_edit status=pass runs=%s expected_edges=%s expected_bounds=%s dirty_edge_neighbor_subchunks=%s dirty_partial_saved_subchunks=%s terrain_queue_max_ms=%s process_wall_p95_ms=%s gpu_compositor_submit_max_ms=%s gpu_upload_fail=0 summary=%s\n' \
  "$single_edge_runs" "$single_edges" "$single_bounds" "$single_case_edge" "$single_case_saved" "$single_case_queue" "$single_case_process" "$single_case_submit" "$(relative_path "$REPEATED_EDIT_SUMMARY")" >> "$CASES_PATH"
printf 'gpu_border_edit_benchmark_case label=corner_edge_border source=repeated_edit status=pass runs=%s expected_edges=%s expected_bounds=%s dirty_edge_neighbor_subchunks=%s dirty_partial_saved_subchunks=%s terrain_queue_max_ms=%s process_wall_p95_ms=%s gpu_compositor_submit_max_ms=%s gpu_upload_fail=0 summary=%s\n' \
  "$corner_edge_runs" "$corner_edges" "$corner_bounds" "$corner_case_edge" "$corner_case_saved" "$corner_case_queue" "$corner_case_process" "$corner_case_submit" "$(relative_path "$REPEATED_EDIT_SUMMARY")" >> "$CASES_PATH"
printf 'gpu_border_edit_benchmark_case label=pressure_corner_border source=pressure_dirty status=pass fixture=%s local_x=%s local_z=%s dirty_blocks=%s dirty_edge_neighbor_subchunks=%s dirty_partial_saved_subchunks=%s dirty_last_edges=%s dirty_last_bounds=%s terrain_queue_max_ms=%s process_wall_p95_ms=%s gpu_compositor_submit_max_ms=%s current_chunk_collision=%s ground_misses=0 gpu_upload_fail=0 summary=%s\n' \
  "$pressure_fixture" "$pressure_local_x" "$pressure_local_z" "$partial_dirty_blocks" "$partial_edge_neighbor_subchunks" "$partial_saved_subchunks" "$partial_last_edges" "$partial_last_bounds" "$partial_queue_max" "$partial_process_max" "$partial_submit_max" "$partial_collision" "$(relative_path "$PRESSURE_DIRTY_SUMMARY")" >> "$CASES_PATH"

max_terrain_queue_ms="$(printf '%s\n%s\n%s\n%s\n%s\n' "$single_case_queue" "$corner_case_queue" "$full_queue_max" "$partial_queue_max" "$repeated_queue_max" | max_value)"
max_process_wall_p95_ms="$(printf '%s\n%s\n%s\n%s\n%s\n' "$single_case_process" "$corner_case_process" "$full_process_max" "$partial_process_max" "$repeated_process_max" | max_value)"
max_gpu_compositor_submit_ms="$(printf '%s\n%s\n%s\n%s\n%s\n' "$single_case_submit" "$corner_case_submit" "$full_submit_max" "$partial_submit_max" "$repeated_submit_max" | max_value)"
min_dirty_edge_neighbor_subchunks="$(printf '%s\n%s\n%s\n' "$single_case_edge" "$corner_case_edge" "$partial_edge_neighbor_subchunks" | min_value)"
max_dirty_edge_neighbor_subchunks="$(printf '%s\n%s\n%s\n' "$single_case_edge" "$corner_case_edge" "$partial_edge_neighbor_subchunks" | max_value)"
min_dirty_partial_saved_subchunks="$(printf '%s\n%s\n%s\n' "$single_case_saved" "$corner_case_saved" "$partial_saved_subchunks" | min_value)"
max_dirty_partial_saved_subchunks="$(printf '%s\n%s\n%s\n' "$single_case_saved" "$corner_case_saved" "$partial_saved_subchunks" | max_value)"
max_dirty_blocks="$(printf '%s\n%s\n' "$full_dirty_blocks" "$partial_dirty_blocks" | max_value)"

printf 'gpu_terrain_border_edit_benchmark status=pass reason=ok case_count=3 pass_cases=3 target_fps=%s budget_ms=%s min_repeated_runs=%s single_edge_runs=%s corner_edge_runs=%s pressure_fixture=%s pressure_local_x=%s pressure_local_z=%s min_pressure_dirty_blocks=%s max_dirty_blocks=%s min_dirty_edge_neighbor_subchunks=%s max_dirty_edge_neighbor_subchunks=%s min_dirty_partial_saved_subchunks=%s max_dirty_partial_saved_subchunks=%s max_terrain_queue_ms=%s max_process_wall_p95_ms=%s max_gpu_compositor_submit_ms=%s current_chunk_collision=%s ground_misses=0 gpu_upload_fail=0 scheduler_change_allowed=0 default_runtime_change_allowed=0 visible_quality_change_allowed=0 external_profile_status=pending_external_profiler requires_external_profiler_before_default=1 requires_mac_windows_validation=1 repeated_edit_summary=%s pressure_dirty_summary=%s repeated_edit_cases=%s cases=%s\n' \
  "$TARGET_FPS" "$budget_ms" "$MIN_REPEATED_RUNS" "$single_edge_runs" "$corner_edge_runs" "$pressure_fixture" "$pressure_local_x" "$pressure_local_z" "$MIN_PRESSURE_DIRTY_BLOCKS" "$max_dirty_blocks" "$min_dirty_edge_neighbor_subchunks" "$max_dirty_edge_neighbor_subchunks" "$min_dirty_partial_saved_subchunks" "$max_dirty_partial_saved_subchunks" "$max_terrain_queue_ms" "$max_process_wall_p95_ms" "$max_gpu_compositor_submit_ms" "$partial_collision" "$(relative_path "$REPEATED_EDIT_SUMMARY")" "$(relative_path "$PRESSURE_DIRTY_SUMMARY")" "$(relative_path "$REPEATED_CASES_PATH")" "$(relative_path "$CASES_PATH")" > "$SUMMARY_PATH"

cat "$SUMMARY_PATH"
