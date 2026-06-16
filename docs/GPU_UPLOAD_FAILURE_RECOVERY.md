# GPU Upload Failure Recovery

Date: 2026-06-16

Scope: Phase 6 upload robustness. This records the current recovery contract when a GPU terrain upload is requested but no GPU slot is confirmed. It does not change upload capacity, allocator policy, retry/backoff policy, draw distance, lighting, shadows, texture quality, protocol, storage, world generation, chunk serialization, or visible quality.

## Current Contract

GPU terrain upload recovery is fallback-first:

- A subchunk is treated as GPU-backed only after `TerrainGpuUploadState::Uploaded`.
- `TerrainGpuUploadState::Failed` never enables the GPU proxy path.
- If the GPU-visible renderer is active but a specific subchunk has no confirmed GPU slot, mesh build planning must choose `FullArrayMesh`.
- Proxy-refresh reuse must choose `BuildMesh` while `existing_gpu_slot=false`; it may remove the CPU node only after `existing_gpu_slot=true` and no CPU proxy role is needed.
- This preserves visible CPU ArrayMesh terrain for per-subchunk upload failures.

The current retry/backoff telemetry remains separate: `gpu_upload_retry_policy=none` and retry/backoff counters stay `0`.

## Evidence

Targeted unit checks:

```sh
cargo test --manifest-path client/rust_ext/Cargo.toml gpu_upload_failure_recovery_keeps_cpu_fallback_until_slot_exists
cargo test --manifest-path client/rust_ext/Cargo.toml terrain_mesh_build_plan_preserves_gpu_proxy_and_fallback_paths
```

Fresh 2026-06-16 results:

- `gpu_upload_failure_recovery_keeps_cpu_fallback_until_slot_exists`: passed.
- `terrain_mesh_build_plan_preserves_gpu_proxy_and_fallback_paths`: passed.
- The broader retry/backoff runtime evidence in `logs/gpu_upload_retry_backoff_movement_current`, `logs/gpu_upload_retry_backoff_in_place_current`, and `logs/gpu_upload_retry_backoff_budget_current` still reports zero upload failures and retry/backoff policy `none/0`.

## Guardrails

- Do not remove CPU ArrayMesh fallback based only on global GPU-visible state; the per-subchunk GPU slot must be confirmed.
- Do not let proxy-refresh jobs remove CPU nodes when a subchunk lacks a GPU slot.
- Do not hide upload failure recovery inside retry loops. A future retry policy must still preserve visual fallback while retries are pending or exhausted.
- Validate future failure injection with visual fallback, shadow fallback, and collision fallback evidence before changing this contract.
