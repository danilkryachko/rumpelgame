package item

import (
	"testing"

	"rumpelmc/server/pkg/world"
)

func TestBlockItemDefinitionsMapCurrentPlaceableBlocks(t *testing.T) {
	want := []struct {
		block world.BlockID
		item  ID
		name  string
	}{
		{block: world.Stone, item: StoneItemID, name: "Stone"},
		{block: world.Dirt, item: DirtItemID, name: "Dirt"},
		{block: world.Grass, item: GrassItemID, name: "Grass"},
		{block: world.Wood, item: WoodItemID, name: "Wood"},
		{block: world.Leaves, item: LeavesItemID, name: "Leaves"},
	}

	definitions := BlockItemDefinitions()
	if len(definitions) != len(want) {
		t.Fatalf("BlockItemDefinitions() length = %d, want %d", len(definitions), len(want))
	}
	for index, row := range want {
		definition := definitions[index]
		if definition.BlockID != row.block || definition.ID != row.item || definition.Name != row.name {
			t.Fatalf("BlockItemDefinitions()[%d] = %+v, want block=%v item=%q name=%q", index, definition, row.block, row.item, row.name)
		}
		itemID, ok := BlockItemID(row.block)
		if !ok {
			t.Fatalf("BlockItemID(%v) missing", row.block)
		}
		if itemID != row.item {
			t.Fatalf("BlockItemID(%v) = %q, want %q", row.block, itemID, row.item)
		}
		blockID, ok := BlockForItem(row.item)
		if !ok {
			t.Fatalf("BlockForItem(%q) missing", row.item)
		}
		if blockID != row.block {
			t.Fatalf("BlockForItem(%q) = %v, want %v", row.item, blockID, row.block)
		}
	}

	if _, ok := BlockItemID(world.Air); ok {
		t.Fatal("BlockItemID(Air) should be absent")
	}
	if _, ok := BlockForItem(ID("block:unknown")); ok {
		t.Fatal("BlockForItem(block:unknown) should be absent")
	}
}

func TestCatalogAccessorsReturnCopies(t *testing.T) {
	blockItems := BlockItemDefinitions()
	blockItems[0].ID = ID("mutated")
	itemID, ok := BlockItemID(world.Stone)
	if !ok {
		t.Fatal("BlockItemID(Stone) missing")
	}
	if itemID != StoneItemID {
		t.Fatalf("BlockItemID(Stone) after copy mutation = %q, want %q", itemID, StoneItemID)
	}

	tools := ToolDefinitions()
	tools[1].EffectiveBlocks[0] = world.Wood
	pickaxe, ok := ToolByID(WoodenPickaxeToolID)
	if !ok {
		t.Fatal("ToolByID(WoodenPickaxeToolID) missing")
	}
	if len(pickaxe.EffectiveBlocks) != 1 || pickaxe.EffectiveBlocks[0] != world.Stone {
		t.Fatalf("Wooden pickaxe effective blocks after copy mutation = %v, want [Stone]", pickaxe.EffectiveBlocks)
	}
}

func TestDefaultToolbeltStartsWithHandAndIncludesWoodTools(t *testing.T) {
	toolbelt := DefaultToolbelt()
	want := []ID{HandToolID, WoodenPickaxeToolID, WoodenAxeToolID, WoodenShovelToolID}
	if len(toolbelt) != len(want) {
		t.Fatalf("DefaultToolbelt() length = %d, want %d", len(toolbelt), len(want))
	}
	for index, wantID := range want {
		if toolbelt[index] != wantID {
			t.Fatalf("DefaultToolbelt()[%d] = %q, want %q", index, toolbelt[index], wantID)
		}
		if _, ok := ToolByID(wantID); !ok {
			t.Fatalf("ToolByID(%q) missing", wantID)
		}
	}
}

func TestAdjustedMiningDurationMSUsesToolEffectiveness(t *testing.T) {
	tests := []struct {
		name   string
		base   int
		block  world.BlockID
		tool   ID
		wanted int
	}{
		{name: "hand keeps stone duration", base: world.StoneBlockMiningMS, block: world.Stone, tool: HandToolID, wanted: world.StoneBlockMiningMS},
		{name: "pickaxe halves stone duration", base: world.StoneBlockMiningMS, block: world.Stone, tool: WoodenPickaxeToolID, wanted: 150},
		{name: "pickaxe does not speed wood", base: world.WoodBlockMiningMS, block: world.Wood, tool: WoodenPickaxeToolID, wanted: world.WoodBlockMiningMS},
		{name: "axe halves wood duration", base: world.WoodBlockMiningMS, block: world.Wood, tool: WoodenAxeToolID, wanted: 125},
		{name: "shovel halves dirt duration", base: world.SoftBlockMiningMS, block: world.Dirt, tool: WoodenShovelToolID, wanted: 75},
		{name: "unknown tool keeps base duration", base: world.SoftBlockMiningMS, block: world.Dirt, tool: ID("tool:missing"), wanted: world.SoftBlockMiningMS},
		{name: "zero base remains zero", base: 0, block: world.Stone, tool: WoodenPickaxeToolID, wanted: 0},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := AdjustedMiningDurationMS(tt.base, tt.block, tt.tool)
			if got != tt.wanted {
				t.Fatalf("AdjustedMiningDurationMS(%d, %v, %q) = %d, want %d", tt.base, tt.block, tt.tool, got, tt.wanted)
			}
		})
	}
}
