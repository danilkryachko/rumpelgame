#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/block_material_registry_foundation"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

SUMMARY_PATH="$OUT_DIR/block-material-registry-foundation-summary.txt"
RAW_SUMMARY_PATH="$OUT_DIR/block-material-registry-matrix-raw.txt"
MATRIX_CMD="${RUMPELMC_BLOCK_MATERIAL_REGISTRY_MATRIX_CMD:-"$ROOT_DIR/server/cmd/block_material_registry_matrix/main.go"}"
SERVER_BLOCKS="${RUMPELMC_BLOCK_MATERIAL_REGISTRY_SERVER_BLOCKS:-"$ROOT_DIR/server/pkg/world/blocks.go"}"
SERVER_BLOCKS_TEST="${RUMPELMC_BLOCK_MATERIAL_REGISTRY_SERVER_BLOCKS_TEST:-"$ROOT_DIR/server/pkg/world/blocks_test.go"}"
DESIGN_DOC="${RUMPELMC_BLOCK_MATERIAL_REGISTRY_DESIGN_DOC:-"$ROOT_DIR/docs/BLOCK_MATERIAL_METADATA_DESIGN.md"}"
PROTOCOL_DOC="${RUMPELMC_BLOCK_MATERIAL_REGISTRY_PROTOCOL_DOC:-"$ROOT_DIR/docs/PROTOCOL.md"}"
EXPECTED_HASH="${RUMPELMC_BLOCK_MATERIAL_REGISTRY_EXPECTED_HASH:-5f6e32de12b5baa99a11d61d985f52fa7c4d5061090d91f82c1744e1c47ba21e}"
RUN_GO_TESTS="${RUMPELMC_BLOCK_MATERIAL_REGISTRY_RUN_GO_TESTS:-1}"

mkdir -p "$OUT_DIR"

fail() {
  echo "block_material_registry_foundation_gate: $*" >&2
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

for path in "$MATRIX_CMD" "$SERVER_BLOCKS" "$SERVER_BLOCKS_TEST" "$DESIGN_DOC" "$PROTOCOL_DOC"; do
  test -s "$path" || fail "missing required input $path"
done

require_token "$MATRIX_CMD" "block_material_registry_matrix status=pass"
require_token "$MATRIX_CMD" "active_protocol_change=0"
require_token "$SERVER_BLOCKS" "type RenderClass string"
require_token "$SERVER_BLOCKS" "RenderClassOpaque"
require_token "$SERVER_BLOCKS" "type CollisionClass string"
require_token "$SERVER_BLOCKS" "type OcclusionClass string"
require_token "$SERVER_BLOCKS" "type ShadowPolicy string"
require_token "$SERVER_BLOCKS" "type DepthPolicy string"
require_token "$SERVER_BLOCKS" "type StoragePolicy string"
require_token "$SERVER_BLOCKS" "type LiquidPolicy string"
require_token "$SERVER_BLOCKS" "type SortPolicy string"
require_token "$SERVER_BLOCKS" "MiningDurationMS"
require_token "$SERVER_BLOCKS" "func BlockDefinitions"
require_token "$SERVER_BLOCKS" "func IsOpaqueSolid"
require_token "$SERVER_BLOCKS_TEST" "TestBlockDefinitionsAreStableOrderedCopy"
require_token "$SERVER_BLOCKS_TEST" "TestBlockMaterialIdentityRowsAreStable"
require_token "$SERVER_BLOCKS_TEST" "TestCurrentNetworkedBlocksPreserveOpaqueSolidMaterialContract"
require_token "$SERVER_BLOCKS_TEST" "TestUnknownBlockMaterialHelpersAreConservative"
require_token "$DESIGN_DOC" "server material registry foundation"
require_token "$DESIGN_DOC" 'Do not add material fields to `ChunkData.blocks`'
require_token "$PROTOCOL_DOC" 'Block material metadata compatibility; `block_id` remains the only current wire/storage identity'

if ! (cd "$ROOT_DIR/server" && go run ./cmd/block_material_registry_matrix > "$RAW_SUMMARY_PATH" 2>"$OUT_DIR/block-material-registry-matrix.err"); then
  cat "$OUT_DIR/block-material-registry-matrix.err" >&2 || true
  fail "block material registry matrix command failed"
fi

raw_status="$(field_metric status "$RAW_SUMMARY_PATH")"
block_count="$(field_metric block_count "$RAW_SUMMARY_PATH")"
registry_hash="$(field_metric registry_hash "$RAW_SUMMARY_PATH")"
networked_blocks="$(field_metric networked_blocks "$RAW_SUMMARY_PATH")"
opaque_solid_blocks="$(field_metric opaque_solid_blocks "$RAW_SUMMARY_PATH")"
placeable_blocks="$(field_metric placeable_blocks "$RAW_SUMMARY_PATH")"
air_blocks="$(field_metric air_blocks "$RAW_SUMMARY_PATH")"
emissive_blocks="$(field_metric emissive_blocks "$RAW_SUMMARY_PATH")"
liquid_blocks="$(field_metric liquid_blocks "$RAW_SUMMARY_PATH")"
mining_duration_metadata="$(field_metric mining_duration_metadata "$RAW_SUMMARY_PATH")"
active_block_id_change="$(field_metric active_block_id_change "$RAW_SUMMARY_PATH")"
active_protocol_change="$(field_metric active_protocol_change "$RAW_SUMMARY_PATH")"
active_storage_change="$(field_metric active_storage_change "$RAW_SUMMARY_PATH")"
renderer_change="$(field_metric renderer_change "$RAW_SUMMARY_PATH")"
proto_diff_count="$(git -C "$ROOT_DIR" diff --name-only -- api/schema/packets.proto server/pkg/api/packets.pb.go | awk 'END { print NR + 0 }')"

world_tests="skipped"
if [ "$RUN_GO_TESTS" = "1" ]; then
  if (cd "$ROOT_DIR/server" && go test ./pkg/world ./cmd/block_material_registry_matrix > "$OUT_DIR/go-test-block-material-registry.txt" 2>&1); then
    world_tests="pass"
  else
    cat "$OUT_DIR/go-test-block-material-registry.txt" >&2 || true
    world_tests="fail"
  fi
fi

awk \
  -v raw_status="${raw_status:-missing}" \
  -v block_count="${block_count:-0}" \
  -v registry_hash="${registry_hash:-missing}" \
  -v expected_hash="$EXPECTED_HASH" \
  -v networked_blocks="${networked_blocks:-0}" \
  -v opaque_solid_blocks="${opaque_solid_blocks:-0}" \
  -v placeable_blocks="${placeable_blocks:-0}" \
  -v air_blocks="${air_blocks:-0}" \
  -v emissive_blocks="${emissive_blocks:-1}" \
  -v liquid_blocks="${liquid_blocks:-1}" \
  -v mining_duration_metadata="${mining_duration_metadata:-missing}" \
  -v active_block_id_change="${active_block_id_change:-1}" \
  -v active_protocol_change="${active_protocol_change:-1}" \
  -v active_storage_change="${active_storage_change:-1}" \
  -v renderer_change="${renderer_change:-1}" \
  -v proto_diff_count="$proto_diff_count" \
  -v world_tests="$world_tests" \
  -v raw_summary="$RAW_SUMMARY_PATH" '
  BEGIN {
    status = "pass"
    reason = "ok"
    material_registry_status = "guarded"
    server_registry_identity = "guarded"
    current_runtime_contract = "opaque_only"
    metadata_scope = "existing_block_ids"
    counts_ok = block_count + 0 == 6 &&
      networked_blocks + 0 == 6 &&
      opaque_solid_blocks + 0 == 5 &&
      placeable_blocks + 0 == 5 &&
      air_blocks + 0 == 1 &&
      emissive_blocks + 0 == 0 &&
      liquid_blocks + 0 == 0
    clean_contract = active_block_id_change + 0 == 0 &&
      active_protocol_change + 0 == 0 &&
      active_storage_change + 0 == 0 &&
      renderer_change + 0 == 0 &&
      proto_diff_count + 0 == 0
    mining_metadata_ok = mining_duration_metadata == "guarded"
    tests_ok = world_tests == "pass" || world_tests == "skipped"

    if (raw_status != "pass") {
      status = "fail"
      reason = "matrix_command_not_clean"
    } else if (registry_hash != expected_hash || !counts_ok) {
      status = "fail"
      reason = "registry_signature_changed"
    } else if (!clean_contract) {
      status = "fail"
      reason = "block_protocol_storage_or_renderer_diff_present"
    } else if (!mining_metadata_ok) {
      status = "fail"
      reason = "mining_duration_metadata_not_guarded"
    } else if (!tests_ok) {
      status = "fail"
      reason = "world_tests_failed"
    }

    printf("block_material_registry_foundation status=%s reason=%s material_registry_status=%s server_registry_identity=%s current_runtime_contract=%s metadata_scope=%s block_count=%d registry_hash=%s networked_blocks=%d opaque_solid_blocks=%d placeable_blocks=%d air_blocks=%d emissive_blocks=%d liquid_blocks=%d mining_duration_metadata=%s active_block_id_change=%d active_protocol_change=%d active_storage_change=%d renderer_change=%d proto_diff_count=%d world_tests=%s raw_summary=%s\n", status, reason, material_registry_status, server_registry_identity, current_runtime_contract, metadata_scope, block_count, registry_hash, networked_blocks, opaque_solid_blocks, placeable_blocks, air_blocks, emissive_blocks, liquid_blocks, mining_duration_metadata, active_block_id_change, active_protocol_change, active_storage_change, renderer_change, proto_diff_count, world_tests, raw_summary)
    if (status != "pass") {
      exit 1
    }
  }
' > "$SUMMARY_PATH" || {
  cat "$SUMMARY_PATH" >&2 || true
  fail "block material registry foundation gate failed"
}

cat "$SUMMARY_PATH"
echo "Block material registry foundation artifacts: $OUT_DIR"
