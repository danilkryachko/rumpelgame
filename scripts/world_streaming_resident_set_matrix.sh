#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/world_streaming_resident_set_matrix"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

SUMMARY_PATH="$OUT_DIR/resident-set-matrix-summary.txt"
RADII="${RUMPELMC_RESIDENT_SET_MATRIX_RADII:-16}"
RUN_MATRIX="${RUMPELMC_RESIDENT_SET_MATRIX_RUN:-0}"
MIN_GPU_DRAWS="${RUMPELMC_RESIDENT_SET_MATRIX_MIN_GPU_DRAWS:-2000}"
MIN_DRAW_CMD_OCCUPANCY_PCT="${RUMPELMC_RESIDENT_SET_MATRIX_MIN_DRAW_CMD_OCCUPANCY_PCT:-25.0}"

mkdir -p "$OUT_DIR"

fail() {
  echo "world_streaming_resident_set_matrix: $*" >&2
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

summary_for_radius() {
  radius="$1"
  if [ "$RUN_MATRIX" = "1" ]; then
    radius_dir="$OUT_DIR/radius-$radius"
    RUMPELMC_RESIDENT_SET_SERVER_VIEW_DISTANCE="$radius" \
      RUMPELMC_RESIDENT_SET_CLIENT_KEEP_CHUNK_DISTANCE="$radius" \
      /bin/sh "$ROOT_DIR/scripts/world_streaming_resident_set_growth.sh" "$radius_dir" > "$radius_dir.run.txt" 2>&1 || {
        cat "$radius_dir.run.txt" >&2 || true
        fail "resident-set growth failed for radius $radius"
      }
    printf '%s/resident-set-growth-summary.txt\n' "$radius_dir"
    return
  fi

  if [ "$radius" = "16" ]; then
    printf '%s/logs/world_streaming_resident_set_growth_radius16_check/resident-set-growth-summary.txt\n' "$ROOT_DIR"
  else
    printf '%s/logs/world_streaming_resident_set_growth_radius%s_check/resident-set-growth-summary.txt\n' "$ROOT_DIR" "$radius"
  fi
}

case "$RUN_MATRIX" in
  0|1) ;;
  *)
    fail "unsupported RUMPELMC_RESIDENT_SET_MATRIX_RUN=$RUN_MATRIX"
    ;;
esac

rows_path="$OUT_DIR/resident-set-matrix-rows.txt"
rm -f "$SUMMARY_PATH" "$rows_path"

for radius in $RADII; do
  case "$radius" in
    ''|*[!0-9]*)
      fail "radius must be a positive integer: $radius"
      ;;
  esac
  if [ "$radius" -le 0 ]; then
    fail "radius must be greater than 0: $radius"
  fi

  source_summary="$(summary_for_radius "$radius")"
  test -s "$source_summary" || fail "missing resident-set summary for radius $radius: $source_summary"

  status="$(field_metric status "$source_summary")"
  server_view_distance="$(field_metric server_view_distance "$source_summary")"
  client_keep_distance="$(field_metric client_keep_chunk_distance "$source_summary")"
  max_subchunks="$(field_metric max_gpu_subchunks "$source_summary")"
  max_draws="$(field_metric max_gpu_draws "$source_summary")"
  max_faces="$(field_metric max_gpu_faces "$source_summary")"
  draw_cmd_bytes="$(field_metric max_gpu_draw_cmd_bytes "$source_summary")"
  draw_cmd_capacity="$(field_metric max_gpu_draw_cmd_capacity_bytes "$source_summary")"
  terrain_queue_max="$(field_metric max_terrain_queue_ms "$source_summary")"
  process_wall_p95="$(field_metric max_process_wall_p95_ms "$source_summary")"
  gpu_submit_max="$(field_metric max_gpu_compositor_submit_ms "$source_summary")"
  upload_fail="$(field_metric gpu_upload_fail "$source_summary")"
  upload_fail_capacity="$(field_metric gpu_upload_fail_capacity "$source_summary")"
  upload_fail_fragmented="$(field_metric gpu_upload_fail_fragmented "$source_summary")"

  awk \
    -v radius="$radius" \
    -v status="${status:-missing}" \
    -v server_view_distance="${server_view_distance:-0}" \
    -v client_keep_distance="${client_keep_distance:-0}" \
    -v max_subchunks="${max_subchunks:-0}" \
    -v max_draws="${max_draws:-0}" \
    -v max_faces="${max_faces:-0}" \
    -v draw_cmd_bytes="${draw_cmd_bytes:-0}" \
    -v draw_cmd_capacity="${draw_cmd_capacity:-0}" \
    -v terrain_queue_max="${terrain_queue_max:-0}" \
    -v process_wall_p95="${process_wall_p95:-0}" \
    -v gpu_submit_max="${gpu_submit_max:-0}" \
    -v upload_fail="${upload_fail:-1}" \
    -v upload_fail_capacity="${upload_fail_capacity:-1}" \
    -v upload_fail_fragmented="${upload_fail_fragmented:-1}" \
    -v source_summary="$source_summary" '
    BEGIN {
      occupancy = 0.0
      headroom = draw_cmd_capacity - draw_cmd_bytes
      if (draw_cmd_capacity > 0) {
        occupancy = draw_cmd_bytes * 100.0 / draw_cmd_capacity
      }
      printf("resident_set_matrix_row radius=%s source_status=%s server_view_distance=%s client_keep_chunk_distance=%s max_gpu_subchunks=%d max_gpu_draws=%d max_gpu_faces=%d max_gpu_draw_cmd_bytes=%d max_gpu_draw_cmd_capacity_bytes=%d gpu_draw_cmd_occupancy_pct=%.3f gpu_draw_cmd_headroom_bytes=%d max_terrain_queue_ms=%.3f max_process_wall_p95_ms=%.3f max_gpu_compositor_submit_ms=%.3f gpu_upload_fail=%d gpu_upload_fail_capacity=%d gpu_upload_fail_fragmented=%d source_summary=%s\n", radius, status, server_view_distance, client_keep_distance, max_subchunks, max_draws, max_faces, draw_cmd_bytes, draw_cmd_capacity, occupancy, headroom, terrain_queue_max, process_wall_p95, gpu_submit_max, upload_fail, upload_fail_capacity, upload_fail_fragmented, source_summary)
    }
  ' >> "$rows_path"
done

awk \
  -v radii="$RADII" \
  -v run_matrix="$RUN_MATRIX" \
  -v min_gpu_draws="$MIN_GPU_DRAWS" \
  -v min_occupancy="$MIN_DRAW_CMD_OCCUPANCY_PCT" '
  {
    rows++
    radius = value_of("radius")
    source_status = value_of("source_status")
    draws = value_of("max_gpu_draws") + 0
    subchunks = value_of("max_gpu_subchunks") + 0
    faces = value_of("max_gpu_faces") + 0
    occupancy = value_of("gpu_draw_cmd_occupancy_pct") + 0.0
    headroom = value_of("gpu_draw_cmd_headroom_bytes") + 0
    terrain_queue = value_of("max_terrain_queue_ms") + 0.0
    process_wall = value_of("max_process_wall_p95_ms") + 0.0
    gpu_submit = value_of("max_gpu_compositor_submit_ms") + 0.0
    upload_fail += value_of("gpu_upload_fail") + 0
    upload_fail_capacity += value_of("gpu_upload_fail_capacity") + 0
    upload_fail_fragmented += value_of("gpu_upload_fail_fragmented") + 0
    if (source_status != "pass") {
      source_fail++
    }
    if (draws > max_draws) {
      max_draws = draws
      best_radius = radius
    }
    if (subchunks > max_subchunks) max_subchunks = subchunks
    if (faces > max_faces) max_faces = faces
    if (occupancy > max_occupancy) max_occupancy = occupancy
    if (rows == 1 || headroom < min_headroom) min_headroom = headroom
    if (terrain_queue > max_terrain_queue) max_terrain_queue = terrain_queue
    if (process_wall > max_process_wall) max_process_wall = process_wall
    if (gpu_submit > max_gpu_submit) max_gpu_submit = gpu_submit
  }
  END {
    status = "pass"
    reason = "ok"
    if (rows == 0) {
      status = "fail"
      reason = "no_rows"
    } else if (source_fail > 0) {
      status = "fail"
      reason = "source_not_pass"
    } else if (upload_fail > 0 || upload_fail_capacity > 0 || upload_fail_fragmented > 0) {
      status = "fail"
      reason = "upload_failure"
    } else if (max_draws < min_gpu_draws) {
      status = "fail"
      reason = "draw_pressure_too_low"
    } else if (max_occupancy < min_occupancy) {
      status = "fail"
      reason = "draw_command_occupancy_too_low"
    }
    printf("resident_set_matrix status=%s reason=%s mode=%s radii=\"%s\" rows=%d min_gpu_draws=%d min_draw_cmd_occupancy_pct=%.1f best_radius=%s max_gpu_subchunks=%d max_gpu_draws=%d max_gpu_faces=%d max_draw_cmd_occupancy_pct=%.3f min_draw_cmd_headroom_bytes=%d max_terrain_queue_ms=%.3f max_process_wall_p95_ms=%.3f max_gpu_compositor_submit_ms=%.3f gpu_upload_fail=%d gpu_upload_fail_capacity=%d gpu_upload_fail_fragmented=%d\n", status, reason, run_matrix == "1" ? "run" : "summary", radii, rows, min_gpu_draws, min_occupancy, best_radius, max_subchunks, max_draws, max_faces, max_occupancy, min_headroom, max_terrain_queue, max_process_wall, max_gpu_submit, upload_fail, upload_fail_capacity, upload_fail_fragmented)
    if (status != "pass") {
      exit 1
    }
  }
  function value_of(key,    i, kv, prefix) {
    prefix = key "="
    for (i = 1; i <= NF; i++) {
      if (index($i, prefix) == 1) {
        split($i, kv, "=")
        gsub(/^"/, "", kv[2])
        gsub(/"$/, "", kv[2])
        return kv[2]
      }
    }
    return ""
  }
' "$rows_path" > "$SUMMARY_PATH" || {
  cat "$SUMMARY_PATH" >&2 || true
  cat "$rows_path" >&2 || true
  fail "resident-set matrix gate failed"
}

cat "$rows_path" >> "$SUMMARY_PATH"
cat "$SUMMARY_PATH"
echo "Resident set matrix artifacts: $OUT_DIR"
