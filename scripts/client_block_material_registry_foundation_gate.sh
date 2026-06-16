#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/client_block_material_registry_foundation"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

SUMMARY_PATH="$OUT_DIR/client-block-material-registry-foundation-summary.txt"
CLIENT_BLOCKS="${RUMPELMC_CLIENT_BLOCK_MATERIAL_SOURCE:-"$ROOT_DIR/client/rust_ext/src/blocks.rs"}"
GPU_TERRAIN="${RUMPELMC_CLIENT_BLOCK_MATERIAL_GPU_TERRAIN:-"$ROOT_DIR/client/rust_ext/src/gpu_terrain.rs"}"
DESIGN_DOC="${RUMPELMC_CLIENT_BLOCK_MATERIAL_DESIGN_DOC:-"$ROOT_DIR/docs/BLOCK_MATERIAL_METADATA_DESIGN.md"}"
SERVER_GATE="${RUMPELMC_CLIENT_BLOCK_MATERIAL_SERVER_GATE:-"$ROOT_DIR/scripts/block_material_registry_foundation_gate.sh"}"
SERVER_GATE_DIR="${RUMPELMC_CLIENT_BLOCK_MATERIAL_SERVER_GATE_DIR:-"$ROOT_DIR/logs/block_material_registry_foundation_current"}"
RUN_RUST_TESTS="${RUMPELMC_CLIENT_BLOCK_MATERIAL_RUN_RUST_TESTS:-1}"

mkdir -p "$OUT_DIR"

fail() {
  echo "client_block_material_registry_foundation_gate: $*" >&2
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

for path in "$CLIENT_BLOCKS" "$GPU_TERRAIN" "$DESIGN_DOC" "$SERVER_GATE"; do
  test -s "$path" || fail "missing required input $path"
done

require_token "$CLIENT_BLOCKS" "pub enum RenderClass"
require_token "$CLIENT_BLOCKS" "pub enum CollisionClass"
require_token "$CLIENT_BLOCKS" "pub enum OcclusionClass"
require_token "$CLIENT_BLOCKS" "pub enum ShadowPolicy"
require_token "$CLIENT_BLOCKS" "pub enum DepthPolicy"
require_token "$CLIENT_BLOCKS" "pub enum StoragePolicy"
require_token "$CLIENT_BLOCKS" "pub enum LiquidPolicy"
require_token "$CLIENT_BLOCKS" "pub enum SortPolicy"
require_token "$CLIENT_BLOCKS" "pub fn is_opaque"
require_token "$CLIENT_BLOCKS" "fn block_material_current_networked_blocks_preserve_opaque_contract"
require_token "$CLIENT_BLOCKS" "fn block_material_unknown_blocks_are_conservative"
require_token "$CLIENT_BLOCKS" "fn block_material_policy_variant_sets_are_explicit"
require_token "$CLIENT_BLOCKS" "fn block_material_identity_rows_are_stable"
require_token "$GPU_TERRAIN" ".filter(|block| blocks::is_opaque_solid(block.id))"
require_token "$DESIGN_DOC" "client material registry foundation"
require_token "$DESIGN_DOC" 'Do not add material fields to `ChunkData.blocks`'

if ! sh "$SERVER_GATE" "$SERVER_GATE_DIR" > "$OUT_DIR/server-registry-gate.log" 2>&1; then
  cat "$OUT_DIR/server-registry-gate.log" >&2 || true
  fail "server material registry gate failed"
fi

server_summary="$SERVER_GATE_DIR/block-material-registry-foundation-summary.txt"
server_status="$(field_metric status "$server_summary")"
server_registry_status="$(field_metric material_registry_status "$server_summary")"
server_registry_hash="$(field_metric registry_hash "$server_summary")"

rust_tests="skipped"
if [ "$RUN_RUST_TESTS" = "1" ]; then
  if cargo test --manifest-path "$ROOT_DIR/client/rust_ext/Cargo.toml" block_material -- --nocapture > "$OUT_DIR/rust-block-material-tests.txt" 2>&1; then
    rust_tests="pass"
  else
    cat "$OUT_DIR/rust-block-material-tests.txt" >&2 || true
    rust_tests="fail"
  fi
fi

client_block_count="$(awk '
  /const BLOCK_DEFINITIONS:/ { in_registry = 1 }
  in_registry && /BlockDefinition[[:space:]]*\{/ { count++ }
  in_registry && /^\];/ { in_registry = 0 }
  END { print count + 0 }
' "$CLIENT_BLOCKS")"
client_opaque_solid_blocks="$(awk '
  /const BLOCK_DEFINITIONS:/ { in_registry = 1 }
  in_registry && /render_class:[[:space:]]*RenderClass::Opaque/ { count++ }
  in_registry && /^\];/ { in_registry = 0 }
  END { print count + 0 }
' "$CLIENT_BLOCKS")"
client_placeable_blocks="$(awk '
  /const BLOCK_DEFINITIONS:/ { in_registry = 1 }
  in_registry && /placeable:[[:space:]]*true/ { count++ }
  in_registry && /^\];/ { in_registry = 0 }
  END { print count + 0 }
' "$CLIENT_BLOCKS")"
client_air_blocks="$(awk '
  /const BLOCK_DEFINITIONS:/ { in_registry = 1 }
  in_registry && /render_class:[[:space:]]*RenderClass::Air/ { count++ }
  in_registry && /^\];/ { in_registry = 0 }
  END { print count + 0 }
' "$CLIENT_BLOCKS")"
client_emissive_blocks="$(awk '
  /const BLOCK_DEFINITIONS:/ { in_registry = 1 }
  in_registry && /light_emission:[[:space:]]*[1-9]/ { count++ }
  in_registry && /^\];/ { in_registry = 0 }
  END { print count + 0 }
' "$CLIENT_BLOCKS")"
client_liquid_none_blocks="$(awk '
  /const BLOCK_DEFINITIONS:/ { in_registry = 1 }
  in_registry && /liquid_policy:[[:space:]]*LiquidPolicy::None/ { count++ }
  in_registry && /^\];/ { in_registry = 0 }
  END { print count + 0 }
' "$CLIENT_BLOCKS")"
client_liquid_blocks="$((client_block_count - client_liquid_none_blocks))"
protocol_diff_count="$(git -C "$ROOT_DIR" diff --name-only -- api/schema/packets.proto server/pkg/api/packets.pb.go | awk 'END { print NR + 0 }')"
storage_diff_count="$(git -C "$ROOT_DIR" diff --name-only -- server/pkg/storage | awk 'END { print NR + 0 }')"
renderer_code_diff_count="$(git -C "$ROOT_DIR" diff --name-only -- client/rust_ext/src/gpu_terrain.rs client/shaders | awk 'END { print NR + 0 }')"

awk \
  -v server_status="${server_status:-missing}" \
  -v server_registry_status="${server_registry_status:-missing}" \
  -v server_registry_hash="${server_registry_hash:-missing}" \
  -v rust_tests="$rust_tests" \
  -v client_block_count="$client_block_count" \
  -v client_opaque_solid_blocks="$client_opaque_solid_blocks" \
  -v client_placeable_blocks="$client_placeable_blocks" \
  -v client_air_blocks="$client_air_blocks" \
  -v client_emissive_blocks="$client_emissive_blocks" \
  -v client_liquid_blocks="$client_liquid_blocks" \
  -v protocol_diff_count="$protocol_diff_count" \
  -v storage_diff_count="$storage_diff_count" \
  -v renderer_code_diff_count="$renderer_code_diff_count" \
  -v server_summary="$server_summary" '
  BEGIN {
    status = "pass"
    reason = "ok"
    client_material_registry_status = "guarded"
    client_registry_identity = "guarded"
    current_runtime_contract = "opaque_only"
    metadata_scope = "existing_block_ids"
    counts_ok = client_block_count + 0 == 6 &&
      client_opaque_solid_blocks + 0 == 5 &&
      client_placeable_blocks + 0 == 5 &&
      client_air_blocks + 0 == 1 &&
      client_emissive_blocks + 0 == 0 &&
      client_liquid_blocks + 0 == 0
    clean_contract = protocol_diff_count + 0 == 0 &&
      storage_diff_count + 0 == 0 &&
      renderer_code_diff_count + 0 == 0
    tests_ok = rust_tests == "pass" || rust_tests == "skipped"
    server_ok = server_status == "pass" && server_registry_status == "guarded"

    if (!counts_ok) {
      status = "fail"
      reason = "client_registry_signature_changed"
    } else if (!server_ok) {
      status = "fail"
      reason = "server_registry_gate_not_clean"
    } else if (!tests_ok) {
      status = "fail"
      reason = "rust_block_material_tests_failed"
    } else if (!clean_contract) {
      status = "fail"
      reason = "protocol_storage_or_renderer_code_diff_present"
    }

    printf("client_block_material_registry_foundation status=%s reason=%s client_material_registry_status=%s client_registry_identity=%s server_material_registry_status=%s current_runtime_contract=%s metadata_scope=%s client_block_count=%d client_opaque_solid_blocks=%d client_placeable_blocks=%d client_air_blocks=%d client_emissive_blocks=%d client_liquid_blocks=%d active_protocol_change=%d active_storage_change=%d renderer_code_change=%d rust_tests=%s server_registry_hash=%s server_summary=%s\n", status, reason, client_material_registry_status, client_registry_identity, server_registry_status, current_runtime_contract, metadata_scope, client_block_count, client_opaque_solid_blocks, client_placeable_blocks, client_air_blocks, client_emissive_blocks, client_liquid_blocks, protocol_diff_count, storage_diff_count, renderer_code_diff_count, rust_tests, server_registry_hash, server_summary)
    if (status != "pass") {
      exit 1
    }
  }
' > "$SUMMARY_PATH" || {
  cat "$SUMMARY_PATH" >&2 || true
  fail "client block material registry foundation gate failed"
}

cat "$SUMMARY_PATH"
echo "Client block material registry foundation artifacts: $OUT_DIR"
