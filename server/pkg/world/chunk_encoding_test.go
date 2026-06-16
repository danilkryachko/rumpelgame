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

func TestEncodeSerializedChunkRLERoundTripsHeightV1Chunk(t *testing.T) {
	generator, err := NewWorldGenerator(GeneratorConfig{
		Seed:        8675309,
		DimensionID: "overworld",
		Version:     GeneratorVersionHeightV1,
	})
	if err != nil {
		t.Fatalf("NewWorldGenerator() error = %v", err)
	}
	chunk, err := generator.GenerateChunk(-3, 5)
	if err != nil {
		t.Fatalf("GenerateChunk(height_v1) error = %v", err)
	}
	raw := chunk.Serialize()

	encoded, err := EncodeSerializedChunkRLE(raw)
	if err != nil {
		t.Fatalf("EncodeSerializedChunkRLE(height_v1) error = %v", err)
	}
	if len(encoded) <= 64 {
		t.Fatalf("encoded height_v1 chunk length = %d, want richer run evidence than flat chunk", len(encoded))
	}
	if len(encoded) >= len(raw) {
		t.Fatalf("encoded height_v1 chunk length = %d, want less than raw %d", len(encoded), len(raw))
	}

	decoded, err := DecodeSerializedChunkRLE(encoded)
	if err != nil {
		t.Fatalf("DecodeSerializedChunkRLE(height_v1) error = %v", err)
	}
	if !bytes.Equal(decoded, raw) {
		t.Fatal("decoded height_v1 chunk differs from raw chunk")
	}

	roundTrip, err := DeserializeChunk(chunk.X, chunk.Z, decoded)
	if err != nil {
		t.Fatalf("DeserializeChunk(height_v1 round trip) error = %v", err)
	}
	assertHeightV1SurfaceVaries(t, generator, roundTrip)
}

func TestEncodeSerializedChunkRLERoundTripsBiomeHeightV1Chunk(t *testing.T) {
	generator, err := NewWorldGenerator(GeneratorConfig{
		Seed:        8675309,
		DimensionID: "overworld",
		Version:     GeneratorVersionBiomeHeightV1,
	})
	if err != nil {
		t.Fatalf("NewWorldGenerator() error = %v", err)
	}
	chunk, err := generator.GenerateChunk(0, 0)
	if err != nil {
		t.Fatalf("GenerateChunk(biome_height_v1) error = %v", err)
	}
	raw := chunk.Serialize()

	encoded, err := EncodeSerializedChunkRLE(raw)
	if err != nil {
		t.Fatalf("EncodeSerializedChunkRLE(biome_height_v1) error = %v", err)
	}
	if len(encoded) <= 64 {
		t.Fatalf("encoded biome_height_v1 chunk length = %d, want richer run evidence than flat chunk", len(encoded))
	}
	if len(encoded) >= len(raw) {
		t.Fatalf("encoded biome_height_v1 chunk length = %d, want less than raw %d", len(encoded), len(raw))
	}

	decoded, err := DecodeSerializedChunkRLE(encoded)
	if err != nil {
		t.Fatalf("DecodeSerializedChunkRLE(biome_height_v1) error = %v", err)
	}
	if !bytes.Equal(decoded, raw) {
		t.Fatal("decoded biome_height_v1 chunk differs from raw chunk")
	}

	roundTrip, err := DeserializeChunk(chunk.X, chunk.Z, decoded)
	if err != nil {
		t.Fatalf("DeserializeChunk(biome_height_v1 round trip) error = %v", err)
	}
	assertHeightV1SurfaceVaries(t, generator, roundTrip)
	assertBiomeHeightV1Column(t, generator, roundTrip, BiomeSnowfields, 0, 0, 0, 0)
}

func TestEncodeSerializedChunkRLERoundTripsCaveHeightV1Chunk(t *testing.T) {
	generator, err := NewWorldGenerator(GeneratorConfig{
		Seed:        8675309,
		DimensionID: "overworld",
		Version:     GeneratorVersionCaveHeightV1,
	})
	if err != nil {
		t.Fatalf("NewWorldGenerator() error = %v", err)
	}
	chunk, err := generator.GenerateChunk(-3, 5)
	if err != nil {
		t.Fatalf("GenerateChunk(cave_height_v1) error = %v", err)
	}
	raw := chunk.Serialize()

	encoded, err := EncodeSerializedChunkRLE(raw)
	if err != nil {
		t.Fatalf("EncodeSerializedChunkRLE(cave_height_v1) error = %v", err)
	}
	if len(encoded) <= 64 {
		t.Fatalf("encoded cave_height_v1 chunk length = %d, want richer run evidence than flat chunk", len(encoded))
	}
	if len(encoded) >= len(raw) {
		t.Fatalf("encoded cave_height_v1 chunk length = %d, want less than raw %d", len(encoded), len(raw))
	}

	decoded, err := DecodeSerializedChunkRLE(encoded)
	if err != nil {
		t.Fatalf("DecodeSerializedChunkRLE(cave_height_v1) error = %v", err)
	}
	if !bytes.Equal(decoded, raw) {
		t.Fatal("decoded cave_height_v1 chunk differs from raw chunk")
	}

	roundTrip, err := DeserializeChunk(chunk.X, chunk.Z, decoded)
	if err != nil {
		t.Fatalf("DeserializeChunk(cave_height_v1 round trip) error = %v", err)
	}
	assertHeightV1SurfaceVaries(t, generator, roundTrip)
	assertCaveHeightV1CarvesUndergroundOpenSamples(t, generator, roundTrip, 34728)
}

func TestEncodeSerializedChunkRLERoundTripsBiomeCaveHeightV1Chunk(t *testing.T) {
	generator, err := NewWorldGenerator(GeneratorConfig{
		Seed:        8675309,
		DimensionID: "overworld",
		Version:     GeneratorVersionBiomeCaveHeightV1,
	})
	if err != nil {
		t.Fatalf("NewWorldGenerator() error = %v", err)
	}
	chunk, err := generator.GenerateChunk(0, 0)
	if err != nil {
		t.Fatalf("GenerateChunk(biome_cave_height_v1) error = %v", err)
	}
	raw := chunk.Serialize()

	encoded, err := EncodeSerializedChunkRLE(raw)
	if err != nil {
		t.Fatalf("EncodeSerializedChunkRLE(biome_cave_height_v1) error = %v", err)
	}
	if len(encoded) <= 64 {
		t.Fatalf("encoded biome_cave_height_v1 chunk length = %d, want richer run evidence than flat chunk", len(encoded))
	}
	if len(encoded) >= len(raw) {
		t.Fatalf("encoded biome_cave_height_v1 chunk length = %d, want less than raw %d", len(encoded), len(raw))
	}

	decoded, err := DecodeSerializedChunkRLE(encoded)
	if err != nil {
		t.Fatalf("DecodeSerializedChunkRLE(biome_cave_height_v1) error = %v", err)
	}
	if !bytes.Equal(decoded, raw) {
		t.Fatal("decoded biome_cave_height_v1 chunk differs from raw chunk")
	}

	roundTrip, err := DeserializeChunk(chunk.X, chunk.Z, decoded)
	if err != nil {
		t.Fatalf("DeserializeChunk(biome_cave_height_v1 round trip) error = %v", err)
	}
	assertHeightV1SurfaceVaries(t, generator, roundTrip)
	assertBiomeCaveHeightV1CombinesBiomeBlocksAndCaves(t, generator, roundTrip, 28152, 1024)
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

func TestEncodeSerializedChunkRLERoundTripsRepresentativeRunPatterns(t *testing.T) {
	blockCount := SerializedChunkSize / 2
	manyShortRuns := make([]testBlockRun, 0, 257)
	for i := 0; i < 256; i++ {
		manyShortRuns = append(manyShortRuns, testBlockRun{
			block:     BlockID(0x20 + i%7),
			runLength: 1,
		})
	}
	manyShortRuns = append(manyShortRuns, testBlockRun{
		block:     Air,
		runLength: uint64(blockCount - 256),
	})

	tests := []struct {
		name string
		runs []testBlockRun
	}{
		{
			name: "varint boundaries",
			runs: []testBlockRun{
				{block: Stone, runLength: 1},
				{block: Dirt, runLength: 126},
				{block: Grass, runLength: 127},
				{block: Wood, runLength: 128},
				{block: Leaves, runLength: 255},
				{block: BlockID(0x1234), runLength: uint64(blockCount - 637)},
			},
		},
		{
			name: "many short runs",
			runs: manyShortRuns,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			raw := serializedChunkFromRuns(t, tc.runs)
			encoded, err := EncodeSerializedChunkRLE(raw)
			if err != nil {
				t.Fatalf("EncodeSerializedChunkRLE() error = %v", err)
			}
			decoded, err := DecodeSerializedChunkRLE(encoded)
			if err != nil {
				t.Fatalf("DecodeSerializedChunkRLE() error = %v", err)
			}
			if !bytes.Equal(decoded, raw) {
				t.Fatal("decoded representative run pattern differs from raw chunk")
			}
		})
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
		{name: "overflowing varint", encoded: append([]byte{0x01, 0x00}, bytes.Repeat([]byte{0x80}, binary.MaxVarintLen64+1)...)},
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

type testBlockRun struct {
	block     BlockID
	runLength uint64
}

func serializedChunkFromRuns(t *testing.T, runs []testBlockRun) []byte {
	t.Helper()

	raw := make([]byte, 0, SerializedChunkSize)
	var total uint64
	for _, run := range runs {
		if run.runLength == 0 {
			t.Fatalf("zero run in test fixture for block %v", run.block)
		}
		total += run.runLength
		for i := uint64(0); i < run.runLength; i++ {
			raw = binary.LittleEndian.AppendUint16(raw, uint16(run.block))
		}
	}
	if len(raw) != SerializedChunkSize {
		t.Fatalf("serialized fixture has %d bytes from %d blocks, want %d bytes", len(raw), total, SerializedChunkSize)
	}
	return raw
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
