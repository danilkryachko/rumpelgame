#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/texture_atlas_evolution"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

SUMMARY_PATH="$OUT_DIR/texture-atlas-evolution-summary.txt"
DESIGN_DOC="${RUMPELMC_TEXTURE_ATLAS_DESIGN_DOC:-"$ROOT_DIR/docs/TEXTURE_ATLAS_EVOLUTION_TRACK.md"}"
BLOCK_MATERIAL_SUMMARY="${RUMPELMC_TEXTURE_ATLAS_BLOCK_MATERIAL_SUMMARY:-"$ROOT_DIR/logs/block_material_metadata_design_current/block-material-metadata-design-summary.txt"}"
BLOCKS_SOURCE="${RUMPELMC_TEXTURE_ATLAS_BLOCKS_SOURCE:-"$ROOT_DIR/client/rust_ext/src/blocks.rs"}"
GPU_TERRAIN_SOURCE="${RUMPELMC_TEXTURE_ATLAS_GPU_TERRAIN_SOURCE:-"$ROOT_DIR/client/rust_ext/src/gpu_terrain.rs"}"
RENDER_SHADER="${RUMPELMC_TEXTURE_ATLAS_RENDER_SHADER:-"$ROOT_DIR/client/shaders/gpu_terrain_render.glsl"}"
MESHER_SHADER="${RUMPELMC_TEXTURE_ATLAS_MESHER_SHADER:-"$ROOT_DIR/client/shaders/mesher.glsl"}"
ATLAS_PNG="${RUMPELMC_TEXTURE_ATLAS_PNG:-"$ROOT_DIR/client/assets/textures/blocks/block_texture_atlas.png"}"

mkdir -p "$OUT_DIR"

fail() {
  echo "texture_atlas_evolution_gate: $*" >&2
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

for path in "$DESIGN_DOC" "$BLOCK_MATERIAL_SUMMARY" "$BLOCKS_SOURCE" "$GPU_TERRAIN_SOURCE" "$RENDER_SHADER" "$MESHER_SHADER" "$ATLAS_PNG"; do
  test -s "$path" || fail "missing required input $path"
done

for token in \
  'atlas_id' \
  'tile_size_px' \
  'tile_capacity' \
  'sampler_filter' \
  'alpha_mode' \
  '0..2047' \
  'Do not repack' \
  'No atlas image edit'; do
  require_token "$DESIGN_DOC" "$token"
done

require_token "$BLOCKS_SOURCE" "pub const TEXTURE_TILE_SIZE_PX: u32 = 64;"
require_token "$BLOCKS_SOURCE" "pub const TEXTURE_ATLAS_COLUMNS: u32 = 10;"
require_token "$BLOCKS_SOURCE" "pub const TEXTURE_ATLAS_ROWS: u32 = 1;"
require_token "$BLOCKS_SOURCE" "const TILE_LEAVES: u32 = 9;"
require_token "$BLOCKS_SOURCE" "pub const MAX_TEXTURE_TILE: u32 = TILE_LEAVES;"
require_token "$BLOCKS_SOURCE" "pub fn texture_atlas_uv"
require_token "$BLOCKS_SOURCE" "compute_mesher_glsl_atlas_layout"
require_token "$GPU_TERRAIN_SOURCE" "debug_assert!(tile < 2048);"
require_token "$GPU_TERRAIN_SOURCE" "GpuTerrainAtlasLayout::from_image_size"
require_token "$GPU_TERRAIN_SOURCE" "blocks::MAX_TEXTURE_TILE >= tile_capacity"
require_token "$GPU_TERRAIN_SOURCE" "sampler_state.set_mag_filter(SamplerFilter::NEAREST);"
require_token "$GPU_TERRAIN_SOURCE" "sampler_state.set_repeat_u(SamplerRepeatMode::CLAMP_TO_EDGE);"
require_token "$RENDER_SHADER" "vec4 atlas_layout;"
require_token "$RENDER_SHADER" "uint tile = (face.pos_face_tile >> 21u) & 2047u;"
require_token "$RENDER_SHADER" "frag_color = vec4(texel.rgb * lighting_in, 1.0);"
require_token "$MESHER_SHADER" "/* RUMPELMC_ATLAS_LAYOUT */"
require_token "$MESHER_SHADER" "vec2 atlas_uv(vec2 tile_uv, uint tile_index)"

atlas_info="$(file "$ATLAS_PNG")"
atlas_width="$(printf '%s\n' "$atlas_info" | sed -n 's/.*PNG image data, \([0-9][0-9]*\) x \([0-9][0-9]*\).*/\1/p')"
atlas_height="$(printf '%s\n' "$atlas_info" | sed -n 's/.*PNG image data, \([0-9][0-9]*\) x \([0-9][0-9]*\).*/\2/p')"
test -n "$atlas_width" || fail "could not parse atlas width from: $atlas_info"
test -n "$atlas_height" || fail "could not parse atlas height from: $atlas_info"

tile_size="$(awk '/TEXTURE_TILE_SIZE_PX: u32 =/ { value=$6; gsub(/;/, "", value); print value; exit }' "$BLOCKS_SOURCE")"
declared_columns="$(awk '/TEXTURE_ATLAS_COLUMNS: u32 =/ { value=$6; gsub(/;/, "", value); print value; exit }' "$BLOCKS_SOURCE")"
declared_rows="$(awk '/TEXTURE_ATLAS_ROWS: u32 =/ { value=$6; gsub(/;/, "", value); print value; exit }' "$BLOCKS_SOURCE")"
max_texture_tile="$(awk '/const TILE_LEAVES: u32 =/ { value=$5; gsub(/;/, "", value); print value; exit }' "$BLOCKS_SOURCE")"
block_material_status="$(field_metric status "$BLOCK_MATERIAL_SUMMARY")"
block_material_schema_change="$(field_metric active_schema_change "$BLOCK_MATERIAL_SUMMARY")"
asset_diff_count="$(git -C "$ROOT_DIR" diff --name-only -- client/assets/textures/blocks | awk 'END { print NR + 0 }')"

awk \
  -v atlas_width="$atlas_width" \
  -v atlas_height="$atlas_height" \
  -v tile_size="$tile_size" \
  -v declared_columns="$declared_columns" \
  -v declared_rows="$declared_rows" \
  -v max_texture_tile="$max_texture_tile" \
  -v block_material_status="${block_material_status:-missing}" \
  -v block_material_schema_change="${block_material_schema_change:-1}" \
  -v asset_diff_count="$asset_diff_count" \
  -v design_doc="$DESIGN_DOC" \
  -v block_material_summary="$BLOCK_MATERIAL_SUMMARY" '
  BEGIN {
    status = "pass"
    reason = "ok"
    atlas_metadata_status = "designed"
    shader_layout_change = 0
    active_asset_change = asset_diff_count + 0
    packed_tile_capacity = 2048
    columns = int(atlas_width / tile_size)
    rows = int(atlas_height / tile_size)
    tile_capacity = columns * rows

    layout_ok = tile_size + 0 == 64 &&
      atlas_width + 0 == 640 &&
      atlas_height + 0 == 64 &&
      declared_columns + 0 == columns &&
      declared_rows + 0 == rows &&
      tile_capacity == 10 &&
      max_texture_tile + 0 == 9 &&
      max_texture_tile + 0 < tile_capacity &&
      max_texture_tile + 0 < packed_tile_capacity
    metadata_ok = block_material_status == "pass" && block_material_schema_change + 0 == 0

    if (!layout_ok) {
      status = "fail"
      reason = "atlas_layout_mismatch"
    } else if (!metadata_ok) {
      status = "fail"
      reason = "block_material_gate_not_clean"
    } else if (active_asset_change != 0) {
      status = "fail"
      reason = "atlas_asset_diff_present"
    }

    printf("texture_atlas_evolution status=%s reason=%s atlas_metadata_status=%s active_asset_change=%d shader_layout_change=%d atlas_width=%d atlas_height=%d tile_size_px=%d columns=%d rows=%d tile_capacity=%d max_texture_tile=%d packed_tile_capacity=%d sampler=nearest/clamp_to_edge alpha_policy=opaque_alpha_forced manifest_status=not_introduced block_material_status=%s block_material_active_schema_change=%d design_doc=%s block_material_summary=%s\n", status, reason, atlas_metadata_status, active_asset_change, shader_layout_change, atlas_width, atlas_height, tile_size, columns, rows, tile_capacity, max_texture_tile, packed_tile_capacity, block_material_status, block_material_schema_change, design_doc, block_material_summary)
    if (status != "pass") {
      exit 1
    }
  }
' > "$SUMMARY_PATH" || {
  cat "$SUMMARY_PATH" >&2 || true
  fail "texture atlas evolution gate failed"
}

cat "$SUMMARY_PATH"
echo "Texture atlas evolution artifacts: $OUT_DIR"
