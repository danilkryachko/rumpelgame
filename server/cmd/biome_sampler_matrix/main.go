package main

import (
	"crypto/sha256"
	"flag"
	"fmt"
	"os"
	"strings"

	"rumpelmc/server/pkg/world"
)

var matrixCoords = [][2]int64{
	{-128, -128},
	{-64, -64},
	{-1, -1},
	{0, 0},
	{63, 63},
	{64, 0},
	{127, 127},
	{1024, -1024},
	{4096, -4097},
}

func main() {
	seed := flag.Int64("seed", 8675309, "world generator seed")
	dimension := flag.String("dimension", world.DefaultDimensionID, "world generator dimension id")
	generatorVersion := flag.String("generator-version", string(world.GeneratorVersionHeightV1), "world generator version")
	flag.Parse()

	summary, err := buildSummary(*seed, *dimension, world.GeneratorVersion(*generatorVersion))
	if err != nil {
		fmt.Fprintf(os.Stderr, "biome_sampler_matrix status=fail error=%q\n", err)
		os.Exit(1)
	}
	fmt.Println(summary)
}

func buildSummary(seed int64, dimension string, generatorVersion world.GeneratorVersion) (string, error) {
	generator, err := world.NewWorldGenerator(world.GeneratorConfig{
		Seed:        seed,
		DimensionID: dimension,
		Version:     generatorVersion,
	})
	if err != nil {
		return "", err
	}

	counts := map[world.BiomeID]int{
		world.BiomePlains:       0,
		world.BiomeForest:       0,
		world.BiomeDryHighlands: 0,
		world.BiomeSnowfields:   0,
	}
	var signature strings.Builder
	for _, coord := range matrixCoords {
		sample := generator.SampleBiome(coord[0], coord[1])
		counts[sample.ID]++
		fmt.Fprintf(&signature, "%d,%d=%s\n", coord[0], coord[1], sample.ID)
	}
	sum := sha256.Sum256([]byte(signature.String()))

	return fmt.Sprintf(
		"biome_sampler_matrix status=pass algorithm_version=%s seed=%d dimension=%s generator_version=%s samples=%d plains=%d forest=%d dry_highlands=%d snowfields=%d sample_hash=%x active_worldgen_change=0 active_serialization_change=0 protocol_change=0",
		world.BiomeAlgorithmVersionV1,
		seed,
		dimension,
		generatorVersion,
		len(matrixCoords),
		counts[world.BiomePlains],
		counts[world.BiomeForest],
		counts[world.BiomeDryHighlands],
		counts[world.BiomeSnowfields],
		sum,
	), nil
}
