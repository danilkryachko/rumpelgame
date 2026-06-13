#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/world_streaming_bootstrap_compare"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

BASE_RADIUS="${RUMPELMC_WORLD_STREAMING_BOOTSTRAP_COMPARE_BASE:-full}"
CANDIDATE_RADIUS="${RUMPELMC_WORLD_STREAMING_BOOTSTRAP_COMPARE_CANDIDATE:-2}"
BUILD_SERVER="${RUMPELMC_WORLD_STREAMING_BOOTSTRAP_COMPARE_BUILD_SERVER:-1}"
BASE_DIR="$OUT_DIR/bootstrap-$BASE_RADIUS"
CANDIDATE_DIR="$OUT_DIR/bootstrap-$CANDIDATE_RADIUS"
BASE_LOG="$BASE_DIR/run.log"
CANDIDATE_LOG="$CANDIDATE_DIR/run.log"
BASE_SUMMARY="$BASE_DIR/world-streaming-bootstrap-summary.txt"
CANDIDATE_SUMMARY="$CANDIDATE_DIR/world-streaming-bootstrap-summary.txt"
COMPARE_SUMMARY="$OUT_DIR/world-streaming-bootstrap-compare-summary.txt"

mkdir -p "$BASE_DIR" "$CANDIDATE_DIR"

fail() {
  echo "world_streaming_bootstrap_compare: $*" >&2
  exit 1
}

sign_server_binary_if_possible() {
  if command -v codesign >/dev/null 2>&1; then
    codesign -s - --force ./server >/dev/null 2>&1 || true
  fi
}

listener_pid() {
  if command -v lsof >/dev/null 2>&1; then
    lsof -tiTCP:25565 -sTCP:LISTEN 2>/dev/null | sed -n '1p'
  fi
}

wait_for_port_clear() {
  tries=0
  while [ "$tries" -lt 10 ]; do
    pid="$(listener_pid || true)"
    if [ -z "$pid" ]; then
      return 0
    fi
    tries=$((tries + 1))
    sleep 1
  done
  fail "port 25565 is still listening after cleanup"
}

cleanup_server() {
  pid="$(listener_pid || true)"
  if [ -n "$pid" ]; then
    kill "$pid" 2>/dev/null || true
    wait_for_port_clear
  fi
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
          gsub(/[^0-9.].*/, "", value)
          print value
          exit
        }
      }
    }
  ' "$path"
}

summary_metric() {
  label="$1"
  key="$2"
  path="$3"
  awk -v label="$label" -v key="$key" '
    $1 == label {
      prefix = key "="
      for (i = 2; i <= NF; i++) {
        if (index($i, prefix) == 1) {
          value = substr($i, length(prefix) + 1)
          gsub(/[^0-9.].*/, "", value)
          print value
          exit
        }
      }
    }
  ' "$path"
}

require_radius_value() {
  name="$1"
  value="$2"
  if [ "$value" = "full" ]; then
    return 0
  fi
  case "$value" in
    ''|*[!0-9]*) fail "$name must be full or a non-negative integer, got $value" ;;
  esac
}

summarize_run() {
  label="$1"
  run_log="$2"
  marker_path="$3"
  movement_summary="$4"
  summary_path="$5"

  test -s "$marker_path" || fail "missing movement marker $marker_path"
  test -s "$movement_summary" || fail "missing movement summary $movement_summary"
  grep -q "smoke_err=0" "$marker_path" || fail "smoke_err is not 0 in $marker_path"
  grep -q 'motion="chunk_walk"' "$marker_path" || fail "movement marker did not run chunk_walk"
  grep -q 'current_chunk="3,2"' "$marker_path" || fail "movement did not finish at chunk 3,2"
  grep -q "Chunk received .* blocks=1048576" "$run_log" || fail "chunks were not decoded to full block payloads"
  grep -q "Chunk stream batch" "$run_log" || fail "missing chunk stream batch metrics in $run_log"

  terrain_queue_max_ms="$(summary_metric movement_terrain_queue max_ms "$movement_summary")"
  process_wall_p95_ms="$(metric process_wall_p95_ms "$movement_summary")"
  gpu_compositor_submit_max_ms="$(metric gpu_compositor_submit_max_ms "$movement_summary")"
  chunk_initial="$(metric chunk_initial "$marker_path")"
  gpu_upload_fail="$(metric gpu_upload_fail "$marker_path")"
  current_chunk_loaded="$(metric current_chunk_loaded "$marker_path")"
  current_chunk_collision="$(metric current_chunk_collision "$marker_path")"
  ground_hits="$(metric ground_hits "$marker_path")"

  awk \
    -v label="$label" \
    -v marker_path="$marker_path" \
    -v run_log="$run_log" \
    -v terrain_queue_max_ms="${terrain_queue_max_ms:-0}" \
    -v process_wall_p95_ms="${process_wall_p95_ms:-0}" \
    -v gpu_compositor_submit_max_ms="${gpu_compositor_submit_max_ms:-0}" \
    -v chunk_initial="${chunk_initial:-0}" \
    -v gpu_upload_fail="${gpu_upload_fail:-0}" \
    -v current_chunk_loaded="${current_chunk_loaded:-0}" \
    -v current_chunk_collision="${current_chunk_collision:-0}" \
    -v ground_hits="${ground_hits:-0}" '
    /Chunk stream batch/ {
      radius = ""
      batch_chunks = 0
      batch_raw = 0
      batch_payload = 0
      batch_wire = 0
      batch_elapsed = 0.0
      for (i = 1; i <= NF; i++) {
        split($i, a, "=")
        if (a[1] == "radius") radius = a[2]
        if (a[1] == "chunks") batch_chunks = a[2]
        if (a[1] == "raw_bytes") batch_raw = a[2]
        if (a[1] == "payload_bytes") batch_payload = a[2]
        if (a[1] == "wire_bytes") batch_wire = a[2]
        if (a[1] == "elapsed_ms") batch_elapsed = a[2]
      }
      if (batches == 0) {
        first_radius = radius
        first_chunks = batch_chunks
        first_raw = batch_raw
        first_payload = batch_payload
        first_wire = batch_wire
        first_elapsed = batch_elapsed
      }
      chunks += batch_chunks
      raw += batch_raw
      payload += batch_payload
      wire += batch_wire
      elapsed += batch_elapsed
      if (batch_elapsed > elapsed_max) elapsed_max = batch_elapsed
      batches++
    }
    END {
      if (batches < 1 || chunks < 1 || raw < 1 || payload < 1 || wire < 1 || first_radius == "") {
        printf("invalid stream metric totals label=%s batches=%d chunks=%d raw=%d payload=%d wire=%d first_radius=%s\n", label, batches, chunks, raw, payload, wire, first_radius) > "/dev/stderr"
        exit 1
      }
      if (payload * 100 >= raw) {
        printf("label=%s payload is not below 1%% of raw raw=%d payload=%d\n", label, raw, payload) > "/dev/stderr"
        exit 1
      }
      if (wire * 100 >= raw) {
        printf("label=%s wire is not below 1%% of raw raw=%d wire=%d\n", label, raw, wire) > "/dev/stderr"
        exit 1
      }
      printf("world_streaming_bootstrap status=pass label=%s first_radius=%s first_chunks=%d first_raw_bytes=%d first_payload_bytes=%d first_wire_bytes=%d first_elapsed_ms=%.3f batches=%d chunks=%d raw_bytes=%d payload_bytes=%d wire_bytes=%d payload_pct=%.6f wire_pct=%.6f elapsed_avg_ms=%.3f elapsed_max_ms=%.3f chunk_initial=%d current_chunk_loaded=%d current_chunk_collision=%d ground_hits=%d gpu_upload_fail=%d terrain_queue_max_ms=%.3f process_wall_p95_ms=%.3f gpu_compositor_submit_max_ms=%.3f marker=%s run_log=%s\n", label, first_radius, first_chunks, first_raw, first_payload, first_wire, first_elapsed, batches, chunks, raw, payload, wire, payload * 100.0 / raw, wire * 100.0 / raw, elapsed / batches, elapsed_max, chunk_initial, current_chunk_loaded, current_chunk_collision, ground_hits, gpu_upload_fail, terrain_queue_max_ms, process_wall_p95_ms, gpu_compositor_submit_max_ms, marker_path, run_log)
    }
  ' "$run_log" > "$summary_path"
}

run_case() {
  label="$1"
  radius="$2"
  run_dir="$3"
  run_log="$4"

  rm -rf "$run_dir"
  mkdir -p "$run_dir"
  if [ "$radius" = "full" ]; then
    RUMPELMC_SERVER_BOOTSTRAP_RADIUS=full \
      RUMPELMC_SERVER_CHUNK_STREAM_METRICS=1 \
      RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE="${RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE:-1}" \
      RUMPELMC_GODOT_RUST_EXT_PROFILE="${RUMPELMC_GODOT_RUST_EXT_PROFILE:-release}" \
      "$ROOT_DIR/scripts/gpu_terrain_movement_stress.sh" "$run_dir" > "$run_log" 2>&1
  else
    RUMPELMC_SERVER_BOOTSTRAP_RADIUS="$radius" \
      RUMPELMC_SERVER_CHUNK_STREAM_METRICS=1 \
      RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE="${RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE:-1}" \
      RUMPELMC_GODOT_RUST_EXT_PROFILE="${RUMPELMC_GODOT_RUST_EXT_PROFILE:-release}" \
      "$ROOT_DIR/scripts/gpu_terrain_movement_stress.sh" "$run_dir" > "$run_log" 2>&1
  fi
}

require_radius_value RUMPELMC_WORLD_STREAMING_BOOTSTRAP_COMPARE_BASE "$BASE_RADIUS"
require_radius_value RUMPELMC_WORLD_STREAMING_BOOTSTRAP_COMPARE_CANDIDATE "$CANDIDATE_RADIUS"

listener="$(listener_pid || true)"
if [ -n "$listener" ]; then
  fail "port 25565 is already in use; stop the existing server before bootstrap compare"
fi
trap cleanup_server EXIT HUP INT TERM

case "$BUILD_SERVER" in
  0) ;;
  1)
    (
      cd "$ROOT_DIR/server"
      go build -o ./server ./cmd/server
      sign_server_binary_if_possible
    )
    ;;
  *)
    fail "unsupported RUMPELMC_WORLD_STREAMING_BOOTSTRAP_COMPARE_BUILD_SERVER=$BUILD_SERVER"
    ;;
esac

rm -f "$BASE_SUMMARY" "$CANDIDATE_SUMMARY" "$COMPARE_SUMMARY"

set +e
run_case "$BASE_RADIUS" "$BASE_RADIUS" "$BASE_DIR" "$BASE_LOG"
rc=$?
set -e
if [ "$rc" -ne 0 ]; then
  cat "$BASE_LOG" >&2 || true
  fail "base bootstrap movement stress failed with exit code $rc"
fi
cleanup_server

set +e
run_case "$CANDIDATE_RADIUS" "$CANDIDATE_RADIUS" "$CANDIDATE_DIR" "$CANDIDATE_LOG"
rc=$?
set -e
if [ "$rc" -ne 0 ]; then
  cat "$CANDIDATE_LOG" >&2 || true
  fail "candidate bootstrap movement stress failed with exit code $rc"
fi
cleanup_server

summarize_run "$BASE_RADIUS" "$BASE_LOG" "$BASE_DIR/gpu-terrain-movement-stress.png.txt" "$BASE_DIR/movement-stress-summary.txt" "$BASE_SUMMARY"
summarize_run "$CANDIDATE_RADIUS" "$CANDIDATE_LOG" "$CANDIDATE_DIR/gpu-terrain-movement-stress.png.txt" "$CANDIDATE_DIR/movement-stress-summary.txt" "$CANDIDATE_SUMMARY"

base_first_chunks="$(metric first_chunks "$BASE_SUMMARY")"
candidate_first_chunks="$(metric first_chunks "$CANDIDATE_SUMMARY")"
base_first_radius="$(metric first_radius "$BASE_SUMMARY")"
candidate_first_radius="$(metric first_radius "$CANDIDATE_SUMMARY")"
base_chunks="$(metric chunks "$BASE_SUMMARY")"
candidate_chunks="$(metric chunks "$CANDIDATE_SUMMARY")"
base_batches="$(metric batches "$BASE_SUMMARY")"
candidate_batches="$(metric batches "$CANDIDATE_SUMMARY")"
base_terrain_queue_max="$(metric terrain_queue_max_ms "$BASE_SUMMARY")"
candidate_terrain_queue_max="$(metric terrain_queue_max_ms "$CANDIDATE_SUMMARY")"
base_process_wall_p95="$(metric process_wall_p95_ms "$BASE_SUMMARY")"
candidate_process_wall_p95="$(metric process_wall_p95_ms "$CANDIDATE_SUMMARY")"
base_submit_max="$(metric gpu_compositor_submit_max_ms "$BASE_SUMMARY")"
candidate_submit_max="$(metric gpu_compositor_submit_max_ms "$CANDIDATE_SUMMARY")"

awk \
  -v base_label="$BASE_RADIUS" \
  -v candidate_label="$CANDIDATE_RADIUS" \
  -v base_first_radius="$base_first_radius" \
  -v candidate_first_radius="$candidate_first_radius" \
  -v base_first_chunks="$base_first_chunks" \
  -v candidate_first_chunks="$candidate_first_chunks" \
  -v base_chunks="$base_chunks" \
  -v candidate_chunks="$candidate_chunks" \
  -v base_batches="$base_batches" \
  -v candidate_batches="$candidate_batches" \
  -v base_terrain_queue_max="$base_terrain_queue_max" \
  -v candidate_terrain_queue_max="$candidate_terrain_queue_max" \
  -v base_process_wall_p95="$base_process_wall_p95" \
  -v candidate_process_wall_p95="$candidate_process_wall_p95" \
  -v base_submit_max="$base_submit_max" \
  -v candidate_submit_max="$candidate_submit_max" \
  -v base_summary="$BASE_SUMMARY" \
  -v candidate_summary="$CANDIDATE_SUMMARY" '
  BEGIN {
    if (candidate_first_chunks >= base_first_chunks) {
      printf("candidate first stream did not shrink base=%d candidate=%d\n", base_first_chunks, candidate_first_chunks) > "/dev/stderr"
      exit 1
    }
    if (candidate_chunks < base_chunks) {
      printf("candidate streamed fewer total chunks than base base=%d candidate=%d\n", base_chunks, candidate_chunks) > "/dev/stderr"
      exit 1
    }
    printf("world_streaming_bootstrap_compare status=pass base_label=%s candidate_label=%s base_first_radius=%s candidate_first_radius=%s base_first_chunks=%d candidate_first_chunks=%d base_chunks=%d candidate_chunks=%d base_batches=%d candidate_batches=%d base_terrain_queue_max_ms=%.3f candidate_terrain_queue_max_ms=%.3f base_process_wall_p95_ms=%.3f candidate_process_wall_p95_ms=%.3f base_gpu_compositor_submit_max_ms=%.3f candidate_gpu_compositor_submit_max_ms=%.3f base_summary=%s candidate_summary=%s\n", base_label, candidate_label, base_first_radius, candidate_first_radius, base_first_chunks, candidate_first_chunks, base_chunks, candidate_chunks, base_batches, candidate_batches, base_terrain_queue_max, candidate_terrain_queue_max, base_process_wall_p95, candidate_process_wall_p95, base_submit_max, candidate_submit_max, base_summary, candidate_summary)
  }
' > "$COMPARE_SUMMARY"

cat "$BASE_SUMMARY"
cat "$CANDIDATE_SUMMARY"
cat "$COMPARE_SUMMARY"
