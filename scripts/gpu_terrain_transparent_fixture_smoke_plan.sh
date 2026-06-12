#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
PACK_PATH="${1:-"$ROOT_DIR/logs/gpu_transparent_fixture_plan/transparent-fixture-pack.txt"}"
case "$PACK_PATH" in
  /*) ;;
  *) PACK_PATH="$ROOT_DIR/$PACK_PATH" ;;
esac
OUT_PATH="${2:-"$(dirname -- "$PACK_PATH")/transparent-fixture-smoke-plan.txt"}"
case "$OUT_PATH" in
  /*) ;;
  *) OUT_PATH="$ROOT_DIR/$OUT_PATH" ;;
esac

fail() {
  echo "gpu_terrain_transparent_fixture_smoke_plan: $*" >&2
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
steps_line="$(required_line "$PACK_PATH" "steps=plan/harness/check/report/report_check")"
runtime_line="$(required_line "$PACK_PATH" "runtime_behavior=unchanged")"
ordinary_line="$(required_line "$PACK_PATH" "ordinary_world_visibility=absent")"
env_line="$(required_line "$PACK_PATH" "env_on_expected=1/0/1")"
tokens_line="$(required_line "$PACK_PATH" "contract_tokens=")"

pack_status="$(required_token "transparent_fixture_pack_status" "$summary_line" "pack summary")"
report_check_status="$(required_token "transparent_fixture_report_check_status" "$summary_line" "pack summary")"
check_status="$(required_token "transparent_fixture_check_status" "$summary_line" "pack summary")"
plan_status="$(required_token "fixture_plan_status" "$summary_line" "pack summary")"
harness_status="$(required_token "transparent_fixture_harness_status" "$summary_line" "pack summary")"
summary_env_expected="$(required_token "env_on_expected" "$summary_line" "pack summary")"
contract_tokens="${tokens_line#contract_tokens=}"
env_expected="${env_line#env_on_expected=}"

test "$pack_status" = "pass" || fail "unexpected transparent_fixture_pack_status=$pack_status"
test "$report_check_status" = "pass" || fail "unexpected transparent_fixture_report_check_status=$report_check_status"
test "$check_status" = "pass" || fail "unexpected transparent_fixture_check_status=$check_status"
test "$plan_status" = "pending_fixture_harness" || fail "unexpected fixture_plan_status=$plan_status"
test "$harness_status" = "placeholder" || fail "unexpected transparent_fixture_harness_status=$harness_status"
test "$summary_env_expected" = "1/0/1" || fail "unexpected summary env_on_expected=$summary_env_expected"
test "$env_expected" = "1/0/1" || fail "unexpected env_on_expected=$env_expected"
test "${steps_line#steps=}" = "plan/harness/check/report/report_check" || fail "unexpected steps line: $steps_line"
test "${runtime_line#runtime_behavior=}" = "unchanged" || fail "unexpected runtime line: $runtime_line"
test "${ordinary_line#ordinary_world_visibility=}" = "absent" || fail "unexpected ordinary line: $ordinary_line"
case "$contract_tokens" in
  ''|*[!0-9]*) fail "contract_tokens must be numeric: $contract_tokens" ;;
esac
test "$contract_tokens" -ge 21 || fail "contract_tokens too low: $contract_tokens"

plan_path="$(resolve_pack_path "$(required_value "$PACK_PATH" "plan")")"
harness_path="$(resolve_pack_path "$(required_value "$PACK_PATH" "harness")")"
check_path="$(resolve_pack_path "$(required_value "$PACK_PATH" "check")")"
report_check_path="$(resolve_pack_path "$(required_value "$PACK_PATH" "report_check")")"

test -s "$plan_path" || fail "missing pack plan $(relative_path "$plan_path")"
test -s "$harness_path" || fail "missing pack harness $(relative_path "$harness_path")"
test -s "$check_path" || fail "missing pack check $(relative_path "$check_path")"
test -s "$report_check_path" || fail "missing pack report-check $(relative_path "$report_check_path")"

required_line "$plan_path" "fixture=gpu-transparent-depth-collision" >/dev/null
required_line "$plan_path" "material=transparent_test_glass" >/dev/null
required_line "$plan_path" "step=env_on_fallback_gate status=current_expected transparent_requested=1 transparent_active=0 transparent_fallback=1 transparent_blocks=0 transparent_faces=0 transparent_draws=0 transparent_subchunks=0" >/dev/null
required_line "$plan_path" "step=future_workload_markers status=required transparent_blocks=pending transparent_faces=pending transparent_draws=pending transparent_subchunks=pending" >/dev/null
required_line "$plan_path" "step=future_active_gate status=blocked_until_implementation transparent_active=1 transparent_fallback=0 gpu_upload_fail=0" >/dev/null
required_line "$harness_path" "step=env_off_gate status=placeholder expected=ordinary_opaque_markers_unchanged" >/dev/null
required_line "$check_path" "summary transparent_fixture_check_status=pass" >/dev/null
required_line "$report_check_path" "summary transparent_fixture_report_check_status=pass" >/dev/null

tmp_plan="$OUT_PATH.tmp"
trap 'rm -f "$tmp_plan"' EXIT

{
  printf 'GPU terrain transparent fixture smoke plan\n'
  printf 'pack=%s\n' "$(relative_path "$PACK_PATH")"
  printf 'plan=%s\n' "$(relative_path "$plan_path")"
  printf 'harness=%s\n' "$(relative_path "$harness_path")"
  printf 'check=%s\n' "$(relative_path "$check_path")"
  printf 'report_check=%s\n' "$(relative_path "$report_check_path")"
  printf 'fixture=gpu-transparent-depth-collision\n'
  printf 'material=transparent_test_glass\n'
  printf 'smoke_plan_status=pending_fixture_scene\n'
  printf 'runtime_behavior=unchanged\n'
  printf 'ordinary_world_visibility=absent\n'
  printf 'pack_status=%s\n' "$pack_status"
  printf 'env_on_expected=%s\n' "$env_expected"
  printf 'step=env_off_current status=required expected=ordinary_opaque_markers_unchanged command="sh scripts/gpu_terrain_movement_stress.sh logs/gpu_transparent_fixture_env_off_capture"\n'
  printf 'step=env_on_fallback_current status=required transparent_requested=1 transparent_active=0 transparent_fallback=1 transparent_blocks=0 transparent_faces=0 transparent_draws=0 transparent_subchunks=0 gpu_upload_fail=0 smoke_err=0 terrain_samples=nonzero command="RUMPELMC_GPU_TERRAIN_TRANSPARENT=1 sh scripts/gpu_terrain_movement_stress.sh logs/gpu_transparent_fixture_fallback_capture"\n'
  printf 'step=future_fixture_scene status=required fixed_camera=required fixed_light=required depth_occluder=required adjacent_same_material_pair=required collision_probe=required\n'
  printf 'step=future_workload_markers status=blocked_until_fixture transparent_blocks=pending transparent_faces=pending transparent_draws=pending transparent_subchunks=pending\n'
  printf 'step=future_active_gate status=blocked_until_implementation transparent_active=1 transparent_fallback=0 gpu_upload_fail=0 opaque_depth_occlusion=required collision_solidity=required opaque_adjacent_faces_visible=required\n'
  printf 'step=non_goals status=enforced shader_alpha=no transparent_pass=no sorting=no block_id=no asset=no protocol=no storage=no worldgen=no\n'
  printf 'summary transparent_fixture_smoke_plan_status=pending_fixture_scene transparent_fixture_pack_status=%s fixture_plan_status=%s transparent_fixture_harness_status=%s env_on_expected=%s\n' \
    "$pack_status" \
    "$plan_status" \
    "$harness_status" \
    "$env_expected"
} > "$tmp_plan"

mv "$tmp_plan" "$OUT_PATH"
cat "$OUT_PATH"
