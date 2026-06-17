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

const (
	NoMiningDurationMS   = 0
	SoftBlockMiningMS    = 150
	WoodBlockMiningMS    = 250
	StoneBlockMiningMS   = 300
	DefaultBlockMiningMS = StoneBlockMiningMS
	UnknownBlockMiningMS = NoMiningDurationMS
	NonPlaceableMiningMS = NoMiningDurationMS
)

type BlockTextures struct {
	Top    string
	Side   string
	Bottom string
}

type RenderClass string

const (
	RenderClassAir         RenderClass = "air"
	RenderClassOpaque      RenderClass = "opaque"
	RenderClassCutout      RenderClass = "cutout"
	RenderClassTransparent RenderClass = "transparent"
	RenderClassLiquid      RenderClass = "liquid"
)

type CollisionClass string

const (
	CollisionClassNone   CollisionClass = "none"
	CollisionClassSolid  CollisionClass = "solid"
	CollisionClassFluid  CollisionClass = "fluid"
	CollisionClassCustom CollisionClass = "custom"
)

type OcclusionClass string

const (
	OcclusionClassNone             OcclusionClass = "none"
	OcclusionClassOpaque           OcclusionClass = "opaque"
	OcclusionClassSameMaterialOnly OcclusionClass = "same_material_only"
	OcclusionClassMaterialPolicy   OcclusionClass = "material_policy"
)

type ShadowPolicy string

const (
	ShadowPolicyNone        ShadowPolicy = "no_shadow"
	ShadowPolicyOpaque      ShadowPolicy = "opaque_shadow"
	ShadowPolicyTransparent ShadowPolicy = "transparent_shadow"
	ShadowPolicyMaterial    ShadowPolicy = "material_policy"
)

type DepthPolicy string

const (
	DepthPolicyNone             DepthPolicy = "no_draw"
	DepthPolicyOpaqueWrite      DepthPolicy = "opaque_depth_write"
	DepthPolicyDepthTestNoWrite DepthPolicy = "depth_test_no_write"
	DepthPolicyMaterial         DepthPolicy = "material_policy"
)

type StoragePolicy string

const (
	StoragePolicyNetworked         StoragePolicy = "networked"
	StoragePolicyClientFixtureOnly StoragePolicy = "client_fixture_only"
	StoragePolicyGeneratedOnly     StoragePolicy = "generated_only"
)

type LiquidPolicy string

const (
	LiquidPolicyNone        LiquidPolicy = "none"
	LiquidPolicyStillLiquid LiquidPolicy = "still_liquid"
	LiquidPolicyFlowing     LiquidPolicy = "flowing_liquid"
)

type SortPolicy string

const (
	SortPolicyNone              SortPolicy = "none"
	SortPolicyChunkSubchunkBack SortPolicy = "chunk_subchunk_back_to_front"
	SortPolicyFuturePrecise     SortPolicy = "future_precise"
)

type BlockDefinition struct {
	ID               BlockID
	Name             string
	Solid            bool
	Opaque           bool
	Placeable        bool
	RenderClass      RenderClass
	CollisionClass   CollisionClass
	OcclusionClass   OcclusionClass
	ShadowPolicy     ShadowPolicy
	DepthPolicy      DepthPolicy
	StoragePolicy    StoragePolicy
	LiquidPolicy     LiquidPolicy
	SortPolicy       SortPolicy
	LightEmission    uint8
	MiningDurationMS int
	Textures         BlockTextures
}

var blockDefinitions = []BlockDefinition{
	{
		ID:               Air,
		Name:             "Air",
		Solid:            false,
		Opaque:           false,
		Placeable:        false,
		RenderClass:      RenderClassAir,
		CollisionClass:   CollisionClassNone,
		OcclusionClass:   OcclusionClassNone,
		ShadowPolicy:     ShadowPolicyNone,
		DepthPolicy:      DepthPolicyNone,
		StoragePolicy:    StoragePolicyNetworked,
		LiquidPolicy:     LiquidPolicyNone,
		SortPolicy:       SortPolicyNone,
		LightEmission:    0,
		MiningDurationMS: NoMiningDurationMS,
		Textures:         BlockTextures{},
	},
	{
		ID:               Stone,
		Name:             "Stone",
		Solid:            true,
		Opaque:           true,
		Placeable:        true,
		RenderClass:      RenderClassOpaque,
		CollisionClass:   CollisionClassSolid,
		OcclusionClass:   OcclusionClassOpaque,
		ShadowPolicy:     ShadowPolicyOpaque,
		DepthPolicy:      DepthPolicyOpaqueWrite,
		StoragePolicy:    StoragePolicyNetworked,
		LiquidPolicy:     LiquidPolicyNone,
		SortPolicy:       SortPolicyNone,
		LightEmission:    0,
		MiningDurationMS: StoneBlockMiningMS,
		Textures:         sameTexture("stone"),
	},
	{
		ID:               Dirt,
		Name:             "Dirt",
		Solid:            true,
		Opaque:           true,
		Placeable:        true,
		RenderClass:      RenderClassOpaque,
		CollisionClass:   CollisionClassSolid,
		OcclusionClass:   OcclusionClassOpaque,
		ShadowPolicy:     ShadowPolicyOpaque,
		DepthPolicy:      DepthPolicyOpaqueWrite,
		StoragePolicy:    StoragePolicyNetworked,
		LiquidPolicy:     LiquidPolicyNone,
		SortPolicy:       SortPolicyNone,
		LightEmission:    0,
		MiningDurationMS: SoftBlockMiningMS,
		Textures:         sameTexture("soil"),
	},
	{
		ID:               Grass,
		Name:             "Grass",
		Solid:            true,
		Opaque:           true,
		Placeable:        true,
		RenderClass:      RenderClassOpaque,
		CollisionClass:   CollisionClassSolid,
		OcclusionClass:   OcclusionClassOpaque,
		ShadowPolicy:     ShadowPolicyOpaque,
		DepthPolicy:      DepthPolicyOpaqueWrite,
		StoragePolicy:    StoragePolicyNetworked,
		LiquidPolicy:     LiquidPolicyNone,
		SortPolicy:       SortPolicyNone,
		LightEmission:    0,
		MiningDurationMS: SoftBlockMiningMS,
		Textures: BlockTextures{
			Top:    "grass_top",
			Side:   "grass_side",
			Bottom: "soil",
		},
	},
	{
		ID:               Wood,
		Name:             "Wood",
		Solid:            true,
		Opaque:           true,
		Placeable:        true,
		RenderClass:      RenderClassOpaque,
		CollisionClass:   CollisionClassSolid,
		OcclusionClass:   OcclusionClassOpaque,
		ShadowPolicy:     ShadowPolicyOpaque,
		DepthPolicy:      DepthPolicyOpaqueWrite,
		StoragePolicy:    StoragePolicyNetworked,
		LiquidPolicy:     LiquidPolicyNone,
		SortPolicy:       SortPolicyNone,
		LightEmission:    0,
		MiningDurationMS: WoodBlockMiningMS,
		Textures: BlockTextures{
			Top:    "wood_top",
			Side:   "wood_side",
			Bottom: "wood_top",
		},
	},
	{
		ID:               Leaves,
		Name:             "Leaves",
		Solid:            true,
		Opaque:           true,
		Placeable:        true,
		RenderClass:      RenderClassOpaque,
		CollisionClass:   CollisionClassSolid,
		OcclusionClass:   OcclusionClassOpaque,
		ShadowPolicy:     ShadowPolicyOpaque,
		DepthPolicy:      DepthPolicyOpaqueWrite,
		StoragePolicy:    StoragePolicyNetworked,
		LiquidPolicy:     LiquidPolicyNone,
		SortPolicy:       SortPolicyNone,
		LightEmission:    0,
		MiningDurationMS: SoftBlockMiningMS,
		Textures:         sameTexture("leaves"),
	},
}

var blockRegistry = blockRegistryByID(blockDefinitions)

func blockRegistryByID(definitions []BlockDefinition) map[BlockID]BlockDefinition {
	registry := make(map[BlockID]BlockDefinition, len(definitions))
	for _, block := range definitions {
		registry[block.ID] = block
	}
	return registry
}

func sameTexture(name string) BlockTextures {
	return BlockTextures{Top: name, Side: name, Bottom: name}
}

func BlockDefinitions() []BlockDefinition {
	definitions := make([]BlockDefinition, len(blockDefinitions))
	copy(definitions, blockDefinitions)
	return definitions
}

func BlockByID(id BlockID) (BlockDefinition, bool) {
	block, ok := blockRegistry[id]
	return block, ok
}

func IsOpaque(id BlockID) bool {
	block, ok := BlockByID(id)
	return ok && block.Opaque
}

func IsOpaqueSolid(id BlockID) bool {
	block, ok := BlockByID(id)
	return ok && block.Solid && block.Opaque
}

func IsSolid(id BlockID) bool {
	block, ok := BlockByID(id)
	return ok && block.Solid
}

func IsPlaceable(id BlockID) bool {
	block, ok := BlockByID(id)
	return ok && block.Placeable
}
