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

pub const TEXTURE_TILE_SIZE_PX: u32 = 64;
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

pub fn definition(id: BlockId) -> Option<BlockDefinition> {
    let block = match id {
        AIR => BlockDefinition {
            id: AIR,
            name: "Air",
            solid: false,
            placeable: false,
            textures: same_texture(TILE_STONE),
        },
        STONE => BlockDefinition {
            id: STONE,
            name: "Stone",
            solid: true,
            placeable: true,
            textures: same_texture(TILE_STONE),
        },
        DIRT => BlockDefinition {
            id: DIRT,
            name: "Dirt",
            solid: true,
            placeable: true,
            textures: same_texture(TILE_SOIL),
        },
        GRASS => BlockDefinition {
            id: GRASS,
            name: "Grass",
            solid: true,
            placeable: true,
            textures: BlockTextures {
                top: TILE_GRASS_TOP,
                side: TILE_GRASS_SIDE,
                bottom: TILE_SOIL,
            },
        },
        WOOD => BlockDefinition {
            id: WOOD,
            name: "Wood",
            solid: true,
            placeable: true,
            textures: BlockTextures {
                top: TILE_WOOD_TOP,
                side: TILE_WOOD_SIDE,
                bottom: TILE_WOOD_TOP,
            },
        },
        LEAVES => BlockDefinition {
            id: LEAVES,
            name: "Leaves",
            solid: true,
            placeable: true,
            textures: same_texture(TILE_LEAVES),
        },
        _ => return None,
    };
    debug_assert_eq!(block.id, id);
    Some(block)
}

pub fn name(id: BlockId) -> &'static str {
    definition(id).map_or("Unknown", |block| block.name)
}

pub fn is_placeable(id: BlockId) -> bool {
    definition(id).is_some_and(|block| block.placeable)
}

pub fn tile_for_face(id: BlockId, face_idx: u32, face_top: u32, face_bottom: u32) -> u32 {
    let Some(block) = definition(id) else {
        return TILE_STONE;
    };
    if !block.solid {
        return TILE_STONE;
    }
    if face_idx == face_top {
        block.textures.top
    } else if face_idx == face_bottom {
        block.textures.bottom
    } else {
        block.textures.side
    }
}
