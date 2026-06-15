# Shadow Quality Parity Program

Date: 2026-06-15

Scope: block 27 of the world streaming architecture plan. This block compares current Godot proxy shadows and native-shadow fallback/prototype evidence by visual parity, CPU proxy/resource counters, report-only FPS fields, and external-profiler readiness.

## Decision

The current shadow quality parity status is pass for the Godot proxy and native-shadow fallback path.

Active native-shadow comparison remains deferred because block 26 still reports `active_prototype_allowed=0` and `reason=implementation_gate_false`. This program therefore checks that the env-on native-shadow path is visually identical to the ordinary GPU terrain path while it falls back to Godot proxy shadows.

## Gate

Use:

```sh
sh scripts/shadow_quality_parity_program.sh logs/shadow_quality_parity_program_current
```

The gate reads:

- Visual parity summary: `logs/gpu_native_shadow_resource_lifecycle_parity_20260614/parity-summary.txt`
- Native-shadow prototype preflight: `logs/gpu_native_shadow_prototype_preflight_current/gpu-native-shadow-prototype-preflight-summary.txt`
- Shadow radius matrix: `logs/gpu_shadow_radius_matrix_wide/shadow-radius-matrix-summary.txt`
- External-profiler capture pack: `logs/gpu_shadow_radius_matrix_wide/shadow-radius-profiler-capture-pack.txt`
- Classified GPU report V2: `logs/gpu_terrain_report_v2_current/gpu-terrain-report-v2-summary.txt`

Fresh local evidence:

- Summary: `logs/shadow_quality_parity_program_current/shadow-quality-parity-summary.txt`
- Status: `pass`
- Active native comparison: `deferred`
- Native fallback visual delta: `avg_luma=0.0000`, `terrain_luma_range=0.0000`
- Lighting shadow visual delta: `avg_luma=0.0137`, `terrain_luma_range=0.0094`
- Compact shadow visual delta: `0.0000`
- Low-angle lighting visual delta: `avg_luma=0.0194`, `terrain_luma_range=0.0307`
- Low-angle compact shadow visual delta: `0.0000`
- Shadow-radius matrix: `4` rows, `3` usable normal-total rows, `1` rejected normal-total row
- External profiler status: `pending_external_profiler`
- Local FPS/frame fields stay `warning_only`

## Policy

- `godot_proxy` remains the production shadow path.
- `scene_shadows_disabled` and `diagnostic_no_shadow_proxy` remain diagnostics, not quality/performance substitutes.
- Native-shadow env-on fallback must stay visually equal to ordinary GPU terrain while `native_shadow_implemented=0`.
- Active native-shadow visual comparisons cannot be claimed until block 26 is no longer deferred and a real `shadow_path=gpu_native_shadow` runtime capture exists.
- FPS and local GPU timestamp fields stay warning-only until external profiler rows are captured and validated.
