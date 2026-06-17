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

func TestBlockIDValuesAreStable(t *testing.T) {
	tests := map[BlockID]uint16{
		Air:    0,
		Stone:  1,
		Dirt:   2,
		Grass:  3,
		Wood:   4,
		Leaves: 5,
	}

	for id, want := range tests {
		if got := uint16(id); got != want {
			t.Fatalf("BlockID %d = %d, want %d", id, got, want)
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

func TestBlockDefinitionsAreStableOrderedCopy(t *testing.T) {
	definitions := BlockDefinitions()
	wantIDs := []BlockID{Air, Stone, Dirt, Grass, Wood, Leaves}
	if len(definitions) != len(wantIDs) {
		t.Fatalf("BlockDefinitions() length = %d, want %d", len(definitions), len(wantIDs))
	}
	for i, wantID := range wantIDs {
		if definitions[i].ID != wantID {
			t.Fatalf("BlockDefinitions()[%d].ID = %d, want %d", i, definitions[i].ID, wantID)
		}
	}

	definitions[0].Name = "mutated"
	air, ok := BlockByID(Air)
	if !ok {
		t.Fatal("BlockByID(Air) missing after copy mutation")
	}
	if air.Name != "Air" {
		t.Fatalf("BlockDefinitions() returned a live registry entry, Air name = %q", air.Name)
	}
}

func TestBlockMaterialIdentityRowsAreStable(t *testing.T) {
	want := []BlockDefinition{
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
	got := BlockDefinitions()
	if len(got) != len(want) {
		t.Fatalf("BlockDefinitions() length = %d, want %d", len(got), len(want))
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("BlockDefinitions()[%d] = %+v, want %+v", i, got[i], want[i])
		}
	}
}

func TestCurrentNetworkedBlocksPreserveOpaqueSolidMaterialContract(t *testing.T) {
	air, ok := BlockByID(Air)
	if !ok {
		t.Fatal("BlockByID(Air) missing")
	}
	if air.RenderClass != RenderClassAir ||
		air.CollisionClass != CollisionClassNone ||
		air.OcclusionClass != OcclusionClassNone ||
		air.ShadowPolicy != ShadowPolicyNone ||
		air.DepthPolicy != DepthPolicyNone ||
		air.StoragePolicy != StoragePolicyNetworked ||
		air.LiquidPolicy != LiquidPolicyNone ||
		air.SortPolicy != SortPolicyNone ||
		air.LightEmission != 0 ||
		air.MiningDurationMS != NoMiningDurationMS ||
		air.Solid ||
		air.Opaque ||
		air.Placeable {
		t.Fatalf("Air material contract = %+v, want inert networked air", air)
	}

	for _, id := range []BlockID{Stone, Dirt, Grass, Wood, Leaves} {
		block, ok := BlockByID(id)
		if !ok {
			t.Fatalf("BlockByID(%d) missing", id)
		}
		if block.RenderClass != RenderClassOpaque {
			t.Fatalf("%s RenderClass = %q, want %q", block.Name, block.RenderClass, RenderClassOpaque)
		}
		if block.CollisionClass != CollisionClassSolid {
			t.Fatalf("%s CollisionClass = %q, want %q", block.Name, block.CollisionClass, CollisionClassSolid)
		}
		if block.OcclusionClass != OcclusionClassOpaque {
			t.Fatalf("%s OcclusionClass = %q, want %q", block.Name, block.OcclusionClass, OcclusionClassOpaque)
		}
		if block.ShadowPolicy != ShadowPolicyOpaque {
			t.Fatalf("%s ShadowPolicy = %q, want %q", block.Name, block.ShadowPolicy, ShadowPolicyOpaque)
		}
		if block.DepthPolicy != DepthPolicyOpaqueWrite {
			t.Fatalf("%s DepthPolicy = %q, want %q", block.Name, block.DepthPolicy, DepthPolicyOpaqueWrite)
		}
		if block.StoragePolicy != StoragePolicyNetworked {
			t.Fatalf("%s StoragePolicy = %q, want %q", block.Name, block.StoragePolicy, StoragePolicyNetworked)
		}
		if block.LiquidPolicy != LiquidPolicyNone {
			t.Fatalf("%s LiquidPolicy = %q, want %q", block.Name, block.LiquidPolicy, LiquidPolicyNone)
		}
		if block.SortPolicy != SortPolicyNone {
			t.Fatalf("%s SortPolicy = %q, want %q", block.Name, block.SortPolicy, SortPolicyNone)
		}
		if block.LightEmission != 0 {
			t.Fatalf("%s LightEmission = %d, want 0", block.Name, block.LightEmission)
		}
		if block.MiningDurationMS <= 0 {
			t.Fatalf("%s MiningDurationMS = %d, want positive duration", block.Name, block.MiningDurationMS)
		}
		if !IsSolid(id) || !IsOpaque(id) || !IsOpaqueSolid(id) || !IsPlaceable(id) {
			t.Fatalf("%s helpers did not preserve solid/opaque/placeable contract", block.Name)
		}
	}
}

func TestUnknownBlockMaterialHelpersAreConservative(t *testing.T) {
	unknown := BlockID(999)
	if IsSolid(unknown) {
		t.Fatal("unknown block should not be solid")
	}
	if IsOpaque(unknown) {
		t.Fatal("unknown block should not be opaque")
	}
	if IsOpaqueSolid(unknown) {
		t.Fatal("unknown block should not be opaque-solid")
	}
	if IsPlaceable(unknown) {
		t.Fatal("unknown block should not be placeable")
	}
}
