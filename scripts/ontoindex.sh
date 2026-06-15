#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCAL_NODE22="$HOME/.local-node22/node_modules/node/bin"

if [ -x "$LOCAL_NODE22/node" ]; then
  export PATH="$LOCAL_NODE22:$PATH"
fi

if command -v ontoindex >/dev/null 2>&1; then
  ONTOINDEX_BIN="$(command -v ontoindex)"
elif [ -x "$HOME/.local/bin/ontoindex" ]; then
  ONTOINDEX_BIN="$HOME/.local/bin/ontoindex"
else
  cat >&2 <<'EOF'
OntoIndex is not installed.

Install the current GitHub release:
  npm install --prefix "$HOME/.local-node22" node@22 npm@10
  "$HOME/.local-node22/node_modules/node/bin/node" "$HOME/.local-node22/node_modules/npm/bin/npm-cli.js" install --prefix "$HOME/.local" -g --omit=optional --ignore-scripts https://github.com/ontograph/ontoindex/releases/download/v1.9.3/ontoindex-1.9.3.tgz
  "$HOME/.local-node22/node_modules/node/bin/node" "$HOME/.local-node22/node_modules/npm/bin/npm-cli.js" install --prefix "$HOME/.local/lib/node_modules/ontoindex" --ignore-scripts --legacy-peer-deps @ladybugdb/core-darwin-arm64@0.17.1
  cd "$HOME/.local/lib/node_modules/ontoindex/node_modules/@ladybugdb/core" && "$HOME/.local-node22/node_modules/node/bin/node" install.js
  cd "$HOME/.local/lib/node_modules/ontoindex/node_modules/tree-sitter" && "$HOME/.local-node22/node_modules/node/bin/node" "$HOME/.local-node22/node_modules/npm/node_modules/node-gyp/bin/node-gyp.js" rebuild

Then run:
  bash ./scripts/ontoindex.sh analyze --skip-agents-md --no-stats
EOF
  exit 127
fi

export ONTOINDEX_MCP_PROJECT_CWD="${ONTOINDEX_MCP_PROJECT_CWD:-$ROOT_DIR}"
export ONTOINDEX_MCP_REPO="${ONTOINDEX_MCP_REPO:-$ROOT_DIR}"
export ONTOINDEX_MCP_AUTO_ANALYZE="${ONTOINDEX_MCP_AUTO_ANALYZE:-0}"
export ONTOINDEX_LBUG_POOL_SIZE="${ONTOINDEX_LBUG_POOL_SIZE:-1}"
export ONTOINDEX_MCP_STARTUP_TIMEOUT_MS="${ONTOINDEX_MCP_STARTUP_TIMEOUT_MS:-10000}"
export ONTOINDEX_MCP_STARTUP_TRACE="${ONTOINDEX_MCP_STARTUP_TRACE:-1}"
export NODE_OPTIONS="${NODE_OPTIONS:---max-old-space-size=1536}"

cd "$ROOT_DIR"
exec "$ONTOINDEX_BIN" "$@"
