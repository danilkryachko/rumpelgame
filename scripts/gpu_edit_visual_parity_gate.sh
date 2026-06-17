#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/gpu_edit_visual_parity_gate_current"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

CASE_ROOT="${RUMPELMC_EDIT_VISUAL_PARITY_CASE_ROOT:-"$ROOT_DIR/logs/gpu_terrain_partial_dirty_edge_matrix_current/cases"}"
case "$CASE_ROOT" in
  /*) ;;
  *) CASE_ROOT="$ROOT_DIR/$CASE_ROOT" ;;
esac

CASE_LIST="${RUMPELMC_EDIT_VISUAL_PARITY_CASES:-"pos_x_single neg_x_single pos_z_single neg_z_single pos_x_pos_z_corner pos_x_neg_z_corner neg_x_pos_z_corner neg_x_neg_z_corner"}"
MAX_AVG_LUMA_DELTA="${RUMPELMC_EDIT_VISUAL_PARITY_MAX_AVG_LUMA_DELTA:-0.02}"
MAX_TERRAIN_LUMA_RANGE_DELTA="${RUMPELMC_EDIT_VISUAL_PARITY_MAX_TERRAIN_LUMA_RANGE_DELTA:-0.02}"
MAX_TERRAIN_SAMPLE_DELTA_PERCENT="${RUMPELMC_EDIT_VISUAL_PARITY_MAX_TERRAIN_SAMPLE_DELTA_PERCENT:-5}"
MIN_TERRAIN_SAMPLE_DELTA="${RUMPELMC_EDIT_VISUAL_PARITY_MIN_TERRAIN_SAMPLE_DELTA:-0}"
MAX_TERRAIN_COLOR_BUCKET_DELTA_PERCENT="${RUMPELMC_EDIT_VISUAL_PARITY_MAX_TERRAIN_COLOR_BUCKET_DELTA_PERCENT:-15}"
MIN_TERRAIN_COLOR_BUCKET_DELTA="${RUMPELMC_EDIT_VISUAL_PARITY_MIN_TERRAIN_COLOR_BUCKET_DELTA:-1}"
MIN_TERRAIN_SAMPLES="${RUMPELMC_EDIT_VISUAL_PARITY_MIN_TERRAIN_SAMPLES:-128}"
MIN_TERRAIN_COLOR_BUCKETS="${RUMPELMC_EDIT_VISUAL_PARITY_MIN_TERRAIN_COLOR_BUCKETS:-4}"
MIN_TERRAIN_CHROMA_SAMPLES="${RUMPELMC_EDIT_VISUAL_PARITY_MIN_TERRAIN_CHROMA_SAMPLES:-8}"
MIN_TERRAIN_LUMA_RANGE="${RUMPELMC_EDIT_VISUAL_PARITY_MIN_TERRAIN_LUMA_RANGE:-0.06}"
MIN_TERRAIN_REGION_SAMPLES="${RUMPELMC_EDIT_VISUAL_PARITY_MIN_TERRAIN_REGION_SAMPLES:-8}"

SUMMARY_PATH="$OUT_DIR/gpu-edit-visual-parity-summary.txt"
CASES_PATH="$OUT_DIR/gpu-edit-visual-parity-cases.txt"

mkdir -p "$OUT_DIR"

fail() {
  echo "gpu_edit_visual_parity_gate: $*" >&2
  exit 1
}

relative_path() {
  path="$1"
  case "$path" in
    "$ROOT_DIR"/*) printf '%s\n' "${path#$ROOT_DIR/}" ;;
    *) printf '%s\n' "$path" ;;
  esac
}

metric() {
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

require_file() {
  label="$1"
  path="$2"
  test -s "$path" || fail "missing $label $path"
}

require_text_eq() {
  path="$1"
  key="$2"
  expected="$3"
  label="$4"
  value="$(metric "$key" "$path")"
  test -n "$value" || fail "missing $label $key in $(relative_path "$path")"
  if [ "$value" != "$expected" ]; then
    fail "$label $key=$value, expected $expected in $(relative_path "$path")"
  fi
}

require_metric_eq() {
  path="$1"
  key="$2"
  expected="$3"
  label="$4"
  value="$(metric "$key" "$path")"
  test -n "$value" || fail "missing $label $key in $(relative_path "$path")"
  if [ "$value" != "$expected" ]; then
    fail "$label $key=$value, expected $expected in $(relative_path "$path")"
  fi
}

require_metric_ge() {
  path="$1"
  key="$2"
  minimum="$3"
  label="$4"
  value="$(metric "$key" "$path")"
  test -n "$value" || fail "missing $label $key in $(relative_path "$path")"
  awk -v value="$value" -v minimum="$minimum" -v key="$key" -v label="$label" -v path="$(relative_path "$path")" '
    BEGIN {
      if (value + 0 < minimum + 0) {
        printf("gpu_edit_visual_parity_gate: %s %s=%s below %s in %s\n", label, key, value, minimum, path) > "/dev/stderr"
        exit 1
      }
    }
  '
}

float_delta() {
  left="$1"
  right="$2"
  awk -v left="$left" -v right="$right" '
    BEGIN {
      delta = left - right
      if (delta < 0) {
        delta = -delta
      }
      printf("%.4f\n", delta)
    }
  '
}

int_delta() {
  left="$1"
  right="$2"
  delta=$((left - right))
  if [ "$delta" -lt 0 ]; then
    delta=$((-delta))
  fi
  printf '%s\n' "$delta"
}

int_delta_percent() {
  left="$1"
  right="$2"
  awk -v left="$left" -v right="$right" '
    BEGIN {
      delta = left - right
      if (delta < 0) {
        delta = -delta
      }
      base = left
      if (right > base) {
        base = right
      }
      if (base > 0) {
        printf("%.3f\n", delta * 100.0 / base)
      } else {
        printf("0.000\n")
      }
    }
  '
}

require_float_delta_le() {
  left="$1"
  right="$2"
  max_delta="$3"
  label="$4"
  awk -v left="$left" -v right="$right" -v max_delta="$max_delta" -v label="$label" '
    BEGIN {
      delta = left - right
      if (delta < 0) {
        delta = -delta
      }
      if (delta > max_delta) {
        printf("gpu_edit_visual_parity_gate: %s delta %.4f exceeds %.4f (left=%.4f right=%.4f)\n", label, delta, max_delta, left, right) > "/dev/stderr"
        exit 1
      }
    }
  '
}

require_int_delta_percent_le() {
  left="$1"
  right="$2"
  percent="$3"
  min_delta="$4"
  label="$5"
  awk -v left="$left" -v right="$right" -v percent="$percent" -v min_delta="$min_delta" -v label="$label" '
    BEGIN {
      delta = left - right
      if (delta < 0) {
        delta = -delta
      }
      base = left
      if (right > base) {
        base = right
      }
      allowed = base * percent / 100.0
      if (allowed < min_delta) {
        allowed = min_delta
      }
      if (delta > allowed) {
        printf("gpu_edit_visual_parity_gate: %s delta %d exceeds %.3f (left=%d right=%d)\n", label, delta, allowed, left, right) > "/dev/stderr"
        exit 1
      }
    }
  '
}

validate_marker() {
  marker="$1"
  label="$2"
  screenshot="${marker%.txt}"

  require_file "$label marker" "$marker"
  require_file "$label screenshot" "$screenshot"
  grep -q 'Visual smoke screenshot saved' "$marker" || fail "missing screenshot marker text in $(relative_path "$marker")"

  require_text_eq "$marker" "pose" "default" "$label"
  require_text_eq "$marker" "motion" "chunk_walk" "$label"
  require_text_eq "$marker" "block_edit" "toggle" "$label"
  require_text_eq "$marker" "shadow_path" "godot_proxy" "$label"
  require_text_eq "$marker" "shadow_mode" "conservative" "$label"
  require_text_eq "$marker" "shadow_mesh" "compact" "$label"

  require_metric_eq "$marker" "smoke_err" 0 "$label"
  require_metric_eq "$marker" "block_edit_dirty_observed" 1 "$label"
  require_metric_eq "$marker" "ground_misses" 0 "$label"
  require_metric_eq "$marker" "gpu_upload_fail" 0 "$label"
  require_metric_ge "$marker" "gpu_frames" 1 "$label"
  require_metric_ge "$marker" "gpu_subchunks" 1 "$label"
  require_metric_ge "$marker" "gpu_faces" 1 "$label"
  require_metric_ge "$marker" "current_chunk_loaded" 1 "$label"
  require_metric_ge "$marker" "current_chunk_submeshes" 1 "$label"
  require_metric_ge "$marker" "current_chunk_collision" 1 "$label"
  require_metric_ge "$marker" "terrain_samples" "$MIN_TERRAIN_SAMPLES" "$label"
  require_metric_ge "$marker" "terrain_mid_samples" "$MIN_TERRAIN_REGION_SAMPLES" "$label"
  require_metric_ge "$marker" "terrain_bottom_samples" "$MIN_TERRAIN_REGION_SAMPLES" "$label"
  require_metric_ge "$marker" "terrain_left_samples" "$MIN_TERRAIN_REGION_SAMPLES" "$label"
  require_metric_ge "$marker" "terrain_right_samples" "$MIN_TERRAIN_REGION_SAMPLES" "$label"
  require_metric_ge "$marker" "terrain_color_buckets" "$MIN_TERRAIN_COLOR_BUCKETS" "$label"
  require_metric_ge "$marker" "terrain_chroma_samples" "$MIN_TERRAIN_CHROMA_SAMPLES" "$label"
  require_metric_ge "$marker" "terrain_luma_range" "$MIN_TERRAIN_LUMA_RANGE" "$label"
}

validate_block_summary() {
  summary="$1"
  label="$2"
  mode="$3"

  require_file "$label block edit summary" "$summary"
  require_text_eq "$summary" "action" "toggle" "$label"
  require_text_eq "$summary" "motion" "chunk_walk" "$label"
  require_metric_eq "$summary" "block_edit_dirty_observed" 1 "$label"
  require_metric_eq "$summary" "gpu_upload_fail" 0 "$label"
  if [ "$mode" = "full" ]; then
    require_metric_eq "$summary" "dirty_edge_neighbor_subchunks" 0 "$label"
    require_metric_eq "$summary" "dirty_partial_subchunks" 0 "$label"
    require_metric_eq "$summary" "dirty_partial_saved_subchunks" 0 "$label"
  else
    require_metric_ge "$summary" "dirty_edge_neighbor_subchunks" 1 "$label"
    require_metric_ge "$summary" "dirty_partial_subchunks" 1 "$label"
    require_metric_ge "$summary" "dirty_partial_saved_subchunks" 1 "$label"
  fi
}

append_case() {
  case_name="$1"
  full_marker="$CASE_ROOT/$case_name/full/gpu-terrain-movement-stress.png.txt"
  partial_marker="$CASE_ROOT/$case_name/partial/gpu-terrain-movement-stress.png.txt"
  full_summary="$CASE_ROOT/$case_name/full/block-edit-stress-summary.txt"
  partial_summary="$CASE_ROOT/$case_name/partial/block-edit-stress-summary.txt"

  validate_marker "$full_marker" "$case_name full"
  validate_marker "$partial_marker" "$case_name partial"
  validate_block_summary "$full_summary" "$case_name full" "full"
  validate_block_summary "$partial_summary" "$case_name partial" "partial"

  full_edges="$(metric "expected_edges" "$full_summary")"
  partial_edges="$(metric "expected_edges" "$partial_summary")"
  test -n "$full_edges" || fail "missing full expected_edges for $case_name"
  test -n "$partial_edges" || fail "missing partial expected_edges for $case_name"
  if [ "$full_edges" != "$partial_edges" ]; then
    fail "$case_name expected_edges mismatch full=$full_edges partial=$partial_edges"
  fi

  full_bounds="$(metric "expected_bounds" "$full_summary")"
  partial_bounds="$(metric "expected_bounds" "$partial_summary")"
  test -n "$full_bounds" || fail "missing full expected_bounds for $case_name"
  test -n "$partial_bounds" || fail "missing partial expected_bounds for $case_name"
  if [ "$full_bounds" != "$partial_bounds" ]; then
    fail "$case_name expected_bounds mismatch full=$full_bounds partial=$partial_bounds"
  fi

  full_avg_luma="$(metric "avg_luma" "$full_marker")"
  partial_avg_luma="$(metric "avg_luma" "$partial_marker")"
  require_float_delta_le "$full_avg_luma" "$partial_avg_luma" "$MAX_AVG_LUMA_DELTA" "$case_name avg_luma"
  avg_luma_delta="$(float_delta "$full_avg_luma" "$partial_avg_luma")"

  full_luma_range="$(metric "terrain_luma_range" "$full_marker")"
  partial_luma_range="$(metric "terrain_luma_range" "$partial_marker")"
  require_float_delta_le "$full_luma_range" "$partial_luma_range" "$MAX_TERRAIN_LUMA_RANGE_DELTA" "$case_name terrain_luma_range"
  terrain_luma_range_delta="$(float_delta "$full_luma_range" "$partial_luma_range")"

  full_terrain_samples="$(metric "terrain_samples" "$full_marker")"
  partial_terrain_samples="$(metric "terrain_samples" "$partial_marker")"
  require_int_delta_percent_le "$full_terrain_samples" "$partial_terrain_samples" "$MAX_TERRAIN_SAMPLE_DELTA_PERCENT" "$MIN_TERRAIN_SAMPLE_DELTA" "$case_name terrain_samples"
  terrain_samples_delta="$(int_delta "$full_terrain_samples" "$partial_terrain_samples")"
  terrain_samples_delta_percent="$(int_delta_percent "$full_terrain_samples" "$partial_terrain_samples")"

  full_color_buckets="$(metric "terrain_color_buckets" "$full_marker")"
  partial_color_buckets="$(metric "terrain_color_buckets" "$partial_marker")"
  require_int_delta_percent_le "$full_color_buckets" "$partial_color_buckets" "$MAX_TERRAIN_COLOR_BUCKET_DELTA_PERCENT" "$MIN_TERRAIN_COLOR_BUCKET_DELTA" "$case_name terrain_color_buckets"
  terrain_color_bucket_delta="$(int_delta "$full_color_buckets" "$partial_color_buckets")"
  terrain_color_bucket_delta_percent="$(int_delta_percent "$full_color_buckets" "$partial_color_buckets")"

  full_chroma_samples="$(metric "terrain_chroma_samples" "$full_marker")"
  partial_chroma_samples="$(metric "terrain_chroma_samples" "$partial_marker")"
  require_int_delta_percent_le "$full_chroma_samples" "$partial_chroma_samples" "$MAX_TERRAIN_SAMPLE_DELTA_PERCENT" "$MIN_TERRAIN_SAMPLE_DELTA" "$case_name terrain_chroma_samples"
  terrain_chroma_samples_delta="$(int_delta "$full_chroma_samples" "$partial_chroma_samples")"
  terrain_chroma_samples_delta_percent="$(int_delta_percent "$full_chroma_samples" "$partial_chroma_samples")"

  full_submeshes="$(metric "current_chunk_submeshes" "$full_marker")"
  partial_submeshes="$(metric "current_chunk_submeshes" "$partial_marker")"
  if [ "$full_submeshes" != "$partial_submeshes" ]; then
    fail "$case_name current_chunk_submeshes mismatch full=$full_submeshes partial=$partial_submeshes"
  fi

  full_collision="$(metric "current_chunk_collision" "$full_marker")"
  partial_collision="$(metric "current_chunk_collision" "$partial_marker")"
  if [ "$full_collision" != "$partial_collision" ]; then
    fail "$case_name current_chunk_collision mismatch full=$full_collision partial=$partial_collision"
  fi

  full_dirty_edge_neighbor_subchunks="$(metric "dirty_edge_neighbor_subchunks" "$full_summary")"
  partial_dirty_edge_neighbor_subchunks="$(metric "dirty_edge_neighbor_subchunks" "$partial_summary")"
  full_dirty_partial_subchunks="$(metric "dirty_partial_subchunks" "$full_summary")"
  partial_dirty_partial_subchunks="$(metric "dirty_partial_subchunks" "$partial_summary")"
  full_dirty_partial_saved_subchunks="$(metric "dirty_partial_saved_subchunks" "$full_summary")"
  partial_dirty_partial_saved_subchunks="$(metric "dirty_partial_saved_subchunks" "$partial_summary")"

  printf 'case=%s status=pass full_marker=%s partial_marker=%s expected_edges=%s expected_bounds=%s avg_luma=%s/%s avg_luma_delta=%s terrain_luma_range=%s/%s terrain_luma_range_delta=%s terrain_samples=%s/%s terrain_samples_delta=%s terrain_samples_delta_percent=%s terrain_color_buckets=%s/%s terrain_color_bucket_delta=%s terrain_color_bucket_delta_percent=%s terrain_chroma_samples=%s/%s terrain_chroma_samples_delta=%s terrain_chroma_samples_delta_percent=%s current_chunk_submeshes=%s/%s current_chunk_collision=%s/%s full_dirty_edge_neighbor_subchunks=%s partial_dirty_edge_neighbor_subchunks=%s full_dirty_partial_subchunks=%s partial_dirty_partial_subchunks=%s full_dirty_partial_saved_subchunks=%s partial_dirty_partial_saved_subchunks=%s gpu_upload_fail=0 ground_misses=0 smoke_err=0 block_edit_dirty_observed=1\n' \
    "$case_name" \
    "$(relative_path "$full_marker")" \
    "$(relative_path "$partial_marker")" \
    "$full_edges" \
    "$full_bounds" \
    "$full_avg_luma" \
    "$partial_avg_luma" \
    "$avg_luma_delta" \
    "$full_luma_range" \
    "$partial_luma_range" \
    "$terrain_luma_range_delta" \
    "$full_terrain_samples" \
    "$partial_terrain_samples" \
    "$terrain_samples_delta" \
    "$terrain_samples_delta_percent" \
    "$full_color_buckets" \
    "$partial_color_buckets" \
    "$terrain_color_bucket_delta" \
    "$terrain_color_bucket_delta_percent" \
    "$full_chroma_samples" \
    "$partial_chroma_samples" \
    "$terrain_chroma_samples_delta" \
    "$terrain_chroma_samples_delta_percent" \
    "$full_submeshes" \
    "$partial_submeshes" \
    "$full_collision" \
    "$partial_collision" \
    "$full_dirty_edge_neighbor_subchunks" \
    "$partial_dirty_edge_neighbor_subchunks" \
    "$full_dirty_partial_subchunks" \
    "$partial_dirty_partial_subchunks" \
    "$full_dirty_partial_saved_subchunks" \
    "$partial_dirty_partial_saved_subchunks" \
    >> "$CASES_PATH"
}

max_case_metric() {
  key="$1"
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
          if (match(raw, /^-?[0-9]+([.][0-9]+)?/)) {
            value = substr(raw, RSTART, RLENGTH) + 0.0
            if (!found || value > max_value) {
              max_value = value
              max_text = substr(raw, RSTART, RLENGTH)
              found = 1
            }
          }
        }
      }
    }
    END {
      print max_text
    }
  ' "$CASES_PATH"
}

case_count_for_summary() {
  awk 'BEGIN { count = 0 } /^case=/ { count++ } END { print count }' "$CASES_PATH"
}

: > "$CASES_PATH"
for case_name in $CASE_LIST; do
  append_case "$case_name"
done

case_count="$(case_count_for_summary)"
marker_count=$((case_count * 2))

{
  printf 'gpu_edit_visual_parity_gate status=pass reason=ok case_count=%s pass_cases=%s fail_cases=0 pair_count=%s marker_count=%s case_root=%s cases=%s max_avg_luma_delta=%s max_terrain_luma_range_delta=%s max_terrain_samples_delta=%s max_terrain_samples_delta_percent=%s max_terrain_color_bucket_delta=%s max_terrain_color_bucket_delta_percent=%s max_terrain_chroma_samples_delta=%s max_terrain_chroma_samples_delta_percent=%s max_full_dirty_edge_neighbor_subchunks=%s max_partial_dirty_edge_neighbor_subchunks=%s max_full_dirty_partial_subchunks=%s max_partial_dirty_partial_subchunks=%s max_full_dirty_partial_saved_subchunks=%s max_partial_dirty_partial_saved_subchunks=%s smoke_err=0 gpu_upload_fail=0 ground_misses=0 block_edit_dirty_observed_failures=0 visual_delta_failures=0 default_runtime_change_allowed=0 visible_quality_change_allowed=0 requires_external_profiler_before_default=1 requires_mac_windows_validation=1 external_profile_status=pending_external_profiler thresholds=max_avg_luma_delta:%s,max_terrain_luma_range_delta:%s,max_terrain_sample_delta_percent:%s,min_terrain_sample_delta:%s,max_terrain_color_bucket_delta_percent:%s,min_terrain_color_bucket_delta:%s,min_terrain_samples:%s,min_terrain_color_buckets:%s,min_terrain_chroma_samples:%s,min_terrain_luma_range:%s,min_terrain_region_samples:%s cases_path=%s\n' \
    "$case_count" \
    "$case_count" \
    "$case_count" \
    "$marker_count" \
    "$(relative_path "$CASE_ROOT")" \
    "$(printf '%s' "$CASE_LIST" | tr ' ' ',')" \
    "$(max_case_metric avg_luma_delta)" \
    "$(max_case_metric terrain_luma_range_delta)" \
    "$(max_case_metric terrain_samples_delta)" \
    "$(max_case_metric terrain_samples_delta_percent)" \
    "$(max_case_metric terrain_color_bucket_delta)" \
    "$(max_case_metric terrain_color_bucket_delta_percent)" \
    "$(max_case_metric terrain_chroma_samples_delta)" \
    "$(max_case_metric terrain_chroma_samples_delta_percent)" \
    "$(max_case_metric full_dirty_edge_neighbor_subchunks)" \
    "$(max_case_metric partial_dirty_edge_neighbor_subchunks)" \
    "$(max_case_metric full_dirty_partial_subchunks)" \
    "$(max_case_metric partial_dirty_partial_subchunks)" \
    "$(max_case_metric full_dirty_partial_saved_subchunks)" \
    "$(max_case_metric partial_dirty_partial_saved_subchunks)" \
    "$MAX_AVG_LUMA_DELTA" \
    "$MAX_TERRAIN_LUMA_RANGE_DELTA" \
    "$MAX_TERRAIN_SAMPLE_DELTA_PERCENT" \
    "$MIN_TERRAIN_SAMPLE_DELTA" \
    "$MAX_TERRAIN_COLOR_BUCKET_DELTA_PERCENT" \
    "$MIN_TERRAIN_COLOR_BUCKET_DELTA" \
    "$MIN_TERRAIN_SAMPLES" \
    "$MIN_TERRAIN_COLOR_BUCKETS" \
    "$MIN_TERRAIN_CHROMA_SAMPLES" \
    "$MIN_TERRAIN_LUMA_RANGE" \
    "$MIN_TERRAIN_REGION_SAMPLES" \
    "$(relative_path "$CASES_PATH")"
} > "$SUMMARY_PATH"

cat "$SUMMARY_PATH"
