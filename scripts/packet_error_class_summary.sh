#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/packet_error_class_summary"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac
shift || true

SUMMARY_PATH="$OUT_DIR/packet-error-class-summary.txt"
COUNTS_PATH="$OUT_DIR/packet-error-class-counts.tsv"
LOG_LIST="$OUT_DIR/packet-error-class-log-files.txt"

mkdir -p "$OUT_DIR"

fail() {
  echo "packet_error_class_summary: $*" >&2
  exit 1
}

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
else
  find "$ROOT_DIR/logs" -maxdepth 3 -type f \
    \( -name 'server.log' -o -name 'server-*.log' -o -name '*server*.log' \) | sort > "$LOG_LIST"
fi

awk \
  -v log_list="$LOG_LIST" \
  -v counts_path="$COUNTS_PATH" '
  BEGIN {
    class_order = "eof short_frame oversized_frame malformed_protobuf timeout short_write encode_error other"
    class_count = split(class_order, classes, " ")
    for (i = 1; i <= class_count; i++) {
      allowed[classes[i]] = 1
      counts[classes[i]] = 0
    }

    while ((getline file < log_list) > 0) {
      log_files++
      while ((getline line < file) > 0) {
        scan_line = line
        while (match(scan_line, /packet_error_class=[A-Za-z0-9_]+/)) {
          value = substr(scan_line, RSTART + length("packet_error_class="), RLENGTH - length("packet_error_class="))
          classified_events++
          if (value in allowed) {
            counts[value]++
          } else {
            unknown_classes++
            unknown_counts[value]++
          }
          scan_line = substr(scan_line, RSTART + RLENGTH)
        }
      }
      close(file)
    }
    close(log_list)

    print "class\tcount" > counts_path
    for (i = 1; i <= class_count; i++) {
      print classes[i] "\t" counts[classes[i]] >> counts_path
    }
    for (value in unknown_counts) {
      print "unknown:" value "\t" unknown_counts[value] >> counts_path
    }

    status = unknown_classes == 0 ? "pass" : "fail"
    reason = unknown_classes == 0 ? "ok" : "unknown_class"
    aggregation_status = classified_events > 0 ? "observed" : "empty"

    printf("packet_error_class_summary status=%s reason=%s aggregation_status=%s log_files=%d classified_events=%d unknown_classes=%d eof=%d short_frame=%d oversized_frame=%d malformed_protobuf=%d timeout=%d short_write=%d encode_error=%d other=%d counts=%s\n",
      status,
      reason,
      aggregation_status,
      log_files + 0,
      classified_events + 0,
      unknown_classes + 0,
      counts["eof"] + 0,
      counts["short_frame"] + 0,
      counts["oversized_frame"] + 0,
      counts["malformed_protobuf"] + 0,
      counts["timeout"] + 0,
      counts["short_write"] + 0,
      counts["encode_error"] + 0,
      counts["other"] + 0,
      counts_path)

    if (status != "pass") {
      exit 1
    }
  }
' > "$SUMMARY_PATH" || {
  cat "$SUMMARY_PATH" >&2 || true
  fail "packet error class summary failed"
}

cat "$SUMMARY_PATH"
echo "Packet error class summary artifacts: $OUT_DIR"
