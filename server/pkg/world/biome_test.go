package world

import (
	"crypto/sha256"
	"fmt"
	"strings"
	"testing"
)

func TestBiomeDefinitionsV1AreStableAndUnique(t *testing.T) {
	definitions := BiomeDefinitionsV1()
	if len(definitions) != 4 {
		t.Fatalf("BiomeDefinitionsV1() count = %d, want 4", len(definitions))
	}

	seen := make(map[BiomeID]bool, len(definitions))
	for _, definition := range definitions {
		if definition.ID == "" {
			t.Fatal("biome definition has empty id")
		}
		if definition.DisplayName == "" {
			t.Fatalf("biome %q has empty display name", definition.ID)
		}
		if definition.SurfaceTint > 0xffffff {
			t.Fatalf("biome %q surface tint = 0x%x, want RGB24", definition.ID, definition.SurfaceTint)
		}
		if seen[definition.ID] {
			t.Fatalf("duplicate biome id %q", definition.ID)
		}
		seen[definition.ID] = true
	}

	definitions[0].ID = "mutated"
	if got := BiomeDefinitionsV1()[0].ID; got != BiomePlains {
		t.Fatalf("BiomeDefinitionsV1() returned mutable catalog, first id = %q", got)
	}
}

func TestBiomeSamplerV1StableVector(t *testing.T) {
	generator, err := NewWorldGenerator(GeneratorConfig{
		Seed:        8675309,
		DimensionID: "overworld",
		Version:     GeneratorVersionHeightV1,
	})
	if err != nil {
		t.Fatalf("NewWorldGenerator() error = %v", err)
	}

	for _, tc := range []struct {
		worldX int64
		worldZ int64
		want   BiomeID
	}{
		{worldX: 0, worldZ: 0, want: BiomeSnowfields},
		{worldX: 63, worldZ: 63, want: BiomeSnowfields},
		{worldX: 64, worldZ: 0, want: BiomeSnowfields},
		{worldX: -1, worldZ: -1, want: BiomeForest},
		{worldX: -64, worldZ: 128, want: BiomeDryHighlands},
		{worldX: 4096, worldZ: -4097, want: BiomeDryHighlands},
	} {
		got := generator.SampleBiome(tc.worldX, tc.worldZ)
		if got.AlgorithmVersion != BiomeAlgorithmVersionV1 {
			t.Fatalf("SampleBiome(%d,%d) version = %q, want %q", tc.worldX, tc.worldZ, got.AlgorithmVersion, BiomeAlgorithmVersionV1)
		}
		if got.ID != tc.want {
			t.Fatalf("SampleBiome(%d,%d) = %q, want %q", tc.worldX, tc.worldZ, got.ID, tc.want)
		}
		if direct := DeterministicBiomeID(generator.Config(), tc.worldX, tc.worldZ); direct != got.ID {
			t.Fatalf("DeterministicBiomeID(%d,%d) = %q, want %q", tc.worldX, tc.worldZ, direct, got.ID)
		}
	}
}

func TestBiomeSamplerChangesWithSeedAndDimension(t *testing.T) {
	base := biomeSignature(GeneratorConfig{Seed: 42, DimensionID: "overworld", Version: GeneratorVersionHeightV1})
	otherSeed := biomeSignature(GeneratorConfig{Seed: 43, DimensionID: "overworld", Version: GeneratorVersionHeightV1})
	otherDimension := biomeSignature(GeneratorConfig{Seed: 42, DimensionID: "alternate_dimension", Version: GeneratorVersionHeightV1})

	if base == otherSeed {
		t.Fatal("biome signature did not change after seed change")
	}
	if base == otherDimension {
		t.Fatal("biome signature did not change after dimension change")
	}
}

func TestBiomeSamplerDoesNotChangeGeneratedChunkBytes(t *testing.T) {
	generator, err := NewWorldGenerator(GeneratorConfig{
		Seed:        99,
		DimensionID: "visual_metadata_only",
		Version:     GeneratorVersionFlatV1,
	})
	if err != nil {
		t.Fatalf("NewWorldGenerator() error = %v", err)
	}
	for _, coord := range [][2]int64{{0, 0}, {64, 0}, {-1, -1}, {2048, -2048}} {
		_ = generator.SampleBiome(coord[0], coord[1])
	}

	chunk, err := generator.GenerateChunk(-3, 5)
	if err != nil {
		t.Fatalf("GenerateChunk() error = %v", err)
	}
	sum := sha256.Sum256(chunk.Serialize())
	if got := fmt.Sprintf("%x", sum); got != stableFlatChunkSHA256 {
		t.Fatalf("flat_v1 bytes after biome sampling = %s, want %s", got, stableFlatChunkSHA256)
	}
}

func biomeSignature(config GeneratorConfig) string {
	coords := [][2]int64{
		{0, 0},
		{63, 63},
		{64, 0},
		{-1, -1},
		{-64, 128},
		{4096, -4097},
		{-8192, 8191},
	}
	ids := make([]string, 0, len(coords))
	for _, coord := range coords {
		ids = append(ids, string(DeterministicBiomeID(config, coord[0], coord[1])))
	}
	return strings.Join(ids, ",")
}
