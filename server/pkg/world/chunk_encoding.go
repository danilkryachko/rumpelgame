package world

import (
	"encoding/binary"
	"fmt"
)

const SerializedChunkSize = ChunkWidth * ChunkHeight * ChunkDepth * 2

func EncodeSerializedChunkRLE(raw []byte) ([]byte, error) {
	if len(raw) != SerializedChunkSize {
		return nil, fmt.Errorf("serialized chunk length = %d, want %d", len(raw), SerializedChunkSize)
	}
	if len(raw) == 0 {
		return nil, nil
	}

	encoded := make([]byte, 0, 64)
	current := binary.LittleEndian.Uint16(raw[:2])
	runLength := uint64(1)
	var runBuf [binary.MaxVarintLen64]byte

	for offset := 2; offset < len(raw); offset += 2 {
		blockID := binary.LittleEndian.Uint16(raw[offset:])
		if blockID == current {
			runLength++
			continue
		}

		encoded = appendBlockRun(encoded, current, runLength, runBuf[:])
		current = blockID
		runLength = 1
	}

	encoded = appendBlockRun(encoded, current, runLength, runBuf[:])
	return encoded, nil
}

func DecodeSerializedChunkRLE(encoded []byte) ([]byte, error) {
	raw := make([]byte, 0, SerializedChunkSize)
	for offset := 0; offset < len(encoded); {
		if len(encoded)-offset < 3 {
			return nil, fmt.Errorf("truncated block run at byte %d", offset)
		}

		blockID := binary.LittleEndian.Uint16(encoded[offset:])
		offset += 2

		runLength, consumed := binary.Uvarint(encoded[offset:])
		if consumed <= 0 {
			return nil, fmt.Errorf("invalid block run length at byte %d", offset)
		}
		if runLength == 0 {
			return nil, fmt.Errorf("zero block run length at byte %d", offset)
		}
		offset += consumed

		runBytes := runLength * 2
		if runBytes > uint64(SerializedChunkSize-len(raw)) {
			return nil, fmt.Errorf("decoded chunk length exceeds %d bytes", SerializedChunkSize)
		}

		for i := uint64(0); i < runLength; i++ {
			raw = binary.LittleEndian.AppendUint16(raw, blockID)
		}
	}

	if len(raw) != SerializedChunkSize {
		return nil, fmt.Errorf("decoded chunk length = %d, want %d", len(raw), SerializedChunkSize)
	}
	return raw, nil
}

func appendBlockRun(dst []byte, blockID uint16, runLength uint64, runBuf []byte) []byte {
	dst = binary.LittleEndian.AppendUint16(dst, blockID)
	n := binary.PutUvarint(runBuf, runLength)
	return append(dst, runBuf[:n]...)
}
