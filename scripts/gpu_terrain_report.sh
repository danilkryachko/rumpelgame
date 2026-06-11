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
  find "$LOG_DIR" -name "$name" -type f -print | sort | tail -n 1
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
  printf -- '- max `gpu_faces`: `%s`\n' "$(metric_max gpu_faces)"
  printf -- '- sum `gpu_upload_fail`: `%s`\n' "$(metric_sum gpu_upload_fail)"
  printf -- '- max `terrain_queue_max_ms`: `%s`\n' "$(metric_max terrain_queue_max_ms)"
  printf -- '- max `process_wall_p95_ms`: `%s`\n' "$(metric_max process_wall_p95_ms)"
  printf -- '- max `gpu_compositor_submit_max_ms`: `%s`\n' "$(metric_max gpu_compositor_submit_max_ms)"
  printf -- '- max `gpu_compositor_gpu_max_us`: `%s`\n' "$(metric_max gpu_compositor_gpu_max_us)"
  printf -- '- max `frame_p95_ms`: `%s`\n' "$(metric_max frame_p95_ms)"
  printf -- '- max `fps_p05`: `%s`\n' "$(metric_max fps_p05)"

  print_optional_file "Selected Movement Stress Summary" "$(latest_file movement-stress-summary.txt)"
  print_optional_file "Selected Fill Stress Summary" "$(latest_file fill-stress-summary.txt)"
  print_optional_file "Selected Workload Matrix Summary" "$(latest_file workload-matrix-summary.txt)"
  print_optional_file "Selected Perf Baseline Summary" "$(latest_file perf-baseline-summary.txt)"

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
