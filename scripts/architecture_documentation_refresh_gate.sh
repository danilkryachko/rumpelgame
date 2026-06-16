#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/architecture_documentation_refresh"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

SUMMARY_PATH="$OUT_DIR/architecture-documentation-refresh-summary.txt"
DESIGN_DOC="${RUMPELMC_ARCH_REFRESH_DOC:-"$ROOT_DIR/docs/ARCHITECTURE_DOCUMENTATION_REFRESH.md"}"
ARCH_DOC="${RUMPELMC_ARCH_DOC:-"$ROOT_DIR/docs/ARCHITECTURE.md"}"
HANDOFF_SUMMARY="${RUMPELMC_ARCH_REFRESH_HANDOFF_SUMMARY:-"$ROOT_DIR/logs/automated_handoff_discipline_current/automated-handoff-discipline-summary.txt"}"

mkdir -p "$OUT_DIR"

fail() {
  echo "architecture_documentation_refresh_gate: $*" >&2
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

for path in \
  "$DESIGN_DOC" \
  "$ARCH_DOC" \
  "$HANDOFF_SUMMARY" \
  "$ROOT_DIR/docs/PROTOCOL.md" \
  "$ROOT_DIR/docs/STORAGE.md" \
  "$ROOT_DIR/docs/WORLD_STREAMING.md" \
  "$ROOT_DIR/docs/GPU_SHADOW_PATH.md" \
  "$ROOT_DIR/docs/GPU_TRANSPARENT_PATH.md" \
  "$ROOT_DIR/docs/OBSERVABILITY_LOGS_CLEANUP.md" \
  "$ROOT_DIR/docs/AUTOMATED_HANDOFF_DISCIPLINE.md"; do
  test -s "$path" || fail "missing required input $path"
done

for token in \
  'Technical Brief' \
  'Refreshed Areas' \
  'Deferred Work' \
  'Compatibility Rules' \
  'Do not use architecture refresh as permission to change runtime behavior'; do
  require_token "$DESIGN_DOC" "$token"
done

for token in \
  '## Stack' \
  '## Current Runtime Flow' \
  '## Server World And Storage' \
  '## Protocol Contract' \
  '## Client Rust GDExtension' \
  '## GPU Terrain Contract' \
  '## Observability And Handoff' \
  '## Guardrails' \
  'RLE by default' \
  'RocksDB chunk keys' \
  'GPU_TERRAIN_NATIVE_SHADOW_IMPLEMENTED=false' \
  'GPU_TERRAIN_TRANSPARENT_IMPLEMENTED=false' \
  'run_id='; do
  require_token "$ARCH_DOC" "$token"
done

handoff_status="$(field_metric status "$HANDOFF_SUMMARY")"
handoff_evidence_index="$(field_metric evidence_index "$HANDOFF_SUMMARY")"
handoff_gpu_report_freshness="$(field_metric observability_gpu_report_freshness "$HANDOFF_SUMMARY")"

awk \
  -v handoff_status="${handoff_status:-missing}" \
  -v handoff_evidence_index="${handoff_evidence_index:-missing}" \
  -v handoff_gpu_report_freshness="${handoff_gpu_report_freshness:-missing}" \
  -v arch_doc="$ARCH_DOC" \
  -v design_doc="$DESIGN_DOC" \
  -v handoff_summary="$HANDOFF_SUMMARY" '
  BEGIN {
    status = "pass"
    reason = "ok"
    architecture_status = "refreshed"
    runtime_change = "none"
    handoff_ok = handoff_status == "pass" && handoff_evidence_index == "present" && handoff_gpu_report_freshness == "guarded"

    if (!handoff_ok) {
      status = "fail"
      reason = "handoff_automation_not_clean"
    }

    printf("architecture_documentation_refresh status=%s reason=%s architecture_status=%s runtime_change=%s handoff_status=%s handoff_evidence_index=%s handoff_gpu_report_freshness=%s arch_doc=%s design_doc=%s handoff_summary=%s\n", status, reason, architecture_status, runtime_change, handoff_status, handoff_evidence_index, handoff_gpu_report_freshness, arch_doc, design_doc, handoff_summary)
    if (status != "pass") {
      exit 1
    }
  }
' > "$SUMMARY_PATH" || {
  cat "$SUMMARY_PATH" >&2 || true
  fail "architecture documentation refresh gate failed"
}

cat "$SUMMARY_PATH"
echo "Architecture documentation refresh artifacts: $OUT_DIR"
