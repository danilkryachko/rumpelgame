package network

import (
	"bytes"
	"io"
	"net"
	"testing"
	"time"

	"google.golang.org/protobuf/proto"
	"rumpelmc/server/pkg/api"
	"rumpelmc/server/pkg/world"
)

func TestConfiguredChunksPerUpdateUsesDefault(t *testing.T) {
	t.Setenv(chunksPerUpdateEnv, "")

	if got := configuredChunksPerUpdate(); got != defaultChunksPerUpdate {
		t.Fatalf("configuredChunksPerUpdate() = %d, want %d", got, defaultChunksPerUpdate)
	}
}

func TestConfiguredChunksPerUpdateUsesEnvOverride(t *testing.T) {
	t.Setenv(chunksPerUpdateEnv, "48")

	if got := configuredChunksPerUpdate(); got != 48 {
		t.Fatalf("configuredChunksPerUpdate() = %d, want 48", got)
	}
}

func TestConfiguredChunksPerUpdateIgnoresInvalidEnv(t *testing.T) {
	for _, value := range []string{"0", "-2", "nope"} {
		t.Run(value, func(t *testing.T) {
			t.Setenv(chunksPerUpdateEnv, value)

			if got := configuredChunksPerUpdate(); got != defaultChunksPerUpdate {
				t.Fatalf("configuredChunksPerUpdate() = %d, want %d", got, defaultChunksPerUpdate)
			}
		})
	}
}

func TestConfiguredViewDistanceDefault(t *testing.T) {
	t.Setenv(viewDistanceEnv, "")

	if got := configuredViewDistance(); got != defaultViewDistance {
		t.Fatalf("configuredViewDistance() = %d, want %d", got, defaultViewDistance)
	}
}

func TestConfiguredViewDistanceIgnoresInvalid(t *testing.T) {
	t.Setenv(viewDistanceEnv, "nope")

	if got := configuredViewDistance(); got != defaultViewDistance {
		t.Fatalf("configuredViewDistance() = %d, want %d", got, defaultViewDistance)
	}
}

func TestConfiguredViewDistanceClampsStressRadius(t *testing.T) {
	t.Setenv(viewDistanceEnv, "99")

	if got := configuredViewDistance(); got != maxViewDistance {
		t.Fatalf("configuredViewDistance() = %d, want %d", got, maxViewDistance)
	}
}

func TestConfiguredBootstrapRadiusDefaultsToViewDistance(t *testing.T) {
	t.Setenv(bootstrapRadiusEnv, "")

	if got := configuredBootstrapRadius(10); got != 10 {
		t.Fatalf("configuredBootstrapRadius() = %d, want 10", got)
	}
}

func TestConfiguredBootstrapRadiusUsesEnvOverride(t *testing.T) {
	t.Setenv(bootstrapRadiusEnv, "2")

	if got := configuredBootstrapRadius(10); got != 2 {
		t.Fatalf("configuredBootstrapRadius() = %d, want 2", got)
	}
}

func TestConfiguredBootstrapRadiusAllowsCurrentChunkOnly(t *testing.T) {
	t.Setenv(bootstrapRadiusEnv, "0")

	if got := configuredBootstrapRadius(10); got != 0 {
		t.Fatalf("configuredBootstrapRadius() = %d, want 0", got)
	}
}

func TestConfiguredBootstrapRadiusClampsToViewDistance(t *testing.T) {
	t.Setenv(bootstrapRadiusEnv, "32")

	if got := configuredBootstrapRadius(10); got != 10 {
		t.Fatalf("configuredBootstrapRadius() = %d, want 10", got)
	}
}

func TestConfiguredBootstrapRadiusIgnoresInvalidEnv(t *testing.T) {
	for _, value := range []string{"-1", "nope"} {
		t.Run(value, func(t *testing.T) {
			t.Setenv(bootstrapRadiusEnv, value)

			if got := configuredBootstrapRadius(10); got != 10 {
				t.Fatalf("configuredBootstrapRadius() = %d, want 10", got)
			}
		})
	}
}

func TestChunkStreamMetricsEnabledParsesSupportedValues(t *testing.T) {
	for _, value := range []string{"1", "true", "yes", "on", " TRUE "} {
		t.Run(value, func(t *testing.T) {
			t.Setenv(chunkStreamMetricsEnv, value)
			if !chunkStreamMetricsEnabled() {
				t.Fatalf("chunkStreamMetricsEnabled() = false, want true for %q", value)
			}
		})
	}
	for _, value := range []string{"", "0", "false", "off", "nope"} {
		t.Run(value, func(t *testing.T) {
			t.Setenv(chunkStreamMetricsEnv, value)
			if chunkStreamMetricsEnabled() {
				t.Fatalf("chunkStreamMetricsEnabled() = true, want false for %q", value)
			}
		})
	}
}

func TestConfiguredChunkEncodingParsesSupportedValues(t *testing.T) {
	t.Setenv(chunkEncodingEnv, "")
	if got := configuredChunkEncoding(); got != api.ChunkEncoding_CHUNK_ENCODING_RLE {
		t.Fatalf("configuredChunkEncoding() = %v, want default rle", got)
	}

	t.Setenv(chunkEncodingEnv, "rle")
	if got := configuredChunkEncoding(); got != api.ChunkEncoding_CHUNK_ENCODING_RLE {
		t.Fatalf("configuredChunkEncoding() = %v, want rle", got)
	}

	t.Setenv(chunkEncodingEnv, "raw")
	if got := configuredChunkEncoding(); got != api.ChunkEncoding_CHUNK_ENCODING_RAW {
		t.Fatalf("configuredChunkEncoding() = %v, want raw rollback", got)
	}

	t.Setenv(chunkEncodingEnv, "invalid")
	if got := configuredChunkEncoding(); got != api.ChunkEncoding_CHUNK_ENCODING_RLE {
		t.Fatalf("configuredChunkEncoding() = %v, want default rle fallback", got)
	}
}

func TestFramedPacketSizeIncludesLengthPrefix(t *testing.T) {
	packet := &api.Packet{
		Payload: &api.Packet_Chunk{
			Chunk: &api.ChunkData{
				X:      1,
				Z:      2,
				Blocks: []byte{0xaa, 0x55},
			},
		},
	}

	if got, want := framedPacketSize(packet), 14; got != want {
		t.Fatalf("framedPacketSize() = %d, want %d", got, want)
	}
}

func TestChunkStreamBatchStatsAggregatesSentChunks(t *testing.T) {
	var batch chunkStreamBatchStats

	batch.add(chunkSendStats{rawBytes: 10, payloadBytes: 5, wireBytes: 12})
	batch.add(chunkSendStats{rawBytes: 20, payloadBytes: 7, wireBytes: 24})

	if batch.chunks != 2 || batch.rawBytes != 30 || batch.payloadBytes != 12 || batch.wireBytes != 36 {
		t.Fatalf("batch stats = chunks:%d raw:%d payload:%d wire:%d, want chunks:2 raw:30 payload:12 wire:36", batch.chunks, batch.rawBytes, batch.payloadBytes, batch.wireBytes)
	}
}

func TestRLEChunkBatchShrinksPayloadAndWireBytes(t *testing.T) {
	gameWorld := world.NewWorld(nil)
	chunks, err := gameWorld.ChunksAround(0, 0, 1, map[world.ChunkCoord]bool{}, 3)
	if err != nil {
		t.Fatalf("ChunksAround() error = %v", err)
	}
	if len(chunks) != 3 {
		t.Fatalf("ChunksAround() returned %d chunks, want 3", len(chunks))
	}

	rawServer := NewServer(":0", gameWorld)
	rawServer.chunkEncoding = api.ChunkEncoding_CHUNK_ENCODING_RAW
	rawStats := sendChunkBatchForTest(t, rawServer, chunks)

	rleServer := NewServer(":0", gameWorld)
	rleServer.chunkEncoding = api.ChunkEncoding_CHUNK_ENCODING_RLE
	rleStats := sendChunkBatchForTest(t, rleServer, chunks)
	t.Logf(
		"raw_payload=%d rle_payload=%d raw_wire=%d rle_wire=%d",
		rawStats.payloadBytes,
		rleStats.payloadBytes,
		rawStats.wireBytes,
		rleStats.wireBytes,
	)

	if rleStats.chunks != rawStats.chunks {
		t.Fatalf("RLE chunks = %d, want %d", rleStats.chunks, rawStats.chunks)
	}
	if rleStats.rawBytes != rawStats.rawBytes {
		t.Fatalf("RLE raw bytes = %d, want %d", rleStats.rawBytes, rawStats.rawBytes)
	}
	if rleStats.payloadBytes >= rawStats.payloadBytes/100 {
		t.Fatalf("RLE payload bytes = %d, want less than 1%% of raw payload bytes %d", rleStats.payloadBytes, rawStats.payloadBytes)
	}
	if rleStats.wireBytes >= rawStats.wireBytes/100 {
		t.Fatalf("RLE wire bytes = %d, want less than 1%% of raw wire bytes %d", rleStats.wireBytes, rawStats.wireBytes)
	}
}

func TestSendChunksAroundWithRadiusLimitsBootstrapArea(t *testing.T) {
	gameWorld := world.NewWorld(nil)
	server := NewServer(":0", gameWorld)
	server.chunkEncoding = api.ChunkEncoding_CHUNK_ENCODING_RLE
	server.chunksPerUpdate = 64
	sentChunks := map[world.ChunkCoord]bool{}
	conn := &recordingConn{}

	if err := server.sendChunksAroundWithRadius(conn, 0, 0, 1, sentChunks); err != nil {
		t.Fatalf("sendChunksAroundWithRadius() error = %v", err)
	}

	if len(sentChunks) != 5 {
		t.Fatalf("sent chunks = %d, want 5 for radius 1", len(sentChunks))
	}
	for coord := range sentChunks {
		if !world.ChunkWithinRadius(coord, 0, 0, 1) {
			t.Fatalf("sent out-of-bootstrap-radius chunk %+v", coord)
		}
	}
}

func TestHandleInitialClientPacketUsesBootstrapRadius(t *testing.T) {
	serverConn, clientConn := net.Pipe()
	defer serverConn.Close()
	defer clientConn.Close()

	server := NewServer(":0", world.NewWorld(nil))
	server.chunkEncoding = api.ChunkEncoding_CHUNK_ENCODING_RLE
	server.chunksPerUpdate = 64
	server.bootstrapRadius = 0
	sentChunks := map[world.ChunkCoord]bool{}

	errCh := make(chan error, 1)
	go func() {
		packet := &api.Packet{
			Payload: &api.Packet_Position{
				Position: &api.ClientPosition{X: 48, Y: 68, Z: 80},
			},
		}
		errCh <- server.handleInitialClientPacket(serverConn, packet, sentChunks)
	}()

	readFrame(t, clientConn)
	if err := <-errCh; err != nil {
		t.Fatalf("handleInitialClientPacket() error = %v", err)
	}

	if len(sentChunks) != 1 {
		t.Fatalf("sent chunks = %d, want 1 for bootstrap radius 0", len(sentChunks))
	}
	if !sentChunks[world.ChunkCoord{X: 1, Z: 2}] {
		t.Fatalf("missing current bootstrap chunk 1,2 in sent map: %+v", sentChunks)
	}
}

func TestSendChunkCanUseRLEPayload(t *testing.T) {
	serverConn, clientConn := net.Pipe()
	defer serverConn.Close()
	defer clientConn.Close()

	chunk := world.NewChunk(0, 0)
	chunk.GenerateFlat()
	raw := chunk.Serialize()
	server := NewServer(":0", world.NewWorld(nil))
	server.chunkEncoding = api.ChunkEncoding_CHUNK_ENCODING_RLE

	errCh := make(chan error, 1)
	var stats chunkSendStats
	go func() {
		var err error
		stats, err = server.sendChunk(serverConn, world.ChunkSnapshot{
			X:      chunk.X,
			Z:      chunk.Z,
			Blocks: raw,
		})
		errCh <- err
	}()

	dataBuf := readFrame(t, clientConn)
	if err := <-errCh; err != nil {
		t.Fatalf("sendChunk() error = %v", err)
	}

	packet := &api.Packet{}
	if err := proto.Unmarshal(dataBuf, packet); err != nil {
		t.Fatalf("unmarshal payload: %v", err)
	}
	chunkData := packet.GetChunk()
	if chunkData == nil {
		t.Fatal("packet chunk = nil")
	}
	if got := chunkData.GetEncoding(); got != api.ChunkEncoding_CHUNK_ENCODING_RLE {
		t.Fatalf("chunk encoding = %v, want RLE", got)
	}
	if got := chunkData.GetUncompressedSize(); got != uint32(world.SerializedChunkSize) {
		t.Fatalf("uncompressed size = %d, want %d", got, world.SerializedChunkSize)
	}
	if len(chunkData.GetBlocks()) >= 64 {
		t.Fatalf("RLE payload length = %d, want less than 64", len(chunkData.GetBlocks()))
	}

	decoded, err := world.DecodeSerializedChunkRLE(chunkData.GetBlocks())
	if err != nil {
		t.Fatalf("DecodeSerializedChunkRLE() error = %v", err)
	}
	if !bytes.Equal(decoded, raw) {
		t.Fatal("decoded RLE payload differs from raw chunk")
	}
	if stats.rawBytes != len(raw) || stats.payloadBytes != len(chunkData.GetBlocks()) || stats.wireBytes != len(dataBuf)+4 {
		t.Fatalf("stats = raw:%d payload:%d wire:%d, want raw:%d payload:%d wire:%d", stats.rawBytes, stats.payloadBytes, stats.wireBytes, len(raw), len(chunkData.GetBlocks()), len(dataBuf)+4)
	}
}

func sendChunkBatchForTest(t *testing.T, server *Server, chunks []world.ChunkSnapshot) chunkStreamBatchStats {
	t.Helper()

	conn := &recordingConn{}
	var batch chunkStreamBatchStats
	for _, chunk := range chunks {
		stats, err := server.sendChunk(conn, chunk)
		if err != nil {
			t.Fatalf("sendChunk() error = %v", err)
		}
		batch.add(stats)
	}
	if conn.written != batch.wireBytes {
		t.Fatalf("connection wrote %d bytes, stats wire bytes = %d", conn.written, batch.wireBytes)
	}
	return batch
}

type recordingConn struct {
	written int
}

func (c *recordingConn) Read([]byte) (int, error) {
	return 0, io.EOF
}

func (c *recordingConn) Write(data []byte) (int, error) {
	c.written += len(data)
	return len(data), nil
}

func (c *recordingConn) Close() error {
	return nil
}

func (c *recordingConn) LocalAddr() net.Addr {
	return testAddr("local")
}

func (c *recordingConn) RemoteAddr() net.Addr {
	return testAddr("remote")
}

func (c *recordingConn) SetDeadline(time.Time) error {
	return nil
}

func (c *recordingConn) SetReadDeadline(time.Time) error {
	return nil
}

func (c *recordingConn) SetWriteDeadline(time.Time) error {
	return nil
}

type testAddr string

func (a testAddr) Network() string {
	return "test"
}

func (a testAddr) String() string {
	return string(a)
}
