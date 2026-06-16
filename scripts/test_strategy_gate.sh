#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/test_strategy_gate_current"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac
SUMMARY_PATH="$OUT_DIR/test-strategy-gate-summary.txt"

EXPLORATION_SOAK_SUMMARY="${RUMPELMC_TEST_STRATEGY_EXPLORATION_SOAK_SUMMARY:-"$ROOT_DIR/logs/world_streaming_exploration_soak_smoke/world-streaming-exploration-soak-summary.txt"}"
LOAD_SCALING_SUMMARY="${RUMPELMC_TEST_STRATEGY_LOAD_SCALING_SUMMARY:-"$ROOT_DIR/logs/gpu_terrain_load_scaling_radius16_summary_check/gpu-terrain-load-scaling-summary.txt"}"
UPLOAD_PRESSURE_SUMMARY="${RUMPELMC_TEST_STRATEGY_UPLOAD_PRESSURE_SUMMARY:-"$ROOT_DIR/logs/gpu_terrain_upload_pressure_smoke/gpu-upload-pressure-summary.txt"}"
RESOURCE_LIFECYCLE_SUMMARY="${RUMPELMC_TEST_STRATEGY_RESOURCE_LIFECYCLE_SUMMARY:-"$ROOT_DIR/logs/gpu_terrain_upload_pressure_smoke/gpu-resource-lifecycle-audit-summary.txt"}"
MEMORY_BUDGET_SUMMARY="${RUMPELMC_TEST_STRATEGY_MEMORY_BUDGET_SUMMARY:-"$ROOT_DIR/logs/gpu_terrain_memory_budget_current/gpu-terrain-memory-budget-summary.txt"}"
REPORT_V2_SUMMARY="${RUMPELMC_TEST_STRATEGY_REPORT_V2_SUMMARY:-"$ROOT_DIR/logs/gpu_terrain_report_v2_current/gpu-terrain-report-v2-summary.txt"}"
GPU_REPORT_FRESHNESS_DIR="${RUMPELMC_TEST_STRATEGY_GPU_REPORT_FRESHNESS_DIR:-"$ROOT_DIR/logs/gpu_terrain_report_freshness_current"}"
GPU_REPORT_FRESHNESS_SUMMARY="${RUMPELMC_TEST_STRATEGY_GPU_REPORT_FRESHNESS_SUMMARY:-"$GPU_REPORT_FRESHNESS_DIR/gpu-terrain-report-freshness-summary.txt"}"
RUN_GPU_REPORT_FRESHNESS="${RUMPELMC_TEST_STRATEGY_RUN_GPU_REPORT_FRESHNESS:-1}"
BASELINE_GOVERNANCE_SUMMARY="${RUMPELMC_TEST_STRATEGY_BASELINE_GOVERNANCE_SUMMARY:-"$ROOT_DIR/logs/performance_baseline_governance_current/performance-baseline-governance-summary.txt"}"

mkdir -p "$OUT_DIR"

fail() {
  echo "test_strategy_gate: $*" >&2
  exit 1
}

relative_path() {
  path="$1"
  case "$path" in
    "$ROOT_DIR"/*) printf '%s\n' "${path#$ROOT_DIR/}" ;;
    *) printf '%s\n' "$path" ;;
  esac
}

field_metric() {
  key="$1"
  path="$2"
  awk -v key="$key" '
    {
      prefix = key "="
      for (i = 1; i <= NF; i++) {
        if (index($i, prefix) == 1) {
          value = substr($i, length(prefix) + 1)
          gsub(/^"/, "", value)
          gsub(/"$/, "", value)
          print value
          exit
        }
      }
    }
  ' "$path"
}

require_status() {
  label="$1"
  path="$2"
  key="$3"
  expected="$4"
  test -s "$path" || fail "missing $label summary $path"
  value="$(field_metric "$key" "$path")"
  test -n "$value" || fail "missing $key in $(relative_path "$path")"
  if [ "$value" != "$expected" ]; then
    fail "$label $key=$value, expected $expected"
  fi
  printf '%s\n' "$value"
}

test -x "$ROOT_DIR/scripts/check.sh" || fail "missing executable scripts/check.sh"
test -x "$ROOT_DIR/scripts/diff_guard.sh" || fail "missing executable scripts/diff_guard.sh"
test -x "$ROOT_DIR/scripts/world_streaming_exploration_soak.sh" || fail "missing executable world streaming soak wrapper"
test -x "$ROOT_DIR/scripts/gpu_terrain_load_scaling.sh" || fail "missing executable load scaling wrapper"
test -x "$ROOT_DIR/scripts/gpu_terrain_upload_pressure.sh" || fail "missing executable upload pressure wrapper"
test -x "$ROOT_DIR/scripts/gpu_resource_lifecycle_audit.sh" || fail "missing executable resource lifecycle audit"
test -x "$ROOT_DIR/scripts/gpu_terrain_memory_budget.sh" || fail "missing executable memory budget gate"
test -x "$ROOT_DIR/scripts/gpu_terrain_report_v2.sh" || fail "missing executable report V2 wrapper"
test -x "$ROOT_DIR/scripts/gpu_terrain_report_freshness_gate.sh" || fail "missing executable report freshness gate"
test -x "$ROOT_DIR/scripts/performance_baseline_governance.sh" || fail "missing executable baseline governance wrapper"

case "$RUN_GPU_REPORT_FRESHNESS" in
  0|1) ;;
  *) fail "RUMPELMC_TEST_STRATEGY_RUN_GPU_REPORT_FRESHNESS must be 0 or 1" ;;
esac

if [ "$RUN_GPU_REPORT_FRESHNESS" = "1" ]; then
  sh "$ROOT_DIR/scripts/gpu_terrain_report_freshness_gate.sh" "$GPU_REPORT_FRESHNESS_DIR" >/dev/null
fi

exploration_status="$(require_status exploration_soak "$EXPLORATION_SOAK_SUMMARY" status pass)"
load_status="$(require_status load_scaling "$LOAD_SCALING_SUMMARY" status pass)"
upload_status="$(require_status upload_pressure "$UPLOAD_PRESSURE_SUMMARY" status pass)"
resource_status="$(require_status resource_lifecycle "$RESOURCE_LIFECYCLE_SUMMARY" resource_lifecycle_audit_status pass)"
memory_status="$(require_status memory_budget "$MEMORY_BUDGET_SUMMARY" status pass)"
report_v2_status="$(require_status report_v2 "$REPORT_V2_SUMMARY" status pass)"
gpu_report_status="$(require_status gpu_report_freshness "$GPU_REPORT_FRESHNESS_SUMMARY" status pass)"
gpu_report_freshness="$(require_status gpu_report_freshness "$GPU_REPORT_FRESHNESS_SUMMARY" freshness_status current)"
gpu_report_error_scan="$(require_status gpu_report_freshness "$GPU_REPORT_FRESHNESS_SUMMARY" report_error_scan clean)"
gpu_report_upload_fail="$(require_status gpu_report_freshness "$GPU_REPORT_FRESHNESS_SUMMARY" gpu_upload_fail 0)"
gpu_report_upload_fail_capacity="$(require_status gpu_report_freshness "$GPU_REPORT_FRESHNESS_SUMMARY" gpu_upload_fail_capacity 0)"
gpu_report_upload_fail_fragmented="$(require_status gpu_report_freshness "$GPU_REPORT_FRESHNESS_SUMMARY" gpu_upload_fail_fragmented 0)"
baseline_status="$(require_status baseline_governance "$BASELINE_GOVERNANCE_SUMMARY" status pass)"

{
  printf 'test_strategy_gate status=pass fast_command="%s" full_command="%s" nightly_runtime_command="%s" nightly_summary_command="%s" exploration_soak_status=%s load_scaling_status=%s upload_pressure_status=%s resource_lifecycle_status=%s memory_budget_status=%s report_v2_status=%s gpu_report_freshness_status=%s gpu_report_freshness=%s gpu_report_error_scan=%s gpu_report_upload_fail=%s gpu_report_upload_fail_capacity=%s gpu_report_upload_fail_fragmented=%s baseline_governance_status=%s exploration_soak_summary=%s load_scaling_summary=%s upload_pressure_summary=%s resource_lifecycle_summary=%s memory_budget_summary=%s report_v2_summary=%s gpu_report_freshness_summary=%s baseline_governance_summary=%s\n' \
    './scripts/check.sh fast' \
    './scripts/check.sh full && git diff --check && ./scripts/diff_guard.sh' \
    'RUMPELMC_EXPLORATION_SOAK_REPEATS=3 ./scripts/world_streaming_exploration_soak.sh logs/nightly/world_streaming_exploration_soak && ./scripts/gpu_terrain_load_scaling.sh logs/nightly/gpu_terrain_load_scaling && ./scripts/gpu_terrain_upload_pressure.sh logs/nightly/gpu_terrain_upload_pressure' \
    './scripts/gpu_resource_lifecycle_audit.sh logs/gpu_terrain_upload_pressure_smoke && ./scripts/gpu_terrain_memory_budget.sh logs/gpu_terrain_memory_budget_current && ./scripts/gpu_terrain_report_v2.sh logs/gpu_terrain_upload_pressure_smoke logs/gpu_terrain_report_v2_current && ./scripts/gpu_terrain_report_freshness_gate.sh logs/gpu_terrain_report_freshness_current && ./scripts/performance_baseline_governance.sh' \
    "$exploration_status" \
    "$load_status" \
    "$upload_status" \
    "$resource_status" \
    "$memory_status" \
    "$report_v2_status" \
    "guarded" \
    "$gpu_report_freshness" \
    "$gpu_report_error_scan" \
    "$gpu_report_upload_fail" \
    "$gpu_report_upload_fail_capacity" \
    "$gpu_report_upload_fail_fragmented" \
    "$baseline_status" \
    "$(relative_path "$EXPLORATION_SOAK_SUMMARY")" \
    "$(relative_path "$LOAD_SCALING_SUMMARY")" \
    "$(relative_path "$UPLOAD_PRESSURE_SUMMARY")" \
    "$(relative_path "$RESOURCE_LIFECYCLE_SUMMARY")" \
    "$(relative_path "$MEMORY_BUDGET_SUMMARY")" \
    "$(relative_path "$REPORT_V2_SUMMARY")" \
    "$(relative_path "$GPU_REPORT_FRESHNESS_SUMMARY")" \
    "$(relative_path "$BASELINE_GOVERNANCE_SUMMARY")"
} > "$SUMMARY_PATH"

cat "$SUMMARY_PATH"
