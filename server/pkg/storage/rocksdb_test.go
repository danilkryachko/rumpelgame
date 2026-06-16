package storage

import (
	"bytes"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"
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

func TestRocksChunkStoreMissingChunkReturnsNotFound(t *testing.T) {
	store, err := OpenRocksChunkStore(t.TempDir())
	if err != nil {
		t.Fatalf("OpenRocksChunkStore() error = %v", err)
	}
	defer store.Close()

	loaded, ok, err := store.LoadChunk(99, -100)
	if err != nil {
		t.Fatalf("LoadChunk() error = %v", err)
	}
	if ok {
		t.Fatal("LoadChunk() ok = true, want false for missing chunk")
	}
	if loaded != nil {
		t.Fatalf("LoadChunk() loaded = %v, want nil for missing chunk", loaded)
	}
}

func TestOpenRocksChunkStoreCreatesMissingParentDirectory(t *testing.T) {
	path := filepath.Join(t.TempDir(), "missing-parent", "chunks.rocksdb")

	store, err := OpenRocksChunkStore(path)
	if err != nil {
		t.Fatalf("OpenRocksChunkStore() error = %v", err)
	}
	defer store.Close()

	if info, err := os.Stat(filepath.Dir(path)); err != nil {
		t.Fatalf("parent directory stat error = %v", err)
	} else if !info.IsDir() {
		t.Fatalf("parent path is not a directory")
	}
	if info, err := os.Stat(path); err != nil {
		t.Fatalf("rocksdb path stat error = %v", err)
	} else if !info.IsDir() {
		t.Fatalf("rocksdb path is not a directory")
	}
}

func TestOpenRocksChunkStoreRejectsFilePath(t *testing.T) {
	path := filepath.Join(t.TempDir(), "chunks.rocksdb")
	if err := os.WriteFile(path, []byte("not a rocksdb directory"), 0o644); err != nil {
		t.Fatalf("WriteFile() error = %v", err)
	}

	store, err := OpenRocksChunkStore(path)
	if err == nil {
		if store != nil {
			store.Close()
		}
		t.Fatal("OpenRocksChunkStore() error = nil, want failure for file path")
	}
	if store != nil {
		store.Close()
		t.Fatalf("OpenRocksChunkStore() store = %v, want nil on failure", store)
	}
	if !strings.Contains(err.Error(), "open RocksDB chunk store") {
		t.Fatalf("OpenRocksChunkStore() error = %q, want open context", err)
	}
	if !strings.Contains(err.Error(), path) {
		t.Fatalf("OpenRocksChunkStore() error = %q, want path %q", err, path)
	}
}

func TestRocksChunkStoreOverwriteKeepsNeighborChunk(t *testing.T) {
	path := t.TempDir()

	store, err := OpenRocksChunkStore(path)
	if err != nil {
		t.Fatalf("OpenRocksChunkStore() error = %v", err)
	}

	first := world.NewChunk(1, 1)
	first.SetBlock(1, 1, 1, world.Stone)
	if err := store.SaveChunk(first); err != nil {
		t.Fatalf("SaveChunk(first) error = %v", err)
	}
	neighbor := world.NewChunk(1, 2)
	neighbor.SetBlock(2, 2, 2, world.Leaves)
	if err := store.SaveChunk(neighbor); err != nil {
		t.Fatalf("SaveChunk(neighbor) error = %v", err)
	}
	overwrite := world.NewChunk(1, 1)
	overwrite.SetBlock(1, 1, 1, world.Dirt)
	overwrite.SetBlock(3, 3, 3, world.Wood)
	if err := store.SaveChunk(overwrite); err != nil {
		t.Fatalf("SaveChunk(overwrite) error = %v", err)
	}
	store.Close()

	store, err = OpenRocksChunkStore(path)
	if err != nil {
		t.Fatalf("reopen OpenRocksChunkStore() error = %v", err)
	}
	defer store.Close()

	loaded, ok, err := store.LoadChunk(1, 1)
	if err != nil {
		t.Fatalf("LoadChunk(1,1) error = %v", err)
	}
	if !ok {
		t.Fatal("LoadChunk(1,1) ok = false")
	}
	if got := loaded.GetBlock(1, 1, 1); got != world.Dirt {
		t.Fatalf("overwritten block = %d, want %d", got, world.Dirt)
	}
	if got := loaded.GetBlock(3, 3, 3); got != world.Wood {
		t.Fatalf("new overwritten block = %d, want %d", got, world.Wood)
	}

	loadedNeighbor, ok, err := store.LoadChunk(1, 2)
	if err != nil {
		t.Fatalf("LoadChunk(1,2) error = %v", err)
	}
	if !ok {
		t.Fatal("LoadChunk(1,2) ok = false")
	}
	if got := loadedNeighbor.GetBlock(2, 2, 2); got != world.Leaves {
		t.Fatalf("neighbor block = %d, want %d", got, world.Leaves)
	}
}

func TestRocksChunkStoreConcurrentSaveLoadDistinctChunks(t *testing.T) {
	store, err := OpenRocksChunkStore(t.TempDir())
	if err != nil {
		t.Fatalf("OpenRocksChunkStore() error = %v", err)
	}
	defer store.Close()

	type expectedChunk struct {
		x, z              int32
		localX, y, localZ int
		block             world.BlockID
	}
	blocks := []world.BlockID{world.Stone, world.Dirt, world.Grass, world.Wood, world.Leaves}
	expected := make([]expectedChunk, 12)
	for i := range expected {
		expected[i] = expectedChunk{
			x:      int32(i - len(expected)/2),
			z:      int32(i*3 - 11),
			localX: i % world.ChunkWidth,
			y:      (i * 7) % world.ChunkHeight,
			localZ: (i * 5) % world.ChunkDepth,
			block:  blocks[i%len(blocks)],
		}
	}

	start := make(chan struct{})
	errs := make(chan error, len(expected))
	var wg sync.WaitGroup
	for _, want := range expected {
		want := want
		wg.Add(1)
		go func() {
			defer wg.Done()
			<-start

			chunk := world.NewChunk(want.x, want.z)
			chunk.SetBlock(want.localX, want.y, want.localZ, want.block)
			if err := store.SaveChunk(chunk); err != nil {
				errs <- fmt.Errorf("SaveChunk(%d,%d): %w", want.x, want.z, err)
				return
			}

			loaded, ok, err := store.LoadChunk(want.x, want.z)
			if err != nil {
				errs <- fmt.Errorf("LoadChunk(%d,%d): %w", want.x, want.z, err)
				return
			}
			if !ok {
				errs <- fmt.Errorf("LoadChunk(%d,%d) ok = false", want.x, want.z)
				return
			}
			if got := loaded.GetBlock(want.localX, want.y, want.localZ); got != want.block {
				errs <- fmt.Errorf("concurrent block at chunk %d,%d = %d, want %d", want.x, want.z, got, want.block)
			}
		}()
	}

	close(start)
	wg.Wait()
	close(errs)
	for err := range errs {
		if err != nil {
			t.Error(err)
		}
	}
	if t.Failed() {
		return
	}

	for _, want := range expected {
		loaded, ok, err := store.LoadChunk(want.x, want.z)
		if err != nil {
			t.Fatalf("final LoadChunk(%d,%d) error = %v", want.x, want.z, err)
		}
		if !ok {
			t.Fatalf("final LoadChunk(%d,%d) ok = false", want.x, want.z)
		}
		if got := loaded.GetBlock(want.localX, want.y, want.localZ); got != want.block {
			t.Fatalf("final block at chunk %d,%d = %d, want %d", want.x, want.z, got, want.block)
		}
	}
}

func TestRocksChunkStoreRejectsCorruptChunkPayload(t *testing.T) {
	store, err := OpenRocksChunkStore(t.TempDir())
	if err != nil {
		t.Fatalf("OpenRocksChunkStore() error = %v", err)
	}
	defer store.Close()

	putRawChunkPayload(t, store, 4, -5, []byte{0x01, 0x02, 0x03})

	loaded, ok, err := store.LoadChunk(4, -5)
	if err == nil {
		t.Fatal("LoadChunk() error = nil, want corrupt payload error")
	}
	if !strings.Contains(err.Error(), "decode RocksDB chunk 4,-5") {
		t.Fatalf("LoadChunk() error = %q, want chunk decode context", err)
	}
	if ok {
		t.Fatal("LoadChunk() ok = true, want false for corrupt payload")
	}
	if loaded != nil {
		t.Fatalf("LoadChunk() loaded = %v, want nil for corrupt payload", loaded)
	}
}

func putRawChunkPayload(t *testing.T, store *RocksChunkStore, x, z int32, data []byte) {
	t.Helper()

	key := chunkKey(x, z)
	if err := store.putChunkData(key, data); err != nil {
		t.Fatal(err)
	}
}
