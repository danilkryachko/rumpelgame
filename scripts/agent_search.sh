#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIMIT="${AGENT_SEARCH_LIMIT:-40}"

RG_COMMON=(
  --hidden
  --smart-case
  --sort path
  --glob '!/.git/**'
  --glob '!/.ontoindex/**'
  --glob '!/.claude/**'
  --glob '!/logs/**'
  --glob '!/client/.godot/**'
  --glob '!/rumpelgame/.godot/**'
  --glob '!/server/data/**'
  --glob '!/target/**'
  --glob '!*.import'
  --glob '!*.uid'
)

CODE_GLOBS=(
  --glob '*.gd'
  --glob '*.rs'
  --glob '*.go'
  --glob '*.wgsl'
  --glob '*.glsl'
  --glob '*.shader'
  --glob '*.ts'
  --glob '*.tsx'
  --glob '*.js'
  --glob '*.json'
  --glob '*.toml'
  --glob '*.md'
)

print_usage() {
  cat <<'EOF'
Usage:
  bash ./scripts/agent_search.sh query "terrain mesh upload"
  bash ./scripts/agent_search.sh symbol render_subchunk_mesh
  bash ./scripts/agent_search.sh files terrain
  bash ./scripts/agent_search.sh index
  bash ./scripts/agent_search.sh status

Environment:
  AGENT_SEARCH_LIMIT=80  Increase per-section output limit.
EOF
}

section() {
  printf '\n## %s\n' "$1"
}

run_limited() {
  local empty_message="$1"
  shift

  local output
  if output="$("$@" 2>/dev/null | sed -n "1,${LIMIT}p")" && [ -n "$output" ]; then
    printf '%s\n' "$output"
  else
    printf '%s\n' "$empty_message"
  fi
}

pick_token() {
  printf '%s\n' "$1" |
    tr -cs '[:alnum:]_' '\n' |
    awk 'length($0) > 2 { if (length($0) > length(best)) best=$0 } END { print best }'
}

query_tokens() {
  printf '%s\n' "$1" |
    tr -cs '[:alnum:]_' '\n' |
    awk 'length($0) > 2 { print tolower($0) }' |
    sort -u
}

rank_files_by_terms() {
  local query="$1"
  local token

  while IFS= read -r token; do
    [ -n "$token" ] || continue
    rg -l -i -F "${RG_COMMON[@]}" "${CODE_GLOBS[@]}" "$token" . 2>/dev/null |
      awk -v token="$token" '/^\.\/(client|server|api|rumpelgame|scripts)\// { print $0 "\t" token }' || true
  done < <(query_tokens "$query") |
    awk -F '\t' '
      {
        seen[$1 SUBSEP $2] = 1
      }
      END {
        for (key in seen) {
          split(key, parts, SUBSEP)
          count[parts[1]] += 1
        }
        for (file in count) {
          print count[file] "\t" file
        }
      }
    ' |
    sort -rn -k1,1 -k2,2 |
    sed -n "1,${LIMIT}p"
}

onto_status() {
  bash "$ROOT_DIR/scripts/ontoindex.sh" status
}

onto_is_fresh() {
  onto_status 2>/dev/null | rg -q 'up-to-date'
}

run_onto_query() {
  local query="$1"

  if onto_is_fresh; then
    bash "$ROOT_DIR/scripts/ontoindex.sh" query "$query" 2>/dev/null | sed -n "1,${LIMIT}p" || true
  else
    printf 'OntoIndex is missing or stale. Refresh with: bash ./scripts/agent_search.sh index\n'
  fi
}

cmd_query() {
  local query="$*"
  local token
  token="$(pick_token "$query")"

  if [ -z "$query" ]; then
    print_usage
    exit 2
  fi

  cd "$ROOT_DIR"

  section "Exact Text"
  run_limited "No exact text matches." rg -n -F "${RG_COMMON[@]}" "${CODE_GLOBS[@]}" "$query" .

  section "Ranked Files"
  run_limited "No ranked file matches." rank_files_by_terms "$query"

  if [ -n "$token" ] && [ "$token" != "$query" ]; then
    section "Token Text: $token"
    run_limited "No token text matches." rg -n -F "${RG_COMMON[@]}" "${CODE_GLOBS[@]}" "$token" .
  fi

  section "Symbols"
  if [ -n "$token" ]; then
    rg -n --pcre2 "${RG_COMMON[@]}" "${CODE_GLOBS[@]}" \
      '^\s*(class_name|func|signal|enum|const|var|static func|pub\s+fn|fn|pub\s+struct|struct|pub\s+enum|enum|impl|trait|type|func\s+\(|func\s+\w|const\s+\(|var\s+\(|shader_type|uniform|void)\b' . |
      rg -i -F "$token" |
      sed -n "1,${LIMIT}p" || printf 'No symbol matches.\n'
  else
    printf 'No usable token for symbol search.\n'
  fi

  section "Files"
  if [ -n "$token" ]; then
    rg --files "${RG_COMMON[@]}" |
      rg -i -F "$token" |
      sed -n "1,${LIMIT}p" || printf 'No file path matches.\n'
  else
    printf 'No usable token for file search.\n'
  fi

  section "Docs"
  run_limited "No docs matches." rg -n -F "${RG_COMMON[@]}" --glob '/docs/**' "$query" .

  section "OntoIndex"
  run_onto_query "$query"
}

cmd_symbol() {
  local symbol="$*"

  if [ -z "$symbol" ]; then
    print_usage
    exit 2
  fi

  cd "$ROOT_DIR"

  section "Exact Symbol Text"
  run_limited "No exact symbol text matches." rg -n -F "${RG_COMMON[@]}" "${CODE_GLOBS[@]}" "$symbol" .

  section "Definitions"
  rg -n --pcre2 "${RG_COMMON[@]}" "${CODE_GLOBS[@]}" \
    '^\s*(class_name|func|signal|enum|const|var|static func|pub\s+fn|fn|pub\s+struct|struct|pub\s+enum|enum|impl|trait|type|func\s+\(|func\s+\w|const\s+\(|var\s+\(|shader_type|uniform|void)\b' . |
    rg -i -F "$symbol" |
    sed -n "1,${LIMIT}p" || printf 'No definition matches.\n'

  section "OntoIndex Context"
  if onto_is_fresh; then
    bash "$ROOT_DIR/scripts/ontoindex.sh" context "$symbol" 2>/dev/null | sed -n "1,${LIMIT}p" || true
  else
    printf 'OntoIndex is missing or stale. Refresh with: bash ./scripts/agent_search.sh index\n'
  fi

  section "OntoIndex Impact"
  if onto_is_fresh; then
    bash "$ROOT_DIR/scripts/ontoindex.sh" impact "$symbol" --depth 2 2>/dev/null | sed -n "1,${LIMIT}p" || true
  else
    printf 'OntoIndex is missing or stale. Refresh with: bash ./scripts/agent_search.sh index\n'
  fi
}

cmd_files() {
  local query="$*"
  local token
  token="$(pick_token "$query")"

  if [ -z "$token" ]; then
    print_usage
    exit 2
  fi

  cd "$ROOT_DIR"
  rg --files "${RG_COMMON[@]}" |
    rg -i -F "$token" |
    sed -n "1,${LIMIT}p" || true
}

cmd_index() {
  cd "$ROOT_DIR"
  bash ./scripts/ontoindex.sh analyze --skip-agents-md --no-stats
  bash ./scripts/ontoindex.sh status
}

cmd_status() {
  cd "$ROOT_DIR"
  section "OntoIndex"
  bash ./scripts/ontoindex.sh status || true

  section "Search Backends"
  if command -v rg >/dev/null 2>&1; then
    printf 'rg: %s\n' "$(command -v rg)"
  else
    printf 'rg: missing\n'
  fi
}

case "${1:-}" in
  query)
    shift
    cmd_query "$@"
    ;;
  symbol)
    shift
    cmd_symbol "$@"
    ;;
  files)
    shift
    cmd_files "$@"
    ;;
  index)
    shift
    cmd_index "$@"
    ;;
  status)
    shift
    cmd_status "$@"
    ;;
  -h|--help|help|"")
    print_usage
    ;;
  *)
    printf 'Unknown command: %s\n\n' "$1" >&2
    print_usage >&2
    exit 2
    ;;
esac
