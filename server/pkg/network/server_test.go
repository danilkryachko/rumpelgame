package network

import (
	"bytes"
	"encoding/binary"
	"errors"
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

func TestConfiguredBootstrapRadiusUsesDefault(t *testing.T) {
	t.Setenv(bootstrapRadiusEnv, "")

	if got := configuredBootstrapRadius(10); got != defaultBootstrapRadius {
		t.Fatalf("configuredBootstrapRadius() = %d, want %d", got, defaultBootstrapRadius)
	}
}

func TestConfiguredBootstrapRadiusDefaultCanUseCurrentChunkOnly(t *testing.T) {
	t.Setenv(bootstrapRadiusEnv, "")

	if got := configuredBootstrapRadius(1); got != defaultBootstrapRadius {
		t.Fatalf("configuredBootstrapRadius() = %d, want %d", got, defaultBootstrapRadius)
	}
}

func TestConfiguredBootstrapRadiusFullUsesViewDistance(t *testing.T) {
	t.Setenv(bootstrapRadiusEnv, "full")

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

			if got := configuredBootstrapRadius(10); got != defaultBootstrapRadius {
				t.Fatalf("configuredBootstrapRadius() = %d, want %d", got, defaultBootstrapRadius)
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

func TestConfiguredChunkOrderModeParsesSupportedValues(t *testing.T) {
	t.Setenv(chunkOrderEnv, "")
	if got := configuredChunkOrderMode(); got != chunkOrderNearest {
		t.Fatalf("configuredChunkOrderMode() = %v, want default nearest", got)
	}

	t.Setenv(chunkOrderEnv, "nearest")
	if got := configuredChunkOrderMode(); got != chunkOrderNearest {
		t.Fatalf("configuredChunkOrderMode() = %v, want nearest", got)
	}

	t.Setenv(chunkOrderEnv, "directional")
	if got := configuredChunkOrderMode(); got != chunkOrderDirectional {
		t.Fatalf("configuredChunkOrderMode() = %v, want directional", got)
	}

	t.Setenv(chunkOrderEnv, "invalid")
	if got := configuredChunkOrderMode(); got != chunkOrderNearest {
		t.Fatalf("configuredChunkOrderMode() = %v, want nearest fallback", got)
	}
}

func TestConfiguredClientWriteTimeoutParsesSupportedValues(t *testing.T) {
	t.Setenv(clientWriteTimeoutEnv, "")
	if got := configuredClientWriteTimeout(); got != defaultClientWriteTimeout {
		t.Fatalf("configuredClientWriteTimeout() = %s, want default %s", got, defaultClientWriteTimeout)
	}

	t.Setenv(clientWriteTimeoutEnv, "25")
	if got := configuredClientWriteTimeout(); got != 25*time.Millisecond {
		t.Fatalf("configuredClientWriteTimeout() = %s, want 25ms", got)
	}

	t.Setenv(clientWriteTimeoutEnv, "0")
	if got := configuredClientWriteTimeout(); got != 0 {
		t.Fatalf("configuredClientWriteTimeout() = %s, want disabled timeout", got)
	}

	for _, value := range []string{"-1", "nope"} {
		t.Run(value, func(t *testing.T) {
			t.Setenv(clientWriteTimeoutEnv, value)
			if got := configuredClientWriteTimeout(); got != defaultClientWriteTimeout {
				t.Fatalf("configuredClientWriteTimeout() = %s, want default %s", got, defaultClientWriteTimeout)
			}
		})
	}
}

func TestClientChunkStreamStateDirectionalOrderTracksChunkMovement(t *testing.T) {
	streamState := clientChunkStreamState{}
	if got := streamState.chunkOrderForCenter(world.ChunkCoord{X: 1, Z: 0}, chunkOrderDirectional); got != (world.ChunkOrder{}) {
		t.Fatalf("chunkOrderForCenter() before last center = %+v, want zero order", got)
	}

	streamState.recordCenter(world.ChunkCoord{X: 0, Z: 0})
	if got := streamState.chunkOrderForCenter(world.ChunkCoord{X: 2, Z: -3}, chunkOrderDirectional); got != (world.ChunkOrder{DirectionX: 1, DirectionZ: -1}) {
		t.Fatalf("chunkOrderForCenter() = %+v, want +X/-Z direction", got)
	}
	if got := streamState.chunkOrderForCenter(world.ChunkCoord{X: 2, Z: -3}, chunkOrderNearest); got != (world.ChunkOrder{}) {
		t.Fatalf("chunkOrderForCenter() nearest mode = %+v, want zero order", got)
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

func TestSendChunksAroundKeepsPerClientSentStateIndependent(t *testing.T) {
	gameWorld := world.NewWorld(nil)
	server := NewServer(":0", gameWorld)
	server.chunkEncoding = api.ChunkEncoding_CHUNK_ENCODING_RLE
	server.chunksPerUpdate = 1

	firstClientSent := map[world.ChunkCoord]bool{}
	firstClientConn := &recordingConn{}
	if err := server.sendChunksAroundWithRadius(firstClientConn, 0, 0, 1, firstClientSent); err != nil {
		t.Fatalf("first client sendChunksAroundWithRadius() error = %v", err)
	}
	if len(firstClientSent) != 1 || !firstClientSent[world.ChunkCoord{X: 0, Z: 0}] {
		t.Fatalf("first client sent chunks = %+v, want only current chunk", firstClientSent)
	}

	secondClientSent := map[world.ChunkCoord]bool{}
	secondClientConn := &recordingConn{}
	if err := server.sendChunksAroundWithRadius(secondClientConn, 0, 0, 1, secondClientSent); err != nil {
		t.Fatalf("second client sendChunksAroundWithRadius() error = %v", err)
	}
	if len(secondClientSent) != 1 || !secondClientSent[world.ChunkCoord{X: 0, Z: 0}] {
		t.Fatalf("second client sent chunks = %+v, want independent current chunk", secondClientSent)
	}
	if firstClientConn.written == 0 || secondClientConn.written == 0 {
		t.Fatalf("client writes = first:%d second:%d, want both nonzero", firstClientConn.written, secondClientConn.written)
	}

	firstClientNextConn := &recordingConn{}
	if err := server.sendChunksAroundWithRadius(firstClientNextConn, 0, 0, 1, firstClientSent); err != nil {
		t.Fatalf("first client next sendChunksAroundWithRadius() error = %v", err)
	}
	if len(firstClientSent) != 2 {
		t.Fatalf("first client sent chunks after next batch = %+v, want 2 chunks", firstClientSent)
	}
	if len(secondClientSent) != 1 {
		t.Fatalf("second client sent chunks changed after first client progress: %+v", secondClientSent)
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

func TestHandleClientPacketIgnoresUnknownBlockAction(t *testing.T) {
	server := NewServer(":0", world.NewWorld(nil))
	conn := &recordingConn{}

	packet := &api.Packet{
		Payload: &api.Packet_BlockAction{
			BlockAction: &api.BlockAction{
				Action: api.BlockAction_ActionType(99),
				X:      1,
				Y:      62,
				Z:      1,
			},
		},
	}

	if err := server.handleClientPacket(conn, packet, map[world.ChunkCoord]bool{}); err != nil {
		t.Fatalf("handleClientPacket() error = %v", err)
	}
	if conn.written != 0 {
		t.Fatalf("unknown block action wrote %d bytes, want 0", conn.written)
	}
}

func TestHandleClientPacketBroadcastsBlockUpdateToInterestedClients(t *testing.T) {
	server := NewServer(":0", world.NewWorld(nil))
	server.chunkEncoding = api.ChunkEncoding_CHUNK_ENCODING_RAW

	origin := newClientSession(&recordingConn{})
	watcher := newClientSession(&recordingConn{})
	uninterested := newClientSession(&recordingConn{})

	watcher.streamState.sentChunks[world.ChunkCoord{X: 0, Z: 0}] = true
	uninterested.streamState.sentChunks[world.ChunkCoord{X: 1, Z: 0}] = true

	server.registerClient(watcher)
	server.registerClient(uninterested)
	defer server.unregisterClient(watcher)
	defer server.unregisterClient(uninterested)

	packet := &api.Packet{
		Payload: &api.Packet_BlockAction{
			BlockAction: &api.BlockAction{
				Action:  api.BlockAction_PLACE,
				X:       1,
				Y:       64,
				Z:       1,
				BlockId: uint32(world.Wood),
			},
		},
	}

	if err := server.handleClientPacketForSession(origin, packet); err != nil {
		t.Fatalf("handleClientPacketForSession() error = %v", err)
	}

	originConn := origin.conn.(*recordingConn)
	watcherConn := watcher.conn.(*recordingConn)
	uninterestedConn := uninterested.conn.(*recordingConn)
	if got := len(recordedFrames(t, originConn)); got != 1 {
		t.Fatalf("origin frames = %d, want 1", got)
	}
	watcherFrames := recordedFrames(t, watcherConn)
	if got := len(watcherFrames); got != 1 {
		t.Fatalf("watcher frames = %d, want 1", got)
	}
	if got := len(recordedFrames(t, uninterestedConn)); got != 0 {
		t.Fatalf("uninterested frames = %d, want 0", got)
	}

	decoded := &api.Packet{}
	if err := proto.Unmarshal(watcherFrames[0], decoded); err != nil {
		t.Fatalf("unmarshal watcher frame: %v", err)
	}
	chunkData := decoded.GetChunk()
	if chunkData == nil {
		t.Fatal("watcher frame chunk = nil")
	}
	if chunkData.GetX() != 0 || chunkData.GetZ() != 0 {
		t.Fatalf("watcher chunk coord = %d,%d, want 0,0", chunkData.GetX(), chunkData.GetZ())
	}
	chunk, err := world.DeserializeChunk(chunkData.GetX(), chunkData.GetZ(), chunkData.GetBlocks())
	if err != nil {
		t.Fatalf("DeserializeChunk(watcher frame) error = %v", err)
	}
	if got := chunk.GetBlock(1, 64, 1); got != world.Wood {
		t.Fatalf("broadcast block = %v, want Wood", got)
	}
}

func TestBroadcastDisconnectsFailedInterestedClient(t *testing.T) {
	server := NewServer(":0", world.NewWorld(nil))
	server.chunkEncoding = api.ChunkEncoding_CHUNK_ENCODING_RAW

	origin := newClientSession(&recordingConn{})
	failedWatcherConn := &failingWriteConn{writeErr: errors.New("write failed")}
	failedWatcher := newClientSession(failedWatcherConn)
	failedWatcher.streamState.sentChunks[world.ChunkCoord{X: 0, Z: 0}] = true

	server.registerClient(failedWatcher)

	packet := &api.Packet{
		Payload: &api.Packet_BlockAction{
			BlockAction: &api.BlockAction{
				Action:  api.BlockAction_PLACE,
				X:       1,
				Y:       64,
				Z:       1,
				BlockId: uint32(world.Wood),
			},
		},
	}

	if err := server.handleClientPacketForSession(origin, packet); err != nil {
		t.Fatalf("handleClientPacketForSession() error = %v", err)
	}
	if !failedWatcherConn.closed {
		t.Fatal("failed watcher connection was not closed")
	}
	if server.clientCountForTest() != 0 {
		t.Fatalf("registered clients = %d, want failed watcher removed", server.clientCountForTest())
	}
}

func TestSendChunkToSessionSetsAndClearsWriteDeadline(t *testing.T) {
	server := NewServer(":0", world.NewWorld(nil))
	server.chunkEncoding = api.ChunkEncoding_CHUNK_ENCODING_RAW
	server.writeTimeout = 25 * time.Millisecond

	conn := &deadlineRecordingConn{}
	client := newClientSession(conn)
	if _, err := server.sendChunkToSession(client, world.ChunkSnapshot{X: 0, Z: 0, Blocks: []byte{0x01, 0x00}}); err != nil {
		t.Fatalf("sendChunkToSession() error = %v", err)
	}

	if len(conn.writeDeadlines) != 2 {
		t.Fatalf("write deadlines = %d, want set and clear", len(conn.writeDeadlines))
	}
	if conn.writeDeadlines[0].IsZero() {
		t.Fatal("first write deadline is zero, want active deadline")
	}
	if !conn.writeDeadlines[1].IsZero() {
		t.Fatalf("second write deadline = %s, want cleared zero deadline", conn.writeDeadlines[1])
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
	data    bytes.Buffer
}

func (c *recordingConn) Read([]byte) (int, error) {
	return 0, io.EOF
}

func (c *recordingConn) Write(data []byte) (int, error) {
	c.written += len(data)
	if _, err := c.data.Write(data); err != nil {
		return 0, err
	}
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

func (s *Server) clientCountForTest() int {
	s.clientsMu.Lock()
	defer s.clientsMu.Unlock()
	return len(s.clients)
}

func recordedFrames(t *testing.T, conn *recordingConn) [][]byte {
	t.Helper()

	data := conn.data.Bytes()
	var frames [][]byte
	for len(data) > 0 {
		if len(data) < 4 {
			t.Fatalf("recorded frame has short length prefix: %d bytes", len(data))
		}
		length := int(binary.LittleEndian.Uint32(data[:4]))
		data = data[4:]
		if len(data) < length {
			t.Fatalf("recorded frame payload length = %d, want %d", len(data), length)
		}
		frames = append(frames, append([]byte(nil), data[:length]...))
		data = data[length:]
	}
	return frames
}

type failingWriteConn struct {
	writeErr error
	closed   bool
}

func (c *failingWriteConn) Read([]byte) (int, error) {
	return 0, io.EOF
}

func (c *failingWriteConn) Write([]byte) (int, error) {
	return 0, c.writeErr
}

func (c *failingWriteConn) Close() error {
	c.closed = true
	return nil
}

func (c *failingWriteConn) LocalAddr() net.Addr {
	return testAddr("local")
}

func (c *failingWriteConn) RemoteAddr() net.Addr {
	return testAddr("failed")
}

func (c *failingWriteConn) SetDeadline(time.Time) error {
	return nil
}

func (c *failingWriteConn) SetReadDeadline(time.Time) error {
	return nil
}

func (c *failingWriteConn) SetWriteDeadline(time.Time) error {
	return nil
}

type deadlineRecordingConn struct {
	recordingConn
	writeDeadlines []time.Time
}

func (c *deadlineRecordingConn) SetWriteDeadline(deadline time.Time) error {
	c.writeDeadlines = append(c.writeDeadlines, deadline)
	return nil
}
