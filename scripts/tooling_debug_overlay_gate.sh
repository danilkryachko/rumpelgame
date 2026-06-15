#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/tooling_debug_overlay"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

SUMMARY_PATH="$OUT_DIR/tooling-debug-overlay-summary.txt"
DESIGN_DOC="${RUMPELMC_TOOLING_DEBUG_OVERLAY_DOC:-"$ROOT_DIR/docs/TOOLING_DEBUG_OVERLAY.md"}"
CLIENT_SOURCE="${RUMPELMC_TOOLING_DEBUG_OVERLAY_CLIENT_SOURCE:-"$ROOT_DIR/client/rust_ext/src/lib.rs"}"
HUD_SOURCE="${RUMPELMC_TOOLING_DEBUG_OVERLAY_HUD_SOURCE:-"$ROOT_DIR/client/hud.gd"}"
DIRTY_SUMMARY="${RUMPELMC_TOOLING_DEBUG_OVERLAY_DIRTY_SUMMARY:-"$ROOT_DIR/logs/dirty_update_scalability_current/dirty-update-scalability-summary.txt"}"
RUN_RUST_TESTS="${RUMPELMC_TOOLING_DEBUG_OVERLAY_RUN_RUST_TESTS:-1}"

mkdir -p "$OUT_DIR"

fail() {
  echo "tooling_debug_overlay_gate: $*" >&2
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

for path in "$DESIGN_DOC" "$CLIENT_SOURCE" "$HUD_SOURCE" "$DIRTY_SUMMARY"; do
  test -s "$path" || fail "missing required input $path"
done

for token in \
  'Technical Brief' \
  'Runtime Overlay Contract' \
  'HUD Wiring' \
  'Perf Log Policy' \
  'Deferred Work' \
  'Compatibility Rules' \
  'Do not treat overlay presence as runtime performance evidence'; do
  require_token "$DESIGN_DOC" "$token"
done

for token in \
  'fn client_lifecycle_state_label' \
  'fn get_debug_overlay_text' \
  'State: {state}' \
  'stats.upload_failures' \
  'self.last_save_event' \
  'client_lifecycle_state_labels_are_overlay_stable'; do
  require_token "$CLIENT_SOURCE" "$token"
done

for token in \
  'GPU/render overlay:' \
  'func get_debug_overlay_text() -> String:' \
  'get_client_text("get_debug_overlay_text", "")' \
  'overlay=\"%s\"' \
  'get_client_text("get_perf_text", "n/a")'; do
  require_token "$HUD_SOURCE" "$token"
done

dirty_status="$(field_metric status "$DIRTY_SUMMARY")"
dirty_protocol_change="$(field_metric active_protocol_change "$DIRTY_SUMMARY")"
proto_diff_count="$(git -C "$ROOT_DIR" diff --name-only -- api/schema/packets.proto server/pkg/api/packets.pb.go | awk 'END { print NR + 0 }')"
scene_resource_diff_count="$(git -C "$ROOT_DIR" diff --name-only -- client | grep -E '\.(tscn|tres|res|import)$' | awk 'END { print NR + 0 }')"

rust_overlay_test="skipped"
if [ "$RUN_RUST_TESTS" = "1" ]; then
  if (cd "$ROOT_DIR/client/rust_ext" && cargo test --lib client_lifecycle_state_labels_are_overlay_stable > "$OUT_DIR/cargo-test-overlay.txt" 2>&1); then
    rust_overlay_test="pass"
  else
    cat "$OUT_DIR/cargo-test-overlay.txt" >&2 || true
    rust_overlay_test="fail"
  fi
fi

awk \
  -v dirty_status="${dirty_status:-missing}" \
  -v dirty_protocol_change="${dirty_protocol_change:-1}" \
  -v proto_diff_count="$proto_diff_count" \
  -v scene_resource_diff_count="$scene_resource_diff_count" \
  -v rust_overlay_test="$rust_overlay_test" \
  -v design_doc="$DESIGN_DOC" \
  -v dirty_summary="$DIRTY_SUMMARY" '
  BEGIN {
    status = "pass"
    reason = "ok"
    overlay_status = "runtime_wired"
    hud_overlay = "compact"
    perf_log_full = "preserved"
    storage_metric = "last_save_event"
    dirty_metric = "present"
    active_protocol_change = proto_diff_count + 0
    active_scene_resource_change = scene_resource_diff_count + 0

    dirty_ok = dirty_status == "pass" && dirty_protocol_change + 0 == 0
    rust_ok = rust_overlay_test == "pass" || rust_overlay_test == "skipped"

    if (active_protocol_change != 0) {
      status = "fail"
      reason = "protocol_diff_present"
    } else if (active_scene_resource_change != 0) {
      status = "fail"
      reason = "scene_resource_diff_present"
    } else if (!dirty_ok) {
      status = "fail"
      reason = "dirty_update_scalability_not_clean"
    } else if (!rust_ok) {
      status = "fail"
      reason = "rust_overlay_test_failed"
    }

    printf("tooling_debug_overlay status=%s reason=%s overlay_status=%s hud_overlay=%s perf_log_full=%s storage_metric=%s dirty_metric=%s active_protocol_change=%d active_scene_resource_change=%d rust_overlay_test=%s dirty_update_scalability_status=%s design_doc=%s dirty_summary=%s\n", status, reason, overlay_status, hud_overlay, perf_log_full, storage_metric, dirty_metric, active_protocol_change, active_scene_resource_change, rust_overlay_test, dirty_status, design_doc, dirty_summary)
    if (status != "pass") {
      exit 1
    }
  }
' > "$SUMMARY_PATH" || {
  cat "$SUMMARY_PATH" >&2 || true
  fail "tooling debug overlay gate failed"
}

cat "$SUMMARY_PATH"
echo "Tooling debug overlay artifacts: $OUT_DIR"
