#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/inventory_protocol_compatibility"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

SUMMARY_PATH="$OUT_DIR/inventory-protocol-compatibility-summary.txt"
DESIGN_DOC="${RUMPELMC_INVENTORY_PROTOCOL_DOC:-"$ROOT_DIR/docs/INVENTORY_PROTOCOL_COMPATIBILITY.md"}"
PROTOCOL_DOC="${RUMPELMC_INVENTORY_PROTOCOL_MAIN_DOC:-"$ROOT_DIR/docs/PROTOCOL.md"}"
SERVER_INVENTORY_DOC="${RUMPELMC_INVENTORY_PROTOCOL_SERVER_INVENTORY_DOC:-"$ROOT_DIR/docs/SERVER_INVENTORY_FOUNDATION.md"}"
GAMEPLAY_DOC="${RUMPELMC_INVENTORY_PROTOCOL_GAMEPLAY_DOC:-"$ROOT_DIR/docs/GAMEPLAY_LOOP_FOUNDATION.md"}"
PROTO_SCHEMA="${RUMPELMC_INVENTORY_PROTOCOL_SCHEMA:-"$ROOT_DIR/api/schema/packets.proto"}"
GO_GENERATED="${RUMPELMC_INVENTORY_PROTOCOL_GO_GENERATED:-"$ROOT_DIR/server/pkg/api/packets.pb.go"}"
SERVER_SOURCE="${RUMPELMC_INVENTORY_PROTOCOL_SERVER_SOURCE:-"$ROOT_DIR/server/pkg/network/server.go"}"
SERVER_TEST="${RUMPELMC_INVENTORY_PROTOCOL_SERVER_TEST:-"$ROOT_DIR/server/pkg/network/server_test.go"}"
FRAMING_TEST="${RUMPELMC_INVENTORY_PROTOCOL_FRAMING_TEST:-"$ROOT_DIR/server/pkg/network/framing_test.go"}"
API_SCHEMA_TEST="${RUMPELMC_INVENTORY_PROTOCOL_API_SCHEMA_TEST:-"$ROOT_DIR/server/pkg/api/protocol_schema_test.go"}"
API_COMPAT_TEST="${RUMPELMC_INVENTORY_PROTOCOL_API_COMPAT_TEST:-"$ROOT_DIR/server/pkg/api/packets_compat_test.go"}"
CLIENT_SOURCE="${RUMPELMC_INVENTORY_PROTOCOL_CLIENT_SOURCE:-"$ROOT_DIR/client/rust_ext/src/lib.rs"}"
HUD_SOURCE="${RUMPELMC_INVENTORY_PROTOCOL_HUD_SOURCE:-"$ROOT_DIR/client/hud.gd"}"
PROTOCOL_SUMMARY="${RUMPELMC_INVENTORY_PROTOCOL_DRIFT_SUMMARY:-"$ROOT_DIR/logs/protocol_generated_drift_current/protocol-generated-drift-summary.txt"}"
SERVER_INVENTORY_SUMMARY="${RUMPELMC_INVENTORY_PROTOCOL_SERVER_SUMMARY:-"$ROOT_DIR/logs/server_inventory_foundation_current/server-inventory-foundation-summary.txt"}"
GAMEPLAY_SUMMARY="${RUMPELMC_INVENTORY_PROTOCOL_GAMEPLAY_SUMMARY:-"$ROOT_DIR/logs/gameplay_loop_foundation_current/gameplay-loop-foundation-summary.txt"}"
RUN_PROTOCOL_GATE="${RUMPELMC_INVENTORY_PROTOCOL_RUN_PROTOCOL_GATE:-1}"
RUN_SERVER_INVENTORY_GATE="${RUMPELMC_INVENTORY_PROTOCOL_RUN_SERVER_GATE:-1}"
RUN_GAMEPLAY_GATE="${RUMPELMC_INVENTORY_PROTOCOL_RUN_GAMEPLAY_GATE:-1}"

mkdir -p "$OUT_DIR"

fail() {
  echo "inventory_protocol_compatibility_gate: $*" >&2
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

for path in "$DESIGN_DOC" "$PROTOCOL_DOC" "$SERVER_INVENTORY_DOC" "$GAMEPLAY_DOC" "$PROTO_SCHEMA" "$GO_GENERATED" "$SERVER_SOURCE" "$SERVER_TEST" "$FRAMING_TEST" "$API_SCHEMA_TEST" "$API_COMPAT_TEST" "$CLIENT_SOURCE" "$HUD_SOURCE"; do
  test -s "$path" || fail "missing required input $path"
done

for token in \
  'Inventory Protocol Compatibility' \
  'Current Decision' \
  'Current Wire Contract' \
  'Inventory Snapshot Contract' \
  'Inventory Action Contract' \
  'Item Entity Pickup Contract' \
  'Compatibility Rules' \
  'inventory_protocol_status=item_entity_pickup_guarded' \
  '`Packet.block_action = 3`' \
  '`Packet.inventory_snapshot = 4`' \
  '`Packet.inventory_action = 5`' \
  '`Packet.item_entities = 6`' \
  '`Packet.item_pickup = 7`' \
  '`ClientPosition.player_id = 4`' \
  '`InventorySlot.block_id = 1`' \
  '`InventorySlot.count = 2`' \
  '`InventorySnapshot.slots = 1`' \
  '`InventorySnapshot.selected_slot = 2`' \
  '`InventorySnapshot.selected_tool_slot = 3`' \
  '`InventoryAction.action = 1`' \
  '`InventoryAction.slot = 2`' \
  '`InventoryAction.tool_slot = 3`' \
  '`InventoryAction SELECT_SLOT = 0`' \
  '`InventoryAction SELECT_TOOL_SLOT = 1`' \
  '`ItemEntity.entity_id = 1`' \
  '`ItemEntity.item_id = 2`' \
  '`ItemEntity.count = 3`' \
  '`ItemEntity.x = 4`' \
  '`ItemEntity.y = 5`' \
  '`ItemEntity.z = 6`' \
  '`ItemEntitySnapshot.entities = 1`' \
  '`ItemEntitySnapshot.revision = 2`' \
  '`ItemPickupAction.entity_id = 1`' \
  'BlockAction` fields `1` through `5` stay fixed'; do
  require_token "$DESIGN_DOC" "$token"
done

require_token "$PROTOCOL_DOC" 'Inventory protocol compatibility planning lives in `docs/INVENTORY_PROTOCOL_COMPATIBILITY.md`.'
require_token "$PROTOCOL_DOC" '`Packet.block_action = 3`'
require_token "$PROTOCOL_DOC" '`Packet.inventory_snapshot = 4`'
require_token "$PROTOCOL_DOC" '`Packet.inventory_action = 5`'
require_token "$PROTOCOL_DOC" '`Packet.item_entities = 6`'
require_token "$PROTOCOL_DOC" '`Packet.item_pickup = 7`'
require_token "$PROTOCOL_DOC" '`ClientPosition.player_id = 4`'
require_token "$PROTOCOL_DOC" '`InventorySnapshot.selected_tool_slot = 3`'
require_token "$PROTOCOL_DOC" '`InventoryAction.tool_slot = 3`'
require_token "$PROTOCOL_DOC" '`InventoryAction SELECT_TOOL_SLOT = 1`'
require_token "$SERVER_INVENTORY_DOC" 'Server Inventory Foundation'
require_token "$SERVER_INVENTORY_DOC" 'session-owned inventory'
require_token "$SERVER_INVENTORY_DOC" 'selectedInventorySlot'
require_token "$SERVER_INVENTORY_DOC" 'player_inventory_persistence=rocksdb_guarded'
require_token "$SERVER_INVENTORY_DOC" 'item_entity_pickup=live_server_guarded'
require_token "$GAMEPLAY_DOC" 'Server Inventory Foundation'
require_token "$GAMEPLAY_DOC" 'server_inventory_status=session_guarded'
require_token "$GAMEPLAY_DOC" 'server_inventory_persistence=rocksdb_guarded'
require_token "$GAMEPLAY_DOC" 'item_entity_pickup=live_server_guarded'
require_token "$PROTO_SCHEMA" 'message Packet'
require_token "$PROTO_SCHEMA" 'oneof payload'
require_token "$PROTO_SCHEMA" 'string player_id = 4;'
require_token "$PROTO_SCHEMA" 'message InventorySlot'
require_token "$PROTO_SCHEMA" 'message InventorySnapshot'
require_token "$PROTO_SCHEMA" 'message InventoryAction'
require_token "$PROTO_SCHEMA" 'ChunkData chunk = 1;'
require_token "$PROTO_SCHEMA" 'ClientPosition position = 2;'
require_token "$PROTO_SCHEMA" 'BlockAction block_action = 3;'
require_token "$PROTO_SCHEMA" 'InventorySnapshot inventory_snapshot = 4;'
require_token "$PROTO_SCHEMA" 'InventoryAction inventory_action = 5;'
require_token "$PROTO_SCHEMA" 'ItemEntitySnapshot item_entities = 6;'
require_token "$PROTO_SCHEMA" 'ItemPickupAction item_pickup = 7;'
require_token "$PROTO_SCHEMA" 'uint32 block_id = 5;'
require_token "$PROTO_SCHEMA" 'uint32 selected_slot = 2;'
require_token "$PROTO_SCHEMA" 'uint32 selected_tool_slot = 3;'
require_token "$PROTO_SCHEMA" 'SELECT_TOOL_SLOT = 1;'
require_token "$PROTO_SCHEMA" 'uint32 tool_slot = 3;'
require_token "$PROTO_SCHEMA" 'message ItemEntity'
require_token "$PROTO_SCHEMA" 'uint64 entity_id = 1;'
require_token "$PROTO_SCHEMA" 'string item_id = 2;'
require_token "$PROTO_SCHEMA" 'uint32 count = 3;'
require_token "$PROTO_SCHEMA" 'float x = 4;'
require_token "$PROTO_SCHEMA" 'float y = 5;'
require_token "$PROTO_SCHEMA" 'float z = 6;'
require_token "$PROTO_SCHEMA" 'message ItemEntitySnapshot'
require_token "$PROTO_SCHEMA" 'repeated ItemEntity entities = 1;'
require_token "$PROTO_SCHEMA" 'uint64 revision = 2;'
require_token "$PROTO_SCHEMA" 'message ItemPickupAction'
require_token "$GO_GENERATED" 'Code generated by protoc-gen-go. DO NOT EDIT.'
require_token "$GO_GENERATED" 'type InventorySlot struct'
require_token "$GO_GENERATED" 'type InventorySnapshot struct'
require_token "$GO_GENERATED" 'type InventoryAction struct'
require_token "$GO_GENERATED" 'SelectedToolSlot uint32'
require_token "$GO_GENERATED" 'ToolSlot uint32'
require_token "$GO_GENERATED" 'InventoryAction_SELECT_TOOL_SLOT'
require_token "$GO_GENERATED" 'PlayerId string'
require_token "$GO_GENERATED" 'type ItemEntity struct'
require_token "$GO_GENERATED" 'type ItemEntitySnapshot struct'
require_token "$GO_GENERATED" 'type ItemPickupAction struct'
require_token "$GO_GENERATED" 'type Packet_InventorySnapshot struct'
require_token "$GO_GENERATED" 'type Packet_InventoryAction struct'
require_token "$GO_GENERATED" 'type Packet_ItemEntities struct'
require_token "$GO_GENERATED" 'type Packet_ItemPickup struct'
require_token "$API_SCHEMA_TEST" 'TestClientPositionFieldNumbersAreStable'
require_token "$API_SCHEMA_TEST" 'TestInventorySnapshotFieldNumbersAreStable'
require_token "$API_SCHEMA_TEST" 'TestInventoryActionFieldNumbersAreStable'
require_token "$API_SCHEMA_TEST" 'TestItemEntityFieldNumbersAreStable'
require_token "$API_COMPAT_TEST" 'inventory snapshot payload tag 4'
require_token "$API_COMPAT_TEST" 'inventory snapshot selected tool slot field tag 3'
require_token "$API_COMPAT_TEST" 'inventory action payload tag 5'
require_token "$API_COMPAT_TEST" 'inventory tool action payload tag 5'
require_token "$API_COMPAT_TEST" 'item entity snapshot payload tag 6'
require_token "$API_COMPAT_TEST" 'item pickup payload tag 7'
require_token "$API_COMPAT_TEST" 'position player id field tag 4'
require_token "$SERVER_SOURCE" 'sendInventorySnapshotToSession'
require_token "$SERVER_SOURCE" 'inventorySnapshotPacket'
require_token "$SERVER_SOURCE" 'inventorySnapshot(inventory playerinventory.Inventory, selectedSlot uint32, selectedToolSlot uint32)'
require_token "$SERVER_SOURCE" 'bindPlayerInventoryFromPosition'
require_token "$SERVER_SOURCE" 'normalizedPlayerID'
require_token "$SERVER_SOURCE" 'case *api.Packet_InventoryAction:'
require_token "$SERVER_SOURCE" 'client.selectInventorySlot(action.Slot)'
require_token "$SERVER_SOURCE" 'case api.InventoryAction_SELECT_TOOL_SLOT:'
require_token "$SERVER_SOURCE" 'client.selectToolSlot(action.ToolSlot)'
require_token "$SERVER_SOURCE" 'case *api.Packet_ItemPickup:'
require_token "$SERVER_SOURCE" 'sendItemEntitySnapshotToSession'
require_token "$SERVER_SOURCE" 'collectItemEntityForSession(client, action.EntityId)'
require_token "$SERVER_TEST" 'TestInventorySnapshotPacketUsesSessionInventorySlots'
require_token "$SERVER_TEST" 'TestSendInventorySnapshotToSessionWritesInventorySnapshot'
require_token "$SERVER_TEST" 'TestHandleConnectionSendsInventorySnapshotBeforeInitialChunks'
require_token "$SERVER_TEST" 'TestHandleClientPacketInventoryActionSelectsSlotAndSendsSnapshot'
require_token "$SERVER_TEST" 'TestHandleClientPacketInventoryActionSelectsToolSlotAndSendsSnapshot'
require_token "$SERVER_TEST" 'TestHandleClientPacketInventoryActionRejectsInvalidToolSlot'
require_token "$SERVER_TEST" 'TestHandleClientPacketInventoryActionRejectsUnavailableSlot'
require_token "$SERVER_TEST" 'TestHandleClientPacketPlaceSendsInventorySnapshotAfterCountedPlacement'
require_token "$SERVER_TEST" 'TestHandleClientPacketDestroySpawnsItemEntityAndSendsSnapshot'
require_token "$SERVER_TEST" 'TestHandleClientPacketPickupPersistsCollectedCountedDrop'
require_token "$SERVER_TEST" 'TestHandleClientPacketPickupRejectsOutOfReachEntity'
require_token "$SERVER_TEST" 'TestHandleClientPacketPositionLoadsPersistedPlayerInventory'
require_token "$FRAMING_TEST" 'snapshotPacket.GetInventorySnapshot()'
require_token "$CLIENT_SOURCE" 'AuthoritativeInventorySlot'
require_token "$CLIENT_SOURCE" 'authoritative_inventory_slots_from_snapshot'
require_token "$CLIENT_SOURCE" 'LOCAL_PLAYER_ID'
require_token "$CLIENT_SOURCE" 'client_position_packet'
require_token "$CLIENT_SOURCE" 'Payload::InventorySnapshot'
require_token "$CLIENT_SOURCE" 'Payload::ItemEntities'
require_token "$CLIENT_SOURCE" 'inventory_action_select_slot_packet'
require_token "$CLIENT_SOURCE" 'inventory_action_select_tool_slot_packet'
require_token "$CLIENT_SOURCE" 'item_pickup_action_packet'
require_token "$CLIENT_SOURCE" 'Payload::InventoryAction'
require_token "$CLIENT_SOURCE" 'fn on_hotbar_selected'
require_token "$CLIENT_SOURCE" 'fn on_tool_slot_selected'
require_token "$CLIENT_SOURCE" 'authoritative_tool_text'
require_token "$CLIENT_SOURCE" 'selected_tool_slot'
require_token "$CLIENT_SOURCE" 'inventory_snapshot_slots_copy_wire_slots'
require_token "$CLIENT_SOURCE" 'inventory_action_select_slot_packet_uses_wire_slot'
require_token "$CLIENT_SOURCE" 'inventory_action_select_tool_slot_packet_uses_wire_tool_slot'
require_token "$CLIENT_SOURCE" 'item_entity_snapshot_copies_authoritative_entities'
require_token "$CLIENT_SOURCE" 'item_pickup_action_packet_uses_wire_entity_id'
require_token "$CLIENT_SOURCE" 'client_position_packet_includes_local_player_id'
require_token "$HUD_SOURCE" 'tool_label'
require_token "$HUD_SOURCE" 'get_authoritative_tool_selected_slot'
require_token "$HUD_SOURCE" 'get_authoritative_tool_text'

schema_file_diff="$(git -C "$ROOT_DIR" diff --name-only -- api/schema/packets.proto | awk 'END { print NR + 0 }')"
generated_file_diff="$(git -C "$ROOT_DIR" diff --name-only -- server/pkg/api/packets.pb.go | awk 'END { print NR + 0 }')"
schema_diff_count="$((schema_file_diff + generated_file_diff))"

if [ "$RUN_PROTOCOL_GATE" = "1" ]; then
  sh "$ROOT_DIR/scripts/protocol_generated_drift_gate.sh" "$ROOT_DIR/logs/protocol_generated_drift_current" > "$OUT_DIR/protocol-generated-drift-run.txt"
fi
if [ "$RUN_SERVER_INVENTORY_GATE" = "1" ] && [ "$schema_diff_count" = "0" ]; then
  sh "$ROOT_DIR/scripts/server_inventory_foundation_gate.sh" "$ROOT_DIR/logs/server_inventory_foundation_current" > "$OUT_DIR/server-inventory-foundation-run.txt"
fi
if [ "$RUN_GAMEPLAY_GATE" = "1" ] && [ "$schema_diff_count" = "0" ]; then
  sh "$ROOT_DIR/scripts/gameplay_loop_foundation_gate.sh" "$ROOT_DIR/logs/gameplay_loop_foundation_current" > "$OUT_DIR/gameplay-loop-foundation-run.txt"
fi

for path in "$PROTOCOL_SUMMARY" "$SERVER_INVENTORY_SUMMARY" "$GAMEPLAY_SUMMARY"; do
  test -s "$path" || fail "missing required summary $path"
done

protocol_status="$(field_metric status "$PROTOCOL_SUMMARY")"
protocol_schema_diff="$(field_metric schema_diff "$PROTOCOL_SUMMARY")"
protocol_generated_diff="$(field_metric generated_diff "$PROTOCOL_SUMMARY")"
server_inventory_status="$(field_metric status "$SERVER_INVENTORY_SUMMARY")"
server_inventory_guard="$(field_metric server_inventory_status "$SERVER_INVENTORY_SUMMARY")"
server_inventory_block_action="$(field_metric block_action_inventory "$SERVER_INVENTORY_SUMMARY")"
server_inventory_persistence="$(field_metric player_inventory_persistence "$SERVER_INVENTORY_SUMMARY")"
server_item_entity_pickup="$(field_metric item_entity_pickup "$SERVER_INVENTORY_SUMMARY")"
server_inventory_protocol_change="$(field_metric active_protocol_change "$SERVER_INVENTORY_SUMMARY")"
server_inventory_storage_change="$(field_metric active_storage_change "$SERVER_INVENTORY_SUMMARY")"
gameplay_status="$(field_metric status "$GAMEPLAY_SUMMARY")"
gameplay_inventory_guard="$(field_metric server_inventory_status "$GAMEPLAY_SUMMARY")"
gameplay_block_action_guard="$(field_metric server_inventory_block_action "$GAMEPLAY_SUMMARY")"
gameplay_inventory_persistence="$(field_metric server_inventory_persistence "$GAMEPLAY_SUMMARY")"
gameplay_item_entity_pickup="$(field_metric item_entity_pickup "$GAMEPLAY_SUMMARY")"
gameplay_protocol_change="$(field_metric active_protocol_change "$GAMEPLAY_SUMMARY")"

awk \
  -v protocol_status="${protocol_status:-missing}" \
  -v protocol_schema_diff="${protocol_schema_diff:-1}" \
  -v protocol_generated_diff="${protocol_generated_diff:-1}" \
  -v server_inventory_status="${server_inventory_status:-missing}" \
  -v server_inventory_guard="${server_inventory_guard:-missing}" \
  -v server_inventory_block_action="${server_inventory_block_action:-missing}" \
  -v server_inventory_persistence="${server_inventory_persistence:-missing}" \
  -v server_item_entity_pickup="${server_item_entity_pickup:-missing}" \
  -v server_inventory_protocol_change="${server_inventory_protocol_change:-1}" \
  -v server_inventory_storage_change="${server_inventory_storage_change:-1}" \
  -v gameplay_status="${gameplay_status:-missing}" \
  -v gameplay_inventory_guard="${gameplay_inventory_guard:-missing}" \
  -v gameplay_block_action_guard="${gameplay_block_action_guard:-missing}" \
  -v gameplay_inventory_persistence="${gameplay_inventory_persistence:-missing}" \
  -v gameplay_item_entity_pickup="${gameplay_item_entity_pickup:-missing}" \
  -v gameplay_protocol_change="${gameplay_protocol_change:-1}" \
  -v schema_file_diff="$schema_file_diff" \
  -v generated_file_diff="$generated_file_diff" \
  -v schema_diff_count="$schema_diff_count" \
  -v design_doc="$DESIGN_DOC" \
  -v protocol_summary="$PROTOCOL_SUMMARY" \
  -v server_inventory_summary="$SERVER_INVENTORY_SUMMARY" \
  -v gameplay_summary="$GAMEPLAY_SUMMARY" '
  BEGIN {
    status = "pass"
    reason = "ok"
    inventory_protocol_status = "item_entity_pickup_guarded"
    current_wire_contract = "block_action_inventory_snapshot_action_tool_action_item_entity_pickup_and_player_id"
    future_packet_tags = "packet_gt_7"
    future_block_action_fields = "block_action_gt_5"
    protocol_generated_drift = "guarded"
    position_identity_schema = "tag_4_guarded"
    inventory_snapshot_schema = "tag_4_guarded"
    inventory_action_schema = "tag_5_guarded"
    tool_selection_schema = "field_3_guarded"
    item_entity_snapshot_schema = "tag_6_guarded"
    item_pickup_schema = "tag_7_guarded"
    server_inventory_report = server_inventory_guard
    gameplay_inventory_status = gameplay_inventory_guard

    protocol_ok = protocol_status == "pass" &&
      protocol_schema_diff + 0 == protocol_generated_diff + 0
	    if (schema_diff_count + 0 != 0) {
	      server_ok = server_inventory_status == "pass" &&
	        server_inventory_guard == "session_guarded" &&
	        server_inventory_block_action == "session_guarded"
	      gameplay_ok = gameplay_status == "pass" &&
	        gameplay_inventory_guard == "session_guarded" &&
	        gameplay_block_action_guard == "session_guarded"
    } else {
      server_ok = server_inventory_status == "pass" &&
        server_inventory_guard == "session_guarded" &&
        server_inventory_block_action == "session_guarded" &&
        server_item_entity_pickup == "live_server_guarded" &&
        server_inventory_persistence == "rocksdb_guarded" &&
        server_inventory_storage_change + 0 == 0
      gameplay_ok = gameplay_status == "pass" &&
        gameplay_inventory_guard == "session_guarded" &&
        gameplay_block_action_guard == "session_guarded" &&
        gameplay_item_entity_pickup == "live_server_guarded" &&
        gameplay_inventory_persistence == "rocksdb_guarded"
    }

    if ((schema_file_diff + 0) != (generated_file_diff + 0)) {
      status = "fail"
      reason = "partial_schema_generated_diff"
    } else if (schema_diff_count + 0 != 0 && schema_diff_count + 0 != 2) {
      status = "fail"
      reason = "unexpected_schema_diff_count"
    } else if (!protocol_ok) {
      status = "fail"
      reason = "protocol_drift_not_clean"
    } else if (!server_ok) {
      status = "fail"
      reason = "server_inventory_not_clean"
    } else if (!gameplay_ok) {
      status = "fail"
      reason = "gameplay_inventory_not_clean"
    }

    printf("inventory_protocol_compatibility status=%s reason=%s inventory_protocol_status=%s active_schema_change=%d current_wire_contract=%s position_identity_schema=%s inventory_snapshot_schema=%s inventory_action_schema=%s tool_selection_schema=%s item_entity_snapshot_schema=%s item_pickup_schema=%s future_packet_tags=%s future_block_action_fields=%s protocol_generated_drift=%s server_inventory_status=%s gameplay_inventory_status=%s protocol_summary=%s server_inventory_summary=%s gameplay_summary=%s design_doc=%s\n", status, reason, inventory_protocol_status, schema_diff_count, current_wire_contract, position_identity_schema, inventory_snapshot_schema, inventory_action_schema, tool_selection_schema, item_entity_snapshot_schema, item_pickup_schema, future_packet_tags, future_block_action_fields, protocol_generated_drift, server_inventory_report, gameplay_inventory_status, protocol_summary, server_inventory_summary, gameplay_summary, design_doc)
    if (status != "pass") {
      exit 1
    }
  }
' > "$SUMMARY_PATH" || {
  cat "$SUMMARY_PATH" >&2 || true
  fail "inventory protocol compatibility gate failed"
}

cat "$SUMMARY_PATH"
echo "Inventory protocol compatibility artifacts: $OUT_DIR"
