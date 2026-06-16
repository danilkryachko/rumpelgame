#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
PLAN_PATH="${1:-"$ROOT_DIR/logs/gpu_shadow_radius_matrix_wide/shadow-radius-profiler-plan.txt"}"
RESULTS_PATH="${2:-"$ROOT_DIR/logs/gpu_shadow_radius_matrix_wide/shadow-radius-profiler-results.txt"}"
OUT_PATH="${3:-"$(dirname -- "$RESULTS_PATH")/shadow-radius-profiler-results-summary.txt"}"
ALLOW_PARTIAL="${RUMPELMC_SHADOW_PROFILER_RESULTS_ALLOW_PARTIAL:-0}"

case "$PLAN_PATH" in
  /*) ;;
  *) PLAN_PATH="$ROOT_DIR/$PLAN_PATH" ;;
esac
case "$RESULTS_PATH" in
  /*) ;;
  *) RESULTS_PATH="$ROOT_DIR/$RESULTS_PATH" ;;
esac
case "$OUT_PATH" in
  /*) ;;
  *) OUT_PATH="$ROOT_DIR/$OUT_PATH" ;;
esac

fail() {
  echo "gpu_terrain_shadow_profiler_results_check: $*" >&2
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
  test -n "$value" || fail "missing $key in row: $line"
  printf '%s\n' "$value"
}

validate_positive_decimal() {
  key="$1"
  value="$2"
  case "$value" in
    ''|*[!0-9.]*|*.*.*) fail "$key must be a positive decimal: $value" ;;
  esac
  awk -v value="$value" -v key="$key" 'BEGIN { if ((value + 0.0) <= 0.0) exit 1 }' \
    || fail "$key must be greater than zero: $value"
}

validate_nonempty_evidence() {
  key="$1"
  value="$2"
  case "$value" in
    ''|pending|operator_required|n/a|unknown)
      fail "$key must identify recorded external evidence, not $value"
      ;;
    *[Tt][Oo][Dd][Oo]*)
      fail "$key must identify recorded external evidence, not $value"
      ;;
  esac
}

test -s "$PLAN_PATH" || fail "missing profiler plan $PLAN_PATH"
test -s "$RESULTS_PATH" || fail "missing profiler results $RESULTS_PATH"
mkdir -p "$(dirname -- "$OUT_PATH")"

tmp_plan_rows="$OUT_PATH.plan-rows.tmp"
tmp_plan_index="$OUT_PATH.plan-index.tmp"
tmp_result_rows="$OUT_PATH.result-rows.tmp"
tmp_result_lines="$OUT_PATH.result-lines.tmp"
tmp_seen_keys="$OUT_PATH.seen-keys.tmp"
tmp_summary="$OUT_PATH.tmp"
trap 'rm -f "$tmp_plan_rows" "$tmp_plan_index" "$tmp_result_rows" "$tmp_result_lines" "$tmp_seen_keys" "$tmp_summary"' EXIT

grep '^priority=' "$PLAN_PATH" > "$tmp_plan_rows" || fail "plan has no priority rows: $PLAN_PATH"
grep '^external_profile_status=' "$RESULTS_PATH" > "$tmp_result_rows" || fail "results have no external_profile_status rows: $RESULTS_PATH"
: > "$tmp_plan_index"
: > "$tmp_result_lines"
: > "$tmp_seen_keys"

plan_count=0
while IFS= read -r line; do
  priority="$(required_token "priority" "$line")"
  radius="$(required_token "radius" "$line")"
  artifact="$(required_token "artifact" "$line")"
  status="$(required_token "external_profile_status" "$line")"
  normal_decision="$(required_token "normal_total_decision" "$line")"
  test "$status" = "pending" || fail "plan rows must be pending before external results are checked"
  printf '%s|%s|%s|%s\n' "$priority" "$radius" "$artifact" "$normal_decision" >> "$tmp_plan_index"
  plan_count=$((plan_count + 1))
done < "$tmp_plan_rows"

captured_count=0
{
  printf 'GPU terrain shadow profiler results summary\n'
  printf 'plan=%s\n' "$(relative_path "$PLAN_PATH")"
  printf 'results=%s\n' "$(relative_path "$RESULTS_PATH")"
  printf 'note=external_profile_status=captured rows are external profiler evidence; pending rows are rejected\n'
} > "$tmp_summary"

while IFS= read -r line; do
  status="$(required_token "external_profile_status" "$line")"
  priority="$(required_token "priority" "$line")"
  radius="$(required_token "radius" "$line")"
  artifact="$(required_token "artifact" "$line")"
  profiler_tool="$(required_token "profiler_tool" "$line")"
  profiler_artifact="$(required_token "profiler_artifact" "$line")"
  shadow_pass_ms="$(required_token "gpu_shadow_pass_ms" "$line")"

  test "$status" = "captured" || fail "result row must use external_profile_status=captured, got $status"
  validate_nonempty_evidence "profiler_tool" "$profiler_tool"
  validate_nonempty_evidence "profiler_artifact" "$profiler_artifact"
  validate_positive_decimal "gpu_shadow_pass_ms" "$shadow_pass_ms"

  plan_match="$(grep -F "${priority}|${radius}|${artifact}|" "$tmp_plan_index" || true)"
  test -n "$plan_match" || fail "result row does not match profiler plan: priority=$priority radius=$radius artifact=$artifact"
  normal_decision="$(printf '%s\n' "$plan_match" | awk -F '|' 'NR == 1 { print $4 }')"
  printf '%s|%s|%s\n' "$priority" "$radius" "$artifact" >> "$tmp_seen_keys"
  captured_count=$((captured_count + 1))

  printf '%s\tpriority=%s radius=%s artifact=%s external_profile_status=captured profiler_tool=%s profiler_artifact=%s gpu_shadow_pass_ms=%s normal_total_decision=%s\n' \
    "$priority" \
    "$priority" \
    "$radius" \
    "$artifact" \
    "$profiler_tool" \
    "$profiler_artifact" \
    "$shadow_pass_ms" \
    "$normal_decision"
done < "$tmp_result_rows" > "$tmp_result_lines"

sort -n -k1,1 "$tmp_result_lines" | cut -f2- >> "$tmp_summary"

missing_count=0
while IFS='|' read -r priority radius artifact normal_decision; do
  if ! grep -F -q "${priority}|${radius}|${artifact}" "$tmp_seen_keys"; then
    missing_count=$((missing_count + 1))
    printf 'missing priority=%s radius=%s artifact=%s normal_total_decision=%s\n' \
      "$priority" \
      "$radius" \
      "$artifact" \
      "$normal_decision" >> "$tmp_summary"
  fi
done < "$tmp_plan_index"

{
  printf 'summary planned_rows=%s captured_rows=%s missing_rows=%s external_profile_status=captured allow_partial=%s\n' \
    "$plan_count" \
    "$captured_count" \
    "$missing_count" \
    "$ALLOW_PARTIAL"
} >> "$tmp_summary"

test "$captured_count" -gt 0 || fail "results contain no captured rows"
if [ "$ALLOW_PARTIAL" != "1" ] && [ "$missing_count" -ne 0 ]; then
  fail "results missing $missing_count planned rows; set RUMPELMC_SHADOW_PROFILER_RESULTS_ALLOW_PARTIAL=1 for partial handoff validation"
fi

mv "$tmp_summary" "$OUT_PATH"
cat "$OUT_PATH"
