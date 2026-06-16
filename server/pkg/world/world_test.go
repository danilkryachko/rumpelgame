package world

import (
	"bytes"
	"testing"
)

func TestChunksAroundUsesCircularRadius(t *testing.T) {
	w := NewWorld(nil)

	alreadySent := map[ChunkCoord]bool{}
	chunks, err := w.ChunksAround(0, 0, 2, alreadySent, 32)
	if err != nil {
		t.Fatalf("ChunksAround() error = %v", err)
	}

	coords := map[ChunkCoord]bool{}
	for _, chunk := range chunks {
		coord := ChunkCoord{X: chunk.X, Z: chunk.Z}
		coords[coord] = true
		if !ChunkWithinRadius(coord, 0, 0, 2) {
			t.Fatalf("ChunksAround() returned out-of-radius coord %+v", coord)
		}
	}

	if !coords[ChunkCoord{X: 2, Z: 0}] {
		t.Fatal("ChunksAround() missing edge coord 2,0")
	}
	if coords[ChunkCoord{X: 2, Z: 2}] {
		t.Fatal("ChunksAround() included square corner 2,2")
	}
}

func TestChunksAroundOrderedKeepsCurrentChunkFirst(t *testing.T) {
	w := NewWorld(nil)

	chunks, err := w.ChunksAroundOrdered(0, 0, 1, map[ChunkCoord]bool{}, 1, ChunkOrder{DirectionX: 1})
	if err != nil {
		t.Fatalf("ChunksAroundOrdered() error = %v", err)
	}
	if len(chunks) != 1 {
		t.Fatalf("ChunksAroundOrdered() returned %d chunks, want 1", len(chunks))
	}
	if got := (ChunkCoord{X: chunks[0].X, Z: chunks[0].Z}); got != (ChunkCoord{X: 0, Z: 0}) {
		t.Fatalf("first chunk = %+v, want current chunk", got)
	}
}

func TestChunksAroundOrderedUsesDirectionTieBreak(t *testing.T) {
	w := NewWorld(nil)

	alreadySent := map[ChunkCoord]bool{{X: 0, Z: 0}: true}
	chunks, err := w.ChunksAroundOrdered(0, 0, 1, alreadySent, 1, ChunkOrder{DirectionX: 1})
	if err != nil {
		t.Fatalf("ChunksAroundOrdered() error = %v", err)
	}
	if len(chunks) != 1 {
		t.Fatalf("ChunksAroundOrdered() returned %d chunks, want 1", len(chunks))
	}
	if got := (ChunkCoord{X: chunks[0].X, Z: chunks[0].Z}); got != (ChunkCoord{X: 1, Z: 0}) {
		t.Fatalf("first directional chunk = %+v, want +X chunk", got)
	}
}

func TestChunkSnapshotIsDeterministicAcrossWorldInstances(t *testing.T) {
	firstWorld := NewWorld(nil)
	secondWorld := NewWorld(nil)

	first, err := firstWorld.ChunkSnapshot(-3, 5)
	if err != nil {
		t.Fatalf("first ChunkSnapshot() error = %v", err)
	}
	second, err := secondWorld.ChunkSnapshot(-3, 5)
	if err != nil {
		t.Fatalf("second ChunkSnapshot() error = %v", err)
	}

	if first.X != -3 || first.Z != 5 {
		t.Fatalf("first snapshot coordinates = (%d, %d), want (-3, 5)", first.X, first.Z)
	}
	if second.X != -3 || second.Z != 5 {
		t.Fatalf("second snapshot coordinates = (%d, %d), want (-3, 5)", second.X, second.Z)
	}
	if !bytes.Equal(first.Blocks, second.Blocks) {
		t.Fatal("ChunkSnapshot() bytes differ across independent worlds for identical coordinates")
	}

	again, err := firstWorld.ChunkSnapshot(-3, 5)
	if err != nil {
		t.Fatalf("repeat ChunkSnapshot() error = %v", err)
	}
	if !bytes.Equal(first.Blocks, again.Blocks) {
		t.Fatal("ChunkSnapshot() bytes changed between repeated snapshots of the same generated chunk")
	}
}

func TestSetBlockGlobalPersistsEditedChunkForReload(t *testing.T) {
	store := newSerializedChunkStore()
	blockX, blockY, blockZ := int32(35), int32(64), int32(-2)
	chunkX, localX := GlobalToChunkLocal(blockX, ChunkWidth)
	chunkZ, localZ := GlobalToChunkLocal(blockZ, ChunkDepth)

	editWorld := NewWorld(store)
	if _, err := editWorld.SetBlockGlobal(blockX, blockY, blockZ, Wood); err != nil {
		t.Fatalf("SetBlockGlobal(place) error = %v", err)
	}
	if store.saves != 1 {
		t.Fatalf("store saves after place = %d, want 1", store.saves)
	}

	placedWorld := NewWorld(store)
	placedSnapshot, err := placedWorld.ChunkSnapshot(chunkX, chunkZ)
	if err != nil {
		t.Fatalf("ChunkSnapshot(placed reload) error = %v", err)
	}
	assertSnapshotBlock(t, placedSnapshot, localX, int(blockY), localZ, Wood)

	if _, err := placedWorld.SetBlockGlobal(blockX, blockY, blockZ, Air); err != nil {
		t.Fatalf("SetBlockGlobal(destroy) error = %v", err)
	}
	if store.saves != 2 {
		t.Fatalf("store saves after destroy = %d, want 2", store.saves)
	}

	destroyedWorld := NewWorld(store)
	destroyedSnapshot, err := destroyedWorld.ChunkSnapshot(chunkX, chunkZ)
	if err != nil {
		t.Fatalf("ChunkSnapshot(destroy reload) error = %v", err)
	}
	assertSnapshotBlock(t, destroyedSnapshot, localX, int(blockY), localZ, Air)
}

func TestSetBlockGlobalRejectsOutOfRangeYWithoutSave(t *testing.T) {
	store := newSerializedChunkStore()
	w := NewWorld(store)

	for _, y := range []int32{-1, int32(ChunkHeight)} {
		if _, err := w.SetBlockGlobal(1, y, 1, Wood); err == nil {
			t.Fatalf("SetBlockGlobal(y=%d) error = nil, want out-of-range error", y)
		}
	}

	if store.saves != 0 {
		t.Fatalf("store saves = %d, want 0", store.saves)
	}
	if len(store.data) != 0 {
		t.Fatalf("store chunks = %d, want 0", len(store.data))
	}
}

func TestChunkWithinRadius(t *testing.T) {
	tests := []struct {
		name   string
		coord  ChunkCoord
		radius int32
		want   bool
	}{
		{name: "center", coord: ChunkCoord{X: 0, Z: 0}, radius: 10, want: true},
		{name: "axis edge", coord: ChunkCoord{X: 10, Z: 0}, radius: 10, want: true},
		{name: "inside diagonal", coord: ChunkCoord{X: 6, Z: 8}, radius: 10, want: true},
		{name: "outside corner", coord: ChunkCoord{X: 10, Z: 10}, radius: 10, want: false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := ChunkWithinRadius(tt.coord, 0, 0, tt.radius); got != tt.want {
				t.Fatalf("ChunkWithinRadius(%+v, radius=%d) = %v, want %v", tt.coord, tt.radius, got, tt.want)
			}
		})
	}
}

type serializedChunkStore struct {
	data  map[ChunkCoord][]byte
	saves int
}

func newSerializedChunkStore() *serializedChunkStore {
	return &serializedChunkStore{data: make(map[ChunkCoord][]byte)}
}

func (s *serializedChunkStore) LoadChunk(x, z int32) (*Chunk, bool, error) {
	data, ok := s.data[ChunkCoord{X: x, Z: z}]
	if !ok {
		return nil, false, nil
	}
	chunk, err := DeserializeChunk(x, z, data)
	if err != nil {
		return nil, false, err
	}
	return chunk, true, nil
}

func (s *serializedChunkStore) SaveChunk(chunk *Chunk) error {
	s.data[ChunkCoord{X: chunk.X, Z: chunk.Z}] = append([]byte(nil), chunk.Serialize()...)
	s.saves++
	return nil
}

func (s *serializedChunkStore) Close() {}

func assertSnapshotBlock(t *testing.T, snapshot ChunkSnapshot, x, y, z int, want BlockID) {
	t.Helper()

	chunk, err := DeserializeChunk(snapshot.X, snapshot.Z, snapshot.Blocks)
	if err != nil {
		t.Fatalf("DeserializeChunk(snapshot) error = %v", err)
	}
	if got := chunk.GetBlock(x, y, z); got != want {
		t.Fatalf("snapshot block at (%d, %d, %d) = %v, want %v", x, y, z, got, want)
	}
}
