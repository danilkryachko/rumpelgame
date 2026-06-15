#version 450

const uint CHUNK_W = 32;
const uint SUBCHUNK_H = 32;
const uint CHUNK_D = 32;
const int PADDED_W = 34;
const int PADDED_H = 34;
const int PADDED_D = 34;
/* RUMPELMC_ATLAS_LAYOUT */
const uint MAX_VERTICES = 100000u;

const uint FACE_LEFT = 0u;
const uint FACE_RIGHT = 1u;
const uint FACE_BOTTOM = 2u;
const uint FACE_TOP = 3u;
const uint FACE_BACK = 4u;
const uint FACE_FRONT = 5u;

/* RUMPELMC_BLOCK_SEMANTICS */

// Blocks array: 1 block per uint (we unpack it from Go's 16-bit array in Rust or just use 32-bit directly)
layout(set = 0, binding = 0, std430) restrict readonly buffer VoxelBuffer {
    uint blocks[];
} in_buf;

// Output vertices: x, y, z, nx, ny, nz, u, v
layout(set = 0, binding = 1, std430) restrict buffer OutputBuffer {
    uint vertex_count;
    float vertices[];
} out_buf;

layout(local_size_x = 8, local_size_y = 8, local_size_z = 8) in;

uint get_block(uint x, uint y, uint z) {
    if (x >= CHUNK_W || y >= SUBCHUNK_H || z >= CHUNK_D) return 0u;
    return in_buf.blocks[(x + 1u) + (y + 1u) * uint(PADDED_W * PADDED_D) + (z + 1u) * uint(PADDED_W)];
}

uint get_padded_block(int x, int y, int z) {
    if (x < 0 || x >= PADDED_W || y < 0 || y >= PADDED_H || z < 0 || z >= PADDED_D) return 0u;
    return in_buf.blocks[uint(x) + uint(y) * uint(PADDED_W * PADDED_D) + uint(z) * uint(PADDED_W)];
}

// 6 faces, 2 triangles per face, 3 vertices per triangle = 6 vertices per face
// Each vertex is 8 floats: pos(3) + normal(3) + uv(2)
void push_vertex(uint idx, vec3 pos, vec3 normal, vec2 uv) {
    uint base = idx * 8u;
    out_buf.vertices[base + 0u] = pos.x;
    out_buf.vertices[base + 1u] = pos.y;
    out_buf.vertices[base + 2u] = pos.z;
    out_buf.vertices[base + 3u] = normal.x;
    out_buf.vertices[base + 4u] = normal.y;
    out_buf.vertices[base + 5u] = normal.z;
    out_buf.vertices[base + 6u] = uv.x;
    out_buf.vertices[base + 7u] = uv.y;
}

vec2 atlas_uv(vec2 tile_uv, uint tile_index) {
    float col = mod(float(tile_index), ATLAS_COLUMNS);
    float row = floor(float(tile_index) / ATLAS_COLUMNS);
    return vec2((col + tile_uv.x) / ATLAS_COLUMNS, (row + tile_uv.y) / ATLAS_ROWS);
}

uint reserve_vertices(uint count) {
    uint old_count;
    uint new_count;
    uint previous_count;
    do {
        old_count = out_buf.vertex_count;
        if (old_count + count > MAX_VERTICES) {
            return MAX_VERTICES;
        }
        new_count = old_count + count;
        previous_count = atomicCompSwap(out_buf.vertex_count, old_count, new_count);
    } while (previous_count != old_count);
    return old_count;
}

void add_face(vec3 pos, vec3 normal, uint block_id, uint face_idx) {
    uint start_v = reserve_vertices(6u);
    if (start_v == MAX_VERTICES) {
        return;
    }
    uint tile = texture_tile(block_id, face_idx);
    
    // Simplistic face vertices for a 1x1x1 cube at `pos`
    vec3 p0, p1, p2, p3;
    
    if (face_idx == 0u) { // Left (-X)
        p0 = pos + vec3(0.0,0.0,1.0); p1 = pos + vec3(0.0,1.0,1.0); p2 = pos + vec3(0.0,1.0,0.0); p3 = pos + vec3(0.0,0.0,0.0);
    } else if (face_idx == 1u) { // Right (+X)
        p0 = pos + vec3(1.0,0.0,0.0); p1 = pos + vec3(1.0,1.0,0.0); p2 = pos + vec3(1.0,1.0,1.0); p3 = pos + vec3(1.0,0.0,1.0);
    } else if (face_idx == 2u) { // Bottom (-Y)
        p0 = pos + vec3(0.0,0.0,1.0); p1 = pos + vec3(0.0,0.0,0.0); p2 = pos + vec3(1.0,0.0,0.0); p3 = pos + vec3(1.0,0.0,1.0);
    } else if (face_idx == 3u) { // Top (+Y)
        p0 = pos + vec3(0.0,1.0,0.0); p1 = pos + vec3(0.0,1.0,1.0); p2 = pos + vec3(1.0,1.0,1.0); p3 = pos + vec3(1.0,1.0,0.0);
    } else if (face_idx == 4u) { // Back (-Z)
        p0 = pos + vec3(1.0,0.0,0.0); p1 = pos + vec3(0.0,0.0,0.0); p2 = pos + vec3(0.0,1.0,0.0); p3 = pos + vec3(1.0,1.0,0.0);
    } else { // Front (+Z)
        p0 = pos + vec3(0.0,0.0,1.0); p1 = pos + vec3(1.0,0.0,1.0); p2 = pos + vec3(1.0,1.0,1.0); p3 = pos + vec3(0.0,1.0,1.0);
    }

    vec2 uv0 = vec2(0.0,0.0);
    vec2 uv1 = vec2(0.0,1.0);
    vec2 uv2 = vec2(1.0,1.0);
    vec2 uv3 = vec2(1.0,0.0);
    if (face_idx == FACE_LEFT || face_idx == FACE_RIGHT) {
        uv0 = vec2(0.0,1.0);
        uv1 = vec2(0.0,0.0);
        uv2 = vec2(1.0,0.0);
        uv3 = vec2(1.0,1.0);
    } else if (face_idx == FACE_BACK) {
        uv0 = vec2(1.0,1.0);
        uv1 = vec2(0.0,1.0);
        uv2 = vec2(0.0,0.0);
        uv3 = vec2(1.0,0.0);
    } else if (face_idx == FACE_FRONT) {
        uv0 = vec2(0.0,1.0);
        uv1 = vec2(1.0,1.0);
        uv2 = vec2(1.0,0.0);
        uv3 = vec2(0.0,0.0);
    }

    push_vertex(start_v + 0u, p0, normal, atlas_uv(uv0, tile));
    push_vertex(start_v + 1u, p2, normal, atlas_uv(uv2, tile));
    push_vertex(start_v + 2u, p1, normal, atlas_uv(uv1, tile));
    push_vertex(start_v + 3u, p0, normal, atlas_uv(uv0, tile));
    push_vertex(start_v + 4u, p3, normal, atlas_uv(uv3, tile));
    push_vertex(start_v + 5u, p2, normal, atlas_uv(uv2, tile));
}

void main() {
    uint x = gl_GlobalInvocationID.x;
    uint y = gl_GlobalInvocationID.y;
    uint z = gl_GlobalInvocationID.z;

    if (x >= CHUNK_W || y >= SUBCHUNK_H || z >= CHUNK_D) return;

    uint block = get_block(x, y, z);
    if (!is_solid(block)) return;

    vec3 pos = vec3(float(x), float(y), float(z));
    
    int px = int(x) + 1;
    int py = int(y) + 1;
    int pz = int(z) + 1;

    if (!is_solid(get_padded_block(px - 1, py, pz))) add_face(pos, vec3(-1.0, 0.0, 0.0), block, 0u);
    if (!is_solid(get_padded_block(px + 1, py, pz))) add_face(pos, vec3(1.0, 0.0, 0.0), block, 1u);
    if (!is_solid(get_padded_block(px, py - 1, pz))) add_face(pos, vec3(0.0, -1.0, 0.0), block, 2u);
    if (!is_solid(get_padded_block(px, py + 1, pz))) add_face(pos, vec3(0.0, 1.0, 0.0), block, 3u);
    if (!is_solid(get_padded_block(px, py, pz - 1))) add_face(pos, vec3(0.0, 0.0, -1.0), block, 4u);
    if (!is_solid(get_padded_block(px, py, pz + 1))) add_face(pos, vec3(0.0, 0.0, 1.0), block, 5u);
}
