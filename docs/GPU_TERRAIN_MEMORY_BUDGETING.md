# GPU Terrain Memory Budgeting

Date: 2026-06-15

Scope: block 22 of the world streaming architecture plan. This introduces explicit GPU terrain memory budgets for current evidence without changing allocator, eviction, draw distance, visible quality, or runtime resource policy.

## Current Decision

Use a summary-only budget gate before changing GPU terrain memory behavior. The current evidence is comfortably within the initial budget, so no allocator policy, repack activation, capacity change, or resident-set eviction change is justified by this block alone.

## Budget Gate

Use:

```sh
sh scripts/gpu_terrain_memory_budget.sh logs/gpu_terrain_memory_budget_current
```

The gate consumes:

- `logs/gpu_terrain_load_scaling_radius16_summary_check/gpu-terrain-load-scaling-summary.txt`
- `logs/gpu_terrain_upload_pressure_smoke/gpu-upload-pressure-summary.txt`
- `logs/gpu_terrain_upload_pressure_smoke/gpu-resource-lifecycle-audit-summary.txt`

It checks prerequisite summaries, configured terrain buffer bytes, active face bytes, resident subchunks/draws/faces, draw-command occupancy/headroom, allocator fragmentation/free-range signals, and upload failures.

Default budgets:

- configured terrain buffers: `70,254,592` bytes;
- active terrain bytes: `4,194,304` bytes;
- subchunks: `4096`;
- draws: `4096`;
- faces: `262,144`;
- draw-command occupancy: `75%`;
- draw-command headroom: `32,768` bytes;
- fragmentation: `1%`;
- upload failures: `0`.

## Evidence

Fresh local evidence:

- Summary: `logs/gpu_terrain_memory_budget_current/gpu-terrain-memory-budget-summary.txt`
- Status: `pass`
- Reason: `within_budget`
- Configured terrain buffer bytes: `67,239,936` of `70,254,592`
- Active terrain bytes: `52,736` of `4,194,304`
- `gpu_subchunks=2482` of `4096`
- `gpu_draws=2482` of `4096`
- `gpu_faces=3296` of `262144`
- draw-command occupancy `30.298%` of `75%`
- draw-command headroom `91,360` bytes, minimum `32,768`
- fragmentation `0.0%` of `1.0%`
- upload failures `0`

## Guardrails

- Treat this as a governance gate, not a runtime memory manager.
- Do not use this block to reduce draw distance, shadows, lighting, texture quality, or visible quality.
- Do not activate repack or allocator mutation because the budget passes; repack remains governed by `docs/GPU_REPACK_ACTIVATION_PREFLIGHT.md`.
- Update budgets deliberately when terrain complexity, transparent rendering, native shadows, or gameplay block edits create representative higher memory pressure.
