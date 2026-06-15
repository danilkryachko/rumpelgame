#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/gpu_terrain_memory_budget"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

SUMMARY_PATH="$OUT_DIR/gpu-terrain-memory-budget-summary.txt"
LOAD_SCALING_SUMMARY="${RUMPELMC_GPU_MEMORY_BUDGET_LOAD_SCALING_SUMMARY:-"$ROOT_DIR/logs/gpu_terrain_load_scaling_radius16_summary_check/gpu-terrain-load-scaling-summary.txt"}"
UPLOAD_PRESSURE_SUMMARY="${RUMPELMC_GPU_MEMORY_BUDGET_UPLOAD_PRESSURE_SUMMARY:-"$ROOT_DIR/logs/gpu_terrain_upload_pressure_smoke/gpu-upload-pressure-summary.txt"}"
RESOURCE_LIFECYCLE_SUMMARY="${RUMPELMC_GPU_MEMORY_BUDGET_RESOURCE_LIFECYCLE_SUMMARY:-"$ROOT_DIR/logs/gpu_terrain_upload_pressure_smoke/gpu-resource-lifecycle-audit-summary.txt"}"

PACKED_FACE_BYTES="${RUMPELMC_GPU_MEMORY_BUDGET_PACKED_FACE_BYTES:-16}"
MAX_CONFIGURED_TERRAIN_BUFFER_BYTES="${RUMPELMC_GPU_MEMORY_BUDGET_MAX_CONFIGURED_BYTES:-70254592}"
MAX_ACTIVE_TERRAIN_BYTES="${RUMPELMC_GPU_MEMORY_BUDGET_MAX_ACTIVE_BYTES:-4194304}"
MAX_GPU_SUBCHUNKS="${RUMPELMC_GPU_MEMORY_BUDGET_MAX_GPU_SUBCHUNKS:-4096}"
MAX_GPU_DRAWS="${RUMPELMC_GPU_MEMORY_BUDGET_MAX_GPU_DRAWS:-4096}"
MAX_GPU_FACES="${RUMPELMC_GPU_MEMORY_BUDGET_MAX_GPU_FACES:-262144}"
MAX_DRAW_CMD_OCCUPANCY_PCT="${RUMPELMC_GPU_MEMORY_BUDGET_MAX_DRAW_CMD_OCCUPANCY_PCT:-75.0}"
MIN_DRAW_CMD_HEADROOM_BYTES="${RUMPELMC_GPU_MEMORY_BUDGET_MIN_DRAW_CMD_HEADROOM_BYTES:-32768}"
MAX_FRAGMENTATION_PCT="${RUMPELMC_GPU_MEMORY_BUDGET_MAX_FRAGMENTATION_PCT:-1.0}"
MIN_GPU_FREE_RANGES="${RUMPELMC_GPU_MEMORY_BUDGET_MIN_GPU_FREE_RANGES:-1}"
MAX_UPLOAD_FAIL="${RUMPELMC_GPU_MEMORY_BUDGET_MAX_UPLOAD_FAIL:-0}"

mkdir -p "$OUT_DIR"

fail() {
  echo "gpu_terrain_memory_budget: $*" >&2
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
test -s "$UPLOAD_PRESSURE_SUMMARY" || fail "missing upload pressure summary $UPLOAD_PRESSURE_SUMMARY"
test -s "$RESOURCE_LIFECYCLE_SUMMARY" || fail "missing resource lifecycle summary $RESOURCE_LIFECYCLE_SUMMARY"

load_status="$(require_field status "$LOAD_SCALING_SUMMARY")"
upload_status="$(require_field status "$UPLOAD_PRESSURE_SUMMARY")"
resource_status="$(require_field resource_lifecycle_audit_status "$RESOURCE_LIFECYCLE_SUMMARY")"
max_subchunks="$(require_field max_gpu_subchunks "$LOAD_SCALING_SUMMARY")"
max_draws="$(require_field max_gpu_draws "$LOAD_SCALING_SUMMARY")"
max_faces="$(require_field max_gpu_faces "$LOAD_SCALING_SUMMARY")"
draw_cmd_bytes="$(require_field max_gpu_draw_cmd_bytes "$LOAD_SCALING_SUMMARY")"
draw_cmd_capacity_bytes="$(require_field max_gpu_draw_cmd_capacity_bytes "$LOAD_SCALING_SUMMARY")"
upload_fail="$(require_field gpu_upload_fail "$UPLOAD_PRESSURE_SUMMARY")"
upload_fail_capacity="$(require_field gpu_upload_fail_capacity "$UPLOAD_PRESSURE_SUMMARY")"
upload_fail_fragmented="$(require_field gpu_upload_fail_fragmented "$UPLOAD_PRESSURE_SUMMARY")"
fragmentation_pct="$(require_field max_gpu_fragmentation_pct "$UPLOAD_PRESSURE_SUMMARY")"
free_ranges="$(require_field max_gpu_free_ranges "$UPLOAD_PRESSURE_SUMMARY")"
effective_draws="$(require_field max_gpu_effective_draws "$UPLOAD_PRESSURE_SUMMARY")"

awk \
  -v load_status="$load_status" \
  -v upload_status="$upload_status" \
  -v resource_status="$resource_status" \
  -v max_subchunks="$max_subchunks" \
  -v max_draws="$max_draws" \
  -v max_faces="$max_faces" \
  -v draw_cmd_bytes="$draw_cmd_bytes" \
  -v draw_cmd_capacity_bytes="$draw_cmd_capacity_bytes" \
  -v upload_fail="$upload_fail" \
  -v upload_fail_capacity="$upload_fail_capacity" \
  -v upload_fail_fragmented="$upload_fail_fragmented" \
  -v fragmentation_pct="$fragmentation_pct" \
  -v free_ranges="$free_ranges" \
  -v effective_draws="$effective_draws" \
  -v packed_face_bytes="$PACKED_FACE_BYTES" \
  -v max_configured_bytes="$MAX_CONFIGURED_TERRAIN_BUFFER_BYTES" \
  -v max_active_bytes="$MAX_ACTIVE_TERRAIN_BYTES" \
  -v budget_subchunks="$MAX_GPU_SUBCHUNKS" \
  -v budget_draws="$MAX_GPU_DRAWS" \
  -v budget_faces="$MAX_GPU_FACES" \
  -v max_occupancy="$MAX_DRAW_CMD_OCCUPANCY_PCT" \
  -v min_headroom="$MIN_DRAW_CMD_HEADROOM_BYTES" \
  -v max_fragmentation="$MAX_FRAGMENTATION_PCT" \
  -v min_free_ranges="$MIN_GPU_FREE_RANGES" \
  -v max_upload_fail="$MAX_UPLOAD_FAIL" \
  -v load_summary="$LOAD_SCALING_SUMMARY" \
  -v upload_summary="$UPLOAD_PRESSURE_SUMMARY" \
  -v resource_summary="$RESOURCE_LIFECYCLE_SUMMARY" '
  BEGIN {
    active_bytes = max_faces * packed_face_bytes
    configured_bytes = draw_cmd_capacity_bytes + (4194304 * packed_face_bytes)
    draw_cmd_occupancy = 0.0
    if (draw_cmd_capacity_bytes > 0) {
      draw_cmd_occupancy = draw_cmd_bytes * 100.0 / draw_cmd_capacity_bytes
    }
    draw_cmd_headroom = draw_cmd_capacity_bytes - draw_cmd_bytes
    status = "pass"
    reason = "within_budget"
    if (load_status != "pass" || upload_status != "pass" || resource_status != "pass") {
      status = "fail"
      reason = "prerequisite_failed"
    } else if (configured_bytes > max_configured_bytes) {
      status = "fail"
      reason = "configured_buffer_budget"
    } else if (active_bytes > max_active_bytes) {
      status = "fail"
      reason = "active_face_bytes_budget"
    } else if (max_subchunks > budget_subchunks) {
      status = "fail"
      reason = "subchunk_budget"
    } else if (max_draws > budget_draws) {
      status = "fail"
      reason = "draw_budget"
    } else if (max_faces > budget_faces) {
      status = "fail"
      reason = "face_budget"
    } else if (draw_cmd_occupancy > max_occupancy) {
      status = "fail"
      reason = "draw_command_occupancy_budget"
    } else if (draw_cmd_headroom < min_headroom) {
      status = "fail"
      reason = "draw_command_headroom_budget"
    } else if (fragmentation_pct > max_fragmentation) {
      status = "fail"
      reason = "fragmentation_budget"
    } else if (free_ranges < min_free_ranges) {
      status = "fail"
      reason = "free_range_budget"
    } else if (upload_fail > max_upload_fail || upload_fail_capacity > max_upload_fail || upload_fail_fragmented > max_upload_fail) {
      status = "fail"
      reason = "upload_failure_budget"
    }

    printf("gpu_terrain_memory_budget status=%s reason=%s load_status=%s upload_status=%s resource_status=%s max_configured_terrain_buffer_bytes=%d configured_terrain_buffer_bytes=%d max_active_terrain_bytes=%d active_terrain_bytes=%d packed_face_bytes=%d max_gpu_subchunks=%d budget_gpu_subchunks=%d max_gpu_draws=%d budget_gpu_draws=%d max_gpu_faces=%d budget_gpu_faces=%d max_gpu_effective_draws=%d gpu_draw_cmd_bytes=%d gpu_draw_cmd_capacity_bytes=%d gpu_draw_cmd_occupancy_pct=%.3f max_draw_cmd_occupancy_pct=%.3f gpu_draw_cmd_headroom_bytes=%d min_draw_cmd_headroom_bytes=%d max_gpu_fragmentation_pct=%.3f max_fragmentation_pct=%.3f max_gpu_free_ranges=%d min_gpu_free_ranges=%d gpu_upload_fail=%d gpu_upload_fail_capacity=%d gpu_upload_fail_fragmented=%d load_summary=%s upload_summary=%s resource_summary=%s\n", status, reason, load_status, upload_status, resource_status, max_configured_bytes, configured_bytes, max_active_bytes, active_bytes, packed_face_bytes, max_subchunks, budget_subchunks, max_draws, budget_draws, max_faces, budget_faces, effective_draws, draw_cmd_bytes, draw_cmd_capacity_bytes, draw_cmd_occupancy, max_occupancy, draw_cmd_headroom, min_headroom, fragmentation_pct, max_fragmentation, free_ranges, min_free_ranges, upload_fail, upload_fail_capacity, upload_fail_fragmented, load_summary, upload_summary, resource_summary)
    if (status != "pass") {
      exit 1
    }
  }
' > "$SUMMARY_PATH" || {
  cat "$SUMMARY_PATH" >&2 || true
  fail "GPU terrain memory budget failed"
}

cat "$SUMMARY_PATH"
echo "GPU terrain memory budget artifacts: $OUT_DIR"
