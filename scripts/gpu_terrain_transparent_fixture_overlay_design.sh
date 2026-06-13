#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
CONTRACT_PATH="${1:-"$ROOT_DIR/docs/GPU_TRANSPARENT_PATH.md"}"
case "$CONTRACT_PATH" in
  /*) ;;
  *) CONTRACT_PATH="$ROOT_DIR/$CONTRACT_PATH" ;;
esac
OUT_PATH="${2:-"$ROOT_DIR/logs/gpu_transparent_fixture_plan/transparent-fixture-overlay-design.txt"}"
case "$OUT_PATH" in
  /*) ;;
  *) OUT_PATH="$ROOT_DIR/$OUT_PATH" ;;
esac

fail() {
  echo "gpu_terrain_transparent_fixture_overlay_design: $*" >&2
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
mkdir -p "$(dirname -- "$OUT_PATH")"

design_tokens='
## Client-Only Fixture Overlay Design
smoke-only overlay contract
overlay_id=transparent_test_glass
fixture=gpu-transparent-depth-collision
RUMPELMC_GPU_TERRAIN_TRANSPARENT_FIXTURE_OVERLAY=1
transparent_fixture_overlay_requested
transparent_fixture_overlay_active
transparent_fixture_overlay_fallback
transparent_fixture_overlay_roles
transparent_fixture_overlay_blocks
No `ChunkData` mutation
no `BlockAction` packet
not use a production block ID
not be serialized
stored in RocksDB/PostgreSQL
included in world generation
No atlas asset, shader alpha, blending, sorting, or transparent pass
'

printf '%s\n' "$design_tokens" | while IFS= read -r token; do
  test -n "$token" || continue
  require_token "$CONTRACT_PATH" "$token"
done
token_count="$(printf '%s\n' "$design_tokens" | awk 'NF { count++ } END { print count + 0 }')"

tmp_design="$OUT_PATH.tmp"
trap 'rm -f "$tmp_design"' EXIT
{
  printf 'GPU terrain transparent fixture overlay design\n'
  printf 'contract=%s\n' "$(relative_path "$CONTRACT_PATH")"
  printf 'fixture=gpu-transparent-depth-collision\n'
  printf 'overlay_id=transparent_test_glass\n'
  printf 'overlay_status=design_only\n'
  printf 'owner=client_visual_smoke_harness\n'
  printf 'lifetime=one_visual_smoke_run\n'
  printf 'default_overlay_active=0\n'
  printf 'env_gate=RUMPELMC_GPU_TERRAIN_TRANSPARENT_FIXTURE_OVERLAY\n'
  printf 'runtime_behavior=unchanged\n'
  printf 'ordinary_world_visibility=absent\n'
  printf 'storage_behavior=unchanged\n'
  printf 'protocol_behavior=unchanged\n'
  printf 'worldgen_behavior=unchanged\n'
  printf 'chunk_data_mutation=no\n'
  printf 'block_action_packet=no\n'
  printf 'production_block_id=no\n'
  printf 'future_markers=transparent_fixture_overlay_requested/transparent_fixture_overlay_active/transparent_fixture_overlay_fallback/transparent_fixture_overlay_roles/transparent_fixture_overlay_blocks\n'
  printf 'current_transparent_gate=transparent_requested=1 transparent_active=0 transparent_fallback=1 transparent_fixture_overlay_requested=1 transparent_fixture_overlay_active=0 transparent_fixture_overlay_fallback=1 transparent_blocks=0 transparent_faces=0 transparent_draws=0 transparent_subchunks=0\n'
  printf 'non_goals shader_alpha=no transparent_pass=no sorting=no block_id=no asset=no protocol=no storage=no worldgen=no tscn=no generated_files=no\n'
  printf 'summary transparent_fixture_overlay_design_status=pass design_tokens=%s overlay_status=design_only default_overlay_active=0\n' "$token_count"
} > "$tmp_design"

mv "$tmp_design" "$OUT_PATH"
cat "$OUT_PATH"
