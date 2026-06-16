package world

import "fmt"

type GeneratorVersion string

const (
	GeneratorVersionFlatV1   GeneratorVersion = "flat_v1"
	GeneratorVersionHeightV1 GeneratorVersion = "height_v1"

	DefaultWorldSeed   int64  = 0
	DefaultDimensionID string = "overworld"

	heightV1BaseSurfaceY = 64
	heightV1MinSurfaceY  = 48
	heightV1MaxSurfaceY  = 80
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
	case GeneratorVersionHeightV1:
		chunk := NewChunk(x, z)
		g.generateHeightV1(chunk)
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
	case GeneratorVersionFlatV1, GeneratorVersionHeightV1:
		return nil
	default:
		return fmt.Errorf("unsupported world generator version %q", config.Version)
	}
}

func (g WorldGenerator) generateHeightV1(chunk *Chunk) {
	for localX := 0; localX < ChunkWidth; localX++ {
		for localZ := 0; localZ < ChunkDepth; localZ++ {
			worldX := int64(chunk.X)*int64(ChunkWidth) + int64(localX)
			worldZ := int64(chunk.Z)*int64(ChunkDepth) + int64(localZ)
			surfaceY := g.heightV1SurfaceY(worldX, worldZ)

			for y := 0; y <= surfaceY; y++ {
				switch {
				case y == surfaceY:
					chunk.SetBlock(localX, y, localZ, Grass)
				case y >= surfaceY-2:
					chunk.SetBlock(localX, y, localZ, Dirt)
				default:
					chunk.SetBlock(localX, y, localZ, Stone)
				}
			}
		}
	}
}

func (g WorldGenerator) heightV1SurfaceY(worldX, worldZ int64) int {
	config := g.Config()
	low := heightV1SmoothNoise(config, worldX, worldZ, 32, 0x9e3779b97f4a7c15)
	mid := heightV1SmoothNoise(config, worldX, worldZ, 16, 0xbf58476d1ce4e5b9)
	high := heightV1SmoothNoise(config, worldX, worldZ, 8, 0x94d049bb133111eb)

	heightOffset := (low*12 + mid*6 + high*3) / 128
	return clampInt(heightV1BaseSurfaceY+heightOffset, heightV1MinSurfaceY, heightV1MaxSurfaceY)
}

func heightV1SmoothNoise(config GeneratorConfig, worldX, worldZ int64, cellSize int64, salt uint64) int {
	gridX, localX := floorDivMod(worldX, cellSize)
	gridZ, localZ := floorDivMod(worldZ, cellSize)

	n00 := heightV1LatticeNoise(config, gridX, gridZ, salt)
	n10 := heightV1LatticeNoise(config, gridX+1, gridZ, salt)
	n01 := heightV1LatticeNoise(config, gridX, gridZ+1, salt)
	n11 := heightV1LatticeNoise(config, gridX+1, gridZ+1, salt)

	invX := cellSize - localX
	invZ := cellSize - localZ
	weighted := n00*invX*invZ +
		n10*localX*invZ +
		n01*invX*localZ +
		n11*localX*localZ

	return int(weighted/(cellSize*cellSize)) - 128
}

func heightV1LatticeNoise(config GeneratorConfig, gridX, gridZ int64, salt uint64) int64 {
	h := uint64(config.Seed) ^ salt
	h = mixHeightV1Hash(h ^ uint64(gridX))
	h = mixHeightV1Hash(h ^ uint64(gridZ))
	for i := 0; i < len(config.DimensionID); i++ {
		h = mixHeightV1Hash(h ^ uint64(config.DimensionID[i]))
	}
	return int64(h & 0xff)
}

func mixHeightV1Hash(v uint64) uint64 {
	v += 0x9e3779b97f4a7c15
	v = (v ^ (v >> 30)) * 0xbf58476d1ce4e5b9
	v = (v ^ (v >> 27)) * 0x94d049bb133111eb
	return v ^ (v >> 31)
}

func floorDivMod(value, divisor int64) (int64, int64) {
	quotient := value / divisor
	remainder := value % divisor
	if remainder < 0 {
		quotient--
		remainder += divisor
	}
	return quotient, remainder
}

func clampInt(value, min, max int) int {
	if value < min {
		return min
	}
	if value > max {
		return max
	}
	return value
}
