use godot::prelude::*;

mod api;
mod network;
mod meshing;
mod player;

struct RumpelmcExtension;

#[gdextension]
unsafe impl ExtensionLibrary for RumpelmcExtension {}

use std::sync::mpsc::{Receiver, channel};

#[derive(GodotClass)]
#[class(base=Node)]
pub struct GameClient {
    base: Base<Node>,
    mesher: Option<meshing::ComputeMesher>,
    network: Option<network::NetworkClient>,
    packet_receiver: Option<Receiver<crate::api::api::Packet>>,
}

#[godot_api]
impl INode for GameClient {
    fn init(base: Base<Node>) -> Self {
        Self { 
            base,
            mesher: None,
            network: None,
            packet_receiver: None,
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
            Ok(client) => {
                godot_print!("Connected to server successfully!");
                
                let stream_clone = client.try_clone_stream().expect("Failed to clone TCP stream");
                let mut reader_client = network::NetworkClient { stream: stream_clone };
                
                let (tx, rx) = channel();
                self.packet_receiver = Some(rx);
                self.network = Some(client);
                
                std::thread::spawn(move || {
                    loop {
                        match reader_client.receive_packet() {
                            Ok(packet) => {
                                if tx.send(packet).is_err() { break; }
                            }
                            Err(e) => {
                                println!("Network reader thread error: {}", e);
                                break;
                            }
                        }
                    }
                });
            }
            Err(e) => {
                godot_print!("Failed to connect to server: {}", e);
            }
        }
        
        // 4. Create Player instead of static camera
        let mut player = crate::player::Player::new_alloc();
        // Подключаем сигнал
        let callable = self.base().callable(&StringName::from("on_block_broken"));
        player.connect(&StringName::from("block_broken"), &callable);
        
        let callable_placed = self.base().callable(&StringName::from("on_block_placed"));
        player.connect(&StringName::from("block_placed"), &callable_placed);
        
        let mut player_node = player.upcast::<godot::classes::Node3D>();
        player_node.set_position(Vector3::new(16.0, 80.0, 16.0));
        
        self.base_mut().add_child(&player_node.upcast::<godot::classes::Node>());
    }

    fn process(&mut self, _delta: f64) {
        let mut packets = Vec::new();
        if let Some(rx) = &self.packet_receiver {
            while let Ok(packet) = rx.try_recv() {
                packets.push(packet);
            }
        }
        for packet in packets {
            if let Some(crate::api::api::packet::Payload::Chunk(chunk)) = packet.payload {
                self.update_chunk(chunk);
            }
        }
    }
}

impl GameClient {
    fn update_chunk(&mut self, chunk: crate::api::api::ChunkData) {
        godot_print!("Received/Updated Chunk! X: {}, Z: {}, Blocks length: {}", chunk.x, chunk.z, chunk.blocks.len());
        if let Some(mesher) = &mut self.mesher {
            if let Some((vertices, normals)) = mesher.mesh_chunk(&chunk.blocks) {
                godot_print!("Meshing complete! Generated {} vertices.", vertices.len());
                
                if vertices.len() > 0 {
                    let mut arrays = Array::new();
                    arrays.resize(13, &Variant::nil());
                    arrays.set(0, &vertices.to_variant());
                    arrays.set(1, &normals.to_variant());
                    
                    let mut array_mesh = godot::classes::ArrayMesh::new_gd();
                    array_mesh.add_surface_from_arrays(godot::classes::mesh::PrimitiveType::TRIANGLES, &arrays);
                    
                    // Check if MeshInstance3D already exists
                    if let Some(mut mesh_instance) = self.base().try_get_node_as::<godot::classes::MeshInstance3D>("ChunkMesh") {
                        mesh_instance.set_mesh(&array_mesh.upcast::<godot::classes::Mesh>());
                        
                        let mut material = godot::classes::StandardMaterial3D::new_gd();
                        material.set_cull_mode(godot::classes::base_material_3d::CullMode::DISABLED);
                        material.set_albedo(Color::from_rgb(0.5, 0.8, 0.3)); // Трава
                        mesh_instance.set_material_override(&material.upcast::<godot::classes::Material>());
                        
                        // Удаляем старую коллизию, если она есть
                        if let Some(mut old_col) = mesh_instance.try_get_node_as::<godot::classes::StaticBody3D>("ChunkMesh_col") {
                            mesh_instance.remove_child(&old_col.upcast::<godot::classes::Node>());
                        }
                        mesh_instance.create_trimesh_collision();
                    } else {
                        // Create MeshInstance3D
                        let mut mesh_instance = godot::classes::MeshInstance3D::new_alloc();
                        mesh_instance.set_name(&StringName::from("ChunkMesh"));
                        mesh_instance.set_mesh(&array_mesh.upcast::<godot::classes::Mesh>());
                        // Create material to disable culling
                        let mut material = godot::classes::StandardMaterial3D::new_gd();
                        material.set_cull_mode(godot::classes::base_material_3d::CullMode::DISABLED);
                        material.set_albedo(Color::from_rgb(0.5, 0.8, 0.3)); // Трава
                        mesh_instance.set_material_override(&material.upcast::<godot::classes::Material>());
                        
                        mesh_instance.create_trimesh_collision();
                        self.base_mut().add_child(&mesh_instance.upcast::<godot::classes::Node>());
                    }
                }
            }
        }
    }
}

#[godot_api]
impl GameClient {
    #[func]
    fn on_block_broken(&mut self, x: i32, y: i32, z: i32) {
        godot_print!("Network sending BlockAction DESTROY: {}, {}, {}", x, y, z);
        
        let packet = crate::api::api::Packet {
            payload: Some(crate::api::api::packet::Payload::BlockAction(crate::api::api::BlockAction {
                action: crate::api::api::block_action::ActionType::Destroy as i32,
                x, y, z,
                block_id: 0,
            })),
        };
        
        if let Some(network) = &mut self.network {
            if let Err(e) = network.send_packet(&packet) {
                godot_print!("Failed to send BlockAction: {}", e);
            }
        }
    }

    #[func]
    fn on_block_placed(&mut self, x: i32, y: i32, z: i32, block_id: i32) {
        godot_print!("Network sending BlockAction PLACE: {}, {}, {} ID: {}", x, y, z, block_id);
        
        let packet = crate::api::api::Packet {
            payload: Some(crate::api::api::packet::Payload::BlockAction(crate::api::api::BlockAction {
                action: crate::api::api::block_action::ActionType::Place as i32,
                x, y, z,
                block_id: block_id as u32,
            })),
        };
        
        if let Some(network) = &mut self.network {
            if let Err(e) = network.send_packet(&packet) {
                godot_print!("Failed to send BlockAction: {}", e);
            }
        }
    }
}
