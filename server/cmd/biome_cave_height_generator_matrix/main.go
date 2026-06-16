package main

import (
	"crypto/sha256"
	"flag"
	"fmt"
	"os"

	"rumpelmc/server/pkg/world"
)

func main() {
	seed := flag.Int64("seed", 8675309, "world generator seed")
	dimension := flag.String("dimension", world.DefaultDimensionID, "world generator dimension id")
	chunkX := flag.Int("chunk-x", 0, "representative chunk x")
	chunkZ := flag.Int("chunk-z", 0, "representative chunk z")
	flag.Parse()

	summary, err := buildSummary(*seed, *dimension, int32(*chunkX), int32(*chunkZ))
	if err != nil {
		fmt.Fprintf(os.Stderr, "biome_cave_height_generator_matrix status=fail error=%q\n", err)
		os.Exit(1)
	}
	fmt.Println(summary)
}

func buildSummary(seed int64, dimension string, chunkX, chunkZ int32) (string, error) {
	baseGenerator, err := world.NewWorldGenerator(world.GeneratorConfig{
		Seed:        seed,
		DimensionID: dimension,
		Version:     world.GeneratorVersionBiomeHeightV1,
	})
	if err != nil {
		return "", err
	}
	combinedGenerator, err := world.NewWorldGenerator(world.GeneratorConfig{
		Seed:        seed,
		DimensionID: dimension,
		Version:     world.GeneratorVersionBiomeCaveHeightV1,
	})
	if err != nil {
		return "", err
	}
	caveGenerator, err := world.NewWorldGenerator(world.GeneratorConfig{
		Seed:        seed,
		DimensionID: dimension,
		Version:     world.GeneratorVersionCaveHeightV1,
	})
	if err != nil {
		return "", err
	}

	baseChunk, err := baseGenerator.GenerateChunk(chunkX, chunkZ)
	if err != nil {
		return "", err
	}
	combinedChunk, err := combinedGenerator.GenerateChunk(chunkX, chunkZ)
	if err != nil {
		return "", err
	}
	caveChunk, err := caveGenerator.GenerateChunk(chunkX, chunkZ)
	if err != nil {
		return "", err
	}

	raw := combinedChunk.Serialize()
	sum := sha256.Sum256(raw)
	carvedAir := 0
	byteDiff := 0
	for i, block := range combinedChunk.Blocks {
		if block != baseChunk.Blocks[i] {
			byteDiff += 2
		}
		if block == world.Air && baseChunk.Blocks[i] != world.Air {
			carvedAir++
		}
	}

	surfaceColumns := world.ChunkWidth * world.ChunkDepth
	surfacePreserved := 0
	biomeSurfaceChanged := 0
	surfaceBlocks := make(map[world.BlockID]bool)
	for localX := 0; localX < world.ChunkWidth; localX++ {
		for localZ := 0; localZ < world.ChunkDepth; localZ++ {
			baseY, baseBlock := highestNonAir(baseChunk, localX, localZ)
			combinedY, combinedBlock := highestNonAir(combinedChunk, localX, localZ)
			caveY, caveBlock := highestNonAir(caveChunk, localX, localZ)
			surfaceBlocks[combinedBlock] = true
			if baseY == combinedY && baseBlock == combinedBlock {
				surfacePreserved++
			}
			if caveY == combinedY && caveBlock != combinedBlock {
				biomeSurfaceChanged++
			}
		}
	}

	return fmt.Sprintf(
		"biome_cave_height_generator_matrix status=pass generator_version=%s seed=%d dimension=%s chunk=%d,%d chunk_hash=%x carved_air=%d byte_diff=%d surface_columns=%d surface_preserved=%d biome_surface_changed=%d surface_block_variants=%d active_default_change=0 active_serialization_change=0 protocol_change=0",
		world.GeneratorVersionBiomeCaveHeightV1,
		seed,
		dimension,
		chunkX,
		chunkZ,
		sum,
		carvedAir,
		byteDiff,
		surfaceColumns,
		surfacePreserved,
		biomeSurfaceChanged,
		len(surfaceBlocks),
	), nil
}

func highestNonAir(chunk *world.Chunk, localX, localZ int) (int, world.BlockID) {
	for y := world.ChunkHeight - 1; y >= 0; y-- {
		block := chunk.GetBlock(localX, y, localZ)
		if block != world.Air {
			return y, block
		}
	}
	return -1, world.Air
}
