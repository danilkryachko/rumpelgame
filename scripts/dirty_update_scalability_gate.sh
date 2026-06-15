#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/dirty_update_scalability"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

SUMMARY_PATH="$OUT_DIR/dirty-update-scalability-summary.txt"
DESIGN_DOC="${RUMPELMC_DIRTY_SCALABILITY_DOC:-"$ROOT_DIR/docs/DIRTY_UPDATE_SCALABILITY.md"}"
CLIENT_SOURCE="${RUMPELMC_DIRTY_SCALABILITY_CLIENT_SOURCE:-"$ROOT_DIR/client/rust_ext/src/lib.rs"}"
BLOCK_EDIT_PERSISTENCE_SUMMARY="${RUMPELMC_DIRTY_SCALABILITY_PERSISTENCE_SUMMARY:-"$ROOT_DIR/logs/block_edit_persistence_current/block-edit-persistence-summary.txt"}"
RUN_RUST_TESTS="${RUMPELMC_DIRTY_SCALABILITY_RUN_RUST_TESTS:-1}"

mkdir -p "$OUT_DIR"

fail() {
  echo "dirty_update_scalability_gate: $*" >&2
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

for path in "$DESIGN_DOC" "$CLIENT_SOURCE" "$BLOCK_EDIT_PERSISTENCE_SUMMARY"; do
  test -s "$path" || fail "missing required input $path"
done

for token in \
  'Current Dirty Update Contract' \
  'Added Unit Guard' \
  'Runtime Evidence Entry Points' \
  'Deferred Work' \
  'Compatibility Rules' \
  'Multi-edit runtime smoke' \
  'Do not treat unit dirty math as full runtime scalability evidence'; do
  require_token "$DESIGN_DOC" "$token"
done

require_token "$CLIENT_SOURCE" 'fn chunk_dirty_update'
require_token "$CLIENT_SOURCE" 'fn dirty_partial_subchunk_count'
require_token "$CLIENT_SOURCE" 'fn dirty_partial_saved_subchunks'
require_token "$CLIENT_SOURCE" 'fn dirty_edge_neighbors'
require_token "$CLIENT_SOURCE" 'fn record_dirty_edge_neighbor_refresh'
require_token "$CLIENT_SOURCE" 'mass_dirty_update_tracks_all_edges_and_partial_scope'
require_token "$CLIENT_SOURCE" 'DIRTY_EDGE_NEG_X | DIRTY_EDGE_POS_X | DIRTY_EDGE_NEG_Z | DIRTY_EDGE_POS_Z'

runtime_scripts="
scripts/gpu_terrain_block_edit_stress.sh
scripts/gpu_terrain_edge_block_edit_stress.sh
scripts/gpu_terrain_edge_dirty_compare.sh
scripts/gpu_terrain_edge_dirty_repeat.sh
scripts/gpu_terrain_single_edge_dirty_compare.sh
scripts/gpu_terrain_single_edge_dirty_repeat.sh
"

script_count=0
for script in $runtime_scripts; do
  path="$ROOT_DIR/$script"
  test -s "$path" || fail "missing runtime script $script"
  script_count=$((script_count + 1))
  sh -n "$path" >> "$OUT_DIR/runtime-script-syntax.txt" 2>&1 || {
    cat "$OUT_DIR/runtime-script-syntax.txt" >&2 || true
    fail "syntax check failed for $script"
  }
done

for script in \
  scripts/gpu_terrain_block_edit_stress.sh \
  scripts/gpu_terrain_edge_dirty_compare.sh \
  scripts/gpu_terrain_edge_dirty_repeat.sh; do
  path="$ROOT_DIR/$script"
  require_token "$path" 'dirty_partial'
  require_token "$path" 'dirty_edge'
  require_token "$path" 'collision'
  require_token "$path" 'gpu_upload_fail'
done

block_edit_persistence_status="$(field_metric status "$BLOCK_EDIT_PERSISTENCE_SUMMARY")"
block_edit_protocol_change="$(field_metric active_protocol_change "$BLOCK_EDIT_PERSISTENCE_SUMMARY")"
proto_diff_count="$(git -C "$ROOT_DIR" diff --name-only -- api/schema/packets.proto server/pkg/api/packets.pb.go | awk 'END { print NR + 0 }')"

mass_dirty_unit="skipped"
dirty_tests="skipped"
if [ "$RUN_RUST_TESTS" = "1" ]; then
  if (cd "$ROOT_DIR/client/rust_ext" && cargo test --lib mass_dirty_update > "$OUT_DIR/cargo-test-mass-dirty.txt" 2>&1); then
    mass_dirty_unit="pass"
  else
    cat "$OUT_DIR/cargo-test-mass-dirty.txt" >&2 || true
    mass_dirty_unit="fail"
  fi

  if [ "$mass_dirty_unit" = "pass" ] && (cd "$ROOT_DIR/client/rust_ext" && cargo test --lib dirty > "$OUT_DIR/cargo-test-dirty.txt" 2>&1); then
    dirty_tests="pass"
  elif [ "$mass_dirty_unit" = "pass" ]; then
    cat "$OUT_DIR/cargo-test-dirty.txt" >&2 || true
    dirty_tests="fail"
  fi
fi

awk \
  -v block_edit_persistence_status="${block_edit_persistence_status:-missing}" \
  -v block_edit_protocol_change="${block_edit_protocol_change:-1}" \
  -v proto_diff_count="$proto_diff_count" \
  -v script_count="$script_count" \
  -v mass_dirty_unit="$mass_dirty_unit" \
  -v dirty_tests="$dirty_tests" \
  -v design_doc="$DESIGN_DOC" \
  -v block_edit_persistence_summary="$BLOCK_EDIT_PERSISTENCE_SUMMARY" '
  BEGIN {
    status = "pass"
    reason = "ok"
    dirty_scalability_status = "unit_guarded"
    edge_runtime_scripts = "available"
    runtime_mass_edit = "deferred"
    active_protocol_change = proto_diff_count + 0

    persistence_ok = block_edit_persistence_status == "pass" && block_edit_protocol_change + 0 == 0
    scripts_ok = script_count + 0 >= 6
    rust_ok = (mass_dirty_unit == "pass" || mass_dirty_unit == "skipped") &&
      (dirty_tests == "pass" || dirty_tests == "skipped")

    if (active_protocol_change != 0) {
      status = "fail"
      reason = "protocol_diff_present"
    } else if (!persistence_ok) {
      status = "fail"
      reason = "block_edit_persistence_not_clean"
    } else if (!scripts_ok) {
      status = "fail"
      reason = "runtime_scripts_missing"
    } else if (!rust_ok) {
      status = "fail"
      reason = "dirty_unit_tests_failed"
    }

    printf("dirty_update_scalability status=%s reason=%s dirty_scalability_status=%s active_protocol_change=%d mass_dirty_unit=%s dirty_tests=%s edge_runtime_scripts=%s runtime_script_count=%d runtime_mass_edit=%s block_edit_persistence_status=%s block_edit_protocol_change=%d design_doc=%s block_edit_persistence_summary=%s\n", status, reason, dirty_scalability_status, active_protocol_change, mass_dirty_unit, dirty_tests, edge_runtime_scripts, script_count, runtime_mass_edit, block_edit_persistence_status, block_edit_protocol_change, design_doc, block_edit_persistence_summary)
    if (status != "pass") {
      exit 1
    }
  }
' > "$SUMMARY_PATH" || {
  cat "$SUMMARY_PATH" >&2 || true
  fail "dirty update scalability gate failed"
}

cat "$SUMMARY_PATH"
echo "Dirty update scalability artifacts: $OUT_DIR"
