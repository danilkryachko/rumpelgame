#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
PACK_PATH="${1:-"$ROOT_DIR/logs/gpu_transparent_fixture_plan/transparent-fixture-pack.txt"}"
case "$PACK_PATH" in
  /*) ;;
  *) PACK_PATH="$ROOT_DIR/$PACK_PATH" ;;
esac
OUT_PATH="${2:-"$(dirname -- "$PACK_PATH")/transparent-fixture-final-report-check.txt"}"
case "$OUT_PATH" in
  /*) ;;
  *) OUT_PATH="$ROOT_DIR/$OUT_PATH" ;;
esac

fail() {
  echo "gpu_terrain_transparent_fixture_final_report_check: $*" >&2
  exit 1
}

relative_path() {
  path="$1"
  case "$path" in
    "$ROOT_DIR"/*) printf '%s\n' "${path#$ROOT_DIR/}" ;;
    *) printf '%s\n' "$path" ;;
  esac
}

resolve_pack_path() {
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

required_line() {
  file_path="$1"
  pattern="$2"
  line="$(grep -F -- "$pattern" "$file_path" || true)"
  line="$(printf '%s\n' "$line" | sed -n '1p')"
  test -n "$line" || fail "missing line in $(relative_path "$file_path"): $pattern"
  printf '%s\n' "$line"
}

required_value() {
  file_path="$1"
  key="$2"
  line="$(required_line "$file_path" "$key=")"
  value="${line#"$key="}"
  test -n "$value" || fail "missing $key value in $(relative_path "$file_path")"
  printf '%s\n' "$value"
}

required_token() {
  key="$1"
  line="$2"
  row_label="$3"
  value="$(line_token "$key" "$line")"
  test -n "$value" || fail "missing $key in $row_label row: $line"
  printf '%s\n' "$value"
}

test -s "$PACK_PATH" || fail "missing transparent fixture pack $PACK_PATH"
mkdir -p "$(dirname -- "$OUT_PATH")"

summary_line="$(required_line "$PACK_PATH" "summary transparent_fixture_pack_status=")"
acceptance_steps_line="$(required_line "$PACK_PATH" "acceptance_steps=acceptance_check/report_refresh")"
default_off_steps_line="$(required_line "$PACK_PATH" "default_off_steps=default_off_check/report_refresh")"
runtime_line="$(required_line "$PACK_PATH" "runtime_behavior=unchanged")"
ordinary_line="$(required_line "$PACK_PATH" "ordinary_world_visibility=absent")"

pack_status="$(required_token "transparent_fixture_pack_status" "$summary_line" "pack summary")"
acceptance_status="$(required_token "transparent_fixture_acceptance_status" "$summary_line" "pack summary")"
default_off_status="$(required_token "transparent_fixture_default_off_status" "$summary_line" "pack summary")"
report_check_status="$(required_token "transparent_fixture_report_check_status" "$summary_line" "pack summary")"
check_status="$(required_token "transparent_fixture_check_status" "$summary_line" "pack summary")"
scene_check_status="$(required_token "transparent_fixture_scene_harness_check_status" "$summary_line" "pack summary")"
plan_status="$(required_token "fixture_plan_status" "$summary_line" "pack summary")"
harness_status="$(required_token "transparent_fixture_harness_status" "$summary_line" "pack summary")"
env_expected="$(required_token "env_on_expected" "$summary_line" "pack summary")"
overlay_env_expected="$(required_token "overlay_env_on_expected" "$summary_line" "pack summary")"
overlay_metadata_expected="$(required_token "overlay_metadata_expected" "$summary_line" "pack summary")"

test "$pack_status" = "pass" || fail "unexpected transparent_fixture_pack_status=$pack_status"
test "$acceptance_status" = "pass" || fail "unexpected transparent_fixture_acceptance_status=$acceptance_status"
test "$default_off_status" = "pass" || fail "unexpected transparent_fixture_default_off_status=$default_off_status"
test "$report_check_status" = "pass" || fail "unexpected transparent_fixture_report_check_status=$report_check_status"
test "$check_status" = "pass" || fail "unexpected transparent_fixture_check_status=$check_status"
test "$scene_check_status" = "pass" || fail "unexpected transparent_fixture_scene_harness_check_status=$scene_check_status"
test "$plan_status" = "pending_fixture_harness" || fail "unexpected fixture_plan_status=$plan_status"
test "$harness_status" = "placeholder" || fail "unexpected transparent_fixture_harness_status=$harness_status"
test "$env_expected" = "1/0/1" || fail "unexpected env_on_expected=$env_expected"
test "$overlay_env_expected" = "1/0/1" || fail "unexpected overlay_env_on_expected=$overlay_env_expected"
test "$overlay_metadata_expected" = "5/5" || fail "unexpected overlay_metadata_expected=$overlay_metadata_expected"
test "${acceptance_steps_line#acceptance_steps=}" = "acceptance_check/report_refresh" || fail "unexpected acceptance steps"
test "${default_off_steps_line#default_off_steps=}" = "default_off_check/report_refresh" || fail "unexpected default-off steps"
test "${runtime_line#runtime_behavior=}" = "unchanged" || fail "unexpected runtime behavior"
test "${ordinary_line#ordinary_world_visibility=}" = "absent" || fail "unexpected ordinary-world visibility"

report_path="$(resolve_pack_path "$(required_value "$PACK_PATH" "report")")"
report_check_path="$(resolve_pack_path "$(required_value "$PACK_PATH" "report_check")")"
acceptance_check_path="$(resolve_pack_path "$(required_value "$PACK_PATH" "acceptance_check")")"
default_off_check_path="$(resolve_pack_path "$(required_value "$PACK_PATH" "default_off_check")")"

for artifact_path in \
  "$report_path" \
  "$report_check_path" \
  "$acceptance_check_path" \
  "$default_off_check_path"; do
  test -s "$artifact_path" || fail "missing linked artifact $(relative_path "$artifact_path")"
done

report_check_summary_line="$(required_line "$report_check_path" "summary transparent_fixture_report_check_status=pass")"
acceptance_summary_line="$(required_line "$acceptance_check_path" "summary transparent_fixture_acceptance_status=pass")"
default_off_summary_line="$(required_line "$default_off_check_path" "summary transparent_fixture_default_off_status=pass")"

report_check_env="$(required_token "env_on_expected" "$report_check_summary_line" "report-check summary")"
report_check_overlay_env="$(required_token "overlay_env_on_expected" "$report_check_summary_line" "report-check summary")"
report_check_overlay_metadata="$(required_token "overlay_metadata_expected" "$report_check_summary_line" "report-check summary")"
acceptance_pack_status="$(required_token "transparent_fixture_pack_status" "$acceptance_summary_line" "acceptance summary")"
acceptance_report_check_status="$(required_token "transparent_fixture_report_check_status" "$acceptance_summary_line" "acceptance summary")"
acceptance_env="$(required_token "env_on_expected" "$acceptance_summary_line" "acceptance summary")"
acceptance_overlay_env="$(required_token "overlay_env_on_expected" "$acceptance_summary_line" "acceptance summary")"
acceptance_overlay_metadata="$(required_token "overlay_metadata_expected" "$acceptance_summary_line" "acceptance summary")"
default_off_acceptance_status="$(required_token "transparent_fixture_acceptance_status" "$default_off_summary_line" "default-off summary")"
default_off_gate="$(required_token "transparent_implementation_gate" "$default_off_summary_line" "default-off summary")"
default_off_env="$(required_token "env_on_expected" "$default_off_summary_line" "default-off summary")"
default_off_overlay_env="$(required_token "overlay_env_on_expected" "$default_off_summary_line" "default-off summary")"
default_off_overlay_metadata="$(required_token "overlay_metadata_expected" "$default_off_summary_line" "default-off summary")"
default_off_future_active="$(required_token "future_active_expected" "$default_off_summary_line" "default-off summary")"

test "$report_check_env" = "$env_expected" || fail "report-check env_on_expected does not match pack"
test "$report_check_overlay_env" = "$overlay_env_expected" || fail "report-check overlay_env_on_expected does not match pack"
test "$report_check_overlay_metadata" = "$overlay_metadata_expected" || fail "report-check overlay_metadata_expected does not match pack"
test "$acceptance_pack_status" = "$pack_status" || fail "acceptance pack status does not match pack"
test "$acceptance_report_check_status" = "$report_check_status" || fail "acceptance report-check status does not match pack"
test "$acceptance_env" = "$env_expected" || fail "acceptance env_on_expected does not match pack"
test "$acceptance_overlay_env" = "$overlay_env_expected" || fail "acceptance overlay_env_on_expected does not match pack"
test "$acceptance_overlay_metadata" = "$overlay_metadata_expected" || fail "acceptance overlay_metadata_expected does not match pack"
test "$default_off_acceptance_status" = "$acceptance_status" || fail "default-off acceptance status does not match pack"
test "$default_off_gate" = "false" || fail "unexpected transparent implementation gate=$default_off_gate"
test "$default_off_env" = "$env_expected" || fail "default-off env_on_expected does not match pack"
test "$default_off_overlay_env" = "$overlay_env_expected" || fail "default-off overlay_env_on_expected does not match pack"
test "$default_off_overlay_metadata" = "$overlay_metadata_expected" || fail "default-off overlay_metadata_expected does not match pack"
test "$default_off_future_active" = "1/0/0" || fail "unexpected future active triplet=$default_off_future_active"

required_line "$report_path" "## Selected Transparent Fixture Acceptance Check" >/dev/null
required_line "$report_path" "Source: \`$acceptance_check_path\`" >/dev/null
required_line "$report_path" "$acceptance_summary_line" >/dev/null
required_line "$report_path" "## Selected Transparent Fixture Default-Off Check" >/dev/null
required_line "$report_path" "Source: \`$default_off_check_path\`" >/dev/null
required_line "$report_path" "$default_off_summary_line" >/dev/null

tmp_check="$OUT_PATH.tmp"
trap 'rm -f "$tmp_check"' EXIT
{
  printf 'GPU terrain transparent fixture final report check\n'
  printf 'pack=%s\n' "$(relative_path "$PACK_PATH")"
  printf 'report=%s\n' "$(relative_path "$report_path")"
  printf 'report_check=%s\n' "$(relative_path "$report_check_path")"
  printf 'acceptance_check=%s\n' "$(relative_path "$acceptance_check_path")"
  printf 'default_off_check=%s\n' "$(relative_path "$default_off_check_path")"
  printf 'report_sections=acceptance_check/default_off_check\n'
  printf 'pack_steps=acceptance_check/report_refresh/default_off_check/report_refresh\n'
  printf 'transparent_fixture_pack_status=%s\n' "$pack_status"
  printf 'transparent_fixture_acceptance_status=%s\n' "$acceptance_status"
  printf 'transparent_fixture_default_off_status=%s\n' "$default_off_status"
  printf 'transparent_fixture_report_check_status=%s\n' "$report_check_status"
  printf 'env_on_expected=%s\n' "$env_expected"
  printf 'overlay_env_on_expected=%s\n' "$overlay_env_expected"
  printf 'overlay_metadata_expected=%s\n' "$overlay_metadata_expected"
  printf 'future_active_expected=1/0/0\n'
  printf 'runtime_behavior=unchanged\n'
  printf 'ordinary_world_visibility=absent\n'
  printf 'summary transparent_fixture_final_report_check_status=pass transparent_fixture_pack_status=%s transparent_fixture_acceptance_status=%s transparent_fixture_default_off_status=%s env_on_expected=%s overlay_env_on_expected=%s overlay_metadata_expected=%s\n' \
    "$pack_status" \
    "$acceptance_status" \
    "$default_off_status" \
    "$env_expected" \
    "$overlay_env_expected" \
    "$overlay_metadata_expected"
} > "$tmp_check"

mv "$tmp_check" "$OUT_PATH"
cat "$OUT_PATH"
