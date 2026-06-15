#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/external_profiling_campaign"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

SUMMARY_PATH="$OUT_DIR/external-profiling-campaign-summary.txt"
PLAN_PATH="$OUT_DIR/external-profiling-campaign-plan.txt"
DESIGN_DOC="${RUMPELMC_EXTERNAL_PROFILING_DOC:-"$ROOT_DIR/docs/EXTERNAL_PROFILING_CAMPAIGN.md"}"
GPU_PROFILING_DOC="${RUMPELMC_EXTERNAL_PROFILING_GPU_DOC:-"$ROOT_DIR/docs/GPU_PROFILING.md"}"
SHADOW_SUMMARY="${RUMPELMC_EXTERNAL_PROFILING_SHADOW_SUMMARY:-"$ROOT_DIR/logs/shadow_quality_parity_program_current/shadow-quality-parity-summary.txt"}"
RC_SUMMARY="${RUMPELMC_EXTERNAL_PROFILING_RC_SUMMARY:-"$ROOT_DIR/logs/release_candidate_gate_current/release-candidate-gate-summary.txt"}"
CAPTURE_PACK="${RUMPELMC_EXTERNAL_PROFILING_CAPTURE_PACK:-"$ROOT_DIR/logs/gpu_shadow_radius_matrix_wide/shadow-radius-profiler-capture-pack.txt"}"
PLAN_INPUT="${RUMPELMC_EXTERNAL_PROFILING_PLAN_INPUT:-"$ROOT_DIR/logs/gpu_shadow_radius_matrix_wide/shadow-radius-profiler-plan.txt"}"
RESULTS_PATH="${RUMPELMC_EXTERNAL_PROFILING_RESULTS:-"$ROOT_DIR/logs/gpu_shadow_radius_matrix_wide/shadow-radius-profiler-results.txt"}"
RESULTS_SUMMARY="${RUMPELMC_EXTERNAL_PROFILING_RESULTS_SUMMARY:-"$ROOT_DIR/logs/gpu_shadow_radius_matrix_wide/shadow-radius-profiler-results-summary.txt"}"

mkdir -p "$OUT_DIR"

fail() {
  echo "external_profiling_campaign_gate: $*" >&2
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

relative_path() {
  path="$1"
  case "$path" in
    "$ROOT_DIR"/*) printf '%s\n' "${path#$ROOT_DIR/}" ;;
    *) printf '%s\n' "$path" ;;
  esac
}

for path in \
  "$DESIGN_DOC" \
  "$GPU_PROFILING_DOC" \
  "$SHADOW_SUMMARY" \
  "$RC_SUMMARY" \
  "$CAPTURE_PACK"; do
  test -s "$path" || fail "missing required input $path"
done

for token in \
  'Technical Brief' \
  'Profiler Evidence Policy' \
  'Capture Matrix' \
  'Current Campaign Status' \
  'Deferred Work' \
  'Compatibility Rules'; do
  require_token "$DESIGN_DOC" "$token"
done

for token in \
  'macOS Metal Workflow' \
  'Windows Workflow' \
  'Godot `RenderingDevice` timestamp samples currently report `0.0us`' \
  'Use the profiler plan guard before external capture handoff'; do
  require_token "$GPU_PROFILING_DOC" "$token"
done

test -x "$ROOT_DIR/scripts/gpu_terrain_shadow_profiler_capture_pack.sh" || fail "missing executable shadow profiler capture pack script"
test -x "$ROOT_DIR/scripts/gpu_terrain_shadow_profiler_results_check.sh" || fail "missing executable shadow profiler results checker"
test -x "$ROOT_DIR/scripts/release_candidate_gate.sh" || fail "missing executable release candidate gate"

shadow_status="$(field_metric status "$SHADOW_SUMMARY")"
shadow_profiler_status="$(field_metric profiler_status "$SHADOW_SUMMARY")"
shadow_profiler_rows="$(field_metric profiler_rows "$SHADOW_SUMMARY")"
rc_status="$(field_metric status "$RC_SUMMARY")"
rc_visual_smoke="$(field_metric visual_smoke "$RC_SUMMARY")"
rc_perf_matrix="$(field_metric perf_matrix "$RC_SUMMARY")"
capture_pack_status="$(field_metric capture_pack_status "$CAPTURE_PACK")"
capture_pack_rows="$(field_metric rows "$CAPTURE_PACK")"
results_file_status="$(field_metric results_file_status "$CAPTURE_PACK")"

external_profile_status="pending_external_profiler"
results_check_status="missing"
captured_rows="0"
missing_rows="$capture_pack_rows"

if [ -s "$RESULTS_PATH" ]; then
  if sh "$ROOT_DIR/scripts/gpu_terrain_shadow_profiler_results_check.sh" "$PLAN_INPUT" "$RESULTS_PATH" "$RESULTS_SUMMARY" > "$OUT_DIR/shadow-profiler-results-check.txt" 2>&1; then
    results_check_status="pass"
    external_profile_status="$(field_metric external_profile_status "$RESULTS_SUMMARY")"
    captured_rows="$(field_metric captured_rows "$RESULTS_SUMMARY")"
    missing_rows="$(field_metric missing_rows "$RESULTS_SUMMARY")"
  else
    cat "$OUT_DIR/shadow-profiler-results-check.txt" >&2 || true
    results_check_status="fail"
  fi
fi

{
  printf 'external_profiling_campaign_plan status=prepared\n'
  printf 'lane=macos_metal_shadow_proxy platform=macos tool=xcode_metal status=%s workload=shadow_radius_matrix capture_pack=%s results=%s validation=%s\n' \
    "$external_profile_status" \
    "$(relative_path "$CAPTURE_PACK")" \
    "$(relative_path "$RESULTS_PATH")" \
    'scripts/gpu_terrain_shadow_profiler_results_check.sh'
  printf 'lane=windows_gpu_shadow_proxy platform=windows tool=pix_renderdoc_or_vendor status=pending_external_machine workload=shadow_radius_matrix capture_pack=%s results=external_artifact_required validation=repeat_plan_and_record_driver_gpu_backend\n' \
    "$(relative_path "$CAPTURE_PACK")"
  printf 'lane=linux_vulkan_shadow_proxy platform=linux tool=renderdoc_or_vulkan_profiler status=deferred_optional workload=shadow_radius_matrix capture_pack=%s results=external_artifact_required validation=only_if_backend_available\n' \
    "$(relative_path "$CAPTURE_PACK")"
  printf 'policy pending_capture_pack_is_not_evidence=1 local_fps_is_warning_only=1 godot_gpu_timestamp_is_warning_only=1\n'
} > "$PLAN_PATH"

awk \
  -v shadow_status="${shadow_status:-missing}" \
  -v shadow_profiler_status="${shadow_profiler_status:-missing}" \
  -v shadow_profiler_rows="${shadow_profiler_rows:-0}" \
  -v rc_status="${rc_status:-missing}" \
  -v rc_visual_smoke="${rc_visual_smoke:-missing}" \
  -v rc_perf_matrix="${rc_perf_matrix:-missing}" \
  -v capture_pack_status="${capture_pack_status:-missing}" \
  -v capture_pack_rows="${capture_pack_rows:-0}" \
  -v results_file_status="${results_file_status:-missing}" \
  -v external_profile_status="$external_profile_status" \
  -v results_check_status="$results_check_status" \
  -v captured_rows="${captured_rows:-0}" \
  -v missing_rows="${missing_rows:-0}" \
  -v plan_path="$PLAN_PATH" \
  -v capture_pack="$CAPTURE_PACK" \
  -v results_path="$RESULTS_PATH" \
  -v results_summary="$RESULTS_SUMMARY" \
  -v shadow_summary="$SHADOW_SUMMARY" \
  -v rc_summary="$RC_SUMMARY" '
  BEGIN {
    status = "pass"
    reason = "external_profiler_pending"
    campaign_status = "prepared"
    macos_metal_status = external_profile_status
    windows_gpu_status = "pending_external_machine"
    linux_vulkan_status = "deferred_optional"

    if (!(shadow_status == "pass" && shadow_profiler_status == "pending_external_profiler" && shadow_profiler_rows + 0 >= 4)) {
      status = "fail"
      reason = "shadow_profiler_plan_not_pending"
    } else if (!(rc_status == "pass" && rc_visual_smoke == "summary_ready" && rc_perf_matrix == "summary_ready")) {
      status = "fail"
      reason = "release_candidate_evidence_not_clean"
    } else if (!(capture_pack_status == "pending_external_profiler" && capture_pack_rows + 0 >= 4)) {
      status = "fail"
      reason = "capture_pack_not_pending"
    } else if (results_check_status == "fail") {
      status = "fail"
      reason = "profiler_results_invalid"
    } else if (results_check_status == "pass" && external_profile_status != "captured") {
      status = "fail"
      reason = "profiler_results_not_captured"
    }

    if (results_check_status == "pass") {
      reason = "validated_external_results"
      macos_metal_status = "captured"
    }

    printf("external_profiling_campaign status=%s reason=%s campaign_status=%s external_profile_status=%s macos_metal_status=%s windows_gpu_status=%s linux_vulkan_status=%s capture_pack_status=%s capture_pack_rows=%d results_file_status=%s results_check_status=%s captured_rows=%d missing_rows=%d shadow_status=%s shadow_profiler_status=%s rc_status=%s rc_visual_smoke=%s rc_perf_matrix=%s plan=%s capture_pack=%s results=%s results_summary=%s shadow_summary=%s rc_summary=%s\n", status, reason, campaign_status, external_profile_status, macos_metal_status, windows_gpu_status, linux_vulkan_status, capture_pack_status, capture_pack_rows, results_file_status, results_check_status, captured_rows, missing_rows, shadow_status, shadow_profiler_status, rc_status, rc_visual_smoke, rc_perf_matrix, plan_path, capture_pack, results_path, results_summary, shadow_summary, rc_summary)
    if (status != "pass") {
      exit 1
    }
  }
' > "$SUMMARY_PATH" || {
  cat "$SUMMARY_PATH" >&2 || true
  fail "external profiling campaign gate failed"
}

cat "$SUMMARY_PATH"
echo "External profiling campaign artifacts: $OUT_DIR"
