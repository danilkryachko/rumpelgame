# GPU Windows RenderDoc Or PIX Capture Pack

Date: 2026-06-17

Scope: required summary-only handoff gate for Week 72 cross-platform profiling work. The Windows RenderDoc or PIX capture pack validates that the local world-interaction checkpoint and macOS Metal capture pack are clean, then emits a concrete Windows capture manifest and checklist for PIX GPU captures, PIX timing captures, RenderDoc frame captures, and shader-cost follow-up. It does not run PIX, RenderDoc, `pixtool.exe`, a Windows Godot build, or vendor profilers by itself, and it is not profiler evidence.

## Command

Use:

```sh
sh scripts/gpu_windows_capture_pack.sh logs/gpu_windows_capture_pack_current
```

The script writes:

- `gpu-windows-capture-pack-summary.txt`
- `gpu-windows-capture-manifest.txt`
- `gpu-windows-capture-checklist.txt`

## Inputs

Required:

- `logs/gpu_world_interaction_checkpoint_current/gpu-world-interaction-checkpoint-summary.txt`
- `logs/gpu_macos_metal_capture_pack_current/gpu-macos-metal-capture-pack-summary.txt`
- `docs/GPU_WINDOWS_CAPTURE_PACK.md`
- `docs/GPU_PROFILING.md`

Optional:

- `logs/gpu_shader_profiler_capture_pack_current/shader-profiler-capture-pack.txt`

The gate fails unless the world-interaction checkpoint and macOS peer pack both pass while keeping default rollout blocked.

## Capture Rows

The generated manifest prepares four Windows rows:

- `pix_gpu_world_interaction`: PIX GPU capture for GPU pass time, draw count, event timing, pipeline state, resource states, and counter evidence.
- `pix_timing_world_interaction`: PIX timing capture for CPU/GPU overlap, queue latency, GPU timings, memory allocations, and counter evidence.
- `renderdoc_frame_world_interaction`: RenderDoc frame capture for draw event count, pipeline state, texture atlas sampling, buffer update events, resource lifetime, and counter evidence.
- `windows_shader_hot_path`: PIX, RenderDoc, or vendor shader capture for vertex stage time, fragment stage time, shader cost, occupancy or invocations, texture sampling, and counter evidence.

These rows are pending handoff state. They become evidence only after an external Windows machine records non-placeholder artifacts and captured rows through a future results validator.

## External Tooling Context

Microsoft documents PIX GPU captures as frame captures for Direct3D 12 API calls with replay, timing data, pipeline/resource state inspection, and event counters. PIX timing captures record CPU/GPU work over time, including GPU timings and memory allocation data. PIX GPU captures can also collect hardware counters on AMD, Intel, and supported NVIDIA hardware:

- [PIX GPU captures](https://learn.microsoft.com/en-us/windows/win32/direct3dtools/pix/articles/gpu-captures/pix-gpu-captures)
- [PIX documentation index](https://devblogs.microsoft.com/pix/documentation/)
- [PIX timing captures](https://devblogs.microsoft.com/pix/timing-captures-new/)
- [PIX hardware counters](https://devblogs.microsoft.com/pix/hardware-counters-in-gpu-captures/)

RenderDoc is the Windows cross-check path when the active backend is Vulkan, D3D11, or D3D12. Its quick-start workflow launches the target application, captures a frame with the overlay capture key, and inspects events, textures, pipeline state, and resources:

- [RenderDoc quick start](https://raw.githubusercontent.com/baldurk/renderdoc/v1.x/docs/getting_started/quick_start.rst)
- [RenderDoc repository and API support matrix](https://github.com/baldurk/renderdoc)

## Policy

- A generated capture pack is not profiler evidence.
- Do not enable default runtime changes from this pack alone.
- Do not reduce draw distance, lighting, shadows, texture quality, terrain quality, or other visible quality settings to make a capture pass.
- Keep macOS peer evidence and Windows driver/backend context together before default-on decisions.
- Record machine context with captured rows: Windows version, GPU vendor/model, driver version, Godot version, rendering backend/driver, PIX version, RenderDoc version, display refresh, and hybrid-GPU mode.
