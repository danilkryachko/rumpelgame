pub type BlockId = u32;

pub const AIR: BlockId = 0;
pub const STONE: BlockId = 1;
pub const DIRT: BlockId = 2;
pub const GRASS: BlockId = 3;
pub const WOOD: BlockId = 4;
pub const LEAVES: BlockId = 5;

pub const PLACEABLE_BLOCKS: [BlockId; 5] = [STONE, DIRT, GRASS, WOOD, LEAVES];

const TILE_GRASS_TOP: u32 = 0;
const TILE_GRASS_SIDE: u32 = 1;
const TILE_SOIL: u32 = 2;
const TILE_STONE: u32 = 3;
const TILE_WOOD_SIDE: u32 = 5;
const TILE_WOOD_TOP: u32 = 8;
const TILE_LEAVES: u32 = 9;
const FALLBACK_TEXTURE_TILE: u32 = TILE_STONE;

pub const TEXTURE_TILE_SIZE_PX: u32 = 64;
pub const TEXTURE_ATLAS_COLUMNS: u32 = 10;
pub const TEXTURE_ATLAS_ROWS: u32 = 1;
pub const MAX_TEXTURE_TILE: u32 = TILE_LEAVES;

#[derive(Clone, Copy)]
pub struct BlockTextures {
    pub top: u32,
    pub side: u32,
    pub bottom: u32,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum RenderClass {
    Air,
    Opaque,
    Cutout,
    Transparent,
    Liquid,
}

impl RenderClass {
    pub const ALL: [Self; 5] = [
        Self::Air,
        Self::Opaque,
        Self::Cutout,
        Self::Transparent,
        Self::Liquid,
    ];
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum CollisionClass {
    None,
    Solid,
    Fluid,
    Custom,
}

impl CollisionClass {
    pub const ALL: [Self; 4] = [Self::None, Self::Solid, Self::Fluid, Self::Custom];
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum OcclusionClass {
    None,
    Opaque,
    SameMaterialOnly,
    MaterialPolicy,
}

impl OcclusionClass {
    pub const ALL: [Self; 4] = [
        Self::None,
        Self::Opaque,
        Self::SameMaterialOnly,
        Self::MaterialPolicy,
    ];
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ShadowPolicy {
    None,
    Opaque,
    Transparent,
    MaterialPolicy,
}

impl ShadowPolicy {
    pub const ALL: [Self; 4] = [
        Self::None,
        Self::Opaque,
        Self::Transparent,
        Self::MaterialPolicy,
    ];
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum DepthPolicy {
    None,
    OpaqueWrite,
    DepthTestNoWrite,
    MaterialPolicy,
}

impl DepthPolicy {
    pub const ALL: [Self; 4] = [
        Self::None,
        Self::OpaqueWrite,
        Self::DepthTestNoWrite,
        Self::MaterialPolicy,
    ];
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum StoragePolicy {
    Networked,
    ClientFixtureOnly,
    GeneratedOnly,
}

impl StoragePolicy {
    pub const ALL: [Self; 3] = [
        Self::Networked,
        Self::ClientFixtureOnly,
        Self::GeneratedOnly,
    ];
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum LiquidPolicy {
    None,
    StillLiquid,
    FlowingLiquid,
}

impl LiquidPolicy {
    pub const ALL: [Self; 3] = [Self::None, Self::StillLiquid, Self::FlowingLiquid];
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum SortPolicy {
    None,
    ChunkSubchunkBackToFront,
    FuturePrecise,
}

impl SortPolicy {
    pub const ALL: [Self; 3] = [
        Self::None,
        Self::ChunkSubchunkBackToFront,
        Self::FuturePrecise,
    ];
}

#[derive(Clone, Copy)]
pub struct BlockDefinition {
    pub id: BlockId,
    pub name: &'static str,
    pub solid: bool,
    pub opaque: bool,
    pub placeable: bool,
    pub render_class: RenderClass,
    pub collision_class: CollisionClass,
    pub occlusion_class: OcclusionClass,
    pub shadow_policy: ShadowPolicy,
    pub depth_policy: DepthPolicy,
    pub storage_policy: StoragePolicy,
    pub liquid_policy: LiquidPolicy,
    pub sort_policy: SortPolicy,
    pub light_emission: u8,
    pub textures: BlockTextures,
}

const fn same_texture(tile: u32) -> BlockTextures {
    BlockTextures {
        top: tile,
        side: tile,
        bottom: tile,
    }
}

const BLOCK_DEFINITIONS: [BlockDefinition; 6] = [
    BlockDefinition {
        id: AIR,
        name: "Air",
        solid: false,
        opaque: false,
        placeable: false,
        render_class: RenderClass::Air,
        collision_class: CollisionClass::None,
        occlusion_class: OcclusionClass::None,
        shadow_policy: ShadowPolicy::None,
        depth_policy: DepthPolicy::None,
        storage_policy: StoragePolicy::Networked,
        liquid_policy: LiquidPolicy::None,
        sort_policy: SortPolicy::None,
        light_emission: 0,
        textures: same_texture(FALLBACK_TEXTURE_TILE),
    },
    BlockDefinition {
        id: STONE,
        name: "Stone",
        solid: true,
        opaque: true,
        placeable: true,
        render_class: RenderClass::Opaque,
        collision_class: CollisionClass::Solid,
        occlusion_class: OcclusionClass::Opaque,
        shadow_policy: ShadowPolicy::Opaque,
        depth_policy: DepthPolicy::OpaqueWrite,
        storage_policy: StoragePolicy::Networked,
        liquid_policy: LiquidPolicy::None,
        sort_policy: SortPolicy::None,
        light_emission: 0,
        textures: same_texture(TILE_STONE),
    },
    BlockDefinition {
        id: DIRT,
        name: "Dirt",
        solid: true,
        opaque: true,
        placeable: true,
        render_class: RenderClass::Opaque,
        collision_class: CollisionClass::Solid,
        occlusion_class: OcclusionClass::Opaque,
        shadow_policy: ShadowPolicy::Opaque,
        depth_policy: DepthPolicy::OpaqueWrite,
        storage_policy: StoragePolicy::Networked,
        liquid_policy: LiquidPolicy::None,
        sort_policy: SortPolicy::None,
        light_emission: 0,
        textures: same_texture(TILE_SOIL),
    },
    BlockDefinition {
        id: GRASS,
        name: "Grass",
        solid: true,
        opaque: true,
        placeable: true,
        render_class: RenderClass::Opaque,
        collision_class: CollisionClass::Solid,
        occlusion_class: OcclusionClass::Opaque,
        shadow_policy: ShadowPolicy::Opaque,
        depth_policy: DepthPolicy::OpaqueWrite,
        storage_policy: StoragePolicy::Networked,
        liquid_policy: LiquidPolicy::None,
        sort_policy: SortPolicy::None,
        light_emission: 0,
        textures: BlockTextures {
            top: TILE_GRASS_TOP,
            side: TILE_GRASS_SIDE,
            bottom: TILE_SOIL,
        },
    },
    BlockDefinition {
        id: WOOD,
        name: "Wood",
        solid: true,
        opaque: true,
        placeable: true,
        render_class: RenderClass::Opaque,
        collision_class: CollisionClass::Solid,
        occlusion_class: OcclusionClass::Opaque,
        shadow_policy: ShadowPolicy::Opaque,
        depth_policy: DepthPolicy::OpaqueWrite,
        storage_policy: StoragePolicy::Networked,
        liquid_policy: LiquidPolicy::None,
        sort_policy: SortPolicy::None,
        light_emission: 0,
        textures: BlockTextures {
            top: TILE_WOOD_TOP,
            side: TILE_WOOD_SIDE,
            bottom: TILE_WOOD_TOP,
        },
    },
    BlockDefinition {
        id: LEAVES,
        name: "Leaves",
        solid: true,
        opaque: true,
        placeable: true,
        render_class: RenderClass::Opaque,
        collision_class: CollisionClass::Solid,
        occlusion_class: OcclusionClass::Opaque,
        shadow_policy: ShadowPolicy::Opaque,
        depth_policy: DepthPolicy::OpaqueWrite,
        storage_policy: StoragePolicy::Networked,
        liquid_policy: LiquidPolicy::None,
        sort_policy: SortPolicy::None,
        light_emission: 0,
        textures: same_texture(TILE_LEAVES),
    },
];

fn read_material_policy_contract() {
    let _ = (
        RenderClass::ALL.len(),
        CollisionClass::ALL.len(),
        OcclusionClass::ALL.len(),
        ShadowPolicy::ALL.len(),
        DepthPolicy::ALL.len(),
        StoragePolicy::ALL.len(),
        LiquidPolicy::ALL.len(),
        SortPolicy::ALL.len(),
    );
    for block in BLOCK_DEFINITIONS {
        let _ = (
            block.collision_class,
            block.occlusion_class,
            block.shadow_policy,
            block.depth_policy,
            block.storage_policy,
            block.liquid_policy,
            block.sort_policy,
            block.light_emission,
        );
    }
}

pub(crate) fn definitions() -> &'static [BlockDefinition] {
    read_material_policy_contract();
    &BLOCK_DEFINITIONS
}

pub fn definition(id: BlockId) -> Option<BlockDefinition> {
    definitions().iter().copied().find(|block| block.id == id)
}

pub fn name(id: BlockId) -> &'static str {
    definition(id).map_or("Unknown", |block| block.name)
}

pub fn is_placeable(id: BlockId) -> bool {
    definition(id).is_some_and(|block| block.placeable)
}

pub fn is_solid(id: BlockId) -> bool {
    definition(id).is_some_and(|block| block.solid)
}

pub fn is_opaque(id: BlockId) -> bool {
    definition(id).is_some_and(|block| block.opaque)
}

pub fn is_opaque_solid(id: BlockId) -> bool {
    is_solid(id)
        && is_opaque(id)
        && definition(id).is_some_and(|block| block.render_class == RenderClass::Opaque)
}

pub fn tile_for_face(id: BlockId, face_idx: u32, face_top: u32, face_bottom: u32) -> u32 {
    let Some(block) = definition(id) else {
        return FALLBACK_TEXTURE_TILE;
    };
    if !block.solid {
        return FALLBACK_TEXTURE_TILE;
    }
    if face_idx == face_top {
        block.textures.top
    } else if face_idx == face_bottom {
        block.textures.bottom
    } else {
        block.textures.side
    }
}

pub fn texture_atlas_uv(tile_uv: (f32, f32), tile_index: u32) -> (f32, f32) {
    let columns = TEXTURE_ATLAS_COLUMNS.max(1);
    let rows = TEXTURE_ATLAS_ROWS.max(1);
    let col = tile_index % columns;
    let row = tile_index / columns;
    (
        (col as f32 + tile_uv.0) / columns as f32,
        (row as f32 + tile_uv.1) / rows as f32,
    )
}

pub(crate) fn compute_mesher_glsl_atlas_layout() -> String {
    format!(
        "const float ATLAS_COLUMNS = {}.0;\nconst float ATLAS_ROWS = {}.0;",
        TEXTURE_ATLAS_COLUMNS, TEXTURE_ATLAS_ROWS
    )
}

pub(crate) fn compute_mesher_glsl_block_semantics() -> String {
    let mut source = String::from("// Generated from client/rust_ext/src/blocks.rs.\n");
    source.push_str("uint texture_tile(uint block_id, uint face_idx) {\n");
    for block in definitions()
        .iter()
        .copied()
        .filter(|block| is_opaque_solid(block.id))
    {
        if block.textures.top == block.textures.side && block.textures.side == block.textures.bottom
        {
            source.push_str(&format!(
                "    if (block_id == {}u) return {}u;\n",
                block.id, block.textures.side
            ));
        } else {
            source.push_str(&format!("    if (block_id == {}u) {{\n", block.id));
            source.push_str(&format!(
                "        if (face_idx == FACE_TOP) return {}u;\n",
                block.textures.top
            ));
            source.push_str(&format!(
                "        if (face_idx == FACE_BOTTOM) return {}u;\n",
                block.textures.bottom
            ));
            source.push_str(&format!("        return {}u;\n", block.textures.side));
            source.push_str("    }\n");
        }
    }
    source.push_str(&format!("    return {}u;\n", FALLBACK_TEXTURE_TILE));
    source.push_str("}\n\n");
    source.push_str("bool is_solid(uint block_id) {\n");
    let solid_checks = definitions()
        .iter()
        .copied()
        .filter(|block| is_opaque_solid(block.id))
        .map(|block| format!("block_id == {}u", block.id))
        .collect::<Vec<_>>()
        .join("\n        || ");
    if solid_checks.is_empty() {
        source.push_str("    return false;\n");
    } else {
        source.push_str("    return ");
        source.push_str(&solid_checks);
        source.push_str(";\n");
    }
    source.push_str("}\n");
    source
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn block_material_definitions_are_stable_and_ordered() {
        let want_ids = [AIR, STONE, DIRT, GRASS, WOOD, LEAVES];
        assert_eq!(definitions().len(), want_ids.len());
        for (index, block) in definitions().iter().copied().enumerate() {
            assert_eq!(block.id, want_ids[index]);
            assert_eq!(block.id as usize, index);
        }
    }

    #[test]
    fn block_material_identity_rows_are_stable() {
        #[derive(Debug, Eq, PartialEq)]
        struct ExpectedBlock {
            id: BlockId,
            name: &'static str,
            solid: bool,
            opaque: bool,
            placeable: bool,
            render_class: RenderClass,
            collision_class: CollisionClass,
            occlusion_class: OcclusionClass,
            shadow_policy: ShadowPolicy,
            depth_policy: DepthPolicy,
            storage_policy: StoragePolicy,
            liquid_policy: LiquidPolicy,
            sort_policy: SortPolicy,
            light_emission: u8,
            texture_top: u32,
            texture_side: u32,
            texture_bottom: u32,
        }

        let rows = definitions()
            .iter()
            .map(|block| ExpectedBlock {
                id: block.id,
                name: block.name,
                solid: block.solid,
                opaque: block.opaque,
                placeable: block.placeable,
                render_class: block.render_class,
                collision_class: block.collision_class,
                occlusion_class: block.occlusion_class,
                shadow_policy: block.shadow_policy,
                depth_policy: block.depth_policy,
                storage_policy: block.storage_policy,
                liquid_policy: block.liquid_policy,
                sort_policy: block.sort_policy,
                light_emission: block.light_emission,
                texture_top: block.textures.top,
                texture_side: block.textures.side,
                texture_bottom: block.textures.bottom,
            })
            .collect::<Vec<_>>();
        assert_eq!(
            rows,
            vec![
                ExpectedBlock {
                    id: AIR,
                    name: "Air",
                    solid: false,
                    opaque: false,
                    placeable: false,
                    render_class: RenderClass::Air,
                    collision_class: CollisionClass::None,
                    occlusion_class: OcclusionClass::None,
                    shadow_policy: ShadowPolicy::None,
                    depth_policy: DepthPolicy::None,
                    storage_policy: StoragePolicy::Networked,
                    liquid_policy: LiquidPolicy::None,
                    sort_policy: SortPolicy::None,
                    light_emission: 0,
                    texture_top: FALLBACK_TEXTURE_TILE,
                    texture_side: FALLBACK_TEXTURE_TILE,
                    texture_bottom: FALLBACK_TEXTURE_TILE,
                },
                ExpectedBlock {
                    id: STONE,
                    name: "Stone",
                    solid: true,
                    opaque: true,
                    placeable: true,
                    render_class: RenderClass::Opaque,
                    collision_class: CollisionClass::Solid,
                    occlusion_class: OcclusionClass::Opaque,
                    shadow_policy: ShadowPolicy::Opaque,
                    depth_policy: DepthPolicy::OpaqueWrite,
                    storage_policy: StoragePolicy::Networked,
                    liquid_policy: LiquidPolicy::None,
                    sort_policy: SortPolicy::None,
                    light_emission: 0,
                    texture_top: TILE_STONE,
                    texture_side: TILE_STONE,
                    texture_bottom: TILE_STONE,
                },
                ExpectedBlock {
                    id: DIRT,
                    name: "Dirt",
                    solid: true,
                    opaque: true,
                    placeable: true,
                    render_class: RenderClass::Opaque,
                    collision_class: CollisionClass::Solid,
                    occlusion_class: OcclusionClass::Opaque,
                    shadow_policy: ShadowPolicy::Opaque,
                    depth_policy: DepthPolicy::OpaqueWrite,
                    storage_policy: StoragePolicy::Networked,
                    liquid_policy: LiquidPolicy::None,
                    sort_policy: SortPolicy::None,
                    light_emission: 0,
                    texture_top: TILE_SOIL,
                    texture_side: TILE_SOIL,
                    texture_bottom: TILE_SOIL,
                },
                ExpectedBlock {
                    id: GRASS,
                    name: "Grass",
                    solid: true,
                    opaque: true,
                    placeable: true,
                    render_class: RenderClass::Opaque,
                    collision_class: CollisionClass::Solid,
                    occlusion_class: OcclusionClass::Opaque,
                    shadow_policy: ShadowPolicy::Opaque,
                    depth_policy: DepthPolicy::OpaqueWrite,
                    storage_policy: StoragePolicy::Networked,
                    liquid_policy: LiquidPolicy::None,
                    sort_policy: SortPolicy::None,
                    light_emission: 0,
                    texture_top: TILE_GRASS_TOP,
                    texture_side: TILE_GRASS_SIDE,
                    texture_bottom: TILE_SOIL,
                },
                ExpectedBlock {
                    id: WOOD,
                    name: "Wood",
                    solid: true,
                    opaque: true,
                    placeable: true,
                    render_class: RenderClass::Opaque,
                    collision_class: CollisionClass::Solid,
                    occlusion_class: OcclusionClass::Opaque,
                    shadow_policy: ShadowPolicy::Opaque,
                    depth_policy: DepthPolicy::OpaqueWrite,
                    storage_policy: StoragePolicy::Networked,
                    liquid_policy: LiquidPolicy::None,
                    sort_policy: SortPolicy::None,
                    light_emission: 0,
                    texture_top: TILE_WOOD_TOP,
                    texture_side: TILE_WOOD_SIDE,
                    texture_bottom: TILE_WOOD_TOP,
                },
                ExpectedBlock {
                    id: LEAVES,
                    name: "Leaves",
                    solid: true,
                    opaque: true,
                    placeable: true,
                    render_class: RenderClass::Opaque,
                    collision_class: CollisionClass::Solid,
                    occlusion_class: OcclusionClass::Opaque,
                    shadow_policy: ShadowPolicy::Opaque,
                    depth_policy: DepthPolicy::OpaqueWrite,
                    storage_policy: StoragePolicy::Networked,
                    liquid_policy: LiquidPolicy::None,
                    sort_policy: SortPolicy::None,
                    light_emission: 0,
                    texture_top: TILE_LEAVES,
                    texture_side: TILE_LEAVES,
                    texture_bottom: TILE_LEAVES,
                },
            ]
        );
    }

    #[test]
    fn texture_atlas_tile_identity_rows_are_stable() {
        #[derive(Debug, Eq, PartialEq)]
        struct ExpectedTile {
            id: u32,
            name: &'static str,
        }

        let rows = vec![
            ExpectedTile {
                id: TILE_GRASS_TOP,
                name: "grass_top",
            },
            ExpectedTile {
                id: TILE_GRASS_SIDE,
                name: "grass_side",
            },
            ExpectedTile {
                id: TILE_SOIL,
                name: "soil",
            },
            ExpectedTile {
                id: TILE_STONE,
                name: "stone",
            },
            ExpectedTile {
                id: TILE_WOOD_SIDE,
                name: "wood_side",
            },
            ExpectedTile {
                id: TILE_WOOD_TOP,
                name: "wood_top",
            },
            ExpectedTile {
                id: TILE_LEAVES,
                name: "leaves",
            },
        ];
        assert_eq!(
            rows,
            vec![
                ExpectedTile {
                    id: 0,
                    name: "grass_top",
                },
                ExpectedTile {
                    id: 1,
                    name: "grass_side",
                },
                ExpectedTile {
                    id: 2,
                    name: "soil",
                },
                ExpectedTile {
                    id: 3,
                    name: "stone",
                },
                ExpectedTile {
                    id: 5,
                    name: "wood_side",
                },
                ExpectedTile {
                    id: 8,
                    name: "wood_top",
                },
                ExpectedTile {
                    id: 9,
                    name: "leaves",
                },
            ]
        );

        let tile_capacity = TEXTURE_ATLAS_COLUMNS * TEXTURE_ATLAS_ROWS;
        assert_eq!(TEXTURE_TILE_SIZE_PX, 64);
        assert_eq!(TEXTURE_ATLAS_COLUMNS, 10);
        assert_eq!(TEXTURE_ATLAS_ROWS, 1);
        assert_eq!(tile_capacity, 10);
        assert_eq!(MAX_TEXTURE_TILE, TILE_LEAVES);
        assert_eq!(FALLBACK_TEXTURE_TILE, TILE_STONE);
        assert!(MAX_TEXTURE_TILE < tile_capacity);
    }

    #[test]
    fn block_material_textures_reference_guarded_atlas_tiles() {
        let guarded_tiles = [
            TILE_GRASS_TOP,
            TILE_GRASS_SIDE,
            TILE_SOIL,
            TILE_STONE,
            TILE_WOOD_SIDE,
            TILE_WOOD_TOP,
            TILE_LEAVES,
        ];
        let tile_capacity = TEXTURE_ATLAS_COLUMNS * TEXTURE_ATLAS_ROWS;

        assert!(guarded_tiles.contains(&FALLBACK_TEXTURE_TILE));

        for block in definitions() {
            for (slot, tile) in [
                ("top", block.textures.top),
                ("side", block.textures.side),
                ("bottom", block.textures.bottom),
            ] {
                assert!(
                    guarded_tiles.contains(&tile),
                    "block {} {} texture tile {} is not guarded",
                    block.name,
                    slot,
                    tile
                );
                assert!(
                    tile <= MAX_TEXTURE_TILE,
                    "block {} {} texture tile {} exceeds MAX_TEXTURE_TILE {}",
                    block.name,
                    slot,
                    tile,
                    MAX_TEXTURE_TILE
                );
                assert!(
                    tile < tile_capacity,
                    "block {} {} texture tile {} exceeds atlas capacity {}",
                    block.name,
                    slot,
                    tile,
                    tile_capacity
                );
            }
        }

        for tile in guarded_tiles {
            let (min_u, min_v) = texture_atlas_uv((0.0, 0.0), tile);
            let (max_u, max_v) = texture_atlas_uv((1.0, 1.0), tile);
            assert!(min_u >= 0.0 && min_v >= 0.0);
            assert!(max_u <= 1.0 && max_v <= 1.0);
            assert!(min_u < max_u);
            assert!(min_v < max_v);
        }
    }

    #[test]
    fn block_material_current_networked_blocks_preserve_opaque_contract() {
        let air = definition(AIR).expect("air definition");
        assert_eq!(air.render_class, RenderClass::Air);
        assert_eq!(air.collision_class, CollisionClass::None);
        assert_eq!(air.occlusion_class, OcclusionClass::None);
        assert_eq!(air.shadow_policy, ShadowPolicy::None);
        assert_eq!(air.depth_policy, DepthPolicy::None);
        assert_eq!(air.storage_policy, StoragePolicy::Networked);
        assert_eq!(air.liquid_policy, LiquidPolicy::None);
        assert_eq!(air.sort_policy, SortPolicy::None);
        assert_eq!(air.light_emission, 0);
        assert!(!air.solid);
        assert!(!air.opaque);
        assert!(!air.placeable);

        for block_id in PLACEABLE_BLOCKS {
            let block = definition(block_id).expect("placeable block definition");
            assert_eq!(block.render_class, RenderClass::Opaque);
            assert_eq!(block.collision_class, CollisionClass::Solid);
            assert_eq!(block.occlusion_class, OcclusionClass::Opaque);
            assert_eq!(block.shadow_policy, ShadowPolicy::Opaque);
            assert_eq!(block.depth_policy, DepthPolicy::OpaqueWrite);
            assert_eq!(block.storage_policy, StoragePolicy::Networked);
            assert_eq!(block.liquid_policy, LiquidPolicy::None);
            assert_eq!(block.sort_policy, SortPolicy::None);
            assert_eq!(block.light_emission, 0);
            assert!(is_solid(block_id));
            assert!(is_opaque(block_id));
            assert!(is_opaque_solid(block_id));
            assert!(is_placeable(block_id));
        }
    }

    #[test]
    fn block_material_unknown_blocks_are_conservative() {
        let unknown = u32::MAX;
        assert!(definition(unknown).is_none());
        assert!(!is_solid(unknown));
        assert!(!is_opaque(unknown));
        assert!(!is_opaque_solid(unknown));
        assert!(!is_placeable(unknown));
        assert_eq!(tile_for_face(unknown, 0, 0, 1), FALLBACK_TEXTURE_TILE);
    }

    #[test]
    fn block_material_policy_variant_sets_are_explicit() {
        assert_eq!(RenderClass::ALL.len(), 5);
        assert_eq!(CollisionClass::ALL.len(), 4);
        assert_eq!(OcclusionClass::ALL.len(), 4);
        assert_eq!(ShadowPolicy::ALL.len(), 4);
        assert_eq!(DepthPolicy::ALL.len(), 4);
        assert_eq!(StoragePolicy::ALL.len(), 3);
        assert_eq!(LiquidPolicy::ALL.len(), 3);
        assert_eq!(SortPolicy::ALL.len(), 3);
    }
}
