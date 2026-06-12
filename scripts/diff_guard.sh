#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$ROOT_DIR"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "diff_guard: not inside a git work tree" >&2
  exit 2
fi

TMP_FILES="$(mktemp)"
TMP_WARNINGS="$(mktemp)"
trap 'rm -f "$TMP_FILES" "$TMP_WARNINGS"' EXIT

{
  git diff --name-only --diff-filter=ACMRTUXB
  git diff --cached --name-only --diff-filter=ACMRTUXB
  git ls-files --others --exclude-standard
} | sed '/^$/d' | sort -u > "$TMP_FILES"

if [ ! -s "$TMP_FILES" ]; then
  echo "diff_guard: no file changes"
  exit 0
fi

FILE_COUNT="$(wc -l < "$TMP_FILES" | tr -d ' ')"
LINE_COUNT="$(
  {
    git diff --numstat
    git diff --cached --numstat
    git ls-files --others --exclude-standard | while IFS= read -r path; do
      if [ -f "$path" ]; then
        lines="$(wc -l < "$path" | tr -d ' ')"
        printf "%s\t0\t%s\n" "$lines" "$path"
      fi
    done
  } | awk '
  {
    if ($1 != "-") added += $1
    if ($2 != "-") deleted += $2
  }
  END { print added + deleted + 0 }
')"

WARNED=0

warn() {
  WARNED=1
  printf "diff_guard: warning: %s\n" "$1" >&2
}

if [ "$FILE_COUNT" -gt 5 ]; then
  warn "changed $FILE_COUNT files; explain why before continuing"
fi

if [ "$LINE_COUNT" -gt 300 ]; then
  warn "changed $LINE_COUNT lines; explain why before continuing"
fi

while IFS= read -r path; do
  case "$path" in
    *.dylib|*.so|*.dll|*.exe|server/server)
      printf "diff_guard: warning: binary/executable artifact changed: %s\n" "$path" >> "$TMP_WARNINGS"
      ;;
    .DS_Store|.godot/*|*/.godot/*|target/*|*/target/*|tmp/*|*/tmp/*)
      printf "diff_guard: warning: local/generated artifact changed: %s\n" "$path" >> "$TMP_WARNINGS"
      ;;
    *.pb.go|*.pb.rs|*.pb.cc|*.pb.h)
      printf "diff_guard: warning: generated protocol file changed: %s\n" "$path" >> "$TMP_WARNINGS"
      ;;
    *.import|*.uid|*.tscn|*.tres|*.res)
      printf "diff_guard: warning: Godot generated/resource file changed: %s\n" "$path" >> "$TMP_WARNINGS"
      ;;
    server/data/*)
      printf "diff_guard: warning: local server data changed: %s\n" "$path" >> "$TMP_WARNINGS"
      ;;
    api/schema/*|server/pkg/api/*|server/pkg/network/*|server/pkg/storage/*|server/pkg/world/*|client/rust_ext/src/*)
      printf "diff_guard: notice: sensitive path changed: %s\n" "$path" >> "$TMP_WARNINGS"
      ;;
  esac
done < "$TMP_FILES"

if [ -s "$TMP_WARNINGS" ]; then
  cat "$TMP_WARNINGS" >&2
  if grep -q "warning:" "$TMP_WARNINGS"; then
    WARNED=1
  fi
fi

if [ "$WARNED" -ne 0 ]; then
  exit 1
fi

echo "diff_guard: ok"
