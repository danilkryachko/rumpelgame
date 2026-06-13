package network

import (
	"testing"

	"rumpelmc/server/pkg/api"
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

	batch.add(chunkSendStats{rawBytes: 10, wireBytes: 12})
	batch.add(chunkSendStats{rawBytes: 20, wireBytes: 24})

	if batch.chunks != 2 || batch.rawBytes != 30 || batch.wireBytes != 36 {
		t.Fatalf("batch stats = chunks:%d raw:%d wire:%d, want chunks:2 raw:30 wire:36", batch.chunks, batch.rawBytes, batch.wireBytes)
	}
}
