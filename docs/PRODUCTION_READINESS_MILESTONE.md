# Production Readiness Milestone

Block 50, Production Readiness Milestone, consolidates the year-plan evidence into one milestone report. It records what is ready, what is reproducibly gated, and what remains deferred before a production release claim.

## Technical Brief

User request:

Run the 50-block world streaming architecture plan in order, use MCP, continue without stopping, and move on when a block cannot be completed locally.

Goal:

Create a final production-readiness milestone gate over stable streaming, high resident set, predictable performance, resource/upload health, storage/protocol integrity, shadow and transparent direction, clean docs, and reproducible gates.

Context to inspect:

- `docs/WORLD_STREAMING_ARCHITECTURE_REVIEW.md`
- `docs/WORLD_STREAMING.md`
- `docs/RELEASE_CANDIDATE_GATE.md`
- `docs/EXTERNAL_PROFILING_CAMPAIGN.md`
- `logs/release_candidate_gate_current/release-candidate-gate-summary.txt`
- `logs/external_profiling_campaign_current/external-profiling-campaign-summary.txt`

Scope:

- Add `scripts/production_readiness_milestone_gate.sh`.
- Add this document.
- Emit one compact readiness summary and one line-oriented milestone report.
- Keep deferred external-profiler, native-shadow, and active-transparent lanes explicit.

Out of scope:

- Do not claim a shipped production release.
- Do not convert deferred native shadow or transparent terrain into active features.
- Do not change runtime behavior, protocol, storage, worldgen, renderer settings, draw distance, lighting, shadows, or texture quality.

Assumptions:

- The milestone is an evidence checkpoint, not a deployment action.
- `release_candidate_gate` summary mode proves reproducible evidence is clean, including `security_deterministic_property_tests=guarded`, `security_conflict_semantics=last_write_wins_guarded`, `security_local_server_exposure=loopback_default_guarded`, and `security_smoke_bind_exposure=loopback_guarded`; live full release checks remain a separate explicit release action and must be repeated for a real release branch.
- Pending external-profiler evidence blocks shadow-retirement decisions but does not block documenting the current milestone.

Implementation plan:

- Validate stable streaming and high resident-set summaries.
- Validate GPU load scaling, upload pressure, memory budget, and performance baseline summaries.
- Validate security/data-integrity, observability, architecture, handoff, RC, and external profiling campaign summaries.
- Validate expected deferred lanes for native shadow, shadow proxy retirement, active transparency, and external profiler capture.
- Generate a milestone report with ready/deferred rows.

Done when:

- `scripts/production_readiness_milestone_gate.sh` emits `production-readiness-milestone-summary.txt` with `status=pass`.
- `production_readiness=rc_evidence_ready`.
- Deferred rows are explicit and not hidden as pass/fail ambiguity.

Checks:

- `sh -n scripts/production_readiness_milestone_gate.sh`
- `/bin/sh scripts/production_readiness_milestone_gate.sh logs/production_readiness_milestone_current`
- `RUMPELMC_RC_RUN_FAST_CHECKS=1 RUMPELMC_RC_RUN_FULL_CHECKS=1 RUMPELMC_RC_RUN_DIFF_GUARD=1 /bin/sh scripts/release_candidate_gate.sh logs/release_candidate_gate_current`

Review gates:

- Before a real release branch, run live `check.sh fast`, `check.sh full`, `git diff --check`, and `diff_guard.sh`, or run the RC gate with the corresponding live flags.

## Milestone Verdict

Current expected milestone verdict:

- `production_readiness=rc_evidence_ready`
- `stable_streaming=pass`
- `high_resident_set=pass`
- `predictable_performance=pass`
- `resource_upload_health=pass`
- `storage_protocol_integrity=pass`
- `docs_reproducible_gates=pass`
- `rc_security_deterministic_property_tests=guarded`
- `security_conflict_semantics=last_write_wins_guarded`
- `security_local_server_exposure=loopback_default_guarded`
- `security_smoke_bind_exposure=loopback_guarded`
- `rc_security_conflict_semantics=last_write_wins_guarded`
- `rc_security_local_server_exposure=loopback_default_guarded`
- `rc_security_smoke_bind_exposure=loopback_guarded`
- `external_rc_security_conflict_semantics=last_write_wins_guarded`
- `external_rc_security_local_server_exposure=loopback_default_guarded`
- `external_rc_security_smoke_bind_exposure=loopback_guarded`
- `external_profiler=pending_external_profiler`
- `external_capture_readiness=ready_for_external_capture`
- `native_shadow_direction=deferred_implementation_gate`
- `transparent_direction=deferred_implementation_gate`
- latest current `live_release_checks=skipped` in summary mode; run the RC gate with live flags for a real release branch

This means the current architecture has a reproducible evidence chain and release-candidate summary readiness, but it is not a declaration that external profiler work, native shadow rollout, or active transparent terrain rollout is complete.

## Fresh Check

Fresh 2026-06-16 current artifacts:

- `logs/release_candidate_gate_current/release-candidate-gate-summary.txt` reported `status=pass`, `live_checks=skipped`, `active_protocol_change=0`, `security_deterministic_property_tests=guarded`, `security_conflict_semantics=last_write_wins_guarded`, `security_local_server_exposure=loopback_default_guarded`, `security_smoke_bind_exposure=loopback_guarded`, `observability_error_scan=clean`, and `baseline_warning_status=ok`. This is a summary-mode refresh; use the live RC flags below for a final release action.
- `logs/external_profiling_campaign_current/external-profiling-campaign-summary.txt` reported `status=pass`, `reason=external_profiler_pending`, `capture_readiness=ready_for_external_capture`, `external_profile_status=pending_external_profiler`, `results_file_status=missing`, `results_template_status=todo`, `results_check_status=missing`, `xctrace_review_packet_status=pass`, `xctrace_overhead_status=pass`, `xctrace_overhead_estimate_p50_ms=1.965`, `xctrace_overhead_candidate_status=single_missing_encoder_navigation_only`, `xctrace_overhead_candidate_p50_ms=0.007`, `captured_rows=0`, `missing_rows=4`, `rc_live_checks=skipped`, `rc_security_deterministic_property_tests=guarded`, `rc_security_conflict_semantics=last_write_wins_guarded`, `rc_security_local_server_exposure=loopback_default_guarded`, and `rc_security_smoke_bind_exposure=loopback_guarded`; `external-profiling-results-intake.txt` is an operator intake contract, and the xctrace review packet plus overhead/candidate summaries are navigation artifacts, not profiler evidence.
- `logs/production_readiness_milestone_current/production-readiness-milestone-summary.txt` reported `status=pass`, `reason=milestone_reached`, `production_readiness=rc_evidence_ready`, `stable_streaming=pass`, `high_resident_set=pass`, `predictable_performance=pass`, `resource_upload_health=pass`, `storage_protocol_integrity=pass`, `docs_reproducible_gates=pass`, `external_profiler=pending_external_profiler`, `external_capture_readiness=ready_for_external_capture`, `external_rc_security_conflict_semantics=last_write_wins_guarded`, `external_rc_security_local_server_exposure=loopback_default_guarded`, `external_rc_security_smoke_bind_exposure=loopback_guarded`, `native_shadow_direction=deferred_implementation_gate`, `transparent_direction=deferred_implementation_gate`, `live_release_checks=skipped`, `rc_security_deterministic_property_tests=guarded`, `security_conflict_semantics=last_write_wins_guarded`, `security_local_server_exposure=loopback_default_guarded`, `security_smoke_bind_exposure=loopback_guarded`, `rc_security_conflict_semantics=last_write_wins_guarded`, `rc_security_local_server_exposure=loopback_default_guarded`, `rc_security_smoke_bind_exposure=loopback_guarded`, `resident_gpu_draws=2482`, `resident_gpu_subchunks=2482`, `upload_effective_draws=21216`, and `memory_fragmentation_pct=0.000`.

## Deferred Release Blockers

- External profiler captures are pending and must be validated before citing GPU pass timings.
- Native-shadow RenderingDevice rendering remains behind `GPU_TERRAIN_NATIVE_SHADOW_IMPLEMENTED=false`.
- CPU shadow proxy retirement remains deferred until active native-shadow capture, profiler evidence, and rollback evidence exist.
- Active transparent terrain remains behind `GPU_TERRAIN_TRANSPARENT_IMPLEMENTED=false`.
- Live full release checks are explicit release actions and must be rerun for the exact release branch, even when the latest current artifact reports `live_release_checks=full`.

## Compatibility Rules

- Do not use the milestone to justify reducing visible quality, draw distance, lighting, shadows, texture quality, storage integrity, protocol compatibility, worldgen determinism, or chunk serialization compatibility.
- Keep pending/deferred lanes visible in future reports.
- Treat any future `production_ready` claim as requiring live checks plus external release criteria, not only this evidence checkpoint.
