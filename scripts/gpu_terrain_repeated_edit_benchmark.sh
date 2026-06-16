#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/gpu_terrain_repeated_edit_benchmark_current"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

SUMMARY_PATH="$OUT_DIR/gpu-terrain-repeated-edit-benchmark-summary.txt"
CASES_PATH="$OUT_DIR/gpu-terrain-repeated-edit-benchmark-cases.txt"
SINGLE_EDGE_SUMMARY="${RUMPELMC_REPEATED_EDIT_BENCHMARK_SINGLE_EDGE_SUMMARY:-"$ROOT_DIR/logs/gpu_single_edge_dirty_repeat_current/edge-dirty-repeat-summary.txt"}"
CORNER_EDGE_SUMMARY="${RUMPELMC_REPEATED_EDIT_BENCHMARK_CORNER_EDGE_SUMMARY:-"$ROOT_DIR/logs/gpu_edge_dirty_repeat_current/edge-dirty-repeat-summary.txt"}"
RUN_REPEATS="${RUMPELMC_REPEATED_EDIT_BENCHMARK_RUN_REPEATS:-0}"
MIN_RUNS="${RUMPELMC_REPEATED_EDIT_BENCHMARK_MIN_RUNS:-3}"
REPEAT_COUNT="${RUMPELMC_REPEATED_EDIT_BENCHMARK_REPEAT_COUNT:-$MIN_RUNS}"
TARGET_FPS="${RUMPELMC_REPEATED_EDIT_BENCHMARK_TARGET_FPS:-150}"

mkdir -p "$OUT_DIR"

fail() {
  echo "gpu_terrain_repeated_edit_benchmark: $*" >&2
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

field_from_prefix() {
  prefix="$1"
  key="$2"
  path="$3"
  awk -v prefix="$prefix" -v key="$key" '
    index($0, prefix) == 1 {
      wanted = key "="
      for (i = 1; i <= NF; i++) {
        if (index($i, wanted) == 1) {
          value = substr($i, length(wanted) + 1)
          gsub(/^"/, "", value)
          gsub(/"$/, "", value)
          print value
          exit
        }
      }
    }
  ' "$path"
}

max_run_field() {
  key="$1"
  path="$2"
  awk -v key="$key" '
    function parse_fields(  i, pos, k, v) {
      for (i = 1; i <= NF; i++) {
        pos = index($i, "=")
        if (pos > 0) {
          k = substr($i, 1, pos - 1)
          v = substr($i, pos + 1)
          if (k == key && v ~ /^-?[0-9]+([.][0-9]+)?$/) {
            if (!seen || v + 0 > max) {
              max = v + 0
              seen = 1
            }
          }
        }
      }
    }
    $1 ~ /^run=/ {
      parse_fields()
    }
    END {
      if (seen) {
        printf("%.3f\n", max)
      } else {
        print "0.000"
      }
    }
  ' "$path"
}

run_fail_count() {
  path="$1"
  awk '
    function value_of(key,  i, wanted) {
      wanted = key "="
      for (i = 1; i <= NF; i++) {
        if (index($i, wanted) == 1) {
          return substr($i, length(wanted) + 1)
        }
      }
      return ""
    }
    $1 ~ /^run=/ {
      if (value_of("status") != "pass" || value_of("gpu_upload_fail") + 0 != 0) {
        failures++
      }
    }
    END { print failures + 0 }
  ' "$path"
}

require_numeric_ge() {
  req_label="$1"
  req_value="$2"
  req_min_value="$3"
  awk -v label="$req_label" -v value="$req_value" -v min_value="$req_min_value" '
    BEGIN {
      if (value + 0 < min_value + 0) {
        printf("gpu_terrain_repeated_edit_benchmark: %s %.3f below %.3f\n", label, value, min_value) > "/dev/stderr"
        exit 1
      }
    }
  '
}

require_numeric_le() {
  req_label="$1"
  req_value="$2"
  req_max_value="$3"
  awk -v label="$req_label" -v value="$req_value" -v max_value="$req_max_value" '
    BEGIN {
      if (value + 0 > max_value + 0) {
        printf("gpu_terrain_repeated_edit_benchmark: %s %.3f exceeds %.3f\n", label, value, max_value) > "/dev/stderr"
        exit 1
      }
    }
  '
}

write_case() {
  label="$1"
  summary="$2"
  expected_edges="$3"
  expected_bounds="$4"
  min_edge_neighbor_subchunks="$5"

  test -s "$summary" || fail "missing $label repeated edit summary $summary"
  header_edges="$(field_from_prefix "GPU terrain edge dirty repeat summary" expected_edges "$summary")"
  header_bounds="$(field_from_prefix "GPU terrain edge dirty repeat summary" expected_bounds "$summary")"
  runs="$(field_from_prefix "aggregate" runs "$summary")"
  aggregate_status="$(field_from_prefix "aggregate" status "$summary")"
  edge_min="$(field_from_prefix "aggregate" dirty_edge_neighbor_subchunks_min "$summary")"
  edge_max="$(field_from_prefix "aggregate" dirty_edge_neighbor_subchunks_max "$summary")"
  saved_min="$(field_from_prefix "aggregate" dirty_partial_saved_subchunks_min "$summary")"
  saved_max="$(field_from_prefix "aggregate" dirty_partial_saved_subchunks_max "$summary")"
  queue_max="$(field_from_prefix "aggregate" terrain_queue_max_ms_max "$summary")"
  submit_max="$(field_from_prefix "aggregate" gpu_compositor_submit_max_ms_max "$summary")"
  process_max="$(field_from_prefix "aggregate" process_wall_p95_ms_max "$summary")"
  upload_fail_max="$(max_run_field gpu_upload_fail "$summary")"
  failed_runs="$(run_fail_count "$summary")"

  test "$header_edges" = "$expected_edges" || fail "$label expected_edges=$header_edges, expected $expected_edges"
  test "$header_bounds" = "$expected_bounds" || fail "$label expected_bounds=$header_bounds, expected $expected_bounds"
  test "$aggregate_status" = "pass" || fail "$label aggregate status=$aggregate_status, expected pass"
  require_numeric_ge "$label runs" "${runs:-0}" "$MIN_RUNS"
  require_numeric_ge "$label dirty_edge_neighbor_subchunks_min" "${edge_min:-0}" "$min_edge_neighbor_subchunks"
  require_numeric_ge "$label dirty_partial_saved_subchunks_min" "${saved_min:-0}" 1
  require_numeric_le "$label terrain_queue_max_ms" "${queue_max:-0}" "$budget_ms"
  require_numeric_le "$label gpu_compositor_submit_max_ms" "${submit_max:-0}" "$budget_ms"
  require_numeric_le "$label process_wall_p95_ms" "${process_max:-0}" "$budget_ms"
  require_numeric_le "$label gpu_upload_fail" "$upload_fail_max" 0
  require_numeric_le "$label failed_runs" "$failed_runs" 0

  printf 'gpu_repeated_edit_benchmark_case label=%s status=pass runs=%s expected_edges=%s expected_bounds=%s dirty_edge_neighbor_subchunks_min=%s dirty_edge_neighbor_subchunks_max=%s dirty_partial_saved_subchunks_min=%s dirty_partial_saved_subchunks_max=%s max_terrain_queue_ms=%s max_process_wall_p95_ms=%s max_gpu_compositor_submit_ms=%s gpu_upload_fail=0 failed_runs=0 summary=%s\n' \
    "$label" "$runs" "$expected_edges" "$expected_bounds" "$edge_min" "$edge_max" "$saved_min" "$saved_max" "$queue_max" "$process_max" "$submit_max" "$(relative_path "$summary")" >> "$CASES_PATH"
}

case "$MIN_RUNS" in
  ''|*[!0-9]*) fail "RUMPELMC_REPEATED_EDIT_BENCHMARK_MIN_RUNS must be a positive integer" ;;
esac
if [ "$MIN_RUNS" -lt 1 ]; then
  fail "RUMPELMC_REPEATED_EDIT_BENCHMARK_MIN_RUNS must be greater than zero"
fi
case "$REPEAT_COUNT" in
  ''|*[!0-9]*) fail "RUMPELMC_REPEATED_EDIT_BENCHMARK_REPEAT_COUNT must be a positive integer" ;;
esac
if [ "$REPEAT_COUNT" -lt 1 ]; then
  fail "RUMPELMC_REPEATED_EDIT_BENCHMARK_REPEAT_COUNT must be greater than zero"
fi

budget_ms="$(frame_budget_ms)"

if [ "$RUN_REPEATS" = "1" ]; then
  single_dir="$OUT_DIR/single-edge"
  corner_dir="$OUT_DIR/corner-edge"
  RUMPELMC_EDGE_DIRTY_REPEAT_COUNT="$REPEAT_COUNT" \
    RUMPELMC_EDGE_DIRTY_REPEAT_TARGET_FPS="$TARGET_FPS" \
    sh "$ROOT_DIR/scripts/gpu_terrain_single_edge_dirty_repeat.sh" "$single_dir"
  RUMPELMC_EDGE_DIRTY_REPEAT_COUNT="$REPEAT_COUNT" \
    RUMPELMC_EDGE_DIRTY_REPEAT_TARGET_FPS="$TARGET_FPS" \
    sh "$ROOT_DIR/scripts/gpu_terrain_edge_dirty_repeat.sh" "$corner_dir"
  SINGLE_EDGE_SUMMARY="$single_dir/edge-dirty-repeat-summary.txt"
  CORNER_EDGE_SUMMARY="$corner_dir/edge-dirty-repeat-summary.txt"
fi

SINGLE_EDGE_SUMMARY="$(normalize_path "$SINGLE_EDGE_SUMMARY")"
CORNER_EDGE_SUMMARY="$(normalize_path "$CORNER_EDGE_SUMMARY")"

: > "$CASES_PATH"
write_case single_edge "$SINGLE_EDGE_SUMMARY" pos_x "31,64,16:31,64,16" 4
write_case corner_edge "$CORNER_EDGE_SUMMARY" pos_x,pos_z "31,64,31:31,64,31" 8

awk \
  -v budget_ms="$budget_ms" \
  -v min_runs="$MIN_RUNS" \
  -v target_fps="$TARGET_FPS" \
  -v single_edge_summary="$(relative_path "$SINGLE_EDGE_SUMMARY")" \
  -v corner_edge_summary="$(relative_path "$CORNER_EDGE_SUMMARY")" \
  -v cases_path="$(relative_path "$CASES_PATH")" '
  function reset_fields(  i) {
    for (i in f) {
      delete f[i]
    }
  }
  function parse_fields(  i, pos, key, value) {
    reset_fields()
    for (i = 2; i <= NF; i++) {
      pos = index($i, "=")
      if (pos > 0) {
        key = substr($i, 1, pos - 1)
        value = substr($i, pos + 1)
        f[key] = value
      }
    }
  }
  function max_update(key, target) {
    if (f[key] ~ /^-?[0-9]+([.][0-9]+)?$/) {
      if (!(target in seen) || f[key] + 0 > max_value[target]) {
        max_value[target] = f[key] + 0
        seen[target] = 1
      }
    }
  }
  function min_update(key, target) {
    if (f[key] ~ /^-?[0-9]+([.][0-9]+)?$/) {
      if (!(target in min_seen) || f[key] + 0 < min_value[target]) {
        min_value[target] = f[key] + 0
        min_seen[target] = 1
      }
    }
  }
  function max_text(target) {
    return (target in seen) ? sprintf("%.3f", max_value[target]) : "0.000"
  }
  function min_int(target) {
    return (target in min_seen) ? sprintf("%d", min_value[target]) : "0"
  }
  $1 == "gpu_repeated_edit_benchmark_case" {
    parse_fields()
    case_count++
    if (f["status"] == "pass") {
      pass_cases++
    }
    if (f["label"] == "single_edge") {
      single_edge_runs = f["runs"]
    } else if (f["label"] == "corner_edge") {
      corner_edge_runs = f["runs"]
    }
    max_update("max_terrain_queue_ms", "terrain_queue")
    max_update("max_process_wall_p95_ms", "process_wall")
    max_update("max_gpu_compositor_submit_ms", "gpu_submit")
    min_update("dirty_edge_neighbor_subchunks_min", "edge_neighbor_subchunks")
    min_update("dirty_partial_saved_subchunks_min", "partial_saved_subchunks")
  }
  END {
    status = "pass"
    reason = "ok"
    if (case_count != 2 || pass_cases != 2) {
      status = "fail"
      reason = "case_count"
    }
    printf("gpu_terrain_repeated_edit_benchmark status=%s reason=%s case_count=%d pass_cases=%d min_runs=%s target_fps=%s budget_ms=%s single_edge_runs=%s corner_edge_runs=%s min_dirty_edge_neighbor_subchunks=%s min_dirty_partial_saved_subchunks=%s max_terrain_queue_ms=%s max_process_wall_p95_ms=%s max_gpu_compositor_submit_ms=%s gpu_upload_fail=0 scheduler_change_allowed=0 default_runtime_change_allowed=0 visible_quality_change_allowed=0 external_profile_status=pending_external_profiler requires_external_profiler_before_default=1 requires_mac_windows_validation=1 single_edge_summary=%s corner_edge_summary=%s cases=%s\n", status, reason, case_count, pass_cases, min_runs, target_fps, budget_ms, single_edge_runs, corner_edge_runs, min_int("edge_neighbor_subchunks"), min_int("partial_saved_subchunks"), max_text("terrain_queue"), max_text("process_wall"), max_text("gpu_submit"), single_edge_summary, corner_edge_summary, cases_path)
    if (status != "pass") {
      exit 1
    }
  }
' "$CASES_PATH" > "$SUMMARY_PATH" || {
  cat "$SUMMARY_PATH" >&2 || true
  fail "repeated edit benchmark failed"
}

cat "$SUMMARY_PATH"
