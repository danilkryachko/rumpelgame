package world

import (
	"encoding/binary"
	"testing"
)

func TestSetAndGetBlock(t *testing.T) {
	chunk := NewChunk(0, 0)

	chunk.SetBlock(1, 2, 3, Wood)

	if got := chunk.GetBlock(1, 2, 3); got != Wood {
		t.Fatalf("GetBlock() = %v, want %v", got, Wood)
	}
}

func TestOutOfBoundsBlocksAreIgnored(t *testing.T) {
	chunk := NewChunk(0, 0)

	chunk.SetBlock(-1, 0, 0, Stone)
	chunk.SetBlock(0, -1, 0, Stone)
	chunk.SetBlock(0, 0, -1, Stone)
	chunk.SetBlock(ChunkWidth, 0, 0, Stone)
	chunk.SetBlock(0, ChunkHeight, 0, Stone)
	chunk.SetBlock(0, 0, ChunkDepth, Stone)

	if got := chunk.GetBlock(-1, 0, 0); got != Air {
		t.Fatalf("GetBlock() out of bounds = %v, want %v", got, Air)
	}
	if got := chunk.GetBlock(0, 0, 0); got != Air {
		t.Fatalf("in-bounds block was changed to %v, want %v", got, Air)
	}
}

func TestSerializeUsesLittleEndianBlockIDs(t *testing.T) {
	chunk := NewChunk(0, 0)
	chunk.SetBlock(0, 0, 0, Leaves)

	data := chunk.Serialize()
	if got, want := len(data), ChunkWidth*ChunkHeight*ChunkDepth*2; got != want {
		t.Fatalf("Serialize() length = %d, want %d", got, want)
	}

	if got := BlockID(binary.LittleEndian.Uint16(data[:2])); got != Leaves {
		t.Fatalf("first serialized block = %v, want %v", got, Leaves)
	}
}
