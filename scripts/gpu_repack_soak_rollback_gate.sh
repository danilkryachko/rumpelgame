#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/gpu_repack_soak_rollback_gate"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

SUMMARY_PATH="$OUT_DIR/gpu-repack-soak-rollback-summary.txt"
PREFLIGHT_SUMMARY="${RUMPELMC_GPU_REPACK_SOAK_PREFLIGHT_SUMMARY:-"$ROOT_DIR/logs/gpu_repack_activation_preflight_current/gpu-repack-activation-preflight-summary.txt"}"

mkdir -p "$OUT_DIR"

fail() {
  echo "gpu_repack_soak_rollback_gate: $*" >&2
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

test -s "$PREFLIGHT_SUMMARY" || fail "missing repack activation preflight summary $PREFLIGHT_SUMMARY"

preflight_status="$(field_metric status "$PREFLIGHT_SUMMARY")"
active_allowed="$(field_metric active_repack_allowed "$PREFLIGHT_SUMMARY")"
reason="$(field_metric reason "$PREFLIGHT_SUMMARY")"
fragmentation_pct="$(field_metric max_gpu_fragmentation_pct "$PREFLIGHT_SUMMARY")"

awk \
  -v preflight_status="${preflight_status:-blocked}" \
  -v active_allowed="${active_allowed:-0}" \
  -v reason="${reason:-unknown}" \
  -v fragmentation_pct="${fragmentation_pct:-0}" \
  -v preflight_summary="$PREFLIGHT_SUMMARY" '
  BEGIN {
    status = "deferred"
    active_soak_run = 0
    rollback_smoke_required = 0
    gate_reason = "active_repack_not_allowed"
    if (preflight_status == "blocked") {
      status = "blocked"
      gate_reason = "preflight_blocked"
    } else if (active_allowed + 0 != 0) {
      status = "needs_manual_review"
      gate_reason = "active_repack_requires_explicit_soak_plan"
      rollback_smoke_required = 1
    }
    printf("gpu_repack_soak_rollback status=%s active_soak_run=%d rollback_smoke_required=%d reason=%s preflight_status=%s preflight_reason=%s active_repack_allowed=%d max_gpu_fragmentation_pct=%.1f preflight_summary=%s\n", status, active_soak_run, rollback_smoke_required, gate_reason, preflight_status, reason, active_allowed, fragmentation_pct, preflight_summary)
    if (status == "blocked") {
      exit 1
    }
  }
' > "$SUMMARY_PATH" || {
  cat "$SUMMARY_PATH" >&2 || true
  fail "GPU repack soak/rollback gate failed"
}

cat "$SUMMARY_PATH"
echo "GPU repack soak/rollback artifacts: $OUT_DIR"
