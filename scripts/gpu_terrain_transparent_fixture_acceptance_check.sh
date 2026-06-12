#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
PACK_PATH="${1:-"$ROOT_DIR/logs/gpu_transparent_fixture_plan/transparent-fixture-pack.txt"}"
case "$PACK_PATH" in
  /*) ;;
  *) PACK_PATH="$ROOT_DIR/$PACK_PATH" ;;
esac
OUT_PATH="${2:-"$(dirname -- "$PACK_PATH")/transparent-fixture-acceptance-check.txt"}"
case "$OUT_PATH" in
  /*) ;;
  *) OUT_PATH="$ROOT_DIR/$OUT_PATH" ;;
esac

fail() {
  echo "gpu_terrain_transparent_fixture_acceptance_check: $*" >&2
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

require_text() {
  line="$1"
  token="$2"
  row_label="$3"
  printf '%s\n' "$line" | grep -F -- "$token" >/dev/null || fail "$row_label missing $token"
}

test -s "$PACK_PATH" || fail "missing transparent fixture pack $PACK_PATH"
mkdir -p "$(dirname -- "$OUT_PATH")"

summary_line="$(required_line "$PACK_PATH" "summary transparent_fixture_pack_status=")"
steps_line="$(required_line "$PACK_PATH" "steps=plan/harness/check/report/report_check")"
scene_steps_line="$(required_line "$PACK_PATH" "scene_steps=smoke_plan/scene_checklist/scene_harness/scene_harness_check")"
acceptance_steps_line="$(grep -F -- "acceptance_steps=" "$PACK_PATH" || true)"
acceptance_steps_line="$(printf '%s\n' "$acceptance_steps_line" | sed -n '1p')"
runtime_line="$(required_line "$PACK_PATH" "runtime_behavior=unchanged")"
ordinary_line="$(required_line "$PACK_PATH" "ordinary_world_visibility=absent")"
tokens_line="$(required_line "$PACK_PATH" "contract_tokens=")"

pack_status="$(required_token "transparent_fixture_pack_status" "$summary_line" "pack summary")"
report_check_status="$(required_token "transparent_fixture_report_check_status" "$summary_line" "pack summary")"
check_status="$(required_token "transparent_fixture_check_status" "$summary_line" "pack summary")"
scene_check_status="$(required_token "transparent_fixture_scene_harness_check_status" "$summary_line" "pack summary")"
plan_status="$(required_token "fixture_plan_status" "$summary_line" "pack summary")"
harness_status="$(required_token "transparent_fixture_harness_status" "$summary_line" "pack summary")"
env_expected="$(required_token "env_on_expected" "$summary_line" "pack summary")"
contract_tokens="${tokens_line#contract_tokens=}"

test "$pack_status" = "pass" || fail "unexpected transparent_fixture_pack_status=$pack_status"
test "$report_check_status" = "pass" || fail "unexpected transparent_fixture_report_check_status=$report_check_status"
test "$check_status" = "pass" || fail "unexpected transparent_fixture_check_status=$check_status"
test "$scene_check_status" = "pass" || fail "unexpected transparent_fixture_scene_harness_check_status=$scene_check_status"
test "$plan_status" = "pending_fixture_harness" || fail "unexpected fixture_plan_status=$plan_status"
test "$harness_status" = "placeholder" || fail "unexpected transparent_fixture_harness_status=$harness_status"
test "$env_expected" = "1/0/1" || fail "unexpected env_on_expected=$env_expected"
test "${steps_line#steps=}" = "plan/harness/check/report/report_check" || fail "unexpected steps: $steps_line"
test "${scene_steps_line#scene_steps=}" = "smoke_plan/scene_checklist/scene_harness/scene_harness_check" || fail "unexpected scene steps: $scene_steps_line"
if [ -n "$acceptance_steps_line" ]; then
  test "${acceptance_steps_line#acceptance_steps=}" = "acceptance_check/report_refresh" || fail "unexpected acceptance steps: $acceptance_steps_line"
fi
test "${runtime_line#runtime_behavior=}" = "unchanged" || fail "unexpected runtime line: $runtime_line"
test "${ordinary_line#ordinary_world_visibility=}" = "absent" || fail "unexpected ordinary-world line: $ordinary_line"
case "$contract_tokens" in
  ''|*[!0-9]*) fail "contract_tokens must be numeric: $contract_tokens" ;;
esac
test "$contract_tokens" -ge 21 || fail "contract_tokens too low: $contract_tokens"

plan_path="$(resolve_pack_path "$(required_value "$PACK_PATH" "plan")")"
harness_path="$(resolve_pack_path "$(required_value "$PACK_PATH" "harness")")"
check_path="$(resolve_pack_path "$(required_value "$PACK_PATH" "check")")"
smoke_plan_path="$(resolve_pack_path "$(required_value "$PACK_PATH" "smoke_plan")")"
scene_checklist_path="$(resolve_pack_path "$(required_value "$PACK_PATH" "scene_checklist")")"
scene_harness_path="$(resolve_pack_path "$(required_value "$PACK_PATH" "scene_harness")")"
scene_harness_check_path="$(resolve_pack_path "$(required_value "$PACK_PATH" "scene_harness_check")")"
report_path="$(resolve_pack_path "$(required_value "$PACK_PATH" "report")")"
report_check_path="$(resolve_pack_path "$(required_value "$PACK_PATH" "report_check")")"

for artifact_path in \
  "$plan_path" \
  "$harness_path" \
  "$check_path" \
  "$smoke_plan_path" \
  "$scene_checklist_path" \
  "$scene_harness_path" \
  "$scene_harness_check_path" \
  "$report_path" \
  "$report_check_path"; do
  test -s "$artifact_path" || fail "missing linked artifact $(relative_path "$artifact_path")"
done

required_line "$plan_path" "step=env_on_fallback_gate status=current_expected transparent_requested=1 transparent_active=0 transparent_fallback=1 transparent_blocks=0 transparent_faces=0 transparent_draws=0 transparent_subchunks=0" >/dev/null
required_line "$plan_path" "step=future_workload_markers status=required transparent_blocks=pending transparent_faces=pending transparent_draws=pending transparent_subchunks=pending" >/dev/null
required_line "$plan_path" "step=future_active_gate status=blocked_until_implementation transparent_active=1 transparent_fallback=0 gpu_upload_fail=0" >/dev/null
required_line "$harness_path" "summary transparent_fixture_harness_status=placeholder" >/dev/null
required_line "$check_path" "summary transparent_fixture_check_status=pass" >/dev/null
required_line "$smoke_plan_path" "summary transparent_fixture_smoke_plan_status=pending_fixture_scene" >/dev/null
required_line "$scene_checklist_path" "summary transparent_fixture_scene_checklist_status=pending_scene_harness" >/dev/null
required_line "$scene_harness_path" "summary transparent_fixture_scene_harness_status=placeholder" >/dev/null
required_line "$scene_harness_check_path" "summary transparent_fixture_scene_harness_check_status=pass" >/dev/null
required_line "$report_check_path" "summary transparent_fixture_report_check_status=pass" >/dev/null
if [ -n "$acceptance_steps_line" ]; then
  acceptance_check_path="$(resolve_pack_path "$(required_value "$PACK_PATH" "acceptance_check")")"
  required_line "$report_path" "## Selected Transparent Fixture Acceptance Check" >/dev/null
  required_line "$report_path" "Source: \`$acceptance_check_path\`" >/dev/null
fi

report_check_sections_line="$(required_line "$report_check_path" "report_sections=plan/harness/check/scene_checklist/scene_harness/scene_harness_check")"
report_future_active_line="$(required_line "$report_check_path" "future_active_expected=1/0/0")"
scene_gates_line="$(required_line "$scene_harness_check_path" "future_gates=blocked_until_implementation")"
workload_gates_line="$(required_line "$scene_harness_check_path" "workload_gates=blocked_until_fixture")"
non_goals_line="$(required_line "$scene_harness_check_path" "non_goals ")"
smoke_env_on_line="$(required_line "$smoke_plan_path" "step=env_on_fallback_current status=required")"
smoke_future_scene_line="$(required_line "$smoke_plan_path" "step=future_fixture_scene status=required")"
smoke_future_workload_line="$(required_line "$smoke_plan_path" "step=future_workload_markers status=blocked_until_fixture")"
smoke_future_active_line="$(required_line "$smoke_plan_path" "step=future_active_gate status=blocked_until_implementation")"

test "${report_check_sections_line#report_sections=}" = "plan/harness/check/scene_checklist/scene_harness/scene_harness_check" || fail "unexpected report sections"
test "${report_future_active_line#future_active_expected=}" = "1/0/0" || fail "unexpected future active triplet"
test "${scene_gates_line#future_gates=}" = "blocked_until_implementation" || fail "unexpected future gates line"
test "${workload_gates_line#workload_gates=}" = "blocked_until_fixture" || fail "unexpected workload gates line"
for token in transparent_requested=1 transparent_active=0 transparent_fallback=1 transparent_blocks=0 transparent_faces=0 transparent_draws=0 transparent_subchunks=0 gpu_upload_fail=0 smoke_err=0 terrain_samples=nonzero; do
  require_text "$smoke_env_on_line" "$token" "smoke env-on gate"
done
for token in fixed_camera=required fixed_light=required depth_occluder=required adjacent_same_material_pair=required collision_probe=required; do
  require_text "$smoke_future_scene_line" "$token" "future fixture-scene gate"
done
for token in transparent_blocks=pending transparent_faces=pending transparent_draws=pending transparent_subchunks=pending; do
  require_text "$smoke_future_workload_line" "$token" "future workload gate"
done
for token in transparent_active=1 transparent_fallback=0 gpu_upload_fail=0 opaque_depth_occlusion=required collision_solidity=required opaque_adjacent_faces_visible=required; do
  require_text "$smoke_future_active_line" "$token" "future active gate"
done
for token in shader_alpha=no transparent_pass=no sorting=no block_id=no asset=no protocol=no storage=no worldgen=no; do
  require_text "$non_goals_line" "$token" "scene non-goals"
done

tmp_check="$OUT_PATH.tmp"
trap 'rm -f "$tmp_check"' EXIT
{
  printf 'GPU terrain transparent fixture acceptance check\n'
  printf 'pack=%s\n' "$(relative_path "$PACK_PATH")"
  printf 'report=%s\n' "$(relative_path "$report_path")"
  printf 'report_check=%s\n' "$(relative_path "$report_check_path")"
  printf 'smoke_plan=%s\n' "$(relative_path "$smoke_plan_path")"
  printf 'scene_harness_check=%s\n' "$(relative_path "$scene_harness_check_path")"
  printf 'acceptance_gates=current_fallback/future_scene/future_workload/future_active/non_goals\n'
  printf 'transparent_fixture_pack_status=%s\n' "$pack_status"
  printf 'transparent_fixture_report_check_status=%s\n' "$report_check_status"
  printf 'transparent_fixture_check_status=%s\n' "$check_status"
  printf 'transparent_fixture_scene_harness_check_status=%s\n' "$scene_check_status"
  printf 'fixture_plan_status=%s\n' "$plan_status"
  printf 'transparent_fixture_harness_status=%s\n' "$harness_status"
  printf 'env_on_expected=%s\n' "$env_expected"
  printf 'future_active_expected=1/0/0\n'
  printf 'contract_tokens=%s\n' "$contract_tokens"
  printf 'runtime_behavior=unchanged\n'
  printf 'ordinary_world_visibility=absent\n'
  printf 'summary transparent_fixture_acceptance_status=pass transparent_fixture_pack_status=%s transparent_fixture_report_check_status=%s transparent_fixture_check_status=%s transparent_fixture_scene_harness_check_status=%s fixture_plan_status=%s transparent_fixture_harness_status=%s env_on_expected=%s\n' \
    "$pack_status" \
    "$report_check_status" \
    "$check_status" \
    "$scene_check_status" \
    "$plan_status" \
    "$harness_status" \
    "$env_expected"
} > "$tmp_check"

mv "$tmp_check" "$OUT_PATH"
cat "$OUT_PATH"
