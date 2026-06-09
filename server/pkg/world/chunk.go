package world

const (
	ChunkWidth  = 32
	ChunkDepth  = 32
	ChunkHeight = 512
)

type BlockID uint16

const (
	Air BlockID = iota
	Stone
	Dirt
	Grass
)

type Chunk struct {
	X      int32
	Z      int32
	Blocks []BlockID
}

func NewChunk(x, z int32) *Chunk {
	return &Chunk{
		X:      x,
		Z:      z,
		Blocks: make([]BlockID, ChunkWidth*ChunkHeight*ChunkDepth),
	}
}

func (c *Chunk) SetBlock(x, y, z int, block BlockID) {
	if x < 0 || x >= ChunkWidth || y < 0 || y >= ChunkHeight || z < 0 || z >= ChunkDepth {
		return
	}
	index := x + y*ChunkWidth*ChunkDepth + z*ChunkWidth
	c.Blocks[index] = block
}

func (c *Chunk) GetBlock(x, y, z int) BlockID {
	if x < 0 || x >= ChunkWidth || y < 0 || y >= ChunkHeight || z < 0 || z >= ChunkDepth {
		return Air
	}
	index := x + y*ChunkWidth*ChunkDepth + z*ChunkWidth
	return c.Blocks[index]
}

func (c *Chunk) GenerateFlat() {
	for x := 0; x < ChunkWidth; x++ {
		for z := 0; z < ChunkDepth; z++ {
			for y := 0; y < 64; y++ {
				if y == 63 {
					c.SetBlock(x, y, z, Grass)
				} else if y > 60 {
					c.SetBlock(x, y, z, Dirt)
				} else {
					c.SetBlock(x, y, z, Stone)
				}
			}
		}
	}
}
