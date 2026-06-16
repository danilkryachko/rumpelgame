#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-"$ROOT_DIR/logs/world_generation_quality"}"
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$ROOT_DIR/$OUT_DIR" ;;
esac

SUMMARY_PATH="$OUT_DIR/world-generation-quality-summary.txt"
DESIGN_DOC="${RUMPELMC_WORLDGEN_QUALITY_DOC:-"$ROOT_DIR/docs/WORLD_GENERATION_QUALITY_PASS.md"}"
WORLDGEN_DOC="${RUMPELMC_WORLDGEN_QUALITY_WORLDGEN_DOC:-"$ROOT_DIR/docs/WORLDGEN_DETERMINISM.md"}"
CAVE_DOC="${RUMPELMC_WORLDGEN_QUALITY_CAVE_DOC:-"$ROOT_DIR/docs/CAVE_GENERATION_FOUNDATION.md"}"
RESOURCE_DOC="${RUMPELMC_WORLDGEN_QUALITY_RESOURCE_DOC:-"$ROOT_DIR/docs/RESOURCE_DISTRIBUTION_FOUNDATION.md"}"
BIOME_SUMMARY="${RUMPELMC_WORLDGEN_QUALITY_BIOME_SUMMARY:-"$ROOT_DIR/logs/biome_visual_variety_foundation_current/biome-visual-variety-foundation-summary.txt"}"
CAVE_SUMMARY="${RUMPELMC_WORLDGEN_QUALITY_CAVE_SUMMARY:-"$ROOT_DIR/logs/cave_sampler_matrix_current/cave-sampler-matrix-summary.txt"}"
RESOURCE_SUMMARY="${RUMPELMC_WORLDGEN_QUALITY_RESOURCE_SUMMARY:-"$ROOT_DIR/logs/resource_distribution_matrix_current/resource-distribution-matrix-summary.txt"}"
CHUNK_SOURCE="${RUMPELMC_WORLDGEN_QUALITY_CHUNK_SOURCE:-"$ROOT_DIR/server/pkg/world/chunk.go"}"
GENERATOR_SOURCE="${RUMPELMC_WORLDGEN_QUALITY_GENERATOR_SOURCE:-"$ROOT_DIR/server/pkg/world/generator.go"}"
CAVE_SOURCE="${RUMPELMC_WORLDGEN_QUALITY_CAVE_SOURCE:-"$ROOT_DIR/server/pkg/world/cave.go"}"
RESOURCE_SOURCE="${RUMPELMC_WORLDGEN_QUALITY_RESOURCE_SOURCE:-"$ROOT_DIR/server/pkg/world/resource.go"}"
WORLD_SOURCE="${RUMPELMC_WORLDGEN_QUALITY_WORLD_SOURCE:-"$ROOT_DIR/server/pkg/world/world.go"}"
WORLD_TEST="${RUMPELMC_WORLDGEN_QUALITY_WORLD_TEST:-"$ROOT_DIR/server/pkg/world/world_test.go"}"
GENERATOR_TEST="${RUMPELMC_WORLDGEN_QUALITY_GENERATOR_TEST:-"$ROOT_DIR/server/pkg/world/generator_test.go"}"
CAVE_TEST="${RUMPELMC_WORLDGEN_QUALITY_CAVE_TEST:-"$ROOT_DIR/server/pkg/world/cave_test.go"}"
RESOURCE_TEST="${RUMPELMC_WORLDGEN_QUALITY_RESOURCE_TEST:-"$ROOT_DIR/server/pkg/world/resource_test.go"}"
CHUNK_ENCODING_TEST="${RUMPELMC_WORLDGEN_QUALITY_CHUNK_ENCODING_TEST:-"$ROOT_DIR/server/pkg/world/chunk_encoding_test.go"}"
HEIGHT_SMOKE_SCRIPT="${RUMPELMC_WORLDGEN_QUALITY_HEIGHT_SMOKE_SCRIPT:-"$ROOT_DIR/scripts/server_height_generator_smoke.sh"}"
HEIGHT_SMOKE_SUMMARY="${RUMPELMC_WORLDGEN_QUALITY_HEIGHT_SMOKE_SUMMARY:-"$ROOT_DIR/logs/server_height_generator_smoke_current/server-height-generator-smoke-summary.txt"}"
SERVER_CMD_SOURCE="${RUMPELMC_WORLDGEN_QUALITY_SERVER_CMD_SOURCE:-"$ROOT_DIR/server/cmd/server/main.go"}"
SERVER_CMD_TEST="${RUMPELMC_WORLDGEN_QUALITY_SERVER_CMD_TEST:-"$ROOT_DIR/server/cmd/server/main_test.go"}"
RUN_GO_TESTS="${RUMPELMC_WORLDGEN_QUALITY_RUN_GO_TESTS:-1}"

mkdir -p "$OUT_DIR"

fail() {
  echo "world_generation_quality_gate: $*" >&2
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

for path in "$DESIGN_DOC" "$WORLDGEN_DOC" "$CAVE_DOC" "$RESOURCE_DOC" "$BIOME_SUMMARY" "$CAVE_SUMMARY" "$RESOURCE_SUMMARY" "$CHUNK_SOURCE" "$GENERATOR_SOURCE" "$CAVE_SOURCE" "$RESOURCE_SOURCE" "$WORLD_SOURCE" "$WORLD_TEST" "$GENERATOR_TEST" "$CAVE_TEST" "$RESOURCE_TEST" "$CHUNK_ENCODING_TEST" "$HEIGHT_SMOKE_SCRIPT" "$HEIGHT_SMOKE_SUMMARY" "$SERVER_CMD_SOURCE" "$SERVER_CMD_TEST"; do
  test -s "$path" || fail "missing required input $path"
done

for token in \
  'terrain_height_model' \
  'cave_layer' \
  'resource_layer' \
  'structure_layer' \
  'generator_version' \
  'validation_and_serialization' \
  'Do not use wall-clock time' \
  'This block is complete as a seed/version, opt-in height-generator, metadata-only biome/cave/resource, and opt-in biome-height checkpoint'; do
  require_token "$DESIGN_DOC" "$token"
done

require_token "$WORLDGEN_DOC" 'current strata contract'
require_token "$CAVE_DOC" 'Cave Generation Foundation'
require_token "$CAVE_DOC" 'cave_v1'
require_token "$CAVE_DOC" 'Cave sampling is guarded and reproducible'
require_token "$CAVE_SOURCE" "CaveAlgorithmVersionV1"
require_token "$CAVE_SOURCE" "func (g WorldGenerator) SampleCave"
require_token "$CAVE_SOURCE" "func DeterministicCaveID"
require_token "$CAVE_TEST" "TestCaveSamplerV1StableVector"
require_token "$CAVE_TEST" "TestCaveSamplerDoesNotChangeGeneratedChunkBytes"
require_token "$RESOURCE_DOC" 'Resource Distribution Foundation'
require_token "$RESOURCE_DOC" 'resource_v1'
require_token "$RESOURCE_DOC" 'Resource sampling is guarded and reproducible'
require_token "$RESOURCE_SOURCE" "ResourceAlgorithmVersionV1"
require_token "$RESOURCE_SOURCE" "func (g WorldGenerator) SampleResource"
require_token "$RESOURCE_SOURCE" "func DeterministicResourceID"
require_token "$RESOURCE_TEST" "TestResourceSamplerV1StableVector"
require_token "$RESOURCE_TEST" "TestResourceSamplerDoesNotChangeGeneratedChunkBytes"
require_token "$CHUNK_SOURCE" "func (c *Chunk) GenerateFlat()"
require_token "$CHUNK_SOURCE" "if y == 63"
require_token "$CHUNK_SOURCE" "else if y > 60"
require_token "$CHUNK_SOURCE" "binary.LittleEndian.PutUint16"
require_token "$GENERATOR_SOURCE" "type GeneratorConfig struct"
require_token "$GENERATOR_SOURCE" "Seed"
require_token "$GENERATOR_SOURCE" "DimensionID"
require_token "$GENERATOR_SOURCE" "GeneratorVersionFlatV1"
require_token "$GENERATOR_SOURCE" "GeneratorVersionHeightV1"
require_token "$GENERATOR_SOURCE" "GeneratorVersionBiomeHeightV1"
require_token "$GENERATOR_SOURCE" "DefaultGeneratorConfig"
require_token "$GENERATOR_SOURCE" "func NewWorldGenerator"
require_token "$GENERATOR_SOURCE" "func (g WorldGenerator) GenerateChunk"
require_token "$GENERATOR_SOURCE" "chunk.GenerateFlat()"
require_token "$GENERATOR_SOURCE" "func (g WorldGenerator) generateHeightV1"
require_token "$GENERATOR_SOURCE" "func (g WorldGenerator) generateBiomeHeightV1"
require_token "$GENERATOR_SOURCE" "func (g WorldGenerator) heightV1SurfaceY"
require_token "$GENERATOR_SOURCE" "func biomeHeightV1ColumnBlocks"
require_token "$WORLD_SOURCE" "NewWorldWithGeneratorConfig"
require_token "$WORLD_SOURCE" "w.generator.GenerateChunk"
require_token "$WORLD_TEST" "TestOriginChunkSnapshotUsesFlatGenerationContract"
require_token "$WORLD_TEST" "TestFlatChunkSnapshotStableByteHash"
require_token "$WORLD_TEST" "TestHeightV1EditedChunkPersistsThroughStoreReload"
require_token "$WORLD_TEST" "TestGlobalToChunkLocalHandlesNegativeBoundaries"
require_token "$WORLD_TEST" "TestGlobalToChunkLocalHandlesLargePositiveBoundaries"
require_token "$WORLD_TEST" "TestChunkCoordForPositionUsesFloorAtNegativeBoundaries"
require_token "$WORLD_TEST" "TestChunkCoordForPositionHandlesLargePositiveBoundaries"
require_token "$GENERATOR_TEST" "TestWorldGeneratorConfigIsExplicitSeedVersionContract"
require_token "$GENERATOR_TEST" "TestConfiguredFlatV1GeneratorPreservesStableChunkBytes"
require_token "$GENERATOR_TEST" "TestConfiguredHeightV1GeneratorIsDeterministicForSeedDimensionAndCoordinates"
require_token "$GENERATOR_TEST" "TestConfiguredHeightV1GeneratorChangesWithSeedAndDimension"
require_token "$GENERATOR_TEST" "TestConfiguredBiomeHeightV1GeneratorIsDeterministicForSeedDimensionAndCoordinates"
require_token "$GENERATOR_TEST" "TestConfiguredBiomeHeightV1GeneratorChangesWithSeedAndDimension"
require_token "$GENERATOR_TEST" "stableHeightV1ChunkSHA256"
require_token "$GENERATOR_TEST" "stableBiomeHeightV1ChunkSHA256"
require_token "$GENERATOR_TEST" "assertHeightV1SurfaceVaries"
require_token "$GENERATOR_TEST" "assertBiomeHeightV1Columns"
require_token "$GENERATOR_TEST" "TestNewWorldWithGeneratorConfigRejectsUnknownVersion"
require_token "$CHUNK_ENCODING_TEST" "TestEncodeSerializedChunkRLERoundTripsHeightV1Chunk"
require_token "$CHUNK_ENCODING_TEST" "TestEncodeSerializedChunkRLERoundTripsBiomeHeightV1Chunk"
require_token "$HEIGHT_SMOKE_SCRIPT" "RUMPELMC_WORLD_GENERATOR_VERSION=height_v1"
require_token "$HEIGHT_SMOKE_SCRIPT" "server_height_generator_smoke status=pass"
require_token "$SERVER_CMD_SOURCE" "configuredWorldGeneratorConfig"
require_token "$SERVER_CMD_SOURCE" "RUMPELMC_WORLD_SEED"
require_token "$SERVER_CMD_SOURCE" "RUMPELMC_WORLD_DIMENSION_ID"
require_token "$SERVER_CMD_SOURCE" "RUMPELMC_WORLD_GENERATOR_VERSION"
require_token "$SERVER_CMD_SOURCE" "world.NewWorldWithGeneratorConfig"
require_token "$SERVER_CMD_TEST" "TestConfiguredWorldGeneratorConfigDefaultsToFlatV1"
require_token "$SERVER_CMD_TEST" "TestConfiguredWorldGeneratorConfigUsesEnvOverrides"
require_token "$SERVER_CMD_TEST" "TestConfiguredWorldGeneratorConfigRejectsInvalidSeed"
require_token "$SERVER_CMD_TEST" "TestConfiguredWorldGeneratorConfigRejectsUnknownVersion"

biome_status="$(field_metric status "$BIOME_SUMMARY")"
biome_runtime="$(field_metric visual_variety_runtime "$BIOME_SUMMARY")"
biome_worldgen_change="$(field_metric active_worldgen_change "$BIOME_SUMMARY")"
biome_serialization_change="$(field_metric active_serialization_change "$BIOME_SUMMARY")"
biome_sampler="$(field_metric biome_sampler "$BIOME_SUMMARY")"
biome_matrix="$(field_metric biome_matrix "$BIOME_SUMMARY")"
cave_status="$(field_metric status "$CAVE_SUMMARY")"
cave_matrix="$(field_metric matrix_status "$CAVE_SUMMARY")"
cave_runtime="$(field_metric metadata_runtime "$CAVE_SUMMARY")"
cave_worldgen_change="$(field_metric active_worldgen_change "$CAVE_SUMMARY")"
cave_serialization_change="$(field_metric active_serialization_change "$CAVE_SUMMARY")"
cave_protocol_change="$(field_metric protocol_change "$CAVE_SUMMARY")"
resource_status="$(field_metric status "$RESOURCE_SUMMARY")"
resource_matrix="$(field_metric matrix_status "$RESOURCE_SUMMARY")"
resource_runtime="$(field_metric metadata_runtime "$RESOURCE_SUMMARY")"
resource_worldgen_change="$(field_metric active_worldgen_change "$RESOURCE_SUMMARY")"
resource_serialization_change="$(field_metric active_serialization_change "$RESOURCE_SUMMARY")"
resource_protocol_change="$(field_metric protocol_change "$RESOURCE_SUMMARY")"
height_smoke_status="$(field_metric status "$HEIGHT_SMOKE_SUMMARY")"
height_smoke_generator="$(field_metric generator_version "$HEIGHT_SMOKE_SUMMARY")"
height_smoke_encoding="$(field_metric encoding "$HEIGHT_SMOKE_SUMMARY")"
height_smoke_varied="$(field_metric varied_surface "$HEIGHT_SMOKE_SUMMARY")"
height_smoke_protocol_change="$(field_metric protocol_change "$HEIGHT_SMOKE_SUMMARY")"

world_tests="skipped"
if [ "$RUN_GO_TESTS" = "1" ]; then
  if (cd "$ROOT_DIR/server" && go test ./pkg/world ./cmd/server > "$OUT_DIR/go-test-world.txt" 2>&1); then
    world_tests="pass"
  else
    cat "$OUT_DIR/go-test-world.txt" >&2 || true
    world_tests="fail"
  fi
fi

awk \
  -v biome_status="${biome_status:-missing}" \
  -v biome_runtime="${biome_runtime:-active}" \
  -v biome_worldgen_change="${biome_worldgen_change:-1}" \
  -v biome_serialization_change="${biome_serialization_change:-1}" \
  -v biome_sampler="${biome_sampler:-missing}" \
  -v biome_matrix="${biome_matrix:-missing}" \
  -v cave_status="${cave_status:-missing}" \
  -v cave_matrix="${cave_matrix:-missing}" \
  -v cave_runtime="${cave_runtime:-active}" \
  -v cave_worldgen_change="${cave_worldgen_change:-1}" \
  -v cave_serialization_change="${cave_serialization_change:-1}" \
  -v cave_protocol_change="${cave_protocol_change:-1}" \
  -v resource_status="${resource_status:-missing}" \
  -v resource_matrix="${resource_matrix:-missing}" \
  -v resource_runtime="${resource_runtime:-active}" \
  -v resource_worldgen_change="${resource_worldgen_change:-1}" \
  -v resource_serialization_change="${resource_serialization_change:-1}" \
  -v resource_protocol_change="${resource_protocol_change:-1}" \
  -v height_smoke_status="${height_smoke_status:-missing}" \
  -v height_smoke_generator="${height_smoke_generator:-missing}" \
  -v height_smoke_encoding="${height_smoke_encoding:-missing}" \
  -v height_smoke_varied="${height_smoke_varied:-0}" \
  -v height_smoke_protocol_change="${height_smoke_protocol_change:-1}" \
  -v world_tests="$world_tests" \
  -v design_doc="$DESIGN_DOC" \
  -v biome_summary="$BIOME_SUMMARY" \
  -v cave_summary="$CAVE_SUMMARY" \
  -v resource_summary="$RESOURCE_SUMMARY" '
  BEGIN {
    status = "pass"
    reason = "ok"
    quality_pass_status = "designed"
    worldgen_seed_version = "guarded"
    worldgen_height_v1 = "guarded"
    worldgen_biome_height_v1 = "guarded"
    height_v1_serialization = "guarded"
    biome_height_v1_serialization = "guarded"
    cave_distribution = "guarded"
    resource_distribution = "guarded"
    height_v1_live_smoke = "guarded"
    active_generator_change = 0
    active_chunk_byte_change = 0
    runtime_quality_pass = "opt_in_biome_height_v1_guarded"
    coordinate_mapping = "guarded"
    origin_chunk = "guarded"
    flat_byte_hash = "guarded"

    biome_ok = biome_status == "pass" &&
      biome_sampler == "guarded" &&
      biome_matrix == "guarded" &&
      biome_runtime == "deferred" &&
      biome_worldgen_change + 0 == 0 &&
      biome_serialization_change + 0 == 0
    cave_ok = cave_status == "pass" &&
      cave_matrix == "guarded" &&
      cave_runtime == "matrix_only" &&
      cave_worldgen_change + 0 == 0 &&
      cave_serialization_change + 0 == 0 &&
      cave_protocol_change + 0 == 0
    resource_ok = resource_status == "pass" &&
      resource_matrix == "guarded" &&
      resource_runtime == "matrix_only" &&
      resource_worldgen_change + 0 == 0 &&
      resource_serialization_change + 0 == 0 &&
      resource_protocol_change + 0 == 0
    height_smoke_ok = height_smoke_status == "pass" &&
      height_smoke_generator == "height_v1" &&
      height_smoke_encoding == "rle" &&
      height_smoke_varied + 0 == 1 &&
      height_smoke_protocol_change + 0 == 0
    tests_ok = world_tests == "pass" || world_tests == "skipped"

    if (!biome_ok) {
      status = "fail"
      reason = "biome_foundation_not_clean"
    } else if (!cave_ok) {
      status = "fail"
      reason = "cave_distribution_not_clean"
    } else if (!resource_ok) {
      status = "fail"
      reason = "resource_distribution_not_clean"
    } else if (!height_smoke_ok) {
      status = "fail"
      reason = "height_v1_live_smoke_not_clean"
    } else if (!tests_ok) {
      status = "fail"
      reason = "world_tests_failed"
    }

    printf("world_generation_quality status=%s reason=%s quality_pass_status=%s worldgen_seed_version=%s worldgen_height_v1=%s worldgen_biome_height_v1=%s height_v1_serialization=%s biome_height_v1_serialization=%s cave_distribution=%s resource_distribution=%s height_v1_live_smoke=%s active_generator_change=%d active_chunk_byte_change=%d runtime_quality_pass=%s coordinate_mapping=%s origin_chunk=%s flat_byte_hash=%s world_tests=%s biome_status=%s biome_sampler=%s biome_matrix=%s biome_runtime=%s biome_active_worldgen_change=%d biome_active_serialization_change=%d cave_status=%s cave_matrix=%s cave_runtime=%s cave_active_worldgen_change=%d cave_active_serialization_change=%d cave_protocol_change=%d resource_status=%s resource_matrix=%s resource_runtime=%s resource_active_worldgen_change=%d resource_active_serialization_change=%d resource_protocol_change=%d height_smoke_status=%s height_smoke_encoding=%s design_doc=%s biome_summary=%s cave_summary=%s resource_summary=%s\n", status, reason, quality_pass_status, worldgen_seed_version, worldgen_height_v1, worldgen_biome_height_v1, height_v1_serialization, biome_height_v1_serialization, cave_distribution, resource_distribution, height_v1_live_smoke, active_generator_change, active_chunk_byte_change, runtime_quality_pass, coordinate_mapping, origin_chunk, flat_byte_hash, world_tests, biome_status, biome_sampler, biome_matrix, biome_runtime, biome_worldgen_change, biome_serialization_change, cave_status, cave_matrix, cave_runtime, cave_worldgen_change, cave_serialization_change, cave_protocol_change, resource_status, resource_matrix, resource_runtime, resource_worldgen_change, resource_serialization_change, resource_protocol_change, height_smoke_status, height_smoke_encoding, design_doc, biome_summary, cave_summary, resource_summary)
    if (status != "pass") {
      exit 1
    }
  }
' > "$SUMMARY_PATH" || {
  cat "$SUMMARY_PATH" >&2 || true
  fail "world generation quality gate failed"
}

cat "$SUMMARY_PATH"
echo "World generation quality artifacts: $OUT_DIR"
