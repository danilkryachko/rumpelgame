package world

import (
	"crypto/sha256"
	"fmt"
	"testing"
)

const stableFlatChunkSHA256 = "41bc68c75bd63c8845bba319c5db67e4ef0ab627b0241cd74e406d5c1878bd94"

func TestWorldGeneratorConfigIsExplicitSeedVersionContract(t *testing.T) {
	config := DefaultGeneratorConfig()
	if config.Seed != DefaultWorldSeed {
		t.Fatalf("default generator seed = %d, want %d", config.Seed, DefaultWorldSeed)
	}
	if config.DimensionID != DefaultDimensionID {
		t.Fatalf("default generator dimension = %q, want %q", config.DimensionID, DefaultDimensionID)
	}
	if config.Version != GeneratorVersionFlatV1 {
		t.Fatalf("default generator version = %q, want %q", config.Version, GeneratorVersionFlatV1)
	}

	world, err := NewWorldWithGeneratorConfig(nil, GeneratorConfig{
		Seed:        123456789,
		DimensionID: "test_dimension",
		Version:     GeneratorVersionFlatV1,
	})
	if err != nil {
		t.Fatalf("NewWorldWithGeneratorConfig() error = %v", err)
	}
	if got, want := world.GeneratorConfig(), (GeneratorConfig{Seed: 123456789, DimensionID: "test_dimension", Version: GeneratorVersionFlatV1}); got != want {
		t.Fatalf("world generator config = %+v, want %+v", got, want)
	}
}

func TestConfiguredFlatV1GeneratorPreservesStableChunkBytes(t *testing.T) {
	for _, config := range []GeneratorConfig{
		DefaultGeneratorConfig(),
		{Seed: 42, DimensionID: "overworld", Version: GeneratorVersionFlatV1},
		{Seed: -9001, DimensionID: "alternate_dimension", Version: GeneratorVersionFlatV1},
	} {
		t.Run(fmt.Sprintf("seed=%d/dimension=%s", config.Seed, config.DimensionID), func(t *testing.T) {
			world, err := NewWorldWithGeneratorConfig(nil, config)
			if err != nil {
				t.Fatalf("NewWorldWithGeneratorConfig() error = %v", err)
			}
			snapshot, err := world.ChunkSnapshot(-3, 5)
			if err != nil {
				t.Fatalf("ChunkSnapshot() error = %v", err)
			}
			if len(snapshot.Blocks) != SerializedChunkSize {
				t.Fatalf("snapshot bytes = %d, want %d", len(snapshot.Blocks), SerializedChunkSize)
			}
			sum := sha256.Sum256(snapshot.Blocks)
			if got := fmt.Sprintf("%x", sum); got != stableFlatChunkSHA256 {
				t.Fatalf("configured flat_v1 chunk SHA-256 = %s, want %s", got, stableFlatChunkSHA256)
			}
			chunk, err := DeserializeChunk(snapshot.X, snapshot.Z, snapshot.Blocks)
			if err != nil {
				t.Fatalf("DeserializeChunk() error = %v", err)
			}
			assertFlatStrata(t, chunk)
		})
	}
}

func TestNewWorldWithGeneratorConfigRejectsUnknownVersion(t *testing.T) {
	if _, err := NewWorldWithGeneratorConfig(nil, GeneratorConfig{
		Seed:        1,
		DimensionID: "overworld",
		Version:     GeneratorVersion("unknown_v99"),
	}); err == nil {
		t.Fatal("NewWorldWithGeneratorConfig() error = nil, want unsupported version error")
	}
}
