# Native Shadow Prototype Preflight

Date: 2026-06-16

Scope: block 26 of the world streaming architecture plan. The requested goal is to move from native-shadow marker/descriptor scaffolding toward a real RenderingDevice shadow path behind a flag.

## Decision

Active native shadow rendering remains deferred.

The current project state does not satisfy the safe local prerequisites for a real RenderingDevice shadow pass:

- `GPU_TERRAIN_NATIVE_SHADOW_IMPLEMENTED` is still `false`.
- Env-on native-shadow captures must continue to fall back to `shadow_path=godot_proxy`.
- Native-shadow resources are descriptor/lifecycle scaffolding only; they must not allocate RenderingDevice RIDs or submit shadow passes while the implementation gate is false.
- Resource lifecycle and baseline evidence are clean, so there is no local pressure that justifies bypassing the current Godot proxy fallback.

The safe Block 26 artifact is therefore a prototype preflight gate, not renderer mutation.

## Preflight

Use:

```sh
sh scripts/gpu_native_shadow_prototype_preflight.sh logs/gpu_native_shadow_prototype_preflight_current
```

The gate reads:

- Native-shadow env-on fallback summary: `logs/gpu_native_shadow_command_buffer_submit_contract_20260614/movement-stress-summary.txt`
- RenderingDevice resource lifecycle summary: `logs/gpu_terrain_upload_pressure_smoke/gpu-resource-lifecycle-audit-summary.txt`
- Performance baseline summary: `logs/performance_baseline_governance_current/performance-baseline-governance-summary.txt`
- Implementation gate source: `client/rust_ext/src/lib.rs`

Fresh local evidence:

- Summary: `logs/gpu_native_shadow_prototype_preflight_current/gpu-native-shadow-prototype-preflight-summary.txt`
- Status: `deferred`
- Reason: `implementation_gate_false`
- `active_prototype_allowed=0`
- Fallback markers: `requested=1`, `active=0`, `fallback=1`, `implemented=0`, `resource_status=disabled`
- Fallback readiness markers: `fallback_readiness_fields=present`, `fallback_readiness_status=disabled_clean`, `fallback_readiness_missing=0`, and `fallback_readiness_errors=0`
- Disabled native path boundaries: framebuffer/pass/command-buffer statuses remain `none`, readiness flags remain `0`, begin/end/submit counts remain `0`
- Resource lifecycle: `resource_status=pass`, `native_shadow_active=0`, native-shadow framebuffer/pass/command-buffer errors `0`
- Baseline governance: `baseline_status=pass`, `baseline_warning_status=ok`

Older compact fallback summaries without framebuffer/pass/command-buffer readiness fields must not be used for this gate; they should fail with `reason=fallback_summary_missing_readiness_fields`.

## Promotion Requirements

Before a later task can run a true native shadow prototype, it must first keep these invariants intact:

- `godot_proxy` remains the default and rollback path.
- `GPU_TERRAIN_NATIVE_SHADOW_IMPLEMENTED` changes only with a real implementation, not with marker-only telemetry.
- The native path reports `shadow_path=gpu_native_shadow` only when it actually renders terrain into the shadow path.
- Env-on fallback evidence remains available for rollback validation.
- Visual parity passes against the Godot proxy path.
- External profiler evidence shows a real benefit before default promotion.
