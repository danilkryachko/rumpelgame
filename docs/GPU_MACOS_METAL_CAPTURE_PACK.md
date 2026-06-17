# GPU macOS Metal Capture Pack

Date: 2026-06-17

Scope: required summary-only handoff gate for Week 71 cross-platform profiling work. The macOS Metal capture pack validates that the local world-interaction checkpoint is clean, then emits a concrete Xcode/Metal capture manifest and checklist. It does not run Xcode, Instruments, `gpucapture`, `gpudebug`, or `metalperftrace` by itself, and it is not profiler evidence.

## Command

Use:

```sh
sh scripts/gpu_macos_metal_capture_pack.sh logs/gpu_macos_metal_capture_pack_current
```

The script writes:

- `gpu-macos-metal-capture-pack-summary.txt`
- `gpu-macos-metal-capture-manifest.txt`
- `gpu-macos-metal-capture-checklist.txt`

## Inputs

Required:

- `logs/gpu_world_interaction_checkpoint_current/gpu-world-interaction-checkpoint-summary.txt`
- `docs/GPU_MACOS_METAL_CAPTURE_PACK.md`
- `docs/GPU_PROFILING.md`

Optional:

- `logs/gpu_shader_profiler_capture_pack_current/shader-profiler-capture-pack.txt`
- `logs/external_profiling_campaign_current/external-profiling-campaign-summary.txt`

The gate fails unless the world-interaction checkpoint reports:

- `status=pass`
- `checkpoint_status=local_complete_external_pending`
- `local_world_interaction_status=pass`
- `rollout_status=defer_defaults`
- `gpu_upload_fail=0`
- `ground_misses=0`
- `default_runtime_change_allowed=0`
- `visible_quality_change_allowed=0`
- `scheduler_change_allowed=0`
- `external_profile_status=pending_external_profiler`
- `requires_external_profiler_before_default=1`
- `requires_mac_windows_validation=1`

## Capture Rows

The generated manifest prepares four macOS Metal rows:

- `world_interaction_checkpoint`: Xcode Metal frame capture for GPU pass time, draw count, encoder stage time, buffer updates, hardware counters, and counter evidence.
- `metal_system_trace_world_interaction`: Metal System Trace for CPU/GPU overlap, command buffer timeline, memory pressure, driver waits, and counter evidence.
- `world_upload_pressure`: Xcode Metal memory/resource report for buffer residency, resource lifetime, upload bytes, staging cost, and counter evidence.
- `shader_hot_path`: Xcode Metal shader cost capture for vertex stage time, fragment stage time, shader cost, texture sampling, and counter evidence.

These rows are pending handoff state. They become evidence only after an external capture records non-placeholder artifacts and captured rows through a future results validator.

## External Tooling Context

Apple documents the Metal debugger, Metal System Trace in Instruments, and command-line tools such as `gpucapture`, `gpudebug`, and `metalperftrace` for capturing, debugging, profiling, and summarizing Metal workloads:

- [Metal developer tools](https://developer.apple.com/metal/tools/)
- [Capturing a Metal workload in Xcode](https://developer.apple.com/documentation/xcode/capturing-a-metal-workload-in-xcode)
- [Optimizing GPU performance](https://developer.apple.com/documentation/xcode/optimizing-gpu-performance)
- [MTLCaptureManager](https://developer.apple.com/documentation/metal/mtlcapturemanager)

The project keeps local FPS and Godot GPU timestamps report-only because current local macOS/Metal timestamp samples still report `0.0us`.

## Policy

- A generated capture pack is not profiler evidence.
- Do not enable default runtime changes from this pack alone.
- Do not reduce draw distance, lighting, shadows, texture quality, terrain quality, or other visible quality settings to make a capture pass.
- Keep Windows/Vulkan/Direct3D validation as a separate blocker before default-on decisions.
- Record machine context with captured rows: Mac model, chip/GPU, macOS version, Xcode version, Godot version, backend, display refresh, and driver notes.
