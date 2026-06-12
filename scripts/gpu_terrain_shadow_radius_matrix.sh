#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
CAPTURE="${RUMPELMC_SHADOW_RADIUS_MATRIX_CAPTURE:-0}"
RADII="${RUMPELMC_SHADOW_RADIUS_MATRIX_RADII:-scene 1}"
OUT_DIR="${1:-"$ROOT_DIR/logs/gpu_shadow_radius_matrix"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

mkdir -p "$OUT_DIR"

fail() {
  echo "gpu_terrain_shadow_radius_matrix: $*" >&2
  exit 1
}

relative_path() {
  path="$1"
  case "$path" in
    "$ROOT_DIR"/*) printf '%s\n' "${path#$ROOT_DIR/}" ;;
    *) printf '%s\n' "$path" ;;
  esac
}

validate_radius() {
  radius="$1"
  case "$radius" in
    scene) return 0 ;;
    ''|*[!0-9]*)
      fail "radius entries must be 'scene' or positive integers: $radius"
      ;;
  esac
  if [ "$radius" -lt 1 ]; then
    fail "radius 0 is reserved for the compact proxy benchmark shadow-disabled control"
  fi
}

radius_case_label() {
  radius="$1"
  if [ "$radius" = "scene" ]; then
    printf '%s\n' "scene"
  else
    printf 'radius-%s\n' "$radius"
  fi
}

summary_token() {
  key="$1"
  summary_path="$2"
  awk -v key="$key" '
    BEGIN { prefix = key "=" }
    {
      for (i = 1; i <= NF; i++) {
        if (index($i, prefix) == 1) {
          print substr($i, length(prefix) + 1)
          exit
        }
      }
    }
  ' "$summary_path"
}

summary_row_token() {
  label="$1"
  key="$2"
  summary_path="$3"
  awk -v label="$label" -v key="$key" '
    BEGIN { prefix = key "=" }
    $1 == label {
      for (i = 1; i <= NF; i++) {
        if (index($i, prefix) == 1) {
          print substr($i, length(prefix) + 1)
          exit
        }
      }
    }
  ' "$summary_path"
}

value_or_na() {
  value="$1"
  if [ -n "$value" ]; then
    printf '%s\n' "$value"
  else
    printf '%s\n' "n/a"
  fi
}

matrix_line() {
  radius="$1"
  case_dir="$2"
  summary_path="$case_dir/compact-proxy-benchmark-summary.txt"

  test -s "$summary_path" || fail "missing summary $summary_path"

  child_capture="$(value_or_na "$(summary_token "capture" "$summary_path")")"
  child_reuse="$(value_or_na "$(summary_token "reuse_server" "$summary_path")")"
  child_radius="$(value_or_na "$(summary_token "shadow_radius_override" "$summary_path")")"
  full_cpu_proxy="$(value_or_na "$(summary_row_token "full" "cpu_proxy" "$summary_path")")"
  full_shadow_only="$(value_or_na "$(summary_row_token "full" "shadow_only" "$summary_path")")"
  full_mesh_max_ms="$(value_or_na "$(summary_row_token "full" "mesh_max_ms" "$summary_path")")"
  full_avg_luma="$(value_or_na "$(summary_row_token "full" "avg_luma" "$summary_path")")"
  full_terrain_samples="$(value_or_na "$(summary_row_token "full" "terrain_samples" "$summary_path")")"
  compact_cpu_proxy="$(value_or_na "$(summary_row_token "compact" "cpu_proxy" "$summary_path")")"
  compact_shadow_only="$(value_or_na "$(summary_row_token "compact" "shadow_only" "$summary_path")")"
  compact_shadow_proxy="$(value_or_na "$(summary_row_token "compact" "compact_shadow_proxy" "$summary_path")")"
  compact_normals_saved="$(value_or_na "$(summary_row_token "compact" "shadow_normals_saved" "$summary_path")")"
  compact_mesh_max_ms="$(value_or_na "$(summary_row_token "compact" "mesh_max_ms" "$summary_path")")"
  compact_coll_avg_ms="$(value_or_na "$(summary_row_token "compact" "coll_avg_ms" "$summary_path")")"
  compact_gpu_frames="$(value_or_na "$(summary_row_token "compact" "gpu_frames" "$summary_path")")"
  compact_avg_luma="$(value_or_na "$(summary_row_token "compact" "avg_luma" "$summary_path")")"
  compact_terrain_samples="$(value_or_na "$(summary_row_token "compact" "terrain_samples" "$summary_path")")"
  normal_delta="$(value_or_na "$(summary_token "shadow_normal_total_delta" "$summary_path")")"
  normal_status="$(value_or_na "$(summary_token "shadow_normal_total_status" "$summary_path")")"
  shadow_disabled_collision_saved="$(value_or_na "$(summary_token "shadow_disabled_collision_normal_payload_saved" "$summary_path")")"
  collision_only_collision_saved="$(value_or_na "$(summary_token "collision_only_collision_normal_payload_saved" "$summary_path")")"

  printf 'radius=%s status=pass child_capture=%s child_reuse_server=%s child_shadow_radius_override=%s full_cpu_proxy=%s full_shadow_only=%s full_mesh_max_ms=%s full_avg_luma=%s full_terrain_samples=%s compact_cpu_proxy=%s compact_shadow_only=%s compact_shadow_proxy=%s compact_shadow_normals_saved=%s compact_mesh_max_ms=%s compact_coll_avg_ms=%s compact_gpu_frames=%s compact_avg_luma=%s compact_terrain_samples=%s shadow_normal_total_delta=%s shadow_normal_total_status=%s shadow_disabled_collision_normals_saved=%s collision_only_collision_normals_saved=%s artifact=%s\n' \
    "$radius" \
    "$child_capture" \
    "$child_reuse" \
    "$child_radius" \
    "$full_cpu_proxy" \
    "$full_shadow_only" \
    "$full_mesh_max_ms" \
    "$full_avg_luma" \
    "$full_terrain_samples" \
    "$compact_cpu_proxy" \
    "$compact_shadow_only" \
    "$compact_shadow_proxy" \
    "$compact_normals_saved" \
    "$compact_mesh_max_ms" \
    "$compact_coll_avg_ms" \
    "$compact_gpu_frames" \
    "$compact_avg_luma" \
    "$compact_terrain_samples" \
    "$normal_delta" \
    "$normal_status" \
    "$shadow_disabled_collision_saved" \
    "$collision_only_collision_saved" \
    "$(relative_path "$case_dir")"
}

case "$CAPTURE" in
  0|1) ;;
  *) fail "RUMPELMC_SHADOW_RADIUS_MATRIX_CAPTURE must be 0 or 1" ;;
esac
test -n "$RADII" || fail "RUMPELMC_SHADOW_RADIUS_MATRIX_RADII must not be empty"

summary_path="$OUT_DIR/shadow-radius-matrix-summary.txt"
tmp_summary_path="$summary_path.tmp"
{
  printf 'GPU terrain shadow radius matrix capture=%s radii="%s"\n' "$CAPTURE" "$RADII"
  printf 'compact_proxy_benchmark=scripts/gpu_terrain_compact_proxy_benchmark.sh\n'
} > "$tmp_summary_path"

for radius in $RADII; do
  validate_radius "$radius"
  case_label="$(radius_case_label "$radius")"
  case_dir="$OUT_DIR/$case_label"
  if [ "$CAPTURE" = "1" ]; then
    rm -rf "$case_dir"
  elif [ ! -d "$case_dir" ]; then
    fail "missing report-mode case dir $case_dir; run with RUMPELMC_SHADOW_RADIUS_MATRIX_CAPTURE=1 first"
  fi
  mkdir -p "$case_dir"
  echo "==> GPU terrain shadow radius matrix: radius=$radius artifact=$(relative_path "$case_dir")"
  run_status=0
  if [ "$radius" = "scene" ]; then
    RUMPELMC_COMPACT_PROXY_BENCH_CAPTURE="$CAPTURE" \
      RUMPELMC_COMPACT_PROXY_BENCH_SHADOW_RADIUS= \
      sh "$ROOT_DIR/scripts/gpu_terrain_compact_proxy_benchmark.sh" "$case_dir" > "$case_dir/run.log" 2>&1 || run_status=$?
  else
    RUMPELMC_COMPACT_PROXY_BENCH_CAPTURE="$CAPTURE" \
      RUMPELMC_COMPACT_PROXY_BENCH_SHADOW_RADIUS="$radius" \
      sh "$ROOT_DIR/scripts/gpu_terrain_compact_proxy_benchmark.sh" "$case_dir" > "$case_dir/run.log" 2>&1 || run_status=$?
  fi
  if [ "$run_status" -ne 0 ]; then
    fail "compact proxy benchmark failed for radius=$radius; see $(relative_path "$case_dir/run.log")"
  fi
  matrix_line "$radius" "$case_dir" >> "$tmp_summary_path"
done

mv "$tmp_summary_path" "$summary_path"
echo
cat "$summary_path"
