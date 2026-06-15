# Automated Handoff Discipline

Block 45, Automated Handoff Discipline, makes continuation snapshots more automatic without forcing a handoff or rewriting the active handoff document.

## Technical Brief

User request:

Continue the annual world streaming architecture plan in order, use MCP/OntoIndex context, and move to the next block if a local blocker cannot be bypassed.

Goal:

Make handoff/report generation preserve the current evidence chain, changed-file context, and required reading list with less manual reconstruction.

Context inspected:

- OntoIndex concept search for handoff scripts, continuation state, summary logs, git status, and artifact indexes.
- `docs/HANDOFF.md`.
- `docs/AGENT_HANDOFF.md`.
- `scripts/handoff.sh`.
- `docs/OBSERVABILITY_LOGS_CLEANUP.md`.
- `logs/observability_logs_cleanup_current/observability-artifact-index.txt`.

Scope:

- Extend `scripts/handoff.sh` with a handoff quality-input section.
- Extend `scripts/handoff.sh` with the current observability artifact index.
- Add a gate that validates snapshot generation and required sections.
- Keep `docs/AGENT_HANDOFF.md` as the human-authored continuation state.

Out of scope:

- No automatic edits to `docs/AGENT_HANDOFF.md`, no thread creation, no commit creation, no log deletion, no CI upload, no issue tracker integration, and no external service.

Assumptions:

- The current evidence lane is produced by Block 44 and lives under `logs/observability_logs_cleanup_current/`.
- A generated handoff snapshot can be stdout or redirected to a file.
- The active agent remains responsible for updating `docs/AGENT_HANDOFF.md` before actually pausing or delegating non-trivial work.

Done when:

- `scripts/handoff.sh` prints required handoff inputs.
- `scripts/handoff.sh` prints the current evidence index or a fallback current-summary list.
- A gate runs the handoff script and verifies the snapshot structure.

Checks:

- `sh scripts/automated_handoff_discipline_gate.sh logs/automated_handoff_discipline_current`

## Snapshot Contract

`scripts/handoff.sh` now includes:

- `## Handoff Quality Inputs`
- `## Current Handoff State`
- `## Git Status`
- `## Diff Stat`
- `## GPU Terrain Report`
- `## Current Evidence Index`
- `## Recent Logs`

The current evidence index uses `logs/observability_logs_cleanup_current/observability-artifact-index.txt` when present. If the index is missing, the script falls back to listing `logs/*current/*summary.txt`.

## Quality Inputs

The handoff snapshot records whether these files are present:

- `AGENTS.md`
- `docs/HANDOFF.md`
- `docs/AGENT_HANDOFF.md`
- `docs/AGENT_MEMORY.md`
- `docs/WORLD_STREAMING_ARCHITECTURE_REVIEW.md`
- `docs/OBSERVABILITY_LOGS_CLEANUP.md`
- `scripts/handoff.sh`
- `scripts/observability_logs_cleanup_gate.sh`

This is a presence check, not a replacement for reading the files.

## Controls

`RUMPELMC_HANDOFF_SUMMARY_LIMIT` controls how many evidence-index rows are printed. The default is `120`.

`RUMPELMC_HANDOFF_REFRESH_GPU_REPORT=1` keeps the existing behavior of refreshing a temporary GPU report during handoff when requested.

## Deferred Work

Still needed:

- Optional generated Markdown section for latest completed blocks once the 50-block pass is finished.
- Optional JSON handoff manifest after summary conventions stabilize.
- A final manual update to `docs/AGENT_HANDOFF.md` before actually stopping or delegating.
- CI artifact bundle generation.

## Compatibility Rules

- Do not auto-edit `docs/AGENT_HANDOFF.md` from `scripts/handoff.sh`.
- Do not remove existing handoff sections.
- Do not require GPU report refresh by default.
- Do not make missing historical logs fail handoff generation.
- Keep the script shell-only and local.

## Block 45 Gate

Use:

```sh
sh scripts/automated_handoff_discipline_gate.sh logs/automated_handoff_discipline_current
```

The expected current result is `status=pass`, `handoff_status=generated`, `quality_inputs=present`, `evidence_index=present`, and `observability_status=pass`.

The gate checks that:

- This document records the snapshot contract, quality inputs, controls, deferred work, and compatibility rules.
- `scripts/handoff.sh` has the new quality-input and current-evidence-index sections.
- `scripts/handoff.sh` is syntax-clean.
- A generated handoff snapshot includes the required sections.
- The Block 44 observability summary is clean.

## Current Status

This block is complete as a handoff automation checkpoint. The script can generate a richer continuation snapshot, while the active agent still controls when to update `docs/AGENT_HANDOFF.md`.
