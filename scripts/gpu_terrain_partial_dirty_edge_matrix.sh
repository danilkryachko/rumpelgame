#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/gpu_terrain_partial_dirty_edge_matrix_current"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

SUMMARY_PATH="$OUT_DIR/gpu-terrain-partial-dirty-edge-matrix-summary.txt"
CASES_PATH="$OUT_DIR/gpu-terrain-partial-dirty-edge-matrix-cases.txt"
RUN_CASES="${RUMPELMC_PARTIAL_DIRTY_EDGE_MATRIX_RUN_CASES:-0}"
TARGET_FPS="${RUMPELMC_PARTIAL_DIRTY_EDGE_MATRIX_TARGET_FPS:-150}"
Y_VALUE="${RUMPELMC_PARTIAL_DIRTY_EDGE_MATRIX_Y:-64}"

mkdir -p "$OUT_DIR"

fail() {
  echo "gpu_terrain_partial_dirty_edge_matrix: $*" >&2
  exit 1
}

relative_path() {
  path="$1"
  case "$path" in
    "$ROOT_DIR"/*) printf '%s\n' "${path#$ROOT_DIR/}" ;;
    *) printf '%s\n' "$path" ;;
  esac
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
        printf("gpu_terrain_partial_dirty_edge_matrix: %s %.3f below %.3f\n", label, value, min_value) > "/dev/stderr"
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
        printf("gpu_terrain_partial_dirty_edge_matrix: %s %.3f exceeds %.3f\n", label, value, max_value) > "/dev/stderr"
        exit 1
      }
    }
  '
}

case_specs() {
  cat <<'CASES'
pos_x_single single 127 80 pos_x 31,64,16:31,64,16 4
neg_x_single single 96 80 neg_x 0,64,16:0,64,16 4
pos_z_single single 112 95 pos_z 16,64,31:16,64,31 4
neg_z_single single 112 64 neg_z 16,64,0:16,64,0 4
pos_x_pos_z_corner corner 127 95 pos_x,pos_z 31,64,31:31,64,31 8
pos_x_neg_z_corner corner 127 64 pos_x,neg_z 31,64,0:31,64,0 8
neg_x_pos_z_corner corner 96 95 neg_x,pos_z 0,64,31:0,64,31 8
neg_x_neg_z_corner corner 96 64 neg_x,neg_z 0,64,0:0,64,0 8
CASES
}

run_case() {
  label="$1"
  x="$2"
  z="$3"
  edges="$4"
  bounds="$5"
  case_dir="$6"
  run_log="$case_dir/matrix-run.log"

  rm -rf "$case_dir"
  mkdir -p "$case_dir"
  echo "==> Partial dirty edge matrix: $label edges=$edges bounds=$bounds"
  if ! RUMPELMC_EDGE_DIRTY_COMPARE_X="$x" \
    RUMPELMC_EDGE_DIRTY_COMPARE_Y="$Y_VALUE" \
    RUMPELMC_EDGE_DIRTY_COMPARE_Z="$z" \
    RUMPELMC_EDGE_DIRTY_COMPARE_EXPECTED_EDGES="$edges" \
    RUMPELMC_EDGE_DIRTY_COMPARE_EXPECTED_BOUNDS="$bounds" \
    sh "$ROOT_DIR/scripts/gpu_terrain_edge_dirty_compare.sh" "$case_dir" > "$run_log" 2>&1; then
    cat "$run_log" >&2 || true
    fail "$label compare failed"
  fi
}

budget_ms="$(frame_budget_ms)"
: > "$CASES_PATH"

case_specs | while read -r label kind x z edges bounds min_edge_subchunks; do
  case_dir="$OUT_DIR/cases/$label"
  summary_path="$case_dir/edge-dirty-compare-summary.txt"
  if [ "$RUN_CASES" = "1" ]; then
    run_case "$label" "$x" "$z" "$edges" "$bounds" "$case_dir"
  fi
  test -s "$summary_path" || fail "missing $label summary $(relative_path "$summary_path"); set RUMPELMC_PARTIAL_DIRTY_EDGE_MATRIX_RUN_CASES=1 to refresh cases"

  header_edges="$(field_from_prefix "GPU terrain edge dirty compare summary" expected_edges "$summary_path")"
  header_bounds="$(field_from_prefix "GPU terrain edge dirty compare summary" expected_bounds "$summary_path")"
  header_x="$(field_from_prefix "GPU terrain edge dirty compare summary" x "$summary_path")"
  header_y="$(field_from_prefix "GPU terrain edge dirty compare summary" y "$summary_path")"
  header_z="$(field_from_prefix "GPU terrain edge dirty compare summary" z "$summary_path")"
  full_dirty_blocks="$(field_from_prefix "full" dirty_blocks "$summary_path")"
  full_rebuild_subchunks="$(field_from_prefix "full" dirty_last_rebuild_subchunks "$summary_path")"
  full_edge_neighbor_subchunks="$(field_from_prefix "full" dirty_edge_neighbor_subchunks "$summary_path")"
  full_partial_subchunks="$(field_from_prefix "full" dirty_partial_subchunks "$summary_path")"
  full_saved_subchunks="$(field_from_prefix "full" dirty_partial_saved_subchunks "$summary_path")"
  full_collision="$(field_from_prefix "full" current_chunk_collision "$summary_path")"
  full_queue_ms="$(field_from_prefix "full" terrain_queue_max_ms "$summary_path")"
  full_process_ms="$(field_from_prefix "full" process_wall_p95_ms "$summary_path")"
  full_submit_ms="$(field_from_prefix "full" gpu_compositor_submit_max_ms "$summary_path")"
  full_upload_fail="$(field_from_prefix "full" gpu_upload_fail "$summary_path")"
  partial_dirty_blocks="$(field_from_prefix "partial" dirty_blocks "$summary_path")"
  partial_rebuild_subchunks="$(field_from_prefix "partial" dirty_last_rebuild_subchunks "$summary_path")"
  partial_edge_neighbor_subchunks="$(field_from_prefix "partial" dirty_edge_neighbor_subchunks "$summary_path")"
  partial_partial_subchunks="$(field_from_prefix "partial" dirty_partial_subchunks "$summary_path")"
  partial_saved_subchunks="$(field_from_prefix "partial" dirty_partial_saved_subchunks "$summary_path")"
  partial_collision="$(field_from_prefix "partial" current_chunk_collision "$summary_path")"
  partial_queue_ms="$(field_from_prefix "partial" terrain_queue_max_ms "$summary_path")"
  partial_process_ms="$(field_from_prefix "partial" process_wall_p95_ms "$summary_path")"
  partial_submit_ms="$(field_from_prefix "partial" gpu_compositor_submit_max_ms "$summary_path")"
  partial_upload_fail="$(field_from_prefix "partial" gpu_upload_fail "$summary_path")"
  dirty_blocks_match="$(field_from_prefix "comparison" dirty_blocks_match "$summary_path")"
  rebuild_match="$(field_from_prefix "comparison" dirty_last_rebuild_subchunks_match "$summary_path")"

  require_eq "$label expected_edges" "$header_edges" "$edges"
  require_eq "$label expected_bounds" "$header_bounds" "$bounds"
  require_eq "$label x" "$header_x" "$x"
  require_eq "$label y" "$header_y" "$Y_VALUE"
  require_eq "$label z" "$header_z" "$z"
  require_numeric_ge "$label full_dirty_blocks" "$full_dirty_blocks" 1
  require_numeric_ge "$label full_rebuild_subchunks" "$full_rebuild_subchunks" 1
  require_eq "$label full_partial_subchunks" "$full_partial_subchunks" 0
  require_eq "$label full_saved_subchunks" "$full_saved_subchunks" 0
  require_eq "$label full_edge_neighbor_subchunks" "$full_edge_neighbor_subchunks" 0
  require_numeric_ge "$label full_collision" "$full_collision" 1
  require_eq "$label full_gpu_upload_fail" "$full_upload_fail" 0
  require_numeric_le "$label full_terrain_queue_max_ms" "$full_queue_ms" "$budget_ms"
  require_numeric_le "$label full_process_wall_p95_ms" "$full_process_ms" "$budget_ms"
  require_numeric_le "$label full_gpu_compositor_submit_max_ms" "$full_submit_ms" "$budget_ms"
  require_eq "$label dirty_blocks_match" "$dirty_blocks_match" 1
  require_eq "$label dirty_rebuild_subchunks_match" "$rebuild_match" 1
  require_numeric_ge "$label partial_dirty_blocks" "$partial_dirty_blocks" 1
  require_numeric_ge "$label partial_rebuild_subchunks" "$partial_rebuild_subchunks" 1
  require_numeric_ge "$label partial_edge_neighbor_subchunks" "$partial_edge_neighbor_subchunks" "$min_edge_subchunks"
  require_numeric_ge "$label partial_partial_subchunks" "$partial_partial_subchunks" 1
  require_numeric_ge "$label partial_saved_subchunks" "$partial_saved_subchunks" 1
  require_numeric_ge "$label partial_collision" "$partial_collision" 1
  require_eq "$label partial_gpu_upload_fail" "$partial_upload_fail" 0
  require_numeric_le "$label partial_terrain_queue_max_ms" "$partial_queue_ms" "$budget_ms"
  require_numeric_le "$label partial_process_wall_p95_ms" "$partial_process_ms" "$budget_ms"
  require_numeric_le "$label partial_gpu_compositor_submit_max_ms" "$partial_submit_ms" "$budget_ms"

  printf 'gpu_partial_dirty_edge_matrix_case label=%s kind=%s status=pass x=%s y=%s z=%s expected_edges=%s expected_bounds=%s full_dirty_blocks=%s partial_dirty_blocks=%s full_dirty_partial_subchunks=0 full_dirty_partial_saved_subchunks=0 full_dirty_edge_neighbor_subchunks=0 partial_dirty_edge_neighbor_subchunks=%s partial_dirty_partial_subchunks=%s partial_dirty_partial_saved_subchunks=%s full_terrain_queue_ms=%s partial_terrain_queue_ms=%s full_process_wall_p95_ms=%s partial_process_wall_p95_ms=%s full_gpu_compositor_submit_ms=%s partial_gpu_compositor_submit_ms=%s current_chunk_collision=%s gpu_upload_fail=0 summary=%s\n' \
    "$label" "$kind" "$x" "$Y_VALUE" "$z" "$edges" "$bounds" "$full_dirty_blocks" "$partial_dirty_blocks" "$partial_edge_neighbor_subchunks" "$partial_partial_subchunks" "$partial_saved_subchunks" "$full_queue_ms" "$partial_queue_ms" "$full_process_ms" "$partial_process_ms" "$full_submit_ms" "$partial_submit_ms" "$partial_collision" "$(relative_path "$summary_path")" >> "$CASES_PATH"
done

awk \
  -v target_fps="$TARGET_FPS" \
  -v budget_ms="$budget_ms" \
  -v cases_path="$(relative_path "$CASES_PATH")" '
  function field(key,  i, wanted) {
    wanted = key "="
    for (i = 1; i <= NF; i++) {
      if (index($i, wanted) == 1) {
        return substr($i, length(wanted) + 1)
      }
    }
    return ""
  }
  function max_update(value, target) {
    if (value ~ /^-?[0-9]+([.][0-9]+)?$/) {
      if (!(target in seen_max) || value + 0 > max_value[target]) {
        max_value[target] = value + 0
        seen_max[target] = 1
      }
    }
  }
  function min_update(value, target) {
    if (value ~ /^-?[0-9]+([.][0-9]+)?$/) {
      if (!(target in seen_min) || value + 0 < min_value[target]) {
        min_value[target] = value + 0
        seen_min[target] = 1
      }
    }
  }
  $1 == "gpu_partial_dirty_edge_matrix_case" {
    cases += 1
    if (field("status") == "pass") {
      pass_cases += 1
    }
    if (field("kind") == "single") {
      single_cases += 1
    } else if (field("kind") == "corner") {
      corner_cases += 1
    }
    max_update(field("full_terrain_queue_ms"), "terrain_queue")
    max_update(field("partial_terrain_queue_ms"), "terrain_queue")
    max_update(field("full_process_wall_p95_ms"), "process")
    max_update(field("partial_process_wall_p95_ms"), "process")
    max_update(field("full_gpu_compositor_submit_ms"), "submit")
    max_update(field("partial_gpu_compositor_submit_ms"), "submit")
    max_update(field("partial_dirty_edge_neighbor_subchunks"), "edge_neighbor")
    max_update(field("partial_dirty_partial_saved_subchunks"), "saved")
    min_update(field("partial_dirty_edge_neighbor_subchunks"), "edge_neighbor")
    min_update(field("partial_dirty_partial_saved_subchunks"), "saved")
  }
  END {
    status = "pass"
    reason = "ok"
    if (cases != 8 || pass_cases != 8 || single_cases != 4 || corner_cases != 4) {
      status = "fail"
      reason = "missing_case_coverage"
    }
    printf("gpu_terrain_partial_dirty_edge_matrix status=%s reason=%s case_count=%d pass_cases=%d single_edge_cases=%d corner_edge_cases=%d target_fps=%s budget_ms=%s min_partial_edge_neighbor_subchunks=%.3f max_partial_edge_neighbor_subchunks=%.3f min_partial_saved_subchunks=%.3f max_partial_saved_subchunks=%.3f max_terrain_queue_ms=%.3f max_process_wall_p95_ms=%.3f max_gpu_compositor_submit_ms=%.3f full_partial_disabled=1 gpu_upload_fail=0 scheduler_change_allowed=0 default_runtime_change_allowed=0 visible_quality_change_allowed=0 external_profile_status=pending_external_profiler requires_external_profiler_before_default=1 requires_mac_windows_validation=1 cases=%s\n", status, reason, cases, pass_cases, single_cases, corner_cases, target_fps, budget_ms, min_value["edge_neighbor"], max_value["edge_neighbor"], min_value["saved"], max_value["saved"], max_value["terrain_queue"], max_value["process"], max_value["submit"], cases_path)
    if (status != "pass") {
      exit 1
    }
  }
' "$CASES_PATH" > "$SUMMARY_PATH" || {
  cat "$SUMMARY_PATH" >&2 || true
  fail "partial dirty edge matrix failed"
}

cat "$SUMMARY_PATH"
