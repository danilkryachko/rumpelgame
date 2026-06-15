#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$ROOT_DIR"
HANDOFF_SUMMARY_LIMIT="${RUMPELMC_HANDOFF_SUMMARY_LIMIT:-120}"

print_handoff_quality_inputs() {
  echo "## Handoff Quality Inputs"
  echo
  for path in \
    AGENTS.md \
    docs/HANDOFF.md \
    docs/AGENT_HANDOFF.md \
    docs/AGENT_MEMORY.md \
    docs/WORLD_STREAMING_ARCHITECTURE_REVIEW.md \
    docs/OBSERVABILITY_LOGS_CLEANUP.md \
    scripts/handoff.sh \
    scripts/observability_logs_cleanup_gate.sh; do
    if [ -e "$path" ]; then
      printf '%s\n' "- \`$path\` status=present"
    else
      printf '%s\n' "- \`$path\` status=missing"
    fi
  done
  echo
}

print_current_evidence_index() {
  echo "## Current Evidence Index"
  echo
  index_path="logs/observability_logs_cleanup_current/observability-artifact-index.txt"
  if [ -s "$index_path" ]; then
    echo "Source: \`$index_path\`"
    echo
    sed -n "1,${HANDOFF_SUMMARY_LIMIT}p" "$index_path"
    echo
    return
  fi

  if [ -d logs ]; then
    echo "No generated observability index found. Current summaries discovered from logs:"
    echo
    find logs -maxdepth 3 -path '*current/*summary.txt' -type f | sort | sed "s#^#- #"
    echo
  else
    echo "No logs directory found."
    echo
  fi
}

print_gpu_report() {
  report_path="${TMPDIR:-/tmp}/rumpel-handoff-gpu-terrain-report-$$.txt"

  if [ "${RUMPELMC_HANDOFF_REFRESH_GPU_REPORT:-0}" = "1" ] && [ -d logs ] && [ -f scripts/gpu_terrain_report.sh ]; then
    if sh scripts/gpu_terrain_report.sh logs "$report_path" >/dev/null 2>&1; then
      echo "## GPU Terrain Report"
      echo
      sed -n '1,120p' "$report_path"
      echo
      rm -f "$report_path"
      return
    fi
    rm -f "$report_path"
  fi

  if [ -f logs/gpu-terrain-report.txt ]; then
    current_commit="$(git rev-parse --short HEAD 2>/dev/null || printf 'unknown')"
    report_commit="$(sed -n 's/^Git commit: `\([^`]*\)`.*/\1/p' logs/gpu-terrain-report.txt | sed -n '1p')"

    echo "## GPU Terrain Report"
    echo
    if [ -n "$report_commit" ] && [ "$report_commit" != "$current_commit" ]; then
      echo "Existing report artifact is stale: report commit \`$report_commit\`, current commit \`$current_commit\`."
      echo "Set \`RUMPELMC_HANDOFF_REFRESH_GPU_REPORT=1\` to generate a fresh temporary report during handoff."
      echo
      return
    fi

    sed -n '1,120p' logs/gpu-terrain-report.txt
    echo
  fi
}

echo "# Codex Handoff Snapshot"
echo
echo "Generated: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
echo "Root: $ROOT_DIR"
echo

echo "## Read First"
echo
echo "- AGENTS.md"
echo "- docs/HANDOFF.md"
echo "- docs/AGENT_HANDOFF.md"
echo "- docs/GPU_ROADMAP.md"
echo "- docs/GPU_PROFILING.md"
echo "- docs/GPU_TRENDS.md"
echo

print_handoff_quality_inputs

if [ -f docs/AGENT_HANDOFF.md ]; then
  echo "## Current Handoff State"
  echo
  sed -n '1,220p' docs/AGENT_HANDOFF.md
  echo
fi

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "## Git Status"
  echo
  git status --short || true
  echo

  echo "## Diff Stat"
  echo
  git diff --stat || true
  echo

  echo "## Recent Commits"
  echo
  git log -5 --oneline || true
  echo
else
  echo "## Git"
  echo
  echo "Not inside a git work tree."
  echo
fi

if [ -f docs/GPU_TRENDS.md ]; then
  echo "## GPU Trends"
  echo
  sed -n '1,120p' docs/GPU_TRENDS.md
  echo
fi

print_gpu_report

print_current_evidence_index

echo "## Recent Logs"
echo
if [ -d logs ]; then
  find logs -type f -name '*.log' | sort | tail -n 10
else
  echo "No logs directory found."
fi
