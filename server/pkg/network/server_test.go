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
	playerinventory "rumpelmc/server/pkg/inventory"
	"rumpelmc/server/pkg/item"
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

func TestConfiguredViewDistanceUsesEnvOverride(t *testing.T) {
	t.Setenv(viewDistanceEnv, "12")

	if got := configuredViewDistance(); got != 12 {
		t.Fatalf("configuredViewDistance() = %d, want 12", got)
	}
}

func TestConfiguredViewDistanceIgnoresInvalid(t *testing.T) {
	t.Setenv(viewDistanceEnv, "nope")

	if got := configuredViewDistance(); got != defaultViewDistance {
		t.Fatalf("configuredViewDistance() = %d, want %d", got, defaultViewDistance)
	}
}

func TestConfiguredViewDistanceIgnoresNonPositive(t *testing.T) {
	for _, value := range []string{"0", "-1"} {
		t.Run(value, func(t *testing.T) {
			t.Setenv(viewDistanceEnv, value)

			if got := configuredViewDistance(); got != defaultViewDistance {
				t.Fatalf("configuredViewDistance() = %d, want %d", got, defaultViewDistance)
			}
		})
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

func TestConfiguredMaxClientsParsesSupportedValues(t *testing.T) {
	t.Setenv(maxClientsEnv, "")
	if got := configuredMaxClients(); got != defaultMaxClients {
		t.Fatalf("configuredMaxClients() = %d, want default %d", got, defaultMaxClients)
	}

	t.Setenv(maxClientsEnv, "0")
	if got := configuredMaxClients(); got != 0 {
		t.Fatalf("configuredMaxClients() = %d, want unlimited 0", got)
	}

	t.Setenv(maxClientsEnv, "3")
	if got := configuredMaxClients(); got != 3 {
		t.Fatalf("configuredMaxClients() = %d, want 3", got)
	}

	for _, value := range []string{"-1", "nope"} {
		t.Run(value, func(t *testing.T) {
			t.Setenv(maxClientsEnv, value)
			if got := configuredMaxClients(); got != defaultMaxClients {
				t.Fatalf("configuredMaxClients() = %d, want default %d", got, defaultMaxClients)
			}
		})
	}
}

func TestConfiguredInventoryModeUsesCreativeDefault(t *testing.T) {
	t.Setenv(inventoryModeEnv, "")

	if got := configuredInventoryMode(); got != inventoryModeCreative {
		t.Fatalf("configuredInventoryMode() = %q, want %q", got, inventoryModeCreative)
	}
}

func TestConfiguredInventoryModeUsesCountedEnv(t *testing.T) {
	for _, value := range []string{"counted", "survival", " COUNTED "} {
		t.Run(value, func(t *testing.T) {
			t.Setenv(inventoryModeEnv, value)

			if got := configuredInventoryMode(); got != inventoryModeCounted {
				t.Fatalf("configuredInventoryMode() = %q, want %q", got, inventoryModeCounted)
			}
		})
	}
}

func TestConfiguredInventoryModeIgnoresInvalidEnv(t *testing.T) {
	t.Setenv(inventoryModeEnv, "invalid")

	if got := configuredInventoryMode(); got != inventoryModeCreative {
		t.Fatalf("configuredInventoryMode() = %q, want %q", got, inventoryModeCreative)
	}
}

func TestConfiguredMiningCooldownUsesModeDefault(t *testing.T) {
	t.Setenv(miningCooldownEnv, "")

	if got := configuredMiningCooldown(inventoryModeCreative); got != 0 {
		t.Fatalf("creative configuredMiningCooldown() = %s, want disabled", got)
	}
	if got := configuredMiningCooldown(inventoryModeCounted); got != defaultCountedMiningCooldown {
		t.Fatalf("counted configuredMiningCooldown() = %s, want %s", got, defaultCountedMiningCooldown)
	}
}

func TestConfiguredMiningCooldownUsesEnvOverride(t *testing.T) {
	t.Setenv(miningCooldownEnv, "125")

	if got := configuredMiningCooldown(inventoryModeCreative); got != 125*time.Millisecond {
		t.Fatalf("configuredMiningCooldown() = %s, want 125ms", got)
	}
}

func TestConfiguredMiningCooldownIgnoresInvalidEnv(t *testing.T) {
	for _, value := range []string{"-1", "nope"} {
		t.Run(value, func(t *testing.T) {
			t.Setenv(miningCooldownEnv, value)
			if got := configuredMiningCooldown(inventoryModeCounted); got != defaultCountedMiningCooldown {
				t.Fatalf("configuredMiningCooldown() = %s, want %s", got, defaultCountedMiningCooldown)
			}
		})
	}
}

func TestConfiguredMiningDurationsUseModeDefaults(t *testing.T) {
	t.Setenv(miningCooldownEnv, "")

	creative := configuredMiningDurations(inventoryModeCreative, configuredMiningCooldown(inventoryModeCreative), false)
	if got := creative[world.Stone]; got != 0 {
		t.Fatalf("creative Stone mining duration = %s, want disabled", got)
	}

	counted := configuredMiningDurations(inventoryModeCounted, configuredMiningCooldown(inventoryModeCounted), false)
	if got := counted[world.Stone]; got != defaultCountedMiningCooldown {
		t.Fatalf("counted Stone mining duration = %s, want %s", got, defaultCountedMiningCooldown)
	}
	if got := counted[world.Dirt]; got != time.Duration(world.SoftBlockMiningMS)*time.Millisecond {
		t.Fatalf("counted Dirt mining duration = %s, want %dms", got, world.SoftBlockMiningMS)
	}
	if got := counted[world.Wood]; got != time.Duration(world.WoodBlockMiningMS)*time.Millisecond {
		t.Fatalf("counted Wood mining duration = %s, want %dms", got, world.WoodBlockMiningMS)
	}
	if got := counted[world.Air]; got != 0 {
		t.Fatalf("Air mining duration = %s, want disabled", got)
	}
}

func TestConfiguredMiningDurationsUseEnvOverride(t *testing.T) {
	t.Setenv(miningCooldownEnv, "125")
	cooldown, override := configuredMiningCooldownWithOverride(inventoryModeCounted)
	if !override {
		t.Fatal("configuredMiningCooldownWithOverride() override = false, want true")
	}
	durations := configuredMiningDurations(inventoryModeCounted, cooldown, override)

	for _, block := range []world.BlockID{world.Stone, world.Dirt, world.Grass, world.Wood, world.Leaves} {
		if got := durations[block]; got != 125*time.Millisecond {
			t.Fatalf("duration for block %d = %s, want 125ms", block, got)
		}
	}
}

func TestTryRegisterClientHonorsMaxClients(t *testing.T) {
	server := NewServer(":0", world.NewWorld(nil))
	server.maxClients = 1

	first := newClientSession(&recordingConn{})
	if activeClients, admitted := server.tryRegisterClient(first); !admitted || activeClients != 1 {
		t.Fatalf("first tryRegisterClient() = active:%d admitted:%v, want active:1 admitted:true", activeClients, admitted)
	}

	second := newClientSession(&recordingConn{})
	if activeClients, admitted := server.tryRegisterClient(second); admitted || activeClients != 1 {
		t.Fatalf("second tryRegisterClient() = active:%d admitted:%v, want active:1 admitted:false", activeClients, admitted)
	}
	if got := server.clientCountForTest(); got != 1 {
		t.Fatalf("registered clients = %d, want 1", got)
	}

	server.unregisterClient(first)
	if activeClients, admitted := server.tryRegisterClient(second); !admitted || activeClients != 1 {
		t.Fatalf("tryRegisterClient() after unregister = active:%d admitted:%v, want active:1 admitted:true", activeClients, admitted)
	}
}

func TestHandleConnectionRejectsWhenMaxClientsReached(t *testing.T) {
	server := NewServer(":0", world.NewWorld(nil))
	server.maxClients = 1
	heldClient := newClientSession(&recordingConn{})
	if activeClients, admitted := server.tryRegisterClient(heldClient); !admitted || activeClients != 1 {
		t.Fatalf("held tryRegisterClient() = active:%d admitted:%v, want active:1 admitted:true", activeClients, admitted)
	}
	defer server.unregisterClient(heldClient)

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
		server.handleConnection(serverConn)
		close(doneCh)
	}()
	waitConnectionClosed(t, doneCh)

	if got := server.clientCountForTest(); got != 1 {
		t.Fatalf("registered clients = %d, want only held client", got)
	}
	logText := logs.String()
	for _, token := range []string{"admission_result=rejected", "active_clients=1", "max_clients=1"} {
		if !strings.Contains(logText, token) {
			t.Fatalf("handleConnection() logs = %q, want token %q", logText, token)
		}
	}
}

func TestHandleConnectionSendsInventorySnapshotBeforeInitialChunks(t *testing.T) {
	serverConn, clientConn := net.Pipe()
	defer clientConn.Close()

	server := NewServer(":0", world.NewWorld(nil))
	server.chunkEncoding = api.ChunkEncoding_CHUNK_ENCODING_RAW

	doneCh := make(chan struct{})
	go func() {
		server.handleConnection(serverConn)
		close(doneCh)
	}()

	dataBuf := readFrame(t, clientConn)
	decoded := &api.Packet{}
	if err := proto.Unmarshal(dataBuf, decoded); err != nil {
		t.Fatalf("unmarshal first server frame: %v", err)
	}
	if decoded.GetInventorySnapshot() == nil {
		t.Fatalf("first server frame inventory snapshot = nil, payload %T", decoded.GetPayload())
	}

	if err := clientConn.Close(); err != nil {
		t.Fatalf("close client connection: %v", err)
	}
	select {
	case <-doneCh:
	case <-time.After(time.Second):
		t.Fatal("handleConnection did not return after client close")
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

func TestHandleInitialClientPacketIgnoresNilPacket(t *testing.T) {
	server := NewServer(":0", world.NewWorld(nil))

	t.Run("legacy state handler", func(t *testing.T) {
		conn := &recordingConn{}
		sentChunks := map[world.ChunkCoord]bool{}
		if err := server.handleInitialClientPacket(conn, nil, sentChunks); err != nil {
			t.Fatalf("handleInitialClientPacket() error = %v", err)
		}
		if len(sentChunks) != 0 {
			t.Fatalf("sent chunks = %+v, want none", sentChunks)
		}
		if got := len(recordedFrames(t, conn)); got != 0 {
			t.Fatalf("legacy initial handler frames = %d, want 0", got)
		}
	})

	t.Run("session handler", func(t *testing.T) {
		client := newClientSession(&recordingConn{})
		if err := server.handleInitialClientPacketForSession(client, nil); err != nil {
			t.Fatalf("handleInitialClientPacketForSession() error = %v", err)
		}
		if got := len(recordedFrames(t, client.conn.(*recordingConn))); got != 0 {
			t.Fatalf("session initial handler frames = %d, want 0", got)
		}
	})
}

func TestHandleInitialClientPacketIgnoresNilPosition(t *testing.T) {
	server := NewServer(":0", world.NewWorld(nil))
	packet := &api.Packet{Payload: &api.Packet_Position{}}

	t.Run("legacy state handler", func(t *testing.T) {
		conn := &recordingConn{}
		sentChunks := map[world.ChunkCoord]bool{}
		if err := server.handleInitialClientPacket(conn, packet, sentChunks); err != nil {
			t.Fatalf("handleInitialClientPacket() error = %v", err)
		}
		if len(sentChunks) != 0 {
			t.Fatalf("sent chunks = %+v, want none", sentChunks)
		}
		if got := len(recordedFrames(t, conn)); got != 0 {
			t.Fatalf("legacy initial handler frames = %d, want 0", got)
		}
	})

	t.Run("session handler", func(t *testing.T) {
		client := newClientSession(&recordingConn{})
		if err := server.handleInitialClientPacketForSession(client, packet); err != nil {
			t.Fatalf("handleInitialClientPacketForSession() error = %v", err)
		}
		if got := len(recordedFrames(t, client.conn.(*recordingConn))); got != 0 {
			t.Fatalf("session initial handler frames = %d, want 0", got)
		}
	})
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

func TestHandleClientPacketIgnoresNilPacket(t *testing.T) {
	server := NewServer(":0", world.NewWorld(nil))

	t.Run("legacy state handler", func(t *testing.T) {
		conn := &recordingConn{}
		sentChunks := map[world.ChunkCoord]bool{}
		if err := server.handleClientPacket(conn, nil, sentChunks); err != nil {
			t.Fatalf("handleClientPacket() error = %v", err)
		}
		if len(sentChunks) != 0 {
			t.Fatalf("sent chunks = %+v, want none", sentChunks)
		}
		if got := len(recordedFrames(t, conn)); got != 0 {
			t.Fatalf("legacy handler frames = %d, want 0", got)
		}
	})

	t.Run("session handler", func(t *testing.T) {
		origin := newClientSession(&recordingConn{})
		watcher := newClientSession(&recordingConn{})
		watcher.streamState.sentChunks[world.ChunkCoord{X: 0, Z: 0}] = true

		server.registerClient(watcher)
		defer server.unregisterClient(watcher)

		if err := server.handleClientPacketForSession(origin, nil); err != nil {
			t.Fatalf("handleClientPacketForSession() error = %v", err)
		}
		if got := len(recordedFrames(t, origin.conn.(*recordingConn))); got != 0 {
			t.Fatalf("origin frames = %d, want 0", got)
		}
		if got := len(recordedFrames(t, watcher.conn.(*recordingConn))); got != 0 {
			t.Fatalf("watcher frames = %d, want 0", got)
		}
	})
}

func TestHandleClientPacketIgnoresNilPosition(t *testing.T) {
	server := NewServer(":0", world.NewWorld(nil))
	packet := &api.Packet{Payload: &api.Packet_Position{}}

	t.Run("legacy state handler", func(t *testing.T) {
		conn := &recordingConn{}
		sentChunks := map[world.ChunkCoord]bool{}
		if err := server.handleClientPacket(conn, packet, sentChunks); err != nil {
			t.Fatalf("handleClientPacket() error = %v", err)
		}
		if len(sentChunks) != 0 {
			t.Fatalf("sent chunks = %+v, want none", sentChunks)
		}
		if got := len(recordedFrames(t, conn)); got != 0 {
			t.Fatalf("legacy handler frames = %d, want 0", got)
		}
	})

	t.Run("session handler", func(t *testing.T) {
		client := newClientSession(&recordingConn{})
		if err := server.handleClientPacketForSession(client, packet); err != nil {
			t.Fatalf("handleClientPacketForSession() error = %v", err)
		}
		if got := len(recordedFrames(t, client.conn.(*recordingConn))); got != 0 {
			t.Fatalf("session handler frames = %d, want 0", got)
		}
	})
}

func TestHandleClientPacketIgnoresEmptyPayload(t *testing.T) {
	server := NewServer(":0", world.NewWorld(nil))

	origin := newClientSession(&recordingConn{})
	watcher := newClientSession(&recordingConn{})
	watcher.streamState.sentChunks[world.ChunkCoord{X: 0, Z: 0}] = true

	server.registerClient(watcher)
	defer server.unregisterClient(watcher)

	if err := server.handleClientPacketForSession(origin, &api.Packet{}); err != nil {
		t.Fatalf("handleClientPacketForSession(empty payload) error = %v", err)
	}
	if got := len(recordedFrames(t, origin.conn.(*recordingConn))); got != 0 {
		t.Fatalf("origin frames = %d, want 0", got)
	}
	if got := len(recordedFrames(t, watcher.conn.(*recordingConn))); got != 0 {
		t.Fatalf("watcher frames = %d, want 0", got)
	}
}

func TestHandleClientPacketIgnoresNilBlockAction(t *testing.T) {
	server := NewServer(":0", world.NewWorld(nil))
	packet := &api.Packet{Payload: &api.Packet_BlockAction{}}

	t.Run("legacy state handler", func(t *testing.T) {
		conn := &recordingConn{}
		if err := server.handleClientPacket(conn, packet, map[world.ChunkCoord]bool{}); err != nil {
			t.Fatalf("handleClientPacket() error = %v", err)
		}
		if got := len(recordedFrames(t, conn)); got != 0 {
			t.Fatalf("legacy handler frames = %d, want 0", got)
		}
	})

	t.Run("session handler", func(t *testing.T) {
		origin := newClientSession(&recordingConn{})
		watcher := newClientSession(&recordingConn{})
		watcher.streamState.sentChunks[world.ChunkCoord{X: 0, Z: 0}] = true

		server.registerClient(watcher)
		defer server.unregisterClient(watcher)

		if err := server.handleClientPacketForSession(origin, packet); err != nil {
			t.Fatalf("handleClientPacketForSession() error = %v", err)
		}
		if got := len(recordedFrames(t, origin.conn.(*recordingConn))); got != 0 {
			t.Fatalf("origin frames = %d, want 0", got)
		}
		if got := len(recordedFrames(t, watcher.conn.(*recordingConn))); got != 0 {
			t.Fatalf("watcher frames = %d, want 0", got)
		}
	})
}

func TestNewClientSessionStartsWithServerAuthoritativeCreativeInventory(t *testing.T) {
	client := newClientSession(&recordingConn{})

	if !client.inventory.CanPlaceBlock(world.Wood) {
		t.Fatal("new client session cannot place Wood, want creative inventory available")
	}
	if client.inventory.CanPlaceBlock(world.Air) {
		t.Fatal("new client session can place Air, want false")
	}
	if got := client.selectedSlot(); got != 0 {
		t.Fatalf("new client session selected slot = %d, want 0", got)
	}
}

func TestServerCountedInventoryModeStartsSessionWithCountedHotbar(t *testing.T) {
	server := NewServer(":0", world.NewWorld(nil))
	server.inventoryMode = inventoryModeCounted
	client := server.newClientSession(&recordingConn{})

	if !client.inventory.CanPlaceBlock(world.Stone) {
		t.Fatal("counted session cannot place Stone, want finite counted inventory available")
	}
	if !client.inventory.PlaceBlock(world.Stone) {
		t.Fatal("counted session first PlaceBlock(Stone) = false, want true")
	}

	slots := client.inventory.Slots()
	if len(slots) == 0 {
		t.Fatal("counted session slots empty")
	}
	if got := slots[0].Count; got != playerinventory.CountedHotbarStackCount-1 {
		t.Fatalf("counted session stone count = %d, want %d", got, playerinventory.CountedHotbarStackCount-1)
	}
}

func TestSendInventorySnapshotToSessionUsesCountedInventoryMode(t *testing.T) {
	server := NewServer(":0", world.NewWorld(nil))
	server.inventoryMode = inventoryModeCounted
	client := server.newClientSession(&recordingConn{})

	if err := server.sendInventorySnapshotToSession(client); err != nil {
		t.Fatalf("sendInventorySnapshotToSession() error = %v", err)
	}

	frames := recordedFrames(t, client.conn.(*recordingConn))
	if got := len(frames); got != 1 {
		t.Fatalf("frames = %d, want 1", got)
	}
	snapshot := decodedPacket(t, frames[0]).GetInventorySnapshot()
	if snapshot == nil {
		t.Fatal("decoded inventory snapshot = nil")
	}
	if got := snapshot.GetSlots()[0].GetCount(); got != playerinventory.CountedHotbarStackCount {
		t.Fatalf("snapshot slot 0 count = %d, want %d", got, playerinventory.CountedHotbarStackCount)
	}
}

func TestHandleClientPacketRejectsPlaceWhenSessionInventoryLacksBlock(t *testing.T) {
	server := NewServer(":0", world.NewWorld(nil))
	server.chunkEncoding = api.ChunkEncoding_CHUNK_ENCODING_RAW

	origin := newClientSession(&recordingConn{})
	recordReachableBlockActionPosition(origin)
	origin.inventory = playerinventory.NewCounted([]playerinventory.Slot{
		{BlockID: world.Stone, Count: 1},
	})
	watcher := newClientSession(&recordingConn{})
	watcher.streamState.sentChunks[world.ChunkCoord{X: 0, Z: 0}] = true

	server.registerClient(watcher)
	defer server.unregisterClient(watcher)

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
	if got := len(recordedFrames(t, origin.conn.(*recordingConn))); got != 0 {
		t.Fatalf("origin frames = %d, want 0", got)
	}
	if got := len(recordedFrames(t, watcher.conn.(*recordingConn))); got != 0 {
		t.Fatalf("watcher frames = %d, want 0", got)
	}
}

func TestHandleClientPacketDoesNotConsumeInventoryWhenBlockUpdateFails(t *testing.T) {
	server := NewServer(":0", world.NewWorld(nil))

	origin := newClientSession(&recordingConn{})
	recordReachableOutOfRangeYPosition(origin)
	origin.inventory = playerinventory.NewCounted([]playerinventory.Slot{
		{BlockID: world.Stone, Count: 1},
	})
	packet := &api.Packet{
		Payload: &api.Packet_BlockAction{
			BlockAction: &api.BlockAction{
				Action:  api.BlockAction_PLACE,
				X:       1,
				Y:       int32(world.ChunkHeight),
				Z:       1,
				BlockId: uint32(world.Stone),
			},
		},
	}

	if err := server.handleClientPacketForSession(origin, packet); err == nil {
		t.Fatal("handleClientPacketForSession() error = nil, want block update error")
	}
	if !origin.inventory.CanPlaceBlock(world.Stone) {
		t.Fatal("failed block update consumed inventory count")
	}
}

func TestHandleClientPacketRejectsBlockActionBeforePosition(t *testing.T) {
	server := NewServer(":0", world.NewWorld(nil))
	server.chunkEncoding = api.ChunkEncoding_CHUNK_ENCODING_RAW

	origin := newClientSession(&recordingConn{})
	watcher := newClientSession(&recordingConn{})
	watcher.streamState.sentChunks[world.ChunkCoord{X: 0, Z: 0}] = true

	server.registerClient(watcher)
	defer server.unregisterClient(watcher)

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
	if got := len(recordedFrames(t, origin.conn.(*recordingConn))); got != 0 {
		t.Fatalf("origin frames = %d, want 0", got)
	}
	if got := len(recordedFrames(t, watcher.conn.(*recordingConn))); got != 0 {
		t.Fatalf("watcher frames = %d, want 0", got)
	}
	snapshot, err := server.world.ChunkSnapshot(0, 0)
	if err != nil {
		t.Fatalf("ChunkSnapshot() error = %v", err)
	}
	chunk, err := world.DeserializeChunk(snapshot.X, snapshot.Z, snapshot.Blocks)
	if err != nil {
		t.Fatalf("DeserializeChunk() error = %v", err)
	}
	if got := chunk.GetBlock(1, 64, 1); got != world.Air {
		t.Fatalf("block after positionless action = %v, want Air", got)
	}
}

func TestHandleClientPacketRejectsOutOfReachBlockAction(t *testing.T) {
	server := NewServer(":0", world.NewWorld(nil))
	server.chunkEncoding = api.ChunkEncoding_CHUNK_ENCODING_RAW

	origin := newClientSession(&recordingConn{})
	recordReachableBlockActionPosition(origin)
	origin.inventory = playerinventory.NewCounted([]playerinventory.Slot{
		{BlockID: world.Stone, Count: 1},
	})
	watcher := newClientSession(&recordingConn{})
	watcher.streamState.sentChunks[world.ChunkCoord{X: 2, Z: 2}] = true

	server.registerClient(watcher)
	defer server.unregisterClient(watcher)

	packet := &api.Packet{
		Payload: &api.Packet_BlockAction{
			BlockAction: &api.BlockAction{
				Action:  api.BlockAction_PLACE,
				X:       32,
				Y:       64,
				Z:       32,
				BlockId: uint32(world.Stone),
			},
		},
	}

	if err := server.handleClientPacketForSession(origin, packet); err != nil {
		t.Fatalf("handleClientPacketForSession() error = %v", err)
	}
	if !origin.inventory.CanPlaceBlock(world.Stone) {
		t.Fatal("out-of-reach block action consumed inventory count")
	}
	if got := len(recordedFrames(t, origin.conn.(*recordingConn))); got != 0 {
		t.Fatalf("origin frames = %d, want 0", got)
	}
	if got := len(recordedFrames(t, watcher.conn.(*recordingConn))); got != 0 {
		t.Fatalf("watcher frames = %d, want 0", got)
	}
}

func TestHandleClientPacketRejectsPlaceInsidePlayer(t *testing.T) {
	server := NewServer(":0", world.NewWorld(nil))
	server.chunkEncoding = api.ChunkEncoding_CHUNK_ENCODING_RAW

	origin := newClientSession(&recordingConn{})
	origin.recordPosition(&api.ClientPosition{X: 1.5, Y: 64, Z: 1.5})
	origin.inventory = playerinventory.NewCounted([]playerinventory.Slot{
		{BlockID: world.Stone, Count: 1},
	})
	watcher := newClientSession(&recordingConn{})
	watcher.streamState.sentChunks[world.ChunkCoord{X: 0, Z: 0}] = true

	server.registerClient(watcher)
	defer server.unregisterClient(watcher)

	packet := &api.Packet{
		Payload: &api.Packet_BlockAction{
			BlockAction: &api.BlockAction{
				Action:  api.BlockAction_PLACE,
				X:       1,
				Y:       64,
				Z:       1,
				BlockId: uint32(world.Stone),
			},
		},
	}

	if err := server.handleClientPacketForSession(origin, packet); err != nil {
		t.Fatalf("handleClientPacketForSession() error = %v", err)
	}
	if !origin.inventory.CanPlaceBlock(world.Stone) {
		t.Fatal("player-intersecting placement consumed inventory count")
	}
	if got := len(recordedFrames(t, origin.conn.(*recordingConn))); got != 0 {
		t.Fatalf("origin frames = %d, want 0", got)
	}
	if got := len(recordedFrames(t, watcher.conn.(*recordingConn))); got != 0 {
		t.Fatalf("watcher frames = %d, want 0", got)
	}
	snapshot, err := server.world.ChunkSnapshot(0, 0)
	if err != nil {
		t.Fatalf("ChunkSnapshot() error = %v", err)
	}
	chunk, err := world.DeserializeChunk(snapshot.X, snapshot.Z, snapshot.Blocks)
	if err != nil {
		t.Fatalf("DeserializeChunk() error = %v", err)
	}
	if got := chunk.GetBlock(1, 64, 1); got != world.Air {
		t.Fatalf("block after player-intersecting placement = %v, want Air", got)
	}
}

func TestBlockActionWithinReachRequiresPositionAndBoundedDistance(t *testing.T) {
	position := clientPositionState{x: 1.5, y: 68, z: 1.5, ok: true}
	nearAction := &api.BlockAction{X: 1, Y: 64, Z: 1}
	farAction := &api.BlockAction{X: 32, Y: 64, Z: 32}

	if !blockActionWithinReach(position, nearAction) {
		t.Fatal("near block action rejected, want within reach")
	}
	if blockActionWithinReach(position, farAction) {
		t.Fatal("far block action accepted, want out of reach")
	}
	if blockActionWithinReach(clientPositionState{}, nearAction) {
		t.Fatal("block action without recorded position accepted")
	}
	if blockActionWithinReach(position, nil) {
		t.Fatal("nil block action accepted")
	}
}

func TestBlockActionIntersectsPlayerMatchesClientAABB(t *testing.T) {
	position := clientPositionState{x: 1.5, y: 64, z: 1.5, ok: true}

	if !blockActionIntersectsPlayer(position, &api.BlockAction{X: 1, Y: 64, Z: 1}) {
		t.Fatal("block overlapping player body was not detected")
	}
	if blockActionIntersectsPlayer(position, &api.BlockAction{X: 2, Y: 64, Z: 1}) {
		t.Fatal("x-separated block detected as overlapping player body")
	}
	if blockActionIntersectsPlayer(position, &api.BlockAction{X: 1, Y: 66, Z: 1}) {
		t.Fatal("y-separated block detected as overlapping player body")
	}
	if blockActionIntersectsPlayer(clientPositionState{}, &api.BlockAction{X: 1, Y: 64, Z: 1}) {
		t.Fatal("block action without recorded position intersected player")
	}
	if blockActionIntersectsPlayer(position, nil) {
		t.Fatal("nil block action intersected player")
	}
}

func TestInventorySnapshotPacketUsesSessionInventorySlots(t *testing.T) {
	inv := playerinventory.NewCounted([]playerinventory.Slot{
		{BlockID: world.Stone, Count: 2},
		{BlockID: world.Wood, Count: 7},
	})

	packet := inventorySnapshotPacket(inv, 1)
	snapshot := packet.GetInventorySnapshot()
	if snapshot == nil {
		t.Fatal("inventory snapshot packet payload = nil")
	}
	if got := snapshot.GetSelectedSlot(); got != 1 {
		t.Fatalf("snapshot selected slot = %d, want 1", got)
	}
	if got := len(snapshot.GetSlots()); got != 2 {
		t.Fatalf("snapshot slots = %d, want 2", got)
	}
	if got := snapshot.GetSlots()[0].GetBlockId(); got != uint32(world.Stone) {
		t.Fatalf("slot 0 block id = %d, want %d", got, world.Stone)
	}
	if got := snapshot.GetSlots()[0].GetCount(); got != 2 {
		t.Fatalf("slot 0 count = %d, want 2", got)
	}
	if got := snapshot.GetSlots()[1].GetBlockId(); got != uint32(world.Wood) {
		t.Fatalf("slot 1 block id = %d, want %d", got, world.Wood)
	}
	if got := snapshot.GetSlots()[1].GetCount(); got != 7 {
		t.Fatalf("slot 1 count = %d, want 7", got)
	}
}

func TestSendInventorySnapshotToSessionWritesInventorySnapshot(t *testing.T) {
	server := NewServer(":0", world.NewWorld(nil))
	client := newClientSession(&recordingConn{})

	if err := server.sendInventorySnapshotToSession(client); err != nil {
		t.Fatalf("sendInventorySnapshotToSession() error = %v", err)
	}

	frames := recordedFrames(t, client.conn.(*recordingConn))
	if got := len(frames); got != 1 {
		t.Fatalf("frames = %d, want 1", got)
	}
	decoded := &api.Packet{}
	if err := proto.Unmarshal(frames[0], decoded); err != nil {
		t.Fatalf("unmarshal inventory snapshot frame: %v", err)
	}
	snapshot := decoded.GetInventorySnapshot()
	if snapshot == nil {
		t.Fatal("decoded inventory snapshot = nil")
	}
	placeableBlocks := 0
	for _, block := range world.BlockDefinitions() {
		if block.Placeable {
			placeableBlocks++
		}
	}
	if got := len(snapshot.GetSlots()); got != placeableBlocks {
		t.Fatalf("snapshot slots = %d, want %d", got, placeableBlocks)
	}
	if got := snapshot.GetSelectedSlot(); got != 0 {
		t.Fatalf("snapshot selected slot = %d, want 0", got)
	}
	for _, slot := range snapshot.GetSlots() {
		if !world.IsPlaceable(world.BlockID(slot.GetBlockId())) {
			t.Fatalf("snapshot block id %d is not placeable", slot.GetBlockId())
		}
		if slot.GetCount() != playerinventory.CreativeStackCount {
			t.Fatalf("snapshot count = %d, want %d", slot.GetCount(), playerinventory.CreativeStackCount)
		}
	}
}

func TestHandleClientPacketInventoryActionSelectsSlotAndSendsSnapshot(t *testing.T) {
	server := NewServer(":0", world.NewWorld(nil))
	client := newClientSession(&recordingConn{})
	client.inventory = playerinventory.NewCounted([]playerinventory.Slot{
		{BlockID: world.Stone, Count: 1},
		{BlockID: world.Wood, Count: 1},
	})

	packet := &api.Packet{
		Payload: &api.Packet_InventoryAction{
			InventoryAction: &api.InventoryAction{
				Action: api.InventoryAction_SELECT_SLOT,
				Slot:   1,
			},
		},
	}

	if err := server.handleClientPacketForSession(client, packet); err != nil {
		t.Fatalf("handleClientPacketForSession() error = %v", err)
	}
	if got := client.selectedSlot(); got != 1 {
		t.Fatalf("selected slot = %d, want 1", got)
	}

	frames := recordedFrames(t, client.conn.(*recordingConn))
	if got := len(frames); got != 1 {
		t.Fatalf("frames = %d, want 1", got)
	}
	decoded := decodedPacket(t, frames[0])
	snapshot := decoded.GetInventorySnapshot()
	if snapshot == nil {
		t.Fatal("inventory action response snapshot = nil")
	}
	if got := snapshot.GetSelectedSlot(); got != 1 {
		t.Fatalf("response selected slot = %d, want 1", got)
	}
}

func TestHandleClientPacketPositionLoadsPersistedPlayerInventory(t *testing.T) {
	store := newMemoryPlayerInventoryStore()
	store.states["local_player"] = playerinventory.State{
		Slots: []playerinventory.Slot{
			{BlockID: world.Stone, Count: 2},
			{BlockID: world.Wood, Count: 7},
		},
		PlacementPolicy: playerinventory.PlacementPolicyConsume,
		SelectedSlot:    1,
	}

	server := NewServerWithPlayerInventoryStore(":0", world.NewWorld(nil), store)
	server.chunkEncoding = api.ChunkEncoding_CHUNK_ENCODING_RAW
	client := newClientSession(&recordingConn{})

	packet := &api.Packet{
		Payload: &api.Packet_Position{
			Position: &api.ClientPosition{
				X:        1,
				Y:        68,
				Z:        1,
				PlayerId: "local_player",
			},
		},
	}

	if err := server.handleInitialClientPacketForSession(client, packet); err != nil {
		t.Fatalf("handleInitialClientPacketForSession() error = %v", err)
	}
	if got := client.selectedSlot(); got != 1 {
		t.Fatalf("selected slot = %d, want persisted slot 1", got)
	}
	if !client.inventory.CanPlaceBlock(world.Wood) {
		t.Fatal("persisted inventory cannot place Wood")
	}
	if got := store.loadCount; got != 1 {
		t.Fatalf("load count = %d, want 1", got)
	}

	frames := recordedFrames(t, client.conn.(*recordingConn))
	if got := len(frames); got != 2 {
		t.Fatalf("frames = %d, want persisted snapshot plus chunk", got)
	}
	snapshot := decodedPacket(t, frames[0]).GetInventorySnapshot()
	if snapshot == nil {
		t.Fatal("first frame inventory snapshot = nil")
	}
	if got := snapshot.GetSelectedSlot(); got != 1 {
		t.Fatalf("snapshot selected slot = %d, want 1", got)
	}
	if got := snapshot.GetSlots()[1].GetCount(); got != 7 {
		t.Fatalf("snapshot slot 1 count = %d, want 7", got)
	}
	if decodedPacket(t, frames[1]).GetChunk() == nil {
		t.Fatal("second frame chunk = nil")
	}
}

func TestHandleClientPacketPositionCreatesPlayerInventoryRecord(t *testing.T) {
	store := newMemoryPlayerInventoryStore()
	server := NewServerWithPlayerInventoryStore(":0", world.NewWorld(nil), store)
	server.chunkEncoding = api.ChunkEncoding_CHUNK_ENCODING_RAW
	client := newClientSession(&recordingConn{})

	packet := &api.Packet{
		Payload: &api.Packet_Position{
			Position: &api.ClientPosition{X: 1, Y: 68, Z: 1, PlayerId: "local_player"},
		},
	}

	if err := server.handleInitialClientPacketForSession(client, packet); err != nil {
		t.Fatalf("handleInitialClientPacketForSession() error = %v", err)
	}
	if got := store.saveCount; got != 1 {
		t.Fatalf("save count = %d, want initial player inventory record", got)
	}
	saved := store.states["local_player"]
	if saved.PlacementPolicy != playerinventory.PlacementPolicyRetain {
		t.Fatalf("saved placement policy = %q, want retain", saved.PlacementPolicy)
	}
	if saved.SelectedSlot != 0 {
		t.Fatalf("saved selected slot = %d, want 0", saved.SelectedSlot)
	}
	if len(saved.Slots) == 0 {
		t.Fatal("saved slots empty")
	}
}

func TestHandleClientPacketPositionCreatesCountedPlayerInventoryRecord(t *testing.T) {
	store := newMemoryPlayerInventoryStore()
	server := NewServerWithPlayerInventoryStore(":0", world.NewWorld(nil), store)
	server.chunkEncoding = api.ChunkEncoding_CHUNK_ENCODING_RAW
	server.inventoryMode = inventoryModeCounted
	client := server.newClientSession(&recordingConn{})

	packet := &api.Packet{
		Payload: &api.Packet_Position{
			Position: &api.ClientPosition{X: 1, Y: 68, Z: 1, PlayerId: "local_player"},
		},
	}

	if err := server.handleInitialClientPacketForSession(client, packet); err != nil {
		t.Fatalf("handleInitialClientPacketForSession() error = %v", err)
	}
	if got := store.saveCount; got != 1 {
		t.Fatalf("save count = %d, want initial counted player inventory record", got)
	}
	saved := store.states["local_player"]
	if saved.PlacementPolicy != playerinventory.PlacementPolicyConsume {
		t.Fatalf("saved placement policy = %q, want consume", saved.PlacementPolicy)
	}
	if len(saved.Slots) == 0 {
		t.Fatal("saved slots empty")
	}
	if got := saved.Slots[0].Count; got != playerinventory.CountedHotbarStackCount {
		t.Fatalf("saved slot 0 count = %d, want %d", got, playerinventory.CountedHotbarStackCount)
	}
}

func TestHandleClientPacketPositionIgnoresInvalidPlayerIDForPersistence(t *testing.T) {
	store := newMemoryPlayerInventoryStore()
	server := NewServerWithPlayerInventoryStore(":0", world.NewWorld(nil), store)
	server.chunkEncoding = api.ChunkEncoding_CHUNK_ENCODING_RAW
	client := newClientSession(&recordingConn{})

	packet := &api.Packet{
		Payload: &api.Packet_Position{
			Position: &api.ClientPosition{X: 1, Y: 68, Z: 1, PlayerId: "../local"},
		},
	}

	if err := server.handleInitialClientPacketForSession(client, packet); err != nil {
		t.Fatalf("handleInitialClientPacketForSession() error = %v", err)
	}
	if store.loadCount != 0 || store.saveCount != 0 {
		t.Fatalf("store load/save = %d/%d, want 0/0", store.loadCount, store.saveCount)
	}
	frames := recordedFrames(t, client.conn.(*recordingConn))
	if got := len(frames); got != 1 {
		t.Fatalf("frames = %d, want chunk only", got)
	}
	if decodedPacket(t, frames[0]).GetChunk() == nil {
		t.Fatal("frame chunk = nil")
	}
}

func TestHandleClientPacketInventoryActionPersistsSelectedSlot(t *testing.T) {
	store := newMemoryPlayerInventoryStore()
	server := NewServerWithPlayerInventoryStore(":0", world.NewWorld(nil), store)
	client := newClientSession(&recordingConn{})
	client.bindPlayerID("local_player")
	client.inventory = playerinventory.NewCounted([]playerinventory.Slot{
		{BlockID: world.Stone, Count: 1},
		{BlockID: world.Wood, Count: 1},
	})

	packet := &api.Packet{
		Payload: &api.Packet_InventoryAction{
			InventoryAction: &api.InventoryAction{
				Action: api.InventoryAction_SELECT_SLOT,
				Slot:   1,
			},
		},
	}

	if err := server.handleClientPacketForSession(client, packet); err != nil {
		t.Fatalf("handleClientPacketForSession() error = %v", err)
	}
	saved := store.states["local_player"]
	if saved.SelectedSlot != 1 {
		t.Fatalf("persisted selected slot = %d, want 1", saved.SelectedSlot)
	}
	if got := store.saveCount; got != 1 {
		t.Fatalf("save count = %d, want 1", got)
	}
}

func TestHandleClientPacketPlacePersistsInventoryAfterCountedPlacement(t *testing.T) {
	store := newMemoryPlayerInventoryStore()
	server := NewServerWithPlayerInventoryStore(":0", world.NewWorld(nil), store)
	server.chunkEncoding = api.ChunkEncoding_CHUNK_ENCODING_RAW
	client := newClientSession(&recordingConn{})
	recordReachableBlockActionPosition(client)
	client.bindPlayerID("local_player")
	client.inventory = playerinventory.NewCounted([]playerinventory.Slot{
		{BlockID: world.Stone, Count: 1},
		{BlockID: world.Wood, Count: 1},
	})

	packet := &api.Packet{
		Payload: &api.Packet_BlockAction{
			BlockAction: &api.BlockAction{
				Action:  api.BlockAction_PLACE,
				X:       1,
				Y:       64,
				Z:       1,
				BlockId: uint32(world.Stone),
			},
		},
	}

	if err := server.handleClientPacketForSession(client, packet); err != nil {
		t.Fatalf("handleClientPacketForSession() error = %v", err)
	}
	saved := store.states["local_player"]
	if len(saved.Slots) != 2 {
		t.Fatalf("persisted slots = %d, want 2", len(saved.Slots))
	}
	if got := saved.Slots[0].Count; got != 0 {
		t.Fatalf("persisted stone count = %d, want 0", got)
	}
	if got := saved.SelectedSlot; got != 1 {
		t.Fatalf("persisted selected slot = %d, want normalized slot 1", got)
	}
}

func TestHandleClientPacketInventoryActionRejectsUnavailableSlot(t *testing.T) {
	server := NewServer(":0", world.NewWorld(nil))
	client := newClientSession(&recordingConn{})
	client.inventory = playerinventory.NewCounted([]playerinventory.Slot{
		{BlockID: world.Stone, Count: 1},
		{BlockID: world.Wood, Count: 0},
	})

	packet := &api.Packet{
		Payload: &api.Packet_InventoryAction{
			InventoryAction: &api.InventoryAction{
				Action: api.InventoryAction_SELECT_SLOT,
				Slot:   1,
			},
		},
	}

	if err := server.handleClientPacketForSession(client, packet); err != nil {
		t.Fatalf("handleClientPacketForSession() error = %v", err)
	}
	if got := client.selectedSlot(); got != 0 {
		t.Fatalf("selected slot = %d, want 0", got)
	}
	frames := recordedFrames(t, client.conn.(*recordingConn))
	if got := len(frames); got != 1 {
		t.Fatalf("frames = %d, want 1", got)
	}
	snapshot := decodedPacket(t, frames[0]).GetInventorySnapshot()
	if snapshot == nil {
		t.Fatal("invalid slot response snapshot = nil")
	}
	if got := snapshot.GetSelectedSlot(); got != 0 {
		t.Fatalf("invalid slot response selected slot = %d, want 0", got)
	}
}

func TestHandleClientPacketPlaceSendsInventorySnapshotAfterCountedPlacement(t *testing.T) {
	server := NewServer(":0", world.NewWorld(nil))
	server.chunkEncoding = api.ChunkEncoding_CHUNK_ENCODING_RAW

	client := newClientSession(&recordingConn{})
	recordReachableBlockActionPosition(client)
	client.inventory = playerinventory.NewCounted([]playerinventory.Slot{
		{BlockID: world.Stone, Count: 1},
		{BlockID: world.Wood, Count: 1},
	})

	packet := &api.Packet{
		Payload: &api.Packet_BlockAction{
			BlockAction: &api.BlockAction{
				Action:  api.BlockAction_PLACE,
				X:       1,
				Y:       64,
				Z:       1,
				BlockId: uint32(world.Stone),
			},
		},
	}

	if err := server.handleClientPacketForSession(client, packet); err != nil {
		t.Fatalf("handleClientPacketForSession() error = %v", err)
	}

	frames := recordedFrames(t, client.conn.(*recordingConn))
	if got := len(frames); got != 2 {
		t.Fatalf("frames = %d, want 2", got)
	}
	if decodedPacket(t, frames[0]).GetChunk() == nil {
		t.Fatal("first frame chunk = nil")
	}
	snapshot := decodedPacket(t, frames[1]).GetInventorySnapshot()
	if snapshot == nil {
		t.Fatal("second frame inventory snapshot = nil")
	}
	if got := snapshot.GetSlots()[0].GetCount(); got != 0 {
		t.Fatalf("stone count after placement = %d, want 0", got)
	}
	if got := snapshot.GetSelectedSlot(); got != 1 {
		t.Fatalf("selected slot after depleted placement = %d, want 1", got)
	}
}

func TestHandleClientPacketDestroyAddsBlockToCountedInventoryAndSendsSnapshot(t *testing.T) {
	server := NewServer(":0", world.NewWorld(nil))
	server.chunkEncoding = api.ChunkEncoding_CHUNK_ENCODING_RAW

	client := newClientSession(&recordingConn{})
	recordReachableStoneDestroyPosition(client)
	client.inventory = playerinventory.NewCounted([]playerinventory.Slot{
		{BlockID: world.Stone, Count: 0},
		{BlockID: world.Wood, Count: 1},
	})

	packet := &api.Packet{
		Payload: &api.Packet_BlockAction{
			BlockAction: &api.BlockAction{
				Action: api.BlockAction_DESTROY,
				X:      1,
				Y:      60,
				Z:      1,
			},
		},
	}

	if err := server.handleClientPacketForSession(client, packet); err != nil {
		t.Fatalf("handleClientPacketForSession() error = %v", err)
	}

	frames := recordedFrames(t, client.conn.(*recordingConn))
	if got := len(frames); got != 2 {
		t.Fatalf("frames = %d, want 2", got)
	}
	if decodedPacket(t, frames[0]).GetChunk() == nil {
		t.Fatal("first frame chunk = nil")
	}
	snapshot := decodedPacket(t, frames[1]).GetInventorySnapshot()
	if snapshot == nil {
		t.Fatal("second frame inventory snapshot = nil")
	}
	if got := snapshot.GetSlots()[0].GetCount(); got != 1 {
		t.Fatalf("stone count after destroy drop = %d, want 1", got)
	}
	if got := snapshot.GetSelectedSlot(); got != 0 {
		t.Fatalf("selected slot after destroy drop = %d, want 0", got)
	}
}

func TestHandleClientPacketDestroyPersistsCollectedCountedDrop(t *testing.T) {
	store := newMemoryPlayerInventoryStore()
	server := NewServerWithPlayerInventoryStore(":0", world.NewWorld(nil), store)
	server.chunkEncoding = api.ChunkEncoding_CHUNK_ENCODING_RAW
	client := newClientSession(&recordingConn{})
	recordReachableStoneDestroyPosition(client)
	client.bindPlayerID("local_player")
	client.inventory = playerinventory.NewCounted([]playerinventory.Slot{
		{BlockID: world.Stone, Count: 0},
		{BlockID: world.Wood, Count: 1},
	})

	packet := &api.Packet{
		Payload: &api.Packet_BlockAction{
			BlockAction: &api.BlockAction{
				Action: api.BlockAction_DESTROY,
				X:      1,
				Y:      60,
				Z:      1,
			},
		},
	}

	if err := server.handleClientPacketForSession(client, packet); err != nil {
		t.Fatalf("handleClientPacketForSession() error = %v", err)
	}

	saved := store.states["local_player"]
	if len(saved.Slots) != 2 {
		t.Fatalf("persisted slots = %d, want 2", len(saved.Slots))
	}
	if got := saved.Slots[0].Count; got != 1 {
		t.Fatalf("persisted stone count after destroy drop = %d, want 1", got)
	}
	if got := store.saveCount; got != 1 {
		t.Fatalf("save count = %d, want 1", got)
	}
}

func TestHandleClientPacketDestroyRejectsMiningCooldown(t *testing.T) {
	server := NewServer(":0", world.NewWorld(nil))
	server.chunkEncoding = api.ChunkEncoding_CHUNK_ENCODING_RAW
	server.miningCooldown = time.Second
	server.miningDurations = miningDurationsForPlaceableBlocks(time.Second)
	now := time.Unix(1000, 0)
	server.now = func() time.Time { return now }

	client := newClientSession(&recordingConn{})
	recordReachableStoneDestroyPosition(client)
	client.inventory = playerinventory.NewCounted([]playerinventory.Slot{
		{BlockID: world.Stone, Count: 0},
	})

	firstDestroy := &api.Packet{
		Payload: &api.Packet_BlockAction{
			BlockAction: &api.BlockAction{
				Action: api.BlockAction_DESTROY,
				X:      1,
				Y:      60,
				Z:      1,
			},
		},
	}
	secondDestroy := &api.Packet{
		Payload: &api.Packet_BlockAction{
			BlockAction: &api.BlockAction{
				Action: api.BlockAction_DESTROY,
				X:      2,
				Y:      60,
				Z:      1,
			},
		},
	}

	if err := server.handleClientPacketForSession(client, firstDestroy); err != nil {
		t.Fatalf("first handleClientPacketForSession() error = %v", err)
	}
	if err := server.handleClientPacketForSession(client, secondDestroy); err != nil {
		t.Fatalf("second handleClientPacketForSession() error = %v", err)
	}

	frames := recordedFrames(t, client.conn.(*recordingConn))
	if got := len(frames); got != 2 {
		t.Fatalf("frames after cooldown rejection = %d, want first destroy chunk and snapshot only", got)
	}
	snapshot := decodedPacket(t, frames[1]).GetInventorySnapshot()
	if snapshot == nil {
		t.Fatal("second frame inventory snapshot = nil")
	}
	if got := snapshot.GetSlots()[0].GetCount(); got != 1 {
		t.Fatalf("stone count after cooldown rejection = %d, want 1", got)
	}
	worldSnapshot, err := server.world.ChunkSnapshot(0, 0)
	if err != nil {
		t.Fatalf("ChunkSnapshot() error = %v", err)
	}
	chunk, err := world.DeserializeChunk(worldSnapshot.X, worldSnapshot.Z, worldSnapshot.Blocks)
	if err != nil {
		t.Fatalf("DeserializeChunk() error = %v", err)
	}
	if got := chunk.GetBlock(2, 60, 1); got != world.Stone {
		t.Fatalf("second block after cooldown rejection = %v, want Stone", got)
	}
}

func TestHandleClientPacketDestroyAllowsAfterMiningCooldown(t *testing.T) {
	server := NewServer(":0", world.NewWorld(nil))
	server.chunkEncoding = api.ChunkEncoding_CHUNK_ENCODING_RAW
	server.miningCooldown = time.Second
	server.miningDurations = miningDurationsForPlaceableBlocks(time.Second)
	now := time.Unix(1000, 0)
	server.now = func() time.Time { return now }

	client := newClientSession(&recordingConn{})
	recordReachableStoneDestroyPosition(client)
	client.inventory = playerinventory.NewCounted([]playerinventory.Slot{
		{BlockID: world.Stone, Count: 0},
	})

	firstDestroy := &api.Packet{
		Payload: &api.Packet_BlockAction{
			BlockAction: &api.BlockAction{
				Action: api.BlockAction_DESTROY,
				X:      1,
				Y:      60,
				Z:      1,
			},
		},
	}
	secondDestroy := &api.Packet{
		Payload: &api.Packet_BlockAction{
			BlockAction: &api.BlockAction{
				Action: api.BlockAction_DESTROY,
				X:      2,
				Y:      60,
				Z:      1,
			},
		},
	}

	if err := server.handleClientPacketForSession(client, firstDestroy); err != nil {
		t.Fatalf("first handleClientPacketForSession() error = %v", err)
	}
	now = now.Add(time.Second)
	if err := server.handleClientPacketForSession(client, secondDestroy); err != nil {
		t.Fatalf("second handleClientPacketForSession() error = %v", err)
	}

	frames := recordedFrames(t, client.conn.(*recordingConn))
	if got := len(frames); got != 4 {
		t.Fatalf("frames after cooldown elapsed = %d, want two destroy chunks and snapshots", got)
	}
	snapshot := decodedPacket(t, frames[3]).GetInventorySnapshot()
	if snapshot == nil {
		t.Fatal("fourth frame inventory snapshot = nil")
	}
	if got := snapshot.GetSlots()[0].GetCount(); got != 2 {
		t.Fatalf("stone count after cooldown elapsed = %d, want 2", got)
	}
}

func TestHandleClientPacketDestroyUsesTargetBlockMiningDuration(t *testing.T) {
	server := NewServer(":0", world.NewWorld(nil))
	server.chunkEncoding = api.ChunkEncoding_CHUNK_ENCODING_RAW
	server.miningDurations = map[world.BlockID]time.Duration{
		world.Stone: time.Second,
		world.Dirt:  100 * time.Millisecond,
	}
	now := time.Unix(1000, 0)
	server.now = func() time.Time { return now }
	if _, err := server.world.SetBlockGlobal(2, 60, 1, world.Dirt); err != nil {
		t.Fatalf("SetBlockGlobal(Dirt) error = %v", err)
	}

	client := newClientSession(&recordingConn{})
	recordReachableStoneDestroyPosition(client)
	client.inventory = playerinventory.NewCounted([]playerinventory.Slot{
		{BlockID: world.Stone, Count: 0},
		{BlockID: world.Dirt, Count: 0},
	})
	destroyPacket := func(x, y, z int32) *api.Packet {
		return &api.Packet{
			Payload: &api.Packet_BlockAction{
				BlockAction: &api.BlockAction{
					Action: api.BlockAction_DESTROY,
					X:      x,
					Y:      y,
					Z:      z,
				},
			},
		}
	}

	if err := server.handleClientPacketForSession(client, destroyPacket(1, 60, 1)); err != nil {
		t.Fatalf("first handleClientPacketForSession() error = %v", err)
	}
	now = now.Add(100 * time.Millisecond)
	if err := server.handleClientPacketForSession(client, destroyPacket(2, 60, 1)); err != nil {
		t.Fatalf("second handleClientPacketForSession() error = %v", err)
	}

	frames := recordedFrames(t, client.conn.(*recordingConn))
	if got := len(frames); got != 4 {
		t.Fatalf("frames after block-specific cooldown elapsed = %d, want two destroy chunks and snapshots", got)
	}
	snapshot := decodedPacket(t, frames[3]).GetInventorySnapshot()
	if snapshot == nil {
		t.Fatal("fourth frame inventory snapshot = nil")
	}
	if got := snapshot.GetSlots()[0].GetCount(); got != 1 {
		t.Fatalf("stone count after block-specific cooldown = %d, want 1", got)
	}
	if got := snapshot.GetSlots()[1].GetCount(); got != 1 {
		t.Fatalf("dirt count after block-specific cooldown = %d, want 1", got)
	}
}

func TestClientSessionStartsWithHandToolSlot(t *testing.T) {
	client := newClientSession(&recordingConn{})

	if got := client.selectedToolID(); got != item.HandToolID {
		t.Fatalf("selectedToolID() = %q, want %q", got, item.HandToolID)
	}

	client.stateMu.Lock()
	client.selectedToolSlot = 1
	client.stateMu.Unlock()
	if got := client.selectedToolID(); got != item.WoodenPickaxeToolID {
		t.Fatalf("selectedToolID() after slot 1 = %q, want %q", got, item.WoodenPickaxeToolID)
	}

	client.stateMu.Lock()
	client.selectedToolSlot = 99
	client.stateMu.Unlock()
	if got := client.selectedToolID(); got != item.HandToolID {
		t.Fatalf("selectedToolID() after invalid slot = %q, want %q", got, item.HandToolID)
	}

	client.stateMu.Lock()
	client.toolbelt = nil
	client.selectedToolSlot = 0
	client.stateMu.Unlock()
	if got := client.selectedToolID(); got != item.HandToolID {
		t.Fatalf("selectedToolID() without toolbelt = %q, want %q", got, item.HandToolID)
	}
}

func TestMiningDurationForBlockWithTool(t *testing.T) {
	server := NewServer(":0", world.NewWorld(nil))
	server.miningDurations = map[world.BlockID]time.Duration{
		world.Stone: 300 * time.Millisecond,
		world.Wood:  250 * time.Millisecond,
		world.Dirt:  150 * time.Millisecond,
	}

	tests := []struct {
		name  string
		block world.BlockID
		tool  item.ID
		want  time.Duration
	}{
		{name: "hand keeps stone duration", block: world.Stone, tool: item.HandToolID, want: 300 * time.Millisecond},
		{name: "pickaxe halves stone duration", block: world.Stone, tool: item.WoodenPickaxeToolID, want: 150 * time.Millisecond},
		{name: "pickaxe does not speed wood", block: world.Wood, tool: item.WoodenPickaxeToolID, want: 250 * time.Millisecond},
		{name: "axe halves wood duration", block: world.Wood, tool: item.WoodenAxeToolID, want: 125 * time.Millisecond},
		{name: "shovel halves dirt duration", block: world.Dirt, tool: item.WoodenShovelToolID, want: 75 * time.Millisecond},
		{name: "air remains instant", block: world.Air, tool: item.WoodenPickaxeToolID, want: 0},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := server.miningDurationForBlockWithTool(tt.block, tt.tool)
			if got != tt.want {
				t.Fatalf("miningDurationForBlockWithTool(%v, %q) = %s, want %s", tt.block, tt.tool, got, tt.want)
			}
		})
	}
}

func TestMiningDurationForBlockWithToolKeepsGlobalOverrideExact(t *testing.T) {
	server := NewServer(":0", world.NewWorld(nil))
	server.miningCooldownOverride = true
	server.miningDurations = map[world.BlockID]time.Duration{
		world.Stone: 300 * time.Millisecond,
	}

	got := server.miningDurationForBlockWithTool(world.Stone, item.WoodenPickaxeToolID)
	if got != 300*time.Millisecond {
		t.Fatalf("miningDurationForBlockWithTool() with override = %s, want 300ms", got)
	}
}

func TestHandleClientPacketDestroyUsesSelectedToolMiningDuration(t *testing.T) {
	server := NewServer(":0", world.NewWorld(nil))
	server.chunkEncoding = api.ChunkEncoding_CHUNK_ENCODING_RAW
	server.miningDurations = map[world.BlockID]time.Duration{
		world.Stone: 300 * time.Millisecond,
	}
	now := time.Unix(1000, 0)
	server.now = func() time.Time { return now }

	client := newClientSession(&recordingConn{})
	recordReachableStoneDestroyPosition(client)
	client.inventory = playerinventory.NewCounted([]playerinventory.Slot{
		{BlockID: world.Stone, Count: 0},
	})
	client.stateMu.Lock()
	client.selectedToolSlot = 1
	client.stateMu.Unlock()

	destroyPacket := func(x, y, z int32) *api.Packet {
		return &api.Packet{
			Payload: &api.Packet_BlockAction{
				BlockAction: &api.BlockAction{
					Action: api.BlockAction_DESTROY,
					X:      x,
					Y:      y,
					Z:      z,
				},
			},
		}
	}

	if err := server.handleClientPacketForSession(client, destroyPacket(1, 60, 1)); err != nil {
		t.Fatalf("first handleClientPacketForSession() error = %v", err)
	}
	now = now.Add(150 * time.Millisecond)
	if err := server.handleClientPacketForSession(client, destroyPacket(2, 60, 1)); err != nil {
		t.Fatalf("second handleClientPacketForSession() error = %v", err)
	}

	frames := recordedFrames(t, client.conn.(*recordingConn))
	if got := len(frames); got != 4 {
		t.Fatalf("frames after tool-adjusted cooldown elapsed = %d, want two destroy chunks and snapshots", got)
	}
	snapshot := decodedPacket(t, frames[3]).GetInventorySnapshot()
	if snapshot == nil {
		t.Fatal("fourth frame inventory snapshot = nil")
	}
	if got := snapshot.GetSlots()[0].GetCount(); got != 2 {
		t.Fatalf("stone count after tool-adjusted cooldown = %d, want 2", got)
	}
}

func TestHandleClientPacketDestroyDoesNotCollectAir(t *testing.T) {
	server := NewServer(":0", world.NewWorld(nil))
	server.chunkEncoding = api.ChunkEncoding_CHUNK_ENCODING_RAW

	client := newClientSession(&recordingConn{})
	recordReachableBlockActionPosition(client)
	client.inventory = playerinventory.NewCounted([]playerinventory.Slot{
		{BlockID: world.Stone, Count: 0},
	})

	packet := &api.Packet{
		Payload: &api.Packet_BlockAction{
			BlockAction: &api.BlockAction{
				Action: api.BlockAction_DESTROY,
				X:      1,
				Y:      64,
				Z:      1,
			},
		},
	}

	if err := server.handleClientPacketForSession(client, packet); err != nil {
		t.Fatalf("handleClientPacketForSession() error = %v", err)
	}

	frames := recordedFrames(t, client.conn.(*recordingConn))
	if got := len(frames); got != 1 {
		t.Fatalf("frames = %d, want chunk only", got)
	}
	if decodedPacket(t, frames[0]).GetChunk() == nil {
		t.Fatal("frame chunk = nil")
	}
	if client.inventory.CanPlaceBlock(world.Stone) {
		t.Fatal("destroying Air added Stone to inventory")
	}
}

func TestHandleClientPacketDestroyDoesNotCollectWhenBlockUpdateFails(t *testing.T) {
	server := NewServer(":0", world.NewWorld(nil))
	client := newClientSession(&recordingConn{})
	recordReachableOutOfRangeYPosition(client)
	client.inventory = playerinventory.NewCounted([]playerinventory.Slot{
		{BlockID: world.Stone, Count: 0},
	})

	packet := &api.Packet{
		Payload: &api.Packet_BlockAction{
			BlockAction: &api.BlockAction{
				Action: api.BlockAction_DESTROY,
				X:      1,
				Y:      int32(world.ChunkHeight),
				Z:      1,
			},
		},
	}

	if err := server.handleClientPacketForSession(client, packet); err == nil {
		t.Fatal("handleClientPacketForSession() error = nil, want block update error")
	}
	if client.inventory.CanPlaceBlock(world.Stone) {
		t.Fatal("failed destroy update added Stone to inventory")
	}
	if got := len(recordedFrames(t, client.conn.(*recordingConn))); got != 0 {
		t.Fatalf("frames = %d, want 0", got)
	}
}

func TestHandleClientPacketRejectsOutOfRangeBlockAction(t *testing.T) {
	server := NewServer(":0", world.NewWorld(nil))
	server.chunkEncoding = api.ChunkEncoding_CHUNK_ENCODING_RAW

	origin := newClientSession(&recordingConn{})
	recordReachableOutOfRangeYPosition(origin)
	watcher := newClientSession(&recordingConn{})
	watcher.streamState.sentChunks[world.ChunkCoord{X: 0, Z: 0}] = true

	server.registerClient(watcher)
	defer server.unregisterClient(watcher)

	packet := &api.Packet{
		Payload: &api.Packet_BlockAction{
			BlockAction: &api.BlockAction{
				Action:  api.BlockAction_PLACE,
				X:       1,
				Y:       int32(world.ChunkHeight),
				Z:       1,
				BlockId: uint32(world.Wood),
			},
		},
	}

	err := server.handleClientPacketForSession(origin, packet)
	if err == nil {
		t.Fatal("handleClientPacketForSession() error = nil, want out-of-range block update error")
	}
	if !strings.Contains(err.Error(), "block y coordinate") {
		t.Fatalf("handleClientPacketForSession() error = %v, want block y coordinate error", err)
	}
	if got := len(recordedFrames(t, origin.conn.(*recordingConn))); got != 0 {
		t.Fatalf("origin frames = %d, want 0", got)
	}
	if got := len(recordedFrames(t, watcher.conn.(*recordingConn))); got != 0 {
		t.Fatalf("watcher frames = %d, want 0", got)
	}
}

func TestHandleClientPacketBroadcastsBlockUpdateToInterestedClients(t *testing.T) {
	server := NewServer(":0", world.NewWorld(nil))
	server.chunkEncoding = api.ChunkEncoding_CHUNK_ENCODING_RAW

	origin := newClientSession(&recordingConn{})
	recordReachableBlockActionPosition(origin)
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
	originFrames := recordedFrames(t, originConn)
	if got := len(originFrames); got != 2 {
		t.Fatalf("origin frames = %d, want 2", got)
	}
	if decodedPacket(t, originFrames[0]).GetChunk() == nil {
		t.Fatal("origin first frame chunk = nil")
	}
	if decodedPacket(t, originFrames[1]).GetInventorySnapshot() == nil {
		t.Fatal("origin second frame inventory snapshot = nil")
	}
	watcherFrames := recordedFrames(t, watcherConn)
	if got := len(watcherFrames); got != 1 {
		t.Fatalf("watcher frames = %d, want 1", got)
	}
	if got := len(recordedFrames(t, uninterestedConn)); got != 0 {
		t.Fatalf("uninterested frames = %d, want 0", got)
	}

	decoded := decodedPacket(t, watcherFrames[0])
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

func TestHandleClientPacketConflictingBlockActionsUseLastWriteSnapshot(t *testing.T) {
	server := NewServer(":0", world.NewWorld(nil))
	server.chunkEncoding = api.ChunkEncoding_CHUNK_ENCODING_RAW

	first := newClientSession(&recordingConn{})
	recordReachableBlockActionPosition(first)
	second := newClientSession(&recordingConn{})
	recordReachableBlockActionPosition(second)
	coord := world.ChunkCoord{X: 0, Z: 0}
	first.streamState.sentChunks[coord] = true
	second.streamState.sentChunks[coord] = true

	server.registerClient(first)
	server.registerClient(second)
	defer server.unregisterClient(first)
	defer server.unregisterClient(second)

	sendPlace := func(client *clientSession, block world.BlockID) {
		t.Helper()
		packet := &api.Packet{
			Payload: &api.Packet_BlockAction{
				BlockAction: &api.BlockAction{
					Action:  api.BlockAction_PLACE,
					X:       1,
					Y:       64,
					Z:       1,
					BlockId: uint32(block),
				},
			},
		}
		if err := server.handleClientPacketForSession(client, packet); err != nil {
			t.Fatalf("handleClientPacketForSession(block=%d) error = %v", block, err)
		}
	}
	blockInFrame := func(label string, frame []byte) (world.BlockID, bool) {
		t.Helper()
		decoded := decodedPacket(t, frame)
		chunkData := decoded.GetChunk()
		if chunkData == nil {
			return world.Air, false
		}
		chunk, err := world.DeserializeChunk(chunkData.GetX(), chunkData.GetZ(), chunkData.GetBlocks())
		if err != nil {
			t.Fatalf("DeserializeChunk(%s frame) error = %v", label, err)
		}
		return chunk.GetBlock(1, 64, 1), true
	}
	latestBlockInFrames := func(label string, frames [][]byte) world.BlockID {
		t.Helper()
		var block world.BlockID
		found := false
		for index, frame := range frames {
			if frameBlock, ok := blockInFrame(fmt.Sprintf("%s[%d]", label, index), frame); ok {
				block = frameBlock
				found = true
			}
		}
		if !found {
			t.Fatalf("%s frames include no chunk frames", label)
		}
		return block
	}

	sendPlace(first, world.Wood)
	sendPlace(second, world.Stone)

	firstFrames := recordedFrames(t, first.conn.(*recordingConn))
	secondFrames := recordedFrames(t, second.conn.(*recordingConn))
	if got := len(firstFrames); got != 3 {
		t.Fatalf("first frames = %d, want 3", got)
	}
	if got := len(secondFrames); got != 3 {
		t.Fatalf("second frames = %d, want 3", got)
	}
	if got := latestBlockInFrames("first", firstFrames); got != world.Stone {
		t.Fatalf("first latest block = %v, want Stone", got)
	}
	if got := latestBlockInFrames("second", secondFrames); got != world.Stone {
		t.Fatalf("second latest block = %v, want Stone", got)
	}

	snapshot, err := server.world.ChunkSnapshot(0, 0)
	if err != nil {
		t.Fatalf("ChunkSnapshot() error = %v", err)
	}
	chunk, err := world.DeserializeChunk(snapshot.X, snapshot.Z, snapshot.Blocks)
	if err != nil {
		t.Fatalf("DeserializeChunk(authoritative snapshot) error = %v", err)
	}
	if got := chunk.GetBlock(1, 64, 1); got != world.Stone {
		t.Fatalf("authoritative block = %v, want Stone", got)
	}
}

func TestBroadcastDisconnectsFailedInterestedClient(t *testing.T) {
	server := NewServer(":0", world.NewWorld(nil))
	server.chunkEncoding = api.ChunkEncoding_CHUNK_ENCODING_RAW

	origin := newClientSession(&recordingConn{})
	recordReachableBlockActionPosition(origin)
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

func decodedPacket(t *testing.T, frame []byte) *api.Packet {
	t.Helper()

	decoded := &api.Packet{}
	if err := proto.Unmarshal(frame, decoded); err != nil {
		t.Fatalf("unmarshal frame: %v", err)
	}
	return decoded
}

func recordReachableBlockActionPosition(client *clientSession) {
	client.recordPosition(&api.ClientPosition{X: 1.5, Y: 68, Z: 1.5})
}

func recordReachableStoneDestroyPosition(client *clientSession) {
	client.recordPosition(&api.ClientPosition{X: 1.5, Y: 65.5, Z: 1.5})
}

func recordReachableOutOfRangeYPosition(client *clientSession) {
	client.recordPosition(&api.ClientPosition{X: 1.5, Y: float32(world.ChunkHeight) + 0.5, Z: 1.5})
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

type memoryPlayerInventoryStore struct {
	states    map[string]playerinventory.State
	loadCount int
	saveCount int
}

func newMemoryPlayerInventoryStore() *memoryPlayerInventoryStore {
	return &memoryPlayerInventoryStore{
		states: make(map[string]playerinventory.State),
	}
}

func (s *memoryPlayerInventoryStore) LoadPlayerInventory(playerID string) (playerinventory.State, bool, error) {
	s.loadCount++
	state, ok := s.states[playerID]
	if !ok {
		return playerinventory.State{}, false, nil
	}
	return cloneInventoryState(state), true, nil
}

func (s *memoryPlayerInventoryStore) SavePlayerInventory(playerID string, state playerinventory.State) error {
	s.saveCount++
	s.states[playerID] = cloneInventoryState(state)
	return nil
}

func cloneInventoryState(state playerinventory.State) playerinventory.State {
	return playerinventory.State{
		Slots:           append([]playerinventory.Slot(nil), state.Slots...),
		PlacementPolicy: state.PlacementPolicy,
		SelectedSlot:    state.SelectedSlot,
	}
}
