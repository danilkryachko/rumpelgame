#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/block_material_registry_parity"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

SUMMARY_PATH="$OUT_DIR/block-material-registry-parity-summary.txt"
SERVER_GATE="${RUMPELMC_BLOCK_MATERIAL_PARITY_SERVER_GATE:-"$ROOT_DIR/scripts/block_material_registry_foundation_gate.sh"}"
CLIENT_GATE="${RUMPELMC_BLOCK_MATERIAL_PARITY_CLIENT_GATE:-"$ROOT_DIR/scripts/client_block_material_registry_foundation_gate.sh"}"
SERVER_GATE_DIR="${RUMPELMC_BLOCK_MATERIAL_PARITY_SERVER_DIR:-"$ROOT_DIR/logs/block_material_registry_foundation_current"}"
CLIENT_GATE_DIR="${RUMPELMC_BLOCK_MATERIAL_PARITY_CLIENT_DIR:-"$ROOT_DIR/logs/client_block_material_registry_foundation_current"}"
SERVER_BLOCKS_TEST="${RUMPELMC_BLOCK_MATERIAL_PARITY_SERVER_TEST:-"$ROOT_DIR/server/pkg/world/blocks_test.go"}"
CLIENT_BLOCKS="${RUMPELMC_BLOCK_MATERIAL_PARITY_CLIENT_BLOCKS:-"$ROOT_DIR/client/rust_ext/src/blocks.rs"}"
DESIGN_DOC="${RUMPELMC_BLOCK_MATERIAL_PARITY_DESIGN_DOC:-"$ROOT_DIR/docs/BLOCK_MATERIAL_METADATA_DESIGN.md"}"

mkdir -p "$OUT_DIR"

fail() {
  echo "block_material_registry_parity_gate: $*" >&2
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

for path in "$SERVER_GATE" "$CLIENT_GATE" "$SERVER_BLOCKS_TEST" "$CLIENT_BLOCKS" "$DESIGN_DOC"; do
  test -s "$path" || fail "missing required input $path"
done

require_token "$SERVER_BLOCKS_TEST" "TestBlockIDValuesAreStable"
require_token "$CLIENT_BLOCKS" "pub const AIR: BlockId = 0;"
require_token "$CLIENT_BLOCKS" "pub const STONE: BlockId = 1;"
require_token "$CLIENT_BLOCKS" "pub const DIRT: BlockId = 2;"
require_token "$CLIENT_BLOCKS" "pub const GRASS: BlockId = 3;"
require_token "$CLIENT_BLOCKS" "pub const WOOD: BlockId = 4;"
require_token "$CLIENT_BLOCKS" "pub const LEAVES: BlockId = 5;"
require_token "$DESIGN_DOC" "client/server material parity gate"

if ! sh "$SERVER_GATE" "$SERVER_GATE_DIR" > "$OUT_DIR/server-gate.log" 2>&1; then
  cat "$OUT_DIR/server-gate.log" >&2 || true
  fail "server material registry gate failed"
fi
if ! sh "$CLIENT_GATE" "$CLIENT_GATE_DIR" > "$OUT_DIR/client-gate.log" 2>&1; then
  cat "$OUT_DIR/client-gate.log" >&2 || true
  fail "client material registry gate failed"
fi

server_summary="$SERVER_GATE_DIR/block-material-registry-foundation-summary.txt"
client_summary="$CLIENT_GATE_DIR/client-block-material-registry-foundation-summary.txt"
server_status="$(field_metric status "$server_summary")"
client_status="$(field_metric status "$client_summary")"
server_material_registry_status="$(field_metric material_registry_status "$server_summary")"
client_material_registry_status="$(field_metric client_material_registry_status "$client_summary")"
client_server_material_registry_status="$(field_metric server_material_registry_status "$client_summary")"
server_block_count="$(field_metric block_count "$server_summary")"
client_block_count="$(field_metric client_block_count "$client_summary")"
server_opaque_solid_blocks="$(field_metric opaque_solid_blocks "$server_summary")"
client_opaque_solid_blocks="$(field_metric client_opaque_solid_blocks "$client_summary")"
server_placeable_blocks="$(field_metric placeable_blocks "$server_summary")"
client_placeable_blocks="$(field_metric client_placeable_blocks "$client_summary")"
server_air_blocks="$(field_metric air_blocks "$server_summary")"
client_air_blocks="$(field_metric client_air_blocks "$client_summary")"
server_emissive_blocks="$(field_metric emissive_blocks "$server_summary")"
client_emissive_blocks="$(field_metric client_emissive_blocks "$client_summary")"
server_liquid_blocks="$(field_metric liquid_blocks "$server_summary")"
client_liquid_blocks="$(field_metric client_liquid_blocks "$client_summary")"
protocol_diff_count="$(git -C "$ROOT_DIR" diff --name-only -- api/schema/packets.proto server/pkg/api/packets.pb.go | awk 'END { print NR + 0 }')"
storage_diff_count="$(git -C "$ROOT_DIR" diff --name-only -- server/pkg/storage | awk 'END { print NR + 0 }')"
renderer_code_diff_count="$(git -C "$ROOT_DIR" diff --name-only -- client/rust_ext/src/gpu_terrain.rs client/shaders | awk 'END { print NR + 0 }')"

awk \
  -v server_status="${server_status:-missing}" \
  -v client_status="${client_status:-missing}" \
  -v server_material_registry_status="${server_material_registry_status:-missing}" \
  -v client_material_registry_status="${client_material_registry_status:-missing}" \
  -v client_server_material_registry_status="${client_server_material_registry_status:-missing}" \
  -v server_block_count="${server_block_count:-0}" \
  -v client_block_count="${client_block_count:-0}" \
  -v server_opaque_solid_blocks="${server_opaque_solid_blocks:-0}" \
  -v client_opaque_solid_blocks="${client_opaque_solid_blocks:-0}" \
  -v server_placeable_blocks="${server_placeable_blocks:-0}" \
  -v client_placeable_blocks="${client_placeable_blocks:-0}" \
  -v server_air_blocks="${server_air_blocks:-0}" \
  -v client_air_blocks="${client_air_blocks:-0}" \
  -v server_emissive_blocks="${server_emissive_blocks:-1}" \
  -v client_emissive_blocks="${client_emissive_blocks:-1}" \
  -v server_liquid_blocks="${server_liquid_blocks:-1}" \
  -v client_liquid_blocks="${client_liquid_blocks:-1}" \
  -v protocol_diff_count="$protocol_diff_count" \
  -v storage_diff_count="$storage_diff_count" \
  -v renderer_code_diff_count="$renderer_code_diff_count" \
  -v server_summary="$server_summary" \
  -v client_summary="$client_summary" '
  BEGIN {
    status = "pass"
    reason = "ok"
    parity_status = "guarded"
    current_runtime_contract = "opaque_only"
    metadata_scope = "existing_block_ids"
    gates_ok = server_status == "pass" &&
      client_status == "pass" &&
      server_material_registry_status == "guarded" &&
      client_material_registry_status == "guarded" &&
      client_server_material_registry_status == "guarded"
    counts_match = server_block_count + 0 == client_block_count + 0 &&
      server_opaque_solid_blocks + 0 == client_opaque_solid_blocks + 0 &&
      server_placeable_blocks + 0 == client_placeable_blocks + 0 &&
      server_air_blocks + 0 == client_air_blocks + 0 &&
      server_emissive_blocks + 0 == client_emissive_blocks + 0 &&
      server_liquid_blocks + 0 == client_liquid_blocks + 0
    clean_contract = protocol_diff_count + 0 == 0 &&
      storage_diff_count + 0 == 0 &&
      renderer_code_diff_count + 0 == 0

    if (!gates_ok) {
      status = "fail"
      reason = "registry_gate_not_clean"
    } else if (!counts_match) {
      status = "fail"
      reason = "client_server_counts_mismatch"
    } else if (!clean_contract) {
      status = "fail"
      reason = "protocol_storage_or_renderer_code_diff_present"
    }

    printf("block_material_registry_parity status=%s reason=%s parity_status=%s current_runtime_contract=%s metadata_scope=%s server_status=%s client_status=%s server_block_count=%d client_block_count=%d server_opaque_solid_blocks=%d client_opaque_solid_blocks=%d server_placeable_blocks=%d client_placeable_blocks=%d server_air_blocks=%d client_air_blocks=%d server_emissive_blocks=%d client_emissive_blocks=%d server_liquid_blocks=%d client_liquid_blocks=%d active_protocol_change=%d active_storage_change=%d renderer_code_change=%d server_summary=%s client_summary=%s\n", status, reason, parity_status, current_runtime_contract, metadata_scope, server_status, client_status, server_block_count, client_block_count, server_opaque_solid_blocks, client_opaque_solid_blocks, server_placeable_blocks, client_placeable_blocks, server_air_blocks, client_air_blocks, server_emissive_blocks, client_emissive_blocks, server_liquid_blocks, client_liquid_blocks, protocol_diff_count, storage_diff_count, renderer_code_diff_count, server_summary, client_summary)
    if (status != "pass") {
      exit 1
    }
  }
' > "$SUMMARY_PATH" || {
  cat "$SUMMARY_PATH" >&2 || true
  fail "block material registry parity gate failed"
}

cat "$SUMMARY_PATH"
echo "Block material registry parity artifacts: $OUT_DIR"
