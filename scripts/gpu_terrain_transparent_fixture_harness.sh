#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
PLAN_PATH="${1:-"$ROOT_DIR/logs/gpu_transparent_fixture_plan/transparent-fixture-plan.txt"}"
case "$PLAN_PATH" in
  /*) ;;
  *) PLAN_PATH="$ROOT_DIR/$PLAN_PATH" ;;
esac
OUT_PATH="${2:-"$(dirname -- "$PLAN_PATH")/transparent-fixture-harness.txt"}"
case "$OUT_PATH" in
  /*) ;;
  *) OUT_PATH="$ROOT_DIR/$OUT_PATH" ;;
esac

fail() {
  echo "gpu_terrain_transparent_fixture_harness: $*" >&2
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

required_line() {
  pattern="$1"
  line="$(grep -F -- "$pattern" "$PLAN_PATH" || true)"
  line="$(printf '%s\n' "$line" | sed -n '1p')"
  test -n "$line" || fail "missing plan line: $pattern"
  printf '%s\n' "$line"
}

required_token() {
  key="$1"
  line="$2"
  value="$(line_token "$key" "$line")"
  test -n "$value" || fail "missing $key in plan row: $line"
  printf '%s\n' "$value"
}

test -s "$PLAN_PATH" || fail "missing transparent fixture plan $PLAN_PATH"
mkdir -p "$(dirname -- "$OUT_PATH")"

fixture_line="$(required_line "fixture=gpu-transparent-depth-collision")"
material_line="$(required_line "material=transparent_test_glass")"
runtime_line="$(required_line "runtime_behavior=unchanged")"
ordinary_line="$(required_line "ordinary_world_visibility=absent")"
rollback_line="$(required_line "opaque_path_rollback=required")"
env_off_line="$(required_line "step=env_off_gate status=required")"
env_on_line="$(required_line "step=env_on_fallback_gate status=current_expected")"
future_markers_line="$(required_line "step=future_workload_markers status=required")"
future_active_line="$(required_line "step=future_active_gate status=blocked_until_implementation")"
non_goals_line="$(required_line "step=non_goals status=enforced")"
summary_line="$(required_line "summary fixture_plan_status=")"

fixture="${fixture_line#fixture=}"
material="${material_line#material=}"
runtime_behavior="${runtime_line#runtime_behavior=}"
ordinary_visibility="${ordinary_line#ordinary_world_visibility=}"
rollback_status="${rollback_line#opaque_path_rollback=}"
plan_status="$(required_token "fixture_plan_status" "$summary_line")"
contract_tokens="$(required_token "contract_tokens" "$summary_line")"
fallback_guard="$(required_token "fallback_guard" "$summary_line")"
requested="$(required_token "transparent_requested" "$env_on_line")"
active="$(required_token "transparent_active" "$env_on_line")"
fallback="$(required_token "transparent_fallback" "$env_on_line")"
future_active="$(required_token "transparent_active" "$future_active_line")"
future_fallback="$(required_token "transparent_fallback" "$future_active_line")"
future_upload_fail="$(required_token "gpu_upload_fail" "$future_active_line")"

test "$fixture" = "gpu-transparent-depth-collision" || fail "unexpected fixture=$fixture"
test "$material" = "transparent_test_glass" || fail "unexpected material=$material"
test "$runtime_behavior" = "unchanged" || fail "unexpected runtime_behavior=$runtime_behavior"
test "$ordinary_visibility" = "absent" || fail "unexpected ordinary_world_visibility=$ordinary_visibility"
test "$rollback_status" = "required" || fail "unexpected opaque_path_rollback=$rollback_status"
test "$plan_status" = "pending_fixture_harness" || fail "unexpected fixture_plan_status=$plan_status"
test "$fallback_guard" = "present" || fail "unexpected fallback_guard=$fallback_guard"
test "$requested" = "1" || fail "unexpected transparent_requested=$requested"
test "$active" = "0" || fail "unexpected transparent_active=$active"
test "$fallback" = "1" || fail "unexpected transparent_fallback=$fallback"
test "$future_active" = "1" || fail "unexpected future transparent_active=$future_active"
test "$future_fallback" = "0" || fail "unexpected future transparent_fallback=$future_fallback"
test "$future_upload_fail" = "0" || fail "unexpected future gpu_upload_fail=$future_upload_fail"
case "$contract_tokens" in
  ''|*[!0-9]*) fail "contract_tokens must be numeric: $contract_tokens" ;;
esac
test "$contract_tokens" -ge 21 || fail "contract_tokens too low: $contract_tokens"
printf '%s\n' "$future_markers_line" | grep -F "transparent_blocks=pending" >/dev/null || fail "future workload markers missing transparent_blocks"
printf '%s\n' "$future_markers_line" | grep -F "transparent_faces=pending" >/dev/null || fail "future workload markers missing transparent_faces"
printf '%s\n' "$future_markers_line" | grep -F "transparent_draws=pending" >/dev/null || fail "future workload markers missing transparent_draws"
printf '%s\n' "$future_markers_line" | grep -F "transparent_subchunks=pending" >/dev/null || fail "future workload markers missing transparent_subchunks"
printf '%s\n' "$non_goals_line" | grep -F "shader_alpha=no transparent_pass=no sorting=no block_id=no asset=no protocol=no storage=no worldgen=no" >/dev/null || fail "non-goals are not fully enforced"

tmp_harness="$OUT_PATH.tmp"
trap 'rm -f "$tmp_harness"' EXIT

{
  printf 'GPU terrain transparent fixture harness\n'
  printf 'plan=%s\n' "$(relative_path "$PLAN_PATH")"
  printf 'fixture=%s\n' "$fixture"
  printf 'material=%s\n' "$material"
  printf 'harness_status=placeholder\n'
  printf 'runtime_behavior=%s\n' "$runtime_behavior"
  printf 'ordinary_world_visibility=%s\n' "$ordinary_visibility"
  printf 'opaque_path_rollback=%s\n' "$rollback_status"
  printf 'note=this placeholder consumes the plan and does not launch Godot or enable transparent terrain materials\n'
  printf 'step=consume_plan status=present fixture_plan_status=%s contract_tokens=%s fallback_guard=%s\n' \
    "$plan_status" \
    "$contract_tokens" \
    "$fallback_guard"
  printf 'step=env_off_gate status=placeholder expected=ordinary_opaque_markers_unchanged command="sh scripts/gpu_terrain_movement_stress.sh logs/gpu_transparent_fixture_env_off_capture"\n'
  printf 'step=env_on_fallback_gate status=placeholder expected_transparent_requested=%s expected_transparent_active=%s expected_transparent_fallback=%s command="RUMPELMC_GPU_TERRAIN_TRANSPARENT=1 sh scripts/gpu_terrain_movement_stress.sh logs/gpu_transparent_fixture_fallback_capture"\n' \
    "$requested" \
    "$active" \
    "$fallback"
  printf 'step=future_workload_markers status=blocked_until_fixture transparent_blocks=pending transparent_faces=pending transparent_draws=pending transparent_subchunks=pending\n'
  printf 'step=future_active_gate status=blocked_until_implementation transparent_active=%s transparent_fallback=%s gpu_upload_fail=%s\n' \
    "$future_active" \
    "$future_fallback" \
    "$future_upload_fail"
  printf 'step=non_goals status=enforced shader_alpha=no transparent_pass=no sorting=no block_id=no asset=no protocol=no storage=no worldgen=no\n'
  printf 'command_generate_plan=sh scripts/gpu_terrain_transparent_fixture_plan.sh docs/GPU_TRANSPARENT_PATH.md %s\n' "$(relative_path "$PLAN_PATH")"
  printf 'command_generate_harness=sh scripts/gpu_terrain_transparent_fixture_harness.sh %s %s\n' \
    "$(relative_path "$PLAN_PATH")" \
    "$(relative_path "$OUT_PATH")"
  printf 'summary transparent_fixture_harness_status=placeholder fixture_plan_status=%s runtime_behavior=%s env_on_expected=%s/%s/%s\n' \
    "$plan_status" \
    "$runtime_behavior" \
    "$requested" \
    "$active" \
    "$fallback"
} > "$tmp_harness"

mv "$tmp_harness" "$OUT_PATH"
cat "$OUT_PATH"
