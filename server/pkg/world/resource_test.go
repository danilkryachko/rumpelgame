package world

import (
	"crypto/sha256"
	"fmt"
	"strings"
	"testing"
)

func TestResourceDefinitionsV1AreStableAndUnique(t *testing.T) {
	definitions := ResourceDefinitionsV1()
	if len(definitions) != 3 {
		t.Fatalf("ResourceDefinitionsV1() count = %d, want 3", len(definitions))
	}

	seen := make(map[ResourceID]bool, len(definitions))
	for _, definition := range definitions {
		if definition.ID == "" || definition.ID == ResourceNone {
			t.Fatalf("resource definition has invalid id %q", definition.ID)
		}
		if definition.DisplayName == "" {
			t.Fatalf("resource %q has empty display name", definition.ID)
		}
		if definition.MinY < 0 || definition.MaxY >= ChunkHeight || definition.MinY > definition.MaxY {
			t.Fatalf("resource %q range = %d..%d, want bounded chunk Y range", definition.ID, definition.MinY, definition.MaxY)
		}
		if definition.Rarity == 0 {
			t.Fatalf("resource %q rarity = 0", definition.ID)
		}
		if seen[definition.ID] {
			t.Fatalf("duplicate resource id %q", definition.ID)
		}
		seen[definition.ID] = true
	}

	definitions[0].ID = "mutated"
	if got := ResourceDefinitionsV1()[0].ID; got != ResourceIron {
		t.Fatalf("ResourceDefinitionsV1() returned mutable catalog, first id = %q", got)
	}
}

func TestResourceSamplerV1StableVector(t *testing.T) {
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
		worldY int
		worldZ int64
		want   ResourceID
	}{
		{worldX: 0, worldY: 32, worldZ: 0, want: ResourceIron},
		{worldX: 15, worldY: 32, worldZ: -15, want: ResourceCoal},
		{worldX: -64, worldY: 48, worldZ: 128, want: ResourceCoal},
		{worldX: 127, worldY: 60, worldZ: 127, want: ResourceCopper},
		{worldX: 1024, worldY: 32, worldZ: -1024, want: ResourceIron},
		{worldX: -1, worldY: 4, worldZ: -1, want: ResourceNone},
		{worldX: 2048, worldY: 120, worldZ: 2048, want: ResourceNone},
	} {
		got := generator.SampleResource(tc.worldX, tc.worldY, tc.worldZ)
		if got.AlgorithmVersion != ResourceAlgorithmVersionV1 {
			t.Fatalf("SampleResource(%d,%d,%d) version = %q, want %q", tc.worldX, tc.worldY, tc.worldZ, got.AlgorithmVersion, ResourceAlgorithmVersionV1)
		}
		if got.ID != tc.want {
			t.Fatalf("SampleResource(%d,%d,%d) = %q, want %q", tc.worldX, tc.worldY, tc.worldZ, got.ID, tc.want)
		}
		if direct := DeterministicResourceID(generator.Config(), tc.worldX, tc.worldY, tc.worldZ); direct != got.ID {
			t.Fatalf("DeterministicResourceID(%d,%d,%d) = %q, want %q", tc.worldX, tc.worldY, tc.worldZ, direct, got.ID)
		}
	}
}

func TestResourceSamplerRejectsOutOfChunkY(t *testing.T) {
	generator, err := NewWorldGenerator(GeneratorConfig{
		Seed:        8675309,
		DimensionID: "overworld",
		Version:     GeneratorVersionHeightV1,
	})
	if err != nil {
		t.Fatalf("NewWorldGenerator() error = %v", err)
	}

	for _, worldY := range []int{-1, ChunkHeight} {
		if got := generator.SampleResource(0, worldY, 0); got.ID != ResourceNone {
			t.Fatalf("SampleResource(0,%d,0) = %q, want %q", worldY, got.ID, ResourceNone)
		}
	}
}

func TestResourceSamplerChangesWithSeedAndDimension(t *testing.T) {
	base := resourceSignature(GeneratorConfig{Seed: 42, DimensionID: "overworld", Version: GeneratorVersionHeightV1})
	otherSeed := resourceSignature(GeneratorConfig{Seed: 43, DimensionID: "overworld", Version: GeneratorVersionHeightV1})
	otherDimension := resourceSignature(GeneratorConfig{Seed: 42, DimensionID: "alternate_dimension", Version: GeneratorVersionHeightV1})

	if base == otherSeed {
		t.Fatal("resource signature did not change after seed change")
	}
	if base == otherDimension {
		t.Fatal("resource signature did not change after dimension change")
	}
}

func TestResourceSamplerDoesNotChangeGeneratedChunkBytes(t *testing.T) {
	generator, err := NewWorldGenerator(GeneratorConfig{
		Seed:        99,
		DimensionID: "resource_metadata_only",
		Version:     GeneratorVersionFlatV1,
	})
	if err != nil {
		t.Fatalf("NewWorldGenerator() error = %v", err)
	}
	for _, coord := range [][3]int64{{0, 32, 0}, {15, 32, -15}, {127, 60, 127}, {2048, 120, 2048}} {
		_ = generator.SampleResource(coord[0], int(coord[1]), coord[2])
	}

	chunk, err := generator.GenerateChunk(-3, 5)
	if err != nil {
		t.Fatalf("GenerateChunk() error = %v", err)
	}
	sum := sha256.Sum256(chunk.Serialize())
	if got := fmt.Sprintf("%x", sum); got != stableFlatChunkSHA256 {
		t.Fatalf("flat_v1 bytes after resource sampling = %s, want %s", got, stableFlatChunkSHA256)
	}
}

func resourceSignature(config GeneratorConfig) string {
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
	ids := make([]string, 0, len(coords))
	for _, coord := range coords {
		ids = append(ids, string(DeterministicResourceID(config, coord[0], int(coord[1]), coord[2])))
	}
	return strings.Join(ids, ",")
}
