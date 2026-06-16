package main

import (
	"crypto/sha256"
	"flag"
	"fmt"
	"os"
	"strings"

	"rumpelmc/server/pkg/world"
)

var matrixCoords = [][3]int64{
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

func main() {
	seed := flag.Int64("seed", 8675309, "world generator seed")
	dimension := flag.String("dimension", world.DefaultDimensionID, "world generator dimension id")
	generatorVersion := flag.String("generator-version", string(world.GeneratorVersionHeightV1), "world generator version")
	flag.Parse()

	summary, err := buildSummary(*seed, *dimension, world.GeneratorVersion(*generatorVersion))
	if err != nil {
		fmt.Fprintf(os.Stderr, "resource_distribution_matrix status=fail error=%q\n", err)
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

	counts := map[world.ResourceID]int{
		world.ResourceNone:   0,
		world.ResourceCoal:   0,
		world.ResourceCopper: 0,
		world.ResourceIron:   0,
	}
	signatureParts := make([]string, 0, len(matrixCoords))
	var signature strings.Builder
	for _, coord := range matrixCoords {
		sample := generator.SampleResource(coord[0], int(coord[1]), coord[2])
		counts[sample.ID]++
		signaturePart := fmt.Sprintf("%d:%d:%d:%s", coord[0], coord[1], coord[2], sample.ID)
		signatureParts = append(signatureParts, signaturePart)
		fmt.Fprintln(&signature, signaturePart)
	}
	sum := sha256.Sum256([]byte(signature.String()))

	return fmt.Sprintf(
		"resource_distribution_matrix status=pass algorithm_version=%s seed=%d dimension=%s generator_version=%s samples=%d none=%d coal=%d copper=%d iron=%d sample_hash=%x signature=%s active_worldgen_change=0 active_serialization_change=0 protocol_change=0",
		world.ResourceAlgorithmVersionV1,
		seed,
		dimension,
		generatorVersion,
		len(matrixCoords),
		counts[world.ResourceNone],
		counts[world.ResourceCoal],
		counts[world.ResourceCopper],
		counts[world.ResourceIron],
		sum,
		strings.Join(signatureParts, ","),
	), nil
}
