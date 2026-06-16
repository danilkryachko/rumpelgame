package inventory

import (
	"testing"

	"rumpelmc/server/pkg/world"
)

func TestCreativeHotbarContainsCurrentPlaceableBlocks(t *testing.T) {
	inv := NewCreativeHotbar()
	slots := inv.Slots()
	placeableBlocks := placeableBlockIDs(t)

	if len(slots) != len(placeableBlocks) {
		t.Fatalf("creative hotbar slots = %d, want %d", len(slots), len(placeableBlocks))
	}

	for index, blockID := range placeableBlocks {
		if slots[index].BlockID != blockID {
			t.Fatalf("slot %d block = %v, want %v", index, slots[index].BlockID, blockID)
		}
		if slots[index].Count != CreativeStackCount {
			t.Fatalf("slot %d count = %d, want %d", index, slots[index].Count, CreativeStackCount)
		}
		if !inv.CanPlaceBlock(blockID) {
			t.Fatalf("CanPlaceBlock(%v) = false, want true", blockID)
		}
	}

	if inv.CanPlaceBlock(world.Air) {
		t.Fatal("CanPlaceBlock(Air) = true, want false")
	}
	if inv.CanPlaceBlock(world.BlockID(999)) {
		t.Fatal("CanPlaceBlock(unknown) = true, want false")
	}
}

func TestCreativeHotbarPlaceBlockRetainsCounts(t *testing.T) {
	inv := NewCreativeHotbar()

	if !inv.PlaceBlock(world.Wood) {
		t.Fatal("PlaceBlock(Wood) = false, want true")
	}
	if !inv.PlaceBlock(world.Wood) {
		t.Fatal("second PlaceBlock(Wood) = false, want true")
	}

	for _, slot := range inv.Slots() {
		if slot.BlockID == world.Wood && slot.Count != CreativeStackCount {
			t.Fatalf("Wood count = %d, want %d", slot.Count, CreativeStackCount)
		}
	}
}

func TestCountedInventoryConsumesStacksAndRejectsEmptySlots(t *testing.T) {
	inv := NewCounted([]Slot{
		{BlockID: world.Stone, Count: 2},
		{BlockID: world.Dirt, Count: 0},
		{BlockID: world.Air, Count: 10},
	})

	if !inv.PlaceBlock(world.Stone) {
		t.Fatal("first PlaceBlock(Stone) = false, want true")
	}
	if !inv.PlaceBlock(world.Stone) {
		t.Fatal("second PlaceBlock(Stone) = false, want true")
	}
	if inv.PlaceBlock(world.Stone) {
		t.Fatal("third PlaceBlock(Stone) = true, want false after count reaches zero")
	}
	if inv.PlaceBlock(world.Dirt) {
		t.Fatal("PlaceBlock(Dirt empty slot) = true, want false")
	}
	if inv.PlaceBlock(world.Air) {
		t.Fatal("PlaceBlock(Air) = true, want false")
	}
}

func TestInventorySlotsReturnsCopy(t *testing.T) {
	inv := NewCounted([]Slot{{BlockID: world.Stone, Count: 1}})
	slots := inv.Slots()
	slots[0].Count = 0

	if !inv.CanPlaceBlock(world.Stone) {
		t.Fatal("mutating Slots() result changed inventory state")
	}
}

func placeableBlockIDs(t *testing.T) []world.BlockID {
	t.Helper()

	var ids []world.BlockID
	for _, block := range world.BlockDefinitions() {
		if block.Placeable {
			ids = append(ids, block.ID)
		}
	}
	return ids
}
