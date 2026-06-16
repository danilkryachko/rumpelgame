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

#[derive(Clone, Copy)]
pub struct BlockDefinition {
    pub id: BlockId,
    pub name: &'static str,
    pub solid: bool,
    pub opaque: bool,
    pub cutout_alpha_test: bool,
    pub placeable: bool,
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
        cutout_alpha_test: false,
        placeable: false,
        textures: same_texture(FALLBACK_TEXTURE_TILE),
    },
    BlockDefinition {
        id: STONE,
        name: "Stone",
        solid: true,
        opaque: true,
        cutout_alpha_test: false,
        placeable: true,
        textures: same_texture(TILE_STONE),
    },
    BlockDefinition {
        id: DIRT,
        name: "Dirt",
        solid: true,
        opaque: true,
        cutout_alpha_test: false,
        placeable: true,
        textures: same_texture(TILE_SOIL),
    },
    BlockDefinition {
        id: GRASS,
        name: "Grass",
        solid: true,
        opaque: true,
        cutout_alpha_test: false,
        placeable: true,
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
        cutout_alpha_test: false,
        placeable: true,
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
        cutout_alpha_test: true,
        placeable: true,
        textures: same_texture(TILE_LEAVES),
    },
];

pub(crate) fn definitions() -> &'static [BlockDefinition] {
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

pub fn is_opaque_solid(id: BlockId) -> bool {
    is_solid(id) && definition(id).is_some_and(|block| block.opaque)
}

pub fn is_cutout_alpha_test(id: BlockId) -> bool {
    definition(id).is_some_and(|block| block.cutout_alpha_test)
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
        .filter(|block| block.solid && block.opaque)
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
        .filter(|block| block.solid && block.opaque)
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
