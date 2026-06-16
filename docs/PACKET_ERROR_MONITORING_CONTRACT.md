# Packet Error Monitoring Contract

This document defines the local production-monitoring handoff contract for classified packet errors. It does not add an external monitoring service, change server runtime behavior, change packet framing, change protocol fields, or expose the server outside loopback.

## Monitoring Contract

The server already emits stable `packet_error_class` labels for packet/framing/write failures. The networking robustness gate proves those labels are unit-guarded, parser-aggregated, and threshold-checked over current live smoke logs.

`scripts/packet_error_monitoring_contract_gate.sh` turns that evidence into a release-checkable monitoring contract by requiring:

- `scripts/packet_error_alert_threshold_gate.sh` reports `status=pass` and `alert_status=threshold_guarded`.
- Unknown classes, protocol-error classes, and write/internal-error classes remain at `0`.
- Classified event count is at or above the configured minimum.
- Networking robustness reports `packet_error_classification=unit_guarded`, `packet_error_aggregation=parser_guarded`, and `packet_error_alerts=threshold_guarded`.
- Observability indexing reports `status=pass`, `error_scan=clean`, and includes the packet-error alert and class-summary artifacts.

## Metrics Export

The contract gate writes:

```text
logs/packet_error_monitoring_contract_current/packet-error-monitoring-metrics.txt
```

The file is line-oriented and intentionally simple:

```text
packet_error_classified_events <count>
packet_error_unknown_classes <count>
packet_error_protocol_errors <count>
packet_error_write_errors <count>
packet_error_timeout_events <count>
packet_error_eof_events <count>
packet_error_log_files <count>
packet_error_threshold_max_unknown <count>
packet_error_threshold_max_protocol_errors <count>
packet_error_threshold_max_write_errors <count>
packet_error_threshold_max_timeout <count>
packet_error_threshold_max_eof <count>
packet_error_threshold_min_classified <count>
```

This is a local export contract for future CI or external monitoring ingestion. It is not a network endpoint, daemon, push job, SaaS integration, or release telemetry pipeline.

## Threshold Policy

Current default thresholds remain owned by `scripts/packet_error_alert_threshold_gate.sh`:

- Unknown classes: `0`
- Protocol errors: `0`
- Write/internal errors: `0`
- Timeout events: bounded by the current slow-reader smoke and matrix evidence
- EOF events: high default threshold, because clean client shutdowns currently log EOF disconnects

Changing thresholds requires updating the alert threshold gate, this document, and the release-chain evidence that consumes the monitoring contract.

## Trust Boundary

The contract is local evidence over current smoke logs. It does not prove:

- Authentication or encryption.
- Abuse detection.
- Internet-facing server safety.
- Long-run production traffic health.
- External alert delivery.

Non-loopback server exposure still requires a separate auth/encryption/exposure-policy review.

## Compatibility Rules

- Do not rename `packet_error_class` labels without updating parser tests, summaries, and this monitoring contract.
- Do not treat unknown classes as acceptable in release evidence.
- Do not change packet framing or protobuf schema as part of monitoring work.
- Do not delete historical logs from this gate.
- Keep summaries and metrics line-oriented for shell/awk consumers.
- Keep this gate side-effect limited to logs under its output directory and the packet-error alert-threshold output directory.

## Gate

Use:

```sh
sh scripts/packet_error_monitoring_contract_gate.sh logs/packet_error_monitoring_contract_current
```

The expected current result is `status=pass`, `monitoring_contract=export_ready`, `metrics_export=present`, `alert_guard=threshold_guarded`, `unknown_classes=0`, `protocol_errors=0`, `write_errors=0`, `networking_packet_error_alerts=threshold_guarded`, `observability_error_scan=clean`, `index_alert_status=present`, and `index_class_status=present`.
