#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/item_entity_persistence"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

SUMMARY_PATH="$OUT_DIR/item-entity-persistence-summary.txt"
DESIGN_DOC="${RUMPELMC_ITEM_ENTITY_PERSISTENCE_DOC:-"$ROOT_DIR/docs/ITEM_ENTITY_PERSISTENCE.md"}"
STORAGE_DOC="${RUMPELMC_ITEM_ENTITY_STORAGE_DOC:-"$ROOT_DIR/docs/STORAGE.md"}"
STORAGE_SOURCE="${RUMPELMC_ITEM_ENTITY_STORAGE_SOURCE:-"$ROOT_DIR/server/pkg/storage/item_entities.go"}"
STORAGE_TEST="${RUMPELMC_ITEM_ENTITY_STORAGE_TEST:-"$ROOT_DIR/server/pkg/storage/rocksdb_test.go"}"
STATE_SOURCE="${RUMPELMC_ITEM_ENTITY_STATE_SOURCE:-"$ROOT_DIR/server/pkg/itementity/state.go"}"
NETWORK_SOURCE="${RUMPELMC_ITEM_ENTITY_NETWORK_SOURCE:-"$ROOT_DIR/server/pkg/network/server.go"}"
NETWORK_TEST="${RUMPELMC_ITEM_ENTITY_NETWORK_TEST:-"$ROOT_DIR/server/pkg/network/server_test.go"}"
SMOKE_SCRIPT="${RUMPELMC_ITEM_ENTITY_SMOKE_SCRIPT:-"$ROOT_DIR/scripts/player_item_entity_persistence_smoke.sh"}"
SMOKE_SUMMARY="${RUMPELMC_ITEM_ENTITY_SMOKE_SUMMARY:-"$ROOT_DIR/logs/player_item_entity_persistence_smoke_current/player-item-entity-persistence-smoke-summary.txt"}"
POLICY_SMOKE_SCRIPT="${RUMPELMC_ITEM_ENTITY_POLICY_SMOKE_SCRIPT:-"$ROOT_DIR/scripts/item_entity_policy_smoke.sh"}"
POLICY_SMOKE_SUMMARY="${RUMPELMC_ITEM_ENTITY_POLICY_SMOKE_SUMMARY:-"$ROOT_DIR/logs/item_entity_policy_current/item-entity-policy-summary.txt"}"
RUN_GO_TESTS="${RUMPELMC_ITEM_ENTITY_RUN_GO_TESTS:-1}"

mkdir -p "$OUT_DIR"

fail() {
  echo "item_entity_persistence_gate: $*" >&2
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

for path in "$DESIGN_DOC" "$STORAGE_DOC" "$STORAGE_SOURCE" "$STORAGE_TEST" "$STATE_SOURCE" "$NETWORK_SOURCE" "$NETWORK_TEST" "$SMOKE_SCRIPT" "$POLICY_SMOKE_SCRIPT"; do
  test -s "$path" || fail "missing required input $path"
done

for token in \
  'Item Entity Persistence' \
  'Current Contract' \
  'Restart Flow' \
  'Dropped Stack Merge And Despawn' \
  'item_entity_persistence=rocksdb_guarded' \
  'uncollected_drop_restart=live_server_guarded' \
  'pickup_after_restart=live_server_guarded' \
  'item_entity_policy=merge_despawn_guarded'; do
  require_token "$DESIGN_DOC" "$token"
done

require_token "$STORAGE_DOC" 'RocksDB item entity records use a separate `i e NUL` byte prefix'
require_token "$STORAGE_DOC" 'JSON version `2`'
require_token "$STATE_SOURCE" 'type State struct'
require_token "$STATE_SOURCE" 'type Entity struct'
require_token "$STATE_SOURCE" 'MaxEntityStackCount'
require_token "$STATE_SOURCE" 'SpawnedAtUnixMS'
require_token "$STORAGE_SOURCE" 'func (s *RocksChunkStore) LoadItemEntities'
require_token "$STORAGE_SOURCE" 'func (s *RocksChunkStore) SaveItemEntities'
require_token "$STORAGE_SOURCE" 'itemEntityRecordVersion'
require_token "$STORAGE_SOURCE" 'legacyItemEntityRecordVersion'
require_token "$STORAGE_SOURCE" 'SpawnedAtUnixMS'
require_token "$STORAGE_SOURCE" "[]byte{'i', 'e', 0}"
require_token "$STATE_SOURCE" 'MaxStateEntities'
require_token "$STORAGE_TEST" 'TestRocksChunkStoreItemEntitiesRoundTrip'
require_token "$STORAGE_TEST" 'TestRocksChunkStoreItemEntitiesLoadsLegacyVersionOneRecord'
require_token "$STORAGE_TEST" 'TestRocksChunkStoreItemEntitiesKeyIsSeparateFromChunkAndPlayerInventoryKey'
require_token "$STORAGE_TEST" 'TestRocksChunkStoreItemEntitiesRejectsCorruptPayload'
require_token "$STORAGE_TEST" 'TestRocksChunkStoreItemEntitiesRejectsInvalidRecords'
require_token "$NETWORK_SOURCE" 'type itemEntityStore interface'
require_token "$NETWORK_SOURCE" 'LoadItemEntities'
require_token "$NETWORK_SOURCE" 'SaveItemEntities'
require_token "$NETWORK_SOURCE" 'loadItemEntitiesFromStore'
require_token "$NETWORK_SOURCE" 'saveItemEntitiesLocked'
require_token "$NETWORK_SOURCE" 'configuredItemEntityDespawn'
require_token "$NETWORK_SOURCE" 'mergeItemEntityLocked'
require_token "$NETWORK_SOURCE" 'pruneExpiredItemEntitiesLocked'
require_token "$NETWORK_SOURCE" 'removeOldestItemEntityIfAtCapacityLocked'
require_token "$NETWORK_SOURCE" 'spawnItemEntityForBlock(previousBlock'
require_token "$NETWORK_SOURCE" 'collectItemEntityForSession(client, action.EntityId)'
require_token "$NETWORK_TEST" 'TestLoadItemEntitiesFromStoreRestoresSnapshotAndNextID'
require_token "$NETWORK_TEST" 'TestLoadItemEntitiesFromStorePrunesExpiredDrops'
require_token "$NETWORK_TEST" 'TestLoadItemEntitiesFromStoreTreatsLegacyTimestampAsFresh'
require_token "$NETWORK_TEST" 'TestSpawnItemEntityMergesNearbySameItemStack'
require_token "$NETWORK_TEST" 'TestSpawnItemEntityDoesNotMergeFullStack'
require_token "$NETWORK_TEST" 'TestHandleClientPacketDestroyPersistsItemEntityState'
require_token "$NETWORK_TEST" 'TestHandleClientPacketPickupPersistsCollectedCountedDrop'
require_token "$NETWORK_TEST" 'TestHandleClientPacketPickupRejectsExpiredEntityAndPersistsDespawn'
require_token "$NETWORK_TEST" 'TestHandleClientPacketPickupRollsBackWhenInventorySaveFails'
require_token "$NETWORK_TEST" 'TestHandleClientPacketPickupRollsBackInventoryWhenItemEntitySaveFails'
require_token "$SMOKE_SCRIPT" 'item_entity_persistence=live_server_guarded'
require_token "$SMOKE_SCRIPT" 'destroy-drop-expect'
require_token "$SMOKE_SCRIPT" 'item-entity-expect'
require_token "$SMOKE_SCRIPT" 'item-pickup-expect'
require_token "$SMOKE_SCRIPT" 'item-absent-expect'
require_token "$POLICY_SMOKE_SCRIPT" 'item_entity_policy=merge_despawn_guarded'
require_token "$POLICY_SMOKE_SCRIPT" 'destroy-merge-expect'
require_token "$POLICY_SMOKE_SCRIPT" 'RUMPELMC_SERVER_ITEM_ENTITY_DESPAWN_MS="$despawn_ms"'

test -s "$SMOKE_SUMMARY" || fail "missing required input $SMOKE_SUMMARY"
smoke_status="$(field_metric status "$SMOKE_SUMMARY")"
smoke_persistence="$(field_metric item_entity_persistence "$SMOKE_SUMMARY")"
smoke_drop_restart="$(field_metric uncollected_drop_restart "$SMOKE_SUMMARY")"
smoke_pickup_restart="$(field_metric pickup_after_restart "$SMOKE_SUMMARY")"
smoke_empty_restart="$(field_metric empty_after_pickup_restart "$SMOKE_SUMMARY")"
smoke_destroy_status="$(field_metric destroy_drop_status "$SMOKE_SUMMARY")"
smoke_verify_drop_status="$(field_metric verify_drop_restart_status "$SMOKE_SUMMARY")"
smoke_pickup_status="$(field_metric pickup_after_restart_status "$SMOKE_SUMMARY")"
smoke_verify_inventory_status="$(field_metric verify_inventory_restart_status "$SMOKE_SUMMARY")"
smoke_verify_empty_status="$(field_metric verify_empty_restart_status "$SMOKE_SUMMARY")"
smoke_restarts="$(field_metric server_restarts "$SMOKE_SUMMARY")"
smoke_protocol_change="$(field_metric protocol_change "$SMOKE_SUMMARY")"

test -s "$POLICY_SMOKE_SUMMARY" || fail "missing required input $POLICY_SMOKE_SUMMARY"
policy_smoke_status="$(field_metric status "$POLICY_SMOKE_SUMMARY")"
policy_guard="$(field_metric item_entity_policy "$POLICY_SMOKE_SUMMARY")"
policy_merge="$(field_metric dropped_stack_merge "$POLICY_SMOKE_SUMMARY")"
policy_despawn="$(field_metric despawn_restart "$POLICY_SMOKE_SUMMARY")"
policy_merge_status="$(field_metric merge_status "$POLICY_SMOKE_SUMMARY")"
policy_despawn_spawn_status="$(field_metric despawn_spawn_status "$POLICY_SMOKE_SUMMARY")"
policy_despawn_absent_status="$(field_metric despawn_absent_status "$POLICY_SMOKE_SUMMARY")"
policy_merged_count="$(field_metric expected_merged_count "$POLICY_SMOKE_SUMMARY")"
policy_restarts="$(field_metric server_restarts "$POLICY_SMOKE_SUMMARY")"
policy_protocol_change="$(field_metric protocol_change "$POLICY_SMOKE_SUMMARY")"

protocol_diff_count="$(git -C "$ROOT_DIR" diff --name-only -- api/schema/packets.proto server/pkg/api/packets.pb.go | awk 'END { print NR + 0 }')"
chunk_payload_diff_count="$(git -C "$ROOT_DIR" diff --name-only -- server/pkg/world api/schema/packets.proto server/pkg/api/packets.pb.go | awk 'END { print NR + 0 }')"

go_tests="skipped"
if [ "$RUN_GO_TESTS" = "1" ]; then
  if (cd "$ROOT_DIR/server" && go test ./pkg/itementity ./pkg/storage ./pkg/network ./cmd/player_inventory_reconnect_smoke > "$OUT_DIR/go-test-item-entity-persistence.txt" 2>&1); then
    go_tests="pass"
  else
    cat "$OUT_DIR/go-test-item-entity-persistence.txt" >&2 || true
    go_tests="fail"
  fi
fi

awk \
  -v protocol_diff_count="$protocol_diff_count" \
  -v chunk_payload_diff_count="$chunk_payload_diff_count" \
  -v go_tests="$go_tests" \
  -v smoke_status="${smoke_status:-missing}" \
  -v smoke_persistence="${smoke_persistence:-missing}" \
  -v smoke_drop_restart="${smoke_drop_restart:-missing}" \
  -v smoke_pickup_restart="${smoke_pickup_restart:-missing}" \
  -v smoke_empty_restart="${smoke_empty_restart:-missing}" \
  -v smoke_destroy_status="${smoke_destroy_status:-missing}" \
  -v smoke_verify_drop_status="${smoke_verify_drop_status:-missing}" \
  -v smoke_pickup_status="${smoke_pickup_status:-missing}" \
  -v smoke_verify_inventory_status="${smoke_verify_inventory_status:-missing}" \
  -v smoke_verify_empty_status="${smoke_verify_empty_status:-missing}" \
  -v smoke_restarts="${smoke_restarts:-0}" \
  -v smoke_protocol_change="${smoke_protocol_change:-1}" \
  -v policy_smoke_status="${policy_smoke_status:-missing}" \
  -v policy_guard="${policy_guard:-missing}" \
  -v policy_merge="${policy_merge:-missing}" \
  -v policy_despawn="${policy_despawn:-missing}" \
  -v policy_merge_status="${policy_merge_status:-missing}" \
  -v policy_despawn_spawn_status="${policy_despawn_spawn_status:-missing}" \
  -v policy_despawn_absent_status="${policy_despawn_absent_status:-missing}" \
  -v policy_merged_count="${policy_merged_count:-0}" \
  -v policy_restarts="${policy_restarts:-0}" \
  -v policy_protocol_change="${policy_protocol_change:-1}" \
  -v design_doc="$DESIGN_DOC" \
  -v storage_doc="$STORAGE_DOC" \
  -v smoke_summary="$SMOKE_SUMMARY" \
  -v policy_smoke_summary="$POLICY_SMOKE_SUMMARY" '
  BEGIN {
    status = "pass"
    reason = "ok"
    item_entity_persistence = "rocksdb_guarded"
    uncollected_drop_restart = "live_server_guarded"
    pickup_after_restart = "live_server_guarded"
    empty_after_pickup_restart = "live_server_guarded"
    item_entity_policy = "merge_despawn_guarded"
    dropped_stack_merge = "live_server_guarded"
    despawn_restart = "live_server_guarded"
    storage_status = "json_record_guarded"
    go_ok = go_tests == "pass" || go_tests == "skipped"
    smoke_ok = smoke_status == "pass" &&
      smoke_persistence == "live_server_guarded" &&
      smoke_drop_restart == "live_server_guarded" &&
      smoke_pickup_restart == "live_server_guarded" &&
      smoke_empty_restart == "live_server_guarded" &&
      smoke_destroy_status == "pass" &&
      smoke_verify_drop_status == "pass" &&
      smoke_pickup_status == "pass" &&
      smoke_verify_inventory_status == "pass" &&
      smoke_verify_empty_status == "pass" &&
      smoke_restarts + 0 >= 4 &&
      smoke_protocol_change + 0 == 0
    policy_ok = policy_smoke_status == "pass" &&
      policy_guard == "merge_despawn_guarded" &&
      policy_merge == "live_server_guarded" &&
      policy_despawn == "live_server_guarded" &&
      policy_merge_status == "pass" &&
      policy_despawn_spawn_status == "pass" &&
      policy_despawn_absent_status == "pass" &&
      policy_merged_count + 0 == 2 &&
      policy_restarts + 0 >= 1 &&
      policy_protocol_change + 0 == 0

    if (protocol_diff_count + 0 != 0) {
      status = "fail"
      reason = "protocol_diff_present"
    } else if (chunk_payload_diff_count + 0 != 0) {
      status = "fail"
      reason = "chunk_payload_diff_present"
    } else if (!go_ok) {
      status = "fail"
      reason = "go_tests_failed"
    } else if (!smoke_ok) {
      status = "fail"
      reason = "smoke_not_clean"
    } else if (!policy_ok) {
      status = "fail"
      reason = "policy_smoke_not_clean"
    }

    printf("item_entity_persistence_gate status=%s reason=%s item_entity_persistence=%s item_entity_policy=%s dropped_stack_merge=%s despawn_restart=%s storage_status=%s uncollected_drop_restart=%s pickup_after_restart=%s empty_after_pickup_restart=%s active_protocol_change=%d active_chunk_payload_change=%d go_tests=%s smoke_status=%s policy_smoke_status=%s design_doc=%s storage_doc=%s smoke_summary=%s policy_smoke_summary=%s\n", status, reason, item_entity_persistence, item_entity_policy, dropped_stack_merge, despawn_restart, storage_status, uncollected_drop_restart, pickup_after_restart, empty_after_pickup_restart, protocol_diff_count, chunk_payload_diff_count, go_tests, smoke_status, policy_smoke_status, design_doc, storage_doc, smoke_summary, policy_smoke_summary)
    exit(status == "pass" ? 0 : 1)
  }
' > "$SUMMARY_PATH"

cat "$SUMMARY_PATH"
