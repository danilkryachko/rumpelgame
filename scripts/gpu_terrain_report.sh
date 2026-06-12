#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
LOG_DIR="${1:-"$ROOT_DIR/logs"}"
case "$LOG_DIR" in
  /*) ;;
  *) LOG_DIR="$ROOT_DIR/$LOG_DIR" ;;
esac
OUT_PATH="${2:-"$LOG_DIR/gpu-terrain-report.txt"}"
case "$OUT_PATH" in
  /*) ;;
  *) OUT_PATH="$ROOT_DIR/$OUT_PATH" ;;
esac

fail() {
  echo "gpu_terrain_report: $*" >&2
  exit 1
}

test -d "$LOG_DIR" || fail "missing log dir $LOG_DIR"
mkdir -p "$(dirname -- "$OUT_PATH")"

latest_file() {
  name="$1"
  latest_path=""
  latest_mtime=0
  for path in $(find "$LOG_DIR" -name "$name" -type f -print); do
    mtime="$(stat -f '%m' "$path" 2>/dev/null || stat -c '%Y' "$path" 2>/dev/null || printf '0')"
    if [ "$mtime" -gt "$latest_mtime" ]; then
      latest_mtime="$mtime"
      latest_path="$path"
    fi
  done
  printf '%s\n' "$latest_path"
}

summary_files() {
  find "$LOG_DIR" \( -name '*summary.txt' -o -name '*.png.txt' \) -type f -print | sort
}

metric_max() {
  key="$1"
  summary_files | xargs grep -h "$key=" 2>/dev/null \
    | sed -n "s/.*$key=\([0-9][0-9]*\(\.[0-9][0-9]*\)\{0,1\}\).*/\1/p" \
    | awk '
      BEGIN { found = 0; max = 0.0 }
      {
        value = $1 + 0.0
        if (!found || value > max) {
          max = value
          found = 1
        }
      }
      END {
        if (found) {
          printf("%.3f\n", max)
        } else {
          printf("n/a\n")
        }
      }
    '
}

metric_max_terrain_queue() {
  {
    summary_files | xargs grep -h 'terrain_queue_max_ms=' 2>/dev/null \
      | sed -n 's/.*terrain_queue_max_ms=\([0-9][0-9]*\(\.[0-9][0-9]*\)\{0,1\}\).*/\1/p'
    summary_files | xargs grep -h '^movement_terrain_queue ' 2>/dev/null \
      | sed -n 's/.* max_ms=\([0-9][0-9]*\(\.[0-9][0-9]*\)\{0,1\}\).*/\1/p'
  } | awk '
    BEGIN { found = 0; max = 0.0 }
    {
      value = $1 + 0.0
      if (!found || value > max) {
        max = value
        found = 1
      }
    }
    END {
      if (found) {
        printf("%.3f\n", max)
      } else {
        printf("n/a\n")
      }
    }
  '
}

metric_sum() {
  key="$1"
  summary_files | xargs grep -h "$key=" 2>/dev/null \
    | sed -n "s/.*$key=\([0-9][0-9]*\).*/\1/p" \
    | awk '
      BEGIN { found = 0; sum = 0 }
      {
        sum += $1
        found = 1
      }
      END {
        if (found) {
          printf("%d\n", sum)
        } else {
          printf("n/a\n")
        }
      }
    '
}

metric_triplet_max() {
  key="$1"
  summary_files | xargs grep -h "$key=" 2>/dev/null \
    | awk -v key="$key" '
      BEGIN {
        found = 0
        max = 0.0
        prefix = key "="
      }
      {
        for (i = 1; i <= NF; i++) {
          if (index($i, prefix) == 1) {
            part_count = split(substr($i, length(prefix) + 1), parts, "/")
            if (part_count >= 3) {
              value = parts[3] + 0.0
              if (!found || value > max) {
                max = value
                found = 1
              }
            }
          }
        }
      }
      END {
        if (found) {
          printf("%.3f\n", max)
        } else {
          printf("n/a\n")
        }
      }
    '
}

metric_max_source() {
  key="$1"
  best_value=""
  best_path=""
  for path in $(summary_files); do
    values="$(grep "$key=" "$path" 2>/dev/null \
      | sed -n "s/.*$key=\([0-9][0-9]*\(\.[0-9][0-9]*\)\{0,1\}\).*/\1/p")"
    for value in $values; do
      if [ -z "$best_value" ] || awk -v value="$value" -v best="$best_value" 'BEGIN { exit !(value > best) }'; then
        best_value="$value"
        best_path="$path"
      fi
    done
  done

  if [ -n "$best_value" ]; then
    printf '%s `%s` from `%s`\n' "$key" "$best_value" "$best_path"
  else
    printf '%s `n/a`\n' "$key"
  fi
}

metric_pair_ratio_max_percent() {
  numerator_key="$1"
  denominator_key="$2"
  summary_files | xargs grep -h "$numerator_key=" 2>/dev/null \
    | awk -v numerator_key="$numerator_key" -v denominator_key="$denominator_key" '
      BEGIN {
        found = 0
        max = 0.0
        numerator_prefix = numerator_key "="
        denominator_prefix = denominator_key "="
      }
      {
        numerator = ""
        denominator = ""
        for (i = 1; i <= NF; i++) {
          if (index($i, numerator_prefix) == 1) {
            numerator = substr($i, length(numerator_prefix) + 1) + 0.0
          }
          if (index($i, denominator_prefix) == 1) {
            denominator = substr($i, length(denominator_prefix) + 1) + 0.0
          }
        }
        if (denominator > 0.0) {
          value = numerator * 100.0 / denominator
          if (!found || value > max) {
            max = value
            found = 1
          }
        }
      }
      END {
        if (found) {
          printf("%.3f\n", max)
        } else {
          printf("n/a\n")
        }
      }
    '
}

metric_pair_headroom_min() {
  used_key="$1"
  capacity_key="$2"
  summary_files | xargs grep -h "$used_key=" 2>/dev/null \
    | awk -v used_key="$used_key" -v capacity_key="$capacity_key" '
      BEGIN {
        found = 0
        min = 0.0
        used_prefix = used_key "="
        capacity_prefix = capacity_key "="
      }
      {
        used = ""
        capacity = ""
        for (i = 1; i <= NF; i++) {
          if (index($i, used_prefix) == 1) {
            used = substr($i, length(used_prefix) + 1) + 0.0
          }
          if (index($i, capacity_prefix) == 1) {
            capacity = substr($i, length(capacity_prefix) + 1) + 0.0
          }
        }
        if (capacity > 0.0) {
          value = capacity - used
          if (!found || value < min) {
            min = value
            found = 1
          }
        }
      }
      END {
        if (found) {
          printf("%.3f\n", min)
        } else {
          printf("n/a\n")
        }
      }
    '
}

metric_pair_ratio_max_source() {
  label="$1"
  numerator_key="$2"
  denominator_key="$3"
  best_value=""
  best_path=""
  for path in $(summary_files); do
    values="$(grep "$numerator_key=" "$path" 2>/dev/null \
      | awk -v numerator_key="$numerator_key" -v denominator_key="$denominator_key" '
        BEGIN {
          numerator_prefix = numerator_key "="
          denominator_prefix = denominator_key "="
        }
        {
          numerator = ""
          denominator = ""
          for (i = 1; i <= NF; i++) {
            if (index($i, numerator_prefix) == 1) {
              numerator = substr($i, length(numerator_prefix) + 1) + 0.0
            }
            if (index($i, denominator_prefix) == 1) {
              denominator = substr($i, length(denominator_prefix) + 1) + 0.0
            }
          }
          if (denominator > 0.0) {
            printf("%.3f\n", numerator * 100.0 / denominator)
          }
        }
      ')"
    for value in $values; do
      if [ -z "$best_value" ] || awk -v value="$value" -v best="$best_value" 'BEGIN { exit !(value > best) }'; then
        best_value="$value"
        best_path="$path"
      fi
    done
  done

  if [ -n "$best_value" ]; then
    printf '%s `%s` from `%s`\n' "$label" "$best_value" "$best_path"
  else
    printf '%s `n/a`\n' "$label"
  fi
}

metric_max_source_terrain_queue() {
  best_value=""
  best_path=""
  for path in $(summary_files); do
    values="$(
      {
        grep 'terrain_queue_max_ms=' "$path" 2>/dev/null \
          | sed -n 's/.*terrain_queue_max_ms=\([0-9][0-9]*\(\.[0-9][0-9]*\)\{0,1\}\).*/\1/p'
        grep '^movement_terrain_queue ' "$path" 2>/dev/null \
          | sed -n 's/.* max_ms=\([0-9][0-9]*\(\.[0-9][0-9]*\)\{0,1\}\).*/\1/p'
      } || true
    )"
    for value in $values; do
      if [ -z "$best_value" ] || awk -v value="$value" -v best="$best_value" 'BEGIN { exit !(value > best) }'; then
        best_value="$value"
        best_path="$path"
      fi
    done
  done

  if [ -n "$best_value" ]; then
    printf 'terrain_queue_max_ms `%s` from `%s`\n' "$best_value" "$best_path"
  else
    printf 'terrain_queue_max_ms `n/a`\n'
  fi
}

rasterization_states() {
  summary_files | xargs grep -h 'gpu_cull=' 2>/dev/null \
    | sed -n 's/.*gpu_cull=\([^ ]*\).*gpu_front_face=\([^ ]*\).*/gpu_cull=\1 gpu_front_face=\2/p' \
    | sort -u
}

print_optional_file() {
  label="$1"
  path="$2"
  if [ -n "$path" ] && [ -s "$path" ]; then
    printf '\n## %s\n\n' "$label"
    printf 'Source: `%s`\n\n' "$path"
    sed -n '1,80p' "$path"
  else
    printf '\n## %s\n\n' "$label"
    printf 'No matching summary found under `%s`.\n' "$LOG_DIR"
  fi
}

print_optional_artifact() {
  label="$1"
  path="$2"
  if [ -n "$path" ] && [ -s "$path" ]; then
    printf '\n## %s\n\n' "$label"
    printf 'Source: `%s`\n\n' "$path"
    sed -n '1,80p' "$path"
  else
    printf '\n## %s\n\n' "$label"
    printf 'No matching artifact found under `%s`.\n' "$LOG_DIR"
  fi
}

error_scan() {
  summary_files | xargs grep -nE 'ERROR|SCRIPT ERROR|panic|ObjectDB|leaked|exceeds|gpu_upload_fail=[1-9]' 2>/dev/null \
    | sed -n '1,80p'
}

tmp_path="$OUT_PATH.tmp"
{
  printf '# GPU Terrain Report\n\n'
  printf 'Log dir: `%s`\n' "$LOG_DIR"
  printf 'Generated: `%s`\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  printf 'Git commit: `%s`\n' "$(git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null || printf 'unknown')"
  printf '\n'
  printf 'Local caveat: visual FPS above display refresh and local macOS/Metal GPU timestamps are report-only unless an external GPU profiler confirms them.\n'
  printf 'Aggregate caveat: aggregate values scan all matching historical summaries under the log dir, not only the newest run.\n'

  printf '\n## Aggregate Signals\n\n'
  printf -- '- max `gpu_draws`: `%s`\n' "$(metric_max gpu_draws)"
  printf -- '- max `gpu_effective_draws`: `%s`\n' "$(metric_max gpu_effective_draws)"
  printf -- '- max `gpu_draw_cmd_bytes`: `%s`\n' "$(metric_max gpu_draw_cmd_bytes)"
  printf -- '- max `gpu_draw_cmd_capacity_bytes`: `%s`\n' "$(metric_max gpu_draw_cmd_capacity_bytes)"
  printf -- '- max `gpu_draw_cmd_stride`: `%s`\n' "$(metric_max gpu_draw_cmd_stride)"
  printf -- '- max `gpu_draw_cmd_occupancy_pct`: `%s`\n' "$(metric_pair_ratio_max_percent gpu_draw_cmd_bytes gpu_draw_cmd_capacity_bytes)"
  printf -- '- min `gpu_draw_cmd_headroom_bytes`: `%s`\n' "$(metric_pair_headroom_min gpu_draw_cmd_bytes gpu_draw_cmd_capacity_bytes)"
  printf -- '- max `gpu_scene_target_create`: `%s`\n' "$(metric_max gpu_scene_target_create)"
  printf -- '- max `gpu_scene_target_reuse`: `%s`\n' "$(metric_max gpu_scene_target_reuse)"
  printf -- '- max `gpu_scene_target_replace`: `%s`\n' "$(metric_max gpu_scene_target_replace)"
  printf -- '- max `gpu_uniform_set_create`: `%s`\n' "$(metric_max gpu_uniform_set_create)"
  printf -- '- max `gpu_atlas_texture_create`: `%s`\n' "$(metric_max gpu_atlas_texture_create)"
  printf -- '- max `gpu_atlas_sampler_create`: `%s`\n' "$(metric_max gpu_atlas_sampler_create)"
  printf -- '- max `gpu_push_constant_bytes`: `%s`\n' "$(metric_max gpu_push_constant_bytes)"
  printf -- '- max `gpu_push_constant_updates`: `%s`\n' "$(metric_max gpu_push_constant_updates)"
  printf -- '- max `gpu_push_constant_total_bytes`: `%s`\n' "$(metric_max gpu_push_constant_total_bytes)"
  printf -- '- max `gpu_push_constant_avg_bytes`: `%s`\n' "$(metric_max gpu_push_constant_avg_bytes)"
  printf -- '- max `gpu_push_constant_camera_bytes`: `%s`\n' "$(metric_max gpu_push_constant_camera_bytes)"
  printf -- '- max `gpu_push_constant_lighting_bytes`: `%s`\n' "$(metric_max gpu_push_constant_lighting_bytes)"
  printf -- '- max `gpu_push_constant_atlas_bytes`: `%s`\n' "$(metric_max gpu_push_constant_atlas_bytes)"
  printf -- '- max `gpu_faces`: `%s`\n' "$(metric_max gpu_faces)"
  printf -- '- sum `gpu_upload_fail`: `%s`\n' "$(metric_sum gpu_upload_fail)"
  printf -- '- max `gpu_upload_ms` max component: `%s`\n' "$(metric_triplet_max gpu_upload_ms)"
  printf -- '- max `gpu_upload_encode_ms` max component: `%s`\n' "$(metric_triplet_max gpu_upload_encode_ms)"
  printf -- '- max `gpu_upload_stage_ms` max component: `%s`\n' "$(metric_triplet_max gpu_upload_stage_ms)"
  printf -- '- max `gpu_upload_update_ms` max component: `%s`\n' "$(metric_triplet_max gpu_upload_update_ms)"
  printf -- '- max `terrain_queue_gpu_uploads` max component: `%s`\n' "$(metric_triplet_max terrain_queue_gpu_uploads)"
  printf -- '- max `terrain_queue_gpu_upload_kb` max component: `%s`\n' "$(metric_triplet_max terrain_queue_gpu_upload_kb)"
  printf -- '- max `chunk_replace`: `%s`\n' "$(metric_max chunk_replace)"
  printf -- '- max `dirty_chunks`: `%s`\n' "$(metric_max dirty_chunks)"
  printf -- '- max `dirty_blocks`: `%s`\n' "$(metric_max dirty_blocks)"
  printf -- '- max `dirty_last_blocks`: `%s`\n' "$(metric_max dirty_last_blocks)"
  printf -- '- max `dirty_last_rebuild_subchunks`: `%s`\n' "$(metric_max dirty_last_rebuild_subchunks)"
  printf -- '- max `dirty_edge_neighbor_subchunks`: `%s`\n' "$(metric_max dirty_edge_neighbor_subchunks)"
  printf -- '- max `dirty_last_edge_neighbor_subchunks`: `%s`\n' "$(metric_max dirty_last_edge_neighbor_subchunks)"
  printf -- '- max `dirty_partial_subchunks`: `%s`\n' "$(metric_max dirty_partial_subchunks)"
  printf -- '- max `dirty_partial_saved_subchunks`: `%s`\n' "$(metric_max dirty_partial_saved_subchunks)"
  printf -- '- max `current_chunk_collision`: `%s`\n' "$(metric_max current_chunk_collision)"
  printf -- '- max `collision_refresh_rebuilt`: `%s`\n' "$(metric_max collision_refresh_rebuilt)"
  printf -- '- max `collision_refresh_last_rebuilt`: `%s`\n' "$(metric_max collision_refresh_last_rebuilt)"
  printf -- '- max `mesh_shadow_only`: `%s`\n' "$(metric_max mesh_shadow_only)"
  printf -- '- max `proxy_shadow`: `%s`\n' "$(metric_max proxy_shadow)"
  printf -- '- max `proxy_shadow_only`: `%s`\n' "$(metric_max proxy_shadow_only)"
  printf -- '- max `native_shadow_requested`: `%s`\n' "$(metric_max native_shadow_requested)"
  printf -- '- max `native_shadow_active`: `%s`\n' "$(metric_max native_shadow_active)"
  printf -- '- max `native_shadow_fallback`: `%s`\n' "$(metric_max native_shadow_fallback)"
  printf -- '- max `transparent_requested`: `%s`\n' "$(metric_max transparent_requested)"
  printf -- '- max `transparent_active`: `%s`\n' "$(metric_max transparent_active)"
  printf -- '- max `transparent_fallback`: `%s`\n' "$(metric_max transparent_fallback)"
  printf -- '- max `compact_shadow_proxy`: `%s`\n' "$(metric_max compact_shadow_proxy)"
  printf -- '- max `compact_shadow_normals_saved`: `%s`\n' "$(metric_max compact_shadow_normals_saved)"
  printf -- '- max `compact_collision_proxy`: `%s`\n' "$(metric_max compact_collision_proxy)"
  printf -- '- max `compact_collision_normals_saved`: `%s`\n' "$(metric_max compact_collision_normals_saved)"
  printf -- '- max `fast_proxy`: `%s`\n' "$(metric_max fast_proxy)"
  printf -- '- max `proxy_refresh_reuse`: `%s`\n' "$(metric_max proxy_refresh_reuse)"
  printf -- '- max `gpu_fragmented_free_faces`: `%s`\n' "$(metric_max gpu_fragmented_free_faces)"
  printf -- '- max `gpu_fragmentation_pct`: `%s`\n' "$(metric_max gpu_fragmentation_pct)"
  printf -- '- max `terrain_queue_max_ms`: `%s`\n' "$(metric_max_terrain_queue)"
  printf -- '- max `process_wall_p95_ms`: `%s`\n' "$(metric_max process_wall_p95_ms)"
  printf -- '- max `gpu_compositor_submit_max_ms`: `%s`\n' "$(metric_max gpu_compositor_submit_max_ms)"
  printf -- '- max `gpu_compositor_gpu_max_us`: `%s`\n' "$(metric_max gpu_compositor_gpu_max_us)"
  printf -- '- max `frame_p95_ms`: `%s`\n' "$(metric_max frame_p95_ms)"
  printf -- '- max `fps_p05`: `%s`\n' "$(metric_max fps_p05)"

  printf '\n## Rasterization States\n\n'
  states="$(rasterization_states || true)"
  if [ -n "$states" ]; then
    printf '%s\n' "$states" | sed 's/^/- `/' | sed 's/$/`/'
  else
    printf 'No `gpu_cull` marker fields found in existing artifacts.\n'
  fi

  printf '\n## Metric Origins\n\n'
  metric_max_source gpu_effective_draws | sed 's/^/- /'
  metric_max_source gpu_draw_cmd_bytes | sed 's/^/- /'
  metric_pair_ratio_max_source gpu_draw_cmd_occupancy_pct gpu_draw_cmd_bytes gpu_draw_cmd_capacity_bytes | sed 's/^/- /'
  metric_max_source gpu_scene_target_create | sed 's/^/- /'
  metric_max_source gpu_scene_target_reuse | sed 's/^/- /'
  metric_max_source gpu_scene_target_replace | sed 's/^/- /'
  metric_max_source gpu_uniform_set_create | sed 's/^/- /'
  metric_max_source gpu_push_constant_bytes | sed 's/^/- /'
  metric_max_source gpu_push_constant_updates | sed 's/^/- /'
  metric_max_source gpu_push_constant_total_bytes | sed 's/^/- /'
  metric_max_source gpu_push_constant_atlas_bytes | sed 's/^/- /'
  metric_max_source gpu_faces | sed 's/^/- /'
  metric_max_source dirty_blocks | sed 's/^/- /'
  metric_max_source dirty_last_blocks | sed 's/^/- /'
  metric_max_source dirty_edge_neighbor_subchunks | sed 's/^/- /'
  metric_max_source dirty_partial_saved_subchunks | sed 's/^/- /'
  metric_max_source current_chunk_collision | sed 's/^/- /'
  metric_max_source collision_refresh_rebuilt | sed 's/^/- /'
  metric_max_source mesh_shadow_only | sed 's/^/- /'
  metric_max_source proxy_shadow | sed 's/^/- /'
  metric_max_source proxy_shadow_only | sed 's/^/- /'
  metric_max_source native_shadow_requested | sed 's/^/- /'
  metric_max_source native_shadow_active | sed 's/^/- /'
  metric_max_source native_shadow_fallback | sed 's/^/- /'
  metric_max_source transparent_requested | sed 's/^/- /'
  metric_max_source transparent_active | sed 's/^/- /'
  metric_max_source transparent_fallback | sed 's/^/- /'
  metric_max_source compact_shadow_proxy | sed 's/^/- /'
  metric_max_source compact_shadow_normals_saved | sed 's/^/- /'
  metric_max_source compact_collision_proxy | sed 's/^/- /'
  metric_max_source compact_collision_normals_saved | sed 's/^/- /'
  metric_max_source fast_proxy | sed 's/^/- /'
  metric_max_source proxy_refresh_reuse | sed 's/^/- /'
  metric_max_source gpu_fragmentation_pct | sed 's/^/- /'
  metric_max_source_terrain_queue | sed 's/^/- /'
  metric_max_source gpu_compositor_submit_max_ms | sed 's/^/- /'
  metric_max_source frame_p95_ms | sed 's/^/- /'

  print_optional_file "Selected Movement Stress Summary" "$(latest_file movement-stress-summary.txt)"
  print_optional_file "Selected Fill Stress Summary" "$(latest_file fill-stress-summary.txt)"
  print_optional_file "Selected Workload Matrix Summary" "$(latest_file workload-matrix-summary.txt)"
  print_optional_file "Selected Perf Baseline Summary" "$(latest_file perf-baseline-summary.txt)"
  print_optional_file "Selected Shadow Profiler Results Summary" "$(latest_file shadow-radius-profiler-results-summary.txt)"
  print_optional_artifact "Selected Shadow Profiler Capture Pack" "$(latest_file shadow-radius-profiler-capture-pack.txt)"
  print_optional_artifact "Selected Transparent Fixture Plan" "$(latest_file transparent-fixture-plan.txt)"
  print_optional_artifact "Selected Transparent Fixture Harness" "$(latest_file transparent-fixture-harness.txt)"
  print_optional_artifact "Selected Transparent Fixture Check" "$(latest_file transparent-fixture-check.txt)"

  printf '\n## Recent Summary Files\n\n'
  summary_files | sed "s#^$ROOT_DIR/##" | tail -n 80 | sed 's/^/- `/' | sed 's/$/`/'

  printf '\n## Error Scan\n\n'
  scan="$(error_scan || true)"
  if [ -n "$scan" ]; then
    printf '%s\n' "$scan"
  else
    printf 'No error patterns found in summary and marker files.\n'
  fi
} > "$tmp_path"

mv "$tmp_path" "$OUT_PATH"
cat "$OUT_PATH"
