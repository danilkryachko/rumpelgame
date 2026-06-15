# Shadow Proxy Retirement Plan

Date: 2026-06-15

Scope: block 28 of the world streaming architecture plan. This block decides whether CPU shadow-only mesh proxies can be removed after native-shadow or proxy-reduction evidence.

## Decision

CPU shadow proxies are not ready for retirement.

The current safe state is `deferred`:

- Block 26 native-shadow prototype preflight reports `active_prototype_allowed=0`.
- Block 27 validates Godot proxy and native-shadow fallback parity, not an active native shadow renderer.
- External profiler rows are still `pending_external_profiler`.
- Current shadow-radius evidence still proves the Godot proxy path is doing real work, with compact proxy savings but no replacement path.

## Gate

Use:

```sh
sh scripts/shadow_proxy_retirement_plan.sh logs/shadow_proxy_retirement_plan_current
```

The gate reads:

- Shadow quality parity summary: `logs/shadow_quality_parity_program_current/shadow-quality-parity-summary.txt`
- Native-shadow prototype preflight: `logs/gpu_native_shadow_prototype_preflight_current/gpu-native-shadow-prototype-preflight-summary.txt`
- Shadow radius matrix: `logs/gpu_shadow_radius_matrix_wide/shadow-radius-matrix-summary.txt`
- External-profiler capture pack: `logs/gpu_shadow_radius_matrix_wide/shadow-radius-profiler-capture-pack.txt`

Fresh local evidence:

- Summary: `logs/shadow_proxy_retirement_plan_current/shadow-proxy-retirement-summary.txt`
- Status: `deferred`
- `retirement_allowed=0`
- Reason: `native_shadow_not_active`
- Required before retirement: active native capture, external profiler evidence, and Godot proxy rollback
- Current proxy evidence: `max_full_cpu_proxy=96`, `max_compact_cpu_proxy=96`, `max_compact_shadow_proxy=201`, `max_compact_shadow_normals_saved=3932`

## Retirement Order

1. Keep `godot_proxy` as the default production shadow path.
2. Keep compact CPU shadow proxies as the measured optimization layer.
3. Only introduce proxy retirement behind a separate rollback flag after a real `shadow_path=gpu_native_shadow` capture exists.
4. Require visual parity, resource lifecycle, performance baseline, long movement smoke, and external profiler results before changing defaults.
5. Remove CPU shadow-only proxies only after rollback restores current `godot_proxy` behavior in the same build.
