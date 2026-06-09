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
        let mut rd = rs.get_rendering_device()?;

        let shader_code = include_str!("../../shaders/mesher.glsl");
        
        let mut shader_source = RdShaderSource::new_gd();
        shader_source.set_language(ShaderLanguage::GLSL);
        shader_source.set_stage_source(ShaderStage::COMPUTE, shader_code);

        let spirv = rd.shader_compile_spirv_from_source(&shader_source)?;
        
        let shader_rid = rd.shader_create_from_spirv(&spirv);
        let pipeline = rd.compute_pipeline_create(shader_rid.clone());

        Some(Self {
            rd,
            shader_rid,
            pipeline,
        })
    }

    pub fn mesh_chunk(&mut self, voxel_data: &[u8]) -> Option<PackedVector3Array> {
        godot_print!("ComputeMesher: received chunk of {} bytes, GPU dispatch stubbed.", voxel_data.len());
        
        let vertices = PackedVector3Array::new();
        Some(vertices)
    }
}
