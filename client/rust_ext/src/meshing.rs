use crate::blocks;
use godot::classes::rendering_device::{ShaderLanguage, ShaderStage};
use godot::classes::{RdShaderSource, RenderingDevice, RenderingServer};
use godot::prelude::*;
use std::time::Instant;

const MAX_OUTPUT_VERTICES: usize = 100_000;
const LOG_MESH_DISPATCH: bool = false;
const BLOCK_SEMANTICS_PLACEHOLDER: &str = "/* RUMPELMC_BLOCK_SEMANTICS */";

#[derive(Clone, Copy, Default)]
pub struct MeshTiming {
    pub prepare_ms: f64,
    pub submit_ms: f64,
    pub sync_ms: f64,
    pub readback_ms: f64,
    pub parse_ms: f64,
}

pub struct MeshResult {
    pub vertices: PackedVector3Array,
    pub normals: PackedVector3Array,
    pub uvs: PackedVector2Array,
    pub timing: MeshTiming,
    pub reported_vertex_count: usize,
}

pub struct ComputeMesher {
    rd: Gd<RenderingDevice>,
    shader_rid: Rid,
    pipeline: Rid,
}

impl ComputeMesher {
    pub fn new() -> Option<Self> {
        let rs = RenderingServer::singleton();
        let mut rd = match rs.create_local_rendering_device() {
            Some(device) => device,
            None => {
                godot_print!("Error: create_local_rendering_device returned None");
                return None;
            }
        };

        let shader_code = compute_mesher_shader_code();

        let mut shader_source = RdShaderSource::new_gd();
        shader_source.set_language(ShaderLanguage::GLSL);
        shader_source.set_stage_source(ShaderStage::COMPUTE, shader_code.as_str());

        let spirv = match rd.shader_compile_spirv_from_source(&shader_source) {
            Some(s) => {
                let err_str = s.get_stage_compile_error(ShaderStage::COMPUTE).to_string();
                if !err_str.is_empty() {
                    godot_print!("Spirv compiler message: {}", err_str);
                }
                s
            }
            None => {
                godot_print!("shader_compile_spirv_from_source returned None");
                return None;
            }
        };

        let shader_rid = rd.shader_create_from_spirv(&spirv);
        let pipeline = rd.compute_pipeline_create(shader_rid);

        Some(Self {
            rd,
            shader_rid,
            pipeline,
        })
    }

    pub fn mesh_chunk(&mut self, voxel_data: &[u8]) -> Option<MeshResult> {
        if LOG_MESH_DISPATCH {
            godot_print!(
                "ComputeMesher: received chunk of {} bytes, starting GPU dispatch.",
                voxel_data.len()
            );
        }

        let prepare_start = Instant::now();
        let mut gpu_voxels = Vec::with_capacity(voxel_data.len() * 2);
        for chunk in voxel_data.chunks_exact(2) {
            let block_id = u16::from_le_bytes([chunk[0], chunk[1]]);
            gpu_voxels.extend_from_slice(&(block_id as u32).to_le_bytes());
        }
        let voxel_pba = PackedByteArray::from(gpu_voxels.as_slice());

        let out_data = vec![0u8; 3_200_004]; // ~100k vertices
        let out_pba = PackedByteArray::from(out_data.as_slice());

        let voxel_buffer_rid = self.rd.storage_buffer_create(voxel_pba.len() as u32);
        self.rd
            .buffer_update(voxel_buffer_rid, 0, voxel_pba.len() as u32, &voxel_pba);

        let out_buffer_rid = self.rd.storage_buffer_create(out_pba.len() as u32);
        self.rd
            .buffer_update(out_buffer_rid, 0, out_pba.len() as u32, &out_pba);

        let mut uniform_voxels = godot::classes::RdUniform::new_gd();
        uniform_voxels
            .set_uniform_type(godot::classes::rendering_device::UniformType::STORAGE_BUFFER);
        uniform_voxels.set_binding(0);
        uniform_voxels.add_id(voxel_buffer_rid);

        let mut uniform_out = godot::classes::RdUniform::new_gd();
        uniform_out.set_uniform_type(godot::classes::rendering_device::UniformType::STORAGE_BUFFER);
        uniform_out.set_binding(1);
        uniform_out.add_id(out_buffer_rid);

        let uniforms = Array::from_iter([uniform_voxels, uniform_out]);
        let uniform_set = self.rd.uniform_set_create(&uniforms, self.shader_rid, 0);
        let prepare_ms = prepare_start.elapsed().as_secs_f64() * 1000.0;

        let submit_start = Instant::now();
        let compute_list = self.rd.compute_list_begin();
        self.rd
            .compute_list_bind_compute_pipeline(compute_list, self.pipeline);
        self.rd
            .compute_list_bind_uniform_set(compute_list, uniform_set, 0);
        self.rd.compute_list_dispatch(compute_list, 4, 4, 4); // 32x32x32 / (8,8,8)
        self.rd.compute_list_end();

        self.rd.submit();
        let submit_ms = submit_start.elapsed().as_secs_f64() * 1000.0;

        let sync_start = Instant::now();
        self.rd.sync();
        let sync_ms = sync_start.elapsed().as_secs_f64() * 1000.0;

        let readback_start = Instant::now();
        let out_bytes = self.rd.buffer_get_data(out_buffer_rid);
        let out_slice = out_bytes.as_slice();
        let readback_ms = readback_start.elapsed().as_secs_f64() * 1000.0;

        self.rd.free_rid(uniform_set);
        self.rd.free_rid(voxel_buffer_rid);
        self.rd.free_rid(out_buffer_rid);

        if out_slice.len() >= 4 {
            let reported_vertex_count =
                u32::from_le_bytes([out_slice[0], out_slice[1], out_slice[2], out_slice[3]])
                    as usize;
            let vertex_count = reported_vertex_count.min(MAX_OUTPUT_VERTICES);
            if LOG_MESH_DISPATCH {
                godot_print!(
                    "Compute Shader generated {} vertices (reading {}).",
                    reported_vertex_count,
                    vertex_count
                );
            }

            let mut vertices = PackedVector3Array::new();
            let mut normals = PackedVector3Array::new();
            let mut uvs = PackedVector2Array::new();
            let parse_start = Instant::now();
            for i in 0..vertex_count {
                let offset = 4 + i * 32;
                if offset + 32 > out_slice.len() {
                    break;
                }

                let x = f32::from_le_bytes([
                    out_slice[offset],
                    out_slice[offset + 1],
                    out_slice[offset + 2],
                    out_slice[offset + 3],
                ]);
                let y = f32::from_le_bytes([
                    out_slice[offset + 4],
                    out_slice[offset + 5],
                    out_slice[offset + 6],
                    out_slice[offset + 7],
                ]);
                let z = f32::from_le_bytes([
                    out_slice[offset + 8],
                    out_slice[offset + 9],
                    out_slice[offset + 10],
                    out_slice[offset + 11],
                ]);

                let nx = f32::from_le_bytes([
                    out_slice[offset + 12],
                    out_slice[offset + 13],
                    out_slice[offset + 14],
                    out_slice[offset + 15],
                ]);
                let ny = f32::from_le_bytes([
                    out_slice[offset + 16],
                    out_slice[offset + 17],
                    out_slice[offset + 18],
                    out_slice[offset + 19],
                ]);
                let nz = f32::from_le_bytes([
                    out_slice[offset + 20],
                    out_slice[offset + 21],
                    out_slice[offset + 22],
                    out_slice[offset + 23],
                ]);
                let u = f32::from_le_bytes([
                    out_slice[offset + 24],
                    out_slice[offset + 25],
                    out_slice[offset + 26],
                    out_slice[offset + 27],
                ]);
                let v = f32::from_le_bytes([
                    out_slice[offset + 28],
                    out_slice[offset + 29],
                    out_slice[offset + 30],
                    out_slice[offset + 31],
                ]);

                vertices.push(Vector3::new(x, y, z));
                normals.push(Vector3::new(nx, ny, nz));
                uvs.push(Vector2::new(u, v));
            }
            let parse_ms = parse_start.elapsed().as_secs_f64() * 1000.0;
            Some(MeshResult {
                vertices,
                normals,
                uvs,
                timing: MeshTiming {
                    prepare_ms,
                    submit_ms,
                    sync_ms,
                    readback_ms,
                    parse_ms,
                },
                reported_vertex_count,
            })
        } else {
            None
        }
    }
}

fn compute_mesher_shader_code() -> String {
    include_str!("../../shaders/mesher.glsl").replace(
        BLOCK_SEMANTICS_PLACEHOLDER,
        &blocks::compute_mesher_glsl_block_semantics(),
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn compute_mesher_shader_embeds_block_semantics_from_rust_definitions() {
        let shader = compute_mesher_shader_code();

        assert!(!shader.contains(BLOCK_SEMANTICS_PLACEHOLDER));
        for snippet in [
            "uint texture_tile(uint block_id, uint face_idx)",
            "if (block_id == 3u) {",
            "if (face_idx == FACE_TOP) return 0u;",
            "if (face_idx == FACE_BOTTOM) return 2u;",
            "bool is_solid(uint block_id)",
            "block_id == 5u",
        ] {
            assert!(shader.contains(snippet));
        }
        for stale_constant in ["const uint BLOCK_GRASS", "const uint TILE_GRASS_TOP"] {
            assert!(!shader.contains(stale_constant));
        }
    }
}
