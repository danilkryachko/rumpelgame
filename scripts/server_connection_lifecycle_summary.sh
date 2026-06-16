#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/server_connection_lifecycle"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac
shift || true

SUMMARY_PATH="$OUT_DIR/server-connection-lifecycle-summary.txt"
COUNTS_PATH="$OUT_DIR/server-connection-lifecycle-counts.tsv"

mkdir -p "$OUT_DIR"

fail() {
  echo "server_connection_lifecycle_summary: $*" >&2
  exit 1
}

if [ "$#" -eq 0 ]; then
  fail "provide at least one server log path"
fi

for path in "$@"; do
  test -s "$path" || fail "missing server log $path"
done

awk -v counts_path="$COUNTS_PATH" '
  BEGIN {
    status = "pass"
    reason = "ok"
  }

  FNR == 1 {
    log_count++
  }

  /Client connected:/ {
    connected_clients++
    if (!record_metric($0, "active_clients", 1)) {
      missing_active_client_fields++
    }
    record_metric($0, "max_clients", 0)
  }

  /admission_result=rejected/ {
    rejected_clients++
    if (!record_metric($0, "active_clients", 1)) {
      missing_active_client_fields++
    }
    record_metric($0, "max_clients", 0)
  }

  /Client disconnected/ {
    disconnected_clients++
    if (index($0, "packet_error_class=") > 0) {
      packet_error_disconnects++
      packet_class = field_value($0, "packet_error_class")
      if (packet_class == "eof") {
        eof_disconnects++
      } else if (packet_class == "timeout") {
        timeout_disconnects++
      }
    } else if (index($0, "EOF") > 0) {
      eof_disconnects++
    }
  }

  /Failed to close client/ {
    close_failures++
  }

  /Failed to accept connection/ {
    accept_failures++
  }

  END {
    if (log_count == 0) {
      status = "fail"
      reason = "missing_logs"
    } else if (connected_clients + rejected_clients + disconnected_clients == 0) {
      status = "fail"
      reason = "no_lifecycle_events"
    } else if (close_failures > 0) {
      status = "fail"
      reason = "client_close_failures"
    } else if (accept_failures > 0) {
      status = "fail"
      reason = "accept_failures"
    }

    print "metric\tcount" > counts_path
    printf("logs\t%d\n", log_count) >> counts_path
    printf("connected_clients\t%d\n", connected_clients + 0) >> counts_path
    printf("rejected_clients\t%d\n", rejected_clients + 0) >> counts_path
    printf("disconnected_clients\t%d\n", disconnected_clients + 0) >> counts_path
    printf("packet_error_disconnects\t%d\n", packet_error_disconnects + 0) >> counts_path
    printf("eof_disconnects\t%d\n", eof_disconnects + 0) >> counts_path
    printf("timeout_disconnects\t%d\n", timeout_disconnects + 0) >> counts_path
    printf("close_failures\t%d\n", close_failures + 0) >> counts_path
    printf("accept_failures\t%d\n", accept_failures + 0) >> counts_path
    printf("max_logged_active_clients\t%d\n", max_logged_active_clients + 0) >> counts_path
    printf("max_logged_max_clients\t%d\n", max_logged_max_clients + 0) >> counts_path
    printf("missing_active_client_fields\t%d\n", missing_active_client_fields + 0) >> counts_path

    printf("server_connection_lifecycle status=%s reason=%s logs=%d connected_clients=%d rejected_clients=%d disconnected_clients=%d packet_error_disconnects=%d eof_disconnects=%d timeout_disconnects=%d close_failures=%d accept_failures=%d max_logged_active_clients=%d max_logged_max_clients=%d missing_active_client_fields=%d counts=%s\n", status, reason, log_count, connected_clients + 0, rejected_clients + 0, disconnected_clients + 0, packet_error_disconnects + 0, eof_disconnects + 0, timeout_disconnects + 0, close_failures + 0, accept_failures + 0, max_logged_active_clients + 0, max_logged_max_clients + 0, missing_active_client_fields + 0, counts_path)
    if (status != "pass") {
      exit 1
    }
  }

  function record_metric(line, key, active_metric, value) {
    value = field_value(line, key)
    if (value == "") {
      return 0
    }
    if (active_metric && value + 0 > max_logged_active_clients + 0) {
      max_logged_active_clients = value + 0
    }
    if (!active_metric && value + 0 > max_logged_max_clients + 0) {
      max_logged_max_clients = value + 0
    }
    return 1
  }

  function field_value(line, key, i, parts, prefix, value, part_count) {
    part_count = split(line, parts, /[[:space:]]+/)
    prefix = key "="
    for (i = 1; i <= part_count; i++) {
      if (index(parts[i], prefix) == 1) {
        value = substr(parts[i], length(prefix) + 1)
        gsub(/^[",]+/, "", value)
        gsub(/[",:]+$/, "", value)
        return value
      }
    }
    return ""
  }
' "$@" > "$SUMMARY_PATH" || {
  cat "$SUMMARY_PATH" >&2 || true
  fail "server connection lifecycle summary failed"
}

cat "$SUMMARY_PATH"
