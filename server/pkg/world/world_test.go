package world

import "testing"

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
