#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/biome_visual_variety_foundation"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

SUMMARY_PATH="$OUT_DIR/biome-visual-variety-foundation-summary.txt"
DESIGN_DOC="${RUMPELMC_BIOME_FOUNDATION_DOC:-"$ROOT_DIR/docs/BIOME_VISUAL_VARIETY_FOUNDATION.md"}"
WORLDGEN_DOC="${RUMPELMC_BIOME_WORLDGEN_DOC:-"$ROOT_DIR/docs/WORLDGEN_DETERMINISM.md"}"
BIOME_SOURCE="${RUMPELMC_BIOME_SOURCE:-"$ROOT_DIR/server/pkg/world/biome.go"}"
BIOME_TEST="${RUMPELMC_BIOME_TEST:-"$ROOT_DIR/server/pkg/world/biome_test.go"}"
CHUNK_SOURCE="${RUMPELMC_BIOME_CHUNK_SOURCE:-"$ROOT_DIR/server/pkg/world/chunk.go"}"
CHUNK_TEST="${RUMPELMC_BIOME_CHUNK_TEST:-"$ROOT_DIR/server/pkg/world/chunk_test.go"}"
WORLD_TEST="${RUMPELMC_BIOME_WORLD_TEST:-"$ROOT_DIR/server/pkg/world/world_test.go"}"
BIOME_MATRIX_SUMMARY="${RUMPELMC_BIOME_MATRIX_SUMMARY:-"$ROOT_DIR/logs/biome_sampler_matrix_current/biome-sampler-matrix-summary.txt"}"
BLOCK_MATERIAL_SUMMARY="${RUMPELMC_BIOME_BLOCK_MATERIAL_SUMMARY:-"$ROOT_DIR/logs/block_material_metadata_design_current/block-material-metadata-design-summary.txt"}"
ATLAS_SUMMARY="${RUMPELMC_BIOME_ATLAS_SUMMARY:-"$ROOT_DIR/logs/texture_atlas_evolution_current/texture-atlas-evolution-summary.txt"}"
RUN_GO_TESTS="${RUMPELMC_BIOME_FOUNDATION_RUN_GO_TESTS:-1}"

mkdir -p "$OUT_DIR"

fail() {
  echo "biome_visual_variety_foundation_gate: $*" >&2
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

for path in "$DESIGN_DOC" "$WORLDGEN_DOC" "$BIOME_SOURCE" "$BIOME_TEST" "$CHUNK_SOURCE" "$CHUNK_TEST" "$WORLD_TEST" "$BIOME_MATRIX_SUMMARY" "$BLOCK_MATERIAL_SUMMARY" "$ATLAS_SUMMARY"; do
  test -s "$path" || fail "missing required input $path"
done

for token in \
  'deterministic_biome_id' \
  'world_seed' \
  'biome_algorithm_version' \
  'Layer 1, metadata-only' \
  'Layer 2, client-visible but block-preserving' \
  'Layer 3, block-distribution changes' \
  'No terrain shape change' \
  'Default runtime biome terrain generation and visual variation remain inactive'; do
  require_token "$DESIGN_DOC" "$token"
done

require_token "$BIOME_SOURCE" "type BiomeID string"
require_token "$BIOME_SOURCE" "BiomeAlgorithmVersionV1"
require_token "$BIOME_SOURCE" "BiomeDefinitionsV1"
require_token "$BIOME_SOURCE" "func (g WorldGenerator) SampleBiome"
require_token "$BIOME_SOURCE" "func DeterministicBiomeID"
require_token "$BIOME_TEST" "TestBiomeDefinitionsV1AreStableAndUnique"
require_token "$BIOME_TEST" "TestBiomeSamplerV1StableVector"
require_token "$BIOME_TEST" "TestBiomeSamplerChangesWithSeedAndDimension"
require_token "$BIOME_TEST" "TestBiomeSamplerDoesNotChangeGeneratedChunkBytes"
require_token "$WORLDGEN_DOC" '`Chunk.GenerateFlat()` is deterministic'
require_token "$WORLDGEN_DOC" 'Stone` from `y=0..60`'
require_token "$WORLDGEN_DOC" 'Dirt` from `y=61..62`'
require_token "$WORLDGEN_DOC" 'Grass` at `y=63`'
require_token "$WORLDGEN_DOC" 'Chunk.Serialize()` emits a stable little-endian `u16` block array'
require_token "$CHUNK_SOURCE" "func (c *Chunk) GenerateFlat()"
require_token "$CHUNK_SOURCE" "if y == 63"
require_token "$CHUNK_SOURCE" "else if y > 60"
require_token "$CHUNK_SOURCE" "binary.LittleEndian.PutUint16"
require_token "$CHUNK_SOURCE" "binary.LittleEndian.Uint16"
require_token "$CHUNK_TEST" "GenerateFlat serialized output differs for identical chunk coordinates"
require_token "$CHUNK_TEST" "assertFlatStrata"
require_token "$CHUNK_TEST" "TestSerializeUsesLittleEndianBlockIDs"
require_token "$WORLD_TEST" "TestChunkSnapshotIsDeterministicAcrossWorldInstances"

block_material_status="$(field_metric status "$BLOCK_MATERIAL_SUMMARY")"
block_material_schema_change="$(field_metric active_schema_change "$BLOCK_MATERIAL_SUMMARY")"
biome_matrix_status="$(field_metric status "$BIOME_MATRIX_SUMMARY")"
biome_matrix_guard="$(field_metric matrix_status "$BIOME_MATRIX_SUMMARY")"
biome_matrix_worldgen_change="$(field_metric active_worldgen_change "$BIOME_MATRIX_SUMMARY")"
biome_matrix_serialization_change="$(field_metric active_serialization_change "$BIOME_MATRIX_SUMMARY")"
biome_matrix_protocol_change="$(field_metric protocol_change "$BIOME_MATRIX_SUMMARY")"
atlas_status="$(field_metric status "$ATLAS_SUMMARY")"
atlas_asset_change="$(field_metric active_asset_change "$ATLAS_SUMMARY")"
atlas_shader_change="$(field_metric shader_layout_change "$ATLAS_SUMMARY")"
chunk_source_diff_count="$(git -C "$ROOT_DIR" diff --name-only -- server/pkg/world/chunk.go | awk 'END { print NR + 0 }')"

world_tests="skipped"
if [ "$RUN_GO_TESTS" = "1" ]; then
  if (cd "$ROOT_DIR/server" && go test ./pkg/world > "$OUT_DIR/go-test-world.txt" 2>&1); then
    world_tests="pass"
  else
    cat "$OUT_DIR/go-test-world.txt" >&2 || true
    world_tests="fail"
  fi
fi

awk \
  -v block_material_status="${block_material_status:-missing}" \
  -v block_material_schema_change="${block_material_schema_change:-1}" \
  -v biome_matrix_status="${biome_matrix_status:-missing}" \
  -v biome_matrix_guard="${biome_matrix_guard:-missing}" \
  -v biome_matrix_worldgen_change="${biome_matrix_worldgen_change:-1}" \
  -v biome_matrix_serialization_change="${biome_matrix_serialization_change:-1}" \
  -v biome_matrix_protocol_change="${biome_matrix_protocol_change:-1}" \
  -v atlas_status="${atlas_status:-missing}" \
  -v atlas_asset_change="${atlas_asset_change:-1}" \
  -v atlas_shader_change="${atlas_shader_change:-1}" \
  -v chunk_source_diff_count="$chunk_source_diff_count" \
  -v world_tests="$world_tests" \
  -v design_doc="$DESIGN_DOC" \
  -v worldgen_doc="$WORLDGEN_DOC" \
  -v block_material_summary="$BLOCK_MATERIAL_SUMMARY" \
  -v atlas_summary="$ATLAS_SUMMARY" '
  BEGIN {
    status = "pass"
    reason = "ok"
    biome_foundation_status = "designed"
    biome_sampler = "guarded"
    biome_matrix = "guarded"
    metadata_layer = "guarded"
    active_worldgen_change = chunk_source_diff_count + 0
    active_serialization_change = chunk_source_diff_count + 0
    visual_variety_runtime = "deferred"

    dependencies_ok = block_material_status == "pass" &&
      block_material_schema_change + 0 == 0 &&
      biome_matrix_status == "pass" &&
      biome_matrix_guard == "guarded" &&
      biome_matrix_worldgen_change + 0 == 0 &&
      biome_matrix_serialization_change + 0 == 0 &&
      biome_matrix_protocol_change + 0 == 0 &&
      atlas_status == "pass" &&
      atlas_asset_change + 0 == 0 &&
      atlas_shader_change + 0 == 0
    tests_ok = world_tests == "pass" || world_tests == "skipped"

    if (active_worldgen_change != 0 || active_serialization_change != 0) {
      status = "fail"
      reason = "chunk_generation_or_serialization_diff_present"
    } else if (!dependencies_ok) {
      status = "fail"
      reason = "material_or_atlas_gate_not_clean"
    } else if (!tests_ok) {
      status = "fail"
      reason = "world_tests_failed"
    }

    printf("biome_visual_variety_foundation status=%s reason=%s biome_foundation_status=%s biome_sampler=%s biome_matrix=%s metadata_layer=%s active_worldgen_change=%d active_serialization_change=%d visual_variety_runtime=%s deterministic_model=designed world_tests=%s block_material_status=%s block_material_active_schema_change=%d atlas_status=%s atlas_active_asset_change=%d atlas_shader_layout_change=%d design_doc=%s worldgen_doc=%s block_material_summary=%s atlas_summary=%s\n", status, reason, biome_foundation_status, biome_sampler, biome_matrix, metadata_layer, active_worldgen_change, active_serialization_change, visual_variety_runtime, world_tests, block_material_status, block_material_schema_change, atlas_status, atlas_asset_change, atlas_shader_change, design_doc, worldgen_doc, block_material_summary, atlas_summary)
    if (status != "pass") {
      exit 1
    }
  }
' > "$SUMMARY_PATH" || {
  cat "$SUMMARY_PATH" >&2 || true
  fail "biome visual variety foundation gate failed"
}

cat "$SUMMARY_PATH"
echo "Biome visual variety foundation artifacts: $OUT_DIR"
