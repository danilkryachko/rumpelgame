#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/transparent_active_path_preflight"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

SUMMARY_PATH="$OUT_DIR/transparent-active-path-preflight-summary.txt"
PACK_SUMMARY="${RUMPELMC_TRANSPARENT_ACTIVE_PACK_SUMMARY:-"$ROOT_DIR/logs/gpu_transparent_fixture_plan/transparent-fixture-pack.txt"}"
SCENE_SMOKE_SUMMARY="${RUMPELMC_TRANSPARENT_ACTIVE_SCENE_SMOKE_SUMMARY:-"$ROOT_DIR/logs/gpu_transparent_fixture_scene_smoke/transparent-fixture-scene-smoke-summary.txt"}"
DEFAULT_OFF_SUMMARY="${RUMPELMC_TRANSPARENT_ACTIVE_DEFAULT_OFF_SUMMARY:-"$ROOT_DIR/logs/gpu_transparent_fixture_plan/transparent-fixture-default-off-check.txt"}"
FINAL_REPORT_SUMMARY="${RUMPELMC_TRANSPARENT_ACTIVE_FINAL_REPORT_SUMMARY:-"$ROOT_DIR/logs/gpu_transparent_fixture_plan/transparent-fixture-final-report-check.txt"}"
RUST_SOURCE="${RUMPELMC_TRANSPARENT_ACTIVE_RUST_SOURCE:-"$ROOT_DIR/client/rust_ext/src/lib.rs"}"

mkdir -p "$OUT_DIR"

fail() {
  echo "transparent_active_path_preflight: $*" >&2
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
test -s "$SCENE_SMOKE_SUMMARY" || fail "missing transparent fixture scene smoke summary $SCENE_SMOKE_SUMMARY"
test -s "$DEFAULT_OFF_SUMMARY" || fail "missing transparent default-off summary $DEFAULT_OFF_SUMMARY"
test -s "$FINAL_REPORT_SUMMARY" || fail "missing transparent final report summary $FINAL_REPORT_SUMMARY"
test -s "$RUST_SOURCE" || fail "missing Rust source $RUST_SOURCE"

if grep -q 'const GPU_TERRAIN_TRANSPARENT_IMPLEMENTED: bool = false;' "$RUST_SOURCE"; then
  implementation_gate="false"
else
  implementation_gate="changed"
fi

pack_status="$(field_metric transparent_fixture_pack_status "$PACK_SUMMARY")"
pack_acceptance_status="$(field_metric transparent_fixture_acceptance_status "$PACK_SUMMARY")"
pack_default_off_status="$(field_metric transparent_fixture_default_off_status "$PACK_SUMMARY")"
pack_final_report_status="$(field_metric transparent_fixture_final_report_check_status "$PACK_SUMMARY")"
pack_scene_gate_status="$(field_metric transparent_fixture_scene_implementation_gate_check_status "$PACK_SUMMARY")"
pack_report_check_status="$(field_metric transparent_fixture_report_check_status "$PACK_SUMMARY")"
pack_env_on_expected="$(field_metric env_on_expected "$PACK_SUMMARY")"
pack_overlay_expected="$(field_metric overlay_env_on_expected "$PACK_SUMMARY")"
pack_overlay_metadata="$(field_metric overlay_metadata_expected "$PACK_SUMMARY")"

scene_status="$(field_metric transparent_fixture_scene_smoke_status "$SCENE_SMOKE_SUMMARY")"
scene_requested="$(field_metric transparent_requested "$SCENE_SMOKE_SUMMARY")"
scene_active="$(field_metric transparent_active "$SCENE_SMOKE_SUMMARY")"
scene_fallback="$(field_metric transparent_fallback "$SCENE_SMOKE_SUMMARY")"
scene_blocks="$(field_metric transparent_blocks "$SCENE_SMOKE_SUMMARY")"
scene_faces="$(field_metric transparent_faces "$SCENE_SMOKE_SUMMARY")"
scene_draws="$(field_metric transparent_draws "$SCENE_SMOKE_SUMMARY")"
scene_subchunks="$(field_metric transparent_subchunks "$SCENE_SMOKE_SUMMARY")"
overlay_requested="$(field_metric transparent_fixture_overlay_requested "$SCENE_SMOKE_SUMMARY")"
overlay_active="$(field_metric transparent_fixture_overlay_active "$SCENE_SMOKE_SUMMARY")"
overlay_fallback="$(field_metric transparent_fixture_overlay_fallback "$SCENE_SMOKE_SUMMARY")"
overlay_roles="$(field_metric transparent_fixture_overlay_roles "$SCENE_SMOKE_SUMMARY")"
overlay_blocks="$(field_metric transparent_fixture_overlay_blocks "$SCENE_SMOKE_SUMMARY")"
scene_upload_fail="$(field_metric gpu_upload_fail "$SCENE_SMOKE_SUMMARY")"

default_off_status="$(field_metric transparent_fixture_default_off_status "$DEFAULT_OFF_SUMMARY")"
default_off_gate="$(field_metric transparent_implementation_gate "$DEFAULT_OFF_SUMMARY")"
final_report_status="$(field_metric transparent_fixture_final_report_check_status "$FINAL_REPORT_SUMMARY")"

awk \
  -v implementation_gate="$implementation_gate" \
  -v pack_status="${pack_status:-fail}" \
  -v pack_acceptance_status="${pack_acceptance_status:-fail}" \
  -v pack_default_off_status="${pack_default_off_status:-fail}" \
  -v pack_final_report_status="${pack_final_report_status:-fail}" \
  -v pack_scene_gate_status="${pack_scene_gate_status:-fail}" \
  -v pack_report_check_status="${pack_report_check_status:-fail}" \
  -v pack_env_on_expected="${pack_env_on_expected:-missing}" \
  -v pack_overlay_expected="${pack_overlay_expected:-missing}" \
  -v pack_overlay_metadata="${pack_overlay_metadata:-missing}" \
  -v scene_status="${scene_status:-fail}" \
  -v scene_requested="${scene_requested:-0}" \
  -v scene_active="${scene_active:-1}" \
  -v scene_fallback="${scene_fallback:-0}" \
  -v scene_blocks="${scene_blocks:-1}" \
  -v scene_faces="${scene_faces:-1}" \
  -v scene_draws="${scene_draws:-1}" \
  -v scene_subchunks="${scene_subchunks:-1}" \
  -v overlay_requested="${overlay_requested:-0}" \
  -v overlay_active="${overlay_active:-1}" \
  -v overlay_fallback="${overlay_fallback:-0}" \
  -v overlay_roles="${overlay_roles:-0}" \
  -v overlay_blocks="${overlay_blocks:-0}" \
  -v scene_upload_fail="${scene_upload_fail:-1}" \
  -v default_off_status="${default_off_status:-fail}" \
  -v default_off_gate="${default_off_gate:-true}" \
  -v final_report_status="${final_report_status:-fail}" \
  -v pack_summary="$PACK_SUMMARY" \
  -v scene_smoke_summary="$SCENE_SMOKE_SUMMARY" \
  -v default_off_summary="$DEFAULT_OFF_SUMMARY" \
  -v final_report_summary="$FINAL_REPORT_SUMMARY" '
  BEGIN {
    status = "deferred"
    active_path_allowed = 0
    reason = "implementation_gate_false"
    requires_material_identity = 1
    requires_sort_policy = 1
    requires_depth_collision_gate = 1
    requires_external_profiler = 1

    pack_ok = pack_status == "pass" && pack_acceptance_status == "pass" && pack_default_off_status == "pass" && pack_final_report_status == "pass" && pack_scene_gate_status == "pass" && pack_report_check_status == "pass" && pack_env_on_expected == "1/0/1" && pack_overlay_expected == "1/0/1" && pack_overlay_metadata == "5/5"
    scene_ok = scene_status == "pass" && scene_requested + 0 == 1 && scene_active + 0 == 0 && scene_fallback + 0 == 1 && scene_blocks + 0 == 0 && scene_faces + 0 == 0 && scene_draws + 0 == 0 && scene_subchunks + 0 == 0 && overlay_requested + 0 == 1 && overlay_active + 0 == 0 && overlay_fallback + 0 == 1 && overlay_roles + 0 == 5 && overlay_blocks + 0 == 5 && scene_upload_fail + 0 == 0
    default_off_ok = default_off_status == "pass" && default_off_gate == "false"

    if (!pack_ok) {
      status = "blocked"
      reason = "fixture_pack_not_clean"
    } else if (!scene_ok) {
      status = "blocked"
      reason = "scene_smoke_fallback_not_clean"
    } else if (!default_off_ok || final_report_status != "pass") {
      status = "blocked"
      reason = "default_off_or_report_not_clean"
    } else if (implementation_gate != "false") {
      status = "needs_manual_review"
      active_path_allowed = 1
      reason = "implementation_gate_changed_requires_active_fixture_review"
    }

    printf("transparent_active_path_preflight status=%s active_path_allowed=%d reason=%s implementation_gate=%s fixture_pack_status=%s scene_smoke_status=%s default_off_status=%s final_report_status=%s transparent_requested=%d transparent_active=%d transparent_fallback=%d transparent_blocks=%d transparent_faces=%d transparent_draws=%d transparent_subchunks=%d transparent_fixture_overlay_requested=%d transparent_fixture_overlay_active=%d transparent_fixture_overlay_fallback=%d transparent_fixture_overlay_roles=%d transparent_fixture_overlay_blocks=%d gpu_upload_fail=%d requires_material_identity=%d requires_sort_policy=%d requires_depth_collision_gate=%d requires_external_profiler=%d pack_summary=%s scene_smoke_summary=%s default_off_summary=%s final_report_summary=%s\n", status, active_path_allowed, reason, implementation_gate, pack_status, scene_status, default_off_status, final_report_status, scene_requested, scene_active, scene_fallback, scene_blocks, scene_faces, scene_draws, scene_subchunks, overlay_requested, overlay_active, overlay_fallback, overlay_roles, overlay_blocks, scene_upload_fail, requires_material_identity, requires_sort_policy, requires_depth_collision_gate, requires_external_profiler, pack_summary, scene_smoke_summary, default_off_summary, final_report_summary)
    if (status == "blocked") {
      exit 1
    }
  }
' > "$SUMMARY_PATH" || {
  cat "$SUMMARY_PATH" >&2 || true
  fail "transparent active path preflight failed"
}

cat "$SUMMARY_PATH"
echo "Transparent active path artifacts: $OUT_DIR"
