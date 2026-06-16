#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/gameplay_loop_foundation"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

SUMMARY_PATH="$OUT_DIR/gameplay-loop-foundation-summary.txt"
DESIGN_DOC="${RUMPELMC_GAMEPLAY_LOOP_DOC:-"$ROOT_DIR/docs/GAMEPLAY_LOOP_FOUNDATION.md"}"
PROTOCOL_DOC="${RUMPELMC_GAMEPLAY_LOOP_PROTOCOL_DOC:-"$ROOT_DIR/docs/PROTOCOL.md"}"
PLAYER_SOURCE="${RUMPELMC_GAMEPLAY_LOOP_PLAYER_SOURCE:-"$ROOT_DIR/client/rust_ext/src/player.rs"}"
CLIENT_SOURCE="${RUMPELMC_GAMEPLAY_LOOP_CLIENT_SOURCE:-"$ROOT_DIR/client/rust_ext/src/lib.rs"}"
SERVER_SOURCE="${RUMPELMC_GAMEPLAY_LOOP_SERVER_SOURCE:-"$ROOT_DIR/server/pkg/network/server.go"}"
WORLD_SOURCE="${RUMPELMC_GAMEPLAY_LOOP_WORLD_SOURCE:-"$ROOT_DIR/server/pkg/world/world.go"}"
SERVER_MAIN="${RUMPELMC_GAMEPLAY_LOOP_SERVER_MAIN:-"$ROOT_DIR/server/cmd/server/main.go"}"
CLIENT_STATE_SUMMARY="${RUMPELMC_GAMEPLAY_LOOP_CLIENT_STATE_SUMMARY:-"$ROOT_DIR/logs/client_state_machine_hardening_current/client-state-machine-hardening-summary.txt"}"
BLOCK_EDIT_PERSISTENCE_SUMMARY="${RUMPELMC_GAMEPLAY_LOOP_BLOCK_EDIT_PERSISTENCE_SUMMARY:-"$ROOT_DIR/logs/block_edit_persistence_current/block-edit-persistence-summary.txt"}"
SERVER_INVENTORY_SUMMARY="${RUMPELMC_GAMEPLAY_LOOP_SERVER_INVENTORY_SUMMARY:-"$ROOT_DIR/logs/server_inventory_foundation_current/server-inventory-foundation-summary.txt"}"
RUN_RUST_TESTS="${RUMPELMC_GAMEPLAY_LOOP_RUN_RUST_TESTS:-1}"
RUN_GO_TESTS="${RUMPELMC_GAMEPLAY_LOOP_RUN_GO_TESTS:-1}"

mkdir -p "$OUT_DIR"

fail() {
  echo "gameplay_loop_foundation_gate: $*" >&2
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

for path in "$DESIGN_DOC" "$PROTOCOL_DOC" "$PLAYER_SOURCE" "$CLIENT_SOURCE" "$SERVER_SOURCE" "$WORLD_SOURCE" "$SERVER_MAIN" "$CLIENT_STATE_SUMMARY"; do
  test -s "$path" || fail "missing required input $path"
done

for token in \
  'Current Mining And Building Loop' \
  'Inventory Foundation' \
  'Persistence Boundary' \
  'Deferred Work' \
  'Compatibility Rules' \
  'Server Inventory Foundation' \
  'Block 41' \
  'Do not add inventory fields to `api/schema/packets.proto`'; do
  require_token "$DESIGN_DOC" "$token"
done

require_token "$PROTOCOL_DOC" '`Packet.block_action = 3`'
require_token "$PLAYER_SOURCE" 'struct InventorySlot'
require_token "$PLAYER_SOURCE" 'PLAYER_HOTBAR_SLOTS'
require_token "$PLAYER_SOURCE" 'CREATIVE_HOTBAR_STACK_COUNT'
require_token "$PLAYER_SOURCE" 'selected_hotbar_slot: usize'
require_token "$PLAYER_SOURCE" 'hotbar: [InventorySlot; PLAYER_HOTBAR_SLOTS]'
require_token "$PLAYER_SOURCE" 'fn initial_hotbar_inventory'
require_token "$PLAYER_SOURCE" 'fn inventory_slot_can_place'
require_token "$PLAYER_SOURCE" 'fn first_placeable_hotbar_slot'
require_token "$PLAYER_SOURCE" 'fn selected_block_for_hotbar_slot'
require_token "$PLAYER_SOURCE" 'fn selected_hotbar_state_after_request'
require_token "$PLAYER_SOURCE" 'fn inventory_has_placeable_block'
require_token "$PLAYER_SOURCE" 'fn hotbar_key_for_slot'
require_token "$PLAYER_SOURCE" 'block_broken'
require_token "$PLAYER_SOURCE" 'block_placed'
require_token "$PLAYER_SOURCE" 'initial_hotbar_inventory_contains_placeable_blocks'
require_token "$PLAYER_SOURCE" 'inventory_slot_can_place_requires_count_and_placeable_block'
require_token "$PLAYER_SOURCE" 'inventory_has_placeable_block_accepts_only_available_hotbar_blocks'
require_token "$PLAYER_SOURCE" 'hotbar_key_mapping_is_bounded_to_inventory_slots'
require_token "$PLAYER_SOURCE" 'hotbar_first_placeable_slot_picks_available_block'
require_token "$PLAYER_SOURCE" 'selected_hotbar_state_tracks_placeable_slot'
require_token "$PLAYER_SOURCE" 'selected_hotbar_state_ignores_unplaceable_or_empty_slot'
require_token "$CLIENT_SOURCE" 'fn on_block_broken'
require_token "$CLIENT_SOURCE" 'fn on_block_placed'
require_token "$CLIENT_SOURCE" 'BlockAction'
require_token "$SERVER_SOURCE" 'case *api.Packet_BlockAction:'
require_token "$SERVER_SOURCE" 'world.IsPlaceable(block)'
require_token "$SERVER_SOURCE" 's.world.SetBlockGlobal'
require_token "$WORLD_SOURCE" 'func (w *World) SetBlockGlobal'
require_token "$WORLD_SOURCE" 'w.store.SaveChunk(chunk)'
require_token "$SERVER_MAIN" 'storage.OpenRocksChunkStore'

client_state_status="$(field_metric status "$CLIENT_STATE_SUMMARY")"
client_state_protocol_change="$(field_metric active_protocol_change "$CLIENT_STATE_SUMMARY")"
test -s "$BLOCK_EDIT_PERSISTENCE_SUMMARY" || fail "missing required input $BLOCK_EDIT_PERSISTENCE_SUMMARY"
block_edit_persistence_status="$(field_metric status "$BLOCK_EDIT_PERSISTENCE_SUMMARY")"
block_edit_visual_path="$(field_metric visual_collision_gpu_path "$BLOCK_EDIT_PERSISTENCE_SUMMARY")"
block_edit_active_protocol_change="$(field_metric active_protocol_change "$BLOCK_EDIT_PERSISTENCE_SUMMARY")"
block_edit_persisted_visual_smoke="$(field_metric persisted_visual_smoke "$BLOCK_EDIT_PERSISTENCE_SUMMARY")"
block_edit_persisted_visual_smoke_status="$(field_metric persisted_visual_smoke_status "$BLOCK_EDIT_PERSISTENCE_SUMMARY")"
block_edit_persisted_visual_scenarios="$(field_metric persisted_visual_scenarios "$BLOCK_EDIT_PERSISTENCE_SUMMARY")"
block_edit_persisted_visual_place_reload_status="$(field_metric persisted_visual_place_reload_status "$BLOCK_EDIT_PERSISTENCE_SUMMARY")"
block_edit_persisted_visual_destroy_after_reload_status="$(field_metric persisted_visual_destroy_after_reload_status "$BLOCK_EDIT_PERSISTENCE_SUMMARY")"
block_edit_persisted_visual_edge_place_status="$(field_metric persisted_visual_edge_place_status "$BLOCK_EDIT_PERSISTENCE_SUMMARY")"
test -s "$SERVER_INVENTORY_SUMMARY" || fail "missing required input $SERVER_INVENTORY_SUMMARY"
server_inventory_status="$(field_metric status "$SERVER_INVENTORY_SUMMARY")"
server_inventory_guard="$(field_metric server_inventory_status "$SERVER_INVENTORY_SUMMARY")"
server_inventory_block_action="$(field_metric block_action_inventory "$SERVER_INVENTORY_SUMMARY")"
server_inventory_protocol_change="$(field_metric active_protocol_change "$SERVER_INVENTORY_SUMMARY")"
server_inventory_storage_change="$(field_metric active_storage_change "$SERVER_INVENTORY_SUMMARY")"
proto_diff_count="$(git -C "$ROOT_DIR" diff --name-only -- api/schema/packets.proto server/pkg/api/packets.pb.go | awk 'END { print NR + 0 }')"

inventory_tests="skipped"
if [ "$RUN_RUST_TESTS" = "1" ]; then
  if (cd "$ROOT_DIR/client/rust_ext" && cargo test --lib inventory > "$OUT_DIR/cargo-test-inventory.txt" 2>&1 && cargo test --lib hotbar >> "$OUT_DIR/cargo-test-inventory.txt" 2>&1); then
    inventory_tests="pass"
  else
    cat "$OUT_DIR/cargo-test-inventory.txt" >&2 || true
    inventory_tests="fail"
  fi
fi

server_tests="skipped"
if [ "$RUN_GO_TESTS" = "1" ]; then
  if (cd "$ROOT_DIR/server" && go test ./pkg/world ./pkg/network ./pkg/storage > "$OUT_DIR/go-test-gameplay-foundation.txt" 2>&1); then
    server_tests="pass"
  else
    cat "$OUT_DIR/go-test-gameplay-foundation.txt" >&2 || true
    server_tests="fail"
  fi
fi

awk \
  -v client_state_status="${client_state_status:-missing}" \
  -v client_state_protocol_change="${client_state_protocol_change:-1}" \
  -v block_edit_persistence_status="${block_edit_persistence_status:-missing}" \
  -v block_edit_visual_path="${block_edit_visual_path:-missing}" \
  -v block_edit_active_protocol_change="${block_edit_active_protocol_change:-1}" \
  -v block_edit_persisted_visual_smoke="${block_edit_persisted_visual_smoke:-missing}" \
  -v block_edit_persisted_visual_smoke_status="${block_edit_persisted_visual_smoke_status:-missing}" \
  -v block_edit_persisted_visual_scenarios="${block_edit_persisted_visual_scenarios:-0}" \
  -v block_edit_persisted_visual_place_reload_status="${block_edit_persisted_visual_place_reload_status:-missing}" \
  -v block_edit_persisted_visual_destroy_after_reload_status="${block_edit_persisted_visual_destroy_after_reload_status:-missing}" \
  -v block_edit_persisted_visual_edge_place_status="${block_edit_persisted_visual_edge_place_status:-missing}" \
  -v server_inventory_status="${server_inventory_status:-missing}" \
  -v server_inventory_guard="${server_inventory_guard:-missing}" \
  -v server_inventory_block_action="${server_inventory_block_action:-missing}" \
  -v server_inventory_protocol_change="${server_inventory_protocol_change:-1}" \
  -v server_inventory_storage_change="${server_inventory_storage_change:-1}" \
  -v proto_diff_count="$proto_diff_count" \
  -v inventory_tests="$inventory_tests" \
  -v server_tests="$server_tests" \
  -v design_doc="$DESIGN_DOC" \
  -v client_state_summary="$CLIENT_STATE_SUMMARY" \
  -v block_edit_persistence_summary="$BLOCK_EDIT_PERSISTENCE_SUMMARY" \
  -v server_inventory_summary="$SERVER_INVENTORY_SUMMARY" '
  BEGIN {
    status = "pass"
    reason = "ok"
    gameplay_loop_status = "foundation_guarded"
    inventory_foundation = "unit_guarded"
    hotbar_selection = "unit_guarded"
    server_edit_persistence = "store_save_boundary"
    block_edit_visual_ok = block_edit_persistence_status == "pass" &&
      block_edit_visual_path == "godot_persisted_reload_guarded" &&
      block_edit_active_protocol_change + 0 == 0 &&
      block_edit_persisted_visual_smoke == "godot_guarded" &&
      block_edit_persisted_visual_smoke_status == "pass" &&
      block_edit_persisted_visual_scenarios + 0 >= 3 &&
      block_edit_persisted_visual_place_reload_status == "pass" &&
      block_edit_persisted_visual_destroy_after_reload_status == "pass" &&
      block_edit_persisted_visual_edge_place_status == "pass"
    server_inventory_ok = server_inventory_status == "pass" &&
      server_inventory_guard == "session_guarded" &&
      server_inventory_block_action == "session_guarded" &&
      server_inventory_protocol_change + 0 == 0 &&
      server_inventory_storage_change + 0 == 0
    full_reload_persistence = block_edit_visual_ok ? "block_41_visual_guarded" : "missing_block_41_visual_proof"
    active_protocol_change = proto_diff_count + 0

    state_ok = client_state_status == "pass" && client_state_protocol_change + 0 == 0
    rust_ok = inventory_tests == "pass" || inventory_tests == "skipped"
    go_ok = server_tests == "pass" || server_tests == "skipped"

    if (active_protocol_change != 0) {
      status = "fail"
      reason = "protocol_diff_present"
    } else if (!state_ok) {
      status = "fail"
      reason = "client_state_gate_not_clean"
    } else if (!rust_ok) {
      status = "fail"
      reason = "inventory_tests_failed"
    } else if (!go_ok) {
      status = "fail"
      reason = "server_tests_failed"
    } else if (!block_edit_visual_ok) {
      status = "fail"
      reason = "block_41_visual_proof_not_clean"
    } else if (!server_inventory_ok) {
      status = "fail"
      reason = "server_inventory_gate_not_clean"
    }

    printf("gameplay_loop_foundation status=%s reason=%s gameplay_loop_status=%s inventory_foundation=%s hotbar_selection=%s server_inventory_status=%s server_inventory_block_action=%s server_edit_persistence=%s active_protocol_change=%d inventory_tests=%s server_tests=%s full_reload_persistence=%s block_edit_persistence_status=%s block_edit_visual_path=%s block_edit_active_protocol_change=%d block_edit_persisted_visual_smoke=%s block_edit_persisted_visual_smoke_status=%s block_edit_persisted_visual_scenarios=%d block_edit_persisted_visual_place_reload_status=%s block_edit_persisted_visual_destroy_after_reload_status=%s block_edit_persisted_visual_edge_place_status=%s client_state_status=%s client_state_protocol_change=%d design_doc=%s client_state_summary=%s block_edit_persistence_summary=%s server_inventory_summary=%s\n", status, reason, gameplay_loop_status, inventory_foundation, hotbar_selection, server_inventory_guard, server_inventory_block_action, server_edit_persistence, active_protocol_change, inventory_tests, server_tests, full_reload_persistence, block_edit_persistence_status, block_edit_visual_path, block_edit_active_protocol_change, block_edit_persisted_visual_smoke, block_edit_persisted_visual_smoke_status, block_edit_persisted_visual_scenarios, block_edit_persisted_visual_place_reload_status, block_edit_persisted_visual_destroy_after_reload_status, block_edit_persisted_visual_edge_place_status, client_state_status, client_state_protocol_change, design_doc, client_state_summary, block_edit_persistence_summary, server_inventory_summary)
    if (status != "pass") {
      exit 1
    }
  }
' > "$SUMMARY_PATH" || {
  cat "$SUMMARY_PATH" >&2 || true
  fail "gameplay loop foundation gate failed"
}

cat "$SUMMARY_PATH"
echo "Gameplay loop foundation artifacts: $OUT_DIR"
