package network

import (
	"bytes"
	"encoding/binary"
	"errors"
	"fmt"
	"io"
	"log"
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
	if got := classifyNetworkError(result.err); got != networkErrorShortFrame {
		t.Fatalf("classifyNetworkError() = %s, want %s", got, networkErrorShortFrame)
	}
}

func TestReceivePacketReturnsOnShortPayload(t *testing.T) {
	serverConn, clientConn := net.Pipe()
	defer serverConn.Close()

	resultCh := receivePacketAsync(serverConn)
	lenBuf := make([]byte, 4)
	binary.LittleEndian.PutUint32(lenBuf, 4)
	if _, err := clientConn.Write(lenBuf); err != nil {
		t.Fatalf("write frame length: %v", err)
	}
	if _, err := clientConn.Write([]byte{0x01, 0x02}); err != nil {
		t.Fatalf("write short payload: %v", err)
	}
	if err := clientConn.Close(); err != nil {
		t.Fatalf("close client connection: %v", err)
	}

	result := waitReceivePacket(t, resultCh)
	if result.err == nil {
		t.Fatal("receivePacket() error = nil, want short payload error")
	}
	if got := classifyNetworkError(result.err); got != networkErrorShortFrame {
		t.Fatalf("classifyNetworkError() = %s, want %s", got, networkErrorShortFrame)
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
	if result.err == nil || !errors.Is(result.err, errPacketTooLarge) {
		t.Fatalf("receivePacket() error = %v, want packet too large", result.err)
	}
	if got := classifyNetworkError(result.err); got != networkErrorOversizedFrame {
		t.Fatalf("classifyNetworkError() = %s, want %s", got, networkErrorOversizedFrame)
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
	if got := classifyNetworkError(result.err); got != networkErrorMalformedProtobuf {
		t.Fatalf("classifyNetworkError() = %s, want %s", got, networkErrorMalformedProtobuf)
	}
}

func TestReceivePacketAcceptsEmptyPayloadFrame(t *testing.T) {
	serverConn, clientConn := net.Pipe()
	defer serverConn.Close()
	defer clientConn.Close()

	resultCh := receivePacketAsync(serverConn)
	writeFrame(t, clientConn, nil)

	result := waitReceivePacket(t, resultCh)
	if result.err != nil {
		t.Fatalf("receivePacket() error = %v, want nil for empty payload frame", result.err)
	}
	if result.packet == nil {
		t.Fatal("receivePacket() packet = nil, want empty packet")
	}
	if result.packet.Payload != nil {
		t.Fatalf("receivePacket() payload = %T, want nil", result.packet.Payload)
	}
}

func TestReceivePacketConsumesExactFrameBoundaries(t *testing.T) {
	serverConn, clientConn := net.Pipe()
	defer serverConn.Close()
	defer clientConn.Close()

	packets := []*api.Packet{
		{
			Payload: &api.Packet_Position{
				Position: &api.ClientPosition{X: 1, Y: 2, Z: 3},
			},
		},
		{
			Payload: &api.Packet_BlockAction{
				BlockAction: &api.BlockAction{
					Action:  api.BlockAction_PLACE,
					X:       4,
					Y:       5,
					Z:       6,
					BlockId: 7,
				},
			},
		},
	}

	writeErrCh := make(chan error, 1)
	go func() {
		for _, packet := range packets {
			data, err := proto.Marshal(packet)
			if err != nil {
				writeErrCh <- err
				return
			}
			if err := writeRawFrame(clientConn, data); err != nil {
				writeErrCh <- err
				return
			}
		}
		writeErrCh <- nil
	}()

	server := NewServer(":0", world.NewWorld(nil))
	for i, want := range packets {
		got, err := server.receivePacket(serverConn)
		if err != nil {
			t.Fatalf("receivePacket(frame %d) error = %v", i+1, err)
		}
		if !proto.Equal(got, want) {
			t.Fatalf("receivePacket(frame %d) mismatch:\n got: %v\nwant: %v", i+1, got, want)
		}
	}
	if err := <-writeErrCh; err != nil {
		t.Fatalf("write frames: %v", err)
	}
}

func TestReceiveInitialClientPacketIgnoresClosedProbe(t *testing.T) {
	serverConn, clientConn := net.Pipe()
	defer serverConn.Close()

	resultCh := receiveInitialClientPacketAsync(serverConn)
	if err := clientConn.Close(); err != nil {
		t.Fatalf("close probe connection: %v", err)
	}

	result := waitReceivePacket(t, resultCh)
	if result.err == nil {
		t.Fatal("receiveInitialClientPacket() error = nil, want closed probe error")
	}
	if result.packet != nil {
		t.Fatalf("receiveInitialClientPacket() packet = %v, want nil", result.packet)
	}
	if got := classifyNetworkError(result.err); got != networkErrorOther {
		t.Fatalf("classifyNetworkError() = %s, want %s", got, networkErrorOther)
	}
}

func TestReceiveInitialClientPacketTreatsTimeoutProbeAsNoPacket(t *testing.T) {
	serverConn, clientConn := net.Pipe()
	defer serverConn.Close()
	defer clientConn.Close()

	resultCh := receiveInitialClientPacketAsync(serverConn)
	result := waitReceivePacket(t, resultCh)
	if result.err != nil {
		t.Fatalf("receiveInitialClientPacket() error = %v, want nil timeout probe", result.err)
	}
	if result.packet != nil {
		t.Fatalf("receiveInitialClientPacket() packet = %v, want nil timeout probe", result.packet)
	}
}

func TestReceiveInitialClientPacketReadsHandshakePosition(t *testing.T) {
	serverConn, clientConn := net.Pipe()
	defer serverConn.Close()
	defer clientConn.Close()

	resultCh := receiveInitialClientPacketAsync(serverConn)
	packet := &api.Packet{
		Payload: &api.Packet_Position{
			Position: &api.ClientPosition{X: 16, Y: 68, Z: 16},
		},
	}
	go func() {
		if err := NewServer(":0", world.NewWorld(nil)).sendPacket(clientConn, packet); err != nil {
			t.Errorf("send handshake packet: %v", err)
		}
	}()

	result := waitReceivePacket(t, resultCh)
	if result.err != nil {
		t.Fatalf("receiveInitialClientPacket() error = %v", result.err)
	}
	if result.packet == nil || !proto.Equal(result.packet, packet) {
		t.Fatalf("receiveInitialClientPacket() packet = %v, want %v", result.packet, packet)
	}
}

func TestHandleConnectionLogsPacketErrorClassForMalformedInitialPacket(t *testing.T) {
	serverConn, clientConn := net.Pipe()
	defer clientConn.Close()

	var logs bytes.Buffer
	originalWriter := log.Writer()
	originalFlags := log.Flags()
	log.SetOutput(&logs)
	log.SetFlags(0)
	defer log.SetOutput(originalWriter)
	defer log.SetFlags(originalFlags)

	doneCh := make(chan struct{})
	go func() {
		NewServer(":0", world.NewWorld(nil)).handleConnection(serverConn)
		close(doneCh)
	}()

	writeFrame(t, clientConn, []byte{0xff})
	waitConnectionClosed(t, doneCh)

	if got := logs.String(); !strings.Contains(got, "packet_error_class=malformed_protobuf") {
		t.Fatalf("handleConnection() logs = %q, want packet_error_class=malformed_protobuf", got)
	}
}

func TestNetworkErrorClassification(t *testing.T) {
	tests := []struct {
		name string
		err  error
		want networkErrorClass
	}{
		{name: "nil", err: nil, want: networkErrorNone},
		{name: "oversized", err: fmt.Errorf("wrapped: %w", errPacketTooLarge), want: networkErrorOversizedFrame},
		{name: "malformed", err: fmt.Errorf("wrapped: %w", errMalformedPacket), want: networkErrorMalformedProtobuf},
		{name: "encode", err: fmt.Errorf("wrapped: %w", errPacketEncode), want: networkErrorEncode},
		{name: "timeout", err: timeoutError{}, want: networkErrorTimeout},
		{name: "short write", err: fmt.Errorf("wrapped: %w", io.ErrShortWrite), want: networkErrorShortWrite},
		{name: "short frame", err: fmt.Errorf("wrapped: %w", io.ErrUnexpectedEOF), want: networkErrorShortFrame},
		{name: "eof", err: fmt.Errorf("wrapped: %w", io.EOF), want: networkErrorEOF},
		{name: "other", err: errors.New("plain error"), want: networkErrorOther},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := classifyNetworkError(tt.err); got != tt.want {
				t.Fatalf("classifyNetworkError() = %s, want %s", got, tt.want)
			}
		})
	}
}

func TestWriteFullClassifiesZeroByteWriteAsShortWrite(t *testing.T) {
	err := writeFull(zeroWriter{}, []byte{0x01})
	if !errors.Is(err, io.ErrShortWrite) {
		t.Fatalf("writeFull() error = %v, want io.ErrShortWrite", err)
	}
	if got := classifyNetworkError(err); got != networkErrorShortWrite {
		t.Fatalf("classifyNetworkError() = %s, want %s", got, networkErrorShortWrite)
	}
}

type timeoutError struct{}

func (timeoutError) Error() string {
	return "timeout"
}

func (timeoutError) Timeout() bool {
	return true
}

func (timeoutError) Temporary() bool {
	return false
}

type zeroWriter struct{}

func (zeroWriter) Write([]byte) (int, error) {
	return 0, nil
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

func receiveInitialClientPacketAsync(conn net.Conn) <-chan receivePacketResult {
	resultCh := make(chan receivePacketResult, 1)
	go func() {
		packet, hasPacket, err := NewServer(":0", world.NewWorld(nil)).receiveInitialClientPacket(conn)
		if !hasPacket {
			packet = nil
		}
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

func waitConnectionClosed(t *testing.T, doneCh <-chan struct{}) {
	t.Helper()

	select {
	case <-doneCh:
	case <-time.After(time.Second):
		t.Fatal("handleConnection() did not return")
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

	if err := writeRawFrame(conn, data); err != nil {
		t.Fatal(err)
	}
}

func writeRawFrame(conn net.Conn, data []byte) error {
	lenBuf := make([]byte, 4)
	binary.LittleEndian.PutUint32(lenBuf, uint32(len(data)))
	if err := writeFull(conn, lenBuf); err != nil {
		return fmt.Errorf("write frame length: %w", err)
	}
	if err := writeFull(conn, data); err != nil {
		return fmt.Errorf("write frame payload: %w", err)
	}
	return nil
}
