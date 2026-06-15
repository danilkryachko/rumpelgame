package world

import "testing"

func BenchmarkChunkSerializeFlat(b *testing.B) {
	chunk := NewChunk(0, 0)
	chunk.GenerateFlat()

	b.ReportAllocs()
	b.SetBytes(SerializedChunkSize)
	for i := 0; i < b.N; i++ {
		_ = chunk.Serialize()
	}
}

func BenchmarkEncodeSerializedChunkRLEFlat(b *testing.B) {
	chunk := NewChunk(0, 0)
	chunk.GenerateFlat()
	raw := chunk.Serialize()

	b.ReportAllocs()
	b.SetBytes(int64(len(raw)))
	for i := 0; i < b.N; i++ {
		encoded, err := EncodeSerializedChunkRLE(raw)
		if err != nil {
			b.Fatal(err)
		}
		_ = encoded
	}
}

func BenchmarkDecodeSerializedChunkRLEFlat(b *testing.B) {
	chunk := NewChunk(0, 0)
	chunk.GenerateFlat()
	raw := chunk.Serialize()
	encoded, err := EncodeSerializedChunkRLE(raw)
	if err != nil {
		b.Fatal(err)
	}

	b.ReportAllocs()
	b.SetBytes(int64(len(raw)))
	for i := 0; i < b.N; i++ {
		decoded, err := DecodeSerializedChunkRLE(encoded)
		if err != nil {
			b.Fatal(err)
		}
		_ = decoded
	}
}
