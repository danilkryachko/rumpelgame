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
layout(location = 1) flat out vec2 tile_offset_out;
layout(location = 2) flat out vec3 lighting_out;
layout(location = 3) flat out uint cutout_flags_out;

const vec3 FACE_NORMALS[8] = vec3[8](
    vec3(-1.0, 0.0, 0.0),
    vec3(1.0, 0.0, 0.0),
    vec3(0.0, -1.0, 0.0),
    vec3(0.0, 1.0, 0.0),
    vec3(0.0, 0.0, -1.0),
    vec3(0.0, 0.0, 1.0),
    vec3(0.0, 0.0, 1.0),
    vec3(0.0, 0.0, 1.0)
);

const vec2 FACE_UV_FACTORS[32] = vec2[32](
    vec2(0.0, 1.0), vec2(0.0, 0.0), vec2(1.0, 0.0), vec2(1.0, 1.0),
    vec2(0.0, 1.0), vec2(0.0, 0.0), vec2(1.0, 0.0), vec2(1.0, 1.0),
    vec2(0.0, 0.0), vec2(0.0, 1.0), vec2(1.0, 1.0), vec2(1.0, 0.0),
    vec2(0.0, 0.0), vec2(0.0, 1.0), vec2(1.0, 1.0), vec2(1.0, 0.0),
    vec2(1.0, 1.0), vec2(0.0, 1.0), vec2(0.0, 0.0), vec2(1.0, 0.0),
    vec2(0.0, 1.0), vec2(1.0, 1.0), vec2(1.0, 0.0), vec2(0.0, 0.0),
    vec2(0.0, 0.0), vec2(0.0, 1.0), vec2(1.0, 1.0), vec2(1.0, 0.0),
    vec2(0.0, 0.0), vec2(0.0, 1.0), vec2(1.0, 1.0), vec2(1.0, 0.0)
);

const vec3 FACE_CORNER_BASES[32] = vec3[32](
    vec3(0.0, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec3(0.0, 0.0, 0.0),
    vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0),
    vec3(0.0, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec3(0.0, 0.0, 0.0),
    vec3(0.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0),
    vec3(0.0, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec3(0.0, 0.0, 0.0),
    vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0),
    vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0),
    vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0)
);

const vec3 FACE_CORNER_EXTENT_X_FACTORS[32] = vec3[32](
    vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 0.0), vec3(0.0, 0.0, 0.0),
    vec3(0.0, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0),
    vec3(0.0, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0),
    vec3(0.0, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0),
    vec3(1.0, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0),
    vec3(0.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(0.0, 0.0, 0.0),
    vec3(0.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(0.0, 0.0, 0.0),
    vec3(0.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(0.0, 0.0, 0.0)
);

const vec3 FACE_CORNER_EXTENT_Y_FACTORS[32] = vec3[32](
    vec3(0.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, 0.0),
    vec3(0.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, 0.0),
    vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec3(0.0, 0.0, 1.0),
    vec3(0.0, 0.0, 0.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 0.0),
    vec3(0.0, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0),
    vec3(0.0, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0),
    vec3(0.0, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0),
    vec3(0.0, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0)
);

const uint TRIANGLE_CORNER_INDICES[6] = uint[6](0u, 2u, 1u, 0u, 3u, 2u);
const uint PACKED_FACE_EXTENT_FLAGS_SHIFT = 12u;
const uint PACKED_FACE_EXTENT_FLAGS_MASK = 15u;

vec3 face_corner(uint face_idx, uint corner_idx, vec2 extent) {
    uint table_idx = (face_idx & 7u) * 4u + corner_idx;
    return FACE_CORNER_BASES[table_idx]
        + FACE_CORNER_EXTENT_X_FACTORS[table_idx] * extent.x
        + FACE_CORNER_EXTENT_Y_FACTORS[table_idx] * extent.y;
}

vec3 face_normal(uint face_idx) {
    return FACE_NORMALS[face_idx & 7u];
}

vec3 face_lighting(uint face_idx) {
    vec3 normal = face_normal(face_idx);
    vec3 direction_to_light = terrain_push.light_direction_ambient.xyz;
    float ambient = terrain_push.light_direction_ambient.w;
    vec3 light_color = terrain_push.light_color_energy.rgb;
    float light_energy = terrain_push.light_color_energy.w;
    float diffuse = max(dot(normal, direction_to_light), 0.0);
    return vec3(ambient) + light_color * diffuse * light_energy;
}

vec2 face_uv(uint face_idx, uint corner_idx, vec2 extent) {
    return FACE_UV_FACTORS[(face_idx & 7u) * 4u + corner_idx] * extent;
}

vec2 atlas_tile_offset(uint tile) {
    float tile_index = float(tile);
    float columns = max(terrain_push.atlas_layout.z, 1.0);
    return vec2(mod(tile_index, columns), floor(tile_index / columns));
}

int unpack_signed_i16(uint value) {
    uint low = value & 65535u;
    return int(low & 32767u) - int(low & 32768u);
}

void main() {
    uint face_instance = uint(gl_InstanceIndex);
    PackedFace face = face_buffer.faces[face_instance];

    uint x = face.pos_face_tile & 63u;
    uint y = (face.pos_face_tile >> 6u) & 63u;
    uint z = (face.pos_face_tile >> 12u) & 63u;
    uint face_idx = (face.pos_face_tile >> 18u) & 7u;
    uint tile = (face.pos_face_tile >> 21u) & 2047u;
    vec2 extent = vec2(float(face.extent & 63u), float((face.extent >> 6u) & 63u));
    uint cutout_flags = (face.extent >> PACKED_FACE_EXTENT_FLAGS_SHIFT) & PACKED_FACE_EXTENT_FLAGS_MASK;
    int chunk_x = unpack_signed_i16(face.block_flags >> 16u);
    int chunk_z = unpack_signed_i16(face.extent >> 16u);
    int sub_y = unpack_signed_i16(face.pad);

    uint corner_idx = TRIANGLE_CORNER_INDICES[uint(gl_VertexIndex) % 6u];
    vec3 local_pos = vec3(float(x), float(y), float(z)) + face_corner(face_idx, corner_idx, extent);
    vec3 world_pos = local_pos + vec3(float(chunk_x * 32), float(sub_y * 32), float(chunk_z * 32));

    gl_Position = terrain_push.clip_from_world * vec4(world_pos, 1.0);
    uv_out = face_uv(face_idx, corner_idx, extent);
    tile_offset_out = atlas_tile_offset(tile);
    lighting_out = face_lighting(face_idx);
    cutout_flags_out = cutout_flags;
}

// -- FRAGMENT --
#version 450

layout(set = 0, binding = 1) uniform sampler2D atlas_texture;
layout(push_constant, std430) uniform TerrainPushConstants {
    mat4 clip_from_world;
    vec4 light_direction_ambient;
    vec4 light_color_energy;
    vec4 atlas_layout;
} terrain_push;

layout(location = 0) in vec2 uv_in;
layout(location = 1) flat in vec2 tile_offset_in;
layout(location = 2) flat in vec3 lighting_in;
layout(location = 3) flat in uint cutout_flags_in;
layout(location = 0) out vec4 frag_color;

const uint PACKED_FACE_CUTOUT_ALPHA_TEST = 1u;
const float CUTOUT_ALPHA_THRESHOLD = 0.5;

vec2 atlas_uv(vec2 tile_uv, vec2 tile_offset) {
    vec2 tiled_uv = fract(tile_uv);
    return (tile_offset + tiled_uv) * terrain_push.atlas_layout.xy;
}

void main() {
    vec2 atlas_uv_in = atlas_uv(uv_in, tile_offset_in);
    vec4 texel = texture(atlas_texture, atlas_uv_in);
    if ((cutout_flags_in & PACKED_FACE_CUTOUT_ALPHA_TEST) != 0u && texel.a < CUTOUT_ALPHA_THRESHOLD) {
        discard;
    }
    frag_color = vec4(texel.rgb * lighting_in, 1.0);
}
