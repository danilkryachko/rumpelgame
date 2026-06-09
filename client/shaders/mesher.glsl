#version 450

const uint CHUNK_W = 32;
const uint CHUNK_H = 512;
const uint CHUNK_D = 32;

// Blocks array: 1 block per uint (we unpack it from Go's 16-bit array in Rust or just use 32-bit directly)
layout(set = 0, binding = 0, std430) restrict readonly buffer VoxelBuffer {
    uint blocks[];
};

// Output vertices: x, y, z, nx, ny, nz, u, v
layout(set = 0, binding = 1, std430) restrict buffer OutputBuffer {
    uint vertex_count;
    float vertices[];
};

layout(local_size_x = 8, local_size_y = 8, local_size_z = 8) in;

uint get_block(uint x, uint y, uint z) {
    if (x >= CHUNK_W || y >= CHUNK_H || z >= CHUNK_D) return 0;
    return blocks[x + y * CHUNK_W * CHUNK_D + z * CHUNK_W];
}

// 6 faces, 2 triangles per face, 3 vertices per triangle = 6 vertices per face
// Each vertex is 8 floats: pos(3) + normal(3) + uv(2)
void push_vertex(uint idx, vec3 pos, vec3 normal, vec2 uv) {
    uint base = 1 + idx * 8; // +1 to skip vertex_count
    vertices[base + 0] = pos.x;
    vertices[base + 1] = pos.y;
    vertices[base + 2] = pos.z;
    vertices[base + 3] = normal.x;
    vertices[base + 4] = normal.y;
    vertices[base + 5] = normal.z;
    vertices[base + 6] = uv.x;
    vertices[base + 7] = uv.y;
}

void add_face(vec3 pos, vec3 normal, uint block_id, uint face_idx) {
    uint start_v = atomicAdd(vertex_count, 6);
    
    // Simplistic face vertices for a 1x1x1 cube at `pos`
    vec3 p0, p1, p2, p3;
    
    if (face_idx == 0) { // Left (-X)
        p0 = pos + vec3(0,0,1); p1 = pos + vec3(0,1,1); p2 = pos + vec3(0,1,0); p3 = pos + vec3(0,0,0);
    } else if (face_idx == 1) { // Right (+X)
        p0 = pos + vec3(1,0,0); p1 = pos + vec3(1,1,0); p2 = pos + vec3(1,1,1); p3 = pos + vec3(1,0,1);
    } else if (face_idx == 2) { // Bottom (-Y)
        p0 = pos + vec3(0,0,1); p1 = pos + vec3(0,0,0); p2 = pos + vec3(1,0,0); p3 = pos + vec3(1,0,1);
    } else if (face_idx == 3) { // Top (+Y)
        p0 = pos + vec3(0,1,0); p1 = pos + vec3(0,1,1); p2 = pos + vec3(1,1,1); p3 = pos + vec3(1,1,0);
    } else if (face_idx == 4) { // Back (-Z)
        p0 = pos + vec3(1,0,0); p1 = pos + vec3(0,0,0); p2 = pos + vec3(0,1,0); p3 = pos + vec3(1,1,0);
    } else { // Front (+Z)
        p0 = pos + vec3(0,0,1); p1 = pos + vec3(1,0,1); p2 = pos + vec3(1,1,1); p3 = pos + vec3(0,1,1);
    }

    push_vertex(start_v + 0, p0, normal, vec2(0,0));
    push_vertex(start_v + 1, p1, normal, vec2(0,1));
    push_vertex(start_v + 2, p2, normal, vec2(1,1));
    push_vertex(start_v + 3, p0, normal, vec2(0,0));
    push_vertex(start_v + 4, p2, normal, vec2(1,1));
    push_vertex(start_v + 5, p3, normal, vec2(1,0));
}

void main() {
    uint x = gl_GlobalInvocationID.x;
    uint y = gl_GlobalInvocationID.y;
    uint z = gl_GlobalInvocationID.z;

    if (x >= CHUNK_W || y >= CHUNK_H || z >= CHUNK_D) return;

    uint block = get_block(x, y, z);
    if (block == 0) return; // Air

    vec3 pos = vec3(x, y, z);
    
    if (get_block(x - 1, y, z) == 0) add_face(pos, vec3(-1, 0, 0), block, 0);
    if (get_block(x + 1, y, z) == 0) add_face(pos, vec3(1, 0, 0), block, 1);
    if (get_block(x, y - 1, z) == 0) add_face(pos, vec3(0, -1, 0), block, 2);
    if (get_block(x, y + 1, z) == 0) add_face(pos, vec3(0, 1, 0), block, 3);
    if (get_block(x, y, z - 1) == 0) add_face(pos, vec3(0, 0, -1), block, 4);
    if (get_block(x, y, z + 1) == 0) add_face(pos, vec3(0, 0, 1), block, 5);
}
