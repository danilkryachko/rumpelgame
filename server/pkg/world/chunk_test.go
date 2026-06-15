package world

import (
	"bytes"
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

func TestNewChunkInitializesCoordinatesAndAirBlocks(t *testing.T) {
	chunk := NewChunk(-2, 7)

	if chunk.X != -2 || chunk.Z != 7 {
		t.Fatalf("chunk coordinates = (%d, %d), want (-2, 7)", chunk.X, chunk.Z)
	}
	if got, want := len(chunk.Blocks), ChunkWidth*ChunkHeight*ChunkDepth; got != want {
		t.Fatalf("len(chunk.Blocks) = %d, want %d", got, want)
	}
	if got := chunk.GetBlock(0, 0, 0); got != Air {
		t.Fatalf("new chunk block = %v, want Air", got)
	}
	if got := chunk.GetBlock(ChunkWidth-1, ChunkHeight-1, ChunkDepth-1); got != Air {
		t.Fatalf("new chunk edge block = %v, want Air", got)
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

func TestGenerateFlatProducesExpectedStrata(t *testing.T) {
	chunk := NewChunk(0, 0)
	chunk.GenerateFlat()

	assertFlatStrata(t, chunk)
}

func TestGenerateFlatIsDeterministicForChunkCoordinates(t *testing.T) {
	tests := []struct {
		name string
		x    int32
		z    int32
	}{
		{name: "origin", x: 0, z: 0},
		{name: "negative x", x: -1, z: 0},
		{name: "negative z", x: 0, z: -1},
		{name: "negative x and z", x: -4, z: -9},
		{name: "mixed signs", x: -4, z: 9},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			first := NewChunk(tt.x, tt.z)
			second := NewChunk(tt.x, tt.z)

			first.GenerateFlat()
			second.GenerateFlat()

			if first.X != tt.x || first.Z != tt.z {
				t.Fatalf("first chunk coordinates = (%d, %d), want (%d, %d)", first.X, first.Z, tt.x, tt.z)
			}
			if second.X != tt.x || second.Z != tt.z {
				t.Fatalf("second chunk coordinates = (%d, %d), want (%d, %d)", second.X, second.Z, tt.x, tt.z)
			}
			if got, want := first.Serialize(), second.Serialize(); !bytes.Equal(got, want) {
				t.Fatal("GenerateFlat serialized output differs for identical chunk coordinates")
			}

			assertFlatStrata(t, first)
		})
	}
}

func assertFlatStrata(t *testing.T, chunk *Chunk) {
	t.Helper()

	for _, pos := range [][2]int{{0, 0}, {ChunkWidth - 1, ChunkDepth - 1}, {13, 21}} {
		x, z := pos[0], pos[1]
		if got := chunk.GetBlock(x, 0, z); got != Stone {
			t.Fatalf("block at (%d, 0, %d) = %v, want Stone", x, z, got)
		}
		if got := chunk.GetBlock(x, 60, z); got != Stone {
			t.Fatalf("block at (%d, 60, %d) = %v, want Stone", x, z, got)
		}
		if got := chunk.GetBlock(x, 61, z); got != Dirt {
			t.Fatalf("block at (%d, 61, %d) = %v, want Dirt", x, z, got)
		}
		if got := chunk.GetBlock(x, 63, z); got != Grass {
			t.Fatalf("block at (%d, 63, %d) = %v, want Grass", x, z, got)
		}
		if got := chunk.GetBlock(x, 64, z); got != Air {
			t.Fatalf("block at (%d, 64, %d) = %v, want Air", x, z, got)
		}
	}
}

func TestSerializeUsesLittleEndianBlockIDs(t *testing.T) {
	chunk := NewChunk(0, 0)
	chunk.SetBlock(0, 0, 0, Leaves)
	chunk.SetBlock(1, 0, 0, Dirt)
	chunk.SetBlock(0, 0, 1, Grass)
	chunk.SetBlock(0, 1, 0, BlockID(0x1234))

	data := chunk.Serialize()
	if got, want := len(data), ChunkWidth*ChunkHeight*ChunkDepth*2; got != want {
		t.Fatalf("Serialize() length = %d, want %d", got, want)
	}

	if got := BlockID(binary.LittleEndian.Uint16(data[:2])); got != Leaves {
		t.Fatalf("first serialized block = %v, want %v", got, Leaves)
	}

	assertSerializedBlock := func(t *testing.T, x, y, z int, want BlockID) {
		t.Helper()
		index := x + y*ChunkWidth*ChunkDepth + z*ChunkWidth
		offset := index * 2
		if got := BlockID(binary.LittleEndian.Uint16(data[offset:])); got != want {
			t.Fatalf("serialized block at (%d, %d, %d) = %v, want %v", x, y, z, got, want)
		}
	}

	assertSerializedBlock(t, 0, 0, 0, Leaves)
	assertSerializedBlock(t, 1, 0, 0, Dirt)
	assertSerializedBlock(t, 0, 0, 1, Grass)
	assertSerializedBlock(t, 0, 1, 0, BlockID(0x1234))

	chunk.SetBlock(0, 0, 0, Air)
	if got := BlockID(binary.LittleEndian.Uint16(data[:2])); got != Leaves {
		t.Fatalf("serialized buffer changed after chunk mutation: %v, want %v", got, Leaves)
	}
}

func TestDeserializeChunkRoundTripPreservesCoordinatesAndBlocks(t *testing.T) {
	chunk := NewChunk(-8, 11)
	chunk.SetBlock(0, 0, 0, Stone)
	chunk.SetBlock(ChunkWidth-1, ChunkHeight-1, ChunkDepth-1, Leaves)
	chunk.SetBlock(7, 63, 9, BlockID(0x1234))

	roundTrip, err := DeserializeChunk(chunk.X, chunk.Z, chunk.Serialize())
	if err != nil {
		t.Fatalf("DeserializeChunk() error = %v", err)
	}

	if roundTrip.X != chunk.X || roundTrip.Z != chunk.Z {
		t.Fatalf("round-trip coordinates = (%d, %d), want (%d, %d)", roundTrip.X, roundTrip.Z, chunk.X, chunk.Z)
	}
	for _, pos := range [][4]int{
		{0, 0, 0, int(Stone)},
		{ChunkWidth - 1, ChunkHeight - 1, ChunkDepth - 1, int(Leaves)},
		{7, 63, 9, 0x1234},
	} {
		if got := roundTrip.GetBlock(pos[0], pos[1], pos[2]); got != BlockID(pos[3]) {
			t.Fatalf("round-trip block at (%d, %d, %d) = %v, want %v", pos[0], pos[1], pos[2], got, BlockID(pos[3]))
		}
	}
}
