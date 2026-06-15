# Transparent Fixture Acceptance Suite

Date: 2026-06-15

Scope: block 32 of the world streaming architecture plan. This block consolidates the transparent fixture pack, runtime scene smoke, default-off guard, active-path preflight, and sorting/depth policy into one acceptance summary.

## Decision

The current fixture fallback acceptance suite passes.

Active transparent fixture acceptance remains deferred because `transparent_active=0` and all transparent workload markers are zero. This is intentional while `GPU_TERRAIN_TRANSPARENT_IMPLEMENTED=false`.

## Gate

Use:

```sh
sh scripts/transparent_fixture_acceptance_suite.sh logs/transparent_fixture_acceptance_suite_current
```

The gate reads:

- Fixture pack: `logs/gpu_transparent_fixture_plan/transparent-fixture-pack.txt`
- Runtime scene smoke: `logs/gpu_transparent_fixture_scene_smoke/transparent-fixture-scene-smoke-summary.txt`
- Active-path preflight: `logs/transparent_active_path_preflight_current/transparent-active-path-preflight-summary.txt`
- Sorting/depth program: `logs/transparent_sorting_depth_program_current/transparent-sorting-depth-summary.txt`
- Acceptance, default-off, and final-report checks from `logs/gpu_transparent_fixture_plan/`

Fresh local evidence:

- Summary: `logs/transparent_fixture_acceptance_suite_current/transparent-fixture-acceptance-suite-summary.txt`
- Status: `pass`
- Current fallback acceptance: `pass`
- Active fixture acceptance: `deferred`
- Runtime scene smoke: `transparent_requested=1`, `transparent_active=0`, `transparent_fallback=1`
- Workload markers: `transparent_blocks=0`, `transparent_faces=0`, `transparent_draws=0`, `transparent_subchunks=0`
- Overlay metadata: `roles=5`, `blocks=5`
- Upload failures: `0`

## Active Acceptance Requirements

Before active acceptance can pass:

- `transparent_active=1` and `transparent_fallback=0` in a reviewed fixture run.
- Nonzero transparent workload markers.
- Sorting/depth policy gates with occlusion and collision evidence.
- Opaque path rollback and default-off checks remain intact.
- External profiler evidence is captured before default promotion.
