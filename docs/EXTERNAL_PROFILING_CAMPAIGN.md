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
- Validate the current pending capture pack and release-candidate evidence.
- Generate a campaign plan artifact for external profiler operators.

Out of scope:

- Do not run Xcode, RenderDoc, PIX, vendor profilers, or Vulkan tools from this local script.
- Do not treat local FPS or Godot GPU timestamp fields as trusted pass/fail signals.
- Do not change renderer, shadow, transparency, draw distance, lighting, storage, protocol, or world generation behavior.

Assumptions:

- macOS/Metal is the first target because the existing shadow capture pack already asks for external Metal evidence.
- Windows and Linux profiling are tracked as campaign lanes until a machine/tooling run produces captured artifacts.
- Pending capture packs are planning artifacts only, not profiler evidence.

Implementation plan:

- Require current GPU profiling docs, shadow quality summary, release-candidate summary, and capture pack.
- Write a line-oriented campaign plan with platform, tool, workload, artifact, and status rows.
- Keep summary status `pass` when the campaign is correctly prepared and external rows are pending.
- If real profiler results exist, validate them with `scripts/gpu_terrain_shadow_profiler_results_check.sh` before marking captured evidence.

Done when:

- `scripts/external_profiling_campaign_gate.sh` emits `external-profiling-campaign-summary.txt`.
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

Pending rows, commented template rows, capture packs, local FPS, and local macOS/Metal Godot timestamp samples are not profiler evidence.

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

## Current Campaign Status

Current local status is expected to be `pending_external_profiler` because no real external profiler trace has been recorded in this workspace. This is a blocked external-lab step, not a local implementation failure.

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
