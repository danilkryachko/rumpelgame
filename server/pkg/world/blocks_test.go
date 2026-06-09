package world

import "testing"

func TestBlockRegistryMatchesWireIDs(t *testing.T) {
	tests := map[BlockID]string{
		Air:    "Air",
		Stone:  "Stone",
		Dirt:   "Dirt",
		Grass:  "Grass",
		Wood:   "Wood",
		Leaves: "Leaves",
	}

	for id, name := range tests {
		block, ok := BlockByID(id)
		if !ok {
			t.Fatalf("BlockByID(%d) missing", id)
		}
		if block.Name != name {
			t.Fatalf("BlockByID(%d).Name = %q, want %q", id, block.Name, name)
		}
	}
}

func TestOnlyNonAirBlocksArePlaceable(t *testing.T) {
	if IsPlaceable(Air) {
		t.Fatal("Air should not be placeable")
	}
	for _, id := range []BlockID{Stone, Dirt, Grass, Wood, Leaves} {
		if !IsPlaceable(id) {
			t.Fatalf("block %d should be placeable", id)
		}
	}
	if IsPlaceable(BlockID(999)) {
		t.Fatal("unknown block should not be placeable")
	}
}
