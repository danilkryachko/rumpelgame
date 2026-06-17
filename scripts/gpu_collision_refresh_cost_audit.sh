#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/gpu_collision_refresh_cost_audit_current"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

SUMMARY_PATH="$OUT_DIR/gpu-collision-refresh-cost-audit-summary.txt"
CASES_PATH="$OUT_DIR/gpu-collision-refresh-cost-audit-cases.txt"
MATRIX_ROOT="${RUMPELMC_COLLISION_REFRESH_COST_PARTIAL_DIRTY_EDGE_MATRIX_ROOT:-"$ROOT_DIR/logs/gpu_terrain_partial_dirty_edge_matrix_current/cases"}"
PRESSURE_ROOT="${RUMPELMC_COLLISION_REFRESH_COST_PRESSURE_DIRTY_COMPARE_ROOT:-"$ROOT_DIR/logs/gpu_terrain_pressure_dirty_compare_current"}"
MIN_MATRIX_CASES="${RUMPELMC_COLLISION_REFRESH_COST_MIN_MATRIX_CASES:-16}"
MIN_PRESSURE_CASES="${RUMPELMC_COLLISION_REFRESH_COST_MIN_PRESSURE_CASES:-2}"
TARGET_FPS="${RUMPELMC_COLLISION_REFRESH_COST_TARGET_FPS:-150}"
MAX_QUEUE_DEPTH="${RUMPELMC_COLLISION_REFRESH_COST_MAX_QUEUE_DEPTH:-64}"
MAX_PHASE_MS="${RUMPELMC_COLLISION_REFRESH_COST_MAX_PHASE_MS:-}"

mkdir -p "$OUT_DIR"

fail() {
  echo "gpu_collision_refresh_cost_audit: $*" >&2
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

field_metric_any() {
  key="$1"
  shift
  for path in "$@"; do
    if [ -s "$path" ]; then
      value="$(field_metric "$key" "$path")"
      if [ -n "$value" ]; then
        printf '%s\n' "$value"
        return
      fi
    fi
  done
  printf 'n/a\n'
}

phase_total() {
  value="$1"
  awk -v value="$value" '
    BEGIN {
      if (split(value, part, "/") < 5) {
        print "n/a"
        exit
      }
      printf("%.3f\n", part[1] + part[2] + part[3] + part[4] + part[5])
    }
  '
}

phase_component_max() {
  value="$1"
  awk -v value="$value" '
    BEGIN {
      count = split(value, part, "/")
      if (count < 5) {
        print "n/a"
        exit
      }
      max = part[1] + 0.0
      for (i = 2; i <= count; i++) {
        if (part[i] + 0.0 > max) {
          max = part[i] + 0.0
        }
      }
      printf("%.3f\n", max)
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

append_reason() {
  current="$1"
  next="$2"
  if [ "$current" = "ok" ]; then
    printf '%s\n' "$next"
  else
    printf '%s,%s\n' "$current" "$next"
  fi
}

record_case() {
  kind="$1"
  label="$2"
  mode="$3"
  evidence_path="$(normalize_path "$4")"
  summary_path="$(dirname -- "$evidence_path")/movement-stress-summary.txt"
  rel_evidence="$(relative_path "$evidence_path")"
  rel_summary="$(relative_path "$summary_path")"

  test -s "$evidence_path" || fail "missing evidence $rel_evidence"
  test -s "$summary_path" || fail "missing movement summary $rel_summary"

  collision_refresh="$(field_metric collision_refresh "$evidence_path")"
  collision_refresh_rebuilt="$(field_metric collision_refresh_rebuilt "$evidence_path")"
  collision_refresh_unchanged="$(field_metric collision_refresh_unchanged "$evidence_path")"
  collision_refresh_missing="$(field_metric collision_refresh_missing "$evidence_path")"
  collision_refresh_last_rebuilt="$(field_metric collision_refresh_last_rebuilt "$evidence_path")"
  collision_q_max="$(field_metric collision_q_max "$evidence_path")"
  collision_q_enq="$(field_metric collision_q_enq "$evidence_path")"
  collision_q_dup="$(field_metric collision_q_dup "$evidence_path")"
  collision_q_drained="$(field_metric collision_q_drained "$evidence_path")"
  collision_q_stale="$(field_metric collision_q_stale "$evidence_path")"
  collision_q_missing="$(field_metric collision_q_missing "$evidence_path")"
  collision_phase_max="$(field_metric collision_refresh_phase_max "$evidence_path")"
  collision_phase_total_ms="$(phase_total "$collision_phase_max")"
  collision_phase_component_ms="$(phase_component_max "$collision_phase_max")"
  current_chunk_collision="$(field_metric_any current_chunk_collision "$summary_path" "$evidence_path")"
  ground_misses="$(field_metric_any ground_misses "$summary_path" "$evidence_path")"
  gpu_upload_fail="$(field_metric gpu_upload_fail "$evidence_path")"
  gpu_upload_fail_capacity="$(field_metric gpu_upload_fail_capacity "$evidence_path")"
  gpu_upload_fail_fragmented="$(field_metric gpu_upload_fail_fragmented "$evidence_path")"
  terrain_queue_max_ms="$(field_metric max_ms "$summary_path")"
  process_wall_p95_ms="$(field_metric process_wall_p95_ms "$summary_path")"
  gpu_compositor_submit_max_ms="$(field_metric gpu_compositor_submit_max_ms "$summary_path")"

  reason="ok"
  if ! numeric_ge "$collision_refresh" 1; then
    reason="$(append_reason "$reason" "missing_collision_refresh")"
  fi
  if ! numeric_ge "$collision_refresh_rebuilt" 1; then
    reason="$(append_reason "$reason" "missing_collision_rebuild")"
  fi
  if ! numeric_ge "$collision_refresh_last_rebuilt" 1; then
    reason="$(append_reason "$reason" "missing_last_collision_rebuild")"
  fi
  if ! numeric_eq "$collision_refresh_missing" 0; then
    reason="$(append_reason "$reason" "collision_refresh_missing")"
  fi
  if ! numeric_eq "$collision_q_dup" 0; then
    reason="$(append_reason "$reason" "collision_queue_duplicates")"
  fi
  if ! numeric_eq "$collision_q_stale" 0; then
    reason="$(append_reason "$reason" "collision_queue_stale")"
  fi
  if ! numeric_eq "$collision_q_missing" 0; then
    reason="$(append_reason "$reason" "collision_queue_missing")"
  fi
  if ! numeric_le "$collision_q_max" "$MAX_QUEUE_DEPTH"; then
    reason="$(append_reason "$reason" "collision_queue_depth")"
  fi
  if ! numeric_le "$collision_phase_total_ms" "$MAX_PHASE_MS"; then
    reason="$(append_reason "$reason" "collision_phase_total_budget")"
  fi
  if ! numeric_le "$collision_phase_component_ms" "$MAX_PHASE_MS"; then
    reason="$(append_reason "$reason" "collision_phase_component_budget")"
  fi
  if ! numeric_ge "$current_chunk_collision" 1; then
    reason="$(append_reason "$reason" "current_chunk_collision_not_ready")"
  fi
  if ! numeric_eq "$ground_misses" 0; then
    reason="$(append_reason "$reason" "ground_misses")"
  fi
  if ! numeric_eq "$gpu_upload_fail" 0; then
    reason="$(append_reason "$reason" "gpu_upload_fail")"
  fi
  if ! numeric_eq "$gpu_upload_fail_capacity" 0; then
    reason="$(append_reason "$reason" "gpu_upload_fail_capacity")"
  fi
  if ! numeric_eq "$gpu_upload_fail_fragmented" 0; then
    reason="$(append_reason "$reason" "gpu_upload_fail_fragmented")"
  fi

  status="pass"
  if [ "$reason" != "ok" ]; then
    status="fail"
  fi

  printf 'gpu_collision_refresh_cost_case kind=%s label=%s mode=%s status=%s reason=%s target_fps=%s budget_ms=%s max_queue_depth=%s collision_refresh=%s collision_refresh_rebuilt=%s collision_refresh_unchanged=%s collision_refresh_missing=%s collision_refresh_last_rebuilt=%s collision_q_max=%s collision_q_enq=%s collision_q_dup=%s collision_q_drained=%s collision_q_stale=%s collision_q_missing=%s collision_refresh_phase_max=%s collision_phase_total_ms=%s collision_phase_component_ms=%s current_chunk_collision=%s ground_misses=%s gpu_upload_fail=%s gpu_upload_fail_capacity=%s gpu_upload_fail_fragmented=%s terrain_queue_max_ms=%s process_wall_p95_ms=%s gpu_compositor_submit_max_ms=%s summary=%s evidence=%s\n' \
    "$kind" "$label" "$mode" "$status" "$reason" "$TARGET_FPS" "$MAX_PHASE_MS" "$MAX_QUEUE_DEPTH" \
    "$collision_refresh" "$collision_refresh_rebuilt" "$collision_refresh_unchanged" "$collision_refresh_missing" "$collision_refresh_last_rebuilt" \
    "$collision_q_max" "$collision_q_enq" "$collision_q_dup" "$collision_q_drained" "$collision_q_stale" "$collision_q_missing" \
    "$collision_phase_max" "$collision_phase_total_ms" "$collision_phase_component_ms" "$current_chunk_collision" "$ground_misses" \
    "$gpu_upload_fail" "$gpu_upload_fail_capacity" "$gpu_upload_fail_fragmented" "$terrain_queue_max_ms" "$process_wall_p95_ms" "$gpu_compositor_submit_max_ms" \
    "$rel_summary" "$rel_evidence" >> "$CASES_PATH"
}

case "$MIN_MATRIX_CASES" in
  ''|*[!0-9]*) fail "RUMPELMC_COLLISION_REFRESH_COST_MIN_MATRIX_CASES must be a positive integer" ;;
esac
case "$MIN_PRESSURE_CASES" in
  ''|*[!0-9]*) fail "RUMPELMC_COLLISION_REFRESH_COST_MIN_PRESSURE_CASES must be a positive integer" ;;
esac
case "$MAX_QUEUE_DEPTH" in
  ''|*[!0-9]*) fail "RUMPELMC_COLLISION_REFRESH_COST_MAX_QUEUE_DEPTH must be a positive integer" ;;
esac

MATRIX_ROOT="$(normalize_path "$MATRIX_ROOT")"
PRESSURE_ROOT="$(normalize_path "$PRESSURE_ROOT")"
test -d "$MATRIX_ROOT" || fail "missing partial dirty edge matrix root $(relative_path "$MATRIX_ROOT")"
test -d "$PRESSURE_ROOT" || fail "missing pressure dirty compare root $(relative_path "$PRESSURE_ROOT")"

budget_ms="$(frame_budget_ms)"
if [ -z "$MAX_PHASE_MS" ]; then
  MAX_PHASE_MS="$budget_ms"
fi

case_paths="$OUT_DIR/gpu-collision-refresh-cost-audit-paths.tmp"
trap 'rm -f "$case_paths"' EXIT HUP INT TERM
: > "$CASES_PATH"

find "$MATRIX_ROOT" -mindepth 3 -maxdepth 3 -name 'gpu-terrain-movement-stress.png.txt' -type f -print | sort > "$case_paths"
matrix_case_count=0
while IFS= read -r evidence_path; do
  rel="${evidence_path#$MATRIX_ROOT/}"
  label="${rel%%/*}"
  rest="${rel#*/}"
  mode="${rest%%/*}"
  record_case partial_dirty_edge_matrix "$label" "$mode" "$evidence_path"
  matrix_case_count=$((matrix_case_count + 1))
done < "$case_paths"

pressure_case_count=0
for mode in full partial; do
  evidence_path="$PRESSURE_ROOT/$mode/pressure/gpu-terrain-movement-stress.png.txt"
  if [ -s "$evidence_path" ]; then
    record_case pressure_dirty_compare "pressure_$mode" "$mode" "$evidence_path"
    pressure_case_count=$((pressure_case_count + 1))
  fi
done

awk \
  -v summary_path="$SUMMARY_PATH" \
  -v cases_path="$CASES_PATH" \
  -v matrix_case_count="$matrix_case_count" \
  -v pressure_case_count="$pressure_case_count" \
  -v min_matrix_cases="$MIN_MATRIX_CASES" \
  -v min_pressure_cases="$MIN_PRESSURE_CASES" \
  -v target_fps="$TARGET_FPS" \
  -v budget_ms="$MAX_PHASE_MS" \
  -v max_queue_depth="$MAX_QUEUE_DEPTH" '
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
  function is_number(value) {
    return value ~ /^-?[0-9]+([.][0-9]+)?$/
  }
  function sum_update(key, target) {
    if (is_number(f[key])) {
      sum_value[target] += f[key] + 0
    }
  }
  function max_update(key, target) {
    if (is_number(f[key])) {
      if (!(target in max_seen) || f[key] + 0 > max_value[target]) {
        max_value[target] = f[key] + 0
        max_seen[target] = 1
      }
    }
  }
  function max_text(target) {
    if (target in max_seen) {
      return sprintf("%.3f", max_value[target])
    }
    return "n/a"
  }
  $1 == "gpu_collision_refresh_cost_case" {
    parse_fields()
    case_count++
    if (f["status"] == "pass") {
      pass_cases++
    } else {
      fail_cases++
    }
    if (f["kind"] == "partial_dirty_edge_matrix") {
      matrix_rows++
    } else if (f["kind"] == "pressure_dirty_compare") {
      pressure_rows++
    }
    if (is_number(f["collision_q_dup"]) && f["collision_q_dup"] + 0 != 0) {
      queue_duplicate_cases++
    }
    if (is_number(f["collision_q_stale"]) && f["collision_q_stale"] + 0 != 0) {
      queue_stale_cases++
    }
    if (is_number(f["collision_q_missing"]) && f["collision_q_missing"] + 0 != 0) {
      queue_missing_cases++
    }
    if (is_number(f["collision_refresh_missing"]) && f["collision_refresh_missing"] + 0 != 0) {
      refresh_missing_cases++
    }
    if (is_number(f["gpu_upload_fail"]) && f["gpu_upload_fail"] + 0 != 0) {
      upload_fail_cases++
    }
    if (is_number(f["ground_misses"]) && f["ground_misses"] + 0 != 0) {
      ground_miss_cases++
    }
    if (is_number(f["collision_phase_total_ms"]) && f["collision_phase_total_ms"] + 0 > budget_ms + 0) {
      phase_budget_cases++
    }
    max_update("collision_refresh", "collision_refresh")
    max_update("collision_refresh_rebuilt", "collision_refresh_rebuilt")
    max_update("collision_refresh_unchanged", "collision_refresh_unchanged")
    max_update("collision_q_max", "collision_q_max")
    max_update("collision_q_enq", "collision_q_enq")
    max_update("collision_q_drained", "collision_q_drained")
    max_update("collision_phase_total_ms", "collision_phase_total_ms")
    max_update("collision_phase_component_ms", "collision_phase_component_ms")
    max_update("terrain_queue_max_ms", "terrain_queue_max_ms")
    max_update("process_wall_p95_ms", "process_wall_p95_ms")
    max_update("gpu_compositor_submit_max_ms", "gpu_compositor_submit_max_ms")
    max_update("current_chunk_collision", "current_chunk_collision")
    sum_update("collision_refresh_missing", "collision_refresh_missing")
    sum_update("collision_q_dup", "collision_q_dup")
    sum_update("collision_q_stale", "collision_q_stale")
    sum_update("collision_q_missing", "collision_q_missing")
    sum_update("gpu_upload_fail", "gpu_upload_fail")
    sum_update("ground_misses", "ground_misses")
  }
  END {
    status = "pass"
    reason = "ok"
    if (matrix_case_count + 0 < min_matrix_cases + 0) {
      status = "fail"
      reason = "missing_matrix_cases"
    } else if (pressure_case_count + 0 < min_pressure_cases + 0) {
      status = "fail"
      reason = "missing_pressure_cases"
    } else if (fail_cases + 0 != 0) {
      status = "fail"
      reason = "case_failures"
    }
    printf("gpu_collision_refresh_cost_audit status=%s reason=%s case_count=%d pass_cases=%d fail_cases=%d matrix_case_count=%d pressure_case_count=%d min_matrix_cases=%d min_pressure_cases=%d target_fps=%s budget_ms=%s max_queue_depth=%s max_collision_refresh=%s max_collision_refresh_rebuilt=%s max_collision_refresh_unchanged=%s max_collision_q_max=%s max_collision_q_enq=%s max_collision_q_drained=%s max_collision_phase_total_ms=%s max_collision_phase_component_ms=%s max_terrain_queue_ms=%s max_process_wall_p95_ms=%s max_gpu_compositor_submit_ms=%s max_current_chunk_collision=%s collision_refresh_missing=%d collision_q_dup=%d collision_q_stale=%d collision_q_missing=%d gpu_upload_fail=%d ground_misses=%d queue_duplicate_cases=%d queue_stale_cases=%d queue_missing_cases=%d refresh_missing_cases=%d upload_fail_cases=%d ground_miss_cases=%d phase_budget_cases=%d default_runtime_change_allowed=0 visible_quality_change_allowed=0 external_profile_status=pending_external_profiler requires_external_profiler_before_default=1 requires_mac_windows_validation=1 cases=%s\n", status, reason, case_count, pass_cases, fail_cases, matrix_case_count, pressure_case_count, min_matrix_cases, min_pressure_cases, target_fps, budget_ms, max_queue_depth, max_text("collision_refresh"), max_text("collision_refresh_rebuilt"), max_text("collision_refresh_unchanged"), max_text("collision_q_max"), max_text("collision_q_enq"), max_text("collision_q_drained"), max_text("collision_phase_total_ms"), max_text("collision_phase_component_ms"), max_text("terrain_queue_max_ms"), max_text("process_wall_p95_ms"), max_text("gpu_compositor_submit_max_ms"), max_text("current_chunk_collision"), sum_value["collision_refresh_missing"], sum_value["collision_q_dup"], sum_value["collision_q_stale"], sum_value["collision_q_missing"], sum_value["gpu_upload_fail"], sum_value["ground_misses"], queue_duplicate_cases, queue_stale_cases, queue_missing_cases, refresh_missing_cases, upload_fail_cases, ground_miss_cases, phase_budget_cases, cases_path) > summary_path
    if (status != "pass") {
      exit 1
    }
  }
' "$CASES_PATH" || {
  cat "$SUMMARY_PATH" >&2 || true
  fail "collision refresh cost audit failed"
}

cat "$SUMMARY_PATH"
