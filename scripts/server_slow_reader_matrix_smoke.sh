#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/server_slow_reader_matrix_current"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

SMOKE_SCRIPT="${RUMPELMC_SERVER_SLOW_READER_MATRIX_SCRIPT:-"$ROOT_DIR/scripts/server_slow_reader_smoke.sh"}"
SUMMARY_PATH="$OUT_DIR/server-slow-reader-matrix-summary.txt"
COUNTS="${RUMPELMC_SERVER_SLOW_READER_MATRIX_FAST_CLIENT_COUNTS:-1 2 4}"
BASE_PORT="${RUMPELMC_SERVER_SLOW_READER_MATRIX_BASE_PORT:-25590}"
BUILD_SERVER="${RUMPELMC_SERVER_SLOW_READER_MATRIX_BUILD_SERVER:-1}"
INPUT_SUMMARIES="$OUT_DIR/slow-reader-matrix-inputs.txt"

mkdir -p "$OUT_DIR"

fail() {
  echo "server_slow_reader_matrix_smoke: $*" >&2
  exit 1
}

field_metric() {
  key="$1"
  path="$2"
  awk -v key="$key" '
    {
      prefix = key "="
      for (i = 1; i <= NF; i++) {
        if (index($i, prefix) == 1) {
          value = substr($i, length(prefix) + 1)
          gsub(/^"/, "", value)
          gsub(/"$/, "", value)
          print value
          exit
        }
      }
    }
  ' "$path"
}

case "$BASE_PORT" in
  ''|*[!0-9]*) fail "unsupported RUMPELMC_SERVER_SLOW_READER_MATRIX_BASE_PORT=$BASE_PORT" ;;
esac
test -x "$SMOKE_SCRIPT" || fail "missing executable slow-reader smoke script $SMOKE_SCRIPT"

rm -rf "$OUT_DIR"/fast-*
rm -f "$SUMMARY_PATH" "$INPUT_SUMMARIES"
: > "$INPUT_SUMMARIES"

count_index=0
for fast_count in $COUNTS; do
  case "$fast_count" in
    ''|*[!0-9]*) fail "unsupported fast-client count $fast_count" ;;
  esac
  if [ "$fast_count" -lt 1 ]; then
    fail "fast-client count must be at least 1, got $fast_count"
  fi

  count_index=$((count_index + 1))
  run_dir="$OUT_DIR/fast-${fast_count}_current"
  run_port=$((BASE_PORT + count_index - 1))
  run_build="$BUILD_SERVER"
  if [ "$count_index" -gt 1 ] && [ "$BUILD_SERVER" = "1" ]; then
    run_build="0"
  fi

  RUMPELMC_SERVER_SLOW_READER_FAST_CLIENTS="$fast_count" \
    RUMPELMC_SERVER_SLOW_READER_SMOKE_PORT="$run_port" \
    RUMPELMC_SERVER_SLOW_READER_SMOKE_BUILD_SERVER="$run_build" \
    "$SMOKE_SCRIPT" "$run_dir" > "$OUT_DIR/fast-$fast_count.txt" 2>&1 || {
      cat "$OUT_DIR/fast-$fast_count.txt" >&2 || true
      fail "slow-reader smoke failed for fast-client count $fast_count"
    }

  run_summary="$run_dir/server-slow-reader-smoke-summary.txt"
  test -s "$run_summary" || fail "missing summary for fast-client count $fast_count"
  if [ "$(field_metric status "$run_summary")" != "pass" ]; then
    cat "$run_summary" >&2 || true
    fail "slow-reader smoke did not pass for fast-client count $fast_count"
  fi
  cat "$run_summary" >> "$INPUT_SUMMARIES"
done

if [ "$count_index" -lt 1 ]; then
  fail "no fast-client counts configured"
fi

awk -v expected_counts="$count_index" '
  {
    status = field_value($0, "status")
    fast_clients = field_value($0, "fast_clients") + 0
    if (fast_clients == 0) {
      fast_clients = field_value($0, "fast_client") + 0
    }
    fast_bootstrap_chunks = field_value($0, "fast_bootstrap_chunks") + 0
    if (fast_bootstrap_chunks == 0) {
      fast_bootstrap_chunks = field_value($0, "fast_bootstrap_chunk") + 0
    }
    fast_bootstrap_ms = field_value($0, "fast_bootstrap_ms") + 0.0
    slow_timeout_observed = field_value($0, "slow_timeout_observed") + 0
    slow_timeout_class = field_value($0, "slow_timeout_class")
    protocol_change += field_value($0, "protocol_change") + 0

    counts_checked++
    if (status == "pass") {
      passed_counts++
    }
    if (fast_clients > max_fast_clients) {
      max_fast_clients = fast_clients
    }
    if (fast_bootstrap_ms > fast_bootstrap_ms_max) {
      fast_bootstrap_ms_max = fast_bootstrap_ms
    }
    total_fast_clients += fast_clients
    total_fast_bootstrap_chunks += fast_bootstrap_chunks
    total_slow_timeouts += slow_timeout_observed

    if (fast_clients < 1 ||
        fast_bootstrap_chunks != fast_clients ||
        slow_timeout_observed != 1 ||
        slow_timeout_class != "timeout") {
      invariant_failures++
    }
  }

  END {
    status = "pass"
    reason = "ok"
    if (counts_checked != expected_counts) {
      status = "fail"
      reason = "missing_counts"
    } else if (passed_counts != expected_counts) {
      status = "fail"
      reason = "count_failed"
    } else if (invariant_failures != 0) {
      status = "fail"
      reason = "slow_reader_invariant_failed"
    } else if (protocol_change != 0) {
      status = "fail"
      reason = "protocol_change_present"
    }

    printf("server_slow_reader_matrix status=%s reason=%s counts_checked=%d passed_counts=%d max_fast_clients=%d total_fast_clients=%d total_fast_bootstrap_chunks=%d total_slow_timeouts=%d fast_bootstrap_ms_max=%.3f protocol_change=%d\n", status, reason, counts_checked + 0, passed_counts + 0, max_fast_clients + 0, total_fast_clients + 0, total_fast_bootstrap_chunks + 0, total_slow_timeouts + 0, fast_bootstrap_ms_max + 0.0, protocol_change + 0)
    if (status != "pass") {
      exit 1
    }
  }

  function field_value(line, key, i, parts, prefix, value, part_count) {
    part_count = split(line, parts, /[[:space:]]+/)
    prefix = key "="
    for (i = 1; i <= part_count; i++) {
      if (index(parts[i], prefix) == 1) {
        value = substr(parts[i], length(prefix) + 1)
        gsub(/^[",]+/, "", value)
        gsub(/[",]+$/, "", value)
        return value
      }
    }
    return ""
  }
' "$INPUT_SUMMARIES" > "$SUMMARY_PATH" || {
  cat "$SUMMARY_PATH" >&2 || true
  fail "slow-reader matrix summary failed"
}

cat "$SUMMARY_PATH"
