#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/transparent_prototype_shape_decision"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

SUMMARY_PATH="$OUT_DIR/transparent-prototype-shape-decision-summary.txt"
ACTIVE_PREFLIGHT_SUMMARY="${RUMPELMC_TRANSPARENT_PROTOTYPE_ACTIVE_PREFLIGHT_SUMMARY:-"$ROOT_DIR/logs/transparent_active_path_preflight_current/transparent-active-path-preflight-summary.txt"}"
SORT_DEPTH_SUMMARY="${RUMPELMC_TRANSPARENT_PROTOTYPE_SORT_DEPTH_SUMMARY:-"$ROOT_DIR/logs/transparent_sorting_depth_program_current/transparent-sorting-depth-summary.txt"}"
ACCEPTANCE_SUMMARY="${RUMPELMC_TRANSPARENT_PROTOTYPE_ACCEPTANCE_SUMMARY:-"$ROOT_DIR/logs/transparent_fixture_acceptance_suite_current/transparent-fixture-acceptance-suite-summary.txt"}"
MATERIAL_SUMMARY="${RUMPELMC_TRANSPARENT_PROTOTYPE_MATERIAL_SUMMARY:-"$ROOT_DIR/logs/block_material_metadata_design_current/block-material-metadata-design-summary.txt"}"
DESIGN_DOC="${RUMPELMC_TRANSPARENT_PROTOTYPE_DESIGN_DOC:-"$ROOT_DIR/docs/GPU_TRANSPARENT_PATH.md"}"
MATERIAL_DOC="${RUMPELMC_TRANSPARENT_PROTOTYPE_MATERIAL_DOC:-"$ROOT_DIR/docs/BLOCK_MATERIAL_METADATA_DESIGN.md"}"
RUST_SOURCE="${RUMPELMC_TRANSPARENT_PROTOTYPE_RUST_SOURCE:-"$ROOT_DIR/client/rust_ext/src/lib.rs"}"

mkdir -p "$OUT_DIR"

fail() {
  echo "transparent_prototype_shape_decision_gate: $*" >&2
  exit 1
}

field_metric() {
  key="$1"
  path="$2"
  awk -v key="$key" '
    {
      prefix = key "="
      for (i = 1; i <= NF; i++) {
        if (index($i, prefix) == 1) {
          value = substr($i, length(prefix) + 1)
          gsub(/^"/, "", value)
          gsub(/"$/, "", value)
          print value
          exit
        }
      }
    }
  ' "$path"
}

require_token() {
  path="$1"
  token="$2"
  test -s "$path" || fail "missing file $path"
  grep -Fq "$token" "$path" || fail "missing token '$token' in $path"
}

for path in "$ACTIVE_PREFLIGHT_SUMMARY" "$SORT_DEPTH_SUMMARY" "$ACCEPTANCE_SUMMARY" "$MATERIAL_SUMMARY" "$DESIGN_DOC" "$MATERIAL_DOC" "$RUST_SOURCE"; do
  test -s "$path" || fail "missing required input $path"
done

for token in \
  "### Option A: Split Opaque And Transparent GPU Buffers" \
  "### Option B: Alpha-Tested Cutout Only" \
  "### Option C: Godot Material Fallback First" \
  "Render transparent terrain after opaque terrain with depth testing against the opaque pass" \
  "CPU/GPU parity and external profiler evidence are required"; do
  require_token "$DESIGN_DOC" "$token"
done

for token in \
  'render_class=cutout' \
  'render_class=transparent' \
  'render_class=cutout` may use alpha test with opaque depth' \
  'current_runtime_contract=opaque_only'; do
  require_token "$MATERIAL_DOC" "$token"
done

if grep -q 'const GPU_TERRAIN_TRANSPARENT_IMPLEMENTED: bool = false;' "$RUST_SOURCE"; then
  implementation_gate="false"
else
  implementation_gate="changed"
fi

active_status="$(field_metric status "$ACTIVE_PREFLIGHT_SUMMARY")"
active_allowed="$(field_metric active_path_allowed "$ACTIVE_PREFLIGHT_SUMMARY")"
active_reason="$(field_metric reason "$ACTIVE_PREFLIGHT_SUMMARY")"
active_implementation_gate="$(field_metric implementation_gate "$ACTIVE_PREFLIGHT_SUMMARY")"
active_blocks="$(field_metric transparent_blocks "$ACTIVE_PREFLIGHT_SUMMARY")"
active_faces="$(field_metric transparent_faces "$ACTIVE_PREFLIGHT_SUMMARY")"
active_draws="$(field_metric transparent_draws "$ACTIVE_PREFLIGHT_SUMMARY")"
active_subchunks="$(field_metric transparent_subchunks "$ACTIVE_PREFLIGHT_SUMMARY")"
active_upload_fail="$(field_metric gpu_upload_fail "$ACTIVE_PREFLIGHT_SUMMARY")"

sort_status="$(field_metric status "$SORT_DEPTH_SUMMARY")"
sort_allowed="$(field_metric sort_depth_active_allowed "$SORT_DEPTH_SUMMARY")"
sort_reason="$(field_metric reason "$SORT_DEPTH_SUMMARY")"
sort_policy="$(field_metric proposed_sort_policy "$SORT_DEPTH_SUMMARY")"
depth_policy="$(field_metric depth_policy "$SORT_DEPTH_SUMMARY")"
sort_blocks="$(field_metric transparent_blocks "$SORT_DEPTH_SUMMARY")"
sort_faces="$(field_metric transparent_faces "$SORT_DEPTH_SUMMARY")"
sort_draws="$(field_metric transparent_draws "$SORT_DEPTH_SUMMARY")"
sort_subchunks="$(field_metric transparent_subchunks "$SORT_DEPTH_SUMMARY")"

accept_status="$(field_metric status "$ACCEPTANCE_SUMMARY")"
current_fallback_acceptance="$(field_metric current_fallback_acceptance "$ACCEPTANCE_SUMMARY")"
active_fixture_acceptance="$(field_metric active_fixture_acceptance "$ACCEPTANCE_SUMMARY")"
active_fixture_reason="$(field_metric active_fixture_reason "$ACCEPTANCE_SUMMARY")"
accept_sort_status="$(field_metric sort_depth_status "$ACCEPTANCE_SUMMARY")"
accept_blocks="$(field_metric transparent_blocks "$ACCEPTANCE_SUMMARY")"
accept_faces="$(field_metric transparent_faces "$ACCEPTANCE_SUMMARY")"
accept_draws="$(field_metric transparent_draws "$ACCEPTANCE_SUMMARY")"
accept_subchunks="$(field_metric transparent_subchunks "$ACCEPTANCE_SUMMARY")"
accept_upload_fail="$(field_metric gpu_upload_fail "$ACCEPTANCE_SUMMARY")"

material_status="$(field_metric status "$MATERIAL_SUMMARY")"
active_schema_change="$(field_metric active_schema_change "$MATERIAL_SUMMARY")"
current_runtime_contract="$(field_metric current_runtime_contract "$MATERIAL_SUMMARY")"
render_classes="$(field_metric render_classes "$MATERIAL_SUMMARY")"
material_transparent_status="$(field_metric transparent_fixture_status "$MATERIAL_SUMMARY")"
material_transparent_active="$(field_metric transparent_active_acceptance "$MATERIAL_SUMMARY")"
material_blocks="$(field_metric transparent_blocks "$MATERIAL_SUMMARY")"
material_faces="$(field_metric transparent_faces "$MATERIAL_SUMMARY")"
material_draws="$(field_metric transparent_draws "$MATERIAL_SUMMARY")"
material_subchunks="$(field_metric transparent_subchunks "$MATERIAL_SUMMARY")"
material_upload_fail="$(field_metric gpu_upload_fail "$MATERIAL_SUMMARY")"

awk \
  -v implementation_gate="$implementation_gate" \
  -v active_status="${active_status:-blocked}" \
  -v active_allowed="${active_allowed:-1}" \
  -v active_reason="${active_reason:-unknown}" \
  -v active_implementation_gate="${active_implementation_gate:-changed}" \
  -v active_blocks="${active_blocks:-1}" \
  -v active_faces="${active_faces:-1}" \
  -v active_draws="${active_draws:-1}" \
  -v active_subchunks="${active_subchunks:-1}" \
  -v active_upload_fail="${active_upload_fail:-1}" \
  -v sort_status="${sort_status:-blocked}" \
  -v sort_allowed="${sort_allowed:-1}" \
  -v sort_reason="${sort_reason:-unknown}" \
  -v sort_policy="${sort_policy:-missing}" \
  -v depth_policy="${depth_policy:-missing}" \
  -v sort_blocks="${sort_blocks:-1}" \
  -v sort_faces="${sort_faces:-1}" \
  -v sort_draws="${sort_draws:-1}" \
  -v sort_subchunks="${sort_subchunks:-1}" \
  -v accept_status="${accept_status:-fail}" \
  -v current_fallback_acceptance="${current_fallback_acceptance:-fail}" \
  -v active_fixture_acceptance="${active_fixture_acceptance:-missing}" \
  -v active_fixture_reason="${active_fixture_reason:-unknown}" \
  -v accept_sort_status="${accept_sort_status:-blocked}" \
  -v accept_blocks="${accept_blocks:-1}" \
  -v accept_faces="${accept_faces:-1}" \
  -v accept_draws="${accept_draws:-1}" \
  -v accept_subchunks="${accept_subchunks:-1}" \
  -v accept_upload_fail="${accept_upload_fail:-1}" \
  -v material_status="${material_status:-fail}" \
  -v active_schema_change="${active_schema_change:-1}" \
  -v current_runtime_contract="${current_runtime_contract:-changed}" \
  -v render_classes="${render_classes:-missing}" \
  -v material_transparent_status="${material_transparent_status:-fail}" \
  -v material_transparent_active="${material_transparent_active:-missing}" \
  -v material_blocks="${material_blocks:-1}" \
  -v material_faces="${material_faces:-1}" \
  -v material_draws="${material_draws:-1}" \
  -v material_subchunks="${material_subchunks:-1}" \
  -v material_upload_fail="${material_upload_fail:-1}" \
  -v active_preflight_summary="$ACTIVE_PREFLIGHT_SUMMARY" \
  -v sort_depth_summary="$SORT_DEPTH_SUMMARY" \
  -v acceptance_summary="$ACCEPTANCE_SUMMARY" \
  -v material_summary="$MATERIAL_SUMMARY" '
  BEGIN {
    status = "pass"
    reason = "ok"
    decision = "cutout_only_first"
    active_prototype_allowed = 0
    default_runtime_change_allowed = 0
    selected_next_runtime_step = "cutout_alpha_test_prototype_behind_flag"
    cutout_status = "selected_first_shape"
    split_buffers_status = "deferred_until_active_workload_and_sort_depth"
    alpha_blend_status = "deferred_until_sort_depth_and_external_profiler"
    godot_fallback_status = "compatibility_fallback_only"
    requires_opaque_rollback = 1
    requires_external_profiler_before_default = 1
    requires_mac_windows_validation = 1

    active_workload = active_blocks + active_faces + active_draws + active_subchunks
    sort_workload = sort_blocks + sort_faces + sort_draws + sort_subchunks
    accept_workload = accept_blocks + accept_faces + accept_draws + accept_subchunks
    material_workload = material_blocks + material_faces + material_draws + material_subchunks

    active_ok = active_status == "deferred" &&
      active_allowed + 0 == 0 &&
      active_reason == "implementation_gate_false" &&
      active_implementation_gate == "false" &&
      active_workload == 0 &&
      active_upload_fail + 0 == 0
    sort_ok = sort_status == "deferred" &&
      sort_allowed + 0 == 0 &&
      sort_reason == "active_transparent_not_available" &&
      sort_policy == "chunk_subchunk_back_to_front" &&
      sort_workload == 0
    acceptance_ok = accept_status == "pass" &&
      current_fallback_acceptance == "pass" &&
      active_fixture_acceptance == "deferred" &&
      accept_sort_status == "deferred" &&
      accept_workload == 0 &&
      accept_upload_fail + 0 == 0
    material_ok = material_status == "pass" &&
      active_schema_change + 0 == 0 &&
      current_runtime_contract == "opaque_only" &&
      material_transparent_status == "pass" &&
      material_transparent_active == "deferred" &&
      material_workload == 0 &&
      material_upload_fail + 0 == 0 &&
      index(render_classes, "cutout") > 0 &&
      index(render_classes, "transparent") > 0 &&
      index(render_classes, "liquid") > 0

    if (implementation_gate != "false") {
      status = "fail"
      reason = "implementation_gate_changed_requires_review"
      decision = "review_active_transparent_implementation"
    } else if (!active_ok) {
      status = "fail"
      reason = "active_preflight_not_at_deferred_zero_workload_gate"
    } else if (!sort_ok) {
      status = "fail"
      reason = "sorting_depth_not_at_deferred_zero_workload_gate"
    } else if (!acceptance_ok) {
      status = "fail"
      reason = "fixture_acceptance_not_at_deferred_gate"
    } else if (!material_ok) {
      status = "fail"
      reason = "material_metadata_not_at_opaque_only_gate"
    }

    printf("transparent_prototype_shape_decision status=%s reason=%s decision=%s active_prototype_allowed=%d default_runtime_change_allowed=%d selected_next_runtime_step=%s cutout_status=%s split_buffers_status=%s alpha_blend_status=%s godot_fallback_status=%s implementation_gate=%s active_path_status=%s active_path_allowed=%d sort_depth_status=%s sort_depth_active_allowed=%d proposed_sort_policy=%s depth_policy=%s fixture_acceptance_status=%s current_fallback_acceptance=%s active_fixture_acceptance=%s active_fixture_reason=%s material_status=%s active_schema_change=%d current_runtime_contract=%s render_classes=%s transparent_blocks=%d transparent_faces=%d transparent_draws=%d transparent_subchunks=%d gpu_upload_fail_total=%d requires_opaque_rollback=%d requires_external_profiler_before_default=%d requires_mac_windows_validation=%d active_preflight_summary=%s sort_depth_summary=%s acceptance_summary=%s material_summary=%s\n", status, reason, decision, active_prototype_allowed, default_runtime_change_allowed, selected_next_runtime_step, cutout_status, split_buffers_status, alpha_blend_status, godot_fallback_status, implementation_gate, active_status, active_allowed, sort_status, sort_allowed, sort_policy, depth_policy, accept_status, current_fallback_acceptance, active_fixture_acceptance, active_fixture_reason, material_status, active_schema_change, current_runtime_contract, render_classes, active_blocks + sort_blocks + accept_blocks + material_blocks, active_faces + sort_faces + accept_faces + material_faces, active_draws + sort_draws + accept_draws + material_draws, active_subchunks + sort_subchunks + accept_subchunks + material_subchunks, active_upload_fail + accept_upload_fail + material_upload_fail, requires_opaque_rollback, requires_external_profiler_before_default, requires_mac_windows_validation, active_preflight_summary, sort_depth_summary, acceptance_summary, material_summary)
    if (status != "pass") {
      exit 1
    }
  }
' > "$SUMMARY_PATH" || {
  cat "$SUMMARY_PATH" >&2 || true
  fail "transparent prototype shape decision failed"
}

cat "$SUMMARY_PATH"
echo "Transparent prototype shape decision artifacts: $OUT_DIR"
