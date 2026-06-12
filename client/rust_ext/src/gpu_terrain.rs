use crate::blocks;
use godot::classes::rendering_device::{
    CompareOperator, DataFormat, DrawFlags, PolygonCullMode, PolygonFrontFace, RenderPrimitive,
    SamplerFilter, SamplerRepeatMode, ShaderLanguage, ShaderStage, StorageBufferUsage,
    TextureSamples, TextureType, TextureUsageBits, UniformType,
};
use godot::classes::{
    Image, RdPipelineColorBlendState, RdPipelineColorBlendStateAttachment,
    RdPipelineDepthStencilState, RdPipelineMultisampleState, RdPipelineRasterizationState,
    RdSamplerState, RdShaderSource, RdTextureFormat, RdTextureView, RdUniform, RenderData,
    RenderSceneBuffersRd, RenderingDevice, RenderingServer, ResourceLoader, Texture2D,
};
use godot::prelude::*;
use std::collections::HashMap;
use std::sync::OnceLock;
use std::time::Instant;

const BLOCK_ATLAS_PATH: &str = "res://assets/textures/blocks/block_texture_atlas.png";
const CHUNK_W: usize = 32;
const SUBCHUNK_H: usize = 32;
const CHUNK_D: usize = 32;
const PADDED_W: usize = 34;
const PADDED_H: usize = 34;
const PADDED_D: usize = 34;
const BLOCK_BYTES: usize = 2;
const PACKED_FACE_BYTES: usize = std::mem::size_of::<PackedFace>();
const INDIRECT_DRAW_FIELD_COUNT: usize = 4;
const INDIRECT_DRAW_BYTES: usize = INDIRECT_DRAW_FIELD_COUNT * std::mem::size_of::<u32>();
const CLIP_FROM_WORLD_PUSH_CONSTANT_BYTES: usize = 64;
const TERRAIN_LIGHTING_PUSH_CONSTANT_BYTES: usize = 32;
const TERRAIN_ATLAS_PUSH_CONSTANT_BYTES: usize = 16;
const TERRAIN_PUSH_CONSTANT_BYTES: usize = CLIP_FROM_WORLD_PUSH_CONSTANT_BYTES
    + TERRAIN_LIGHTING_PUSH_CONSTANT_BYTES
    + TERRAIN_ATLAS_PUSH_CONSTANT_BYTES;
const MAX_GPU_TERRAIN_FACES: usize = 4_194_304;
const MAX_INDIRECT_DRAWS: usize = 8192;
const MAX_CPU_ARRAY_MESH_VERTICES: usize = 100_000;
const MAX_CPU_PROXY_VERTICES: usize = 100_000;
const DEBUG_OFFSCREEN_SIZE: u32 = 256;
const DEFAULT_TERRAIN_AMBIENT: f32 = 0.55;
const DEFAULT_TERRAIN_LIGHT_ENERGY: f32 = 0.45;
const GPU_TERRAIN_TIMESTAMP_BEGIN: &str = "rumpel_gpu_terrain_begin";
const GPU_TERRAIN_TIMESTAMP_END: &str = "rumpel_gpu_terrain_end";
const GPU_TERRAIN_COMPOSITOR_DRAW_REPEAT_ENV: &str = "RUMPELMC_GPU_TERRAIN_COMPOSITOR_DRAW_REPEAT";
const MAX_GPU_TERRAIN_COMPOSITOR_DRAW_REPEAT: u32 = 64;
const GPU_TERRAIN_CULL_MODE_ENV: &str = "RUMPELMC_GPU_TERRAIN_CULL_MODE";

pub const FACE_LEFT: u32 = 0;
pub const FACE_RIGHT: u32 = 1;
pub const FACE_BOTTOM: u32 = 2;
pub const FACE_TOP: u32 = 3;
pub const FACE_BACK: u32 = 4;
pub const FACE_FRONT: u32 = 5;

const FACE_NEIGHBOR_OFFSETS: [(u32, usize, usize, usize); 6] = [
    (FACE_LEFT, 0, 1, 1),
    (FACE_RIGHT, 2, 1, 1),
    (FACE_BOTTOM, 1, 0, 1),
    (FACE_TOP, 1, 2, 1),
    (FACE_BACK, 1, 1, 0),
    (FACE_FRONT, 1, 1, 2),
];

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct PackedFace {
    pub pos_face_tile: u32,
    pub block_flags: u32,
    pub extent: u32,
    pub _pad: u32,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct PackedFaceExtent {
    u: u32,
    v: u32,
}

impl PackedFace {
    pub fn new(x: u32, y: u32, z: u32, face: u32, tile: u32, block_id: u32) -> Self {
        Self::with_extent(
            x,
            y,
            z,
            face,
            tile,
            block_id,
            PackedFaceExtent { u: 1, v: 1 },
        )
    }

    fn with_extent(
        x: u32,
        y: u32,
        z: u32,
        face: u32,
        tile: u32,
        block_id: u32,
        extent: PackedFaceExtent,
    ) -> Self {
        debug_assert!(x < 64);
        debug_assert!(y < 64);
        debug_assert!(z < 64);
        debug_assert!(face < 8);
        debug_assert!(tile < 2048);
        debug_assert!(extent.u > 0 && extent.u < 64);
        debug_assert!(extent.v > 0 && extent.v < 64);
        Self {
            pos_face_tile: x | (y << 6) | (z << 12) | (face << 18) | (tile << 21),
            block_flags: block_id & 0xffff,
            extent: extent.u | (extent.v << 6),
            _pad: 0,
        }
    }

    fn face(self) -> u32 {
        (self.pos_face_tile >> 18) & 0x7
    }

    fn x(self) -> u32 {
        self.pos_face_tile & 0x3f
    }

    fn y(self) -> u32 {
        (self.pos_face_tile >> 6) & 0x3f
    }

    fn z(self) -> u32 {
        (self.pos_face_tile >> 12) & 0x3f
    }

    fn tile(self) -> u32 {
        (self.pos_face_tile >> 21) & 0x7ff
    }

    fn block_id(self) -> u32 {
        self.block_flags & 0xffff
    }

    fn extent_u(self) -> u32 {
        self.extent & 0x3f
    }

    fn extent_v(self) -> u32 {
        (self.extent >> 6) & 0x3f
    }
}

#[derive(Debug, Default)]
pub struct PackedFaceBatch {
    faces: Vec<PackedFace>,
}

pub struct CpuProxyMesh {
    pub vertices: PackedVector3Array,
    pub normals: PackedVector3Array,
    pub indices: PackedInt32Array,
}

pub struct CpuArrayMesh {
    pub vertices: PackedVector3Array,
    pub normals: PackedVector3Array,
    pub uvs: PackedVector2Array,
    pub indices: PackedInt32Array,
    pub reported_vertex_count: usize,
}

impl PackedFaceBatch {
    #[cfg(test)]
    fn faces(&self) -> &[PackedFace] {
        &self.faces
    }

    pub fn face_count(&self) -> usize {
        self.faces.len()
    }

    pub fn byte_len(&self) -> usize {
        self.faces.len() * PACKED_FACE_BYTES
    }

    pub fn build_cpu_proxy_mesh(&self) -> CpuProxyMesh {
        let proxy_vertices = self.cpu_proxy_vertices();
        let mut vertices = Vec::with_capacity(proxy_vertices.len());
        let mut normals = Vec::with_capacity(proxy_vertices.len());

        for (point, normal) in proxy_vertices {
            vertices.push(point);
            normals.push(normal);
        }

        CpuProxyMesh {
            vertices: PackedVector3Array::from(vertices),
            normals: PackedVector3Array::from(normals),
            indices: PackedInt32Array::new(),
        }
    }

    pub fn build_compact_cpu_proxy_mesh(&self) -> CpuProxyMesh {
        CpuProxyMesh {
            vertices: PackedVector3Array::from(self.cpu_proxy_positions()),
            normals: PackedVector3Array::new(),
            indices: PackedInt32Array::new(),
        }
    }

    pub fn build_indexed_compact_cpu_proxy_mesh(&self) -> CpuProxyMesh {
        let (positions, indices) = self.indexed_cpu_proxy_positions();
        CpuProxyMesh {
            vertices: PackedVector3Array::from(positions),
            normals: PackedVector3Array::new(),
            indices: PackedInt32Array::from(indices),
        }
    }

    pub fn build_collision_faces(&self) -> PackedVector3Array {
        PackedVector3Array::from(self.collision_face_positions())
    }

    pub fn build_cpu_array_mesh(&self) -> CpuArrayMesh {
        let reported_vertex_capacity = self.cpu_array_mesh_vertex_capacity();
        let mut vertices = Vec::with_capacity(reported_vertex_capacity / 6 * 4);
        let mut normals = Vec::with_capacity(vertices.capacity());
        let mut uvs = Vec::with_capacity(vertices.capacity());
        let mut indices = Vec::with_capacity(reported_vertex_capacity);

        for face in &self.faces {
            if !append_indexed_cpu_array_mesh_face_to_arrays(
                *face,
                &mut vertices,
                &mut normals,
                &mut uvs,
                &mut indices,
                MAX_CPU_ARRAY_MESH_VERTICES,
            ) {
                break;
            }
        }

        let reported_vertex_count = indices.len();
        CpuArrayMesh {
            vertices: PackedVector3Array::from(vertices),
            normals: PackedVector3Array::from(normals),
            uvs: PackedVector2Array::from(uvs),
            indices: PackedInt32Array::from(indices),
            reported_vertex_count,
        }
    }

    fn cpu_proxy_vertices(&self) -> Vec<(Vector3, Vector3)> {
        let mut vertices = Vec::new();
        for face in &self.faces {
            if vertices.len() + 6 > MAX_CPU_PROXY_VERTICES {
                break;
            }
            append_cpu_proxy_face(*face, &mut vertices);
        }
        vertices
    }

    fn cpu_proxy_positions(&self) -> Vec<Vector3> {
        let mut vertices = Vec::new();
        for face in &self.faces {
            if vertices.len() + 6 > MAX_CPU_PROXY_VERTICES {
                break;
            }
            append_cpu_proxy_face_positions(*face, &mut vertices);
        }
        vertices
    }

    fn indexed_cpu_proxy_positions(&self) -> (Vec<Vector3>, Vec<i32>) {
        let mut vertices = Vec::new();
        let mut indices = Vec::new();
        for face_idx in [
            FACE_LEFT,
            FACE_RIGHT,
            FACE_BOTTOM,
            FACE_TOP,
            FACE_BACK,
            FACE_FRONT,
        ] {
            if vertices.len() + 4 > MAX_CPU_PROXY_VERTICES {
                break;
            }
            append_greedy_indexed_cpu_proxy_face_positions(
                &self.faces,
                face_idx,
                &mut vertices,
                &mut indices,
            );
        }
        (vertices, indices)
    }

    fn collision_face_positions(&self) -> Vec<Vector3> {
        let mut vertices = Vec::new();
        for face_idx in [
            FACE_LEFT,
            FACE_RIGHT,
            FACE_BOTTOM,
            FACE_TOP,
            FACE_BACK,
            FACE_FRONT,
        ] {
            if vertices.len() + 6 > MAX_CPU_PROXY_VERTICES {
                break;
            }
            append_greedy_collision_face_positions(&self.faces, face_idx, &mut vertices);
        }
        vertices
    }

    #[cfg(test)]
    fn cpu_array_mesh_vertices(&self) -> Vec<(Vector3, Vector3, Vector2)> {
        let mut vertices = Vec::with_capacity(self.cpu_array_mesh_vertex_capacity());
        for face in &self.faces {
            append_cpu_array_mesh_face(*face, &mut vertices);
        }
        vertices
    }

    #[cfg(test)]
    fn indexed_cpu_array_mesh_arrays(
        &self,
    ) -> (Vec<Vector3>, Vec<Vector3>, Vec<Vector2>, Vec<i32>) {
        let reported_vertex_capacity = self.cpu_array_mesh_vertex_capacity();
        let mut vertices = Vec::with_capacity(reported_vertex_capacity / 6 * 4);
        let mut normals = Vec::with_capacity(vertices.capacity());
        let mut uvs = Vec::with_capacity(vertices.capacity());
        let mut indices = Vec::with_capacity(reported_vertex_capacity);

        for face in &self.faces {
            if !append_indexed_cpu_array_mesh_face_to_arrays(
                *face,
                &mut vertices,
                &mut normals,
                &mut uvs,
                &mut indices,
                MAX_CPU_ARRAY_MESH_VERTICES,
            ) {
                break;
            }
        }

        (vertices, normals, uvs, indices)
    }

    fn cpu_array_mesh_vertex_capacity(&self) -> usize {
        self.faces
            .iter()
            .map(|face| {
                (face.extent_u() as usize)
                    .saturating_mul(face.extent_v() as usize)
                    .saturating_mul(6)
            })
            .sum::<usize>()
            .min(MAX_CPU_ARRAY_MESH_VERTICES)
    }

    fn to_bytes_for_subchunk(&self, key: GpuSubchunkKey) -> Vec<u8> {
        let chunk_x_bits = pack_signed_i16(key.chunk_x) << 16;
        let chunk_z_bits = pack_signed_i16(key.chunk_z) << 16;
        let sub_y_bits = pack_signed_i16(key.sub_y);
        let mut bytes = Vec::with_capacity(self.byte_len());
        for face in &self.faces {
            let block_flags = (face.block_flags & 0x0000_ffff) | chunk_x_bits;
            let extent = (face.extent & 0x0000_ffff) | chunk_z_bits;
            bytes.extend_from_slice(&face.pos_face_tile.to_le_bytes());
            bytes.extend_from_slice(&block_flags.to_le_bytes());
            bytes.extend_from_slice(&extent.to_le_bytes());
            bytes.extend_from_slice(&sub_y_bits.to_le_bytes());
        }
        bytes
    }
}

#[cfg(test)]
fn append_cpu_array_mesh_face(face: PackedFace, vertices: &mut Vec<(Vector3, Vector3, Vector2)>) {
    let normal = cpu_proxy_face_normal(face.face());
    let uvs = cpu_array_mesh_face_uvs(face.face());
    let tile = face.tile();

    for corners in unit_face_rects(face) {
        if vertices.len() + 6 > MAX_CPU_ARRAY_MESH_VERTICES {
            return;
        }
        for idx in [0usize, 2, 1, 0, 3, 2] {
            vertices.push((corners[idx], normal, atlas_uv(uvs[idx], tile)));
        }
    }
}

fn append_indexed_cpu_array_mesh_face_to_arrays(
    face: PackedFace,
    vertices: &mut Vec<Vector3>,
    normals: &mut Vec<Vector3>,
    out_uvs: &mut Vec<Vector2>,
    indices: &mut Vec<i32>,
    max_reported_vertices: usize,
) -> bool {
    let normal = cpu_proxy_face_normal(face.face());
    let uvs = cpu_array_mesh_face_uvs(face.face());
    let tile = face.tile();

    for corners in unit_face_rects(face) {
        if indices.len() + 6 > max_reported_vertices {
            return false;
        }
        let base = vertices.len() as i32;
        for idx in 0..4 {
            vertices.push(corners[idx]);
            normals.push(normal);
            out_uvs.push(atlas_uv(uvs[idx], tile));
        }
        indices.extend_from_slice(&[base, base + 2, base + 1, base, base + 3, base + 2]);
    }
    true
}

fn append_cpu_proxy_face(face: PackedFace, vertices: &mut Vec<(Vector3, Vector3)>) {
    let normal = cpu_proxy_face_normal(face.face());
    let corners = packed_face_rect_corners(face);

    for idx in [0usize, 2, 1, 0, 3, 2] {
        vertices.push((corners[idx], normal));
    }
}

fn append_cpu_proxy_face_positions(face: PackedFace, vertices: &mut Vec<Vector3>) {
    let corners = packed_face_rect_corners(face);

    for idx in [0usize, 2, 1, 0, 3, 2] {
        vertices.push(corners[idx]);
    }
}

fn packed_face_rect_corners(face: PackedFace) -> [Vector3; 4] {
    let (plane, u, v) = collision_face_plane_uv(face);
    rect_face_corners(
        face.face(),
        plane,
        u,
        v,
        face.extent_u() as usize,
        face.extent_v() as usize,
    )
}

fn unit_face_rects(face: PackedFace) -> impl Iterator<Item = [Vector3; 4]> {
    let (plane, u, v) = collision_face_plane_uv(face);
    let face_idx = face.face();
    (0..face.extent_v() as usize).flat_map(move |dv| {
        (0..face.extent_u() as usize)
            .map(move |du| rect_face_corners(face_idx, plane, u + du, v + dv, 1, 1))
    })
}

fn append_greedy_indexed_cpu_proxy_face_positions(
    faces: &[PackedFace],
    face_idx: u32,
    vertices: &mut Vec<Vector3>,
    indices: &mut Vec<i32>,
) {
    visit_greedy_face_rects_by_key(
        faces,
        face_idx,
        greedy_face_merge_key,
        |face_idx, plane, u, v, width, height| {
            if vertices.len() + 4 > MAX_CPU_PROXY_VERTICES {
                return false;
            }
            let corners = rect_face_corners(face_idx, plane, u, v, width, height);
            append_indexed_rect_face_positions(&corners, vertices, indices);
            true
        },
    );
}

fn append_greedy_collision_face_positions(
    faces: &[PackedFace],
    face_idx: u32,
    vertices: &mut Vec<Vector3>,
) {
    visit_greedy_face_rects_by_key(
        faces,
        face_idx,
        |_| 0,
        |face_idx, plane, u, v, width, height| {
            if vertices.len() + 6 > MAX_CPU_PROXY_VERTICES {
                return false;
            }
            append_collision_rect_face_positions(face_idx, plane, u, v, width, height, vertices);
            true
        },
    );
}

fn visit_greedy_face_rects_by_key(
    faces: &[PackedFace],
    face_idx: u32,
    key: impl Fn(PackedFace) -> u32,
    mut visit: impl FnMut(u32, usize, usize, usize, usize, usize) -> bool,
) {
    const GRID: usize = CHUNK_W;
    const GRID_CELLS: usize = GRID * GRID;
    const PLANES: usize = GRID + 1;

    let mut cells = vec![None; PLANES * GRID_CELLS];
    for face in faces {
        if face.face() != face_idx {
            continue;
        }
        mark_greedy_face_cells(*face, key(*face), &mut cells);
    }

    for plane in 0..PLANES {
        for v in 0..GRID {
            let mut u = 0;
            while u < GRID {
                let idx = collision_grid_index(plane, u, v);
                let Some(cell_key) = cells[idx] else {
                    u += 1;
                    continue;
                };

                let mut width = 1;
                while u + width < GRID
                    && cells[collision_grid_index(plane, u + width, v)] == Some(cell_key)
                {
                    width += 1;
                }

                let mut height = 1;
                'height: while v + height < GRID {
                    for du in 0..width {
                        if cells[collision_grid_index(plane, u + du, v + height)] != Some(cell_key)
                        {
                            break 'height;
                        }
                    }
                    height += 1;
                }

                for dv in 0..height {
                    for du in 0..width {
                        cells[collision_grid_index(plane, u + du, v + dv)] = None;
                    }
                }
                if !visit(face_idx, plane, u, v, width, height) {
                    return;
                }
                u += width;
            }
        }
    }
}

fn mark_greedy_face_cells(face: PackedFace, key: u32, cells: &mut [Option<u32>]) {
    let (plane, u, v) = collision_face_plane_uv(face);
    for dv in 0..face.extent_v() as usize {
        for du in 0..face.extent_u() as usize {
            cells[collision_grid_index(plane, u + du, v + dv)] = Some(key);
        }
    }
}

fn collision_face_plane_uv(face: PackedFace) -> (usize, usize, usize) {
    match face.face() {
        FACE_LEFT => (face.x() as usize, face.z() as usize, face.y() as usize),
        FACE_RIGHT => (face.x() as usize + 1, face.z() as usize, face.y() as usize),
        FACE_BOTTOM => (face.y() as usize, face.x() as usize, face.z() as usize),
        FACE_TOP => (face.y() as usize + 1, face.x() as usize, face.z() as usize),
        FACE_BACK => (face.z() as usize, face.x() as usize, face.y() as usize),
        _ => (face.z() as usize + 1, face.x() as usize, face.y() as usize),
    }
}

fn collision_grid_index(plane: usize, u: usize, v: usize) -> usize {
    const GRID: usize = CHUNK_W;
    plane * GRID * GRID + v * GRID + u
}

fn append_collision_rect_face_positions(
    face_idx: u32,
    plane: usize,
    u: usize,
    v: usize,
    width: usize,
    height: usize,
    vertices: &mut Vec<Vector3>,
) {
    let corners = rect_face_corners(face_idx, plane, u, v, width, height);
    for idx in [0usize, 2, 1, 0, 3, 2] {
        vertices.push(corners[idx]);
    }
}

fn append_indexed_rect_face_positions(
    corners: &[Vector3; 4],
    vertices: &mut Vec<Vector3>,
    indices: &mut Vec<i32>,
) {
    let base_index = vertices.len() as i32;
    vertices.extend_from_slice(corners);
    indices.extend_from_slice(&[
        base_index,
        base_index + 2,
        base_index + 1,
        base_index,
        base_index + 3,
        base_index + 2,
    ]);
}

fn rect_face_corners(
    face_idx: u32,
    plane: usize,
    u: usize,
    v: usize,
    width: usize,
    height: usize,
) -> [Vector3; 4] {
    let plane = plane as f32;
    let u0 = u as f32;
    let v0 = v as f32;
    let u1 = (u + width) as f32;
    let v1 = (v + height) as f32;
    match face_idx {
        FACE_LEFT => [
            Vector3::new(plane, v0, u1),
            Vector3::new(plane, v1, u1),
            Vector3::new(plane, v1, u0),
            Vector3::new(plane, v0, u0),
        ],
        FACE_RIGHT => [
            Vector3::new(plane, v0, u0),
            Vector3::new(plane, v1, u0),
            Vector3::new(plane, v1, u1),
            Vector3::new(plane, v0, u1),
        ],
        FACE_BOTTOM => [
            Vector3::new(u0, plane, v1),
            Vector3::new(u0, plane, v0),
            Vector3::new(u1, plane, v0),
            Vector3::new(u1, plane, v1),
        ],
        FACE_TOP => [
            Vector3::new(u0, plane, v0),
            Vector3::new(u0, plane, v1),
            Vector3::new(u1, plane, v1),
            Vector3::new(u1, plane, v0),
        ],
        FACE_BACK => [
            Vector3::new(u1, v0, plane),
            Vector3::new(u0, v0, plane),
            Vector3::new(u0, v1, plane),
            Vector3::new(u1, v1, plane),
        ],
        _ => [
            Vector3::new(u0, v0, plane),
            Vector3::new(u1, v0, plane),
            Vector3::new(u1, v1, plane),
            Vector3::new(u0, v1, plane),
        ],
    }
}

fn cpu_array_mesh_face_uvs(face_idx: u32) -> [Vector2; 4] {
    match face_idx {
        FACE_LEFT | FACE_RIGHT => [
            Vector2::new(0.0, 1.0),
            Vector2::new(0.0, 0.0),
            Vector2::new(1.0, 0.0),
            Vector2::new(1.0, 1.0),
        ],
        FACE_BACK => [
            Vector2::new(1.0, 1.0),
            Vector2::new(0.0, 1.0),
            Vector2::new(0.0, 0.0),
            Vector2::new(1.0, 0.0),
        ],
        FACE_FRONT => [
            Vector2::new(0.0, 1.0),
            Vector2::new(1.0, 1.0),
            Vector2::new(1.0, 0.0),
            Vector2::new(0.0, 0.0),
        ],
        _ => [
            Vector2::new(0.0, 0.0),
            Vector2::new(0.0, 1.0),
            Vector2::new(1.0, 1.0),
            Vector2::new(1.0, 0.0),
        ],
    }
}

fn atlas_uv(tile_uv: Vector2, tile_index: u32) -> Vector2 {
    let (u, v) = blocks::texture_atlas_uv((tile_uv.x, tile_uv.y), tile_index);
    Vector2::new(u, v)
}

fn cpu_proxy_face_normal(face_idx: u32) -> Vector3 {
    match face_idx {
        FACE_LEFT => Vector3::new(-1.0, 0.0, 0.0),
        FACE_RIGHT => Vector3::new(1.0, 0.0, 0.0),
        FACE_BOTTOM => Vector3::new(0.0, -1.0, 0.0),
        FACE_TOP => Vector3::new(0.0, 1.0, 0.0),
        FACE_BACK => Vector3::new(0.0, 0.0, -1.0),
        _ => Vector3::new(0.0, 0.0, 1.0),
    }
}

fn pack_signed_i16(value: i32) -> u32 {
    let value = value.clamp(i16::MIN as i32, i16::MAX as i32) as i16;
    u16::from_le_bytes(value.to_le_bytes()) as u32
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub struct GpuSubchunkKey {
    pub chunk_x: i32,
    pub sub_y: i32,
    pub chunk_z: i32,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct FaceRange {
    start: usize,
    len: usize,
}

impl FaceRange {
    fn end(self) -> usize {
        self.start + self.len
    }
}

#[derive(Debug)]
struct FaceRangeAllocator {
    free_ranges: Vec<FaceRange>,
}

impl FaceRangeAllocator {
    fn new(capacity: usize) -> Self {
        Self {
            free_ranges: vec![FaceRange {
                start: 0,
                len: capacity,
            }],
        }
    }

    fn allocate(&mut self, len: usize) -> Option<FaceRange> {
        if len == 0 {
            return Some(FaceRange { start: 0, len: 0 });
        }

        let idx = self
            .free_ranges
            .iter()
            .enumerate()
            .filter(|(_, range)| range.len >= len)
            .min_by_key(|(_, range)| range.len)
            .map(|(idx, _)| idx)?;
        let allocated = FaceRange {
            start: self.free_ranges[idx].start,
            len,
        };

        self.free_ranges[idx].start += len;
        self.free_ranges[idx].len -= len;
        if self.free_ranges[idx].len == 0 {
            self.free_ranges.remove(idx);
        }

        Some(allocated)
    }

    fn free(&mut self, range: FaceRange) {
        if range.len == 0 {
            return;
        }

        self.free_ranges.push(range);
        self.free_ranges.sort_by_key(|range| range.start);

        let mut merged: Vec<FaceRange> = Vec::with_capacity(self.free_ranges.len());
        for range in self.free_ranges.drain(..) {
            if let Some(last) = merged.last_mut()
                && last.end() == range.start
            {
                last.len += range.len;
                continue;
            }
            merged.push(range);
        }
        self.free_ranges = merged;
    }

    fn stats(&self) -> FaceAllocatorStats {
        let mut free_faces = 0usize;
        let mut largest_free_faces = 0usize;
        for range in &self.free_ranges {
            free_faces += range.len;
            largest_free_faces = largest_free_faces.max(range.len);
        }
        FaceAllocatorStats {
            free_ranges: self.free_ranges.len(),
            free_faces,
            largest_free_faces,
        }
    }
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
struct FaceAllocatorStats {
    free_ranges: usize,
    free_faces: usize,
    largest_free_faces: usize,
}

impl FaceAllocatorStats {
    fn fragmented_free_faces(&self) -> usize {
        self.free_faces.saturating_sub(self.largest_free_faces)
    }

    fn fragmentation_pct(&self) -> f64 {
        if self.free_faces == 0 {
            0.0
        } else {
            self.fragmented_free_faces() as f64 * 100.0 / self.free_faces as f64
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum UploadFailureKind {
    Capacity,
    Fragmentation,
}

fn upload_failure_kind(stats: FaceAllocatorStats, requested_faces: usize) -> UploadFailureKind {
    if stats.free_faces >= requested_faces {
        UploadFailureKind::Fragmentation
    } else {
        UploadFailureKind::Capacity
    }
}

#[derive(Clone, Copy, Debug)]
pub struct GpuTerrainSlot {
    pub start_face: usize,
    pub face_count: usize,
}

#[repr(C)]
#[derive(Clone, Copy, Debug)]
struct IndirectDrawCommand {
    // RenderingDevice uses the Vulkan-style DrawIndirectCommand ABI:
    // vertex_count, instance_count, first_vertex, first_instance. Terrain binds
    // no vertex buffer, so first_vertex stays zero, but first_instance is not
    // spare: the shader consumes it through gl_InstanceIndex as the face-buffer
    // base for each subchunk slot.
    vertex_count: u32,
    instance_count: u32,
    first_vertex: u32,
    first_instance: u32,
}

fn draw_command_active_bytes(draw_count: usize) -> usize {
    draw_count.saturating_mul(INDIRECT_DRAW_BYTES)
}

fn draw_command_capacity_bytes(max_draws: usize) -> usize {
    max_draws.saturating_mul(INDIRECT_DRAW_BYTES)
}

impl IndirectDrawCommand {
    fn for_slot(slot: GpuTerrainSlot) -> Self {
        Self {
            vertex_count: 6,
            instance_count: slot.face_count as u32,
            first_vertex: 0,
            first_instance: slot.start_face as u32,
        }
    }

    fn append_bytes(self, bytes: &mut Vec<u8>) {
        bytes.extend_from_slice(&self.vertex_count.to_le_bytes());
        bytes.extend_from_slice(&self.instance_count.to_le_bytes());
        bytes.extend_from_slice(&self.first_vertex.to_le_bytes());
        bytes.extend_from_slice(&self.first_instance.to_le_bytes());
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct DrawCommandRemoval {
    index: usize,
    moved_key: Option<GpuSubchunkKey>,
}

fn insert_draw_key(
    draw_keys: &mut Vec<GpuSubchunkKey>,
    draw_indices: &mut HashMap<GpuSubchunkKey, usize>,
    key: GpuSubchunkKey,
    max_draws: usize,
) -> Option<usize> {
    if draw_keys.len() >= max_draws {
        return None;
    }

    let draw_index = draw_keys.len();
    draw_keys.push(key);
    draw_indices.insert(key, draw_index);
    Some(draw_index)
}

fn remove_draw_key(
    draw_keys: &mut Vec<GpuSubchunkKey>,
    draw_indices: &mut HashMap<GpuSubchunkKey, usize>,
    key: GpuSubchunkKey,
) -> Option<DrawCommandRemoval> {
    let draw_index = draw_indices.remove(&key)?;
    let last_key = draw_keys.pop()?;
    let moved_key = if last_key == key {
        None
    } else {
        draw_keys[draw_index] = last_key;
        draw_indices.insert(last_key, draw_index);
        Some(last_key)
    };

    Some(DrawCommandRemoval {
        index: draw_index,
        moved_key,
    })
}

#[derive(Clone, Copy, Debug, Default)]
pub struct GpuTerrainStats {
    pub subchunks: usize,
    pub faces: usize,
    pub bytes: usize,
    pub draw_count: usize,
    pub draw_command_bytes: usize,
    pub draw_command_capacity_bytes: usize,
    pub draw_command_stride_bytes: usize,
    pub compositor_draw_repeat: u32,
    pub compositor_effective_draw_count: usize,
    pub compositor_frames: u64,
    pub scene_target_create_count: u64,
    pub scene_target_reuse_count: u64,
    pub scene_target_replace_count: u64,
    pub uniform_set_create_count: u64,
    pub atlas_texture_create_count: u64,
    pub atlas_sampler_create_count: u64,
    pub push_constant_bytes: usize,
    pub push_constant_update_count: u64,
    pub push_constant_total_bytes: u64,
    pub avg_push_constant_bytes: f64,
    pub push_constant_camera_bytes: usize,
    pub push_constant_lighting_bytes: usize,
    pub push_constant_atlas_bytes: usize,
    pub upload_count: u64,
    pub upload_bytes: usize,
    pub last_upload_bytes: usize,
    pub last_upload_ms: f64,
    pub avg_upload_ms: f64,
    pub max_upload_ms: f64,
    pub last_upload_encode_ms: f64,
    pub avg_upload_encode_ms: f64,
    pub max_upload_encode_ms: f64,
    pub last_upload_stage_ms: f64,
    pub avg_upload_stage_ms: f64,
    pub max_upload_stage_ms: f64,
    pub last_upload_update_ms: f64,
    pub avg_upload_update_ms: f64,
    pub max_upload_update_ms: f64,
    pub upload_failures: u64,
    pub upload_capacity_failures: u64,
    pub upload_fragmentation_failures: u64,
    pub free_ranges: usize,
    pub free_faces: usize,
    pub largest_free_faces: usize,
    pub fragmented_free_faces: usize,
    pub fragmentation_pct: f64,
    pub draw_rebuild_count: u64,
    pub last_draw_rebuild_ms: f64,
    pub avg_draw_rebuild_ms: f64,
    pub max_draw_rebuild_ms: f64,
    pub draw_patch_count: u64,
    pub last_draw_patch_ms: f64,
    pub avg_draw_patch_ms: f64,
    pub max_draw_patch_ms: f64,
    pub compositor_submit_count: u64,
    pub last_compositor_submit_ms: f64,
    pub avg_compositor_submit_ms: f64,
    pub max_compositor_submit_ms: f64,
    pub last_compositor_submit_breakdown_ms: GpuCompositorSubmitBreakdown,
    pub max_compositor_submit_breakdown_ms: GpuCompositorSubmitBreakdown,
    pub compositor_gpu_sample_count: u64,
    pub last_compositor_gpu_ms: f64,
    pub avg_compositor_gpu_ms: f64,
    pub max_compositor_gpu_ms: f64,
}

#[derive(Clone, Copy, Debug, Default)]
pub struct GpuCompositorSubmitBreakdown {
    pub setup_ms: f64,
    pub target_ms: f64,
    pub constants_ms: f64,
    pub draw_ms: f64,
}

#[derive(Clone, Copy, Debug)]
pub struct GpuTerrainLighting {
    pub direction_to_light: Vector3,
    pub color: Color,
    pub energy: f32,
    pub ambient: f32,
}

impl GpuTerrainLighting {
    pub fn directional(direction_to_light: Vector3, color: Color, energy: f32) -> Self {
        Self {
            direction_to_light,
            color,
            energy,
            ambient: DEFAULT_TERRAIN_AMBIENT,
        }
        .sanitized()
    }

    fn sanitized(self) -> Self {
        Self {
            direction_to_light: normalized_or_default_light_direction(self.direction_to_light),
            color: Color::from_rgb(
                sanitize_non_negative(self.color.r, 1.0),
                sanitize_non_negative(self.color.g, 1.0),
                sanitize_non_negative(self.color.b, 1.0),
            ),
            energy: sanitize_non_negative(self.energy, DEFAULT_TERRAIN_LIGHT_ENERGY),
            ambient: sanitize_non_negative(self.ambient, DEFAULT_TERRAIN_AMBIENT).min(1.0),
        }
    }
}

impl Default for GpuTerrainLighting {
    fn default() -> Self {
        Self {
            direction_to_light: default_light_direction_to_light(),
            color: Color::WHITE,
            energy: DEFAULT_TERRAIN_LIGHT_ENERGY,
            ambient: DEFAULT_TERRAIN_AMBIENT,
        }
    }
}

struct GpuTerrainRenderPipeline {
    shader_rid: Rid,
    uniform_set_rid: Rid,
    offscreen_render_pipeline_rid: Rid,
    framebuffer_rid: Rid,
    color_texture_rid: Rid,
    atlas_texture_rid: Rid,
    atlas_sampler_rid: Rid,
    atlas_layout: GpuTerrainAtlasLayout,
    scene_target: Option<GpuTerrainSceneTarget>,
    vertex_format: i64,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct GpuTerrainAtlasLayout {
    columns: u32,
    rows: u32,
}

impl GpuTerrainAtlasLayout {
    fn from_image_size(width: i32, height: i32) -> Option<Self> {
        let tile_size = blocks::TEXTURE_TILE_SIZE_PX as i32;
        if width <= 0 || height <= 0 || width % tile_size != 0 || height % tile_size != 0 {
            return None;
        }

        let columns = (width / tile_size) as u32;
        let rows = (height / tile_size) as u32;
        let tile_capacity = columns.checked_mul(rows)?;
        if tile_capacity == 0 || blocks::MAX_TEXTURE_TILE >= tile_capacity {
            return None;
        }

        Some(Self { columns, rows })
    }

    fn push_constant_values(self) -> [f32; 4] {
        [
            1.0 / self.columns as f32,
            1.0 / self.rows as f32,
            self.columns as f32,
            self.rows as f32,
        ]
    }
}

struct GpuTerrainSceneTarget {
    color_texture_rid: Rid,
    depth_texture_rid: Rid,
    framebuffer_rid: Rid,
    render_pipeline_rid: Rid,
    view_count: u32,
}

pub struct GpuTerrainCompositor {
    compositor_rid: Rid,
    effect_rid: Rid,
    camera_rid: Rid,
}

impl GpuTerrainCompositor {
    pub fn new(callback: &Callable) -> Option<Self> {
        let mut rs = RenderingServer::singleton();
        let effect_rid = rs.compositor_effect_create();
        let compositor_rid = rs.compositor_create();
        if effect_rid.is_invalid() || compositor_rid.is_invalid() {
            godot_print!("GPU terrain compositor: failed to create compositor RIDs");
            if effect_rid.is_valid() {
                rs.free_rid(effect_rid);
            }
            if compositor_rid.is_valid() {
                rs.free_rid(compositor_rid);
            }
            return None;
        }

        rs.compositor_effect_set_enabled(effect_rid, true);
        rs.compositor_effect_set_flag(
            effect_rid,
            godot::classes::rendering_server::CompositorEffectFlags::ACCESS_RESOLVED_COLOR,
            true,
        );
        rs.compositor_effect_set_flag(
            effect_rid,
            godot::classes::rendering_server::CompositorEffectFlags::ACCESS_RESOLVED_DEPTH,
            true,
        );
        rs.compositor_effect_set_callback(
            effect_rid,
            godot::classes::rendering_server::CompositorEffectCallbackType::POST_OPAQUE,
            callback,
        );

        let effects = Array::from_iter([effect_rid]);
        rs.compositor_set_compositor_effects(compositor_rid, &effects);

        Some(Self {
            compositor_rid,
            effect_rid,
            camera_rid: Rid::Invalid,
        })
    }

    pub fn attach_to_camera(&mut self, camera_rid: Rid) -> bool {
        if camera_rid.is_invalid() || self.camera_rid == camera_rid {
            return false;
        }

        RenderingServer::singleton().camera_set_compositor(camera_rid, self.compositor_rid);
        self.camera_rid = camera_rid;
        true
    }

    pub fn detach_from_camera(&mut self) {
        if self.camera_rid.is_invalid() {
            return;
        }

        RenderingServer::singleton().camera_set_compositor(self.camera_rid, Rid::Invalid);
        self.camera_rid = Rid::Invalid;
    }

    pub fn is_attached(&self) -> bool {
        self.camera_rid.is_valid()
    }
}

impl Drop for GpuTerrainCompositor {
    fn drop(&mut self) {
        self.detach_from_camera();
        let mut rs = RenderingServer::singleton();
        rs.free_rid(self.compositor_rid);
        rs.free_rid(self.effect_rid);
    }
}

pub struct GpuTerrainBufferPool {
    rd: Gd<RenderingDevice>,
    faces_buffer_rid: Rid,
    indirect_buffer_rid: Rid,
    allocator: FaceRangeAllocator,
    slots: HashMap<GpuSubchunkKey, GpuTerrainSlot>,
    draw_keys: Vec<GpuSubchunkKey>,
    draw_indices: HashMap<GpuSubchunkKey, usize>,
    render_pipeline: Option<GpuTerrainRenderPipeline>,
    used_faces: usize,
    draw_count: usize,
    draw_dirty: bool,
    debug_offscreen_rendered: bool,
    compositor_frames: u64,
    scene_target_create_count: u64,
    scene_target_reuse_count: u64,
    scene_target_replace_count: u64,
    uniform_set_create_count: u64,
    atlas_texture_create_count: u64,
    atlas_sampler_create_count: u64,
    push_constant_bytes: usize,
    push_constant_update_count: u64,
    push_constant_total_bytes: u64,
    compositor_logged: bool,
    lighting: GpuTerrainLighting,
    upload_count: u64,
    upload_bytes: usize,
    last_upload_bytes: usize,
    last_upload_ms: f64,
    avg_upload_ms: f64,
    max_upload_ms: f64,
    last_upload_encode_ms: f64,
    avg_upload_encode_ms: f64,
    max_upload_encode_ms: f64,
    last_upload_stage_ms: f64,
    avg_upload_stage_ms: f64,
    max_upload_stage_ms: f64,
    last_upload_update_ms: f64,
    avg_upload_update_ms: f64,
    max_upload_update_ms: f64,
    upload_failures: u64,
    upload_capacity_failures: u64,
    upload_fragmentation_failures: u64,
    draw_rebuild_count: u64,
    avg_draw_rebuild_ms: f64,
    max_draw_rebuild_ms: f64,
    last_draw_rebuild_ms: f64,
    draw_patch_count: u64,
    avg_draw_patch_ms: f64,
    max_draw_patch_ms: f64,
    last_draw_patch_ms: f64,
    compositor_submit_count: u64,
    avg_compositor_submit_ms: f64,
    max_compositor_submit_ms: f64,
    last_compositor_submit_ms: f64,
    last_compositor_submit_breakdown_ms: GpuCompositorSubmitBreakdown,
    max_compositor_submit_breakdown_ms: GpuCompositorSubmitBreakdown,
    compositor_gpu_sample_count: u64,
    avg_compositor_gpu_ms: f64,
    max_compositor_gpu_ms: f64,
    last_compositor_gpu_ms: f64,
    last_compositor_gpu_timestamp_frame: Option<u64>,
}

impl GpuTerrainBufferPool {
    pub fn new(enable_debug_render: bool) -> Option<Self> {
        let rs = RenderingServer::singleton();
        let mut rd = match rs.get_rendering_device() {
            Some(device) => device,
            None => {
                godot_print!("GPU terrain: global RenderingDevice is unavailable");
                return None;
            }
        };

        let faces_bytes = (MAX_GPU_TERRAIN_FACES * PACKED_FACE_BYTES) as u32;
        let indirect_bytes = draw_command_capacity_bytes(MAX_INDIRECT_DRAWS) as u32;
        let faces_buffer_rid = rd.storage_buffer_create(faces_bytes);
        let indirect_buffer_rid = rd
            .storage_buffer_create_ex(indirect_bytes)
            .usage(StorageBufferUsage::DISPATCH_INDIRECT)
            .done();
        let render_pipeline = if enable_debug_render {
            Self::create_debug_render_pipeline(&mut rd, faces_buffer_rid)
        } else {
            None
        };
        let immutable_binding_create_count = u64::from(render_pipeline.is_some());

        Some(Self {
            rd,
            faces_buffer_rid,
            indirect_buffer_rid,
            allocator: FaceRangeAllocator::new(MAX_GPU_TERRAIN_FACES),
            slots: HashMap::new(),
            draw_keys: Vec::new(),
            draw_indices: HashMap::new(),
            render_pipeline,
            used_faces: 0,
            draw_count: 0,
            draw_dirty: false,
            debug_offscreen_rendered: false,
            compositor_frames: 0,
            scene_target_create_count: 0,
            scene_target_reuse_count: 0,
            scene_target_replace_count: 0,
            uniform_set_create_count: immutable_binding_create_count,
            atlas_texture_create_count: immutable_binding_create_count,
            atlas_sampler_create_count: immutable_binding_create_count,
            push_constant_bytes: 0,
            push_constant_update_count: 0,
            push_constant_total_bytes: 0,
            compositor_logged: false,
            lighting: GpuTerrainLighting::default(),
            upload_count: 0,
            upload_bytes: 0,
            last_upload_bytes: 0,
            last_upload_ms: 0.0,
            avg_upload_ms: 0.0,
            max_upload_ms: 0.0,
            last_upload_encode_ms: 0.0,
            avg_upload_encode_ms: 0.0,
            max_upload_encode_ms: 0.0,
            last_upload_stage_ms: 0.0,
            avg_upload_stage_ms: 0.0,
            max_upload_stage_ms: 0.0,
            last_upload_update_ms: 0.0,
            avg_upload_update_ms: 0.0,
            max_upload_update_ms: 0.0,
            upload_failures: 0,
            upload_capacity_failures: 0,
            upload_fragmentation_failures: 0,
            draw_rebuild_count: 0,
            avg_draw_rebuild_ms: 0.0,
            max_draw_rebuild_ms: 0.0,
            last_draw_rebuild_ms: 0.0,
            draw_patch_count: 0,
            avg_draw_patch_ms: 0.0,
            max_draw_patch_ms: 0.0,
            last_draw_patch_ms: 0.0,
            compositor_submit_count: 0,
            avg_compositor_submit_ms: 0.0,
            max_compositor_submit_ms: 0.0,
            last_compositor_submit_ms: 0.0,
            last_compositor_submit_breakdown_ms: GpuCompositorSubmitBreakdown::default(),
            max_compositor_submit_breakdown_ms: GpuCompositorSubmitBreakdown::default(),
            compositor_gpu_sample_count: 0,
            avg_compositor_gpu_ms: 0.0,
            max_compositor_gpu_ms: 0.0,
            last_compositor_gpu_ms: 0.0,
            last_compositor_gpu_timestamp_frame: None,
        })
    }

    pub fn upload_subchunk(
        &mut self,
        key: GpuSubchunkKey,
        batch: &PackedFaceBatch,
    ) -> Option<GpuTerrainSlot> {
        self.remove_subchunk(key);
        if batch.face_count() == 0 {
            return None;
        }

        let upload_start = Instant::now();
        let Some(range) = self.allocator.allocate(batch.face_count()) else {
            self.record_upload_failure(batch.face_count());
            return None;
        };
        let encode_start = Instant::now();
        let bytes = batch.to_bytes_for_subchunk(key);
        let upload_encode_ms = encode_start.elapsed().as_secs_f64() * 1000.0;
        let stage_start = Instant::now();
        let pba = PackedByteArray::from(bytes.as_slice());
        let upload_stage_ms = stage_start.elapsed().as_secs_f64() * 1000.0;
        let offset = (range.start * PACKED_FACE_BYTES) as u32;
        let update_start = Instant::now();
        self.rd
            .buffer_update(self.faces_buffer_rid, offset, pba.len() as u32, &pba);
        let upload_update_ms = update_start.elapsed().as_secs_f64() * 1000.0;
        self.upload_count += 1;
        self.upload_bytes += pba.len();
        self.last_upload_bytes = pba.len();
        self.record_upload_timing(
            upload_start.elapsed().as_secs_f64() * 1000.0,
            upload_encode_ms,
            upload_stage_ms,
            upload_update_ms,
        );

        let slot = GpuTerrainSlot {
            start_face: range.start,
            face_count: range.len,
        };
        self.slots.insert(key, slot);
        self.used_faces += range.len;
        self.insert_draw_command(key, slot);
        Some(slot)
    }

    fn record_upload_timing(
        &mut self,
        upload_ms: f64,
        upload_encode_ms: f64,
        upload_stage_ms: f64,
        upload_update_ms: f64,
    ) {
        self.last_upload_ms = upload_ms;
        let n = self.upload_count as f64;
        self.avg_upload_ms += (upload_ms - self.avg_upload_ms) / n;
        self.max_upload_ms = self.max_upload_ms.max(upload_ms);
        self.last_upload_encode_ms = upload_encode_ms;
        self.avg_upload_encode_ms += (upload_encode_ms - self.avg_upload_encode_ms) / n;
        self.max_upload_encode_ms = self.max_upload_encode_ms.max(upload_encode_ms);
        self.last_upload_stage_ms = upload_stage_ms;
        self.avg_upload_stage_ms += (upload_stage_ms - self.avg_upload_stage_ms) / n;
        self.max_upload_stage_ms = self.max_upload_stage_ms.max(upload_stage_ms);
        self.last_upload_update_ms = upload_update_ms;
        self.avg_upload_update_ms += (upload_update_ms - self.avg_upload_update_ms) / n;
        self.max_upload_update_ms = self.max_upload_update_ms.max(upload_update_ms);
    }

    pub fn remove_subchunk(&mut self, key: GpuSubchunkKey) {
        let Some(slot) = self.slots.remove(&key) else {
            return;
        };

        self.remove_draw_command(key);
        self.used_faces = self.used_faces.saturating_sub(slot.face_count);
        self.allocator.free(FaceRange {
            start: slot.start_face,
            len: slot.face_count,
        });
    }

    pub fn has_subchunk(&self, key: GpuSubchunkKey) -> bool {
        self.slots.contains_key(&key)
    }

    pub fn stats(&self) -> GpuTerrainStats {
        let allocator_stats = self.allocator.stats();
        GpuTerrainStats {
            subchunks: self.slots.len(),
            faces: self.used_faces,
            bytes: self.used_faces * PACKED_FACE_BYTES,
            draw_count: self.draw_count,
            draw_command_bytes: draw_command_active_bytes(self.draw_count),
            draw_command_capacity_bytes: draw_command_capacity_bytes(MAX_INDIRECT_DRAWS),
            draw_command_stride_bytes: INDIRECT_DRAW_BYTES,
            compositor_draw_repeat: gpu_terrain_compositor_draw_repeat(),
            compositor_effective_draw_count: self
                .draw_count
                .saturating_mul(gpu_terrain_compositor_draw_repeat() as usize),
            compositor_frames: self.compositor_frames,
            scene_target_create_count: self.scene_target_create_count,
            scene_target_reuse_count: self.scene_target_reuse_count,
            scene_target_replace_count: self.scene_target_replace_count,
            uniform_set_create_count: self.uniform_set_create_count,
            atlas_texture_create_count: self.atlas_texture_create_count,
            atlas_sampler_create_count: self.atlas_sampler_create_count,
            push_constant_bytes: self.push_constant_bytes,
            push_constant_update_count: self.push_constant_update_count,
            push_constant_total_bytes: self.push_constant_total_bytes,
            avg_push_constant_bytes: if self.push_constant_update_count == 0 {
                0.0
            } else {
                self.push_constant_total_bytes as f64 / self.push_constant_update_count as f64
            },
            push_constant_camera_bytes: CLIP_FROM_WORLD_PUSH_CONSTANT_BYTES,
            push_constant_lighting_bytes: TERRAIN_LIGHTING_PUSH_CONSTANT_BYTES,
            push_constant_atlas_bytes: TERRAIN_ATLAS_PUSH_CONSTANT_BYTES,
            upload_count: self.upload_count,
            upload_bytes: self.upload_bytes,
            last_upload_bytes: self.last_upload_bytes,
            last_upload_ms: self.last_upload_ms,
            avg_upload_ms: self.avg_upload_ms,
            max_upload_ms: self.max_upload_ms,
            last_upload_encode_ms: self.last_upload_encode_ms,
            avg_upload_encode_ms: self.avg_upload_encode_ms,
            max_upload_encode_ms: self.max_upload_encode_ms,
            last_upload_stage_ms: self.last_upload_stage_ms,
            avg_upload_stage_ms: self.avg_upload_stage_ms,
            max_upload_stage_ms: self.max_upload_stage_ms,
            last_upload_update_ms: self.last_upload_update_ms,
            avg_upload_update_ms: self.avg_upload_update_ms,
            max_upload_update_ms: self.max_upload_update_ms,
            upload_failures: self.upload_failures,
            upload_capacity_failures: self.upload_capacity_failures,
            upload_fragmentation_failures: self.upload_fragmentation_failures,
            free_ranges: allocator_stats.free_ranges,
            free_faces: allocator_stats.free_faces,
            largest_free_faces: allocator_stats.largest_free_faces,
            fragmented_free_faces: allocator_stats.fragmented_free_faces(),
            fragmentation_pct: allocator_stats.fragmentation_pct(),
            draw_rebuild_count: self.draw_rebuild_count,
            last_draw_rebuild_ms: self.last_draw_rebuild_ms,
            avg_draw_rebuild_ms: self.avg_draw_rebuild_ms,
            max_draw_rebuild_ms: self.max_draw_rebuild_ms,
            draw_patch_count: self.draw_patch_count,
            last_draw_patch_ms: self.last_draw_patch_ms,
            avg_draw_patch_ms: self.avg_draw_patch_ms,
            max_draw_patch_ms: self.max_draw_patch_ms,
            compositor_submit_count: self.compositor_submit_count,
            last_compositor_submit_ms: self.last_compositor_submit_ms,
            avg_compositor_submit_ms: self.avg_compositor_submit_ms,
            max_compositor_submit_ms: self.max_compositor_submit_ms,
            last_compositor_submit_breakdown_ms: self.last_compositor_submit_breakdown_ms,
            max_compositor_submit_breakdown_ms: self.max_compositor_submit_breakdown_ms,
            compositor_gpu_sample_count: self.compositor_gpu_sample_count,
            last_compositor_gpu_ms: self.last_compositor_gpu_ms,
            avg_compositor_gpu_ms: self.avg_compositor_gpu_ms,
            max_compositor_gpu_ms: self.max_compositor_gpu_ms,
        }
    }

    pub fn set_lighting(&mut self, lighting: GpuTerrainLighting) {
        self.lighting = lighting.sanitized();
    }

    pub fn render_ready(&self) -> bool {
        self.render_pipeline.is_some()
    }

    pub fn visible_render_confirmed(&self) -> bool {
        self.render_ready() && self.compositor_frames > 0
    }

    pub fn render_debug_offscreen_once(&mut self) {
        if self.debug_offscreen_rendered || self.render_pipeline.is_none() || self.slots.is_empty()
        {
            return;
        }

        self.rebuild_draw_buffers_if_needed();
        if self.draw_count == 0 {
            return;
        }

        let Some(render_pipeline) = &self.render_pipeline else {
            return;
        };
        let clear_colors = PackedColorArray::from_iter([Color::from_rgba(0.0, 0.0, 0.0, 1.0)]);
        let draw_list = self
            .rd
            .draw_list_begin_ex(render_pipeline.framebuffer_rid)
            .draw_flags(DrawFlags::CLEAR_COLOR_ALL)
            .clear_color_values(&clear_colors)
            .done();
        if draw_list < 0 {
            return;
        }

        self.rd.draw_list_bind_render_pipeline(
            draw_list,
            render_pipeline.offscreen_render_pipeline_rid,
        );
        self.rd
            .draw_list_bind_uniform_set(draw_list, render_pipeline.uniform_set_rid, 0);
        self.rd.draw_list_bind_vertex_buffers_format(
            draw_list,
            render_pipeline.vertex_format,
            6,
            &Array::new(),
        );
        let push_constants =
            push_constants_for_debug_projection(self.lighting, render_pipeline.atlas_layout);
        self.record_push_constant_update(push_constants.len());
        self.rd.draw_list_set_push_constant(
            draw_list,
            &push_constants,
            push_constants.len() as u32,
        );
        self.rd
            .draw_list_draw_indirect_ex(draw_list, false, self.indirect_buffer_rid)
            .draw_count(self.draw_count as u32)
            .stride(INDIRECT_DRAW_BYTES as u32)
            .done();
        self.rd.draw_list_end();
        self.debug_offscreen_rendered = true;
        godot_print!(
            "GPU terrain offscreen debug draw: draws={} faces={}",
            self.draw_count,
            self.used_faces
        );
    }

    pub fn render_compositor(&mut self, _callback_type: i32, render_data: Gd<RenderData>) {
        self.record_captured_compositor_gpu_timestamps();
        if self.render_pipeline.is_none() || self.slots.is_empty() {
            return;
        }
        let submit_start = Instant::now();
        let mut phase_start = Instant::now();
        let mut submit_breakdown = GpuCompositorSubmitBreakdown::default();

        let Some(scene_buffers) = render_data.get_render_scene_buffers() else {
            return;
        };
        let Ok(scene_buffers) = scene_buffers.try_cast::<RenderSceneBuffersRd>() else {
            return;
        };

        let size = scene_buffers.get_internal_size();
        if size.x <= 0 || size.y <= 0 {
            return;
        }

        self.rebuild_draw_buffers_if_needed();
        if self.draw_count == 0 {
            return;
        }

        let color_texture_rid = scene_buffers.get_color_layer(0);
        if color_texture_rid.is_invalid() {
            return;
        }
        let depth_texture_rid = scene_buffers.get_depth_layer(0);

        let view_count = scene_buffers.get_view_count().max(1);
        submit_breakdown.setup_ms = phase_start.elapsed().as_secs_f64() * 1000.0;
        phase_start = Instant::now();
        let Some((framebuffer_rid, render_pipeline_rid, vertex_format, uniform_set_rid)) =
            self.ensure_scene_target(color_texture_rid, depth_texture_rid, view_count)
        else {
            return;
        };
        submit_breakdown.target_ms = phase_start.elapsed().as_secs_f64() * 1000.0;
        phase_start = Instant::now();
        let Some(atlas_layout) = self
            .render_pipeline
            .as_ref()
            .map(|pipeline| pipeline.atlas_layout)
        else {
            return;
        };
        let push_constants =
            clip_from_world_push_constants(&render_data, self.lighting, atlas_layout);
        submit_breakdown.constants_ms = phase_start.elapsed().as_secs_f64() * 1000.0;
        phase_start = Instant::now();

        self.rd.capture_timestamp(GPU_TERRAIN_TIMESTAMP_BEGIN);
        let draw_list = self.rd.draw_list_begin(framebuffer_rid);
        if draw_list < 0 {
            return;
        }

        self.rd
            .draw_list_bind_render_pipeline(draw_list, render_pipeline_rid);
        self.rd
            .draw_list_bind_uniform_set(draw_list, uniform_set_rid, 0);
        self.rd
            .draw_list_bind_vertex_buffers_format(draw_list, vertex_format, 6, &Array::new());
        self.record_push_constant_update(push_constants.len());
        self.rd.draw_list_set_push_constant(
            draw_list,
            &push_constants,
            push_constants.len() as u32,
        );
        let draw_repeat = gpu_terrain_compositor_draw_repeat();
        for _ in 0..draw_repeat {
            self.rd
                .draw_list_draw_indirect_ex(draw_list, false, self.indirect_buffer_rid)
                .draw_count(self.draw_count as u32)
                .stride(INDIRECT_DRAW_BYTES as u32)
                .done();
        }
        self.rd.draw_list_end();
        self.rd.capture_timestamp(GPU_TERRAIN_TIMESTAMP_END);
        submit_breakdown.draw_ms = phase_start.elapsed().as_secs_f64() * 1000.0;

        self.compositor_frames += 1;
        self.record_compositor_submit_ms(
            submit_start.elapsed().as_secs_f64() * 1000.0,
            submit_breakdown,
        );
        if !self.compositor_logged {
            self.compositor_logged = true;
            godot_print!(
                "GPU terrain compositor draw: size={}x{} views={} depth={} draws={} repeat={} effective_draws={} faces={}",
                size.x,
                size.y,
                view_count,
                depth_texture_rid.is_valid(),
                self.draw_count,
                draw_repeat,
                self.draw_count.saturating_mul(draw_repeat as usize),
                self.used_faces
            );
        }
    }

    fn ensure_scene_target(
        &mut self,
        color_texture_rid: Rid,
        depth_texture_rid: Rid,
        view_count: u32,
    ) -> Option<(Rid, Rid, i64, Rid)> {
        let target_matches = self
            .render_pipeline
            .as_ref()
            .and_then(|pipeline| pipeline.scene_target.as_ref())
            .is_some_and(|target| {
                target.color_texture_rid == color_texture_rid
                    && target.depth_texture_rid == depth_texture_rid
                    && target.view_count == view_count
            });
        if target_matches {
            self.scene_target_reuse_count += 1;
            let pipeline = self.render_pipeline.as_ref()?;
            let target = pipeline.scene_target.as_ref()?;
            return Some((
                target.framebuffer_rid,
                target.render_pipeline_rid,
                pipeline.vertex_format,
                pipeline.uniform_set_rid,
            ));
        }

        let (shader_rid, vertex_format, uniform_set_rid, old_target) = {
            let pipeline = self.render_pipeline.as_mut()?;
            (
                pipeline.shader_rid,
                pipeline.vertex_format,
                pipeline.uniform_set_rid,
                pipeline.scene_target.take(),
            )
        };
        let old_target_existed = old_target.is_some();
        if let Some(target) = old_target {
            self.rd.free_rid(target.render_pipeline_rid);
            self.rd.free_rid(target.framebuffer_rid);
        }

        let textures = if depth_texture_rid.is_valid() {
            Array::from_iter([color_texture_rid, depth_texture_rid])
        } else {
            Array::from_iter([color_texture_rid])
        };
        let framebuffer_rid = self
            .rd
            .framebuffer_create_ex(&textures)
            .view_count(view_count)
            .done();
        if !self.rd.framebuffer_is_valid(framebuffer_rid) {
            godot_print!("GPU terrain compositor: scene framebuffer is invalid");
            return None;
        }

        let framebuffer_format = self.rd.framebuffer_get_format(framebuffer_rid);
        let render_pipeline_rid = create_render_pipeline(
            &mut self.rd,
            shader_rid,
            framebuffer_format,
            vertex_format,
            depth_texture_rid.is_valid(),
        )?;

        let pipeline = self.render_pipeline.as_mut()?;
        pipeline.scene_target = Some(GpuTerrainSceneTarget {
            color_texture_rid,
            depth_texture_rid,
            framebuffer_rid,
            render_pipeline_rid,
            view_count,
        });
        self.scene_target_create_count += 1;
        if old_target_existed {
            self.scene_target_replace_count += 1;
        }

        Some((
            framebuffer_rid,
            render_pipeline_rid,
            vertex_format,
            uniform_set_rid,
        ))
    }

    fn rebuild_draw_buffers_if_needed(&mut self) {
        if !self.draw_dirty {
            return;
        }
        let rebuild_start = Instant::now();

        let draw_count = self.slots.len().min(MAX_INDIRECT_DRAWS);
        if draw_count == 0 {
            self.draw_count = 0;
            self.draw_keys.clear();
            self.draw_indices.clear();
            self.draw_dirty = false;
            self.record_draw_rebuild_ms(rebuild_start.elapsed().as_secs_f64() * 1000.0);
            return;
        }

        let mut indirect_bytes = Vec::with_capacity(draw_count * INDIRECT_DRAW_BYTES);
        self.draw_keys.clear();
        self.draw_indices.clear();
        for (key, slot) in self.slots.iter().take(draw_count) {
            self.draw_indices.insert(*key, self.draw_keys.len());
            self.draw_keys.push(*key);
            IndirectDrawCommand::for_slot(*slot).append_bytes(&mut indirect_bytes);
        }

        let indirect_pba = PackedByteArray::from(indirect_bytes.as_slice());
        self.rd.buffer_update(
            self.indirect_buffer_rid,
            0,
            indirect_pba.len() as u32,
            &indirect_pba,
        );

        self.draw_count = self.draw_keys.len();
        self.draw_dirty = false;
        self.record_draw_rebuild_ms(rebuild_start.elapsed().as_secs_f64() * 1000.0);
    }

    fn insert_draw_command(&mut self, key: GpuSubchunkKey, slot: GpuTerrainSlot) {
        let Some(draw_index) = insert_draw_key(
            &mut self.draw_keys,
            &mut self.draw_indices,
            key,
            MAX_INDIRECT_DRAWS,
        ) else {
            self.draw_dirty = true;
            return;
        };

        self.write_draw_command(draw_index, slot);
        self.draw_count = self.draw_keys.len();
    }

    fn remove_draw_command(&mut self, key: GpuSubchunkKey) {
        let Some(removal) = remove_draw_key(&mut self.draw_keys, &mut self.draw_indices, key)
        else {
            return;
        };

        if let Some(moved_key) = removal.moved_key {
            let Some(slot) = self.slots.get(&moved_key).copied() else {
                self.draw_dirty = true;
                return;
            };
            self.write_draw_command(removal.index, slot);
        }

        self.draw_count = self.draw_keys.len();
        if self.slots.len() >= MAX_INDIRECT_DRAWS {
            self.draw_dirty = true;
        }
    }

    fn write_draw_command(&mut self, draw_index: usize, slot: GpuTerrainSlot) {
        let patch_start = Instant::now();
        let mut indirect_bytes = Vec::with_capacity(INDIRECT_DRAW_BYTES);
        IndirectDrawCommand::for_slot(slot).append_bytes(&mut indirect_bytes);
        let indirect_pba = PackedByteArray::from(indirect_bytes.as_slice());
        self.rd.buffer_update(
            self.indirect_buffer_rid,
            (draw_index * INDIRECT_DRAW_BYTES) as u32,
            indirect_pba.len() as u32,
            &indirect_pba,
        );
        self.record_draw_patch_ms(patch_start.elapsed().as_secs_f64() * 1000.0);
    }

    fn record_draw_rebuild_ms(&mut self, elapsed_ms: f64) {
        self.draw_rebuild_count += 1;
        self.last_draw_rebuild_ms = elapsed_ms;
        let count = self.draw_rebuild_count as f64;
        self.avg_draw_rebuild_ms += (elapsed_ms - self.avg_draw_rebuild_ms) / count;
        self.max_draw_rebuild_ms = self.max_draw_rebuild_ms.max(elapsed_ms);
    }

    fn record_draw_patch_ms(&mut self, elapsed_ms: f64) {
        self.draw_patch_count += 1;
        self.last_draw_patch_ms = elapsed_ms;
        let count = self.draw_patch_count as f64;
        self.avg_draw_patch_ms += (elapsed_ms - self.avg_draw_patch_ms) / count;
        self.max_draw_patch_ms = self.max_draw_patch_ms.max(elapsed_ms);
    }

    fn record_compositor_submit_ms(
        &mut self,
        elapsed_ms: f64,
        breakdown_ms: GpuCompositorSubmitBreakdown,
    ) {
        self.compositor_submit_count += 1;
        self.last_compositor_submit_ms = elapsed_ms;
        self.last_compositor_submit_breakdown_ms = breakdown_ms;
        let count = self.compositor_submit_count as f64;
        self.avg_compositor_submit_ms += (elapsed_ms - self.avg_compositor_submit_ms) / count;
        if elapsed_ms >= self.max_compositor_submit_ms {
            self.max_compositor_submit_ms = elapsed_ms;
            self.max_compositor_submit_breakdown_ms = breakdown_ms;
        }
    }

    fn record_push_constant_update(&mut self, byte_count: usize) {
        self.push_constant_bytes = byte_count;
        self.push_constant_update_count += 1;
        self.push_constant_total_bytes = self
            .push_constant_total_bytes
            .saturating_add(byte_count as u64);
    }

    fn record_captured_compositor_gpu_timestamps(&mut self) {
        let frame = self.rd.get_captured_timestamps_frame();
        if self.last_compositor_gpu_timestamp_frame == Some(frame) {
            return;
        }

        let count = self.rd.get_captured_timestamps_count();
        let mut timestamps = Vec::new();
        for index in 0..count {
            let name = self.rd.get_captured_timestamp_name(index).to_string();
            if name == GPU_TERRAIN_TIMESTAMP_BEGIN || name == GPU_TERRAIN_TIMESTAMP_END {
                timestamps.push((name, self.rd.get_captured_timestamp_gpu_time(index)));
            }
        }

        let Some(elapsed_ms) = compositor_gpu_timestamp_delta_ms(
            timestamps.iter().map(|(name, time)| (name.as_str(), *time)),
        ) else {
            return;
        };

        self.last_compositor_gpu_timestamp_frame = Some(frame);
        self.compositor_gpu_sample_count += 1;
        self.last_compositor_gpu_ms = elapsed_ms;
        let count = self.compositor_gpu_sample_count as f64;
        self.avg_compositor_gpu_ms += (elapsed_ms - self.avg_compositor_gpu_ms) / count;
        self.max_compositor_gpu_ms = self.max_compositor_gpu_ms.max(elapsed_ms);
    }

    fn record_upload_failure(&mut self, requested_faces: usize) {
        self.upload_failures += 1;
        let allocator_stats = self.allocator.stats();
        match upload_failure_kind(allocator_stats, requested_faces) {
            UploadFailureKind::Capacity => self.upload_capacity_failures += 1,
            UploadFailureKind::Fragmentation => self.upload_fragmentation_failures += 1,
        }
    }

    fn create_debug_render_pipeline(
        rd: &mut Gd<RenderingDevice>,
        faces_buffer_rid: Rid,
    ) -> Option<GpuTerrainRenderPipeline> {
        let (vertex_source, fragment_source) = split_render_shader_source()?;
        let mut shader_source = RdShaderSource::new_gd();
        shader_source.set_language(ShaderLanguage::GLSL);
        shader_source.set_stage_source(ShaderStage::VERTEX, vertex_source);
        shader_source.set_stage_source(ShaderStage::FRAGMENT, fragment_source);

        let spirv = match rd.shader_compile_spirv_from_source(&shader_source) {
            Some(spirv) => {
                let vertex_error = spirv
                    .get_stage_compile_error(ShaderStage::VERTEX)
                    .to_string();
                let fragment_error = spirv
                    .get_stage_compile_error(ShaderStage::FRAGMENT)
                    .to_string();
                if !vertex_error.is_empty() || !fragment_error.is_empty() {
                    godot_print!(
                        "GPU terrain shader compile messages: vertex='{}' fragment='{}'",
                        vertex_error,
                        fragment_error
                    );
                }
                spirv
            }
            None => {
                godot_print!("GPU terrain: shader_compile_spirv_from_source returned None");
                return None;
            }
        };

        let shader_rid = rd.shader_create_from_spirv(&spirv);
        if shader_rid.is_invalid() {
            godot_print!("GPU terrain: shader_create_from_spirv returned an invalid RID");
            return None;
        }
        let Some((framebuffer_rid, color_texture_rid, framebuffer_format)) =
            create_debug_offscreen_framebuffer(rd)
        else {
            rd.free_rid(shader_rid);
            return None;
        };
        if framebuffer_format < 0 {
            godot_print!("GPU terrain: offscreen framebuffer format is unavailable");
            rd.free_rid(framebuffer_rid);
            rd.free_rid(color_texture_rid);
            rd.free_rid(shader_rid);
            return None;
        }

        let vertex_format = rd.vertex_format_create(&Array::new());
        let Some(render_pipeline_rid) =
            create_render_pipeline(rd, shader_rid, framebuffer_format, vertex_format, false)
        else {
            rd.free_rid(framebuffer_rid);
            rd.free_rid(color_texture_rid);
            rd.free_rid(shader_rid);
            return None;
        };

        let Some((atlas_texture_rid, atlas_sampler_rid, atlas_layout)) =
            create_atlas_texture_sampler(rd)
        else {
            rd.free_rid(render_pipeline_rid);
            rd.free_rid(framebuffer_rid);
            rd.free_rid(color_texture_rid);
            rd.free_rid(shader_rid);
            return None;
        };

        let uniform_set_rid = create_uniform_set(
            rd,
            shader_rid,
            faces_buffer_rid,
            atlas_texture_rid,
            atlas_sampler_rid,
        );
        if !rd.uniform_set_is_valid(uniform_set_rid) {
            godot_print!("GPU terrain: uniform set is invalid");
            rd.free_rid(atlas_sampler_rid);
            rd.free_rid(atlas_texture_rid);
            rd.free_rid(render_pipeline_rid);
            rd.free_rid(framebuffer_rid);
            rd.free_rid(color_texture_rid);
            rd.free_rid(shader_rid);
            return None;
        }

        Some(GpuTerrainRenderPipeline {
            shader_rid,
            uniform_set_rid,
            offscreen_render_pipeline_rid: render_pipeline_rid,
            framebuffer_rid,
            color_texture_rid,
            atlas_texture_rid,
            atlas_sampler_rid,
            atlas_layout,
            scene_target: None,
            vertex_format,
        })
    }
}

impl Drop for GpuTerrainBufferPool {
    fn drop(&mut self) {
        if let Some(render_pipeline) = &self.render_pipeline {
            if let Some(target) = &render_pipeline.scene_target {
                self.rd.free_rid(target.render_pipeline_rid);
                self.rd.free_rid(target.framebuffer_rid);
            }
            self.rd.free_rid(render_pipeline.uniform_set_rid);
            self.rd
                .free_rid(render_pipeline.offscreen_render_pipeline_rid);
            self.rd.free_rid(render_pipeline.framebuffer_rid);
            self.rd.free_rid(render_pipeline.color_texture_rid);
            self.rd.free_rid(render_pipeline.atlas_sampler_rid);
            self.rd.free_rid(render_pipeline.atlas_texture_rid);
            self.rd.free_rid(render_pipeline.shader_rid);
        }
        self.rd.free_rid(self.faces_buffer_rid);
        self.rd.free_rid(self.indirect_buffer_rid);
    }
}

fn compositor_gpu_timestamp_delta_ms<I, S>(timestamps: I) -> Option<f64>
where
    I: IntoIterator<Item = (S, u64)>,
    S: AsRef<str>,
{
    let mut begin_time = None;
    let mut elapsed_ms = None;
    for (name, gpu_time_us) in timestamps {
        match name.as_ref() {
            GPU_TERRAIN_TIMESTAMP_BEGIN => begin_time = Some(gpu_time_us),
            GPU_TERRAIN_TIMESTAMP_END => {
                let Some(begin_time_us) = begin_time.take() else {
                    continue;
                };
                if gpu_time_us >= begin_time_us {
                    elapsed_ms = Some((gpu_time_us - begin_time_us) as f64 / 1000.0);
                }
            }
            _ => {}
        }
    }
    elapsed_ms
}

fn split_render_shader_source() -> Option<(&'static str, &'static str)> {
    let source = include_str!("../../shaders/gpu_terrain_render.glsl");
    let (_, vertex_and_fragment) = source.split_once("// -- VERTEX --")?;
    let (vertex_source, fragment_source) = vertex_and_fragment.split_once("// -- FRAGMENT --")?;
    Some((vertex_source.trim_start(), fragment_source.trim_start()))
}

fn create_debug_offscreen_framebuffer(rd: &mut Gd<RenderingDevice>) -> Option<(Rid, Rid, i64)> {
    let mut texture_format = RdTextureFormat::new_gd();
    texture_format.set_format(DataFormat::R8G8B8A8_UNORM);
    texture_format.set_width(DEBUG_OFFSCREEN_SIZE);
    texture_format.set_height(DEBUG_OFFSCREEN_SIZE);
    texture_format.set_depth(1);
    texture_format.set_array_layers(1);
    texture_format.set_mipmaps(1);
    texture_format.set_texture_type(TextureType::TYPE_2D);
    texture_format.set_samples(TextureSamples::SAMPLES_1);
    texture_format.set_usage_bits(
        TextureUsageBits::COLOR_ATTACHMENT_BIT | TextureUsageBits::CAN_COPY_FROM_BIT,
    );

    let texture_view = RdTextureView::new_gd();
    let color_texture_rid = rd.texture_create(&texture_format, &texture_view);
    if !rd.texture_is_valid(color_texture_rid) {
        godot_print!("GPU terrain: offscreen color texture is invalid");
        return None;
    }

    let textures = Array::from_iter([color_texture_rid]);
    let framebuffer_rid = rd.framebuffer_create(&textures);
    if !rd.framebuffer_is_valid(framebuffer_rid) {
        godot_print!("GPU terrain: offscreen framebuffer is invalid");
        rd.free_rid(color_texture_rid);
        return None;
    }

    let framebuffer_format = rd.framebuffer_get_format(framebuffer_rid);
    Some((framebuffer_rid, color_texture_rid, framebuffer_format))
}

fn create_atlas_texture_sampler(
    rd: &mut Gd<RenderingDevice>,
) -> Option<(Rid, Rid, GpuTerrainAtlasLayout)> {
    let mut image = load_atlas_image()?;
    let Some(atlas_layout) =
        GpuTerrainAtlasLayout::from_image_size(image.get_width(), image.get_height())
    else {
        godot_print!(
            "GPU terrain: atlas image {}x{} is incompatible with {}px block tiles or tile ids up to {}",
            image.get_width(),
            image.get_height(),
            blocks::TEXTURE_TILE_SIZE_PX,
            blocks::MAX_TEXTURE_TILE
        );
        return None;
    };
    if image.get_format() != godot::classes::image::Format::RGBA8 {
        image.convert(godot::classes::image::Format::RGBA8);
    }

    let mut texture_format = RdTextureFormat::new_gd();
    let usage_bits = TextureUsageBits::SAMPLING_BIT | TextureUsageBits::CAN_UPDATE_BIT;
    texture_format.set_format(atlas_texture_format(rd, usage_bits));
    texture_format.set_width(image.get_width() as u32);
    texture_format.set_height(image.get_height() as u32);
    texture_format.set_depth(1);
    texture_format.set_array_layers(1);
    texture_format.set_mipmaps(1);
    texture_format.set_texture_type(TextureType::TYPE_2D);
    texture_format.set_samples(TextureSamples::SAMPLES_1);
    texture_format.set_usage_bits(usage_bits);

    let texture_data = Array::from_iter([image.get_data()]);
    let texture_view = RdTextureView::new_gd();
    let texture_rid = rd
        .texture_create_ex(&texture_format, &texture_view)
        .data(&texture_data)
        .done();
    if !rd.texture_is_valid(texture_rid) {
        godot_print!("GPU terrain: atlas texture is invalid");
        return None;
    }

    let mut sampler_state = RdSamplerState::new_gd();
    sampler_state.set_mag_filter(SamplerFilter::NEAREST);
    sampler_state.set_min_filter(SamplerFilter::NEAREST);
    sampler_state.set_mip_filter(SamplerFilter::NEAREST);
    sampler_state.set_repeat_u(SamplerRepeatMode::CLAMP_TO_EDGE);
    sampler_state.set_repeat_v(SamplerRepeatMode::CLAMP_TO_EDGE);
    sampler_state.set_repeat_w(SamplerRepeatMode::CLAMP_TO_EDGE);

    let sampler_rid = rd.sampler_create(&sampler_state);
    if sampler_rid.is_invalid() {
        godot_print!("GPU terrain: atlas sampler is invalid");
        rd.free_rid(texture_rid);
        return None;
    }

    Some((texture_rid, sampler_rid, atlas_layout))
}

fn atlas_texture_format(rd: &Gd<RenderingDevice>, usage_bits: TextureUsageBits) -> DataFormat {
    let srgb_format = DataFormat::R8G8B8A8_SRGB;
    if rd.texture_is_format_supported_for_usage(srgb_format, usage_bits)
        && rd.sampler_is_format_supported_for_filter(srgb_format, SamplerFilter::NEAREST)
    {
        return srgb_format;
    }

    godot_print!("GPU terrain: R8G8B8A8_SRGB atlas texture unsupported; falling back to UNORM");
    DataFormat::R8G8B8A8_UNORM
}

fn load_atlas_image() -> Option<Gd<Image>> {
    let mut loader = ResourceLoader::singleton();
    if let Some(resource) = loader.load(BLOCK_ATLAS_PATH)
        && let Ok(texture) = resource.try_cast::<Texture2D>()
        && let Some(image) = texture.get_image()
        && !image.is_empty()
    {
        return Some(image);
    }

    let image = Image::load_from_file(BLOCK_ATLAS_PATH)?;
    if image.is_empty() {
        godot_print!("GPU terrain: atlas image is empty");
        return None;
    }
    Some(image)
}

fn create_render_pipeline(
    rd: &mut Gd<RenderingDevice>,
    shader_rid: Rid,
    framebuffer_format: i64,
    vertex_format: i64,
    enable_depth: bool,
) -> Option<Rid> {
    if framebuffer_format < 0 {
        godot_print!("GPU terrain: framebuffer format is unavailable");
        return None;
    }

    let rasterization_state = create_rasterization_state();
    let multisample_state = create_multisample_state();
    let depth_state = create_depth_state(enable_depth);
    let color_blend_state = create_color_blend_state();
    let render_pipeline_rid = rd.render_pipeline_create(
        shader_rid,
        framebuffer_format,
        vertex_format,
        RenderPrimitive::TRIANGLES,
        &rasterization_state,
        &multisample_state,
        &depth_state,
        &color_blend_state,
    );
    if !rd.render_pipeline_is_valid(render_pipeline_rid) {
        godot_print!("GPU terrain: render pipeline is invalid");
        return None;
    }

    Some(render_pipeline_rid)
}

fn create_uniform_set(
    rd: &mut Gd<RenderingDevice>,
    shader_rid: Rid,
    faces_buffer_rid: Rid,
    atlas_texture_rid: Rid,
    atlas_sampler_rid: Rid,
) -> Rid {
    let mut faces_uniform = RdUniform::new_gd();
    faces_uniform.set_uniform_type(UniformType::STORAGE_BUFFER);
    faces_uniform.set_binding(0);
    faces_uniform.add_id(faces_buffer_rid);

    let mut atlas_uniform = RdUniform::new_gd();
    atlas_uniform.set_uniform_type(UniformType::SAMPLER_WITH_TEXTURE);
    atlas_uniform.set_binding(1);
    atlas_uniform.add_id(atlas_sampler_rid);
    atlas_uniform.add_id(atlas_texture_rid);

    let uniforms = Array::from_iter([faces_uniform, atlas_uniform]);
    rd.uniform_set_create(&uniforms, shader_rid, 0)
}

fn create_rasterization_state() -> Gd<RdPipelineRasterizationState> {
    let config = terrain_rasterization_config(gpu_terrain_cull_mode());
    let mut state = RdPipelineRasterizationState::new_gd();
    state.set_cull_mode(config.cull_mode);
    state.set_front_face(config.front_face);
    state.set_wireframe(false);
    state.set_discard_primitives(false);
    state
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
struct TerrainRasterizationConfig {
    cull_mode: PolygonCullMode,
    front_face: PolygonFrontFace,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct TerrainRasterizationLabels {
    pub cull_mode: &'static str,
    pub front_face: &'static str,
}

fn terrain_rasterization_config(cull_mode: PolygonCullMode) -> TerrainRasterizationConfig {
    TerrainRasterizationConfig {
        cull_mode,
        front_face: PolygonFrontFace::CLOCKWISE,
    }
}

pub fn terrain_rasterization_labels() -> TerrainRasterizationLabels {
    let config = terrain_rasterization_config(gpu_terrain_cull_mode());
    TerrainRasterizationLabels {
        cull_mode: polygon_cull_mode_label(config.cull_mode),
        front_face: polygon_front_face_label(config.front_face),
    }
}

fn create_multisample_state() -> Gd<RdPipelineMultisampleState> {
    let mut state = RdPipelineMultisampleState::new_gd();
    state.set_sample_count(TextureSamples::SAMPLES_1);
    state
}

fn create_depth_state(enable_depth: bool) -> Gd<RdPipelineDepthStencilState> {
    let config = terrain_depth_state_config(enable_depth);
    let mut state = RdPipelineDepthStencilState::new_gd();
    state.set_enable_depth_test(config.enable_depth_test);
    state.set_enable_depth_write(config.enable_depth_write);
    state.set_depth_compare_operator(config.compare_operator);
    state
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
struct TerrainDepthStateConfig {
    enable_depth_test: bool,
    enable_depth_write: bool,
    compare_operator: CompareOperator,
}

fn terrain_depth_state_config(enable_depth: bool) -> TerrainDepthStateConfig {
    TerrainDepthStateConfig {
        enable_depth_test: enable_depth,
        enable_depth_write: enable_depth,
        compare_operator: CompareOperator::GREATER_OR_EQUAL,
    }
}

fn create_color_blend_state() -> Gd<RdPipelineColorBlendState> {
    let mut attachment = RdPipelineColorBlendStateAttachment::new_gd();
    attachment.set_enable_blend(false);

    let attachments = Array::from_iter([attachment]);
    let mut state = RdPipelineColorBlendState::new_gd();
    state.set_attachments(&attachments);
    state
}

fn clip_from_world_push_constants(
    render_data: &Gd<RenderData>,
    lighting: GpuTerrainLighting,
    atlas_layout: GpuTerrainAtlasLayout,
) -> PackedByteArray {
    let Some(scene_data) = render_data.get_render_scene_data() else {
        return push_constants_for_debug_projection(lighting, atlas_layout);
    };

    let projection = if scene_data.get_view_count() > 0 {
        scene_data.get_view_projection(0)
    } else {
        scene_data.get_cam_projection()
    };
    let view = Projection::from(scene_data.get_cam_transform().affine_inverse());
    push_constants_from_projection(projection * view, lighting, atlas_layout)
}

fn push_constants_for_debug_projection(
    lighting: GpuTerrainLighting,
    atlas_layout: GpuTerrainAtlasLayout,
) -> PackedByteArray {
    push_constants_from_projection(
        Projection::from_cols(
            Vector4::new(0.012, 0.006, 0.0, 0.0),
            Vector4::new(0.0, -0.014, 0.0, 0.0),
            Vector4::new(-0.012, 0.006, 0.0, 0.0),
            Vector4::new(0.0, 0.0, 0.35, 1.0),
        ),
        lighting,
        atlas_layout,
    )
}

fn push_constants_from_projection(
    projection: Projection,
    lighting: GpuTerrainLighting,
    atlas_layout: GpuTerrainAtlasLayout,
) -> PackedByteArray {
    let bytes = push_constant_bytes_from_projection(projection, lighting, atlas_layout);
    PackedByteArray::from(bytes.as_slice())
}

fn push_constant_bytes_from_projection(
    projection: Projection,
    lighting: GpuTerrainLighting,
    atlas_layout: GpuTerrainAtlasLayout,
) -> Vec<u8> {
    let lighting = lighting.sanitized();
    let mut bytes = Vec::with_capacity(TERRAIN_PUSH_CONSTANT_BYTES);
    for col in projection.cols {
        for value in [col.x, col.y, col.z, col.w] {
            bytes.extend_from_slice(&value.to_le_bytes());
        }
    }

    for value in [
        lighting.direction_to_light.x,
        lighting.direction_to_light.y,
        lighting.direction_to_light.z,
        lighting.ambient,
        lighting.color.r,
        lighting.color.g,
        lighting.color.b,
        lighting.energy,
    ] {
        bytes.extend_from_slice(&value.to_le_bytes());
    }

    for value in atlas_layout.push_constant_values() {
        bytes.extend_from_slice(&value.to_le_bytes());
    }

    bytes
}

fn default_light_direction_to_light() -> Vector3 {
    Vector3::new(0.35, 0.75, 0.55).normalized()
}

fn normalized_or_default_light_direction(direction: Vector3) -> Vector3 {
    if !direction.x.is_finite() || !direction.y.is_finite() || !direction.z.is_finite() {
        return default_light_direction_to_light();
    }
    if direction.length() <= f32::EPSILON {
        return default_light_direction_to_light();
    }
    direction.normalized()
}

fn sanitize_non_negative(value: f32, fallback: f32) -> f32 {
    if value.is_finite() && value >= 0.0 {
        value
    } else {
        fallback
    }
}

fn gpu_terrain_compositor_draw_repeat() -> u32 {
    static DRAW_REPEAT: OnceLock<u32> = OnceLock::new();
    *DRAW_REPEAT.get_or_init(|| {
        compositor_draw_repeat_from_env(std::env::var(GPU_TERRAIN_COMPOSITOR_DRAW_REPEAT_ENV).ok())
    })
}

fn compositor_draw_repeat_from_env(value: Option<String>) -> u32 {
    value
        .as_deref()
        .and_then(|value| value.trim().parse::<u32>().ok())
        .filter(|repeat| *repeat > 0)
        .map(|repeat| repeat.min(MAX_GPU_TERRAIN_COMPOSITOR_DRAW_REPEAT))
        .unwrap_or(1)
}

fn gpu_terrain_cull_mode() -> PolygonCullMode {
    static CULL_MODE: OnceLock<PolygonCullMode> = OnceLock::new();
    *CULL_MODE.get_or_init(|| {
        gpu_terrain_cull_mode_from_env(std::env::var(GPU_TERRAIN_CULL_MODE_ENV).ok())
    })
}

fn gpu_terrain_cull_mode_from_env(value: Option<String>) -> PolygonCullMode {
    match value.as_deref().map(str::trim).map(str::to_lowercase) {
        Some(value) if value == "disabled" || value == "none" || value == "off" => {
            PolygonCullMode::DISABLED
        }
        Some(value) if value == "front" => PolygonCullMode::FRONT,
        Some(value) if value == "back" || value.is_empty() => PolygonCullMode::BACK,
        _ => PolygonCullMode::BACK,
    }
}

fn polygon_cull_mode_label(cull_mode: PolygonCullMode) -> &'static str {
    match cull_mode {
        PolygonCullMode::DISABLED => "disabled",
        PolygonCullMode::FRONT => "front",
        PolygonCullMode::BACK => "back",
        _ => "unknown",
    }
}

fn polygon_front_face_label(front_face: PolygonFrontFace) -> &'static str {
    match front_face {
        PolygonFrontFace::CLOCKWISE => "clockwise",
        PolygonFrontFace::COUNTER_CLOCKWISE => "counter_clockwise",
        _ => "unknown",
    }
}

pub fn build_packed_faces(padded_blocks: &[u8]) -> PackedFaceBatch {
    let block_lookup = PackedBlockLookup::from_definitions();
    let mut faces = Vec::with_capacity(4096);

    for y in 0..SUBCHUNK_H {
        for z in 0..CHUNK_D {
            for x in 0..CHUNK_W {
                let block_id = padded_block(padded_blocks, x + 1, y + 1, z + 1);
                let Some(block_info) = block_lookup.info(block_id) else {
                    continue;
                };

                for (face, neighbor_x, neighbor_y, neighbor_z) in FACE_NEIGHBOR_OFFSETS {
                    push_visible_face(
                        &mut faces,
                        &block_lookup,
                        block_info,
                        FaceCandidate {
                            x,
                            y,
                            z,
                            block_id,
                            face,
                            neighbor_block_id: padded_block(
                                padded_blocks,
                                x + neighbor_x,
                                y + neighbor_y,
                                z + neighbor_z,
                            ),
                        },
                    );
                }
            }
        }
    }

    let faces = greedy_merge_packed_faces(&faces);
    PackedFaceBatch { faces }
}

fn greedy_merge_packed_faces(faces: &[PackedFace]) -> Vec<PackedFace> {
    let mut merged = Vec::with_capacity(faces.len());
    for face_idx in [
        FACE_LEFT,
        FACE_RIGHT,
        FACE_BOTTOM,
        FACE_TOP,
        FACE_BACK,
        FACE_FRONT,
    ] {
        visit_greedy_face_rects_by_key(
            faces,
            face_idx,
            greedy_face_merge_key,
            |face_idx, plane, u, v, width, height| {
                let (x, y, z) = greedy_face_origin(face_idx, plane, u, v);
                let sample = faces
                    .iter()
                    .find(|face| {
                        face.face() == face_idx && collision_face_plane_uv(**face) == (plane, u, v)
                    })
                    .expect("greedy cell has source face");
                merged.push(PackedFace::with_extent(
                    x as u32,
                    y as u32,
                    z as u32,
                    face_idx,
                    sample.tile(),
                    sample.block_id(),
                    PackedFaceExtent {
                        u: width as u32,
                        v: height as u32,
                    },
                ));
                true
            },
        );
    }
    merged
}

fn greedy_face_merge_key(face: PackedFace) -> u32 {
    face.block_id() | (face.tile() << 16)
}

fn greedy_face_origin(face_idx: u32, plane: usize, u: usize, v: usize) -> (usize, usize, usize) {
    match face_idx {
        FACE_LEFT => (plane, v, u),
        FACE_RIGHT => (plane - 1, v, u),
        FACE_BOTTOM => (u, plane, v),
        FACE_TOP => (u, plane - 1, v),
        FACE_BACK => (u, v, plane),
        _ => (u, v, plane - 1),
    }
}

#[derive(Clone, Copy)]
struct FaceCandidate {
    x: usize,
    y: usize,
    z: usize,
    block_id: u32,
    face: u32,
    neighbor_block_id: u32,
}

fn push_visible_face(
    faces: &mut Vec<PackedFace>,
    block_lookup: &PackedBlockLookup,
    block_info: PackedBlockInfo,
    candidate: FaceCandidate,
) {
    if block_lookup.is_solid(candidate.neighbor_block_id) {
        return;
    }

    faces.push(PackedFace::new(
        candidate.x as u32,
        candidate.y as u32,
        candidate.z as u32,
        candidate.face,
        block_info.tile_for_face(candidate.face),
        candidate.block_id,
    ));
}

#[derive(Clone, Copy, Debug)]
struct PackedBlockInfo {
    top_tile: u32,
    side_tile: u32,
    bottom_tile: u32,
}

impl PackedBlockInfo {
    fn tile_for_face(self, face: u32) -> u32 {
        if face == FACE_TOP {
            self.top_tile
        } else if face == FACE_BOTTOM {
            self.bottom_tile
        } else {
            self.side_tile
        }
    }
}

struct PackedBlockLookup {
    blocks: Vec<Option<PackedBlockInfo>>,
}

impl PackedBlockLookup {
    fn from_definitions() -> Self {
        let max_id = blocks::definitions()
            .iter()
            .map(|block| block.id as usize)
            .max()
            .unwrap_or(0);
        let mut blocks_by_id = vec![None; max_id + 1];
        for block in blocks::definitions()
            .iter()
            .copied()
            .filter(|block| blocks::is_opaque_solid(block.id))
        {
            blocks_by_id[block.id as usize] = Some(PackedBlockInfo {
                top_tile: block.textures.top,
                side_tile: block.textures.side,
                bottom_tile: block.textures.bottom,
            });
        }

        Self {
            blocks: blocks_by_id,
        }
    }

    fn info(&self, block_id: u32) -> Option<PackedBlockInfo> {
        self.blocks.get(block_id as usize).copied().flatten()
    }

    fn is_solid(&self, block_id: u32) -> bool {
        self.info(block_id).is_some()
    }
}

fn padded_block(blocks: &[u8], x: usize, y: usize, z: usize) -> u32 {
    if x >= PADDED_W || y >= PADDED_H || z >= PADDED_D {
        return 0;
    }

    let idx = padded_byte_index(x, y, z);
    if idx + BLOCK_BYTES > blocks.len() {
        return 0;
    }

    u16::from_le_bytes([blocks[idx], blocks[idx + 1]]) as u32
}

fn padded_byte_index(x: usize, y: usize, z: usize) -> usize {
    (x + y * PADDED_W * PADDED_D + z * PADDED_W) * BLOCK_BYTES
}

#[cfg(test)]
mod tests {
    use super::*;

    fn write_block(blocks: &mut [u8], x: usize, y: usize, z: usize, block_id: u16) {
        let idx = padded_byte_index(x, y, z);
        blocks[idx..idx + BLOCK_BYTES].copy_from_slice(&block_id.to_le_bytes());
    }

    fn read_u32(bytes: &[u8], offset: usize) -> u32 {
        u32::from_le_bytes(
            bytes[offset..offset + 4]
                .try_into()
                .expect("u32 byte slice"),
        )
    }

    fn read_f32(bytes: &[u8], offset: usize) -> f32 {
        f32::from_le_bytes(
            bytes[offset..offset + 4]
                .try_into()
                .expect("f32 byte slice"),
        )
    }

    #[test]
    fn compositor_draw_repeat_defaults_to_one() {
        assert_eq!(compositor_draw_repeat_from_env(None), 1);
        assert_eq!(compositor_draw_repeat_from_env(Some(String::new())), 1);
        assert_eq!(
            compositor_draw_repeat_from_env(Some("not-a-number".to_string())),
            1
        );
        assert_eq!(compositor_draw_repeat_from_env(Some("0".to_string())), 1);
    }

    #[test]
    fn compositor_draw_repeat_clamps_stress_value() {
        assert_eq!(compositor_draw_repeat_from_env(Some("8".to_string())), 8);
        assert_eq!(
            compositor_draw_repeat_from_env(Some("999".to_string())),
            MAX_GPU_TERRAIN_COMPOSITOR_DRAW_REPEAT
        );
    }

    #[test]
    fn gpu_terrain_cull_mode_defaults_to_back_faces() {
        assert_eq!(gpu_terrain_cull_mode_from_env(None), PolygonCullMode::BACK);
        assert_eq!(
            gpu_terrain_cull_mode_from_env(Some(String::new())),
            PolygonCullMode::BACK
        );
        assert_eq!(
            gpu_terrain_cull_mode_from_env(Some("unknown".to_string())),
            PolygonCullMode::BACK
        );
    }

    #[test]
    fn gpu_terrain_cull_mode_supports_rollback_and_front_control() {
        assert_eq!(
            gpu_terrain_cull_mode_from_env(Some("disabled".to_string())),
            PolygonCullMode::DISABLED
        );
        assert_eq!(
            gpu_terrain_cull_mode_from_env(Some("off".to_string())),
            PolygonCullMode::DISABLED
        );
        assert_eq!(
            gpu_terrain_cull_mode_from_env(Some("front".to_string())),
            PolygonCullMode::FRONT
        );
    }

    #[test]
    fn terrain_rasterization_uses_clockwise_front_faces() {
        let config = terrain_rasterization_config(PolygonCullMode::BACK);

        assert_eq!(config.cull_mode, PolygonCullMode::BACK);
        assert_eq!(config.front_face, PolygonFrontFace::CLOCKWISE);
    }

    #[test]
    fn terrain_rasterization_labels_are_stable_for_markers() {
        assert_eq!(polygon_cull_mode_label(PolygonCullMode::BACK), "back");
        assert_eq!(polygon_cull_mode_label(PolygonCullMode::FRONT), "front");
        assert_eq!(
            polygon_cull_mode_label(PolygonCullMode::DISABLED),
            "disabled"
        );
        assert_eq!(
            polygon_front_face_label(PolygonFrontFace::CLOCKWISE),
            "clockwise"
        );
        assert_eq!(
            polygon_front_face_label(PolygonFrontFace::COUNTER_CLOCKWISE),
            "counter_clockwise"
        );
    }

    #[test]
    fn single_solid_block_emits_six_faces() {
        let mut blocks = vec![0u8; PADDED_W * PADDED_H * PADDED_D * BLOCK_BYTES];
        write_block(&mut blocks, 1, 1, 1, blocks::STONE as u16);

        let batch = build_packed_faces(&blocks);

        assert_eq!(batch.face_count(), 6);
        assert_eq!(batch.byte_len(), 6 * std::mem::size_of::<PackedFace>());
    }

    #[test]
    fn packed_faces_greedy_merge_coplanar_faces() {
        let mut blocks = vec![0u8; PADDED_W * PADDED_H * PADDED_D * BLOCK_BYTES];
        for z in 1..=2 {
            for x in 1..=3 {
                write_block(&mut blocks, x, 1, z, blocks::STONE as u16);
            }
        }

        let batch = build_packed_faces(&blocks);
        let top_face = batch
            .faces()
            .iter()
            .find(|face| face.face() == FACE_TOP)
            .expect("merged top face");

        assert_eq!(top_face.x(), 0);
        assert_eq!(top_face.y(), 0);
        assert_eq!(top_face.z(), 0);
        assert_eq!(top_face.extent_u(), 3);
        assert_eq!(top_face.extent_v(), 2);
        assert_eq!(
            top_face.tile(),
            blocks::tile_for_face(blocks::STONE, FACE_TOP, FACE_TOP, FACE_BOTTOM)
        );
        assert_eq!(
            batch
                .faces()
                .iter()
                .filter(|face| face.face() == FACE_TOP)
                .count(),
            1
        );
        assert_eq!(
            batch
                .faces()
                .iter()
                .filter(|face| face.face() == FACE_BOTTOM)
                .count(),
            1
        );
        assert!(batch.face_count() < 6 * 6);
    }

    #[test]
    fn packed_faces_do_not_merge_different_tiles() {
        let mut blocks = vec![0u8; PADDED_W * PADDED_H * PADDED_D * BLOCK_BYTES];
        write_block(&mut blocks, 1, 1, 1, blocks::GRASS as u16);
        write_block(&mut blocks, 2, 1, 1, blocks::STONE as u16);

        let batch = build_packed_faces(&blocks);
        let top_faces = batch
            .faces()
            .iter()
            .filter(|face| face.face() == FACE_TOP)
            .count();

        assert_eq!(top_faces, 2);
    }

    #[test]
    fn subchunk_bytes_preserve_extent_low_bits() {
        let batch = PackedFaceBatch {
            faces: vec![PackedFace::with_extent(
                1,
                2,
                3,
                FACE_TOP,
                7,
                blocks::STONE,
                PackedFaceExtent { u: 5, v: 6 },
            )],
        };

        let bytes = batch.to_bytes_for_subchunk(GpuSubchunkKey {
            chunk_x: 0,
            sub_y: 0,
            chunk_z: -3,
        });

        assert_eq!(read_u32(&bytes, 8) & 0xffff, 5 | (6 << 6));
        assert_eq!(read_u32(&bytes, 8) >> 16, pack_signed_i16(-3));
    }

    #[test]
    fn hidden_neighbor_face_is_not_emitted() {
        let mut blocks = vec![0u8; PADDED_W * PADDED_H * PADDED_D * BLOCK_BYTES];
        write_block(&mut blocks, 1, 1, 1, blocks::STONE as u16);
        write_block(&mut blocks, 2, 1, 1, blocks::STONE as u16);

        let batch = build_packed_faces(&blocks);
        let left_faces = batch
            .faces()
            .iter()
            .filter(|face| face.face() == FACE_LEFT)
            .count();
        let right_faces = batch
            .faces()
            .iter()
            .filter(|face| face.face() == FACE_RIGHT)
            .count();

        assert_eq!(batch.face_count(), 6);
        assert_eq!(left_faces, 1);
        assert_eq!(right_faces, 1);
    }

    #[test]
    fn packed_faces_use_block_definition_tiles() {
        for block_id in [blocks::GRASS, blocks::WOOD] {
            let mut blocks_data = vec![0u8; PADDED_W * PADDED_H * PADDED_D * BLOCK_BYTES];
            write_block(&mut blocks_data, 1, 1, 1, block_id as u16);

            let batch = build_packed_faces(&blocks_data);

            assert_eq!(batch.face_count(), 6);
            for face_idx in [
                FACE_LEFT,
                FACE_RIGHT,
                FACE_BOTTOM,
                FACE_TOP,
                FACE_BACK,
                FACE_FRONT,
            ] {
                let face = batch
                    .faces()
                    .iter()
                    .find(|face| face.face() == face_idx)
                    .expect("face emitted for isolated solid block");
                assert_eq!(
                    face.tile(),
                    blocks::tile_for_face(block_id, face_idx, FACE_TOP, FACE_BOTTOM)
                );
            }
        }
    }

    #[test]
    fn current_gpu_terrain_blocks_are_opaque_solids() {
        assert!(!blocks::is_opaque_solid(blocks::AIR));
        assert!(!blocks::is_opaque_solid(999));
        for block_id in blocks::PLACEABLE_BLOCKS {
            assert!(blocks::is_solid(block_id));
            assert!(blocks::is_opaque_solid(block_id));
        }
    }

    #[test]
    fn solid_gpu_terrain_fragment_forces_opaque_alpha() {
        let (_, fragment_source) = split_render_shader_source().expect("render shader stages");

        assert!(fragment_source.contains("frag_color = vec4(texel.rgb * lighting_in, 1.0);"));
        assert!(!fragment_source.contains("texel.a"));
    }

    #[test]
    fn render_shader_uses_face_extent_for_geometry_and_tiled_uvs() {
        let (vertex_source, fragment_source) =
            split_render_shader_source().expect("render shader stages");

        assert!(
            vertex_source.contains("vec3 face_corner(uint face_idx, uint corner_idx, vec2 extent)")
        );
        assert!(
            vertex_source.contains("vec2 face_uv(uint face_idx, uint corner_idx, vec2 extent)")
        );
        assert!(vertex_source.contains(
            "vec2 extent = vec2(float(face.extent & 63u), float((face.extent >> 6u) & 63u));"
        ));
        assert!(vertex_source.contains("face_corner(face_idx, corner_idx, extent)"));
        assert!(
            vertex_source.contains(
                "uv_tile_out = vec3(face_uv(face_idx, corner_idx, extent), float(tile));"
            )
        );
        assert!(fragment_source.contains("vec2 tiled_uv = fract(tile_uv);"));
        assert!(fragment_source.contains("vec2 uv_in = atlas_uv(uv_tile_in.xy, uv_tile_in.z);"));
    }

    #[test]
    fn render_shader_consumes_indirect_instance_range() {
        let (vertex_source, _) = split_render_shader_source().expect("render shader stages");

        assert!(vertex_source.contains("uint face_instance = uint(gl_InstanceIndex);"));
        assert!(vertex_source.contains("PackedFace face = face_buffer.faces[face_instance];"));
        assert!(vertex_source.contains("uint corner_idx = corner_map[uint(gl_VertexIndex) % 6u];"));
    }

    #[test]
    fn render_shader_push_constant_layout_matches_rust_bytes() {
        let (vertex_source, _) = split_render_shader_source().expect("render shader stages");
        let clip_idx = vertex_source
            .find("mat4 clip_from_world;")
            .expect("clip matrix push constant");
        let light_direction_idx = vertex_source
            .find("vec4 light_direction_ambient;")
            .expect("light direction push constant");
        let light_color_idx = vertex_source
            .find("vec4 light_color_energy;")
            .expect("light color push constant");
        let atlas_idx = vertex_source
            .find("vec4 atlas_layout;")
            .expect("atlas layout push constant");

        assert!(clip_idx < light_direction_idx);
        assert!(light_direction_idx < light_color_idx);
        assert!(light_color_idx < atlas_idx);
        assert_eq!(CLIP_FROM_WORLD_PUSH_CONSTANT_BYTES, 64);
        assert_eq!(TERRAIN_LIGHTING_PUSH_CONSTANT_BYTES, 32);
        assert_eq!(TERRAIN_ATLAS_PUSH_CONSTANT_BYTES, 16);
        assert_eq!(TERRAIN_PUSH_CONSTANT_BYTES, 112);
    }

    #[test]
    fn scene_depth_state_uses_reverse_z_compare() {
        let depth_disabled = terrain_depth_state_config(false);
        assert!(!depth_disabled.enable_depth_test);
        assert!(!depth_disabled.enable_depth_write);
        assert_eq!(
            depth_disabled.compare_operator,
            CompareOperator::GREATER_OR_EQUAL
        );

        let depth_enabled = terrain_depth_state_config(true);
        assert!(depth_enabled.enable_depth_test);
        assert!(depth_enabled.enable_depth_write);
        assert_eq!(
            depth_enabled.compare_operator,
            CompareOperator::GREATER_OR_EQUAL
        );
    }

    #[test]
    fn cpu_proxy_mesh_uses_packed_face_geometry() {
        let batch = PackedFaceBatch {
            faces: vec![PackedFace::new(1, 2, 3, FACE_TOP, 7, blocks::GRASS)],
        };

        let proxy = batch.cpu_proxy_vertices();

        assert_eq!(proxy.len(), 6);
        assert_eq!(
            proxy[0],
            (Vector3::new(1.0, 3.0, 3.0), Vector3::new(0.0, 1.0, 0.0))
        );
        assert_eq!(
            proxy[1],
            (Vector3::new(2.0, 3.0, 4.0), Vector3::new(0.0, 1.0, 0.0))
        );
        assert_eq!(
            proxy[2],
            (Vector3::new(1.0, 3.0, 4.0), Vector3::new(0.0, 1.0, 0.0))
        );
    }

    #[test]
    fn compact_cpu_proxy_positions_preserve_geometry() {
        let batch = PackedFaceBatch {
            faces: vec![PackedFace::new(1, 2, 3, FACE_TOP, 7, blocks::GRASS)],
        };

        let proxy = batch.cpu_proxy_positions();

        assert_eq!(proxy.len(), 6);
        assert_eq!(proxy[0], Vector3::new(1.0, 3.0, 3.0));
        assert_eq!(proxy[1], Vector3::new(2.0, 3.0, 4.0));
        assert_eq!(proxy[2], Vector3::new(1.0, 3.0, 4.0));
    }

    #[test]
    fn indexed_compact_cpu_proxy_positions_use_quad_vertices_and_indices() {
        let batch = PackedFaceBatch {
            faces: vec![PackedFace::new(1, 2, 3, FACE_TOP, 7, blocks::GRASS)],
        };

        let compact_positions = batch.cpu_proxy_positions();
        let (positions, indices) = batch.indexed_cpu_proxy_positions();

        assert_eq!(compact_positions.len(), 6);
        assert_eq!(positions.len(), 4);
        assert_eq!(positions[0], Vector3::new(1.0, 3.0, 3.0));
        assert_eq!(positions[1], Vector3::new(1.0, 3.0, 4.0));
        assert_eq!(positions[2], Vector3::new(2.0, 3.0, 4.0));
        assert_eq!(positions[3], Vector3::new(2.0, 3.0, 3.0));
        assert_eq!(indices, vec![0, 2, 1, 0, 3, 2]);
    }

    #[test]
    fn indexed_compact_cpu_proxy_positions_preserve_all_face_directions() {
        for face_idx in [
            FACE_LEFT,
            FACE_RIGHT,
            FACE_BOTTOM,
            FACE_TOP,
            FACE_BACK,
            FACE_FRONT,
        ] {
            let batch = PackedFaceBatch {
                faces: vec![PackedFace::new(1, 2, 3, face_idx, 7, blocks::GRASS)],
            };
            let (positions, indices) = batch.indexed_cpu_proxy_positions();
            let expanded: Vec<Vector3> = indices
                .iter()
                .map(|index| positions[*index as usize])
                .collect();

            assert_eq!(positions.len(), 4);
            assert_eq!(expanded, batch.collision_face_positions());
        }
    }

    #[test]
    fn indexed_compact_cpu_proxy_positions_merge_adjacent_coplanar_quads() {
        let batch = PackedFaceBatch {
            faces: vec![
                PackedFace::new(1, 2, 3, FACE_TOP, 7, blocks::GRASS),
                PackedFace::new(2, 2, 3, FACE_TOP, 7, blocks::GRASS),
            ],
        };

        let (positions, indices) = batch.indexed_cpu_proxy_positions();

        assert_eq!(positions.len(), 4);
        assert_eq!(positions[0], Vector3::new(1.0, 3.0, 3.0));
        assert_eq!(positions[1], Vector3::new(1.0, 3.0, 4.0));
        assert_eq!(positions[2], Vector3::new(3.0, 3.0, 4.0));
        assert_eq!(positions[3], Vector3::new(3.0, 3.0, 3.0));
        assert_eq!(indices, vec![0, 2, 1, 0, 3, 2]);
    }

    #[test]
    fn indexed_compact_cpu_proxy_positions_preserve_merged_face_extent() {
        let batch = PackedFaceBatch {
            faces: vec![PackedFace::with_extent(
                1,
                2,
                3,
                FACE_TOP,
                7,
                blocks::GRASS,
                PackedFaceExtent { u: 3, v: 2 },
            )],
        };

        let (positions, indices) = batch.indexed_cpu_proxy_positions();

        assert_eq!(positions.len(), 4);
        assert_eq!(positions[0], Vector3::new(1.0, 3.0, 3.0));
        assert_eq!(positions[1], Vector3::new(1.0, 3.0, 5.0));
        assert_eq!(positions[2], Vector3::new(4.0, 3.0, 5.0));
        assert_eq!(positions[3], Vector3::new(4.0, 3.0, 3.0));
        assert_eq!(indices, vec![0, 2, 1, 0, 3, 2]);
    }

    #[test]
    fn collision_faces_preserve_single_face_geometry() {
        for face_idx in [
            FACE_LEFT,
            FACE_RIGHT,
            FACE_BOTTOM,
            FACE_TOP,
            FACE_BACK,
            FACE_FRONT,
        ] {
            let face = PackedFace::new(1, 2, 3, face_idx, 7, blocks::GRASS);
            let batch = PackedFaceBatch { faces: vec![face] };
            let mut expected = Vec::new();
            append_cpu_proxy_face_positions(face, &mut expected);

            let collision_faces = batch.collision_face_positions();

            assert_eq!(collision_faces, expected);
        }
    }

    #[test]
    fn collision_faces_merge_adjacent_coplanar_quads() {
        let batch = PackedFaceBatch {
            faces: vec![
                PackedFace::new(1, 2, 3, FACE_TOP, 7, blocks::GRASS),
                PackedFace::new(2, 2, 3, FACE_TOP, 7, blocks::GRASS),
            ],
        };

        let collision_faces = batch.collision_face_positions();

        assert_eq!(collision_faces.len(), 6);
        assert_eq!(collision_faces[0], Vector3::new(1.0, 3.0, 3.0));
        assert_eq!(collision_faces[1], Vector3::new(3.0, 3.0, 4.0));
        assert_eq!(collision_faces[2], Vector3::new(1.0, 3.0, 4.0));
        assert_eq!(collision_faces[3], Vector3::new(1.0, 3.0, 3.0));
        assert_eq!(collision_faces[4], Vector3::new(3.0, 3.0, 3.0));
        assert_eq!(collision_faces[5], Vector3::new(3.0, 3.0, 4.0));
    }

    #[test]
    fn collision_faces_preserve_merged_face_extent() {
        let batch = PackedFaceBatch {
            faces: vec![PackedFace::with_extent(
                1,
                2,
                3,
                FACE_TOP,
                7,
                blocks::GRASS,
                PackedFaceExtent { u: 3, v: 2 },
            )],
        };

        let collision_faces = batch.collision_face_positions();

        assert_eq!(collision_faces.len(), 6);
        assert_eq!(collision_faces[0], Vector3::new(1.0, 3.0, 3.0));
        assert_eq!(collision_faces[1], Vector3::new(4.0, 3.0, 5.0));
        assert_eq!(collision_faces[2], Vector3::new(1.0, 3.0, 5.0));
        assert_eq!(collision_faces[3], Vector3::new(1.0, 3.0, 3.0));
        assert_eq!(collision_faces[4], Vector3::new(4.0, 3.0, 3.0));
        assert_eq!(collision_faces[5], Vector3::new(4.0, 3.0, 5.0));
    }

    #[test]
    fn cpu_array_mesh_uses_packed_face_geometry_normals_and_uvs() {
        let batch = PackedFaceBatch {
            faces: vec![PackedFace::new(1, 2, 3, FACE_TOP, 7, blocks::GRASS)],
        };

        let mesh = batch.cpu_array_mesh_vertices();

        assert_eq!(mesh.len(), 6);
        assert_eq!(
            mesh[0],
            (
                Vector3::new(1.0, 3.0, 3.0),
                Vector3::new(0.0, 1.0, 0.0),
                Vector2::new(0.7, 0.0)
            )
        );
        assert_eq!(
            mesh[1],
            (
                Vector3::new(2.0, 3.0, 4.0),
                Vector3::new(0.0, 1.0, 0.0),
                Vector2::new(0.8, 1.0)
            )
        );
        assert_eq!(
            mesh[2],
            (
                Vector3::new(1.0, 3.0, 4.0),
                Vector3::new(0.0, 1.0, 0.0),
                Vector2::new(0.7, 1.0)
            )
        );
    }

    #[test]
    fn cpu_array_mesh_keeps_grass_face_tiles_in_atlas_uvs() {
        let mut blocks_data = vec![0u8; PADDED_W * PADDED_H * PADDED_D * BLOCK_BYTES];
        write_block(&mut blocks_data, 1, 1, 1, blocks::GRASS as u16);

        let batch = build_packed_faces(&blocks_data);
        let top_face = batch
            .faces()
            .iter()
            .find(|face| face.face() == FACE_TOP)
            .expect("grass top face");
        let side_face = batch
            .faces()
            .iter()
            .find(|face| face.face() == FACE_LEFT)
            .expect("grass side face");
        let bottom_face = batch
            .faces()
            .iter()
            .find(|face| face.face() == FACE_BOTTOM)
            .expect("grass bottom face");

        let mut top_vertices = Vec::new();
        append_cpu_array_mesh_face(*top_face, &mut top_vertices);
        let mut side_vertices = Vec::new();
        append_cpu_array_mesh_face(*side_face, &mut side_vertices);
        let mut bottom_vertices = Vec::new();
        append_cpu_array_mesh_face(*bottom_face, &mut bottom_vertices);

        assert_eq!(top_vertices[0].2, Vector2::new(0.0, 0.0));
        assert_eq!(side_vertices[0].2, Vector2::new(0.1, 1.0));
        assert_eq!(bottom_vertices[0].2, Vector2::new(0.2, 0.0));
    }

    #[test]
    fn cpu_array_mesh_uses_quad_vertices_and_indices() {
        let batch = PackedFaceBatch {
            faces: vec![PackedFace::new(1, 2, 3, FACE_TOP, 7, blocks::GRASS)],
        };

        let (vertices, normals, uvs, indices) = batch.indexed_cpu_array_mesh_arrays();

        assert_eq!(vertices.len(), 4);
        assert_eq!(normals.len(), 4);
        assert_eq!(uvs.len(), 4);
        assert_eq!(indices, vec![0, 2, 1, 0, 3, 2]);
    }

    #[test]
    fn indexed_cpu_array_mesh_preserves_grass_face_tiles() {
        let mut blocks_data = vec![0u8; PADDED_W * PADDED_H * PADDED_D * BLOCK_BYTES];
        write_block(&mut blocks_data, 1, 1, 1, blocks::GRASS as u16);

        let batch = build_packed_faces(&blocks_data);
        let top_face = PackedFaceBatch {
            faces: batch
                .faces()
                .iter()
                .copied()
                .filter(|face| face.face() == FACE_TOP)
                .collect(),
        };

        let (_, _, uvs, _) = top_face.indexed_cpu_array_mesh_arrays();

        assert_eq!(uvs[0], Vector2::new(0.0, 0.0));
    }

    #[test]
    fn cpu_array_mesh_respects_vertex_cap_by_whole_faces() {
        let face_count = MAX_CPU_ARRAY_MESH_VERTICES / 6 + 4;
        let batch = PackedFaceBatch {
            faces: vec![PackedFace::new(1, 2, 3, FACE_TOP, 7, blocks::GRASS); face_count],
        };

        let (vertices, _, _, indices) = batch.indexed_cpu_array_mesh_arrays();

        assert_eq!(indices.len(), MAX_CPU_ARRAY_MESH_VERTICES / 6 * 6);
        assert_eq!(vertices.len(), indices.len() / 6 * 4);
    }

    #[test]
    fn cpu_array_mesh_respects_vertex_cap_for_merged_faces() {
        let merged_face_vertices = 32 * 32 * 6;
        let face_count = MAX_CPU_ARRAY_MESH_VERTICES / merged_face_vertices + 4;
        let batch = PackedFaceBatch {
            faces: vec![
                PackedFace::with_extent(
                    0,
                    0,
                    0,
                    FACE_TOP,
                    7,
                    blocks::GRASS,
                    PackedFaceExtent { u: 32, v: 32 },
                );
                face_count
            ],
        };

        let (vertices, _, _, indices) = batch.indexed_cpu_array_mesh_arrays();

        assert!(indices.len() <= MAX_CPU_ARRAY_MESH_VERTICES);
        assert_eq!(indices.len() % 6, 0);
        assert_eq!(vertices.len(), indices.len() / 6 * 4);
    }

    #[test]
    fn allocator_reuses_freed_ranges() {
        let mut allocator = FaceRangeAllocator::new(12);
        let first = allocator.allocate(4).unwrap();
        let second = allocator.allocate(4).unwrap();
        let third = allocator.allocate(4).unwrap();

        assert_eq!(first, FaceRange { start: 0, len: 4 });
        assert_eq!(second, FaceRange { start: 4, len: 4 });
        assert_eq!(third, FaceRange { start: 8, len: 4 });

        allocator.free(second);
        assert_eq!(allocator.allocate(3), Some(FaceRange { start: 4, len: 3 }));
    }

    #[test]
    fn allocator_prefers_best_fit_free_range() {
        let mut allocator = FaceRangeAllocator::new(21);
        let first = allocator.allocate(4).unwrap();
        let _gap = allocator.allocate(2).unwrap();
        let second = allocator.allocate(6).unwrap();
        let _gap2 = allocator.allocate(2).unwrap();
        let third = allocator.allocate(3).unwrap();
        let _tail = allocator.allocate(4).unwrap();

        allocator.free(first);
        allocator.free(second);
        allocator.free(third);

        assert_eq!(allocator.allocate(3), Some(FaceRange { start: 14, len: 3 }));
        assert_eq!(allocator.allocate(4), Some(FaceRange { start: 0, len: 4 }));
    }

    #[test]
    fn allocator_merges_adjacent_ranges() {
        let mut allocator = FaceRangeAllocator::new(8);
        let first = allocator.allocate(2).unwrap();
        let second = allocator.allocate(3).unwrap();
        let third = allocator.allocate(3).unwrap();

        allocator.free(second);
        allocator.free(first);
        allocator.free(third);

        assert_eq!(allocator.allocate(8), Some(FaceRange { start: 0, len: 8 }));
    }

    #[test]
    fn allocator_stats_report_fragmentation_budget_inputs() {
        let mut allocator = FaceRangeAllocator::new(12);
        let first = allocator.allocate(3).unwrap();
        let second = allocator.allocate(4).unwrap();
        let third = allocator.allocate(2).unwrap();
        allocator.free(second);

        assert_eq!(
            allocator.stats(),
            FaceAllocatorStats {
                free_ranges: 2,
                free_faces: 7,
                largest_free_faces: 4,
            }
        );
        assert_eq!(allocator.stats().fragmented_free_faces(), 3);
        assert!((allocator.stats().fragmentation_pct() - 42.857).abs() < 0.001);

        allocator.free(first);
        assert_eq!(
            allocator.stats(),
            FaceAllocatorStats {
                free_ranges: 2,
                free_faces: 10,
                largest_free_faces: 7,
            }
        );
        assert_eq!(allocator.stats().fragmented_free_faces(), 3);
        assert_eq!(allocator.stats().fragmentation_pct(), 30.0);

        allocator.free(third);
        assert_eq!(
            allocator.stats(),
            FaceAllocatorStats {
                free_ranges: 1,
                free_faces: 12,
                largest_free_faces: 12,
            }
        );
        assert_eq!(allocator.stats().fragmented_free_faces(), 0);
        assert_eq!(allocator.stats().fragmentation_pct(), 0.0);
    }

    #[test]
    fn compositor_gpu_timestamp_delta_tracks_latest_valid_pair() {
        let timestamps = [
            ("other", 10_000),
            (GPU_TERRAIN_TIMESTAMP_BEGIN, 20_000),
            (GPU_TERRAIN_TIMESTAMP_END, 21_250),
            (GPU_TERRAIN_TIMESTAMP_BEGIN, 30_000),
            (GPU_TERRAIN_TIMESTAMP_END, 32_500),
        ];

        assert_eq!(compositor_gpu_timestamp_delta_ms(timestamps), Some(2.5));
    }

    #[test]
    fn compositor_gpu_timestamp_delta_ignores_unpaired_or_reversed_markers() {
        let timestamps = [
            (GPU_TERRAIN_TIMESTAMP_END, 10_000),
            (GPU_TERRAIN_TIMESTAMP_BEGIN, 30_000),
            (GPU_TERRAIN_TIMESTAMP_END, 20_000),
        ];

        assert_eq!(compositor_gpu_timestamp_delta_ms(timestamps), None);
    }

    #[test]
    fn indirect_draw_command_layout_matches_rendering_device_stride() {
        assert_eq!(
            std::mem::size_of::<IndirectDrawCommand>(),
            INDIRECT_DRAW_BYTES
        );
        assert_eq!(
            std::mem::align_of::<IndirectDrawCommand>(),
            std::mem::align_of::<u32>()
        );

        let slot = GpuTerrainSlot {
            start_face: 7,
            face_count: 13,
        };
        let mut bytes = Vec::new();
        IndirectDrawCommand::for_slot(slot).append_bytes(&mut bytes);

        assert_eq!(bytes.len(), INDIRECT_DRAW_BYTES);
        let words = bytes
            .chunks_exact(std::mem::size_of::<u32>())
            .map(|chunk| u32::from_le_bytes(chunk.try_into().unwrap()))
            .collect::<Vec<_>>();
        assert_eq!(words, vec![6, 13, 0, 7]);
    }

    #[test]
    fn draw_command_buffer_byte_counts_track_active_and_capacity() {
        assert_eq!(draw_command_active_bytes(0), 0);
        assert_eq!(draw_command_active_bytes(3), 3 * INDIRECT_DRAW_BYTES);
        assert_eq!(
            draw_command_capacity_bytes(MAX_INDIRECT_DRAWS),
            MAX_INDIRECT_DRAWS * INDIRECT_DRAW_BYTES
        );
    }

    #[test]
    fn draw_keys_patch_insert_and_swap_remove_commands() {
        let first = GpuSubchunkKey {
            chunk_x: 0,
            sub_y: 0,
            chunk_z: 0,
        };
        let second = GpuSubchunkKey {
            chunk_x: 1,
            sub_y: 0,
            chunk_z: 0,
        };
        let third = GpuSubchunkKey {
            chunk_x: 2,
            sub_y: 0,
            chunk_z: 0,
        };
        let mut draw_keys = Vec::new();
        let mut draw_indices = HashMap::new();

        assert_eq!(
            insert_draw_key(&mut draw_keys, &mut draw_indices, first, 3),
            Some(0)
        );
        assert_eq!(
            insert_draw_key(&mut draw_keys, &mut draw_indices, second, 3),
            Some(1)
        );
        assert_eq!(
            insert_draw_key(&mut draw_keys, &mut draw_indices, third, 3),
            Some(2)
        );
        assert_eq!(
            insert_draw_key(
                &mut draw_keys,
                &mut draw_indices,
                GpuSubchunkKey {
                    chunk_x: 3,
                    sub_y: 0,
                    chunk_z: 0,
                },
                3,
            ),
            None
        );

        assert_eq!(
            remove_draw_key(&mut draw_keys, &mut draw_indices, second),
            Some(DrawCommandRemoval {
                index: 1,
                moved_key: Some(third),
            })
        );
        assert_eq!(draw_keys, vec![first, third]);
        assert_eq!(draw_indices.get(&first), Some(&0));
        assert_eq!(draw_indices.get(&third), Some(&1));
        assert!(!draw_indices.contains_key(&second));

        assert_eq!(
            remove_draw_key(&mut draw_keys, &mut draw_indices, third),
            Some(DrawCommandRemoval {
                index: 1,
                moved_key: None,
            })
        );
        assert_eq!(draw_keys, vec![first]);
        assert_eq!(draw_indices.get(&first), Some(&0));
        assert!(!draw_indices.contains_key(&third));
    }

    #[test]
    fn upload_failure_classification_separates_capacity_and_fragmentation() {
        let fragmented = FaceAllocatorStats {
            free_ranges: 2,
            free_faces: 10,
            largest_free_faces: 6,
        };
        assert_eq!(
            upload_failure_kind(fragmented, 8),
            UploadFailureKind::Fragmentation
        );

        let exhausted = FaceAllocatorStats {
            free_ranges: 1,
            free_faces: 6,
            largest_free_faces: 6,
        };
        assert_eq!(
            upload_failure_kind(exhausted, 8),
            UploadFailureKind::Capacity
        );
    }

    #[test]
    fn subchunk_bytes_encode_debug_origin() {
        let batch = PackedFaceBatch {
            faces: vec![PackedFace::new(1, 2, 3, FACE_TOP, 7, blocks::STONE)],
        };

        let bytes = batch.to_bytes_for_subchunk(GpuSubchunkKey {
            chunk_x: -2,
            sub_y: 3,
            chunk_z: 5,
        });

        assert_eq!(read_u32(&bytes, 4) >> 16, pack_signed_i16(-2));
        assert_eq!(read_u32(&bytes, 8) >> 16, pack_signed_i16(5));
        assert_eq!(read_u32(&bytes, 12), pack_signed_i16(3));
    }

    #[test]
    fn push_constants_include_lighting_block() {
        let lighting = GpuTerrainLighting {
            direction_to_light: Vector3::new(0.0, 2.0, 0.0),
            color: Color::from_rgb(0.8, 0.7, 0.6),
            energy: 0.45,
            ambient: 0.5,
        };
        let bytes = push_constant_bytes_from_projection(
            Projection::from_cols(
                Vector4::new(1.0, 0.0, 0.0, 0.0),
                Vector4::new(0.0, 1.0, 0.0, 0.0),
                Vector4::new(0.0, 0.0, 1.0, 0.0),
                Vector4::new(0.0, 0.0, 0.0, 1.0),
            ),
            lighting,
            GpuTerrainAtlasLayout {
                columns: 10,
                rows: 1,
            },
        );

        assert_eq!(bytes.len(), TERRAIN_PUSH_CONSTANT_BYTES);
        assert_eq!(read_f32(&bytes, 64), 0.0);
        assert_eq!(read_f32(&bytes, 68), 1.0);
        assert_eq!(read_f32(&bytes, 72), 0.0);
        assert_eq!(read_f32(&bytes, 76), 0.5);
        assert_eq!(read_f32(&bytes, 80), 0.8);
        assert_eq!(read_f32(&bytes, 84), 0.7);
        assert_eq!(read_f32(&bytes, 88), 0.6);
        assert_eq!(read_f32(&bytes, 92), 0.45);
        assert_eq!(read_f32(&bytes, 96), 0.1);
        assert_eq!(read_f32(&bytes, 100), 1.0);
        assert_eq!(read_f32(&bytes, 104), 10.0);
        assert_eq!(read_f32(&bytes, 108), 1.0);
    }

    #[test]
    fn atlas_layout_matches_current_block_texture_atlas() {
        assert_eq!(
            GpuTerrainAtlasLayout::from_image_size(640, 64),
            Some(GpuTerrainAtlasLayout {
                columns: 10,
                rows: 1,
            })
        );
    }

    #[test]
    fn atlas_layout_rejects_incomplete_or_too_small_atlas() {
        assert_eq!(GpuTerrainAtlasLayout::from_image_size(639, 64), None);
        assert_eq!(GpuTerrainAtlasLayout::from_image_size(64, 64), None);
    }
}
