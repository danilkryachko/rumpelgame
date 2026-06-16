# GPU Terrain Upload Budgeting

Date: 2026-06-16

Scope: Phase 5 upload pipeline budgeting. This introduces a summary-only per-frame GPU terrain upload budget over current movement and dirty-update evidence. It does not change upload capacity, allocator policy, draw distance, lighting, shadows, texture quality, protocol, storage, world generation, chunk serialization, or visible quality.

## Current Decision

Use a conservative budget gate before changing GPU upload pooling, retry, allocator, or scheduling behavior. Current movement and in-place dirty-update evidence stays within the initial budget, so this slice only records the budget and blocks future regressions.

## Budget Gate

Use:

```sh
sh scripts/gpu_terrain_upload_budget.sh logs/gpu_terrain_upload_budget_current
```

The gate consumes:

- `logs/gpu_upload_lane_split_movement_current/movement-stress-summary.txt`
- `logs/gpu_upload_lane_split_movement_current/gpu-terrain-movement-stress.png.txt`
- `logs/gpu_upload_lane_split_in_place_current/gpu-in-place-upload-summary.txt`

Default budgets:

- total movement uploads per frame: `1`;
- total movement upload payload: `2.0 KiB`;
- new-slot uploads per frame: `1`;
- replacement-slot uploads per frame: `1`;
- new-slot upload payload: `2.0 KiB`;
- replacement-slot upload payload: `2.0 KiB`;
- upload failures, capacity failures, and fragmentation failures: `0`.

Set the `RUMPELMC_GPU_UPLOAD_BUDGET_*` environment variables in `scripts/gpu_terrain_upload_budget.sh` only for explicit experiments or negative validation. Tightening a budget should be supported by fresh movement, dirty-update, and high-resident evidence.

## Evidence

Fresh local evidence:

- Summary: `logs/gpu_terrain_upload_budget_current/gpu-terrain-upload-budget-summary.txt`
- Status: `pass`
- Reason: `within_budget`
- Movement total upload max: `1` of `1`
- Movement upload payload max: `0.2 KiB` of `2.0 KiB`
- Movement new-slot / replacement-slot upload max: `1 / 1`
- In-place new-slot / replacement-slot upload max: `1 / 1`
- Movement and in-place upload failures: `0`

Negative validation:

```sh
RUMPELMC_GPU_UPLOAD_BUDGET_MAX_UPLOAD_KB_PER_FRAME=0.05 \
sh scripts/gpu_terrain_upload_budget.sh logs/gpu_terrain_upload_budget_negative
```

The expected result is failure with `reason=movement_upload_kb_budget`.

## Guardrails

- Treat this as a governance gate, not runtime throttling.
- Do not reduce draw distance, lighting, shadows, texture quality, or visible quality to pass this gate.
- Do not use a passing budget alone to justify upload pool, allocator, or repack activation.
- Keep new-slot and replacement-slot lanes separate when evaluating world-load pressure versus dirty-update pressure.
- Rebaseline deliberately when representative larger worlds, transparent terrain, native shadows, or mass-edit workloads create a stable higher upload envelope.

## External References

- Godot `RenderingDevice` is a low-level abstraction over Vulkan/Direct3D 12/Metal/WebGPU-style APIs, and `buffer_update` has explicit buffer range and active draw/compute list constraints: <https://docs.godotengine.org/en/stable/classes/class_renderingdevice.html>
- Vulkan synchronization examples document CPU-to-GPU upload paths using explicit transfer dependencies and staging resources: <https://docs.vulkan.org/guide/latest/synchronization_examples.html>
- Apple Metal resource guidance separates shared/managed/private storage models on macOS and recommends avoiding per-frame buffer creation for dynamic data through reusable buffering: <https://developer.apple.com/library/archive/documentation/3DDrawing/Conceptual/MTLBestPracticesGuide/ResourceOptions.html> and <https://developer.apple.com/library/archive/documentation/3DDrawing/Conceptual/MTLBestPracticesGuide/TripleBuffering.html>
