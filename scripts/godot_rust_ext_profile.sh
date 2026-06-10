#!/usr/bin/env sh

RUMPELMC_GODOT_RUST_EXT_RESTORE_ACTIVE=0
RUMPELMC_GODOT_RUST_EXT_DEBUG_LIB=""
RUMPELMC_GODOT_RUST_EXT_BACKUP_LIB=""

restore_godot_rust_ext_profile() {
  if [ "${RUMPELMC_GODOT_RUST_EXT_RESTORE_ACTIVE:-0}" != "1" ]; then
    return 0
  fi

  RUMPELMC_GODOT_RUST_EXT_RESTORE_ACTIVE=0
  rm -f "$RUMPELMC_GODOT_RUST_EXT_DEBUG_LIB" || true
  if [ -n "$RUMPELMC_GODOT_RUST_EXT_BACKUP_LIB" ]; then
    mv "$RUMPELMC_GODOT_RUST_EXT_BACKUP_LIB" "$RUMPELMC_GODOT_RUST_EXT_DEBUG_LIB" || true
  fi
}

godot_rust_ext_expected_profile() {
  profile="${RUMPELMC_GODOT_RUST_EXT_PROFILE:-release}"
  case "$profile" in
    debug|release)
      printf '%s\n' "$profile"
      ;;
    *)
      echo "godot_rust_ext_profile: unsupported RUMPELMC_GODOT_RUST_EXT_PROFILE=$profile" >&2
      exit 2
      ;;
  esac
}

require_godot_rust_ext_marker_profile() {
  marker_path="$1"
  expected_profile="$(godot_rust_ext_expected_profile)"
  grep -q "rust_ext_profile=$expected_profile" "$marker_path" || {
    echo "godot_rust_ext_profile: expected rust_ext_profile=$expected_profile in $marker_path" >&2
    exit 1
  }
}

prepare_godot_rust_ext_profile() {
  root_dir="$1"
  profile="$(godot_rust_ext_expected_profile)"

  case "$profile" in
    debug)
      echo "==> Rust GDExtension profile: debug"
      return 0
      ;;
    release) ;;
  esac

  case "$(uname -s)" in
    Darwin)
      debug_lib="$root_dir/client/rust_ext/target/debug/librust_ext.dylib"
      release_lib="$root_dir/client/rust_ext/target/release/librust_ext.dylib"
      ;;
    *)
      echo "godot_rust_ext_profile: release editor-run shim is only configured for macOS" >&2
      exit 2
      ;;
  esac

  build_release="${RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE:-0}"
  case "$build_release" in
    0|1) ;;
    *)
      echo "godot_rust_ext_profile: unsupported RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE=$build_release" >&2
      exit 2
      ;;
  esac

  echo "==> Rust GDExtension profile: release"
  if [ "$build_release" = "1" ]; then
    (
      cd "$root_dir/client/rust_ext"
      cargo build --release
    )
  fi
  test -s "$release_lib" || {
    echo "godot_rust_ext_profile: missing release library $release_lib" >&2
    echo "godot_rust_ext_profile: build it with RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE=1 or run with RUMPELMC_GODOT_RUST_EXT_PROFILE=debug" >&2
    exit 1
  }

  mkdir -p "$(dirname "$debug_lib")"
  RUMPELMC_GODOT_RUST_EXT_DEBUG_LIB="$debug_lib"
  RUMPELMC_GODOT_RUST_EXT_BACKUP_LIB=""
  if [ -e "$debug_lib" ]; then
    RUMPELMC_GODOT_RUST_EXT_BACKUP_LIB="$debug_lib.rumpelmc-debug-backup.$$"
  fi
  RUMPELMC_GODOT_RUST_EXT_RESTORE_ACTIVE=1
  trap restore_godot_rust_ext_profile EXIT HUP INT TERM

  if [ -n "$RUMPELMC_GODOT_RUST_EXT_BACKUP_LIB" ]; then
    mv "$debug_lib" "$RUMPELMC_GODOT_RUST_EXT_BACKUP_LIB"
  fi
  cp "$release_lib" "$debug_lib"
  echo "==> Godot editor will load release Rust GDExtension through the debug extension slot"
}
