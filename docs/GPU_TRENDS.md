# GPU Trends

Use this file for durable GPU optimization checkpoints. Keep entries short and factual; link the detailed artifact directory instead of copying long logs.

## Reading The Table

- `visual_fps` is report-only when the run is display/driver paced.
- `gpu_time` is report-only on the current macOS/Metal path because Godot timestamp samples report `0.0us`.
- Prefer `terrain_queue_max_ms`, `process_wall_p95_ms`, `gpu_compositor_submit_max_ms`, `gpu_upload_fail`, draw counts, and external GPU profiler captures for decisions.

## 2026-06-12

| Commit | Slice | Artifact | Key Result | Caveat |
| --- | --- | --- | --- | --- |
| `post-d270c2a` | GPU upload frame telemetry | `logs/gpu_terrain_queue_upload_frame` | release movement passed with `terrain_queue_gpu_uploads=1/0.84/1`, `terrain_queue_gpu_upload_kb=0.0/0.0/1.5`, `gpu_upload_ms=0.014/0.005/0.136`, `gpu_upload_fail=0`, `gpu_fragmentation_pct=0.0`, `smoke_err=0`, `terrain_queue_max_ms=3.660`, and `gpu_compositor_submit_max_ms=0.169` | visual FPS was display-paced at 60 Hz; default server batch/radius produced `gpu_draws=246`, so repeat under heavy workload before drawing upload-budget conclusions |

## 2026-06-11

| Commit | Slice | Artifact | Key Result | Caveat |
| --- | --- | --- | --- | --- |
| `2635006` | GPU terrain back-face culling | `logs/gpu_terrain_cull_back_smoke` | radius-16 movement passed with `gpu_draws=1582`, `gpu_faces=2244`, `gpu_upload_fail=0`, `smoke_err=0` | fill-stress comparison was display-limited at 60 FPS in that session |
| `c5dad7f` | GPU roadmap/profiling docs | `docs/GPU_ROADMAP.md`, `docs/GPU_PROFILING.md` | 120 sequential GPU iterations and trusted/untrusted metric definitions | docs only |
| `a79fe71` | Unified GPU report | `logs/gpu-terrain-report.txt` | aggregate report reads existing movement/fill/workload/baseline summaries | aggregates historical logs, not only newest runs |
| `c24cb98` | Rasterization state markers | `logs/gpu_terrain_cull_summary` | marker and movement summary report `gpu_cull=back gpu_front_face=clockwise`, `gpu_upload_fail=0`, `fps_p05=144.0` | same run reported very large `post_draw_wait_ms`, so capture timing needs watching |
| `50be49c` | Fill-stress report-only repeats | `/tmp/rumpel_fill_report_only_fail` | report-only failure path writes `status=failed` and exits 0 | normal repeat=1 validation can still miss screenshot capture |
| `8ad45ad` | Fill-stress visual correctness fields | `scripts/gpu_terrain_fill_stress.sh` | pass lines include `status`, `smoke_err`, `terrain_samples`, and `terrain_color_buckets` | normal pass-line format was not revalidated by a successful fill-stress capture due capture-window instability |
| `74518b8` | Fragmentation telemetry | unit tests | derives `gpu_fragmented_free_faces` and `gpu_fragmentation_pct` without allocator behavior changes | existing logs show `n/a` until a fresh marker is captured |
| `82532a5` | Metric origins in GPU report | `logs/gpu-terrain-report.txt` | report points aggregate spikes to exact summary/marker files | selected summaries now use file mtime after `493c8e6` |

## Next Trend Entry

Record the next entry after a fresh successful heavy or fill-stress run that includes:

- `gpu_cull` and `gpu_front_face`.
- `gpu_fragmented_free_faces` and `gpu_fragmentation_pct`.
- `terrain_queue_gpu_uploads` and `terrain_queue_gpu_upload_kb`.
- fill-stress visual correctness fields on a pass line, if the run is fill stress.
- the artifact path and exact env vars.
