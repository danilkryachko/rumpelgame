#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
PLAN_PATH="${1:-"$ROOT_DIR/logs/gpu_shadow_radius_matrix_wide/shadow-radius-profiler-plan.txt"}"
case "$PLAN_PATH" in
  /*) ;;
  *) PLAN_PATH="$ROOT_DIR/$PLAN_PATH" ;;
esac
OUT_PATH="${2:-"$(dirname -- "$PLAN_PATH")/shadow-radius-profiler-results-template.txt"}"
case "$OUT_PATH" in
  /*) ;;
  *) OUT_PATH="$ROOT_DIR/$OUT_PATH" ;;
esac

fail() {
  echo "gpu_terrain_shadow_profiler_results_template: $*" >&2
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

test -s "$PLAN_PATH" || fail "missing profiler plan $PLAN_PATH"
mkdir -p "$(dirname -- "$OUT_PATH")"

tmp_rows="$OUT_PATH.rows.tmp"
tmp_template="$OUT_PATH.tmp"
trap 'rm -f "$tmp_rows" "$tmp_template"' EXIT

grep '^priority=' "$PLAN_PATH" > "$tmp_rows" || fail "plan has no priority rows: $PLAN_PATH"

{
  printf 'GPU terrain shadow profiler results template\n'
  printf 'plan=%s\n' "$(relative_path "$PLAN_PATH")"
  printf 'note=rows are commented so the validator rejects this file until real external profiler values replace operator_required fields\n'
  printf 'note=remove the leading "# " from a row only after replacing profiler_tool, profiler_artifact, and gpu_shadow_pass_ms\n'
  printf 'note=normal_total_decision=do_not_cite remains do_not_cite even after external capture\n'
} > "$tmp_template"

row_count=0
while IFS= read -r line; do
  priority="$(required_token "priority" "$line")"
  radius="$(required_token "radius" "$line")"
  role="$(required_token "role" "$line")"
  artifact="$(required_token "artifact" "$line")"
  status="$(required_token "external_profile_status" "$line")"
  normal_decision="$(required_token "normal_total_decision" "$line")"

  test "$status" = "pending" || fail "plan rows must be pending before a results template is generated"
  row_count=$((row_count + 1))

  printf '# external_profile_status=captured priority=%s radius=%s role=%s artifact=%s profiler_tool=operator_required profiler_artifact=operator_required gpu_shadow_pass_ms=operator_required normal_total_decision=%s\n' \
    "$priority" \
    "$radius" \
    "$role" \
    "$artifact" \
    "$normal_decision" >> "$tmp_template"
done < "$tmp_rows"

printf 'summary rows=%s template_status=operator_intake_template\n' "$row_count" >> "$tmp_template"

test "$row_count" -gt 0 || fail "plan has no profiler rows: $PLAN_PATH"
mv "$tmp_template" "$OUT_PATH"
cat "$OUT_PATH"
