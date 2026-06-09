#version 450

const uint CHUNK_W = 32;
const uint CHUNK_H = 512;
const uint CHUNK_D = 32;

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
    if (x >= CHUNK_W || y >= CHUNK_H || z >= CHUNK_D) return 0u;
    return in_buf.blocks[x + y * CHUNK_W * CHUNK_D + z * CHUNK_W];
}

// 6 faces, 2 triangles per face, 3 vertices per triangle = 6 vertices per face
// Each vertex is 8 floats: pos(3) + normal(3) + uv(2)
void push_vertex(uint idx, vec3 pos, vec3 normal, vec2 uv) {
    uint base = 1u + idx * 8u; // +1 to skip vertex_count
    out_buf.vertices[base + 0u] = pos.x;
    out_buf.vertices[base + 1u] = pos.y;
    out_buf.vertices[base + 2u] = pos.z;
    out_buf.vertices[base + 3u] = normal.x;
    out_buf.vertices[base + 4u] = normal.y;
    out_buf.vertices[base + 5u] = normal.z;
    out_buf.vertices[base + 6u] = uv.x;
    out_buf.vertices[base + 7u] = uv.y;
}

void add_face(vec3 pos, vec3 normal, uint block_id, uint face_idx) {
    uint start_v = atomicAdd(out_buf.vertex_count, 6u);
    
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

    push_vertex(start_v + 0u, p0, normal, vec2(0.0,0.0));
    push_vertex(start_v + 1u, p2, normal, vec2(1.0,1.0));
    push_vertex(start_v + 2u, p1, normal, vec2(0.0,1.0));
    push_vertex(start_v + 3u, p0, normal, vec2(0.0,0.0));
    push_vertex(start_v + 4u, p3, normal, vec2(1.0,0.0));
    push_vertex(start_v + 5u, p2, normal, vec2(1.0,1.0));
}

void main() {
    uint x = gl_GlobalInvocationID.x;
    uint y = gl_GlobalInvocationID.y;
    uint z = gl_GlobalInvocationID.z;

    if (x >= CHUNK_W || y >= CHUNK_H || z >= CHUNK_D) return;

    uint block = get_block(x, y, z);
    if (block == 0u) return; // Air

    vec3 pos = vec3(float(x), float(y), float(z));
    
    if (get_block(x - 1u, y, z) == 0u) add_face(pos, vec3(-1.0, 0.0, 0.0), block, 0u);
    if (get_block(x + 1u, y, z) == 0u) add_face(pos, vec3(1.0, 0.0, 0.0), block, 1u);
    if (get_block(x, y - 1u, z) == 0u) add_face(pos, vec3(0.0, -1.0, 0.0), block, 2u);
    if (get_block(x, y + 1u, z) == 0u) add_face(pos, vec3(0.0, 1.0, 0.0), block, 3u);
    if (get_block(x, y, z - 1u) == 0u) add_face(pos, vec3(0.0, 0.0, -1.0), block, 4u);
    if (get_block(x, y, z + 1u) == 0u) add_face(pos, vec3(0.0, 0.0, 1.0), block, 5u);
}
