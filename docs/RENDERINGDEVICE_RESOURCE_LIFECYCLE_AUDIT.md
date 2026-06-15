# RenderingDevice Resource Lifecycle Audit

Date: 2026-06-15

Scope: block 21 of the world streaming architecture plan. This is an audit-only slice for GPU terrain `RenderingDevice` resources: RIDs, buffers, uniform sets, atlas resources, scene targets, and native-shadow lifecycle markers.

## Current Decision

Do not change GPU resource ownership behavior yet. Current pressure evidence shows clean reuse and no upload/native-shadow resource errors, so this block adds a repeatable audit gate rather than activating allocator/repack/resource replacement behavior.

## Audit Gate

Use:

```sh
sh scripts/gpu_resource_lifecycle_audit.sh logs/gpu_terrain_upload_pressure_smoke
```

The gate regenerates a scoped `gpu_terrain_report.sh` report and requires:

- clean report error scan, including no `ERROR`, `SCRIPT ERROR`, `panic`, `ObjectDB`, `leaked`, or nonzero upload failure markers;
- at least one `gpu_scene_target_create` and `gpu_scene_target_reuse`;
- zero `gpu_scene_target_replace` by default;
- at least one `gpu_uniform_set_create`, `gpu_atlas_texture_create`, and `gpu_atlas_sampler_create`;
- zero `gpu_upload_fail`, `gpu_upload_fail_capacity`, and `gpu_upload_fail_fragmented`;
- zero native-shadow framebuffer/pass/command-buffer error counters.

Thresholds are configurable with `RUMPELMC_RESOURCE_LIFECYCLE_*` environment variables in the script. The defaults are intentionally strict for the current single-scene pressure artifact.

## Evidence

Fresh local evidence:

- Summary: `logs/gpu_terrain_upload_pressure_smoke/gpu-resource-lifecycle-audit-summary.txt`
- Report: `logs/gpu_terrain_upload_pressure_smoke/gpu-resource-lifecycle-report.txt`
- Status: `pass`
- `gpu_scene_target_create=1`
- `gpu_scene_target_reuse=1854`
- `gpu_scene_target_replace=0`
- `gpu_uniform_set_create=1`
- `gpu_atlas_texture_create=1`
- `gpu_atlas_sampler_create=1`
- `gpu_upload_fail=0`
- `gpu_upload_fail_capacity=0`
- `gpu_upload_fail_fragmented=0`
- `native_shadow_active=0`
- native-shadow framebuffer/pass/command-buffer error counters all `0`

This evidence validates the current default GPU terrain lifecycle under the existing upload-pressure smoke artifact. It is not evidence for active native shadows or active repack, because those paths remain disabled/deferred.

## Guardrails

- Keep this block audit-only unless a later task explicitly asks for resource behavior changes.
- Do not cite zero native-shadow lifecycle counters as native-shadow runtime validation while `native_shadow_active=0`.
- Do not relax `gpu_scene_target_replace=0` without a new reload/resize/error-path scenario that intentionally exercises target replacement.
- Re-run this gate after renderer resource ownership, atlas creation, uniform set layout, repack upload, native shadow resources, or shutdown cleanup changes.
