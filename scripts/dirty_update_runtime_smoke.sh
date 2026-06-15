#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/dirty_update_runtime_smoke"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

SUMMARY_PATH="$OUT_DIR/dirty-update-runtime-smoke-summary.txt"
case "$(basename "$OUT_DIR")" in
  *_current)
    ARTIFACT_DIR="${RUMPELMC_DIRTY_RUNTIME_ARTIFACT_DIR:-"$ROOT_DIR/logs/dirty_update_runtime_smoke_artifacts"}"
    ;;
  *)
    ARTIFACT_DIR="${RUMPELMC_DIRTY_RUNTIME_ARTIFACT_DIR:-"$OUT_DIR/artifacts"}"
    ;;
esac
case "$ARTIFACT_DIR" in
  /*) ;;
  *) ARTIFACT_DIR="$ROOT_DIR/$ARTIFACT_DIR" ;;
esac
SINGLE_COMPARE_DIR="$ARTIFACT_DIR/single_edge_compare"
CORNER_COMPARE_DIR="$ARTIFACT_DIR/corner_edge_compare"
CORNER_REPEAT_DIR="$ARTIFACT_DIR/corner_edge_repeat"
REPEAT_COUNT="${RUMPELMC_DIRTY_RUNTIME_REPEAT_COUNT:-2}"
TARGET_FPS="${RUMPELMC_DIRTY_RUNTIME_TARGET_FPS:-100}"

fail() {
  echo "dirty_update_runtime_smoke: $*" >&2
  exit 1
}

require_line_regex() {
  path="$1"
  regex="$2"
  test -s "$path" || fail "missing summary $path"
  grep -Eq "$regex" "$path" || fail "missing regex '$regex' in $path"
}

line_metric() {
  regex="$1"
  key="$2"
  path="$3"
  awk -v regex="$regex" -v key="$key" '
    $0 ~ regex {
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

require_positive_int() {
  name="$1"
  value="$2"
  case "$value" in
    ''|*[!0-9]*) fail "$name must be a positive integer, got $value" ;;
  esac
  if [ "$value" -lt 1 ]; then
    fail "$name must be >= 1, got $value"
  fi
}

require_metric_equals() {
  line_regex="$1"
  key="$2"
  path="$3"
  expected="$4"
  value="$(line_metric "$line_regex" "$key" "$path")"
  test -n "$value" || fail "missing $key on $line_regex in $path"
  if [ "$value" != "$expected" ]; then
    fail "$key=$value on $line_regex in $path, expected $expected"
  fi
}

require_metric_positive() {
  line_regex="$1"
  key="$2"
  path="$3"
  value="$(line_metric "$line_regex" "$key" "$path")"
  test -n "$value" || fail "missing $key on $line_regex in $path"
  require_positive_int "$key" "$value"
}

validate_compare_summary() {
  label="$1"
  summary="$2"
  expected_edges="$3"
  expected_bounds="$4"

  require_line_regex "$summary" "^GPU terrain edge dirty compare summary .*expected_edges=$expected_edges .*expected_bounds=$expected_bounds"
  require_metric_equals '^full ' dirty_edge_neighbor_subchunks "$summary" 0
  require_metric_equals '^full ' dirty_partial_subchunks "$summary" 0
  require_metric_equals '^full ' dirty_partial_saved_subchunks "$summary" 0
  require_metric_equals '^full ' gpu_upload_fail "$summary" 0
  require_metric_positive '^partial ' dirty_edge_neighbor_subchunks "$summary"
  require_metric_positive '^partial ' dirty_partial_subchunks "$summary"
  require_metric_positive '^partial ' dirty_partial_saved_subchunks "$summary"
  require_metric_equals '^partial ' gpu_upload_fail "$summary" 0
  require_metric_equals '^comparison ' dirty_blocks_match "$summary" 1
  require_metric_equals '^comparison ' dirty_last_rebuild_subchunks_match "$summary" 1
  printf '%s\n' "$label"
}

validate_repeat_summary() {
  summary="$1"
  require_line_regex "$summary" "^GPU terrain edge dirty repeat summary repeats=$REPEAT_COUNT "
  require_line_regex "$summary" '^aggregate .*status=pass'
  runs="$(line_metric '^aggregate ' runs "$summary")"
  test -n "$runs" || fail "missing aggregate runs in $summary"
  if [ "$runs" -ne "$REPEAT_COUNT" ]; then
    fail "repeat aggregate runs=$runs, expected $REPEAT_COUNT"
  fi
  pass_runs="$(grep -Ec '^run=.* status=pass' "$summary")"
  if [ "$pass_runs" -ne "$REPEAT_COUNT" ]; then
    fail "repeat pass runs=$pass_runs, expected $REPEAT_COUNT"
  fi
}

run_single_edge_compare() {
  log_path="$OUT_DIR/single-edge-compare-run.log"
  if ! sh "$ROOT_DIR/scripts/gpu_terrain_single_edge_dirty_compare.sh" "$SINGLE_COMPARE_DIR" > "$log_path" 2>&1; then
    cat "$log_path" >&2 || true
    fail "single-edge dirty compare failed"
  fi
}

run_corner_edge_compare() {
  log_path="$OUT_DIR/corner-edge-compare-run.log"
  if ! RUMPELMC_EDGE_DIRTY_COMPARE_ACTION=toggle \
    RUMPELMC_EDGE_DIRTY_COMPARE_X=127 \
    RUMPELMC_EDGE_DIRTY_COMPARE_Y=64 \
    RUMPELMC_EDGE_DIRTY_COMPARE_Z=95 \
    RUMPELMC_EDGE_DIRTY_COMPARE_EXPECTED_EDGES=pos_x,pos_z \
    RUMPELMC_EDGE_DIRTY_COMPARE_EXPECTED_BOUNDS=31,64,31:31,64,31 \
    sh "$ROOT_DIR/scripts/gpu_terrain_edge_dirty_compare.sh" "$CORNER_COMPARE_DIR" > "$log_path" 2>&1; then
    cat "$log_path" >&2 || true
    fail "corner-edge dirty compare failed"
  fi
}

run_corner_edge_repeat() {
  log_path="$OUT_DIR/corner-edge-repeat-run.log"
  if ! RUMPELMC_EDGE_DIRTY_REPEAT_COUNT="$REPEAT_COUNT" \
    RUMPELMC_EDGE_DIRTY_REPEAT_TARGET_FPS="$TARGET_FPS" \
    RUMPELMC_EDGE_DIRTY_REPEAT_ACTION=toggle \
    RUMPELMC_EDGE_DIRTY_REPEAT_X=127 \
    RUMPELMC_EDGE_DIRTY_REPEAT_Y=64 \
    RUMPELMC_EDGE_DIRTY_REPEAT_Z=95 \
    RUMPELMC_EDGE_DIRTY_REPEAT_EXPECTED_EDGES=pos_x,pos_z \
    RUMPELMC_EDGE_DIRTY_REPEAT_EXPECTED_BOUNDS=31,64,31:31,64,31 \
    sh "$ROOT_DIR/scripts/gpu_terrain_edge_dirty_repeat.sh" "$CORNER_REPEAT_DIR" > "$log_path" 2>&1; then
    cat "$log_path" >&2 || true
    fail "corner-edge dirty repeat failed"
  fi
}

require_positive_int RUMPELMC_DIRTY_RUNTIME_REPEAT_COUNT "$REPEAT_COUNT"
mkdir -p "$OUT_DIR"
mkdir -p "$ARTIFACT_DIR"
rm -rf "$SINGLE_COMPARE_DIR" "$CORNER_COMPARE_DIR" "$CORNER_REPEAT_DIR"
rm -rf "$OUT_DIR/single_edge_compare" "$OUT_DIR/corner_edge_compare" "$OUT_DIR/corner_edge_repeat"
rm -f "$SUMMARY_PATH" "$OUT_DIR"/*-run.log

proto_diff_count="$(git -C "$ROOT_DIR" diff --name-only -- api/schema/packets.proto server/pkg/api/packets.pb.go | awk 'END { print NR + 0 }')"
if [ "$proto_diff_count" -ne 0 ]; then
  fail "protocol diff present"
fi

run_single_edge_compare
run_corner_edge_compare
run_corner_edge_repeat

single_summary="$SINGLE_COMPARE_DIR/edge-dirty-compare-summary.txt"
corner_summary="$CORNER_COMPARE_DIR/edge-dirty-compare-summary.txt"
repeat_summary="$CORNER_REPEAT_DIR/edge-dirty-repeat-summary.txt"

validate_compare_summary single_edge_compare "$single_summary" pos_x '31,64,16:31,64,16' >/dev/null
validate_compare_summary corner_edge_compare "$corner_summary" pos_x,pos_z '31,64,31:31,64,31' >/dev/null
validate_repeat_summary "$repeat_summary"

single_partial_saved="$(line_metric '^partial ' dirty_partial_saved_subchunks "$single_summary")"
single_partial_edge_neighbors="$(line_metric '^partial ' dirty_edge_neighbor_subchunks "$single_summary")"
single_queue_max="$(line_metric '^partial ' terrain_queue_max_ms "$single_summary")"
corner_partial_saved="$(line_metric '^partial ' dirty_partial_saved_subchunks "$corner_summary")"
corner_partial_edge_neighbors="$(line_metric '^partial ' dirty_edge_neighbor_subchunks "$corner_summary")"
corner_queue_max="$(line_metric '^partial ' terrain_queue_max_ms "$corner_summary")"
repeat_queue_max="$(line_metric '^aggregate ' terrain_queue_max_ms_max "$repeat_summary")"
repeat_submit_max="$(line_metric '^aggregate ' gpu_compositor_submit_max_ms_max "$repeat_summary")"
repeat_process_p95="$(line_metric '^aggregate ' process_wall_p95_ms_max "$repeat_summary")"

{
  printf 'dirty_update_runtime_smoke status=pass runtime_edge_dirty=godot_guarded runtime_mass_edit=deferred single_edge_compare=pass corner_edge_compare=pass corner_edge_repeat=pass repeat_runs=%s target_fps=%s active_protocol_change=0 single_summary=%s corner_summary=%s repeat_summary=%s\n' \
    "$REPEAT_COUNT" \
    "$TARGET_FPS" \
    "$single_summary" \
    "$corner_summary" \
    "$repeat_summary"
  printf 'single_edge partial_saved_subchunks=%s partial_edge_neighbor_subchunks=%s partial_terrain_queue_max_ms=%s gpu_upload_fail=0\n' \
    "$single_partial_saved" \
    "$single_partial_edge_neighbors" \
    "$single_queue_max"
  printf 'corner_edge partial_saved_subchunks=%s partial_edge_neighbor_subchunks=%s partial_terrain_queue_max_ms=%s gpu_upload_fail=0\n' \
    "$corner_partial_saved" \
    "$corner_partial_edge_neighbors" \
    "$corner_queue_max"
  printf 'corner_repeat runs=%s terrain_queue_max_ms=%s gpu_compositor_submit_max_ms=%s process_wall_p95_ms=%s gpu_upload_fail=0\n' \
    "$REPEAT_COUNT" \
    "$repeat_queue_max" \
    "$repeat_submit_max" \
    "$repeat_process_p95"
} > "$SUMMARY_PATH"

cat "$SUMMARY_PATH"
