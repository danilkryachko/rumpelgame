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
BIOME_SUMMARY="${RUMPELMC_WORLDGEN_QUALITY_BIOME_SUMMARY:-"$ROOT_DIR/logs/biome_visual_variety_foundation_current/biome-visual-variety-foundation-summary.txt"}"
CHUNK_SOURCE="${RUMPELMC_WORLDGEN_QUALITY_CHUNK_SOURCE:-"$ROOT_DIR/server/pkg/world/chunk.go"}"
WORLD_SOURCE="${RUMPELMC_WORLDGEN_QUALITY_WORLD_SOURCE:-"$ROOT_DIR/server/pkg/world/world.go"}"
WORLD_TEST="${RUMPELMC_WORLDGEN_QUALITY_WORLD_TEST:-"$ROOT_DIR/server/pkg/world/world_test.go"}"
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

for path in "$DESIGN_DOC" "$WORLDGEN_DOC" "$BIOME_SUMMARY" "$CHUNK_SOURCE" "$WORLD_SOURCE" "$WORLD_TEST"; do
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
  'Runtime worldgen quality improvements remain future work'; do
  require_token "$DESIGN_DOC" "$token"
done

require_token "$WORLDGEN_DOC" 'current strata contract'
require_token "$CHUNK_SOURCE" "func (c *Chunk) GenerateFlat()"
require_token "$CHUNK_SOURCE" "if y == 63"
require_token "$CHUNK_SOURCE" "else if y > 60"
require_token "$CHUNK_SOURCE" "binary.LittleEndian.PutUint16"
require_token "$WORLD_SOURCE" "chunk.GenerateFlat()"
require_token "$WORLD_TEST" "TestGlobalToChunkLocalHandlesNegativeBoundaries"
require_token "$WORLD_TEST" "TestChunkCoordForPositionUsesFloorAtNegativeBoundaries"

biome_status="$(field_metric status "$BIOME_SUMMARY")"
biome_runtime="$(field_metric visual_variety_runtime "$BIOME_SUMMARY")"
biome_worldgen_change="$(field_metric active_worldgen_change "$BIOME_SUMMARY")"
biome_serialization_change="$(field_metric active_serialization_change "$BIOME_SUMMARY")"
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
  -v biome_status="${biome_status:-missing}" \
  -v biome_runtime="${biome_runtime:-active}" \
  -v biome_worldgen_change="${biome_worldgen_change:-1}" \
  -v biome_serialization_change="${biome_serialization_change:-1}" \
  -v chunk_source_diff_count="$chunk_source_diff_count" \
  -v world_tests="$world_tests" \
  -v design_doc="$DESIGN_DOC" \
  -v biome_summary="$BIOME_SUMMARY" '
  BEGIN {
    status = "pass"
    reason = "ok"
    quality_pass_status = "designed"
    active_generator_change = chunk_source_diff_count + 0
    active_chunk_byte_change = chunk_source_diff_count + 0
    runtime_quality_pass = "deferred"
    coordinate_mapping = "guarded"

    biome_ok = biome_status == "pass" &&
      biome_runtime == "deferred" &&
      biome_worldgen_change + 0 == 0 &&
      biome_serialization_change + 0 == 0
    tests_ok = world_tests == "pass" || world_tests == "skipped"

    if (active_generator_change != 0 || active_chunk_byte_change != 0) {
      status = "fail"
      reason = "chunk_generator_diff_present"
    } else if (!biome_ok) {
      status = "fail"
      reason = "biome_foundation_not_clean"
    } else if (!tests_ok) {
      status = "fail"
      reason = "world_tests_failed"
    }

    printf("world_generation_quality status=%s reason=%s quality_pass_status=%s active_generator_change=%d active_chunk_byte_change=%d runtime_quality_pass=%s coordinate_mapping=%s world_tests=%s biome_status=%s biome_runtime=%s biome_active_worldgen_change=%d biome_active_serialization_change=%d design_doc=%s biome_summary=%s\n", status, reason, quality_pass_status, active_generator_change, active_chunk_byte_change, runtime_quality_pass, coordinate_mapping, world_tests, biome_status, biome_runtime, biome_worldgen_change, biome_serialization_change, design_doc, biome_summary)
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
