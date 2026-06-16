#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/dirty_update_high_count_runtime"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

SUMMARY_PATH="$OUT_DIR/dirty-update-high-count-runtime-summary.txt"
PERSISTED_SMOKE_SCRIPT="${RUMPELMC_DIRTY_HIGH_COUNT_PERSISTED_SCRIPT:-"$ROOT_DIR/scripts/dirty_update_persisted_reload_runtime_smoke.sh"}"
PERSISTED_SUMMARY="${RUMPELMC_DIRTY_HIGH_COUNT_PERSISTED_SUMMARY:-"$ROOT_DIR/logs/dirty_update_persisted_reload_runtime_high_count_current/dirty-update-persisted-reload-runtime-summary.txt"}"
MASS_RUNTIME_SUMMARY="${RUMPELMC_DIRTY_HIGH_COUNT_MASS_RUNTIME_SUMMARY:-"$ROOT_DIR/logs/dirty_update_mass_edit_runtime_current/dirty-update-mass-edit-runtime-summary.txt"}"
CROSS_MASS_RUNTIME_SUMMARY="${RUMPELMC_DIRTY_HIGH_COUNT_CROSS_MASS_RUNTIME_SUMMARY:-"$ROOT_DIR/logs/dirty_update_cross_chunk_mass_runtime_current/dirty-update-cross-chunk-mass-runtime-summary.txt"}"
RUN_PERSISTED_SMOKE="${RUMPELMC_DIRTY_HIGH_COUNT_RUN_PERSISTED_SMOKE:-0}"
SOAK_CYCLES="${RUMPELMC_DIRTY_HIGH_COUNT_SOAK_CYCLES:-5}"
MIN_SOAK_CYCLES="${RUMPELMC_DIRTY_HIGH_COUNT_MIN_SOAK_CYCLES:-5}"
MIN_FINAL_VERIFY_COUNT="${RUMPELMC_DIRTY_HIGH_COUNT_MIN_FINAL_VERIFY_COUNT:-20}"
MIN_PERSISTED_DIRTY_BLOCKS="${RUMPELMC_DIRTY_HIGH_COUNT_MIN_PERSISTED_DIRTY_BLOCKS:-40}"
MIN_PERSISTED_CHUNK_REPLACE="${RUMPELMC_DIRTY_HIGH_COUNT_MIN_PERSISTED_CHUNK_REPLACE:-40}"
MIN_PERSISTED_EDGE_NEIGHBOR_SUBCHUNKS="${RUMPELMC_DIRTY_HIGH_COUNT_MIN_PERSISTED_EDGE_NEIGHBOR_SUBCHUNKS:-80}"
MIN_PERSISTED_PARTIAL_SUBCHUNKS="${RUMPELMC_DIRTY_HIGH_COUNT_MIN_PERSISTED_PARTIAL_SUBCHUNKS:-60}"
MIN_PERSISTED_PARTIAL_SAVED_SUBCHUNKS="${RUMPELMC_DIRTY_HIGH_COUNT_MIN_PERSISTED_PARTIAL_SAVED_SUBCHUNKS:-60}"
MIN_MATRIX_DIRTY_BLOCKS="${RUMPELMC_DIRTY_HIGH_COUNT_MIN_MATRIX_DIRTY_BLOCKS:-60}"
MIN_MATRIX_CHUNK_REPLACE="${RUMPELMC_DIRTY_HIGH_COUNT_MIN_MATRIX_CHUNK_REPLACE:-60}"
MIN_MATRIX_EDIT_COUNT="${RUMPELMC_DIRTY_HIGH_COUNT_MIN_MATRIX_EDIT_COUNT:-24}"
MAX_TERRAIN_QUEUE_MS="${RUMPELMC_DIRTY_HIGH_COUNT_MAX_TERRAIN_QUEUE_MS:-8.000}"
MAX_GPU_COMPOSITOR_SUBMIT_MS="${RUMPELMC_DIRTY_HIGH_COUNT_MAX_GPU_COMPOSITOR_SUBMIT_MS:-1.000}"
MAX_PROCESS_WALL_P95_MS="${RUMPELMC_DIRTY_HIGH_COUNT_MAX_PROCESS_WALL_P95_MS:-1.000}"

mkdir -p "$OUT_DIR"

fail() {
  echo "dirty_update_high_count_runtime_gate: $*" >&2
  exit 1
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

require_file() {
  path="$1"
  test -s "$path" || fail "missing required file $path"
}

require_int_ge() {
  name="$1"
  value="$2"
  min_value="$3"
  case "$value" in
    ''|*[!0-9]*) fail "$name must be an integer, got $value" ;;
  esac
  if [ "$value" -lt "$min_value" ]; then
    fail "$name=$value is below $min_value"
  fi
}

require_float_le() {
  name="$1"
  value="$2"
  max_value="$3"
  test -n "$value" || fail "missing $name"
  awk -v name="$name" -v value="$value" -v max_value="$max_value" '
    BEGIN {
      if (value > max_value) {
        printf("dirty_update_high_count_runtime_gate: %s %.3f exceeds %.3f\n", name, value, max_value) > "/dev/stderr"
        exit 1
      }
    }
  '
}

if [ "$RUN_PERSISTED_SMOKE" = "1" ]; then
  require_file "$PERSISTED_SMOKE_SCRIPT"
  persisted_dir="$(dirname -- "$PERSISTED_SUMMARY")"
  mkdir -p "$persisted_dir"
  if ! RUMPELMC_DIRTY_PERSISTED_RUNTIME_ARTIFACT_DIR="$ROOT_DIR/logs/dirty_update_persisted_reload_runtime_high_count_artifacts" \
    RUMPELMC_DIRTY_PERSISTED_RUNTIME_SOAK_CYCLES="$SOAK_CYCLES" \
    RUMPELMC_DIRTY_PERSISTED_RUNTIME_MIN_SOAK_CYCLES="$MIN_SOAK_CYCLES" \
    sh "$PERSISTED_SMOKE_SCRIPT" "$persisted_dir" > "$OUT_DIR/persisted-high-count-run.log" 2>&1; then
    cat "$OUT_DIR/persisted-high-count-run.log" >&2 || true
    fail "high-count persisted dirty runtime smoke failed"
  fi
fi

for path in "$PERSISTED_SUMMARY" "$MASS_RUNTIME_SUMMARY" "$CROSS_MASS_RUNTIME_SUMMARY"; do
  require_file "$path"
done

proto_diff_count="$(git -C "$ROOT_DIR" diff --name-only -- api/schema/packets.proto server/pkg/api/packets.pb.go | awk 'END { print NR + 0 }')"

persisted_status="$(field_metric status "$PERSISTED_SUMMARY")"
persisted_dirty="$(field_metric runtime_persisted_dirty "$PERSISTED_SUMMARY")"
persisted_soak_status="$(field_metric soak_status "$PERSISTED_SUMMARY")"
persisted_soak_cycles="$(field_metric soak_cycles "$PERSISTED_SUMMARY")"
persisted_reload_cycles="$(field_metric reload_cycles "$PERSISTED_SUMMARY")"
persisted_final_verify_count="$(field_metric final_verify_count "$PERSISTED_SUMMARY")"
persisted_edit_count="$(field_metric mass_edit_count "$PERSISTED_SUMMARY")"
persisted_protocol_change="$(field_metric active_protocol_change "$PERSISTED_SUMMARY")"
persisted_dirty_blocks="$(field_metric soak_dirty_blocks "$PERSISTED_SUMMARY")"
persisted_chunk_replace="$(field_metric soak_chunk_replace "$PERSISTED_SUMMARY")"
persisted_edge_neighbor_subchunks="$(field_metric soak_edge_neighbor_subchunks "$PERSISTED_SUMMARY")"
persisted_partial_subchunks="$(field_metric soak_partial_subchunks "$PERSISTED_SUMMARY")"
persisted_partial_saved_subchunks="$(field_metric soak_partial_saved_subchunks "$PERSISTED_SUMMARY")"
persisted_terrain_queue_max="$(field_metric terrain_queue_max_ms "$PERSISTED_SUMMARY")"
persisted_gpu_submit_max="$(field_metric gpu_compositor_submit_max_ms "$PERSISTED_SUMMARY")"
persisted_process_wall_p95="$(field_metric process_wall_p95_ms "$PERSISTED_SUMMARY")"
persisted_gpu_upload_fail="$(field_metric gpu_upload_fail "$PERSISTED_SUMMARY")"

mass_status="$(field_metric status "$MASS_RUNTIME_SUMMARY")"
mass_runtime="$(field_metric runtime_mass_edit "$MASS_RUNTIME_SUMMARY")"
mass_budget="$(field_metric runtime_mass_budget "$MASS_RUNTIME_SUMMARY")"
mass_edit_count="$(field_metric mass_edit_count "$MASS_RUNTIME_SUMMARY")"
mass_dirty_blocks="$(field_metric dirty_blocks "$MASS_RUNTIME_SUMMARY")"
mass_chunk_replace="$(field_metric chunk_replace "$MASS_RUNTIME_SUMMARY")"
mass_protocol_change="$(field_metric active_protocol_change "$MASS_RUNTIME_SUMMARY")"

cross_status="$(field_metric status "$CROSS_MASS_RUNTIME_SUMMARY")"
cross_runtime="$(field_metric runtime_cross_chunk_mass_edit "$CROSS_MASS_RUNTIME_SUMMARY")"
cross_budget="$(field_metric cross_chunk_mass_budget "$CROSS_MASS_RUNTIME_SUMMARY")"
cross_chunk_count="$(field_metric cross_chunk_count "$CROSS_MASS_RUNTIME_SUMMARY")"
cross_edit_count="$(field_metric mass_edit_count "$CROSS_MASS_RUNTIME_SUMMARY")"
cross_dirty_blocks="$(field_metric dirty_blocks "$CROSS_MASS_RUNTIME_SUMMARY")"
cross_chunk_replace="$(field_metric chunk_replace "$CROSS_MASS_RUNTIME_SUMMARY")"
cross_protocol_change="$(field_metric active_protocol_change "$CROSS_MASS_RUNTIME_SUMMARY")"

test "$proto_diff_count" = "0" || fail "protocol diff present"
test "$persisted_status" = "pass" || fail "persisted status is $persisted_status"
test "$persisted_dirty" = "godot_guarded" || fail "persisted dirty is $persisted_dirty"
test "$persisted_soak_status" = "pass" || fail "persisted soak status is $persisted_soak_status"
test "$persisted_protocol_change" = "0" || fail "persisted protocol change is $persisted_protocol_change"
test "$persisted_gpu_upload_fail" = "0" || fail "persisted gpu upload failures are $persisted_gpu_upload_fail"
require_int_ge persisted_soak_cycles "$persisted_soak_cycles" "$MIN_SOAK_CYCLES"
require_int_ge persisted_reload_cycles "$persisted_reload_cycles" "$((persisted_soak_cycles + 1))"
require_int_ge persisted_final_verify_count "$persisted_final_verify_count" "$MIN_FINAL_VERIFY_COUNT"
require_int_ge persisted_dirty_blocks "$persisted_dirty_blocks" "$MIN_PERSISTED_DIRTY_BLOCKS"
require_int_ge persisted_chunk_replace "$persisted_chunk_replace" "$MIN_PERSISTED_CHUNK_REPLACE"
require_int_ge persisted_edge_neighbor_subchunks "$persisted_edge_neighbor_subchunks" "$MIN_PERSISTED_EDGE_NEIGHBOR_SUBCHUNKS"
require_int_ge persisted_partial_subchunks "$persisted_partial_subchunks" "$MIN_PERSISTED_PARTIAL_SUBCHUNKS"
require_int_ge persisted_partial_saved_subchunks "$persisted_partial_saved_subchunks" "$MIN_PERSISTED_PARTIAL_SAVED_SUBCHUNKS"
require_float_le persisted_terrain_queue_max_ms "$persisted_terrain_queue_max" "$MAX_TERRAIN_QUEUE_MS"
require_float_le persisted_gpu_compositor_submit_max_ms "$persisted_gpu_submit_max" "$MAX_GPU_COMPOSITOR_SUBMIT_MS"
require_float_le persisted_process_wall_p95_ms "$persisted_process_wall_p95" "$MAX_PROCESS_WALL_P95_MS"

test "$mass_status" = "pass" || fail "mass status is $mass_status"
test "$mass_runtime" = "godot_guarded" || fail "mass runtime is $mass_runtime"
test "$mass_budget" = "godot_guarded" || fail "mass budget is $mass_budget"
test "$mass_protocol_change" = "0" || fail "mass protocol change is $mass_protocol_change"
test "$cross_status" = "pass" || fail "cross status is $cross_status"
test "$cross_runtime" = "godot_guarded" || fail "cross runtime is $cross_runtime"
test "$cross_budget" = "godot_guarded" || fail "cross budget is $cross_budget"
test "$cross_protocol_change" = "0" || fail "cross protocol change is $cross_protocol_change"
require_int_ge cross_chunk_count "$cross_chunk_count" 4

matrix_dirty_blocks=$((persisted_dirty_blocks + mass_dirty_blocks + cross_dirty_blocks))
matrix_chunk_replace=$((persisted_chunk_replace + mass_chunk_replace + cross_chunk_replace))
matrix_edit_count=$((persisted_soak_cycles * persisted_edit_count + mass_edit_count + cross_edit_count))
require_int_ge matrix_dirty_blocks "$matrix_dirty_blocks" "$MIN_MATRIX_DIRTY_BLOCKS"
require_int_ge matrix_chunk_replace "$matrix_chunk_replace" "$MIN_MATRIX_CHUNK_REPLACE"
require_int_ge matrix_edit_count "$matrix_edit_count" "$MIN_MATRIX_EDIT_COUNT"

{
  printf 'dirty_update_high_count_runtime status=pass high_count_status=persisted_reload_matrix_guarded persisted_high_count=godot_guarded matrix_status=pass matrix_lane_count=3 active_protocol_change=0 persisted_soak_cycles=%s persisted_reload_cycles=%s persisted_final_verify_count=%s persisted_dirty_blocks=%s persisted_chunk_replace=%s persisted_edge_neighbor_subchunks=%s persisted_partial_subchunks=%s persisted_partial_saved_subchunks=%s persisted_terrain_queue_max_ms=%s persisted_gpu_compositor_submit_max_ms=%s persisted_process_wall_p95_ms=%s persisted_gpu_upload_fail=%s mass_runtime_status=%s mass_edit_count=%s mass_dirty_blocks=%s cross_chunk_mass_status=%s cross_chunk_count=%s cross_mass_edit_count=%s cross_dirty_blocks=%s matrix_dirty_blocks=%s matrix_chunk_replace=%s matrix_edit_count=%s persisted_summary=%s mass_summary=%s cross_summary=%s\n' \
    "$persisted_soak_cycles" \
    "$persisted_reload_cycles" \
    "$persisted_final_verify_count" \
    "$persisted_dirty_blocks" \
    "$persisted_chunk_replace" \
    "$persisted_edge_neighbor_subchunks" \
    "$persisted_partial_subchunks" \
    "$persisted_partial_saved_subchunks" \
    "$persisted_terrain_queue_max" \
    "$persisted_gpu_submit_max" \
    "$persisted_process_wall_p95" \
    "$persisted_gpu_upload_fail" \
    "$mass_status" \
    "$mass_edit_count" \
    "$mass_dirty_blocks" \
    "$cross_status" \
    "$cross_chunk_count" \
    "$cross_edit_count" \
    "$cross_dirty_blocks" \
    "$matrix_dirty_blocks" \
    "$matrix_chunk_replace" \
    "$matrix_edit_count" \
    "$PERSISTED_SUMMARY" \
    "$MASS_RUNTIME_SUMMARY" \
    "$CROSS_MASS_RUNTIME_SUMMARY"
} > "$SUMMARY_PATH"

cat "$SUMMARY_PATH"
echo "Dirty update high-count runtime artifacts: $OUT_DIR"
