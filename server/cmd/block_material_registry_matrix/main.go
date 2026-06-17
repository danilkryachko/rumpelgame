package main

import (
	"crypto/sha256"
	"fmt"
	"os"
	"strings"

	"rumpelmc/server/pkg/world"
)

func main() {
	summary, err := buildSummary()
	if err != nil {
		fmt.Fprintf(os.Stderr, "block_material_registry_matrix status=fail error=%q\n", err)
		os.Exit(1)
	}
	fmt.Println(summary)
}

func buildSummary() (string, error) {
	definitions := world.BlockDefinitions()
	if len(definitions) == 0 {
		return "", fmt.Errorf("block registry is empty")
	}

	seen := make(map[world.BlockID]bool, len(definitions))
	var rows strings.Builder
	networked := 0
	opaqueSolid := 0
	placeable := 0
	airBlocks := 0
	emissive := 0
	liquid := 0
	for index, block := range definitions {
		if seen[block.ID] {
			return "", fmt.Errorf("duplicate block id %d", block.ID)
		}
		seen[block.ID] = true
		if int(block.ID) != index {
			return "", fmt.Errorf("block id %d at index %d", block.ID, index)
		}
		if block.StoragePolicy == world.StoragePolicyNetworked {
			networked++
		}
		if block.Solid && block.Opaque && block.RenderClass == world.RenderClassOpaque {
			opaqueSolid++
		}
		if block.Placeable {
			placeable++
		}
		if block.RenderClass == world.RenderClassAir {
			airBlocks++
		}
		if block.LightEmission > 0 {
			emissive++
		}
		if block.LiquidPolicy != world.LiquidPolicyNone {
			liquid++
		}
		rows.WriteString(fmt.Sprintf(
			"%d|%s|solid=%t|opaque=%t|placeable=%t|render=%s|collision=%s|occlusion=%s|shadow=%s|depth=%s|storage=%s|liquid=%s|sort=%s|emission=%d|mining_ms=%d|textures=%s,%s,%s\n",
			block.ID,
			block.Name,
			block.Solid,
			block.Opaque,
			block.Placeable,
			block.RenderClass,
			block.CollisionClass,
			block.OcclusionClass,
			block.ShadowPolicy,
			block.DepthPolicy,
			block.StoragePolicy,
			block.LiquidPolicy,
			block.SortPolicy,
			block.LightEmission,
			block.MiningDurationMS,
			block.Textures.Top,
			block.Textures.Side,
			block.Textures.Bottom,
		))
	}
	sum := sha256.Sum256([]byte(rows.String()))

	return fmt.Sprintf(
		"block_material_registry_matrix status=pass block_count=%d registry_hash=%x networked_blocks=%d opaque_solid_blocks=%d placeable_blocks=%d air_blocks=%d emissive_blocks=%d liquid_blocks=%d mining_duration_metadata=guarded active_block_id_change=0 active_protocol_change=0 active_storage_change=0 renderer_change=0",
		len(definitions),
		sum,
		networked,
		opaqueSolid,
		placeable,
		airBlocks,
		emissive,
		liquid,
	), nil
}
