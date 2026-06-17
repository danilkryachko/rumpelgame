#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/gpu_terrain_mass_chunk_load_current"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

SUMMARY_PATH="$OUT_DIR/gpu-terrain-mass-chunk-load-summary.txt"
LOAD_SCALING_SUMMARY="${RUMPELMC_GPU_MASS_LOAD_SCALING_SUMMARY:-"$ROOT_DIR/logs/gpu_terrain_load_scaling_radius16_summary_check/gpu-terrain-load-scaling-summary.txt"}"
UPLOAD_BUDGET_SUMMARY="${RUMPELMC_GPU_MASS_LOAD_UPLOAD_BUDGET_SUMMARY:-"$ROOT_DIR/logs/gpu_terrain_upload_budget_current/gpu-terrain-upload-budget-summary.txt"}"

MIN_GPU_SUBCHUNKS="${RUMPELMC_GPU_MASS_LOAD_MIN_GPU_SUBCHUNKS:-2000}"
MIN_GPU_DRAWS="${RUMPELMC_GPU_MASS_LOAD_MIN_GPU_DRAWS:-2000}"
MIN_GPU_FACES="${RUMPELMC_GPU_MASS_LOAD_MIN_GPU_FACES:-3000}"
MIN_DRAW_CMD_OCCUPANCY_PCT="${RUMPELMC_GPU_MASS_LOAD_MIN_DRAW_CMD_OCCUPANCY_PCT:-25.0}"
MAX_TERRAIN_QUEUE_MS="${RUMPELMC_GPU_MASS_LOAD_MAX_TERRAIN_QUEUE_MS:-6.667}"
MAX_PROCESS_WALL_P95_MS="${RUMPELMC_GPU_MASS_LOAD_MAX_PROCESS_WALL_P95_MS:-6.667}"
MAX_GPU_COMPOSITOR_SUBMIT_MS="${RUMPELMC_GPU_MASS_LOAD_MAX_GPU_COMPOSITOR_SUBMIT_MS:-6.667}"
MAX_UPLOAD_FAIL="${RUMPELMC_GPU_MASS_LOAD_MAX_UPLOAD_FAIL:-0}"

mkdir -p "$OUT_DIR"

fail() {
  echo "gpu_terrain_mass_chunk_load_gate: $*" >&2
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

test -s "$LOAD_SCALING_SUMMARY" || fail "missing load scaling summary $LOAD_SCALING_SUMMARY"
test -s "$UPLOAD_BUDGET_SUMMARY" || fail "missing upload budget summary $UPLOAD_BUDGET_SUMMARY"

load_status="$(require_field status "$LOAD_SCALING_SUMMARY")"
load_source_status="$(require_field source_status "$LOAD_SCALING_SUMMARY")"
load_subchunks="$(require_field max_gpu_subchunks "$LOAD_SCALING_SUMMARY")"
load_draws="$(require_field max_gpu_draws "$LOAD_SCALING_SUMMARY")"
load_faces="$(require_field max_gpu_faces "$LOAD_SCALING_SUMMARY")"
draw_cmd_bytes="$(require_field max_gpu_draw_cmd_bytes "$LOAD_SCALING_SUMMARY")"
draw_cmd_capacity_bytes="$(require_field max_gpu_draw_cmd_capacity_bytes "$LOAD_SCALING_SUMMARY")"
draw_cmd_occupancy_pct="$(require_field gpu_draw_cmd_occupancy_pct "$LOAD_SCALING_SUMMARY")"
draw_cmd_headroom_bytes="$(require_field gpu_draw_cmd_headroom_bytes "$LOAD_SCALING_SUMMARY")"
terrain_queue_max="$(require_field max_terrain_queue_ms "$LOAD_SCALING_SUMMARY")"
process_wall_p95="$(require_field max_process_wall_p95_ms "$LOAD_SCALING_SUMMARY")"
gpu_submit_max="$(require_field max_gpu_compositor_submit_ms "$LOAD_SCALING_SUMMARY")"
load_upload_fail="$(require_field gpu_upload_fail "$LOAD_SCALING_SUMMARY")"
load_upload_fail_capacity="$(require_field gpu_upload_fail_capacity "$LOAD_SCALING_SUMMARY")"
load_upload_fail_fragmented="$(require_field gpu_upload_fail_fragmented "$LOAD_SCALING_SUMMARY")"
load_source_summary="$(require_field source_summary "$LOAD_SCALING_SUMMARY")"

upload_budget_status="$(require_field status "$UPLOAD_BUDGET_SUMMARY")"
upload_budget_reason="$(require_field reason "$UPLOAD_BUDGET_SUMMARY")"
movement_budget_status="$(require_field movement_budget_status "$UPLOAD_BUDGET_SUMMARY")"
in_place_status="$(require_field in_place_status "$UPLOAD_BUDGET_SUMMARY")"
max_uploads_per_frame="$(require_field max_uploads_per_frame "$UPLOAD_BUDGET_SUMMARY")"
movement_uploads_max="$(require_field movement_uploads_max "$UPLOAD_BUDGET_SUMMARY")"
max_upload_kb_per_frame="$(require_field max_upload_kb_per_frame "$UPLOAD_BUDGET_SUMMARY")"
movement_upload_kb_max="$(require_field movement_upload_kb_max "$UPLOAD_BUDGET_SUMMARY")"
max_new_slot_uploads_per_frame="$(require_field max_new_slot_uploads_per_frame "$UPLOAD_BUDGET_SUMMARY")"
movement_new_slot_uploads_max="$(require_field movement_new_slot_uploads_max "$UPLOAD_BUDGET_SUMMARY")"
in_place_new_slot_uploads_max="$(require_field in_place_new_slot_uploads_max "$UPLOAD_BUDGET_SUMMARY")"
max_replace_slot_uploads_per_frame="$(require_field max_replace_slot_uploads_per_frame "$UPLOAD_BUDGET_SUMMARY")"
movement_replace_slot_uploads_max="$(require_field movement_replace_slot_uploads_max "$UPLOAD_BUDGET_SUMMARY")"
in_place_replace_slot_uploads_max="$(require_field in_place_replace_slot_uploads_max "$UPLOAD_BUDGET_SUMMARY")"
movement_upload_fail="$(require_field movement_upload_fail "$UPLOAD_BUDGET_SUMMARY")"
movement_upload_fail_capacity="$(require_field movement_upload_fail_capacity "$UPLOAD_BUDGET_SUMMARY")"
movement_upload_fail_fragmented="$(require_field movement_upload_fail_fragmented "$UPLOAD_BUDGET_SUMMARY")"
in_place_upload_fail="$(require_field in_place_upload_fail "$UPLOAD_BUDGET_SUMMARY")"
in_place_upload_fail_capacity="$(require_field in_place_upload_fail_capacity "$UPLOAD_BUDGET_SUMMARY")"
in_place_upload_fail_fragmented="$(require_field in_place_upload_fail_fragmented "$UPLOAD_BUDGET_SUMMARY")"

awk \
  -v load_status="$load_status" \
  -v load_source_status="$load_source_status" \
  -v load_subchunks="$load_subchunks" \
  -v load_draws="$load_draws" \
  -v load_faces="$load_faces" \
  -v draw_cmd_bytes="$draw_cmd_bytes" \
  -v draw_cmd_capacity_bytes="$draw_cmd_capacity_bytes" \
  -v draw_cmd_occupancy_pct="$draw_cmd_occupancy_pct" \
  -v draw_cmd_headroom_bytes="$draw_cmd_headroom_bytes" \
  -v terrain_queue_max="$terrain_queue_max" \
  -v process_wall_p95="$process_wall_p95" \
  -v gpu_submit_max="$gpu_submit_max" \
  -v load_upload_fail="$load_upload_fail" \
  -v load_upload_fail_capacity="$load_upload_fail_capacity" \
  -v load_upload_fail_fragmented="$load_upload_fail_fragmented" \
  -v upload_budget_status="$upload_budget_status" \
  -v upload_budget_reason="$upload_budget_reason" \
  -v movement_budget_status="$movement_budget_status" \
  -v in_place_status="$in_place_status" \
  -v max_uploads_per_frame="$max_uploads_per_frame" \
  -v movement_uploads_max="$movement_uploads_max" \
  -v max_upload_kb_per_frame="$max_upload_kb_per_frame" \
  -v movement_upload_kb_max="$movement_upload_kb_max" \
  -v max_new_slot_uploads_per_frame="$max_new_slot_uploads_per_frame" \
  -v movement_new_slot_uploads_max="$movement_new_slot_uploads_max" \
  -v in_place_new_slot_uploads_max="$in_place_new_slot_uploads_max" \
  -v max_replace_slot_uploads_per_frame="$max_replace_slot_uploads_per_frame" \
  -v movement_replace_slot_uploads_max="$movement_replace_slot_uploads_max" \
  -v in_place_replace_slot_uploads_max="$in_place_replace_slot_uploads_max" \
  -v movement_upload_fail="$movement_upload_fail" \
  -v movement_upload_fail_capacity="$movement_upload_fail_capacity" \
  -v movement_upload_fail_fragmented="$movement_upload_fail_fragmented" \
  -v in_place_upload_fail="$in_place_upload_fail" \
  -v in_place_upload_fail_capacity="$in_place_upload_fail_capacity" \
  -v in_place_upload_fail_fragmented="$in_place_upload_fail_fragmented" \
  -v min_subchunks="$MIN_GPU_SUBCHUNKS" \
  -v min_draws="$MIN_GPU_DRAWS" \
  -v min_faces="$MIN_GPU_FACES" \
  -v min_occupancy="$MIN_DRAW_CMD_OCCUPANCY_PCT" \
  -v max_terrain_queue="$MAX_TERRAIN_QUEUE_MS" \
  -v max_process_wall="$MAX_PROCESS_WALL_P95_MS" \
  -v max_gpu_submit="$MAX_GPU_COMPOSITOR_SUBMIT_MS" \
  -v max_upload_fail="$MAX_UPLOAD_FAIL" \
  -v load_source_summary="$load_source_summary" \
  -v load_summary="$LOAD_SCALING_SUMMARY" \
  -v upload_budget_summary="$UPLOAD_BUDGET_SUMMARY" '
  function set_fail(why) {
    if (status == "pass") {
      status = "fail"
      reason = why
    }
  }
  BEGIN {
    status = "pass"
    reason = "mass_load_within_budget"
    load_fail_total = load_upload_fail + load_upload_fail_capacity + load_upload_fail_fragmented
    budget_fail_total = movement_upload_fail + movement_upload_fail_capacity + movement_upload_fail_fragmented + in_place_upload_fail + in_place_upload_fail_capacity + in_place_upload_fail_fragmented

    if (load_status != "pass" || load_source_status != "pass") {
      set_fail("load_scaling_prerequisite")
    } else if (upload_budget_status != "pass" || movement_budget_status != "pass" || in_place_status != "pass") {
      set_fail("upload_budget_prerequisite")
    } else if (load_subchunks + 0 < min_subchunks + 0) {
      set_fail("mass_subchunk_pressure")
    } else if (load_draws + 0 < min_draws + 0) {
      set_fail("mass_draw_pressure")
    } else if (load_faces + 0 < min_faces + 0) {
      set_fail("mass_face_pressure")
    } else if (draw_cmd_occupancy_pct + 0.0 < min_occupancy + 0.0) {
      set_fail("draw_command_occupancy")
    } else if (terrain_queue_max + 0.0 > max_terrain_queue + 0.0) {
      set_fail("terrain_queue_budget")
    } else if (process_wall_p95 + 0.0 > max_process_wall + 0.0) {
      set_fail("process_wall_budget")
    } else if (gpu_submit_max + 0.0 > max_gpu_submit + 0.0) {
      set_fail("gpu_submit_budget")
    } else if (load_fail_total > max_upload_fail + 0 || budget_fail_total > max_upload_fail + 0) {
      set_fail("upload_failure_budget")
    }

    printf("gpu_terrain_mass_chunk_load status=%s reason=%s load_status=%s load_source_status=%s upload_budget_status=%s upload_budget_reason=%s movement_budget_status=%s in_place_status=%s min_gpu_subchunks=%d max_gpu_subchunks=%d min_gpu_draws=%d max_gpu_draws=%d min_gpu_faces=%d max_gpu_faces=%d min_draw_cmd_occupancy_pct=%.1f gpu_draw_cmd_occupancy_pct=%.3f gpu_draw_cmd_bytes=%d gpu_draw_cmd_capacity_bytes=%d gpu_draw_cmd_headroom_bytes=%d max_terrain_queue_ms=%.3f terrain_queue_max_ms=%.3f max_process_wall_p95_ms=%.3f process_wall_p95_ms=%.3f max_gpu_compositor_submit_ms=%.3f gpu_compositor_submit_max_ms=%.3f max_upload_fail=%d load_gpu_upload_fail=%d load_gpu_upload_fail_capacity=%d load_gpu_upload_fail_fragmented=%d movement_upload_fail=%d movement_upload_fail_capacity=%d movement_upload_fail_fragmented=%d in_place_upload_fail=%d in_place_upload_fail_capacity=%d in_place_upload_fail_fragmented=%d max_uploads_per_frame=%s movement_uploads_max=%s max_upload_kb_per_frame=%.3f movement_upload_kb_max=%.3f max_new_slot_uploads_per_frame=%s movement_new_slot_uploads_max=%s in_place_new_slot_uploads_max=%s max_replace_slot_uploads_per_frame=%s movement_replace_slot_uploads_max=%s in_place_replace_slot_uploads_max=%s load_source_summary=%s load_summary=%s upload_budget_summary=%s\n", status, reason, load_status, load_source_status, upload_budget_status, upload_budget_reason, movement_budget_status, in_place_status, min_subchunks, load_subchunks, min_draws, load_draws, min_faces, load_faces, min_occupancy, draw_cmd_occupancy_pct, draw_cmd_bytes, draw_cmd_capacity_bytes, draw_cmd_headroom_bytes, max_terrain_queue, terrain_queue_max, max_process_wall, process_wall_p95, max_gpu_submit, gpu_submit_max, max_upload_fail, load_upload_fail, load_upload_fail_capacity, load_upload_fail_fragmented, movement_upload_fail, movement_upload_fail_capacity, movement_upload_fail_fragmented, in_place_upload_fail, in_place_upload_fail_capacity, in_place_upload_fail_fragmented, max_uploads_per_frame, movement_uploads_max, max_upload_kb_per_frame + 0.0, movement_upload_kb_max + 0.0, max_new_slot_uploads_per_frame, movement_new_slot_uploads_max, in_place_new_slot_uploads_max, max_replace_slot_uploads_per_frame, movement_replace_slot_uploads_max, in_place_replace_slot_uploads_max, load_source_summary, load_summary, upload_budget_summary)
    if (status != "pass") {
      exit 1
    }
  }
' > "$SUMMARY_PATH" || {
  cat "$SUMMARY_PATH" >&2 || true
  fail "GPU terrain mass chunk-load gate failed"
}

cat "$SUMMARY_PATH"
echo "GPU terrain mass chunk-load artifacts: $OUT_DIR"
