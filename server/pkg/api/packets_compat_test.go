package api

import (
	"bytes"
	"testing"

	"google.golang.org/protobuf/proto"
)

func TestPacketWireCompatibility(t *testing.T) {
	tests := []struct {
		name     string
		packet   *Packet
		expected []byte
	}{
		{
			name: "chunk payload tag 1",
			packet: &Packet{
				Payload: &Packet_Chunk{
					Chunk: &ChunkData{
						X:      1,
						Z:      2,
						Blocks: []byte{0xaa, 0x55},
					},
				},
			},
			expected: []byte{
				0x0a, 0x08,
				0x08, 0x01,
				0x10, 0x02,
				0x1a, 0x02, 0xaa, 0x55,
			},
		},
		{
			name: "position payload tag 2",
			packet: &Packet{
				Payload: &Packet_Position{
					Position: &ClientPosition{
						X: 1.5,
						Y: -2.25,
						Z: 0.5,
					},
				},
			},
			expected: []byte{
				0x12, 0x0f,
				0x0d, 0x00, 0x00, 0xc0, 0x3f,
				0x15, 0x00, 0x00, 0x10, 0xc0,
				0x1d, 0x00, 0x00, 0x00, 0x3f,
			},
		},
		{
			name: "block action payload tag 3",
			packet: &Packet{
				Payload: &Packet_BlockAction{
					BlockAction: &BlockAction{
						Action:  BlockAction_PLACE,
						X:       10,
						Y:       20,
						Z:       30,
						BlockId: 4,
					},
				},
			},
			expected: []byte{
				0x1a, 0x0a,
				0x08, 0x01,
				0x10, 0x0a,
				0x18, 0x14,
				0x20, 0x1e,
				0x28, 0x04,
			},
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			data, err := proto.Marshal(tc.packet)
			if err != nil {
				t.Fatalf("marshal packet: %v", err)
			}
			if !bytes.Equal(data, tc.expected) {
				t.Fatalf("wire bytes changed:\n got: % x\nwant: % x", data, tc.expected)
			}

			decoded := &Packet{}
			if err := proto.Unmarshal(tc.expected, decoded); err != nil {
				t.Fatalf("unmarshal expected bytes: %v", err)
			}
			if !proto.Equal(decoded, tc.packet) {
				t.Fatalf("decoded packet mismatch:\n got: %v\nwant: %v", decoded, tc.packet)
			}
		})
	}
}
