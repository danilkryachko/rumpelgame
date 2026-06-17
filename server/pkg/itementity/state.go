package itementity

import (
	"fmt"
	"math"
	"sort"

	"rumpelmc/server/pkg/item"
)

const (
	MaxStateEntities      = 4096
	MaxEntityStackCount   = 64
	LegacySpawnedAtUnixMS = 0
)

type Entity struct {
	EntityID        uint64
	ItemID          string
	Count           uint32
	X               float64
	Y               float64
	Z               float64
	SpawnedAtUnixMS int64
}

type State struct {
	NextEntityID uint64
	Revision     uint64
	Entities     []Entity
}

func NormalizeState(state State) (State, error) {
	if state.NextEntityID == 0 {
		return State{}, fmt.Errorf("next entity id cannot be zero")
	}
	if len(state.Entities) > MaxStateEntities {
		return State{}, fmt.Errorf("item entity count %d exceeds max %d", len(state.Entities), MaxStateEntities)
	}

	entities := append([]Entity(nil), state.Entities...)
	sort.Slice(entities, func(i, j int) bool {
		return entities[i].EntityID < entities[j].EntityID
	})

	seen := make(map[uint64]struct{}, len(entities))
	var maxEntityID uint64
	for _, entity := range entities {
		if entity.EntityID == 0 {
			return State{}, fmt.Errorf("item entity id cannot be zero")
		}
		if _, ok := seen[entity.EntityID]; ok {
			return State{}, fmt.Errorf("duplicate item entity id %d", entity.EntityID)
		}
		seen[entity.EntityID] = struct{}{}
		if _, ok := item.BlockForItem(item.ID(entity.ItemID)); !ok {
			return State{}, fmt.Errorf("unsupported item entity item id %q", entity.ItemID)
		}
		if entity.Count == 0 {
			return State{}, fmt.Errorf("item entity %d count cannot be zero", entity.EntityID)
		}
		if entity.Count > MaxEntityStackCount {
			return State{}, fmt.Errorf("item entity %d count %d exceeds max %d", entity.EntityID, entity.Count, MaxEntityStackCount)
		}
		if !finiteCoordinate(entity.X) || !finiteCoordinate(entity.Y) || !finiteCoordinate(entity.Z) {
			return State{}, fmt.Errorf("item entity %d has non-finite position", entity.EntityID)
		}
		if entity.SpawnedAtUnixMS < LegacySpawnedAtUnixMS {
			return State{}, fmt.Errorf("item entity %d has negative spawned timestamp", entity.EntityID)
		}
		if entity.EntityID > maxEntityID {
			maxEntityID = entity.EntityID
		}
	}
	if maxEntityID > 0 && state.NextEntityID <= maxEntityID {
		return State{}, fmt.Errorf("next entity id %d must be greater than max entity id %d", state.NextEntityID, maxEntityID)
	}

	return State{
		NextEntityID: state.NextEntityID,
		Revision:     state.Revision,
		Entities:     entities,
	}, nil
}

func finiteCoordinate(value float64) bool {
	return !math.IsNaN(value) && !math.IsInf(value, 0)
}
