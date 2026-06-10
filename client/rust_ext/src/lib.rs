use godot::prelude::*;
use std::collections::{HashMap, HashSet, VecDeque};
use std::ops::Range;
use std::time::Instant;

mod api;
mod blocks;
mod gpu_terrain;
mod meshing;
mod network;
mod player;

struct RumpelmcExtension;

#[gdextension]
unsafe impl ExtensionLibrary for RumpelmcExtension {}

use std::sync::{
    OnceLock,
    mpsc::{Receiver, channel},
};

#[derive(GodotClass)]
#[class(base=Node)]
pub struct GameClient {
    base: Base<Node>,
    mesher: Option<meshing::ComputeMesher>,
    gpu_terrain: Option<gpu_terrain::GpuTerrainBufferPool>,
    gpu_terrain_compositor: Option<gpu_terrain::GpuTerrainCompositor>,
    gpu_visible_transition_applied: bool,
    network: Option<network::NetworkClient>,
    packet_receiver: Option<Receiver<crate::api::Packet>>,
    player_spawned: bool,
    texture_debug_stand_visible: bool,
    chunk_material: Option<Gd<godot::classes::Material>>,
    chunk_blocks: HashMap<(i32, i32), Vec<u8>>,
    mesh_queue: VecDeque<SubchunkKey>,
    queued_subchunks: HashSet<SubchunkKey>,
    position_send_timer: f64,
    current_player_chunk: Option<(i32, i32)>,
    last_block_action: String,
    last_chunk_event: String,
    last_save_event: String,
    perf: PerfStats,
}

#[godot_api]
impl INode for GameClient {
    fn init(base: Base<Node>) -> Self {
        Self {
            base,
            mesher: None,
            gpu_terrain: None,
            gpu_terrain_compositor: None,
            gpu_visible_transition_applied: false,
            network: None,
            packet_receiver: None,
            player_spawned: false,
            texture_debug_stand_visible: false,
            chunk_material: None,
            chunk_blocks: HashMap::new(),
            mesh_queue: VecDeque::new(),
            queued_subchunks: HashSet::new(),
            position_send_timer: 0.0,
            current_player_chunk: None,
            last_block_action: "n/a".to_string(),
            last_chunk_event: "n/a".to_string(),
            last_save_event: "n/a".to_string(),
            perf: PerfStats::default(),
        }
    }

    fn ready(&mut self) {
        self.emit_debug_log("GameClient ready; initializing ComputeMesher");
        self.mesher = meshing::ComputeMesher::new();
        if self.mesher.is_none() {
            self.emit_debug_log("Failed to initialize ComputeMesher");
        } else {
            self.emit_debug_log("ComputeMesher initialized successfully");
        }

        let gpu_terrain_render = gpu_terrain_render_enabled();
        if gpu_terrain_upload_enabled() {
            self.gpu_terrain = gpu_terrain::GpuTerrainBufferPool::new(gpu_terrain_render);
            if self.gpu_terrain.is_some() {
                self.emit_debug_log(&format!(
                    "GPU terrain buffer pool initialized; debug_render={gpu_terrain_render}"
                ));
            } else {
                self.emit_debug_log(
                    "GPU terrain buffer pool unavailable; using ArrayMesh fallback",
                );
            }
        }
        if gpu_terrain_render && self.gpu_terrain.is_some() {
            let callback = self
                .base()
                .callable(&StringName::from("on_gpu_terrain_compositor"));
            self.gpu_terrain_compositor = gpu_terrain::GpuTerrainCompositor::new(&callback);
            if self.gpu_terrain_compositor.is_some() {
                self.emit_debug_log("GPU terrain compositor initialized");
            } else {
                self.emit_debug_log("GPU terrain compositor unavailable");
            }
        }

        self.emit_debug_log("Connecting to server");

        match network::NetworkClient::connect("127.0.0.1:25565") {
            Ok(client) => {
                self.emit_debug_log("Connected to server successfully");

                let stream_clone = client
                    .try_clone_stream()
                    .expect("Failed to clone TCP stream");
                let mut reader_client = network::NetworkClient {
                    stream: stream_clone,
                };

                let (tx, rx) = channel();
                self.packet_receiver = Some(rx);
                self.network = Some(client);

                std::thread::spawn(move || {
                    loop {
                        match reader_client.receive_packet() {
                            Ok(packet) => {
                                if tx.send(packet).is_err() {
                                    break;
                                }
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
                self.emit_debug_log(&format!("Failed to connect to server: {e}"));
            }
        }

        self.emit_debug_log("Waiting for first chunk before spawning player");
    }

    fn process(&mut self, delta: f64) {
        self.position_send_timer -= delta;
        if self.position_send_timer <= 0.0 {
            self.position_send_timer = 0.5;
            self.update_player_position_state();
        }

        let mut packets = Vec::new();
        if let Some(rx) = &self.packet_receiver {
            while let Ok(packet) = rx.try_recv() {
                packets.push(packet);
            }
        }
        for packet in packets {
            if let Some(crate::api::packet::Payload::Chunk(chunk)) = packet.payload {
                self.update_chunk(chunk);
            }
        }
        self.process_mesh_queue();
        self.sync_gpu_terrain_lighting();
        self.update_gpu_visible_transition();
        if gpu_terrain_render_enabled()
            && let Some(gpu_terrain) = &mut self.gpu_terrain
        {
            gpu_terrain.render_debug_offscreen_once();
        }
    }
}

impl GameClient {
    fn spawn_player(&mut self) {
        if self.player_spawned {
            return;
        }

        let mut player = crate::player::Player::new_alloc();

        let callable = self.base().callable(&StringName::from("on_block_broken"));
        player.connect(&StringName::from("block_broken"), &callable);

        let callable_placed = self.base().callable(&StringName::from("on_block_placed"));
        player.connect(&StringName::from("block_placed"), &callable_placed);

        let callable_log = self
            .base()
            .callable(&StringName::from("on_player_debug_log"));
        player.connect(&StringName::from("debug_log"), &callable_log);

        let mut player_node = player.upcast::<godot::classes::Node3D>();
        player_node.set_name(&StringName::from("Player"));
        player_node.set_position(Vector3::new(16.0, 68.0, 16.0));

        self.base_mut()
            .add_child(&player_node.upcast::<godot::classes::Node>());

        self.player_spawned = true;
        self.emit_debug_log("Player spawned after chunk collision was created");
        self.attach_gpu_terrain_compositor_to_player_camera();
    }

    fn update_chunk(&mut self, chunk: crate::api::ChunkData) {
        let chunk_x = chunk.x;
        let chunk_z = chunk.z;
        self.emit_debug_log(&format!(
            "Chunk received x={} z={} blocks={}",
            chunk_x,
            chunk_z,
            chunk.blocks.len()
        ));
        self.last_chunk_event = format!("received {chunk_x},{chunk_z}");
        self.last_save_event = format!("chunk {chunk_x},{chunk_z} updated");

        self.chunk_blocks.insert((chunk_x, chunk_z), chunk.blocks);
        self.perf.chunk_bytes_loaded = self.total_chunk_bytes_loaded();
        self.enqueue_chunk_subchunks(chunk_x, chunk_z);

        for (x, z) in chunk_neighbors(chunk_x, chunk_z) {
            if self.chunk_blocks.contains_key(&(x, z)) {
                self.enqueue_chunk_subchunks(x, z);
            }
        }

        if let Some(center) = self.current_player_chunk {
            self.unload_far_chunks(center);
        }

        if chunk_x == 0 && chunk_z == 0 {
            let spawn_lower = SubchunkKey {
                chunk_x: 0,
                sub_y: 0,
                chunk_z: 0,
            };
            let spawn_upper = SubchunkKey {
                chunk_x: 0,
                sub_y: 1,
                chunk_z: 0,
            };
            self.queued_subchunks.remove(&spawn_lower);
            self.queued_subchunks.remove(&spawn_upper);
            self.render_subchunk_mesh(spawn_lower);
            self.render_subchunk_mesh(spawn_upper);
            self.spawn_player();
        }
    }

    fn process_mesh_queue(&mut self) {
        let mut processed = 0;
        let mut drained = 0;
        while processed < MAX_MESH_JOBS_PER_FRAME && drained < MAX_MESH_QUEUE_DRAINS_PER_FRAME {
            let Some(key) = self.mesh_queue.pop_front() else {
                break;
            };
            drained += 1;
            if !self.queued_subchunks.remove(&key) {
                continue;
            }

            if !self.chunk_blocks.contains_key(&(key.chunk_x, key.chunk_z)) {
                continue;
            }
            self.render_subchunk_mesh(key);
            processed += 1;
        }
        self.perf.mesh_queue_depth = self.mesh_queue.len();
    }

    fn enqueue_chunk_subchunks(&mut self, chunk_x: i32, chunk_z: i32) {
        for sub_y in 0..SUBCHUNKS_PER_CHUNK {
            if self.subchunk_has_blocks(chunk_x, sub_y, chunk_z) {
                self.enqueue_subchunk(SubchunkKey {
                    chunk_x,
                    sub_y,
                    chunk_z,
                });
            } else {
                self.remove_subchunk_mesh(SubchunkKey {
                    chunk_x,
                    sub_y,
                    chunk_z,
                });
            }
        }
    }

    fn enqueue_subchunk(&mut self, key: SubchunkKey) {
        if self.queued_subchunks.insert(key) {
            self.mesh_queue.push_back(key);
        }
        self.perf.mesh_queue_depth = self.mesh_queue.len();
    }

    fn render_subchunk_mesh(&mut self, key: SubchunkKey) {
        let build_start = Instant::now();
        let Some(padded_blocks) = self.build_padded_subchunk_blocks(key) else {
            return;
        };
        let needs_gpu_faces = gpu_terrain_stats_enabled() || gpu_terrain_upload_enabled();
        let packed_faces = needs_gpu_faces.then(|| gpu_terrain::build_packed_faces(&padded_blocks));
        if gpu_terrain_stats_enabled()
            && let Some(packed_faces) = &packed_faces
        {
            godot_print!(
                "GPU terrain prototype {}: faces={} bytes={}",
                subchunk_mesh_name(key),
                packed_faces.face_count(),
                packed_faces.byte_len()
            );
        }
        let mut gpu_upload_state = TerrainGpuUploadState::for_request(gpu_terrain_upload_enabled());
        if gpu_terrain_upload_enabled()
            && let (Some(gpu_terrain), Some(packed_faces)) = (&mut self.gpu_terrain, &packed_faces)
        {
            gpu_upload_state = TerrainGpuUploadState::from_upload_result(
                gpu_terrain
                    .upload_subchunk(gpu_subchunk_key(key), packed_faces)
                    .is_some(),
            );
        }

        let needs_cpu_proxy = self.subchunk_needs_cpu_proxy(key);
        let gpu_visible_render_active = self.gpu_terrain_visible_render_active();
        let mesh_build_plan = terrain_mesh_build_plan(
            gpu_upload_state,
            gpu_visible_render_active,
            needs_cpu_proxy,
            packed_faces.is_some(),
        );
        if mesh_build_plan == TerrainMeshBuildPlan::RemoveCpuNode {
            self.remove_cpu_subchunk_mesh_node(key);
            return;
        }

        let should_have_collision = self.subchunk_needs_collision(key);
        let should_have_shadow_proxy =
            gpu_visible_render_active && self.subchunk_needs_shadow_proxy(key);
        let cpu_proxy_mesh = mesh_build_plan == TerrainMeshBuildPlan::CpuProxyMesh;
        let cpu_proxy_mesh_payload = terrain_cpu_proxy_mesh_payload(
            gpu_terrain_shadow_proxy_mesh_mode(),
            cpu_proxy_mesh,
            should_have_collision,
            should_have_shadow_proxy,
        );
        let (vertices, normals, uvs, timing, reported_vertices): (
            PackedVector3Array,
            PackedVector3Array,
            PackedVector2Array,
            meshing::MeshTiming,
            usize,
        ) = if cpu_proxy_mesh {
            let packed_faces = packed_faces
                .as_ref()
                .expect("packed faces are built for uploaded GPU terrain");
            let proxy_mesh = if cpu_proxy_mesh_payload.uses_compact_mesh() {
                packed_faces.build_compact_cpu_proxy_mesh()
            } else {
                packed_faces.build_cpu_proxy_mesh()
            };
            let reported_vertices = proxy_mesh.vertices.len();
            (
                proxy_mesh.vertices,
                proxy_mesh.normals,
                PackedVector2Array::new(),
                meshing::MeshTiming::default(),
                reported_vertices,
            )
        } else {
            let Some(mesher) = &mut self.mesher else {
                return;
            };
            let Some(mesh_result) = mesher.mesh_chunk(&padded_blocks) else {
                return;
            };
            (
                mesh_result.vertices,
                mesh_result.normals,
                mesh_result.uvs,
                mesh_result.timing,
                mesh_result.reported_vertex_count,
            )
        };

        if vertices.is_empty() {
            self.remove_subchunk_mesh(key);
            return;
        }
        let mesh_ms = build_start.elapsed().as_secs_f64() * 1000.0;

        let mut arrays = Array::new();
        arrays.resize(13, &Variant::nil());
        arrays.set(0, &vertices.to_variant());
        if !normals.is_empty() {
            arrays.set(1, &normals.to_variant());
        }
        if !uvs.is_empty() {
            arrays.set(4, &uvs.to_variant());
        }

        let mut array_mesh = godot::classes::ArrayMesh::new_gd();
        array_mesh.add_surface_from_arrays(godot::classes::mesh::PrimitiveType::TRIANGLES, &arrays);

        let mesh_name = subchunk_mesh_name(key);
        let chunk_position = Vector3::new(
            key.chunk_x as f32 * CHUNK_SIZE,
            key.sub_y as f32 * SUBCHUNK_SIZE,
            key.chunk_z as f32 * CHUNK_SIZE,
        );
        let collision_start = Instant::now();
        let collision_bodies;

        if let Some(mut mesh_instance) = self
            .base()
            .try_get_node_as::<godot::classes::MeshInstance3D>(&mesh_name)
        {
            mesh_instance.set_mesh(&array_mesh.upcast::<godot::classes::Mesh>());
            mesh_instance.set_position(chunk_position);
            configure_terrain_mesh_render_mode(
                &mut mesh_instance,
                cpu_proxy_mesh,
                should_have_shadow_proxy,
            );

            let material = self.get_chunk_material();
            mesh_instance.set_material_override(&material);

            clear_mesh_collisions(&mut mesh_instance);
            if should_have_collision {
                mesh_instance.create_trimesh_collision();
            }
            collision_bodies = count_static_body_children(&mesh_instance);
        } else {
            let mut mesh_instance = godot::classes::MeshInstance3D::new_alloc();
            mesh_instance.set_name(&StringName::from(&mesh_name));
            mesh_instance.set_position(chunk_position);
            mesh_instance.set_mesh(&array_mesh.upcast::<godot::classes::Mesh>());
            configure_terrain_mesh_render_mode(
                &mut mesh_instance,
                cpu_proxy_mesh,
                should_have_shadow_proxy,
            );

            let material = self.get_chunk_material();
            mesh_instance.set_material_override(&material);

            let mesh_node = mesh_instance.clone().upcast::<godot::classes::Node>();
            self.base_mut().add_child(&mesh_node);
            if should_have_collision {
                mesh_instance.create_trimesh_collision();
            }
            collision_bodies = count_static_body_children(&mesh_instance);
        }

        let collision_ms = collision_start.elapsed().as_secs_f64() * 1000.0;
        let node_counts = self.current_node_perf_counts();
        self.perf.record_mesh(MeshRecord {
            vertices: vertices.len(),
            normals: normals.len(),
            reported_vertices,
            cpu_proxy_mesh,
            compact_shadow_proxy_mesh: cpu_proxy_mesh_payload.compact_shadow_proxy_mesh,
            compact_collision_proxy_mesh: cpu_proxy_mesh_payload.compact_collision_proxy_mesh,
            mesh_ms,
            timing,
            collision_ms,
            collision_bodies,
            node_counts,
        });
    }

    fn emit_debug_log(&mut self, message: &str) {
        godot_print!("{}", message);
        self.base_mut()
            .emit_signal(&StringName::from("debug_log"), &[message.to_variant()]);
    }

    fn ensure_texture_debug_stand(&mut self) -> Gd<godot::classes::MeshInstance3D> {
        if let Some(stand) = self
            .base()
            .try_get_node_as::<godot::classes::MeshInstance3D>("TextureDebugStand")
        {
            return stand;
        }

        let mut stand = godot::classes::MeshInstance3D::new_alloc();
        stand.set_name(&StringName::from("TextureDebugStand"));
        stand.set_mesh(&create_texture_debug_stand_mesh().upcast::<godot::classes::Mesh>());
        let material = self.get_chunk_material();
        stand.set_material_override(&material);
        stand.set_visible(false);

        let node = stand.clone().upcast::<godot::classes::Node>();
        self.base_mut().add_child(&node);
        stand
    }

    fn texture_debug_stand_position(&self) -> Vector3 {
        if let Some(player) = self
            .base()
            .try_get_node_as::<godot::classes::Node3D>("Player")
        {
            return player.get_global_position() + Vector3::new(3.0, 0.0, -5.0);
        }

        Vector3::new(19.0, 68.0, 11.0)
    }

    fn get_chunk_material(&mut self) -> Gd<godot::classes::Material> {
        if let Some(material) = &self.chunk_material {
            return material.clone();
        }

        let material = create_chunk_material().upcast::<godot::classes::Material>();
        self.chunk_material = Some(material.clone());
        material
    }

    fn send_packet_to_server(&mut self, packet: &crate::api::Packet) {
        let Some(network) = &mut self.network else {
            return;
        };

        if let Err(e) = network.send_packet(packet) {
            godot_print!("Failed to send BlockAction: {}", e);
        }
    }

    fn update_player_position_state(&mut self) {
        let Some(player) = self
            .base()
            .try_get_node_as::<godot::classes::Node3D>("Player")
        else {
            return;
        };

        let pos = player.get_global_position();
        let chunk = chunk_coord_for_position(pos.x, pos.z);
        let previous_chunk = self.current_player_chunk;
        if previous_chunk != Some(chunk) {
            self.current_player_chunk = Some(chunk);
            self.last_chunk_event = format!("player chunk {},{}", chunk.0, chunk.1);
            self.emit_debug_log(&format!("Player entered chunk {},{}", chunk.0, chunk.1));
            self.enqueue_collision_refresh(previous_chunk, chunk);
            self.enqueue_cpu_proxy_refresh(previous_chunk, chunk);
        }

        let packet = crate::api::Packet {
            payload: Some(crate::api::packet::Payload::Position(
                crate::api::ClientPosition {
                    x: pos.x,
                    y: pos.y,
                    z: pos.z,
                },
            )),
        };
        self.send_packet_to_server(&packet);
        self.unload_far_chunks(chunk);
    }

    fn build_padded_subchunk_blocks(&self, key: SubchunkKey) -> Option<Vec<u8>> {
        let mut padded = vec![0u8; PADDED_BLOCK_BYTES];
        let center = self.chunk_blocks.get(&(key.chunk_x, key.chunk_z))?;
        let y_start = key.sub_y as usize * SUBCHUNK_H;
        let y_end = y_start + SUBCHUNK_H;

        copy_chunk_region(
            center,
            &mut padded,
            ChunkRegion::new(0..32, y_start..y_end, 0..32),
            (1, 1, 1),
        );

        if y_start > 0 {
            copy_chunk_region(
                center,
                &mut padded,
                ChunkRegion::new(0..32, y_start - 1..y_start, 0..32),
                (1, 0, 1),
            );
        }
        if y_end < CHUNK_H {
            copy_chunk_region(
                center,
                &mut padded,
                ChunkRegion::new(0..32, y_end..y_end + 1, 0..32),
                (1, 33, 1),
            );
        }

        if let Some(west) = self.chunk_blocks.get(&(key.chunk_x - 1, key.chunk_z)) {
            copy_chunk_region(
                west,
                &mut padded,
                ChunkRegion::new(31..32, y_start..y_end, 0..32),
                (0, 1, 1),
            );
        }
        if let Some(east) = self.chunk_blocks.get(&(key.chunk_x + 1, key.chunk_z)) {
            copy_chunk_region(
                east,
                &mut padded,
                ChunkRegion::new(0..1, y_start..y_end, 0..32),
                (33, 1, 1),
            );
        }
        if let Some(back) = self.chunk_blocks.get(&(key.chunk_x, key.chunk_z - 1)) {
            copy_chunk_region(
                back,
                &mut padded,
                ChunkRegion::new(0..32, y_start..y_end, 31..32),
                (1, 1, 0),
            );
        }
        if let Some(front) = self.chunk_blocks.get(&(key.chunk_x, key.chunk_z + 1)) {
            copy_chunk_region(
                front,
                &mut padded,
                ChunkRegion::new(0..32, y_start..y_end, 0..1),
                (1, 1, 33),
            );
        }

        Some(padded)
    }

    fn subchunk_has_blocks(&self, chunk_x: i32, sub_y: i32, chunk_z: i32) -> bool {
        let Some(blocks) = self.chunk_blocks.get(&(chunk_x, chunk_z)) else {
            return false;
        };
        let y_start = sub_y as usize * SUBCHUNK_H;
        let y_end = (y_start + SUBCHUNK_H).min(CHUNK_H);
        for y in y_start..y_end {
            for z in 0..CHUNK_D {
                for x in 0..CHUNK_W {
                    let idx = chunk_byte_index(x, y, z);
                    if idx + BLOCK_BYTES <= blocks.len()
                        && u16::from_le_bytes([blocks[idx], blocks[idx + 1]]) != 0
                    {
                        return true;
                    }
                }
            }
        }
        false
    }

    fn subchunk_needs_collision(&self, key: SubchunkKey) -> bool {
        subchunk_needs_collision(key, self.current_player_chunk)
    }

    fn subchunk_needs_cpu_proxy(&self, key: SubchunkKey) -> bool {
        if !self.gpu_terrain_visible_render_active() {
            return subchunk_needs_cpu_proxy(false, false, false);
        }

        let needs_collision = self.subchunk_needs_collision(key);
        let needs_shadow_proxy = !needs_collision && self.subchunk_needs_shadow_proxy(key);
        subchunk_needs_cpu_proxy(true, needs_collision, needs_shadow_proxy)
    }

    fn subchunk_needs_shadow_proxy(&self, key: SubchunkKey) -> bool {
        let mode = gpu_terrain_shadow_proxy_mode();
        if !mode.keeps_shadow_proxies() {
            return false;
        }

        subchunk_needs_shadow_proxy(
            key,
            self.current_player_chunk,
            mode,
            self.terrain_shadow_proxy_chunk_distance(),
        )
    }

    fn terrain_shadow_proxy_chunk_distance(&self) -> i32 {
        terrain_shadow_proxy_chunk_distance(
            gpu_terrain_shadow_proxy_chunk_distance_override(),
            self.scene_directional_shadow_distance(),
        )
    }

    fn scene_directional_shadow_distance(&self) -> Option<f32> {
        let parent = self.base().get_parent()?;
        let sun = parent.try_get_node_as::<godot::classes::DirectionalLight3D>("SunLight")?;
        if !sun.has_shadow() {
            return Some(0.0);
        }

        Some(sun.get_param(godot::classes::light_3d::Param::SHADOW_MAX_DISTANCE))
    }

    fn total_chunk_bytes_loaded(&self) -> usize {
        self.chunk_blocks.values().map(Vec::len).sum()
    }

    fn enqueue_collision_refresh(&mut self, previous: Option<(i32, i32)>, current: (i32, i32)) {
        let loaded_chunks: Vec<(i32, i32)> = self.chunk_blocks.keys().copied().collect();
        for coord in loaded_chunks {
            let was_near = previous
                .is_some_and(|prev| chunk_within_radius(coord, prev, COLLISION_CHUNK_DISTANCE));
            let is_near = chunk_within_radius(coord, current, COLLISION_CHUNK_DISTANCE);
            if was_near || is_near {
                self.refresh_chunk_collisions(coord.0, coord.1);
            }
        }
    }

    fn enqueue_cpu_proxy_refresh(&mut self, previous: Option<(i32, i32)>, current: (i32, i32)) {
        if !gpu_terrain_render_enabled() {
            return;
        }

        let shadow_radius = if gpu_terrain_shadow_proxy_mode().keeps_shadow_proxies() {
            self.terrain_shadow_proxy_chunk_distance()
        } else {
            0
        };
        let loaded_chunks: Vec<(i32, i32)> = self.chunk_blocks.keys().copied().collect();
        for coord in loaded_chunks {
            if chunk_needs_cpu_proxy_refresh(coord, previous, current, shadow_radius) {
                self.enqueue_chunk_subchunks(coord.0, coord.1);
            }
        }
    }

    fn refresh_chunk_collisions(&mut self, chunk_x: i32, chunk_z: i32) {
        for sub_y in 0..SUBCHUNKS_PER_CHUNK {
            self.refresh_subchunk_collision(SubchunkKey {
                chunk_x,
                sub_y,
                chunk_z,
            });
        }
    }

    fn refresh_subchunk_collision(&mut self, key: SubchunkKey) {
        let mesh_name = subchunk_mesh_name(key);
        let Some(mut mesh_instance) = self
            .base()
            .try_get_node_as::<godot::classes::MeshInstance3D>(&mesh_name)
        else {
            return;
        };

        let needs_collision = self.subchunk_needs_collision(key);
        let has_collision = count_static_body_children(&mesh_instance) > 0;
        if needs_collision == has_collision {
            return;
        }

        let collision_start = Instant::now();
        clear_mesh_collisions(&mut mesh_instance);
        if needs_collision {
            mesh_instance.create_trimesh_collision();
        }
        self.perf.last_collision_ms = collision_start.elapsed().as_secs_f64() * 1000.0;
        self.perf.max_collision_ms = self.perf.max_collision_ms.max(self.perf.last_collision_ms);
        self.refresh_node_perf_counts();
    }

    fn unload_far_chunks(&mut self, center: (i32, i32)) {
        let to_unload: Vec<(i32, i32)> = self
            .chunk_blocks
            .keys()
            .copied()
            .filter(|coord| !chunk_within_radius(*coord, center, CLIENT_KEEP_CHUNK_DISTANCE))
            .collect();
        if to_unload.is_empty() {
            return;
        }

        let mut rerender = HashSet::new();
        for coord in to_unload {
            self.chunk_blocks.remove(&coord);
            self.remove_chunk_meshes(coord.0, coord.1);
            self.last_chunk_event = format!("unloaded {},{}", coord.0, coord.1);
            self.emit_debug_log(&format!("Chunk unloaded {},{}", coord.0, coord.1));

            for neighbor in chunk_neighbors(coord.0, coord.1) {
                if self.chunk_blocks.contains_key(&neighbor) {
                    rerender.insert(neighbor);
                }
            }
        }

        for (x, z) in rerender {
            self.enqueue_chunk_subchunks(x, z);
        }
    }

    fn remove_chunk_meshes(&mut self, chunk_x: i32, chunk_z: i32) {
        for sub_y in 0..SUBCHUNKS_PER_CHUNK {
            let key = SubchunkKey {
                chunk_x,
                sub_y,
                chunk_z,
            };
            self.queued_subchunks.remove(&key);
            self.remove_subchunk_mesh(key);
        }
    }

    fn remove_subchunk_mesh(&mut self, key: SubchunkKey) {
        if let Some(gpu_terrain) = &mut self.gpu_terrain {
            gpu_terrain.remove_subchunk(gpu_subchunk_key(key));
        }

        self.remove_cpu_subchunk_mesh_node(key);
    }

    fn remove_cpu_subchunk_mesh_node(&mut self, key: SubchunkKey) {
        let mesh_name = subchunk_mesh_name(key);
        let Some(mut mesh_node) = self
            .base()
            .try_get_node_as::<godot::classes::MeshInstance3D>(&mesh_name)
        else {
            return;
        };

        self.base_mut()
            .remove_child(&mesh_node.clone().upcast::<godot::classes::Node>());
        mesh_node.queue_free();
        self.refresh_node_perf_counts();
    }

    fn refresh_node_perf_counts(&mut self) {
        self.perf.node_counts = self.current_node_perf_counts();
    }

    fn current_node_perf_counts(&self) -> NodePerfCounts {
        let mut counts = NodePerfCounts::default();
        let gpu_visible = self.gpu_terrain_visible_render_active();
        for idx in 0..self.base().get_child_count() {
            let Some(child) = self.base().get_child(idx) else {
                continue;
            };
            let Some(key) = subchunk_key_from_mesh_name(&child.get_name().to_string()) else {
                continue;
            };
            counts.rendered_submeshes += 1;

            let needs_collision = self.subchunk_needs_collision(key);
            let needs_shadow = gpu_visible && self.subchunk_needs_shadow_proxy(key);
            counts.record_cpu_proxy_reasons(needs_collision, needs_shadow);

            let Ok(mesh_instance) = child.try_cast::<godot::classes::MeshInstance3D>() else {
                continue;
            };
            counts.record_mesh_render_state(&mesh_instance);
            counts.total_collision_bodies += count_static_body_children(&mesh_instance);
        }
        counts
    }

    fn attach_gpu_terrain_compositor_to_player_camera(&mut self) {
        if !gpu_terrain_render_enabled() {
            return;
        }
        let Some(camera_rid) = self.player_camera_rid() else {
            return;
        };
        let Some(compositor) = &mut self.gpu_terrain_compositor else {
            return;
        };
        if compositor.attach_to_camera(camera_rid) {
            self.emit_debug_log("GPU terrain compositor attached to player camera");
        }
    }

    fn sync_gpu_terrain_lighting(&mut self) {
        if !gpu_terrain_render_enabled() {
            return;
        }

        let Some(lighting) = self.gpu_terrain_lighting_from_scene() else {
            return;
        };
        let Some(gpu_terrain) = &mut self.gpu_terrain else {
            return;
        };

        gpu_terrain.set_lighting(lighting);
    }

    fn gpu_terrain_lighting_from_scene(&self) -> Option<gpu_terrain::GpuTerrainLighting> {
        let parent = self.base().get_parent()?;
        let sun = parent.try_get_node_as::<godot::classes::DirectionalLight3D>("SunLight")?;
        let transform = sun.get_global_transform();
        let direction_to_light = transform.basis.col_c();
        let color = sun.get_color();
        let energy = sun.get_param(godot::classes::light_3d::Param::ENERGY);

        Some(gpu_terrain::GpuTerrainLighting::directional(
            direction_to_light,
            color,
            energy,
        ))
    }

    fn current_terrain_shadow_path(&self) -> GpuTerrainShadowPath {
        let gpu_visible = self.gpu_terrain_visible_render_active();
        let mode = gpu_terrain_shadow_proxy_mode();
        let radius = if gpu_visible && mode.keeps_shadow_proxies() {
            self.terrain_shadow_proxy_chunk_distance()
        } else {
            0
        };
        terrain_shadow_path_decision(gpu_visible, mode, radius)
    }

    fn gpu_terrain_visible_render_active(&self) -> bool {
        gpu_terrain_visible_render_active_decision(
            gpu_terrain_render_enabled(),
            self.gpu_terrain_compositor
                .as_ref()
                .is_some_and(gpu_terrain::GpuTerrainCompositor::is_attached),
            self.gpu_terrain
                .as_ref()
                .is_some_and(gpu_terrain::GpuTerrainBufferPool::visible_render_confirmed),
        )
    }

    fn update_gpu_visible_transition(&mut self) {
        let active = self.gpu_terrain_visible_render_active();
        if active == self.gpu_visible_transition_applied {
            return;
        }

        self.gpu_visible_transition_applied = active;
        self.refresh_terrain_mesh_render_modes();
        if active {
            self.emit_debug_log("GPU terrain visible path confirmed");
            self.refresh_cpu_proxies_after_gpu_attach();
        }
    }

    fn refresh_terrain_mesh_render_modes(&mut self) {
        let gpu_visible_render_active = self.gpu_terrain_visible_render_active();
        for idx in 0..self.base().get_child_count() {
            let Some(child) = self.base().get_child(idx) else {
                continue;
            };
            let Some(key) = subchunk_key_from_mesh_name(&child.get_name().to_string()) else {
                continue;
            };
            let Ok(mut mesh_instance) = child.try_cast::<godot::classes::MeshInstance3D>() else {
                continue;
            };
            let gpu_upload_state = TerrainGpuUploadState::from_existing_slot(
                self.gpu_terrain
                    .as_ref()
                    .is_some_and(|gpu_terrain| gpu_terrain.has_subchunk(gpu_subchunk_key(key))),
            );
            let cpu_proxy_mesh =
                terrain_cpu_proxy_mesh_active(gpu_visible_render_active, gpu_upload_state);
            let needs_shadow_proxy = cpu_proxy_mesh && self.subchunk_needs_shadow_proxy(key);
            configure_terrain_mesh_render_mode(
                &mut mesh_instance,
                cpu_proxy_mesh,
                needs_shadow_proxy,
            );
        }
        self.refresh_node_perf_counts();
    }

    fn refresh_cpu_proxies_after_gpu_attach(&mut self) {
        let loaded_chunks = chunks_to_refresh_after_gpu_attach(
            self.chunk_blocks.keys().copied(),
            self.gpu_terrain_visible_render_active(),
        );
        for (chunk_x, chunk_z) in loaded_chunks {
            self.enqueue_chunk_subchunks(chunk_x, chunk_z);
        }
    }

    fn player_camera_rid(&self) -> Option<Rid> {
        let player = self
            .base()
            .try_get_node_as::<godot::classes::Node>("Player")?;
        for idx in 0..player.get_child_count() {
            let Some(child) = player.get_child(idx) else {
                continue;
            };
            let Ok(camera) = child.try_cast::<godot::classes::Camera3D>() else {
                continue;
            };
            return Some(camera.get_camera_rid());
        }
        None
    }
}

#[derive(Clone, Copy, PartialEq, Eq, Hash)]
struct SubchunkKey {
    chunk_x: i32,
    sub_y: i32,
    chunk_z: i32,
}

#[derive(Default)]
struct PerfStats {
    mesh_queue_depth: usize,
    mesh_jobs_completed: u64,
    last_mesh_ms: f64,
    avg_mesh_ms: f64,
    max_mesh_ms: f64,
    last_collision_ms: f64,
    avg_collision_ms: f64,
    max_collision_ms: f64,
    last_vertices: usize,
    last_normals: usize,
    last_reported_vertices: usize,
    total_vertices: usize,
    total_normals: usize,
    collision_bodies: i32,
    node_counts: NodePerfCounts,
    chunk_bytes_loaded: usize,
    last_prepare_ms: f64,
    last_submit_ms: f64,
    last_sync_ms: f64,
    last_readback_ms: f64,
    last_parse_ms: f64,
    cpu_proxy_meshes_built: u64,
    compact_shadow_proxy_meshes_built: u64,
    compact_shadow_proxy_normals_saved: usize,
    compact_collision_proxy_meshes_built: u64,
    compact_collision_proxy_normals_saved: usize,
}

struct MeshRecord {
    vertices: usize,
    normals: usize,
    reported_vertices: usize,
    cpu_proxy_mesh: bool,
    compact_shadow_proxy_mesh: bool,
    compact_collision_proxy_mesh: bool,
    mesh_ms: f64,
    timing: meshing::MeshTiming,
    collision_ms: f64,
    collision_bodies: i32,
    node_counts: NodePerfCounts,
}

#[derive(Clone, Copy, Default)]
struct NodePerfCounts {
    rendered_submeshes: i32,
    visible_submeshes: i32,
    shadow_off_submeshes: i32,
    shadow_double_sided_submeshes: i32,
    shadow_only_submeshes: i32,
    total_collision_bodies: i32,
    cpu_proxy_collision: i32,
    cpu_proxy_shadow: i32,
    cpu_proxy_both: i32,
    cpu_proxy_shadow_only: i32,
}

impl NodePerfCounts {
    fn record_cpu_proxy_reasons(&mut self, needs_collision: bool, needs_shadow: bool) {
        if needs_collision {
            self.cpu_proxy_collision += 1;
        }
        if needs_shadow {
            self.cpu_proxy_shadow += 1;
        }
        if needs_collision && needs_shadow {
            self.cpu_proxy_both += 1;
        } else if needs_shadow {
            self.cpu_proxy_shadow_only += 1;
        }
    }

    fn record_mesh_render_state(&mut self, mesh_instance: &Gd<godot::classes::MeshInstance3D>) {
        self.record_mesh_render_state_values(
            mesh_instance.is_visible(),
            mesh_instance.get_cast_shadows_setting(),
        );
    }

    fn record_mesh_render_state_values(
        &mut self,
        visible: bool,
        shadow_setting: godot::classes::geometry_instance_3d::ShadowCastingSetting,
    ) {
        if visible {
            self.visible_submeshes += 1;
        }

        match shadow_setting {
            godot::classes::geometry_instance_3d::ShadowCastingSetting::OFF => {
                self.shadow_off_submeshes += 1;
            }
            godot::classes::geometry_instance_3d::ShadowCastingSetting::DOUBLE_SIDED => {
                self.shadow_double_sided_submeshes += 1;
            }
            godot::classes::geometry_instance_3d::ShadowCastingSetting::SHADOWS_ONLY => {
                self.shadow_only_submeshes += 1;
            }
            _ => {}
        }
    }
}

impl PerfStats {
    fn record_mesh(&mut self, record: MeshRecord) {
        self.mesh_jobs_completed += 1;
        let n = self.mesh_jobs_completed as f64;
        self.last_mesh_ms = record.mesh_ms;
        self.avg_mesh_ms += (record.mesh_ms - self.avg_mesh_ms) / n;
        self.max_mesh_ms = self.max_mesh_ms.max(record.mesh_ms);
        self.last_collision_ms = record.collision_ms;
        self.avg_collision_ms += (record.collision_ms - self.avg_collision_ms) / n;
        self.max_collision_ms = self.max_collision_ms.max(record.collision_ms);
        self.last_vertices = record.vertices;
        self.last_normals = record.normals;
        self.last_reported_vertices = record.reported_vertices;
        self.total_vertices = self.total_vertices.saturating_add(record.vertices);
        self.total_normals = self.total_normals.saturating_add(record.normals);
        if record.cpu_proxy_mesh {
            self.cpu_proxy_meshes_built += 1;
        }
        if record.compact_shadow_proxy_mesh {
            self.compact_shadow_proxy_meshes_built += 1;
            self.compact_shadow_proxy_normals_saved = self
                .compact_shadow_proxy_normals_saved
                .saturating_add(record.vertices);
        }
        if record.compact_collision_proxy_mesh {
            self.compact_collision_proxy_meshes_built += 1;
            self.compact_collision_proxy_normals_saved = self
                .compact_collision_proxy_normals_saved
                .saturating_add(record.vertices);
        }
        self.collision_bodies = record.collision_bodies;
        self.node_counts = record.node_counts;
        self.last_prepare_ms = record.timing.prepare_ms;
        self.last_submit_ms = record.timing.submit_ms;
        self.last_sync_ms = record.timing.sync_ms;
        self.last_readback_ms = record.timing.readback_ms;
        self.last_parse_ms = record.timing.parse_ms;
    }
}

struct ChunkRegion {
    x: Range<usize>,
    y: Range<usize>,
    z: Range<usize>,
}

impl ChunkRegion {
    fn new(x: Range<usize>, y: Range<usize>, z: Range<usize>) -> Self {
        Self { x, y, z }
    }
}

const CHUNK_SIZE: f32 = 32.0;
const SUBCHUNK_SIZE: f32 = 32.0;
const CHUNK_W: usize = 32;
const CHUNK_H: usize = 512;
const CHUNK_D: usize = 32;
const SUBCHUNK_H: usize = 32;
const SUBCHUNKS_PER_CHUNK: i32 = (CHUNK_H / SUBCHUNK_H) as i32;
const PADDED_W: usize = 34;
const PADDED_H: usize = 34;
const PADDED_D: usize = 34;
const BLOCK_BYTES: usize = 2;
const PADDED_BLOCK_BYTES: usize = PADDED_W * PADDED_H * PADDED_D * BLOCK_BYTES;
const CLIENT_KEEP_CHUNK_DISTANCE: i32 = 10;
const COLLISION_CHUNK_DISTANCE: i32 = 1;
const DEFAULT_GPU_TERRAIN_SHADOW_PROXY_DISTANCE: f32 = 160.0;
const DEFAULT_GPU_TERRAIN_SHADOW_PROXY_CHUNK_DISTANCE: i32 = 5;
const MAX_MESH_JOBS_PER_FRAME: usize = 1;
const MAX_MESH_QUEUE_DRAINS_PER_FRAME: usize = 32;
const GPU_TERRAIN_PROTOTYPE_STATS: bool = false;
const GPU_TERRAIN_PROTOTYPE_UPLOAD: bool = false;
const GPU_TERRAIN_PROTOTYPE_RENDER: bool = false;
const GPU_TERRAIN_RENDER_DEFAULT_ENABLED: bool = false;
const GPU_TERRAIN_STATS_ENV: &str = "RUMPELMC_GPU_TERRAIN_STATS";
const GPU_TERRAIN_UPLOAD_ENV: &str = "RUMPELMC_GPU_TERRAIN_UPLOAD";
const GPU_TERRAIN_RENDER_ENV: &str = "RUMPELMC_GPU_TERRAIN_RENDER";
const GPU_TERRAIN_SHADOW_PROXY_CHUNK_DISTANCE_ENV: &str =
    "RUMPELMC_GPU_TERRAIN_SHADOW_PROXY_CHUNK_DISTANCE";
const GPU_TERRAIN_SHADOW_PROXY_MODE_ENV: &str = "RUMPELMC_GPU_TERRAIN_SHADOW_PROXY_MODE";
const GPU_TERRAIN_SHADOW_PROXY_MESH_ENV: &str = "RUMPELMC_GPU_TERRAIN_SHADOW_PROXY_MESH";
const FACE_LEFT: u32 = 0;
const FACE_RIGHT: u32 = 1;
const FACE_BOTTOM: u32 = 2;
const FACE_TOP: u32 = 3;
const FACE_BACK: u32 = 4;
const FACE_FRONT: u32 = 5;

fn subchunk_mesh_name(key: SubchunkKey) -> String {
    format!("SubchunkMesh_{}_{}_{}", key.chunk_x, key.sub_y, key.chunk_z)
}

fn subchunk_key_from_mesh_name(name: &str) -> Option<SubchunkKey> {
    let mut parts = name.strip_prefix("SubchunkMesh_")?.split('_');
    let chunk_x = parts.next()?.parse::<i32>().ok()?;
    let sub_y = parts.next()?.parse::<i32>().ok()?;
    let chunk_z = parts.next()?.parse::<i32>().ok()?;
    if parts.next().is_some() {
        return None;
    }

    Some(SubchunkKey {
        chunk_x,
        sub_y,
        chunk_z,
    })
}

fn gpu_subchunk_key(key: SubchunkKey) -> gpu_terrain::GpuSubchunkKey {
    gpu_terrain::GpuSubchunkKey {
        chunk_x: key.chunk_x,
        sub_y: key.sub_y,
        chunk_z: key.chunk_z,
    }
}

fn chunk_neighbors(x: i32, z: i32) -> [(i32, i32); 4] {
    [(x - 1, z), (x + 1, z), (x, z - 1), (x, z + 1)]
}

fn chunk_within_radius(a: (i32, i32), b: (i32, i32), radius: i32) -> bool {
    let dx = i64::from(a.0 - b.0);
    let dz = i64::from(a.1 - b.1);
    let radius = i64::from(radius);
    dx * dx + dz * dz <= radius * radius
}

fn subchunk_needs_collision(key: SubchunkKey, current_player_chunk: Option<(i32, i32)>) -> bool {
    let Some(center) = current_player_chunk else {
        return key.chunk_x == 0 && key.chunk_z == 0;
    };
    chunk_within_radius((key.chunk_x, key.chunk_z), center, COLLISION_CHUNK_DISTANCE)
}

fn subchunk_needs_shadow_proxy(
    key: SubchunkKey,
    current_player_chunk: Option<(i32, i32)>,
    mode: GpuTerrainShadowProxyMode,
    radius: i32,
) -> bool {
    if !mode.keeps_shadow_proxies() || radius <= 0 {
        return false;
    }

    let Some(center) = current_player_chunk else {
        return key.chunk_x == 0 && key.chunk_z == 0;
    };
    chunk_within_radius((key.chunk_x, key.chunk_z), center, radius)
}

fn subchunk_needs_cpu_proxy(
    gpu_visible_render_active: bool,
    needs_collision: bool,
    needs_shadow_proxy: bool,
) -> bool {
    !gpu_visible_render_active || needs_collision || needs_shadow_proxy
}

fn chunk_needs_cpu_proxy_refresh(
    coord: (i32, i32),
    previous: Option<(i32, i32)>,
    current: (i32, i32),
    shadow_radius: i32,
) -> bool {
    previous.is_some_and(|prev| chunk_has_cpu_proxy_reason(coord, prev, shadow_radius))
        || chunk_has_cpu_proxy_reason(coord, current, shadow_radius)
}

fn chunk_has_cpu_proxy_reason(coord: (i32, i32), center: (i32, i32), shadow_radius: i32) -> bool {
    chunk_within_radius(coord, center, COLLISION_CHUNK_DISTANCE)
        || (shadow_radius > 0 && chunk_within_radius(coord, center, shadow_radius))
}

fn chunks_to_refresh_after_gpu_attach(
    loaded_chunks: impl IntoIterator<Item = (i32, i32)>,
    gpu_visible_render_active: bool,
) -> Vec<(i32, i32)> {
    if !gpu_visible_render_active {
        return Vec::new();
    }

    loaded_chunks.into_iter().collect()
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum TerrainMeshBuildPlan {
    RemoveCpuNode,
    CpuProxyMesh,
    FullArrayMesh,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum TerrainGpuUploadState {
    NotRequested,
    Uploaded,
    Failed,
}

impl TerrainGpuUploadState {
    fn for_request(upload_enabled: bool) -> Self {
        if upload_enabled {
            Self::Failed
        } else {
            Self::NotRequested
        }
    }

    fn from_upload_result(uploaded: bool) -> Self {
        if uploaded {
            Self::Uploaded
        } else {
            Self::Failed
        }
    }

    fn from_existing_slot(has_slot: bool) -> Self {
        if has_slot {
            Self::Uploaded
        } else {
            Self::Failed
        }
    }

    fn has_confirmed_slot(self) -> bool {
        matches!(self, Self::Uploaded)
    }
}

fn terrain_mesh_build_plan(
    gpu_upload_state: TerrainGpuUploadState,
    gpu_visible_render_active: bool,
    needs_cpu_proxy: bool,
    has_packed_faces: bool,
) -> TerrainMeshBuildPlan {
    let cpu_proxy_mesh_active =
        terrain_cpu_proxy_mesh_active(gpu_visible_render_active, gpu_upload_state);
    if cpu_proxy_mesh_active && !needs_cpu_proxy {
        return TerrainMeshBuildPlan::RemoveCpuNode;
    }
    if cpu_proxy_mesh_active && has_packed_faces {
        return TerrainMeshBuildPlan::CpuProxyMesh;
    }

    TerrainMeshBuildPlan::FullArrayMesh
}

fn terrain_cpu_proxy_mesh_active(
    gpu_visible_render_active: bool,
    gpu_upload_state: TerrainGpuUploadState,
) -> bool {
    gpu_visible_render_active && gpu_upload_state.has_confirmed_slot()
}

fn gpu_terrain_stats_enabled() -> bool {
    static ENABLED: OnceLock<bool> = OnceLock::new();
    *ENABLED.get_or_init(|| GPU_TERRAIN_PROTOTYPE_STATS || env_flag_enabled(GPU_TERRAIN_STATS_ENV))
}

fn gpu_terrain_upload_enabled() -> bool {
    static ENABLED: OnceLock<bool> = OnceLock::new();
    *ENABLED.get_or_init(|| {
        gpu_terrain_upload_decision(
            env_flag_enabled(GPU_TERRAIN_UPLOAD_ENV),
            gpu_terrain_render_enabled(),
        )
    })
}

fn gpu_terrain_upload_decision(upload_env_enabled: bool, render_enabled: bool) -> bool {
    GPU_TERRAIN_PROTOTYPE_UPLOAD || upload_env_enabled || render_enabled
}

fn gpu_terrain_render_decision(env_state: Option<bool>) -> bool {
    GPU_TERRAIN_PROTOTYPE_RENDER || env_state.unwrap_or(GPU_TERRAIN_RENDER_DEFAULT_ENABLED)
}

fn gpu_terrain_render_enabled() -> bool {
    static ENABLED: OnceLock<bool> = OnceLock::new();
    *ENABLED.get_or_init(|| gpu_terrain_render_decision(env_flag_state(GPU_TERRAIN_RENDER_ENV)))
}

fn gpu_terrain_visible_render_active_decision(
    render_enabled: bool,
    compositor_attached: bool,
    visible_render_confirmed: bool,
) -> bool {
    render_enabled && compositor_attached && visible_render_confirmed
}

fn gpu_terrain_shadow_proxy_chunk_distance_override() -> Option<i32> {
    static OVERRIDE: OnceLock<Option<i32>> = OnceLock::new();
    *OVERRIDE.get_or_init(|| {
        std::env::var(GPU_TERRAIN_SHADOW_PROXY_CHUNK_DISTANCE_ENV)
            .ok()
            .and_then(|value| value.trim().parse::<i32>().ok())
    })
}

fn terrain_shadow_proxy_chunk_distance(
    override_radius: Option<i32>,
    scene_shadow_distance: Option<f32>,
) -> i32 {
    if let Some(radius) = override_radius {
        return radius.clamp(0, CLIENT_KEEP_CHUNK_DISTANCE);
    }

    let Some(shadow_distance) = scene_shadow_distance else {
        return shadow_distance_to_chunk_radius(DEFAULT_GPU_TERRAIN_SHADOW_PROXY_DISTANCE);
    };
    if !shadow_distance.is_finite() {
        return DEFAULT_GPU_TERRAIN_SHADOW_PROXY_CHUNK_DISTANCE;
    }
    if shadow_distance <= 0.0 {
        return 0;
    }

    shadow_distance_to_chunk_radius(shadow_distance)
}

fn shadow_distance_to_chunk_radius(shadow_distance: f32) -> i32 {
    ((shadow_distance / CHUNK_SIZE).ceil() as i32 + 1).clamp(0, CLIENT_KEEP_CHUNK_DISTANCE)
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum GpuTerrainShadowProxyMode {
    Conservative,
    CollisionOnly,
}

impl GpuTerrainShadowProxyMode {
    fn from_env_value(value: &str) -> Option<Self> {
        match value.trim().to_ascii_lowercase().as_str() {
            "" | "conservative" | "default" => Some(Self::Conservative),
            "collision_only" | "collision-only" | "collision" => Some(Self::CollisionOnly),
            _ => None,
        }
    }

    fn as_str(self) -> &'static str {
        match self {
            Self::Conservative => "conservative",
            Self::CollisionOnly => "collision_only",
        }
    }

    fn keeps_shadow_proxies(self) -> bool {
        matches!(self, Self::Conservative)
    }
}

fn gpu_terrain_shadow_proxy_mode() -> GpuTerrainShadowProxyMode {
    static MODE: OnceLock<GpuTerrainShadowProxyMode> = OnceLock::new();
    *MODE.get_or_init(|| {
        std::env::var(GPU_TERRAIN_SHADOW_PROXY_MODE_ENV)
            .ok()
            .and_then(|value| GpuTerrainShadowProxyMode::from_env_value(&value))
            .unwrap_or(GpuTerrainShadowProxyMode::Conservative)
    })
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum GpuTerrainShadowPath {
    ArrayMesh,
    GodotProxy,
    SceneShadowsDisabled,
    DiagnosticNoShadowProxy,
}

impl GpuTerrainShadowPath {
    fn as_str(self) -> &'static str {
        match self {
            Self::ArrayMesh => "arraymesh",
            Self::GodotProxy => "godot_proxy",
            Self::SceneShadowsDisabled => "scene_shadows_disabled",
            Self::DiagnosticNoShadowProxy => "diagnostic_no_shadow_proxy",
        }
    }
}

fn terrain_shadow_path_decision(
    gpu_visible_render_active: bool,
    mode: GpuTerrainShadowProxyMode,
    shadow_proxy_radius: i32,
) -> GpuTerrainShadowPath {
    if !gpu_visible_render_active {
        return GpuTerrainShadowPath::ArrayMesh;
    }
    if !mode.keeps_shadow_proxies() {
        return GpuTerrainShadowPath::DiagnosticNoShadowProxy;
    }
    if shadow_proxy_radius <= 0 {
        return GpuTerrainShadowPath::SceneShadowsDisabled;
    }

    GpuTerrainShadowPath::GodotProxy
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum GpuTerrainShadowProxyMeshMode {
    Full,
    Compact,
}

impl GpuTerrainShadowProxyMeshMode {
    fn from_env_value(value: &str) -> Option<Self> {
        match value.trim().to_ascii_lowercase().as_str() {
            "" | "compact" | "default" | "vertex_only" | "vertex-only" => Some(Self::Compact),
            "full" => Some(Self::Full),
            _ => None,
        }
    }

    fn as_str(self) -> &'static str {
        match self {
            Self::Full => "full",
            Self::Compact => "compact",
        }
    }

    fn compacts_shadow_only_mesh(
        self,
        cpu_proxy_mesh: bool,
        needs_collision: bool,
        needs_shadow_proxy: bool,
    ) -> bool {
        matches!(self, Self::Compact) && cpu_proxy_mesh && !needs_collision && needs_shadow_proxy
    }
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
struct TerrainCpuProxyMeshPayload {
    compact_shadow_proxy_mesh: bool,
    compact_collision_proxy_mesh: bool,
}

impl TerrainCpuProxyMeshPayload {
    fn uses_compact_mesh(self) -> bool {
        self.compact_shadow_proxy_mesh || self.compact_collision_proxy_mesh
    }
}

fn terrain_cpu_proxy_mesh_payload(
    shadow_mesh_mode: GpuTerrainShadowProxyMeshMode,
    cpu_proxy_mesh: bool,
    needs_collision: bool,
    needs_shadow_proxy: bool,
) -> TerrainCpuProxyMeshPayload {
    if !cpu_proxy_mesh {
        return TerrainCpuProxyMeshPayload::default();
    }

    TerrainCpuProxyMeshPayload {
        compact_shadow_proxy_mesh: shadow_mesh_mode.compacts_shadow_only_mesh(
            cpu_proxy_mesh,
            needs_collision,
            needs_shadow_proxy,
        ),
        compact_collision_proxy_mesh: needs_collision && !needs_shadow_proxy,
    }
}

fn gpu_terrain_shadow_proxy_mesh_mode() -> GpuTerrainShadowProxyMeshMode {
    static MODE: OnceLock<GpuTerrainShadowProxyMeshMode> = OnceLock::new();
    *MODE.get_or_init(|| {
        std::env::var(GPU_TERRAIN_SHADOW_PROXY_MESH_ENV)
            .ok()
            .and_then(|value| GpuTerrainShadowProxyMeshMode::from_env_value(&value))
            .unwrap_or(GpuTerrainShadowProxyMeshMode::Compact)
    })
}

fn flag_state_from_value(value: &str) -> Option<bool> {
    match value.trim().to_ascii_lowercase().as_str() {
        "1" | "true" | "yes" | "on" => Some(true),
        "0" | "false" | "no" | "off" => Some(false),
        _ => None,
    }
}

fn env_flag_state(name: &str) -> Option<bool> {
    std::env::var(name)
        .ok()
        .and_then(|value| flag_state_from_value(&value))
}

fn env_flag_enabled(name: &str) -> bool {
    env_flag_state(name) == Some(true)
}

fn chunk_coord_for_position(x: f32, z: f32) -> (i32, i32) {
    (
        (x.floor() as i32).div_euclid(CHUNK_W as i32),
        (z.floor() as i32).div_euclid(CHUNK_D as i32),
    )
}

fn copy_chunk_region(
    source: &[u8],
    padded: &mut [u8],
    source_region: ChunkRegion,
    padded_start: (usize, usize, usize),
) {
    let width = source_region.x.end - source_region.x.start;
    let height = source_region.y.end - source_region.y.start;
    let depth = source_region.z.end - source_region.z.start;
    for dy in 0..height {
        for dx in 0..width {
            for dz in 0..depth {
                let sx = source_region.x.start + dx;
                let sy = source_region.y.start + dy;
                let sz = source_region.z.start + dz;
                let px = padded_start.0 + dx;
                let py = padded_start.1 + dy;
                let pz = padded_start.2 + dz;

                let src = chunk_byte_index(sx, sy, sz);
                let dst = padded_byte_index(px, py, pz);
                if src + BLOCK_BYTES <= source.len() && dst + BLOCK_BYTES <= padded.len() {
                    padded[dst..dst + BLOCK_BYTES].copy_from_slice(&source[src..src + BLOCK_BYTES]);
                }
            }
        }
    }
}

fn chunk_byte_index(x: usize, y: usize, z: usize) -> usize {
    (x + y * CHUNK_W * CHUNK_D + z * CHUNK_W) * BLOCK_BYTES
}

fn padded_byte_index(x: usize, y: usize, z: usize) -> usize {
    (x + y * PADDED_W * PADDED_D + z * PADDED_W) * BLOCK_BYTES
}

fn create_texture_debug_stand_mesh() -> Gd<godot::classes::ArrayMesh> {
    let mut vertices = PackedVector3Array::new();
    let mut normals = PackedVector3Array::new();
    let mut uvs = PackedVector2Array::new();

    for (idx, block_id) in blocks::PLACEABLE_BLOCKS.into_iter().enumerate() {
        let base = Vector3::new(idx as f32 * 1.4, 0.0, 0.0);
        for face in [
            FACE_LEFT,
            FACE_RIGHT,
            FACE_BOTTOM,
            FACE_TOP,
            FACE_BACK,
            FACE_FRONT,
        ] {
            push_debug_face(base, block_id, face, &mut vertices, &mut normals, &mut uvs);
        }
    }

    let mut arrays = Array::new();
    arrays.resize(13, &Variant::nil());
    arrays.set(0, &vertices.to_variant());
    arrays.set(1, &normals.to_variant());
    arrays.set(4, &uvs.to_variant());

    let mut mesh = godot::classes::ArrayMesh::new_gd();
    mesh.add_surface_from_arrays(godot::classes::mesh::PrimitiveType::TRIANGLES, &arrays);
    mesh
}

fn push_debug_face(
    pos: Vector3,
    block_id: u32,
    face_idx: u32,
    vertices: &mut PackedVector3Array,
    normals: &mut PackedVector3Array,
    uvs: &mut PackedVector2Array,
) {
    let (p0, p1, p2, p3, normal) = match face_idx {
        FACE_LEFT => (
            pos + Vector3::new(0.0, 0.0, 1.0),
            pos + Vector3::new(0.0, 1.0, 1.0),
            pos + Vector3::new(0.0, 1.0, 0.0),
            pos + Vector3::new(0.0, 0.0, 0.0),
            Vector3::new(-1.0, 0.0, 0.0),
        ),
        FACE_RIGHT => (
            pos + Vector3::new(1.0, 0.0, 0.0),
            pos + Vector3::new(1.0, 1.0, 0.0),
            pos + Vector3::new(1.0, 1.0, 1.0),
            pos + Vector3::new(1.0, 0.0, 1.0),
            Vector3::new(1.0, 0.0, 0.0),
        ),
        FACE_BOTTOM => (
            pos + Vector3::new(0.0, 0.0, 1.0),
            pos + Vector3::new(0.0, 0.0, 0.0),
            pos + Vector3::new(1.0, 0.0, 0.0),
            pos + Vector3::new(1.0, 0.0, 1.0),
            Vector3::new(0.0, -1.0, 0.0),
        ),
        FACE_TOP => (
            pos + Vector3::new(0.0, 1.0, 0.0),
            pos + Vector3::new(0.0, 1.0, 1.0),
            pos + Vector3::new(1.0, 1.0, 1.0),
            pos + Vector3::new(1.0, 1.0, 0.0),
            Vector3::new(0.0, 1.0, 0.0),
        ),
        FACE_BACK => (
            pos + Vector3::new(1.0, 0.0, 0.0),
            pos + Vector3::new(0.0, 0.0, 0.0),
            pos + Vector3::new(0.0, 1.0, 0.0),
            pos + Vector3::new(1.0, 1.0, 0.0),
            Vector3::new(0.0, 0.0, -1.0),
        ),
        _ => (
            pos + Vector3::new(0.0, 0.0, 1.0),
            pos + Vector3::new(1.0, 0.0, 1.0),
            pos + Vector3::new(1.0, 1.0, 1.0),
            pos + Vector3::new(0.0, 1.0, 1.0),
            Vector3::new(0.0, 0.0, 1.0),
        ),
    };

    let (uv0, uv1, uv2, uv3) = face_uvs(face_idx);
    let tile = texture_tile(block_id, face_idx);
    for (point, uv) in [
        (p0, uv0),
        (p2, uv2),
        (p1, uv1),
        (p0, uv0),
        (p3, uv3),
        (p2, uv2),
    ] {
        vertices.push(point);
        normals.push(normal);
        uvs.push(atlas_uv(uv, tile));
    }
}

fn face_uvs(face_idx: u32) -> (Vector2, Vector2, Vector2, Vector2) {
    match face_idx {
        FACE_LEFT | FACE_RIGHT => (
            Vector2::new(0.0, 1.0),
            Vector2::new(0.0, 0.0),
            Vector2::new(1.0, 0.0),
            Vector2::new(1.0, 1.0),
        ),
        FACE_BACK => (
            Vector2::new(1.0, 1.0),
            Vector2::new(0.0, 1.0),
            Vector2::new(0.0, 0.0),
            Vector2::new(1.0, 0.0),
        ),
        FACE_FRONT => (
            Vector2::new(0.0, 1.0),
            Vector2::new(1.0, 1.0),
            Vector2::new(1.0, 0.0),
            Vector2::new(0.0, 0.0),
        ),
        _ => (
            Vector2::new(0.0, 0.0),
            Vector2::new(0.0, 1.0),
            Vector2::new(1.0, 1.0),
            Vector2::new(1.0, 0.0),
        ),
    }
}

fn texture_tile(block_id: u32, face_idx: u32) -> u32 {
    blocks::tile_for_face(block_id, face_idx, FACE_TOP, FACE_BOTTOM)
}

fn atlas_uv(tile_uv: Vector2, tile_index: u32) -> Vector2 {
    let (u, v) = blocks::texture_atlas_uv((tile_uv.x, tile_uv.y), tile_index);
    Vector2::new(u, v)
}

fn create_chunk_material() -> Gd<godot::classes::StandardMaterial3D> {
    let mut material = godot::classes::StandardMaterial3D::new_gd();
    material.set_cull_mode(godot::classes::base_material_3d::CullMode::DISABLED);
    material.set_albedo(Color::WHITE);
    material.set_shading_mode(godot::classes::base_material_3d::ShadingMode::UNSHADED);
    material.set_specular_mode(godot::classes::base_material_3d::SpecularMode::DISABLED);
    material.set_specular(0.0);
    material.set_roughness(1.0);
    material.set_flag(godot::classes::base_material_3d::Flags::DISABLE_FOG, true);
    material.set_flag(
        godot::classes::base_material_3d::Flags::DISABLE_AMBIENT_LIGHT,
        true,
    );
    material.set_texture_filter(godot::classes::base_material_3d::TextureFilter::NEAREST);
    material.set_transparency(godot::classes::base_material_3d::Transparency::DISABLED);
    material.set_depth_draw_mode(godot::classes::base_material_3d::DepthDrawMode::OPAQUE_ONLY);

    let mut loader = godot::classes::ResourceLoader::singleton();
    if let Some(resource) = loader.load("res://assets/textures/blocks/block_texture_atlas.png")
        && let Ok(texture) = resource.try_cast::<godot::classes::Texture2D>()
    {
        material.set_texture(
            godot::classes::base_material_3d::TextureParam::ALBEDO,
            &texture,
        );
    }

    material
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum TerrainMeshRenderMode {
    VisibleDoubleSided,
    ShadowsOnly,
    CollisionOnly,
}

impl TerrainMeshRenderMode {
    fn from_proxy_state(cpu_proxy_mesh: bool, needs_shadow_proxy: bool) -> Self {
        if !cpu_proxy_mesh {
            return Self::VisibleDoubleSided;
        }
        if needs_shadow_proxy {
            Self::ShadowsOnly
        } else {
            Self::CollisionOnly
        }
    }

    fn is_visible(self) -> bool {
        !matches!(self, Self::CollisionOnly)
    }

    fn shadow_setting(self) -> godot::classes::geometry_instance_3d::ShadowCastingSetting {
        match self {
            Self::VisibleDoubleSided => {
                godot::classes::geometry_instance_3d::ShadowCastingSetting::DOUBLE_SIDED
            }
            Self::ShadowsOnly => {
                godot::classes::geometry_instance_3d::ShadowCastingSetting::SHADOWS_ONLY
            }
            Self::CollisionOnly => godot::classes::geometry_instance_3d::ShadowCastingSetting::OFF,
        }
    }
}

fn configure_terrain_mesh_render_mode(
    mesh_instance: &mut Gd<godot::classes::MeshInstance3D>,
    cpu_proxy_mesh: bool,
    needs_shadow_proxy: bool,
) {
    let mode = TerrainMeshRenderMode::from_proxy_state(cpu_proxy_mesh, needs_shadow_proxy);
    mesh_instance.set_visible(mode.is_visible());
    mesh_instance.set_cast_shadows_setting(mode.shadow_setting());
}

fn clear_mesh_collisions(mesh_instance: &mut Gd<godot::classes::MeshInstance3D>) {
    for idx in (0..mesh_instance.get_child_count()).rev() {
        let Some(mut child) = mesh_instance.get_child(idx) else {
            continue;
        };
        if child
            .clone()
            .try_cast::<godot::classes::StaticBody3D>()
            .is_ok()
        {
            mesh_instance.remove_child(&child);
            child.queue_free();
        }
    }
}

fn count_static_body_children(mesh_instance: &Gd<godot::classes::MeshInstance3D>) -> i32 {
    let mut count = 0;
    for idx in 0..mesh_instance.get_child_count() {
        let Some(child) = mesh_instance.get_child(idx) else {
            continue;
        };
        if child.try_cast::<godot::classes::StaticBody3D>().is_ok() {
            count += 1;
        }
    }
    count
}

#[godot_api]
impl GameClient {
    #[func]
    fn toggle_texture_debug_stand(&mut self) {
        self.texture_debug_stand_visible = !self.texture_debug_stand_visible;
        let position = self.texture_debug_stand_position();
        let mut stand = self.ensure_texture_debug_stand();
        stand.set_position(position);
        stand.set_visible(self.texture_debug_stand_visible);

        let state = if self.texture_debug_stand_visible {
            "shown"
        } else {
            "hidden"
        };
        self.emit_debug_log(&format!("Texture debug stand {state}"));
    }

    #[func]
    fn is_texture_debug_stand_visible(&self) -> bool {
        self.texture_debug_stand_visible
    }

    #[func]
    fn get_loaded_chunk_count(&self) -> i32 {
        self.chunk_blocks.len() as i32
    }

    #[func]
    fn get_rendered_chunk_count(&self) -> i32 {
        self.perf.node_counts.rendered_submeshes
    }

    #[func]
    fn get_chunk_collision_count(&self) -> i32 {
        self.perf.node_counts.total_collision_bodies
    }

    #[func]
    fn get_current_chunk_text(&self) -> GString {
        let text = self
            .current_player_chunk
            .map(|(x, z)| format!("{x},{z}"))
            .unwrap_or_else(|| "n/a".to_string());
        GString::from(text.as_str())
    }

    #[func]
    fn get_last_chunk_event_text(&self) -> GString {
        GString::from(self.last_chunk_event.as_str())
    }

    #[func]
    fn get_last_block_action_text(&self) -> GString {
        GString::from(self.last_block_action.as_str())
    }

    #[func]
    fn get_last_save_text(&self) -> GString {
        GString::from(self.last_save_event.as_str())
    }

    #[func]
    fn get_perf_text(&self) -> GString {
        let shadow_path = self.current_terrain_shadow_path();
        let gpu_terrain_text = self
            .gpu_terrain
            .as_ref()
            .map(|pool| {
                let stats = pool.stats();
                format!(
                    " gpu_subchunks={} gpu_draws={} gpu_faces={} gpu_frames={} gpu_mem={:.1}MB gpu_uploads={} gpu_upload_fail={} gpu_upload_fail_capacity={} gpu_upload_fail_fragmented={} gpu_upload_mb={:.2} gpu_last_upload_kb={:.1} gpu_free_ranges={} gpu_free_faces={} gpu_largest_free={} gpu_draw_rebuilds={} gpu_draw_rebuild_ms={:.3}/{:.3}/{:.3} gpu_draw_patches={} gpu_draw_patch_ms={:.3}/{:.3}/{:.3}",
                    stats.subchunks,
                    stats.draw_count,
                    stats.faces,
                    stats.compositor_frames,
                    stats.bytes as f64 / (1024.0 * 1024.0),
                    stats.upload_count,
                    stats.upload_failures,
                    stats.upload_capacity_failures,
                    stats.upload_fragmentation_failures,
                    stats.upload_bytes as f64 / (1024.0 * 1024.0),
                    stats.last_upload_bytes as f64 / 1024.0,
                    stats.free_ranges,
                    stats.free_faces,
                    stats.largest_free_faces,
                    stats.draw_rebuild_count,
                    stats.last_draw_rebuild_ms,
                    stats.avg_draw_rebuild_ms,
                    stats.max_draw_rebuild_ms,
                    stats.draw_patch_count,
                    stats.last_draw_patch_ms,
                    stats.avg_draw_patch_ms,
                    stats.max_draw_patch_ms
                )
            })
            .unwrap_or_default();
        let text = format!(
            "queue={} jobs={} cpu_proxy={} mesh_visible={} mesh_shadow_off={} mesh_shadow_double={} mesh_shadow_only={} proxy_coll={} proxy_shadow={} proxy_both={} proxy_shadow_only={} shadow_path={} shadow_mode={} shadow_mesh={} compact_shadow_proxy={} compact_shadow_normals_saved={} compact_collision_proxy={} compact_collision_normals_saved={} fast_proxy={} collision={} mesh {:.2}/{:.2}/{:.2}ms gpu prep/sub/sync/read/parse {:.2}/{:.2}/{:.2}/{:.2}/{:.2}ms coll {:.2}/{:.2}/{:.2}ms verts last={}/{} total={} normals last={} total={} mem={:.1}MB{}",
            self.perf.mesh_queue_depth,
            self.perf.mesh_jobs_completed,
            self.perf.node_counts.rendered_submeshes,
            self.perf.node_counts.visible_submeshes,
            self.perf.node_counts.shadow_off_submeshes,
            self.perf.node_counts.shadow_double_sided_submeshes,
            self.perf.node_counts.shadow_only_submeshes,
            self.perf.node_counts.cpu_proxy_collision,
            self.perf.node_counts.cpu_proxy_shadow,
            self.perf.node_counts.cpu_proxy_both,
            self.perf.node_counts.cpu_proxy_shadow_only,
            shadow_path.as_str(),
            gpu_terrain_shadow_proxy_mode().as_str(),
            gpu_terrain_shadow_proxy_mesh_mode().as_str(),
            self.perf.compact_shadow_proxy_meshes_built,
            self.perf.compact_shadow_proxy_normals_saved,
            self.perf.compact_collision_proxy_meshes_built,
            self.perf.compact_collision_proxy_normals_saved,
            self.perf.cpu_proxy_meshes_built,
            self.perf.node_counts.total_collision_bodies,
            self.perf.last_mesh_ms,
            self.perf.avg_mesh_ms,
            self.perf.max_mesh_ms,
            self.perf.last_prepare_ms,
            self.perf.last_submit_ms,
            self.perf.last_sync_ms,
            self.perf.last_readback_ms,
            self.perf.last_parse_ms,
            self.perf.last_collision_ms,
            self.perf.avg_collision_ms,
            self.perf.max_collision_ms,
            self.perf.last_vertices,
            self.perf.last_reported_vertices,
            self.perf.total_vertices,
            self.perf.last_normals,
            self.perf.total_normals,
            self.perf.chunk_bytes_loaded as f64 / (1024.0 * 1024.0),
            gpu_terrain_text,
        );
        GString::from(text.as_str())
    }

    #[func]
    fn get_block_name(&self, block_id: i32) -> GString {
        blocks::name(block_id as u32).into()
    }

    #[func]
    fn on_player_debug_log(&mut self, message: GString) {
        self.emit_debug_log(&message.to_string());
    }

    #[func]
    fn on_gpu_terrain_compositor(
        &mut self,
        callback_type: i32,
        render_data: Gd<godot::classes::RenderData>,
    ) {
        if let Some(gpu_terrain) = &mut self.gpu_terrain {
            gpu_terrain.render_compositor(callback_type, render_data);
        }
    }

    #[func]
    fn on_block_broken(&mut self, x: i32, y: i32, z: i32) {
        self.last_block_action = format!("destroy {x},{y},{z}");
        self.last_save_event = format!(
            "pending chunk {},{}",
            x.div_euclid(CHUNK_W as i32),
            z.div_euclid(CHUNK_D as i32)
        );
        self.emit_debug_log(&format!("Block destroy sent: {x}, {y}, {z}"));

        let packet = crate::api::Packet {
            payload: Some(crate::api::packet::Payload::BlockAction(
                crate::api::BlockAction {
                    action: crate::api::block_action::ActionType::Destroy as i32,
                    x,
                    y,
                    z,
                    block_id: 0,
                },
            )),
        };

        self.send_packet_to_server(&packet);
    }

    #[func]
    fn on_block_placed(&mut self, x: i32, y: i32, z: i32, block_id: i32) {
        if !blocks::is_placeable(block_id as u32) {
            self.emit_debug_log(&format!("Skipped invalid place id={block_id}"));
            return;
        }

        self.last_block_action = format!("place {} at {x},{y},{z}", blocks::name(block_id as u32));
        self.last_save_event = format!(
            "pending chunk {},{}",
            x.div_euclid(CHUNK_W as i32),
            z.div_euclid(CHUNK_D as i32)
        );
        self.emit_debug_log(&format!("Block place sent: {x}, {y}, {z} id={block_id}"));

        let packet = crate::api::Packet {
            payload: Some(crate::api::packet::Payload::BlockAction(
                crate::api::BlockAction {
                    action: crate::api::block_action::ActionType::Place as i32,
                    x,
                    y,
                    z,
                    block_id: block_id as u32,
                },
            )),
        };

        self.send_packet_to_server(&packet);
    }

    #[signal]
    fn debug_log(message: GString);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn subchunk_key_from_mesh_name_parses_expected_format() {
        let key = subchunk_key_from_mesh_name("SubchunkMesh_-2_7_3").expect("valid subchunk key");

        assert_eq!(key.chunk_x, -2);
        assert_eq!(key.sub_y, 7);
        assert_eq!(key.chunk_z, 3);
        assert!(subchunk_key_from_mesh_name("SubchunkMesh_-2_7_3_extra").is_none());
        assert!(subchunk_key_from_mesh_name("ChunkMesh_-2_7_3").is_none());
    }

    #[test]
    fn flag_state_parses_supported_values() {
        assert_eq!(flag_state_from_value("1"), Some(true));
        assert_eq!(flag_state_from_value(" TRUE "), Some(true));
        assert_eq!(flag_state_from_value("on"), Some(true));
        assert_eq!(flag_state_from_value("0"), Some(false));
        assert_eq!(flag_state_from_value("false"), Some(false));
        assert_eq!(flag_state_from_value("off"), Some(false));
        assert_eq!(flag_state_from_value(""), None);
        assert_eq!(flag_state_from_value("invalid"), None);
    }

    #[test]
    fn gpu_terrain_render_remains_opt_in_with_explicit_enable() {
        assert!(!gpu_terrain_render_decision(None));
        assert!(gpu_terrain_render_decision(Some(true)));
        assert!(!gpu_terrain_render_decision(Some(false)));
    }

    #[test]
    fn gpu_terrain_upload_follows_explicit_upload_or_render_enable() {
        assert!(!gpu_terrain_upload_decision(false, false));
        assert!(gpu_terrain_upload_decision(true, false));
        assert!(gpu_terrain_upload_decision(false, true));
        assert!(gpu_terrain_upload_decision(true, true));
    }

    #[test]
    fn gpu_visible_render_waits_for_flag_attachment_and_confirmed_frame() {
        assert!(!gpu_terrain_visible_render_active_decision(
            false, true, true
        ));
        assert!(!gpu_terrain_visible_render_active_decision(
            true, false, true
        ));
        assert!(!gpu_terrain_visible_render_active_decision(
            true, true, false
        ));
        assert!(gpu_terrain_visible_render_active_decision(true, true, true));
    }

    #[test]
    fn shadow_proxy_mode_parses_supported_values() {
        assert_eq!(
            GpuTerrainShadowProxyMode::from_env_value(""),
            Some(GpuTerrainShadowProxyMode::Conservative)
        );
        assert_eq!(
            GpuTerrainShadowProxyMode::from_env_value("collision-only"),
            Some(GpuTerrainShadowProxyMode::CollisionOnly)
        );
        assert_eq!(GpuTerrainShadowProxyMode::from_env_value("invalid"), None);
    }

    #[test]
    fn terrain_shadow_path_keeps_production_and_diagnostic_paths_explicit() {
        assert_eq!(
            terrain_shadow_path_decision(false, GpuTerrainShadowProxyMode::Conservative, 5),
            GpuTerrainShadowPath::ArrayMesh
        );
        assert_eq!(
            terrain_shadow_path_decision(true, GpuTerrainShadowProxyMode::Conservative, 5),
            GpuTerrainShadowPath::GodotProxy
        );
        assert_eq!(
            terrain_shadow_path_decision(true, GpuTerrainShadowProxyMode::Conservative, 0),
            GpuTerrainShadowPath::SceneShadowsDisabled
        );
        assert_eq!(
            terrain_shadow_path_decision(true, GpuTerrainShadowProxyMode::CollisionOnly, 5),
            GpuTerrainShadowPath::DiagnosticNoShadowProxy
        );
    }

    #[test]
    fn shadow_proxy_radius_prefers_clamped_override() {
        assert_eq!(
            terrain_shadow_proxy_chunk_distance(Some(-2), Some(160.0)),
            0
        );
        assert_eq!(
            terrain_shadow_proxy_chunk_distance(Some(CLIENT_KEEP_CHUNK_DISTANCE + 5), Some(32.0)),
            CLIENT_KEEP_CHUNK_DISTANCE
        );
    }

    #[test]
    fn shadow_proxy_radius_tracks_scene_shadow_distance() {
        assert_eq!(terrain_shadow_proxy_chunk_distance(None, Some(32.0)), 2);
        assert_eq!(
            terrain_shadow_proxy_chunk_distance(
                None,
                Some(DEFAULT_GPU_TERRAIN_SHADOW_PROXY_DISTANCE)
            ),
            6
        );
        assert_eq!(
            terrain_shadow_proxy_chunk_distance(None, Some(1_000_000.0)),
            CLIENT_KEEP_CHUNK_DISTANCE
        );
    }

    #[test]
    fn shadow_proxy_radius_handles_disabled_or_unavailable_scene_shadows() {
        assert_eq!(terrain_shadow_proxy_chunk_distance(None, Some(0.0)), 0);
        assert_eq!(terrain_shadow_proxy_chunk_distance(None, Some(-1.0)), 0);
        assert_eq!(
            terrain_shadow_proxy_chunk_distance(None, Some(f32::NAN)),
            DEFAULT_GPU_TERRAIN_SHADOW_PROXY_CHUNK_DISTANCE
        );
        assert_eq!(
            terrain_shadow_proxy_chunk_distance(None, Some(f32::INFINITY)),
            DEFAULT_GPU_TERRAIN_SHADOW_PROXY_CHUNK_DISTANCE
        );
        assert_eq!(terrain_shadow_proxy_chunk_distance(None, None), 6);
    }

    #[test]
    fn subchunk_collision_proxy_tracks_player_radius() {
        let origin = SubchunkKey {
            chunk_x: 0,
            sub_y: 3,
            chunk_z: 0,
        };
        let near = SubchunkKey {
            chunk_x: 6,
            sub_y: 3,
            chunk_z: -7,
        };
        let far = SubchunkKey {
            chunk_x: 8,
            sub_y: 3,
            chunk_z: -7,
        };

        assert!(subchunk_needs_collision(origin, None));
        assert!(!subchunk_needs_collision(near, None));
        assert!(subchunk_needs_collision(near, Some((5, -7))));
        assert!(!subchunk_needs_collision(far, Some((5, -7))));
    }

    #[test]
    fn subchunk_shadow_proxy_tracks_mode_radius_and_player_chunk() {
        let origin = SubchunkKey {
            chunk_x: 0,
            sub_y: 4,
            chunk_z: 0,
        };
        let near = SubchunkKey {
            chunk_x: 4,
            sub_y: 4,
            chunk_z: -7,
        };
        let far = SubchunkKey {
            chunk_x: 9,
            sub_y: 4,
            chunk_z: -7,
        };

        assert!(!subchunk_needs_shadow_proxy(
            origin,
            None,
            GpuTerrainShadowProxyMode::Conservative,
            0
        ));
        assert!(subchunk_needs_shadow_proxy(
            origin,
            None,
            GpuTerrainShadowProxyMode::Conservative,
            5
        ));
        assert!(!subchunk_needs_shadow_proxy(
            origin,
            None,
            GpuTerrainShadowProxyMode::CollisionOnly,
            5
        ));
        assert!(subchunk_needs_shadow_proxy(
            near,
            Some((5, -7)),
            GpuTerrainShadowProxyMode::Conservative,
            2
        ));
        assert!(!subchunk_needs_shadow_proxy(
            far,
            Some((5, -7)),
            GpuTerrainShadowProxyMode::Conservative,
            2
        ));
    }

    #[test]
    fn subchunk_cpu_proxy_keeps_fallback_collision_or_shadow_only_reasons() {
        assert!(subchunk_needs_cpu_proxy(false, false, false));
        assert!(subchunk_needs_cpu_proxy(true, true, false));
        assert!(subchunk_needs_cpu_proxy(true, false, true));
        assert!(subchunk_needs_cpu_proxy(true, true, true));
        assert!(!subchunk_needs_cpu_proxy(true, false, false));
    }

    #[test]
    fn cpu_proxy_refresh_tracks_collision_and_shadow_radius_edges() {
        assert!(chunk_needs_cpu_proxy_refresh((1, 0), None, (0, 0), 0));
        assert!(!chunk_needs_cpu_proxy_refresh((2, 0), None, (0, 0), 0));

        assert!(chunk_needs_cpu_proxy_refresh(
            (1, 0),
            Some((0, 0)),
            (4, 0),
            0
        ));
        assert!(chunk_needs_cpu_proxy_refresh(
            (4, 0),
            Some((0, 0)),
            (3, 0),
            0
        ));

        assert!(chunk_needs_cpu_proxy_refresh((4, 0), None, (0, 0), 5));
        assert!(!chunk_needs_cpu_proxy_refresh((4, 0), None, (0, 0), 0));
        assert!(!chunk_needs_cpu_proxy_refresh(
            (8, 0),
            Some((0, 0)),
            (1, 0),
            5
        ));
    }

    #[test]
    fn gpu_attach_refresh_requeues_all_loaded_chunks_only_when_visible() {
        let loaded_chunks = vec![(-10, 7), (0, 0), (6, -4)];

        assert_eq!(
            chunks_to_refresh_after_gpu_attach(loaded_chunks.iter().copied(), false),
            Vec::<(i32, i32)>::new()
        );
        assert_eq!(
            chunks_to_refresh_after_gpu_attach(loaded_chunks.iter().copied(), true),
            loaded_chunks
        );
    }

    #[test]
    fn terrain_cpu_proxy_mesh_requires_visible_gpu_slot() {
        assert!(!terrain_cpu_proxy_mesh_active(
            false,
            TerrainGpuUploadState::Failed
        ));
        assert!(!terrain_cpu_proxy_mesh_active(
            false,
            TerrainGpuUploadState::Uploaded
        ));
        assert!(!terrain_cpu_proxy_mesh_active(
            true,
            TerrainGpuUploadState::Failed
        ));
        assert!(!terrain_cpu_proxy_mesh_active(
            true,
            TerrainGpuUploadState::NotRequested
        ));
        assert!(terrain_cpu_proxy_mesh_active(
            true,
            TerrainGpuUploadState::Uploaded
        ));
    }

    #[test]
    fn terrain_mesh_build_plan_preserves_gpu_proxy_and_fallback_paths() {
        assert_eq!(
            terrain_mesh_build_plan(TerrainGpuUploadState::Uploaded, true, false, true),
            TerrainMeshBuildPlan::RemoveCpuNode
        );
        assert_eq!(
            terrain_mesh_build_plan(TerrainGpuUploadState::Uploaded, true, true, true),
            TerrainMeshBuildPlan::CpuProxyMesh
        );
        assert_eq!(
            terrain_mesh_build_plan(TerrainGpuUploadState::Uploaded, true, true, false),
            TerrainMeshBuildPlan::FullArrayMesh
        );
        assert_eq!(
            terrain_mesh_build_plan(TerrainGpuUploadState::Uploaded, false, true, true),
            TerrainMeshBuildPlan::FullArrayMesh
        );
        assert_eq!(
            terrain_mesh_build_plan(TerrainGpuUploadState::Uploaded, false, false, true),
            TerrainMeshBuildPlan::FullArrayMesh
        );
        assert_eq!(
            terrain_mesh_build_plan(TerrainGpuUploadState::Failed, true, true, true),
            TerrainMeshBuildPlan::FullArrayMesh
        );
        assert_eq!(
            terrain_mesh_build_plan(TerrainGpuUploadState::NotRequested, true, false, true),
            TerrainMeshBuildPlan::FullArrayMesh
        );
    }

    #[test]
    fn terrain_gpu_upload_state_separates_request_and_result() {
        assert_eq!(
            TerrainGpuUploadState::for_request(false),
            TerrainGpuUploadState::NotRequested
        );
        assert_eq!(
            TerrainGpuUploadState::for_request(true),
            TerrainGpuUploadState::Failed
        );
        assert_eq!(
            TerrainGpuUploadState::from_upload_result(true),
            TerrainGpuUploadState::Uploaded
        );
        assert_eq!(
            TerrainGpuUploadState::from_upload_result(false),
            TerrainGpuUploadState::Failed
        );
        assert_eq!(
            TerrainGpuUploadState::from_existing_slot(true),
            TerrainGpuUploadState::Uploaded
        );
        assert_eq!(
            TerrainGpuUploadState::from_existing_slot(false),
            TerrainGpuUploadState::Failed
        );
        assert!(TerrainGpuUploadState::Uploaded.has_confirmed_slot());
        assert!(!TerrainGpuUploadState::Failed.has_confirmed_slot());
        assert!(!TerrainGpuUploadState::NotRequested.has_confirmed_slot());
    }

    #[test]
    fn shadow_proxy_mesh_mode_parses_supported_values() {
        assert_eq!(
            GpuTerrainShadowProxyMeshMode::from_env_value(""),
            Some(GpuTerrainShadowProxyMeshMode::Compact)
        );
        assert_eq!(
            GpuTerrainShadowProxyMeshMode::from_env_value("full"),
            Some(GpuTerrainShadowProxyMeshMode::Full)
        );
        assert_eq!(
            GpuTerrainShadowProxyMeshMode::from_env_value("vertex-only"),
            Some(GpuTerrainShadowProxyMeshMode::Compact)
        );
        assert_eq!(
            GpuTerrainShadowProxyMeshMode::from_env_value("invalid"),
            None
        );
    }

    #[test]
    fn compact_shadow_proxy_mesh_only_applies_to_shadow_only_cpu_proxy() {
        let compact = GpuTerrainShadowProxyMeshMode::Compact;

        assert!(compact.compacts_shadow_only_mesh(true, false, true));
        assert!(!compact.compacts_shadow_only_mesh(true, true, true));
        assert!(!compact.compacts_shadow_only_mesh(true, false, false));
        assert!(!compact.compacts_shadow_only_mesh(false, false, true));
        assert!(!GpuTerrainShadowProxyMeshMode::Full.compacts_shadow_only_mesh(true, false, true));
    }

    #[test]
    fn cpu_proxy_mesh_payload_compacts_shadow_or_collision_only_roles() {
        let no_proxy = terrain_cpu_proxy_mesh_payload(
            GpuTerrainShadowProxyMeshMode::Compact,
            false,
            true,
            false,
        );
        assert_eq!(no_proxy, TerrainCpuProxyMeshPayload::default());
        assert!(!no_proxy.uses_compact_mesh());

        let shadow_only = terrain_cpu_proxy_mesh_payload(
            GpuTerrainShadowProxyMeshMode::Compact,
            true,
            false,
            true,
        );
        assert_eq!(
            shadow_only,
            TerrainCpuProxyMeshPayload {
                compact_shadow_proxy_mesh: true,
                compact_collision_proxy_mesh: false,
            }
        );
        assert!(shadow_only.uses_compact_mesh());

        let collision_and_shadow = terrain_cpu_proxy_mesh_payload(
            GpuTerrainShadowProxyMeshMode::Compact,
            true,
            true,
            true,
        );
        assert_eq!(collision_and_shadow, TerrainCpuProxyMeshPayload::default());
        assert!(!collision_and_shadow.uses_compact_mesh());

        let collision_only =
            terrain_cpu_proxy_mesh_payload(GpuTerrainShadowProxyMeshMode::Full, true, true, false);
        assert_eq!(
            collision_only,
            TerrainCpuProxyMeshPayload {
                compact_shadow_proxy_mesh: false,
                compact_collision_proxy_mesh: true,
            }
        );
        assert!(collision_only.uses_compact_mesh());
    }

    #[test]
    fn terrain_mesh_render_mode_matches_proxy_role() {
        let fallback = TerrainMeshRenderMode::from_proxy_state(false, false);
        assert_eq!(fallback, TerrainMeshRenderMode::VisibleDoubleSided);
        assert!(fallback.is_visible());
        assert_eq!(
            fallback.shadow_setting(),
            godot::classes::geometry_instance_3d::ShadowCastingSetting::DOUBLE_SIDED
        );
        assert_eq!(
            TerrainMeshRenderMode::from_proxy_state(false, true),
            TerrainMeshRenderMode::VisibleDoubleSided
        );

        let shadow_proxy = TerrainMeshRenderMode::from_proxy_state(true, true);
        assert_eq!(shadow_proxy, TerrainMeshRenderMode::ShadowsOnly);
        assert!(shadow_proxy.is_visible());
        assert_eq!(
            shadow_proxy.shadow_setting(),
            godot::classes::geometry_instance_3d::ShadowCastingSetting::SHADOWS_ONLY
        );

        let collision_only = TerrainMeshRenderMode::from_proxy_state(true, false);
        assert_eq!(collision_only, TerrainMeshRenderMode::CollisionOnly);
        assert!(!collision_only.is_visible());
        assert_eq!(
            collision_only.shadow_setting(),
            godot::classes::geometry_instance_3d::ShadowCastingSetting::OFF
        );
    }

    #[test]
    fn node_perf_counts_record_visible_and_shadow_state_buckets() {
        let mut counts = NodePerfCounts::default();

        counts.record_mesh_render_state_values(
            true,
            godot::classes::geometry_instance_3d::ShadowCastingSetting::DOUBLE_SIDED,
        );
        counts.record_mesh_render_state_values(
            false,
            godot::classes::geometry_instance_3d::ShadowCastingSetting::OFF,
        );
        counts.record_mesh_render_state_values(
            true,
            godot::classes::geometry_instance_3d::ShadowCastingSetting::SHADOWS_ONLY,
        );

        assert_eq!(counts.visible_submeshes, 2);
        assert_eq!(counts.shadow_off_submeshes, 1);
        assert_eq!(counts.shadow_double_sided_submeshes, 1);
        assert_eq!(counts.shadow_only_submeshes, 1);
    }

    #[test]
    fn node_perf_counts_record_cpu_proxy_reason_buckets() {
        let mut counts = NodePerfCounts::default();

        counts.record_cpu_proxy_reasons(true, false);
        counts.record_cpu_proxy_reasons(false, true);
        counts.record_cpu_proxy_reasons(true, true);
        counts.record_cpu_proxy_reasons(false, false);

        assert_eq!(counts.cpu_proxy_collision, 2);
        assert_eq!(counts.cpu_proxy_shadow, 2);
        assert_eq!(counts.cpu_proxy_both, 1);
        assert_eq!(counts.cpu_proxy_shadow_only, 1);
    }

    #[test]
    fn perf_records_compact_shadow_proxy_normal_savings() {
        let mut perf = PerfStats::default();

        perf.record_mesh(MeshRecord {
            vertices: 24,
            normals: 0,
            reported_vertices: 24,
            cpu_proxy_mesh: true,
            compact_shadow_proxy_mesh: true,
            compact_collision_proxy_mesh: false,
            mesh_ms: 1.0,
            timing: meshing::MeshTiming::default(),
            collision_ms: 0.0,
            collision_bodies: 0,
            node_counts: NodePerfCounts::default(),
        });

        assert_eq!(perf.last_normals, 0);
        assert_eq!(perf.total_normals, 0);
        assert_eq!(perf.compact_shadow_proxy_normals_saved, 24);

        perf.record_mesh(MeshRecord {
            vertices: 12,
            normals: 12,
            reported_vertices: 12,
            cpu_proxy_mesh: true,
            compact_shadow_proxy_mesh: false,
            compact_collision_proxy_mesh: false,
            mesh_ms: 1.0,
            timing: meshing::MeshTiming::default(),
            collision_ms: 0.0,
            collision_bodies: 0,
            node_counts: NodePerfCounts::default(),
        });

        assert_eq!(perf.last_normals, 12);
        assert_eq!(perf.total_normals, 12);
        assert_eq!(perf.compact_shadow_proxy_normals_saved, 24);

        perf.record_mesh(MeshRecord {
            vertices: 18,
            normals: 0,
            reported_vertices: 18,
            cpu_proxy_mesh: true,
            compact_shadow_proxy_mesh: false,
            compact_collision_proxy_mesh: true,
            mesh_ms: 1.0,
            timing: meshing::MeshTiming::default(),
            collision_ms: 0.0,
            collision_bodies: 0,
            node_counts: NodePerfCounts::default(),
        });

        assert_eq!(perf.compact_collision_proxy_meshes_built, 1);
        assert_eq!(perf.compact_collision_proxy_normals_saved, 18);
        assert_eq!(perf.compact_shadow_proxy_normals_saved, 24);
    }
}
