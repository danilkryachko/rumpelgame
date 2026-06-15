#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/block_edit_persistence"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

SUMMARY_PATH="$OUT_DIR/block-edit-persistence-summary.txt"
DESIGN_DOC="${RUMPELMC_BLOCK_EDIT_PERSISTENCE_DOC:-"$ROOT_DIR/docs/BLOCK_EDIT_PERSISTENCE_TRACK.md"}"
STORAGE_DOC="${RUMPELMC_BLOCK_EDIT_PERSISTENCE_STORAGE_DOC:-"$ROOT_DIR/docs/STORAGE.md"}"
WORLD_SOURCE="${RUMPELMC_BLOCK_EDIT_PERSISTENCE_WORLD_SOURCE:-"$ROOT_DIR/server/pkg/world/world.go"}"
WORLD_TEST="${RUMPELMC_BLOCK_EDIT_PERSISTENCE_WORLD_TEST:-"$ROOT_DIR/server/pkg/world/world_test.go"}"
NETWORK_SOURCE="${RUMPELMC_BLOCK_EDIT_PERSISTENCE_NETWORK_SOURCE:-"$ROOT_DIR/server/pkg/network/server.go"}"
CLIENT_SOURCE="${RUMPELMC_BLOCK_EDIT_PERSISTENCE_CLIENT_SOURCE:-"$ROOT_DIR/client/rust_ext/src/lib.rs"}"
GAMEPLAY_SUMMARY="${RUMPELMC_BLOCK_EDIT_PERSISTENCE_GAMEPLAY_SUMMARY:-"$ROOT_DIR/logs/gameplay_loop_foundation_current/gameplay-loop-foundation-summary.txt"}"
RUN_GO_TESTS="${RUMPELMC_BLOCK_EDIT_PERSISTENCE_RUN_GO_TESTS:-1}"
RUN_RUST_TESTS="${RUMPELMC_BLOCK_EDIT_PERSISTENCE_RUN_RUST_TESTS:-1}"

mkdir -p "$OUT_DIR"

fail() {
  echo "block_edit_persistence_gate: $*" >&2
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

for path in "$DESIGN_DOC" "$STORAGE_DOC" "$WORLD_SOURCE" "$WORLD_TEST" "$NETWORK_SOURCE" "$CLIENT_SOURCE" "$GAMEPLAY_SUMMARY"; do
  test -s "$path" || fail "missing required input $path"
done

for token in \
  'Persistence Contract' \
  'Added Unit Guard' \
  'Visual/Collision/GPU Update Path' \
  'Deferred Work' \
  'Compatibility Rules' \
  'Runtime edit -> server restart/reopen -> client reload visual smoke' \
  'Do not change the RocksDB key format'; do
  require_token "$DESIGN_DOC" "$token"
done

require_token "$STORAGE_DOC" 'Preserve persistence compatibility unless the task explicitly changes it.'
require_token "$STORAGE_DOC" 'Persisted chunk payloads use the exact byte output of `world.Chunk.Serialize()`'
require_token "$WORLD_SOURCE" 'func (w *World) SetBlockGlobal'
require_token "$WORLD_SOURCE" 'w.store.SaveChunk(chunk)'
require_token "$WORLD_SOURCE" 'w.store.LoadChunk(x, z)'
require_token "$WORLD_TEST" 'TestSetBlockGlobalPersistsEditedChunkForReload'
require_token "$WORLD_TEST" 'newSerializedChunkStore'
require_token "$WORLD_TEST" 'assertSnapshotBlock'
require_token "$NETWORK_SOURCE" 'case *api.Packet_BlockAction:'
require_token "$NETWORK_SOURCE" 's.world.SetBlockGlobal'
require_token "$CLIENT_SOURCE" 'fn update_chunk'
require_token "$CLIENT_SOURCE" 'chunk_dirty_update'
require_token "$CLIENT_SOURCE" 'chunk_update_needs_geometry_refresh'
require_token "$CLIENT_SOURCE" 'enqueue_dirty_chunk_subchunks'
require_token "$CLIENT_SOURCE" 'process_collision_refresh_queue'
require_token "$CLIENT_SOURCE" 'upload_gpu_subchunk'

gameplay_status="$(field_metric status "$GAMEPLAY_SUMMARY")"
gameplay_protocol_change="$(field_metric active_protocol_change "$GAMEPLAY_SUMMARY")"
proto_diff_count="$(git -C "$ROOT_DIR" diff --name-only -- api/schema/packets.proto server/pkg/api/packets.pb.go | awk 'END { print NR + 0 }')"

world_reload_test="skipped"
storage_tests="skipped"
network_tests="skipped"
if [ "$RUN_GO_TESTS" = "1" ]; then
  if (cd "$ROOT_DIR/server" && go test ./pkg/world -run TestSetBlockGlobalPersistsEditedChunkForReload > "$OUT_DIR/go-test-world-reload.txt" 2>&1); then
    world_reload_test="pass"
  else
    cat "$OUT_DIR/go-test-world-reload.txt" >&2 || true
    world_reload_test="fail"
  fi

  if [ "$world_reload_test" = "pass" ] && (cd "$ROOT_DIR/server" && go test ./pkg/storage > "$OUT_DIR/go-test-storage.txt" 2>&1); then
    storage_tests="pass"
  elif [ "$world_reload_test" = "pass" ]; then
    cat "$OUT_DIR/go-test-storage.txt" >&2 || true
    storage_tests="fail"
  fi

  if [ "$world_reload_test" = "pass" ] && [ "$storage_tests" = "pass" ] && (cd "$ROOT_DIR/server" && go test ./pkg/network > "$OUT_DIR/go-test-network.txt" 2>&1); then
    network_tests="pass"
  elif [ "$world_reload_test" = "pass" ] && [ "$storage_tests" = "pass" ]; then
    cat "$OUT_DIR/go-test-network.txt" >&2 || true
    network_tests="fail"
  fi
fi

dirty_update_tests="skipped"
if [ "$RUN_RUST_TESTS" = "1" ]; then
  if (cd "$ROOT_DIR/client/rust_ext" && cargo test --lib dirty > "$OUT_DIR/cargo-test-dirty.txt" 2>&1); then
    dirty_update_tests="pass"
  else
    cat "$OUT_DIR/cargo-test-dirty.txt" >&2 || true
    dirty_update_tests="fail"
  fi
fi

awk \
  -v gameplay_status="${gameplay_status:-missing}" \
  -v gameplay_protocol_change="${gameplay_protocol_change:-1}" \
  -v proto_diff_count="$proto_diff_count" \
  -v world_reload_test="$world_reload_test" \
  -v storage_tests="$storage_tests" \
  -v network_tests="$network_tests" \
  -v dirty_update_tests="$dirty_update_tests" \
  -v design_doc="$DESIGN_DOC" \
  -v gameplay_summary="$GAMEPLAY_SUMMARY" '
  BEGIN {
    status = "pass"
    reason = "ok"
    persistence_status = "unit_guarded"
    place_reload = "guarded"
    destroy_reload = "guarded"
    runtime_reload_smoke = "deferred"
    visual_collision_gpu_path = "existing_update_chunk_path"
    active_protocol_change = proto_diff_count + 0

    gameplay_ok = gameplay_status == "pass" && gameplay_protocol_change + 0 == 0
    go_ok = (world_reload_test == "pass" || world_reload_test == "skipped") &&
      (storage_tests == "pass" || storage_tests == "skipped") &&
      (network_tests == "pass" || network_tests == "skipped")
    rust_ok = dirty_update_tests == "pass" || dirty_update_tests == "skipped"

    if (active_protocol_change != 0) {
      status = "fail"
      reason = "protocol_diff_present"
    } else if (!gameplay_ok) {
      status = "fail"
      reason = "gameplay_foundation_not_clean"
    } else if (!go_ok) {
      status = "fail"
      reason = "go_persistence_tests_failed"
    } else if (!rust_ok) {
      status = "fail"
      reason = "dirty_update_tests_failed"
    }

    printf("block_edit_persistence status=%s reason=%s persistence_status=%s place_reload=%s destroy_reload=%s runtime_reload_smoke=%s visual_collision_gpu_path=%s active_protocol_change=%d world_reload_test=%s storage_tests=%s network_tests=%s dirty_update_tests=%s gameplay_status=%s gameplay_protocol_change=%d design_doc=%s gameplay_summary=%s\n", status, reason, persistence_status, place_reload, destroy_reload, runtime_reload_smoke, visual_collision_gpu_path, active_protocol_change, world_reload_test, storage_tests, network_tests, dirty_update_tests, gameplay_status, gameplay_protocol_change, design_doc, gameplay_summary)
    if (status != "pass") {
      exit 1
    }
  }
' > "$SUMMARY_PATH" || {
  cat "$SUMMARY_PATH" >&2 || true
  fail "block edit persistence gate failed"
}

cat "$SUMMARY_PATH"
echo "Block edit persistence artifacts: $OUT_DIR"
