#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$ROOT_DIR"

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
echo

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

echo "## Recent Logs"
echo
if [ -d logs ]; then
  find logs -type f -name '*.log' | sort | tail -n 10
else
  echo "No logs directory found."
fi
