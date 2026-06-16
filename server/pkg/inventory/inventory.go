package inventory

import "rumpelmc/server/pkg/world"

const CreativeStackCount uint32 = 999

type PlacementPolicy string

const (
	PlacementPolicyRetain  PlacementPolicy = "retain"
	PlacementPolicyConsume PlacementPolicy = "consume"
)

type Slot struct {
	BlockID world.BlockID
	Count   uint32
}

type Inventory struct {
	slots           []Slot
	placementPolicy PlacementPolicy
}

func New(slots []Slot, placementPolicy PlacementPolicy) Inventory {
	copiedSlots := make([]Slot, len(slots))
	copy(copiedSlots, slots)

	return Inventory{
		slots:           copiedSlots,
		placementPolicy: placementPolicy,
	}
}

func NewCounted(slots []Slot) Inventory {
	return New(slots, PlacementPolicyConsume)
}

func NewCreativeHotbar() Inventory {
	definitions := world.BlockDefinitions()
	slots := make([]Slot, 0, len(definitions))
	for _, block := range definitions {
		if block.Placeable {
			slots = append(slots, Slot{
				BlockID: block.ID,
				Count:   CreativeStackCount,
			})
		}
	}
	return New(slots, PlacementPolicyRetain)
}

func (i *Inventory) CanPlaceBlock(blockID world.BlockID) bool {
	_, ok := i.placeableSlotIndex(blockID)
	return ok
}

func (i *Inventory) CanSelectSlot(slot uint32) bool {
	_, ok := i.PlaceableBlockAtSlot(slot)
	return ok
}

func (i *Inventory) FirstPlaceableSlot() (uint32, bool) {
	for index, slot := range i.slots {
		if inventorySlotCanPlace(slot) {
			return uint32(index), true
		}
	}
	return 0, false
}

func (i *Inventory) PlaceableBlockAtSlot(slot uint32) (world.BlockID, bool) {
	if uint64(slot) >= uint64(len(i.slots)) {
		return world.Air, false
	}

	inventorySlot := i.slots[slot]
	if !inventorySlotCanPlace(inventorySlot) {
		return world.Air, false
	}
	return inventorySlot.BlockID, true
}

func (i *Inventory) PlaceBlock(blockID world.BlockID) bool {
	slotIndex, ok := i.placeableSlotIndex(blockID)
	if !ok {
		return false
	}

	if i.placementPolicy == PlacementPolicyConsume {
		i.slots[slotIndex].Count--
	}
	return true
}

func (i *Inventory) Slots() []Slot {
	copiedSlots := make([]Slot, len(i.slots))
	copy(copiedSlots, i.slots)
	return copiedSlots
}

func (i *Inventory) placeableSlotIndex(blockID world.BlockID) (int, bool) {
	if !world.IsPlaceable(blockID) {
		return -1, false
	}

	for index, slot := range i.slots {
		if slot.BlockID == blockID && inventorySlotCanPlace(slot) {
			return index, true
		}
	}
	return -1, false
}

func inventorySlotCanPlace(slot Slot) bool {
	return slot.Count > 0 && world.IsPlaceable(slot.BlockID)
}
