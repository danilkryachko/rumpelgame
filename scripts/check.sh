#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
MODE="${1:-fast}"

case "$MODE" in
  fast|full) ;;
  *)
    echo "usage: $0 [fast|full]" >&2
    exit 2
    ;;
esac

echo "==> Go server tests"
(
  cd "$ROOT_DIR/server"
  go test ./...
)

if [ "$MODE" = "full" ]; then
  if command -v golangci-lint >/dev/null 2>&1; then
    echo "==> Go lint"
    (
      cd "$ROOT_DIR/server"
      golangci-lint run ./...
    )
  else
    echo "==> Go lint skipped: golangci-lint not found"
  fi
fi

echo "==> Rust extension checks"
(
  cd "$ROOT_DIR/client/rust_ext"
  if [ "$MODE" = "full" ]; then
    cargo fmt -- --check
    cargo clippy -- -D warnings
  fi
  cargo check
  cargo test
)
