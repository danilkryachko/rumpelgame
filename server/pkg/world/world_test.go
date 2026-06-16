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

func TestOriginChunkSnapshotUsesFlatGenerationContract(t *testing.T) {
	w := NewWorld(nil)

	first, err := w.ChunkSnapshot(0, 0)
	if err != nil {
		t.Fatalf("ChunkSnapshot(0,0) error = %v", err)
	}
	if first.X != 0 || first.Z != 0 {
		t.Fatalf("origin snapshot coordinates = (%d, %d), want (0, 0)", first.X, first.Z)
	}

	again, err := w.ChunkSnapshot(0, 0)
	if err != nil {
		t.Fatalf("repeat ChunkSnapshot(0,0) error = %v", err)
	}
	if !bytes.Equal(first.Blocks, again.Blocks) {
		t.Fatal("origin ChunkSnapshot() bytes changed between repeated snapshots")
	}

	chunk, err := DeserializeChunk(first.X, first.Z, first.Blocks)
	if err != nil {
		t.Fatalf("DeserializeChunk(origin snapshot) error = %v", err)
	}
	for _, want := range []struct {
		name  string
		x     int
		y     int
		z     int
		block BlockID
	}{
		{name: "bottom stone", x: 0, y: 0, z: 0, block: Stone},
		{name: "upper stone", x: ChunkWidth - 1, y: 60, z: ChunkDepth - 1, block: Stone},
		{name: "dirt layer", x: 1, y: 61, z: 1, block: Dirt},
		{name: "grass surface", x: 2, y: 63, z: 2, block: Grass},
		{name: "air above surface", x: 3, y: 64, z: 3, block: Air},
	} {
		t.Run(want.name, func(t *testing.T) {
			if got := chunk.GetBlock(want.x, want.y, want.z); got != want.block {
				t.Fatalf("origin block at (%d, %d, %d) = %v, want %v", want.x, want.y, want.z, got, want.block)
			}
		})
	}
}

func TestGlobalToChunkLocalHandlesNegativeBoundaries(t *testing.T) {
	tests := []struct {
		name      string
		block     int32
		wantChunk int32
		wantLocal int
	}{
		{name: "origin", block: 0, wantChunk: 0, wantLocal: 0},
		{name: "positive edge", block: int32(ChunkWidth - 1), wantChunk: 0, wantLocal: ChunkWidth - 1},
		{name: "positive next chunk", block: int32(ChunkWidth), wantChunk: 1, wantLocal: 0},
		{name: "negative previous edge", block: -1, wantChunk: -1, wantLocal: ChunkWidth - 1},
		{name: "negative exact chunk", block: -int32(ChunkWidth), wantChunk: -1, wantLocal: 0},
		{name: "negative next chunk edge", block: -int32(ChunkWidth) - 1, wantChunk: -2, wantLocal: ChunkWidth - 1},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			gotChunk, gotLocal := GlobalToChunkLocal(tt.block, ChunkWidth)
			if gotChunk != tt.wantChunk || gotLocal != tt.wantLocal {
				t.Fatalf("GlobalToChunkLocal(%d) = (%d, %d), want (%d, %d)", tt.block, gotChunk, gotLocal, tt.wantChunk, tt.wantLocal)
			}
		})
	}
}

func TestGlobalToChunkLocalHandlesLargePositiveBoundaries(t *testing.T) {
	base := int32(12345 * ChunkWidth)
	tests := []struct {
		name      string
		block     int32
		wantChunk int32
		wantLocal int
	}{
		{name: "large positive exact chunk", block: base, wantChunk: 12345, wantLocal: 0},
		{name: "large positive edge", block: base + int32(ChunkWidth) - 1, wantChunk: 12345, wantLocal: ChunkWidth - 1},
		{name: "large positive next chunk", block: base + int32(ChunkWidth), wantChunk: 12346, wantLocal: 0},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			gotChunk, gotLocal := GlobalToChunkLocal(tt.block, ChunkWidth)
			if gotChunk != tt.wantChunk || gotLocal != tt.wantLocal {
				t.Fatalf("GlobalToChunkLocal(%d) = (%d, %d), want (%d, %d)", tt.block, gotChunk, gotLocal, tt.wantChunk, tt.wantLocal)
			}
		})
	}
}

func TestChunkCoordForPositionUsesFloorAtNegativeBoundaries(t *testing.T) {
	tests := []struct {
		name string
		x    float32
		z    float32
		want ChunkCoord
	}{
		{name: "origin", x: 0, z: 0, want: ChunkCoord{X: 0, Z: 0}},
		{name: "positive edge", x: float32(ChunkWidth) - 0.25, z: float32(ChunkDepth) - 0.25, want: ChunkCoord{X: 0, Z: 0}},
		{name: "positive next chunk", x: float32(ChunkWidth), z: float32(ChunkDepth), want: ChunkCoord{X: 1, Z: 1}},
		{name: "negative fractional edge", x: -0.25, z: -0.25, want: ChunkCoord{X: -1, Z: -1}},
		{name: "negative exact chunk", x: -float32(ChunkWidth), z: -float32(ChunkDepth), want: ChunkCoord{X: -1, Z: -1}},
		{name: "negative next chunk", x: -float32(ChunkWidth) - 0.25, z: -float32(ChunkDepth) - 0.25, want: ChunkCoord{X: -2, Z: -2}},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := ChunkCoordForPosition(tt.x, tt.z); got != tt.want {
				t.Fatalf("ChunkCoordForPosition(%f, %f) = %+v, want %+v", tt.x, tt.z, got, tt.want)
			}
		})
	}
}

func TestChunkCoordForPositionHandlesLargePositiveBoundaries(t *testing.T) {
	baseX := float32(12345 * ChunkWidth)
	baseZ := float32(23456 * ChunkDepth)
	tests := []struct {
		name string
		x    float32
		z    float32
		want ChunkCoord
	}{
		{name: "large positive exact chunk", x: baseX, z: baseZ, want: ChunkCoord{X: 12345, Z: 23456}},
		{name: "large positive interior", x: baseX + 1.5, z: baseZ + 2.5, want: ChunkCoord{X: 12345, Z: 23456}},
		{name: "large positive next chunk", x: baseX + float32(ChunkWidth), z: baseZ + float32(ChunkDepth), want: ChunkCoord{X: 12346, Z: 23457}},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := ChunkCoordForPosition(tt.x, tt.z); got != tt.want {
				t.Fatalf("ChunkCoordForPosition(%f, %f) = %+v, want %+v", tt.x, tt.z, got, tt.want)
			}
		})
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

func TestSetBlockGlobalPersistsNegativeBoundaryCoordinates(t *testing.T) {
	store := newSerializedChunkStore()
	w := NewWorld(store)

	tests := []struct {
		name  string
		x     int32
		z     int32
		block BlockID
	}{
		{name: "negative previous edge", x: -1, z: -1, block: Wood},
		{name: "negative exact chunk", x: -int32(ChunkWidth), z: -int32(ChunkDepth), block: Stone},
		{name: "negative next edge mixed z", x: -int32(ChunkWidth) - 1, z: int32(ChunkDepth), block: Dirt},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			chunkX, localX := GlobalToChunkLocal(tt.x, ChunkWidth)
			chunkZ, localZ := GlobalToChunkLocal(tt.z, ChunkDepth)

			snapshot, err := w.SetBlockGlobal(tt.x, 64, tt.z, tt.block)
			if err != nil {
				t.Fatalf("SetBlockGlobal() error = %v", err)
			}
			if snapshot.X != chunkX || snapshot.Z != chunkZ {
				t.Fatalf("snapshot chunk = (%d, %d), want (%d, %d)", snapshot.X, snapshot.Z, chunkX, chunkZ)
			}
			assertSnapshotBlock(t, snapshot, localX, 64, localZ, tt.block)
		})
	}

	if store.saves != len(tests) {
		t.Fatalf("store saves = %d, want %d", store.saves, len(tests))
	}

	reloadedWorld := NewWorld(store)
	for _, tt := range tests {
		t.Run(tt.name+"/reload", func(t *testing.T) {
			chunkX, localX := GlobalToChunkLocal(tt.x, ChunkWidth)
			chunkZ, localZ := GlobalToChunkLocal(tt.z, ChunkDepth)

			snapshot, err := reloadedWorld.ChunkSnapshot(chunkX, chunkZ)
			if err != nil {
				t.Fatalf("ChunkSnapshot() error = %v", err)
			}
			assertSnapshotBlock(t, snapshot, localX, 64, localZ, tt.block)
		})
	}
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
