# AI Task Template

Use this template when the user describes a feature or change in plain language. The agent should translate the request into this brief before implementing or delegating. Ask only the questions that materially affect scope, architecture, or user-visible behavior.

## Brief

User request:

Goal:

Context to inspect:

Scope:

Out of scope:

Questions:

Assumptions:

Implementation plan:

Worker split, if useful:

Done when:

Checks:

Review gates:

## Rules

- Keep the brief concrete and short.
- Prefer conservative assumptions for small tasks.
- Ask clarifying questions before large, ambiguous, protocol, storage, persistence, UI, or gameplay changes.
- Do not use the brief to expand the user's request beyond what they asked for.
- Do not impose fixed file-count or line-count caps; split work by risk, reviewability, and testability instead.
- If delegating to worker threads, give each worker a disjoint write scope.
- The main agent remains responsible for final coordination and integration.

## Example

User request:

```text
Make an inventory system.
```

Goal:

Implement a player inventory system that fits the existing Godot + Rust + Go architecture.

Questions:

- Should inventory state be authoritative on the server or client-only for the first prototype?
- Should the first version include a hotbar?
- Should inventory persist between sessions?
- Should items map directly to existing block IDs?

Done when:

- Inventory behavior is implemented within the agreed scope.
- Relevant client, server, protocol, and UI checks pass.
- Sensitive changes receive a review pass.
