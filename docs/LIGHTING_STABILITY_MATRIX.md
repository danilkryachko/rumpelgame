# Lighting Stability Matrix

Date: 2026-06-15

Scope: block 29 of the world streaming architecture plan. This block checks directional-light stability across sun angle, energy, shadow proxy mode, movement, dense resident load, and visual/perf gates.

## Matrix

Use:

```sh
sh scripts/lighting_stability_matrix.sh logs/lighting_stability_matrix_current
```

The gate reads:

- Visual parity summary: `logs/gpu_native_shadow_resource_lifecycle_parity_20260614/parity-summary.txt`
- Default movement lighting summary: `logs/gpu_lighting_marker_summary_retry_20260613/movement-stress-summary.txt`
- Low-angle movement lighting summary: `logs/gpu_lighting_low_angle_smoke_20260613_retry/movement-stress-summary.txt`
- Dense resident load summary: `logs/gpu_terrain_load_scaling_radius16_summary_check/gpu-terrain-load-scaling-summary.txt`
- Shadow quality summary: `logs/shadow_quality_parity_program_current/shadow-quality-parity-summary.txt`

Fresh local evidence:

- Summary: `logs/lighting_stability_matrix_current/lighting-stability-matrix-summary.txt`
- Status: `pass`
- Default light: `gpu_light_dir=-0.355/0.743/0.567`, `gpu_light_energy=0.450`, `gpu_light_ambient=0.550`
- Low-angle light: `gpu_light_dir=-0.775/0.407/0.484`, `gpu_light_energy=0.700`, `gpu_light_ambient=0.550`
- Default movement: `terrain_queue_max_ms=1.179`, `gpu_compositor_submit_max_ms=0.130`, `process_wall_p95_ms=0.019`
- Low-angle movement: `terrain_queue_max_ms=1.200`, `gpu_compositor_submit_max_ms=0.174`, `process_wall_p95_ms=0.034`
- Visual parity: lighting shadow delta `0.0137`, low-angle delta `0.0194`, compact shadow deltas `0.0000`
- Dense resident load: `2482` subchunks/draws, `3296` faces, upload failures `0`

Ambient variation remains a deferred sub-gate because current compatible artifacts keep `gpu_light_ambient=0.550` for both default and low-angle lighting. Add a new smoke-only ambient pose before claiming ambient-variant coverage.

## Policy

- Lighting variants are smoke-only controls.
- Do not change default scene lighting, draw distance, shadows, texture quality, protocol, storage, world generation, or chunk serialization for this matrix.
- Local FPS and GPU timestamps remain report-only.
- Any future shader lighting, native-shadow, or default light change must rerun this matrix or a stricter successor.
