# Observability And Logs Cleanup

Block 44, Observability And Logs Cleanup, standardizes the current runtime evidence surface without deleting historical logs or changing existing script parsers.

## Technical Brief

User request:

Continue the annual world streaming architecture plan in order, use MCP/OntoIndex context, and move to the next block if a local blocker cannot be bypassed.

Goal:

Make logs, summary files, artifact naming, error scans, and run IDs consistent enough for long sequential work.

Context inspected:

- OntoIndex concept search for runtime logs, summary artifacts, perf log, debug logs, GPU report, and world streaming scripts.
- `client/hud.gd` perf log writer.
- `scripts/gpu_terrain_report.sh` summary/error-scan conventions.
- Current `logs/*current/*summary.txt` artifacts.
- `docs/TOOLING_DEBUG_OVERLAY.md`.

Scope:

- Add a run ID field to HUD perf-log headers and samples.
- Add a gate that indexes current summary artifacts and checks status, naming, and error patterns.
- Preserve existing `perf=` and summary key/value conventions.
- Document artifact naming and error-scan rules.

Out of scope:

- No log deletion, no history rewrite, no schema migration, no protocol change, no storage change, no renderer behavior change, no new logging dependency, and no new central logging service.

Assumptions:

- Current block gates write one-line key/value summaries ending in `*-summary.txt`.
- `logs/*_current/` and `logs/*_gate_current/` directories represent the current evidence lane for this long-running plan.
- Historical experimental logs can contain failed attempts; cleanup should index them separately later instead of making this block fail.

Done when:

- `client/hud.gd` can stamp perf log samples with a stable `run_id`.
- Current summary files are indexable with a status value.
- Current summaries pass a focused error scan.
- A generated artifact index records path, root token, status, and byte size.

Checks:

- `sh scripts/observability_logs_cleanup_gate.sh logs/observability_logs_cleanup_current`

## Run ID Contract

HUD perf logging now uses `RUMPELMC_RUN_ID` when set. If the environment variable is absent, the client generates `godot-<unix_time>`.

The perf log keeps the existing full diagnostic field:

```text
perf="..."
```

and now also carries:

```text
run_id=<id> overlay="..."
```

The run ID is for correlation only. It must not affect gameplay, networking, storage, rendering, chunk scheduling, or test pass/fail policy.

## Summary Naming

Current block artifacts should use:

- directory: `logs/<block_or_gate>_current/`
- primary summary: `*-summary.txt`
- first field: a stable root token such as `tooling_debug_overlay`
- status field: `status=pass` or `status=deferred` for non-failing current checkpoints

Gate-specific summaries may include additional paths to source summaries, but should keep one-line key/value output for machine parsing.

## Error Scan Policy

The cleanup gate scans current summaries for:

- `ERROR`
- `SCRIPT ERROR`
- `panic`
- `ObjectDB`
- `leaked`
- nonzero `gpu_upload_fail=`
- nonzero `gpu_upload_fail_capacity=`
- nonzero `gpu_upload_fail_fragmented=`

Historical logs are not fail-gated by this block because several plan checkpoints intentionally preserved failed attempts for diagnosis.

## Generated Index

`scripts/observability_logs_cleanup_gate.sh` writes:

- `observability-artifact-index.txt`
- `observability-error-scan.txt`
- `observability-logs-cleanup-summary.txt`

The index is a compact current-lane catalog. It is not a replacement for the original summary files.

When the cleanup gate is rerun after a failed attempt, its own previous `observability-logs-cleanup-summary.txt` must not poison the next run's input status check; the rerun should be able to recover once all other current summaries are clean.

## Deferred Work

Still needed:

- Historical log retention/archival policy.
- Optional JSON export for current summaries after the shell key/value convention stabilizes.
- Runtime Godot smoke with a caller-provided `RUMPELMC_RUN_ID`.
- Cross-script run ID propagation for heavier workload wrappers.
- CI artifact upload/retention mapping.

## Compatibility Rules

- Do not delete old log directories as part of observability cleanup.
- Do not rename existing summary files without updating every consuming gate.
- Keep `perf=` in HUD perf logs while adding `run_id=` and `overlay=`.
- Keep summary files line-oriented and shell/awk friendly.
- Treat historical failed runs as diagnostic evidence, not as current gate failures.

## Block 44 Gate

Use:

```sh
sh scripts/observability_logs_cleanup_gate.sh logs/observability_logs_cleanup_current
```

The expected current result is `status=pass`, `observability_status=indexed`, `run_id_status=wired`, `summary_lane=current`, and `error_scan=clean`.

The gate checks that:

- This document records run IDs, summary naming, error-scan policy, generated index, deferred work, and compatibility rules.
- HUD perf logging has `RUMPELMC_RUN_ID`, `run_id=`, `overlay=`, and full `perf=`.
- Current summary artifacts have `*-summary.txt` naming and `status=pass` or `status=deferred`.
- Current summary artifacts have a clean focused error scan.
- The prior tooling debug overlay summary is clean.

## Current Status

This block is complete as an observability cleanup checkpoint. It standardizes current-run indexing and run ID stamping while preserving historical logs and existing parsers.
