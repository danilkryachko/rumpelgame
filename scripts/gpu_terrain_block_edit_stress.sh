#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/gpu_terrain_visual_smoke/block_edit_stress"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

ACTION="${RUMPELMC_BLOCK_EDIT_STRESS_ACTION:-toggle}"
EDIT_X="${RUMPELMC_BLOCK_EDIT_STRESS_X:-112}"
EDIT_Y="${RUMPELMC_BLOCK_EDIT_STRESS_Y:-64}"
EDIT_Z="${RUMPELMC_BLOCK_EDIT_STRESS_Z:-80}"
EDIT_BLOCK_ID="${RUMPELMC_BLOCK_EDIT_STRESS_BLOCK_ID:-1}"
EDIT_WAIT_SEC="${RUMPELMC_BLOCK_EDIT_STRESS_WAIT_SEC:-3.0}"
MOTION_NAME="${RUMPELMC_BLOCK_EDIT_STRESS_MOTION:-${RUMPELMC_MOVEMENT_STRESS_MOTION:-chunk_walk}}"
EXPECTED_CURRENT_CHUNK="${RUMPELMC_BLOCK_EDIT_STRESS_EXPECTED_CHUNK:-${RUMPELMC_MOVEMENT_STRESS_EXPECTED_CHUNK:-3,2}}"
MIN_MOTION_CHUNKS="${RUMPELMC_BLOCK_EDIT_STRESS_MIN_CHUNKS:-${RUMPELMC_MOVEMENT_STRESS_MIN_CHUNKS:-4}}"
EXPECTED_EDGES="${RUMPELMC_BLOCK_EDIT_STRESS_EXPECTED_EDGES:-}"
EXPECTED_EDGES_EXACT="${RUMPELMC_BLOCK_EDIT_STRESS_EXPECTED_EDGES_EXACT:-0}"
EXPECTED_BOUNDS="${RUMPELMC_BLOCK_EDIT_STRESS_EXPECTED_BOUNDS:-}"
MIN_PARTIAL_CHUNKS="${RUMPELMC_BLOCK_EDIT_STRESS_MIN_PARTIAL_CHUNKS:-0}"
MIN_PARTIAL_SUBCHUNKS="${RUMPELMC_BLOCK_EDIT_STRESS_MIN_PARTIAL_SUBCHUNKS:-0}"
MIN_PARTIAL_SAVED_SUBCHUNKS="${RUMPELMC_BLOCK_EDIT_STRESS_MIN_PARTIAL_SAVED_SUBCHUNKS:-0}"
MIN_EDGE_NEIGHBOR_CHUNKS="${RUMPELMC_BLOCK_EDIT_STRESS_MIN_EDGE_NEIGHBOR_CHUNKS:-0}"
MIN_EDGE_NEIGHBOR_SUBCHUNKS="${RUMPELMC_BLOCK_EDIT_STRESS_MIN_EDGE_NEIGHBOR_SUBCHUNKS:-0}"
MIN_LAST_EDGE_NEIGHBOR_CHUNKS="${RUMPELMC_BLOCK_EDIT_STRESS_MIN_LAST_EDGE_NEIGHBOR_CHUNKS:-0}"
MIN_LAST_EDGE_NEIGHBOR_SUBCHUNKS="${RUMPELMC_BLOCK_EDIT_STRESS_MIN_LAST_EDGE_NEIGHBOR_SUBCHUNKS:-0}"
MIN_CURRENT_CHUNK_COLLISION="${RUMPELMC_BLOCK_EDIT_STRESS_MIN_CURRENT_CHUNK_COLLISION:-0}"
MIN_COLLISION_REFRESH_REBUILT="${RUMPELMC_BLOCK_EDIT_STRESS_MIN_COLLISION_REFRESH_REBUILT:-0}"
MIN_LAST_COLLISION_REFRESH_REBUILT="${RUMPELMC_BLOCK_EDIT_STRESS_MIN_LAST_COLLISION_REFRESH_REBUILT:-0}"
MIN_MESH_SHADOW_ONLY="${RUMPELMC_BLOCK_EDIT_STRESS_MIN_MESH_SHADOW_ONLY:-0}"
MIN_PROXY_SHADOW="${RUMPELMC_BLOCK_EDIT_STRESS_MIN_PROXY_SHADOW:-0}"
MIN_PROXY_SHADOW_ONLY="${RUMPELMC_BLOCK_EDIT_STRESS_MIN_PROXY_SHADOW_ONLY:-0}"
MIN_COMPACT_SHADOW_PROXY="${RUMPELMC_BLOCK_EDIT_STRESS_MIN_COMPACT_SHADOW_PROXY:-0}"
MIN_PROXY_REFRESH_REUSE="${RUMPELMC_BLOCK_EDIT_STRESS_MIN_PROXY_REFRESH_REUSE:-0}"
CUTOUT_PROTOTYPE="${RUMPELMC_GPU_TERRAIN_CUTOUT_PROTOTYPE:-0}"
TRANSPARENT_REQUEST="${RUMPELMC_GPU_TERRAIN_TRANSPARENT:-0}"

fail() {
  echo "gpu_terrain_block_edit_stress: $*" >&2
  exit 1
}

metric() {
  key="$1"
  marker_path="$2"
  sed -n "s/.*$key=\([0-9][0-9]*\).*/\1/p" "$marker_path" | sed -n '1p'
}

float_metric() {
  key="$1"
  marker_path="$2"
  sed -n "s/.*$key=\([0-9][0-9]*\.[0-9][0-9]*\).*/\1/p" "$marker_path" | sed -n '1p'
}

text_metric() {
  key="$1"
  marker_path="$2"
  sed -n "s/.*$key=\([^ ]*\).*/\1/p" "$marker_path" | sed -n '1p'
}

require_metric_ge() {
  marker_path="$1"
  key="$2"
  min_value="$3"
  value="$(metric "$key" "$marker_path")"
  test -n "$value" || fail "missing $key in $marker_path"
  if [ "$value" -lt "$min_value" ]; then
    fail "$key=$value is below $min_value in $marker_path"
  fi
}

require_metric_eq() {
  marker_path="$1"
  key="$2"
  expected="$3"
  value="$(metric "$key" "$marker_path")"
  test -n "$value" || fail "missing $key in $marker_path"
  if [ "$value" -ne "$expected" ]; then
    fail "$key=$value, expected $expected in $marker_path"
  fi
}

require_text_metric_eq() {
  marker_path="$1"
  key="$2"
  expected="$3"
  value="$(text_metric "$key" "$marker_path")"
  test -n "$value" || fail "missing $key in $marker_path"
  if [ "$value" != "$expected" ]; then
    fail "$key=$value, expected $expected in $marker_path"
  fi
}

require_text_metric_contains_all() {
  marker_path="$1"
  key="$2"
  expected_list="$3"
  value="$(text_metric "$key" "$marker_path")"
  test -n "$value" || fail "missing $key in $marker_path"

  old_ifs="$IFS"
  IFS=,
  for expected in $expected_list; do
    case ",$value," in
      *",$expected,"*) ;;
      *) fail "$key=$value does not include $expected in $marker_path" ;;
    esac
  done
  IFS="$old_ifs"
}

env_truthy() {
  value="$1"
  case "$value" in
    1|true|TRUE|yes|YES|on|ON|enabled|ENABLED) return 0 ;;
    *) return 1 ;;
  esac
}

write_summary() {
  summary_path="$OUT_DIR/block-edit-stress-summary.txt"
  {
    printf 'GPU terrain block edit stress summary action=%s x=%s y=%s z=%s block_id=%s motion=%s expected_chunk=%s expected_edges=%s expected_edges_exact=%s expected_bounds=%s\n' \
      "$ACTION" "$EDIT_X" "$EDIT_Y" "$EDIT_Z" "$EDIT_BLOCK_ID" "$MOTION_NAME" "$EXPECTED_CURRENT_CHUNK" "$EXPECTED_EDGES" "$EXPECTED_EDGES_EXACT" "$EXPECTED_BOUNDS"
    printf 'block_edit_dirty chunk_replace=%s dirty_chunks=%s dirty_blocks=%s dirty_last_blocks=%s dirty_last_changed_subchunks=%s dirty_last_rebuild_subchunks=%s dirty_last_bounds=%s dirty_last_edges=%s dirty_edge_neighbor_chunks=%s dirty_edge_neighbor_subchunks=%s dirty_last_edge_neighbor_chunks=%s dirty_last_edge_neighbor_subchunks=%s dirty_partial_chunks=%s dirty_partial_subchunks=%s dirty_partial_saved_subchunks=%s dirty_last_partial_subchunks=%s dirty_last_partial_saved_subchunks=%s gpu_upload_fail=%s block_edit_dirty_observed=%s\n' \
      "$(metric chunk_replace "$marker_path")" \
      "$(metric dirty_chunks "$marker_path")" \
      "$(metric dirty_blocks "$marker_path")" \
      "$(metric dirty_last_blocks "$marker_path")" \
      "$(metric dirty_last_changed_subchunks "$marker_path")" \
      "$(metric dirty_last_rebuild_subchunks "$marker_path")" \
      "$(text_metric dirty_last_bounds "$marker_path")" \
      "$(text_metric dirty_last_edges "$marker_path")" \
      "$(metric dirty_edge_neighbor_chunks "$marker_path")" \
      "$(metric dirty_edge_neighbor_subchunks "$marker_path")" \
      "$(metric dirty_last_edge_neighbor_chunks "$marker_path")" \
      "$(metric dirty_last_edge_neighbor_subchunks "$marker_path")" \
      "$(metric dirty_partial_chunks "$marker_path")" \
      "$(metric dirty_partial_subchunks "$marker_path")" \
      "$(metric dirty_partial_saved_subchunks "$marker_path")" \
      "$(metric dirty_last_partial_subchunks "$marker_path")" \
      "$(metric dirty_last_partial_saved_subchunks "$marker_path")" \
      "$(metric gpu_upload_fail "$marker_path")" \
      "$(metric block_edit_dirty_observed "$marker_path")"
    printf 'block_edit_collision_shadow current_chunk_collision=%s collision_refresh_rebuilt=%s collision_refresh_last_rebuilt=%s mesh_shadow_only=%s proxy_shadow=%s proxy_shadow_only=%s compact_shadow_proxy=%s proxy_refresh_reuse=%s\n' \
      "$(metric current_chunk_collision "$marker_path")" \
      "$(metric collision_refresh_rebuilt "$marker_path")" \
      "$(metric collision_refresh_last_rebuilt "$marker_path")" \
      "$(metric mesh_shadow_only "$marker_path")" \
      "$(metric proxy_shadow "$marker_path")" \
      "$(metric proxy_shadow_only "$marker_path")" \
      "$(metric compact_shadow_proxy "$marker_path")" \
      "$(metric proxy_refresh_reuse "$marker_path")"
    printf 'block_edit_transparent transparent_requested=%s transparent_active=%s transparent_fallback=%s transparent_blocks=%s transparent_faces=%s transparent_draws=%s transparent_subchunks=%s transparent_cutout_uploads=%s transparent_cutout_upload_bytes=%s transparent_cutout_upload_faces=%s transparent_cutout_upload_face_bytes=%s transparent_cutout_last_upload_bytes=%s transparent_cutout_last_upload_faces=%s transparent_cutout_last_upload_face_bytes=%s transparent_sort_policy=%s transparent_sort_active=%s transparent_sort_keys=%s transparent_sort_ms=%s transparent_build_cost_source=%s transparent_build_faces=%s transparent_build_subchunks=%s transparent_build_envelope_ms=%s transparent_build_uploads=%s transparent_build_upload_bytes=%s transparent_build_upload_faces=%s transparent_build_upload_face_bytes=%s gpu_upload_fail=%s\n' \
      "$(metric transparent_requested "$marker_path")" \
      "$(metric transparent_active "$marker_path")" \
      "$(metric transparent_fallback "$marker_path")" \
      "$(metric transparent_blocks "$marker_path")" \
      "$(metric transparent_faces "$marker_path")" \
      "$(metric transparent_draws "$marker_path")" \
      "$(metric transparent_subchunks "$marker_path")" \
      "$(metric transparent_cutout_uploads "$marker_path")" \
      "$(metric transparent_cutout_upload_bytes "$marker_path")" \
      "$(metric transparent_cutout_upload_faces "$marker_path")" \
      "$(metric transparent_cutout_upload_face_bytes "$marker_path")" \
      "$(metric transparent_cutout_last_upload_bytes "$marker_path")" \
      "$(metric transparent_cutout_last_upload_faces "$marker_path")" \
      "$(metric transparent_cutout_last_upload_face_bytes "$marker_path")" \
      "$(text_metric transparent_sort_policy "$marker_path")" \
      "$(metric transparent_sort_active "$marker_path")" \
      "$(metric transparent_sort_keys "$marker_path")" \
      "$(float_metric transparent_sort_ms "$marker_path")" \
      "$(text_metric transparent_build_cost_source "$marker_path")" \
      "$(metric transparent_build_faces "$marker_path")" \
      "$(metric transparent_build_subchunks "$marker_path")" \
      "$(float_metric transparent_build_envelope_ms "$marker_path")" \
      "$(metric transparent_build_uploads "$marker_path")" \
      "$(metric transparent_build_upload_bytes "$marker_path")" \
      "$(metric transparent_build_upload_faces "$marker_path")" \
      "$(metric transparent_build_upload_face_bytes "$marker_path")" \
      "$(metric gpu_upload_fail "$marker_path")"
  } > "$summary_path"
  cat "$summary_path"
}

mkdir -p "$OUT_DIR"

echo "==> GPU terrain block edit stress"
RUMPELMC_MOVEMENT_STRESS_MOTION="$MOTION_NAME" \
RUMPELMC_MOVEMENT_STRESS_EXPECTED_CHUNK="$EXPECTED_CURRENT_CHUNK" \
RUMPELMC_MOVEMENT_STRESS_MIN_CHUNKS="$MIN_MOTION_CHUNKS" \
RUMPELMC_VISUAL_SMOKE_BLOCK_EDIT="$ACTION" \
RUMPELMC_VISUAL_SMOKE_BLOCK_EDIT_X="$EDIT_X" \
RUMPELMC_VISUAL_SMOKE_BLOCK_EDIT_Y="$EDIT_Y" \
RUMPELMC_VISUAL_SMOKE_BLOCK_EDIT_Z="$EDIT_Z" \
RUMPELMC_VISUAL_SMOKE_BLOCK_EDIT_ID="$EDIT_BLOCK_ID" \
RUMPELMC_VISUAL_SMOKE_BLOCK_EDIT_WAIT_SEC="$EDIT_WAIT_SEC" \
sh "$ROOT_DIR/scripts/gpu_terrain_movement_stress.sh" "$OUT_DIR"

marker_path="$OUT_DIR/gpu-terrain-movement-stress.png.txt"
test -s "$marker_path" || fail "missing marker $marker_path"
grep -q "block_edit=\"$ACTION\"" "$marker_path" || fail "unexpected block edit action in $marker_path"
require_metric_eq "$marker_path" block_edit_dirty_observed 1
require_metric_ge "$marker_path" chunk_replace 1
require_metric_ge "$marker_path" dirty_chunks 1
require_metric_ge "$marker_path" dirty_blocks 1
require_metric_ge "$marker_path" dirty_last_blocks 1
require_metric_ge "$marker_path" dirty_last_changed_subchunks 1
require_metric_ge "$marker_path" dirty_last_rebuild_subchunks 1
require_metric_eq "$marker_path" gpu_upload_fail 0
if [ -n "$EXPECTED_EDGES" ]; then
  if [ "$EXPECTED_EDGES_EXACT" = "1" ]; then
    require_text_metric_eq "$marker_path" dirty_last_edges "$EXPECTED_EDGES"
  else
    require_text_metric_contains_all "$marker_path" dirty_last_edges "$EXPECTED_EDGES"
  fi
fi
if [ -n "$EXPECTED_BOUNDS" ]; then
  require_text_metric_eq "$marker_path" dirty_last_bounds "$EXPECTED_BOUNDS"
fi
if [ "$MIN_PARTIAL_CHUNKS" -gt 0 ]; then
  require_metric_ge "$marker_path" dirty_partial_chunks "$MIN_PARTIAL_CHUNKS"
fi
if [ "$MIN_PARTIAL_SUBCHUNKS" -gt 0 ]; then
  require_metric_ge "$marker_path" dirty_partial_subchunks "$MIN_PARTIAL_SUBCHUNKS"
fi
if [ "$MIN_PARTIAL_SAVED_SUBCHUNKS" -gt 0 ]; then
  require_metric_ge "$marker_path" dirty_partial_saved_subchunks "$MIN_PARTIAL_SAVED_SUBCHUNKS"
fi
if [ "$MIN_EDGE_NEIGHBOR_CHUNKS" -gt 0 ]; then
  require_metric_ge "$marker_path" dirty_edge_neighbor_chunks "$MIN_EDGE_NEIGHBOR_CHUNKS"
fi
if [ "$MIN_EDGE_NEIGHBOR_SUBCHUNKS" -gt 0 ]; then
  require_metric_ge "$marker_path" dirty_edge_neighbor_subchunks "$MIN_EDGE_NEIGHBOR_SUBCHUNKS"
fi
if [ "$MIN_LAST_EDGE_NEIGHBOR_CHUNKS" -gt 0 ]; then
  require_metric_ge "$marker_path" dirty_last_edge_neighbor_chunks "$MIN_LAST_EDGE_NEIGHBOR_CHUNKS"
fi
if [ "$MIN_LAST_EDGE_NEIGHBOR_SUBCHUNKS" -gt 0 ]; then
  require_metric_ge "$marker_path" dirty_last_edge_neighbor_subchunks "$MIN_LAST_EDGE_NEIGHBOR_SUBCHUNKS"
fi
if [ "$MIN_CURRENT_CHUNK_COLLISION" -gt 0 ]; then
  require_metric_ge "$marker_path" current_chunk_collision "$MIN_CURRENT_CHUNK_COLLISION"
fi
if [ "$MIN_COLLISION_REFRESH_REBUILT" -gt 0 ]; then
  require_metric_ge "$marker_path" collision_refresh_rebuilt "$MIN_COLLISION_REFRESH_REBUILT"
fi
if [ "$MIN_LAST_COLLISION_REFRESH_REBUILT" -gt 0 ]; then
  require_metric_ge "$marker_path" collision_refresh_last_rebuilt "$MIN_LAST_COLLISION_REFRESH_REBUILT"
fi
if [ "$MIN_MESH_SHADOW_ONLY" -gt 0 ]; then
  require_metric_ge "$marker_path" mesh_shadow_only "$MIN_MESH_SHADOW_ONLY"
fi
if [ "$MIN_PROXY_SHADOW" -gt 0 ]; then
  require_metric_ge "$marker_path" proxy_shadow "$MIN_PROXY_SHADOW"
fi
if [ "$MIN_PROXY_SHADOW_ONLY" -gt 0 ]; then
  require_metric_ge "$marker_path" proxy_shadow_only "$MIN_PROXY_SHADOW_ONLY"
fi
if [ "$MIN_COMPACT_SHADOW_PROXY" -gt 0 ]; then
  require_metric_ge "$marker_path" compact_shadow_proxy "$MIN_COMPACT_SHADOW_PROXY"
fi
if [ "$MIN_PROXY_REFRESH_REUSE" -gt 0 ]; then
  require_metric_ge "$marker_path" proxy_refresh_reuse "$MIN_PROXY_REFRESH_REUSE"
fi
if env_truthy "$CUTOUT_PROTOTYPE"; then
    require_metric_eq "$marker_path" transparent_requested 1
    require_metric_eq "$marker_path" transparent_active 1
    require_metric_eq "$marker_path" transparent_fallback 0
    require_metric_ge "$marker_path" transparent_blocks 1
    require_metric_ge "$marker_path" transparent_faces 1
    require_metric_ge "$marker_path" transparent_draws 1
    require_metric_ge "$marker_path" transparent_subchunks 1
    require_metric_ge "$marker_path" transparent_cutout_uploads 1
    require_metric_ge "$marker_path" transparent_cutout_upload_bytes 1
    require_metric_ge "$marker_path" transparent_cutout_upload_faces 1
    require_metric_ge "$marker_path" transparent_cutout_upload_face_bytes 1
    require_text_metric_eq "$marker_path" transparent_sort_policy opaque_depth_alpha_test_no_sort
    require_metric_eq "$marker_path" transparent_sort_active 0
    require_metric_eq "$marker_path" transparent_sort_keys 0
    transparent_sort_ms="$(float_metric transparent_sort_ms "$marker_path")"
    test "$transparent_sort_ms" = "0.000" || fail "transparent_sort_ms=$transparent_sort_ms, expected 0.000 in $marker_path"
    require_text_metric_eq "$marker_path" transparent_build_cost_source cutout_in_opaque_mesh_phase
    require_metric_ge "$marker_path" transparent_build_faces 1
    require_metric_ge "$marker_path" transparent_build_subchunks 1
    transparent_build_envelope_ms="$(float_metric transparent_build_envelope_ms "$marker_path")"
    test -n "$transparent_build_envelope_ms" || fail "missing transparent_build_envelope_ms in $marker_path"
    require_metric_ge "$marker_path" transparent_build_uploads 1
    require_metric_ge "$marker_path" transparent_build_upload_bytes 1
    require_metric_ge "$marker_path" transparent_build_upload_faces 1
    require_metric_ge "$marker_path" transparent_build_upload_face_bytes 1
elif [ "$EDIT_BLOCK_ID" = "5" ] && ! env_truthy "$TRANSPARENT_REQUEST"; then
    require_metric_eq "$marker_path" transparent_requested 0
    require_metric_eq "$marker_path" transparent_active 0
    require_metric_eq "$marker_path" transparent_fallback 0
    require_metric_eq "$marker_path" transparent_blocks 0
    require_metric_eq "$marker_path" transparent_faces 0
    require_metric_eq "$marker_path" transparent_draws 0
    require_metric_eq "$marker_path" transparent_subchunks 0
    require_metric_eq "$marker_path" transparent_cutout_uploads 0
    require_metric_eq "$marker_path" transparent_cutout_upload_bytes 0
    require_metric_eq "$marker_path" transparent_cutout_upload_faces 0
    require_metric_eq "$marker_path" transparent_cutout_upload_face_bytes 0
    require_text_metric_eq "$marker_path" transparent_sort_policy none
    require_metric_eq "$marker_path" transparent_sort_active 0
    require_metric_eq "$marker_path" transparent_sort_keys 0
    require_text_metric_eq "$marker_path" transparent_build_cost_source inactive
    require_metric_eq "$marker_path" transparent_build_faces 0
    require_metric_eq "$marker_path" transparent_build_subchunks 0
    require_metric_eq "$marker_path" transparent_build_uploads 0
    require_metric_eq "$marker_path" transparent_build_upload_bytes 0
    require_metric_eq "$marker_path" transparent_build_upload_faces 0
    require_metric_eq "$marker_path" transparent_build_upload_face_bytes 0
fi
write_summary

echo "GPU terrain block edit stress artifacts: $OUT_DIR"
