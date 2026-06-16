package world

import (
	"crypto/sha256"
	"fmt"
	"strings"
	"testing"
)

func TestCaveDefinitionsV1AreStableAndUnique(t *testing.T) {
	definitions := CaveDefinitionsV1()
	if len(definitions) != 2 {
		t.Fatalf("CaveDefinitionsV1() count = %d, want 2", len(definitions))
	}

	seen := make(map[CaveID]bool, len(definitions))
	for _, definition := range definitions {
		if definition.ID == "" {
			t.Fatal("cave definition has empty id")
		}
		if definition.DisplayName == "" {
			t.Fatalf("cave definition %q has empty display name", definition.ID)
		}
		if seen[definition.ID] {
			t.Fatalf("duplicate cave id %q", definition.ID)
		}
		seen[definition.ID] = true
	}
	if !seen[CaveSolid] || !seen[CaveOpen] {
		t.Fatalf("CaveDefinitionsV1() ids = %+v, want solid and open", seen)
	}

	definitions[0].ID = "mutated"
	if got := CaveDefinitionsV1()[0].ID; got != CaveSolid {
		t.Fatalf("CaveDefinitionsV1() returned mutable catalog, first id = %q", got)
	}
}

func TestCaveSamplerV1StableVector(t *testing.T) {
	generator, err := NewWorldGenerator(GeneratorConfig{
		Seed:        8675309,
		DimensionID: "overworld",
		Version:     GeneratorVersionHeightV1,
	})
	if err != nil {
		t.Fatalf("NewWorldGenerator() error = %v", err)
	}

	for _, tc := range []struct {
		worldX      int64
		worldY      int
		worldZ      int64
		wantID      CaveID
		wantDensity uint8
	}{
		{worldX: 0, worldY: 8, worldZ: 0, wantID: CaveSolid, wantDensity: 135},
		{worldX: 15, worldY: 32, worldZ: -15, wantID: CaveOpen, wantDensity: 142},
		{worldX: 127, worldY: 60, worldZ: 127, wantID: CaveOpen, wantDensity: 92},
		{worldX: 1024, worldY: 32, worldZ: -1024, wantID: CaveOpen, wantDensity: 147},
		{worldX: 4096, worldY: 12, worldZ: -4097, wantID: CaveOpen, wantDensity: 83},
		{worldX: -4096, worldY: 70, worldZ: 4096, wantID: CaveSolid, wantDensity: 179},
		{worldX: -1, worldY: 4, worldZ: -1, wantID: CaveSolid, wantDensity: 255},
		{worldX: 2048, worldY: 120, worldZ: 2048, wantID: CaveSolid, wantDensity: 255},
	} {
		got := generator.SampleCave(tc.worldX, tc.worldY, tc.worldZ)
		if got.AlgorithmVersion != CaveAlgorithmVersionV1 {
			t.Fatalf("SampleCave(%d,%d,%d) version = %q, want %q", tc.worldX, tc.worldY, tc.worldZ, got.AlgorithmVersion, CaveAlgorithmVersionV1)
		}
		if got.ID != tc.wantID || got.Density != tc.wantDensity {
			t.Fatalf("SampleCave(%d,%d,%d) = %q density %d, want %q density %d", tc.worldX, tc.worldY, tc.worldZ, got.ID, got.Density, tc.wantID, tc.wantDensity)
		}
		if direct := DeterministicCaveID(generator.Config(), tc.worldX, tc.worldY, tc.worldZ); direct != got.ID {
			t.Fatalf("DeterministicCaveID(%d,%d,%d) = %q, want %q", tc.worldX, tc.worldY, tc.worldZ, direct, got.ID)
		}
	}
}

func TestCaveSamplerRejectsOutOfCaveYBand(t *testing.T) {
	generator, err := NewWorldGenerator(GeneratorConfig{
		Seed:        8675309,
		DimensionID: "overworld",
		Version:     GeneratorVersionHeightV1,
	})
	if err != nil {
		t.Fatalf("NewWorldGenerator() error = %v", err)
	}

	for _, worldY := range []int{-1, 0, caveV1MinY - 1, caveV1MaxY + 1, ChunkHeight} {
		got := generator.SampleCave(0, worldY, 0)
		if got.ID != CaveSolid || got.Density != 255 {
			t.Fatalf("SampleCave(0,%d,0) = %q density %d, want %q density 255", worldY, got.ID, got.Density, CaveSolid)
		}
	}
}

func TestCaveSamplerChangesWithSeedAndDimension(t *testing.T) {
	base := caveSignature(GeneratorConfig{Seed: 42, DimensionID: "overworld", Version: GeneratorVersionHeightV1})
	otherSeed := caveSignature(GeneratorConfig{Seed: 43, DimensionID: "overworld", Version: GeneratorVersionHeightV1})
	otherDimension := caveSignature(GeneratorConfig{Seed: 42, DimensionID: "alternate_dimension", Version: GeneratorVersionHeightV1})

	if base == otherSeed {
		t.Fatal("cave signature did not change after seed change")
	}
	if base == otherDimension {
		t.Fatal("cave signature did not change after dimension change")
	}
}

func TestCaveSamplerDoesNotChangeGeneratedChunkBytes(t *testing.T) {
	generator, err := NewWorldGenerator(GeneratorConfig{
		Seed:        99,
		DimensionID: "cave_metadata_only",
		Version:     GeneratorVersionFlatV1,
	})
	if err != nil {
		t.Fatalf("NewWorldGenerator() error = %v", err)
	}
	for _, coord := range [][3]int64{{15, 32, -15}, {127, 60, 127}, {1024, 32, -1024}, {4096, 12, -4097}} {
		_ = generator.SampleCave(coord[0], int(coord[1]), coord[2])
	}

	chunk, err := generator.GenerateChunk(-3, 5)
	if err != nil {
		t.Fatalf("GenerateChunk() error = %v", err)
	}
	sum := sha256.Sum256(chunk.Serialize())
	if got := fmt.Sprintf("%x", sum); got != stableFlatChunkSHA256 {
		t.Fatalf("flat_v1 bytes after cave sampling = %s, want %s", got, stableFlatChunkSHA256)
	}
}

func caveSignature(config GeneratorConfig) string {
	coords := [][3]int64{
		{0, 8, 0},
		{0, 32, 0},
		{15, 32, -15},
		{64, 24, 64},
		{-64, 48, 128},
		{127, 60, 127},
		{1024, 32, -1024},
		{4096, 12, -4097},
		{-4096, 70, 4096},
		{32, 90, 32},
		{-1, 4, -1},
		{2048, 120, 2048},
	}
	parts := make([]string, 0, len(coords))
	for _, coord := range coords {
		sample := sampleCaveV1(config, coord[0], int(coord[1]), coord[2])
		parts = append(parts, fmt.Sprintf("%s:%d", sample.ID, sample.Density))
	}
	return strings.Join(parts, ",")
}
