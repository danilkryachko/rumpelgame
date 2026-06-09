use godot::prelude::*;
use godot::classes::{RenderingServer, RenderingDevice, RdShaderSource};
use godot::classes::rendering_device::{ShaderLanguage, ShaderStage};

pub struct ComputeMesher {
    rd: Gd<RenderingDevice>,
    shader_rid: Rid,
    pipeline: Rid,
}

impl ComputeMesher {
    pub fn new() -> Option<Self> {
        let mut rs = RenderingServer::singleton();
        let mut rd = match rs.create_local_rendering_device() {
            Some(device) => device,
            None => { godot_print!("Error: create_local_rendering_device returned None"); return None; }
        };

        let shader_code = include_str!("../../shaders/mesher.glsl");
        
        let mut shader_source = RdShaderSource::new_gd();
        shader_source.set_language(ShaderLanguage::GLSL);
        shader_source.set_stage_source(ShaderStage::COMPUTE, shader_code);

        let spirv = match rd.shader_compile_spirv_from_source(&shader_source) {
            Some(s) => {
                let err_str = s.get_stage_compile_error(ShaderStage::COMPUTE);
                if err_str.to_string() != "" {
                    godot_print!("Spirv compiler message: {}", err_str);
                }
                s
            },
            None => {
                godot_print!("shader_compile_spirv_from_source returned None");
                return None;
            }
        };
        
        let shader_rid = rd.shader_create_from_spirv(&spirv);
        let pipeline = rd.compute_pipeline_create(shader_rid.clone());

        Some(Self {
            rd,
            shader_rid,
            pipeline,
        })
    }

    pub fn mesh_chunk(&mut self, voxel_data: &[u8]) -> Option<PackedVector3Array> {
        godot_print!("ComputeMesher: received chunk of {} bytes, starting GPU dispatch.", voxel_data.len());
        
        let mut gpu_voxels = Vec::with_capacity(voxel_data.len() * 2);
        for chunk in voxel_data.chunks_exact(2) {
            let block_id = u16::from_le_bytes([chunk[0], chunk[1]]);
            gpu_voxels.extend_from_slice(&(block_id as u32).to_le_bytes());
        }
        let voxel_pba = PackedByteArray::from(gpu_voxels.as_slice());

        let out_data = vec![0u8; 3_200_004]; // ~100k vertices
        let out_pba = PackedByteArray::from(out_data.as_slice());

        let voxel_buffer_rid = self.rd.storage_buffer_create(voxel_pba.len() as u32);
        self.rd.buffer_update(voxel_buffer_rid.clone(), 0, voxel_pba.len() as u32, &voxel_pba);

        let out_buffer_rid = self.rd.storage_buffer_create(out_pba.len() as u32);
        self.rd.buffer_update(out_buffer_rid.clone(), 0, out_pba.len() as u32, &out_pba);

        let mut uniform_voxels = godot::classes::RdUniform::new_gd();
        uniform_voxels.set_uniform_type(godot::classes::rendering_device::UniformType::STORAGE_BUFFER);
        uniform_voxels.set_binding(0);
        uniform_voxels.add_id(voxel_buffer_rid.clone());

        let mut uniform_out = godot::classes::RdUniform::new_gd();
        uniform_out.set_uniform_type(godot::classes::rendering_device::UniformType::STORAGE_BUFFER);
        uniform_out.set_binding(1);
        uniform_out.add_id(out_buffer_rid.clone());

        let uniforms = Array::from_iter([uniform_voxels, uniform_out]);
        let uniform_set = self.rd.uniform_set_create(&uniforms, self.shader_rid.clone(), 0);

        let compute_list = self.rd.compute_list_begin();
        self.rd.compute_list_bind_compute_pipeline(compute_list, self.pipeline.clone());
        self.rd.compute_list_bind_uniform_set(compute_list, uniform_set.clone(), 0);
        self.rd.compute_list_dispatch(compute_list, 4, 64, 4); // 32x512x32 / (8,8,8)
        self.rd.compute_list_end();

        self.rd.submit();
        self.rd.sync();

        let out_bytes = self.rd.buffer_get_data(out_buffer_rid.clone());
        let out_slice = out_bytes.as_slice();

        self.rd.free_rid(voxel_buffer_rid);
        self.rd.free_rid(out_buffer_rid);

        if out_slice.len() >= 4 {
            let vertex_count = u32::from_le_bytes([out_slice[0], out_slice[1], out_slice[2], out_slice[3]]) as usize;
            godot_print!("Compute Shader generated {} vertices.", vertex_count);

            let mut vertices = PackedVector3Array::new();
            for i in 0..vertex_count {
                let offset = 4 + i * 32; 
                if offset + 12 > out_slice.len() { break; } 
                
                let x = f32::from_le_bytes([out_slice[offset+0], out_slice[offset+1], out_slice[offset+2], out_slice[offset+3]]);
                let y = f32::from_le_bytes([out_slice[offset+4], out_slice[offset+5], out_slice[offset+6], out_slice[offset+7]]);
                let z = f32::from_le_bytes([out_slice[offset+8], out_slice[offset+9], out_slice[offset+10], out_slice[offset+11]]);
                
                vertices.push(Vector3::new(x, y, z));
            }
            Some(vertices)
        } else {
            None
        }
    }
}
