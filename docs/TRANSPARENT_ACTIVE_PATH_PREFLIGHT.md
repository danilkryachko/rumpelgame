# Transparent Active Path Preflight

Date: 2026-06-15

Scope: block 30 of the world streaming architecture plan. This block asks whether transparent terrain can move from fixture metadata/fallback toward a real transparent workload and render pass behind a flag.

## Decision

Active transparent rendering remains deferred.

Current evidence proves the fixture fallback chain, not an active transparent pass:

- `GPU_TERRAIN_TRANSPARENT_IMPLEMENTED=false`.
- Env-on fixture smoke reports `transparent_requested=1`, `transparent_active=0`, and `transparent_fallback=1`.
- Transparent workload markers remain zero: `transparent_blocks=0`, `transparent_faces=0`, `transparent_draws=0`, and `transparent_subchunks=0`.
- Fixture overlay metadata is present only as inactive client-only metadata: `transparent_fixture_overlay_roles=5`, `transparent_fixture_overlay_blocks=5`.
- No transparent face buffer, alpha blending shader path, sort policy, material identity, production block ID, protocol/storage/worldgen path, or external profiler result exists.

## Gate

Use:

```sh
sh scripts/transparent_active_path_preflight.sh logs/transparent_active_path_preflight_current
```

The gate reads:

- Fixture pack: `logs/gpu_transparent_fixture_plan/transparent-fixture-pack.txt`
- Runtime fixture scene smoke: `logs/gpu_transparent_fixture_scene_smoke/transparent-fixture-scene-smoke-summary.txt`
- Default-off guard: `logs/gpu_transparent_fixture_plan/transparent-fixture-default-off-check.txt`
- Final report guard: `logs/gpu_transparent_fixture_plan/transparent-fixture-final-report-check.txt`
- Implementation gate source: `client/rust_ext/src/lib.rs`

Fresh local evidence:

- Summary: `logs/transparent_active_path_preflight_current/transparent-active-path-preflight-summary.txt`
- Status: `deferred`
- `active_path_allowed=0`
- Reason: `implementation_gate_false`
- Fixture pack, scene smoke, default-off, and final-report guards are clean.

## Promotion Requirements

Before the active path can advance:

- Approve a fixture-only material identity or production block ID path.
- Define transparent sorting and depth policy.
- Add a real transparent workload with nonzero `transparent_blocks`, `transparent_faces`, `transparent_draws`, and `transparent_subchunks`.
- Keep the opaque path as default rollback.
- Prove opaque-depth occlusion, explicit collision-by-solidity behavior, and visible opaque faces next to transparent fixture blocks.
- Add external profiler evidence before default promotion.
