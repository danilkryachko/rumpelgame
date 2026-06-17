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

summary_list_path="$OUT_PATH.summary-files.tmp"
summary_index_path="$OUT_PATH.summary-index.tmp"
tmp_path="$OUT_PATH.tmp"
trap 'rm -f "$summary_list_path" "$summary_index_path" "$tmp_path"' EXIT HUP INT TERM

find "$LOG_DIR" \( -name '*summary.txt' -o -name '*.png.txt' \) -type f -print | sort > "$summary_list_path"
if [ -s "$summary_list_path" ]; then
  xargs awk '{ print FILENAME ":" $0 }' < "$summary_list_path" > "$summary_index_path"
else
  : > "$summary_index_path"
fi

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
  cat "$summary_list_path"
}

summary_grep() {
  pattern="$1"
  test -s "$summary_index_path" || return 0
  grep "$pattern" "$summary_index_path" 2>/dev/null || true
}

summary_grep_with_path() {
  pattern="$1"
  summary_grep "$pattern"
}

metric_max() {
  key="$1"
  summary_grep "$key=" \
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
    summary_grep 'terrain_queue_max_ms=' \
      | sed -n 's/.*terrain_queue_max_ms=\([0-9][0-9]*\(\.[0-9][0-9]*\)\{0,1\}\).*/\1/p'
    summary_grep ':movement_terrain_queue ' \
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
  summary_grep "$key=" \
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

metric_latest_text() {
  key="$1"
  summary_grep "$key=" | awk -v key="$key" '
    BEGIN { prefix = key "=" }
    {
      for (i = 1; i <= NF; i++) {
        if (index($i, prefix) == 1) {
          value = substr($i, length(prefix) + 1)
          found = 1
        }
      }
    }
    END {
      if (found) {
        printf("%s\n", value)
      } else {
        printf("n/a\n")
      }
    }
  '
}

metric_triplet_max() {
  key="$1"
  summary_grep "$key=" \
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
  summary_grep_with_path "$key=" | awk -v key="$key" '
    BEGIN { prefix = key "=" }
    {
      path = $0
      sub(/:.*/, "", path)
      for (i = 1; i <= NF; i++) {
        if (index($i, prefix) == 1) {
          raw = substr($i, length(prefix) + 1)
          if (match(raw, /^[0-9]+(\.[0-9]+)?/)) {
            value = substr(raw, RSTART, RLENGTH) + 0.0
            if (!found || value > best) {
              best = value
              best_path = path
              best_text = substr(raw, RSTART, RLENGTH)
              found = 1
            }
          }
        }
      }
    }
    END {
      if (found) {
        printf("%s `%s` from `%s`\n", key, best_text, best_path)
      } else {
        printf("%s `n/a`\n", key)
      }
    }
  '
}

metric_pair_ratio_max_percent() {
  numerator_key="$1"
  denominator_key="$2"
  summary_grep "$numerator_key=" \
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
  summary_grep "$used_key=" \
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
  summary_grep_with_path "$numerator_key=" \
    | awk -v label="$label" -v numerator_key="$numerator_key" -v denominator_key="$denominator_key" '
        BEGIN {
          numerator_prefix = numerator_key "="
          denominator_prefix = denominator_key "="
        }
        {
          path = $0
          sub(/:.*/, "", path)
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
            if (!found || value > best) {
              best = value
              best_path = path
              found = 1
            }
          }
        }
        END {
          if (found) {
            printf("%s `%.3f` from `%s`\n", label, best, best_path)
          } else {
            printf("%s `n/a`\n", label)
          }
        }
      '
}

metric_max_source_terrain_queue() {
  {
    summary_grep_with_path 'terrain_queue_max_ms=' \
      | sed -n 's/^\([^:]*\):.*terrain_queue_max_ms=\([0-9][0-9]*\(\.[0-9][0-9]*\)\{0,1\}\).*/\2 \1/p'
    summary_grep_with_path ':movement_terrain_queue ' \
      | sed -n 's/^\([^:]*\):.* max_ms=\([0-9][0-9]*\(\.[0-9][0-9]*\)\{0,1\}\).*/\2 \1/p'
  } | awk '
    NF >= 2 {
      value = $1 + 0.0
      path = substr($0, index($0, $2))
      if (!found || value > best) {
        best = value
        best_path = path
        found = 1
      }
    }
    END {
      if (found) {
        printf("terrain_queue_max_ms `%s` from `%s`\n", best, best_path)
      } else {
        printf("terrain_queue_max_ms `n/a`\n")
      }
    }
  '
}

rasterization_states() {
  summary_grep 'gpu_cull=' \
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
  test -s "$summary_index_path" || return 0
  grep -nE 'ERROR|SCRIPT ERROR|panic|ObjectDB|leaked|exceeds|gpu_upload_fail=[1-9]' "$summary_index_path" 2>/dev/null \
    | awk '
      function metric(line, key, pattern, value_len) {
        pattern = key "=[0-9][0-9]*"
        if (match(line, pattern) == 0) {
          return ""
        }
        value_len = RLENGTH - length(key) - 1
        return substr(line, RSTART + length(key) + 1, value_len)
      }

      function expected_injected_upload_failure_line(line, upload_fail, injected, capacity, fragmented) {
        if (line !~ /gpu_upload_failure_fallback/ && line !~ /gpu_terrain_upload_failure_fallback/) {
          return 0
        }
        if (line !~ /gpu_upload_fail=[1-9]/ || line !~ /gpu_upload_fail_injected=[1-9]/) {
          return 0
        }
        if (line ~ /ERROR|SCRIPT ERROR|panic|ObjectDB|leaked|exceeds/) {
          return 0
        }

        upload_fail = metric(line, "gpu_upload_fail")
        injected = metric(line, "gpu_upload_fail_injected")
        capacity = metric(line, "gpu_upload_fail_capacity")
        fragmented = metric(line, "gpu_upload_fail_fragmented")
        if (upload_fail == "" || injected == "" || capacity == "" || fragmented == "") {
          return 0
        }
        return upload_fail + 0 == injected + 0 && capacity + 0 == 0 && fragmented + 0 == 0
      }

      expected_injected_upload_failure_line($0) { next }
      { print }
    ' \
    | sed -n '1,80p'
}

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
  printf -- '- max `gpu_draw_grouped_enabled`: `%s`\n' "$(metric_max gpu_draw_grouped_enabled)"
  printf -- '- max `gpu_draw_records_logical`: `%s`\n' "$(metric_max gpu_draw_records_logical)"
  printf -- '- max `gpu_draw_records_grouped`: `%s`\n' "$(metric_max gpu_draw_records_grouped)"
  printf -- '- max `gpu_draw_grouped_saved_records`: `%s`\n' "$(metric_max gpu_draw_grouped_saved_records)"
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
  printf -- '- max `gpu_light_energy`: `%s`\n' "$(metric_max gpu_light_energy)"
  printf -- '- max `gpu_light_ambient`: `%s`\n' "$(metric_max gpu_light_ambient)"
  printf -- '- max `gpu_faces`: `%s`\n' "$(metric_max gpu_faces)"
  printf -- '- sum `gpu_upload_fail`: `%s`\n' "$(metric_sum gpu_upload_fail)"
  printf -- '- sum `gpu_upload_fail_capacity`: `%s`\n' "$(metric_sum gpu_upload_fail_capacity)"
  printf -- '- sum `gpu_upload_fail_fragmented`: `%s`\n' "$(metric_sum gpu_upload_fail_fragmented)"
  printf -- '- sum `gpu_upload_fail_injected`: `%s`\n' "$(metric_sum gpu_upload_fail_injected)"
  printf -- '- latest `gpu_upload_retry_policy`: `%s`\n' "$(metric_latest_text gpu_upload_retry_policy)"
  printf -- '- sum `gpu_upload_retry_attempts`: `%s`\n' "$(metric_sum gpu_upload_retry_attempts)"
  printf -- '- sum `gpu_upload_retry_success`: `%s`\n' "$(metric_sum gpu_upload_retry_success)"
  printf -- '- sum `gpu_upload_retry_giveups`: `%s`\n' "$(metric_sum gpu_upload_retry_giveups)"
  printf -- '- max `gpu_upload_backoff_active`: `%s`\n' "$(metric_max gpu_upload_backoff_active)"
  printf -- '- sum `gpu_upload_backoff_frames`: `%s`\n' "$(metric_sum gpu_upload_backoff_frames)"
  printf -- '- max `gpu_upload_backoff_max_frames`: `%s`\n' "$(metric_max gpu_upload_backoff_max_frames)"
  printf -- '- max `gpu_upload_ms` max component: `%s`\n' "$(metric_triplet_max gpu_upload_ms)"
  printf -- '- max `gpu_upload_encode_ms` max component: `%s`\n' "$(metric_triplet_max gpu_upload_encode_ms)"
  printf -- '- max `gpu_upload_stage_ms` max component: `%s`\n' "$(metric_triplet_max gpu_upload_stage_ms)"
  printf -- '- max `gpu_upload_update_ms` max component: `%s`\n' "$(metric_triplet_max gpu_upload_update_ms)"
  printf -- '- max `gpu_upload_stage_pool_enabled`: `%s`\n' "$(metric_max gpu_upload_stage_pool_enabled)"
  printf -- '- max `gpu_upload_stage_pool_entries`: `%s`\n' "$(metric_max gpu_upload_stage_pool_entries)"
  printf -- '- max `gpu_upload_stage_pool_bytes`: `%s`\n' "$(metric_max gpu_upload_stage_pool_bytes)"
  printf -- '- sum `gpu_upload_stage_pba_creates`: `%s`\n' "$(metric_sum gpu_upload_stage_pba_creates)"
  printf -- '- sum `gpu_upload_stage_pba_reuses`: `%s`\n' "$(metric_sum gpu_upload_stage_pba_reuses)"
  printf -- '- max `terrain_queue_gpu_uploads` max component: `%s`\n' "$(metric_triplet_max terrain_queue_gpu_uploads)"
  printf -- '- max `terrain_queue_gpu_upload_kb` max component: `%s`\n' "$(metric_triplet_max terrain_queue_gpu_upload_kb)"
  printf -- '- max `terrain_queue_gpu_upload_new_slots` max component: `%s`\n' "$(metric_triplet_max terrain_queue_gpu_upload_new_slots)"
  printf -- '- max `terrain_queue_gpu_upload_replace_slots` max component: `%s`\n' "$(metric_triplet_max terrain_queue_gpu_upload_replace_slots)"
  printf -- '- max `terrain_queue_gpu_upload_new_slot_kb` max component: `%s`\n' "$(metric_triplet_max terrain_queue_gpu_upload_new_slot_kb)"
  printf -- '- max `terrain_queue_gpu_upload_replace_slot_kb` max component: `%s`\n' "$(metric_triplet_max terrain_queue_gpu_upload_replace_slot_kb)"
  printf -- '- max `terrain_queue_gpu_upload_cutout_slots` max component: `%s`\n' "$(metric_triplet_max terrain_queue_gpu_upload_cutout_slots)"
  printf -- '- max `terrain_queue_gpu_upload_cutout_kb` max component: `%s`\n' "$(metric_triplet_max terrain_queue_gpu_upload_cutout_kb)"
  printf -- '- max `terrain_queue_gpu_upload_cutout_faces` max component: `%s`\n' "$(metric_triplet_max terrain_queue_gpu_upload_cutout_faces)"
  printf -- '- max `terrain_queue_gpu_upload_cutout_face_kb` max component: `%s`\n' "$(metric_triplet_max terrain_queue_gpu_upload_cutout_face_kb)"
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
  printf -- '- max `collision_phase_total_ms`: `%s`\n' "$(metric_max collision_phase_total_ms)"
  printf -- '- max `collision_phase_component_ms`: `%s`\n' "$(metric_max collision_phase_component_ms)"
  printf -- '- max `max_collision_phase_total_ms`: `%s`\n' "$(metric_max max_collision_phase_total_ms)"
  printf -- '- max `max_collision_phase_component_ms`: `%s`\n' "$(metric_max max_collision_phase_component_ms)"
  printf -- '- latest `stream_scheduler_mode`: `%s`\n' "$(metric_latest_text stream_scheduler_mode)"
  printf -- '- max `stream_scheduler_active`: `%s`\n' "$(metric_max stream_scheduler_active)"
  printf -- '- max `stream_scheduler_preview_mismatch`: `%s`\n' "$(metric_max stream_scheduler_preview_mismatch)"
  printf -- '- max `mesh_scheduler_directional_ties`: `%s`\n' "$(metric_max mesh_scheduler_directional_ties)"
  printf -- '- max `collision_scheduler_directional_ties`: `%s`\n' "$(metric_max collision_scheduler_directional_ties)"
  printf -- '- max `stream_scheduler_fifo_fallbacks`: `%s`\n' "$(metric_max stream_scheduler_fifo_fallbacks)"
  printf -- '- max `mesh_shadow_only`: `%s`\n' "$(metric_max mesh_shadow_only)"
  printf -- '- max `proxy_shadow`: `%s`\n' "$(metric_max proxy_shadow)"
  printf -- '- max `proxy_shadow_only`: `%s`\n' "$(metric_max proxy_shadow_only)"
  printf -- '- max `native_shadow_requested`: `%s`\n' "$(metric_max native_shadow_requested)"
  printf -- '- max `native_shadow_active`: `%s`\n' "$(metric_max native_shadow_active)"
  printf -- '- max `native_shadow_fallback`: `%s`\n' "$(metric_max native_shadow_fallback)"
  printf -- '- max `native_shadow_implemented`: `%s`\n' "$(metric_max native_shadow_implemented)"
  printf -- '- max `native_shadow_resource_width`: `%s`\n' "$(metric_max native_shadow_resource_width)"
  printf -- '- max `native_shadow_resource_height`: `%s`\n' "$(metric_max native_shadow_resource_height)"
  printf -- '- max `native_shadow_resource_layers`: `%s`\n' "$(metric_max native_shadow_resource_layers)"
  printf -- '- max `native_shadow_resource_bytes`: `%s`\n' "$(metric_max native_shadow_resource_bytes)"
  printf -- '- max `native_shadow_pass_clear_depth_milli`: `%s`\n' "$(metric_max native_shadow_pass_clear_depth_milli)"
  printf -- '- max `native_shadow_depth_attachment_binding_count`: `%s`\n' "$(metric_max native_shadow_depth_attachment_binding_count)"
  printf -- '- max `native_shadow_depth_attachment_clear_count`: `%s`\n' "$(metric_max native_shadow_depth_attachment_clear_count)"
  printf -- '- max `native_shadow_resource_transition_count`: `%s`\n' "$(metric_max native_shadow_resource_transition_count)"
  printf -- '- max `native_shadow_resource_barrier_error_count`: `%s`\n' "$(metric_max native_shadow_resource_barrier_error_count)"
  printf -- '- max `native_shadow_framebuffer_rid_allocated`: `%s`\n' "$(metric_max native_shadow_framebuffer_rid_allocated)"
  printf -- '- max `native_shadow_framebuffer_attachment_count`: `%s`\n' "$(metric_max native_shadow_framebuffer_attachment_count)"
  printf -- '- max `native_shadow_framebuffer_pass_compat_error_count`: `%s`\n' "$(metric_max native_shadow_framebuffer_pass_compat_error_count)"
  printf -- '- max `native_shadow_framebuffer_depth_only_enabled`: `%s`\n' "$(metric_max native_shadow_framebuffer_depth_only_enabled)"
  printf -- '- max `native_shadow_framebuffer_color_attachment_count`: `%s`\n' "$(metric_max native_shadow_framebuffer_color_attachment_count)"
  printf -- '- max `native_shadow_framebuffer_attachment_owned`: `%s`\n' "$(metric_max native_shadow_framebuffer_attachment_owned)"
  printf -- '- max `native_shadow_framebuffer_attachment_reuse_count`: `%s`\n' "$(metric_max native_shadow_framebuffer_attachment_reuse_count)"
  printf -- '- max `native_shadow_framebuffer_descriptor_valid`: `%s`\n' "$(metric_max native_shadow_framebuffer_descriptor_valid)"
  printf -- '- max `native_shadow_framebuffer_descriptor_error_count`: `%s`\n' "$(metric_max native_shadow_framebuffer_descriptor_error_count)"
  printf -- '- max `native_shadow_framebuffer_bind_ready`: `%s`\n' "$(metric_max native_shadow_framebuffer_bind_ready)"
  printf -- '- max `native_shadow_framebuffer_bind_error_count`: `%s`\n' "$(metric_max native_shadow_framebuffer_bind_error_count)"
  printf -- '- max `native_shadow_pass_descriptor_valid`: `%s`\n' "$(metric_max native_shadow_pass_descriptor_valid)"
  printf -- '- max `native_shadow_pass_descriptor_error_count`: `%s`\n' "$(metric_max native_shadow_pass_descriptor_error_count)"
  printf -- '- max `native_shadow_pass_rid_allocated`: `%s`\n' "$(metric_max native_shadow_pass_rid_allocated)"
  printf -- '- max `native_shadow_pass_lifecycle_ready`: `%s`\n' "$(metric_max native_shadow_pass_lifecycle_ready)"
  printf -- '- max `native_shadow_pass_lifecycle_error_count`: `%s`\n' "$(metric_max native_shadow_pass_lifecycle_error_count)"
  printf -- '- max `native_shadow_pass_begin_count`: `%s`\n' "$(metric_max native_shadow_pass_begin_count)"
  printf -- '- max `native_shadow_pass_end_count`: `%s`\n' "$(metric_max native_shadow_pass_end_count)"
  printf -- '- max `native_shadow_command_buffer_record_ready`: `%s`\n' "$(metric_max native_shadow_command_buffer_record_ready)"
  printf -- '- max `native_shadow_command_buffer_record_error_count`: `%s`\n' "$(metric_max native_shadow_command_buffer_record_error_count)"
  printf -- '- max `native_shadow_command_buffer_submit_ready`: `%s`\n' "$(metric_max native_shadow_command_buffer_submit_ready)"
  printf -- '- max `native_shadow_command_buffer_submit_error_count`: `%s`\n' "$(metric_max native_shadow_command_buffer_submit_error_count)"
  printf -- '- max `native_shadow_command_buffer_submit_count`: `%s`\n' "$(metric_max native_shadow_command_buffer_submit_count)"
  printf -- '- max `native_shadow_command_buffer_error_count`: `%s`\n' "$(metric_max native_shadow_command_buffer_error_count)"
  printf -- '- max `native_shadow_sampler_compare_enabled`: `%s`\n' "$(metric_max native_shadow_sampler_compare_enabled)"
  printf -- '- max `native_shadow_depth_bias_constant_milli`: `%s`\n' "$(metric_max native_shadow_depth_bias_constant_milli)"
  printf -- '- max `native_shadow_depth_bias_slope_milli`: `%s`\n' "$(metric_max native_shadow_depth_bias_slope_milli)"
  printf -- '- max `native_shadow_depth_bias_clamp_milli`: `%s`\n' "$(metric_max native_shadow_depth_bias_clamp_milli)"
  printf -- '- max `native_shadow_viewport_x_px`: `%s`\n' "$(metric_max native_shadow_viewport_x_px)"
  printf -- '- max `native_shadow_viewport_y_px`: `%s`\n' "$(metric_max native_shadow_viewport_y_px)"
  printf -- '- max `native_shadow_viewport_width_px`: `%s`\n' "$(metric_max native_shadow_viewport_width_px)"
  printf -- '- max `native_shadow_viewport_height_px`: `%s`\n' "$(metric_max native_shadow_viewport_height_px)"
  printf -- '- max `native_shadow_viewport_min_depth_milli`: `%s`\n' "$(metric_max native_shadow_viewport_min_depth_milli)"
  printf -- '- max `native_shadow_viewport_max_depth_milli`: `%s`\n' "$(metric_max native_shadow_viewport_max_depth_milli)"
  printf -- '- max `native_shadow_pipeline_depth_test_enabled`: `%s`\n' "$(metric_max native_shadow_pipeline_depth_test_enabled)"
  printf -- '- max `native_shadow_pipeline_depth_write_enabled`: `%s`\n' "$(metric_max native_shadow_pipeline_depth_write_enabled)"
  printf -- '- max `native_shadow_draw_face_stride_bytes`: `%s`\n' "$(metric_max native_shadow_draw_face_stride_bytes)"
  printf -- '- max `native_shadow_draw_command_stride_bytes`: `%s`\n' "$(metric_max native_shadow_draw_command_stride_bytes)"
  printf -- '- max `native_shadow_draw_indirect_enabled`: `%s`\n' "$(metric_max native_shadow_draw_indirect_enabled)"
  printf -- '- max `native_shadow_draw_call_count`: `%s`\n' "$(metric_max native_shadow_draw_call_count)"
  printf -- '- max `native_shadow_draw_face_count`: `%s`\n' "$(metric_max native_shadow_draw_face_count)"
  printf -- '- max `native_shadow_uniform_set_index`: `%s`\n' "$(metric_max native_shadow_uniform_set_index)"
  printf -- '- max `native_shadow_face_buffer_binding`: `%s`\n' "$(metric_max native_shadow_face_buffer_binding)"
  printf -- '- max `native_shadow_push_constant_bytes`: `%s`\n' "$(metric_max native_shadow_push_constant_bytes)"
  printf -- '- max `native_shadow_texture_sampling_enabled`: `%s`\n' "$(metric_max native_shadow_texture_sampling_enabled)"
  printf -- '- max `native_shadow_shader_depth_output_enabled`: `%s`\n' "$(metric_max native_shadow_shader_depth_output_enabled)"
  printf -- '- max `native_shadow_shader_color_output_enabled`: `%s`\n' "$(metric_max native_shadow_shader_color_output_enabled)"
  printf -- '- max `native_shadow_shader_source_bytes`: `%s`\n' "$(metric_max native_shadow_shader_source_bytes)"
  printf -- '- max `native_shadow_shader_source_checksum`: `%s`\n' "$(metric_max native_shadow_shader_source_checksum)"
  printf -- '- max `native_shadow_shader_module_rid_allocated`: `%s`\n' "$(metric_max native_shadow_shader_module_rid_allocated)"
  printf -- '- max `native_shadow_cascade_count`: `%s`\n' "$(metric_max native_shadow_cascade_count)"
  printf -- '- max `native_shadow_light_matrix_bytes`: `%s`\n' "$(metric_max native_shadow_light_matrix_bytes)"
  printf -- '- max `native_shadow_depth_near_milli`: `%s`\n' "$(metric_max native_shadow_depth_near_milli)"
  printf -- '- max `native_shadow_depth_far_chunks`: `%s`\n' "$(metric_max native_shadow_depth_far_chunks)"
  printf -- '- max `native_shadow_resource_creates`: `%s`\n' "$(metric_max native_shadow_resource_creates)"
  printf -- '- max `native_shadow_resource_replaces`: `%s`\n' "$(metric_max native_shadow_resource_replaces)"
  printf -- '- max `native_shadow_resource_releases`: `%s`\n' "$(metric_max native_shadow_resource_releases)"
  printf -- '- max `native_shadow_covered_chunks`: `%s`\n' "$(metric_max native_shadow_covered_chunks)"
  printf -- '- max `native_shadow_covered_subchunks`: `%s`\n' "$(metric_max native_shadow_covered_subchunks)"
  printf -- '- max `transparent_requested`: `%s`\n' "$(metric_max transparent_requested)"
  printf -- '- max `transparent_active`: `%s`\n' "$(metric_max transparent_active)"
  printf -- '- max `transparent_fallback`: `%s`\n' "$(metric_max transparent_fallback)"
  printf -- '- max `transparent_blocks`: `%s`\n' "$(metric_max transparent_blocks)"
  printf -- '- max `transparent_faces`: `%s`\n' "$(metric_max transparent_faces)"
  printf -- '- max `transparent_draws`: `%s`\n' "$(metric_max transparent_draws)"
  printf -- '- max `transparent_subchunks`: `%s`\n' "$(metric_max transparent_subchunks)"
  printf -- '- max `transparent_cutout_uploads`: `%s`\n' "$(metric_max transparent_cutout_uploads)"
  printf -- '- max `transparent_cutout_upload_bytes`: `%s`\n' "$(metric_max transparent_cutout_upload_bytes)"
  printf -- '- max `transparent_cutout_upload_faces`: `%s`\n' "$(metric_max transparent_cutout_upload_faces)"
  printf -- '- max `transparent_cutout_upload_face_bytes`: `%s`\n' "$(metric_max transparent_cutout_upload_face_bytes)"
  printf -- '- latest `transparent_sort_policy`: `%s`\n' "$(metric_latest_text transparent_sort_policy)"
  printf -- '- max `transparent_sort_active`: `%s`\n' "$(metric_max transparent_sort_active)"
  printf -- '- max `transparent_sort_keys`: `%s`\n' "$(metric_max transparent_sort_keys)"
  printf -- '- max `transparent_sort_ms`: `%s`\n' "$(metric_max transparent_sort_ms)"
  printf -- '- latest `transparent_build_cost_source`: `%s`\n' "$(metric_latest_text transparent_build_cost_source)"
  printf -- '- max `transparent_build_faces`: `%s`\n' "$(metric_max transparent_build_faces)"
  printf -- '- max `transparent_build_subchunks`: `%s`\n' "$(metric_max transparent_build_subchunks)"
  printf -- '- max `transparent_build_envelope_ms`: `%s`\n' "$(metric_max transparent_build_envelope_ms)"
  printf -- '- max `transparent_build_uploads`: `%s`\n' "$(metric_max transparent_build_uploads)"
  printf -- '- max `transparent_build_upload_bytes`: `%s`\n' "$(metric_max transparent_build_upload_bytes)"
  printf -- '- max `transparent_build_upload_faces`: `%s`\n' "$(metric_max transparent_build_upload_faces)"
  printf -- '- max `transparent_build_upload_face_bytes`: `%s`\n' "$(metric_max transparent_build_upload_face_bytes)"
  printf -- '- max `cutout_fixture_adjacent_pair_blocks`: `%s`\n' "$(metric_max cutout_fixture_adjacent_pair_blocks)"
  printf -- '- max `cutout_fixture_adjacent_pair_block_id`: `%s`\n' "$(metric_max cutout_fixture_adjacent_pair_block_id)"
  printf -- '- max `cutout_fixture_adjacent_pair_same_material`: `%s`\n' "$(metric_max cutout_fixture_adjacent_pair_same_material)"
  printf -- '- max `cutout_fixture_adjacent_pair_neighbor`: `%s`\n' "$(metric_max cutout_fixture_adjacent_pair_neighbor)"
  printf -- '- max `cutout_fixture_adjacent_pair_collision_hits`: `%s`\n' "$(metric_max cutout_fixture_adjacent_pair_collision_hits)"
  printf -- '- max `transparent_fixture_overlay_requested`: `%s`\n' "$(metric_max transparent_fixture_overlay_requested)"
  printf -- '- max `transparent_fixture_overlay_active`: `%s`\n' "$(metric_max transparent_fixture_overlay_active)"
  printf -- '- max `transparent_fixture_overlay_fallback`: `%s`\n' "$(metric_max transparent_fixture_overlay_fallback)"
  printf -- '- max `transparent_fixture_overlay_roles`: `%s`\n' "$(metric_max transparent_fixture_overlay_roles)"
  printf -- '- max `transparent_fixture_overlay_blocks`: `%s`\n' "$(metric_max transparent_fixture_overlay_blocks)"
  printf -- '- max `compact_shadow_proxy`: `%s`\n' "$(metric_max compact_shadow_proxy)"
  printf -- '- max `compact_shadow_normals_saved`: `%s`\n' "$(metric_max compact_shadow_normals_saved)"
  printf -- '- max `compact_collision_proxy`: `%s`\n' "$(metric_max compact_collision_proxy)"
  printf -- '- max `compact_collision_normals_saved`: `%s`\n' "$(metric_max compact_collision_normals_saved)"
  printf -- '- max `fast_proxy`: `%s`\n' "$(metric_max fast_proxy)"
  printf -- '- max `proxy_refresh_reuse`: `%s`\n' "$(metric_max proxy_refresh_reuse)"
  printf -- '- max `gpu_free_ranges`: `%s`\n' "$(metric_max gpu_free_ranges)"
  printf -- '- max `gpu_free_faces`: `%s`\n' "$(metric_max gpu_free_faces)"
  printf -- '- max `gpu_largest_free`: `%s`\n' "$(metric_max gpu_largest_free)"
  printf -- '- max `gpu_fragmented_free_faces`: `%s`\n' "$(metric_max gpu_fragmented_free_faces)"
  printf -- '- max `gpu_fragmentation_pct`: `%s`\n' "$(metric_max gpu_fragmentation_pct)"
  printf -- '- max `gpu_repack_requested`: `%s`\n' "$(metric_max gpu_repack_requested)"
  printf -- '- max `gpu_repack_active`: `%s`\n' "$(metric_max gpu_repack_active)"
  printf -- '- max `gpu_repack_attempts`: `%s`\n' "$(metric_max gpu_repack_attempts)"
  printf -- '- max `gpu_repack_success`: `%s`\n' "$(metric_max gpu_repack_success)"
  printf -- '- max `gpu_repack_abort`: `%s`\n' "$(metric_max gpu_repack_abort)"
  printf -- '- max `gpu_repack_moved_subchunks`: `%s`\n' "$(metric_max gpu_repack_moved_subchunks)"
  printf -- '- max `gpu_repack_moved_faces`: `%s`\n' "$(metric_max gpu_repack_moved_faces)"
  printf -- '- max `gpu_repack_bytes`: `%s`\n' "$(metric_max gpu_repack_bytes)"
  printf -- '- max `gpu_repack_source_subchunks`: `%s`\n' "$(metric_max gpu_repack_source_subchunks)"
  printf -- '- max `gpu_repack_source_bytes`: `%s`\n' "$(metric_max gpu_repack_source_bytes)"
  printf -- '- max `gpu_repack_source_missing`: `%s`\n' "$(metric_max gpu_repack_source_missing)"
  printf -- '- max `gpu_repack_payload_ready`: `%s`\n' "$(metric_max gpu_repack_payload_ready)"
  printf -- '- max `gpu_repack_payload_bytes`: `%s`\n' "$(metric_max gpu_repack_payload_bytes)"
  printf -- '- max `gpu_repack_upload_ready`: `%s`\n' "$(metric_max gpu_repack_upload_ready)"
  printf -- '- max `gpu_repack_upload_bytes`: `%s`\n' "$(metric_max gpu_repack_upload_bytes)"
  printf -- '- max `gpu_repack_upload_ms`: `%s`\n' "$(metric_max gpu_repack_upload_ms)"
  printf -- '- max `gpu_repack_bind_ready`: `%s`\n' "$(metric_max gpu_repack_bind_ready)"
  printf -- '- max `gpu_repack_bind_ms`: `%s`\n' "$(metric_max gpu_repack_bind_ms)"
  printf -- '- max `gpu_repack_draw_ready`: `%s`\n' "$(metric_max gpu_repack_draw_ready)"
  printf -- '- max `gpu_repack_draw_bytes`: `%s`\n' "$(metric_max gpu_repack_draw_bytes)"
  printf -- '- max `gpu_repack_stage_ready`: `%s`\n' "$(metric_max gpu_repack_stage_ready)"
  printf -- '- max `gpu_repack_stage_slots`: `%s`\n' "$(metric_max gpu_repack_stage_slots)"
  printf -- '- max `gpu_repack_stage_bytes`: `%s`\n' "$(metric_max gpu_repack_stage_bytes)"
  printf -- '- max `gpu_repack_commit_ready`: `%s`\n' "$(metric_max gpu_repack_commit_ready)"
  printf -- '- max `gpu_repack_commit_steps`: `%s`\n' "$(metric_max gpu_repack_commit_steps)"
  printf -- '- max `gpu_repack_commit_tail_free`: `%s`\n' "$(metric_max gpu_repack_commit_tail_free)"
  printf -- '- max `gpu_repack_apply_ready`: `%s`\n' "$(metric_max gpu_repack_apply_ready)"
  printf -- '- max `gpu_repack_apply_steps`: `%s`\n' "$(metric_max gpu_repack_apply_steps)"
  printf -- '- max `gpu_repack_apply_slots`: `%s`\n' "$(metric_max gpu_repack_apply_slots)"
  printf -- '- max `gpu_repack_final_swap_ready`: `%s`\n' "$(metric_max gpu_repack_final_swap_ready)"
  printf -- '- max `gpu_repack_final_swap_blocked`: `%s`\n' "$(metric_max gpu_repack_final_swap_blocked)"
  printf -- '- max `gpu_repack_final_swap_slots`: `%s`\n' "$(metric_max gpu_repack_final_swap_slots)"
  printf -- '- max `gpu_repack_ms`: `%s`\n' "$(metric_max gpu_repack_ms)"
  printf -- '- max `gpu_repack_fragmentation_before_pct`: `%s`\n' "$(metric_max gpu_repack_fragmentation_before_pct)"
  printf -- '- max `gpu_repack_fragmentation_after_pct`: `%s`\n' "$(metric_max gpu_repack_fragmentation_after_pct)"
  printf -- '- max `gpu_repack_largest_free_before`: `%s`\n' "$(metric_max gpu_repack_largest_free_before)"
  printf -- '- max `gpu_repack_largest_free_after`: `%s`\n' "$(metric_max gpu_repack_largest_free_after)"
  printf -- '- latest `gpu_repack_failure_reason`: `%s`\n' "$(metric_latest_text gpu_repack_failure_reason)"
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
  metric_max_source gpu_draw_records_logical | sed 's/^/- /'
  metric_max_source gpu_draw_records_grouped | sed 's/^/- /'
  metric_max_source gpu_draw_grouped_saved_records | sed 's/^/- /'
  metric_pair_ratio_max_source gpu_draw_cmd_occupancy_pct gpu_draw_cmd_bytes gpu_draw_cmd_capacity_bytes | sed 's/^/- /'
  metric_max_source gpu_scene_target_create | sed 's/^/- /'
  metric_max_source gpu_scene_target_reuse | sed 's/^/- /'
  metric_max_source gpu_scene_target_replace | sed 's/^/- /'
  metric_max_source gpu_uniform_set_create | sed 's/^/- /'
  metric_max_source gpu_push_constant_bytes | sed 's/^/- /'
  metric_max_source gpu_push_constant_updates | sed 's/^/- /'
  metric_max_source gpu_push_constant_total_bytes | sed 's/^/- /'
  metric_max_source gpu_push_constant_atlas_bytes | sed 's/^/- /'
  metric_max_source gpu_light_energy | sed 's/^/- /'
  metric_max_source gpu_light_ambient | sed 's/^/- /'
  metric_max_source gpu_faces | sed 's/^/- /'
  metric_max_source gpu_upload_fail_capacity | sed 's/^/- /'
  metric_max_source gpu_upload_fail_fragmented | sed 's/^/- /'
  metric_max_source gpu_upload_retry_attempts | sed 's/^/- /'
  metric_max_source gpu_upload_backoff_max_frames | sed 's/^/- /'
  metric_max_source dirty_blocks | sed 's/^/- /'
  metric_max_source dirty_last_blocks | sed 's/^/- /'
  metric_max_source dirty_edge_neighbor_subchunks | sed 's/^/- /'
  metric_max_source dirty_partial_saved_subchunks | sed 's/^/- /'
  metric_max_source current_chunk_collision | sed 's/^/- /'
  metric_max_source collision_refresh_rebuilt | sed 's/^/- /'
  metric_max_source collision_phase_total_ms | sed 's/^/- /'
  metric_max_source collision_phase_component_ms | sed 's/^/- /'
  metric_max_source max_collision_phase_total_ms | sed 's/^/- /'
  metric_max_source max_collision_phase_component_ms | sed 's/^/- /'
  metric_max_source mesh_shadow_only | sed 's/^/- /'
  metric_max_source proxy_shadow | sed 's/^/- /'
  metric_max_source proxy_shadow_only | sed 's/^/- /'
  metric_max_source native_shadow_requested | sed 's/^/- /'
  metric_max_source native_shadow_active | sed 's/^/- /'
  metric_max_source native_shadow_fallback | sed 's/^/- /'
  metric_max_source native_shadow_implemented | sed 's/^/- /'
  metric_max_source native_shadow_resource_width | sed 's/^/- /'
  metric_max_source native_shadow_resource_height | sed 's/^/- /'
  metric_max_source native_shadow_resource_layers | sed 's/^/- /'
  metric_max_source native_shadow_resource_bytes | sed 's/^/- /'
  metric_max_source native_shadow_pass_clear_depth_milli | sed 's/^/- /'
  metric_max_source native_shadow_depth_attachment_binding_count | sed 's/^/- /'
  metric_max_source native_shadow_depth_attachment_clear_count | sed 's/^/- /'
  metric_max_source native_shadow_resource_transition_count | sed 's/^/- /'
  metric_max_source native_shadow_resource_barrier_error_count | sed 's/^/- /'
  metric_max_source native_shadow_framebuffer_rid_allocated | sed 's/^/- /'
  metric_max_source native_shadow_framebuffer_attachment_count | sed 's/^/- /'
  metric_max_source native_shadow_framebuffer_pass_compat_error_count | sed 's/^/- /'
  metric_max_source native_shadow_framebuffer_depth_only_enabled | sed 's/^/- /'
  metric_max_source native_shadow_framebuffer_color_attachment_count | sed 's/^/- /'
  metric_max_source native_shadow_framebuffer_attachment_owned | sed 's/^/- /'
  metric_max_source native_shadow_framebuffer_attachment_reuse_count | sed 's/^/- /'
  metric_max_source native_shadow_framebuffer_descriptor_valid | sed 's/^/- /'
  metric_max_source native_shadow_framebuffer_descriptor_error_count | sed 's/^/- /'
  metric_max_source native_shadow_framebuffer_bind_ready | sed 's/^/- /'
  metric_max_source native_shadow_framebuffer_bind_error_count | sed 's/^/- /'
  metric_max_source native_shadow_pass_descriptor_valid | sed 's/^/- /'
  metric_max_source native_shadow_pass_descriptor_error_count | sed 's/^/- /'
  metric_max_source native_shadow_pass_rid_allocated | sed 's/^/- /'
  metric_max_source native_shadow_pass_lifecycle_ready | sed 's/^/- /'
  metric_max_source native_shadow_pass_lifecycle_error_count | sed 's/^/- /'
  metric_max_source native_shadow_pass_begin_count | sed 's/^/- /'
  metric_max_source native_shadow_pass_end_count | sed 's/^/- /'
  metric_max_source native_shadow_command_buffer_record_ready | sed 's/^/- /'
  metric_max_source native_shadow_command_buffer_record_error_count | sed 's/^/- /'
  metric_max_source native_shadow_command_buffer_submit_ready | sed 's/^/- /'
  metric_max_source native_shadow_command_buffer_submit_error_count | sed 's/^/- /'
  metric_max_source native_shadow_command_buffer_submit_count | sed 's/^/- /'
  metric_max_source native_shadow_command_buffer_error_count | sed 's/^/- /'
  metric_max_source native_shadow_sampler_compare_enabled | sed 's/^/- /'
  metric_max_source native_shadow_depth_bias_constant_milli | sed 's/^/- /'
  metric_max_source native_shadow_depth_bias_slope_milli | sed 's/^/- /'
  metric_max_source native_shadow_depth_bias_clamp_milli | sed 's/^/- /'
  metric_max_source native_shadow_viewport_x_px | sed 's/^/- /'
  metric_max_source native_shadow_viewport_y_px | sed 's/^/- /'
  metric_max_source native_shadow_viewport_width_px | sed 's/^/- /'
  metric_max_source native_shadow_viewport_height_px | sed 's/^/- /'
  metric_max_source native_shadow_viewport_min_depth_milli | sed 's/^/- /'
  metric_max_source native_shadow_viewport_max_depth_milli | sed 's/^/- /'
  metric_max_source native_shadow_pipeline_depth_test_enabled | sed 's/^/- /'
  metric_max_source native_shadow_pipeline_depth_write_enabled | sed 's/^/- /'
  metric_max_source native_shadow_draw_face_stride_bytes | sed 's/^/- /'
  metric_max_source native_shadow_draw_command_stride_bytes | sed 's/^/- /'
  metric_max_source native_shadow_draw_indirect_enabled | sed 's/^/- /'
  metric_max_source native_shadow_draw_call_count | sed 's/^/- /'
  metric_max_source native_shadow_draw_face_count | sed 's/^/- /'
  metric_max_source native_shadow_uniform_set_index | sed 's/^/- /'
  metric_max_source native_shadow_face_buffer_binding | sed 's/^/- /'
  metric_max_source native_shadow_push_constant_bytes | sed 's/^/- /'
  metric_max_source native_shadow_texture_sampling_enabled | sed 's/^/- /'
  metric_max_source native_shadow_shader_depth_output_enabled | sed 's/^/- /'
  metric_max_source native_shadow_shader_color_output_enabled | sed 's/^/- /'
  metric_max_source native_shadow_shader_source_bytes | sed 's/^/- /'
  metric_max_source native_shadow_shader_source_checksum | sed 's/^/- /'
  metric_max_source native_shadow_shader_module_rid_allocated | sed 's/^/- /'
  metric_max_source native_shadow_cascade_count | sed 's/^/- /'
  metric_max_source native_shadow_light_matrix_bytes | sed 's/^/- /'
  metric_max_source native_shadow_depth_near_milli | sed 's/^/- /'
  metric_max_source native_shadow_depth_far_chunks | sed 's/^/- /'
  metric_max_source native_shadow_resource_creates | sed 's/^/- /'
  metric_max_source native_shadow_resource_replaces | sed 's/^/- /'
  metric_max_source native_shadow_resource_releases | sed 's/^/- /'
  metric_max_source native_shadow_covered_chunks | sed 's/^/- /'
  metric_max_source native_shadow_covered_subchunks | sed 's/^/- /'
  metric_max_source transparent_requested | sed 's/^/- /'
  metric_max_source transparent_active | sed 's/^/- /'
  metric_max_source transparent_fallback | sed 's/^/- /'
  metric_max_source transparent_fixture_overlay_requested | sed 's/^/- /'
  metric_max_source transparent_fixture_overlay_active | sed 's/^/- /'
  metric_max_source transparent_fixture_overlay_fallback | sed 's/^/- /'
  metric_max_source transparent_fixture_overlay_roles | sed 's/^/- /'
  metric_max_source transparent_fixture_overlay_blocks | sed 's/^/- /'
  metric_max_source transparent_blocks | sed 's/^/- /'
  metric_max_source transparent_faces | sed 's/^/- /'
  metric_max_source transparent_draws | sed 's/^/- /'
  metric_max_source transparent_subchunks | sed 's/^/- /'
  metric_max_source transparent_cutout_uploads | sed 's/^/- /'
  metric_max_source transparent_cutout_upload_bytes | sed 's/^/- /'
  metric_max_source transparent_cutout_upload_faces | sed 's/^/- /'
  metric_max_source transparent_cutout_upload_face_bytes | sed 's/^/- /'
  metric_max_source transparent_sort_active | sed 's/^/- /'
  metric_max_source transparent_sort_keys | sed 's/^/- /'
  metric_max_source transparent_sort_ms | sed 's/^/- /'
  metric_max_source transparent_build_faces | sed 's/^/- /'
  metric_max_source transparent_build_subchunks | sed 's/^/- /'
  metric_max_source transparent_build_envelope_ms | sed 's/^/- /'
  metric_max_source transparent_build_uploads | sed 's/^/- /'
  metric_max_source transparent_build_upload_bytes | sed 's/^/- /'
  metric_max_source transparent_build_upload_faces | sed 's/^/- /'
  metric_max_source transparent_build_upload_face_bytes | sed 's/^/- /'
  metric_max_source cutout_fixture_adjacent_pair_blocks | sed 's/^/- /'
  metric_max_source cutout_fixture_adjacent_pair_block_id | sed 's/^/- /'
  metric_max_source cutout_fixture_adjacent_pair_same_material | sed 's/^/- /'
  metric_max_source cutout_fixture_adjacent_pair_neighbor | sed 's/^/- /'
  metric_max_source cutout_fixture_adjacent_pair_collision_hits | sed 's/^/- /'
  metric_max_source compact_shadow_proxy | sed 's/^/- /'
  metric_max_source compact_shadow_normals_saved | sed 's/^/- /'
  metric_max_source compact_collision_proxy | sed 's/^/- /'
  metric_max_source compact_collision_normals_saved | sed 's/^/- /'
  metric_max_source fast_proxy | sed 's/^/- /'
  metric_max_source proxy_refresh_reuse | sed 's/^/- /'
  metric_max_source gpu_free_ranges | sed 's/^/- /'
  metric_max_source gpu_free_faces | sed 's/^/- /'
  metric_max_source gpu_largest_free | sed 's/^/- /'
  metric_max_source gpu_fragmented_free_faces | sed 's/^/- /'
  metric_max_source gpu_fragmentation_pct | sed 's/^/- /'
  metric_max_source_terrain_queue | sed 's/^/- /'
  metric_max_source gpu_compositor_submit_max_ms | sed 's/^/- /'
  metric_max_source frame_p95_ms | sed 's/^/- /'

  print_optional_file "Selected Movement Stress Summary" "$(latest_file movement-stress-summary.txt)"
  print_optional_file "Selected GPU Stress Artifact Index Summary" "$(latest_file gpu-stress-artifact-index-summary.txt)"
  print_optional_file "Selected GPU Stress Artifact Index" "$(latest_file gpu-stress-artifact-index.txt)"
  print_optional_file "Selected GPU Streaming Priority Audit Summary" "$(latest_file gpu-streaming-priority-audit-summary.txt)"
  print_optional_file "Selected GPU Streaming Scheduler Prototype Summary" "$(latest_file gpu-streaming-scheduler-prototype-summary.txt)"
  print_optional_file "Selected GPU Streaming Scheduler Workload Matrix Summary" "$(latest_file gpu-streaming-scheduler-workload-matrix-summary.txt)"
  print_optional_file "Selected GPU Streaming Scheduler Workload Matrix Cases" "$(latest_file gpu-streaming-scheduler-workload-matrix-cases.txt)"
  print_optional_file "Selected GPU Streaming Scheduler Tie Probe Summary" "$(latest_file gpu-streaming-scheduler-tie-probe-summary.txt)"
  print_optional_file "Selected GPU Streaming Scheduler Decision Checkpoint Summary" "$(latest_file gpu-streaming-scheduler-decision-checkpoint-summary.txt)"
  print_optional_file "Selected GPU Streaming Scheduler Boundary Matrix Summary" "$(latest_file gpu-streaming-scheduler-boundary-matrix-summary.txt)"
  print_optional_file "Selected GPU Streaming Scheduler Boundary Matrix Cases" "$(latest_file gpu-streaming-scheduler-boundary-matrix-cases.txt)"
  print_optional_file "Selected GPU Buffer Residency Budget Summary" "$(latest_file gpu-buffer-residency-budget-summary.txt)"
  print_optional_file "Selected Rapid Camera-Turn Stress Summary" "$(latest_file rapid-camera-turn-stress-summary.txt)"
  print_optional_file "Selected Chunk Boundary Stress Summary" "$(latest_file chunk-boundary-stress-summary.txt)"
  print_optional_file "Selected GPU Chunk Unload Churn Diagnosis Summary" "$(latest_file gpu-chunk-unload-churn-diagnosis-summary.txt)"
  print_optional_file "Selected GPU Terrain Repeated Edit Benchmark Summary" "$(latest_file gpu-terrain-repeated-edit-benchmark-summary.txt)"
  print_optional_file "Selected GPU Terrain Repeated Edit Benchmark Cases" "$(latest_file gpu-terrain-repeated-edit-benchmark-cases.txt)"
  print_optional_file "Selected GPU Terrain Border Edit Benchmark Summary" "$(latest_file gpu-terrain-border-edit-benchmark-summary.txt)"
  print_optional_file "Selected GPU Terrain Border Edit Benchmark Cases" "$(latest_file gpu-terrain-border-edit-benchmark-cases.txt)"
  print_optional_file "Selected GPU Terrain Partial Dirty Edge Matrix Summary" "$(latest_file gpu-terrain-partial-dirty-edge-matrix-summary.txt)"
  print_optional_file "Selected GPU Terrain Partial Dirty Edge Matrix Cases" "$(latest_file gpu-terrain-partial-dirty-edge-matrix-cases.txt)"
  print_optional_file "Selected GPU Collision Refresh Cost Audit Summary" "$(latest_file gpu-collision-refresh-cost-audit-summary.txt)"
  print_optional_file "Selected GPU Collision Refresh Cost Audit Cases" "$(latest_file gpu-collision-refresh-cost-audit-cases.txt)"
  print_optional_file "Selected Fill Stress Summary" "$(latest_file fill-stress-summary.txt)"
  print_optional_file "Selected Workload Matrix Summary" "$(latest_file workload-matrix-summary.txt)"
  print_optional_file "Selected Perf Baseline Summary" "$(latest_file perf-baseline-summary.txt)"
  print_optional_file "Selected Shader Profiler Results Summary" "$(latest_file shader-profiler-results-summary.txt)"
  print_optional_artifact "Selected Shader Profiler Capture Pack" "$(latest_file shader-profiler-capture-pack.txt)"
  print_optional_file "Selected Shadow Proxy Cost Decision Summary" "$(latest_file shadow-proxy-cost-decision-summary.txt)"
  print_optional_file "Selected Shadow Profiler Results Summary" "$(latest_file shadow-radius-profiler-results-summary.txt)"
  print_optional_artifact "Selected Shadow Profiler Capture Pack" "$(latest_file shadow-radius-profiler-capture-pack.txt)"
  print_optional_file "Selected Transparent Prototype Shape Decision Summary" "$(latest_file transparent-prototype-shape-decision-summary.txt)"
  print_optional_file "Selected Transparent Cutout Prototype Acceptance Summary" "$(latest_file transparent-cutout-prototype-acceptance-summary.txt)"
  print_optional_file "Selected Cutout Pressure Load Scaling Summary" "$(latest_file gpu-terrain-cutout-pressure-load-scaling-summary.txt)"
  print_optional_file "Selected Cutout Fixture Scene Smoke Summary" "$(latest_file transparent-cutout-fixture-scene-smoke-summary.txt)"
  print_optional_file "Selected Cutout Fixture Acceptance Summary" "$(latest_file transparent-cutout-fixture-acceptance-summary.txt)"
  print_optional_file "Selected Transparent Cutout Sort Build Cost Summary" "$(latest_file transparent-cutout-sort-build-cost-summary.txt)"
  print_optional_artifact "Selected Transparent Fixture Plan" "$(latest_file transparent-fixture-plan.txt)"
  print_optional_artifact "Selected Transparent Fixture Harness" "$(latest_file transparent-fixture-harness.txt)"
  print_optional_artifact "Selected Transparent Fixture Check" "$(latest_file transparent-fixture-check.txt)"
  print_optional_artifact "Selected Transparent Fixture Scene Checklist" "$(latest_file transparent-fixture-scene-checklist.txt)"
  print_optional_artifact "Selected Transparent Fixture Scene Harness" "$(latest_file transparent-fixture-scene-harness.txt)"
  print_optional_artifact "Selected Transparent Fixture Scene Harness Check" "$(latest_file transparent-fixture-scene-harness-check.txt)"
  print_optional_artifact "Selected Transparent Fixture Acceptance Check" "$(latest_file transparent-fixture-acceptance-check.txt)"
  print_optional_artifact "Selected Transparent Fixture Default-Off Check" "$(latest_file transparent-fixture-default-off-check.txt)"
  print_optional_artifact "Selected Transparent Fixture Final Report Check" "$(latest_file transparent-fixture-final-report-check.txt)"
  print_optional_artifact "Selected Transparent Fixture Scene Implementation Checklist" "$(latest_file transparent-fixture-scene-implementation-checklist.txt)"
  print_optional_artifact "Selected Transparent Fixture Scene Implementation Gate Check" "$(latest_file transparent-fixture-scene-implementation-gate-check.txt)"
  print_optional_artifact "Selected Transparent Fixture Overlay Design" "$(latest_file transparent-fixture-overlay-design.txt)"
  print_optional_file "Selected Transparent Fixture Scene Smoke Summary" "$(latest_file transparent-fixture-scene-smoke-summary.txt)"

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
