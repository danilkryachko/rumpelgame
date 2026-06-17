package itementity

import (
	"math"
	"testing"

	"rumpelmc/server/pkg/item"
)

func TestNormalizeStateSortsEntities(t *testing.T) {
	state, err := NormalizeState(State{
		NextEntityID: 10,
		Revision:     7,
		Entities: []Entity{
			{EntityID: 9, ItemID: string(item.StoneItemID), Count: 1, X: 1.5, Y: 60.5, Z: 1.5},
			{EntityID: 3, ItemID: string(item.WoodItemID), Count: 2, X: -2.5, Y: 64.5, Z: 0.5},
		},
	})
	if err != nil {
		t.Fatalf("NormalizeState() error = %v", err)
	}
	if state.Revision != 7 {
		t.Fatalf("revision = %d, want 7", state.Revision)
	}
	if state.NextEntityID != 10 {
		t.Fatalf("next entity id = %d, want 10", state.NextEntityID)
	}
	if len(state.Entities) != 2 {
		t.Fatalf("entities = %d, want 2", len(state.Entities))
	}
	if state.Entities[0].EntityID != 3 || state.Entities[1].EntityID != 9 {
		t.Fatalf("entity order = [%d %d], want [3 9]", state.Entities[0].EntityID, state.Entities[1].EntityID)
	}
}

func TestNormalizeStateRejectsInvalidEntities(t *testing.T) {
	tests := []struct {
		name  string
		state State
	}{
		{
			name: "zero next id",
			state: State{
				Entities: []Entity{},
			},
		},
		{
			name: "zero entity id",
			state: State{
				NextEntityID: 2,
				Entities:     []Entity{{EntityID: 0, ItemID: string(item.StoneItemID), Count: 1}},
			},
		},
		{
			name: "duplicate id",
			state: State{
				NextEntityID: 3,
				Entities: []Entity{
					{EntityID: 1, ItemID: string(item.StoneItemID), Count: 1},
					{EntityID: 1, ItemID: string(item.DirtItemID), Count: 1},
				},
			},
		},
		{
			name: "unknown item",
			state: State{
				NextEntityID: 2,
				Entities:     []Entity{{EntityID: 1, ItemID: "block:missing", Count: 1}},
			},
		},
		{
			name: "zero count",
			state: State{
				NextEntityID: 2,
				Entities:     []Entity{{EntityID: 1, ItemID: string(item.StoneItemID), Count: 0}},
			},
		},
		{
			name: "non-finite coordinate",
			state: State{
				NextEntityID: 2,
				Entities:     []Entity{{EntityID: 1, ItemID: string(item.StoneItemID), Count: 1, X: math.NaN()}},
			},
		},
		{
			name: "next id reuses live id",
			state: State{
				NextEntityID: 1,
				Entities:     []Entity{{EntityID: 1, ItemID: string(item.StoneItemID), Count: 1}},
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if _, err := NormalizeState(tt.state); err == nil {
				t.Fatal("NormalizeState() error = nil, want failure")
			}
		})
	}
}
