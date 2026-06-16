# Server Session Monitoring Contract

This document defines the local monitoring handoff contract for server session, admission, lifecycle, and bounded resource evidence. It does not add an external monitoring service, change server runtime behavior, change packet framing, change protocol fields, change storage, or expose the server outside loopback.

## Monitoring Contract

The server scalability and connection lifecycle gates already prove bounded local session evidence:

- Multi-client bootstrap and block-edit fanout are live-guarded.
- Repeated six-client fanout/resource evidence is live-guarded.
- Opt-in max-client admission and the current admission matrix are live-guarded.
- Connection lifecycle logs classify connected, rejected, disconnected, packet-error disconnect, EOF, timeout, close-failure, accept-failure, max-active-client, and active-client-field completeness counters.

`scripts/server_session_monitoring_contract_gate.sh` turns that evidence into a release-checkable monitoring contract by requiring:

- `scripts/server_scalability_pass_gate.sh` reports `status=pass`, `scalability_status=repeat_live_guarded`, `resource_profile_status=repeat_live_guarded`, `admission_policy=matrix_live_guarded`, and `disconnect_cleanup_status=lifecycle_summary_guarded`.
- Live two-client, broader six-client, repeated six-client, admission-limit, and admission-matrix summaries are all clean.
- Connection lifecycle evidence reports connected, rejected, and disconnected sessions; zero close failures; zero accept failures; and complete active-client fields.
- Observability indexing reports `status=pass`, `error_scan=clean`, and includes the server scalability and connection lifecycle summaries.

## Session Metrics

The contract records session metrics from current local smoke evidence only. The counters are suitable for CI artifact ingestion or future external monitoring upload, but they are not collected from a long-running production daemon.

Current required session evidence includes:

- Connected, rejected, and disconnected client counts.
- Packet-error, EOF, and timeout disconnect counts.
- Close and accept failure counts.
- Max active and configured client counts observed in server logs.
- Live, broader, repeated, and admission-matrix coverage counts.
- Bounded RSS and CPU samples from the existing multi-client smoke wrappers.

## Metrics Export

The contract gate writes:

```text
logs/server_session_monitoring_contract_current/server-session-monitoring-metrics.txt
```

The file is line-oriented and intentionally simple:

```text
server_session_connected_clients <count>
server_session_rejected_clients <count>
server_session_disconnected_clients <count>
server_session_packet_error_disconnects <count>
server_session_eof_disconnects <count>
server_session_timeout_disconnects <count>
server_session_close_failures <count>
server_session_accept_failures <count>
server_session_max_active_clients <count>
server_session_max_configured_clients <count>
server_session_missing_active_client_fields <count>
server_session_live_detail_clients <count>
server_session_live_resource_samples <count>
server_session_live_resource_rss_kb_max <count>
server_session_live_resource_cpu_pct_max <value>
server_session_broader_live_clients <count>
server_session_broader_live_resource_samples <count>
server_session_broader_live_resource_rss_kb_max <count>
server_session_broader_live_resource_cpu_pct_max <value>
server_session_repeat_smoke_repeats <count>
server_session_repeat_smoke_clients <count>
server_session_repeat_smoke_resource_samples <count>
server_session_repeat_smoke_max_rss_kb <count>
server_session_repeat_smoke_max_cpu_pct <value>
server_session_admission_matrix_limits_checked <count>
server_session_admission_matrix_total_rejected <count>
```

This is a local export contract for future CI or external monitoring ingestion. It is not a network endpoint, daemon, push job, SaaS integration, production retention policy, or release telemetry pipeline.

## Trust Boundary

The contract is local evidence over current smoke summaries and current server logs. It does not prove:

- Internet-facing server safety.
- Authentication, encryption, or abuse detection.
- Sustained production max-client sizing.
- Long-run memory or CPU stability.
- Adaptive overload or backpressure behavior.
- External alert delivery or metrics retention.

Non-loopback server exposure and production monitoring upload still require separate auth, exposure-policy, and operations work.

## Compatibility Rules

- Do not change packet framing or protobuf schema as part of session monitoring work.
- Do not persist connection/session state into world or storage data.
- Do not treat bounded RSS/CPU smoke samples as production capacity sizing.
- Do not treat this metrics file as an adaptive admission, overload, or backpressure policy.
- Do not delete historical logs from this gate.
- Keep summaries and metrics line-oriented for shell/awk consumers.
- Keep this gate side-effect limited to logs under its output directory and the server scalability output directory.

## Gate

Use:

```sh
sh scripts/server_session_monitoring_contract_gate.sh logs/server_session_monitoring_contract_current
```

The expected current result is `status=pass`, `monitoring_contract=export_ready`, `metrics_export=present`, `scalability_guard=repeat_live_guarded`, `resource_profile_status=repeat_live_guarded`, `admission_policy=matrix_live_guarded`, `disconnect_cleanup_status=lifecycle_summary_guarded`, `lifecycle_status=pass`, `connected_clients=9`, `rejected_clients=1`, `disconnected_clients=9`, `close_failures=0`, `accept_failures=0`, `missing_active_client_fields=0`, `index_scalability_status=present`, and `index_lifecycle_status=present`.
