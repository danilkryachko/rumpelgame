# Next Step Workflow

Use this workflow when the user asks what to do next, what to improve, what to fix, or where development should go now.

## Inspect First

Before recommending next work, inspect the current project state:

- `git status --short`
- recent commits or current branch when relevant
- `README.md`
- `docs/ARCHITECTURE.md`
- `docs/AGENT_MEMORY.md`
- `docs/BUGS.md`
- `docs/CODE_REVIEW.md`
- `docs/STORAGE.md` and `docs/PROTOCOL.md` when storage or protocol are likely involved
- existing tests and the narrowest relevant check results when practical

## Recommend

Base recommendations on the current codebase, not a generic roadmap.

Prioritize work that:

- unblocks development
- reduces code degradation risk
- adds missing tests around sensitive behavior
- stabilizes protocol, storage, world generation, chunk serialization, or client/server flow
- turns existing dirty or partially implemented work into coherent, reviewable changes
- improves the player's visible loop only after core correctness is stable enough

## Output Shape

Keep the answer concise and practical:

- Current state summary
- Top 3 recommended next steps
- Why each step matters now
- Suggested worker split, if parallel work helps
- Checks or review gates for the recommended path

## Rules

- Do not recommend broad rewrites unless the current code clearly requires it.
- Do not invent priorities without inspecting the repo.
- Call out uncertainty and stale information.
- If the working tree is dirty, consider stabilization, review, or splitting changes before new feature work.
