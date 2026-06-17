#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
MANIFEST_PATH="${1:-"$ROOT_DIR/logs/gpu_shader_profiler_capture_pack_current/shader-profiler-manifest.txt"}"
RESULTS_PATH="${2:-"$(dirname -- "$MANIFEST_PATH")/shader-profiler-results.txt"}"
OUT_PATH="${3:-"$(dirname -- "$RESULTS_PATH")/shader-profiler-results-summary.txt"}"
ALLOW_PARTIAL="${RUMPELMC_SHADER_PROFILER_RESULTS_ALLOW_PARTIAL:-0}"

case "$MANIFEST_PATH" in
  /*) ;;
  *) MANIFEST_PATH="$ROOT_DIR/$MANIFEST_PATH" ;;
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
  echo "gpu_shader_profiler_results_check: $*" >&2
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

validate_nonnegative_decimal() {
  key="$1"
  value="$2"
  case "$value" in
    ''|*[!0-9.]*|*.*.*) fail "$key must be a nonnegative decimal: $value" ;;
  esac
}

validate_evidence_token() {
  key="$1"
  value="$2"
  case "$value" in
    ''|pending|todo|TODO|n/a|unknown|external_trace_required)
      fail "$key must identify recorded external evidence, not $value"
      ;;
  esac
}

test -s "$MANIFEST_PATH" || fail "missing shader profiler manifest $MANIFEST_PATH"
test -s "$RESULTS_PATH" || fail "missing shader profiler results $RESULTS_PATH"
mkdir -p "$(dirname -- "$OUT_PATH")"

tmp_plan_rows="$OUT_PATH.plan-rows.tmp"
tmp_plan_index="$OUT_PATH.plan-index.tmp"
tmp_result_rows="$OUT_PATH.result-rows.tmp"
tmp_result_lines="$OUT_PATH.result-lines.tmp"
tmp_seen_keys="$OUT_PATH.seen-keys.tmp"
tmp_summary="$OUT_PATH.tmp"
trap 'rm -f "$tmp_plan_rows" "$tmp_plan_index" "$tmp_result_rows" "$tmp_result_lines" "$tmp_seen_keys" "$tmp_summary"' EXIT

grep '^row=' "$MANIFEST_PATH" > "$tmp_plan_rows" || fail "manifest has no row entries: $MANIFEST_PATH"
grep '^external_profile_status=' "$RESULTS_PATH" > "$tmp_result_rows" || fail "results have no external_profile_status rows: $RESULTS_PATH"
: > "$tmp_plan_index"
: > "$tmp_result_lines"
: > "$tmp_seen_keys"

plan_count=0
while IFS= read -r line; do
  row="$(required_token "row" "$line")"
  priority="$(required_token "priority" "$line")"
  platform="$(required_token "platform" "$line")"
  backend="$(required_token "backend" "$line")"
  capture_status="$(required_token "capture_status" "$line")"
  artifact="$(required_token "artifact" "$line")"

  case "$priority" in
    ''|*[!0-9]*) fail "priority must be a positive integer: $priority" ;;
  esac
  test "$priority" -ge 1 || fail "priority must be a positive integer: $priority"
  test "$capture_status" = "pending_external_profiler" || fail "manifest rows must remain pending before captured results are checked"
  test "$artifact" = "external_trace_required" || fail "manifest artifact should stay external_trace_required until results are recorded"

  printf '%s|%s|%s|%s\n' "$priority" "$row" "$platform" "$backend" >> "$tmp_plan_index"
  plan_count=$((plan_count + 1))
done < "$tmp_plan_rows"

captured_count=0
macos_rows=0
windows_rows=0
cross_platform_rows=0
{
  printf 'GPU shader profiler results summary\n'
  printf 'manifest=%s\n' "$(relative_path "$MANIFEST_PATH")"
  printf 'results=%s\n' "$(relative_path "$RESULTS_PATH")"
  printf 'note=external_profile_status=captured rows are external profiler evidence; pending rows are rejected\n'
} > "$tmp_summary"

while IFS= read -r line; do
  status="$(required_token "external_profile_status" "$line")"
  row="$(required_token "row" "$line")"
  priority="$(required_token "priority" "$line")"
  platform="$(required_token "platform" "$line")"
  backend="$(required_token "backend" "$line")"
  profiler_tool="$(required_token "profiler_tool" "$line")"
  profiler_artifact="$(required_token "profiler_artifact" "$line")"
  shader_pass_ms="$(required_token "shader_pass_ms" "$line")"
  draw_pass_ms="$(required_token "draw_pass_ms" "$line")"
  vertex_stage_ms="$(required_token "vertex_stage_ms" "$line")"
  fragment_stage_ms="$(required_token "fragment_stage_ms" "$line")"
  counter_evidence="$(required_token "counter_evidence" "$line")"

  test "$status" = "captured" || fail "result row must use external_profile_status=captured, got $status"
  validate_evidence_token "profiler_tool" "$profiler_tool"
  validate_evidence_token "profiler_artifact" "$profiler_artifact"
  validate_evidence_token "counter_evidence" "$counter_evidence"
  validate_positive_decimal "shader_pass_ms" "$shader_pass_ms"
  validate_positive_decimal "draw_pass_ms" "$draw_pass_ms"
  validate_nonnegative_decimal "vertex_stage_ms" "$vertex_stage_ms"
  validate_nonnegative_decimal "fragment_stage_ms" "$fragment_stage_ms"

  plan_match="$(grep -F "${priority}|${row}|${platform}|${backend}" "$tmp_plan_index" || true)"
  test -n "$plan_match" || fail "result row does not match shader profiler manifest: priority=$priority row=$row platform=$platform backend=$backend"
  printf '%s|%s|%s|%s\n' "$priority" "$row" "$platform" "$backend" >> "$tmp_seen_keys"
  captured_count=$((captured_count + 1))
  case "$platform" in
    macos) macos_rows=$((macos_rows + 1)) ;;
    windows) windows_rows=$((windows_rows + 1)) ;;
    cross_platform) cross_platform_rows=$((cross_platform_rows + 1)) ;;
  esac

  printf '%s\trow=%s priority=%s platform=%s backend=%s external_profile_status=captured profiler_tool=%s profiler_artifact=%s shader_pass_ms=%s draw_pass_ms=%s vertex_stage_ms=%s fragment_stage_ms=%s counter_evidence=%s\n' \
    "$priority" \
    "$row" \
    "$priority" \
    "$platform" \
    "$backend" \
    "$profiler_tool" \
    "$profiler_artifact" \
    "$shader_pass_ms" \
    "$draw_pass_ms" \
    "$vertex_stage_ms" \
    "$fragment_stage_ms" \
    "$counter_evidence"
done < "$tmp_result_rows" > "$tmp_result_lines"

sort -n -k1,1 "$tmp_result_lines" | cut -f2- >> "$tmp_summary"

missing_count=0
while IFS='|' read -r priority row platform backend; do
  if ! grep -F -q "${priority}|${row}|${platform}|${backend}" "$tmp_seen_keys"; then
    missing_count=$((missing_count + 1))
    printf 'missing row=%s priority=%s platform=%s backend=%s\n' \
      "$row" \
      "$priority" \
      "$platform" \
      "$backend" >> "$tmp_summary"
  fi
done < "$tmp_plan_index"

metrics="$(
  awk '
    /^row=/ {
      for (i = 1; i <= NF; i++) {
        split($i, kv, "=")
        if (kv[1] == "shader_pass_ms" && kv[2] + 0 > max_shader_pass_ms) max_shader_pass_ms = kv[2] + 0
        if (kv[1] == "draw_pass_ms" && kv[2] + 0 > max_draw_pass_ms) max_draw_pass_ms = kv[2] + 0
        if (kv[1] == "vertex_stage_ms" && kv[2] + 0 > max_vertex_stage_ms) max_vertex_stage_ms = kv[2] + 0
        if (kv[1] == "fragment_stage_ms" && kv[2] + 0 > max_fragment_stage_ms) max_fragment_stage_ms = kv[2] + 0
      }
    }
    END {
      printf("max_shader_pass_ms=%.3f max_draw_pass_ms=%.3f max_vertex_stage_ms=%.3f max_fragment_stage_ms=%.3f\n", max_shader_pass_ms, max_draw_pass_ms, max_vertex_stage_ms, max_fragment_stage_ms)
    }
  ' "$tmp_summary"
)"

{
  printf 'summary planned_rows=%s captured_rows=%s missing_rows=%s macos_rows=%s windows_rows=%s cross_platform_rows=%s external_profile_status=captured allow_partial=%s %s\n' \
    "$plan_count" \
    "$captured_count" \
    "$missing_count" \
    "$macos_rows" \
    "$windows_rows" \
    "$cross_platform_rows" \
    "$ALLOW_PARTIAL" \
    "$metrics"
} >> "$tmp_summary"

test "$captured_count" -gt 0 || fail "results contain no captured rows"
if [ "$ALLOW_PARTIAL" != "1" ] && [ "$missing_count" -ne 0 ]; then
  fail "results missing $missing_count planned rows; set RUMPELMC_SHADER_PROFILER_RESULTS_ALLOW_PARTIAL=1 for partial handoff validation"
fi

mv "$tmp_summary" "$OUT_PATH"
cat "$OUT_PATH"
