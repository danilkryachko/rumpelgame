package network

import (
	"bytes"
	"encoding/binary"
	"testing"

	"google.golang.org/protobuf/encoding/protowire"
	"google.golang.org/protobuf/proto"
	"rumpelmc/server/pkg/api"
	"rumpelmc/server/pkg/world"
)

func TestChunkDataRawPayloadDefaultsRemainBackwardCompatible(t *testing.T) {
	raw := make([]byte, world.SerializedChunkSize)
	binary.LittleEndian.PutUint16(raw, uint16(world.Stone))

	packet := &api.Packet{
		Payload: &api.Packet_Chunk{
			Chunk: &api.ChunkData{
				X:      -2,
				Z:      7,
				Blocks: raw,
			},
		},
	}

	data, err := proto.Marshal(packet)
	if err != nil {
		t.Fatalf("marshal old raw packet: %v", err)
	}
	var decoded api.Packet
	if err := proto.Unmarshal(data, &decoded); err != nil {
		t.Fatalf("unmarshal old raw packet: %v", err)
	}

	chunk := decoded.GetChunk()
	if chunk == nil {
		t.Fatal("decoded chunk = nil")
	}
	if chunk.GetEncoding() != api.ChunkEncoding_CHUNK_ENCODING_RAW {
		t.Fatalf("default encoding = %v, want RAW", chunk.GetEncoding())
	}
	if chunk.GetUncompressedSize() != 0 {
		t.Fatalf("default uncompressed_size = %d, want 0", chunk.GetUncompressedSize())
	}
	if chunk.GetX() != -2 || chunk.GetZ() != 7 {
		t.Fatalf("chunk coordinates = (%d, %d), want (-2, 7)", chunk.GetX(), chunk.GetZ())
	}
	if !bytes.Equal(chunk.GetBlocks(), raw) {
		t.Fatal("raw chunk bytes changed across protobuf round-trip")
	}
}

func TestChunkDataUnknownFieldsSurviveGoRoundTrip(t *testing.T) {
	unknown := protowire.AppendTag(nil, 99, protowire.VarintType)
	unknown = protowire.AppendVarint(unknown, 12345)

	chunk := &api.ChunkData{
		X:                1,
		Z:                2,
		Blocks:           []byte{0x01, 0x00, 0x02},
		Encoding:         api.ChunkEncoding_CHUNK_ENCODING_RLE,
		UncompressedSize: uint32(world.SerializedChunkSize),
	}
	chunk.ProtoReflect().SetUnknown(unknown)
	packet := &api.Packet{Payload: &api.Packet_Chunk{Chunk: chunk}}

	data, err := proto.Marshal(packet)
	if err != nil {
		t.Fatalf("marshal packet with unknown chunk field: %v", err)
	}
	var decoded api.Packet
	if err := proto.Unmarshal(data, &decoded); err != nil {
		t.Fatalf("unmarshal packet with unknown chunk field: %v", err)
	}
	if got := decoded.GetChunk().ProtoReflect().GetUnknown(); !bytes.Equal(got, unknown) {
		t.Fatalf("unknown chunk fields after unmarshal = %v, want %v", got, unknown)
	}

	roundTrip, err := proto.Marshal(&decoded)
	if err != nil {
		t.Fatalf("remarshal packet with unknown chunk field: %v", err)
	}
	var decodedAgain api.Packet
	if err := proto.Unmarshal(roundTrip, &decodedAgain); err != nil {
		t.Fatalf("unmarshal remarshal packet with unknown chunk field: %v", err)
	}
	if got := decodedAgain.GetChunk().ProtoReflect().GetUnknown(); !bytes.Equal(got, unknown) {
		t.Fatalf("unknown chunk fields after remarshal = %v, want %v", got, unknown)
	}
}
