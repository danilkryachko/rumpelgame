package network

import (
	"encoding/binary"
	"io"
	"net"
	"strings"
	"testing"
	"time"

	"google.golang.org/protobuf/proto"
	"rumpelmc/server/pkg/api"
	"rumpelmc/server/pkg/world"
)

func TestSendPacketWritesLengthPrefixedProtobuf(t *testing.T) {
	serverConn, clientConn := net.Pipe()
	defer serverConn.Close()
	defer clientConn.Close()

	packet := &api.Packet{
		Payload: &api.Packet_BlockAction{
			BlockAction: &api.BlockAction{
				Action:  api.BlockAction_PLACE,
				X:       1,
				Y:       2,
				Z:       3,
				BlockId: 4,
			},
		},
	}

	errCh := make(chan error, 1)
	go func() {
		errCh <- NewServer(":0", world.NewWorld(nil)).sendPacket(serverConn, packet)
	}()

	dataBuf := readFrame(t, clientConn)

	if err := <-errCh; err != nil {
		t.Fatalf("send packet: %v", err)
	}

	decoded := &api.Packet{}
	if err := proto.Unmarshal(dataBuf, decoded); err != nil {
		t.Fatalf("unmarshal payload: %v", err)
	}
	if !proto.Equal(decoded, packet) {
		t.Fatalf("decoded packet mismatch:\n got: %v\nwant: %v", decoded, packet)
	}
}

func TestReceivePacketReturnsOnShortFrame(t *testing.T) {
	serverConn, clientConn := net.Pipe()
	defer serverConn.Close()

	resultCh := receivePacketAsync(serverConn)
	if _, err := clientConn.Write([]byte{0x02, 0x00}); err != nil {
		t.Fatalf("write short frame: %v", err)
	}
	if err := clientConn.Close(); err != nil {
		t.Fatalf("close client connection: %v", err)
	}

	result := waitReceivePacket(t, resultCh)
	if result.err == nil {
		t.Fatal("receivePacket() error = nil, want short frame error")
	}
}

func TestReceivePacketRejectsOversizedLength(t *testing.T) {
	serverConn, clientConn := net.Pipe()
	defer serverConn.Close()
	defer clientConn.Close()

	resultCh := receivePacketAsync(serverConn)
	lenBuf := make([]byte, 4)
	binary.LittleEndian.PutUint32(lenBuf, uint32(maxPacketSize+1))
	if _, err := clientConn.Write(lenBuf); err != nil {
		t.Fatalf("write oversized length: %v", err)
	}

	result := waitReceivePacket(t, resultCh)
	if result.err == nil || !strings.Contains(result.err.Error(), "packet too large") {
		t.Fatalf("receivePacket() error = %v, want packet too large", result.err)
	}
}

func TestReceivePacketRejectsMalformedPayload(t *testing.T) {
	serverConn, clientConn := net.Pipe()
	defer serverConn.Close()
	defer clientConn.Close()

	resultCh := receivePacketAsync(serverConn)
	writeFrame(t, clientConn, []byte{0xff})
	result := waitReceivePacket(t, resultCh)
	if result.err == nil {
		t.Fatal("receivePacket() error = nil, want malformed protobuf error")
	}
}

type receivePacketResult struct {
	packet *api.Packet
	err    error
}

func receivePacketAsync(conn net.Conn) <-chan receivePacketResult {
	resultCh := make(chan receivePacketResult, 1)
	go func() {
		packet, err := NewServer(":0", world.NewWorld(nil)).receivePacket(conn)
		resultCh <- receivePacketResult{packet: packet, err: err}
	}()
	return resultCh
}

func waitReceivePacket(t *testing.T, resultCh <-chan receivePacketResult) receivePacketResult {
	t.Helper()

	select {
	case result := <-resultCh:
		return result
	case <-time.After(time.Second):
		t.Fatal("receivePacket() did not return")
		return receivePacketResult{}
	}
}

func readFrame(t *testing.T, conn net.Conn) []byte {
	t.Helper()

	lenBuf := make([]byte, 4)
	if _, err := io.ReadFull(conn, lenBuf); err != nil {
		t.Fatalf("read frame length: %v", err)
	}

	data := make([]byte, binary.LittleEndian.Uint32(lenBuf))
	if _, err := io.ReadFull(conn, data); err != nil {
		t.Fatalf("read frame payload: %v", err)
	}
	return data
}

func writeFrame(t *testing.T, conn net.Conn, data []byte) {
	t.Helper()

	lenBuf := make([]byte, 4)
	binary.LittleEndian.PutUint32(lenBuf, uint32(len(data)))
	if _, err := conn.Write(lenBuf); err != nil {
		t.Fatalf("write frame length: %v", err)
	}
	if _, err := conn.Write(data); err != nil {
		t.Fatalf("write frame payload: %v", err)
	}
}
