package item

import "rumpelmc/server/pkg/world"

type ID string

type Kind string

const (
	KindBlock Kind = "block"
	KindTool  Kind = "tool"
)

type ToolKind string

const (
	ToolKindHand    ToolKind = "hand"
	ToolKindPickaxe ToolKind = "pickaxe"
	ToolKindAxe     ToolKind = "axe"
	ToolKindShovel  ToolKind = "shovel"
)

type ToolTier string

const (
	ToolTierNone ToolTier = "none"
	ToolTierWood ToolTier = "wood"
)

const (
	StoneItemID  ID = "block:stone"
	DirtItemID   ID = "block:dirt"
	GrassItemID  ID = "block:grass"
	WoodItemID   ID = "block:wood"
	LeavesItemID ID = "block:leaves"

	HandToolID          ID = "tool:hand"
	WoodenPickaxeToolID ID = "tool:wooden_pickaxe"
	WoodenAxeToolID     ID = "tool:wooden_axe"
	WoodenShovelToolID  ID = "tool:wooden_shovel"
)

type BlockItemDefinition struct {
	ID      ID
	Name    string
	BlockID world.BlockID
}

type ToolDefinition struct {
	ID              ID
	Name            string
	Kind            ToolKind
	Tier            ToolTier
	SpeedMultiplier int
	EffectiveBlocks []world.BlockID
}

var blockItemDefinitions = []BlockItemDefinition{
	{ID: StoneItemID, Name: "Stone", BlockID: world.Stone},
	{ID: DirtItemID, Name: "Dirt", BlockID: world.Dirt},
	{ID: GrassItemID, Name: "Grass", BlockID: world.Grass},
	{ID: WoodItemID, Name: "Wood", BlockID: world.Wood},
	{ID: LeavesItemID, Name: "Leaves", BlockID: world.Leaves},
}

var toolDefinitions = []ToolDefinition{
	{ID: HandToolID, Name: "Hand", Kind: ToolKindHand, Tier: ToolTierNone, SpeedMultiplier: 1},
	{ID: WoodenPickaxeToolID, Name: "Wooden Pickaxe", Kind: ToolKindPickaxe, Tier: ToolTierWood, SpeedMultiplier: 2, EffectiveBlocks: []world.BlockID{world.Stone}},
	{ID: WoodenAxeToolID, Name: "Wooden Axe", Kind: ToolKindAxe, Tier: ToolTierWood, SpeedMultiplier: 2, EffectiveBlocks: []world.BlockID{world.Wood, world.Leaves}},
	{ID: WoodenShovelToolID, Name: "Wooden Shovel", Kind: ToolKindShovel, Tier: ToolTierWood, SpeedMultiplier: 2, EffectiveBlocks: []world.BlockID{world.Dirt, world.Grass}},
}

var blockItemsByBlock = blockItemRegistryByBlock(blockItemDefinitions)
var blockItemsByID = blockItemRegistryByID(blockItemDefinitions)
var toolsByID = toolRegistryByID(toolDefinitions)

func BlockItemDefinitions() []BlockItemDefinition {
	definitions := make([]BlockItemDefinition, len(blockItemDefinitions))
	copy(definitions, blockItemDefinitions)
	return definitions
}

func ToolDefinitions() []ToolDefinition {
	definitions := make([]ToolDefinition, len(toolDefinitions))
	for index, definition := range toolDefinitions {
		definitions[index] = copyToolDefinition(definition)
	}
	return definitions
}

func BlockItemID(block world.BlockID) (ID, bool) {
	definition, ok := blockItemsByBlock[block]
	return definition.ID, ok
}

func BlockForItem(id ID) (world.BlockID, bool) {
	definition, ok := blockItemsByID[id]
	return definition.BlockID, ok
}

func ToolByID(id ID) (ToolDefinition, bool) {
	definition, ok := toolsByID[id]
	if !ok {
		return ToolDefinition{}, false
	}
	return copyToolDefinition(definition), true
}

func DefaultToolbelt() []ID {
	return []ID{HandToolID, WoodenPickaxeToolID, WoodenAxeToolID, WoodenShovelToolID}
}

func AdjustedMiningDurationMS(baseDurationMS int, block world.BlockID, toolID ID) int {
	if baseDurationMS <= 0 {
		return baseDurationMS
	}

	tool, ok := ToolByID(toolID)
	if !ok || tool.SpeedMultiplier <= 1 || !toolEffectiveForBlock(tool, block) {
		return baseDurationMS
	}
	return divideRoundUp(baseDurationMS, tool.SpeedMultiplier)
}

func blockItemRegistryByBlock(definitions []BlockItemDefinition) map[world.BlockID]BlockItemDefinition {
	registry := make(map[world.BlockID]BlockItemDefinition, len(definitions))
	for _, definition := range definitions {
		registry[definition.BlockID] = definition
	}
	return registry
}

func blockItemRegistryByID(definitions []BlockItemDefinition) map[ID]BlockItemDefinition {
	registry := make(map[ID]BlockItemDefinition, len(definitions))
	for _, definition := range definitions {
		registry[definition.ID] = definition
	}
	return registry
}

func toolRegistryByID(definitions []ToolDefinition) map[ID]ToolDefinition {
	registry := make(map[ID]ToolDefinition, len(definitions))
	for _, definition := range definitions {
		registry[definition.ID] = copyToolDefinition(definition)
	}
	return registry
}

func copyToolDefinition(definition ToolDefinition) ToolDefinition {
	definition.EffectiveBlocks = append([]world.BlockID(nil), definition.EffectiveBlocks...)
	return definition
}

func toolEffectiveForBlock(tool ToolDefinition, block world.BlockID) bool {
	for _, effectiveBlock := range tool.EffectiveBlocks {
		if effectiveBlock == block {
			return true
		}
	}
	return false
}

func divideRoundUp(value, divisor int) int {
	return (value + divisor - 1) / divisor
}
