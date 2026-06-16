package world

import (
	"bytes"
	"crypto/sha256"
	"fmt"
	"testing"
)

const (
	stableFlatChunkSHA256     = "41bc68c75bd63c8845bba319c5db67e4ef0ab627b0241cd74e406d5c1878bd94"
	stableHeightV1ChunkSHA256 = "1101411ccf572478dc9dee8772428714fd80d5ea9f82f491401e2ca410369dc7"
)

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

func TestConfiguredHeightV1GeneratorIsDeterministicForSeedDimensionAndCoordinates(t *testing.T) {
	config := GeneratorConfig{
		Seed:        8675309,
		DimensionID: "overworld",
		Version:     GeneratorVersionHeightV1,
	}
	firstWorld, err := NewWorldWithGeneratorConfig(nil, config)
	if err != nil {
		t.Fatalf("NewWorldWithGeneratorConfig(first) error = %v", err)
	}
	secondWorld, err := NewWorldWithGeneratorConfig(nil, config)
	if err != nil {
		t.Fatalf("NewWorldWithGeneratorConfig(second) error = %v", err)
	}

	first, err := firstWorld.ChunkSnapshot(-3, 5)
	if err != nil {
		t.Fatalf("first ChunkSnapshot() error = %v", err)
	}
	second, err := secondWorld.ChunkSnapshot(-3, 5)
	if err != nil {
		t.Fatalf("second ChunkSnapshot() error = %v", err)
	}
	if !bytes.Equal(first.Blocks, second.Blocks) {
		t.Fatal("height_v1 chunk bytes differ across independent worlds for identical seed, dimension, and coordinates")
	}
	if len(first.Blocks) != SerializedChunkSize {
		t.Fatalf("height_v1 snapshot bytes = %d, want %d", len(first.Blocks), SerializedChunkSize)
	}
	sum := sha256.Sum256(first.Blocks)
	if got := fmt.Sprintf("%x", sum); got != stableHeightV1ChunkSHA256 {
		t.Fatalf("height_v1 chunk SHA-256 = %s, want %s", got, stableHeightV1ChunkSHA256)
	}

	chunk, err := DeserializeChunk(first.X, first.Z, first.Blocks)
	if err != nil {
		t.Fatalf("DeserializeChunk(height_v1 snapshot) error = %v", err)
	}
	generator, err := NewWorldGenerator(config)
	if err != nil {
		t.Fatalf("NewWorldGenerator() error = %v", err)
	}
	assertHeightV1SurfaceVaries(t, generator, chunk)
	for _, pos := range [][2]int{{0, 0}, {ChunkWidth - 1, ChunkDepth - 1}, {13, 21}} {
		assertHeightV1Column(t, generator, chunk, pos[0], pos[1])
	}
}

func TestConfiguredHeightV1GeneratorChangesWithSeedAndDimension(t *testing.T) {
	base := heightV1SnapshotBytes(t, GeneratorConfig{
		Seed:        42,
		DimensionID: "overworld",
		Version:     GeneratorVersionHeightV1,
	})
	otherSeed := heightV1SnapshotBytes(t, GeneratorConfig{
		Seed:        43,
		DimensionID: "overworld",
		Version:     GeneratorVersionHeightV1,
	})
	otherDimension := heightV1SnapshotBytes(t, GeneratorConfig{
		Seed:        42,
		DimensionID: "alternate_dimension",
		Version:     GeneratorVersionHeightV1,
	})

	if bytes.Equal(base, otherSeed) {
		t.Fatal("height_v1 chunk bytes did not change after seed change")
	}
	if bytes.Equal(base, otherDimension) {
		t.Fatal("height_v1 chunk bytes did not change after dimension change")
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

func heightV1SnapshotBytes(t *testing.T, config GeneratorConfig) []byte {
	t.Helper()

	world, err := NewWorldWithGeneratorConfig(nil, config)
	if err != nil {
		t.Fatalf("NewWorldWithGeneratorConfig() error = %v", err)
	}
	snapshot, err := world.ChunkSnapshot(2, -4)
	if err != nil {
		t.Fatalf("ChunkSnapshot() error = %v", err)
	}
	return snapshot.Blocks
}

func assertHeightV1Column(t *testing.T, generator WorldGenerator, chunk *Chunk, localX, localZ int) {
	t.Helper()

	worldX := int64(chunk.X)*int64(ChunkWidth) + int64(localX)
	worldZ := int64(chunk.Z)*int64(ChunkDepth) + int64(localZ)
	surfaceY := generator.heightV1SurfaceY(worldX, worldZ)
	if surfaceY < heightV1MinSurfaceY || surfaceY > heightV1MaxSurfaceY {
		t.Fatalf("height_v1 surface at (%d, %d) = %d, want %d..%d", worldX, worldZ, surfaceY, heightV1MinSurfaceY, heightV1MaxSurfaceY)
	}
	if got := chunk.GetBlock(localX, surfaceY, localZ); got != Grass {
		t.Fatalf("height_v1 surface block at (%d, %d, %d) = %v, want Grass", localX, surfaceY, localZ, got)
	}
	if got := chunk.GetBlock(localX, surfaceY-1, localZ); got != Dirt {
		t.Fatalf("height_v1 subsurface block at (%d, %d, %d) = %v, want Dirt", localX, surfaceY-1, localZ, got)
	}
	if got := chunk.GetBlock(localX, surfaceY-2, localZ); got != Dirt {
		t.Fatalf("height_v1 second subsurface block at (%d, %d, %d) = %v, want Dirt", localX, surfaceY-2, localZ, got)
	}
	if got := chunk.GetBlock(localX, surfaceY-3, localZ); got != Stone {
		t.Fatalf("height_v1 base block at (%d, %d, %d) = %v, want Stone", localX, surfaceY-3, localZ, got)
	}
	if got := chunk.GetBlock(localX, surfaceY+1, localZ); got != Air {
		t.Fatalf("height_v1 air block at (%d, %d, %d) = %v, want Air", localX, surfaceY+1, localZ, got)
	}
}

func assertHeightV1SurfaceVaries(t *testing.T, generator WorldGenerator, chunk *Chunk) {
	t.Helper()

	minSurfaceY := ChunkHeight
	maxSurfaceY := 0
	for localX := 0; localX < ChunkWidth; localX++ {
		for localZ := 0; localZ < ChunkDepth; localZ++ {
			worldX := int64(chunk.X)*int64(ChunkWidth) + int64(localX)
			worldZ := int64(chunk.Z)*int64(ChunkDepth) + int64(localZ)
			surfaceY := generator.heightV1SurfaceY(worldX, worldZ)
			if surfaceY < heightV1MinSurfaceY || surfaceY > heightV1MaxSurfaceY {
				t.Fatalf("height_v1 surface at (%d, %d) = %d, want %d..%d", worldX, worldZ, surfaceY, heightV1MinSurfaceY, heightV1MaxSurfaceY)
			}
			if surfaceY < minSurfaceY {
				minSurfaceY = surfaceY
			}
			if surfaceY > maxSurfaceY {
				maxSurfaceY = surfaceY
			}
		}
	}
	if minSurfaceY == maxSurfaceY {
		t.Fatalf("height_v1 surface is flat at y=%d, want varied surface in representative chunk", minSurfaceY)
	}
}
