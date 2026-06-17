# GPU Windows Capture Results

Date: 2026-06-17

Scope: validation for real Windows PIX, RenderDoc, or vendor profiler rows captured from the manifest produced by `scripts/gpu_windows_capture_pack.sh`. The validator is sidecar-based: it does not parse binary `.wpix`, `.rdc`, or vendor capture files. Instead, the Windows machine records one text row per capture artifact with machine context, driver/backend context, profiler artifact identity, counters, and numeric timings.

## Command

Use:

```sh
sh scripts/gpu_windows_capture_results_check.sh \
  logs/gpu_windows_capture_pack_current/gpu-windows-capture-manifest.txt \
  logs/gpu_windows_capture_pack_current/gpu-windows-capture-results.txt \
  logs/gpu_windows_capture_pack_current/gpu-windows-capture-results-summary.txt
```

For partial handoff validation while captures are still being collected:

```sh
RUMPELMC_WINDOWS_CAPTURE_RESULTS_ALLOW_PARTIAL=1 \
sh scripts/gpu_windows_capture_results_check.sh \
  logs/gpu_windows_capture_pack_current/gpu-windows-capture-manifest.txt \
  logs/gpu_windows_capture_pack_current/gpu-windows-capture-results.txt \
  logs/gpu_windows_capture_pack_current/gpu-windows-capture-results-summary.txt
```

Partial validation lists missing planned rows and is not full cross-platform profiler evidence.

## Common Row Fields

Each captured row must start with `external_profile_status=captured` and include:

- `row`
- `priority`
- `platform=windows`
- `backend`
- `profiler_tool`
- `profiler_artifact`
- `machine_context`
- `windows_version`
- `gpu_vendor`
- `gpu_model`
- `driver_version`
- `godot_version`
- `rendering_driver`
- `display_refresh_hz`
- `gpu_pass_ms`
- `draw_count`
- `counter_evidence`

Placeholder values such as `pending`, `TODO`, `unknown`, `n/a`, `missing`, `placeholder`, or `external_*_required` are rejected.

## Row-Specific Fields

`pix_gpu_world_interaction` additionally requires:

- `event_timing_ms`
- `resource_state_events`
- `pipeline_state_evidence`

`pix_timing_world_interaction` additionally requires:

- `gpu_timing_ms`
- `cpu_gpu_overlap_ms`
- `memory_allocation_mb`
- `timing_capture_span_ms`

`renderdoc_frame_world_interaction` additionally requires:

- `draw_event_count`
- `pipeline_state_evidence`
- `texture_sampling_evidence`
- `buffer_update_events`
- `resource_lifetime_events`

`windows_shader_hot_path` additionally requires:

- `shader_pass_ms`
- `vertex_stage_ms`
- `fragment_stage_ms`
- `shader_cost_evidence`
- `texture_sampling_evidence`

## Policy

- A pending capture pack is not profiler evidence.
- Synthetic rows are test fixtures only.
- Real rows must point to recorded external artifacts and counter evidence.
- Windows captured rows alone do not permit default runtime changes; macOS peer validation and quality gates still apply.
- Do not reduce draw distance, lighting, shadows, texture quality, terrain quality, or other visible quality settings to make a capture pass.
