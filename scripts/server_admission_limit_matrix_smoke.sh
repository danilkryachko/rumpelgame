#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/server_admission_limit_matrix_current"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

SMOKE_SCRIPT="${RUMPELMC_SERVER_ADMISSION_LIMIT_MATRIX_SCRIPT:-"$ROOT_DIR/scripts/server_admission_limit_smoke.sh"}"
SUMMARY_PATH="$OUT_DIR/server-admission-limit-matrix-summary.txt"
LIMITS="${RUMPELMC_SERVER_ADMISSION_LIMIT_MATRIX_LIMITS:-1 2 3}"
BASE_PORT="${RUMPELMC_SERVER_ADMISSION_LIMIT_MATRIX_BASE_PORT:-25580}"
BUILD_SERVER="${RUMPELMC_SERVER_ADMISSION_LIMIT_MATRIX_BUILD_SERVER:-1}"
SUMMARY_ARGS=""

mkdir -p "$OUT_DIR"

fail() {
  echo "server_admission_limit_matrix_smoke: $*" >&2
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
  ''|*[!0-9]*) fail "unsupported RUMPELMC_SERVER_ADMISSION_LIMIT_MATRIX_BASE_PORT=$BASE_PORT" ;;
esac
test -x "$SMOKE_SCRIPT" || fail "missing executable admission smoke script $SMOKE_SCRIPT"

rm -rf "$OUT_DIR"/limit-*
rm -f "$SUMMARY_PATH"

limit_count=0
for limit in $LIMITS; do
  case "$limit" in
    ''|*[!0-9]*) fail "unsupported admission limit value $limit" ;;
  esac
  if [ "$limit" -lt 1 ]; then
    fail "admission limit must be at least 1, got $limit"
  fi

  limit_count=$((limit_count + 1))
  run_dir="$OUT_DIR/limit-${limit}_current"
  run_port=$((BASE_PORT + limit_count - 1))
  run_build="$BUILD_SERVER"
  if [ "$limit_count" -gt 1 ] && [ "$BUILD_SERVER" = "1" ]; then
    run_build="0"
  fi

  RUMPELMC_SERVER_ADMISSION_LIMIT_SMOKE_MAX_CLIENTS="$limit" \
    RUMPELMC_SERVER_ADMISSION_LIMIT_SMOKE_PORT="$run_port" \
    RUMPELMC_SERVER_ADMISSION_LIMIT_SMOKE_BUILD_SERVER="$run_build" \
    "$SMOKE_SCRIPT" "$run_dir" > "$OUT_DIR/limit-$limit.txt" 2>&1 || {
      cat "$OUT_DIR/limit-$limit.txt" >&2 || true
      fail "admission limit $limit smoke failed"
    }

  run_summary="$run_dir/server-admission-limit-smoke-summary.txt"
  test -s "$run_summary" || fail "missing summary for admission limit $limit"
  if [ "$(field_metric status "$run_summary")" != "pass" ]; then
    cat "$run_summary" >&2 || true
    fail "admission limit $limit did not pass"
  fi
  SUMMARY_ARGS="$SUMMARY_ARGS $run_summary"
done

if [ "$limit_count" -lt 1 ]; then
  fail "no admission limits configured"
fi

awk -v expected_limits="$limit_count" '
  {
    status = field_value($0, "status")
    max_clients = field_value($0, "max_clients") + 0
    attempted_clients = field_value($0, "attempted_clients") + 0
    admitted_clients = field_value($0, "admitted_clients") + 0
    rejected_clients = field_value($0, "rejected_clients") + 0
    holder_initial_chunks = field_value($0, "holder_initial_chunks") + 0
    if (holder_initial_chunks == 0) {
      holder_initial_chunks = field_value($0, "holder_initial_chunk") + 0
    }
    rejected_close_observed = field_value($0, "rejected_close_observed") + 0
    admission_rejection_log = field_value($0, "admission_rejection_log") + 0
    protocol_change += field_value($0, "protocol_change") + 0

    limits_checked++
    if (status == "pass") {
      passed_limits++
    }
    if (max_clients > max_limit) {
      max_limit = max_clients
    }
    total_attempted += attempted_clients
    total_admitted += admitted_clients
    total_rejected += rejected_clients
    total_holder_initial_chunks += holder_initial_chunks
    total_rejection_logs += admission_rejection_log

    if (attempted_clients != max_clients + 1 ||
        admitted_clients != max_clients ||
        rejected_clients != 1 ||
        holder_initial_chunks != max_clients ||
        rejected_close_observed != 1 ||
        admission_rejection_log != 1) {
      invariant_failures++
    }
  }

  END {
    status = "pass"
    reason = "ok"
    if (limits_checked != expected_limits) {
      status = "fail"
      reason = "missing_limits"
    } else if (passed_limits != expected_limits) {
      status = "fail"
      reason = "limit_failed"
    } else if (invariant_failures != 0) {
      status = "fail"
      reason = "admission_invariant_failed"
    } else if (protocol_change != 0) {
      status = "fail"
      reason = "protocol_change_present"
    }

    printf("server_admission_limit_matrix status=%s reason=%s limits_checked=%d passed_limits=%d max_limit=%d total_attempted_clients=%d total_admitted_clients=%d total_rejected_clients=%d total_holder_initial_chunks=%d total_rejection_logs=%d protocol_change=%d\n", status, reason, limits_checked + 0, passed_limits + 0, max_limit + 0, total_attempted + 0, total_admitted + 0, total_rejected + 0, total_holder_initial_chunks + 0, total_rejection_logs + 0, protocol_change + 0)
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
' $SUMMARY_ARGS > "$SUMMARY_PATH" || {
  cat "$SUMMARY_PATH" >&2 || true
  fail "admission limit matrix summary failed"
}

cat "$SUMMARY_PATH"
