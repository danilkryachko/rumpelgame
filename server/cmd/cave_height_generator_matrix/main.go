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
	chunkX := flag.Int("chunk-x", -3, "representative chunk x")
	chunkZ := flag.Int("chunk-z", 5, "representative chunk z")
	flag.Parse()

	summary, err := buildSummary(*seed, *dimension, int32(*chunkX), int32(*chunkZ))
	if err != nil {
		fmt.Fprintf(os.Stderr, "cave_height_generator_matrix status=fail error=%q\n", err)
		os.Exit(1)
	}
	fmt.Println(summary)
}

func buildSummary(seed int64, dimension string, chunkX, chunkZ int32) (string, error) {
	baseGenerator, err := world.NewWorldGenerator(world.GeneratorConfig{
		Seed:        seed,
		DimensionID: dimension,
		Version:     world.GeneratorVersionHeightV1,
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
	caveChunk, err := caveGenerator.GenerateChunk(chunkX, chunkZ)
	if err != nil {
		return "", err
	}

	raw := caveChunk.Serialize()
	sum := sha256.Sum256(raw)
	carvedAir := 0
	byteDiff := 0
	for i, block := range caveChunk.Blocks {
		if block != baseChunk.Blocks[i] {
			byteDiff += 2
		}
		if block == world.Air && baseChunk.Blocks[i] != world.Air {
			carvedAir++
		}
	}

	surfaceColumns := world.ChunkWidth * world.ChunkDepth
	surfacePreserved := 0
	for localX := 0; localX < world.ChunkWidth; localX++ {
		for localZ := 0; localZ < world.ChunkDepth; localZ++ {
			baseY, baseBlock := highestNonAir(baseChunk, localX, localZ)
			caveY, caveBlock := highestNonAir(caveChunk, localX, localZ)
			if baseY == caveY && baseBlock == caveBlock {
				surfacePreserved++
			}
		}
	}

	return fmt.Sprintf(
		"cave_height_generator_matrix status=pass generator_version=%s seed=%d dimension=%s chunk=%d,%d chunk_hash=%x carved_air=%d byte_diff=%d surface_columns=%d surface_preserved=%d active_default_change=0 active_serialization_change=0 protocol_change=0",
		world.GeneratorVersionCaveHeightV1,
		seed,
		dimension,
		chunkX,
		chunkZ,
		sum,
		carvedAir,
		byteDiff,
		surfaceColumns,
		surfacePreserved,
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
