#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/gpu_buffer_residency_budget_current"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

SUMMARY_PATH="$OUT_DIR/gpu-buffer-residency-budget-summary.txt"
MASS_CHUNK_LOAD_SUMMARY="${RUMPELMC_GPU_BUFFER_RESIDENCY_MASS_CHUNK_LOAD_SUMMARY:-"$ROOT_DIR/logs/gpu_terrain_mass_chunk_load_current/gpu-terrain-mass-chunk-load-summary.txt"}"
STAGE_POOL_SUMMARY="${RUMPELMC_GPU_BUFFER_RESIDENCY_STAGE_POOL_SUMMARY:-"$ROOT_DIR/logs/gpu_terrain_upload_stage_pool_load_scaling_current/gpu-terrain-upload-stage-pool-load-scaling-summary.txt"}"
GROUPED_DRAWS_SUMMARY="${RUMPELMC_GPU_BUFFER_RESIDENCY_GROUPED_DRAWS_SUMMARY:-"$ROOT_DIR/logs/gpu_terrain_grouped_draws_current/gpu-terrain-grouped-draws-summary.txt"}"
CUTOUT_PRESSURE_SUMMARY="${RUMPELMC_GPU_BUFFER_RESIDENCY_CUTOUT_PRESSURE_SUMMARY:-"$ROOT_DIR/logs/gpu_terrain_cutout_pressure_load_scaling_current/gpu-terrain-cutout-pressure-load-scaling-summary.txt"}"
MEMORY_BUDGET_SUMMARY="${RUMPELMC_GPU_BUFFER_RESIDENCY_MEMORY_BUDGET_SUMMARY:-"$ROOT_DIR/logs/gpu_terrain_memory_budget_current/gpu-terrain-memory-budget-summary.txt"}"

PACKED_FACE_BYTES="${RUMPELMC_GPU_BUFFER_RESIDENCY_PACKED_FACE_BYTES:-16}"
FACE_BUFFER_CAPACITY_FACES="${RUMPELMC_GPU_BUFFER_RESIDENCY_FACE_BUFFER_CAPACITY_FACES:-4194304}"
MAX_CONFIGURED_BUFFER_BYTES="${RUMPELMC_GPU_BUFFER_RESIDENCY_MAX_CONFIGURED_BUFFER_BYTES:-70254592}"
MAX_ACTIVE_FACE_BYTES="${RUMPELMC_GPU_BUFFER_RESIDENCY_MAX_ACTIVE_FACE_BYTES:-4194304}"
MAX_GPU_SUBCHUNKS="${RUMPELMC_GPU_BUFFER_RESIDENCY_MAX_GPU_SUBCHUNKS:-4096}"
MAX_LOGICAL_DRAW_RECORDS="${RUMPELMC_GPU_BUFFER_RESIDENCY_MAX_LOGICAL_DRAW_RECORDS:-4096}"
MAX_SUBMITTED_DRAW_RECORDS="${RUMPELMC_GPU_BUFFER_RESIDENCY_MAX_SUBMITTED_DRAW_RECORDS:-4096}"
MAX_GPU_FACES="${RUMPELMC_GPU_BUFFER_RESIDENCY_MAX_GPU_FACES:-262144}"
MAX_DRAW_CMD_OCCUPANCY_PCT="${RUMPELMC_GPU_BUFFER_RESIDENCY_MAX_DRAW_CMD_OCCUPANCY_PCT:-75.0}"
MIN_DRAW_CMD_HEADROOM_BYTES="${RUMPELMC_GPU_BUFFER_RESIDENCY_MIN_DRAW_CMD_HEADROOM_BYTES:-32768}"
MAX_TERRAIN_QUEUE_MS="${RUMPELMC_GPU_BUFFER_RESIDENCY_MAX_TERRAIN_QUEUE_MS:-6.667}"
MAX_PROCESS_WALL_P95_MS="${RUMPELMC_GPU_BUFFER_RESIDENCY_MAX_PROCESS_WALL_P95_MS:-6.667}"
MAX_GPU_COMPOSITOR_SUBMIT_MS="${RUMPELMC_GPU_BUFFER_RESIDENCY_MAX_GPU_COMPOSITOR_SUBMIT_MS:-6.667}"
MAX_UPLOAD_FAIL="${RUMPELMC_GPU_BUFFER_RESIDENCY_MAX_UPLOAD_FAIL:-0}"
MAX_FRAGMENTATION_PCT="${RUMPELMC_GPU_BUFFER_RESIDENCY_MAX_FRAGMENTATION_PCT:-1.0}"
MIN_GPU_FREE_RANGES="${RUMPELMC_GPU_BUFFER_RESIDENCY_MIN_GPU_FREE_RANGES:-1}"
REQUIRE_ALLOCATOR_EVIDENCE="${RUMPELMC_GPU_BUFFER_RESIDENCY_REQUIRE_ALLOCATOR_EVIDENCE:-0}"

fail() {
  echo "gpu_buffer_residency_budget: $*" >&2
  exit 1
}

relative_path() {
  path="$1"
  case "$path" in
    "$ROOT_DIR"/*) printf '%s\n' "${path#$ROOT_DIR/}" ;;
    *) printf '%s\n' "$path" ;;
  esac
}

normalize_path() {
  path="$1"
  case "$path" in
    /*) printf '%s\n' "$path" ;;
    *) printf '%s\n' "$ROOT_DIR/$path" ;;
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

MASS_CHUNK_LOAD_SUMMARY="$(normalize_path "$MASS_CHUNK_LOAD_SUMMARY")"
STAGE_POOL_SUMMARY="$(normalize_path "$STAGE_POOL_SUMMARY")"
GROUPED_DRAWS_SUMMARY="$(normalize_path "$GROUPED_DRAWS_SUMMARY")"
CUTOUT_PRESSURE_SUMMARY="$(normalize_path "$CUTOUT_PRESSURE_SUMMARY")"
MEMORY_BUDGET_SUMMARY="$(normalize_path "$MEMORY_BUDGET_SUMMARY")"

mkdir -p "$OUT_DIR"

test -s "$MASS_CHUNK_LOAD_SUMMARY" || fail "missing mass chunk-load summary $MASS_CHUNK_LOAD_SUMMARY"
test -s "$STAGE_POOL_SUMMARY" || fail "missing upload stage-pool load-scaling summary $STAGE_POOL_SUMMARY"
test -s "$GROUPED_DRAWS_SUMMARY" || fail "missing grouped draws summary $GROUPED_DRAWS_SUMMARY"
test -s "$CUTOUT_PRESSURE_SUMMARY" || fail "missing cutout pressure summary $CUTOUT_PRESSURE_SUMMARY"

mass_status="$(require_field status "$MASS_CHUNK_LOAD_SUMMARY")"
mass_subchunks="$(require_field max_gpu_subchunks "$MASS_CHUNK_LOAD_SUMMARY")"
mass_draws="$(require_field max_gpu_draws "$MASS_CHUNK_LOAD_SUMMARY")"
mass_faces="$(require_field max_gpu_faces "$MASS_CHUNK_LOAD_SUMMARY")"
mass_draw_cmd_bytes="$(require_field gpu_draw_cmd_bytes "$MASS_CHUNK_LOAD_SUMMARY")"
mass_draw_cmd_capacity_bytes="$(require_field gpu_draw_cmd_capacity_bytes "$MASS_CHUNK_LOAD_SUMMARY")"
mass_draw_cmd_headroom_bytes="$(require_field gpu_draw_cmd_headroom_bytes "$MASS_CHUNK_LOAD_SUMMARY")"
mass_draw_cmd_occupancy_pct="$(require_field gpu_draw_cmd_occupancy_pct "$MASS_CHUNK_LOAD_SUMMARY")"
mass_terrain_queue_ms="$(require_field terrain_queue_max_ms "$MASS_CHUNK_LOAD_SUMMARY")"
mass_process_wall_ms="$(require_field process_wall_p95_ms "$MASS_CHUNK_LOAD_SUMMARY")"
mass_gpu_submit_ms="$(require_field gpu_compositor_submit_max_ms "$MASS_CHUNK_LOAD_SUMMARY")"
mass_upload_fail="$(require_field load_gpu_upload_fail "$MASS_CHUNK_LOAD_SUMMARY")"
mass_upload_fail_capacity="$(require_field load_gpu_upload_fail_capacity "$MASS_CHUNK_LOAD_SUMMARY")"
mass_upload_fail_fragmented="$(require_field load_gpu_upload_fail_fragmented "$MASS_CHUNK_LOAD_SUMMARY")"

stage_status="$(require_field status "$STAGE_POOL_SUMMARY")"
stage_baseline_subchunks="$(require_field baseline_max_gpu_subchunks "$STAGE_POOL_SUMMARY")"
stage_pooled_subchunks="$(require_field pooled_max_gpu_subchunks "$STAGE_POOL_SUMMARY")"
stage_baseline_draws="$(require_field baseline_max_gpu_draws "$STAGE_POOL_SUMMARY")"
stage_pooled_draws="$(require_field pooled_max_gpu_draws "$STAGE_POOL_SUMMARY")"
stage_baseline_faces="$(require_field baseline_max_gpu_faces "$STAGE_POOL_SUMMARY")"
stage_pooled_faces="$(require_field pooled_max_gpu_faces "$STAGE_POOL_SUMMARY")"
stage_baseline_occupancy="$(require_field baseline_draw_cmd_occupancy_pct "$STAGE_POOL_SUMMARY")"
stage_pooled_occupancy="$(require_field pooled_draw_cmd_occupancy_pct "$STAGE_POOL_SUMMARY")"
stage_baseline_queue_ms="$(require_field baseline_terrain_queue_max_ms "$STAGE_POOL_SUMMARY")"
stage_pooled_queue_ms="$(require_field pooled_terrain_queue_max_ms "$STAGE_POOL_SUMMARY")"
stage_baseline_process_ms="$(require_field baseline_process_wall_p95_ms "$STAGE_POOL_SUMMARY")"
stage_pooled_process_ms="$(require_field pooled_process_wall_p95_ms "$STAGE_POOL_SUMMARY")"
stage_baseline_submit_ms="$(require_field baseline_gpu_compositor_submit_max_ms "$STAGE_POOL_SUMMARY")"
stage_pooled_submit_ms="$(require_field pooled_gpu_compositor_submit_max_ms "$STAGE_POOL_SUMMARY")"
stage_baseline_upload_fail="$(require_field baseline_upload_fail "$STAGE_POOL_SUMMARY")"
stage_pooled_upload_fail="$(require_field pooled_upload_fail "$STAGE_POOL_SUMMARY")"
stage_pooled_reuses="$(require_field pooled_stage_pba_reuses "$STAGE_POOL_SUMMARY")"

grouped_status="$(require_field status "$GROUPED_DRAWS_SUMMARY")"
grouped_baseline_subchunks="$(require_field baseline_subchunks "$GROUPED_DRAWS_SUMMARY")"
grouped_subchunks="$(require_field grouped_subchunks "$GROUPED_DRAWS_SUMMARY")"
grouped_baseline_draws="$(require_field baseline_draws "$GROUPED_DRAWS_SUMMARY")"
grouped_draws="$(require_field grouped_draws "$GROUPED_DRAWS_SUMMARY")"
grouped_logical_records="$(require_field grouped_logical_records "$GROUPED_DRAWS_SUMMARY")"
grouped_baseline_faces="$(require_field baseline_faces "$GROUPED_DRAWS_SUMMARY")"
grouped_faces="$(require_field grouped_faces "$GROUPED_DRAWS_SUMMARY")"
grouped_baseline_cmd_bytes="$(require_field baseline_cmd_bytes "$GROUPED_DRAWS_SUMMARY")"
grouped_cmd_bytes="$(require_field grouped_cmd_bytes "$GROUPED_DRAWS_SUMMARY")"
grouped_saved_records="$(require_field grouped_saved_records "$GROUPED_DRAWS_SUMMARY")"
grouped_baseline_queue_ms="$(require_field baseline_terrain_queue_max_ms "$GROUPED_DRAWS_SUMMARY")"
grouped_queue_ms="$(require_field grouped_terrain_queue_max_ms "$GROUPED_DRAWS_SUMMARY")"
grouped_baseline_process_ms="$(require_field baseline_process_wall_p95_ms "$GROUPED_DRAWS_SUMMARY")"
grouped_process_ms="$(require_field grouped_process_wall_p95_ms "$GROUPED_DRAWS_SUMMARY")"
grouped_baseline_submit_ms="$(require_field baseline_gpu_compositor_submit_max_ms "$GROUPED_DRAWS_SUMMARY")"
grouped_submit_ms="$(require_field grouped_gpu_compositor_submit_max_ms "$GROUPED_DRAWS_SUMMARY")"
grouped_baseline_upload_fail="$(require_field baseline_upload_fail "$GROUPED_DRAWS_SUMMARY")"
grouped_upload_fail="$(require_field grouped_upload_fail "$GROUPED_DRAWS_SUMMARY")"
grouped_baseline_ground_misses="$(require_field baseline_ground_misses "$GROUPED_DRAWS_SUMMARY")"
grouped_ground_misses="$(require_field grouped_ground_misses "$GROUPED_DRAWS_SUMMARY")"

cutout_status="$(require_field status "$CUTOUT_PRESSURE_SUMMARY")"
cutout_subchunks="$(require_field max_gpu_subchunks "$CUTOUT_PRESSURE_SUMMARY")"
cutout_draws="$(require_field max_gpu_draws "$CUTOUT_PRESSURE_SUMMARY")"
cutout_faces="$(require_field max_gpu_faces "$CUTOUT_PRESSURE_SUMMARY")"
cutout_occupancy="$(require_field gpu_draw_cmd_occupancy_pct "$CUTOUT_PRESSURE_SUMMARY")"
cutout_queue_ms="$(require_field max_terrain_queue_ms "$CUTOUT_PRESSURE_SUMMARY")"
cutout_process_ms="$(require_field max_process_wall_p95_ms "$CUTOUT_PRESSURE_SUMMARY")"
cutout_submit_ms="$(require_field max_gpu_compositor_submit_ms "$CUTOUT_PRESSURE_SUMMARY")"
cutout_upload_fail="$(require_field gpu_upload_fail "$CUTOUT_PRESSURE_SUMMARY")"
cutout_upload_fail_capacity="$(require_field gpu_upload_fail_capacity "$CUTOUT_PRESSURE_SUMMARY")"
cutout_upload_fail_fragmented="$(require_field gpu_upload_fail_fragmented "$CUTOUT_PRESSURE_SUMMARY")"
cutout_transparent_subchunks="$(require_field transparent_subchunks "$CUTOUT_PRESSURE_SUMMARY")"
cutout_transparent_faces="$(require_field transparent_faces "$CUTOUT_PRESSURE_SUMMARY")"
cutout_uploads="$(require_field transparent_cutout_uploads "$CUTOUT_PRESSURE_SUMMARY")"
cutout_default_change="$(require_field default_runtime_change_allowed "$CUTOUT_PRESSURE_SUMMARY")"

if [ -s "$MEMORY_BUDGET_SUMMARY" ]; then
  memory_summary_status="present"
  memory_status="$(require_field status "$MEMORY_BUDGET_SUMMARY")"
  memory_resource_status="$(require_field resource_status "$MEMORY_BUDGET_SUMMARY")"
  memory_fragmentation_pct="$(require_field max_gpu_fragmentation_pct "$MEMORY_BUDGET_SUMMARY")"
  memory_free_ranges="$(require_field max_gpu_free_ranges "$MEMORY_BUDGET_SUMMARY")"
  memory_upload_fail="$(require_field gpu_upload_fail "$MEMORY_BUDGET_SUMMARY")"
  memory_upload_fail_capacity="$(require_field gpu_upload_fail_capacity "$MEMORY_BUDGET_SUMMARY")"
  memory_upload_fail_fragmented="$(require_field gpu_upload_fail_fragmented "$MEMORY_BUDGET_SUMMARY")"
else
  memory_summary_status="missing"
  memory_status="missing"
  memory_resource_status="missing"
  memory_fragmentation_pct="-1"
  memory_free_ranges="-1"
  memory_upload_fail="0"
  memory_upload_fail_capacity="0"
  memory_upload_fail_fragmented="0"
fi

awk \
  -v mass_status="$mass_status" \
  -v mass_subchunks="$mass_subchunks" \
  -v mass_draws="$mass_draws" \
  -v mass_faces="$mass_faces" \
  -v mass_draw_cmd_bytes="$mass_draw_cmd_bytes" \
  -v mass_draw_cmd_capacity_bytes="$mass_draw_cmd_capacity_bytes" \
  -v mass_draw_cmd_headroom_bytes="$mass_draw_cmd_headroom_bytes" \
  -v mass_draw_cmd_occupancy_pct="$mass_draw_cmd_occupancy_pct" \
  -v mass_terrain_queue_ms="$mass_terrain_queue_ms" \
  -v mass_process_wall_ms="$mass_process_wall_ms" \
  -v mass_gpu_submit_ms="$mass_gpu_submit_ms" \
  -v mass_upload_fail="$mass_upload_fail" \
  -v mass_upload_fail_capacity="$mass_upload_fail_capacity" \
  -v mass_upload_fail_fragmented="$mass_upload_fail_fragmented" \
  -v stage_status="$stage_status" \
  -v stage_baseline_subchunks="$stage_baseline_subchunks" \
  -v stage_pooled_subchunks="$stage_pooled_subchunks" \
  -v stage_baseline_draws="$stage_baseline_draws" \
  -v stage_pooled_draws="$stage_pooled_draws" \
  -v stage_baseline_faces="$stage_baseline_faces" \
  -v stage_pooled_faces="$stage_pooled_faces" \
  -v stage_baseline_occupancy="$stage_baseline_occupancy" \
  -v stage_pooled_occupancy="$stage_pooled_occupancy" \
  -v stage_baseline_queue_ms="$stage_baseline_queue_ms" \
  -v stage_pooled_queue_ms="$stage_pooled_queue_ms" \
  -v stage_baseline_process_ms="$stage_baseline_process_ms" \
  -v stage_pooled_process_ms="$stage_pooled_process_ms" \
  -v stage_baseline_submit_ms="$stage_baseline_submit_ms" \
  -v stage_pooled_submit_ms="$stage_pooled_submit_ms" \
  -v stage_baseline_upload_fail="$stage_baseline_upload_fail" \
  -v stage_pooled_upload_fail="$stage_pooled_upload_fail" \
  -v stage_pooled_reuses="$stage_pooled_reuses" \
  -v grouped_status="$grouped_status" \
  -v grouped_baseline_subchunks="$grouped_baseline_subchunks" \
  -v grouped_subchunks="$grouped_subchunks" \
  -v grouped_baseline_draws="$grouped_baseline_draws" \
  -v grouped_draws="$grouped_draws" \
  -v grouped_logical_records="$grouped_logical_records" \
  -v grouped_baseline_faces="$grouped_baseline_faces" \
  -v grouped_faces="$grouped_faces" \
  -v grouped_baseline_cmd_bytes="$grouped_baseline_cmd_bytes" \
  -v grouped_cmd_bytes="$grouped_cmd_bytes" \
  -v grouped_saved_records="$grouped_saved_records" \
  -v grouped_baseline_queue_ms="$grouped_baseline_queue_ms" \
  -v grouped_queue_ms="$grouped_queue_ms" \
  -v grouped_baseline_process_ms="$grouped_baseline_process_ms" \
  -v grouped_process_ms="$grouped_process_ms" \
  -v grouped_baseline_submit_ms="$grouped_baseline_submit_ms" \
  -v grouped_submit_ms="$grouped_submit_ms" \
  -v grouped_baseline_upload_fail="$grouped_baseline_upload_fail" \
  -v grouped_upload_fail="$grouped_upload_fail" \
  -v grouped_baseline_ground_misses="$grouped_baseline_ground_misses" \
  -v grouped_ground_misses="$grouped_ground_misses" \
  -v cutout_status="$cutout_status" \
  -v cutout_subchunks="$cutout_subchunks" \
  -v cutout_draws="$cutout_draws" \
  -v cutout_faces="$cutout_faces" \
  -v cutout_occupancy="$cutout_occupancy" \
  -v cutout_queue_ms="$cutout_queue_ms" \
  -v cutout_process_ms="$cutout_process_ms" \
  -v cutout_submit_ms="$cutout_submit_ms" \
  -v cutout_upload_fail="$cutout_upload_fail" \
  -v cutout_upload_fail_capacity="$cutout_upload_fail_capacity" \
  -v cutout_upload_fail_fragmented="$cutout_upload_fail_fragmented" \
  -v cutout_transparent_subchunks="$cutout_transparent_subchunks" \
  -v cutout_transparent_faces="$cutout_transparent_faces" \
  -v cutout_uploads="$cutout_uploads" \
  -v cutout_default_change="$cutout_default_change" \
  -v memory_summary_status="$memory_summary_status" \
  -v memory_status="$memory_status" \
  -v memory_resource_status="$memory_resource_status" \
  -v memory_fragmentation_pct="$memory_fragmentation_pct" \
  -v memory_free_ranges="$memory_free_ranges" \
  -v memory_upload_fail="$memory_upload_fail" \
  -v memory_upload_fail_capacity="$memory_upload_fail_capacity" \
  -v memory_upload_fail_fragmented="$memory_upload_fail_fragmented" \
  -v packed_face_bytes="$PACKED_FACE_BYTES" \
  -v face_capacity="$FACE_BUFFER_CAPACITY_FACES" \
  -v budget_configured_bytes="$MAX_CONFIGURED_BUFFER_BYTES" \
  -v budget_active_bytes="$MAX_ACTIVE_FACE_BYTES" \
  -v budget_subchunks="$MAX_GPU_SUBCHUNKS" \
  -v budget_logical_draws="$MAX_LOGICAL_DRAW_RECORDS" \
  -v budget_submitted_draws="$MAX_SUBMITTED_DRAW_RECORDS" \
  -v budget_faces="$MAX_GPU_FACES" \
  -v budget_occupancy="$MAX_DRAW_CMD_OCCUPANCY_PCT" \
  -v budget_headroom="$MIN_DRAW_CMD_HEADROOM_BYTES" \
  -v budget_queue="$MAX_TERRAIN_QUEUE_MS" \
  -v budget_process="$MAX_PROCESS_WALL_P95_MS" \
  -v budget_submit="$MAX_GPU_COMPOSITOR_SUBMIT_MS" \
  -v budget_upload_fail="$MAX_UPLOAD_FAIL" \
  -v budget_fragmentation="$MAX_FRAGMENTATION_PCT" \
  -v budget_free_ranges="$MIN_GPU_FREE_RANGES" \
  -v require_allocator="$REQUIRE_ALLOCATOR_EVIDENCE" \
  -v mass_summary="$MASS_CHUNK_LOAD_SUMMARY" \
  -v stage_summary="$STAGE_POOL_SUMMARY" \
  -v grouped_summary="$GROUPED_DRAWS_SUMMARY" \
  -v cutout_summary="$CUTOUT_PRESSURE_SUMMARY" \
  -v memory_summary="$MEMORY_BUDGET_SUMMARY" '
  function max2(a, b) { return (a + 0.0 > b + 0.0) ? a + 0.0 : b + 0.0 }
  function max4(a, b, c, d) { return max2(max2(a, b), max2(c, d)) }
  function max8(a, b, c, d, e, f, g, h) { return max2(max4(a, b, c, d), max4(e, f, g, h)) }
  function set_fail(why) {
    if (status == "pass") {
      status = "fail"
      reason = why
    }
  }
  function pressure_class(subchunk_pct, occupancy_pct, active_pct, configured_pct) {
    if (subchunk_pct >= 75.0 || occupancy_pct >= 75.0 || active_pct >= 75.0 || configured_pct >= 75.0) return "high"
    if (subchunk_pct >= 50.0 || occupancy_pct >= 50.0 || active_pct >= 50.0 || configured_pct >= 50.0) return "moderate"
    return "low"
  }
  BEGIN {
    status = "pass"
    reason = "within_residency_budget"

    max_subchunks = max8(mass_subchunks, stage_baseline_subchunks, stage_pooled_subchunks, grouped_baseline_subchunks, grouped_subchunks, cutout_subchunks, 0, 0)
    max_logical_draws = max8(mass_draws, stage_baseline_draws, stage_pooled_draws, grouped_baseline_draws, grouped_logical_records, cutout_draws, 0, 0)
    max_submitted_draws = max8(mass_draws, stage_baseline_draws, stage_pooled_draws, grouped_baseline_draws, grouped_draws, cutout_draws, 0, 0)
    max_faces = max8(mass_faces, stage_baseline_faces, stage_pooled_faces, grouped_baseline_faces, grouped_faces, cutout_faces, 0, 0)
    max_draw_cmd_bytes = max2(mass_draw_cmd_bytes, grouped_baseline_cmd_bytes)
    max_draw_cmd_bytes = max2(max_draw_cmd_bytes, grouped_cmd_bytes)
    max_occupancy = max4(mass_draw_cmd_occupancy_pct, stage_baseline_occupancy, stage_pooled_occupancy, cutout_occupancy)
    min_headroom = mass_draw_cmd_headroom_bytes + 0
    max_queue = max8(mass_terrain_queue_ms, stage_baseline_queue_ms, stage_pooled_queue_ms, grouped_baseline_queue_ms, grouped_queue_ms, cutout_queue_ms, 0, 0)
    max_process = max8(mass_process_wall_ms, stage_baseline_process_ms, stage_pooled_process_ms, grouped_baseline_process_ms, grouped_process_ms, cutout_process_ms, 0, 0)
    max_submit = max8(mass_gpu_submit_ms, stage_baseline_submit_ms, stage_pooled_submit_ms, grouped_baseline_submit_ms, grouped_submit_ms, cutout_submit_ms, 0, 0)
    upload_fail_total = mass_upload_fail + mass_upload_fail_capacity + mass_upload_fail_fragmented + stage_baseline_upload_fail + stage_pooled_upload_fail + grouped_baseline_upload_fail + grouped_upload_fail + cutout_upload_fail + cutout_upload_fail_capacity + cutout_upload_fail_fragmented + memory_upload_fail + memory_upload_fail_capacity + memory_upload_fail_fragmented
    ground_miss_total = grouped_baseline_ground_misses + grouped_ground_misses
    configured_bytes = face_capacity * packed_face_bytes + mass_draw_cmd_capacity_bytes
    active_face_bytes = max_faces * packed_face_bytes
    subchunk_budget_pct = max_subchunks * 100.0 / budget_subchunks
    logical_draw_budget_pct = max_logical_draws * 100.0 / budget_logical_draws
    submitted_draw_budget_pct = max_submitted_draws * 100.0 / budget_submitted_draws
    active_face_budget_pct = active_face_bytes * 100.0 / budget_active_bytes
    configured_budget_pct = configured_bytes * 100.0 / budget_configured_bytes
    face_capacity_pct = max_faces * 100.0 / face_capacity
    draw_cmd_headroom_bytes = mass_draw_cmd_capacity_bytes - max_draw_cmd_bytes
    if (draw_cmd_headroom_bytes < min_headroom) min_headroom = draw_cmd_headroom_bytes
    residency_pressure_class = pressure_class(subchunk_budget_pct, max_occupancy, active_face_budget_pct, configured_budget_pct)
    allocator_evidence_status = "missing_optional"
    residency_proof_status = "partial"
    allocator_default_blocker = 1
    if (memory_summary_status == "present" && memory_status == "pass" && memory_resource_status == "pass") {
      allocator_evidence_status = "pass"
      residency_proof_status = "summary_complete"
      allocator_default_blocker = 0
    }
    if (allocator_evidence_status != "pass") {
      reason = "within_summary_budget_allocator_evidence_missing"
    }

    if (mass_status != "pass" || stage_status != "pass" || grouped_status != "pass" || cutout_status != "pass") {
      set_fail("prerequisite_status")
    } else if (memory_summary_status == "present" && (memory_status != "pass" || memory_resource_status != "pass")) {
      set_fail("allocator_memory_budget_status")
    } else if (require_allocator != 0 && allocator_evidence_status != "pass") {
      set_fail("allocator_free_range_evidence")
    } else if (configured_bytes > budget_configured_bytes) {
      set_fail("configured_buffer_bytes")
    } else if (active_face_bytes > budget_active_bytes) {
      set_fail("active_face_bytes")
    } else if (max_subchunks > budget_subchunks) {
      set_fail("resident_subchunks")
    } else if (max_logical_draws > budget_logical_draws) {
      set_fail("logical_draw_records")
    } else if (max_submitted_draws > budget_submitted_draws) {
      set_fail("submitted_draw_records")
    } else if (max_faces > budget_faces) {
      set_fail("resident_faces")
    } else if (max_occupancy > budget_occupancy) {
      set_fail("draw_command_occupancy")
    } else if (min_headroom < budget_headroom) {
      set_fail("draw_command_headroom")
    } else if (max_queue > budget_queue) {
      set_fail("terrain_queue_budget")
    } else if (max_process > budget_process) {
      set_fail("process_wall_budget")
    } else if (max_submit > budget_submit) {
      set_fail("gpu_submit_budget")
    } else if (upload_fail_total > budget_upload_fail) {
      set_fail("upload_failure_budget")
    } else if (allocator_evidence_status == "pass" && memory_fragmentation_pct > budget_fragmentation) {
      set_fail("allocator_fragmentation")
    } else if (allocator_evidence_status == "pass" && memory_free_ranges < budget_free_ranges) {
      set_fail("allocator_free_ranges")
    } else if (ground_miss_total != 0) {
      set_fail("ground_misses")
    } else if (cutout_default_change != "0") {
      set_fail("unexpected_default_runtime_change")
    }

    printf("gpu_buffer_residency_budget status=%s reason=%s budget_policy=classify_budget_stream residency_pressure_class=%s residency_proof_status=%s allocator_evidence_status=%s allocator_memory_budget_status=%s allocator_resource_status=%s max_allocator_fragmentation_pct=%.3f budget_allocator_fragmentation_pct=%.3f max_allocator_free_ranges=%d budget_min_allocator_free_ranges=%d requires_allocator_free_range_evidence_before_default=%d mass_status=%s stage_pool_status=%s grouped_draws_status=%s cutout_pressure_status=%s max_configured_buffer_bytes=%d configured_buffer_bytes=%d configured_buffer_budget_pct=%.3f face_buffer_capacity_faces=%d packed_face_bytes=%d max_active_face_bytes=%d active_face_bytes=%d active_face_budget_pct=%.3f max_gpu_subchunks=%d budget_gpu_subchunks=%d subchunk_budget_pct=%.3f max_logical_draw_records=%d budget_logical_draw_records=%d logical_draw_budget_pct=%.3f max_submitted_draw_records=%d budget_submitted_draw_records=%d submitted_draw_budget_pct=%.3f max_gpu_faces=%d budget_gpu_faces=%d face_capacity_pct=%.3f max_draw_cmd_bytes=%d gpu_draw_cmd_capacity_bytes=%d max_draw_cmd_occupancy_pct=%.3f budget_draw_cmd_occupancy_pct=%.3f min_draw_cmd_headroom_bytes=%d budget_min_draw_cmd_headroom_bytes=%d max_terrain_queue_ms=%.3f budget_terrain_queue_ms=%.3f max_process_wall_p95_ms=%.3f budget_process_wall_p95_ms=%.3f max_gpu_compositor_submit_ms=%.3f budget_gpu_compositor_submit_ms=%.3f upload_fail_total=%d max_upload_fail=%d ground_miss_total=%d stage_pool_reuses=%d grouped_saved_records=%d cutout_transparent_subchunks=%d cutout_transparent_faces=%d cutout_uploads=%d default_runtime_change_allowed=0 active_repack_allowed=0 active_eviction_policy_change_allowed=0 local_fps_status=report_only godot_gpu_timestamp_status=report_only external_profile_status=pending_external_profiler requires_external_profiler_before_default=1 requires_mac_windows_validation=1 mass_summary=%s stage_pool_summary=%s grouped_draws_summary=%s cutout_pressure_summary=%s memory_budget_summary=%s\n", status, reason, residency_pressure_class, residency_proof_status, allocator_evidence_status, memory_status, memory_resource_status, memory_fragmentation_pct, budget_fragmentation, memory_free_ranges, budget_free_ranges, allocator_default_blocker, mass_status, stage_status, grouped_status, cutout_status, budget_configured_bytes, configured_bytes, configured_budget_pct, face_capacity, packed_face_bytes, budget_active_bytes, active_face_bytes, active_face_budget_pct, max_subchunks, budget_subchunks, subchunk_budget_pct, max_logical_draws, budget_logical_draws, logical_draw_budget_pct, max_submitted_draws, budget_submitted_draws, submitted_draw_budget_pct, max_faces, budget_faces, face_capacity_pct, max_draw_cmd_bytes, mass_draw_cmd_capacity_bytes, max_occupancy, budget_occupancy, min_headroom, budget_headroom, max_queue, budget_queue, max_process, budget_process, max_submit, budget_submit, upload_fail_total, budget_upload_fail, ground_miss_total, stage_pooled_reuses, grouped_saved_records, cutout_transparent_subchunks, cutout_transparent_faces, cutout_uploads, mass_summary, stage_summary, grouped_summary, cutout_summary, memory_summary)
    printf("gpu_buffer_residency_source name=mass_chunk_load status=%s gpu_subchunks=%d logical_draw_records=%d submitted_draw_records=%d gpu_faces=%d draw_cmd_bytes=%d draw_cmd_occupancy_pct=%.3f terrain_queue_ms=%.3f process_wall_p95_ms=%.3f gpu_submit_ms=%.3f upload_fail=%d summary=%s\n", mass_status, mass_subchunks, mass_draws, mass_draws, mass_faces, mass_draw_cmd_bytes, mass_draw_cmd_occupancy_pct, mass_terrain_queue_ms, mass_process_wall_ms, mass_gpu_submit_ms, mass_upload_fail + mass_upload_fail_capacity + mass_upload_fail_fragmented, mass_summary)
    printf("gpu_buffer_residency_source name=stage_pool_pressure status=%s gpu_subchunks=%d logical_draw_records=%d submitted_draw_records=%d gpu_faces=%d draw_cmd_bytes=n/a draw_cmd_occupancy_pct=%.3f terrain_queue_ms=%.3f process_wall_p95_ms=%.3f gpu_submit_ms=%.3f upload_fail=%d stage_pool_reuses=%d summary=%s\n", stage_status, max2(stage_baseline_subchunks, stage_pooled_subchunks), max2(stage_baseline_draws, stage_pooled_draws), max2(stage_baseline_draws, stage_pooled_draws), max2(stage_baseline_faces, stage_pooled_faces), max2(stage_baseline_occupancy, stage_pooled_occupancy), max2(stage_baseline_queue_ms, stage_pooled_queue_ms), max2(stage_baseline_process_ms, stage_pooled_process_ms), max2(stage_baseline_submit_ms, stage_pooled_submit_ms), stage_baseline_upload_fail + stage_pooled_upload_fail, stage_pooled_reuses, stage_summary)
    printf("gpu_buffer_residency_source name=grouped_draws_pressure status=%s gpu_subchunks=%d logical_draw_records=%d submitted_draw_records=%d gpu_faces=%d draw_cmd_bytes=%d draw_cmd_occupancy_pct=derived terrain_queue_ms=%.3f process_wall_p95_ms=%.3f gpu_submit_ms=%.3f upload_fail=%d grouped_saved_records=%d summary=%s\n", grouped_status, max2(grouped_baseline_subchunks, grouped_subchunks), max2(grouped_baseline_draws, grouped_logical_records), max2(grouped_baseline_draws, grouped_draws), max2(grouped_baseline_faces, grouped_faces), max2(grouped_baseline_cmd_bytes, grouped_cmd_bytes), max2(grouped_baseline_queue_ms, grouped_queue_ms), max2(grouped_baseline_process_ms, grouped_process_ms), max2(grouped_baseline_submit_ms, grouped_submit_ms), grouped_baseline_upload_fail + grouped_upload_fail, grouped_saved_records, grouped_summary)
    printf("gpu_buffer_residency_source name=cutout_pressure status=%s gpu_subchunks=%d logical_draw_records=%d submitted_draw_records=%d gpu_faces=%d draw_cmd_bytes=n/a draw_cmd_occupancy_pct=%.3f terrain_queue_ms=%.3f process_wall_p95_ms=%.3f gpu_submit_ms=%.3f upload_fail=%d transparent_subchunks=%d transparent_faces=%d cutout_uploads=%d summary=%s\n", cutout_status, cutout_subchunks, cutout_draws, cutout_draws, cutout_faces, cutout_occupancy, cutout_queue_ms, cutout_process_ms, cutout_submit_ms, cutout_upload_fail + cutout_upload_fail_capacity + cutout_upload_fail_fragmented, cutout_transparent_subchunks, cutout_transparent_faces, cutout_uploads, cutout_summary)
    if (status != "pass") {
      exit 1
    }
  }
' > "$SUMMARY_PATH" || {
  cat "$SUMMARY_PATH" >&2 || true
  fail "GPU buffer residency budget failed"
}

cat "$SUMMARY_PATH"
echo "GPU buffer residency budget artifacts: $OUT_DIR"
