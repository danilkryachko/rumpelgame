#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/packet_error_monitoring_contract_current"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

SUMMARY_PATH="$OUT_DIR/packet-error-monitoring-contract-summary.txt"
METRICS_PATH="$OUT_DIR/packet-error-monitoring-metrics.txt"
RUN_LOG="$OUT_DIR/packet-error-alert-threshold-run.txt"
DESIGN_DOC="${RUMPELMC_PACKET_ERROR_MONITORING_DOC:-"$ROOT_DIR/docs/PACKET_ERROR_MONITORING_CONTRACT.md"}"
ALERT_SCRIPT="${RUMPELMC_PACKET_ERROR_MONITORING_ALERT_SCRIPT:-"$ROOT_DIR/scripts/packet_error_alert_threshold_gate.sh"}"
ALERT_SUMMARY="${RUMPELMC_PACKET_ERROR_MONITORING_ALERT_SUMMARY:-"$ROOT_DIR/logs/packet_error_alert_threshold_current/packet-error-alert-threshold-summary.txt"}"
NETWORKING_SUMMARY="${RUMPELMC_PACKET_ERROR_MONITORING_NETWORKING_SUMMARY:-"$ROOT_DIR/logs/networking_robustness_current/networking-robustness-summary.txt"}"
OBSERVABILITY_SUMMARY="${RUMPELMC_PACKET_ERROR_MONITORING_OBSERVABILITY_SUMMARY:-"$ROOT_DIR/logs/observability_logs_cleanup_current/observability-logs-cleanup-summary.txt"}"
RUN_ALERT="${RUMPELMC_PACKET_ERROR_MONITORING_RUN_ALERT:-1}"

mkdir -p "$OUT_DIR"

fail() {
  echo "packet_error_monitoring_contract_gate: $*" >&2
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

require_token() {
  path="$1"
  token="$2"
  test -s "$path" || fail "missing file $path"
  grep -Fq "$token" "$path" || fail "missing token '$token' in $path"
}

relative_path() {
  path="$1"
  case "$path" in
    "$ROOT_DIR"/*) printf '%s\n' "${path#"$ROOT_DIR"/}" ;;
    *) printf '%s\n' "$path" ;;
  esac
}

case "$RUN_ALERT" in
  0|1) ;;
  *) fail "RUMPELMC_PACKET_ERROR_MONITORING_RUN_ALERT must be 0 or 1" ;;
esac

test -x "$ALERT_SCRIPT" || fail "missing executable alert script $ALERT_SCRIPT"
test -s "$DESIGN_DOC" || fail "missing design doc $DESIGN_DOC"

for token in \
  'Monitoring Contract' \
  'Metrics Export' \
  'Threshold Policy' \
  'Trust Boundary' \
  'Compatibility Rules'; do
  require_token "$DESIGN_DOC" "$token"
done

if [ "$RUN_ALERT" = "1" ]; then
  alert_out_dir="$(dirname -- "$ALERT_SUMMARY")"
  sh "$ALERT_SCRIPT" "$alert_out_dir" > "$RUN_LOG" 2>&1 || {
    cat "$RUN_LOG" >&2 || true
    fail "packet error alert threshold gate failed"
  }
fi

for path in "$ALERT_SUMMARY" "$NETWORKING_SUMMARY" "$OBSERVABILITY_SUMMARY"; do
  test -s "$path" || fail "missing required input $path"
done

alert_status="$(field_metric status "$ALERT_SUMMARY")"
alert_guard="$(field_metric alert_status "$ALERT_SUMMARY")"
alert_log_files="$(field_metric log_files "$ALERT_SUMMARY")"
classified_events="$(field_metric classified_events "$ALERT_SUMMARY")"
unknown_classes="$(field_metric unknown_classes "$ALERT_SUMMARY")"
eof_count="$(field_metric eof "$ALERT_SUMMARY")"
timeout_count="$(field_metric timeout "$ALERT_SUMMARY")"
protocol_errors="$(field_metric protocol_errors "$ALERT_SUMMARY")"
write_errors="$(field_metric write_errors "$ALERT_SUMMARY")"
max_unknown="$(field_metric max_unknown "$ALERT_SUMMARY")"
max_protocol_errors="$(field_metric max_protocol_errors "$ALERT_SUMMARY")"
max_write_errors="$(field_metric max_write_errors "$ALERT_SUMMARY")"
max_timeout="$(field_metric max_timeout "$ALERT_SUMMARY")"
max_eof="$(field_metric max_eof "$ALERT_SUMMARY")"
min_classified="$(field_metric min_classified "$ALERT_SUMMARY")"
class_summary="$(field_metric class_summary "$ALERT_SUMMARY")"
log_list="$(field_metric log_list "$ALERT_SUMMARY")"

test -s "$class_summary" || fail "missing class summary $class_summary"
test -s "$log_list" || fail "missing alert log list $log_list"

class_status="$(field_metric status "$class_summary")"
class_aggregation_status="$(field_metric aggregation_status "$class_summary")"
networking_status="$(field_metric status "$NETWORKING_SUMMARY")"
networking_packet_error_classification="$(field_metric packet_error_classification "$NETWORKING_SUMMARY")"
networking_packet_error_aggregation="$(field_metric packet_error_aggregation "$NETWORKING_SUMMARY")"
networking_packet_error_alerts="$(field_metric packet_error_alerts "$NETWORKING_SUMMARY")"
observability_status="$(field_metric status "$OBSERVABILITY_SUMMARY")"
observability_error_scan="$(field_metric error_scan "$OBSERVABILITY_SUMMARY")"
observability_index="$(field_metric index "$OBSERVABILITY_SUMMARY")"

test -s "$observability_index" || fail "missing observability index $observability_index"

alert_rel="$(relative_path "$ALERT_SUMMARY")"
class_rel="$(relative_path "$class_summary")"
index_alert_status="missing"
index_class_status="missing"
if grep -F "path=$alert_rel " "$observability_index" >/dev/null 2>&1; then
  index_alert_status="present"
fi
if grep -F "path=$class_rel " "$observability_index" >/dev/null 2>&1; then
  index_class_status="present"
fi

{
  printf 'packet_error_classified_events %s\n' "${classified_events:-0}"
  printf 'packet_error_unknown_classes %s\n' "${unknown_classes:-0}"
  printf 'packet_error_protocol_errors %s\n' "${protocol_errors:-0}"
  printf 'packet_error_write_errors %s\n' "${write_errors:-0}"
  printf 'packet_error_timeout_events %s\n' "${timeout_count:-0}"
  printf 'packet_error_eof_events %s\n' "${eof_count:-0}"
  printf 'packet_error_log_files %s\n' "${alert_log_files:-0}"
  printf 'packet_error_threshold_max_unknown %s\n' "${max_unknown:-0}"
  printf 'packet_error_threshold_max_protocol_errors %s\n' "${max_protocol_errors:-0}"
  printf 'packet_error_threshold_max_write_errors %s\n' "${max_write_errors:-0}"
  printf 'packet_error_threshold_max_timeout %s\n' "${max_timeout:-0}"
  printf 'packet_error_threshold_max_eof %s\n' "${max_eof:-0}"
  printf 'packet_error_threshold_min_classified %s\n' "${min_classified:-0}"
} > "$METRICS_PATH"

awk \
  -v alert_status="${alert_status:-missing}" \
  -v alert_guard="${alert_guard:-missing}" \
  -v alert_log_files="${alert_log_files:-0}" \
  -v classified_events="${classified_events:-0}" \
  -v unknown_classes="${unknown_classes:-1}" \
  -v protocol_errors="${protocol_errors:-1}" \
  -v write_errors="${write_errors:-1}" \
  -v timeout_count="${timeout_count:-0}" \
  -v eof_count="${eof_count:-0}" \
  -v max_unknown="${max_unknown:-0}" \
  -v max_protocol_errors="${max_protocol_errors:-0}" \
  -v max_write_errors="${max_write_errors:-0}" \
  -v max_timeout="${max_timeout:-0}" \
  -v max_eof="${max_eof:-0}" \
  -v min_classified="${min_classified:-1}" \
  -v class_status="${class_status:-missing}" \
  -v class_aggregation_status="${class_aggregation_status:-missing}" \
  -v networking_status="${networking_status:-missing}" \
  -v networking_packet_error_classification="${networking_packet_error_classification:-missing}" \
  -v networking_packet_error_aggregation="${networking_packet_error_aggregation:-missing}" \
  -v networking_packet_error_alerts="${networking_packet_error_alerts:-missing}" \
  -v observability_status="${observability_status:-missing}" \
  -v observability_error_scan="${observability_error_scan:-dirty}" \
  -v index_alert_status="$index_alert_status" \
  -v index_class_status="$index_class_status" \
  -v metrics_path="$METRICS_PATH" \
  -v alert_summary="$ALERT_SUMMARY" \
  -v class_summary="$class_summary" \
  -v networking_summary="$NETWORKING_SUMMARY" \
  -v observability_summary="$OBSERVABILITY_SUMMARY" \
  -v observability_index="$observability_index" '
  BEGIN {
    status = "pass"
    reason = "ok"
    monitoring_contract = "export_ready"
    metrics_export = "present"

    alert_ok = alert_status == "pass" &&
      alert_guard == "threshold_guarded" &&
      class_status == "pass" &&
      class_aggregation_status == "observed" &&
      alert_log_files + 0 > 0 &&
      classified_events + 0 >= min_classified + 0 &&
      unknown_classes + 0 == 0 &&
      protocol_errors + 0 == 0 &&
      write_errors + 0 == 0

    networking_ok = networking_status == "pass" &&
      networking_packet_error_classification == "unit_guarded" &&
      networking_packet_error_aggregation == "parser_guarded" &&
      networking_packet_error_alerts == "threshold_guarded"

    observability_ok = observability_status == "pass" &&
      observability_error_scan == "clean" &&
      index_alert_status == "present" &&
      index_class_status == "present"

    if (!alert_ok) {
      status = "fail"
      reason = "alert_threshold_not_exportable"
      monitoring_contract = "fail"
    } else if (!networking_ok) {
      status = "fail"
      reason = "networking_packet_error_contract_not_clean"
      monitoring_contract = "fail"
    } else if (!observability_ok) {
      status = "fail"
      reason = "observability_index_missing_packet_error_artifacts"
      monitoring_contract = "fail"
    }

    printf("packet_error_monitoring_contract status=%s reason=%s monitoring_contract=%s metrics_export=%s alert_status=%s alert_guard=%s class_status=%s class_aggregation_status=%s log_files=%d classified_events=%d unknown_classes=%d protocol_errors=%d write_errors=%d timeout=%d eof=%d max_unknown=%d max_protocol_errors=%d max_write_errors=%d max_timeout=%d max_eof=%d min_classified=%d networking_status=%s networking_packet_error_classification=%s networking_packet_error_aggregation=%s networking_packet_error_alerts=%s observability_status=%s observability_error_scan=%s index_alert_status=%s index_class_status=%s metrics=%s alert_summary=%s class_summary=%s networking_summary=%s observability_summary=%s observability_index=%s\n", status, reason, monitoring_contract, metrics_export, alert_status, alert_guard, class_status, class_aggregation_status, alert_log_files + 0, classified_events + 0, unknown_classes + 0, protocol_errors + 0, write_errors + 0, timeout_count + 0, eof_count + 0, max_unknown + 0, max_protocol_errors + 0, max_write_errors + 0, max_timeout + 0, max_eof + 0, min_classified + 0, networking_status, networking_packet_error_classification, networking_packet_error_aggregation, networking_packet_error_alerts, observability_status, observability_error_scan, index_alert_status, index_class_status, metrics_path, alert_summary, class_summary, networking_summary, observability_summary, observability_index)
    if (status != "pass") {
      exit 1
    }
  }
' > "$SUMMARY_PATH" || {
  cat "$SUMMARY_PATH" >&2 || true
  fail "packet error monitoring contract failed"
}

cat "$SUMMARY_PATH"
echo "Packet error monitoring contract artifacts: $OUT_DIR"
