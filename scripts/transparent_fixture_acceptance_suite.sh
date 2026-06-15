#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/transparent_fixture_acceptance_suite"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

SUMMARY_PATH="$OUT_DIR/transparent-fixture-acceptance-suite-summary.txt"
PACK_SUMMARY="${RUMPELMC_TRANSPARENT_ACCEPTANCE_PACK_SUMMARY:-"$ROOT_DIR/logs/gpu_transparent_fixture_plan/transparent-fixture-pack.txt"}"
SCENE_SMOKE_SUMMARY="${RUMPELMC_TRANSPARENT_ACCEPTANCE_SCENE_SMOKE_SUMMARY:-"$ROOT_DIR/logs/gpu_transparent_fixture_scene_smoke/transparent-fixture-scene-smoke-summary.txt"}"
ACTIVE_PREFLIGHT_SUMMARY="${RUMPELMC_TRANSPARENT_ACCEPTANCE_ACTIVE_PREFLIGHT_SUMMARY:-"$ROOT_DIR/logs/transparent_active_path_preflight_current/transparent-active-path-preflight-summary.txt"}"
SORT_DEPTH_SUMMARY="${RUMPELMC_TRANSPARENT_ACCEPTANCE_SORT_DEPTH_SUMMARY:-"$ROOT_DIR/logs/transparent_sorting_depth_program_current/transparent-sorting-depth-summary.txt"}"
ACCEPTANCE_CHECK="${RUMPELMC_TRANSPARENT_ACCEPTANCE_CHECK:-"$ROOT_DIR/logs/gpu_transparent_fixture_plan/transparent-fixture-acceptance-check.txt"}"
DEFAULT_OFF_CHECK="${RUMPELMC_TRANSPARENT_ACCEPTANCE_DEFAULT_OFF_CHECK:-"$ROOT_DIR/logs/gpu_transparent_fixture_plan/transparent-fixture-default-off-check.txt"}"
FINAL_REPORT_CHECK="${RUMPELMC_TRANSPARENT_ACCEPTANCE_FINAL_REPORT_CHECK:-"$ROOT_DIR/logs/gpu_transparent_fixture_plan/transparent-fixture-final-report-check.txt"}"

mkdir -p "$OUT_DIR"

fail() {
  echo "transparent_fixture_acceptance_suite: $*" >&2
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

test -s "$PACK_SUMMARY" || fail "missing transparent fixture pack $PACK_SUMMARY"
test -s "$SCENE_SMOKE_SUMMARY" || fail "missing transparent scene smoke summary $SCENE_SMOKE_SUMMARY"
test -s "$ACTIVE_PREFLIGHT_SUMMARY" || fail "missing transparent active preflight summary $ACTIVE_PREFLIGHT_SUMMARY"
test -s "$SORT_DEPTH_SUMMARY" || fail "missing transparent sort/depth summary $SORT_DEPTH_SUMMARY"
test -s "$ACCEPTANCE_CHECK" || fail "missing transparent acceptance check $ACCEPTANCE_CHECK"
test -s "$DEFAULT_OFF_CHECK" || fail "missing transparent default-off check $DEFAULT_OFF_CHECK"
test -s "$FINAL_REPORT_CHECK" || fail "missing transparent final report check $FINAL_REPORT_CHECK"

pack_status="$(field_metric transparent_fixture_pack_status "$PACK_SUMMARY")"
pack_check_status="$(field_metric transparent_fixture_check_status "$PACK_SUMMARY")"
pack_scene_harness_check_status="$(field_metric transparent_fixture_scene_harness_check_status "$PACK_SUMMARY")"
pack_acceptance_status="$(field_metric transparent_fixture_acceptance_status "$PACK_SUMMARY")"
pack_default_off_status="$(field_metric transparent_fixture_default_off_status "$PACK_SUMMARY")"
pack_final_report_status="$(field_metric transparent_fixture_final_report_check_status "$PACK_SUMMARY")"
pack_scene_gate_status="$(field_metric transparent_fixture_scene_implementation_gate_check_status "$PACK_SUMMARY")"
pack_overlay_metadata="$(field_metric overlay_metadata_expected "$PACK_SUMMARY")"

scene_status="$(field_metric transparent_fixture_scene_smoke_status "$SCENE_SMOKE_SUMMARY")"
scene_requested="$(field_metric transparent_requested "$SCENE_SMOKE_SUMMARY")"
scene_active="$(field_metric transparent_active "$SCENE_SMOKE_SUMMARY")"
scene_fallback="$(field_metric transparent_fallback "$SCENE_SMOKE_SUMMARY")"
scene_blocks="$(field_metric transparent_blocks "$SCENE_SMOKE_SUMMARY")"
scene_faces="$(field_metric transparent_faces "$SCENE_SMOKE_SUMMARY")"
scene_draws="$(field_metric transparent_draws "$SCENE_SMOKE_SUMMARY")"
scene_subchunks="$(field_metric transparent_subchunks "$SCENE_SMOKE_SUMMARY")"
scene_overlay_roles="$(field_metric transparent_fixture_overlay_roles "$SCENE_SMOKE_SUMMARY")"
scene_overlay_blocks="$(field_metric transparent_fixture_overlay_blocks "$SCENE_SMOKE_SUMMARY")"
scene_upload_fail="$(field_metric gpu_upload_fail "$SCENE_SMOKE_SUMMARY")"

active_status="$(field_metric status "$ACTIVE_PREFLIGHT_SUMMARY")"
active_allowed="$(field_metric active_path_allowed "$ACTIVE_PREFLIGHT_SUMMARY")"
active_reason="$(field_metric reason "$ACTIVE_PREFLIGHT_SUMMARY")"
sort_status="$(field_metric status "$SORT_DEPTH_SUMMARY")"
sort_allowed="$(field_metric sort_depth_active_allowed "$SORT_DEPTH_SUMMARY")"
sort_reason="$(field_metric reason "$SORT_DEPTH_SUMMARY")"
sort_roles="$(field_metric scene_roles "$SORT_DEPTH_SUMMARY")"
acceptance_status="$(field_metric transparent_fixture_acceptance_status "$ACCEPTANCE_CHECK")"
default_off_status="$(field_metric transparent_fixture_default_off_status "$DEFAULT_OFF_CHECK")"
final_report_status="$(field_metric transparent_fixture_final_report_check_status "$FINAL_REPORT_CHECK")"

awk \
  -v pack_status="${pack_status:-fail}" \
  -v pack_check_status="${pack_check_status:-fail}" \
  -v pack_scene_harness_check_status="${pack_scene_harness_check_status:-fail}" \
  -v pack_acceptance_status="${pack_acceptance_status:-fail}" \
  -v pack_default_off_status="${pack_default_off_status:-fail}" \
  -v pack_final_report_status="${pack_final_report_status:-fail}" \
  -v pack_scene_gate_status="${pack_scene_gate_status:-fail}" \
  -v pack_overlay_metadata="${pack_overlay_metadata:-missing}" \
  -v scene_status="${scene_status:-fail}" \
  -v scene_requested="${scene_requested:-0}" \
  -v scene_active="${scene_active:-1}" \
  -v scene_fallback="${scene_fallback:-0}" \
  -v scene_blocks="${scene_blocks:-1}" \
  -v scene_faces="${scene_faces:-1}" \
  -v scene_draws="${scene_draws:-1}" \
  -v scene_subchunks="${scene_subchunks:-1}" \
  -v scene_overlay_roles="${scene_overlay_roles:-0}" \
  -v scene_overlay_blocks="${scene_overlay_blocks:-0}" \
  -v scene_upload_fail="${scene_upload_fail:-1}" \
  -v active_status="${active_status:-blocked}" \
  -v active_allowed="${active_allowed:-1}" \
  -v active_reason="${active_reason:-unknown}" \
  -v sort_status="${sort_status:-blocked}" \
  -v sort_allowed="${sort_allowed:-1}" \
  -v sort_reason="${sort_reason:-unknown}" \
  -v sort_roles="${sort_roles:-0}" \
  -v acceptance_status="${acceptance_status:-fail}" \
  -v default_off_status="${default_off_status:-fail}" \
  -v final_report_status="${final_report_status:-fail}" \
  -v pack_summary="$PACK_SUMMARY" \
  -v scene_smoke_summary="$SCENE_SMOKE_SUMMARY" \
  -v active_preflight_summary="$ACTIVE_PREFLIGHT_SUMMARY" \
  -v sort_depth_summary="$SORT_DEPTH_SUMMARY" \
  -v acceptance_check="$ACCEPTANCE_CHECK" \
  -v default_off_check="$DEFAULT_OFF_CHECK" \
  -v final_report_check="$FINAL_REPORT_CHECK" '
  BEGIN {
    status = "pass"
    reason = "ok"
    current_fallback_acceptance = "pass"
    active_fixture_acceptance = "deferred"
    active_fixture_reason = active_reason

    pack_ok = pack_status == "pass" && pack_check_status == "pass" && pack_scene_harness_check_status == "pass" && pack_acceptance_status == "pass" && pack_default_off_status == "pass" && pack_final_report_status == "pass" && pack_scene_gate_status == "pass" && pack_overlay_metadata == "5/5"
    scene_ok = scene_status == "pass" && scene_requested + 0 == 1 && scene_active + 0 == 0 && scene_fallback + 0 == 1 && scene_blocks + 0 == 0 && scene_faces + 0 == 0 && scene_draws + 0 == 0 && scene_subchunks + 0 == 0 && scene_overlay_roles + 0 == 5 && scene_overlay_blocks + 0 == 5 && scene_upload_fail + 0 == 0
    active_deferred_ok = active_status == "deferred" && active_allowed + 0 == 0
    sort_deferred_ok = sort_status == "deferred" && sort_allowed + 0 == 0 && sort_roles + 0 == 5

    if (!pack_ok) {
      status = "fail"
      reason = "fixture_pack_not_clean"
    } else if (!scene_ok) {
      status = "fail"
      reason = "scene_smoke_not_clean"
    } else if (!active_deferred_ok) {
      status = "fail"
      reason = "active_preflight_not_deferred"
    } else if (!sort_deferred_ok) {
      status = "fail"
      reason = "sorting_depth_not_deferred"
    } else if (!(acceptance_status == "pass" && default_off_status == "pass" && final_report_status == "pass")) {
      status = "fail"
      reason = "acceptance_default_or_report_not_clean"
    }

    printf("transparent_fixture_acceptance_suite status=%s reason=%s current_fallback_acceptance=%s active_fixture_acceptance=%s active_fixture_reason=%s sort_depth_status=%s sort_depth_reason=%s fixture_pack_status=%s scene_smoke_status=%s acceptance_status=%s default_off_status=%s final_report_status=%s transparent_requested=%d transparent_active=%d transparent_fallback=%d transparent_blocks=%d transparent_faces=%d transparent_draws=%d transparent_subchunks=%d overlay_roles=%d overlay_blocks=%d gpu_upload_fail=%d pack_summary=%s scene_smoke_summary=%s active_preflight_summary=%s sort_depth_summary=%s acceptance_check=%s default_off_check=%s final_report_check=%s\n", status, reason, current_fallback_acceptance, active_fixture_acceptance, active_fixture_reason, sort_status, sort_reason, pack_status, scene_status, acceptance_status, default_off_status, final_report_status, scene_requested, scene_active, scene_fallback, scene_blocks, scene_faces, scene_draws, scene_subchunks, scene_overlay_roles, scene_overlay_blocks, scene_upload_fail, pack_summary, scene_smoke_summary, active_preflight_summary, sort_depth_summary, acceptance_check, default_off_check, final_report_check)
    if (status != "pass") {
      exit 1
    }
  }
' > "$SUMMARY_PATH" || {
  cat "$SUMMARY_PATH" >&2 || true
  fail "transparent fixture acceptance suite failed"
}

cat "$SUMMARY_PATH"
echo "Transparent fixture acceptance suite artifacts: $OUT_DIR"
