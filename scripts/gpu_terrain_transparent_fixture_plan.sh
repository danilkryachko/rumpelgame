#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
CONTRACT_PATH="${1:-"$ROOT_DIR/docs/GPU_TRANSPARENT_PATH.md"}"
case "$CONTRACT_PATH" in
  /*) ;;
  *) CONTRACT_PATH="$ROOT_DIR/$CONTRACT_PATH" ;;
esac
OUT_PATH="${2:-"$ROOT_DIR/logs/gpu_transparent_fixture_plan/transparent-fixture-plan.txt"}"
case "$OUT_PATH" in
  /*) ;;
  *) OUT_PATH="$ROOT_DIR/$OUT_PATH" ;;
esac

FALLBACK_SCRIPT="$ROOT_DIR/scripts/gpu_terrain_movement_stress.sh"

fail() {
  echo "gpu_terrain_transparent_fixture_plan: $*" >&2
  exit 1
}

relative_path() {
  path="$1"
  case "$path" in
    "$ROOT_DIR"/*) printf '%s\n' "${path#$ROOT_DIR/}" ;;
    *) printf '%s\n' "$path" ;;
  esac
}

require_token() {
  file_path="$1"
  token="$2"
  grep -F -- "$token" "$file_path" >/dev/null || fail "missing token in $(relative_path "$file_path"): $token"
}

test -s "$CONTRACT_PATH" || fail "missing transparent contract $CONTRACT_PATH"
test -s "$FALLBACK_SCRIPT" || fail "missing fallback guard script $FALLBACK_SCRIPT"
mkdir -p "$(dirname -- "$OUT_PATH")"

contract_tokens='
## First Fixture Contract
transparent_test_glass
gpu-transparent-depth-collision
render_class=transparent
solid=true
Render opacity and collision solidity must stay separate
Opaque faces next to transparent fixture blocks must remain visible
fixed camera, fixed light setup, and fixed fixture chunk coordinates
transparent_blocks
transparent_faces
transparent_draws
transparent_subchunks
GPU_TERRAIN_TRANSPARENT_IMPLEMENTED=false
transparent_requested=1
transparent_active=0
transparent_fallback=1
transparent_fixture_overlay_requested=1
transparent_fixture_overlay_active=0
transparent_fixture_overlay_fallback=1
transparent_fixture_overlay_roles
transparent_fixture_overlay_blocks
transparent_active=1
transparent_fallback=0
gpu_upload_fail=0
No new production block ID
No change to default opaque terrain rendering
'

token_count=0
printf '%s\n' "$contract_tokens" | while IFS= read -r token; do
  test -n "$token" || continue
  require_token "$CONTRACT_PATH" "$token"
done
token_count="$(printf '%s\n' "$contract_tokens" | awk 'NF { count++ } END { print count + 0 }')"

require_token "$FALLBACK_SCRIPT" "require_transparent_fallback_marker_if_requested"
require_token "$FALLBACK_SCRIPT" 'require_metric_eq "$marker_path" "transparent_requested" 1'
require_token "$FALLBACK_SCRIPT" 'require_metric_eq "$marker_path" "transparent_active" 0'
require_token "$FALLBACK_SCRIPT" 'require_metric_eq "$marker_path" "transparent_fallback" 1'
require_token "$FALLBACK_SCRIPT" 'require_metric_eq "$marker_path" "transparent_fixture_overlay_requested" 1'
require_token "$FALLBACK_SCRIPT" 'require_metric_eq "$marker_path" "transparent_fixture_overlay_active" 0'
require_token "$FALLBACK_SCRIPT" 'require_metric_eq "$marker_path" "transparent_fixture_overlay_fallback" 1'

tmp_plan="$OUT_PATH.tmp"
trap 'rm -f "$tmp_plan"' EXIT

{
  printf 'GPU terrain transparent fixture plan\n'
  printf 'contract=%s\n' "$(relative_path "$CONTRACT_PATH")"
  printf 'fallback_guard=%s\n' "$(relative_path "$FALLBACK_SCRIPT")"
  printf 'fixture=gpu-transparent-depth-collision\n'
  printf 'material=transparent_test_glass\n'
  printf 'fixture_status=contract_only\n'
  printf 'runtime_behavior=unchanged\n'
  printf 'ordinary_world_visibility=absent\n'
  printf 'opaque_path_rollback=required\n'
  printf 'step=contract_guard status=present required_tokens=%s\n' "$token_count"
  printf 'step=env_off_gate status=required expected=ordinary_opaque_markers_unchanged\n'
  printf 'step=env_on_fallback_gate status=current_expected transparent_requested=1 transparent_active=0 transparent_fallback=1 transparent_fixture_overlay_requested=1 transparent_fixture_overlay_active=0 transparent_fixture_overlay_fallback=1 transparent_blocks=0 transparent_faces=0 transparent_draws=0 transparent_subchunks=0\n'
  printf 'step=client_overlay_metadata status=planned overlay_id=transparent_test_glass transparent_fixture_overlay_roles=5 transparent_fixture_overlay_blocks=5 geometry_active=0 chunk_data_mutation=no\n'
  printf 'step=future_workload_markers status=required transparent_blocks=blocked_until_fixture transparent_faces=blocked_until_fixture transparent_draws=blocked_until_fixture transparent_subchunks=blocked_until_fixture\n'
  printf 'step=future_active_gate status=blocked_until_implementation transparent_active=1 transparent_fallback=0 gpu_upload_fail=0\n'
  printf 'step=non_goals status=enforced shader_alpha=no transparent_pass=no sorting=no block_id=no asset=no protocol=no storage=no worldgen=no\n'
  printf 'command_generate_plan=sh scripts/gpu_terrain_transparent_fixture_plan.sh %s %s\n' \
    "$(relative_path "$CONTRACT_PATH")" \
    "$(relative_path "$OUT_PATH")"
  printf 'command_env_on_fallback=RUMPELMC_GPU_TERRAIN_TRANSPARENT=1 RUMPELMC_GPU_TERRAIN_TRANSPARENT_FIXTURE_OVERLAY=1 sh scripts/gpu_terrain_movement_stress.sh logs/gpu_transparent_fixture_fallback_capture\n'
  printf 'summary fixture_plan_status=contract_ready contract_tokens=%s fallback_guard=present\n' "$token_count"
} > "$tmp_plan"

mv "$tmp_plan" "$OUT_PATH"
cat "$OUT_PATH"
