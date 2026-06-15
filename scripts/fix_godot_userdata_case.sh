#!/usr/bin/env sh
set -eu

PROJECT_NAME="${RUMPELMC_GODOT_PROJECT_NAME:-rumpelgame}"
STALE_PROJECT_NAME="${RUMPELMC_GODOT_STALE_PROJECT_NAME:-RUMPELGAME}"
APP_USERDATA_DIR="${GODOT_APP_USERDATA_DIR:-$HOME/Library/Application Support/Godot/app_userdata}"

canonical_dir="$APP_USERDATA_DIR/$PROJECT_NAME"
stale_dir="$APP_USERDATA_DIR/$STALE_PROJECT_NAME"
temp_dir="$APP_USERDATA_DIR/.${PROJECT_NAME}.casefix.$$"

dir_id() {
  case "$(uname -s)" in
    Darwin) stat -f '%d:%i' "$1" ;;
    *) stat -c '%d:%i' "$1" ;;
  esac
}

exact_dir_exists() {
  expected_name="$1"
  for path in "$APP_USERDATA_DIR"/*; do
    [ -e "$path" ] || continue
    [ -d "$path" ] || continue
    [ "$(basename "$path")" = "$expected_name" ] || continue
    return 0
  done
  return 1
}

rename_stale_dir() {
  if [ -e "$temp_dir" ]; then
    echo "Temporary path already exists: $temp_dir" >&2
    exit 1
  fi
  mv "$stale_dir" "$temp_dir"
  mv "$temp_dir" "$canonical_dir"
  echo "Renamed Godot userdata directory:"
  echo "  $stale_dir"
  echo "  -> $canonical_dir"
}

if [ ! -d "$APP_USERDATA_DIR" ]; then
  echo "Godot userdata root not found: $APP_USERDATA_DIR"
  exit 0
fi

if [ "$canonical_dir" = "$stale_dir" ]; then
  echo "Project names already match: $PROJECT_NAME"
  exit 0
fi

canonical_exact=0
stale_exact=0
if exact_dir_exists "$PROJECT_NAME"; then
  canonical_exact=1
fi
if exact_dir_exists "$STALE_PROJECT_NAME"; then
  stale_exact=1
fi

if [ "$canonical_exact" = "1" ] && [ "$stale_exact" = "0" ]; then
  echo "Godot userdata directory already normalized: $canonical_dir"
  exit 0
fi

if [ "$canonical_exact" = "1" ] && [ "$stale_exact" = "1" ]; then
  echo "Both Godot userdata directories exist:" >&2
  echo "  stale:     $stale_dir" >&2
  echo "  canonical: $canonical_dir" >&2
  echo "Refusing to merge or delete user data automatically." >&2
  exit 1
fi

if [ -d "$stale_dir" ] && [ -d "$canonical_dir" ]; then
  stale_id="$(dir_id "$stale_dir")"
  canonical_id="$(dir_id "$canonical_dir")"
  if [ "$stale_id" = "$canonical_id" ]; then
    rename_stale_dir
    exit 0
  fi
  echo "Both Godot userdata directories exist:" >&2
  echo "  stale:     $stale_dir" >&2
  echo "  canonical: $canonical_dir" >&2
  echo "Refusing to merge or delete user data automatically." >&2
  exit 1
fi

if [ -d "$stale_dir" ]; then
  rename_stale_dir
  exit 0
fi

echo "Godot userdata directory already normalized: $canonical_dir"
