# GPU Repack Soak And Rollback

Date: 2026-06-15

This note records the current soak/rollback gate for GPU terrain buffer repack.

## Decision

Active repack soak is deferred because active repack is not currently allowed by preflight.

The soak/rollback gate is:

```sh
/bin/sh scripts/gpu_repack_soak_rollback_gate.sh logs/gpu_repack_soak_rollback_gate_current
```

It reads the activation preflight summary and refuses to imply active soak coverage when `active_repack_allowed=0`.

Fresh check:

- `logs/gpu_repack_soak_rollback_gate_current/gpu-repack-soak-rollback-summary.txt` reported `status=deferred`, `active_soak_run=0`, `rollback_smoke_required=0`, `reason=active_repack_not_allowed`, `preflight_status=deferred`, `preflight_reason=no_fragmentation_pressure`, and `max_gpu_fragmentation_pct=0.0`.

## Follow-Up Condition

If a future preflight reports `active_repack_allowed=1`, do not reuse this deferred gate as evidence. Create an explicit active-repack soak plan with movement stress, fill stress, allocator stress, rollback-off control, and renderer state consistency checks before swapping active renderer state.
