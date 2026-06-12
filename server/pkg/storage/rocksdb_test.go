package storage

import (
	"bytes"
	"testing"

	"rumpelmc/server/pkg/world"
)

func TestChunkKeyFormatIsStable(t *testing.T) {
	got := chunkKey(0, 0)
	want := []byte{'c', 0x80, 0x00, 0x00, 0x00, 0x80, 0x00, 0x00, 0x00}
	if !bytes.Equal(got, want) {
		t.Fatalf("chunkKey(0, 0) = % x, want % x", got, want)
	}
}

func TestChunkKeysSortBySignedCoordinates(t *testing.T) {
	keys := [][]byte{
		chunkKey(-2, 0),
		chunkKey(-1, 0),
		chunkKey(0, 0),
		chunkKey(1, 0),
		chunkKey(2, 0),
	}

	for i := 1; i < len(keys); i++ {
		if bytes.Compare(keys[i-1], keys[i]) >= 0 {
			t.Fatalf("key %d should sort before key %d", i-1, i)
		}
	}
}

func TestRocksChunkStoreRoundTrip(t *testing.T) {
	path := t.TempDir()

	store, err := OpenRocksChunkStore(path)
	if err != nil {
		t.Fatalf("OpenRocksChunkStore() error = %v", err)
	}

	chunk := world.NewChunk(-2, 3)
	chunk.SetBlock(4, 63, 5, world.Grass)
	chunk.SetBlock(6, 12, 7, world.Leaves)
	if err := store.SaveChunk(chunk); err != nil {
		t.Fatalf("SaveChunk() error = %v", err)
	}
	store.Close()

	store, err = OpenRocksChunkStore(path)
	if err != nil {
		t.Fatalf("reopen OpenRocksChunkStore() error = %v", err)
	}
	defer store.Close()

	loaded, ok, err := store.LoadChunk(-2, 3)
	if err != nil {
		t.Fatalf("LoadChunk() error = %v", err)
	}
	if !ok {
		t.Fatal("LoadChunk() ok = false")
	}
	if loaded.X != -2 || loaded.Z != 3 {
		t.Fatalf("loaded chunk coord = %d,%d, want -2,3", loaded.X, loaded.Z)
	}
	if got := loaded.GetBlock(4, 63, 5); got != world.Grass {
		t.Fatalf("Grass block = %d, want %d", got, world.Grass)
	}
	if got := loaded.GetBlock(6, 12, 7); got != world.Leaves {
		t.Fatalf("Leaves block = %d, want %d", got, world.Leaves)
	}
}
