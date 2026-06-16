package world

type CaveID string

const (
	CaveAlgorithmVersionV1 = "cave_v1"

	CaveSolid CaveID = "solid"
	CaveOpen  CaveID = "open"

	caveV1MinY = 8
	caveV1MaxY = 112
)

type CaveDefinition struct {
	ID          CaveID
	DisplayName string
}

type CaveSample struct {
	ID               CaveID
	AlgorithmVersion string
	Density          uint8
}

var caveDefinitionsV1 = []CaveDefinition{
	{ID: CaveSolid, DisplayName: "Solid"},
	{ID: CaveOpen, DisplayName: "Open"},
}

func CaveDefinitionsV1() []CaveDefinition {
	definitions := make([]CaveDefinition, len(caveDefinitionsV1))
	copy(definitions, caveDefinitionsV1)
	return definitions
}

func (g WorldGenerator) SampleCave(worldX int64, worldY int, worldZ int64) CaveSample {
	return sampleCaveV1(g.Config(), worldX, worldY, worldZ)
}

func DeterministicCaveID(config GeneratorConfig, worldX int64, worldY int, worldZ int64) CaveID {
	return sampleCaveV1(config, worldX, worldY, worldZ).ID
}

func sampleCaveV1(config GeneratorConfig, worldX int64, worldY int, worldZ int64) CaveSample {
	config = normalizeGeneratorConfig(config)
	if worldY < caveV1MinY || worldY > caveV1MaxY || worldY >= ChunkHeight {
		return CaveSample{ID: CaveSolid, AlgorithmVersion: CaveAlgorithmVersionV1, Density: 255}
	}

	density := caveV1Density(config, worldX, worldY, worldZ)
	if density < caveV1OpenThreshold(worldY) {
		return CaveSample{ID: CaveOpen, AlgorithmVersion: CaveAlgorithmVersionV1, Density: density}
	}
	return CaveSample{ID: CaveSolid, AlgorithmVersion: CaveAlgorithmVersionV1, Density: density}
}

func caveV1OpenThreshold(worldY int) uint8 {
	switch {
	case worldY < 24:
		return 96
	case worldY > 88:
		return 96
	default:
		return 150
	}
}

func caveV1Density(config GeneratorConfig, worldX int64, worldY int, worldZ int64) uint8 {
	large := caveV1Hash(config, worldX/16, int64(worldY/12), worldZ/16, 0x4738a54d88f1a9c3)
	small := caveV1Hash(config, worldX/8, int64(worldY/8), worldZ/8, 0xb5ad4eceda1ce2a9)
	return uint8(((large & 0xff) + (small & 0xff)) / 2)
}

func caveV1Hash(config GeneratorConfig, gridX, gridY, gridZ int64, salt uint64) uint64 {
	h := uint64(config.Seed) ^ salt
	h = mixCaveV1Hash(h ^ uint64(gridX) ^ 0x9e3779b97f4a7c15)
	h = mixCaveV1Hash(h ^ uint64(gridY) ^ 0xd6e8feb86659fd93)
	h = mixCaveV1Hash(h ^ uint64(gridZ) ^ 0xbf58476d1ce4e5b9)
	for i := 0; i < len(config.DimensionID); i++ {
		h = mixCaveV1Hash(h ^ uint64(config.DimensionID[i]))
	}
	return h
}

func mixCaveV1Hash(v uint64) uint64 {
	v += 0x9e3779b97f4a7c15
	v = (v ^ (v >> 30)) * 0xbf58476d1ce4e5b9
	v = (v ^ (v >> 27)) * 0x94d049bb133111eb
	return v ^ (v >> 31)
}
