#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/automated_handoff_discipline"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

SUMMARY_PATH="$OUT_DIR/automated-handoff-discipline-summary.txt"
SNAPSHOT_PATH="$OUT_DIR/handoff-snapshot.md"
DESIGN_DOC="${RUMPELMC_HANDOFF_DISCIPLINE_DOC:-"$ROOT_DIR/docs/AUTOMATED_HANDOFF_DISCIPLINE.md"}"
HANDOFF_SCRIPT="${RUMPELMC_HANDOFF_DISCIPLINE_SCRIPT:-"$ROOT_DIR/scripts/handoff.sh"}"
OBSERVABILITY_SUMMARY="${RUMPELMC_HANDOFF_DISCIPLINE_OBSERVABILITY_SUMMARY:-"$ROOT_DIR/logs/observability_logs_cleanup_current/observability-logs-cleanup-summary.txt"}"
OBSERVABILITY_INDEX="${RUMPELMC_HANDOFF_DISCIPLINE_OBSERVABILITY_INDEX:-"$ROOT_DIR/logs/observability_logs_cleanup_current/observability-artifact-index.txt"}"

mkdir -p "$OUT_DIR"

fail() {
  echo "automated_handoff_discipline_gate: $*" >&2
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

for path in "$DESIGN_DOC" "$HANDOFF_SCRIPT" "$OBSERVABILITY_SUMMARY" "$OBSERVABILITY_INDEX"; do
  test -s "$path" || fail "missing required input $path"
done

for token in \
  'Snapshot Contract' \
  'Quality Inputs' \
  'Controls' \
  'Deferred Work' \
  'Compatibility Rules' \
  'Do not auto-edit `docs/AGENT_HANDOFF.md`'; do
  require_token "$DESIGN_DOC" "$token"
done

for token in \
  'print_handoff_quality_inputs' \
  'print_current_evidence_index' \
  'RUMPELMC_HANDOFF_SUMMARY_LIMIT' \
  'observability-artifact-index.txt' \
  '## Handoff Quality Inputs' \
  '## Current Evidence Index'; do
  require_token "$HANDOFF_SCRIPT" "$token"
done

sh -n "$HANDOFF_SCRIPT" || fail "handoff script syntax check failed"

if RUMPELMC_HANDOFF_SUMMARY_LIMIT=40 "$HANDOFF_SCRIPT" > "$SNAPSHOT_PATH" 2> "$OUT_DIR/handoff-stderr.txt"; then
  handoff_status="generated"
else
  cat "$OUT_DIR/handoff-stderr.txt" >&2 || true
  fail "handoff snapshot generation failed"
fi

for token in \
  '# Codex Handoff Snapshot' \
  '## Handoff Quality Inputs' \
  '## Current Handoff State' \
  '## Git Status' \
  '## Diff Stat' \
  '## Current Evidence Index' \
  '## Recent Logs'; do
  require_token "$SNAPSHOT_PATH" "$token"
done

observability_status="$(field_metric status "$OBSERVABILITY_SUMMARY")"
observability_error_scan="$(field_metric error_scan "$OBSERVABILITY_SUMMARY")"
index_count="$(awk 'END { print NR + 0 }' "$OBSERVABILITY_INDEX")"
snapshot_bytes="$(wc -c < "$SNAPSHOT_PATH" | tr -d ' ')"

awk \
  -v handoff_status="$handoff_status" \
  -v observability_status="${observability_status:-missing}" \
  -v observability_error_scan="${observability_error_scan:-dirty}" \
  -v index_count="$index_count" \
  -v snapshot_bytes="$snapshot_bytes" \
  -v snapshot_path="$SNAPSHOT_PATH" \
  -v observability_summary="$OBSERVABILITY_SUMMARY" \
  -v observability_index="$OBSERVABILITY_INDEX" '
  BEGIN {
    status = "pass"
    reason = "ok"
    quality_inputs = "present"
    evidence_index = index_count + 0 > 0 ? "present" : "missing"

    observability_ok = observability_status == "pass" && observability_error_scan == "clean"

    if (handoff_status != "generated") {
      status = "fail"
      reason = "handoff_not_generated"
    } else if (!observability_ok) {
      status = "fail"
      reason = "observability_not_clean"
    } else if (evidence_index != "present") {
      status = "fail"
      reason = "evidence_index_missing"
    } else if (snapshot_bytes + 0 <= 0) {
      status = "fail"
      reason = "empty_snapshot"
    }

    printf("automated_handoff_discipline status=%s reason=%s handoff_status=%s quality_inputs=%s evidence_index=%s evidence_index_rows=%d snapshot_bytes=%d observability_status=%s observability_error_scan=%s snapshot=%s observability_summary=%s observability_index=%s\n", status, reason, handoff_status, quality_inputs, evidence_index, index_count, snapshot_bytes, observability_status, observability_error_scan, snapshot_path, observability_summary, observability_index)
    if (status != "pass") {
      exit 1
    }
  }
' > "$SUMMARY_PATH" || {
  cat "$SUMMARY_PATH" >&2 || true
  fail "automated handoff discipline gate failed"
}

cat "$SUMMARY_PATH"
echo "Automated handoff discipline artifacts: $OUT_DIR"
