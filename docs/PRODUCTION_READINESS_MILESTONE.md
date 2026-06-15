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
- `release_candidate_gate` summary mode proves reproducible evidence is clean; live full release checks remain a separate explicit release action.
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
- `external_profiler=pending_external_profiler`
- `native_shadow_direction=deferred_implementation_gate`
- `transparent_direction=deferred_implementation_gate`

This means the current architecture has a reproducible evidence chain and release-candidate summary readiness, but it is not a declaration that external profiler work, native shadow rollout, or active transparent terrain rollout is complete.

## Deferred Release Blockers

- External profiler captures are pending and must be validated before citing GPU pass timings.
- Native-shadow RenderingDevice rendering remains behind `GPU_TERRAIN_NATIVE_SHADOW_IMPLEMENTED=false`.
- CPU shadow proxy retirement remains deferred until active native-shadow capture, profiler evidence, and rollback evidence exist.
- Active transparent terrain remains behind `GPU_TERRAIN_TRANSPARENT_IMPLEMENTED=false`.
- Live full release checks are explicit release actions, not always run by summary gates.

## Compatibility Rules

- Do not use the milestone to justify reducing visible quality, draw distance, lighting, shadows, texture quality, storage integrity, protocol compatibility, worldgen determinism, or chunk serialization compatibility.
- Keep pending/deferred lanes visible in future reports.
- Treat any future `production_ready` claim as requiring live checks plus external release criteria, not only this evidence checkpoint.
