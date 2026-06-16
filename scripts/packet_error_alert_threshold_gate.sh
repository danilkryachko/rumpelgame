#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/packet_error_alert_threshold_current"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac
shift || true

SUMMARY_SCRIPT="${RUMPELMC_PACKET_ERROR_ALERT_SUMMARY_SCRIPT:-"$ROOT_DIR/scripts/packet_error_class_summary.sh"}"
SUMMARY_PATH="$OUT_DIR/packet-error-alert-threshold-summary.txt"
CLASS_SUMMARY_PATH="$OUT_DIR/packet-error-class-summary.txt"
RUN_LOG="$OUT_DIR/packet-error-class-summary-run.txt"
LOG_LIST="$OUT_DIR/packet-error-alert-log-files.txt"

MAX_UNKNOWN="${RUMPELMC_PACKET_ERROR_ALERT_MAX_UNKNOWN:-0}"
MAX_PROTOCOL_ERRORS="${RUMPELMC_PACKET_ERROR_ALERT_MAX_PROTOCOL_ERRORS:-0}"
MAX_WRITE_ERRORS="${RUMPELMC_PACKET_ERROR_ALERT_MAX_WRITE_ERRORS:-0}"
MAX_TIMEOUT="${RUMPELMC_PACKET_ERROR_ALERT_MAX_TIMEOUT:-4}"
MAX_EOF="${RUMPELMC_PACKET_ERROR_ALERT_MAX_EOF:-999999}"
MIN_CLASSIFIED="${RUMPELMC_PACKET_ERROR_ALERT_MIN_CLASSIFIED:-1}"

mkdir -p "$OUT_DIR"

fail() {
  echo "packet_error_alert_threshold_gate: $*" >&2
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

validate_non_negative_int() {
  name="$1"
  value="$2"
  case "$value" in
    ''|*[!0-9]*) fail "$name must be a non-negative integer, got $value" ;;
  esac
}

for pair in \
  "RUMPELMC_PACKET_ERROR_ALERT_MAX_UNKNOWN=$MAX_UNKNOWN" \
  "RUMPELMC_PACKET_ERROR_ALERT_MAX_PROTOCOL_ERRORS=$MAX_PROTOCOL_ERRORS" \
  "RUMPELMC_PACKET_ERROR_ALERT_MAX_WRITE_ERRORS=$MAX_WRITE_ERRORS" \
  "RUMPELMC_PACKET_ERROR_ALERT_MAX_TIMEOUT=$MAX_TIMEOUT" \
  "RUMPELMC_PACKET_ERROR_ALERT_MAX_EOF=$MAX_EOF" \
  "RUMPELMC_PACKET_ERROR_ALERT_MIN_CLASSIFIED=$MIN_CLASSIFIED"; do
  validate_non_negative_int "${pair%%=*}" "${pair#*=}"
done

test -x "$SUMMARY_SCRIPT" || fail "missing executable summary script $SUMMARY_SCRIPT"

: > "$LOG_LIST"
if [ "$#" -gt 0 ]; then
  for path in "$@"; do
    case "$path" in
      /*) log_path="$path" ;;
      *) log_path="$ROOT_DIR/$path" ;;
    esac
    test -s "$log_path" || fail "missing log file $log_path"
    printf '%s\n' "$log_path" >> "$LOG_LIST"
  done
elif [ "${RUMPELMC_PACKET_ERROR_ALERT_LOGS:-}" ]; then
  for path in $RUMPELMC_PACKET_ERROR_ALERT_LOGS; do
    case "$path" in
      /*) log_path="$path" ;;
      *) log_path="$ROOT_DIR/$path" ;;
    esac
    test -s "$log_path" || fail "missing log file $log_path"
    printf '%s\n' "$log_path" >> "$LOG_LIST"
  done
else
  for path in \
    "$ROOT_DIR/logs/server_multi_client_smoke_current/server.log" \
    "$ROOT_DIR/logs/server_multi_client_load_current/server.log" \
    "$ROOT_DIR/logs/server_multi_client_repeat_smoke_current/run-1_current/server.log" \
    "$ROOT_DIR/logs/server_multi_client_repeat_smoke_current/run-2_current/server.log" \
    "$ROOT_DIR/logs/server_multi_client_repeat_smoke_current/run-3_current/server.log" \
    "$ROOT_DIR/logs/server_slow_reader_smoke_current/server.log" \
    "$ROOT_DIR/logs/server_slow_reader_matrix_current/fast-1_current/server.log" \
    "$ROOT_DIR/logs/server_slow_reader_matrix_current/fast-2_current/server.log" \
    "$ROOT_DIR/logs/server_slow_reader_matrix_current/fast-4_current/server.log" \
    "$ROOT_DIR/logs/server_admission_limit_smoke_current/server.log"; do
    if [ -s "$path" ]; then
      printf '%s\n' "$path" >> "$LOG_LIST"
    fi
  done
fi

if [ ! -s "$LOG_LIST" ]; then
  fail "no live server logs available for packet error alert thresholds"
fi

SUMMARY_ARGS=""
while IFS= read -r log_path; do
  SUMMARY_ARGS="$SUMMARY_ARGS $log_path"
done < "$LOG_LIST"

"$SUMMARY_SCRIPT" "$OUT_DIR" $SUMMARY_ARGS > "$RUN_LOG" 2>&1 || {
  cat "$RUN_LOG" >&2 || true
  fail "packet error class summary failed"
}
test -s "$CLASS_SUMMARY_PATH" || fail "missing class summary $CLASS_SUMMARY_PATH"

class_status="$(field_metric status "$CLASS_SUMMARY_PATH")"
log_files="$(field_metric log_files "$CLASS_SUMMARY_PATH")"
classified_events="$(field_metric classified_events "$CLASS_SUMMARY_PATH")"
unknown_classes="$(field_metric unknown_classes "$CLASS_SUMMARY_PATH")"
eof_count="$(field_metric eof "$CLASS_SUMMARY_PATH")"
short_frame_count="$(field_metric short_frame "$CLASS_SUMMARY_PATH")"
oversized_frame_count="$(field_metric oversized_frame "$CLASS_SUMMARY_PATH")"
malformed_count="$(field_metric malformed_protobuf "$CLASS_SUMMARY_PATH")"
timeout_count="$(field_metric timeout "$CLASS_SUMMARY_PATH")"
short_write_count="$(field_metric short_write "$CLASS_SUMMARY_PATH")"
encode_error_count="$(field_metric encode_error "$CLASS_SUMMARY_PATH")"
other_count="$(field_metric other "$CLASS_SUMMARY_PATH")"

awk \
  -v class_status="${class_status:-missing}" \
  -v log_files="${log_files:-0}" \
  -v classified_events="${classified_events:-0}" \
  -v unknown_classes="${unknown_classes:-0}" \
  -v eof_count="${eof_count:-0}" \
  -v short_frame_count="${short_frame_count:-0}" \
  -v oversized_frame_count="${oversized_frame_count:-0}" \
  -v malformed_count="${malformed_count:-0}" \
  -v timeout_count="${timeout_count:-0}" \
  -v short_write_count="${short_write_count:-0}" \
  -v encode_error_count="${encode_error_count:-0}" \
  -v other_count="${other_count:-0}" \
  -v max_unknown="$MAX_UNKNOWN" \
  -v max_protocol_errors="$MAX_PROTOCOL_ERRORS" \
  -v max_write_errors="$MAX_WRITE_ERRORS" \
  -v max_timeout="$MAX_TIMEOUT" \
  -v max_eof="$MAX_EOF" \
  -v min_classified="$MIN_CLASSIFIED" \
  -v class_summary="$CLASS_SUMMARY_PATH" \
  -v log_list="$LOG_LIST" '
  BEGIN {
    status = "pass"
    reason = "ok"
    alert_status = "threshold_guarded"
    protocol_errors = short_frame_count + oversized_frame_count + malformed_count
    write_errors = short_write_count + encode_error_count + other_count

    if (class_status != "pass") {
      status = "fail"
      reason = "class_summary_failed"
    } else if (classified_events + 0 < min_classified + 0) {
      status = "fail"
      reason = "classified_events_below_min"
    } else if (unknown_classes + 0 > max_unknown + 0) {
      status = "fail"
      reason = "unknown_class_threshold_exceeded"
    } else if (protocol_errors + 0 > max_protocol_errors + 0) {
      status = "fail"
      reason = "protocol_error_threshold_exceeded"
    } else if (write_errors + 0 > max_write_errors + 0) {
      status = "fail"
      reason = "write_error_threshold_exceeded"
    } else if (timeout_count + 0 > max_timeout + 0) {
      status = "fail"
      reason = "timeout_threshold_exceeded"
    } else if (eof_count + 0 > max_eof + 0) {
      status = "fail"
      reason = "eof_threshold_exceeded"
    }

    printf("packet_error_alert_threshold status=%s reason=%s alert_status=%s log_files=%d classified_events=%d unknown_classes=%d eof=%d timeout=%d protocol_errors=%d write_errors=%d max_unknown=%d max_protocol_errors=%d max_write_errors=%d max_timeout=%d max_eof=%d min_classified=%d class_summary=%s log_list=%s\n", status, reason, alert_status, log_files + 0, classified_events + 0, unknown_classes + 0, eof_count + 0, timeout_count + 0, protocol_errors + 0, write_errors + 0, max_unknown + 0, max_protocol_errors + 0, max_write_errors + 0, max_timeout + 0, max_eof + 0, min_classified + 0, class_summary, log_list)
    if (status != "pass") {
      exit 1
    }
  }
' > "$SUMMARY_PATH" || {
  cat "$SUMMARY_PATH" >&2 || true
  fail "packet error alert thresholds failed"
}

cat "$SUMMARY_PATH"
echo "Packet error alert threshold artifacts: $OUT_DIR"
