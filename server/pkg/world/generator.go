package world

import "fmt"

type GeneratorVersion string

const (
	GeneratorVersionFlatV1 GeneratorVersion = "flat_v1"

	DefaultWorldSeed   int64  = 0
	DefaultDimensionID string = "overworld"
)

type GeneratorConfig struct {
	Seed        int64
	DimensionID string
	Version     GeneratorVersion
}

type WorldGenerator struct {
	config GeneratorConfig
}

func DefaultGeneratorConfig() GeneratorConfig {
	return GeneratorConfig{
		Seed:        DefaultWorldSeed,
		DimensionID: DefaultDimensionID,
		Version:     GeneratorVersionFlatV1,
	}
}

func NewWorldGenerator(config GeneratorConfig) (WorldGenerator, error) {
	config = normalizeGeneratorConfig(config)
	if err := validateGeneratorConfig(config); err != nil {
		return WorldGenerator{}, err
	}
	return WorldGenerator{config: config}, nil
}

func DefaultWorldGenerator() WorldGenerator {
	return WorldGenerator{config: DefaultGeneratorConfig()}
}

func (g WorldGenerator) Config() GeneratorConfig {
	return normalizeGeneratorConfig(g.config)
}

func (g WorldGenerator) GenerateChunk(x, z int32) (*Chunk, error) {
	config := g.Config()
	if err := validateGeneratorConfig(config); err != nil {
		return nil, err
	}

	switch config.Version {
	case GeneratorVersionFlatV1:
		chunk := NewChunk(x, z)
		chunk.GenerateFlat()
		return chunk, nil
	default:
		return nil, fmt.Errorf("unsupported world generator version %q", config.Version)
	}
}

func normalizeGeneratorConfig(config GeneratorConfig) GeneratorConfig {
	if config.DimensionID == "" {
		config.DimensionID = DefaultDimensionID
	}
	if config.Version == "" {
		config.Version = GeneratorVersionFlatV1
	}
	return config
}

func validateGeneratorConfig(config GeneratorConfig) error {
	if config.DimensionID == "" {
		return fmt.Errorf("world generator dimension id must not be empty")
	}
	switch config.Version {
	case GeneratorVersionFlatV1:
		return nil
	default:
		return fmt.Errorf("unsupported world generator version %q", config.Version)
	}
}
