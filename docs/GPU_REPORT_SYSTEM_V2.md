# GPU Report System V2

Date: 2026-06-15

Scope: block 23 of the world streaming architecture plan. This adds a V2 report wrapper that separates scoped metrics, historical aggregate metrics, fail gates, and warning-only local signals without removing the existing `gpu_terrain_report.sh`.

## Current Decision

Keep the existing GPU terrain report as the historical aggregate source, but do not let consumers confuse aggregate maxima with one fresh scoped run. Use `scripts/gpu_terrain_report_v2.sh` when a task needs explicit evidence classes.

## Command

```sh
sh scripts/gpu_terrain_report_v2.sh logs/gpu_terrain_upload_pressure_smoke logs/gpu_terrain_report_v2_current
```

The wrapper writes:

- `gpu-terrain-report-v2-summary.txt`
- `gpu-terrain-report-v2.txt`
- `gpu-terrain-report-v2-legacy.txt`

Use the freshness gate when the long-running ignored aggregate report must be current for handoff or observability indexing:

```sh
sh scripts/gpu_terrain_report_freshness_gate.sh logs/gpu_terrain_report_freshness_current
```

The freshness gate refreshes `logs/gpu-terrain-report.txt` by default, then verifies the report commit matches `HEAD`, the aggregate error scan is clean, aggregate upload failures are zero, and key aggregate workload metrics are present.

## Evidence Classes

- Fresh scoped metrics: one selected summary file, defaulting to `gpu-upload-pressure-summary.txt` in the input log dir when present.
- Fail gates: resource lifecycle audit status, memory budget status, and legacy report error scan.
- Historical aggregate metrics: values extracted from `gpu_terrain_report.sh`, explicitly labeled as aggregate over the whole log directory.
- Warning-only local signals: local visual FPS/frame timing and macOS/Metal GPU timestamp fields that remain untrusted without external profiler evidence.

## Evidence

Fresh local evidence:

- Summary: `logs/gpu_terrain_report_v2_current/gpu-terrain-report-v2-summary.txt`
- Report: `logs/gpu_terrain_report_v2_current/gpu-terrain-report-v2.txt`
- Status: `pass`
- Scoped status: `pass`
- Resource lifecycle status: `pass`
- Memory budget status: `pass`
- Legacy error scan: `clean`
- Historical `gpu_draws`: `1335`
- Historical `gpu_effective_draws`: `21216`
- Historical `gpu_faces`: `1469`
- Historical draw-command occupancy: `16.296%`
- Historical upload failures: `0`
- Historical fragmentation: `0.0%`
- Warning-only local `frame_p95_ms`: `8.368`
- Warning-only local `fps_p05`: `120`
- Warning-only local `gpu_compositor_gpu_max_us`: `0.0`

## Guardrails

- Do not delete or replace `gpu_terrain_report.sh`; V2 is a classifier wrapper.
- Do not cite historical aggregate maxima as scoped run evidence.
- Do not use warning-only local FPS/GPU timestamp fields as pass/fail gates unless external profiler evidence validates them.
- Fail gates should stay small and explicit. Add a new gate summary first, then teach V2 to consume it.
- Keep `gpu_terrain_report_freshness_gate.sh` focused on freshness and aggregate safety. Do not use it as scoped performance evidence.
