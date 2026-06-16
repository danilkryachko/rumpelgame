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
RUNTIME_RELOAD_SMOKE_SCRIPT="${RUMPELMC_BLOCK_EDIT_PERSISTENCE_RUNTIME_RELOAD_SMOKE_SCRIPT:-"$ROOT_DIR/scripts/server_persisted_reload_smoke.sh"}"
RUNTIME_RELOAD_SMOKE_SUMMARY="${RUMPELMC_BLOCK_EDIT_PERSISTENCE_RUNTIME_RELOAD_SMOKE_SUMMARY:-"$ROOT_DIR/logs/server_persisted_reload_smoke_current/server-persisted-reload-smoke-summary.txt"}"
PERSISTED_VISUAL_SMOKE_SCRIPT="${RUMPELMC_BLOCK_EDIT_PERSISTENCE_PERSISTED_VISUAL_SMOKE_SCRIPT:-"$ROOT_DIR/scripts/block_edit_persisted_visual_smoke.sh"}"
PERSISTED_VISUAL_SMOKE_SUMMARY="${RUMPELMC_BLOCK_EDIT_PERSISTENCE_PERSISTED_VISUAL_SMOKE_SUMMARY:-"$ROOT_DIR/logs/block_edit_persisted_visual_smoke_current/block-edit-persisted-visual-smoke-summary.txt"}"
RUN_GO_TESTS="${RUMPELMC_BLOCK_EDIT_PERSISTENCE_RUN_GO_TESTS:-1}"
RUN_RUST_TESTS="${RUMPELMC_BLOCK_EDIT_PERSISTENCE_RUN_RUST_TESTS:-1}"
RUN_RUNTIME_RELOAD_SMOKE="${RUMPELMC_BLOCK_EDIT_PERSISTENCE_RUN_RUNTIME_RELOAD_SMOKE:-0}"
RUN_PERSISTED_VISUAL_SMOKE="${RUMPELMC_BLOCK_EDIT_PERSISTENCE_RUN_PERSISTED_VISUAL_SMOKE:-0}"

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

for path in "$DESIGN_DOC" "$STORAGE_DOC" "$WORLD_SOURCE" "$WORLD_TEST" "$NETWORK_SOURCE" "$CLIENT_SOURCE" "$GAMEPLAY_SUMMARY" "$RUNTIME_RELOAD_SMOKE_SCRIPT" "$PERSISTED_VISUAL_SMOKE_SCRIPT"; do
  test -s "$path" || fail "missing required input $path"
done

for token in \
  'Persistence Contract' \
  'Added Unit Guard' \
  'Visual/Collision/GPU Update Path' \
  'Live Restart/Reload Smoke' \
  'Deferred Work' \
  'Compatibility Rules' \
  'Godot persisted visual smoke proves' \
  'Do not change the RocksDB key format'; do
  require_token "$DESIGN_DOC" "$token"
done

require_token "$STORAGE_DOC" 'Preserve persistence compatibility unless the task explicitly changes it.'
require_token "$STORAGE_DOC" 'Persisted chunk payloads use the exact byte output of `world.Chunk.Serialize()`'
require_token "$WORLD_SOURCE" 'func (w *World) SetBlockGlobal'
require_token "$WORLD_SOURCE" 'w.store.SaveChunk(chunk)'
require_token "$WORLD_SOURCE" 'w.store.LoadChunk(x, z)'
require_token "$WORLD_TEST" 'TestSetBlockGlobalPersistsEditedChunkForReload'
require_token "$WORLD_TEST" 'TestHeightV1EditedChunkPersistsThroughStoreReload'
require_token "$WORLD_TEST" 'TestSetBlockGlobalPersistsNegativeBoundaryCoordinates'
require_token "$WORLD_TEST" 'TestChunkSnapshotPropagatesStoreLoadErrorWithoutRegenerating'
require_token "$WORLD_TEST" 'TestSetBlockGlobalRollsBackInMemoryBlockOnSaveError'
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
require_token "$RUNTIME_RELOAD_SMOKE_SCRIPT" 'server_persisted_reload_smoke status=pass'
require_token "$PERSISTED_VISUAL_SMOKE_SCRIPT" 'block_edit_persisted_visual_smoke status=pass'
require_token "$PERSISTED_VISUAL_SMOKE_SCRIPT" 'visual_collision_gpu_path=godot_persisted_reload_guarded'
require_token "$PERSISTED_VISUAL_SMOKE_SCRIPT" 'destroy_after_reload'
require_token "$PERSISTED_VISUAL_SMOKE_SCRIPT" 'edge_place'

gameplay_status="$(field_metric status "$GAMEPLAY_SUMMARY")"
gameplay_protocol_change="$(field_metric active_protocol_change "$GAMEPLAY_SUMMARY")"
case "$RUN_RUNTIME_RELOAD_SMOKE" in
  0) ;;
  1)
    runtime_reload_smoke_dir="$(dirname "$RUNTIME_RELOAD_SMOKE_SUMMARY")"
    "$RUNTIME_RELOAD_SMOKE_SCRIPT" "$runtime_reload_smoke_dir" > "$OUT_DIR/runtime-reload-smoke-run.txt" 2>&1 || {
      cat "$OUT_DIR/runtime-reload-smoke-run.txt" >&2 || true
      fail "live restart/reload smoke failed"
    }
    ;;
  *)
    fail "unsupported RUMPELMC_BLOCK_EDIT_PERSISTENCE_RUN_RUNTIME_RELOAD_SMOKE=$RUN_RUNTIME_RELOAD_SMOKE"
    ;;
esac
case "$RUN_PERSISTED_VISUAL_SMOKE" in
  0) ;;
  1)
    persisted_visual_smoke_dir="$(dirname "$PERSISTED_VISUAL_SMOKE_SUMMARY")"
    "$PERSISTED_VISUAL_SMOKE_SCRIPT" "$persisted_visual_smoke_dir" > "$OUT_DIR/persisted-visual-smoke-run.txt" 2>&1 || {
      cat "$OUT_DIR/persisted-visual-smoke-run.txt" >&2 || true
      fail "persisted visual smoke failed"
    }
    ;;
  *)
    fail "unsupported RUMPELMC_BLOCK_EDIT_PERSISTENCE_RUN_PERSISTED_VISUAL_SMOKE=$RUN_PERSISTED_VISUAL_SMOKE"
    ;;
esac
runtime_reload_smoke_status="deferred"
runtime_reload_protocol_change="0"
if [ -s "$RUNTIME_RELOAD_SMOKE_SUMMARY" ]; then
  runtime_reload_smoke_status="$(field_metric status "$RUNTIME_RELOAD_SMOKE_SUMMARY")"
  runtime_reload_protocol_change="$(field_metric protocol_change "$RUNTIME_RELOAD_SMOKE_SUMMARY")"
fi
persisted_visual_smoke_status="deferred"
persisted_visual_protocol_change="0"
persisted_visual_path="deferred"
persisted_visual_scenarios="0"
persisted_visual_place_reload_status="deferred"
persisted_visual_destroy_after_reload_status="deferred"
persisted_visual_edge_place_status="deferred"
if [ -s "$PERSISTED_VISUAL_SMOKE_SUMMARY" ]; then
  persisted_visual_smoke_status="$(field_metric status "$PERSISTED_VISUAL_SMOKE_SUMMARY")"
  persisted_visual_protocol_change="$(field_metric protocol_change "$PERSISTED_VISUAL_SMOKE_SUMMARY")"
  persisted_visual_path="$(field_metric visual_collision_gpu_path "$PERSISTED_VISUAL_SMOKE_SUMMARY")"
  persisted_visual_scenarios="$(field_metric scenarios "$PERSISTED_VISUAL_SMOKE_SUMMARY")"
  persisted_visual_place_reload_status="$(field_metric place_reload_status "$PERSISTED_VISUAL_SMOKE_SUMMARY")"
  persisted_visual_destroy_after_reload_status="$(field_metric destroy_after_reload_status "$PERSISTED_VISUAL_SMOKE_SUMMARY")"
  persisted_visual_edge_place_status="$(field_metric edge_place_status "$PERSISTED_VISUAL_SMOKE_SUMMARY")"
fi
proto_diff_count="$(git -C "$ROOT_DIR" diff --name-only -- api/schema/packets.proto server/pkg/api/packets.pb.go | awk 'END { print NR + 0 }')"

world_reload_test="skipped"
storage_tests="skipped"
network_tests="skipped"
if [ "$RUN_GO_TESTS" = "1" ]; then
  if (cd "$ROOT_DIR/server" && go test ./pkg/world -run 'Test(SetBlockGlobalPersists(EditedChunkForReload|NegativeBoundaryCoordinates)|HeightV1EditedChunkPersistsThroughStoreReload|SetBlockGlobalRollsBackInMemoryBlockOnSaveError|ChunkSnapshotPropagatesStoreLoadErrorWithoutRegenerating)' > "$OUT_DIR/go-test-world-reload.txt" 2>&1); then
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
  -v runtime_reload_smoke_status="${runtime_reload_smoke_status:-deferred}" \
  -v runtime_reload_protocol_change="${runtime_reload_protocol_change:-0}" \
  -v runtime_reload_required="$RUN_RUNTIME_RELOAD_SMOKE" \
  -v persisted_visual_smoke_status="${persisted_visual_smoke_status:-deferred}" \
  -v persisted_visual_protocol_change="${persisted_visual_protocol_change:-0}" \
  -v persisted_visual_path="${persisted_visual_path:-deferred}" \
  -v persisted_visual_scenarios="${persisted_visual_scenarios:-0}" \
  -v persisted_visual_place_reload_status="${persisted_visual_place_reload_status:-deferred}" \
  -v persisted_visual_destroy_after_reload_status="${persisted_visual_destroy_after_reload_status:-deferred}" \
  -v persisted_visual_edge_place_status="${persisted_visual_edge_place_status:-deferred}" \
  -v persisted_visual_required="$RUN_PERSISTED_VISUAL_SMOKE" \
  -v proto_diff_count="$proto_diff_count" \
  -v world_reload_test="$world_reload_test" \
  -v storage_tests="$storage_tests" \
  -v network_tests="$network_tests" \
  -v dirty_update_tests="$dirty_update_tests" \
  -v design_doc="$DESIGN_DOC" \
  -v gameplay_summary="$GAMEPLAY_SUMMARY" \
  -v runtime_reload_smoke_summary="$RUNTIME_RELOAD_SMOKE_SUMMARY" \
  -v persisted_visual_smoke_summary="$PERSISTED_VISUAL_SMOKE_SUMMARY" '
  BEGIN {
    status = "pass"
    reason = "ok"
    runtime_ok = runtime_reload_smoke_status == "pass" && runtime_reload_protocol_change + 0 == 0
    persisted_visual_ok = persisted_visual_smoke_status == "pass" &&
      persisted_visual_protocol_change + 0 == 0 &&
      persisted_visual_path == "godot_persisted_reload_guarded" &&
      persisted_visual_scenarios + 0 >= 3 &&
      persisted_visual_place_reload_status == "pass" &&
      persisted_visual_destroy_after_reload_status == "pass" &&
      persisted_visual_edge_place_status == "pass"
    persistence_status = runtime_ok ? "runtime_guarded" : "unit_guarded"
    place_reload = runtime_ok ? "live_restart_guarded" : "guarded"
    destroy_reload = runtime_ok ? "live_restart_guarded" : "guarded"
    runtime_reload_smoke = runtime_ok ? "live_restart_guarded" : "deferred"
    persisted_visual_smoke = persisted_visual_ok ? "godot_guarded" : "deferred"
    visual_collision_gpu_path = persisted_visual_ok ? "godot_persisted_reload_guarded" : "existing_update_chunk_path"
    negative_boundary_edits = "guarded"
    height_v1_reload = "guarded"
    store_load_errors = "propagated_guarded"
    save_failure_rollback = "guarded"
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
    } else if (runtime_reload_required == "1" && !runtime_ok) {
      status = "fail"
      reason = "runtime_reload_smoke_failed"
    } else if (persisted_visual_required == "1" && !persisted_visual_ok) {
      status = "fail"
      reason = "persisted_visual_smoke_failed"
    } else if (!go_ok) {
      status = "fail"
      reason = "go_persistence_tests_failed"
    } else if (!rust_ok) {
      status = "fail"
      reason = "dirty_update_tests_failed"
    }

    printf("block_edit_persistence status=%s reason=%s persistence_status=%s place_reload=%s destroy_reload=%s runtime_reload_smoke=%s runtime_reload_smoke_status=%s persisted_visual_smoke=%s persisted_visual_smoke_status=%s persisted_visual_scenarios=%d persisted_visual_place_reload_status=%s persisted_visual_destroy_after_reload_status=%s persisted_visual_edge_place_status=%s visual_collision_gpu_path=%s negative_boundary_edits=%s height_v1_reload=%s store_load_errors=%s save_failure_rollback=%s active_protocol_change=%d world_reload_test=%s storage_tests=%s network_tests=%s dirty_update_tests=%s gameplay_status=%s gameplay_protocol_change=%d design_doc=%s gameplay_summary=%s runtime_reload_smoke_summary=%s persisted_visual_smoke_summary=%s\n", status, reason, persistence_status, place_reload, destroy_reload, runtime_reload_smoke, runtime_reload_smoke_status, persisted_visual_smoke, persisted_visual_smoke_status, persisted_visual_scenarios, persisted_visual_place_reload_status, persisted_visual_destroy_after_reload_status, persisted_visual_edge_place_status, visual_collision_gpu_path, negative_boundary_edits, height_v1_reload, store_load_errors, save_failure_rollback, active_protocol_change, world_reload_test, storage_tests, network_tests, dirty_update_tests, gameplay_status, gameplay_protocol_change, design_doc, gameplay_summary, runtime_reload_smoke_summary, persisted_visual_smoke_summary)
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
