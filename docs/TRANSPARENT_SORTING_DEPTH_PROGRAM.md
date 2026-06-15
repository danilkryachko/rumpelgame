# Transparent Sorting And Depth Program

Date: 2026-06-15

Scope: block 31 of the world streaming architecture plan. This block defines the sorting and depth policy that must exist before any active transparent terrain pass.

## Decision

Sorting and depth activation remains deferred.

The proposed first policy is:

- Sort transparent chunks/subchunks back-to-front from the camera.
- Render opaque terrain first.
- Depth-test transparent terrain against opaque depth.
- Do not rely on transparent depth writes as an opaque occlusion substitute until a fixture proves the behavior.
- Keep same-material transparent seams hidden only when the fixture explicitly accepts that rule.

This policy is not active because the transparent active path is still deferred and workload markers are zero.

## Gate

Use:

```sh
sh scripts/transparent_sorting_depth_program.sh logs/transparent_sorting_depth_program_current
```

The gate reads:

- Active-path preflight: `logs/transparent_active_path_preflight_current/transparent-active-path-preflight-summary.txt`
- Fixture scene checklist: `logs/gpu_transparent_fixture_plan/transparent-fixture-scene-checklist.txt`
- Fixture scene harness check: `logs/gpu_transparent_fixture_plan/transparent-fixture-scene-harness-check.txt`
- Fixture acceptance check: `logs/gpu_transparent_fixture_plan/transparent-fixture-acceptance-check.txt`

Fresh local evidence:

- Summary: `logs/transparent_sorting_depth_program_current/transparent-sorting-depth-summary.txt`
- Status: `deferred`
- `sort_depth_active_allowed=0`
- Reason: `active_transparent_not_available`
- Scene contract roles: front transparent, behind wall transparent, opaque depth occluder, adjacent same-material pair, collision probe
- Transparent workload markers: all `0`

## Promotion Requirements

Before activation:

- Active transparent workload markers must become nonzero in a reviewed fixture run.
- Opaque depth occlusion must be proven by screenshot/marker evidence.
- Collision solidity must be asserted independently from render opacity.
- Sorting cost and policy must be reported.
- The opaque render path must remain the default rollback.
