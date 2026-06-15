# External Profiling Campaign

Block 49, External Profiling Campaign, records the cross-platform GPU profiler workflow and the current evidence status. It does not invent profiler numbers when external tools have not produced captured artifacts.

## Technical Brief

User request:

Run the year-plan blocks in order, use MCP, and move on when a block cannot be completed locally.

Goal:

Prepare and gate an external profiling campaign for macOS/Xcode Metal, Windows GPU profiling, and optional Linux/Vulkan profiling while preserving the existing local evidence trust policy.

Context to inspect:

- `docs/GPU_PROFILING.md`
- `docs/GPU_ROADMAP.md`
- `docs/GPU_TRENDS.md`
- `docs/SHADOW_QUALITY_PARITY_PROGRAM.md`
- `logs/gpu_shadow_radius_matrix_wide/shadow-radius-profiler-capture-pack.txt`
- `scripts/gpu_terrain_shadow_profiler_results_check.sh`

Scope:

- Add `scripts/external_profiling_campaign_gate.sh`.
- Add this campaign document.
- Add the optional sanitized macOS `xctrace --attach` helper command to the operator handoff.
- Validate the current pending capture pack and release-candidate evidence.
- Generate a campaign plan artifact for external profiler operators.
- Generate a results-intake artifact that records the trusted row format, validator command, and trust boundary.

Out of scope:

- Do not run Xcode, RenderDoc, PIX, vendor profilers, or Vulkan tools from the campaign gate itself.
- Do not treat local FPS or Godot GPU timestamp fields as trusted pass/fail signals.
- Do not change renderer, shadow, transparency, draw distance, lighting, storage, protocol, or world generation behavior.

Assumptions:

- macOS/Metal is the first target because the existing shadow capture pack already asks for external Metal evidence.
- `scripts/gpu_terrain_shadow_xctrace_attach_capture.sh` is an operator helper for local macOS trace capture, not a profiler-results validator.
- Windows and Linux profiling are tracked as campaign lanes until a machine/tooling run produces captured artifacts.
- Pending capture packs are planning artifacts only, not profiler evidence.

Implementation plan:

- Require current GPU profiling docs, shadow quality summary, release-candidate summary, capture pack, capture plan, and results template.
- Write a line-oriented campaign plan with platform, tool, workload, artifact, and status rows.
- Write a line-oriented results-intake artifact for operators before any external profiler rows exist.
- Keep summary status `pass` when the campaign is correctly prepared and external rows are pending.
- If real profiler results exist, validate them with `scripts/gpu_terrain_shadow_profiler_results_check.sh` before marking captured evidence.

Done when:

- `scripts/external_profiling_campaign_gate.sh` emits `external-profiling-campaign-summary.txt`.
- `scripts/external_profiling_campaign_gate.sh` emits `external-profiling-results-intake.txt`.
- The summary records `external_profile_status=pending_external_profiler` unless real validated results exist.
- Docs point future agents to the campaign gate.

Checks:

- `sh -n scripts/external_profiling_campaign_gate.sh`
- `/bin/sh scripts/external_profiling_campaign_gate.sh logs/external_profiling_campaign_current`

Review gates:

- Any later profiler-number-driven renderer decision must cite validated captured results, not this pending campaign plan.

## Profiler Evidence Policy

Trusted external profiler evidence must include:

- Captured row status: `external_profile_status=captured`.
- Tool identity: Xcode Metal, PIX, RenderDoc, vendor GPU profiler, or Vulkan profiler.
- Artifact identity: a real profiler trace, capture, report, or screenshot path outside the generated TODO template.
- Positive GPU timing, such as `gpu_shadow_pass_ms`.
- Matching workload identity from the current capture plan.

Pending rows, commented template rows, capture packs, results-intake files, local FPS, and local macOS/Metal Godot timestamp samples are not profiler evidence.

## Capture Matrix

The current campaign uses these lanes:

- `macos_metal_shadow_proxy`: capture the existing shadow-radius rows with Xcode/Metal tooling.
- `windows_gpu_shadow_proxy`: repeat the same workload on a Windows GPU backend using PIX, RenderDoc, or a vendor profiler.
- `linux_vulkan_shadow_proxy`: optional lane for RenderDoc or Vulkan tooling when a Linux/Vulkan backend is available.

The macOS lane starts from:

```text
logs/gpu_shadow_radius_matrix_wide/shadow-radius-profiler-capture-pack.txt
```

The required validation command after real captured rows are written is:

```sh
sh scripts/gpu_terrain_shadow_profiler_results_check.sh \
  logs/gpu_shadow_radius_matrix_wide/shadow-radius-profiler-plan.txt \
  logs/gpu_shadow_radius_matrix_wide/shadow-radius-profiler-results.txt \
  logs/gpu_shadow_radius_matrix_wide/shadow-radius-profiler-results-summary.txt
```

The campaign gate also emits the current results-intake envelope:

```text
logs/external_profiling_campaign_current/external-profiling-results-intake.txt
```

That intake file is the handoff contract for external operators: it records the required captured row format, result/template paths, validation commands, and explicit trust boundary. It is not a profiler result.

For local macOS/Xcode Metal capture attempts, the intake points to:

```sh
RUMPELMC_SHADOW_XCTRACE_RECORD_SEC=10 \
RUMPELMC_SHADOW_XCTRACE_SMOKE_DELAY_SEC=25 \
sh scripts/gpu_terrain_shadow_xctrace_attach_capture.sh logs/gpu_shadow_xctrace_attach_current
```

That helper launches Godot with a minimal environment, attaches `Metal System Trace` to the Godot process, exports Metal command-buffer and encoder tables, and writes `shadow-xctrace-attach-capture-summary.txt`. Its trace/XML outputs still require manual profiler review; they are not accepted rows until a positive `gpu_shadow_pass_ms` is explicitly recorded and validated against the plan.

## Current Campaign Status

Current local status is expected to be `pending_external_profiler` because no validated external profiler result rows exist in this workspace. This is a blocked measurement-review step, not a local implementation failure.

Fresh 2026-06-15 current artifact:

- `logs/external_profiling_campaign_current/external-profiling-campaign-summary.txt` reported `status=pass`, `reason=external_profiler_pending`, `campaign_status=prepared`, `capture_readiness=live_rc_ready_for_external_capture`, `external_profile_status=pending_external_profiler`, `capture_pack_status=pending_external_profiler`, `capture_pack_rows=4`, `results_file_status=missing`, `results_template_status=todo`, `results_check_status=missing`, `captured_rows=0`, `missing_rows=4`, and `rc_live_checks=full`.
- `logs/external_profiling_campaign_current/external-profiling-results-intake.txt` reported `status=prepared`, `capture_readiness=live_rc_ready_for_external_capture`, the strict captured row format, the macOS `xctrace --attach` helper command, the full validator command, `template_rows_are_not_evidence=1`, `xctrace_exports_are_not_result_rows=1`, and `manual_gpu_shadow_pass_ms_required=1`.
- 2026-06-15 local Xcode/Metal attempts found that `xctrace --launch` against the shell workload failed with `Operation not permitted`, while an all-processes Metal trace grew to an unusable 13 GB before being killed and deleted. Targeted attach to a normally launched Godot process did work, so the sanitized attach helper now wraps that path.
- The current targeted attach run at `logs/gpu_shadow_xctrace_attach_current` reported `shadow_xctrace_attach_capture status=pass`, `trace_status=captured`, `trace_env_sanitized=1`, `profiler_artifact=logs/gpu_shadow_xctrace_attach_current/shadow-xctrace-attach.trace`, and `gpu_shadow_pass_ms_status=missing`.
- A later local marker-identification run at `logs/gpu_shadow_xctrace_attach_profiler_markers_current` reported `shadow_xctrace_attach_capture status=pass`, `trace_status=captured`, `trace_env_sanitized=1`, `profiler_artifact=logs/gpu_shadow_xctrace_attach_profiler_markers_current/shadow-xctrace-attach.trace`, `gpu_profiler_breadcrumb=1381256515`, `gpu_profiler_shader=rumpel_gpu_terrain_render_shader`, `gpu_profiler_pipeline=rumpel_gpu_terrain_compositor_pipeline`, and `gpu_shadow_pass_ms_status=missing`.
- Additional `xcrun xctrace export` review artifacts were saved beside the trace for `metal-command-buffer-completed`, `metal-gpu-intervals`, `metal-command-buffer-frame-assignment`, `metal-gpu-submission-to-command-buffer-id`, `metal-application-event-interval`, `metal-object-label`, and `metal-shader-profiler-shader-list`.
- CLI table inspection showed generic Godot/Xcode labels such as command-buffer render/blit commands, drawable present events, completion handlers, and shader entries. The newer terrain compositor markers were validated in the smoke marker and helper summary, but did not surface in exported CLI XML tables. Do not infer `gpu_shadow_pass_ms` from those rows.
- No accepted `gpu_shadow_pass_ms` has been reviewed from the targeted attach trace, and no result row has been copied into `shadow-radius-profiler-results.txt`.

The campaign gate is still useful because it verifies:

- The profiler capture pack exists and has planned rows.
- Shadow quality parity still treats profiler evidence as pending.
- Release-candidate evidence is clean before external capture.
- Future captured rows have a deterministic validator.

## Deferred Work

- Capture Xcode/Metal rows for the shadow-radius plan.
- Capture Windows GPU rows on matching workload and record driver/GPU/backend details.
- Capture Linux/Vulkan rows only if the backend is available and comparable.
- Decide shadow proxy retirement or native-shadow prioritization only after validated captured rows exist.
- Integrate validated results into report/baseline docs without changing the pending/captured trust boundary.

## Compatibility Rules

- Do not use this campaign document as permission to reduce shadows, lighting, draw distance, terrain quality, texture quality, or visible quality.
- Do not cite generated TODO templates, pending capture packs, or missing results files as measured GPU cost.
- Backend-specific optimizations must be explicitly gated and must preserve macOS behavior unless a separate architecture decision says otherwise.
- Production shadow-proxy retirement still requires active native-shadow evidence, validated profiler results, and Godot proxy rollback evidence.
