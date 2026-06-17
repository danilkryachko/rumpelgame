package storage

import (
	"bytes"
	"errors"
	"fmt"
	"math"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"

	playerinventory "rumpelmc/server/pkg/inventory"
	"rumpelmc/server/pkg/itementity"
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

func TestOpenRocksChunkStoreRejectsFileParentPath(t *testing.T) {
	parent := filepath.Join(t.TempDir(), "not-a-directory")
	if err := os.WriteFile(parent, []byte("not a directory"), 0o644); err != nil {
		t.Fatalf("WriteFile() error = %v", err)
	}
	path := filepath.Join(parent, "chunks.rocksdb")

	store, err := OpenRocksChunkStore(path)
	if err == nil {
		if store != nil {
			store.Close()
		}
		t.Fatal("OpenRocksChunkStore() error = nil, want failure for file parent path")
	}
	if store != nil {
		store.Close()
		t.Fatalf("OpenRocksChunkStore() store = %v, want nil on failure", store)
	}
	if !strings.Contains(err.Error(), "create RocksDB parent directory") {
		t.Fatalf("OpenRocksChunkStore() error = %q, want parent directory context", err)
	}
	if !strings.Contains(err.Error(), parent) {
		t.Fatalf("OpenRocksChunkStore() error = %q, want parent path %q", err, parent)
	}
}

func TestOpenRocksChunkStoreRejectsEmptyPathBeforeCAPI(t *testing.T) {
	store, err := OpenRocksChunkStore("")
	if err == nil {
		if store != nil {
			store.Close()
		}
		t.Fatal("OpenRocksChunkStore() error = nil, want failure for empty path")
	}
	if store != nil {
		store.Close()
		t.Fatalf("OpenRocksChunkStore() store = %v, want nil on failure", store)
	}
	if !errors.Is(err, errEmptyRocksStorePath) {
		t.Fatalf("OpenRocksChunkStore() error = %v, want empty path error", err)
	}
	if !strings.Contains(err.Error(), "open RocksDB chunk store") {
		t.Fatalf("OpenRocksChunkStore() error = %q, want open context", err)
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

func TestRocksChunkStoreRejectsOperationsAfterClose(t *testing.T) {
	store, err := OpenRocksChunkStore(t.TempDir())
	if err != nil {
		t.Fatalf("OpenRocksChunkStore() error = %v", err)
	}

	store.Close()
	store.Close()

	if _, ok, err := store.LoadChunk(0, 0); !errors.Is(err, errRocksChunkStoreClosed) {
		t.Fatalf("LoadChunk() error = %v, want closed store error", err)
	} else if ok {
		t.Fatal("LoadChunk() ok = true, want false for closed store")
	}

	if err := store.SaveChunk(world.NewChunk(0, 0)); !errors.Is(err, errRocksChunkStoreClosed) {
		t.Fatalf("SaveChunk() error = %v, want closed store error", err)
	} else if !strings.Contains(err.Error(), "save RocksDB chunk 0,0") {
		t.Fatalf("SaveChunk() error = %q, want chunk context", err)
	}
}

func TestRocksChunkStoreRejectsNilChunkSave(t *testing.T) {
	store, err := OpenRocksChunkStore(t.TempDir())
	if err != nil {
		t.Fatalf("OpenRocksChunkStore() error = %v", err)
	}
	defer store.Close()

	if err := store.SaveChunk(nil); !errors.Is(err, errNilRocksChunk) {
		t.Fatalf("SaveChunk(nil) error = %v, want nil chunk error", err)
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

func TestRocksChunkStorePlayerInventoryRoundTrip(t *testing.T) {
	path := t.TempDir()

	store, err := OpenRocksChunkStore(path)
	if err != nil {
		t.Fatalf("OpenRocksChunkStore() error = %v", err)
	}

	state := playerinventory.State{
		Slots: []playerinventory.Slot{
			{BlockID: world.Stone, Count: 12},
			{BlockID: world.Wood, Count: 3},
		},
		PlacementPolicy: playerinventory.PlacementPolicyConsume,
		SelectedSlot:    1,
	}
	if err := store.SavePlayerInventory("local_player", state); err != nil {
		t.Fatalf("SavePlayerInventory() error = %v", err)
	}
	store.Close()

	store, err = OpenRocksChunkStore(path)
	if err != nil {
		t.Fatalf("reopen OpenRocksChunkStore() error = %v", err)
	}
	defer store.Close()

	loaded, ok, err := store.LoadPlayerInventory("local_player")
	if err != nil {
		t.Fatalf("LoadPlayerInventory() error = %v", err)
	}
	if !ok {
		t.Fatal("LoadPlayerInventory() ok = false")
	}
	if loaded.SelectedSlot != 1 {
		t.Fatalf("selected slot = %d, want 1", loaded.SelectedSlot)
	}
	if loaded.PlacementPolicy != playerinventory.PlacementPolicyConsume {
		t.Fatalf("placement policy = %q, want %q", loaded.PlacementPolicy, playerinventory.PlacementPolicyConsume)
	}
	if len(loaded.Slots) != 2 {
		t.Fatalf("loaded slots = %d, want 2", len(loaded.Slots))
	}
	if loaded.Slots[0] != (playerinventory.Slot{BlockID: world.Stone, Count: 12}) {
		t.Fatalf("slot 0 = %+v, want Stone x12", loaded.Slots[0])
	}
	if loaded.Slots[1] != (playerinventory.Slot{BlockID: world.Wood, Count: 3}) {
		t.Fatalf("slot 1 = %+v, want Wood x3", loaded.Slots[1])
	}
}

func TestRocksChunkStorePlayerInventoryKeyIsSeparateFromChunkKey(t *testing.T) {
	playerKey, err := playerInventoryKey("local_player")
	if err != nil {
		t.Fatalf("playerInventoryKey() error = %v", err)
	}
	chunkKey := chunkKey(0, 0)

	if bytes.Equal(playerKey, chunkKey) {
		t.Fatalf("player inventory key % x matches chunk key % x", playerKey, chunkKey)
	}
	if playerKey[0] != 'p' || playerKey[1] != 'i' || playerKey[2] != 0 {
		t.Fatalf("player inventory key prefix = % x, want 70 69 00", playerKey[:3])
	}
}

func TestRocksChunkStorePlayerInventoryRejectsCorruptPayload(t *testing.T) {
	store, err := OpenRocksChunkStore(t.TempDir())
	if err != nil {
		t.Fatalf("OpenRocksChunkStore() error = %v", err)
	}
	defer store.Close()

	key, err := playerInventoryKey("local_player")
	if err != nil {
		t.Fatalf("playerInventoryKey() error = %v", err)
	}
	if err := store.putData(key, []byte(`{"version":99,"slots":[]}`)); err != nil {
		t.Fatal(err)
	}

	loaded, ok, err := store.LoadPlayerInventory("local_player")
	if err == nil {
		t.Fatal("LoadPlayerInventory() error = nil, want corrupt payload error")
	}
	if !strings.Contains(err.Error(), `decode RocksDB player inventory "local_player"`) {
		t.Fatalf("LoadPlayerInventory() error = %q, want decode context", err)
	}
	if ok {
		t.Fatal("LoadPlayerInventory() ok = true, want false for corrupt payload")
	}
	if len(loaded.Slots) != 0 {
		t.Fatalf("LoadPlayerInventory() loaded = %+v, want zero state", loaded)
	}
}

func TestRocksChunkStorePlayerInventoryRejectsEmptyID(t *testing.T) {
	store, err := OpenRocksChunkStore(t.TempDir())
	if err != nil {
		t.Fatalf("OpenRocksChunkStore() error = %v", err)
	}
	defer store.Close()

	inventory := playerinventory.NewCreativeHotbar()
	if err := store.SavePlayerInventory("", inventory.State(0)); !errors.Is(err, errEmptyPlayerInventoryID) {
		t.Fatalf("SavePlayerInventory(empty) error = %v, want empty id error", err)
	}
	if _, ok, err := store.LoadPlayerInventory(""); !errors.Is(err, errEmptyPlayerInventoryID) {
		t.Fatalf("LoadPlayerInventory(empty) error = %v, want empty id error", err)
	} else if ok {
		t.Fatal("LoadPlayerInventory(empty) ok = true, want false")
	}
}

func TestRocksChunkStoreItemEntitiesRoundTrip(t *testing.T) {
	path := t.TempDir()

	store, err := OpenRocksChunkStore(path)
	if err != nil {
		t.Fatalf("OpenRocksChunkStore() error = %v", err)
	}

	state := itementity.State{
		NextEntityID: 9,
		Revision:     3,
		Entities: []itementity.Entity{
			{EntityID: 8, ItemID: "block:wood", Count: 2, X: 4.5, Y: 65.5, Z: -2.5},
			{EntityID: 2, ItemID: "block:stone", Count: 1, X: 1.5, Y: 60.5, Z: 1.5},
		},
	}
	if err := store.SaveItemEntities(state); err != nil {
		t.Fatalf("SaveItemEntities() error = %v", err)
	}
	store.Close()

	store, err = OpenRocksChunkStore(path)
	if err != nil {
		t.Fatalf("reopen OpenRocksChunkStore() error = %v", err)
	}
	defer store.Close()

	loaded, ok, err := store.LoadItemEntities()
	if err != nil {
		t.Fatalf("LoadItemEntities() error = %v", err)
	}
	if !ok {
		t.Fatal("LoadItemEntities() ok = false")
	}
	if loaded.NextEntityID != 9 {
		t.Fatalf("next entity id = %d, want 9", loaded.NextEntityID)
	}
	if loaded.Revision != 3 {
		t.Fatalf("revision = %d, want 3", loaded.Revision)
	}
	if len(loaded.Entities) != 2 {
		t.Fatalf("loaded entities = %d, want 2", len(loaded.Entities))
	}
	if loaded.Entities[0] != (itementity.Entity{EntityID: 2, ItemID: "block:stone", Count: 1, X: 1.5, Y: 60.5, Z: 1.5}) {
		t.Fatalf("entity 0 = %+v, want sorted Stone drop", loaded.Entities[0])
	}
	if loaded.Entities[1] != (itementity.Entity{EntityID: 8, ItemID: "block:wood", Count: 2, X: 4.5, Y: 65.5, Z: -2.5}) {
		t.Fatalf("entity 1 = %+v, want sorted Wood drop", loaded.Entities[1])
	}
}

func TestRocksChunkStoreItemEntitiesKeyIsSeparateFromChunkAndPlayerInventoryKey(t *testing.T) {
	itemKey := itemEntitiesKey()
	chunkKey := chunkKey(0, 0)
	playerKey, err := playerInventoryKey("local_player")
	if err != nil {
		t.Fatalf("playerInventoryKey() error = %v", err)
	}

	if bytes.Equal(itemKey, chunkKey) {
		t.Fatalf("item entity key % x matches chunk key % x", itemKey, chunkKey)
	}
	if bytes.Equal(itemKey, playerKey) {
		t.Fatalf("item entity key % x matches player key % x", itemKey, playerKey)
	}
	if !bytes.Equal(itemKey, []byte{'i', 'e', 0}) {
		t.Fatalf("item entity key prefix = % x, want 69 65 00", itemKey)
	}
}

func TestRocksChunkStoreItemEntitiesRejectsCorruptPayload(t *testing.T) {
	store, err := OpenRocksChunkStore(t.TempDir())
	if err != nil {
		t.Fatalf("OpenRocksChunkStore() error = %v", err)
	}
	defer store.Close()

	if err := store.putData(itemEntitiesKey(), []byte(`{"version":99,"entities":[]}`)); err != nil {
		t.Fatal(err)
	}

	loaded, ok, err := store.LoadItemEntities()
	if err == nil {
		t.Fatal("LoadItemEntities() error = nil, want corrupt payload error")
	}
	if !strings.Contains(err.Error(), "decode RocksDB item entities") {
		t.Fatalf("LoadItemEntities() error = %q, want decode context", err)
	}
	if ok {
		t.Fatal("LoadItemEntities() ok = true, want false for corrupt payload")
	}
	if len(loaded.Entities) != 0 {
		t.Fatalf("LoadItemEntities() loaded = %+v, want zero state", loaded)
	}
}

func TestRocksChunkStoreItemEntitiesRejectsInvalidRecords(t *testing.T) {
	store, err := OpenRocksChunkStore(t.TempDir())
	if err != nil {
		t.Fatalf("OpenRocksChunkStore() error = %v", err)
	}
	defer store.Close()

	tests := []struct {
		name  string
		state itementity.State
	}{
		{
			name: "duplicate entity id",
			state: itementity.State{
				NextEntityID: 3,
				Entities: []itementity.Entity{
					{EntityID: 1, ItemID: "block:stone", Count: 1, X: 1, Y: 2, Z: 3},
					{EntityID: 1, ItemID: "block:wood", Count: 1, X: 1, Y: 2, Z: 3},
				},
			},
		},
		{
			name: "non-finite position",
			state: itementity.State{
				NextEntityID: 2,
				Entities: []itementity.Entity{
					{EntityID: 1, ItemID: "block:stone", Count: 1, X: math.Inf(1), Y: 2, Z: 3},
				},
			},
		},
		{
			name: "next id not above max",
			state: itementity.State{
				NextEntityID: 1,
				Entities: []itementity.Entity{
					{EntityID: 1, ItemID: "block:stone", Count: 1, X: 1, Y: 2, Z: 3},
				},
			},
		},
		{
			name: "zero count",
			state: itementity.State{
				NextEntityID: 2,
				Entities: []itementity.Entity{
					{EntityID: 1, ItemID: "block:stone", Count: 0, X: 1, Y: 2, Z: 3},
				},
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if err := store.SaveItemEntities(tt.state); err == nil {
				t.Fatal("SaveItemEntities() error = nil, want invalid record error")
			}
		})
	}
}

func putRawChunkPayload(t *testing.T, store *RocksChunkStore, x, z int32, data []byte) {
	t.Helper()

	key := chunkKey(x, z)
	if err := store.putData(key, data); err != nil {
		t.Fatal(err)
	}
}
