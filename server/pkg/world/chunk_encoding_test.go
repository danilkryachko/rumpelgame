package world

import (
	"bytes"
	"encoding/binary"
	"testing"
)

func TestEncodeSerializedChunkRLERoundTripsFlatChunk(t *testing.T) {
	chunk := NewChunk(0, 0)
	chunk.GenerateFlat()
	raw := chunk.Serialize()

	encoded, err := EncodeSerializedChunkRLE(raw)
	if err != nil {
		t.Fatalf("EncodeSerializedChunkRLE() error = %v", err)
	}
	if len(encoded) >= 64 {
		t.Fatalf("encoded flat chunk length = %d, want less than 64", len(encoded))
	}

	decoded, err := DecodeSerializedChunkRLE(encoded)
	if err != nil {
		t.Fatalf("DecodeSerializedChunkRLE() error = %v", err)
	}
	if !bytes.Equal(decoded, raw) {
		t.Fatal("decoded chunk differs from raw chunk")
	}
}

func TestEncodeSerializedChunkRLEPreservesEditedChunk(t *testing.T) {
	chunk := NewChunk(-3, 5)
	chunk.GenerateFlat()
	chunk.SetBlock(2, 70, 3, Wood)
	chunk.SetBlock(3, 70, 3, Leaves)
	chunk.SetBlock(4, 70, 3, BlockID(0x1234))
	raw := chunk.Serialize()

	encoded, err := EncodeSerializedChunkRLE(raw)
	if err != nil {
		t.Fatalf("EncodeSerializedChunkRLE() error = %v", err)
	}
	decoded, err := DecodeSerializedChunkRLE(encoded)
	if err != nil {
		t.Fatalf("DecodeSerializedChunkRLE() error = %v", err)
	}

	roundTrip, err := DeserializeChunk(chunk.X, chunk.Z, decoded)
	if err != nil {
		t.Fatalf("DeserializeChunk() error = %v", err)
	}
	for _, pos := range [][4]int{
		{2, 70, 3, int(Wood)},
		{3, 70, 3, int(Leaves)},
		{4, 70, 3, 0x1234},
	} {
		if got := roundTrip.GetBlock(pos[0], pos[1], pos[2]); got != BlockID(pos[3]) {
			t.Fatalf("round-trip block at %d,%d,%d = %v, want %v", pos[0], pos[1], pos[2], got, BlockID(pos[3]))
		}
	}
}

func TestEncodeSerializedChunkRLEUsesStableWireVector(t *testing.T) {
	raw := make([]byte, SerializedChunkSize)
	writeSerializedBlock(raw, 0, Stone)
	writeSerializedBlock(raw, 1, Stone)
	writeSerializedBlock(raw, 2, Dirt)
	writeSerializedBlock(raw, 3, Grass)
	writeSerializedBlock(raw, 4, Grass)

	encoded, err := EncodeSerializedChunkRLE(raw)
	if err != nil {
		t.Fatalf("EncodeSerializedChunkRLE() error = %v", err)
	}

	expected := appendExpectedBlockRun(nil, Stone, 2)
	expected = appendExpectedBlockRun(expected, Dirt, 1)
	expected = appendExpectedBlockRun(expected, Grass, 2)
	expected = appendExpectedBlockRun(expected, Air, uint64(SerializedChunkSize/2-5))
	if !bytes.Equal(encoded, expected) {
		t.Fatalf("encoded RLE vector mismatch:\n got: %v\nwant: %v", encoded, expected)
	}

	decoded, err := DecodeSerializedChunkRLE(encoded)
	if err != nil {
		t.Fatalf("DecodeSerializedChunkRLE() error = %v", err)
	}
	if !bytes.Equal(decoded, raw) {
		t.Fatal("decoded stable wire vector differs from raw chunk")
	}
}

func TestEncodeSerializedChunkRLERejectsWrongLength(t *testing.T) {
	if _, err := EncodeSerializedChunkRLE(make([]byte, SerializedChunkSize-2)); err == nil {
		t.Fatal("EncodeSerializedChunkRLE() error = nil, want wrong length error")
	}
}

func TestDecodeSerializedChunkRLERejectsMalformedRuns(t *testing.T) {
	tests := []struct {
		name    string
		encoded []byte
	}{
		{name: "truncated block id", encoded: []byte{0x01}},
		{name: "missing run length", encoded: []byte{0x01, 0x00}},
		{name: "zero run length", encoded: []byte{0x01, 0x00, 0x00}},
		{name: "overflow run length", encoded: singleRun(Air, uint64(SerializedChunkSize/2+1))},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			if _, err := DecodeSerializedChunkRLE(tc.encoded); err == nil {
				t.Fatal("DecodeSerializedChunkRLE() error = nil, want malformed run error")
			}
		})
	}
}

func singleRun(block BlockID, runLength uint64) []byte {
	var runBuf [binary.MaxVarintLen64]byte
	encoded := binary.LittleEndian.AppendUint16(nil, uint16(block))
	n := binary.PutUvarint(runBuf[:], runLength)
	return append(encoded, runBuf[:n]...)
}

func writeSerializedBlock(raw []byte, blockIndex int, block BlockID) {
	binary.LittleEndian.PutUint16(raw[blockIndex*2:], uint16(block))
}

func appendExpectedBlockRun(dst []byte, block BlockID, runLength uint64) []byte {
	var runBuf [binary.MaxVarintLen64]byte
	dst = binary.LittleEndian.AppendUint16(dst, uint16(block))
	n := binary.PutUvarint(runBuf[:], runLength)
	return append(dst, runBuf[:n]...)
}
