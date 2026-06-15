# GPU Repack Activation Preflight

Date: 2026-06-15

This note records the current activation decision for GPU terrain buffer repack.

## Decision

Active repack remains disabled.

Current evidence does not justify swapping active RenderingDevice buffers, render bindings, indirect buffers, slot maps, or allocator state:

- Upload-pressure evidence is clean.
- Load-scaling evidence is clean.
- Fragmentation pressure is `0.0%`.
- There are no upload capacity or fragmented allocation failures to recover from.

The safe local action for Block 19 is therefore a preflight gate, not active renderer mutation.

## Preflight

The preflight is:

```sh
/bin/sh scripts/gpu_repack_activation_preflight.sh logs/gpu_repack_activation_preflight_current
```

It reads the current upload-pressure and load-scaling summaries and writes `gpu-repack-activation-preflight-summary.txt`.

Fresh check:

- `logs/gpu_repack_activation_preflight_current/gpu-repack-activation-preflight-summary.txt` reported `status=deferred`, `active_repack_allowed=0`, `reason=no_fragmentation_pressure`, `gpu_upload_fail=0`, `gpu_upload_fail_capacity=0`, `gpu_upload_fail_fragmented=0`, `max_gpu_fragmentation_pct=0.0`, `max_gpu_effective_draws=21216`, and radius-16 load evidence `2482` draws/subchunks with `3296` faces.
