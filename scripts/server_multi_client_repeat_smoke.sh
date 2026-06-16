#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/server_multi_client_repeat_smoke"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

SMOKE_SCRIPT="${RUMPELMC_SERVER_MULTI_CLIENT_REPEAT_SMOKE_SCRIPT:-"$ROOT_DIR/scripts/server_multi_client_smoke.sh"}"
SUMMARY_PATH="$OUT_DIR/server-multi-client-repeat-smoke-summary.txt"
REPEATS="${RUMPELMC_SERVER_MULTI_CLIENT_REPEAT_SMOKE_REPEATS:-3}"
CLIENTS="${RUMPELMC_SERVER_MULTI_CLIENT_REPEAT_SMOKE_CLIENTS:-6}"
BASE_PORT="${RUMPELMC_SERVER_MULTI_CLIENT_REPEAT_SMOKE_BASE_PORT:-25570}"
BUILD_SERVER="${RUMPELMC_SERVER_MULTI_CLIENT_REPEAT_SMOKE_BUILD_SERVER:-1}"
SUMMARY_ARGS=""

mkdir -p "$OUT_DIR"

fail() {
  echo "server_multi_client_repeat_smoke: $*" >&2
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

case "$REPEATS" in
  ''|*[!0-9]*) fail "unsupported RUMPELMC_SERVER_MULTI_CLIENT_REPEAT_SMOKE_REPEATS=$REPEATS" ;;
esac
case "$CLIENTS" in
  ''|*[!0-9]*) fail "unsupported RUMPELMC_SERVER_MULTI_CLIENT_REPEAT_SMOKE_CLIENTS=$CLIENTS" ;;
esac
if [ "$REPEATS" -lt 1 ]; then
  fail "RUMPELMC_SERVER_MULTI_CLIENT_REPEAT_SMOKE_REPEATS must be at least 1"
fi
if [ "$CLIENTS" -lt 2 ]; then
  fail "RUMPELMC_SERVER_MULTI_CLIENT_REPEAT_SMOKE_CLIENTS must be at least 2"
fi
test -x "$SMOKE_SCRIPT" || fail "missing executable smoke script $SMOKE_SCRIPT"

rm -rf "$OUT_DIR"/run-*
rm -f "$SUMMARY_PATH"

run_index=1
while [ "$run_index" -le "$REPEATS" ]; do
  run_dir="$OUT_DIR/run-${run_index}_current"
  run_port=$((BASE_PORT + run_index - 1))
  run_build="$BUILD_SERVER"
  if [ "$run_index" -gt 1 ] && [ "$BUILD_SERVER" = "1" ]; then
    run_build="0"
  fi

  RUMPELMC_SERVER_MULTI_CLIENT_SMOKE_CLIENTS="$CLIENTS" \
    RUMPELMC_SERVER_MULTI_CLIENT_SMOKE_PORT="$run_port" \
    RUMPELMC_SERVER_MULTI_CLIENT_SMOKE_BUILD_SERVER="$run_build" \
    "$SMOKE_SCRIPT" "$run_dir" > "$OUT_DIR/run-$run_index.txt" 2>&1 || {
      cat "$OUT_DIR/run-$run_index.txt" >&2 || true
      fail "repeat $run_index failed"
    }

  run_summary="$run_dir/server-multi-client-smoke-summary.txt"
  test -s "$run_summary" || fail "missing summary for repeat $run_index"
  if [ "$(field_metric status "$run_summary")" != "pass" ]; then
    cat "$run_summary" >&2 || true
    fail "repeat $run_index did not pass"
  fi
  SUMMARY_ARGS="$SUMMARY_ARGS $run_summary"
  run_index=$((run_index + 1))
done

awk -v repeats="$REPEATS" -v clients="$CLIENTS" '
  {
    status = field_value($0, "status")
    run_clients = field_value($0, "clients") + 0
    initial_chunks = field_value($0, "initial_chunks") + 0
    fanout_updates = field_value($0, "fanout_updates") + 0
    detail_status = field_value($0, "detail_status")
    detail_clients = field_value($0, "detail_clients") + 0
    detail_initial_chunks = field_value($0, "detail_initial_chunks") + 0
    detail_update_chunks = field_value($0, "detail_update_chunks") + 0
    resource_samples = field_value($0, "server_resource_samples") + 0
    rss_max = field_value($0, "server_rss_kb_max") + 0
    cpu_max = field_value($0, "server_cpu_pct_max") + 0.0
    initial_ms = field_value($0, "detail_initial_ms_max") + 0.0
    update_ms = field_value($0, "detail_update_ms_max") + 0.0
    protocol_change += field_value($0, "protocol_change") + 0

    runs++
    if (status == "pass") {
      passed_runs++
    }
    if (run_clients != clients) {
      client_mismatches++
    }
    total_initial_chunks += initial_chunks
    total_fanout_updates += fanout_updates
    total_detail_clients += detail_clients
    total_resource_samples += resource_samples
    if (detail_status != "pass" || detail_clients != run_clients || detail_initial_chunks != run_clients || detail_update_chunks != run_clients) {
      detail_failures++
    }
    if (resource_samples < 1 || rss_max < 1) {
      resource_failures++
    }
    if (rss_max > max_rss) {
      max_rss = rss_max
    }
    if (cpu_max > max_cpu) {
      max_cpu = cpu_max
    }
    if (initial_ms > max_initial_ms) {
      max_initial_ms = initial_ms
    }
    if (update_ms > max_update_ms) {
      max_update_ms = update_ms
    }
  }

  END {
    status = "pass"
    reason = "ok"
    expected_events = repeats * clients
    if (runs != repeats) {
      status = "fail"
      reason = "missing_runs"
    } else if (passed_runs != repeats) {
      status = "fail"
      reason = "run_failed"
    } else if (client_mismatches != 0) {
      status = "fail"
      reason = "client_count_mismatch"
    } else if (total_initial_chunks != expected_events || total_fanout_updates != expected_events) {
      status = "fail"
      reason = "chunk_count_mismatch"
    } else if (detail_failures != 0 || total_detail_clients != expected_events) {
      status = "fail"
      reason = "detail_mismatch"
    } else if (resource_failures != 0 || total_resource_samples < repeats) {
      status = "fail"
      reason = "resource_samples_missing"
    } else if (protocol_change != 0) {
      status = "fail"
      reason = "protocol_change_present"
    }

    printf("server_multi_client_repeat_smoke status=%s reason=%s repeats=%d clients=%d passed_runs=%d total_initial_chunks=%d total_fanout_updates=%d total_detail_clients=%d total_resource_samples=%d max_rss_kb=%d max_cpu_pct=%.1f max_initial_ms=%.3f max_update_ms=%.3f protocol_change=%d\n", status, reason, repeats, clients, passed_runs + 0, total_initial_chunks + 0, total_fanout_updates + 0, total_detail_clients + 0, total_resource_samples + 0, max_rss + 0, max_cpu + 0.0, max_initial_ms + 0.0, max_update_ms + 0.0, protocol_change + 0)
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
  fail "repeat smoke summary failed"
}

cat "$SUMMARY_PATH"
