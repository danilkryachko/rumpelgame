# Agent Handoff

Use this protocol when another Codex thread may continue the work, or when a task is paused after non-trivial changes. The goal is to preserve concrete state, not to write a diary.

## Incoming Agent

1. Read `AGENTS.md`, then this file.
2. Read `docs/AGENT_HANDOFF.md` for the latest task state.
3. Run `./scripts/handoff.sh` to see the current git state, changed files, recent logs, and recent commits.
4. Verify assumptions from the handoff against the actual files before editing.
5. Continue incrementally from the recorded next step.

## Outgoing Agent

Before handing off a non-trivial task, update `docs/AGENT_HANDOFF.md` with:

- Current goal and status.
- What was changed, with file paths.
- Checks that passed or failed.
- Important logs or commands, with paths.
- Known risks, limitations, and assumptions.
- Exact next steps for the next agent.

Keep entries short and factual. Do not include secrets, access tokens, private keys, local credentials, or long copied logs.

`./scripts/handoff.sh` also prints a handoff quality-input checklist and the current observability artifact index when available. Treat those generated sections as orientation aids; they do not replace reading and updating `docs/AGENT_HANDOFF.md` when a real handoff is happening.

## Handoff Quality Bar

A new agent should be able to answer these questions in under five minutes:

- What task is active?
- What has already been done?
- What files are relevant?
- What checks were run?
- What remains risky or incomplete?
- What is the next concrete action?

If the handoff cannot answer those questions, update it before stopping.
