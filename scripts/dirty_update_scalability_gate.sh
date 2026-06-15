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
RUNTIME_SMOKE_SCRIPT="${RUMPELMC_DIRTY_SCALABILITY_RUNTIME_SMOKE_SCRIPT:-"$ROOT_DIR/scripts/dirty_update_runtime_smoke.sh"}"
RUNTIME_SMOKE_SUMMARY="${RUMPELMC_DIRTY_SCALABILITY_RUNTIME_SMOKE_SUMMARY:-"$ROOT_DIR/logs/dirty_update_runtime_smoke_current/dirty-update-runtime-smoke-summary.txt"}"
MASS_RUNTIME_SMOKE_SCRIPT="${RUMPELMC_DIRTY_SCALABILITY_MASS_RUNTIME_SMOKE_SCRIPT:-"$ROOT_DIR/scripts/dirty_update_mass_edit_runtime_smoke.sh"}"
MASS_RUNTIME_SMOKE_SUMMARY="${RUMPELMC_DIRTY_SCALABILITY_MASS_RUNTIME_SMOKE_SUMMARY:-"$ROOT_DIR/logs/dirty_update_mass_edit_runtime_current/dirty-update-mass-edit-runtime-summary.txt"}"
PERSISTED_RUNTIME_SMOKE_SCRIPT="${RUMPELMC_DIRTY_SCALABILITY_PERSISTED_RUNTIME_SMOKE_SCRIPT:-"$ROOT_DIR/scripts/dirty_update_persisted_reload_runtime_smoke.sh"}"
PERSISTED_RUNTIME_SMOKE_SUMMARY="${RUMPELMC_DIRTY_SCALABILITY_PERSISTED_RUNTIME_SMOKE_SUMMARY:-"$ROOT_DIR/logs/dirty_update_persisted_reload_runtime_current/dirty-update-persisted-reload-runtime-summary.txt"}"
RUN_RUST_TESTS="${RUMPELMC_DIRTY_SCALABILITY_RUN_RUST_TESTS:-1}"
RUN_RUNTIME_SMOKE="${RUMPELMC_DIRTY_SCALABILITY_RUN_RUNTIME_SMOKE:-0}"
RUN_MASS_RUNTIME_SMOKE="${RUMPELMC_DIRTY_SCALABILITY_RUN_MASS_RUNTIME_SMOKE:-0}"
RUN_PERSISTED_RUNTIME_SMOKE="${RUMPELMC_DIRTY_SCALABILITY_RUN_PERSISTED_RUNTIME_SMOKE:-0}"

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
  'Runtime Edge Dirty Smoke' \
  'Runtime Mass Edit Smoke' \
  'Runtime Persisted Reload Dirty Smoke' \
  'Deferred Work' \
  'Compatibility Rules' \
  'Do not treat unit dirty math or the mixed current-chunk budget smoke as broad cross-chunk runtime scalability evidence'; do
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
scripts/dirty_update_runtime_smoke.sh
scripts/dirty_update_mass_edit_runtime_smoke.sh
scripts/dirty_update_persisted_reload_runtime_smoke.sh
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
  scripts/gpu_terrain_edge_dirty_repeat.sh \
  scripts/dirty_update_runtime_smoke.sh \
  scripts/dirty_update_mass_edit_runtime_smoke.sh \
  scripts/dirty_update_persisted_reload_runtime_smoke.sh; do
  path="$ROOT_DIR/$script"
  require_token "$path" 'dirty_partial'
  require_token "$path" 'dirty_edge'
  require_token "$path" 'gpu_upload_fail'
done

require_token "$ROOT_DIR/scripts/gpu_terrain_block_edit_stress.sh" 'collision'
require_token "$ROOT_DIR/scripts/gpu_terrain_edge_dirty_compare.sh" 'collision'
require_token "$ROOT_DIR/scripts/gpu_terrain_edge_dirty_repeat.sh" 'collision'
require_token "$RUNTIME_SMOKE_SCRIPT" 'dirty_update_runtime_smoke status=pass'
require_token "$RUNTIME_SMOKE_SCRIPT" 'runtime_edge_dirty=godot_guarded'
require_token "$MASS_RUNTIME_SMOKE_SCRIPT" 'dirty_update_mass_edit_runtime status=pass'
require_token "$MASS_RUNTIME_SMOKE_SCRIPT" 'runtime_mass_edit=godot_guarded'
require_token "$MASS_RUNTIME_SMOKE_SCRIPT" 'runtime_mass_budget=godot_guarded'
require_token "$PERSISTED_RUNTIME_SMOKE_SCRIPT" 'dirty_update_persisted_reload_runtime status=pass'
require_token "$PERSISTED_RUNTIME_SMOKE_SCRIPT" 'runtime_persisted_dirty=godot_guarded'

block_edit_persistence_status="$(field_metric status "$BLOCK_EDIT_PERSISTENCE_SUMMARY")"
block_edit_protocol_change="$(field_metric active_protocol_change "$BLOCK_EDIT_PERSISTENCE_SUMMARY")"
proto_diff_count="$(git -C "$ROOT_DIR" diff --name-only -- api/schema/packets.proto server/pkg/api/packets.pb.go | awk 'END { print NR + 0 }')"

if [ "$RUN_RUNTIME_SMOKE" = "1" ]; then
  runtime_dir="$(dirname -- "$RUNTIME_SMOKE_SUMMARY")"
  mkdir -p "$runtime_dir"
  if ! sh "$RUNTIME_SMOKE_SCRIPT" "$runtime_dir" > "$OUT_DIR/runtime-smoke-run.log" 2>&1; then
    cat "$OUT_DIR/runtime-smoke-run.log" >&2 || true
    fail "dirty update runtime smoke failed"
  fi
fi

if [ "$RUN_MASS_RUNTIME_SMOKE" = "1" ]; then
  mass_runtime_dir="$(dirname -- "$MASS_RUNTIME_SMOKE_SUMMARY")"
  mkdir -p "$mass_runtime_dir"
  if ! sh "$MASS_RUNTIME_SMOKE_SCRIPT" "$mass_runtime_dir" > "$OUT_DIR/mass-runtime-smoke-run.log" 2>&1; then
    cat "$OUT_DIR/mass-runtime-smoke-run.log" >&2 || true
    fail "dirty update mass-edit runtime smoke failed"
  fi
fi

if [ "$RUN_PERSISTED_RUNTIME_SMOKE" = "1" ]; then
  persisted_runtime_dir="$(dirname -- "$PERSISTED_RUNTIME_SMOKE_SUMMARY")"
  mkdir -p "$persisted_runtime_dir"
  if ! sh "$PERSISTED_RUNTIME_SMOKE_SCRIPT" "$persisted_runtime_dir" > "$OUT_DIR/persisted-runtime-smoke-run.log" 2>&1; then
    cat "$OUT_DIR/persisted-runtime-smoke-run.log" >&2 || true
    fail "dirty update persisted-reload runtime smoke failed"
  fi
fi

runtime_summary_present=0
runtime_smoke_status="missing"
runtime_protocol_change=0
runtime_edge_dirty="deferred"
runtime_smoke_mass_edit="deferred"
single_edge_compare="deferred"
corner_edge_compare="deferred"
corner_edge_repeat="deferred"
runtime_repeat_runs=0
if [ -s "$RUNTIME_SMOKE_SUMMARY" ]; then
  runtime_summary_present=1
  require_token "$RUNTIME_SMOKE_SUMMARY" 'dirty_update_runtime_smoke status=pass'
  require_token "$RUNTIME_SMOKE_SUMMARY" 'runtime_edge_dirty=godot_guarded'
  require_token "$RUNTIME_SMOKE_SUMMARY" 'single_edge_compare=pass'
  require_token "$RUNTIME_SMOKE_SUMMARY" 'corner_edge_compare=pass'
  require_token "$RUNTIME_SMOKE_SUMMARY" 'corner_edge_repeat=pass'
  runtime_smoke_status="$(field_metric status "$RUNTIME_SMOKE_SUMMARY")"
  runtime_protocol_change="$(field_metric active_protocol_change "$RUNTIME_SMOKE_SUMMARY")"
  runtime_edge_dirty="$(field_metric runtime_edge_dirty "$RUNTIME_SMOKE_SUMMARY")"
  runtime_smoke_mass_edit="$(field_metric runtime_mass_edit "$RUNTIME_SMOKE_SUMMARY")"
  single_edge_compare="$(field_metric single_edge_compare "$RUNTIME_SMOKE_SUMMARY")"
  corner_edge_compare="$(field_metric corner_edge_compare "$RUNTIME_SMOKE_SUMMARY")"
  corner_edge_repeat="$(field_metric corner_edge_repeat "$RUNTIME_SMOKE_SUMMARY")"
  runtime_repeat_runs="$(field_metric repeat_runs "$RUNTIME_SMOKE_SUMMARY")"
fi

mass_runtime_summary_present=0
mass_runtime_smoke_status="missing"
mass_runtime_protocol_change=0
mass_runtime_mass_edit="deferred"
mass_runtime_budget="deferred"
mass_runtime_edit_count=0
mass_runtime_place_actions=0
mass_runtime_destroy_actions=0
if [ -s "$MASS_RUNTIME_SMOKE_SUMMARY" ]; then
  mass_runtime_summary_present=1
  require_token "$MASS_RUNTIME_SMOKE_SUMMARY" 'dirty_update_mass_edit_runtime status=pass'
  require_token "$MASS_RUNTIME_SMOKE_SUMMARY" 'runtime_mass_edit=godot_guarded'
  require_token "$MASS_RUNTIME_SMOKE_SUMMARY" 'runtime_mass_budget=godot_guarded'
  require_token "$MASS_RUNTIME_SMOKE_SUMMARY" 'budget_status=pass'
  mass_runtime_smoke_status="$(field_metric status "$MASS_RUNTIME_SMOKE_SUMMARY")"
  mass_runtime_protocol_change="$(field_metric active_protocol_change "$MASS_RUNTIME_SMOKE_SUMMARY")"
  mass_runtime_mass_edit="$(field_metric runtime_mass_edit "$MASS_RUNTIME_SMOKE_SUMMARY")"
  mass_runtime_budget="$(field_metric runtime_mass_budget "$MASS_RUNTIME_SMOKE_SUMMARY")"
  mass_runtime_edit_count="$(field_metric mass_edit_count "$MASS_RUNTIME_SMOKE_SUMMARY")"
  mass_runtime_place_actions="$(field_metric place_actions "$MASS_RUNTIME_SMOKE_SUMMARY")"
  mass_runtime_destroy_actions="$(field_metric destroy_actions "$MASS_RUNTIME_SMOKE_SUMMARY")"
fi

persisted_runtime_summary_present=0
persisted_runtime_smoke_status="missing"
persisted_runtime_protocol_change=0
persisted_runtime_dirty="deferred"
persisted_runtime_reload_cycles=0
persisted_runtime_final_verify_count=0
if [ -s "$PERSISTED_RUNTIME_SMOKE_SUMMARY" ]; then
  persisted_runtime_summary_present=1
  require_token "$PERSISTED_RUNTIME_SMOKE_SUMMARY" 'dirty_update_persisted_reload_runtime status=pass'
  require_token "$PERSISTED_RUNTIME_SMOKE_SUMMARY" 'runtime_persisted_dirty=godot_guarded'
  persisted_runtime_smoke_status="$(field_metric status "$PERSISTED_RUNTIME_SMOKE_SUMMARY")"
  persisted_runtime_protocol_change="$(field_metric active_protocol_change "$PERSISTED_RUNTIME_SMOKE_SUMMARY")"
  persisted_runtime_dirty="$(field_metric runtime_persisted_dirty "$PERSISTED_RUNTIME_SMOKE_SUMMARY")"
  persisted_runtime_reload_cycles="$(field_metric reload_cycles "$PERSISTED_RUNTIME_SMOKE_SUMMARY")"
  persisted_runtime_final_verify_count="$(field_metric final_verify_count "$PERSISTED_RUNTIME_SMOKE_SUMMARY")"
fi

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
  -v run_runtime_smoke="$RUN_RUNTIME_SMOKE" \
  -v run_mass_runtime_smoke="$RUN_MASS_RUNTIME_SMOKE" \
  -v run_persisted_runtime_smoke="$RUN_PERSISTED_RUNTIME_SMOKE" \
  -v runtime_summary_present="$runtime_summary_present" \
  -v runtime_smoke_status="$runtime_smoke_status" \
  -v runtime_protocol_change="${runtime_protocol_change:-0}" \
  -v runtime_edge_dirty="${runtime_edge_dirty:-deferred}" \
  -v runtime_smoke_mass_edit="${runtime_smoke_mass_edit:-deferred}" \
  -v single_edge_compare="${single_edge_compare:-deferred}" \
  -v corner_edge_compare="${corner_edge_compare:-deferred}" \
  -v corner_edge_repeat="${corner_edge_repeat:-deferred}" \
  -v runtime_repeat_runs="${runtime_repeat_runs:-0}" \
  -v mass_runtime_summary_present="$mass_runtime_summary_present" \
  -v mass_runtime_smoke_status="$mass_runtime_smoke_status" \
  -v mass_runtime_protocol_change="${mass_runtime_protocol_change:-0}" \
  -v mass_runtime_mass_edit="${mass_runtime_mass_edit:-deferred}" \
  -v mass_runtime_budget="${mass_runtime_budget:-deferred}" \
  -v mass_runtime_edit_count="${mass_runtime_edit_count:-0}" \
  -v mass_runtime_place_actions="${mass_runtime_place_actions:-0}" \
  -v mass_runtime_destroy_actions="${mass_runtime_destroy_actions:-0}" \
  -v persisted_runtime_summary_present="$persisted_runtime_summary_present" \
  -v persisted_runtime_smoke_status="$persisted_runtime_smoke_status" \
  -v persisted_runtime_protocol_change="${persisted_runtime_protocol_change:-0}" \
  -v persisted_runtime_dirty="${persisted_runtime_dirty:-deferred}" \
  -v persisted_runtime_reload_cycles="${persisted_runtime_reload_cycles:-0}" \
  -v persisted_runtime_final_verify_count="${persisted_runtime_final_verify_count:-0}" \
  -v design_doc="$DESIGN_DOC" \
  -v block_edit_persistence_summary="$BLOCK_EDIT_PERSISTENCE_SUMMARY" '
  BEGIN {
    status = "pass"
    reason = "ok"
    dirty_scalability_status = "unit_guarded"
    edge_runtime_scripts = "available"
    runtime_edge_dirty_status = "deferred"
    runtime_mass_edit_status = "deferred"
    runtime_persisted_dirty_status = "deferred"
    runtime_persisted_dirty = "deferred"
    runtime_mass_edit = "deferred"
    active_protocol_change = proto_diff_count + 0

    persistence_ok = block_edit_persistence_status == "pass" && block_edit_protocol_change + 0 == 0
    scripts_ok = script_count + 0 >= 9
    rust_ok = (mass_dirty_unit == "pass" || mass_dirty_unit == "skipped") &&
      (dirty_tests == "pass" || dirty_tests == "skipped")
    runtime_ok = runtime_smoke_status == "pass" &&
      runtime_protocol_change + 0 == 0 &&
      runtime_edge_dirty == "godot_guarded" &&
      runtime_smoke_mass_edit == "deferred" &&
      single_edge_compare == "pass" &&
      corner_edge_compare == "pass" &&
      corner_edge_repeat == "pass" &&
      runtime_repeat_runs + 0 >= 1
    mass_runtime_ok = mass_runtime_smoke_status == "pass" &&
      mass_runtime_protocol_change + 0 == 0 &&
      mass_runtime_mass_edit == "godot_guarded" &&
      mass_runtime_budget == "godot_guarded" &&
      mass_runtime_edit_count + 0 >= 8 &&
      mass_runtime_place_actions + 0 >= 4 &&
      mass_runtime_destroy_actions + 0 >= 4
    persisted_runtime_ok = persisted_runtime_smoke_status == "pass" &&
      persisted_runtime_protocol_change + 0 == 0 &&
      persisted_runtime_dirty == "godot_guarded" &&
      persisted_runtime_reload_cycles + 0 >= 2 &&
      persisted_runtime_final_verify_count + 0 >= 1

    if (runtime_ok) {
      dirty_scalability_status = "unit_and_edge_runtime_guarded"
      runtime_edge_dirty_status = "pass"
    }
    if (mass_runtime_ok) {
      runtime_mass_edit = "godot_guarded"
      runtime_mass_edit_status = "pass"
      dirty_scalability_status = runtime_ok ? "unit_edge_and_mixed_mass_runtime_guarded" : "unit_and_mixed_mass_runtime_guarded"
    }
    if (persisted_runtime_ok) {
      runtime_persisted_dirty = "godot_guarded"
      runtime_persisted_dirty_status = "pass"
      if (runtime_ok && mass_runtime_ok) {
        dirty_scalability_status = "unit_edge_mixed_mass_and_persisted_runtime_guarded"
      } else if (runtime_ok) {
        dirty_scalability_status = "unit_edge_and_persisted_runtime_guarded"
      } else {
        dirty_scalability_status = "unit_and_persisted_runtime_guarded"
      }
    }

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
    } else if (!runtime_ok && (run_runtime_smoke == "1" || runtime_summary_present + 0 == 1)) {
      status = "fail"
      reason = "runtime_edge_dirty_not_clean"
    } else if (!mass_runtime_ok && (run_mass_runtime_smoke == "1" || mass_runtime_summary_present + 0 == 1)) {
      status = "fail"
      reason = "runtime_mass_edit_not_clean"
    } else if (!persisted_runtime_ok && (run_persisted_runtime_smoke == "1" || persisted_runtime_summary_present + 0 == 1)) {
      status = "fail"
      reason = "runtime_persisted_dirty_not_clean"
    }

    printf("dirty_update_scalability status=%s reason=%s dirty_scalability_status=%s active_protocol_change=%d mass_dirty_unit=%s dirty_tests=%s edge_runtime_scripts=%s runtime_script_count=%d runtime_edge_dirty=%s runtime_edge_dirty_status=%s runtime_smoke_status=%s single_edge_compare=%s corner_edge_compare=%s corner_edge_repeat=%s runtime_repeat_runs=%d runtime_mass_edit=%s runtime_mass_edit_status=%s runtime_mass_budget=%s mass_runtime_smoke_status=%s mass_runtime_edit_count=%d mass_runtime_place_actions=%d mass_runtime_destroy_actions=%d runtime_persisted_dirty=%s runtime_persisted_dirty_status=%s persisted_runtime_smoke_status=%s persisted_runtime_reload_cycles=%d persisted_runtime_final_verify_count=%d block_edit_persistence_status=%s block_edit_protocol_change=%d design_doc=%s block_edit_persistence_summary=%s\n", status, reason, dirty_scalability_status, active_protocol_change, mass_dirty_unit, dirty_tests, edge_runtime_scripts, script_count, runtime_edge_dirty, runtime_edge_dirty_status, runtime_smoke_status, single_edge_compare, corner_edge_compare, corner_edge_repeat, runtime_repeat_runs, runtime_mass_edit, runtime_mass_edit_status, mass_runtime_budget, mass_runtime_smoke_status, mass_runtime_edit_count, mass_runtime_place_actions, mass_runtime_destroy_actions, runtime_persisted_dirty, runtime_persisted_dirty_status, persisted_runtime_smoke_status, persisted_runtime_reload_cycles, persisted_runtime_final_verify_count, block_edit_persistence_status, block_edit_protocol_change, design_doc, block_edit_persistence_summary)
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
