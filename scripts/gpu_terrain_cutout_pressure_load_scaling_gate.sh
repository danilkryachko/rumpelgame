#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/gpu_terrain_cutout_pressure_load_scaling_current"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

SUMMARY_PATH="$OUT_DIR/gpu-terrain-cutout-pressure-load-scaling-summary.txt"
LOAD_SCALING_SUMMARY="${RUMPELMC_CUTOUT_PRESSURE_LOAD_SCALING_SUMMARY:-}"
LOAD_SCALING_DIR="$OUT_DIR/load-scaling"
ROCKSDB_PATH="$OUT_DIR/rocksdb"
REPORT_PATH="$OUT_DIR/gpu-terrain-cutout-pressure-load-scaling-report.txt"
CLEANUP_SERVER_ON_EXIT=0

MIN_GPU_SUBCHUNKS="${RUMPELMC_CUTOUT_PRESSURE_MIN_GPU_SUBCHUNKS:-1800}"
MIN_GPU_DRAWS="${RUMPELMC_CUTOUT_PRESSURE_MIN_GPU_DRAWS:-1800}"
MIN_GPU_FACES="${RUMPELMC_CUTOUT_PRESSURE_MIN_GPU_FACES:-3000}"
MIN_DRAW_CMD_OCCUPANCY_PCT="${RUMPELMC_CUTOUT_PRESSURE_MIN_DRAW_CMD_OCCUPANCY_PCT:-22.0}"
MIN_FIXTURE_BLOCKS="${RUMPELMC_CUTOUT_PRESSURE_MIN_FIXTURE_BLOCKS:-500}"
MIN_TRANSPARENT_BLOCKS="${RUMPELMC_CUTOUT_PRESSURE_MIN_TRANSPARENT_BLOCKS:-500}"
MIN_TRANSPARENT_FACES="${RUMPELMC_CUTOUT_PRESSURE_MIN_TRANSPARENT_FACES:-500}"
MIN_TRANSPARENT_DRAWS="${RUMPELMC_CUTOUT_PRESSURE_MIN_TRANSPARENT_DRAWS:-100}"
MIN_TRANSPARENT_SUBCHUNKS="${RUMPELMC_CUTOUT_PRESSURE_MIN_TRANSPARENT_SUBCHUNKS:-100}"
MAX_TERRAIN_QUEUE_MS="${RUMPELMC_CUTOUT_PRESSURE_MAX_TERRAIN_QUEUE_MS:-6.667}"
MAX_PROCESS_WALL_P95_MS="${RUMPELMC_CUTOUT_PRESSURE_MAX_PROCESS_WALL_P95_MS:-6.667}"
MAX_GPU_COMPOSITOR_SUBMIT_MS="${RUMPELMC_CUTOUT_PRESSURE_MAX_GPU_COMPOSITOR_SUBMIT_MS:-6.667}"

fail() {
  echo "gpu_terrain_cutout_pressure_load_scaling_gate: $*" >&2
  exit 1
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

require_field() {
  key="$1"
  path="$2"
  value="$(field_metric "$key" "$path")"
  test -n "$value" || fail "missing $key in $(relative_path "$path")"
  printf '%s\n' "$value"
}

require_port_free() {
  if command -v lsof >/dev/null 2>&1 && lsof -nP -iTCP:25565 -sTCP:LISTEN >/dev/null 2>&1; then
    fail "port 25565 is already in use; refusing to reuse a server for this isolated pressure gate"
  fi
}

cleanup_isolated_server() {
  test "$CLEANUP_SERVER_ON_EXIT" = "1" || return 0
  command -v lsof >/dev/null 2>&1 || return 0
  pid="$(lsof -tiTCP:25565 -sTCP:LISTEN | sed -n '1p' || true)"
  test -n "$pid" || return 0
  kill "$pid" >/dev/null 2>&1 || true
}

cleanup() {
  test -z "${tmp_summary:-}" || rm -f "$tmp_summary"
  cleanup_isolated_server
}

require_source_token() {
  path="$1"
  token="$2"
  test -s "$path" || fail "missing source $(relative_path "$path")"
  grep -Fq "$token" "$path" || fail "missing token '$token' in $(relative_path "$path")"
}

mkdir -p "$OUT_DIR"
tmp_summary="$SUMMARY_PATH.tmp"
trap cleanup EXIT
trap 'cleanup; exit 1' HUP INT TERM

if [ -n "$LOAD_SCALING_SUMMARY" ]; then
  case "$LOAD_SCALING_SUMMARY" in
    /*) ;;
    *) LOAD_SCALING_SUMMARY="$ROOT_DIR/$LOAD_SCALING_SUMMARY" ;;
  esac
fi

if [ -z "$LOAD_SCALING_SUMMARY" ]; then
  rm -rf "$LOAD_SCALING_DIR" "$ROCKSDB_PATH"
  require_port_free
  CLEANUP_SERVER_ON_EXIT=1
  RUMPELMC_SERVER_ROCKSDB_PATH="$ROCKSDB_PATH" \
    RUMPELMC_GPU_TERRAIN_CUTOUT_PROTOTYPE=1 \
    RUMPELMC_RESIDENT_SET_CASE_SET=pressure \
    RUMPELMC_RESIDENT_SET_TERRAIN_PRESSURE_FIXTURE=chunk_disc \
    RUMPELMC_RESIDENT_SET_TERRAIN_PRESSURE_FIXTURE_BLOCK_ID=5 \
    RUMPELMC_GPU_LOAD_SCALING_MIN_GPU_SUBCHUNKS="$MIN_GPU_SUBCHUNKS" \
    RUMPELMC_GPU_LOAD_SCALING_MIN_GPU_DRAWS="$MIN_GPU_DRAWS" \
    RUMPELMC_GPU_LOAD_SCALING_MIN_GPU_FACES="$MIN_GPU_FACES" \
    RUMPELMC_GPU_LOAD_SCALING_MIN_DRAW_CMD_OCCUPANCY_PCT="$MIN_DRAW_CMD_OCCUPANCY_PCT" \
    /bin/sh "$ROOT_DIR/scripts/gpu_terrain_load_scaling.sh" "$LOAD_SCALING_DIR"
  LOAD_SCALING_SUMMARY="$LOAD_SCALING_DIR/gpu-terrain-load-scaling-summary.txt"
fi

test -s "$LOAD_SCALING_SUMMARY" || fail "missing load-scaling summary $(relative_path "$LOAD_SCALING_SUMMARY")"

status="$(require_field status "$LOAD_SCALING_SUMMARY")"
source_status="$(require_field source_status "$LOAD_SCALING_SUMMARY")"
source_case_set="$(require_field source_case_set "$LOAD_SCALING_SUMMARY")"
terrain_pressure_fixture="$(require_field terrain_pressure_fixture "$LOAD_SCALING_SUMMARY")"
terrain_pressure_fixture_block_id="$(require_field terrain_pressure_fixture_block_id "$LOAD_SCALING_SUMMARY")"
max_gpu_subchunks="$(require_field max_gpu_subchunks "$LOAD_SCALING_SUMMARY")"
max_gpu_draws="$(require_field max_gpu_draws "$LOAD_SCALING_SUMMARY")"
max_gpu_faces="$(require_field max_gpu_faces "$LOAD_SCALING_SUMMARY")"
gpu_draw_cmd_occupancy_pct="$(require_field gpu_draw_cmd_occupancy_pct "$LOAD_SCALING_SUMMARY")"
max_terrain_queue_ms="$(require_field max_terrain_queue_ms "$LOAD_SCALING_SUMMARY")"
max_process_wall_p95_ms="$(require_field max_process_wall_p95_ms "$LOAD_SCALING_SUMMARY")"
max_gpu_compositor_submit_ms="$(require_field max_gpu_compositor_submit_ms "$LOAD_SCALING_SUMMARY")"
gpu_upload_fail="$(require_field gpu_upload_fail "$LOAD_SCALING_SUMMARY")"
gpu_upload_fail_capacity="$(require_field gpu_upload_fail_capacity "$LOAD_SCALING_SUMMARY")"
gpu_upload_fail_fragmented="$(require_field gpu_upload_fail_fragmented "$LOAD_SCALING_SUMMARY")"
terrain_pressure_fixture_blocks="$(require_field terrain_pressure_fixture_blocks "$LOAD_SCALING_SUMMARY")"
terrain_pressure_fixture_dirty_observed="$(require_field terrain_pressure_fixture_dirty_observed "$LOAD_SCALING_SUMMARY")"
transparent_requested="$(require_field transparent_requested "$LOAD_SCALING_SUMMARY")"
transparent_active="$(require_field transparent_active "$LOAD_SCALING_SUMMARY")"
transparent_fallback="$(require_field transparent_fallback "$LOAD_SCALING_SUMMARY")"
transparent_blocks="$(require_field transparent_blocks "$LOAD_SCALING_SUMMARY")"
transparent_faces="$(require_field transparent_faces "$LOAD_SCALING_SUMMARY")"
transparent_draws="$(require_field transparent_draws "$LOAD_SCALING_SUMMARY")"
transparent_subchunks="$(require_field transparent_subchunks "$LOAD_SCALING_SUMMARY")"

require_source_token "$ROOT_DIR/client/rust_ext/src/lib.rs" "const GPU_TERRAIN_TRANSPARENT_IMPLEMENTED: bool = false;"
require_source_token "$ROOT_DIR/client/rust_ext/src/lib.rs" "const GPU_TERRAIN_CUTOUT_PROTOTYPE_IMPLEMENTED: bool = true;"
require_source_token "$ROOT_DIR/docs/GPU_TRANSPARENT_PATH.md" "There is no alpha blending, no transparent pass, and no transparent sorting in this slice."

awk \
  -v source_status="$source_status" \
  -v status="$status" \
  -v source_case_set="$source_case_set" \
  -v terrain_pressure_fixture="$terrain_pressure_fixture" \
  -v terrain_pressure_fixture_block_id="$terrain_pressure_fixture_block_id" \
  -v max_gpu_subchunks="$max_gpu_subchunks" \
  -v max_gpu_draws="$max_gpu_draws" \
  -v max_gpu_faces="$max_gpu_faces" \
  -v occupancy="$gpu_draw_cmd_occupancy_pct" \
  -v queue_ms="$max_terrain_queue_ms" \
  -v process_ms="$max_process_wall_p95_ms" \
  -v submit_ms="$max_gpu_compositor_submit_ms" \
  -v upload_fail="$gpu_upload_fail" \
  -v upload_fail_capacity="$gpu_upload_fail_capacity" \
  -v upload_fail_fragmented="$gpu_upload_fail_fragmented" \
  -v fixture_blocks="$terrain_pressure_fixture_blocks" \
  -v fixture_dirty="$terrain_pressure_fixture_dirty_observed" \
  -v transparent_requested="$transparent_requested" \
  -v transparent_active="$transparent_active" \
  -v transparent_fallback="$transparent_fallback" \
  -v transparent_blocks="$transparent_blocks" \
  -v transparent_faces="$transparent_faces" \
  -v transparent_draws="$transparent_draws" \
  -v transparent_subchunks="$transparent_subchunks" \
  -v min_subchunks="$MIN_GPU_SUBCHUNKS" \
  -v min_draws="$MIN_GPU_DRAWS" \
  -v min_faces="$MIN_GPU_FACES" \
  -v min_occupancy="$MIN_DRAW_CMD_OCCUPANCY_PCT" \
  -v min_fixture_blocks="$MIN_FIXTURE_BLOCKS" \
  -v min_transparent_blocks="$MIN_TRANSPARENT_BLOCKS" \
  -v min_transparent_faces="$MIN_TRANSPARENT_FACES" \
  -v min_transparent_draws="$MIN_TRANSPARENT_DRAWS" \
  -v min_transparent_subchunks="$MIN_TRANSPARENT_SUBCHUNKS" \
  -v max_queue="$MAX_TERRAIN_QUEUE_MS" \
  -v max_process="$MAX_PROCESS_WALL_P95_MS" \
  -v max_submit="$MAX_GPU_COMPOSITOR_SUBMIT_MS" \
  -v load_summary="$LOAD_SCALING_SUMMARY" '
  function set_fail(why) {
    if (gate_status == "pass") {
      gate_status = "fail"
      reason = why
    }
  }
  BEGIN {
    gate_status = "pass"
    reason = "cutout_pressure_within_budget"
    if (status != "pass" || source_status != "pass") {
      set_fail("load_scaling_prerequisite")
    } else if (source_case_set != "pressure" || terrain_pressure_fixture != "chunk_disc" || terrain_pressure_fixture_block_id + 0 != 5) {
      set_fail("fixture_identity")
    } else if (max_gpu_subchunks + 0 < min_subchunks + 0 || max_gpu_draws + 0 < min_draws + 0 || max_gpu_faces + 0 < min_faces + 0) {
      set_fail("gpu_pressure_too_low")
    } else if (occupancy + 0.0 < min_occupancy + 0.0) {
      set_fail("draw_command_occupancy")
    } else if (queue_ms + 0.0 > max_queue + 0.0) {
      set_fail("terrain_queue_budget")
    } else if (process_ms + 0.0 > max_process + 0.0) {
      set_fail("process_wall_budget")
    } else if (submit_ms + 0.0 > max_submit + 0.0) {
      set_fail("gpu_submit_budget")
    } else if (upload_fail + upload_fail_capacity + upload_fail_fragmented > 0) {
      set_fail("upload_failures")
    } else if (fixture_blocks + 0 < min_fixture_blocks + 0 || fixture_dirty + 0 < 1) {
      set_fail("fixture_dirty_pressure")
    } else if (transparent_requested + 0 != 1 || transparent_active + 0 != 1 || transparent_fallback + 0 != 0) {
      set_fail("cutout_transparent_state")
    } else if (transparent_blocks + 0 < min_transparent_blocks + 0 || transparent_faces + 0 < min_transparent_faces + 0 || transparent_draws + 0 < min_transparent_draws + 0 || transparent_subchunks + 0 < min_transparent_subchunks + 0) {
      set_fail("transparent_workload_too_low")
    }

    printf("gpu_terrain_cutout_pressure_load_scaling status=%s reason=%s runtime_contract=default_off_cutout_only source_status=%s source_case_set=%s terrain_pressure_fixture=%s terrain_pressure_fixture_block_id=%d terrain_pressure_fixture_blocks=%d terrain_pressure_fixture_dirty_observed=%d min_gpu_subchunks=%d max_gpu_subchunks=%d min_gpu_draws=%d max_gpu_draws=%d min_gpu_faces=%d max_gpu_faces=%d min_draw_cmd_occupancy_pct=%.1f gpu_draw_cmd_occupancy_pct=%.3f max_terrain_queue_ms=%.3f terrain_queue_budget_ms=%.3f max_process_wall_p95_ms=%.3f process_wall_budget_ms=%.3f max_gpu_compositor_submit_ms=%.3f gpu_submit_budget_ms=%.3f gpu_upload_fail=%d gpu_upload_fail_capacity=%d gpu_upload_fail_fragmented=%d transparent_requested=%d transparent_active=%d transparent_fallback=%d min_transparent_blocks=%d transparent_blocks=%d min_transparent_faces=%d transparent_faces=%d min_transparent_draws=%d transparent_draws=%d min_transparent_subchunks=%d transparent_subchunks=%d default_runtime_change_allowed=0 requires_external_profiler_before_default=1 requires_mac_windows_validation=1 load_summary=%s\n", gate_status, reason, source_status, source_case_set, terrain_pressure_fixture, terrain_pressure_fixture_block_id, fixture_blocks, fixture_dirty, min_subchunks, max_gpu_subchunks, min_draws, max_gpu_draws, min_faces, max_gpu_faces, min_occupancy, occupancy, queue_ms, max_queue, process_ms, max_process, submit_ms, max_submit, upload_fail, upload_fail_capacity, upload_fail_fragmented, transparent_requested, transparent_active, transparent_fallback, min_transparent_blocks, transparent_blocks, min_transparent_faces, transparent_faces, min_transparent_draws, transparent_draws, min_transparent_subchunks, transparent_subchunks, load_summary)
    if (gate_status != "pass") {
      exit 1
    }
  }
' > "$tmp_summary" || {
  cat "$tmp_summary" >&2 || true
  fail "cutout pressure load-scaling gate failed"
}

mv "$tmp_summary" "$SUMMARY_PATH"

sh "$ROOT_DIR/scripts/gpu_terrain_report.sh" "$OUT_DIR" "$REPORT_PATH" >/dev/null
grep -F "## Selected Cutout Pressure Load Scaling Summary" "$REPORT_PATH" >/dev/null \
  || fail "aggregate report did not surface cutout pressure load-scaling summary"
grep -F "gpu_terrain_cutout_pressure_load_scaling status=pass" "$REPORT_PATH" >/dev/null \
  || fail "aggregate report did not surface passing cutout pressure summary"

cat "$SUMMARY_PATH"
echo "GPU terrain cutout pressure load-scaling artifacts: $OUT_DIR"
