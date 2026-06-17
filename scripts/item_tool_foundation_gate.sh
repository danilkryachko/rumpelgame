#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/item_tool_foundation"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

SUMMARY_PATH="$OUT_DIR/item-tool-foundation-summary.txt"
DESIGN_DOC="${RUMPELMC_ITEM_TOOL_DOC:-"$ROOT_DIR/docs/ITEM_TOOL_FOUNDATION.md"}"
ITEM_SOURCE="${RUMPELMC_ITEM_TOOL_ITEM_SOURCE:-"$ROOT_DIR/server/pkg/item/catalog.go"}"
ITEM_TEST="${RUMPELMC_ITEM_TOOL_ITEM_TEST:-"$ROOT_DIR/server/pkg/item/catalog_test.go"}"
NETWORK_SOURCE="${RUMPELMC_ITEM_TOOL_NETWORK_SOURCE:-"$ROOT_DIR/server/pkg/network/server.go"}"
NETWORK_TEST="${RUMPELMC_ITEM_TOOL_NETWORK_TEST:-"$ROOT_DIR/server/pkg/network/server_test.go"}"
PROTOCOL_DOC="${RUMPELMC_ITEM_TOOL_PROTOCOL_DOC:-"$ROOT_DIR/docs/PROTOCOL.md"}"
RUN_GO_TESTS="${RUMPELMC_ITEM_TOOL_RUN_GO_TESTS:-1}"

mkdir -p "$OUT_DIR"

fail() {
  echo "item_tool_foundation_gate: $*" >&2
  exit 1
}

require_token() {
  path="$1"
  token="$2"
  test -s "$path" || fail "missing file $path"
  grep -Fq "$token" "$path" || fail "missing token '$token' in $path"
}

for path in "$DESIGN_DOC" "$ITEM_SOURCE" "$ITEM_TEST" "$NETWORK_SOURCE" "$NETWORK_TEST" "$PROTOCOL_DOC"; do
  test -s "$path" || fail "missing required input $path"
done

for token in \
  'Item Tool Foundation' \
  'Server-Owned Item Identity' \
  'First Tool Slot' \
  'Mining Duration Contract' \
  'Compatibility Rules' \
  'item_tool_foundation=server_guarded' \
  'tool_mining=selected_tool_guarded'; do
  require_token "$DESIGN_DOC" "$token"
done

for token in \
  'type ID string' \
  'StoneItemID' \
  'DirtItemID' \
  'GrassItemID' \
  'WoodItemID' \
  'LeavesItemID' \
  'HandToolID' \
  'WoodenPickaxeToolID' \
  'WoodenAxeToolID' \
  'WoodenShovelToolID' \
  'BlockItemDefinitions' \
  'ToolDefinitions' \
  'BlockItemID' \
  'BlockForItem' \
  'ToolByID' \
  'DefaultToolbelt' \
  'AdjustedMiningDurationMS' \
  'divideRoundUp'; do
  require_token "$ITEM_SOURCE" "$token"
done

for token in \
  'TestBlockItemDefinitionsMapCurrentPlaceableBlocks' \
  'TestCatalogAccessorsReturnCopies' \
  'TestDefaultToolbeltStartsWithHandAndIncludesWoodTools' \
  'TestAdjustedMiningDurationMSUsesToolEffectiveness'; do
  require_token "$ITEM_TEST" "$token"
done

for token in \
  'toolbelt              []item.ID' \
  'selectedToolSlot      uint32' \
  'toolbelt := item.DefaultToolbelt()' \
  'miningDurationForBlockWithTool' \
  'client.selectedToolID()' \
  's.miningCooldownOverride' \
  'return item.HandToolID'; do
  require_token "$NETWORK_SOURCE" "$token"
done

for token in \
  'TestClientSessionStartsWithHandToolSlot' \
  'TestMiningDurationForBlockWithTool' \
  'TestMiningDurationForBlockWithToolKeepsGlobalOverrideExact' \
  'TestHandleClientPacketDestroyUsesSelectedToolMiningDuration'; do
  require_token "$NETWORK_TEST" "$token"
done

require_token "$PROTOCOL_DOC" '`Packet.block_action = 3`'
require_token "$PROTOCOL_DOC" '`Packet.inventory_snapshot = 4`'
require_token "$PROTOCOL_DOC" '`Packet.inventory_action = 5`'

protocol_diff_count="$(git -C "$ROOT_DIR" diff --name-only -- api/schema/packets.proto server/pkg/api/packets.pb.go | awk 'END { print NR + 0 }')"
storage_diff_count="$(git -C "$ROOT_DIR" diff --name-only -- server/pkg/storage docs/STORAGE.md | awk 'END { print NR + 0 }')"
worldgen_diff_count="$(git -C "$ROOT_DIR" diff --name-only -- server/pkg/world/chunk.go server/pkg/world/generator.go server/pkg/world/biome.go server/pkg/world/cave.go server/pkg/world/resource.go docs/WORLDGEN_DETERMINISM.md | awk 'END { print NR + 0 }')"

go_tests="skipped"
if [ "$RUN_GO_TESTS" = "1" ]; then
  if (cd "$ROOT_DIR/server" && go test ./pkg/item ./pkg/network > "$OUT_DIR/go-test-item-tool-foundation.txt" 2>&1); then
    go_tests="pass"
  else
    cat "$OUT_DIR/go-test-item-tool-foundation.txt" >&2 || true
    go_tests="fail"
  fi
fi

awk \
  -v protocol_diff_count="$protocol_diff_count" \
  -v storage_diff_count="$storage_diff_count" \
  -v worldgen_diff_count="$worldgen_diff_count" \
  -v go_tests="$go_tests" \
  -v design_doc="$DESIGN_DOC" \
  -v item_source="$ITEM_SOURCE" \
  -v network_source="$NETWORK_SOURCE" '
  BEGIN {
    status = "pass"
    reason = "ok"
    item_tool_foundation = "server_guarded"
    item_identity = "block_items_guarded"
    tool_catalog = "wood_tools_guarded"
    first_tool_slot = "hand_guarded"
    tool_mining = "selected_tool_guarded"
    go_ok = go_tests == "pass" || go_tests == "skipped"

    if (protocol_diff_count + 0 != 0) {
      status = "fail"
      reason = "protocol_diff_present"
    } else if (storage_diff_count + 0 != 0) {
      status = "fail"
      reason = "storage_diff_present"
    } else if (worldgen_diff_count + 0 != 0) {
      status = "fail"
      reason = "worldgen_diff_present"
    } else if (!go_ok) {
      status = "fail"
      reason = "go_tests_failed"
    }

    printf("item_tool_foundation status=%s reason=%s item_tool_foundation=%s item_identity=%s tool_catalog=%s first_tool_slot=%s tool_mining=%s active_protocol_change=%d active_storage_change=%d active_worldgen_change=%d go_tests=%s design_doc=%s item_source=%s network_source=%s\n", status, reason, item_tool_foundation, item_identity, tool_catalog, first_tool_slot, tool_mining, protocol_diff_count, storage_diff_count, worldgen_diff_count, go_tests, design_doc, item_source, network_source)
    if (status != "pass") {
      exit 1
    }
  }
' > "$SUMMARY_PATH" || {
  cat "$SUMMARY_PATH" >&2 || true
  fail "item tool foundation gate failed"
}

cat "$SUMMARY_PATH"
echo "Item tool foundation artifacts: $OUT_DIR"
