# Release Candidate Gate

Block 48, Release Candidate Gate, defines one reproducible readiness gate over the current world-streaming, GPU, observability, architecture, and data-integrity evidence.

## Technical Brief

User request:

Run the year-plan blocks in order and do not forget MCP.

Goal:

Add a single release-candidate gate that composes the current check strategy, performance evidence, visual smoke evidence, observability cleanup, architecture refresh, and security/data-integrity review without changing runtime behavior.

Context to inspect:

- `docs/TEST_STRATEGY.md`
- `docs/SECURITY_DATA_INTEGRITY_REVIEW.md`
- `docs/OBSERVABILITY_LOGS_CLEANUP.md`
- `docs/ARCHITECTURE_DOCUMENTATION_REFRESH.md`
- `docs/PERFORMANCE_BASELINE_GOVERNANCE.md`
- `docs/SHADOW_QUALITY_PARITY_PROGRAM.md`
- `docs/TRANSPARENT_FIXTURE_ACCEPTANCE_SUITE.md`
- `docs/LIGHTING_STABILITY_MATRIX.md`

Scope:

- Add `scripts/release_candidate_gate.sh`.
- Add this document.
- Validate prerequisite summary artifacts and command wiring.
- Preserve optional live fast/full/diff checks behind explicit environment flags.

Out of scope:

- Do not run heavy Godot/nightly profiler workloads by default.
- Do not change protocol, storage, worldgen, rendering, draw distance, lighting, or gameplay behavior.
- Do not rename or delete existing log artifacts.

Assumptions:

- Current `logs/*current/*summary.txt` artifacts are the canonical short-lived evidence lane.
- `scripts/test_strategy_gate.sh` remains the source of truth for daily fast, pre-merge full, and nightly command names.
- RC evidence can pass in summary mode only if security, observability, architecture, baseline, visual, and lighting summaries are clean.

Implementation plan:

- Check required docs and scripts are present.
- Check prerequisite summaries report expected pass/deferred states.
- Verify no active protobuf schema/generated diff is present.
- Optionally execute live `check.sh fast`, `check.sh full`, `git diff --check`, and `diff_guard.sh` when requested.
- Emit one compact summary artifact.

Done when:

- `scripts/release_candidate_gate.sh` produces `release-candidate-gate-summary.txt` with `status=pass`.
- The gate records skipped or passed live checks explicitly.
- World-streaming docs point to the RC gate.

Checks:

- `sh -n scripts/release_candidate_gate.sh`
- `/bin/sh scripts/release_candidate_gate.sh logs/release_candidate_gate_current`
- `RUMPELMC_RC_RUN_FAST_CHECKS=1 RUMPELMC_RC_RUN_FULL_CHECKS=1 RUMPELMC_RC_RUN_DIFF_GUARD=1 /bin/sh scripts/release_candidate_gate.sh logs/release_candidate_gate_current`

Review gates:

- Treat this as release/process infrastructure only. Sensitive runtime changes still need their own focused tests and review pass.

## RC Gate Contract

The default gate is evidence-only and is intended to be quick. It verifies:

- Fast, full, and nightly command wiring through `scripts/test_strategy_gate.sh`.
- Current security/data-integrity review is clean and reports `deterministic_property_tests=guarded` plus `local_server_exposure=loopback_default_guarded`.
- Observability current-lane summary index and error scan are clean.
- Architecture refresh reports no runtime behavior change.
- Performance baseline governance is clean.
- Shadow quality, lighting stability, and transparent fixture acceptance are clean for the current implemented/fallback paths.
- No active protocol schema or generated protobuf diff exists.

## Optional Live Checks

Set these flags to turn the same command into a stricter local RC gate:

```sh
RUMPELMC_RC_RUN_FAST_CHECKS=1 /bin/sh scripts/release_candidate_gate.sh logs/release_candidate_gate_current
RUMPELMC_RC_RUN_FULL_CHECKS=1 RUMPELMC_RC_RUN_DIFF_GUARD=1 /bin/sh scripts/release_candidate_gate.sh logs/release_candidate_gate_current
```

`RUMPELMC_RC_RUN_FULL_CHECKS=1` runs `./scripts/check.sh full`; this may include lint/clippy if those tools are installed. `RUMPELMC_RC_RUN_DIFF_GUARD=1` runs `git diff --check` and `./scripts/diff_guard.sh`.

## Current Inputs

Default summaries:

- `logs/test_strategy_gate_current/test-strategy-gate-summary.txt`
- `logs/security_data_integrity_review_current/security-data-integrity-review-summary.txt`
- `logs/observability_logs_cleanup_current/observability-logs-cleanup-summary.txt`
- `logs/architecture_documentation_refresh_current/architecture-documentation-refresh-summary.txt`
- `logs/performance_baseline_governance_current/performance-baseline-governance-summary.txt`
- `logs/shadow_quality_parity_program_current/shadow-quality-parity-summary.txt`
- `logs/transparent_fixture_acceptance_suite_current/transparent-fixture-acceptance-suite-summary.txt`
- `logs/lighting_stability_matrix_current/lighting-stability-matrix-summary.txt`

## Fresh Check

Fresh 2026-06-16 current artifact:

- `logs/release_candidate_gate_current/release-candidate-gate-summary.txt` reported `status=pass`, `reason=ok`, `rc_status=summary_ready`, `perf_matrix=summary_ready`, `visual_smoke=summary_ready`, `storage_protocol_compatibility=guarded`, `active_protocol_change=0`, `security_deterministic_property_tests=guarded`, `security_local_server_exposure=loopback_default_guarded`, `observability_error_scan=clean`, `observability_summary_count=69`, `current_summary_count=69`, `arch_runtime_change=none`, `baseline_warning_status=ok`, `shadow_active_native=deferred`, `transparent_active_fixture=deferred`, `lighting_ambient_status=deferred`, `live_checks=skipped`, `security_status=pass`, `observability_status=pass`, and `test_strategy_status=pass`.
- This was a summary-only refresh after the security/data-integrity review update and GPU upload staging telemetry slice. Use the optional live flags below for a final release action.

Fresh 2026-06-15 current artifact:

- `logs/release_candidate_gate_current/release-candidate-gate-summary.txt` reported `status=pass`, `reason=ok`, `rc_status=summary_ready`, `perf_matrix=summary_ready`, `visual_smoke=summary_ready`, `storage_protocol_compatibility=guarded`, `active_protocol_change=0`, `observability_error_scan=clean`, `observability_summary_count=46`, `current_summary_count=46`, `arch_runtime_change=none`, `baseline_warning_status=ok`, `shadow_active_native=deferred`, `transparent_active_fixture=deferred`, `lighting_ambient_status=deferred`, `live_checks=full`, `fast_check=pass`, `full_check=pass`, `diff_check=pass`, and `diff_guard=pass`.
- The live full check ran `./scripts/check.sh full`; Go lint was skipped because `golangci-lint` was not installed, and Rust unit tests reported `173 passed`.

## Deferred Work

- Repeat live full and diff guard as a final release action, not as every quick evidence refresh.
- Add external profiler artifacts once Block 49 records Xcode/Metal, Windows GPU, or Linux/Vulkan captures.
- Add a real native-shadow active-renderer RC row only after `GPU_TERRAIN_NATIVE_SHADOW_IMPLEMENTED=true`.
- Add a real active-transparent RC row only after `GPU_TERRAIN_TRANSPARENT_IMPLEMENTED=true`.

## Compatibility Rules

- The RC gate must not authorize protocol, storage, chunk serialization, worldgen, draw-distance, lighting, texture, or gameplay behavior changes by itself.
- Summary-only pass means the current evidence is internally consistent; it is not a substitute for live checks before shipping a release build.
- Deferred native-shadow and active-transparent rows are acceptable only while the implementation flags remain false and fallback evidence is clean.
- Protocol schema and generated protobuf diffs must stay at zero unless a separate explicit protocol task owns the change.
