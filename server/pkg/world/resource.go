package world

type ResourceID string

const (
	ResourceAlgorithmVersionV1 = "resource_v1"

	ResourceNone   ResourceID = "none"
	ResourceCoal   ResourceID = "coal"
	ResourceCopper ResourceID = "copper"
	ResourceIron   ResourceID = "iron"
)

type ResourceDefinition struct {
	ID          ResourceID
	DisplayName string
	MinY        int
	MaxY        int
	Rarity      uint64
}

type ResourceSample struct {
	ID               ResourceID
	AlgorithmVersion string
}

var resourceDefinitionsV1 = []ResourceDefinition{
	{ID: ResourceIron, DisplayName: "Iron", MinY: 4, MaxY: 64, Rarity: 3},
	{ID: ResourceCopper, DisplayName: "Copper", MinY: 16, MaxY: 88, Rarity: 4},
	{ID: ResourceCoal, DisplayName: "Coal", MinY: 8, MaxY: 96, Rarity: 2},
}

func ResourceDefinitionsV1() []ResourceDefinition {
	definitions := make([]ResourceDefinition, len(resourceDefinitionsV1))
	copy(definitions, resourceDefinitionsV1)
	return definitions
}

func (g WorldGenerator) SampleResource(worldX int64, worldY int, worldZ int64) ResourceSample {
	return sampleResourceV1(g.Config(), worldX, worldY, worldZ)
}

func DeterministicResourceID(config GeneratorConfig, worldX int64, worldY int, worldZ int64) ResourceID {
	return sampleResourceV1(config, worldX, worldY, worldZ).ID
}

func sampleResourceV1(config GeneratorConfig, worldX int64, worldY int, worldZ int64) ResourceSample {
	config = normalizeGeneratorConfig(config)
	if worldY < 0 || worldY >= ChunkHeight {
		return ResourceSample{ID: ResourceNone, AlgorithmVersion: ResourceAlgorithmVersionV1}
	}

	for _, definition := range resourceDefinitionsV1 {
		if worldY < definition.MinY || worldY > definition.MaxY {
			continue
		}
		if resourceV1Hash(config, definition.ID, worldX, worldY, worldZ)%definition.Rarity == 0 {
			return ResourceSample{ID: definition.ID, AlgorithmVersion: ResourceAlgorithmVersionV1}
		}
	}

	return ResourceSample{ID: ResourceNone, AlgorithmVersion: ResourceAlgorithmVersionV1}
}

func resourceV1Hash(config GeneratorConfig, resourceID ResourceID, worldX int64, worldY int, worldZ int64) uint64 {
	h := uint64(config.Seed) ^ 0x7f4a7c152d358dcc
	h = mixResourceV1Hash(h ^ uint64(worldX) ^ 0x9e3779b97f4a7c15)
	h = mixResourceV1Hash(h ^ uint64(int64(worldY)) ^ 0xd6e8feb86659fd93)
	h = mixResourceV1Hash(h ^ uint64(worldZ) ^ 0xbf58476d1ce4e5b9)
	for i := 0; i < len(config.DimensionID); i++ {
		h = mixResourceV1Hash(h ^ uint64(config.DimensionID[i]))
	}
	for i := 0; i < len(resourceID); i++ {
		h = mixResourceV1Hash(h ^ uint64(resourceID[i]))
	}
	return h
}

func mixResourceV1Hash(v uint64) uint64 {
	v += 0x9e3779b97f4a7c15
	v = (v ^ (v >> 30)) * 0xbf58476d1ce4e5b9
	v = (v ^ (v >> 27)) * 0x94d049bb133111eb
	return v ^ (v >> 31)
}
