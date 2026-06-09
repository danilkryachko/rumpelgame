package world

type BlockID uint16

const (
	Air BlockID = iota
	Stone
	Dirt
	Grass
	Wood
	Leaves
)

type BlockTextures struct {
	Top    string
	Side   string
	Bottom string
}

type BlockDefinition struct {
	ID        BlockID
	Name      string
	Solid     bool
	Placeable bool
	Textures  BlockTextures
}

var blockRegistry = map[BlockID]BlockDefinition{
	Air: {
		ID:        Air,
		Name:      "Air",
		Solid:     false,
		Placeable: false,
		Textures:  BlockTextures{},
	},
	Stone: {
		ID:        Stone,
		Name:      "Stone",
		Solid:     true,
		Placeable: true,
		Textures:  sameTexture("stone"),
	},
	Dirt: {
		ID:        Dirt,
		Name:      "Dirt",
		Solid:     true,
		Placeable: true,
		Textures:  sameTexture("soil"),
	},
	Grass: {
		ID:        Grass,
		Name:      "Grass",
		Solid:     true,
		Placeable: true,
		Textures: BlockTextures{
			Top:    "grass_top",
			Side:   "grass_side",
			Bottom: "soil",
		},
	},
	Wood: {
		ID:        Wood,
		Name:      "Wood",
		Solid:     true,
		Placeable: true,
		Textures: BlockTextures{
			Top:    "wood_top",
			Side:   "wood_side",
			Bottom: "wood_top",
		},
	},
	Leaves: {
		ID:        Leaves,
		Name:      "Leaves",
		Solid:     true,
		Placeable: true,
		Textures:  sameTexture("leaves"),
	},
}

func sameTexture(name string) BlockTextures {
	return BlockTextures{Top: name, Side: name, Bottom: name}
}

func BlockByID(id BlockID) (BlockDefinition, bool) {
	block, ok := blockRegistry[id]
	return block, ok
}

func IsSolid(id BlockID) bool {
	block, ok := BlockByID(id)
	return ok && block.Solid
}

func IsPlaceable(id BlockID) bool {
	block, ok := BlockByID(id)
	return ok && block.Placeable
}
