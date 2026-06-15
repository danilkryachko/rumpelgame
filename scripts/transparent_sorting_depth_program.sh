#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/transparent_sorting_depth_program"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

SUMMARY_PATH="$OUT_DIR/transparent-sorting-depth-summary.txt"
ACTIVE_PREFLIGHT_SUMMARY="${RUMPELMC_TRANSPARENT_SORT_DEPTH_ACTIVE_PREFLIGHT_SUMMARY:-"$ROOT_DIR/logs/transparent_active_path_preflight_current/transparent-active-path-preflight-summary.txt"}"
SCENE_CHECKLIST="${RUMPELMC_TRANSPARENT_SORT_DEPTH_SCENE_CHECKLIST:-"$ROOT_DIR/logs/gpu_transparent_fixture_plan/transparent-fixture-scene-checklist.txt"}"
SCENE_HARNESS_CHECK="${RUMPELMC_TRANSPARENT_SORT_DEPTH_SCENE_HARNESS_CHECK:-"$ROOT_DIR/logs/gpu_transparent_fixture_plan/transparent-fixture-scene-harness-check.txt"}"
ACCEPTANCE_CHECK="${RUMPELMC_TRANSPARENT_SORT_DEPTH_ACCEPTANCE_CHECK:-"$ROOT_DIR/logs/gpu_transparent_fixture_plan/transparent-fixture-acceptance-check.txt"}"

mkdir -p "$OUT_DIR"

fail() {
  echo "transparent_sorting_depth_program: $*" >&2
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

required_grep() {
  path="$1"
  pattern="$2"
  grep -F -- "$pattern" "$path" >/dev/null || fail "missing pattern in $path: $pattern"
}

test -s "$ACTIVE_PREFLIGHT_SUMMARY" || fail "missing active transparent preflight summary $ACTIVE_PREFLIGHT_SUMMARY"
test -s "$SCENE_CHECKLIST" || fail "missing transparent scene checklist $SCENE_CHECKLIST"
test -s "$SCENE_HARNESS_CHECK" || fail "missing transparent scene harness check $SCENE_HARNESS_CHECK"
test -s "$ACCEPTANCE_CHECK" || fail "missing transparent acceptance check $ACCEPTANCE_CHECK"

required_grep "$SCENE_CHECKLIST" "block_role=front_transparent"
required_grep "$SCENE_CHECKLIST" "block_role=behind_wall_transparent"
required_grep "$SCENE_CHECKLIST" "block_role=opaque_depth_occluder"
required_grep "$SCENE_CHECKLIST" "block_role=adjacent_same_material_pair"
required_grep "$SCENE_CHECKLIST" "block_role=collision_probe"
required_grep "$SCENE_CHECKLIST" "expected_opaque_occlusion=required"
required_grep "$SCENE_CHECKLIST" "expected_same_material_seam=hidden_or_explicit"
required_grep "$SCENE_CHECKLIST" "expected_collision_solidity=explicit"

active_status="$(field_metric status "$ACTIVE_PREFLIGHT_SUMMARY")"
active_allowed="$(field_metric active_path_allowed "$ACTIVE_PREFLIGHT_SUMMARY")"
active_reason="$(field_metric reason "$ACTIVE_PREFLIGHT_SUMMARY")"
scene_checklist_status="$(field_metric transparent_fixture_scene_checklist_status "$SCENE_CHECKLIST")"
scene_harness_check_status="$(field_metric transparent_fixture_scene_harness_check_status "$SCENE_HARNESS_CHECK")"
scene_roles="$(field_metric roles "$SCENE_HARNESS_CHECK")"
acceptance_status="$(field_metric transparent_fixture_acceptance_status "$ACCEPTANCE_CHECK")"
transparent_blocks="$(field_metric transparent_blocks "$ACTIVE_PREFLIGHT_SUMMARY")"
transparent_faces="$(field_metric transparent_faces "$ACTIVE_PREFLIGHT_SUMMARY")"
transparent_draws="$(field_metric transparent_draws "$ACTIVE_PREFLIGHT_SUMMARY")"
transparent_subchunks="$(field_metric transparent_subchunks "$ACTIVE_PREFLIGHT_SUMMARY")"

awk \
  -v active_status="${active_status:-blocked}" \
  -v active_allowed="${active_allowed:-1}" \
  -v active_reason="${active_reason:-unknown}" \
  -v scene_checklist_status="${scene_checklist_status:-missing}" \
  -v scene_harness_check_status="${scene_harness_check_status:-fail}" \
  -v scene_roles="${scene_roles:-0}" \
  -v acceptance_status="${acceptance_status:-fail}" \
  -v transparent_blocks="${transparent_blocks:-0}" \
  -v transparent_faces="${transparent_faces:-0}" \
  -v transparent_draws="${transparent_draws:-0}" \
  -v transparent_subchunks="${transparent_subchunks:-0}" \
  -v active_preflight_summary="$ACTIVE_PREFLIGHT_SUMMARY" \
  -v scene_checklist="$SCENE_CHECKLIST" \
  -v scene_harness_check="$SCENE_HARNESS_CHECK" \
  -v acceptance_check="$ACCEPTANCE_CHECK" '
  BEGIN {
    status = "deferred"
    sort_depth_active_allowed = 0
    reason = "active_transparent_not_available"
    proposed_sort_policy = "chunk_subchunk_back_to_front"
    depth_policy = "opaque_depth_test_then_transparent_depth_test_no_opaque_write_until_proven"
    requires_active_workload = 1
    requires_occlusion_fixture = 1
    requires_collision_solidity_fixture = 1

    if (!(active_status == "deferred" && active_allowed + 0 == 0)) {
      status = "needs_manual_review"
      sort_depth_active_allowed = 1
      reason = "active_path_state_changed"
    } else if (!(scene_checklist_status == "pending_scene_harness" && scene_harness_check_status == "pass" && scene_roles + 0 == 5 && acceptance_status == "pass")) {
      status = "blocked"
      reason = "fixture_scene_contract_not_clean"
    } else if (transparent_blocks + transparent_faces + transparent_draws + transparent_subchunks != 0) {
      status = "needs_manual_review"
      sort_depth_active_allowed = 1
      reason = "transparent_workload_present_without_sort_depth_review"
    }

    printf("transparent_sorting_depth_program status=%s sort_depth_active_allowed=%d reason=%s active_path_status=%s active_path_reason=%s proposed_sort_policy=%s depth_policy=%s scene_checklist_status=%s scene_harness_check_status=%s scene_roles=%d acceptance_status=%s transparent_blocks=%d transparent_faces=%d transparent_draws=%d transparent_subchunks=%d requires_active_workload=%d requires_occlusion_fixture=%d requires_collision_solidity_fixture=%d active_preflight_summary=%s scene_checklist=%s scene_harness_check=%s acceptance_check=%s\n", status, sort_depth_active_allowed, reason, active_status, active_reason, proposed_sort_policy, depth_policy, scene_checklist_status, scene_harness_check_status, scene_roles, acceptance_status, transparent_blocks, transparent_faces, transparent_draws, transparent_subchunks, requires_active_workload, requires_occlusion_fixture, requires_collision_solidity_fixture, active_preflight_summary, scene_checklist, scene_harness_check, acceptance_check)
    if (status == "blocked") {
      exit 1
    }
  }
' > "$SUMMARY_PATH" || {
  cat "$SUMMARY_PATH" >&2 || true
  fail "transparent sorting/depth program failed"
}

cat "$SUMMARY_PATH"
echo "Transparent sorting/depth artifacts: $OUT_DIR"
