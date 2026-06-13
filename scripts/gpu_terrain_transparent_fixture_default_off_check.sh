#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
PACK_PATH="${1:-"$ROOT_DIR/logs/gpu_transparent_fixture_plan/transparent-fixture-pack.txt"}"
case "$PACK_PATH" in
  /*) ;;
  *) PACK_PATH="$ROOT_DIR/$PACK_PATH" ;;
esac
OUT_PATH="${2:-"$(dirname -- "$PACK_PATH")/transparent-fixture-default-off-check.txt"}"
case "$OUT_PATH" in
  /*) ;;
  *) OUT_PATH="$ROOT_DIR/$OUT_PATH" ;;
esac

RUST_SOURCE="$ROOT_DIR/client/rust_ext/src/lib.rs"
MOVEMENT_STRESS="$ROOT_DIR/scripts/gpu_terrain_movement_stress.sh"
CONTRACT_PATH="$ROOT_DIR/docs/GPU_TRANSPARENT_PATH.md"

fail() {
  echo "gpu_terrain_transparent_fixture_default_off_check: $*" >&2
  exit 1
}

relative_path() {
  path="$1"
  case "$path" in
    "$ROOT_DIR"/*) printf '%s\n' "${path#$ROOT_DIR/}" ;;
    *) printf '%s\n' "$path" ;;
  esac
}

resolve_pack_path() {
  path="$1"
  case "$path" in
    /*) printf '%s\n' "$path" ;;
    *) printf '%s\n' "$ROOT_DIR/$path" ;;
  esac
}

line_token() {
  key="$1"
  line="$2"
  printf '%s\n' "$line" | awk -v key="$key" '
    BEGIN { prefix = key "=" }
    {
      for (i = 1; i <= NF; i++) {
        if (index($i, prefix) == 1) {
          print substr($i, length(prefix) + 1)
          exit
        }
      }
    }
  '
}

required_line() {
  file_path="$1"
  pattern="$2"
  line="$(grep -F -- "$pattern" "$file_path" || true)"
  line="$(printf '%s\n' "$line" | sed -n '1p')"
  test -n "$line" || fail "missing line in $(relative_path "$file_path"): $pattern"
  printf '%s\n' "$line"
}

required_value() {
  file_path="$1"
  key="$2"
  line="$(required_line "$file_path" "$key=")"
  value="${line#"$key="}"
  test -n "$value" || fail "missing $key value in $(relative_path "$file_path")"
  printf '%s\n' "$value"
}

required_token() {
  key="$1"
  line="$2"
  row_label="$3"
  value="$(line_token "$key" "$line")"
  test -n "$value" || fail "missing $key in $row_label row: $line"
  printf '%s\n' "$value"
}

require_text() {
  line="$1"
  token="$2"
  row_label="$3"
  printf '%s\n' "$line" | grep -F -- "$token" >/dev/null || fail "$row_label missing $token"
}

test -s "$PACK_PATH" || fail "missing transparent fixture pack $PACK_PATH"
test -s "$RUST_SOURCE" || fail "missing Rust source $RUST_SOURCE"
test -s "$MOVEMENT_STRESS" || fail "missing movement stress script $MOVEMENT_STRESS"
test -s "$CONTRACT_PATH" || fail "missing transparent contract $CONTRACT_PATH"
mkdir -p "$(dirname -- "$OUT_PATH")"

summary_line="$(required_line "$PACK_PATH" "summary transparent_fixture_pack_status=")"
acceptance_steps_line="$(required_line "$PACK_PATH" "acceptance_steps=acceptance_check/report_refresh")"
runtime_line="$(required_line "$PACK_PATH" "runtime_behavior=unchanged")"
ordinary_line="$(required_line "$PACK_PATH" "ordinary_world_visibility=absent")"

pack_status="$(required_token "transparent_fixture_pack_status" "$summary_line" "pack summary")"
acceptance_status="$(required_token "transparent_fixture_acceptance_status" "$summary_line" "pack summary")"
report_check_status="$(required_token "transparent_fixture_report_check_status" "$summary_line" "pack summary")"
check_status="$(required_token "transparent_fixture_check_status" "$summary_line" "pack summary")"
scene_check_status="$(required_token "transparent_fixture_scene_harness_check_status" "$summary_line" "pack summary")"
plan_status="$(required_token "fixture_plan_status" "$summary_line" "pack summary")"
harness_status="$(required_token "transparent_fixture_harness_status" "$summary_line" "pack summary")"
env_expected="$(required_token "env_on_expected" "$summary_line" "pack summary")"
overlay_env_expected="$(required_token "overlay_env_on_expected" "$summary_line" "pack summary")"
overlay_metadata_expected="$(required_token "overlay_metadata_expected" "$summary_line" "pack summary")"

test "$pack_status" = "pass" || fail "unexpected transparent_fixture_pack_status=$pack_status"
test "$acceptance_status" = "pass" || fail "unexpected transparent_fixture_acceptance_status=$acceptance_status"
test "$report_check_status" = "pass" || fail "unexpected transparent_fixture_report_check_status=$report_check_status"
test "$check_status" = "pass" || fail "unexpected transparent_fixture_check_status=$check_status"
test "$scene_check_status" = "pass" || fail "unexpected transparent_fixture_scene_harness_check_status=$scene_check_status"
test "$plan_status" = "pending_fixture_harness" || fail "unexpected fixture_plan_status=$plan_status"
test "$harness_status" = "placeholder" || fail "unexpected transparent_fixture_harness_status=$harness_status"
test "$env_expected" = "1/0/1" || fail "unexpected env_on_expected=$env_expected"
test "$overlay_env_expected" = "1/0/1" || fail "unexpected overlay_env_on_expected=$overlay_env_expected"
test "$overlay_metadata_expected" = "5/5" || fail "unexpected overlay_metadata_expected=$overlay_metadata_expected"
test "${acceptance_steps_line#acceptance_steps=}" = "acceptance_check/report_refresh" || fail "unexpected acceptance steps"
test "${runtime_line#runtime_behavior=}" = "unchanged" || fail "unexpected runtime behavior"
test "${ordinary_line#ordinary_world_visibility=}" = "absent" || fail "unexpected ordinary-world visibility"

acceptance_check_path="$(resolve_pack_path "$(required_value "$PACK_PATH" "acceptance_check")")"
smoke_plan_path="$(resolve_pack_path "$(required_value "$PACK_PATH" "smoke_plan")")"
scene_harness_check_path="$(resolve_pack_path "$(required_value "$PACK_PATH" "scene_harness_check")")"

test -s "$acceptance_check_path" || fail "missing acceptance check $(relative_path "$acceptance_check_path")"
test -s "$smoke_plan_path" || fail "missing smoke plan $(relative_path "$smoke_plan_path")"
test -s "$scene_harness_check_path" || fail "missing scene harness check $(relative_path "$scene_harness_check_path")"

acceptance_summary_line="$(required_line "$acceptance_check_path" "summary transparent_fixture_acceptance_status=")"
acceptance_summary_status="$(required_token "transparent_fixture_acceptance_status" "$acceptance_summary_line" "acceptance summary")"
acceptance_env_expected="$(required_token "env_on_expected" "$acceptance_summary_line" "acceptance summary")"
acceptance_overlay_env_expected="$(required_token "overlay_env_on_expected" "$acceptance_summary_line" "acceptance summary")"
acceptance_overlay_metadata_expected="$(required_token "overlay_metadata_expected" "$acceptance_summary_line" "acceptance summary")"
test "$acceptance_summary_status" = "pass" || fail "unexpected acceptance summary status=$acceptance_summary_status"
test "$acceptance_env_expected" = "$env_expected" || fail "acceptance env_on_expected does not match pack"
test "$acceptance_overlay_env_expected" = "$overlay_env_expected" || fail "acceptance overlay_env_on_expected does not match pack"
test "$acceptance_overlay_metadata_expected" = "$overlay_metadata_expected" || fail "acceptance overlay_metadata_expected does not match pack"

smoke_env_on_line="$(required_line "$smoke_plan_path" "step=env_on_fallback_current status=required")"
smoke_overlay_metadata_line="$(required_line "$smoke_plan_path" "step=client_overlay_metadata status=required")"
smoke_future_workload_line="$(required_line "$smoke_plan_path" "step=future_workload_markers status=blocked_until_fixture")"
smoke_future_active_line="$(required_line "$smoke_plan_path" "step=future_active_gate status=blocked_until_implementation")"
for token in transparent_requested=1 transparent_active=0 transparent_fallback=1 transparent_fixture_overlay_requested=1 transparent_fixture_overlay_active=0 transparent_fixture_overlay_fallback=1 transparent_blocks=0 transparent_faces=0 transparent_draws=0 transparent_subchunks=0 gpu_upload_fail=0 smoke_err=0 terrain_samples=nonzero; do
  require_text "$smoke_env_on_line" "$token" "smoke env-on fallback gate"
done
for token in overlay_id=transparent_test_glass transparent_fixture_overlay_roles=5 transparent_fixture_overlay_blocks=5 geometry_active=0 chunk_data_mutation=no; do
  require_text "$smoke_overlay_metadata_line" "$token" "smoke overlay metadata gate"
done
for token in transparent_blocks=pending transparent_faces=pending transparent_draws=pending transparent_subchunks=pending; do
  require_text "$smoke_future_workload_line" "$token" "smoke future workload gate"
done
for token in transparent_active=1 transparent_fallback=0 gpu_upload_fail=0 opaque_depth_occlusion=required collision_solidity=required opaque_adjacent_faces_visible=required; do
  require_text "$smoke_future_active_line" "$token" "smoke future active gate"
done

required_line "$scene_harness_check_path" "future_gates=blocked_until_implementation" >/dev/null
required_line "$scene_harness_check_path" "workload_gates=blocked_until_fixture" >/dev/null
required_line "$scene_harness_check_path" "non_goals shader_alpha=no transparent_pass=no sorting=no block_id=no asset=no protocol=no storage=no worldgen=no" >/dev/null

required_line "$RUST_SOURCE" "const GPU_TERRAIN_TRANSPARENT_ENV: &str = \"RUMPELMC_GPU_TERRAIN_TRANSPARENT\";" >/dev/null
required_line "$RUST_SOURCE" "const GPU_TERRAIN_TRANSPARENT_FIXTURE_OVERLAY_ENV: &str =" >/dev/null
required_line "$RUST_SOURCE" "\"RUMPELMC_GPU_TERRAIN_TRANSPARENT_FIXTURE_OVERLAY\";" >/dev/null
required_line "$RUST_SOURCE" "const GPU_TERRAIN_TRANSPARENT_IMPLEMENTED: bool = false;" >/dev/null
required_line "$RUST_SOURCE" "gpu_terrain_transparent_active_decision(" >/dev/null
required_line "$RUST_SOURCE" "GPU_TERRAIN_TRANSPARENT_IMPLEMENTED," >/dev/null
required_line "$RUST_SOURCE" "fn gpu_terrain_transparent_requested_decision(env_state: Option<bool>) -> bool {" >/dev/null
required_line "$RUST_SOURCE" "fn gpu_terrain_transparent_active_decision(requested: bool, implementation_ready: bool) -> bool {" >/dev/null
required_line "$RUST_SOURCE" "requested && implementation_ready" >/dev/null
required_line "$RUST_SOURCE" "fn gpu_terrain_transparent_fallback_decision(requested: bool, active: bool) -> bool {" >/dev/null
required_line "$RUST_SOURCE" "requested && !active" >/dev/null
required_line "$RUST_SOURCE" "fn gpu_transparent_gate_stays_disabled_until_implemented()" >/dev/null
required_line "$RUST_SOURCE" "assert!(!gpu_terrain_transparent_active_decision(true, false));" >/dev/null
required_line "$RUST_SOURCE" "assert!(gpu_terrain_transparent_fallback_decision(true, false));" >/dev/null
required_line "$RUST_SOURCE" "fn gpu_terrain_transparent_fixture_overlay_requested_decision(env_state: Option<bool>) -> bool {" >/dev/null
required_line "$RUST_SOURCE" "fn gpu_terrain_transparent_fixture_overlay_active_decision(" >/dev/null
required_line "$RUST_SOURCE" "fn gpu_terrain_transparent_fixture_overlay_fallback_decision(" >/dev/null
required_line "$RUST_SOURCE" "assert!(!gpu_terrain_transparent_fixture_overlay_active_decision(" >/dev/null
required_line "$RUST_SOURCE" "assert!(gpu_terrain_transparent_fixture_overlay_fallback_decision(" >/dev/null
required_line "$RUST_SOURCE" "true, false" >/dev/null

required_line "$MOVEMENT_STRESS" "require_transparent_fallback_marker_if_requested()" >/dev/null
required_line "$MOVEMENT_STRESS" "RUMPELMC_GPU_TERRAIN_TRANSPARENT" >/dev/null
required_line "$MOVEMENT_STRESS" "RUMPELMC_GPU_TERRAIN_TRANSPARENT_FIXTURE_OVERLAY" >/dev/null
required_line "$MOVEMENT_STRESS" 'require_metric_eq "$marker_path" "transparent_requested" 1' >/dev/null
required_line "$MOVEMENT_STRESS" 'require_metric_eq "$marker_path" "transparent_active" 0' >/dev/null
required_line "$MOVEMENT_STRESS" 'require_metric_eq "$marker_path" "transparent_fallback" 1' >/dev/null
required_line "$MOVEMENT_STRESS" 'require_metric_eq "$marker_path" "transparent_fixture_overlay_requested" 1' >/dev/null
required_line "$MOVEMENT_STRESS" 'require_metric_eq "$marker_path" "transparent_fixture_overlay_active" 0' >/dev/null
required_line "$MOVEMENT_STRESS" 'require_metric_eq "$marker_path" "transparent_fixture_overlay_fallback" 1' >/dev/null

required_line "$CONTRACT_PATH" "While \`GPU_TERRAIN_TRANSPARENT_IMPLEMENTED=false\`, the env-on fixture must still report requested-but-fallback markers" >/dev/null
required_line "$CONTRACT_PATH" "transparent_fixture_overlay_requested=1" >/dev/null
required_line "$CONTRACT_PATH" "transparent_fixture_overlay_active=0" >/dev/null
required_line "$CONTRACT_PATH" "transparent_fixture_overlay_fallback=1" >/dev/null
required_line "$CONTRACT_PATH" "No transparent face buffer, alpha blending, sort policy, shader alpha path, Godot transparent material, block ID, atlas asset, or protocol behavior is implemented." >/dev/null

tmp_check="$OUT_PATH.tmp"
trap 'rm -f "$tmp_check"' EXIT
{
  printf 'GPU terrain transparent fixture default-off check\n'
  printf 'pack=%s\n' "$(relative_path "$PACK_PATH")"
  printf 'acceptance_check=%s\n' "$(relative_path "$acceptance_check_path")"
  printf 'smoke_plan=%s\n' "$(relative_path "$smoke_plan_path")"
  printf 'scene_harness_check=%s\n' "$(relative_path "$scene_harness_check_path")"
  printf 'rust_source=%s\n' "$(relative_path "$RUST_SOURCE")"
  printf 'movement_stress=%s\n' "$(relative_path "$MOVEMENT_STRESS")"
  printf 'contract=%s\n' "$(relative_path "$CONTRACT_PATH")"
  printf 'transparent_implementation_gate=false\n'
  printf 'runtime_behavior=unchanged\n'
  printf 'ordinary_world_visibility=absent\n'
  printf 'transparent_fixture_overlay_default=0/0/0\n'
  printf 'env_on_expected=%s\n' "$env_expected"
  printf 'overlay_env_on_expected=%s\n' "$overlay_env_expected"
  printf 'overlay_metadata_expected=%s\n' "$overlay_metadata_expected"
  printf 'future_active_expected=1/0/0\n'
  printf 'future_gates=blocked_until_implementation\n'
  printf 'workload_gates=blocked_until_fixture\n'
  printf 'non_goals shader_alpha=no transparent_pass=no sorting=no block_id=no asset=no protocol=no storage=no worldgen=no\n'
  printf 'summary transparent_fixture_default_off_status=pass transparent_fixture_acceptance_status=%s transparent_implementation_gate=false env_on_expected=%s overlay_env_on_expected=%s overlay_metadata_expected=%s future_active_expected=1/0/0\n' \
    "$acceptance_status" \
    "$env_expected" \
    "$overlay_env_expected" \
    "$overlay_metadata_expected"
} > "$tmp_check"

mv "$tmp_check" "$OUT_PATH"
cat "$OUT_PATH"
