package world

import (
	"math"
	"sort"
	"sync"
)

type ChunkStore interface {
	LoadChunk(x, z int32) (*Chunk, bool, error)
	SaveChunk(chunk *Chunk) error
	Close()
}

type World struct {
	mu     sync.Mutex
	chunks map[ChunkCoord]*Chunk
	store  ChunkStore
}

func NewWorld(store ChunkStore) *World {
	return &World{
		chunks: make(map[ChunkCoord]*Chunk),
		store:  store,
	}
}

func (w *World) Close() {
	if w.store != nil {
		w.store.Close()
	}
}

func (w *World) ChunkSnapshot(x, z int32) (ChunkSnapshot, error) {
	w.mu.Lock()
	defer w.mu.Unlock()

	chunk, err := w.getOrCreateLocked(x, z)
	if err != nil {
		return ChunkSnapshot{}, err
	}
	return snapshotChunk(chunk), nil
}

func (w *World) ChunksAround(centerX, centerZ, radius int32, alreadySent map[ChunkCoord]bool, limit int) ([]ChunkSnapshot, error) {
	w.mu.Lock()
	defer w.mu.Unlock()

	if limit <= 0 {
		return nil, nil
	}

	coords := make([]ChunkCoord, 0, (radius*2+1)*(radius*2+1))
	for x := centerX - radius; x <= centerX+radius; x++ {
		for z := centerZ - radius; z <= centerZ+radius; z++ {
			coord := ChunkCoord{X: x, Z: z}
			if alreadySent[coord] || !ChunkWithinRadius(coord, centerX, centerZ, radius) {
				continue
			}
			coords = append(coords, coord)
		}
	}

	sort.Slice(coords, func(i, j int) bool {
		a := chunkDistanceSquared(coords[i], centerX, centerZ)
		b := chunkDistanceSquared(coords[j], centerX, centerZ)
		if a != b {
			return a < b
		}
		if coords[i].X != coords[j].X {
			return coords[i].X < coords[j].X
		}
		return coords[i].Z < coords[j].Z
	})

	if len(coords) > limit {
		coords = coords[:limit]
	}

	snapshots := make([]ChunkSnapshot, 0, len(coords))
	for _, coord := range coords {
		chunk, err := w.getOrCreateLocked(coord.X, coord.Z)
		if err != nil {
			return nil, err
		}
		snapshots = append(snapshots, snapshotChunk(chunk))
		alreadySent[coord] = true
	}
	return snapshots, nil
}

func ChunkWithinRadius(coord ChunkCoord, centerX, centerZ, radius int32) bool {
	return chunkDistanceSquared(coord, centerX, centerZ) <= int64(radius)*int64(radius)
}

func chunkDistanceSquared(coord ChunkCoord, centerX, centerZ int32) int64 {
	dx := int64(coord.X - centerX)
	dz := int64(coord.Z - centerZ)
	return dx*dx + dz*dz
}

func (w *World) SetBlockGlobal(x, y, z int32, block BlockID) (ChunkSnapshot, error) {
	chunkX, localX := GlobalToChunkLocal(x, ChunkWidth)
	chunkZ, localZ := GlobalToChunkLocal(z, ChunkDepth)

	w.mu.Lock()
	defer w.mu.Unlock()

	chunk, err := w.getOrCreateLocked(chunkX, chunkZ)
	if err != nil {
		return ChunkSnapshot{}, err
	}
	chunk.SetBlock(localX, int(y), localZ, block)

	if w.store != nil {
		if err := w.store.SaveChunk(chunk); err != nil {
			return ChunkSnapshot{}, err
		}
	}

	return snapshotChunk(chunk), nil
}

func (w *World) getOrCreateLocked(x, z int32) (*Chunk, error) {
	coord := ChunkCoord{X: x, Z: z}
	if chunk, ok := w.chunks[coord]; ok {
		return chunk, nil
	}

	if w.store != nil {
		chunk, ok, err := w.store.LoadChunk(x, z)
		if err != nil {
			return nil, err
		}
		if ok {
			w.chunks[coord] = chunk
			return chunk, nil
		}
	}

	chunk := NewChunk(x, z)
	chunk.GenerateFlat()
	w.chunks[coord] = chunk
	return chunk, nil
}

func snapshotChunk(chunk *Chunk) ChunkSnapshot {
	return ChunkSnapshot{
		X:      chunk.X,
		Z:      chunk.Z,
		Blocks: chunk.Serialize(),
	}
}

func GlobalToChunkLocal(block int32, size int) (int32, int) {
	size32 := int32(size)
	chunk := int32(math.Floor(float64(block) / float64(size32)))
	local := int(block - chunk*size32)
	return chunk, local
}

func ChunkCoordForPosition(x, z float32) ChunkCoord {
	chunkX, _ := GlobalToChunkLocal(int32(math.Floor(float64(x))), ChunkWidth)
	chunkZ, _ := GlobalToChunkLocal(int32(math.Floor(float64(z))), ChunkDepth)
	return ChunkCoord{X: chunkX, Z: chunkZ}
}
