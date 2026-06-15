#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
MANIFEST_PATH="${1:-"$ROOT_DIR/logs/gpu_shadow_radius_matrix_wide/shadow-radius-profiler-manifest.txt"}"
case "$MANIFEST_PATH" in
  /*) ;;
  *) MANIFEST_PATH="$ROOT_DIR/$MANIFEST_PATH" ;;
esac
OUT_PATH="${2:-"$(dirname -- "$MANIFEST_PATH")/shadow-radius-profiler-plan.txt"}"
case "$OUT_PATH" in
  /*) ;;
  *) OUT_PATH="$ROOT_DIR/$OUT_PATH" ;;
esac

fail() {
  echo "gpu_terrain_shadow_profiler_plan: $*" >&2
  exit 1
}

relative_path() {
  path="$1"
  case "$path" in
    "$ROOT_DIR"/*) printf '%s\n' "${path#$ROOT_DIR/}" ;;
    *) printf '%s\n' "$path" ;;
  esac
}

path_for_token() {
  path="$1"
  case "$path" in
    /*) printf '%s\n' "$path" ;;
    *) printf '%s\n' "$ROOT_DIR/$path" ;;
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
  test -n "$value" || fail "missing $key in manifest row: $line"
  printf '%s\n' "$value"
}

normal_total_decision() {
  evidence="$1"
  case "$evidence" in
    usable)
      printf '%s\n' "may_cite_after_external_profiler"
      ;;
    rejected)
      printf '%s\n' "do_not_cite"
      ;;
    unknown)
      printf '%s\n' "needs_review"
      ;;
    *)
      fail "invalid shadow_normal_total_savings_evidence=$evidence"
      ;;
  esac
}

test -s "$MANIFEST_PATH" || fail "missing manifest $MANIFEST_PATH"
mkdir -p "$(dirname -- "$OUT_PATH")"

tmp_rows="$OUT_PATH.rows.tmp"
tmp_sorted_rows="$OUT_PATH.sorted-rows.tmp"
tmp_plan="$OUT_PATH.tmp"
trap 'rm -f "$tmp_rows" "$tmp_sorted_rows" "$tmp_plan"' EXIT

grep '^priority=' "$MANIFEST_PATH" > "$tmp_rows" || fail "manifest has no priority rows: $MANIFEST_PATH"

row_count=0
usable_count=0
rejected_count=0
unknown_count=0
{
  printf 'GPU terrain shadow profiler plan\n'
  printf 'manifest=%s\n' "$(relative_path "$MANIFEST_PATH")"
  printf 'note=external_profile_status remains pending until a real Metal/Xcode profiler artifact is recorded\n'
  printf 'note=normal_total_decision=do_not_cite rows must not be used as normal-total savings evidence\n'
} > "$tmp_plan"

while IFS= read -r line; do
  priority="$(required_token "priority" "$line")"
  radius="$(required_token "radius" "$line")"
  role="$(required_token "role" "$line")"
  artifact="$(required_token "artifact" "$line")"
  full_png="$(required_token "full_png" "$line")"
  compact_png="$(required_token "compact_png" "$line")"
  compact_marker="$(required_token "compact_marker" "$line")"
  compact_shadow_proxy="$(required_token "compact_shadow_proxy" "$line")"
  compact_normals_saved="$(required_token "compact_shadow_normals_saved" "$line")"
  normal_status="$(required_token "shadow_normal_total_status" "$line")"
  normal_evidence="$(required_token "shadow_normal_total_savings_evidence" "$line")"
  profiler_required="$(required_token "profiler_required" "$line")"

  case "$priority" in
    ''|*[!0-9]*) fail "priority must be a positive integer: $priority" ;;
  esac
  test "$priority" -ge 1 || fail "priority must be a positive integer: $priority"
  test "$profiler_required" = "external_metal" || fail "profiler_required must be external_metal for radius=$radius"

  for required_path in "$artifact" "$full_png" "$compact_png" "$compact_marker"; do
    test -e "$(path_for_token "$required_path")" || fail "missing artifact for radius=$radius: $required_path"
  done

  decision="$(normal_total_decision "$normal_evidence")"
  case "$normal_evidence" in
    usable) usable_count=$((usable_count + 1)) ;;
    rejected) rejected_count=$((rejected_count + 1)) ;;
    unknown) unknown_count=$((unknown_count + 1)) ;;
  esac
  row_count=$((row_count + 1))

  printf '%s\tpriority=%s radius=%s role=%s artifact=%s external_profile_status=pending profiler_required=%s shadow_normal_total_status=%s shadow_normal_total_savings_evidence=%s normal_total_decision=%s compact_shadow_proxy=%s compact_shadow_normals_saved=%s full_png=%s compact_png=%s compact_marker=%s\n' \
    "$priority" \
    "$priority" \
    "$radius" \
    "$role" \
    "$artifact" \
    "$profiler_required" \
    "$normal_status" \
    "$normal_evidence" \
    "$decision" \
    "$compact_shadow_proxy" \
    "$compact_normals_saved" \
    "$full_png" \
    "$compact_png" \
    "$compact_marker"
done < "$tmp_rows" > "$tmp_sorted_rows"

sort -n -k1,1 "$tmp_sorted_rows" | cut -f2- >> "$tmp_plan"

{
  printf 'summary rows=%s usable=%s rejected=%s unknown=%s external_profile_status=pending\n' \
    "$row_count" \
    "$usable_count" \
    "$rejected_count" \
    "$unknown_count"
} >> "$tmp_plan"

test "$row_count" -gt 0 || fail "manifest has no profiler rows: $MANIFEST_PATH"
mv "$tmp_plan" "$OUT_PATH"
cat "$OUT_PATH"
