package api

import (
	"testing"

	"google.golang.org/protobuf/reflect/protoreflect"
)

func TestPacketPayloadFieldNumbersAreStable(t *testing.T) {
	packet := (&Packet{}).ProtoReflect().Descriptor()

	assertFieldNumber(t, packet, "chunk", 1)
	assertFieldNumber(t, packet, "position", 2)
	assertFieldNumber(t, packet, "block_action", 3)
}

func TestChunkDataFieldNumbersAreStable(t *testing.T) {
	chunkData := (&ChunkData{}).ProtoReflect().Descriptor()

	assertFieldNumber(t, chunkData, "x", 1)
	assertFieldNumber(t, chunkData, "z", 2)
	assertFieldNumber(t, chunkData, "blocks", 3)
	assertFieldNumber(t, chunkData, "encoding", 4)
	assertFieldNumber(t, chunkData, "uncompressed_size", 5)
}

func TestChunkEncodingWireValuesAreStable(t *testing.T) {
	encoding := ChunkEncoding_CHUNK_ENCODING_RAW.Descriptor()

	assertEnumNumber(t, encoding, "CHUNK_ENCODING_RAW", 0)
	assertEnumNumber(t, encoding, "CHUNK_ENCODING_RLE", 1)
}

func assertFieldNumber(t *testing.T, message protoreflect.MessageDescriptor, name protoreflect.Name, want protoreflect.FieldNumber) {
	t.Helper()

	field := message.Fields().ByName(name)
	if field == nil {
		t.Fatalf("%s.%s field missing", message.FullName(), name)
	}
	if got := field.Number(); got != want {
		t.Fatalf("%s.%s field number = %d, want %d", message.FullName(), name, got, want)
	}
}

func assertEnumNumber(t *testing.T, enum protoreflect.EnumDescriptor, name protoreflect.Name, want protoreflect.EnumNumber) {
	t.Helper()

	value := enum.Values().ByName(name)
	if value == nil {
		t.Fatalf("%s.%s enum value missing", enum.FullName(), name)
	}
	if got := value.Number(); got != want {
		t.Fatalf("%s.%s enum number = %d, want %d", enum.FullName(), name, got, want)
	}
}
