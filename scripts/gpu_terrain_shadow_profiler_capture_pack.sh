#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
MANIFEST_PATH="${1:-"$ROOT_DIR/logs/gpu_shadow_radius_matrix_wide/shadow-radius-profiler-manifest.txt"}"
case "$MANIFEST_PATH" in
  /*) ;;
  *) MANIFEST_PATH="$ROOT_DIR/$MANIFEST_PATH" ;;
esac
OUT_PATH="${2:-"$(dirname -- "$MANIFEST_PATH")/shadow-radius-profiler-capture-pack.txt"}"
case "$OUT_PATH" in
  /*) ;;
  *) OUT_PATH="$ROOT_DIR/$OUT_PATH" ;;
esac

OUT_DIR="$(dirname -- "$OUT_PATH")"
PLAN_PATH="$OUT_DIR/shadow-radius-profiler-plan.txt"
TEMPLATE_PATH="$OUT_DIR/shadow-radius-profiler-results-template.txt"
RESULTS_PATH="$OUT_DIR/shadow-radius-profiler-results.txt"
SUMMARY_PATH="$OUT_DIR/shadow-radius-profiler-results-summary.txt"

fail() {
  echo "gpu_terrain_shadow_profiler_capture_pack: $*" >&2
  exit 1
}

relative_path() {
  path="$1"
  case "$path" in
    "$ROOT_DIR"/*) printf '%s\n' "${path#$ROOT_DIR/}" ;;
    *) printf '%s\n' "$path" ;;
  esac
}

line_token() {
  key="$1"
  line="$2"
  printf '%s\n' "$line" | awk -v key="$key" '
    BEGIN { prefix = key "=" }
    {
      for (i = 1; i <= NF; i++) {
        if (index($i, prefix) == 1) {
          print substr($i, length(prefix) + 1)
          exit
        }
      }
    }
  '
}

required_token() {
  key="$1"
  line="$2"
  value="$(line_token "$key" "$line")"
  test -n "$value" || fail "missing $key in plan row: $line"
  printf '%s\n' "$value"
}

test -s "$MANIFEST_PATH" || fail "missing profiler manifest $MANIFEST_PATH"
mkdir -p "$OUT_DIR"

tmp_rows="$OUT_PATH.rows.tmp"
tmp_pack="$OUT_PATH.tmp"
tmp_plan_log="$OUT_PATH.plan.log.tmp"
tmp_template_log="$OUT_PATH.template.log.tmp"
trap 'rm -f "$tmp_rows" "$tmp_pack" "$tmp_plan_log" "$tmp_template_log"' EXIT

sh "$ROOT_DIR/scripts/gpu_terrain_shadow_profiler_plan.sh" \
  "$MANIFEST_PATH" \
  "$PLAN_PATH" > "$tmp_plan_log"
sh "$ROOT_DIR/scripts/gpu_terrain_shadow_profiler_results_template.sh" \
  "$PLAN_PATH" \
  "$TEMPLATE_PATH" > "$tmp_template_log"

grep '^priority=' "$PLAN_PATH" > "$tmp_rows" || fail "generated plan has no priority rows: $PLAN_PATH"

results_status="missing"
if [ -e "$RESULTS_PATH" ]; then
  results_status="present"
fi

{
  printf 'GPU terrain shadow profiler capture pack\n'
  printf 'manifest=%s\n' "$(relative_path "$MANIFEST_PATH")"
  printf 'plan=%s\n' "$(relative_path "$PLAN_PATH")"
  printf 'results_template=%s\n' "$(relative_path "$TEMPLATE_PATH")"
  printf 'results=%s\n' "$(relative_path "$RESULTS_PATH")"
  printf 'results_summary=%s\n' "$(relative_path "$SUMMARY_PATH")"
  printf 'results_file_status=%s\n' "$results_status"
  printf 'note=plan rows remain external_profile_status=pending until a real Metal/Xcode profiler artifact is recorded\n'
  printf 'note=template rows are commented TODO examples and must not be cited as evidence\n'
  printf 'note=after capture, write captured rows to results and validate before running the aggregate report\n'
  printf 'command_generate_pack=sh scripts/gpu_terrain_shadow_profiler_capture_pack.sh %s %s\n' \
    "$(relative_path "$MANIFEST_PATH")" \
    "$(relative_path "$OUT_PATH")"
  printf 'command_validate_results=sh scripts/gpu_terrain_shadow_profiler_results_check.sh %s %s %s\n' \
    "$(relative_path "$PLAN_PATH")" \
    "$(relative_path "$RESULTS_PATH")" \
    "$(relative_path "$SUMMARY_PATH")"
  printf 'command_validate_partial=RUMPELMC_SHADOW_PROFILER_RESULTS_ALLOW_PARTIAL=1 sh scripts/gpu_terrain_shadow_profiler_results_check.sh %s %s %s\n' \
    "$(relative_path "$PLAN_PATH")" \
    "$(relative_path "$RESULTS_PATH")" \
    "$(relative_path "$SUMMARY_PATH")"
  printf 'command_surface_report=sh scripts/gpu_terrain_report.sh logs /tmp/rumpel-gpu-report-shadow-profiler-results.txt\n'
} > "$tmp_pack"

row_count=0
while IFS= read -r line; do
  priority="$(required_token "priority" "$line")"
  radius="$(required_token "radius" "$line")"
  role="$(required_token "role" "$line")"
  artifact="$(required_token "artifact" "$line")"
  normal_decision="$(required_token "normal_total_decision" "$line")"
  compact_shadow_proxy="$(required_token "compact_shadow_proxy" "$line")"
  compact_normals_saved="$(required_token "compact_shadow_normals_saved" "$line")"

  row_count=$((row_count + 1))
  printf 'capture priority=%s radius=%s role=%s artifact=%s normal_total_decision=%s compact_shadow_proxy=%s compact_shadow_normals_saved=%s\n' \
    "$priority" \
    "$radius" \
    "$role" \
    "$artifact" \
    "$normal_decision" \
    "$compact_shadow_proxy" \
    "$compact_normals_saved" >> "$tmp_pack"
done < "$tmp_rows"

printf 'summary rows=%s capture_pack_status=pending_external_profiler\n' "$row_count" >> "$tmp_pack"

test "$row_count" -gt 0 || fail "generated capture pack has no rows"
mv "$tmp_pack" "$OUT_PATH"
cat "$OUT_PATH"
