# Parallel Development Month Plan

This document coordinates the five existing RUMPELMC worker chats. Do not create more worker chats for this plan unless the user explicitly asks.

## Brief

User request:

Split a month-scale development backlog across the five existing Codex chats, while the HQ chat remains responsible for coordination and integration.

Goal:

Move toward stable high-FPS gameplay and stronger engineering control without reducing draw distance, lighting, shadows, texture quality, or visible quality.

Context to inspect:

- `AGENTS.md`
- `docs/HANDOFF.md`
- `docs/AGENT_HANDOFF.md`
- `docs/AGENT_MEMORY.md`
- `docs/ARCHITECTURE.md`
- `docs/GPU_ROADMAP.md`
- `docs/GPU_PROFILING.md`
- `docs/GPU_TRENDS.md`

Scope:

- GPU terrain and client Rust performance work.
- World streaming and deterministic world behavior.
- PostgreSQL and RocksDB storage reliability/performance.
- Protocol compatibility and packet regression protection.
- Review, checks, reporting, and anti-degradation tooling.

Out of scope:

- New database engines. PostgreSQL and RocksDB are the approved databases.
- Quality reductions to reach FPS targets.
- Broad rewrites, framework swaps, or architecture changes without explicit approval.
- Cross-domain edits without coordination through HQ.

Assumptions:

- The five pinned worker chats already exist and should be reused.
- Each worker owns one primary write scope.
- HQ integrates completed slices and resolves cross-domain conflicts.
- Workers continue from their current local worktree state; no destructive reset or forced sync.

Done when:

- Each worker can execute small, reviewable slices independently.
- Completed slices are committed, checked, and summarized.
- Blocked slices are recorded with concrete cause and next possible action.
- HQ can merge or reject each slice from a factual handoff.

Checks:

- Small changes: narrow relevant tests.
- Normal changes: `./scripts/check.sh fast`.
- Broad or sensitive changes: `./scripts/check.sh full` and `./scripts/diff_guard.sh`.
- GPU/client changes: relevant Rust tests plus GPU report/stress scripts when behavior or telemetry changes.

Review gates:

- Storage, protocol, world generation, chunk serialization, persistence, and Rust extension changes require a review pass before final integration.
- If a slice changes more than 5 files or more than 300 lines, stop and explain why before continuing.

## Worker Threads

| Worker | Thread ID | Worktree | Primary scope |
| --- | --- | --- | --- |
| HQ | `019eaacb-ee55-7d90-aa46-17a017b7403f` | `/Users/daniil/Documents/RUMPELMC` | Coordination, integration, final checks |
| Storage | `019eaae8-a9ab-7f41-a7c7-1a96321277a4` | `/Users/daniil/.codex/worktrees/0842/RUMPELMC` | PostgreSQL/RocksDB storage |
| World | `019eaae8-d0df-7c21-b8b8-ea57022e6f9a` | `/Users/daniil/.codex/worktrees/1d04/RUMPELMC` | World generation and chunk streaming |
| Protocol | `019eaae8-ef74-7722-922a-150e57f513aa` | `/Users/daniil/.codex/worktrees/5b99/RUMPELMC` | Packet schema, compatibility, framing |
| Client Rust | `019eaae9-0c21-70e0-abbc-e5de2e1b0d0f` | `/Users/daniil/.codex/worktrees/551c/RUMPELMC` | Rust extension, GPU terrain, client performance |
| Review QA | `019eaae9-2f10-70b0-9069-dc171db3f94a` | `/Users/daniil/.codex/worktrees/3aee/RUMPELMC` | Checks, docs, reports, review gates |

Known current worker worktree state:

- World: detached HEAD, untracked `server/pkg/world/chunk_test.go`.
- Storage: detached HEAD, modified `docs/STORAGE.md`, untracked `server/pkg/storage/`.
- Protocol: detached HEAD, modified `docs/PROTOCOL.md`, untracked protocol/framing tests.
- Client Rust: detached HEAD, modified `client/rust_ext/src/lib.rs`, `meshing.rs`, `network.rs`.
- Review QA: detached HEAD, modified `scripts/diff_guard.sh`.

## Global Worker Rules

- Write and report in Russian.
- Start by running `git status --short --branch` in the worker worktree.
- Preserve existing dirty work; do not reset, checkout, or overwrite it.
- If this document is absent in a worker worktree, read the HQ copy at `/Users/daniil/Documents/RUMPELMC/docs/PARALLEL_DEVELOPMENT_MONTH_PLAN.md`.
- Work in small commits. Each commit should have a narrow behavior, test, or documentation purpose.
- Prefer current architecture and local patterns over new abstractions.
- Do not touch another worker's primary scope without asking HQ.
- If blocked and not locally solvable, record the blocker in the worker summary and move to the next safe task.
- Stop and ask HQ before changing packet compatibility, storage invariants, world determinism, or visible quality.

## Integration Cadence

1. Worker finishes a small slice.
2. Worker runs relevant checks.
3. Worker updates its handoff summary with changed files, checks, risks, and next step.
4. HQ reviews the slice and either integrates it or sends concrete fixes back.
5. HQ updates `docs/AGENT_HANDOFF.md` only with stable cross-thread state.

## Storage Backlog

1. Finish/inspect current storage worktree changes and record what they do.
2. Add focused tests for PostgreSQL connection/config validation.
3. Add focused tests for RocksDB path/config validation.
4. Document the exact PostgreSQL vs RocksDB ownership boundary.
5. Add storage package smoke tests that do not require external secrets.
6. Add failure-path tests for missing/corrupt storage directories.
7. Add chunk persistence round-trip tests if storage APIs already exist.
8. Add deterministic serialization checks around saved chunk payloads.
9. Add storage benchmark or timing helper only if existing test patterns support it.
10. Improve storage logs for failed open/read/write paths.
11. Verify no SQLite or other database references are introduced.
12. Add migration/schema drift notes for PostgreSQL structures.
13. Add RocksDB compaction/cleanup notes if current code exposes them.
14. Add tests for concurrent save/load behavior if APIs support it.
15. Add storage cleanup test fixtures to avoid dirty local state.
16. Review storage errors for actionable messages.
17. Run storage-specific checks and `./scripts/check.sh fast`.
18. Prepare a review summary for HQ.
19. Address review findings in a separate small slice.
20. Record remaining storage risks and next recommended slice.

## World Backlog

1. Finish/inspect current world test work and record coverage.
2. Add deterministic tests for chunk coordinates including negative coordinates.
3. Add tests for chunk neighbor boundaries.
4. Add tests for circular/near-player loading semantics where server code owns them.
5. Add tests that view-distance changes do not reduce configured radius unexpectedly.
6. Add stress-style unit tests for repeated chunk generation if current tests support it.
7. Add deterministic seed regression fixtures.
8. Validate chunk serialization assumptions against world data structures.
9. Add tests for unload/reload consistency.
10. Review world generation hot paths for avoidable allocation churn.
11. Add a benchmark only if Go benchmark patterns already exist.
12. Improve logs for chunk generation failures.
13. Verify no protocol or storage behavior is changed from world-only work.
14. Add edge-case tests for high positive coordinates.
15. Add edge-case tests for zero and origin chunks.
16. Add tests for chunk request ordering if world package owns the logic.
17. Run world-specific tests and `./scripts/check.sh fast`.
18. Prepare a review summary for HQ.
19. Address review findings in a separate small slice.
20. Record remaining world risks and next recommended slice.

## Protocol Backlog

1. Finish/inspect current protocol/framing tests and record coverage.
2. Add packet compatibility tests for existing generated schemas.
3. Add framing boundary tests for short, malformed, and oversized payloads.
4. Document protocol versioning expectations in `docs/PROTOCOL.md`.
5. Add a generated-code drift check if existing tooling allows it.
6. Add tests for chunk payload size limits.
7. Add tests for packet ordering assumptions if current network code exposes them.
8. Add tests for unknown/unsupported packet handling.
9. Add docs for when packet fields may be added vs changed.
10. Verify no storage/world/client behavior changes are hidden in protocol work.
11. Add compatibility fixtures for representative packet payloads.
12. Add validation around empty payload handling.
13. Add validation around partial frame reads.
14. Add validation around multiple frames in one stream.
15. Add notes for future dirty-block update packets without implementing them prematurely.
16. Run protocol/network checks and `./scripts/check.sh fast`.
17. Prepare a review summary for HQ.
18. Address review findings in a separate small slice.
19. Record protocol risks that require HQ decision.
20. Record the next recommended protocol slice.

## Client Rust / GPU Backlog

1. Finish/inspect current Rust extension changes and record intent.
2. Rerun heavy GPU terrain report with current upload-frame telemetry.
3. If upload count or upload KB spikes, add a conservative upload budget/retry telemetry gate.
4. If upload stays stable, measure staging allocation churn.
5. Add staging reuse only after tests show allocation churn matters.
6. Add focused tests for GPU allocator free-range behavior.
7. Add warnings for fragmentation thresholds without changing allocation policy.
8. Add dirty-update telemetry for block/subchunk changes.
9. Implement smallest safe dirty-update path only if telemetry proves need.
10. Keep fallback ArrayMesh behavior unchanged.
11. Add draw submission telemetry if compositor submit spikes recur.
12. Add binding/cache telemetry only if current code has stable boundaries.
13. Audit shader hot path for obvious redundant work without changing visuals.
14. Add feature flags for risky GPU experiments.
15. Validate macOS behavior with current Metal path.
16. Keep Windows/Vulkan assumptions documented and unbroken.
17. Run Rust fmt/tests plus relevant GPU scripts.
18. Prepare a review summary for HQ.
19. Address review findings in a separate small slice.
20. Record next bottleneck from measured data, not guesses.

## Review QA Backlog

1. Finish/inspect current `scripts/diff_guard.sh` changes and record intent.
2. Strengthen diff guard for generated files if current patterns are clear.
3. Add/verify line-count and file-count warnings for broad patches.
4. Add optional report output for changed sensitive areas.
5. Improve `scripts/check.sh` messages without changing check semantics.
6. Verify `fast` and `full` modes remain stable.
7. Add docs for when to use GitHub MCP and Context7 MCP.
8. Add a review checklist for GPU/client Rust slices.
9. Add a review checklist for storage/protocol/world slices.
10. Add artifact index/report hygiene for GPU logs.
11. Add stale-log cleanup guidance without deleting artifacts automatically.
12. Add handoff quality checks to `scripts/handoff.sh` if low-risk.
13. Review `docs/AI_GUIDELINES.md` for duplicates after recent changes.
14. Review `docs/CODE_REVIEW.md` for actionable gates.
15. Add CI-friendly shell syntax checks where missing.
16. Run docs/script checks and `./scripts/check.sh fast`.
17. Prepare a review summary for HQ.
18. Address review findings in a separate small slice.
19. Record remaining process risks.
20. Record the next recommended QA slice.
