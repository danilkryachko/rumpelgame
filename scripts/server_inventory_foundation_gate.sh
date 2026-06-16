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
STORAGE_SOURCE="${RUMPELMC_SERVER_INVENTORY_STORAGE_SOURCE:-"$ROOT_DIR/server/pkg/storage/player_inventory.go"}"
STORAGE_TEST="${RUMPELMC_SERVER_INVENTORY_STORAGE_TEST:-"$ROOT_DIR/server/pkg/storage/rocksdb_test.go"}"
PROTOCOL_DOC="${RUMPELMC_SERVER_INVENTORY_PROTOCOL_DOC:-"$ROOT_DIR/docs/PROTOCOL.md"}"
COUNTED_SMOKE_SCRIPT="${RUMPELMC_SERVER_INVENTORY_COUNTED_SMOKE_SCRIPT:-"$ROOT_DIR/scripts/player_inventory_counted_smoke.sh"}"
COUNTED_SMOKE_SUMMARY="${RUMPELMC_SERVER_INVENTORY_COUNTED_SMOKE_SUMMARY:-"$ROOT_DIR/logs/player_inventory_counted_smoke_current/player-inventory-counted-smoke-summary.txt"}"
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

for path in "$DESIGN_DOC" "$INVENTORY_SOURCE" "$INVENTORY_TEST" "$NETWORK_SOURCE" "$NETWORK_TEST" "$STORAGE_SOURCE" "$STORAGE_TEST" "$PROTOCOL_DOC" "$COUNTED_SMOKE_SCRIPT"; do
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
require_token "$INVENTORY_SOURCE" 'type State struct'
require_token "$INVENTORY_SOURCE" 'CreativeStackCount'
require_token "$INVENTORY_SOURCE" 'CountedHotbarStackCount'
require_token "$INVENTORY_SOURCE" 'func NewCreativeHotbar'
require_token "$INVENTORY_SOURCE" 'func NewCounted'
require_token "$INVENTORY_SOURCE" 'func NewCountedHotbar'
require_token "$INVENTORY_SOURCE" 'func NewFromState'
require_token "$INVENTORY_SOURCE" 'func (i *Inventory) CanPlaceBlock'
require_token "$INVENTORY_SOURCE" 'func (i *Inventory) CanSelectSlot'
require_token "$INVENTORY_SOURCE" 'func (i *Inventory) FirstPlaceableSlot'
require_token "$INVENTORY_SOURCE" 'func (i *Inventory) PlaceableBlockAtSlot'
require_token "$INVENTORY_SOURCE" 'func (i *Inventory) PlaceBlock'
require_token "$INVENTORY_SOURCE" 'func (i *Inventory) State'
require_token "$INVENTORY_SOURCE" 'world.IsPlaceable'
require_token "$INVENTORY_TEST" 'TestCreativeHotbarContainsCurrentPlaceableBlocks'
require_token "$INVENTORY_TEST" 'TestCreativeHotbarPlaceBlockRetainsCounts'
require_token "$INVENTORY_TEST" 'TestCountedHotbarConsumesCurrentPlaceableBlocks'
require_token "$INVENTORY_TEST" 'TestCountedInventoryConsumesStacksAndRejectsEmptySlots'
require_token "$INVENTORY_TEST" 'TestInventorySlotsReturnsCopy'
require_token "$INVENTORY_TEST" 'TestInventorySlotSelectionRequiresAvailablePlaceableSlot'
require_token "$INVENTORY_TEST" 'TestInventoryFirstPlaceableSlotSkipsUnavailableSlots'
require_token "$NETWORK_SOURCE" 'playerinventory "rumpelmc/server/pkg/inventory"'
require_token "$NETWORK_SOURCE" 'type playerInventoryStore interface'
require_token "$NETWORK_SOURCE" 'NewServerWithPlayerInventoryStore'
require_token "$NETWORK_SOURCE" 'RUMPELMC_SERVER_INVENTORY_MODE'
require_token "$NETWORK_SOURCE" 'configuredInventoryMode'
require_token "$NETWORK_SOURCE" 'inventoryModeCounted'
require_token "$NETWORK_SOURCE" 'LoadPlayerInventory'
require_token "$NETWORK_SOURCE" 'SavePlayerInventory'
require_token "$NETWORK_SOURCE" 'inventory             playerinventory.Inventory'
require_token "$NETWORK_SOURCE" 'selectedInventorySlot uint32'
require_token "$NETWORK_SOURCE" 'playerID              string'
require_token "$NETWORK_SOURCE" 'playerinventory.NewCreativeHotbar()'
require_token "$NETWORK_SOURCE" 'inventory.FirstPlaceableSlot()'
require_token "$NETWORK_SOURCE" 'client.selectInventorySlot(action.Slot)'
require_token "$NETWORK_SOURCE" 'client.placeInventoryBlock(block)'
require_token "$NETWORK_SOURCE" 's.saveClientInventory(client)'
require_token "$NETWORK_SOURCE" 'client.inventory.CanPlaceBlock'
require_token "$NETWORK_SOURCE" 'normalizedPlayerID'
require_token "$NETWORK_SOURCE" 'world.IsPlaceable(block)'
require_token "$STORAGE_SOURCE" 'func (s *RocksChunkStore) LoadPlayerInventory'
require_token "$STORAGE_SOURCE" 'func (s *RocksChunkStore) SavePlayerInventory'
require_token "$STORAGE_SOURCE" 'playerInventoryRecordVersion'
require_token "$STORAGE_SOURCE" "[]byte{'p', 'i', 0}"
require_token "$STORAGE_TEST" 'TestRocksChunkStorePlayerInventoryRoundTrip'
require_token "$STORAGE_TEST" 'TestRocksChunkStorePlayerInventoryKeyIsSeparateFromChunkKey'
require_token "$STORAGE_TEST" 'TestRocksChunkStorePlayerInventoryRejectsCorruptPayload'
require_token "$NETWORK_TEST" 'TestNewClientSessionStartsWithServerAuthoritativeCreativeInventory'
require_token "$NETWORK_TEST" 'TestConfiguredInventoryModeUsesCountedEnv'
require_token "$NETWORK_TEST" 'TestServerCountedInventoryModeStartsSessionWithCountedHotbar'
require_token "$NETWORK_TEST" 'TestSendInventorySnapshotToSessionUsesCountedInventoryMode'
require_token "$NETWORK_TEST" 'TestHandleClientPacketPositionLoadsPersistedPlayerInventory'
require_token "$NETWORK_TEST" 'TestHandleClientPacketPositionCreatesPlayerInventoryRecord'
require_token "$NETWORK_TEST" 'TestHandleClientPacketPositionCreatesCountedPlayerInventoryRecord'
require_token "$NETWORK_TEST" 'TestHandleClientPacketPositionIgnoresInvalidPlayerIDForPersistence'
require_token "$NETWORK_TEST" 'TestHandleClientPacketInventoryActionPersistsSelectedSlot'
require_token "$NETWORK_TEST" 'TestHandleClientPacketPlacePersistsInventoryAfterCountedPlacement'
require_token "$NETWORK_TEST" 'TestHandleClientPacketInventoryActionSelectsSlotAndSendsSnapshot'
require_token "$NETWORK_TEST" 'TestHandleClientPacketInventoryActionRejectsUnavailableSlot'
require_token "$NETWORK_TEST" 'TestHandleClientPacketPlaceSendsInventorySnapshotAfterCountedPlacement'
require_token "$NETWORK_TEST" 'TestHandleClientPacketRejectsPlaceWhenSessionInventoryLacksBlock'
require_token "$NETWORK_TEST" 'TestHandleClientPacketDoesNotConsumeInventoryWhenBlockUpdateFails'
require_token "$COUNTED_SMOKE_SCRIPT" 'RUMPELMC_SERVER_INVENTORY_MODE=counted'
require_token "$COUNTED_SMOKE_SCRIPT" 'counted_inventory_runtime=live_server_guarded'

test -s "$COUNTED_SMOKE_SUMMARY" || fail "missing required input $COUNTED_SMOKE_SUMMARY"
counted_smoke_status="$(field_metric status "$COUNTED_SMOKE_SUMMARY")"
counted_runtime="$(field_metric counted_inventory_runtime "$COUNTED_SMOKE_SUMMARY")"
counted_place_status="$(field_metric place_status "$COUNTED_SMOKE_SUMMARY")"
counted_verify_restart_status="$(field_metric verify_restart_status "$COUNTED_SMOKE_SUMMARY")"
counted_restarts="$(field_metric server_restarts "$COUNTED_SMOKE_SUMMARY")"
counted_protocol_change="$(field_metric protocol_change "$COUNTED_SMOKE_SUMMARY")"

protocol_diff_count="$(git -C "$ROOT_DIR" diff --name-only -- api/schema/packets.proto server/pkg/api/packets.pb.go | awk 'END { print NR + 0 }')"
storage_diff_count="$(git -C "$ROOT_DIR" diff --name-only -- server/pkg/storage docs/STORAGE.md docs/STORAGE_PERSISTENCE_FOUNDATION.md | awk 'END { print NR + 0 }')"

go_tests="skipped"
if [ "$RUN_GO_TESTS" = "1" ]; then
  if (cd "$ROOT_DIR/server" && go test ./pkg/inventory ./pkg/storage ./pkg/network > "$OUT_DIR/go-test-server-inventory.txt" 2>&1); then
    go_tests="pass"
  else
    cat "$OUT_DIR/go-test-server-inventory.txt" >&2 || true
    go_tests="fail"
  fi
fi

awk \
  -v protocol_diff_count="$protocol_diff_count" \
  -v storage_diff_count="$storage_diff_count" \
  -v counted_smoke_status="${counted_smoke_status:-missing}" \
  -v counted_runtime="${counted_runtime:-missing}" \
  -v counted_place_status="${counted_place_status:-missing}" \
  -v counted_verify_restart_status="${counted_verify_restart_status:-missing}" \
  -v counted_restarts="${counted_restarts:-0}" \
  -v counted_protocol_change="${counted_protocol_change:-1}" \
  -v go_tests="$go_tests" \
  -v design_doc="$DESIGN_DOC" \
  -v inventory_source="$INVENTORY_SOURCE" \
  -v network_source="$NETWORK_SOURCE" \
  -v counted_smoke_summary="$COUNTED_SMOKE_SUMMARY" '
  BEGIN {
    status = "pass"
    reason = "ok"
    server_inventory_status = "session_guarded"
    creative_inventory = "unit_guarded"
    counted_inventory = "unit_guarded"
    counted_runtime_status = "live_server_guarded"
    block_action_inventory = "session_guarded"
    player_inventory_persistence = "rocksdb_guarded"
    go_ok = go_tests == "pass" || go_tests == "skipped"
    counted_ok = counted_smoke_status == "pass" &&
      counted_runtime == "live_server_guarded" &&
      counted_place_status == "pass" &&
      counted_verify_restart_status == "pass" &&
      counted_restarts + 0 >= 1 &&
      counted_protocol_change + 0 == 0

    if (protocol_diff_count + 0 != 0) {
      status = "fail"
      reason = "protocol_diff_present"
    } else if (storage_diff_count + 0 != 0) {
      status = "fail"
      reason = "storage_diff_present"
    } else if (!counted_ok) {
      status = "fail"
      reason = "counted_runtime_not_clean"
    } else if (!go_ok) {
      status = "fail"
      reason = "go_tests_failed"
    }

    printf("server_inventory_foundation status=%s reason=%s server_inventory_status=%s creative_inventory=%s counted_inventory=%s counted_inventory_runtime=%s counted_inventory_runtime_status=%s counted_inventory_restarts=%d block_action_inventory=%s player_inventory_persistence=%s active_protocol_change=%d active_storage_change=%d go_tests=%s design_doc=%s inventory_source=%s network_source=%s counted_smoke_summary=%s\n", status, reason, server_inventory_status, creative_inventory, counted_inventory, counted_runtime_status, counted_smoke_status, counted_restarts, block_action_inventory, player_inventory_persistence, protocol_diff_count, storage_diff_count, go_tests, design_doc, inventory_source, network_source, counted_smoke_summary)
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
