# Agent Code Search

Use `scripts/agent_search.sh` when an agent needs to find code quickly without already knowing the exact file.

## Commands

```bash
bash ./scripts/agent_search.sh status
bash ./scripts/agent_search.sh query "gpu terrain mesh upload"
bash ./scripts/agent_search.sh symbol render_subchunk_mesh
bash ./scripts/agent_search.sh files terrain
bash ./scripts/agent_search.sh index
```

`query` combines:

- exact `rg` text search over source, config, and docs;
- ranked file search by distinct query terms;
- token search for broad natural-language prompts;
- definition-like symbol search for GDScript, Rust, Go, shaders, and config files;
- path search;
- docs search;
- OntoIndex semantic/graph search when the index is fresh.

`symbol` is for known functions, classes, methods, types, and constants. It adds OntoIndex context and impact output when available.

`index` refreshes OntoIndex through the project wrapper with `--skip-agents-md --no-stats`.

## Agent Workflow

1. Start with `query` for broad questions.
2. Use `symbol` when a likely symbol is found.
3. Use targeted `rg`, file reads, or OntoIndex MCP tools after the result narrows the search area.
4. Refresh with `index` when `status` reports a stale graph.

The script intentionally excludes generated/cache/runtime-heavy paths such as `.ontoindex/`, `.git/`, Godot `.godot/`, `logs/`, `target/`, and `server/data/`.
