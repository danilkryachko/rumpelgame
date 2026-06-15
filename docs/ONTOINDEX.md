# OntoIndex

OntoIndex is an optional local code graph for agent navigation. It is not part of the game runtime, build, or checks. The local graph lives in `.ontoindex/` and must not be committed.

## Install

The npm registry package was not available during setup, so install the GitHub release tarball. Use a local Node 22 runtime; Node 24/25 and a scripted install stalled on native `tree-sitter` postinstall during setup.

```bash
npm install --prefix "$HOME/.local-node22" node@22 npm@10
"$HOME/.local-node22/node_modules/node/bin/node" "$HOME/.local-node22/node_modules/npm/bin/npm-cli.js" install --prefix "$HOME/.local" -g --omit=optional --ignore-scripts https://github.com/ontograph/ontoindex/releases/download/v1.9.3/ontoindex-1.9.3.tgz
"$HOME/.local-node22/node_modules/node/bin/node" "$HOME/.local-node22/node_modules/npm/bin/npm-cli.js" install --prefix "$HOME/.local/lib/node_modules/ontoindex" --ignore-scripts --legacy-peer-deps @ladybugdb/core-darwin-arm64@0.17.1
cd "$HOME/.local/lib/node_modules/ontoindex/node_modules/@ladybugdb/core" && "$HOME/.local-node22/node_modules/node/bin/node" install.js
cd "$HOME/.local/lib/node_modules/ontoindex/node_modules/tree-sitter" && "$HOME/.local-node22/node_modules/node/bin/node" "$HOME/.local-node22/node_modules/npm/node_modules/node-gyp/bin/node-gyp.js" rebuild
```

## Index

Run from the repository root:

```bash
bash ./scripts/ontoindex.sh analyze --skip-agents-md --no-stats
bash ./scripts/ontoindex.sh status
```

Always keep `--skip-agents-md` for this project. The project `AGENTS.md` is maintained manually.

## Query

Useful local commands:

```bash
bash ./scripts/ontoindex.sh query "gpu terrain meshing"
bash ./scripts/ontoindex.sh context render_subchunk_mesh
bash ./scripts/ontoindex.sh impact render_subchunk_mesh --depth 2
bash ./scripts/ontoindex.sh detect-changes
bash ./scripts/ontoindex.sh review diff
```

If a command fails or the index is stale, use `rg` and the project docs as the fallback source of truth.

## Codex MCP

Register a scoped MCP server for this repository:

```bash
codex mcp add ontoindex -- /bin/bash /Users/daniil/Documents/RUMPELMC/scripts/ontoindex.sh mcp
codex mcp list
```

The wrapper pins `ONTOINDEX_MCP_PROJECT_CWD` and `ONTOINDEX_MCP_REPO` to this repository and disables MCP auto-analyze.
