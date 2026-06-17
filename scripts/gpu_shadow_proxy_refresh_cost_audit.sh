#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/gpu_shadow_proxy_refresh_cost_audit_current"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

SUMMARY_PATH="$OUT_DIR/gpu-shadow-proxy-refresh-cost-audit-summary.txt"
CASES_PATH="$OUT_DIR/gpu-shadow-proxy-refresh-cost-audit-cases.txt"
MATRIX_ROOT="${RUMPELMC_SHADOW_PROXY_REFRESH_COST_PARTIAL_DIRTY_EDGE_MATRIX_ROOT:-"$ROOT_DIR/logs/gpu_terrain_partial_dirty_edge_matrix_current/cases"}"
PRESSURE_ROOT="${RUMPELMC_SHADOW_PROXY_REFRESH_COST_PRESSURE_DIRTY_COMPARE_ROOT:-"$ROOT_DIR/logs/gpu_terrain_pressure_dirty_compare_current"}"
MIN_MATRIX_CASES="${RUMPELMC_SHADOW_PROXY_REFRESH_COST_MIN_MATRIX_CASES:-16}"
MIN_PRESSURE_CASES="${RUMPELMC_SHADOW_PROXY_REFRESH_COST_MIN_PRESSURE_CASES:-2}"
TARGET_FPS="${RUMPELMC_SHADOW_PROXY_REFRESH_COST_TARGET_FPS:-150}"
MAX_QUEUE_MS="${RUMPELMC_SHADOW_PROXY_REFRESH_COST_MAX_QUEUE_MS:-}"
MAX_PROCESS_MS="${RUMPELMC_SHADOW_PROXY_REFRESH_COST_MAX_PROCESS_MS:-}"
MAX_SUBMIT_MS="${RUMPELMC_SHADOW_PROXY_REFRESH_COST_MAX_SUBMIT_MS:-}"

mkdir -p "$OUT_DIR"

fail() {
  echo "gpu_shadow_proxy_refresh_cost_audit: $*" >&2
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

  shadow_path="$(field_metric shadow_path "$evidence_path")"
  shadow_mode="$(field_metric shadow_mode "$evidence_path")"
  shadow_mesh="$(field_metric shadow_mesh "$evidence_path")"
  mesh_shadow_only="$(field_metric mesh_shadow_only "$evidence_path")"
  proxy_shadow="$(field_metric proxy_shadow "$evidence_path")"
  proxy_shadow_only="$(field_metric proxy_shadow_only "$evidence_path")"
  compact_shadow_proxy="$(field_metric compact_shadow_proxy "$evidence_path")"
  compact_shadow_normals_saved="$(field_metric compact_shadow_normals_saved "$evidence_path")"
  proxy_refresh_reuse="$(field_metric proxy_refresh_reuse "$evidence_path")"
  fast_proxy="$(field_metric fast_proxy "$evidence_path")"
  cpu_proxy="$(field_metric cpu_proxy "$evidence_path")"
  native_shadow_requested="$(field_metric native_shadow_requested "$evidence_path")"
  native_shadow_active="$(field_metric native_shadow_active "$evidence_path")"
  native_shadow_fallback="$(field_metric native_shadow_fallback "$evidence_path")"
  native_shadow_implemented="$(field_metric native_shadow_implemented "$evidence_path")"
  native_shadow_resource_status="$(field_metric native_shadow_resource_status "$evidence_path")"
  current_chunk_collision="$(field_metric_any current_chunk_collision "$summary_path" "$evidence_path")"
  ground_misses="$(field_metric_any ground_misses "$summary_path" "$evidence_path")"
  gpu_upload_fail="$(field_metric gpu_upload_fail "$evidence_path")"
  gpu_upload_fail_capacity="$(field_metric gpu_upload_fail_capacity "$evidence_path")"
  gpu_upload_fail_fragmented="$(field_metric gpu_upload_fail_fragmented "$evidence_path")"
  terrain_queue_max_ms="$(field_metric max_ms "$summary_path")"
  process_wall_p95_ms="$(field_metric process_wall_p95_ms "$summary_path")"
  gpu_compositor_submit_max_ms="$(field_metric gpu_compositor_submit_max_ms "$summary_path")"

  reason="ok"
  if [ "$shadow_path" != "godot_proxy" ]; then
    reason="$(append_reason "$reason" "shadow_path_changed")"
  fi
  if [ "$shadow_mode" != "conservative" ]; then
    reason="$(append_reason "$reason" "shadow_mode_changed")"
  fi
  if [ "$shadow_mesh" != "compact" ]; then
    reason="$(append_reason "$reason" "shadow_mesh_changed")"
  fi
  if ! numeric_ge "$mesh_shadow_only" 1; then
    reason="$(append_reason "$reason" "missing_mesh_shadow_only")"
  fi
  if ! numeric_ge "$proxy_shadow" 1; then
    reason="$(append_reason "$reason" "missing_proxy_shadow")"
  fi
  if ! numeric_ge "$proxy_shadow_only" 1; then
    reason="$(append_reason "$reason" "missing_proxy_shadow_only")"
  fi
  if ! numeric_eq "$proxy_shadow" "$mesh_shadow_only"; then
    reason="$(append_reason "$reason" "shadow_proxy_count_mismatch")"
  fi
  if ! numeric_eq "$cpu_proxy" "$proxy_shadow"; then
    reason="$(append_reason "$reason" "cpu_proxy_count_mismatch")"
  fi
  if ! numeric_ge "$compact_shadow_proxy" "$proxy_shadow"; then
    reason="$(append_reason "$reason" "compact_shadow_proxy_under_proxy_shadow")"
  fi
  if ! numeric_ge "$compact_shadow_normals_saved" 1; then
    reason="$(append_reason "$reason" "missing_compact_shadow_savings")"
  fi
  if ! numeric_ge "$proxy_refresh_reuse" 1; then
    reason="$(append_reason "$reason" "missing_proxy_refresh_reuse")"
  fi
  if ! numeric_eq "$fast_proxy" "$compact_shadow_proxy"; then
    reason="$(append_reason "$reason" "fast_proxy_compact_mismatch")"
  fi
  if ! numeric_eq "$native_shadow_requested" 0; then
    reason="$(append_reason "$reason" "native_shadow_requested")"
  fi
  if ! numeric_eq "$native_shadow_active" 0; then
    reason="$(append_reason "$reason" "native_shadow_active")"
  fi
  if ! numeric_eq "$native_shadow_fallback" 0; then
    reason="$(append_reason "$reason" "native_shadow_fallback")"
  fi
  if ! numeric_eq "$native_shadow_implemented" 0; then
    reason="$(append_reason "$reason" "native_shadow_implemented")"
  fi
  if [ "$native_shadow_resource_status" != "disabled" ]; then
    reason="$(append_reason "$reason" "native_shadow_resource_enabled")"
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
  if ! numeric_le "$terrain_queue_max_ms" "$MAX_QUEUE_MS"; then
    reason="$(append_reason "$reason" "terrain_queue_budget")"
  fi
  if ! numeric_le "$process_wall_p95_ms" "$MAX_PROCESS_MS"; then
    reason="$(append_reason "$reason" "process_wall_budget")"
  fi
  if ! numeric_le "$gpu_compositor_submit_max_ms" "$MAX_SUBMIT_MS"; then
    reason="$(append_reason "$reason" "gpu_compositor_submit_budget")"
  fi

  status="pass"
  if [ "$reason" != "ok" ]; then
    status="fail"
  fi

  printf 'gpu_shadow_proxy_refresh_cost_case kind=%s label=%s mode=%s status=%s reason=%s target_fps=%s queue_budget_ms=%s process_budget_ms=%s submit_budget_ms=%s shadow_path=%s shadow_mode=%s shadow_mesh=%s mesh_shadow_only=%s proxy_shadow=%s proxy_shadow_only=%s compact_shadow_proxy=%s compact_shadow_normals_saved=%s proxy_refresh_reuse=%s fast_proxy=%s cpu_proxy=%s native_shadow_requested=%s native_shadow_active=%s native_shadow_fallback=%s native_shadow_implemented=%s native_shadow_resource_status=%s current_chunk_collision=%s ground_misses=%s gpu_upload_fail=%s gpu_upload_fail_capacity=%s gpu_upload_fail_fragmented=%s terrain_queue_max_ms=%s process_wall_p95_ms=%s gpu_compositor_submit_max_ms=%s summary=%s evidence=%s\n' \
    "$kind" "$label" "$mode" "$status" "$reason" "$TARGET_FPS" "$MAX_QUEUE_MS" "$MAX_PROCESS_MS" "$MAX_SUBMIT_MS" \
    "$shadow_path" "$shadow_mode" "$shadow_mesh" "$mesh_shadow_only" "$proxy_shadow" "$proxy_shadow_only" \
    "$compact_shadow_proxy" "$compact_shadow_normals_saved" "$proxy_refresh_reuse" "$fast_proxy" "$cpu_proxy" \
    "$native_shadow_requested" "$native_shadow_active" "$native_shadow_fallback" "$native_shadow_implemented" "$native_shadow_resource_status" \
    "$current_chunk_collision" "$ground_misses" "$gpu_upload_fail" "$gpu_upload_fail_capacity" "$gpu_upload_fail_fragmented" \
    "$terrain_queue_max_ms" "$process_wall_p95_ms" "$gpu_compositor_submit_max_ms" "$rel_summary" "$rel_evidence" >> "$CASES_PATH"
}

case "$MIN_MATRIX_CASES" in
  ''|*[!0-9]*) fail "RUMPELMC_SHADOW_PROXY_REFRESH_COST_MIN_MATRIX_CASES must be a positive integer" ;;
esac
case "$MIN_PRESSURE_CASES" in
  ''|*[!0-9]*) fail "RUMPELMC_SHADOW_PROXY_REFRESH_COST_MIN_PRESSURE_CASES must be a positive integer" ;;
esac

MATRIX_ROOT="$(normalize_path "$MATRIX_ROOT")"
PRESSURE_ROOT="$(normalize_path "$PRESSURE_ROOT")"
test -d "$MATRIX_ROOT" || fail "missing partial dirty edge matrix root $(relative_path "$MATRIX_ROOT")"
test -d "$PRESSURE_ROOT" || fail "missing pressure dirty compare root $(relative_path "$PRESSURE_ROOT")"

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

case_paths="$OUT_DIR/gpu-shadow-proxy-refresh-cost-audit-paths.tmp"
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
  -v queue_budget_ms="$MAX_QUEUE_MS" \
  -v process_budget_ms="$MAX_PROCESS_MS" \
  -v submit_budget_ms="$MAX_SUBMIT_MS" '
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
  $1 == "gpu_shadow_proxy_refresh_cost_case" {
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
    if (f["shadow_path"] != "godot_proxy") {
      shadow_path_changed_cases++
    }
    if (f["shadow_mode"] != "conservative") {
      shadow_mode_changed_cases++
    }
    if (f["shadow_mesh"] != "compact") {
      shadow_mesh_changed_cases++
    }
    if (is_number(f["native_shadow_requested"]) && f["native_shadow_requested"] + 0 != 0) {
      native_shadow_requested_cases++
    }
    if (is_number(f["native_shadow_active"]) && f["native_shadow_active"] + 0 != 0) {
      native_shadow_active_cases++
    }
    if (is_number(f["gpu_upload_fail"]) && f["gpu_upload_fail"] + 0 != 0) {
      upload_fail_cases++
    }
    if (is_number(f["ground_misses"]) && f["ground_misses"] + 0 != 0) {
      ground_miss_cases++
    }
    if (is_number(f["terrain_queue_max_ms"]) && f["terrain_queue_max_ms"] + 0 > queue_budget_ms + 0) {
      terrain_queue_budget_cases++
    }
    if (is_number(f["process_wall_p95_ms"]) && f["process_wall_p95_ms"] + 0 > process_budget_ms + 0) {
      process_wall_budget_cases++
    }
    if (is_number(f["gpu_compositor_submit_max_ms"]) && f["gpu_compositor_submit_max_ms"] + 0 > submit_budget_ms + 0) {
      submit_budget_cases++
    }
    max_update("mesh_shadow_only", "mesh_shadow_only")
    max_update("proxy_shadow", "proxy_shadow")
    max_update("proxy_shadow_only", "proxy_shadow_only")
    max_update("compact_shadow_proxy", "compact_shadow_proxy")
    max_update("compact_shadow_normals_saved", "compact_shadow_normals_saved")
    max_update("proxy_refresh_reuse", "proxy_refresh_reuse")
    max_update("fast_proxy", "fast_proxy")
    max_update("cpu_proxy", "cpu_proxy")
    max_update("terrain_queue_max_ms", "terrain_queue_max_ms")
    max_update("process_wall_p95_ms", "process_wall_p95_ms")
    max_update("gpu_compositor_submit_max_ms", "gpu_compositor_submit_max_ms")
    max_update("current_chunk_collision", "current_chunk_collision")
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
    printf("gpu_shadow_proxy_refresh_cost_audit status=%s reason=%s case_count=%d pass_cases=%d fail_cases=%d matrix_case_count=%d pressure_case_count=%d min_matrix_cases=%d min_pressure_cases=%d target_fps=%s queue_budget_ms=%s process_budget_ms=%s submit_budget_ms=%s shadow_path_status=godot_proxy shadow_mode_status=conservative shadow_mesh_status=compact max_mesh_shadow_only=%s max_proxy_shadow=%s max_proxy_shadow_only=%s max_compact_shadow_proxy=%s max_compact_shadow_normals_saved=%s max_proxy_refresh_reuse=%s max_fast_proxy=%s max_cpu_proxy=%s max_terrain_queue_ms=%s max_process_wall_p95_ms=%s max_gpu_compositor_submit_ms=%s max_current_chunk_collision=%s gpu_upload_fail=%d ground_misses=%d shadow_path_changed_cases=%d shadow_mode_changed_cases=%d shadow_mesh_changed_cases=%d native_shadow_requested_cases=%d native_shadow_active_cases=%d upload_fail_cases=%d ground_miss_cases=%d terrain_queue_budget_cases=%d process_wall_budget_cases=%d submit_budget_cases=%d default_runtime_change_allowed=0 visible_quality_change_allowed=0 external_profile_status=pending_external_profiler requires_external_profiler_before_default=1 requires_mac_windows_validation=1 cases=%s\n", status, reason, case_count, pass_cases, fail_cases, matrix_case_count, pressure_case_count, min_matrix_cases, min_pressure_cases, target_fps, queue_budget_ms, process_budget_ms, submit_budget_ms, max_text("mesh_shadow_only"), max_text("proxy_shadow"), max_text("proxy_shadow_only"), max_text("compact_shadow_proxy"), max_text("compact_shadow_normals_saved"), max_text("proxy_refresh_reuse"), max_text("fast_proxy"), max_text("cpu_proxy"), max_text("terrain_queue_max_ms"), max_text("process_wall_p95_ms"), max_text("gpu_compositor_submit_max_ms"), max_text("current_chunk_collision"), sum_value["gpu_upload_fail"], sum_value["ground_misses"], shadow_path_changed_cases, shadow_mode_changed_cases, shadow_mesh_changed_cases, native_shadow_requested_cases, native_shadow_active_cases, upload_fail_cases, ground_miss_cases, terrain_queue_budget_cases, process_wall_budget_cases, submit_budget_cases, cases_path) > summary_path
    if (status != "pass") {
      exit 1
    }
  }
' "$CASES_PATH" || {
  cat "$SUMMARY_PATH" >&2 || true
  fail "shadow proxy refresh cost audit failed"
}

cat "$SUMMARY_PATH"
