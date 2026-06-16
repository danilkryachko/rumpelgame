#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/block_material_metadata_design"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

SUMMARY_PATH="$OUT_DIR/block-material-metadata-design-summary.txt"
DESIGN_DOC="${RUMPELMC_BLOCK_MATERIAL_DESIGN_DOC:-"$ROOT_DIR/docs/BLOCK_MATERIAL_METADATA_DESIGN.md"}"
TRANSPARENT_DOC="${RUMPELMC_BLOCK_MATERIAL_TRANSPARENT_DOC:-"$ROOT_DIR/docs/GPU_TRANSPARENT_PATH.md"}"
PROTOCOL_DOC="${RUMPELMC_BLOCK_MATERIAL_PROTOCOL_DOC:-"$ROOT_DIR/docs/PROTOCOL.md"}"
CLIENT_BLOCKS="${RUMPELMC_BLOCK_MATERIAL_CLIENT_BLOCKS:-"$ROOT_DIR/client/rust_ext/src/blocks.rs"}"
GPU_TERRAIN="${RUMPELMC_BLOCK_MATERIAL_GPU_TERRAIN:-"$ROOT_DIR/client/rust_ext/src/gpu_terrain.rs"}"
SERVER_BLOCKS="${RUMPELMC_BLOCK_MATERIAL_SERVER_BLOCKS:-"$ROOT_DIR/server/pkg/world/blocks.go"}"
TRANSPARENT_ACCEPTANCE="${RUMPELMC_BLOCK_MATERIAL_TRANSPARENT_ACCEPTANCE:-"$ROOT_DIR/logs/transparent_fixture_acceptance_suite_current/transparent-fixture-acceptance-suite-summary.txt"}"

mkdir -p "$OUT_DIR"

fail() {
  echo "block_material_metadata_design_gate: $*" >&2
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

require_pattern() {
  path="$1"
  pattern="$2"
  test -s "$path" || fail "missing file $path"
  grep -Eq "$pattern" "$path" || fail "missing pattern '$pattern' in $path"
}

for path in "$DESIGN_DOC" "$TRANSPARENT_DOC" "$PROTOCOL_DOC" "$CLIENT_BLOCKS" "$GPU_TERRAIN" "$SERVER_BLOCKS" "$TRANSPARENT_ACCEPTANCE"; do
  test -s "$path" || fail "missing required input $path"
done

for token in \
  'render_class' \
  'collision_class' \
  'light_emission' \
  'liquid_policy' \
  'depth_policy' \
  'storage_policy' \
  '`block_id` remains the only wire/storage identity' \
  'Do not add material fields to `ChunkData.blocks`' \
  'No new block IDs'; do
  require_token "$DESIGN_DOC" "$token"
done

for token in \
  "Render opacity and collision solidity must stay separate" \
  "No new production block ID" \
  "transparent_fixture_overlay_roles=5" \
  "GPU_TERRAIN_TRANSPARENT_IMPLEMENTED=false"; do
  require_token "$TRANSPARENT_DOC" "$token"
done

require_token "$PROTOCOL_DOC" "Block IDs are serialized as unsigned 16-bit little-endian values."
require_token "$PROTOCOL_DOC" "Add new fields to existing messages with new field numbers"
require_token "$CLIENT_BLOCKS" "pub struct BlockDefinition"
require_token "$CLIENT_BLOCKS" "pub opaque: bool"
require_token "$CLIENT_BLOCKS" "pub solid: bool"
require_token "$CLIENT_BLOCKS" ".filter(|block| block.solid && block.opaque)"
require_token "$CLIENT_BLOCKS" "pub fn is_opaque_solid"
require_token "$GPU_TERRAIN" ".filter(|block| blocks::is_opaque_solid(block.id))"
require_token "$GPU_TERRAIN" "frag_color = vec4(texel.rgb * lighting_in, 1.0);"
require_token "$GPU_TERRAIN" "solid_gpu_terrain_fragment_forces_opaque_alpha"
require_token "$SERVER_BLOCKS" "type BlockID uint16"
require_token "$SERVER_BLOCKS" "type BlockDefinition struct"
require_pattern "$SERVER_BLOCKS" '^[[:space:]]+Solid[[:space:]]+bool$'
require_pattern "$SERVER_BLOCKS" '^[[:space:]]+Opaque[[:space:]]+bool$'
require_pattern "$SERVER_BLOCKS" '^[[:space:]]+Placeable[[:space:]]+bool$'
require_token "$SERVER_BLOCKS" "RenderClass"
require_token "$SERVER_BLOCKS" "CollisionClass"
require_token "$SERVER_BLOCKS" "StoragePolicy"

transparent_status="$(field_metric status "$TRANSPARENT_ACCEPTANCE")"
transparent_active_acceptance="$(field_metric active_fixture_acceptance "$TRANSPARENT_ACCEPTANCE")"
transparent_blocks="$(field_metric transparent_blocks "$TRANSPARENT_ACCEPTANCE")"
transparent_faces="$(field_metric transparent_faces "$TRANSPARENT_ACCEPTANCE")"
transparent_draws="$(field_metric transparent_draws "$TRANSPARENT_ACCEPTANCE")"
transparent_subchunks="$(field_metric transparent_subchunks "$TRANSPARENT_ACCEPTANCE")"
transparent_upload_fail="$(field_metric gpu_upload_fail "$TRANSPARENT_ACCEPTANCE")"

client_block_count="$(awk '/^pub const [A-Z_]+: BlockId =/ { count++ } END { print count + 0 }' "$CLIENT_BLOCKS")"
server_block_count="$(awk '/^[[:space:]]*ID:[[:space:]]*(Air|Stone|Dirt|Grass|Wood|Leaves),/ { count++ } END { print count + 0 }' "$SERVER_BLOCKS")"

awk \
  -v transparent_status="${transparent_status:-missing}" \
  -v transparent_active_acceptance="${transparent_active_acceptance:-missing}" \
  -v transparent_blocks="${transparent_blocks:-1}" \
  -v transparent_faces="${transparent_faces:-1}" \
  -v transparent_draws="${transparent_draws:-1}" \
  -v transparent_subchunks="${transparent_subchunks:-1}" \
  -v transparent_upload_fail="${transparent_upload_fail:-1}" \
  -v client_block_count="$client_block_count" \
  -v server_block_count="$server_block_count" \
  -v design_doc="$DESIGN_DOC" \
  -v transparent_acceptance="$TRANSPARENT_ACCEPTANCE" '
  BEGIN {
    status = "pass"
    reason = "ok"
    production_metadata_status = "server_registry_guarded"
    server_material_metadata = "guarded"
    active_schema_change = 0
    current_runtime_contract = "opaque_only"
    migration_gate = "required"
    wire_identity = "block_id_u16"
    client_flags = "solid_opaque_placeable_textures"
    server_flags = "solid_opaque_placeable_material_policies_textures"

    transparent_ok = transparent_status == "pass" &&
      transparent_active_acceptance == "deferred" &&
      transparent_blocks + 0 == 0 &&
      transparent_faces + 0 == 0 &&
      transparent_draws + 0 == 0 &&
      transparent_subchunks + 0 == 0 &&
      transparent_upload_fail + 0 == 0
    registry_ok = client_block_count + 0 >= 6 && server_block_count + 0 >= 6

    if (!registry_ok) {
      status = "fail"
      reason = "block_registry_unexpected"
    } else if (!transparent_ok) {
      status = "fail"
      reason = "transparent_acceptance_not_at_fallback_gate"
    }

    printf("block_material_metadata_design status=%s reason=%s production_metadata_status=%s server_material_metadata=%s active_schema_change=%d current_runtime_contract=%s migration_gate=%s wire_identity=%s client_flags=%s server_flags=%s client_block_count=%d server_block_count=%d transparent_fixture_status=%s transparent_active_acceptance=%s transparent_blocks=%d transparent_faces=%d transparent_draws=%d transparent_subchunks=%d gpu_upload_fail=%d render_classes=air,opaque,cutout,transparent,liquid collision_classes=none,solid,fluid,custom emissive_policy=light_emission_inert_until_lighting_gate design_doc=%s transparent_acceptance=%s\n", status, reason, production_metadata_status, server_material_metadata, active_schema_change, current_runtime_contract, migration_gate, wire_identity, client_flags, server_flags, client_block_count, server_block_count, transparent_status, transparent_active_acceptance, transparent_blocks, transparent_faces, transparent_draws, transparent_subchunks, transparent_upload_fail, design_doc, transparent_acceptance)
    if (status != "pass") {
      exit 1
    }
  }
' > "$SUMMARY_PATH" || {
  cat "$SUMMARY_PATH" >&2 || true
  fail "block material metadata design gate failed"
}

cat "$SUMMARY_PATH"
echo "Block material metadata design artifacts: $OUT_DIR"
