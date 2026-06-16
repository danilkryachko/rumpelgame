# Fast Full Nightly Test Strategy

Date: 2026-06-15

Scope: block 25 of the world streaming architecture plan. This separates daily fast checks, pre-merge full checks, and heavy/nightly performance checks while preserving sensitive-change guardrails.

## Strategy Gate

Use:

```sh
sh scripts/test_strategy_gate.sh
```

The gate validates that the current check commands and summary-only nightly evidence are wired together. It does not launch heavy Godot/runtime tests by default.

Fresh local evidence:

- Summary: `logs/test_strategy_gate_current/test-strategy-gate-summary.txt`
- Status: `pass`
- Fast command: `./scripts/check.sh fast`
- Full command: `./scripts/check.sh full && git diff --check && ./scripts/diff_guard.sh`
- Nightly runtime command: `RUMPELMC_EXPLORATION_SOAK_REPEATS=3 ./scripts/world_streaming_exploration_soak.sh logs/nightly/world_streaming_exploration_soak && ./scripts/gpu_terrain_load_scaling.sh logs/nightly/gpu_terrain_load_scaling && ./scripts/gpu_terrain_upload_pressure.sh logs/nightly/gpu_terrain_upload_pressure`
- Nightly summary command: `./scripts/gpu_resource_lifecycle_audit.sh logs/gpu_terrain_upload_pressure_smoke && ./scripts/gpu_terrain_memory_budget.sh logs/gpu_terrain_memory_budget_current && ./scripts/gpu_terrain_report_v2.sh logs/gpu_terrain_upload_pressure_smoke logs/gpu_terrain_report_v2_current && ./scripts/gpu_terrain_report_freshness_gate.sh logs/gpu_terrain_report_freshness_current && ./scripts/performance_baseline_governance.sh`
- GPU report freshness: `gpu_report_freshness_status=guarded`

## Fast

Use for normal local development and narrow code changes:

```sh
./scripts/check.sh fast
```

Current scope:

- Go server tests: `go test ./...`
- Rust extension: `cargo check`
- Rust extension: `cargo test`
- Optional Rust `sccache` when available

Fast intentionally avoids Godot runtime captures, external profiler work, and broad diff policy gates.

## Full

Use before handing off a broad patch or when touching sensitive paths:

```sh
./scripts/check.sh full
git diff --check
./scripts/diff_guard.sh
```

Current scope:

- Everything in fast
- Go lint when `golangci-lint` exists
- Rust format check
- Rust clippy with `-D warnings`
- Diff whitespace check
- Sensitive/generated/local-artifact guard

`diff_guard.sh` can emit notices for sensitive paths without failing, but warnings for generated/local/binary artifacts should be resolved or explicitly explained.

## Nightly

Use for heavy performance and world-streaming coverage. This is intentionally separate from `check.sh` so normal development checks do not depend on local logs, a free server port, Godot capture timing, or long-running performance scripts.

Runtime nightly command:

```sh
RUMPELMC_EXPLORATION_SOAK_REPEATS=3 \
  ./scripts/world_streaming_exploration_soak.sh logs/nightly/world_streaming_exploration_soak
./scripts/gpu_terrain_load_scaling.sh logs/nightly/gpu_terrain_load_scaling
./scripts/gpu_terrain_upload_pressure.sh logs/nightly/gpu_terrain_upload_pressure
```

Summary/gate nightly command:

```sh
./scripts/gpu_resource_lifecycle_audit.sh logs/gpu_terrain_upload_pressure_smoke
./scripts/gpu_terrain_memory_budget.sh logs/gpu_terrain_memory_budget_current
./scripts/gpu_terrain_report_v2.sh logs/gpu_terrain_upload_pressure_smoke logs/gpu_terrain_report_v2_current
./scripts/gpu_terrain_report_freshness_gate.sh logs/gpu_terrain_report_freshness_current
./scripts/performance_baseline_governance.sh
```

Nightly runtime artifacts should then feed the summary/gate steps by overriding the documented `RUMPELMC_*_SUMMARY` env vars when using new artifact locations.

## Policy

- Run the narrowest relevant check for small edits.
- Run `./scripts/check.sh fast` for normal code changes.
- Run full plus `diff_guard.sh` for broad or sensitive changes.
- Run nightly runtime checks for performance, GPU, long-run streaming, or release-candidate evidence.
- Keep local FPS/GPU timestamp signals warning-only unless external profiler evidence changes their trust status.
- Keep `gpu_report_freshness_status=guarded` in the test-strategy summary so release-candidate checks do not rely on a stale ignored aggregate GPU report.
