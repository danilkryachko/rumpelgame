package world

import (
	"bytes"
	"crypto/sha256"
	"fmt"
	"testing"
)

const (
	stableFlatChunkSHA256              = "41bc68c75bd63c8845bba319c5db67e4ef0ab627b0241cd74e406d5c1878bd94"
	stableHeightV1ChunkSHA256          = "1101411ccf572478dc9dee8772428714fd80d5ea9f82f491401e2ca410369dc7"
	stableBiomeHeightV1ChunkSHA256     = "af66b8ea8a62f93acb3dda64fe20b845d08f3d7ac5e3de3f7712691b636d149b"
	stableCaveHeightV1ChunkSHA256      = "b68d1ca3e6471015c317c4b1d750dcddc59a8481f4cc2d26e394730d55fd7541"
	stableBiomeCaveHeightV1ChunkSHA256 = "c781f5530436094665f9596b9338065717400f4d497b9dd32f3f0d8839ff76a0"
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

func TestConfiguredBiomeHeightV1GeneratorIsDeterministicForSeedDimensionAndCoordinates(t *testing.T) {
	config := GeneratorConfig{
		Seed:        8675309,
		DimensionID: "overworld",
		Version:     GeneratorVersionBiomeHeightV1,
	}
	firstWorld, err := NewWorldWithGeneratorConfig(nil, config)
	if err != nil {
		t.Fatalf("NewWorldWithGeneratorConfig(first) error = %v", err)
	}
	secondWorld, err := NewWorldWithGeneratorConfig(nil, config)
	if err != nil {
		t.Fatalf("NewWorldWithGeneratorConfig(second) error = %v", err)
	}

	first, err := firstWorld.ChunkSnapshot(0, 0)
	if err != nil {
		t.Fatalf("first ChunkSnapshot() error = %v", err)
	}
	second, err := secondWorld.ChunkSnapshot(0, 0)
	if err != nil {
		t.Fatalf("second ChunkSnapshot() error = %v", err)
	}
	if !bytes.Equal(first.Blocks, second.Blocks) {
		t.Fatal("biome_height_v1 chunk bytes differ across independent worlds for identical seed, dimension, and coordinates")
	}
	if len(first.Blocks) != SerializedChunkSize {
		t.Fatalf("biome_height_v1 snapshot bytes = %d, want %d", len(first.Blocks), SerializedChunkSize)
	}
	sum := sha256.Sum256(first.Blocks)
	if got := fmt.Sprintf("%x", sum); got != stableBiomeHeightV1ChunkSHA256 {
		t.Fatalf("biome_height_v1 chunk SHA-256 = %s, want %s", got, stableBiomeHeightV1ChunkSHA256)
	}
	if got := fmt.Sprintf("%x", sum); got == stableHeightV1ChunkSHA256 {
		t.Fatalf("biome_height_v1 representative chunk SHA-256 unexpectedly matches height_v1 hash %s", got)
	}

	chunk, err := DeserializeChunk(first.X, first.Z, first.Blocks)
	if err != nil {
		t.Fatalf("DeserializeChunk(biome_height_v1 snapshot) error = %v", err)
	}
	generator, err := NewWorldGenerator(config)
	if err != nil {
		t.Fatalf("NewWorldGenerator() error = %v", err)
	}
	assertHeightV1SurfaceVaries(t, generator, chunk)
	assertBiomeHeightV1Columns(t, generator)
}

func TestConfiguredBiomeHeightV1GeneratorChangesWithSeedAndDimension(t *testing.T) {
	base := biomeHeightV1SnapshotBytes(t, GeneratorConfig{
		Seed:        42,
		DimensionID: "overworld",
		Version:     GeneratorVersionBiomeHeightV1,
	})
	otherSeed := biomeHeightV1SnapshotBytes(t, GeneratorConfig{
		Seed:        43,
		DimensionID: "overworld",
		Version:     GeneratorVersionBiomeHeightV1,
	})
	otherDimension := biomeHeightV1SnapshotBytes(t, GeneratorConfig{
		Seed:        42,
		DimensionID: "alternate_dimension",
		Version:     GeneratorVersionBiomeHeightV1,
	})

	if bytes.Equal(base, otherSeed) {
		t.Fatal("biome_height_v1 chunk bytes did not change after seed change")
	}
	if bytes.Equal(base, otherDimension) {
		t.Fatal("biome_height_v1 chunk bytes did not change after dimension change")
	}
}

func TestConfiguredCaveHeightV1GeneratorIsDeterministicForSeedDimensionAndCoordinates(t *testing.T) {
	config := GeneratorConfig{
		Seed:        8675309,
		DimensionID: "overworld",
		Version:     GeneratorVersionCaveHeightV1,
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
		t.Fatal("cave_height_v1 chunk bytes differ across independent worlds for identical seed, dimension, and coordinates")
	}
	if len(first.Blocks) != SerializedChunkSize {
		t.Fatalf("cave_height_v1 snapshot bytes = %d, want %d", len(first.Blocks), SerializedChunkSize)
	}
	sum := sha256.Sum256(first.Blocks)
	if got := fmt.Sprintf("%x", sum); got != stableCaveHeightV1ChunkSHA256 {
		t.Fatalf("cave_height_v1 chunk SHA-256 = %s, want %s", got, stableCaveHeightV1ChunkSHA256)
	}
	if got := fmt.Sprintf("%x", sum); got == stableHeightV1ChunkSHA256 {
		t.Fatalf("cave_height_v1 representative chunk SHA-256 unexpectedly matches height_v1 hash %s", got)
	}

	chunk, err := DeserializeChunk(first.X, first.Z, first.Blocks)
	if err != nil {
		t.Fatalf("DeserializeChunk(cave_height_v1 snapshot) error = %v", err)
	}
	generator, err := NewWorldGenerator(config)
	if err != nil {
		t.Fatalf("NewWorldGenerator() error = %v", err)
	}
	assertHeightV1SurfaceVaries(t, generator, chunk)
	assertCaveHeightV1CarvesUndergroundOpenSamples(t, generator, chunk, 34728)
}

func TestConfiguredCaveHeightV1GeneratorChangesWithSeedAndDimension(t *testing.T) {
	base := caveHeightV1SnapshotBytes(t, GeneratorConfig{
		Seed:        42,
		DimensionID: "overworld",
		Version:     GeneratorVersionCaveHeightV1,
	})
	otherSeed := caveHeightV1SnapshotBytes(t, GeneratorConfig{
		Seed:        43,
		DimensionID: "overworld",
		Version:     GeneratorVersionCaveHeightV1,
	})
	otherDimension := caveHeightV1SnapshotBytes(t, GeneratorConfig{
		Seed:        42,
		DimensionID: "alternate_dimension",
		Version:     GeneratorVersionCaveHeightV1,
	})

	if bytes.Equal(base, otherSeed) {
		t.Fatal("cave_height_v1 chunk bytes did not change after seed change")
	}
	if bytes.Equal(base, otherDimension) {
		t.Fatal("cave_height_v1 chunk bytes did not change after dimension change")
	}
}

func TestConfiguredBiomeCaveHeightV1GeneratorIsDeterministicForSeedDimensionAndCoordinates(t *testing.T) {
	config := GeneratorConfig{
		Seed:        8675309,
		DimensionID: "overworld",
		Version:     GeneratorVersionBiomeCaveHeightV1,
	}
	firstWorld, err := NewWorldWithGeneratorConfig(nil, config)
	if err != nil {
		t.Fatalf("NewWorldWithGeneratorConfig(first) error = %v", err)
	}
	secondWorld, err := NewWorldWithGeneratorConfig(nil, config)
	if err != nil {
		t.Fatalf("NewWorldWithGeneratorConfig(second) error = %v", err)
	}

	first, err := firstWorld.ChunkSnapshot(0, 0)
	if err != nil {
		t.Fatalf("first ChunkSnapshot() error = %v", err)
	}
	second, err := secondWorld.ChunkSnapshot(0, 0)
	if err != nil {
		t.Fatalf("second ChunkSnapshot() error = %v", err)
	}
	if !bytes.Equal(first.Blocks, second.Blocks) {
		t.Fatal("biome_cave_height_v1 chunk bytes differ across independent worlds for identical seed, dimension, and coordinates")
	}
	if len(first.Blocks) != SerializedChunkSize {
		t.Fatalf("biome_cave_height_v1 snapshot bytes = %d, want %d", len(first.Blocks), SerializedChunkSize)
	}
	sum := sha256.Sum256(first.Blocks)
	if got := fmt.Sprintf("%x", sum); got != stableBiomeCaveHeightV1ChunkSHA256 {
		t.Fatalf("biome_cave_height_v1 chunk SHA-256 = %s, want %s", got, stableBiomeCaveHeightV1ChunkSHA256)
	}
	if got := fmt.Sprintf("%x", sum); got == stableBiomeHeightV1ChunkSHA256 {
		t.Fatalf("biome_cave_height_v1 representative chunk SHA-256 unexpectedly matches biome_height_v1 hash %s", got)
	}

	chunk, err := DeserializeChunk(first.X, first.Z, first.Blocks)
	if err != nil {
		t.Fatalf("DeserializeChunk(biome_cave_height_v1 snapshot) error = %v", err)
	}
	generator, err := NewWorldGenerator(config)
	if err != nil {
		t.Fatalf("NewWorldGenerator() error = %v", err)
	}
	assertHeightV1SurfaceVaries(t, generator, chunk)
	assertBiomeCaveHeightV1Columns(t, generator)
	assertBiomeCaveHeightV1CombinesBiomeBlocksAndCaves(t, generator, chunk, 28152, 1024)
}

func TestConfiguredBiomeCaveHeightV1GeneratorChangesWithSeedAndDimension(t *testing.T) {
	base := biomeCaveHeightV1SnapshotBytes(t, GeneratorConfig{
		Seed:        42,
		DimensionID: "overworld",
		Version:     GeneratorVersionBiomeCaveHeightV1,
	})
	otherSeed := biomeCaveHeightV1SnapshotBytes(t, GeneratorConfig{
		Seed:        43,
		DimensionID: "overworld",
		Version:     GeneratorVersionBiomeCaveHeightV1,
	})
	otherDimension := biomeCaveHeightV1SnapshotBytes(t, GeneratorConfig{
		Seed:        42,
		DimensionID: "alternate_dimension",
		Version:     GeneratorVersionBiomeCaveHeightV1,
	})

	if bytes.Equal(base, otherSeed) {
		t.Fatal("biome_cave_height_v1 chunk bytes did not change after seed change")
	}
	if bytes.Equal(base, otherDimension) {
		t.Fatal("biome_cave_height_v1 chunk bytes did not change after dimension change")
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

func biomeHeightV1SnapshotBytes(t *testing.T, config GeneratorConfig) []byte {
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

func caveHeightV1SnapshotBytes(t *testing.T, config GeneratorConfig) []byte {
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

func biomeCaveHeightV1SnapshotBytes(t *testing.T, config GeneratorConfig) []byte {
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

func assertBiomeHeightV1Columns(t *testing.T, generator WorldGenerator) {
	t.Helper()

	for _, biomeID := range []BiomeID{BiomePlains, BiomeForest, BiomeDryHighlands, BiomeSnowfields} {
		worldX, worldZ := findBiomeSampleCoordinate(t, generator, biomeID)
		chunkX, localX := GlobalToChunkLocal(int32(worldX), ChunkWidth)
		chunkZ, localZ := GlobalToChunkLocal(int32(worldZ), ChunkDepth)
		generated, err := generator.GenerateChunk(chunkX, chunkZ)
		if err != nil {
			t.Fatalf("GenerateChunk(%d,%d) error = %v", chunkX, chunkZ, err)
		}
		assertBiomeHeightV1Column(t, generator, generated, biomeID, worldX, worldZ, localX, localZ)
	}
}

func findBiomeSampleCoordinate(t *testing.T, generator WorldGenerator, biomeID BiomeID) (int64, int64) {
	t.Helper()

	for worldX := int64(-512); worldX <= 512; worldX += 16 {
		for worldZ := int64(-512); worldZ <= 512; worldZ += 16 {
			if got := generator.SampleBiome(worldX, worldZ).ID; got == biomeID {
				return worldX, worldZ
			}
		}
	}
	t.Fatalf("no sample coordinate found for biome %q", biomeID)
	return 0, 0
}

func assertBiomeHeightV1Column(t *testing.T, generator WorldGenerator, chunk *Chunk, biomeID BiomeID, worldX, worldZ int64, localX, localZ int) {
	t.Helper()

	sample := generator.SampleBiome(worldX, worldZ)
	if sample.ID != biomeID {
		t.Fatalf("SampleBiome(%d,%d) = %q, want %q", worldX, worldZ, sample.ID, biomeID)
	}
	surfaceY := generator.heightV1SurfaceY(worldX, worldZ)
	surfaceBlock, subsurfaceBlock := biomeHeightV1ColumnBlocks(biomeID)
	if got := chunk.GetBlock(localX, surfaceY, localZ); got != surfaceBlock {
		t.Fatalf("biome_height_v1 %s surface block at (%d,%d,%d) = %v, want %v", biomeID, localX, surfaceY, localZ, got, surfaceBlock)
	}
	if got := chunk.GetBlock(localX, surfaceY-1, localZ); got != subsurfaceBlock {
		t.Fatalf("biome_height_v1 %s subsurface block at (%d,%d,%d) = %v, want %v", biomeID, localX, surfaceY-1, localZ, got, subsurfaceBlock)
	}
	if got := chunk.GetBlock(localX, surfaceY-3, localZ); got != Stone {
		t.Fatalf("biome_height_v1 %s base block at (%d,%d,%d) = %v, want Stone", biomeID, localX, surfaceY-3, localZ, got)
	}
	if got := chunk.GetBlock(localX, surfaceY+1, localZ); got != Air {
		t.Fatalf("biome_height_v1 %s air block at (%d,%d,%d) = %v, want Air", biomeID, localX, surfaceY+1, localZ, got)
	}
}

func assertCaveHeightV1CarvesUndergroundOpenSamples(t *testing.T, generator WorldGenerator, chunk *Chunk, wantCarved int) {
	t.Helper()

	carved := 0
	foundSolid := false
	for localX := 0; localX < ChunkWidth; localX++ {
		for localZ := 0; localZ < ChunkDepth; localZ++ {
			worldX := int64(chunk.X)*int64(ChunkWidth) + int64(localX)
			worldZ := int64(chunk.Z)*int64(ChunkDepth) + int64(localZ)
			surfaceY := generator.heightV1SurfaceY(worldX, worldZ)
			if got := chunk.GetBlock(localX, surfaceY, localZ); got != Grass {
				t.Fatalf("cave_height_v1 surface block at (%d,%d,%d) = %v, want Grass", localX, surfaceY, localZ, got)
			}
			if got := chunk.GetBlock(localX, surfaceY-1, localZ); got != Dirt {
				t.Fatalf("cave_height_v1 subsurface block at (%d,%d,%d) = %v, want Dirt", localX, surfaceY-1, localZ, got)
			}

			for y := caveV1MinY; y <= surfaceY-3 && y <= caveV1MaxY; y++ {
				sample := generator.SampleCave(worldX, y, worldZ)
				got := chunk.GetBlock(localX, y, localZ)
				if sample.ID == CaveOpen {
					if got != Air {
						t.Fatalf("cave_height_v1 open sample at (%d,%d,%d) = %v, want Air", localX, y, localZ, got)
					}
					carved++
				} else if !foundSolid {
					if got != Stone {
						t.Fatalf("cave_height_v1 solid sample at (%d,%d,%d) = %v, want Stone", localX, y, localZ, got)
					}
					foundSolid = true
				}
			}
		}
	}
	if carved != wantCarved {
		t.Fatalf("cave_height_v1 carved blocks = %d, want %d", carved, wantCarved)
	}
	if !foundSolid {
		t.Fatal("cave_height_v1 representative chunk did not include a guarded solid cave sample")
	}
}

func assertBiomeCaveHeightV1Columns(t *testing.T, generator WorldGenerator) {
	t.Helper()

	for _, biomeID := range []BiomeID{BiomePlains, BiomeForest, BiomeDryHighlands, BiomeSnowfields} {
		worldX, worldZ := findBiomeSampleCoordinate(t, generator, biomeID)
		chunkX, localX := GlobalToChunkLocal(int32(worldX), ChunkWidth)
		chunkZ, localZ := GlobalToChunkLocal(int32(worldZ), ChunkDepth)
		generated, err := generator.GenerateChunk(chunkX, chunkZ)
		if err != nil {
			t.Fatalf("GenerateChunk(%d,%d) error = %v", chunkX, chunkZ, err)
		}
		assertBiomeCaveHeightV1Column(t, generator, generated, biomeID, worldX, worldZ, localX, localZ)
	}
}

func assertBiomeCaveHeightV1Column(t *testing.T, generator WorldGenerator, chunk *Chunk, biomeID BiomeID, worldX, worldZ int64, localX, localZ int) {
	t.Helper()

	sample := generator.SampleBiome(worldX, worldZ)
	if sample.ID != biomeID {
		t.Fatalf("SampleBiome(%d,%d) = %q, want %q", worldX, worldZ, sample.ID, biomeID)
	}
	surfaceY := generator.heightV1SurfaceY(worldX, worldZ)
	surfaceBlock, subsurfaceBlock := biomeHeightV1ColumnBlocks(biomeID)
	if got := chunk.GetBlock(localX, surfaceY, localZ); got != surfaceBlock {
		t.Fatalf("biome_cave_height_v1 %s surface block at (%d,%d,%d) = %v, want %v", biomeID, localX, surfaceY, localZ, got, surfaceBlock)
	}
	if got := chunk.GetBlock(localX, surfaceY-1, localZ); got != subsurfaceBlock {
		t.Fatalf("biome_cave_height_v1 %s subsurface block at (%d,%d,%d) = %v, want %v", biomeID, localX, surfaceY-1, localZ, got, subsurfaceBlock)
	}
	if got := chunk.GetBlock(localX, surfaceY-2, localZ); got != subsurfaceBlock {
		t.Fatalf("biome_cave_height_v1 %s second subsurface block at (%d,%d,%d) = %v, want %v", biomeID, localX, surfaceY-2, localZ, got, subsurfaceBlock)
	}
	if got := chunk.GetBlock(localX, surfaceY+1, localZ); got != Air {
		t.Fatalf("biome_cave_height_v1 %s air block at (%d,%d,%d) = %v, want Air", biomeID, localX, surfaceY+1, localZ, got)
	}
}

func assertBiomeCaveHeightV1CombinesBiomeBlocksAndCaves(t *testing.T, generator WorldGenerator, chunk *Chunk, wantCarved, wantBiomeSurfaceChanged int) {
	t.Helper()

	caveConfig := generator.Config()
	caveConfig.Version = GeneratorVersionCaveHeightV1
	caveGenerator, err := NewWorldGenerator(caveConfig)
	if err != nil {
		t.Fatalf("NewWorldGenerator(cave_height_v1) error = %v", err)
	}
	caveChunk, err := caveGenerator.GenerateChunk(chunk.X, chunk.Z)
	if err != nil {
		t.Fatalf("GenerateChunk(cave_height_v1) error = %v", err)
	}

	carved := 0
	biomeSurfaceChanged := 0
	foundSolid := false
	for localX := 0; localX < ChunkWidth; localX++ {
		for localZ := 0; localZ < ChunkDepth; localZ++ {
			worldX := int64(chunk.X)*int64(ChunkWidth) + int64(localX)
			worldZ := int64(chunk.Z)*int64(ChunkDepth) + int64(localZ)
			surfaceY := generator.heightV1SurfaceY(worldX, worldZ)
			surfaceBlock, subsurfaceBlock := biomeHeightV1ColumnBlocks(generator.SampleBiome(worldX, worldZ).ID)
			if got := chunk.GetBlock(localX, surfaceY, localZ); got != surfaceBlock {
				t.Fatalf("biome_cave_height_v1 surface block at (%d,%d,%d) = %v, want %v", localX, surfaceY, localZ, got, surfaceBlock)
			}
			if got := chunk.GetBlock(localX, surfaceY-1, localZ); got != subsurfaceBlock {
				t.Fatalf("biome_cave_height_v1 subsurface block at (%d,%d,%d) = %v, want %v", localX, surfaceY-1, localZ, got, subsurfaceBlock)
			}
			if caveChunk.GetBlock(localX, surfaceY, localZ) != surfaceBlock {
				biomeSurfaceChanged++
			}

			for y := caveV1MinY; y <= surfaceY-3 && y <= caveV1MaxY; y++ {
				sample := generator.SampleCave(worldX, y, worldZ)
				got := chunk.GetBlock(localX, y, localZ)
				if sample.ID == CaveOpen {
					if got != Air {
						t.Fatalf("biome_cave_height_v1 open sample at (%d,%d,%d) = %v, want Air", localX, y, localZ, got)
					}
					carved++
				} else if !foundSolid {
					if got != Stone {
						t.Fatalf("biome_cave_height_v1 solid sample at (%d,%d,%d) = %v, want Stone", localX, y, localZ, got)
					}
					foundSolid = true
				}
			}
		}
	}
	if carved != wantCarved {
		t.Fatalf("biome_cave_height_v1 carved blocks = %d, want %d", carved, wantCarved)
	}
	if biomeSurfaceChanged != wantBiomeSurfaceChanged {
		t.Fatalf("biome_cave_height_v1 biome surface changes = %d, want %d", biomeSurfaceChanged, wantBiomeSurfaceChanged)
	}
	if !foundSolid {
		t.Fatal("biome_cave_height_v1 representative chunk did not include a guarded solid cave sample")
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
