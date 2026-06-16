package world

import (
	"fmt"
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

type ChunkOrder struct {
	DirectionX int32
	DirectionZ int32
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
	return w.ChunksAroundOrdered(centerX, centerZ, radius, alreadySent, limit, ChunkOrder{})
}

func (w *World) ChunksAroundOrdered(centerX, centerZ, radius int32, alreadySent map[ChunkCoord]bool, limit int, order ChunkOrder) ([]ChunkSnapshot, error) {
	w.mu.Lock()
	defer w.mu.Unlock()

	if limit <= 0 {
		return nil, nil
	}
	if alreadySent == nil {
		alreadySent = make(map[ChunkCoord]bool)
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
		if order.DirectionX != 0 || order.DirectionZ != 0 {
			aDirection := chunkDirectionScore(coords[i], centerX, centerZ, order)
			bDirection := chunkDirectionScore(coords[j], centerX, centerZ, order)
			if aDirection != bDirection {
				return aDirection > bDirection
			}
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

func chunkDirectionScore(coord ChunkCoord, centerX, centerZ int32, order ChunkOrder) int64 {
	dx := int64(coord.X - centerX)
	dz := int64(coord.Z - centerZ)
	return dx*int64(order.DirectionX) + dz*int64(order.DirectionZ)
}

func (w *World) SetBlockGlobal(x, y, z int32, block BlockID) (ChunkSnapshot, error) {
	if y < 0 || y >= int32(ChunkHeight) {
		return ChunkSnapshot{}, fmt.Errorf("block y coordinate %d out of range [0,%d)", y, ChunkHeight)
	}

	chunkX, localX := GlobalToChunkLocal(x, ChunkWidth)
	chunkZ, localZ := GlobalToChunkLocal(z, ChunkDepth)

	w.mu.Lock()
	defer w.mu.Unlock()

	chunk, err := w.getOrCreateLocked(chunkX, chunkZ)
	if err != nil {
		return ChunkSnapshot{}, err
	}
	previousBlock := chunk.GetBlock(localX, int(y), localZ)
	chunk.SetBlock(localX, int(y), localZ, block)

	if w.store != nil {
		if err := w.store.SaveChunk(chunk); err != nil {
			chunk.SetBlock(localX, int(y), localZ, previousBlock)
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
