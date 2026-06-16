#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/release_candidate_gate"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

SUMMARY_PATH="$OUT_DIR/release-candidate-gate-summary.txt"
DESIGN_DOC="${RUMPELMC_RC_DOC:-"$ROOT_DIR/docs/RELEASE_CANDIDATE_GATE.md"}"
TEST_STRATEGY_SUMMARY="${RUMPELMC_RC_TEST_STRATEGY_SUMMARY:-"$ROOT_DIR/logs/test_strategy_gate_current/test-strategy-gate-summary.txt"}"
SECURITY_SUMMARY="${RUMPELMC_RC_SECURITY_SUMMARY:-"$ROOT_DIR/logs/security_data_integrity_review_current/security-data-integrity-review-summary.txt"}"
OBSERVABILITY_SUMMARY="${RUMPELMC_RC_OBSERVABILITY_SUMMARY:-"$ROOT_DIR/logs/observability_logs_cleanup_current/observability-logs-cleanup-summary.txt"}"
ARCH_SUMMARY="${RUMPELMC_RC_ARCH_SUMMARY:-"$ROOT_DIR/logs/architecture_documentation_refresh_current/architecture-documentation-refresh-summary.txt"}"
BASELINE_SUMMARY="${RUMPELMC_RC_BASELINE_SUMMARY:-"$ROOT_DIR/logs/performance_baseline_governance_current/performance-baseline-governance-summary.txt"}"
SHADOW_SUMMARY="${RUMPELMC_RC_SHADOW_SUMMARY:-"$ROOT_DIR/logs/shadow_quality_parity_program_current/shadow-quality-parity-summary.txt"}"
TRANSPARENT_SUMMARY="${RUMPELMC_RC_TRANSPARENT_SUMMARY:-"$ROOT_DIR/logs/transparent_fixture_acceptance_suite_current/transparent-fixture-acceptance-suite-summary.txt"}"
LIGHTING_SUMMARY="${RUMPELMC_RC_LIGHTING_SUMMARY:-"$ROOT_DIR/logs/lighting_stability_matrix_current/lighting-stability-matrix-summary.txt"}"
RUN_FAST_CHECKS="${RUMPELMC_RC_RUN_FAST_CHECKS:-0}"
RUN_FULL_CHECKS="${RUMPELMC_RC_RUN_FULL_CHECKS:-0}"
RUN_DIFF_GUARD="${RUMPELMC_RC_RUN_DIFF_GUARD:-0}"
MIN_CURRENT_SUMMARIES="${RUMPELMC_RC_MIN_CURRENT_SUMMARIES:-25}"

mkdir -p "$OUT_DIR"

fail() {
  echo "release_candidate_gate: $*" >&2
  exit 1
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

require_token() {
  path="$1"
  token="$2"
  test -s "$path" || fail "missing file $path"
  grep -Fq "$token" "$path" || fail "missing token '$token' in $path"
}

require_status() {
  label="$1"
  path="$2"
  key="$3"
  expected="$4"
  test -s "$path" || fail "missing $label summary $path"
  value="$(field_metric "$key" "$path")"
  test -n "$value" || fail "missing $key in $path"
  test "$value" = "$expected" || fail "$label $key=$value, expected $expected"
  printf '%s\n' "$value"
}

for path in \
  "$DESIGN_DOC" \
  "$TEST_STRATEGY_SUMMARY" \
  "$SECURITY_SUMMARY" \
  "$OBSERVABILITY_SUMMARY" \
  "$ARCH_SUMMARY" \
  "$BASELINE_SUMMARY" \
  "$SHADOW_SUMMARY" \
  "$TRANSPARENT_SUMMARY" \
  "$LIGHTING_SUMMARY"; do
  test -s "$path" || fail "missing required input $path"
done

for token in \
  'Technical Brief' \
  'RC Gate Contract' \
  'Optional Live Checks' \
  'Current Inputs' \
  'Deferred Work' \
  'Compatibility Rules'; do
  require_token "$DESIGN_DOC" "$token"
done

test -x "$ROOT_DIR/scripts/check.sh" || fail "missing executable scripts/check.sh"
test -x "$ROOT_DIR/scripts/diff_guard.sh" || fail "missing executable scripts/diff_guard.sh"
test -x "$ROOT_DIR/scripts/test_strategy_gate.sh" || fail "missing executable scripts/test_strategy_gate.sh"
test -x "$ROOT_DIR/scripts/security_data_integrity_review_gate.sh" || fail "missing executable scripts/security_data_integrity_review_gate.sh"

test_status="$(require_status test_strategy "$TEST_STRATEGY_SUMMARY" status pass)"
security_status="$(require_status security "$SECURITY_SUMMARY" status pass)"
observability_status="$(require_status observability "$OBSERVABILITY_SUMMARY" status pass)"
arch_status="$(require_status architecture "$ARCH_SUMMARY" status pass)"
baseline_status="$(require_status baseline "$BASELINE_SUMMARY" status pass)"
shadow_status="$(require_status shadow_quality "$SHADOW_SUMMARY" status pass)"
transparent_status="$(require_status transparent_fixture "$TRANSPARENT_SUMMARY" status pass)"
lighting_status="$(require_status lighting "$LIGHTING_SUMMARY" status pass)"

if grep -Fq 'fast_command="./scripts/check.sh fast"' "$TEST_STRATEGY_SUMMARY"; then
  test_fast_command_status="pass"
else
  test_fast_command_status="fail"
fi

if grep -Fq 'full_command="./scripts/check.sh full && git diff --check && ./scripts/diff_guard.sh"' "$TEST_STRATEGY_SUMMARY"; then
  test_full_command_status="pass"
else
  test_full_command_status="fail"
fi

security_protocol_change="$(field_metric active_protocol_change "$SECURITY_SUMMARY")"
security_deterministic_property_tests="$(field_metric deterministic_property_tests "$SECURITY_SUMMARY")"
observability_error_scan="$(field_metric error_scan "$OBSERVABILITY_SUMMARY")"
observability_summary_count="$(field_metric summary_count "$OBSERVABILITY_SUMMARY")"
current_summary_count="$(find "$ROOT_DIR/logs" -maxdepth 3 -path '*current/*summary.txt' -type f | awk 'END { print NR + 0 }')"
arch_runtime_change="$(field_metric runtime_change "$ARCH_SUMMARY")"
baseline_warning_status="$(field_metric warning_status "$BASELINE_SUMMARY")"
shadow_active_native="$(field_metric active_native_comparison "$SHADOW_SUMMARY")"
transparent_active_fixture="$(field_metric active_fixture_acceptance "$TRANSPARENT_SUMMARY")"
lighting_ambient_status="$(field_metric ambient_variant_status "$LIGHTING_SUMMARY")"
proto_diff_count="$(git -C "$ROOT_DIR" diff --name-only -- api/schema/packets.proto server/pkg/api/packets.pb.go | awk 'END { print NR + 0 }')"

fast_check="skipped"
full_check="skipped"
diff_check="skipped"
diff_guard="skipped"

case "$RUN_FAST_CHECKS" in
  0|1) ;;
  *) fail "RUMPELMC_RC_RUN_FAST_CHECKS must be 0 or 1" ;;
esac

case "$RUN_FULL_CHECKS" in
  0|1) ;;
  *) fail "RUMPELMC_RC_RUN_FULL_CHECKS must be 0 or 1" ;;
esac

case "$RUN_DIFF_GUARD" in
  0|1) ;;
  *) fail "RUMPELMC_RC_RUN_DIFF_GUARD must be 0 or 1" ;;
esac

if [ "$RUN_FAST_CHECKS" = "1" ]; then
  if (cd "$ROOT_DIR" && /bin/sh scripts/check.sh fast > "$OUT_DIR/check-fast.txt" 2>&1); then
    fast_check="pass"
  else
    cat "$OUT_DIR/check-fast.txt" >&2 || true
    fast_check="fail"
  fi
fi

if [ "$RUN_FULL_CHECKS" = "1" ]; then
  if (cd "$ROOT_DIR" && /bin/sh scripts/check.sh full > "$OUT_DIR/check-full.txt" 2>&1); then
    full_check="pass"
  else
    cat "$OUT_DIR/check-full.txt" >&2 || true
    full_check="fail"
  fi
fi

if [ "$RUN_DIFF_GUARD" = "1" ]; then
  if (cd "$ROOT_DIR" && git diff --check > "$OUT_DIR/git-diff-check.txt" 2>&1); then
    diff_check="pass"
  else
    cat "$OUT_DIR/git-diff-check.txt" >&2 || true
    diff_check="fail"
  fi

  if [ "$diff_check" = "pass" ] && (cd "$ROOT_DIR" && /bin/sh scripts/diff_guard.sh > "$OUT_DIR/diff-guard.txt" 2>&1); then
    diff_guard="pass"
  elif [ "$diff_check" = "pass" ]; then
    cat "$OUT_DIR/diff-guard.txt" >&2 || true
    diff_guard="fail"
  fi
fi

awk \
  -v test_status="${test_status:-missing}" \
  -v security_status="${security_status:-missing}" \
  -v observability_status="${observability_status:-missing}" \
  -v arch_status="${arch_status:-missing}" \
  -v baseline_status="${baseline_status:-missing}" \
  -v shadow_status="${shadow_status:-missing}" \
  -v transparent_status="${transparent_status:-missing}" \
  -v lighting_status="${lighting_status:-missing}" \
  -v test_fast_command_status="$test_fast_command_status" \
  -v test_full_command_status="$test_full_command_status" \
  -v security_protocol_change="${security_protocol_change:-1}" \
  -v security_deterministic_property_tests="${security_deterministic_property_tests:-missing}" \
  -v observability_error_scan="${observability_error_scan:-dirty}" \
  -v observability_summary_count="${observability_summary_count:-0}" \
  -v current_summary_count="$current_summary_count" \
  -v arch_runtime_change="${arch_runtime_change:-changed}" \
  -v baseline_warning_status="${baseline_warning_status:-missing}" \
  -v shadow_active_native="${shadow_active_native:-missing}" \
  -v transparent_active_fixture="${transparent_active_fixture:-missing}" \
  -v lighting_ambient_status="${lighting_ambient_status:-missing}" \
  -v proto_diff_count="$proto_diff_count" \
  -v min_current_summaries="$MIN_CURRENT_SUMMARIES" \
  -v fast_check="$fast_check" \
  -v full_check="$full_check" \
  -v diff_check="$diff_check" \
  -v diff_guard="$diff_guard" \
  -v test_strategy_summary="$TEST_STRATEGY_SUMMARY" \
  -v security_summary="$SECURITY_SUMMARY" \
  -v observability_summary="$OBSERVABILITY_SUMMARY" \
  -v arch_summary="$ARCH_SUMMARY" \
  -v baseline_summary="$BASELINE_SUMMARY" \
  -v shadow_summary="$SHADOW_SUMMARY" \
  -v transparent_summary="$TRANSPARENT_SUMMARY" \
  -v lighting_summary="$LIGHTING_SUMMARY" '
  BEGIN {
    status = "pass"
    reason = "ok"
    rc_status = "summary_ready"
    perf_matrix = "summary_ready"
    visual_smoke = "summary_ready"
    storage_protocol_compatibility = "guarded"
    live_checks = "skipped"

    summaries_ok = test_status == "pass" &&
      security_status == "pass" &&
      observability_status == "pass" &&
      arch_status == "pass" &&
      baseline_status == "pass" &&
      shadow_status == "pass" &&
      transparent_status == "pass" &&
      lighting_status == "pass"

    if (fast_check == "pass" || full_check == "pass" || diff_check == "pass" || diff_guard == "pass") {
      live_checks = "partial"
    }
    if (fast_check == "pass" && full_check == "pass" && diff_check == "pass" && diff_guard == "pass") {
      live_checks = "full"
    }

    if (!summaries_ok) {
      status = "fail"
      reason = "prerequisite_summary_not_clean"
    } else if (test_fast_command_status != "pass" || test_full_command_status != "pass") {
      status = "fail"
      reason = "test_strategy_command_drift"
    } else if (security_protocol_change + 0 != 0 || proto_diff_count + 0 != 0) {
      status = "fail"
      reason = "protocol_diff_present"
    } else if (security_deterministic_property_tests != "guarded") {
      status = "fail"
      reason = "security_deterministic_property_tests_not_guarded"
    } else if (observability_error_scan != "clean" || current_summary_count + 0 < min_current_summaries + 0) {
      status = "fail"
      reason = "observability_not_clean"
    } else if (arch_runtime_change != "none") {
      status = "fail"
      reason = "architecture_runtime_change"
    } else if (baseline_warning_status != "ok") {
      status = "fail"
      reason = "baseline_warning_status"
    } else if (!(shadow_active_native == "deferred" && transparent_active_fixture == "deferred" && lighting_ambient_status == "deferred")) {
      status = "fail"
      reason = "expected_deferred_visual_lane_changed"
    } else if (fast_check == "fail" || full_check == "fail" || diff_check == "fail" || diff_guard == "fail") {
      status = "fail"
      reason = "live_check_failed"
    }

    printf("release_candidate_gate status=%s reason=%s rc_status=%s perf_matrix=%s visual_smoke=%s storage_protocol_compatibility=%s active_protocol_change=%d security_deterministic_property_tests=%s observability_error_scan=%s observability_summary_count=%d current_summary_count=%d arch_runtime_change=%s baseline_warning_status=%s shadow_active_native=%s transparent_active_fixture=%s lighting_ambient_status=%s live_checks=%s fast_check=%s full_check=%s diff_check=%s diff_guard=%s test_strategy_status=%s test_fast_command=%s test_full_command=%s security_status=%s observability_status=%s arch_status=%s baseline_status=%s shadow_status=%s transparent_status=%s lighting_status=%s test_strategy_summary=%s security_summary=%s observability_summary=%s arch_summary=%s baseline_summary=%s shadow_summary=%s transparent_summary=%s lighting_summary=%s\n", status, reason, rc_status, perf_matrix, visual_smoke, storage_protocol_compatibility, proto_diff_count, security_deterministic_property_tests, observability_error_scan, observability_summary_count, current_summary_count, arch_runtime_change, baseline_warning_status, shadow_active_native, transparent_active_fixture, lighting_ambient_status, live_checks, fast_check, full_check, diff_check, diff_guard, test_status, test_fast_command_status, test_full_command_status, security_status, observability_status, arch_status, baseline_status, shadow_status, transparent_status, lighting_status, test_strategy_summary, security_summary, observability_summary, arch_summary, baseline_summary, shadow_summary, transparent_summary, lighting_summary)
    if (status != "pass") {
      exit 1
    }
  }
' > "$SUMMARY_PATH" || {
  cat "$SUMMARY_PATH" >&2 || true
  fail "release candidate gate failed"
}

cat "$SUMMARY_PATH"
echo "Release candidate gate artifacts: $OUT_DIR"
