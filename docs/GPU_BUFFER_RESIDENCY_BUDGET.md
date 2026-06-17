# GPU Buffer Residency Budget

Date: 2026-06-16

Scope: summary-only GPU terrain buffer residency budget over current world-loading evidence. This gate does not change rendering behavior, draw distance, camera far plane, lighting, shadows, texture quality, visible quality, protocol, storage, world generation, chunk serialization, allocator policy, repack policy, or eviction policy.

## Command

Use:

```sh
sh scripts/gpu_buffer_residency_budget.sh logs/gpu_buffer_residency_budget_current
```

The script writes `gpu-buffer-residency-budget-summary.txt`.

## Inputs

Required summary inputs:

- mass chunk-load gate: resident subchunks/draws/faces, draw-command capacity/headroom, queue/process/submit, upload failures
- upload stage-pool load-scaling gate: high resident-set stage-pool pressure and reuse count
- grouped draw gate: logical versus submitted draw records and grouped saved records
- cutout pressure gate: cutout/leaf pressure, uploads, and default-runtime-change guard

Optional allocator input:

- memory budget gate: resource lifecycle status, fragmentation, free-range count, and upload-failure counters

When the memory budget summary is missing, this gate can still pass the current summary budget, but it emits `residency_proof_status=partial`, `allocator_evidence_status=missing_optional`, and `requires_allocator_free_range_evidence_before_default=1`. Set `RUMPELMC_GPU_BUFFER_RESIDENCY_REQUIRE_ALLOCATOR_EVIDENCE=1` when allocator/free-range evidence must be present.

## Current Evidence

Fresh local evidence:

- `logs/gpu_buffer_residency_budget_current/gpu-buffer-residency-budget-summary.txt`

The current summary passed with:

- `residency_pressure_class=high`
- `residency_proof_status=partial`
- `configured_buffer_bytes=67239936` under `max_configured_buffer_bytes=70254592`
- `configured_buffer_budget_pct=95.709`
- `active_face_bytes=100672` under `max_active_face_bytes=4194304`
- `active_face_budget_pct=2.400`
- resident subchunks/logical draw records/submitted draw records: `2482` / `2482` / `2482`
- resident faces: `6292`
- draw-command occupancy/headroom: `30.298%` / `91360` bytes
- queue/process/submit: `2.214ms` / `0.059ms` / `5.677ms`
- upload failures and ground misses: `0`
- stage-pool reuses: `3128`
- grouped saved records: `2174`
- cutout transparent subchunks/faces/uploads: `265` / `1590` / `265`

The high pressure class is caused by configured terrain buffers being close to the current soft cap, not by active face bytes. This blocks any default repack, eviction, or residency policy change until allocator/free-range evidence and external profiler evidence exist.

## Budget Policy

The gate follows a `classify_budget_stream` policy:

- classify current residency pressure from configured buffer bytes, active face bytes, resident subchunks, logical draw records, submitted draw records, faces, and draw-command occupancy
- budget those dimensions against explicit soft caps before changing runtime behavior
- stream future changes through external profiler validation rather than trusting local FPS or Godot GPU timestamps alone

The current local macOS/Metal run keeps `local_fps_status=report_only` and `godot_gpu_timestamp_status=report_only`. It also emits `external_profile_status=pending_external_profiler`, `requires_external_profiler_before_default=1`, and `requires_mac_windows_validation=1`.

## External Context

- Microsoft D3D12 memory guidance recommends classifying resources, budgeting residency, and streaming based on adapter budget. See [D3D12 memory management strategies](https://learn.microsoft.com/en-us/windows/win32/direct3d12/memory-management-strategies) and [D3D12 residency](https://learn.microsoft.com/en-us/windows/win32/direct3d12/residency).
- Vulkan exposes heap budget and heap usage through `VK_EXT_memory_budget`; see [VK_EXT_memory_budget](https://docs.vulkan.org/refpages/latest/refpages/source/VK_EXT_memory_budget.html).
- Godot `RenderingDevice.buffer_update` must be used outside active draw/compute lists; see [RenderingDevice.buffer_update](https://docs.godotengine.org/en/stable/classes/class_renderingdevice.html).
- Apple Metal resource option and buffering guidance should be used for platform validation before changing default resource residency behavior; see [Metal resource options](https://developer.apple.com/library/archive/documentation/3DDrawing/Conceptual/MTLBestPracticesGuide/ResourceOptions.html) and [triple buffering](https://developer.apple.com/library/archive/documentation/3DDrawing/Conceptual/MTLBestPracticesGuide/TripleBuffering.html).
