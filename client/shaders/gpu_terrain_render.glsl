// -- VERTEX --
#version 450

struct PackedFace {
    uint pos_face_tile;
    uint block_flags;
    uint extent;
    uint pad;
};

layout(set = 0, binding = 0, std430) readonly buffer FaceBuffer {
    PackedFace faces[];
} face_buffer;

layout(set = 0, binding = 1) uniform sampler2D atlas_texture;

layout(push_constant, std430) uniform TerrainPushConstants {
    mat4 clip_from_world;
    vec4 light_direction_ambient;
    vec4 light_color_energy;
    vec4 atlas_layout;
} terrain_push;

layout(location = 0) out vec2 uv_out;
layout(location = 1) out vec3 lighting_out;

vec3 face_corner(uint face_idx, uint corner_idx) {
    if (face_idx == 0u) {
        vec3 corners[4] = vec3[4](
            vec3(0.0, 0.0, 1.0),
            vec3(0.0, 1.0, 1.0),
            vec3(0.0, 1.0, 0.0),
            vec3(0.0, 0.0, 0.0)
        );
        return corners[corner_idx];
    }
    if (face_idx == 1u) {
        vec3 corners[4] = vec3[4](
            vec3(1.0, 0.0, 0.0),
            vec3(1.0, 1.0, 0.0),
            vec3(1.0, 1.0, 1.0),
            vec3(1.0, 0.0, 1.0)
        );
        return corners[corner_idx];
    }
    if (face_idx == 2u) {
        vec3 corners[4] = vec3[4](
            vec3(0.0, 0.0, 1.0),
            vec3(0.0, 0.0, 0.0),
            vec3(1.0, 0.0, 0.0),
            vec3(1.0, 0.0, 1.0)
        );
        return corners[corner_idx];
    }
    if (face_idx == 3u) {
        vec3 corners[4] = vec3[4](
            vec3(0.0, 1.0, 0.0),
            vec3(0.0, 1.0, 1.0),
            vec3(1.0, 1.0, 1.0),
            vec3(1.0, 1.0, 0.0)
        );
        return corners[corner_idx];
    }
    if (face_idx == 4u) {
        vec3 corners[4] = vec3[4](
            vec3(1.0, 0.0, 0.0),
            vec3(0.0, 0.0, 0.0),
            vec3(0.0, 1.0, 0.0),
            vec3(1.0, 1.0, 0.0)
        );
        return corners[corner_idx];
    }

    vec3 corners[4] = vec3[4](
        vec3(0.0, 0.0, 1.0),
        vec3(1.0, 0.0, 1.0),
        vec3(1.0, 1.0, 1.0),
        vec3(0.0, 1.0, 1.0)
    );
    return corners[corner_idx];
}

vec3 face_normal(uint face_idx) {
    if (face_idx == 0u) return vec3(-1.0, 0.0, 0.0);
    if (face_idx == 1u) return vec3(1.0, 0.0, 0.0);
    if (face_idx == 2u) return vec3(0.0, -1.0, 0.0);
    if (face_idx == 3u) return vec3(0.0, 1.0, 0.0);
    if (face_idx == 4u) return vec3(0.0, 0.0, -1.0);
    return vec3(0.0, 0.0, 1.0);
}

vec3 face_lighting(uint face_idx) {
    vec3 normal = face_normal(face_idx);
    vec3 direction_to_light = normalize(terrain_push.light_direction_ambient.xyz);
    float ambient = clamp(terrain_push.light_direction_ambient.w, 0.0, 1.0);
    vec3 light_color = max(terrain_push.light_color_energy.rgb, vec3(0.0));
    float light_energy = max(terrain_push.light_color_energy.w, 0.0);
    float diffuse = max(dot(normal, direction_to_light), 0.0);
    return vec3(ambient) + light_color * diffuse * light_energy;
}

vec2 face_uv(uint face_idx, uint corner_idx) {
    if (face_idx == 0u || face_idx == 1u) {
        vec2 uvs[4] = vec2[4](
            vec2(0.0, 1.0),
            vec2(0.0, 0.0),
            vec2(1.0, 0.0),
            vec2(1.0, 1.0)
        );
        return uvs[corner_idx];
    }
    if (face_idx == 4u) {
        vec2 uvs[4] = vec2[4](
            vec2(1.0, 1.0),
            vec2(0.0, 1.0),
            vec2(0.0, 0.0),
            vec2(1.0, 0.0)
        );
        return uvs[corner_idx];
    }
    if (face_idx == 5u) {
        vec2 uvs[4] = vec2[4](
            vec2(0.0, 1.0),
            vec2(1.0, 1.0),
            vec2(1.0, 0.0),
            vec2(0.0, 0.0)
        );
        return uvs[corner_idx];
    }

    vec2 uvs[4] = vec2[4](
        vec2(0.0, 0.0),
        vec2(0.0, 1.0),
        vec2(1.0, 1.0),
        vec2(1.0, 0.0)
    );
    return uvs[corner_idx];
}

vec2 atlas_uv(vec2 tile_uv, uint tile_index) {
    float columns = max(terrain_push.atlas_layout.z, 1.0);
    float col = mod(float(tile_index), columns);
    float row = floor(float(tile_index) / columns);
    return vec2(col + tile_uv.x, row + tile_uv.y) * terrain_push.atlas_layout.xy;
}

int unpack_signed_i16(uint value) {
    uint low = value & 65535u;
    if (low >= 32768u) {
        return int(low) - 65536;
    }
    return int(low);
}

void main() {
    uint face_instance = uint(gl_InstanceIndex);
    PackedFace face = face_buffer.faces[face_instance];

    uint x = face.pos_face_tile & 63u;
    uint y = (face.pos_face_tile >> 6u) & 63u;
    uint z = (face.pos_face_tile >> 12u) & 63u;
    uint face_idx = (face.pos_face_tile >> 18u) & 7u;
    uint tile = (face.pos_face_tile >> 21u) & 2047u;
    int chunk_x = unpack_signed_i16(face.block_flags >> 16u);
    int chunk_z = unpack_signed_i16(face.extent >> 16u);
    int sub_y = unpack_signed_i16(face.pad);

    uint corner_map[6] = uint[6](0u, 2u, 1u, 0u, 3u, 2u);
    uint corner_idx = corner_map[uint(gl_VertexIndex) % 6u];
    vec3 local_pos = vec3(float(x), float(y), float(z)) + face_corner(face_idx, corner_idx);
    vec3 world_pos = local_pos + vec3(float(chunk_x * 32), float(sub_y * 32), float(chunk_z * 32));

    gl_Position = terrain_push.clip_from_world * vec4(world_pos, 1.0);
    uv_out = atlas_uv(face_uv(face_idx, corner_idx), tile);
    lighting_out = face_lighting(face_idx);
}

// -- FRAGMENT --
#version 450

layout(set = 0, binding = 1) uniform sampler2D atlas_texture;

layout(location = 0) in vec2 uv_in;
layout(location = 1) in vec3 lighting_in;
layout(location = 0) out vec4 frag_color;

void main() {
    vec4 texel = texture(atlas_texture, uv_in);
    frag_color = vec4(texel.rgb * lighting_in, 1.0);
}
