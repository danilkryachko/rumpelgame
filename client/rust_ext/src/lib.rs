use godot::prelude::*;

mod api;
mod network;
mod meshing;

struct RumpelmcExtension;

#[gdextension]
unsafe impl ExtensionLibrary for RumpelmcExtension {}

#[derive(GodotClass)]
#[class(base=Node)]
pub struct GameClient {
    base: Base<Node>,
    mesher: Option<meshing::ComputeMesher>,
}

#[godot_api]
impl INode for GameClient {
    fn init(base: Base<Node>) -> Self {
        Self { 
            base,
            mesher: None,
        }
    }

    fn ready(&mut self) {
        godot_print!("GameClient ready! Initializing ComputeMesher...");
        self.mesher = meshing::ComputeMesher::new();
        if self.mesher.is_none() {
            godot_print!("Failed to initialize ComputeMesher!");
        } else {
            godot_print!("ComputeMesher initialized successfully.");
        }

        godot_print!("Connecting to server...");
        
        match network::NetworkClient::connect("127.0.0.1:25565") {
            Ok(mut client) => {
                godot_print!("Connected to server successfully!");
                match client.receive_packet() {
                    Ok(packet) => {
                        if let Some(crate::api::api::packet::Payload::Chunk(chunk)) = packet.payload {
                            godot_print!("Received Chunk! X: {}, Z: {}, Blocks length: {}", chunk.x, chunk.z, chunk.blocks.len());
                            if let Some(mesher) = &mut self.mesher {
                                if let Some(vertices) = mesher.mesh_chunk(&chunk.blocks) {
                                    godot_print!("Meshing complete! Generated {} vertices.", vertices.len());
                                    
                                    if vertices.len() > 0 {
                                        // 1. Create Array for ArrayMesh
                                        let mut arrays = Array::new();
                                        arrays.resize(14, &Variant::nil()); // ArrayType::MAX = 14
                                        arrays.set(0, &vertices.to_variant()); // ArrayType::VERTEX = 0
                                        
                                        // 2. Construct ArrayMesh
                                        let mut array_mesh = godot::classes::ArrayMesh::new_gd();
                                        array_mesh.add_surface_from_arrays(godot::classes::mesh::PrimitiveType::TRIANGLES, &arrays);
                                        
                                        // 3. Create MeshInstance3D and add to scene
                                        let mut mesh_instance = godot::classes::MeshInstance3D::new_alloc();
                                        mesh_instance.set_mesh(&array_mesh.upcast::<godot::classes::Mesh>());
                                        self.base_mut().add_child(&mesh_instance.upcast::<godot::classes::Node>());
                                        
                                        // 4. Create Camera3D so we can see it
                                        let mut camera = godot::classes::Camera3D::new_alloc();
                                        camera.set_position(Vector3::new(16.0, 80.0, 60.0));
                                        camera.look_at(Vector3::new(16.0, 64.0, 16.0));
                                        self.base_mut().add_child(&camera.upcast::<godot::classes::Node>());
                                        
                                        godot_print!("Chunk rendered and Camera added!");
                                    }
                                }
                            }
                        }
                    }
                    Err(e) => {
                        godot_print!("Failed to receive packet: {}", e);
                    }
                }
            }
            Err(e) => {
                godot_print!("Failed to connect to server: {}", e);
            }
        }
    }
}
