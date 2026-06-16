package world

type BiomeID string

const (
	BiomeAlgorithmVersionV1 = "biome_v1"

	BiomePlains       BiomeID = "plains"
	BiomeForest       BiomeID = "forest"
	BiomeDryHighlands BiomeID = "dry_highlands"
	BiomeSnowfields   BiomeID = "snowfields"

	biomeV1CellSize = int64(64)
)

type BiomeDefinition struct {
	ID          BiomeID
	DisplayName string
	SurfaceTint uint32
}

type BiomeSample struct {
	ID               BiomeID
	AlgorithmVersion string
}

var biomeDefinitionsV1 = []BiomeDefinition{
	{ID: BiomePlains, DisplayName: "Plains", SurfaceTint: 0x78b957},
	{ID: BiomeForest, DisplayName: "Forest", SurfaceTint: 0x3f8f3f},
	{ID: BiomeDryHighlands, DisplayName: "Dry Highlands", SurfaceTint: 0xb89b4f},
	{ID: BiomeSnowfields, DisplayName: "Snowfields", SurfaceTint: 0xc8d7d2},
}

func BiomeDefinitionsV1() []BiomeDefinition {
	definitions := make([]BiomeDefinition, len(biomeDefinitionsV1))
	copy(definitions, biomeDefinitionsV1)
	return definitions
}

func (g WorldGenerator) SampleBiome(worldX, worldZ int64) BiomeSample {
	return sampleBiomeV1(g.Config(), worldX, worldZ)
}

func DeterministicBiomeID(config GeneratorConfig, worldX, worldZ int64) BiomeID {
	return sampleBiomeV1(config, worldX, worldZ).ID
}

func sampleBiomeV1(config GeneratorConfig, worldX, worldZ int64) BiomeSample {
	config = normalizeGeneratorConfig(config)
	gridX, _ := floorDivMod(worldX, biomeV1CellSize)
	gridZ, _ := floorDivMod(worldZ, biomeV1CellSize)
	return BiomeSample{
		ID:               biomeIDFromV1Hash(biomeV1Hash(config, gridX, gridZ)),
		AlgorithmVersion: BiomeAlgorithmVersionV1,
	}
}

func biomeIDFromV1Hash(hash uint64) BiomeID {
	switch hash % 16 {
	case 0, 1, 2, 3, 4, 5, 6:
		return BiomePlains
	case 7, 8, 9, 10:
		return BiomeForest
	case 11, 12, 13:
		return BiomeDryHighlands
	default:
		return BiomeSnowfields
	}
}

func biomeV1Hash(config GeneratorConfig, gridX, gridZ int64) uint64 {
	h := uint64(config.Seed) ^ 0x2d358dccaa6c78a5
	h = mixBiomeV1Hash(h ^ uint64(gridX) ^ 0x9e3779b97f4a7c15)
	h = mixBiomeV1Hash(h ^ uint64(gridZ) ^ 0xbf58476d1ce4e5b9)
	for i := 0; i < len(config.DimensionID); i++ {
		h = mixBiomeV1Hash(h ^ uint64(config.DimensionID[i]))
	}
	return h
}

func mixBiomeV1Hash(v uint64) uint64 {
	v += 0x9e3779b97f4a7c15
	v = (v ^ (v >> 30)) * 0xbf58476d1ce4e5b9
	v = (v ^ (v >> 27)) * 0x94d049bb133111eb
	return v ^ (v >> 31)
}
