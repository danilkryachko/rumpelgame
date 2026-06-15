# Performance Baseline Governance

Date: 2026-06-15

Scope: block 24 of the world streaming architecture plan. This defines accepted baseline files, compare-to-baseline flow, threshold policy, and the update process for GPU/world-streaming performance evidence.

## Current Baseline

Accepted baseline:

- `docs/performance_baselines/gpu_terrain_world_streaming.baseline`
- Baseline id: `gpu_terrain_world_streaming_20260615`
- Source summary: `logs/gpu_terrain_report_v2_current/gpu-terrain-report-v2-summary.txt`

The baseline is intentionally based on the classified V2 report, not raw local FPS. Trusted gates are scoped/fail statuses, upload failures, fragmentation, draw-command occupancy, and minimum pressure coverage. Local frame/FPS/GPU timestamp values are warning-only.

## Compare Command

```sh
sh scripts/performance_baseline_governance.sh
```

The default command compares:

- current summary: `logs/gpu_terrain_report_v2_current/gpu-terrain-report-v2-summary.txt`
- accepted baseline: `docs/performance_baselines/gpu_terrain_world_streaming.baseline`
- output: `logs/performance_baseline_governance_current/performance-baseline-governance-summary.txt`

## Threshold Policy

Fail gates:

- V2 report status must match the baseline requirement.
- Scoped status, resource lifecycle status, memory budget status, and legacy error scan must match the accepted baseline.
- Historical effective draw coverage must stay above the baseline minimum.
- Historical upload failures must stay at or below the accepted maximum.
- Historical fragmentation must stay at or below the accepted maximum.
- Historical draw-command occupancy must stay at or below the accepted maximum.

Warning-only gates:

- `warning_frame_p95_ms`
- `warning_gpu_compositor_gpu_max_us`

These warning-only signals may set `warning_status=warn`, but they do not fail the baseline governance check because local macOS/Metal FPS and GPU timestamps remain untrusted without external profiler evidence.

## Evidence

Fresh local evidence:

- Summary: `logs/performance_baseline_governance_current/performance-baseline-governance-summary.txt`
- Status: `pass`
- Reason: `within_baseline`
- Warning status: `ok`
- Baseline id: `gpu_terrain_world_streaming_20260615`
- Historical effective draws: `21216` with minimum `20000`
- Historical upload failures: `0`
- Historical fragmentation: `0.0%` with maximum `1.0%`
- Historical draw-command occupancy: `16.296%` with maximum `75.0%`
- Warning local frame p95: `8.368ms` with warning maximum `20.0ms`
- Warning local GPU timestamp max: `0.0us`

## Update Process

1. Capture or regenerate the relevant evidence artifacts.
2. Generate a V2 report with `scripts/gpu_terrain_report_v2.sh`.
3. Run `scripts/performance_baseline_governance.sh` against the existing accepted baseline.
4. If the result fails because coverage increased or a trusted threshold needs to change, document why the new threshold is acceptable.
5. Update the baseline file in `docs/performance_baselines/` with a new `baseline_id`, `accepted_date`, source summary, and threshold values.
6. Re-run governance and record the new summary path in docs.

Do not update accepted baselines to hide regressions. Increases in upload failures, fragmentation, error scans, or failed lifecycle/memory gates need a fix or an explicit design decision before the baseline changes.
