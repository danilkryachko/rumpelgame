# Post Milestone Stabilization Plan

This plan records the next stabilization step after the 50-block world streaming architecture checkpoint. It is a review/commit split plan only; it does not change runtime behavior.

## Technical Brief

User request:

Proceed with the recommended next step after the production-readiness milestone.

Goal:

Turn the large dirty worktree into a coherent, reviewable set of changes and validate it with live release-candidate checks before new feature work.

Context to inspect:

- `git status --short`
- `docs/NEXT_STEP_WORKFLOW.md`
- `docs/WORLD_STREAMING_ARCHITECTURE_REVIEW.md`
- `logs/release_candidate_gate_current/release-candidate-gate-summary.txt`
- `logs/production_readiness_milestone_current/production-readiness-milestone-summary.txt`

Scope:

- Keep the current implementation intact.
- Preserve the 50-block checkpoint evidence.
- Define review groups and commit-order candidates.
- Identify files that need hunk-level staging if the work is split into small commits.

Out of scope:

- Do not stage or commit automatically from this plan.
- Do not start new renderer, protocol, storage, worldgen, or gameplay features.
- Do not reduce visible quality or deferred gate requirements.

Assumptions:

- The current worktree is intentionally dirty after the 50-block checkpoint.
- `release_candidate_gate` has been run with live fast/full/diff checks.
- External profiler, native shadow, and active transparent terrain remain deferred.

Done when:

- The worktree has a clear review split.
- Live RC checks pass.
- MCP review confirms no unexpected scope or test gaps.

Checks:

- `RUMPELMC_RC_RUN_FAST_CHECKS=1 RUMPELMC_RC_RUN_FULL_CHECKS=1 RUMPELMC_RC_RUN_DIFF_GUARD=1 /bin/sh scripts/release_candidate_gate.sh logs/release_candidate_gate_current`
- `git diff --check`
- `/bin/sh scripts/diff_guard.sh`
- MCP `gn_pre_commit_audit`, `gn_verify_diff`, and `gn_test_gap`

## Current Gate State

- `release_candidate_gate`: `status=pass`, `live_checks=full`.
- `production_readiness_milestone`: `status=pass`, `production_readiness=rc_evidence_ready`, `live_release_checks=full`.
- `external_profiling_campaign`: `status=pass`, `external_profile_status=pending_external_profiler`.

## Recommended Review Split

1. **Core protocol, storage, and world correctness**
   - `server/pkg/api/protocol_schema_test.go`
   - `server/pkg/network/protocol_compat_test.go`
   - `server/pkg/network/server.go`
   - `server/pkg/network/server_test.go`
   - `server/pkg/storage/rocksdb.go`
   - `server/pkg/storage/rocksdb_test.go`
   - `server/pkg/world/chunk_encoding_test.go`
   - `server/pkg/world/chunk_test.go`
   - `server/pkg/world/world.go`
   - `server/pkg/world/world_test.go`
   - Related docs/scripts: serialization, storage, networking, server scalability, block edit persistence.

2. **Client Rust streaming, lifecycle, dirty update, and gameplay foundation**
   - `client/rust_ext/src/lib.rs`
   - `client/rust_ext/src/network.rs`
   - `client/rust_ext/src/player.rs`
   - Related docs/scripts: client state machine, dirty update scalability, gameplay loop, tooling/debug overlay.

3. **Godot HUD/main observability and startup wiring**
   - `client/hud.gd`
   - `client/main.gd`
   - Related docs/scripts: observability logs cleanup, automated handoff, architecture refresh.

4. **World streaming and performance evidence gates**
   - `scripts/world_streaming_compression_decision.sh`
   - `scripts/world_streaming_exploration_soak.sh`
   - `scripts/world_streaming_high_pressure_suite.sh`
   - `scripts/world_streaming_resident_set_growth.sh`
   - Related docs: compression, unload, pop-in, collision readiness, long-run soak, resident-set growth.

5. **GPU load, memory, report, shadow, and transparent gates**
   - `scripts/gpu_*`
   - `scripts/lighting_stability_matrix.sh`
   - `scripts/shadow_*`
   - `scripts/transparent_*`
   - Related docs: GPU load scaling, upload pressure, memory budget, report V2, native shadow, shadow parity/retirement, transparent preflight/sorting/acceptance.

6. **Release process and final milestone**
   - `scripts/test_strategy_gate.sh`
   - `scripts/security_data_integrity_review_gate.sh`
   - `scripts/release_candidate_gate.sh`
   - `scripts/external_profiling_campaign_gate.sh`
   - `scripts/production_readiness_milestone_gate.sh`
   - Related docs: test strategy, security/data-integrity, release candidate, external profiling campaign, production readiness milestone.

7. **Shared documentation and memory**
   - `docs/WORLD_STREAMING.md`
   - `docs/WORLD_STREAMING_ARCHITECTURE_REVIEW.md`
   - `docs/ARCHITECTURE.md`
   - `docs/AGENT_MEMORY.md`
   - `docs/GPU_PROFILING.md`
   - `docs/GPU_TRENDS.md`
   - `docs/HANDOFF.md`

## Hunk-Level Split Notes

These files contain changes from multiple blocks and should be reviewed carefully if small commits are required:

- `client/rust_ext/src/lib.rs`: lifecycle, metrics, dirty update, GPU/shadow/transparent markers, overlay, tests.
- `server/pkg/network/server.go`: streaming controls, packet handling, metrics, protocol boundaries.
- `server/pkg/world/world.go`: chunk radius/order/edit persistence behavior.
- `docs/WORLD_STREAMING.md`: cumulative operational guide across most blocks.
- `docs/AGENT_MEMORY.md`: stable invariants from many independent tracks.

If hunk-level staging becomes too risky, prefer a smaller number of broad checkpoint commits instead of forcing artificial separation.

## Next Feature Lane After Stabilization

The best next feature lane is still external profiling:

- Capture real Xcode/Metal rows for `logs/gpu_shadow_radius_matrix_wide/shadow-radius-profiler-capture-pack.txt`.
- Write only real captured rows to `logs/gpu_shadow_radius_matrix_wide/shadow-radius-profiler-results.txt`.
- Validate with `scripts/gpu_terrain_shadow_profiler_results_check.sh`.
- Do not cite pending capture packs or operator-intake templates as GPU timing evidence.
