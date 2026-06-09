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
