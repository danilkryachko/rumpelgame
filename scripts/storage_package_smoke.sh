#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/storage_package_smoke_current"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

SUMMARY_PATH="$OUT_DIR/storage-package-smoke-summary.txt"
GO_TEST_LOG="$OUT_DIR/go-storage-smoke-tests.txt"

mkdir -p "$OUT_DIR"

if (
  cd "$ROOT_DIR/server"
  RUMPELMC_SERVER_ROCKSDB_PATH="" \
    DATABASE_URL="postgres://ignored:ignored@127.0.0.1/ignored" \
    PGHOST="ignored" \
    PGDATABASE="ignored" \
    PGUSER="ignored" \
    PGPASSWORD="ignored" \
    go test ./cmd/server ./pkg/storage
) > "$GO_TEST_LOG" 2>&1; then
  printf 'storage_package_smoke status=pass reason=ok smoke_status=guarded external_secret_required=0 database_env_policy=postgres_env_ignored approved_databases=postgresql_rocksdb go_tests=pass log=%s\n' "$GO_TEST_LOG" > "$SUMMARY_PATH"
else
  cat "$GO_TEST_LOG" >&2 || true
  printf 'storage_package_smoke status=fail reason=go_tests_failed smoke_status=failed external_secret_required=0 database_env_policy=postgres_env_ignored approved_databases=postgresql_rocksdb go_tests=fail log=%s\n' "$GO_TEST_LOG" > "$SUMMARY_PATH"
  cat "$SUMMARY_PATH" >&2 || true
  exit 1
fi

cat "$SUMMARY_PATH"
echo "Storage package smoke artifacts: $OUT_DIR"
