#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/server_inventory_foundation"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

SUMMARY_PATH="$OUT_DIR/server-inventory-foundation-summary.txt"
DESIGN_DOC="${RUMPELMC_SERVER_INVENTORY_DOC:-"$ROOT_DIR/docs/SERVER_INVENTORY_FOUNDATION.md"}"
INVENTORY_SOURCE="${RUMPELMC_SERVER_INVENTORY_SOURCE:-"$ROOT_DIR/server/pkg/inventory/inventory.go"}"
INVENTORY_TEST="${RUMPELMC_SERVER_INVENTORY_TEST:-"$ROOT_DIR/server/pkg/inventory/inventory_test.go"}"
NETWORK_SOURCE="${RUMPELMC_SERVER_INVENTORY_NETWORK_SOURCE:-"$ROOT_DIR/server/pkg/network/server.go"}"
NETWORK_TEST="${RUMPELMC_SERVER_INVENTORY_NETWORK_TEST:-"$ROOT_DIR/server/pkg/network/server_test.go"}"
PROTOCOL_DOC="${RUMPELMC_SERVER_INVENTORY_PROTOCOL_DOC:-"$ROOT_DIR/docs/PROTOCOL.md"}"
RUN_GO_TESTS="${RUMPELMC_SERVER_INVENTORY_RUN_GO_TESTS:-1}"

mkdir -p "$OUT_DIR"

fail() {
  echo "server_inventory_foundation_gate: $*" >&2
  exit 1
}

require_token() {
  path="$1"
  token="$2"
  test -s "$path" || fail "missing file $path"
  grep -Fq "$token" "$path" || fail "missing token '$token' in $path"
}

for path in "$DESIGN_DOC" "$INVENTORY_SOURCE" "$INVENTORY_TEST" "$NETWORK_SOURCE" "$NETWORK_TEST" "$PROTOCOL_DOC"; do
  test -s "$path" || fail "missing required input $path"
done

for token in \
  'Server Inventory Foundation' \
  'Current Contract' \
  'Session Placement Boundary' \
  'Compatibility Rules' \
  'server_inventory_status=session_guarded' \
  'BlockAction PLACE'; do
  require_token "$DESIGN_DOC" "$token"
done

require_token "$PROTOCOL_DOC" '`Packet.block_action = 3`'
require_token "$INVENTORY_SOURCE" 'type Inventory struct'
require_token "$INVENTORY_SOURCE" 'type Slot struct'
require_token "$INVENTORY_SOURCE" 'CreativeStackCount'
require_token "$INVENTORY_SOURCE" 'func NewCreativeHotbar'
require_token "$INVENTORY_SOURCE" 'func NewCounted'
require_token "$INVENTORY_SOURCE" 'func (i *Inventory) CanPlaceBlock'
require_token "$INVENTORY_SOURCE" 'func (i *Inventory) CanSelectSlot'
require_token "$INVENTORY_SOURCE" 'func (i *Inventory) FirstPlaceableSlot'
require_token "$INVENTORY_SOURCE" 'func (i *Inventory) PlaceableBlockAtSlot'
require_token "$INVENTORY_SOURCE" 'func (i *Inventory) PlaceBlock'
require_token "$INVENTORY_SOURCE" 'world.IsPlaceable'
require_token "$INVENTORY_TEST" 'TestCreativeHotbarContainsCurrentPlaceableBlocks'
require_token "$INVENTORY_TEST" 'TestCreativeHotbarPlaceBlockRetainsCounts'
require_token "$INVENTORY_TEST" 'TestCountedInventoryConsumesStacksAndRejectsEmptySlots'
require_token "$INVENTORY_TEST" 'TestInventorySlotsReturnsCopy'
require_token "$INVENTORY_TEST" 'TestInventorySlotSelectionRequiresAvailablePlaceableSlot'
require_token "$INVENTORY_TEST" 'TestInventoryFirstPlaceableSlotSkipsUnavailableSlots'
require_token "$NETWORK_SOURCE" 'playerinventory "rumpelmc/server/pkg/inventory"'
require_token "$NETWORK_SOURCE" 'inventory             playerinventory.Inventory'
require_token "$NETWORK_SOURCE" 'selectedInventorySlot uint32'
require_token "$NETWORK_SOURCE" 'playerinventory.NewCreativeHotbar()'
require_token "$NETWORK_SOURCE" 'inventory.FirstPlaceableSlot()'
require_token "$NETWORK_SOURCE" 'client.selectInventorySlot(action.Slot)'
require_token "$NETWORK_SOURCE" 'client.normalizeSelectedInventorySlot()'
require_token "$NETWORK_SOURCE" 'client.inventory.CanPlaceBlock'
require_token "$NETWORK_SOURCE" 'client.inventory.PlaceBlock'
require_token "$NETWORK_SOURCE" 'world.IsPlaceable(block)'
require_token "$NETWORK_TEST" 'TestNewClientSessionStartsWithServerAuthoritativeCreativeInventory'
require_token "$NETWORK_TEST" 'TestHandleClientPacketInventoryActionSelectsSlotAndSendsSnapshot'
require_token "$NETWORK_TEST" 'TestHandleClientPacketInventoryActionRejectsUnavailableSlot'
require_token "$NETWORK_TEST" 'TestHandleClientPacketPlaceSendsInventorySnapshotAfterCountedPlacement'
require_token "$NETWORK_TEST" 'TestHandleClientPacketRejectsPlaceWhenSessionInventoryLacksBlock'
require_token "$NETWORK_TEST" 'TestHandleClientPacketDoesNotConsumeInventoryWhenBlockUpdateFails'

protocol_diff_count="$(git -C "$ROOT_DIR" diff --name-only -- api/schema/packets.proto server/pkg/api/packets.pb.go | awk 'END { print NR + 0 }')"
storage_diff_count="$(git -C "$ROOT_DIR" diff --name-only -- server/pkg/storage docs/STORAGE.md docs/STORAGE_PERSISTENCE_FOUNDATION.md | awk 'END { print NR + 0 }')"

go_tests="skipped"
if [ "$RUN_GO_TESTS" = "1" ]; then
  if (cd "$ROOT_DIR/server" && go test ./pkg/inventory ./pkg/network > "$OUT_DIR/go-test-server-inventory.txt" 2>&1); then
    go_tests="pass"
  else
    cat "$OUT_DIR/go-test-server-inventory.txt" >&2 || true
    go_tests="fail"
  fi
fi

awk \
  -v protocol_diff_count="$protocol_diff_count" \
  -v storage_diff_count="$storage_diff_count" \
  -v go_tests="$go_tests" \
  -v design_doc="$DESIGN_DOC" \
  -v inventory_source="$INVENTORY_SOURCE" \
  -v network_source="$NETWORK_SOURCE" '
  BEGIN {
    status = "pass"
    reason = "ok"
    server_inventory_status = "session_guarded"
    creative_inventory = "unit_guarded"
    counted_inventory = "unit_guarded"
    block_action_inventory = "session_guarded"
    go_ok = go_tests == "pass" || go_tests == "skipped"

    if (protocol_diff_count + 0 != 0) {
      status = "fail"
      reason = "protocol_diff_present"
    } else if (storage_diff_count + 0 != 0) {
      status = "fail"
      reason = "storage_diff_present"
    } else if (!go_ok) {
      status = "fail"
      reason = "go_tests_failed"
    }

    printf("server_inventory_foundation status=%s reason=%s server_inventory_status=%s creative_inventory=%s counted_inventory=%s block_action_inventory=%s active_protocol_change=%d active_storage_change=%d go_tests=%s design_doc=%s inventory_source=%s network_source=%s\n", status, reason, server_inventory_status, creative_inventory, counted_inventory, block_action_inventory, protocol_diff_count, storage_diff_count, go_tests, design_doc, inventory_source, network_source)
    if (status != "pass") {
      exit 1
    }
  }
' > "$SUMMARY_PATH" || {
  cat "$SUMMARY_PATH" >&2 || true
  fail "server inventory foundation gate failed"
}

cat "$SUMMARY_PATH"
echo "Server inventory foundation artifacts: $OUT_DIR"
