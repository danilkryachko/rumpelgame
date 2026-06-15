package world

import (
	"encoding/binary"
	"fmt"
)

const (
	ChunkWidth  = 32
	ChunkDepth  = 32
	ChunkHeight = 512
)

type Chunk struct {
	X      int32
	Z      int32
	Blocks []BlockID
}

type ChunkCoord struct {
	X int32
	Z int32
}

type ChunkSnapshot struct {
	X      int32
	Z      int32
	Blocks []byte
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

func (c *Chunk) Serialize() []byte {
	buf := make([]byte, len(c.Blocks)*2)
	for i, b := range c.Blocks {
		binary.LittleEndian.PutUint16(buf[i*2:], uint16(b))
	}
	return buf
}

func DeserializeChunk(x, z int32, data []byte) (*Chunk, error) {
	expected := ChunkWidth * ChunkHeight * ChunkDepth * 2
	if len(data) != expected {
		return nil, fmt.Errorf("chunk data length = %d, want %d", len(data), expected)
	}

	chunk := NewChunk(x, z)
	for i := range chunk.Blocks {
		chunk.Blocks[i] = BlockID(binary.LittleEndian.Uint16(data[i*2:]))
	}
	return chunk, nil
}
