#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/gpu_native_shadow_prototype_preflight"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

SUMMARY_PATH="$OUT_DIR/gpu-native-shadow-prototype-preflight-summary.txt"
FALLBACK_SUMMARY="${RUMPELMC_NATIVE_SHADOW_PREFLIGHT_FALLBACK_SUMMARY:-"$ROOT_DIR/logs/gpu_native_shadow_command_buffer_submit_contract_20260614/movement-stress-summary.txt"}"
RESOURCE_SUMMARY="${RUMPELMC_NATIVE_SHADOW_PREFLIGHT_RESOURCE_SUMMARY:-"$ROOT_DIR/logs/gpu_terrain_upload_pressure_smoke/gpu-resource-lifecycle-audit-summary.txt"}"
BASELINE_SUMMARY="${RUMPELMC_NATIVE_SHADOW_PREFLIGHT_BASELINE_SUMMARY:-"$ROOT_DIR/logs/performance_baseline_governance_current/performance-baseline-governance-summary.txt"}"
RUST_SOURCE="${RUMPELMC_NATIVE_SHADOW_PREFLIGHT_RUST_SOURCE:-"$ROOT_DIR/client/rust_ext/src/lib.rs"}"

mkdir -p "$OUT_DIR"

fail() {
  echo "gpu_native_shadow_prototype_preflight: $*" >&2
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

row_field_metric() {
  row="$1"
  key="$2"
  path="$3"
  awk -v row="$row" -v key="$key" '
    $1 == row {
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

test -s "$FALLBACK_SUMMARY" || fail "missing native-shadow fallback summary $FALLBACK_SUMMARY"
test -s "$RESOURCE_SUMMARY" || fail "missing resource lifecycle summary $RESOURCE_SUMMARY"
test -s "$BASELINE_SUMMARY" || fail "missing baseline governance summary $BASELINE_SUMMARY"
test -s "$RUST_SOURCE" || fail "missing Rust source $RUST_SOURCE"

if grep -q 'const GPU_TERRAIN_NATIVE_SHADOW_IMPLEMENTED: bool = false;' "$RUST_SOURCE"; then
  implementation_gate="false"
else
  implementation_gate="changed"
fi

fallback_requested="$(row_field_metric movement_native_shadow requested "$FALLBACK_SUMMARY")"
fallback_active="$(row_field_metric movement_native_shadow active "$FALLBACK_SUMMARY")"
fallback_fallback="$(row_field_metric movement_native_shadow fallback "$FALLBACK_SUMMARY")"
fallback_implemented="$(row_field_metric movement_native_shadow implemented "$FALLBACK_SUMMARY")"
fallback_resource_status="$(row_field_metric movement_native_shadow resource_status "$FALLBACK_SUMMARY")"
fallback_resource_creates="$(row_field_metric movement_native_shadow resource_creates "$FALLBACK_SUMMARY")"
fallback_resource_reuses="$(row_field_metric movement_native_shadow resource_reuses "$FALLBACK_SUMMARY")"
fallback_resource_replaces="$(row_field_metric movement_native_shadow resource_replaces "$FALLBACK_SUMMARY")"
fallback_resource_releases="$(row_field_metric movement_native_shadow resource_releases "$FALLBACK_SUMMARY")"
fallback_covered_chunks="$(row_field_metric movement_native_shadow covered_chunks "$FALLBACK_SUMMARY")"
fallback_covered_subchunks="$(row_field_metric movement_native_shadow covered_subchunks "$FALLBACK_SUMMARY")"
fallback_framebuffer_status="$(row_field_metric movement_native_shadow framebuffer_status "$FALLBACK_SUMMARY")"
fallback_framebuffer_descriptor_valid="$(row_field_metric movement_native_shadow framebuffer_descriptor_valid "$FALLBACK_SUMMARY")"
fallback_framebuffer_descriptor_error_count="$(row_field_metric movement_native_shadow framebuffer_descriptor_error_count "$FALLBACK_SUMMARY")"
fallback_framebuffer_bind_ready="$(row_field_metric movement_native_shadow framebuffer_bind_ready "$FALLBACK_SUMMARY")"
fallback_framebuffer_bind_error_count="$(row_field_metric movement_native_shadow framebuffer_bind_error_count "$FALLBACK_SUMMARY")"
fallback_pass_status="$(row_field_metric movement_native_shadow pass_status "$FALLBACK_SUMMARY")"
fallback_pass_descriptor_valid="$(row_field_metric movement_native_shadow pass_descriptor_valid "$FALLBACK_SUMMARY")"
fallback_pass_descriptor_error_count="$(row_field_metric movement_native_shadow pass_descriptor_error_count "$FALLBACK_SUMMARY")"
fallback_pass_submit_status="$(row_field_metric movement_native_shadow pass_submit_status "$FALLBACK_SUMMARY")"
fallback_pass_lifecycle_ready="$(row_field_metric movement_native_shadow pass_lifecycle_ready "$FALLBACK_SUMMARY")"
fallback_pass_lifecycle_error_count="$(row_field_metric movement_native_shadow pass_lifecycle_error_count "$FALLBACK_SUMMARY")"
fallback_pass_begin_count="$(row_field_metric movement_native_shadow pass_begin_count "$FALLBACK_SUMMARY")"
fallback_pass_end_count="$(row_field_metric movement_native_shadow pass_end_count "$FALLBACK_SUMMARY")"
fallback_command_buffer_status="$(row_field_metric movement_native_shadow command_buffer_status "$FALLBACK_SUMMARY")"
fallback_command_buffer_record_ready="$(row_field_metric movement_native_shadow command_buffer_record_ready "$FALLBACK_SUMMARY")"
fallback_command_buffer_record_error_count="$(row_field_metric movement_native_shadow command_buffer_record_error_count "$FALLBACK_SUMMARY")"
fallback_command_buffer_submit_ready="$(row_field_metric movement_native_shadow command_buffer_submit_ready "$FALLBACK_SUMMARY")"
fallback_command_buffer_submit_error_count="$(row_field_metric movement_native_shadow command_buffer_submit_error_count "$FALLBACK_SUMMARY")"
fallback_command_buffer_submit_count="$(row_field_metric movement_native_shadow command_buffer_submit_count "$FALLBACK_SUMMARY")"
fallback_command_buffer_error_count="$(row_field_metric movement_native_shadow command_buffer_error_count "$FALLBACK_SUMMARY")"

resource_status="$(field_metric resource_lifecycle_audit_status "$RESOURCE_SUMMARY")"
native_shadow_active="$(field_metric native_shadow_active "$RESOURCE_SUMMARY")"
framebuffer_bind_errors="$(field_metric native_shadow_framebuffer_bind_error_count "$RESOURCE_SUMMARY")"
framebuffer_descriptor_errors="$(field_metric native_shadow_framebuffer_descriptor_error_count "$RESOURCE_SUMMARY")"
pass_descriptor_errors="$(field_metric native_shadow_pass_descriptor_error_count "$RESOURCE_SUMMARY")"
pass_lifecycle_errors="$(field_metric native_shadow_pass_lifecycle_error_count "$RESOURCE_SUMMARY")"
command_record_errors="$(field_metric native_shadow_command_buffer_record_error_count "$RESOURCE_SUMMARY")"
command_submit_errors="$(field_metric native_shadow_command_buffer_submit_error_count "$RESOURCE_SUMMARY")"
command_errors="$(field_metric native_shadow_command_buffer_error_count "$RESOURCE_SUMMARY")"

baseline_status="$(field_metric status "$BASELINE_SUMMARY")"
baseline_warning_status="$(field_metric warning_status "$BASELINE_SUMMARY")"

awk \
  -v implementation_gate="$implementation_gate" \
  -v fallback_requested="${fallback_requested:-missing}" \
  -v fallback_active="${fallback_active:-missing}" \
  -v fallback_fallback="${fallback_fallback:-missing}" \
  -v fallback_implemented="${fallback_implemented:-missing}" \
  -v fallback_resource_status="${fallback_resource_status:-missing}" \
  -v fallback_resource_creates="${fallback_resource_creates:-0}" \
  -v fallback_resource_reuses="${fallback_resource_reuses:-0}" \
  -v fallback_resource_replaces="${fallback_resource_replaces:-0}" \
  -v fallback_resource_releases="${fallback_resource_releases:-0}" \
  -v fallback_covered_chunks="${fallback_covered_chunks:-0}" \
  -v fallback_covered_subchunks="${fallback_covered_subchunks:-0}" \
  -v fallback_framebuffer_status="${fallback_framebuffer_status:-missing}" \
  -v fallback_framebuffer_descriptor_valid="${fallback_framebuffer_descriptor_valid:-missing}" \
  -v fallback_framebuffer_descriptor_error_count="${fallback_framebuffer_descriptor_error_count:-missing}" \
  -v fallback_framebuffer_bind_ready="${fallback_framebuffer_bind_ready:-missing}" \
  -v fallback_framebuffer_bind_error_count="${fallback_framebuffer_bind_error_count:-missing}" \
  -v fallback_pass_status="${fallback_pass_status:-missing}" \
  -v fallback_pass_descriptor_valid="${fallback_pass_descriptor_valid:-missing}" \
  -v fallback_pass_descriptor_error_count="${fallback_pass_descriptor_error_count:-missing}" \
  -v fallback_pass_submit_status="${fallback_pass_submit_status:-missing}" \
  -v fallback_pass_lifecycle_ready="${fallback_pass_lifecycle_ready:-missing}" \
  -v fallback_pass_lifecycle_error_count="${fallback_pass_lifecycle_error_count:-missing}" \
  -v fallback_pass_begin_count="${fallback_pass_begin_count:-missing}" \
  -v fallback_pass_end_count="${fallback_pass_end_count:-missing}" \
  -v fallback_command_buffer_status="${fallback_command_buffer_status:-missing}" \
  -v fallback_command_buffer_record_ready="${fallback_command_buffer_record_ready:-missing}" \
  -v fallback_command_buffer_record_error_count="${fallback_command_buffer_record_error_count:-missing}" \
  -v fallback_command_buffer_submit_ready="${fallback_command_buffer_submit_ready:-missing}" \
  -v fallback_command_buffer_submit_error_count="${fallback_command_buffer_submit_error_count:-missing}" \
  -v fallback_command_buffer_submit_count="${fallback_command_buffer_submit_count:-missing}" \
  -v fallback_command_buffer_error_count="${fallback_command_buffer_error_count:-missing}" \
  -v resource_status="${resource_status:-fail}" \
  -v native_shadow_active="${native_shadow_active:-0}" \
  -v framebuffer_bind_errors="${framebuffer_bind_errors:-0}" \
  -v framebuffer_descriptor_errors="${framebuffer_descriptor_errors:-0}" \
  -v pass_descriptor_errors="${pass_descriptor_errors:-0}" \
  -v pass_lifecycle_errors="${pass_lifecycle_errors:-0}" \
  -v command_record_errors="${command_record_errors:-0}" \
  -v command_submit_errors="${command_submit_errors:-0}" \
  -v command_errors="${command_errors:-0}" \
  -v baseline_status="${baseline_status:-fail}" \
  -v baseline_warning_status="${baseline_warning_status:-fail}" \
  -v fallback_summary="$FALLBACK_SUMMARY" \
  -v resource_summary="$RESOURCE_SUMMARY" \
  -v baseline_summary="$BASELINE_SUMMARY" '
  BEGIN {
    status = "deferred"
    active_prototype_allowed = 0
    reason = "implementation_gate_false"

    fallback_ok = fallback_requested == "1" && fallback_active == "0" && fallback_fallback == "1" && fallback_implemented == "0" && fallback_resource_status == "disabled" && fallback_resource_creates + 0 == 0 && fallback_resource_reuses + 0 == 0 && fallback_resource_replaces + 0 == 0 && fallback_resource_releases + 0 == 0 && fallback_covered_chunks + 0 == 0 && fallback_covered_subchunks + 0 == 0
    fallback_readiness_missing = 0
    fallback_readiness_missing += fallback_framebuffer_status == "missing"
    fallback_readiness_missing += fallback_framebuffer_descriptor_valid == "missing"
    fallback_readiness_missing += fallback_framebuffer_descriptor_error_count == "missing"
    fallback_readiness_missing += fallback_framebuffer_bind_ready == "missing"
    fallback_readiness_missing += fallback_framebuffer_bind_error_count == "missing"
    fallback_readiness_missing += fallback_pass_status == "missing"
    fallback_readiness_missing += fallback_pass_descriptor_valid == "missing"
    fallback_readiness_missing += fallback_pass_descriptor_error_count == "missing"
    fallback_readiness_missing += fallback_pass_submit_status == "missing"
    fallback_readiness_missing += fallback_pass_lifecycle_ready == "missing"
    fallback_readiness_missing += fallback_pass_lifecycle_error_count == "missing"
    fallback_readiness_missing += fallback_pass_begin_count == "missing"
    fallback_readiness_missing += fallback_pass_end_count == "missing"
    fallback_readiness_missing += fallback_command_buffer_status == "missing"
    fallback_readiness_missing += fallback_command_buffer_record_ready == "missing"
    fallback_readiness_missing += fallback_command_buffer_record_error_count == "missing"
    fallback_readiness_missing += fallback_command_buffer_submit_ready == "missing"
    fallback_readiness_missing += fallback_command_buffer_submit_error_count == "missing"
    fallback_readiness_missing += fallback_command_buffer_submit_count == "missing"
    fallback_readiness_missing += fallback_command_buffer_error_count == "missing"
    fallback_readiness_fields = fallback_readiness_missing == 0 ? "present" : "missing"
    fallback_readiness_errors = fallback_framebuffer_descriptor_error_count + fallback_framebuffer_bind_error_count + fallback_pass_descriptor_error_count + fallback_pass_lifecycle_error_count + fallback_command_buffer_record_error_count + fallback_command_buffer_submit_error_count + fallback_command_buffer_error_count
    fallback_readiness_clean = fallback_readiness_fields == "present" && fallback_framebuffer_status == "none" && fallback_framebuffer_descriptor_valid + 0 == 0 && fallback_framebuffer_bind_ready + 0 == 0 && fallback_pass_status == "none" && fallback_pass_descriptor_valid + 0 == 0 && fallback_pass_submit_status == "none" && fallback_pass_lifecycle_ready + 0 == 0 && fallback_pass_begin_count + 0 == 0 && fallback_pass_end_count + 0 == 0 && fallback_command_buffer_status == "none" && fallback_command_buffer_record_ready + 0 == 0 && fallback_command_buffer_submit_ready + 0 == 0 && fallback_command_buffer_submit_count + 0 == 0 && fallback_readiness_errors + 0 == 0
    fallback_readiness_status = fallback_readiness_fields == "present" ? (fallback_readiness_clean ? "disabled_clean" : "dirty") : "missing"
    resource_ok = resource_status == "pass" && native_shadow_active + 0 == 0 && framebuffer_bind_errors + 0 == 0 && framebuffer_descriptor_errors + 0 == 0 && pass_descriptor_errors + 0 == 0 && pass_lifecycle_errors + 0 == 0 && command_record_errors + 0 == 0 && command_submit_errors + 0 == 0 && command_errors + 0 == 0
    baseline_ok = baseline_status == "pass" && baseline_warning_status == "ok"

    if (fallback_readiness_fields != "present") {
      status = "blocked"
      reason = "fallback_summary_missing_readiness_fields"
    } else if (!fallback_ok) {
      status = "blocked"
      reason = "fallback_evidence_not_clean"
    } else if (!fallback_readiness_clean) {
      status = "blocked"
      reason = "fallback_readiness_not_clean"
    } else if (!resource_ok) {
      status = "blocked"
      reason = "resource_lifecycle_not_clean"
    } else if (!baseline_ok) {
      status = "blocked"
      reason = "baseline_not_clean"
    } else if (implementation_gate != "false") {
      status = "needs_manual_review"
      active_prototype_allowed = 1
      reason = "implementation_gate_changed_requires_runtime_capture"
    }

    printf("gpu_native_shadow_prototype_preflight status=%s active_prototype_allowed=%d reason=%s implementation_gate=%s fallback_requested=%s fallback_active=%s fallback_fallback=%s fallback_implemented=%s fallback_resource_status=%s fallback_resource_creates=%d fallback_resource_reuses=%d fallback_resource_replaces=%d fallback_resource_releases=%d fallback_covered_chunks=%d fallback_covered_subchunks=%d fallback_readiness_fields=%s fallback_readiness_status=%s fallback_readiness_missing=%d fallback_readiness_errors=%d fallback_framebuffer_status=%s fallback_framebuffer_descriptor_valid=%s fallback_framebuffer_bind_ready=%s fallback_pass_status=%s fallback_pass_descriptor_valid=%s fallback_pass_submit_status=%s fallback_pass_lifecycle_ready=%s fallback_pass_begin_count=%s fallback_pass_end_count=%s fallback_command_buffer_status=%s fallback_command_buffer_record_ready=%s fallback_command_buffer_submit_ready=%s fallback_command_buffer_submit_count=%s resource_status=%s native_shadow_active=%.3f native_shadow_resource_errors=%d baseline_status=%s baseline_warning_status=%s fallback_summary=%s resource_summary=%s baseline_summary=%s\n", status, active_prototype_allowed, reason, implementation_gate, fallback_requested, fallback_active, fallback_fallback, fallback_implemented, fallback_resource_status, fallback_resource_creates, fallback_resource_reuses, fallback_resource_replaces, fallback_resource_releases, fallback_covered_chunks, fallback_covered_subchunks, fallback_readiness_fields, fallback_readiness_status, fallback_readiness_missing, fallback_readiness_errors, fallback_framebuffer_status, fallback_framebuffer_descriptor_valid, fallback_framebuffer_bind_ready, fallback_pass_status, fallback_pass_descriptor_valid, fallback_pass_submit_status, fallback_pass_lifecycle_ready, fallback_pass_begin_count, fallback_pass_end_count, fallback_command_buffer_status, fallback_command_buffer_record_ready, fallback_command_buffer_submit_ready, fallback_command_buffer_submit_count, resource_status, native_shadow_active, framebuffer_bind_errors + framebuffer_descriptor_errors + pass_descriptor_errors + pass_lifecycle_errors + command_record_errors + command_submit_errors + command_errors, baseline_status, baseline_warning_status, fallback_summary, resource_summary, baseline_summary)
    if (status == "blocked") {
      exit 1
    }
  }
' > "$SUMMARY_PATH" || {
  cat "$SUMMARY_PATH" >&2 || true
  fail "GPU native shadow prototype preflight failed"
}

cat "$SUMMARY_PATH"
echo "GPU native shadow prototype preflight artifacts: $OUT_DIR"
