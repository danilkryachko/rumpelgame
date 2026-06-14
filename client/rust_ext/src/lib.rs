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
    gpu_native_shadow_resources: GpuNativeShadowResources,
    gpu_visible_transition_applied: bool,
    network: Option<network::NetworkClient>,
    packet_receiver: Option<Receiver<network::PacketReadRecord>>,
    player_spawned: bool,
    texture_debug_stand_visible: bool,
    chunk_material: Option<Gd<godot::classes::Material>>,
    chunk_blocks: HashMap<(i32, i32), Vec<u8>>,
    chunk_non_empty_subchunks: HashMap<(i32, i32), u32>,
    chunk_last_seen_sec: HashMap<(i32, i32), f64>,
    mesh_queue: VecDeque<SubchunkKey>,
    queued_subchunks: HashMap<SubchunkKey, MeshQueueReason>,
    collision_refresh_queue: VecDeque<SubchunkKey>,
    queued_collision_refreshes: HashSet<SubchunkKey>,
    cpu_proxy_mesh_payloads: HashMap<SubchunkKey, TerrainCpuProxyMeshPayload>,
    terrain_collision_faces: HashMap<SubchunkKey, PackedVector3Array>,
    subchunk_node_counts: HashMap<SubchunkKey, NodePerfCounts>,
    position_send_timer: f64,
    client_runtime_sec: f64,
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
            gpu_native_shadow_resources: GpuNativeShadowResources::default(),
            gpu_visible_transition_applied: false,
            network: None,
            packet_receiver: None,
            player_spawned: false,
            texture_debug_stand_visible: false,
            chunk_material: None,
            chunk_blocks: HashMap::new(),
            chunk_non_empty_subchunks: HashMap::new(),
            chunk_last_seen_sec: HashMap::new(),
            mesh_queue: VecDeque::new(),
            queued_subchunks: HashMap::new(),
            collision_refresh_queue: VecDeque::new(),
            queued_collision_refreshes: HashSet::new(),
            cpu_proxy_mesh_payloads: HashMap::new(),
            terrain_collision_faces: HashMap::new(),
            subchunk_node_counts: HashMap::new(),
            position_send_timer: 0.0,
            client_runtime_sec: 0.0,
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
            Ok(mut client) => {
                self.emit_debug_log("Connected to server successfully");
                let initial_position = crate::api::Packet {
                    payload: Some(crate::api::packet::Payload::Position(
                        crate::api::ClientPosition {
                            x: INITIAL_PLAYER_X,
                            y: INITIAL_PLAYER_Y,
                            z: INITIAL_PLAYER_Z,
                        },
                    )),
                };
                if let Err(err) = client.send_packet(&initial_position) {
                    self.emit_debug_log(&format!("Failed to send initial position: {err}"));
                    return;
                }

                let stream_clone = match client.try_clone_stream() {
                    Ok(stream) => stream,
                    Err(err) => {
                        self.emit_debug_log(&format!("Failed to clone TCP stream: {err}"));
                        return;
                    }
                };
                let mut reader_client = network::NetworkClient {
                    stream: stream_clone,
                };

                let (tx, rx) = channel();
                self.packet_receiver = Some(rx);
                self.network = Some(client);

                std::thread::spawn(move || {
                    let reader_start = Instant::now();
                    loop {
                        match reader_client.receive_packet_with_timing_since(reader_start) {
                            Ok(record) => {
                                if tx.send(record).is_err() {
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
        if delta.is_finite() && delta > 0.0 {
            self.client_runtime_sec += delta;
        }
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
        for mut record in packets {
            record.timing.queue_lag_ms = elapsed_ms(record.received_at);
            if let Some(crate::api::packet::Payload::Chunk(chunk)) = record.packet.payload {
                self.update_chunk(chunk, record.timing);
            }
        }
        let collision_frame = self.process_collision_refresh_queue();
        let mesh_frame =
            if should_process_mesh_queue_after_collision_refresh(collision_frame.rebuilt) {
                self.process_mesh_queue()
            } else {
                self.perf
                    .record_mesh_queue_frame(self.mesh_queue.len(), 0, 0, 0, 0, 0);
                MeshQueueFrame::default()
            };
        self.perf.record_terrain_queue_frame_work(
            mesh_frame.work_ms,
            collision_frame.work_ms,
            mesh_frame.gpu_uploads,
            mesh_frame.gpu_upload_bytes,
        );
        self.sync_gpu_terrain_lighting();
        self.update_gpu_native_shadow_resources();
        self.update_gpu_visible_transition();
        if gpu_terrain_render_enabled()
            && let Some(gpu_terrain) = &mut self.gpu_terrain
        {
            gpu_terrain.render_debug_offscreen_once();
        }
    }

    fn exit_tree(&mut self) {
        self.shutdown_runtime_resources();
    }
}

impl GameClient {
    fn shutdown_runtime_resources(&mut self) {
        if let Some(compositor) = &mut self.gpu_terrain_compositor {
            compositor.detach_from_camera();
        }
        self.gpu_terrain_compositor = None;
        self.gpu_terrain = None;
        self.gpu_native_shadow_resources.release();
        self.mesher = None;
        self.network = None;
        self.packet_receiver = None;
    }

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
        player_node.set_position(initial_player_position());

        self.base_mut()
            .add_child(&player_node.upcast::<godot::classes::Node>());

        self.player_spawned = true;
        self.perf
            .record_startup_player_spawn(self.client_runtime_sec);
        self.emit_debug_log("Player spawned after chunk collision was created");
        self.attach_gpu_terrain_compositor_to_player_camera();
    }

    fn update_chunk(
        &mut self,
        chunk: crate::api::ChunkData,
        packet_timing: network::PacketReadTiming,
    ) {
        let chunk_x = chunk.x;
        let chunk_z = chunk.z;
        let is_startup_chunk = (chunk_x, chunk_z) == initial_player_chunk();
        if is_startup_chunk {
            self.perf.record_startup_chunk_packet(
                self.client_runtime_sec,
                packet_timing.read_ms,
                packet_timing.decode_ms,
                packet_timing.reader_elapsed_ms,
                packet_timing.queue_lag_ms,
            );
        }
        let chunk_decode_start = Instant::now();
        let raw_blocks = match decode_chunk_blocks(&chunk) {
            Ok(blocks) => blocks,
            Err(err) => {
                self.emit_debug_log(&format!(
                    "Chunk decode failed x={} z={}: {}",
                    chunk_x, chunk_z, err
                ));
                return;
            }
        };
        if is_startup_chunk {
            self.perf.record_startup_chunk_decoded(
                self.client_runtime_sec,
                elapsed_ms(chunk_decode_start),
            );
        }
        self.emit_debug_log(&format!(
            "Chunk received x={} z={} blocks={}",
            chunk_x,
            chunk_z,
            raw_blocks.len()
        ));
        self.last_chunk_event = format!("received {chunk_x},{chunk_z}");
        self.last_save_event = format!("chunk {chunk_x},{chunk_z} updated");

        let previous_non_empty_subchunks = self
            .chunk_non_empty_subchunks
            .get(&(chunk_x, chunk_z))
            .copied()
            .unwrap_or(0);
        let dirty_update = self
            .chunk_blocks
            .get(&(chunk_x, chunk_z))
            .map(|previous_blocks| chunk_dirty_update(previous_blocks, &raw_blocks));
        let non_empty_subchunks = compute_chunk_non_empty_subchunks(&raw_blocks);
        self.perf.record_chunk_update(dirty_update);
        self.chunk_blocks.insert((chunk_x, chunk_z), raw_blocks);
        self.chunk_non_empty_subchunks
            .insert((chunk_x, chunk_z), non_empty_subchunks);
        self.chunk_last_seen_sec
            .insert((chunk_x, chunk_z), self.client_runtime_sec);
        self.perf.chunk_bytes_loaded = self.total_chunk_bytes_loaded();
        if is_startup_chunk {
            self.perf
                .record_startup_chunk_inserted(self.client_runtime_sec);
            self.perf
                .record_startup_chunk_loaded(self.client_runtime_sec);
        }

        if chunk_update_needs_geometry_refresh(dirty_update) {
            if let Some(update) = dirty_update.filter(|update| {
                gpu_terrain_partial_dirty_upload_enabled() && update.changed_blocks > 0
            }) {
                self.enqueue_dirty_chunk_subchunks(chunk_x, chunk_z, update.rebuild_subchunk_mask);
                self.perf.record_partial_dirty_enqueue(
                    dirty_partial_subchunk_count(
                        previous_non_empty_subchunks,
                        non_empty_subchunks,
                        update.rebuild_subchunk_mask,
                    ),
                    dirty_partial_saved_subchunks(
                        previous_non_empty_subchunks,
                        non_empty_subchunks,
                        update.rebuild_subchunk_mask,
                    ),
                );

                let refresh_subchunks = update.rebuild_subchunk_mask.count_ones() as usize;
                let mut edge_neighbor_chunks = 0usize;
                let mut edge_neighbor_subchunks = 0usize;
                for (x, z) in dirty_edge_neighbors(chunk_x, chunk_z, update.edge_mask) {
                    if self.chunk_blocks.contains_key(&(x, z)) {
                        self.enqueue_chunk_subchunks_for_mask(x, z, update.rebuild_subchunk_mask);
                        edge_neighbor_chunks += 1;
                        edge_neighbor_subchunks += refresh_subchunks;
                    }
                }
                self.perf.record_dirty_edge_neighbor_refresh(
                    edge_neighbor_chunks,
                    edge_neighbor_subchunks,
                );
            } else {
                self.enqueue_chunk_subchunks(chunk_x, chunk_z);

                let neighbor_refresh_mask = neighbor_geometry_refresh_mask(
                    previous_non_empty_subchunks,
                    non_empty_subchunks,
                );
                for (x, z) in chunk_neighbors(chunk_x, chunk_z) {
                    if self.chunk_blocks.contains_key(&(x, z)) {
                        self.enqueue_chunk_subchunks_for_mask(x, z, neighbor_refresh_mask);
                    }
                }
            }
        }

        if let Some(center) = self.current_player_chunk {
            self.unload_far_chunks(center);
        }

        if is_startup_chunk {
            for key in initial_spawn_mesh_subchunks() {
                self.queued_subchunks.remove(&key);
                self.perf
                    .record_startup_mesh_dispatched(self.client_runtime_sec);
                self.render_subchunk_mesh(key, MeshQueueReason::GeometryChanged);
            }
            self.perf.record_startup_collision_ready(
                self.client_runtime_sec,
                self.chunk_node_counts(initial_player_chunk()),
            );
            self.spawn_player();
        }
    }

    fn process_mesh_queue(&mut self) -> MeshQueueFrame {
        let mut processed = 0;
        let mut drained = 0;
        let mut geometry_drained = 0;
        let mut proxy_refresh_drained = 0;
        let mut stale_drops = 0;
        let mut missing_chunk_drops = 0;
        let mut frame = MeshQueueFrame::default();
        while processed < MAX_MESH_JOBS_PER_FRAME && drained < MAX_MESH_QUEUE_DRAINS_PER_FRAME {
            let Some(key) = pop_next_mesh_queue_key(
                &mut self.mesh_queue,
                player_chunk_queue_hint(self.current_player_chunk),
            ) else {
                break;
            };
            drained += 1;
            let Some(reason) = self.queued_subchunks.remove(&key) else {
                stale_drops += 1;
                continue;
            };
            match reason {
                MeshQueueReason::GeometryChanged => geometry_drained += 1,
                MeshQueueReason::ProxyRefresh => proxy_refresh_drained += 1,
            }

            if !self.chunk_blocks.contains_key(&(key.chunk_x, key.chunk_z)) {
                missing_chunk_drops += 1;
                continue;
            }
            if reason == MeshQueueReason::ProxyRefresh {
                let proxy_refresh_start = Instant::now();
                if self.handle_proxy_refresh_without_mesh_job(key) {
                    frame.work_ms += elapsed_ms(proxy_refresh_start);
                    continue;
                }
            }
            if reason == MeshQueueReason::GeometryChanged {
                self.perf
                    .record_startup_mesh_dispatched(self.client_runtime_sec);
            }
            frame.record_mesh_job(self.render_subchunk_mesh(key, reason));
            processed += 1;
        }
        self.perf.record_mesh_queue_frame(
            self.mesh_queue.len(),
            drained,
            geometry_drained,
            proxy_refresh_drained,
            stale_drops,
            missing_chunk_drops,
        );
        frame
    }

    fn process_collision_refresh_queue(&mut self) -> CollisionRefreshFrame {
        let mut batch = CollisionRefreshBatch::default();
        let mut drained = 0;
        let mut stale_drops = 0;
        let mut missing_chunk_drops = 0;
        let mut rebuilt = 0;
        let mut work_ms = 0.0;

        while drained < MAX_COLLISION_REFRESH_DRAINS_PER_FRAME
            && rebuilt < MAX_COLLISION_REFRESH_REBUILDS_PER_FRAME
        {
            let Some(key) = pop_next_mesh_queue_key(
                &mut self.collision_refresh_queue,
                player_chunk_queue_hint(self.current_player_chunk),
            ) else {
                break;
            };
            drained += 1;

            if !self.queued_collision_refreshes.remove(&key) {
                stale_drops += 1;
                continue;
            }

            if !self.chunk_blocks.contains_key(&(key.chunk_x, key.chunk_z)) {
                missing_chunk_drops += 1;
                continue;
            }

            let record = self.refresh_subchunk_collision(key);
            work_ms += record.work_ms;
            if record.result == CollisionRefreshResult::Rebuilt {
                rebuilt += 1;
            }
            batch.record(record.result);
        }

        self.perf.record_collision_refresh_queue_frame(
            self.collision_refresh_queue.len(),
            drained,
            stale_drops,
            missing_chunk_drops,
        );
        if batch.checked > 0 {
            self.perf.record_collision_refresh(batch);
        }
        CollisionRefreshFrame { rebuilt, work_ms }
    }

    fn enqueue_chunk_subchunks(&mut self, chunk_x: i32, chunk_z: i32) {
        for sub_y in 0..SUBCHUNKS_PER_CHUNK {
            if self.subchunk_has_blocks(chunk_x, sub_y, chunk_z) {
                self.enqueue_subchunk(
                    SubchunkKey {
                        chunk_x,
                        sub_y,
                        chunk_z,
                    },
                    MeshQueueReason::GeometryChanged,
                );
            } else {
                self.remove_subchunk_mesh(SubchunkKey {
                    chunk_x,
                    sub_y,
                    chunk_z,
                });
            }
        }
    }

    fn enqueue_chunk_subchunks_for_mask(&mut self, chunk_x: i32, chunk_z: i32, mask: u32) {
        for sub_y in 0..SUBCHUNKS_PER_CHUNK {
            if subchunk_mask_has_blocks(mask, sub_y)
                && self.subchunk_has_blocks(chunk_x, sub_y, chunk_z)
            {
                self.enqueue_subchunk(
                    SubchunkKey {
                        chunk_x,
                        sub_y,
                        chunk_z,
                    },
                    MeshQueueReason::GeometryChanged,
                );
            }
        }
    }

    fn enqueue_dirty_chunk_subchunks(&mut self, chunk_x: i32, chunk_z: i32, mask: u32) {
        for sub_y in 0..SUBCHUNKS_PER_CHUNK {
            if !subchunk_mask_has_blocks(mask, sub_y) {
                continue;
            }
            let key = SubchunkKey {
                chunk_x,
                sub_y,
                chunk_z,
            };
            if self.subchunk_has_blocks(chunk_x, sub_y, chunk_z) {
                self.enqueue_subchunk(key, MeshQueueReason::GeometryChanged);
            } else {
                self.remove_subchunk_mesh(key);
            }
        }
    }

    fn enqueue_proxy_refresh_subchunks(&mut self, chunk_x: i32, chunk_z: i32) {
        for sub_y in 0..SUBCHUNKS_PER_CHUNK {
            if self.subchunk_has_blocks(chunk_x, sub_y, chunk_z) {
                self.enqueue_subchunk(
                    SubchunkKey {
                        chunk_x,
                        sub_y,
                        chunk_z,
                    },
                    MeshQueueReason::ProxyRefresh,
                );
            } else {
                self.remove_subchunk_mesh(SubchunkKey {
                    chunk_x,
                    sub_y,
                    chunk_z,
                });
            }
        }
    }

    fn enqueue_subchunk(&mut self, key: SubchunkKey, reason: MeshQueueReason) {
        let inserted = if let Some(queued_reason) = self.queued_subchunks.get_mut(&key) {
            *queued_reason = queued_reason.merged_with(reason);
            false
        } else {
            self.queued_subchunks.insert(key, reason);
            true
        };
        if reason == MeshQueueReason::GeometryChanged {
            self.perf
                .record_startup_mesh_queued(self.client_runtime_sec);
        }
        if inserted {
            self.mesh_queue.push_back(key);
        }
        self.perf
            .record_mesh_queue_enqueue(self.mesh_queue.len(), reason, inserted);
    }

    fn enqueue_collision_refresh_subchunk(&mut self, key: SubchunkKey) {
        let inserted = self.queued_collision_refreshes.insert(key);
        if inserted {
            self.collision_refresh_queue.push_back(key);
        }
        self.perf
            .record_collision_refresh_queue_enqueue(self.collision_refresh_queue.len(), inserted);
    }

    fn try_reuse_gpu_proxy_refresh(
        &mut self,
        key: SubchunkKey,
        reason: MeshQueueReason,
        existing_gpu_slot: bool,
        gpu_visible_render_active: bool,
        needs_cpu_proxy: bool,
        should_have_collision: bool,
        should_have_shadow_proxy: bool,
        work_start: Instant,
    ) -> Option<MeshJobResult> {
        if reason != MeshQueueReason::ProxyRefresh
            || !gpu_visible_render_active
            || !existing_gpu_slot
        {
            return None;
        }

        if !needs_cpu_proxy {
            self.remove_cpu_subchunk_mesh_node(key);
            return Some(MeshJobResult::elapsed(work_start));
        }

        let desired_payload = terrain_cpu_proxy_mesh_payload(
            gpu_terrain_shadow_proxy_mesh_mode(),
            true,
            should_have_collision,
            should_have_shadow_proxy,
        );
        if self.refresh_existing_cpu_proxy_mesh_node(
            key,
            desired_payload,
            should_have_collision,
            should_have_shadow_proxy,
        ) {
            return Some(MeshJobResult::elapsed(work_start));
        }

        None
    }

    fn upload_gpu_subchunk(
        &mut self,
        should_upload_gpu: bool,
        existing_gpu_slot: bool,
        gpu_key: gpu_terrain::GpuSubchunkKey,
        packed_faces: Option<&gpu_terrain::PackedFaceBatch>,
    ) -> GpuUploadResult {
        let mut state = TerrainGpuUploadState::for_request(gpu_terrain_upload_enabled());
        let mut uploads = 0;
        let mut bytes = 0;
        let start = Instant::now();

        if should_upload_gpu
            && let (Some(gpu_terrain), Some(packed_faces)) = (&mut self.gpu_terrain, packed_faces)
        {
            let upload_bytes = packed_faces.byte_len();
            let uploaded = gpu_terrain.upload_subchunk(gpu_key, packed_faces).is_some();
            state = TerrainGpuUploadState::from_upload_result(uploaded);
            if uploaded {
                uploads = 1;
                bytes = upload_bytes;
            }
        } else if existing_gpu_slot {
            state = TerrainGpuUploadState::Uploaded;
        }

        GpuUploadResult {
            state,
            uploads,
            bytes,
            ms: elapsed_ms(start),
        }
    }

    fn build_subchunk_mesh_data(
        &mut self,
        padded_blocks: &[u8],
        packed_faces: Option<&gpu_terrain::PackedFaceBatch>,
        mesh_build_plan: TerrainMeshBuildPlan,
        cpu_proxy_mesh_payload: TerrainCpuProxyMeshPayload,
        work_start: Instant,
        gpu_uploads: usize,
        gpu_upload_bytes: usize,
    ) -> Result<SubchunkMeshData, MeshJobResult> {
        if mesh_build_plan == TerrainMeshBuildPlan::CpuProxyMesh {
            let packed_faces = packed_faces
                .as_ref()
                .expect("packed faces are built for uploaded GPU terrain");
            let proxy_mesh = if cpu_proxy_mesh_payload.uses_indexed_shadow_mesh() {
                packed_faces.build_indexed_compact_cpu_proxy_mesh()
            } else if cpu_proxy_mesh_payload.uses_compact_mesh() {
                packed_faces.build_compact_cpu_proxy_mesh()
            } else {
                packed_faces.build_cpu_proxy_mesh()
            };
            let reported_vertices = if proxy_mesh.indices.is_empty() {
                proxy_mesh.vertices.len()
            } else {
                proxy_mesh.indices.len()
            };
            return Ok(SubchunkMeshData {
                vertices: proxy_mesh.vertices,
                normals: proxy_mesh.normals,
                uvs: PackedVector2Array::new(),
                indices: proxy_mesh.indices,
                timing: meshing::MeshTiming::default(),
                reported_vertices,
            });
        }

        if let Some(packed_faces) = packed_faces {
            let mesh = packed_faces.build_cpu_array_mesh();
            return Ok(SubchunkMeshData {
                vertices: mesh.vertices,
                normals: mesh.normals,
                uvs: mesh.uvs,
                indices: mesh.indices,
                timing: meshing::MeshTiming::default(),
                reported_vertices: mesh.reported_vertex_count,
            });
        }

        let Some(mesher) = &mut self.mesher else {
            return Err(MeshJobResult::new(
                elapsed_ms(work_start),
                gpu_uploads,
                gpu_upload_bytes,
            ));
        };
        let Some(mesh_result) = mesher.mesh_chunk(padded_blocks) else {
            return Err(MeshJobResult::new(
                elapsed_ms(work_start),
                gpu_uploads,
                gpu_upload_bytes,
            ));
        };
        Ok(SubchunkMeshData {
            vertices: mesh_result.vertices,
            normals: mesh_result.normals,
            uvs: mesh_result.uvs,
            indices: PackedInt32Array::new(),
            timing: mesh_result.timing,
            reported_vertices: mesh_result.reported_vertex_count,
        })
    }

    fn build_array_mesh_surface(
        mesh_data: &SubchunkMeshData,
        build_render_surface: bool,
    ) -> Option<Gd<godot::classes::Mesh>> {
        if !build_render_surface {
            return None;
        }

        let mut arrays = Array::new();
        arrays.resize(13, &Variant::nil());
        arrays.set(0, &mesh_data.vertices.to_variant());
        if !mesh_data.normals.is_empty() {
            arrays.set(1, &mesh_data.normals.to_variant());
        }
        if !mesh_data.uvs.is_empty() {
            arrays.set(4, &mesh_data.uvs.to_variant());
        }
        if !mesh_data.indices.is_empty() {
            arrays.set(12, &mesh_data.indices.to_variant());
        }

        let mut array_mesh = godot::classes::ArrayMesh::new_gd();
        array_mesh.add_surface_from_arrays(godot::classes::mesh::PrimitiveType::TRIANGLES, &arrays);
        Some(array_mesh.upcast::<godot::classes::Mesh>())
    }

    fn apply_subchunk_mesh_node(
        &mut self,
        key: SubchunkKey,
        chunk_position: Vector3,
        array_mesh: Option<&Gd<godot::classes::Mesh>>,
        cpu_proxy_mesh: bool,
        should_have_shadow_proxy: bool,
        build_render_surface: bool,
        collision_faces: Option<&PackedVector3Array>,
    ) -> i32 {
        let mesh_name = subchunk_mesh_name(key);
        if let Some(mut mesh_instance) = self
            .base()
            .try_get_node_as::<godot::classes::MeshInstance3D>(&mesh_name)
        {
            set_mesh_instance_surface(&mut mesh_instance, array_mesh);
            mesh_instance.set_position(chunk_position);
            configure_terrain_mesh_render_mode(
                &mut mesh_instance,
                cpu_proxy_mesh,
                should_have_shadow_proxy,
            );

            if build_render_surface {
                let material = self.get_chunk_material();
                mesh_instance.set_material_override(&material);
            }

            clear_mesh_collisions(&mut mesh_instance);
            if let Some(collision_faces) = collision_faces {
                create_mesh_trimesh_collision(&mut mesh_instance, collision_faces);
            }
            return count_static_body_children(&mesh_instance);
        }

        let mut mesh_instance = godot::classes::MeshInstance3D::new_alloc();
        mesh_instance.set_name(&StringName::from(&mesh_name));
        mesh_instance.set_position(chunk_position);
        set_mesh_instance_surface(&mut mesh_instance, array_mesh);
        configure_terrain_mesh_render_mode(
            &mut mesh_instance,
            cpu_proxy_mesh,
            should_have_shadow_proxy,
        );

        if build_render_surface {
            let material = self.get_chunk_material();
            mesh_instance.set_material_override(&material);
        }

        let mesh_node = mesh_instance.clone().upcast::<godot::classes::Node>();
        self.base_mut().add_child(&mesh_node);
        if let Some(collision_faces) = collision_faces {
            create_mesh_trimesh_collision(&mut mesh_instance, collision_faces);
        }
        count_static_body_children(&mesh_instance)
    }

    fn render_subchunk_mesh(&mut self, key: SubchunkKey, reason: MeshQueueReason) -> MeshJobResult {
        let work_start = Instant::now();
        let upload_enabled = gpu_terrain_upload_enabled();
        let gpu_key = gpu_subchunk_key(key);
        let existing_gpu_slot = upload_enabled
            && self
                .gpu_terrain
                .as_ref()
                .is_some_and(|gpu_terrain| gpu_terrain.has_subchunk(gpu_key));
        let needs_cpu_proxy = self.subchunk_needs_cpu_proxy(key);
        let gpu_visible_render_active = self.gpu_terrain_visible_render_active();
        let should_have_collision = self.subchunk_needs_collision(key);
        let should_have_shadow_proxy =
            gpu_visible_render_active && self.subchunk_needs_shadow_proxy(key);

        if let Some(result) = self.try_reuse_gpu_proxy_refresh(
            key,
            reason,
            existing_gpu_slot,
            gpu_visible_render_active,
            needs_cpu_proxy,
            should_have_collision,
            should_have_shadow_proxy,
            work_start,
        ) {
            return result;
        }

        let padded_start = Instant::now();
        let Some(padded_blocks) = self.build_padded_subchunk_blocks(key) else {
            return MeshJobResult::elapsed(work_start);
        };
        let padded_ms = elapsed_ms(padded_start);
        let should_upload_gpu = upload_enabled
            && should_upload_gpu_subchunk_for_queue_reason(reason, existing_gpu_slot);
        let needs_gpu_faces =
            gpu_terrain_stats_enabled() || upload_enabled || cpu_array_mesh_packed_faces_enabled();
        let packed_faces_start = Instant::now();
        let packed_faces = needs_gpu_faces.then(|| gpu_terrain::build_packed_faces(&padded_blocks));
        let packed_faces_ms = elapsed_ms(packed_faces_start);
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

        let gpu_upload = self.upload_gpu_subchunk(
            should_upload_gpu,
            existing_gpu_slot,
            gpu_key,
            packed_faces.as_ref(),
        );

        let mesh_build_plan = terrain_mesh_build_plan(
            gpu_upload.state,
            gpu_visible_render_active,
            needs_cpu_proxy,
            packed_faces.is_some(),
        );
        if mesh_build_plan == TerrainMeshBuildPlan::RemoveCpuNode {
            self.remove_cpu_subchunk_mesh_node(key);
            return MeshJobResult::new(
                elapsed_ms(work_start),
                gpu_upload.uploads,
                gpu_upload.bytes,
            );
        }

        let cpu_proxy_mesh = mesh_build_plan == TerrainMeshBuildPlan::CpuProxyMesh;
        let cpu_proxy_mesh_payload = terrain_cpu_proxy_mesh_payload(
            gpu_terrain_shadow_proxy_mesh_mode(),
            cpu_proxy_mesh,
            should_have_collision,
            should_have_shadow_proxy,
        );
        let cpu_mesh_start = Instant::now();
        let mesh_data = match self.build_subchunk_mesh_data(
            &padded_blocks,
            packed_faces.as_ref(),
            mesh_build_plan,
            cpu_proxy_mesh_payload,
            work_start,
            gpu_upload.uploads,
            gpu_upload.bytes,
        ) {
            Ok(mesh_data) => mesh_data,
            Err(result) => return result,
        };
        let cpu_mesh_ms = elapsed_ms(cpu_mesh_start);

        if mesh_data.vertices.is_empty() {
            self.remove_subchunk_mesh(key);
            return MeshJobResult::new(
                elapsed_ms(work_start),
                gpu_upload.uploads,
                gpu_upload.bytes,
            );
        }
        let render_mode =
            TerrainMeshRenderMode::from_proxy_state(cpu_proxy_mesh, should_have_shadow_proxy);
        let build_render_surface = render_mode.needs_render_surface();
        let array_mesh_start = Instant::now();
        let array_mesh = Self::build_array_mesh_surface(&mesh_data, build_render_surface);
        let array_mesh_ms = elapsed_ms(array_mesh_start);

        let chunk_position = Vector3::new(
            key.chunk_x as f32 * CHUNK_SIZE,
            key.sub_y as f32 * SUBCHUNK_SIZE,
            key.chunk_z as f32 * CHUNK_SIZE,
        );
        let collision_start = Instant::now();
        let collision_faces = should_have_collision.then(|| {
            if let Some(packed_faces) = &packed_faces {
                packed_faces.build_collision_faces()
            } else {
                mesh_data.vertices.clone()
            }
        });
        let collision_bodies = self.apply_subchunk_mesh_node(
            key,
            chunk_position,
            array_mesh.as_ref(),
            cpu_proxy_mesh,
            should_have_shadow_proxy,
            build_render_surface,
            collision_faces.as_ref(),
        );

        let collision_ms = elapsed_ms(collision_start);
        let collision_faces_len = collision_faces.as_ref().map_or(0, |faces| faces.len());
        let direct_collision_faces = collision_faces.is_some();
        if gpu_visible_render_active && let Some(collision_faces) = collision_faces {
            if !collision_faces.is_empty() {
                self.terrain_collision_faces.insert(key, collision_faces);
            } else {
                self.terrain_collision_faces.remove(&key);
            }
        } else if gpu_visible_render_active && mesh_data.indices.is_empty() {
            self.terrain_collision_faces
                .insert(key, mesh_data.vertices.clone());
        } else {
            self.terrain_collision_faces.remove(&key);
        }
        if cpu_proxy_mesh {
            self.cpu_proxy_mesh_payloads
                .insert(key, cpu_proxy_mesh_payload);
        } else {
            self.cpu_proxy_mesh_payloads.remove(&key);
        }
        let node_counts_start = Instant::now();
        let subchunk_node_counts = NodePerfCounts::from_subchunk_state(
            should_have_collision,
            should_have_shadow_proxy,
            render_mode.is_visible(),
            render_mode.shadow_setting(),
            collision_bodies,
        );
        self.replace_subchunk_node_perf_counts(key, subchunk_node_counts);
        let node_counts = self.perf.node_counts;
        let node_counts_ms = node_counts_start.elapsed().as_secs_f64() * 1000.0;
        let mesh_ms = elapsed_ms(work_start);
        let mesh_record = MeshRecord {
            vertices: mesh_data.vertices.len(),
            normals: mesh_data.normals.len(),
            reported_vertices: mesh_data.reported_vertices,
            reason,
            cpu_proxy_mesh,
            compact_shadow_proxy_mesh: cpu_proxy_mesh_payload.compact_shadow_proxy_mesh,
            compact_collision_proxy_mesh: cpu_proxy_mesh_payload.compact_collision_proxy_mesh,
            mesh_ms,
            timing: mesh_data.timing,
            phase_timing: TerrainMeshPhaseTiming {
                padded_ms,
                packed_faces_ms,
                gpu_upload_ms: gpu_upload.ms,
                cpu_mesh_ms,
                array_mesh_ms,
                node_counts_ms,
            },
            collision_ms,
            collision_faces: collision_faces_len,
            direct_collision_faces,
            collision_bodies,
            node_counts,
        };
        if reason == MeshQueueReason::GeometryChanged {
            self.perf
                .record_startup_first_mesh(self.client_runtime_sec, &mesh_record);
        }
        self.perf.record_mesh(mesh_record);
        MeshJobResult::new(elapsed_ms(work_start), gpu_upload.uploads, gpu_upload.bytes)
    }

    fn handle_proxy_refresh_without_mesh_job(&mut self, key: SubchunkKey) -> bool {
        let upload_enabled = gpu_terrain_upload_enabled();
        let existing_gpu_slot = upload_enabled
            && self
                .gpu_terrain
                .as_ref()
                .is_some_and(|gpu_terrain| gpu_terrain.has_subchunk(gpu_subchunk_key(key)));
        let gpu_visible_render_active = self.gpu_terrain_visible_render_active();
        let should_have_collision = self.subchunk_needs_collision(key);
        let should_have_shadow_proxy =
            gpu_visible_render_active && self.subchunk_needs_shadow_proxy(key);
        let needs_cpu_proxy = subchunk_needs_cpu_proxy(
            gpu_visible_render_active,
            should_have_collision,
            !should_have_collision && should_have_shadow_proxy,
        );
        let desired_payload = terrain_cpu_proxy_mesh_payload(
            gpu_terrain_shadow_proxy_mesh_mode(),
            true,
            should_have_collision,
            should_have_shadow_proxy,
        );

        match proxy_refresh_queue_action(
            gpu_visible_render_active,
            existing_gpu_slot,
            needs_cpu_proxy,
            self.cpu_proxy_mesh_payloads.get(&key).copied(),
            desired_payload,
        ) {
            ProxyRefreshQueueAction::BuildMesh => false,
            ProxyRefreshQueueAction::RemoveCpuNode => {
                self.remove_cpu_subchunk_mesh_node(key);
                true
            }
            ProxyRefreshQueueAction::ReuseCpuProxy => self.refresh_existing_cpu_proxy_mesh_node(
                key,
                desired_payload,
                should_have_collision,
                should_have_shadow_proxy,
            ),
        }
    }

    fn refresh_existing_cpu_proxy_mesh_node(
        &mut self,
        key: SubchunkKey,
        desired_payload: TerrainCpuProxyMeshPayload,
        should_have_collision: bool,
        should_have_shadow_proxy: bool,
    ) -> bool {
        let Some(existing_payload) = self.cpu_proxy_mesh_payloads.get(&key).copied() else {
            return false;
        };
        if !existing_payload.can_satisfy(desired_payload) {
            return false;
        }

        let mesh_name = subchunk_mesh_name(key);
        let Some(mut mesh_instance) = self
            .base()
            .try_get_node_as::<godot::classes::MeshInstance3D>(&mesh_name)
        else {
            self.cpu_proxy_mesh_payloads.remove(&key);
            self.remove_subchunk_node_perf_counts(key);
            return false;
        };

        configure_terrain_mesh_render_mode(&mut mesh_instance, true, should_have_shadow_proxy);
        let has_collision = count_static_body_children(&mesh_instance) > 0;
        if should_have_collision != has_collision {
            self.enqueue_collision_refresh_subchunk(key);
        }

        self.cpu_proxy_mesh_payloads.insert(key, existing_payload);
        self.perf.cpu_proxy_refreshes_reused += 1;
        let node_counts = self.subchunk_node_perf_counts_for_mesh_instance(key, &mesh_instance);
        self.replace_subchunk_node_perf_counts(key, node_counts);
        true
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
        if let Some(mask) = self.chunk_non_empty_subchunks.get(&(chunk_x, chunk_z)) {
            return subchunk_mask_has_blocks(*mask, sub_y);
        }

        let Some(blocks) = self.chunk_blocks.get(&(chunk_x, chunk_z)) else {
            return false;
        };
        chunk_subchunk_has_blocks(blocks, sub_y)
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
        let radius = terrain_godot_shadow_proxy_chunk_distance(
            mode,
            self.terrain_shadow_proxy_chunk_distance(),
            gpu_terrain_native_shadow_active(),
        );

        subchunk_needs_shadow_proxy(key, self.current_player_chunk, mode, radius)
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
            if !chunk_needs_collision_refresh(coord, previous, current) {
                continue;
            }
            for sub_y in 0..SUBCHUNKS_PER_CHUNK {
                if !self.subchunk_has_blocks(coord.0, sub_y, coord.1) {
                    continue;
                }
                self.enqueue_collision_refresh_subchunk(SubchunkKey {
                    chunk_x: coord.0,
                    sub_y,
                    chunk_z: coord.1,
                });
            }
        }
    }

    fn enqueue_cpu_proxy_refresh(&mut self, previous: Option<(i32, i32)>, current: (i32, i32)) {
        if !gpu_terrain_render_enabled() {
            return;
        }

        let shadow_radius = terrain_godot_shadow_proxy_chunk_distance(
            gpu_terrain_shadow_proxy_mode(),
            self.terrain_shadow_proxy_chunk_distance(),
            gpu_terrain_native_shadow_active(),
        );
        let loaded_chunks: Vec<(i32, i32)> = self.chunk_blocks.keys().copied().collect();
        for coord in loaded_chunks {
            if chunk_needs_cpu_proxy_refresh(coord, previous, current, shadow_radius) {
                self.enqueue_proxy_refresh_subchunks(coord.0, coord.1);
            }
        }
    }

    fn refresh_subchunk_collision(&mut self, key: SubchunkKey) -> CollisionRefreshRecord {
        let work_start = Instant::now();
        let mesh_name = subchunk_mesh_name(key);
        let Some(mut mesh_instance) = self
            .base()
            .try_get_node_as::<godot::classes::MeshInstance3D>(&mesh_name)
        else {
            return CollisionRefreshRecord::new(CollisionRefreshResult::MissingMesh, work_start);
        };

        let needs_collision = self.subchunk_needs_collision(key);
        let has_collision = count_static_body_children(&mesh_instance) > 0;
        if needs_collision == has_collision {
            return CollisionRefreshRecord::new(CollisionRefreshResult::Unchanged, work_start);
        }

        let faces_start = Instant::now();
        let (collision_faces, cached_faces) = if needs_collision {
            self.subchunk_collision_faces_for_refresh(key)
                .map_or((None, false), |faces| (Some(faces), true))
        } else {
            (None, false)
        };
        let collision_faces_ms = elapsed_ms(faces_start);

        let collision_start = Instant::now();
        let clear_start = Instant::now();
        clear_mesh_collisions(&mut mesh_instance);
        let clear_ms = elapsed_ms(clear_start);
        let create_start = Instant::now();
        if needs_collision {
            if let Some(faces) = collision_faces.as_ref() {
                create_mesh_trimesh_collision(&mut mesh_instance, faces);
            } else {
                mesh_instance.create_trimesh_collision();
            }
        }
        let create_ms = elapsed_ms(create_start);
        let collision_ms = collision_start.elapsed().as_secs_f64() * 1000.0;
        let count_start = Instant::now();
        let collision_bodies = count_static_body_children(&mesh_instance);
        let count_ms = elapsed_ms(count_start);
        let collision_faces_len = collision_faces.as_ref().map_or(0, PackedVector3Array::len);
        let payload = self
            .cpu_proxy_mesh_payloads
            .get(&key)
            .copied()
            .unwrap_or_default();
        if let Some(faces) = collision_faces {
            self.terrain_collision_faces.insert(key, faces);
        }
        let node_counts_start = Instant::now();
        let node_counts = self.subchunk_node_perf_counts_for_mesh_instance(key, &mesh_instance);
        self.replace_subchunk_node_perf_counts(key, node_counts);
        let node_counts_ms = elapsed_ms(node_counts_start);
        self.perf.record_collision_timing(CollisionPerfRecord {
            ms: collision_ms,
            source: CollisionPerfSource::RefreshQueue,
            reason: None,
            cpu_proxy_mesh: self.cpu_proxy_mesh_payloads.contains_key(&key),
            compact_shadow_proxy_mesh: payload.compact_shadow_proxy_mesh,
            compact_collision_proxy_mesh: payload.compact_collision_proxy_mesh,
            collision_bodies,
            collision_faces: collision_faces_len,
            vertices: collision_faces_len,
            reported_vertices: collision_faces_len,
            cached_faces,
            phase_timing: TerrainMeshPhaseTiming::default(),
            refresh_phase_timing: CollisionRefreshPhaseTiming {
                faces_ms: collision_faces_ms,
                clear_ms,
                create_ms,
                count_ms,
                node_counts_ms,
            },
        });
        CollisionRefreshRecord::new(CollisionRefreshResult::Rebuilt, work_start)
    }

    fn subchunk_collision_faces_for_refresh(&self, key: SubchunkKey) -> Option<PackedVector3Array> {
        if let Some(faces) = self.terrain_collision_faces.get(&key) {
            return Some(faces.clone());
        }

        let padded_blocks = self.build_padded_subchunk_blocks(key)?;
        let packed_faces = gpu_terrain::build_packed_faces(&padded_blocks);
        Some(packed_faces.build_collision_faces())
    }

    fn unload_far_chunks(&mut self, center: (i32, i32)) {
        let now_sec = self.client_runtime_sec;
        let keep_distance = client_keep_chunk_distance();
        for coord in self.chunk_blocks.keys().copied() {
            if chunk_within_radius(coord, center, keep_distance) {
                self.chunk_last_seen_sec.insert(coord, now_sec);
            }
        }

        let grace_sec = client_chunk_unload_grace_sec();
        let to_unload: Vec<(i32, i32)> = self
            .chunk_blocks
            .keys()
            .copied()
            .filter(|coord| {
                should_unload_chunk(
                    *coord,
                    center,
                    keep_distance,
                    self.chunk_last_seen_sec.get(coord).copied(),
                    now_sec,
                    grace_sec,
                )
            })
            .collect();
        if to_unload.is_empty() {
            return;
        }

        let mut rerender = HashSet::new();
        for coord in to_unload {
            self.chunk_blocks.remove(&coord);
            self.chunk_non_empty_subchunks.remove(&coord);
            self.chunk_last_seen_sec.remove(&coord);
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
            self.queued_collision_refreshes.remove(&key);
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
        self.cpu_proxy_mesh_payloads.remove(&key);
        self.terrain_collision_faces.remove(&key);
        self.queued_collision_refreshes.remove(&key);
        self.remove_subchunk_node_perf_counts(key);
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
    }

    fn refresh_node_perf_counts(&mut self) {
        let mut subchunk_node_counts = HashMap::new();
        let mut counts = NodePerfCounts::default();
        for idx in 0..self.base().get_child_count() {
            let Some(child) = self.base().get_child(idx) else {
                continue;
            };
            let Some(key) = subchunk_key_from_mesh_name(&child.get_name().to_string()) else {
                continue;
            };
            let Ok(mesh_instance) = child.try_cast::<godot::classes::MeshInstance3D>() else {
                continue;
            };
            let subchunk_counts =
                self.subchunk_node_perf_counts_for_mesh_instance(key, &mesh_instance);
            counts.add(subchunk_counts);
            subchunk_node_counts.insert(key, subchunk_counts);
        }
        self.subchunk_node_counts = subchunk_node_counts;
        self.perf.node_counts = counts;
    }

    fn replace_subchunk_node_perf_counts(&mut self, key: SubchunkKey, counts: NodePerfCounts) {
        if let Some(previous) = self.subchunk_node_counts.insert(key, counts) {
            self.perf.node_counts.subtract(previous);
        }
        self.perf.node_counts.add(counts);
    }

    fn remove_subchunk_node_perf_counts(&mut self, key: SubchunkKey) {
        if let Some(previous) = self.subchunk_node_counts.remove(&key) {
            self.perf.node_counts.subtract(previous);
        }
    }

    fn current_chunk_node_counts(&self) -> NodePerfCounts {
        let Some((chunk_x, chunk_z)) = self.current_player_chunk else {
            return NodePerfCounts::default();
        };
        self.chunk_node_counts((chunk_x, chunk_z))
    }

    fn chunk_node_counts(&self, (chunk_x, chunk_z): (i32, i32)) -> NodePerfCounts {
        self.subchunk_node_counts
            .iter()
            .filter(|(key, _)| key.chunk_x == chunk_x && key.chunk_z == chunk_z)
            .fold(
                NodePerfCounts::default(),
                |mut counts, (_, subchunk_counts)| {
                    counts.add(*subchunk_counts);
                    counts
                },
            )
    }

    fn subchunk_node_perf_counts_for_mesh_instance(
        &self,
        key: SubchunkKey,
        mesh_instance: &Gd<godot::classes::MeshInstance3D>,
    ) -> NodePerfCounts {
        NodePerfCounts::from_subchunk_state(
            self.subchunk_needs_collision(key),
            self.gpu_terrain_visible_render_active() && self.subchunk_needs_shadow_proxy(key),
            mesh_instance.is_visible(),
            mesh_instance.get_cast_shadows_setting(),
            count_static_body_children(mesh_instance),
        )
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

    fn update_gpu_native_shadow_resources(&mut self) {
        let gpu_visible = self.gpu_terrain_visible_render_active();
        let mode = gpu_terrain_shadow_proxy_mode();
        let scene_shadow_radius = self.terrain_shadow_proxy_chunk_distance();
        self.gpu_native_shadow_resources.sync(
            gpu_terrain_native_shadow_active(),
            gpu_visible,
            mode,
            scene_shadow_radius,
        );
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
        terrain_shadow_path_decision(
            gpu_visible,
            mode,
            radius,
            gpu_terrain_native_shadow_active(),
        )
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
        let gpu_visible_render_active = self.gpu_terrain_visible_render_active();
        let Some(refresh_reason) = mesh_queue_reason_after_gpu_attach(gpu_visible_render_active)
        else {
            return;
        };
        let loaded_chunks = chunks_to_refresh_after_gpu_attach(
            self.chunk_blocks.keys().copied(),
            gpu_visible_render_active,
        );
        for (chunk_x, chunk_z) in loaded_chunks {
            self.enqueue_chunk_subchunks_for_reason(chunk_x, chunk_z, refresh_reason);
        }
    }

    fn enqueue_chunk_subchunks_for_reason(
        &mut self,
        chunk_x: i32,
        chunk_z: i32,
        reason: MeshQueueReason,
    ) {
        match reason {
            MeshQueueReason::GeometryChanged => self.enqueue_chunk_subchunks(chunk_x, chunk_z),
            MeshQueueReason::ProxyRefresh => self.enqueue_proxy_refresh_subchunks(chunk_x, chunk_z),
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

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum MeshQueueReason {
    ProxyRefresh,
    GeometryChanged,
}

impl MeshQueueReason {
    fn merged_with(self, other: Self) -> Self {
        if self == Self::GeometryChanged || other == Self::GeometryChanged {
            Self::GeometryChanged
        } else {
            Self::ProxyRefresh
        }
    }

    fn as_str(self) -> &'static str {
        match self {
            Self::ProxyRefresh => "proxy_refresh",
            Self::GeometryChanged => "geometry",
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum ProxyRefreshQueueAction {
    BuildMesh,
    RemoveCpuNode,
    ReuseCpuProxy,
}

fn proxy_refresh_queue_action(
    gpu_visible_render_active: bool,
    existing_gpu_slot: bool,
    needs_cpu_proxy: bool,
    existing_payload: Option<TerrainCpuProxyMeshPayload>,
    desired_payload: TerrainCpuProxyMeshPayload,
) -> ProxyRefreshQueueAction {
    if !gpu_visible_render_active || !existing_gpu_slot {
        return ProxyRefreshQueueAction::BuildMesh;
    }
    if !needs_cpu_proxy {
        return ProxyRefreshQueueAction::RemoveCpuNode;
    }
    if existing_payload.is_some_and(|payload| payload.can_satisfy(desired_payload)) {
        return ProxyRefreshQueueAction::ReuseCpuProxy;
    }

    ProxyRefreshQueueAction::BuildMesh
}

#[allow(dead_code)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum CollisionRefreshResult {
    MissingMesh,
    SkippedEmpty,
    Unchanged,
    Rebuilt,
}

#[derive(Clone, Copy, Debug, Default)]
struct CollisionRefreshFrame {
    rebuilt: usize,
    work_ms: f64,
}

#[derive(Clone, Copy, Debug, Default)]
struct MeshQueueFrame {
    work_ms: f64,
    gpu_uploads: usize,
    gpu_upload_bytes: usize,
}

impl MeshQueueFrame {
    fn record_mesh_job(&mut self, job: MeshJobResult) {
        self.work_ms += job.work_ms;
        self.gpu_uploads += job.gpu_uploads;
        self.gpu_upload_bytes += job.gpu_upload_bytes;
    }
}

#[derive(Clone, Copy, Debug, Default)]
struct MeshJobResult {
    work_ms: f64,
    gpu_uploads: usize,
    gpu_upload_bytes: usize,
}

impl MeshJobResult {
    fn new(work_ms: f64, gpu_uploads: usize, gpu_upload_bytes: usize) -> Self {
        Self {
            work_ms,
            gpu_uploads,
            gpu_upload_bytes,
        }
    }

    fn elapsed(start: Instant) -> Self {
        Self::new(elapsed_ms(start), 0, 0)
    }
}

struct SubchunkMeshData {
    vertices: PackedVector3Array,
    normals: PackedVector3Array,
    uvs: PackedVector2Array,
    indices: PackedInt32Array,
    timing: meshing::MeshTiming,
    reported_vertices: usize,
}

#[derive(Clone, Copy, Debug)]
struct GpuUploadResult {
    state: TerrainGpuUploadState,
    uploads: usize,
    bytes: usize,
    ms: f64,
}

#[derive(Clone, Copy, Debug)]
struct CollisionRefreshRecord {
    result: CollisionRefreshResult,
    work_ms: f64,
}

impl CollisionRefreshRecord {
    fn new(result: CollisionRefreshResult, start: Instant) -> Self {
        Self {
            result,
            work_ms: elapsed_ms(start),
        }
    }
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
struct CollisionRefreshBatch {
    checked: usize,
    skipped_empty: usize,
    missing_meshes: usize,
    unchanged: usize,
    rebuilt: usize,
}

impl CollisionRefreshBatch {
    fn record(&mut self, result: CollisionRefreshResult) {
        self.checked += 1;
        match result {
            CollisionRefreshResult::MissingMesh => self.missing_meshes += 1,
            CollisionRefreshResult::SkippedEmpty => self.skipped_empty += 1,
            CollisionRefreshResult::Unchanged => self.unchanged += 1,
            CollisionRefreshResult::Rebuilt => self.rebuilt += 1,
        }
    }
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
struct ChunkDirtyBounds {
    min_x: usize,
    min_y: usize,
    min_z: usize,
    max_x: usize,
    max_y: usize,
    max_z: usize,
}

impl ChunkDirtyBounds {
    fn include(&mut self, x: usize, y: usize, z: usize, initialized: bool) {
        if !initialized {
            self.min_x = x;
            self.min_y = y;
            self.min_z = z;
            self.max_x = x;
            self.max_y = y;
            self.max_z = z;
            return;
        }

        self.min_x = self.min_x.min(x);
        self.min_y = self.min_y.min(y);
        self.min_z = self.min_z.min(z);
        self.max_x = self.max_x.max(x);
        self.max_y = self.max_y.max(y);
        self.max_z = self.max_z.max(z);
    }
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
struct ChunkDirtyUpdate {
    changed_blocks: usize,
    changed_subchunk_mask: u32,
    rebuild_subchunk_mask: u32,
    edge_mask: u8,
    bounds: Option<ChunkDirtyBounds>,
}

fn should_upload_gpu_subchunk_for_queue_reason(
    reason: MeshQueueReason,
    existing_gpu_slot: bool,
) -> bool {
    matches!(reason, MeshQueueReason::GeometryChanged) || !existing_gpu_slot
}

fn pop_next_mesh_queue_key(
    queue: &mut VecDeque<SubchunkKey>,
    current_player_chunk: Option<(i32, i32)>,
) -> Option<SubchunkKey> {
    let Some(center) = current_player_chunk else {
        return queue.pop_front();
    };

    let best_idx = queue
        .iter()
        .enumerate()
        .min_by_key(|(idx, key)| (subchunk_chunk_distance_sq(**key, center), *idx))
        .map(|(idx, _)| idx)?;
    queue.remove(best_idx)
}

fn should_process_mesh_queue_after_collision_refresh(collision_rebuilds: usize) -> bool {
    collision_rebuilds == 0
}

fn elapsed_ms(start: Instant) -> f64 {
    start.elapsed().as_secs_f64() * 1000.0
}

fn subchunk_chunk_distance_sq(key: SubchunkKey, center: (i32, i32)) -> i64 {
    let dx = i64::from(key.chunk_x - center.0);
    let dz = i64::from(key.chunk_z - center.1);
    dx * dx + dz * dz
}

#[derive(Default)]
struct PerfStats {
    mesh_queue_depth: usize,
    max_mesh_queue_depth: usize,
    mesh_queue_enqueues: u64,
    mesh_queue_geometry_enqueues: u64,
    mesh_queue_proxy_refresh_enqueues: u64,
    mesh_queue_duplicate_enqueues: u64,
    mesh_queue_geometry_duplicate_enqueues: u64,
    mesh_queue_proxy_refresh_duplicate_enqueues: u64,
    mesh_queue_drained: u64,
    mesh_queue_geometry_drained: u64,
    mesh_queue_proxy_refresh_drained: u64,
    mesh_queue_stale_drops: u64,
    mesh_queue_missing_chunk_drops: u64,
    last_mesh_queue_drained: usize,
    last_mesh_queue_geometry_drained: usize,
    last_mesh_queue_proxy_refresh_drained: usize,
    last_mesh_queue_stale_drops: usize,
    last_mesh_queue_missing_chunk_drops: usize,
    mesh_jobs_completed: u64,
    last_mesh_ms: f64,
    avg_mesh_ms: f64,
    max_mesh_ms: f64,
    max_mesh_reason: Option<MeshQueueReason>,
    max_mesh_cpu_proxy_mesh: bool,
    max_mesh_compact_shadow_proxy_mesh: bool,
    max_mesh_compact_collision_proxy_mesh: bool,
    max_mesh_collision_bodies: i32,
    max_mesh_vertices: usize,
    max_mesh_reported_vertices: usize,
    max_mesh_job_phase: TerrainMeshPhaseTiming,
    max_array_mesh_reason: Option<MeshQueueReason>,
    max_array_mesh_cpu_proxy_mesh: bool,
    max_array_mesh_compact_shadow_proxy_mesh: bool,
    max_array_mesh_compact_collision_proxy_mesh: bool,
    max_array_mesh_collision_bodies: i32,
    max_array_mesh_vertices: usize,
    max_array_mesh_reported_vertices: usize,
    max_array_mesh_job_phase: TerrainMeshPhaseTiming,
    last_collision_ms: f64,
    avg_collision_ms: f64,
    max_collision_ms: f64,
    collision_refresh_checked: u64,
    collision_refresh_skipped_empty: u64,
    collision_refresh_missing_meshes: u64,
    collision_refresh_unchanged: u64,
    collision_refresh_rebuilt: u64,
    collision_refresh_queue_depth: usize,
    max_collision_refresh_queue_depth: usize,
    collision_refresh_queue_enqueues: u64,
    collision_refresh_queue_duplicate_enqueues: u64,
    collision_refresh_queue_drained: u64,
    collision_refresh_queue_stale_drops: u64,
    collision_refresh_queue_missing_chunk_drops: u64,
    last_collision_refresh_checked: usize,
    last_collision_refresh_skipped_empty: usize,
    last_collision_refresh_missing_meshes: usize,
    last_collision_refresh_unchanged: usize,
    last_collision_refresh_rebuilt: usize,
    last_collision_refresh_queue_drained: usize,
    last_collision_refresh_queue_stale_drops: usize,
    last_collision_refresh_queue_missing_chunk_drops: usize,
    terrain_queue_work_frames: u64,
    last_terrain_queue_work_ms: f64,
    avg_terrain_queue_work_ms: f64,
    max_terrain_queue_work_ms: f64,
    max_terrain_queue_mesh_work_ms: f64,
    max_terrain_queue_collision_work_ms: f64,
    last_terrain_queue_gpu_uploads: usize,
    avg_terrain_queue_gpu_uploads: f64,
    max_terrain_queue_gpu_uploads: usize,
    last_terrain_queue_gpu_upload_bytes: usize,
    avg_terrain_queue_gpu_upload_bytes: f64,
    max_terrain_queue_gpu_upload_bytes: usize,
    last_collision_refresh_phase: CollisionRefreshPhaseTiming,
    max_collision_refresh_phase: CollisionRefreshPhaseTiming,
    last_vertices: usize,
    last_normals: usize,
    last_reported_vertices: usize,
    total_vertices: usize,
    total_normals: usize,
    collision_bodies: i32,
    node_counts: NodePerfCounts,
    chunk_bytes_loaded: usize,
    chunk_initial_loads: u64,
    chunk_replacement_updates: u64,
    startup_chunk_packet_ms: f64,
    startup_packet_read_work_ms: f64,
    startup_packet_decode_work_ms: f64,
    startup_packet_reader_elapsed_ms: f64,
    startup_packet_queue_lag_ms: f64,
    startup_chunk_decode_work_ms: f64,
    startup_chunk_inserted_ms: f64,
    startup_chunk_loaded_ms: f64,
    startup_mesh_queued_ms: f64,
    startup_mesh_dispatched_ms: f64,
    startup_first_mesh_ms: f64,
    startup_first_mesh_work_ms: f64,
    startup_first_mesh_phase: TerrainMeshPhaseTiming,
    startup_first_mesh_collision_work_ms: f64,
    startup_collision_ms: f64,
    startup_player_spawn_ms: f64,
    dirty_chunk_updates: u64,
    dirty_block_changes: u64,
    dirty_changed_subchunks: u64,
    dirty_rebuild_subchunks: u64,
    dirty_edge_chunk_updates: u64,
    dirty_edge_neighbor_refresh_chunks: u64,
    dirty_edge_neighbor_refresh_subchunks: u64,
    dirty_partial_chunk_updates: u64,
    dirty_partial_subchunks: u64,
    dirty_partial_saved_subchunks: u64,
    last_dirty_edge_neighbor_refresh_chunks: usize,
    last_dirty_edge_neighbor_refresh_subchunks: usize,
    last_dirty_partial_subchunks: usize,
    last_dirty_partial_saved_subchunks: usize,
    last_dirty_block_changes: usize,
    last_dirty_changed_subchunks: usize,
    last_dirty_rebuild_subchunks: usize,
    last_dirty_changed_subchunk_mask: u32,
    last_dirty_rebuild_subchunk_mask: u32,
    last_dirty_edge_mask: u8,
    last_dirty_bounds: Option<ChunkDirtyBounds>,
    last_prepare_ms: f64,
    last_submit_ms: f64,
    last_sync_ms: f64,
    last_readback_ms: f64,
    last_parse_ms: f64,
    last_mesh_phase: TerrainMeshPhaseTiming,
    avg_mesh_phase: TerrainMeshPhaseTiming,
    max_mesh_phase: TerrainMeshPhaseTiming,
    cpu_proxy_meshes_built: u64,
    compact_shadow_proxy_meshes_built: u64,
    compact_shadow_proxy_normals_saved: usize,
    compact_collision_proxy_meshes_built: u64,
    compact_collision_proxy_normals_saved: usize,
    cpu_proxy_refreshes_reused: u64,
}

struct MeshRecord {
    vertices: usize,
    normals: usize,
    reported_vertices: usize,
    reason: MeshQueueReason,
    cpu_proxy_mesh: bool,
    compact_shadow_proxy_mesh: bool,
    compact_collision_proxy_mesh: bool,
    mesh_ms: f64,
    timing: meshing::MeshTiming,
    phase_timing: TerrainMeshPhaseTiming,
    collision_ms: f64,
    collision_faces: usize,
    direct_collision_faces: bool,
    collision_bodies: i32,
    node_counts: NodePerfCounts,
}

#[cfg(test)]
fn test_mesh_record(
    vertices: usize,
    normals: usize,
    reported_vertices: usize,
    reason: MeshQueueReason,
    cpu_proxy_mesh: bool,
    compact_shadow_proxy_mesh: bool,
    compact_collision_proxy_mesh: bool,
    mesh_ms: f64,
    phase_timing: TerrainMeshPhaseTiming,
    collision_bodies: i32,
) -> MeshRecord {
    MeshRecord {
        vertices,
        normals,
        reported_vertices,
        reason,
        cpu_proxy_mesh,
        compact_shadow_proxy_mesh,
        compact_collision_proxy_mesh,
        mesh_ms,
        timing: meshing::MeshTiming::default(),
        phase_timing,
        collision_ms: 0.0,
        collision_faces: 0,
        direct_collision_faces: false,
        collision_bodies,
        node_counts: NodePerfCounts::default(),
    }
}

#[derive(Clone, Copy)]
enum CollisionPerfSource {
    MeshBuild,
    RefreshQueue,
}

struct CollisionPerfRecord {
    ms: f64,
    source: CollisionPerfSource,
    reason: Option<MeshQueueReason>,
    cpu_proxy_mesh: bool,
    compact_shadow_proxy_mesh: bool,
    compact_collision_proxy_mesh: bool,
    collision_bodies: i32,
    collision_faces: usize,
    vertices: usize,
    reported_vertices: usize,
    cached_faces: bool,
    phase_timing: TerrainMeshPhaseTiming,
    refresh_phase_timing: CollisionRefreshPhaseTiming,
}

#[derive(Clone, Copy, Default)]
struct TerrainMeshPhaseTiming {
    padded_ms: f64,
    packed_faces_ms: f64,
    gpu_upload_ms: f64,
    cpu_mesh_ms: f64,
    array_mesh_ms: f64,
    node_counts_ms: f64,
}

impl TerrainMeshPhaseTiming {
    fn record_average(&mut self, record: Self, n: f64) {
        self.padded_ms += (record.padded_ms - self.padded_ms) / n;
        self.packed_faces_ms += (record.packed_faces_ms - self.packed_faces_ms) / n;
        self.gpu_upload_ms += (record.gpu_upload_ms - self.gpu_upload_ms) / n;
        self.cpu_mesh_ms += (record.cpu_mesh_ms - self.cpu_mesh_ms) / n;
        self.array_mesh_ms += (record.array_mesh_ms - self.array_mesh_ms) / n;
        self.node_counts_ms += (record.node_counts_ms - self.node_counts_ms) / n;
    }

    fn record_max(&mut self, record: Self) {
        self.padded_ms = self.padded_ms.max(record.padded_ms);
        self.packed_faces_ms = self.packed_faces_ms.max(record.packed_faces_ms);
        self.gpu_upload_ms = self.gpu_upload_ms.max(record.gpu_upload_ms);
        self.cpu_mesh_ms = self.cpu_mesh_ms.max(record.cpu_mesh_ms);
        self.array_mesh_ms = self.array_mesh_ms.max(record.array_mesh_ms);
        self.node_counts_ms = self.node_counts_ms.max(record.node_counts_ms);
    }
}

#[derive(Clone, Copy, Default)]
struct CollisionRefreshPhaseTiming {
    faces_ms: f64,
    clear_ms: f64,
    create_ms: f64,
    count_ms: f64,
    node_counts_ms: f64,
}

impl CollisionRefreshPhaseTiming {
    fn record_max(&mut self, record: Self) {
        self.faces_ms = self.faces_ms.max(record.faces_ms);
        self.clear_ms = self.clear_ms.max(record.clear_ms);
        self.create_ms = self.create_ms.max(record.create_ms);
        self.count_ms = self.count_ms.max(record.count_ms);
        self.node_counts_ms = self.node_counts_ms.max(record.node_counts_ms);
    }
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
    fn from_subchunk_state(
        needs_collision: bool,
        needs_shadow: bool,
        visible: bool,
        shadow_setting: godot::classes::geometry_instance_3d::ShadowCastingSetting,
        collision_bodies: i32,
    ) -> Self {
        let mut counts = Self {
            rendered_submeshes: 1,
            total_collision_bodies: collision_bodies,
            ..Self::default()
        };
        counts.record_cpu_proxy_reasons(needs_collision, needs_shadow);
        counts.record_mesh_render_state_values(visible, shadow_setting);
        counts
    }

    fn add(&mut self, other: Self) {
        self.rendered_submeshes += other.rendered_submeshes;
        self.visible_submeshes += other.visible_submeshes;
        self.shadow_off_submeshes += other.shadow_off_submeshes;
        self.shadow_double_sided_submeshes += other.shadow_double_sided_submeshes;
        self.shadow_only_submeshes += other.shadow_only_submeshes;
        self.total_collision_bodies += other.total_collision_bodies;
        self.cpu_proxy_collision += other.cpu_proxy_collision;
        self.cpu_proxy_shadow += other.cpu_proxy_shadow;
        self.cpu_proxy_both += other.cpu_proxy_both;
        self.cpu_proxy_shadow_only += other.cpu_proxy_shadow_only;
    }

    fn subtract(&mut self, other: Self) {
        self.rendered_submeshes -= other.rendered_submeshes;
        self.visible_submeshes -= other.visible_submeshes;
        self.shadow_off_submeshes -= other.shadow_off_submeshes;
        self.shadow_double_sided_submeshes -= other.shadow_double_sided_submeshes;
        self.shadow_only_submeshes -= other.shadow_only_submeshes;
        self.total_collision_bodies -= other.total_collision_bodies;
        self.cpu_proxy_collision -= other.cpu_proxy_collision;
        self.cpu_proxy_shadow -= other.cpu_proxy_shadow;
        self.cpu_proxy_both -= other.cpu_proxy_both;
        self.cpu_proxy_shadow_only -= other.cpu_proxy_shadow_only;
    }

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
    fn record_startup_chunk_packet(
        &mut self,
        runtime_sec: f64,
        packet_read_ms: f64,
        packet_decode_ms: f64,
        packet_reader_elapsed_ms: f64,
        packet_queue_lag_ms: f64,
    ) {
        if self.startup_chunk_packet_ms == 0.0 {
            self.startup_chunk_packet_ms = runtime_sec.max(0.0) * 1000.0;
            self.startup_packet_read_work_ms = packet_read_ms.max(0.0);
            self.startup_packet_decode_work_ms = packet_decode_ms.max(0.0);
            self.startup_packet_reader_elapsed_ms = packet_reader_elapsed_ms.max(0.0);
            self.startup_packet_queue_lag_ms = packet_queue_lag_ms.max(0.0);
        }
    }

    fn record_startup_chunk_decoded(&mut self, runtime_sec: f64, chunk_decode_ms: f64) {
        if self.startup_chunk_decode_work_ms == 0.0 {
            self.startup_chunk_decode_work_ms = chunk_decode_ms.max(0.0);
            if self.startup_chunk_packet_ms == 0.0 {
                self.startup_chunk_packet_ms = runtime_sec.max(0.0) * 1000.0;
            }
        }
    }

    fn record_startup_chunk_inserted(&mut self, runtime_sec: f64) {
        if self.startup_chunk_inserted_ms == 0.0 {
            self.startup_chunk_inserted_ms = runtime_sec.max(0.0) * 1000.0;
        }
    }

    fn record_startup_chunk_loaded(&mut self, runtime_sec: f64) {
        if self.startup_chunk_loaded_ms == 0.0 {
            self.startup_chunk_loaded_ms = runtime_sec.max(0.0) * 1000.0;
        }
    }

    fn record_startup_mesh_queued(&mut self, runtime_sec: f64) {
        if self.startup_mesh_queued_ms == 0.0 {
            self.startup_mesh_queued_ms = runtime_sec.max(0.0) * 1000.0;
        }
    }

    fn record_startup_mesh_dispatched(&mut self, runtime_sec: f64) {
        if self.startup_mesh_dispatched_ms == 0.0 {
            self.startup_mesh_dispatched_ms = runtime_sec.max(0.0) * 1000.0;
        }
    }

    fn record_startup_first_mesh(&mut self, runtime_sec: f64, record: &MeshRecord) {
        if self.startup_first_mesh_ms == 0.0 {
            self.startup_first_mesh_ms = runtime_sec.max(0.0) * 1000.0;
            self.startup_first_mesh_work_ms = record.mesh_ms;
            self.startup_first_mesh_phase = record.phase_timing;
            self.startup_first_mesh_collision_work_ms = record.collision_ms;
        }
    }

    fn record_startup_collision_ready(&mut self, runtime_sec: f64, counts: NodePerfCounts) {
        if self.startup_collision_ms == 0.0 && counts.total_collision_bodies > 0 {
            self.startup_collision_ms = runtime_sec.max(0.0) * 1000.0;
        }
    }

    fn record_startup_player_spawn(&mut self, runtime_sec: f64) {
        if self.startup_player_spawn_ms == 0.0 {
            self.startup_player_spawn_ms = runtime_sec.max(0.0) * 1000.0;
        }
    }

    fn record_chunk_update(&mut self, dirty_update: Option<ChunkDirtyUpdate>) {
        if let Some(update) = dirty_update {
            self.chunk_replacement_updates += 1;
            self.last_dirty_block_changes = update.changed_blocks;
            self.last_dirty_changed_subchunk_mask = update.changed_subchunk_mask;
            self.last_dirty_rebuild_subchunk_mask = update.rebuild_subchunk_mask;
            self.last_dirty_changed_subchunks = update.changed_subchunk_mask.count_ones() as usize;
            self.last_dirty_rebuild_subchunks = update.rebuild_subchunk_mask.count_ones() as usize;
            self.last_dirty_edge_mask = update.edge_mask;
            self.last_dirty_bounds = update.bounds;

            if update.changed_blocks > 0 {
                self.dirty_chunk_updates += 1;
                self.dirty_block_changes = self
                    .dirty_block_changes
                    .saturating_add(update.changed_blocks as u64);
                self.dirty_changed_subchunks = self
                    .dirty_changed_subchunks
                    .saturating_add(self.last_dirty_changed_subchunks as u64);
                self.dirty_rebuild_subchunks = self
                    .dirty_rebuild_subchunks
                    .saturating_add(self.last_dirty_rebuild_subchunks as u64);
                if update.edge_mask != 0 {
                    self.dirty_edge_chunk_updates += 1;
                }
            }
        } else {
            self.chunk_initial_loads += 1;
        }
    }

    fn record_partial_dirty_enqueue(&mut self, subchunks: usize, saved_subchunks: usize) {
        self.dirty_partial_chunk_updates += 1;
        self.dirty_partial_subchunks = self
            .dirty_partial_subchunks
            .saturating_add(subchunks as u64);
        self.dirty_partial_saved_subchunks = self
            .dirty_partial_saved_subchunks
            .saturating_add(saved_subchunks as u64);
        self.last_dirty_partial_subchunks = subchunks;
        self.last_dirty_partial_saved_subchunks = saved_subchunks;
    }

    fn record_dirty_edge_neighbor_refresh(&mut self, chunks: usize, subchunks: usize) {
        self.dirty_edge_neighbor_refresh_chunks = self
            .dirty_edge_neighbor_refresh_chunks
            .saturating_add(chunks as u64);
        self.dirty_edge_neighbor_refresh_subchunks = self
            .dirty_edge_neighbor_refresh_subchunks
            .saturating_add(subchunks as u64);
        self.last_dirty_edge_neighbor_refresh_chunks = chunks;
        self.last_dirty_edge_neighbor_refresh_subchunks = subchunks;
    }

    fn record_mesh_queue_enqueue(&mut self, depth: usize, reason: MeshQueueReason, inserted: bool) {
        self.mesh_queue_depth = depth;
        self.max_mesh_queue_depth = self.max_mesh_queue_depth.max(depth);
        if inserted {
            self.mesh_queue_enqueues += 1;
            match reason {
                MeshQueueReason::GeometryChanged => self.mesh_queue_geometry_enqueues += 1,
                MeshQueueReason::ProxyRefresh => self.mesh_queue_proxy_refresh_enqueues += 1,
            }
        } else {
            self.mesh_queue_duplicate_enqueues += 1;
            match reason {
                MeshQueueReason::GeometryChanged => {
                    self.mesh_queue_geometry_duplicate_enqueues += 1;
                }
                MeshQueueReason::ProxyRefresh => {
                    self.mesh_queue_proxy_refresh_duplicate_enqueues += 1;
                }
            }
        }
    }

    fn record_mesh_queue_frame(
        &mut self,
        depth: usize,
        drained: usize,
        geometry_drained: usize,
        proxy_refresh_drained: usize,
        stale_drops: usize,
        missing_chunk_drops: usize,
    ) {
        self.mesh_queue_depth = depth;
        self.max_mesh_queue_depth = self.max_mesh_queue_depth.max(depth);
        self.mesh_queue_drained += drained as u64;
        self.mesh_queue_geometry_drained += geometry_drained as u64;
        self.mesh_queue_proxy_refresh_drained += proxy_refresh_drained as u64;
        self.mesh_queue_stale_drops += stale_drops as u64;
        self.mesh_queue_missing_chunk_drops += missing_chunk_drops as u64;
        self.last_mesh_queue_drained = drained;
        self.last_mesh_queue_geometry_drained = geometry_drained;
        self.last_mesh_queue_proxy_refresh_drained = proxy_refresh_drained;
        self.last_mesh_queue_stale_drops = stale_drops;
        self.last_mesh_queue_missing_chunk_drops = missing_chunk_drops;
    }

    fn record_collision_refresh(&mut self, batch: CollisionRefreshBatch) {
        self.collision_refresh_checked += batch.checked as u64;
        self.collision_refresh_skipped_empty += batch.skipped_empty as u64;
        self.collision_refresh_missing_meshes += batch.missing_meshes as u64;
        self.collision_refresh_unchanged += batch.unchanged as u64;
        self.collision_refresh_rebuilt += batch.rebuilt as u64;
        self.last_collision_refresh_checked = batch.checked;
        self.last_collision_refresh_skipped_empty = batch.skipped_empty;
        self.last_collision_refresh_missing_meshes = batch.missing_meshes;
        self.last_collision_refresh_unchanged = batch.unchanged;
        self.last_collision_refresh_rebuilt = batch.rebuilt;
    }

    fn record_collision_refresh_queue_enqueue(&mut self, depth: usize, inserted: bool) {
        self.collision_refresh_queue_depth = depth;
        self.max_collision_refresh_queue_depth = self.max_collision_refresh_queue_depth.max(depth);
        if inserted {
            self.collision_refresh_queue_enqueues += 1;
        } else {
            self.collision_refresh_queue_duplicate_enqueues += 1;
        }
    }

    fn record_collision_refresh_queue_frame(
        &mut self,
        depth: usize,
        drained: usize,
        stale_drops: usize,
        missing_chunk_drops: usize,
    ) {
        self.collision_refresh_queue_depth = depth;
        self.max_collision_refresh_queue_depth = self.max_collision_refresh_queue_depth.max(depth);
        self.collision_refresh_queue_drained += drained as u64;
        self.collision_refresh_queue_stale_drops += stale_drops as u64;
        self.collision_refresh_queue_missing_chunk_drops += missing_chunk_drops as u64;
        self.last_collision_refresh_queue_drained = drained;
        self.last_collision_refresh_queue_stale_drops = stale_drops;
        self.last_collision_refresh_queue_missing_chunk_drops = missing_chunk_drops;
    }

    fn record_terrain_queue_frame_work(
        &mut self,
        mesh_work_ms: f64,
        collision_work_ms: f64,
        gpu_uploads: usize,
        gpu_upload_bytes: usize,
    ) {
        let work_ms = mesh_work_ms + collision_work_ms;
        self.terrain_queue_work_frames += 1;
        let n = self.terrain_queue_work_frames as f64;
        self.last_terrain_queue_work_ms = work_ms;
        self.avg_terrain_queue_work_ms += (work_ms - self.avg_terrain_queue_work_ms) / n;
        self.last_terrain_queue_gpu_uploads = gpu_uploads;
        self.avg_terrain_queue_gpu_uploads +=
            (gpu_uploads as f64 - self.avg_terrain_queue_gpu_uploads) / n;
        self.max_terrain_queue_gpu_uploads = self.max_terrain_queue_gpu_uploads.max(gpu_uploads);
        self.last_terrain_queue_gpu_upload_bytes = gpu_upload_bytes;
        self.avg_terrain_queue_gpu_upload_bytes +=
            (gpu_upload_bytes as f64 - self.avg_terrain_queue_gpu_upload_bytes) / n;
        self.max_terrain_queue_gpu_upload_bytes = self
            .max_terrain_queue_gpu_upload_bytes
            .max(gpu_upload_bytes);
        if work_ms >= self.max_terrain_queue_work_ms {
            self.max_terrain_queue_work_ms = work_ms;
            self.max_terrain_queue_mesh_work_ms = mesh_work_ms;
            self.max_terrain_queue_collision_work_ms = collision_work_ms;
        }
    }

    fn record_collision_timing(&mut self, record: CollisionPerfRecord) {
        self.last_collision_ms = record.ms;
        self.max_collision_ms = self.max_collision_ms.max(record.ms);
        let n = (self.mesh_jobs_completed + self.collision_refresh_rebuilt).max(1) as f64;
        self.avg_collision_ms += (record.ms - self.avg_collision_ms) / n;
        if matches!(record.source, CollisionPerfSource::RefreshQueue) {
            self.last_collision_refresh_phase = record.refresh_phase_timing;
            self.max_collision_refresh_phase
                .record_max(record.refresh_phase_timing);
        }

        let _ = (
            record.source,
            record.reason,
            record.cpu_proxy_mesh,
            record.compact_shadow_proxy_mesh,
            record.compact_collision_proxy_mesh,
            record.collision_bodies,
            record.collision_faces,
            record.vertices,
            record.reported_vertices,
            record.cached_faces,
            record.phase_timing,
            record.refresh_phase_timing,
        );
    }

    fn record_mesh(&mut self, record: MeshRecord) {
        self.mesh_jobs_completed += 1;
        let n = self.mesh_jobs_completed as f64;
        self.last_mesh_ms = record.mesh_ms;
        self.avg_mesh_ms += (record.mesh_ms - self.avg_mesh_ms) / n;
        if record.mesh_ms >= self.max_mesh_ms {
            self.max_mesh_ms = record.mesh_ms;
            self.max_mesh_reason = Some(record.reason);
            self.max_mesh_cpu_proxy_mesh = record.cpu_proxy_mesh;
            self.max_mesh_compact_shadow_proxy_mesh = record.compact_shadow_proxy_mesh;
            self.max_mesh_compact_collision_proxy_mesh = record.compact_collision_proxy_mesh;
            self.max_mesh_collision_bodies = record.collision_bodies;
            self.max_mesh_vertices = record.vertices;
            self.max_mesh_reported_vertices = record.reported_vertices;
            self.max_mesh_job_phase = record.phase_timing;
        }
        if record.phase_timing.array_mesh_ms >= self.max_array_mesh_job_phase.array_mesh_ms {
            self.max_array_mesh_reason = Some(record.reason);
            self.max_array_mesh_cpu_proxy_mesh = record.cpu_proxy_mesh;
            self.max_array_mesh_compact_shadow_proxy_mesh = record.compact_shadow_proxy_mesh;
            self.max_array_mesh_compact_collision_proxy_mesh = record.compact_collision_proxy_mesh;
            self.max_array_mesh_collision_bodies = record.collision_bodies;
            self.max_array_mesh_vertices = record.vertices;
            self.max_array_mesh_reported_vertices = record.reported_vertices;
            self.max_array_mesh_job_phase = record.phase_timing;
        }
        self.record_collision_timing(CollisionPerfRecord {
            ms: record.collision_ms,
            source: CollisionPerfSource::MeshBuild,
            reason: Some(record.reason),
            cpu_proxy_mesh: record.cpu_proxy_mesh,
            compact_shadow_proxy_mesh: record.compact_shadow_proxy_mesh,
            compact_collision_proxy_mesh: record.compact_collision_proxy_mesh,
            collision_bodies: record.collision_bodies,
            collision_faces: record.collision_faces,
            vertices: record.vertices,
            reported_vertices: record.reported_vertices,
            cached_faces: record.direct_collision_faces,
            phase_timing: record.phase_timing,
            refresh_phase_timing: CollisionRefreshPhaseTiming::default(),
        });
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
        self.last_mesh_phase = record.phase_timing;
        self.avg_mesh_phase.record_average(record.phase_timing, n);
        self.max_mesh_phase.record_max(record.phase_timing);
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
const INITIAL_PLAYER_X: f32 = 16.0;
const INITIAL_PLAYER_Y: f32 = 68.0;
const INITIAL_PLAYER_Z: f32 = 16.0;
const DIRTY_EDGE_NEG_X: u8 = 1 << 0;
const DIRTY_EDGE_POS_X: u8 = 1 << 1;
const DIRTY_EDGE_NEG_Z: u8 = 1 << 2;
const DIRTY_EDGE_POS_Z: u8 = 1 << 3;
const PADDED_W: usize = 34;
const PADDED_H: usize = 34;
const PADDED_D: usize = 34;
const BLOCK_BYTES: usize = 2;
const SERIALIZED_CHUNK_BYTES: usize = CHUNK_W * CHUNK_H * CHUNK_D * BLOCK_BYTES;
const PADDED_BLOCK_BYTES: usize = PADDED_W * PADDED_H * PADDED_D * BLOCK_BYTES;
const CLIENT_KEEP_CHUNK_DISTANCE: i32 = 10;
const MAX_CLIENT_KEEP_CHUNK_DISTANCE: i32 = 16;
const CLIENT_CHUNK_UNLOAD_GRACE_SEC: f64 = 20.0;
const MAX_CLIENT_CHUNK_UNLOAD_GRACE_SEC: f64 = 120.0;
const COLLISION_CHUNK_DISTANCE: i32 = 1;
const DEFAULT_GPU_TERRAIN_SHADOW_PROXY_DISTANCE: f32 = 160.0;
const DEFAULT_GPU_TERRAIN_SHADOW_PROXY_CHUNK_DISTANCE: i32 = 5;
const MAX_MESH_JOBS_PER_FRAME: usize = 1;
const MAX_MESH_QUEUE_DRAINS_PER_FRAME: usize = 32;
const MAX_COLLISION_REFRESH_REBUILDS_PER_FRAME: usize = 1;
const MAX_COLLISION_REFRESH_DRAINS_PER_FRAME: usize = 32;
const GPU_TERRAIN_PROTOTYPE_STATS: bool = false;
const GPU_TERRAIN_PROTOTYPE_UPLOAD: bool = false;
const GPU_TERRAIN_PROTOTYPE_RENDER: bool = false;
const GPU_TERRAIN_RENDER_DEFAULT_ENABLED: bool = false;
const GPU_TERRAIN_STATS_ENV: &str = "RUMPELMC_GPU_TERRAIN_STATS";
const GPU_TERRAIN_UPLOAD_ENV: &str = "RUMPELMC_GPU_TERRAIN_UPLOAD";
const GPU_TERRAIN_RENDER_ENV: &str = "RUMPELMC_GPU_TERRAIN_RENDER";
const GPU_TERRAIN_PARTIAL_DIRTY_UPLOAD_ENV: &str = "RUMPELMC_GPU_TERRAIN_PARTIAL_DIRTY_UPLOAD";
const GPU_TERRAIN_PARTIAL_DIRTY_UPLOAD_DEFAULT_ENABLED: bool = true;
const CPU_ARRAY_MESH_PACKED_FACES_ENV: &str = "RUMPELMC_CPU_ARRAY_MESH_PACKED_FACES";
const CPU_ARRAY_MESH_PACKED_FACES_DEFAULT_ENABLED: bool = true;
const CLIENT_KEEP_CHUNK_DISTANCE_ENV: &str = "RUMPELMC_CLIENT_KEEP_CHUNK_DISTANCE";
const CLIENT_CHUNK_UNLOAD_GRACE_SEC_ENV: &str = "RUMPELMC_CLIENT_CHUNK_UNLOAD_GRACE_SEC";
const GPU_TERRAIN_SHADOW_PROXY_CHUNK_DISTANCE_ENV: &str =
    "RUMPELMC_GPU_TERRAIN_SHADOW_PROXY_CHUNK_DISTANCE";
const GPU_TERRAIN_SHADOW_PROXY_MODE_ENV: &str = "RUMPELMC_GPU_TERRAIN_SHADOW_PROXY_MODE";
const GPU_TERRAIN_SHADOW_PROXY_MESH_ENV: &str = "RUMPELMC_GPU_TERRAIN_SHADOW_PROXY_MESH";
const GPU_TERRAIN_NATIVE_SHADOW_ENV: &str = "RUMPELMC_GPU_TERRAIN_NATIVE_SHADOW";
const GPU_TERRAIN_NATIVE_SHADOW_IMPLEMENTED: bool = false;
const GPU_TERRAIN_NATIVE_SHADOW_MAP_SIZE_PX: u32 = 2048;
const GPU_TERRAIN_NATIVE_SHADOW_LAYERS: u32 = 1;
const GPU_TERRAIN_NATIVE_SHADOW_BYTES_PER_TEXEL: u32 = 4;
const GPU_TERRAIN_NATIVE_SHADOW_FORMAT: &str = "d32_sfloat";
const GPU_TERRAIN_NATIVE_SHADOW_USAGE: &str = "depth_stencil_attachment|sampling";
const GPU_TERRAIN_NATIVE_SHADOW_PASS_LOAD_OP: &str = "clear";
const GPU_TERRAIN_NATIVE_SHADOW_PASS_STORE_OP: &str = "store";
const GPU_TERRAIN_NATIVE_SHADOW_PASS_CLEAR_DEPTH_MILLI: u32 = 1000;
const GPU_TERRAIN_NATIVE_SHADOW_DEPTH_ATTACHMENT_STATUS: &str = "not_bound";
const GPU_TERRAIN_NATIVE_SHADOW_DEPTH_ATTACHMENT_BINDING_COUNT: u32 = 0;
const GPU_TERRAIN_NATIVE_SHADOW_DEPTH_ATTACHMENT_CLEAR_COUNT: u32 = 0;
const GPU_TERRAIN_NATIVE_SHADOW_RESOURCE_BARRIER_STATUS: &str = "not_issued";
const GPU_TERRAIN_NATIVE_SHADOW_RESOURCE_TRANSITION_COUNT: u32 = 0;
const GPU_TERRAIN_NATIVE_SHADOW_RESOURCE_BARRIER_ERROR_COUNT: u32 = 0;
const GPU_TERRAIN_NATIVE_SHADOW_FRAMEBUFFER_STATUS: &str = "not_created";
const GPU_TERRAIN_NATIVE_SHADOW_FRAMEBUFFER_RID_ALLOCATED: u32 = 0;
const GPU_TERRAIN_NATIVE_SHADOW_FRAMEBUFFER_ATTACHMENT_COUNT: u32 = 1;
const GPU_TERRAIN_NATIVE_SHADOW_FRAMEBUFFER_PASS_COMPAT_STATUS: &str = "not_validated";
const GPU_TERRAIN_NATIVE_SHADOW_FRAMEBUFFER_PASS_COMPAT_ERROR_COUNT: u32 = 0;
const GPU_TERRAIN_NATIVE_SHADOW_FRAMEBUFFER_DEPTH_ONLY_ENABLED: u32 = 1;
const GPU_TERRAIN_NATIVE_SHADOW_FRAMEBUFFER_COLOR_ATTACHMENT_COUNT: u32 = 0;
const GPU_TERRAIN_NATIVE_SHADOW_PASS_STATUS: &str = "descriptor_ready";
const GPU_TERRAIN_NATIVE_SHADOW_PASS_RID_ALLOCATED: u32 = 0;
const GPU_TERRAIN_NATIVE_SHADOW_PASS_SUBMIT_STATUS: &str = "not_submitted";
const GPU_TERRAIN_NATIVE_SHADOW_PASS_BEGIN_COUNT: u32 = 0;
const GPU_TERRAIN_NATIVE_SHADOW_PASS_END_COUNT: u32 = 0;
const GPU_TERRAIN_NATIVE_SHADOW_COMMAND_BUFFER_STATUS: &str = "not_recorded";
const GPU_TERRAIN_NATIVE_SHADOW_COMMAND_BUFFER_SUBMIT_COUNT: u32 = 0;
const GPU_TERRAIN_NATIVE_SHADOW_COMMAND_BUFFER_ERROR_COUNT: u32 = 0;
const GPU_TERRAIN_NATIVE_SHADOW_SAMPLER_FILTER: &str = "linear";
const GPU_TERRAIN_NATIVE_SHADOW_SAMPLER_ADDRESS: &str = "clamp_to_edge";
const GPU_TERRAIN_NATIVE_SHADOW_SAMPLER_COMPARE_OP: &str = "less_equal";
const GPU_TERRAIN_NATIVE_SHADOW_SAMPLER_COMPARE_ENABLED: u32 = 1;
const GPU_TERRAIN_NATIVE_SHADOW_DEPTH_BIAS_CONSTANT_MILLI: u32 = 2;
const GPU_TERRAIN_NATIVE_SHADOW_DEPTH_BIAS_SLOPE_MILLI: u32 = 1500;
const GPU_TERRAIN_NATIVE_SHADOW_DEPTH_BIAS_CLAMP_MILLI: u32 = 0;
const GPU_TERRAIN_NATIVE_SHADOW_VIEWPORT_X_PX: u32 = 0;
const GPU_TERRAIN_NATIVE_SHADOW_VIEWPORT_Y_PX: u32 = 0;
const GPU_TERRAIN_NATIVE_SHADOW_VIEWPORT_MIN_DEPTH_MILLI: u32 = 0;
const GPU_TERRAIN_NATIVE_SHADOW_VIEWPORT_MAX_DEPTH_MILLI: u32 = 1000;
const GPU_TERRAIN_NATIVE_SHADOW_PIPELINE_DEPTH_TEST_ENABLED: u32 = 1;
const GPU_TERRAIN_NATIVE_SHADOW_PIPELINE_DEPTH_WRITE_ENABLED: u32 = 1;
const GPU_TERRAIN_NATIVE_SHADOW_PIPELINE_CULL_MODE: &str = "back";
const GPU_TERRAIN_NATIVE_SHADOW_PIPELINE_FRONT_FACE: &str = "clockwise";
const GPU_TERRAIN_NATIVE_SHADOW_DRAW_SOURCE: &str = "packed_faces";
const GPU_TERRAIN_NATIVE_SHADOW_DRAW_PRIMITIVE: &str = "triangles";
const GPU_TERRAIN_NATIVE_SHADOW_DRAW_FACE_STRIDE_BYTES: u32 = 16;
const GPU_TERRAIN_NATIVE_SHADOW_DRAW_COMMAND_STRIDE_BYTES: u32 = 16;
const GPU_TERRAIN_NATIVE_SHADOW_DRAW_INDIRECT_ENABLED: u32 = 1;
const GPU_TERRAIN_NATIVE_SHADOW_DRAW_STATUS: &str = "not_submitted";
const GPU_TERRAIN_NATIVE_SHADOW_DRAW_CALL_COUNT: u32 = 0;
const GPU_TERRAIN_NATIVE_SHADOW_DRAW_FACE_COUNT: u32 = 0;
const GPU_TERRAIN_NATIVE_SHADOW_UNIFORM_SET_INDEX: u32 = 0;
const GPU_TERRAIN_NATIVE_SHADOW_FACE_BUFFER_BINDING: u32 = 0;
const GPU_TERRAIN_NATIVE_SHADOW_PUSH_CONSTANT_BYTES: u32 = 64;
const GPU_TERRAIN_NATIVE_SHADOW_TEXTURE_SAMPLING_ENABLED: u32 = 0;
const GPU_TERRAIN_NATIVE_SHADOW_SHADER_LANGUAGE: &str = "glsl";
const GPU_TERRAIN_NATIVE_SHADOW_SHADER_ENTRY: &str = "native_shadow_depth";
const GPU_TERRAIN_NATIVE_SHADOW_SHADER_DEPTH_OUTPUT: u32 = 1;
const GPU_TERRAIN_NATIVE_SHADOW_SHADER_COLOR_OUTPUT: u32 = 0;
const GPU_TERRAIN_NATIVE_SHADOW_SHADER_SOURCE_CONTRACT: &str =
    "native_shadow_depth:packed_faces:world_to_shadow:depth_only";
const GPU_TERRAIN_NATIVE_SHADOW_SHADER_MODULE_STATUS: &str = "source_ready";
const GPU_TERRAIN_NATIVE_SHADOW_SHADER_MODULE_RID_ALLOCATED: u32 = 0;
const GPU_TERRAIN_NATIVE_SHADOW_LIGHT_SOURCE: &str = "directional_light";
const GPU_TERRAIN_NATIVE_SHADOW_LIGHT_SPACE: &str = "world_to_shadow";
const GPU_TERRAIN_NATIVE_SHADOW_CASCADE_COUNT: u32 = 1;
const GPU_TERRAIN_NATIVE_SHADOW_LIGHT_MATRIX_BYTES: u32 = 64;
const GPU_TERRAIN_NATIVE_SHADOW_DEPTH_CLIP_SPACE: &str = "zero_to_one";
const GPU_TERRAIN_NATIVE_SHADOW_DEPTH_RANGE_SOURCE: &str = "scene_shadow_radius";
const GPU_TERRAIN_NATIVE_SHADOW_DEPTH_NEAR_MILLI: u32 = 100;
const GPU_TERRAIN_TRANSPARENT_ENV: &str = "RUMPELMC_GPU_TERRAIN_TRANSPARENT";
const GPU_TERRAIN_TRANSPARENT_FIXTURE_OVERLAY_ENV: &str =
    "RUMPELMC_GPU_TERRAIN_TRANSPARENT_FIXTURE_OVERLAY";
const GPU_TERRAIN_TRANSPARENT_IMPLEMENTED: bool = false;
const TRANSPARENT_FIXTURE_OVERLAY_ENTRIES: [TransparentFixtureOverlayEntry; 5] = [
    TransparentFixtureOverlayEntry::new("front_transparent", (0, 2, 0)),
    TransparentFixtureOverlayEntry::new("behind_wall_transparent", (0, 2, -2)),
    TransparentFixtureOverlayEntry::new("opaque_depth_occluder", (0, 2, -1)),
    TransparentFixtureOverlayEntry::new("adjacent_same_material_pair", (1, 2, 0)),
    TransparentFixtureOverlayEntry::new("collision_probe", (0, 1, 1)),
];
const FACE_LEFT: u32 = 0;
const FACE_RIGHT: u32 = 1;
const FACE_BOTTOM: u32 = 2;
const FACE_TOP: u32 = 3;
const FACE_BACK: u32 = 4;
const FACE_FRONT: u32 = 5;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
struct TransparentFixtureOverlayEntry {
    role: &'static str,
    block_offset: (i32, i32, i32),
}

impl TransparentFixtureOverlayEntry {
    const fn new(role: &'static str, block_offset: (i32, i32, i32)) -> Self {
        Self { role, block_offset }
    }
}

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

fn rust_ext_build_profile() -> &'static str {
    if cfg!(debug_assertions) {
        "debug"
    } else {
        "release"
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

fn client_keep_chunk_distance() -> i32 {
    static KEEP_DISTANCE: OnceLock<i32> = OnceLock::new();
    *KEEP_DISTANCE.get_or_init(|| {
        std::env::var(CLIENT_KEEP_CHUNK_DISTANCE_ENV)
            .ok()
            .and_then(|value| value.trim().parse::<i32>().ok())
            .filter(|radius| *radius > 0)
            .map(|radius| radius.clamp(1, MAX_CLIENT_KEEP_CHUNK_DISTANCE))
            .unwrap_or(CLIENT_KEEP_CHUNK_DISTANCE)
    })
}

fn initial_player_position() -> Vector3 {
    Vector3::new(INITIAL_PLAYER_X, INITIAL_PLAYER_Y, INITIAL_PLAYER_Z)
}

fn initial_player_chunk() -> (i32, i32) {
    chunk_coord_for_position(INITIAL_PLAYER_X, INITIAL_PLAYER_Z)
}

fn initial_spawn_mesh_subchunks() -> [SubchunkKey; 2] {
    let (chunk_x, chunk_z) = initial_player_chunk();
    [
        SubchunkKey {
            chunk_x,
            sub_y: 0,
            chunk_z,
        },
        SubchunkKey {
            chunk_x,
            sub_y: 1,
            chunk_z,
        },
    ]
}

fn player_chunk_queue_hint(current_player_chunk: Option<(i32, i32)>) -> Option<(i32, i32)> {
    current_player_chunk.or_else(|| Some(initial_player_chunk()))
}

fn client_chunk_unload_grace_sec() -> f64 {
    static UNLOAD_GRACE: OnceLock<f64> = OnceLock::new();
    *UNLOAD_GRACE.get_or_init(|| {
        std::env::var(CLIENT_CHUNK_UNLOAD_GRACE_SEC_ENV)
            .ok()
            .and_then(|value| value.trim().parse::<f64>().ok())
            .filter(|seconds| seconds.is_finite() && *seconds >= 0.0)
            .map(|seconds| seconds.clamp(0.0, MAX_CLIENT_CHUNK_UNLOAD_GRACE_SEC))
            .unwrap_or(CLIENT_CHUNK_UNLOAD_GRACE_SEC)
    })
}

fn should_unload_chunk(
    coord: (i32, i32),
    center: (i32, i32),
    keep_distance: i32,
    last_seen_sec: Option<f64>,
    now_sec: f64,
    grace_sec: f64,
) -> bool {
    if chunk_within_radius(coord, center, keep_distance) {
        return false;
    }
    if grace_sec <= 0.0 {
        return true;
    }

    let Some(last_seen_sec) = last_seen_sec else {
        return true;
    };
    let elapsed_sec = now_sec - last_seen_sec;
    elapsed_sec.is_finite() && elapsed_sec >= grace_sec
}

fn subchunk_needs_collision(key: SubchunkKey, current_player_chunk: Option<(i32, i32)>) -> bool {
    let Some(center) = current_player_chunk else {
        let center = initial_player_chunk();
        return (key.chunk_x, key.chunk_z) == center;
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
        let center = initial_player_chunk();
        return (key.chunk_x, key.chunk_z) == center;
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
    let current_role = chunk_cpu_proxy_role(coord, current, shadow_radius);
    let Some(previous) = previous else {
        return current_role != ChunkCpuProxyRole::None;
    };

    chunk_cpu_proxy_role(coord, previous, shadow_radius) != current_role
}

fn chunk_needs_collision_refresh(
    coord: (i32, i32),
    previous: Option<(i32, i32)>,
    current: (i32, i32),
) -> bool {
    let was_near =
        previous.is_some_and(|prev| chunk_within_radius(coord, prev, COLLISION_CHUNK_DISTANCE));
    let is_near = chunk_within_radius(coord, current, COLLISION_CHUNK_DISTANCE);
    was_near || is_near
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum ChunkCpuProxyRole {
    None,
    Collision,
    Shadow,
    CollisionAndShadow,
}

fn chunk_cpu_proxy_role(
    coord: (i32, i32),
    center: (i32, i32),
    shadow_radius: i32,
) -> ChunkCpuProxyRole {
    let needs_collision = chunk_within_radius(coord, center, COLLISION_CHUNK_DISTANCE);
    let needs_shadow = shadow_radius > 0 && chunk_within_radius(coord, center, shadow_radius);
    match (needs_collision, needs_shadow) {
        (false, false) => ChunkCpuProxyRole::None,
        (true, false) => ChunkCpuProxyRole::Collision,
        (false, true) => ChunkCpuProxyRole::Shadow,
        (true, true) => ChunkCpuProxyRole::CollisionAndShadow,
    }
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

fn mesh_queue_reason_after_gpu_attach(gpu_visible_render_active: bool) -> Option<MeshQueueReason> {
    gpu_visible_render_active.then_some(MeshQueueReason::ProxyRefresh)
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

fn gpu_terrain_partial_dirty_upload_enabled() -> bool {
    static ENABLED: OnceLock<bool> = OnceLock::new();
    *ENABLED.get_or_init(|| {
        gpu_terrain_partial_dirty_upload_decision(env_flag_state(
            GPU_TERRAIN_PARTIAL_DIRTY_UPLOAD_ENV,
        ))
    })
}

fn gpu_terrain_partial_dirty_upload_decision(env_state: Option<bool>) -> bool {
    env_state.unwrap_or(GPU_TERRAIN_PARTIAL_DIRTY_UPLOAD_DEFAULT_ENABLED)
}

fn cpu_array_mesh_packed_faces_enabled() -> bool {
    static ENABLED: OnceLock<bool> = OnceLock::new();
    *ENABLED.get_or_init(|| {
        cpu_array_mesh_packed_faces_decision(env_flag_state(CPU_ARRAY_MESH_PACKED_FACES_ENV))
    })
}

fn cpu_array_mesh_packed_faces_decision(env_state: Option<bool>) -> bool {
    env_state.unwrap_or(CPU_ARRAY_MESH_PACKED_FACES_DEFAULT_ENABLED)
}

fn gpu_terrain_visible_render_active_decision(
    render_enabled: bool,
    compositor_attached: bool,
    visible_render_confirmed: bool,
) -> bool {
    render_enabled && compositor_attached && visible_render_confirmed
}

fn gpu_terrain_native_shadow_active() -> bool {
    static ENABLED: OnceLock<bool> = OnceLock::new();
    *ENABLED.get_or_init(|| {
        gpu_terrain_native_shadow_active_decision(
            gpu_terrain_native_shadow_requested(),
            GPU_TERRAIN_NATIVE_SHADOW_IMPLEMENTED,
        )
    })
}

fn gpu_terrain_native_shadow_requested() -> bool {
    static REQUESTED: OnceLock<bool> = OnceLock::new();
    *REQUESTED.get_or_init(|| {
        gpu_terrain_native_shadow_requested_decision(env_flag_state(GPU_TERRAIN_NATIVE_SHADOW_ENV))
    })
}

fn gpu_terrain_native_shadow_requested_decision(env_state: Option<bool>) -> bool {
    env_state.unwrap_or(false)
}

fn gpu_terrain_native_shadow_active_decision(requested: bool, implementation_ready: bool) -> bool {
    requested && implementation_ready
}

fn gpu_terrain_native_shadow_fallback_decision(requested: bool, active: bool) -> bool {
    requested && !active
}

fn native_shadow_contract_checksum(input: &str) -> u32 {
    input.as_bytes().iter().fold(2_166_136_261, |hash, byte| {
        (hash ^ u32::from(*byte)).wrapping_mul(16_777_619)
    })
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
struct GpuNativeShadowResourceDescriptor {
    map_size_px: u32,
    width_px: u32,
    height_px: u32,
    layers: u32,
    shadow_radius_chunks: i32,
    bytes_per_texel: u32,
    estimated_bytes: u64,
    format: &'static str,
    usage: &'static str,
    pass_load_op: &'static str,
    pass_store_op: &'static str,
    pass_clear_depth_milli: u32,
    depth_attachment_status: &'static str,
    depth_attachment_binding_count: u32,
    depth_attachment_clear_count: u32,
    resource_barrier_status: &'static str,
    resource_transition_count: u32,
    resource_barrier_error_count: u32,
    framebuffer_status: &'static str,
    framebuffer_rid_allocated: u32,
    framebuffer_attachment_count: u32,
    framebuffer_pass_compat_status: &'static str,
    framebuffer_pass_compat_error_count: u32,
    framebuffer_depth_only_enabled: u32,
    framebuffer_color_attachment_count: u32,
    pass_status: &'static str,
    pass_rid_allocated: u32,
    pass_submit_status: &'static str,
    pass_begin_count: u32,
    pass_end_count: u32,
    command_buffer_status: &'static str,
    command_buffer_submit_count: u32,
    command_buffer_error_count: u32,
    sampler_filter: &'static str,
    sampler_address: &'static str,
    sampler_compare_op: &'static str,
    sampler_compare_enabled: u32,
    depth_bias_constant_milli: u32,
    depth_bias_slope_milli: u32,
    depth_bias_clamp_milli: u32,
    viewport_x_px: u32,
    viewport_y_px: u32,
    viewport_width_px: u32,
    viewport_height_px: u32,
    viewport_min_depth_milli: u32,
    viewport_max_depth_milli: u32,
    pipeline_depth_test_enabled: u32,
    pipeline_depth_write_enabled: u32,
    pipeline_cull_mode: &'static str,
    pipeline_front_face: &'static str,
    draw_source: &'static str,
    draw_primitive: &'static str,
    draw_face_stride_bytes: u32,
    draw_command_stride_bytes: u32,
    draw_indirect_enabled: u32,
    draw_status: &'static str,
    draw_call_count: u32,
    draw_face_count: u32,
    uniform_set_index: u32,
    face_buffer_binding: u32,
    push_constant_bytes: u32,
    texture_sampling_enabled: u32,
    shader_language: &'static str,
    shader_entry: &'static str,
    shader_depth_output_enabled: u32,
    shader_color_output_enabled: u32,
    shader_source_bytes: u32,
    shader_source_checksum: u32,
    shader_module_status: &'static str,
    shader_module_rid_allocated: u32,
    light_source: &'static str,
    light_space: &'static str,
    cascade_count: u32,
    light_matrix_bytes: u32,
    depth_clip_space: &'static str,
    depth_range_source: &'static str,
    depth_near_milli: u32,
    depth_far_chunks: i32,
}

impl GpuNativeShadowResourceDescriptor {
    fn new(shadow_radius_chunks: i32) -> Self {
        let map_size_px = GPU_TERRAIN_NATIVE_SHADOW_MAP_SIZE_PX;
        let width_px = map_size_px;
        let height_px = map_size_px;
        let layers = GPU_TERRAIN_NATIVE_SHADOW_LAYERS;
        let bytes_per_texel = GPU_TERRAIN_NATIVE_SHADOW_BYTES_PER_TEXEL;
        Self {
            map_size_px,
            width_px,
            height_px,
            layers,
            shadow_radius_chunks,
            bytes_per_texel,
            estimated_bytes: u64::from(width_px)
                * u64::from(height_px)
                * u64::from(layers)
                * u64::from(bytes_per_texel),
            format: GPU_TERRAIN_NATIVE_SHADOW_FORMAT,
            usage: GPU_TERRAIN_NATIVE_SHADOW_USAGE,
            pass_load_op: GPU_TERRAIN_NATIVE_SHADOW_PASS_LOAD_OP,
            pass_store_op: GPU_TERRAIN_NATIVE_SHADOW_PASS_STORE_OP,
            pass_clear_depth_milli: GPU_TERRAIN_NATIVE_SHADOW_PASS_CLEAR_DEPTH_MILLI,
            depth_attachment_status: GPU_TERRAIN_NATIVE_SHADOW_DEPTH_ATTACHMENT_STATUS,
            depth_attachment_binding_count:
                GPU_TERRAIN_NATIVE_SHADOW_DEPTH_ATTACHMENT_BINDING_COUNT,
            depth_attachment_clear_count: GPU_TERRAIN_NATIVE_SHADOW_DEPTH_ATTACHMENT_CLEAR_COUNT,
            resource_barrier_status: GPU_TERRAIN_NATIVE_SHADOW_RESOURCE_BARRIER_STATUS,
            resource_transition_count: GPU_TERRAIN_NATIVE_SHADOW_RESOURCE_TRANSITION_COUNT,
            resource_barrier_error_count: GPU_TERRAIN_NATIVE_SHADOW_RESOURCE_BARRIER_ERROR_COUNT,
            framebuffer_status: GPU_TERRAIN_NATIVE_SHADOW_FRAMEBUFFER_STATUS,
            framebuffer_rid_allocated: GPU_TERRAIN_NATIVE_SHADOW_FRAMEBUFFER_RID_ALLOCATED,
            framebuffer_attachment_count: GPU_TERRAIN_NATIVE_SHADOW_FRAMEBUFFER_ATTACHMENT_COUNT,
            framebuffer_pass_compat_status:
                GPU_TERRAIN_NATIVE_SHADOW_FRAMEBUFFER_PASS_COMPAT_STATUS,
            framebuffer_pass_compat_error_count:
                GPU_TERRAIN_NATIVE_SHADOW_FRAMEBUFFER_PASS_COMPAT_ERROR_COUNT,
            framebuffer_depth_only_enabled:
                GPU_TERRAIN_NATIVE_SHADOW_FRAMEBUFFER_DEPTH_ONLY_ENABLED,
            framebuffer_color_attachment_count:
                GPU_TERRAIN_NATIVE_SHADOW_FRAMEBUFFER_COLOR_ATTACHMENT_COUNT,
            pass_status: GPU_TERRAIN_NATIVE_SHADOW_PASS_STATUS,
            pass_rid_allocated: GPU_TERRAIN_NATIVE_SHADOW_PASS_RID_ALLOCATED,
            pass_submit_status: GPU_TERRAIN_NATIVE_SHADOW_PASS_SUBMIT_STATUS,
            pass_begin_count: GPU_TERRAIN_NATIVE_SHADOW_PASS_BEGIN_COUNT,
            pass_end_count: GPU_TERRAIN_NATIVE_SHADOW_PASS_END_COUNT,
            command_buffer_status: GPU_TERRAIN_NATIVE_SHADOW_COMMAND_BUFFER_STATUS,
            command_buffer_submit_count: GPU_TERRAIN_NATIVE_SHADOW_COMMAND_BUFFER_SUBMIT_COUNT,
            command_buffer_error_count: GPU_TERRAIN_NATIVE_SHADOW_COMMAND_BUFFER_ERROR_COUNT,
            sampler_filter: GPU_TERRAIN_NATIVE_SHADOW_SAMPLER_FILTER,
            sampler_address: GPU_TERRAIN_NATIVE_SHADOW_SAMPLER_ADDRESS,
            sampler_compare_op: GPU_TERRAIN_NATIVE_SHADOW_SAMPLER_COMPARE_OP,
            sampler_compare_enabled: GPU_TERRAIN_NATIVE_SHADOW_SAMPLER_COMPARE_ENABLED,
            depth_bias_constant_milli: GPU_TERRAIN_NATIVE_SHADOW_DEPTH_BIAS_CONSTANT_MILLI,
            depth_bias_slope_milli: GPU_TERRAIN_NATIVE_SHADOW_DEPTH_BIAS_SLOPE_MILLI,
            depth_bias_clamp_milli: GPU_TERRAIN_NATIVE_SHADOW_DEPTH_BIAS_CLAMP_MILLI,
            viewport_x_px: GPU_TERRAIN_NATIVE_SHADOW_VIEWPORT_X_PX,
            viewport_y_px: GPU_TERRAIN_NATIVE_SHADOW_VIEWPORT_Y_PX,
            viewport_width_px: width_px,
            viewport_height_px: height_px,
            viewport_min_depth_milli: GPU_TERRAIN_NATIVE_SHADOW_VIEWPORT_MIN_DEPTH_MILLI,
            viewport_max_depth_milli: GPU_TERRAIN_NATIVE_SHADOW_VIEWPORT_MAX_DEPTH_MILLI,
            pipeline_depth_test_enabled: GPU_TERRAIN_NATIVE_SHADOW_PIPELINE_DEPTH_TEST_ENABLED,
            pipeline_depth_write_enabled: GPU_TERRAIN_NATIVE_SHADOW_PIPELINE_DEPTH_WRITE_ENABLED,
            pipeline_cull_mode: GPU_TERRAIN_NATIVE_SHADOW_PIPELINE_CULL_MODE,
            pipeline_front_face: GPU_TERRAIN_NATIVE_SHADOW_PIPELINE_FRONT_FACE,
            draw_source: GPU_TERRAIN_NATIVE_SHADOW_DRAW_SOURCE,
            draw_primitive: GPU_TERRAIN_NATIVE_SHADOW_DRAW_PRIMITIVE,
            draw_face_stride_bytes: GPU_TERRAIN_NATIVE_SHADOW_DRAW_FACE_STRIDE_BYTES,
            draw_command_stride_bytes: GPU_TERRAIN_NATIVE_SHADOW_DRAW_COMMAND_STRIDE_BYTES,
            draw_indirect_enabled: GPU_TERRAIN_NATIVE_SHADOW_DRAW_INDIRECT_ENABLED,
            draw_status: GPU_TERRAIN_NATIVE_SHADOW_DRAW_STATUS,
            draw_call_count: GPU_TERRAIN_NATIVE_SHADOW_DRAW_CALL_COUNT,
            draw_face_count: GPU_TERRAIN_NATIVE_SHADOW_DRAW_FACE_COUNT,
            uniform_set_index: GPU_TERRAIN_NATIVE_SHADOW_UNIFORM_SET_INDEX,
            face_buffer_binding: GPU_TERRAIN_NATIVE_SHADOW_FACE_BUFFER_BINDING,
            push_constant_bytes: GPU_TERRAIN_NATIVE_SHADOW_PUSH_CONSTANT_BYTES,
            texture_sampling_enabled: GPU_TERRAIN_NATIVE_SHADOW_TEXTURE_SAMPLING_ENABLED,
            shader_language: GPU_TERRAIN_NATIVE_SHADOW_SHADER_LANGUAGE,
            shader_entry: GPU_TERRAIN_NATIVE_SHADOW_SHADER_ENTRY,
            shader_depth_output_enabled: GPU_TERRAIN_NATIVE_SHADOW_SHADER_DEPTH_OUTPUT,
            shader_color_output_enabled: GPU_TERRAIN_NATIVE_SHADOW_SHADER_COLOR_OUTPUT,
            shader_source_bytes: GPU_TERRAIN_NATIVE_SHADOW_SHADER_SOURCE_CONTRACT.len() as u32,
            shader_source_checksum: native_shadow_contract_checksum(
                GPU_TERRAIN_NATIVE_SHADOW_SHADER_SOURCE_CONTRACT,
            ),
            shader_module_status: GPU_TERRAIN_NATIVE_SHADOW_SHADER_MODULE_STATUS,
            shader_module_rid_allocated: GPU_TERRAIN_NATIVE_SHADOW_SHADER_MODULE_RID_ALLOCATED,
            light_source: GPU_TERRAIN_NATIVE_SHADOW_LIGHT_SOURCE,
            light_space: GPU_TERRAIN_NATIVE_SHADOW_LIGHT_SPACE,
            cascade_count: GPU_TERRAIN_NATIVE_SHADOW_CASCADE_COUNT,
            light_matrix_bytes: GPU_TERRAIN_NATIVE_SHADOW_LIGHT_MATRIX_BYTES,
            depth_clip_space: GPU_TERRAIN_NATIVE_SHADOW_DEPTH_CLIP_SPACE,
            depth_range_source: GPU_TERRAIN_NATIVE_SHADOW_DEPTH_RANGE_SOURCE,
            depth_near_milli: GPU_TERRAIN_NATIVE_SHADOW_DEPTH_NEAR_MILLI,
            depth_far_chunks: shadow_radius_chunks,
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum GpuNativeShadowResourceAction {
    Disabled,
    Create,
    Reuse,
    Replace,
    Release,
}

#[derive(Debug, Default)]
struct GpuNativeShadowResources {
    descriptor: Option<GpuNativeShadowResourceDescriptor>,
    creates: u64,
    reuses: u64,
    replaces: u64,
    releases: u64,
}

impl GpuNativeShadowResources {
    fn sync(
        &mut self,
        native_shadow_active: bool,
        gpu_visible_render_active: bool,
        mode: GpuTerrainShadowProxyMode,
        scene_shadow_radius: i32,
    ) -> GpuNativeShadowResourceAction {
        let desired = gpu_native_shadow_resource_descriptor(
            native_shadow_active,
            gpu_visible_render_active,
            mode,
            scene_shadow_radius,
        );
        match (self.descriptor, desired) {
            (None, None) => GpuNativeShadowResourceAction::Disabled,
            (Some(_), None) => {
                self.descriptor = None;
                self.releases += 1;
                GpuNativeShadowResourceAction::Release
            }
            (None, Some(descriptor)) => {
                self.descriptor = Some(descriptor);
                self.creates += 1;
                GpuNativeShadowResourceAction::Create
            }
            (Some(current), Some(descriptor)) if current == descriptor => {
                self.reuses += 1;
                GpuNativeShadowResourceAction::Reuse
            }
            (Some(_), Some(descriptor)) => {
                self.descriptor = Some(descriptor);
                self.replaces += 1;
                GpuNativeShadowResourceAction::Replace
            }
        }
    }

    fn release(&mut self) -> GpuNativeShadowResourceAction {
        if self.descriptor.take().is_some() {
            self.releases += 1;
            GpuNativeShadowResourceAction::Release
        } else {
            GpuNativeShadowResourceAction::Disabled
        }
    }

    fn status_label(&self) -> &'static str {
        if self.descriptor.is_some() {
            "ready"
        } else {
            "disabled"
        }
    }

    fn shadow_radius_chunks(&self) -> i32 {
        self.descriptor
            .map(|descriptor| descriptor.shadow_radius_chunks)
            .unwrap_or(0)
    }

    fn map_size_px(&self) -> u32 {
        self.descriptor
            .map(|descriptor| descriptor.map_size_px)
            .unwrap_or(0)
    }

    fn width_px(&self) -> u32 {
        self.descriptor
            .map(|descriptor| descriptor.width_px)
            .unwrap_or(0)
    }

    fn height_px(&self) -> u32 {
        self.descriptor
            .map(|descriptor| descriptor.height_px)
            .unwrap_or(0)
    }

    fn layers(&self) -> u32 {
        self.descriptor
            .map(|descriptor| descriptor.layers)
            .unwrap_or(0)
    }

    fn bytes_per_texel(&self) -> u32 {
        self.descriptor
            .map(|descriptor| descriptor.bytes_per_texel)
            .unwrap_or(0)
    }

    fn estimated_bytes(&self) -> u64 {
        self.descriptor
            .map(|descriptor| descriptor.estimated_bytes)
            .unwrap_or(0)
    }

    fn format_label(&self) -> &'static str {
        self.descriptor
            .map(|descriptor| descriptor.format)
            .unwrap_or("none")
    }

    fn usage_label(&self) -> &'static str {
        self.descriptor
            .map(|descriptor| descriptor.usage)
            .unwrap_or("none")
    }

    fn pass_load_op_label(&self) -> &'static str {
        self.descriptor
            .map(|descriptor| descriptor.pass_load_op)
            .unwrap_or("none")
    }

    fn pass_store_op_label(&self) -> &'static str {
        self.descriptor
            .map(|descriptor| descriptor.pass_store_op)
            .unwrap_or("none")
    }

    fn pass_clear_depth_milli(&self) -> u32 {
        self.descriptor
            .map(|descriptor| descriptor.pass_clear_depth_milli)
            .unwrap_or(0)
    }

    fn depth_attachment_status_label(&self) -> &'static str {
        self.descriptor
            .map(|descriptor| descriptor.depth_attachment_status)
            .unwrap_or("none")
    }

    fn depth_attachment_binding_count(&self) -> u32 {
        self.descriptor
            .map(|descriptor| descriptor.depth_attachment_binding_count)
            .unwrap_or(0)
    }

    fn depth_attachment_clear_count(&self) -> u32 {
        self.descriptor
            .map(|descriptor| descriptor.depth_attachment_clear_count)
            .unwrap_or(0)
    }

    fn resource_barrier_status_label(&self) -> &'static str {
        self.descriptor
            .map(|descriptor| descriptor.resource_barrier_status)
            .unwrap_or("none")
    }

    fn resource_transition_count(&self) -> u32 {
        self.descriptor
            .map(|descriptor| descriptor.resource_transition_count)
            .unwrap_or(0)
    }

    fn resource_barrier_error_count(&self) -> u32 {
        self.descriptor
            .map(|descriptor| descriptor.resource_barrier_error_count)
            .unwrap_or(0)
    }

    fn framebuffer_status_label(&self) -> &'static str {
        self.descriptor
            .map(|descriptor| descriptor.framebuffer_status)
            .unwrap_or("none")
    }

    fn framebuffer_rid_allocated(&self) -> u32 {
        self.descriptor
            .map(|descriptor| descriptor.framebuffer_rid_allocated)
            .unwrap_or(0)
    }

    fn framebuffer_attachment_count(&self) -> u32 {
        self.descriptor
            .map(|descriptor| descriptor.framebuffer_attachment_count)
            .unwrap_or(0)
    }

    fn framebuffer_pass_compat_status_label(&self) -> &'static str {
        self.descriptor
            .map(|descriptor| descriptor.framebuffer_pass_compat_status)
            .unwrap_or("none")
    }

    fn framebuffer_pass_compat_error_count(&self) -> u32 {
        self.descriptor
            .map(|descriptor| descriptor.framebuffer_pass_compat_error_count)
            .unwrap_or(0)
    }

    fn framebuffer_depth_only_enabled(&self) -> u32 {
        self.descriptor
            .map(|descriptor| descriptor.framebuffer_depth_only_enabled)
            .unwrap_or(0)
    }

    fn framebuffer_color_attachment_count(&self) -> u32 {
        self.descriptor
            .map(|descriptor| descriptor.framebuffer_color_attachment_count)
            .unwrap_or(0)
    }

    fn pass_status_label(&self) -> &'static str {
        self.descriptor
            .map(|descriptor| descriptor.pass_status)
            .unwrap_or("none")
    }

    fn pass_rid_allocated(&self) -> u32 {
        self.descriptor
            .map(|descriptor| descriptor.pass_rid_allocated)
            .unwrap_or(0)
    }

    fn pass_submit_status_label(&self) -> &'static str {
        self.descriptor
            .map(|descriptor| descriptor.pass_submit_status)
            .unwrap_or("none")
    }

    fn pass_begin_count(&self) -> u32 {
        self.descriptor
            .map(|descriptor| descriptor.pass_begin_count)
            .unwrap_or(0)
    }

    fn pass_end_count(&self) -> u32 {
        self.descriptor
            .map(|descriptor| descriptor.pass_end_count)
            .unwrap_or(0)
    }

    fn command_buffer_status_label(&self) -> &'static str {
        self.descriptor
            .map(|descriptor| descriptor.command_buffer_status)
            .unwrap_or("none")
    }

    fn command_buffer_submit_count(&self) -> u32 {
        self.descriptor
            .map(|descriptor| descriptor.command_buffer_submit_count)
            .unwrap_or(0)
    }

    fn command_buffer_error_count(&self) -> u32 {
        self.descriptor
            .map(|descriptor| descriptor.command_buffer_error_count)
            .unwrap_or(0)
    }

    fn sampler_filter_label(&self) -> &'static str {
        self.descriptor
            .map(|descriptor| descriptor.sampler_filter)
            .unwrap_or("none")
    }

    fn sampler_address_label(&self) -> &'static str {
        self.descriptor
            .map(|descriptor| descriptor.sampler_address)
            .unwrap_or("none")
    }

    fn sampler_compare_op_label(&self) -> &'static str {
        self.descriptor
            .map(|descriptor| descriptor.sampler_compare_op)
            .unwrap_or("none")
    }

    fn sampler_compare_enabled(&self) -> u32 {
        self.descriptor
            .map(|descriptor| descriptor.sampler_compare_enabled)
            .unwrap_or(0)
    }

    fn depth_bias_constant_milli(&self) -> u32 {
        self.descriptor
            .map(|descriptor| descriptor.depth_bias_constant_milli)
            .unwrap_or(0)
    }

    fn depth_bias_slope_milli(&self) -> u32 {
        self.descriptor
            .map(|descriptor| descriptor.depth_bias_slope_milli)
            .unwrap_or(0)
    }

    fn depth_bias_clamp_milli(&self) -> u32 {
        self.descriptor
            .map(|descriptor| descriptor.depth_bias_clamp_milli)
            .unwrap_or(0)
    }

    fn viewport_x_px(&self) -> u32 {
        self.descriptor
            .map(|descriptor| descriptor.viewport_x_px)
            .unwrap_or(0)
    }

    fn viewport_y_px(&self) -> u32 {
        self.descriptor
            .map(|descriptor| descriptor.viewport_y_px)
            .unwrap_or(0)
    }

    fn viewport_width_px(&self) -> u32 {
        self.descriptor
            .map(|descriptor| descriptor.viewport_width_px)
            .unwrap_or(0)
    }

    fn viewport_height_px(&self) -> u32 {
        self.descriptor
            .map(|descriptor| descriptor.viewport_height_px)
            .unwrap_or(0)
    }

    fn viewport_min_depth_milli(&self) -> u32 {
        self.descriptor
            .map(|descriptor| descriptor.viewport_min_depth_milli)
            .unwrap_or(0)
    }

    fn viewport_max_depth_milli(&self) -> u32 {
        self.descriptor
            .map(|descriptor| descriptor.viewport_max_depth_milli)
            .unwrap_or(0)
    }

    fn pipeline_depth_test_enabled(&self) -> u32 {
        self.descriptor
            .map(|descriptor| descriptor.pipeline_depth_test_enabled)
            .unwrap_or(0)
    }

    fn pipeline_depth_write_enabled(&self) -> u32 {
        self.descriptor
            .map(|descriptor| descriptor.pipeline_depth_write_enabled)
            .unwrap_or(0)
    }

    fn pipeline_cull_mode_label(&self) -> &'static str {
        self.descriptor
            .map(|descriptor| descriptor.pipeline_cull_mode)
            .unwrap_or("none")
    }

    fn pipeline_front_face_label(&self) -> &'static str {
        self.descriptor
            .map(|descriptor| descriptor.pipeline_front_face)
            .unwrap_or("none")
    }

    fn draw_source_label(&self) -> &'static str {
        self.descriptor
            .map(|descriptor| descriptor.draw_source)
            .unwrap_or("none")
    }

    fn draw_primitive_label(&self) -> &'static str {
        self.descriptor
            .map(|descriptor| descriptor.draw_primitive)
            .unwrap_or("none")
    }

    fn draw_face_stride_bytes(&self) -> u32 {
        self.descriptor
            .map(|descriptor| descriptor.draw_face_stride_bytes)
            .unwrap_or(0)
    }

    fn draw_command_stride_bytes(&self) -> u32 {
        self.descriptor
            .map(|descriptor| descriptor.draw_command_stride_bytes)
            .unwrap_or(0)
    }

    fn draw_indirect_enabled(&self) -> u32 {
        self.descriptor
            .map(|descriptor| descriptor.draw_indirect_enabled)
            .unwrap_or(0)
    }

    fn draw_status_label(&self) -> &'static str {
        self.descriptor
            .map(|descriptor| descriptor.draw_status)
            .unwrap_or("none")
    }

    fn draw_call_count(&self) -> u32 {
        self.descriptor
            .map(|descriptor| descriptor.draw_call_count)
            .unwrap_or(0)
    }

    fn draw_face_count(&self) -> u32 {
        self.descriptor
            .map(|descriptor| descriptor.draw_face_count)
            .unwrap_or(0)
    }

    fn uniform_set_index(&self) -> u32 {
        self.descriptor
            .map(|descriptor| descriptor.uniform_set_index)
            .unwrap_or(0)
    }

    fn face_buffer_binding(&self) -> u32 {
        self.descriptor
            .map(|descriptor| descriptor.face_buffer_binding)
            .unwrap_or(0)
    }

    fn push_constant_bytes(&self) -> u32 {
        self.descriptor
            .map(|descriptor| descriptor.push_constant_bytes)
            .unwrap_or(0)
    }

    fn texture_sampling_enabled(&self) -> u32 {
        self.descriptor
            .map(|descriptor| descriptor.texture_sampling_enabled)
            .unwrap_or(0)
    }

    fn shader_language_label(&self) -> &'static str {
        self.descriptor
            .map(|descriptor| descriptor.shader_language)
            .unwrap_or("none")
    }

    fn shader_entry_label(&self) -> &'static str {
        self.descriptor
            .map(|descriptor| descriptor.shader_entry)
            .unwrap_or("none")
    }

    fn shader_depth_output_enabled(&self) -> u32 {
        self.descriptor
            .map(|descriptor| descriptor.shader_depth_output_enabled)
            .unwrap_or(0)
    }

    fn shader_color_output_enabled(&self) -> u32 {
        self.descriptor
            .map(|descriptor| descriptor.shader_color_output_enabled)
            .unwrap_or(0)
    }

    fn shader_source_bytes(&self) -> u32 {
        self.descriptor
            .map(|descriptor| descriptor.shader_source_bytes)
            .unwrap_or(0)
    }

    fn shader_source_checksum(&self) -> u32 {
        self.descriptor
            .map(|descriptor| descriptor.shader_source_checksum)
            .unwrap_or(0)
    }

    fn shader_module_status_label(&self) -> &'static str {
        self.descriptor
            .map(|descriptor| descriptor.shader_module_status)
            .unwrap_or("none")
    }

    fn shader_module_rid_allocated(&self) -> u32 {
        self.descriptor
            .map(|descriptor| descriptor.shader_module_rid_allocated)
            .unwrap_or(0)
    }

    fn light_source_label(&self) -> &'static str {
        self.descriptor
            .map(|descriptor| descriptor.light_source)
            .unwrap_or("none")
    }

    fn light_space_label(&self) -> &'static str {
        self.descriptor
            .map(|descriptor| descriptor.light_space)
            .unwrap_or("none")
    }

    fn cascade_count(&self) -> u32 {
        self.descriptor
            .map(|descriptor| descriptor.cascade_count)
            .unwrap_or(0)
    }

    fn light_matrix_bytes(&self) -> u32 {
        self.descriptor
            .map(|descriptor| descriptor.light_matrix_bytes)
            .unwrap_or(0)
    }

    fn depth_clip_space_label(&self) -> &'static str {
        self.descriptor
            .map(|descriptor| descriptor.depth_clip_space)
            .unwrap_or("none")
    }

    fn depth_range_source_label(&self) -> &'static str {
        self.descriptor
            .map(|descriptor| descriptor.depth_range_source)
            .unwrap_or("none")
    }

    fn depth_near_milli(&self) -> u32 {
        self.descriptor
            .map(|descriptor| descriptor.depth_near_milli)
            .unwrap_or(0)
    }

    fn depth_far_chunks(&self) -> i32 {
        self.descriptor
            .map(|descriptor| descriptor.depth_far_chunks)
            .unwrap_or(0)
    }

    fn coverage_counts(
        &self,
        chunk_non_empty_subchunks: &HashMap<(i32, i32), u32>,
    ) -> (usize, usize) {
        if self.descriptor.is_none() {
            return (0, 0);
        }

        let covered_chunks = chunk_non_empty_subchunks
            .values()
            .filter(|mask| **mask != 0)
            .count();
        let covered_subchunks = chunk_non_empty_subchunks
            .values()
            .map(|mask| mask.count_ones() as usize)
            .sum();
        (covered_chunks, covered_subchunks)
    }
}

fn gpu_native_shadow_resource_descriptor(
    native_shadow_active: bool,
    gpu_visible_render_active: bool,
    mode: GpuTerrainShadowProxyMode,
    scene_shadow_radius: i32,
) -> Option<GpuNativeShadowResourceDescriptor> {
    if !native_shadow_active
        || !gpu_visible_render_active
        || !mode.keeps_shadow_proxies()
        || scene_shadow_radius <= 0
    {
        return None;
    }

    Some(GpuNativeShadowResourceDescriptor::new(scene_shadow_radius))
}

fn gpu_terrain_transparent_active() -> bool {
    static ENABLED: OnceLock<bool> = OnceLock::new();
    *ENABLED.get_or_init(|| {
        gpu_terrain_transparent_active_decision(
            gpu_terrain_transparent_requested(),
            GPU_TERRAIN_TRANSPARENT_IMPLEMENTED,
        )
    })
}

fn gpu_terrain_transparent_requested() -> bool {
    static REQUESTED: OnceLock<bool> = OnceLock::new();
    *REQUESTED.get_or_init(|| {
        gpu_terrain_transparent_requested_decision(env_flag_state(GPU_TERRAIN_TRANSPARENT_ENV))
    })
}

fn gpu_terrain_transparent_requested_decision(env_state: Option<bool>) -> bool {
    env_state.unwrap_or(false)
}

fn gpu_terrain_transparent_active_decision(requested: bool, implementation_ready: bool) -> bool {
    requested && implementation_ready
}

fn gpu_terrain_transparent_fallback_decision(requested: bool, active: bool) -> bool {
    requested && !active
}

fn gpu_terrain_transparent_fixture_overlay_requested() -> bool {
    static REQUESTED: OnceLock<bool> = OnceLock::new();
    *REQUESTED.get_or_init(|| {
        gpu_terrain_transparent_fixture_overlay_requested_decision(env_flag_state(
            GPU_TERRAIN_TRANSPARENT_FIXTURE_OVERLAY_ENV,
        ))
    })
}

fn gpu_terrain_transparent_fixture_overlay_requested_decision(env_state: Option<bool>) -> bool {
    env_state.unwrap_or(false)
}

fn gpu_terrain_transparent_fixture_overlay_active_decision(
    requested: bool,
    transparent_active: bool,
) -> bool {
    requested && transparent_active
}

fn gpu_terrain_transparent_fixture_overlay_fallback_decision(
    requested: bool,
    active: bool,
) -> bool {
    requested && !active
}

fn gpu_terrain_transparent_fixture_overlay_metadata_counts(requested: bool) -> (u32, u32) {
    if requested {
        let count = TRANSPARENT_FIXTURE_OVERLAY_ENTRIES.len() as u32;
        (count, count)
    } else {
        (0, 0)
    }
}

fn gpu_terrain_transparent_workload_counts(_active: bool) -> (u32, u32, u32, u32) {
    (0, 0, 0, 0)
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
    let keep_distance = client_keep_chunk_distance();
    if let Some(radius) = override_radius {
        return radius.clamp(0, keep_distance);
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
    ((shadow_distance / CHUNK_SIZE).ceil() as i32 + 1).clamp(0, client_keep_chunk_distance())
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
    GpuNativeShadow,
    SceneShadowsDisabled,
    DiagnosticNoShadowProxy,
}

impl GpuTerrainShadowPath {
    fn as_str(self) -> &'static str {
        match self {
            Self::ArrayMesh => "arraymesh",
            Self::GodotProxy => "godot_proxy",
            Self::GpuNativeShadow => "gpu_native_shadow",
            Self::SceneShadowsDisabled => "scene_shadows_disabled",
            Self::DiagnosticNoShadowProxy => "diagnostic_no_shadow_proxy",
        }
    }
}

fn terrain_shadow_path_decision(
    gpu_visible_render_active: bool,
    mode: GpuTerrainShadowProxyMode,
    shadow_proxy_radius: i32,
    native_shadow_active: bool,
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
    if native_shadow_active {
        return GpuTerrainShadowPath::GpuNativeShadow;
    }

    GpuTerrainShadowPath::GodotProxy
}

fn terrain_godot_shadow_proxy_chunk_distance(
    mode: GpuTerrainShadowProxyMode,
    scene_shadow_radius: i32,
    native_shadow_active: bool,
) -> i32 {
    if native_shadow_active || !mode.keeps_shadow_proxies() {
        return 0;
    }

    scene_shadow_radius.max(0)
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

    fn compacts_shadow_proxy_mesh(self, cpu_proxy_mesh: bool, needs_shadow_proxy: bool) -> bool {
        matches!(self, Self::Compact) && cpu_proxy_mesh && needs_shadow_proxy
    }
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
struct TerrainCpuProxyMeshPayload {
    compact_shadow_proxy_mesh: bool,
    compact_collision_proxy_mesh: bool,
    indexed_shadow_proxy_mesh: bool,
}

impl TerrainCpuProxyMeshPayload {
    fn uses_compact_mesh(self) -> bool {
        self.compact_shadow_proxy_mesh || self.compact_collision_proxy_mesh
    }

    fn uses_indexed_shadow_mesh(self) -> bool {
        self.indexed_shadow_proxy_mesh
    }

    fn can_satisfy(self, desired: Self) -> bool {
        self == desired
            || !self.uses_compact_mesh()
            // Collision-only compact proxies are meshless, and indexed shadow-only proxies do
            // not carry triangle-list faces for collision refreshes.
            || (self.compact_shadow_proxy_mesh
                && !self.indexed_shadow_proxy_mesh
                && desired.uses_compact_mesh())
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

    let compact_shadow_proxy_mesh =
        shadow_mesh_mode.compacts_shadow_proxy_mesh(cpu_proxy_mesh, needs_shadow_proxy);
    TerrainCpuProxyMeshPayload {
        compact_shadow_proxy_mesh,
        compact_collision_proxy_mesh: needs_collision && !needs_shadow_proxy,
        indexed_shadow_proxy_mesh: compact_shadow_proxy_mesh && !needs_collision,
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
    let row_bytes = width * BLOCK_BYTES;
    for dy in 0..height {
        for dz in 0..depth {
            let sy = source_region.y.start + dy;
            let sz = source_region.z.start + dz;
            let py = padded_start.1 + dy;
            let pz = padded_start.2 + dz;
            let src = chunk_byte_index(source_region.x.start, sy, sz);
            let dst = padded_byte_index(padded_start.0, py, pz);
            let copy_bytes = bounded_block_copy_bytes(
                row_bytes,
                source.len().saturating_sub(src),
                padded.len().saturating_sub(dst),
            );
            if copy_bytes > 0 {
                padded[dst..dst + copy_bytes].copy_from_slice(&source[src..src + copy_bytes]);
            }
        }
    }
}

fn bounded_block_copy_bytes(
    requested: usize,
    source_remaining: usize,
    target_remaining: usize,
) -> usize {
    requested.min(source_remaining).min(target_remaining) / BLOCK_BYTES * BLOCK_BYTES
}

fn compute_chunk_non_empty_subchunks(blocks: &[u8]) -> u32 {
    let mut mask = 0u32;
    for sub_y in 0..SUBCHUNKS_PER_CHUNK {
        if chunk_subchunk_has_blocks(blocks, sub_y) {
            mask |= 1u32 << sub_y;
        }
    }
    mask
}

fn neighbor_geometry_refresh_mask(previous_mask: u32, current_mask: u32) -> u32 {
    (previous_mask | current_mask) & valid_subchunk_mask()
}

fn dirty_partial_subchunk_count(
    previous_non_empty_mask: u32,
    current_non_empty_mask: u32,
    rebuild_mask: u32,
) -> usize {
    ((previous_non_empty_mask | current_non_empty_mask) & rebuild_mask & valid_subchunk_mask())
        .count_ones() as usize
}

fn dirty_partial_saved_subchunks(
    previous_non_empty_mask: u32,
    current_non_empty_mask: u32,
    rebuild_mask: u32,
) -> usize {
    let full_mask = (previous_non_empty_mask | current_non_empty_mask) & valid_subchunk_mask();
    let partial_count = (full_mask & rebuild_mask).count_ones() as usize;
    (full_mask.count_ones() as usize).saturating_sub(partial_count)
}

fn dirty_edge_neighbors(chunk_x: i32, chunk_z: i32, edge_mask: u8) -> Vec<(i32, i32)> {
    let mut neighbors = Vec::new();
    if edge_mask & DIRTY_EDGE_NEG_X != 0 {
        neighbors.push((chunk_x - 1, chunk_z));
    }
    if edge_mask & DIRTY_EDGE_POS_X != 0 {
        neighbors.push((chunk_x + 1, chunk_z));
    }
    if edge_mask & DIRTY_EDGE_NEG_Z != 0 {
        neighbors.push((chunk_x, chunk_z - 1));
    }
    if edge_mask & DIRTY_EDGE_POS_Z != 0 {
        neighbors.push((chunk_x, chunk_z + 1));
    }
    neighbors
}

fn chunk_update_needs_geometry_refresh(dirty_update: Option<ChunkDirtyUpdate>) -> bool {
    match dirty_update {
        Some(update) => update.changed_blocks > 0,
        None => true,
    }
}

fn decode_chunk_blocks(chunk: &crate::api::ChunkData) -> Result<Vec<u8>, String> {
    match crate::api::ChunkEncoding::try_from(chunk.encoding) {
        Ok(crate::api::ChunkEncoding::Raw) => {
            if chunk.blocks.len() != SERIALIZED_CHUNK_BYTES {
                return Err(format!(
                    "raw chunk has {} bytes, expected {}",
                    chunk.blocks.len(),
                    SERIALIZED_CHUNK_BYTES
                ));
            }
            Ok(chunk.blocks.clone())
        }
        Ok(crate::api::ChunkEncoding::Rle) => {
            let uncompressed_size = chunk.uncompressed_size as usize;
            if uncompressed_size != SERIALIZED_CHUNK_BYTES {
                return Err(format!(
                    "RLE chunk uncompressed_size={} expected {}",
                    uncompressed_size, SERIALIZED_CHUNK_BYTES
                ));
            }
            decode_serialized_chunk_rle(&chunk.blocks, uncompressed_size)
        }
        Err(_) => Err(format!("unsupported chunk encoding {}", chunk.encoding)),
    }
}

fn decode_serialized_chunk_rle(encoded: &[u8], expected_size: usize) -> Result<Vec<u8>, String> {
    let expected_blocks = expected_size / BLOCK_BYTES;
    let mut decoded = Vec::with_capacity(expected_size);
    let mut offset = 0;

    while offset < encoded.len() {
        if offset + BLOCK_BYTES > encoded.len() {
            return Err("truncated RLE block id".to_string());
        }
        let block_id = u16::from_le_bytes([encoded[offset], encoded[offset + 1]]);
        offset += BLOCK_BYTES;

        let run_length = read_uvarint(encoded, &mut offset)?;
        if run_length == 0 {
            return Err("RLE run length is zero".to_string());
        }
        if run_length > expected_blocks as u64 {
            return Err(format!("RLE run length {} exceeds chunk size", run_length));
        }

        let run_bytes = run_length as usize * BLOCK_BYTES;
        if decoded.len() + run_bytes > expected_size {
            return Err(format!(
                "RLE decoded size would exceed {} bytes",
                expected_size
            ));
        }

        let block_bytes = block_id.to_le_bytes();
        for _ in 0..run_length {
            decoded.extend_from_slice(&block_bytes);
        }
    }

    if decoded.len() != expected_size {
        return Err(format!(
            "RLE decoded {} bytes, expected {}",
            decoded.len(),
            expected_size
        ));
    }
    Ok(decoded)
}

fn read_uvarint(encoded: &[u8], offset: &mut usize) -> Result<u64, String> {
    let mut value = 0u64;
    let mut shift = 0u32;

    while *offset < encoded.len() {
        let byte = encoded[*offset];
        *offset += 1;

        if shift == 63 && byte > 1 {
            return Err("RLE varint overflows u64".to_string());
        }
        value |= u64::from(byte & 0x7f) << shift;
        if byte < 0x80 {
            return Ok(value);
        }
        shift += 7;
        if shift >= 64 {
            return Err("RLE varint overflows u64".to_string());
        }
    }

    Err("truncated RLE run length".to_string())
}

fn chunk_dirty_update(previous: &[u8], current: &[u8]) -> ChunkDirtyUpdate {
    let mut update = ChunkDirtyUpdate::default();
    let mut bounds = ChunkDirtyBounds::default();
    let mut bounds_initialized = false;

    for block_index in 0..CHUNK_W * CHUNK_H * CHUNK_D {
        if chunk_block_id_at(previous, block_index) == chunk_block_id_at(current, block_index) {
            continue;
        }

        let (x, y, z) = chunk_block_coords(block_index);
        update.changed_blocks += 1;
        update.changed_subchunk_mask |= 1u32 << (y / SUBCHUNK_H);
        update.rebuild_subchunk_mask |= dirty_rebuild_subchunk_mask_for_y(y);
        update.edge_mask |= dirty_chunk_edge_mask(x, z);
        bounds.include(x, y, z, bounds_initialized);
        bounds_initialized = true;
    }

    if bounds_initialized {
        update.bounds = Some(bounds);
    }
    update
}

fn chunk_block_id_at(blocks: &[u8], block_index: usize) -> u16 {
    let byte_index = block_index * BLOCK_BYTES;
    if byte_index + 1 >= blocks.len() {
        return 0;
    }

    u16::from_le_bytes([blocks[byte_index], blocks[byte_index + 1]])
}

fn chunk_block_coords(block_index: usize) -> (usize, usize, usize) {
    let y = block_index / (CHUNK_W * CHUNK_D);
    let layer_index = block_index % (CHUNK_W * CHUNK_D);
    let z = layer_index / CHUNK_W;
    let x = layer_index % CHUNK_W;
    (x, y, z)
}

fn dirty_rebuild_subchunk_mask_for_y(y: usize) -> u32 {
    let sub_y = y / SUBCHUNK_H;
    let mut mask = 1u32 << sub_y;
    if y % SUBCHUNK_H == 0 && sub_y > 0 {
        mask |= 1u32 << (sub_y - 1);
    }
    if y % SUBCHUNK_H == SUBCHUNK_H - 1 && sub_y + 1 < SUBCHUNKS_PER_CHUNK as usize {
        mask |= 1u32 << (sub_y + 1);
    }
    mask
}

fn dirty_chunk_edge_mask(x: usize, z: usize) -> u8 {
    let mut mask = 0;
    if x == 0 {
        mask |= DIRTY_EDGE_NEG_X;
    }
    if x + 1 == CHUNK_W {
        mask |= DIRTY_EDGE_POS_X;
    }
    if z == 0 {
        mask |= DIRTY_EDGE_NEG_Z;
    }
    if z + 1 == CHUNK_D {
        mask |= DIRTY_EDGE_POS_Z;
    }
    mask
}

fn dirty_bounds_label(bounds: Option<ChunkDirtyBounds>) -> String {
    match bounds {
        Some(bounds) => format!(
            "{},{},{}:{},{},{}",
            bounds.min_x, bounds.min_y, bounds.min_z, bounds.max_x, bounds.max_y, bounds.max_z
        ),
        None => "none".to_string(),
    }
}

fn dirty_edge_label(mask: u8) -> String {
    if mask == 0 {
        return "none".to_string();
    }

    let mut parts = Vec::new();
    if mask & DIRTY_EDGE_NEG_X != 0 {
        parts.push("neg_x");
    }
    if mask & DIRTY_EDGE_POS_X != 0 {
        parts.push("pos_x");
    }
    if mask & DIRTY_EDGE_NEG_Z != 0 {
        parts.push("neg_z");
    }
    if mask & DIRTY_EDGE_POS_Z != 0 {
        parts.push("pos_z");
    }
    parts.join(",")
}

fn subchunk_mask_has_blocks(mask: u32, sub_y: i32) -> bool {
    if !(0..SUBCHUNKS_PER_CHUNK).contains(&sub_y) {
        return false;
    }
    (mask & (1u32 << sub_y)) != 0
}

fn valid_subchunk_mask() -> u32 {
    (1u32 << SUBCHUNKS_PER_CHUNK) - 1
}

fn chunk_subchunk_has_blocks(blocks: &[u8], sub_y: i32) -> bool {
    if !(0..SUBCHUNKS_PER_CHUNK).contains(&sub_y) {
        return false;
    }

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

    fn needs_render_surface(self) -> bool {
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

fn set_mesh_instance_surface(
    mesh_instance: &mut Gd<godot::classes::MeshInstance3D>,
    mesh: Option<&Gd<godot::classes::Mesh>>,
) {
    if let Some(mesh) = mesh {
        mesh_instance.set_mesh(mesh);
    } else {
        mesh_instance.set_mesh(Gd::<godot::classes::Mesh>::null_arg());
    }
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

fn create_mesh_trimesh_collision(
    mesh_instance: &mut Gd<godot::classes::MeshInstance3D>,
    faces: &PackedVector3Array,
) {
    let mut shape = godot::classes::ConcavePolygonShape3D::new_gd();
    shape.set_faces(faces);

    let mut collision_shape = godot::classes::CollisionShape3D::new_alloc();
    collision_shape.set_shape(&shape.upcast::<godot::classes::Shape3D>());

    let mut body = godot::classes::StaticBody3D::new_alloc();
    body.add_child(&collision_shape.upcast::<godot::classes::Node>());
    mesh_instance.add_child(&body.upcast::<godot::classes::Node>());
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
    fn get_current_chunk_loaded(&self) -> i32 {
        let Some(coord) = self.current_player_chunk else {
            return 0;
        };
        i32::from(self.chunk_blocks.contains_key(&coord))
    }

    #[func]
    fn get_current_chunk_rendered_count(&self) -> i32 {
        self.current_chunk_node_counts().rendered_submeshes
    }

    #[func]
    fn get_current_chunk_collision_count(&self) -> i32 {
        self.current_chunk_node_counts().total_collision_bodies
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

    fn gpu_terrain_perf_text(&self) -> String {
        self
            .gpu_terrain
            .as_ref()
            .map(|pool| {
                let stats = pool.stats();
                let rasterization = gpu_terrain::terrain_rasterization_labels();
                format!(
                    " gpu_subchunks={} gpu_draws={} gpu_effective_draws={} gpu_draw_repeat={} gpu_draw_cmd_bytes={} gpu_draw_cmd_capacity_bytes={} gpu_draw_cmd_stride={} gpu_cull={} gpu_front_face={} gpu_faces={} gpu_frames={} gpu_scene_target_create={} gpu_scene_target_reuse={} gpu_scene_target_replace={} gpu_uniform_set_create={} gpu_atlas_texture_create={} gpu_atlas_sampler_create={} gpu_push_constant_bytes={} gpu_push_constant_updates={} gpu_push_constant_total_bytes={} gpu_push_constant_avg_bytes={:.1} gpu_push_constant_camera_bytes={} gpu_push_constant_lighting_bytes={} gpu_push_constant_atlas_bytes={} gpu_light_dir={:.3}/{:.3}/{:.3} gpu_light_color={:.3}/{:.3}/{:.3} gpu_light_energy={:.3} gpu_light_ambient={:.3} gpu_mem={:.1}MB gpu_uploads={} gpu_upload_fail={} gpu_upload_fail_capacity={} gpu_upload_fail_fragmented={} gpu_upload_mb={:.2} gpu_last_upload_kb={:.1} gpu_upload_ms={:.3}/{:.3}/{:.3} gpu_upload_encode_ms={:.3}/{:.3}/{:.3} gpu_upload_stage_ms={:.3}/{:.3}/{:.3} gpu_upload_update_ms={:.3}/{:.3}/{:.3} gpu_free_ranges={} gpu_free_faces={} gpu_largest_free={} gpu_fragmented_free_faces={} gpu_fragmentation_pct={:.1} gpu_draw_rebuilds={} gpu_draw_rebuild_ms={:.3}/{:.3}/{:.3} gpu_draw_patches={} gpu_draw_patch_ms={:.3}/{:.3}/{:.3} gpu_compositor_submit={} gpu_compositor_submit_ms={:.3}/{:.3}/{:.3} gpu_compositor_submit_parts={:.3}/{:.3}/{:.3}/{:.3} gpu_compositor_submit_max_parts={:.3}/{:.3}/{:.3}/{:.3} gpu_compositor_gpu_samples={} gpu_compositor_gpu_ms={:.3}/{:.3}/{:.3} gpu_compositor_gpu_us={:.1}/{:.1}/{:.1}",
                    stats.subchunks,
                    stats.draw_count,
                    stats.compositor_effective_draw_count,
                    stats.compositor_draw_repeat,
                    stats.draw_command_bytes,
                    stats.draw_command_capacity_bytes,
                    stats.draw_command_stride_bytes,
                    rasterization.cull_mode,
                    rasterization.front_face,
                    stats.faces,
                    stats.compositor_frames,
                    stats.scene_target_create_count,
                    stats.scene_target_reuse_count,
                    stats.scene_target_replace_count,
                    stats.uniform_set_create_count,
                    stats.atlas_texture_create_count,
                    stats.atlas_sampler_create_count,
                    stats.push_constant_bytes,
                    stats.push_constant_update_count,
                    stats.push_constant_total_bytes,
                    stats.avg_push_constant_bytes,
                    stats.push_constant_camera_bytes,
                    stats.push_constant_lighting_bytes,
                    stats.push_constant_atlas_bytes,
                    stats.lighting.direction_to_light.x,
                    stats.lighting.direction_to_light.y,
                    stats.lighting.direction_to_light.z,
                    stats.lighting.color.r,
                    stats.lighting.color.g,
                    stats.lighting.color.b,
                    stats.lighting.energy,
                    stats.lighting.ambient,
                    stats.bytes as f64 / (1024.0 * 1024.0),
                    stats.upload_count,
                    stats.upload_failures,
                    stats.upload_capacity_failures,
                    stats.upload_fragmentation_failures,
                    stats.upload_bytes as f64 / (1024.0 * 1024.0),
                    stats.last_upload_bytes as f64 / 1024.0,
                    stats.last_upload_ms,
                    stats.avg_upload_ms,
                    stats.max_upload_ms,
                    stats.last_upload_encode_ms,
                    stats.avg_upload_encode_ms,
                    stats.max_upload_encode_ms,
                    stats.last_upload_stage_ms,
                    stats.avg_upload_stage_ms,
                    stats.max_upload_stage_ms,
                    stats.last_upload_update_ms,
                    stats.avg_upload_update_ms,
                    stats.max_upload_update_ms,
                    stats.free_ranges,
                    stats.free_faces,
                    stats.largest_free_faces,
                    stats.fragmented_free_faces,
                    stats.fragmentation_pct,
                    stats.draw_rebuild_count,
                    stats.last_draw_rebuild_ms,
                    stats.avg_draw_rebuild_ms,
                    stats.max_draw_rebuild_ms,
                    stats.draw_patch_count,
                    stats.last_draw_patch_ms,
                    stats.avg_draw_patch_ms,
                    stats.max_draw_patch_ms,
                    stats.compositor_submit_count,
                    stats.last_compositor_submit_ms,
                    stats.avg_compositor_submit_ms,
                    stats.max_compositor_submit_ms,
                    stats.last_compositor_submit_breakdown_ms.setup_ms,
                    stats.last_compositor_submit_breakdown_ms.target_ms,
                    stats.last_compositor_submit_breakdown_ms.constants_ms,
                    stats.last_compositor_submit_breakdown_ms.draw_ms,
                    stats.max_compositor_submit_breakdown_ms.setup_ms,
                    stats.max_compositor_submit_breakdown_ms.target_ms,
                    stats.max_compositor_submit_breakdown_ms.constants_ms,
                    stats.max_compositor_submit_breakdown_ms.draw_ms,
                    stats.compositor_gpu_sample_count,
                    stats.last_compositor_gpu_ms,
                    stats.avg_compositor_gpu_ms,
                    stats.max_compositor_gpu_ms,
                    stats.last_compositor_gpu_ms * 1000.0,
                    stats.avg_compositor_gpu_ms * 1000.0,
                    stats.max_compositor_gpu_ms * 1000.0
                )
            })
            .unwrap_or_default()
    }

    #[func]
    fn get_perf_text(&self) -> GString {
        let shadow_path = self.current_terrain_shadow_path();
        let native_shadow_requested = gpu_terrain_native_shadow_requested();
        let native_shadow_active = gpu_terrain_native_shadow_active();
        let native_shadow_fallback = gpu_terrain_native_shadow_fallback_decision(
            native_shadow_requested,
            native_shadow_active,
        );
        let native_shadow_implemented = GPU_TERRAIN_NATIVE_SHADOW_IMPLEMENTED;
        let native_shadow_resource_status = self.gpu_native_shadow_resources.status_label();
        let native_shadow_resource_radius = self.gpu_native_shadow_resources.shadow_radius_chunks();
        let native_shadow_resource_map = self.gpu_native_shadow_resources.map_size_px();
        let native_shadow_resource_width = self.gpu_native_shadow_resources.width_px();
        let native_shadow_resource_height = self.gpu_native_shadow_resources.height_px();
        let native_shadow_resource_layers = self.gpu_native_shadow_resources.layers();
        let native_shadow_resource_bytes_per_texel =
            self.gpu_native_shadow_resources.bytes_per_texel();
        let native_shadow_resource_bytes = self.gpu_native_shadow_resources.estimated_bytes();
        let native_shadow_resource_format = self.gpu_native_shadow_resources.format_label();
        let native_shadow_resource_usage = self.gpu_native_shadow_resources.usage_label();
        let native_shadow_pass_load_op = self.gpu_native_shadow_resources.pass_load_op_label();
        let native_shadow_pass_store_op = self.gpu_native_shadow_resources.pass_store_op_label();
        let native_shadow_pass_clear_depth_milli =
            self.gpu_native_shadow_resources.pass_clear_depth_milli();
        let native_shadow_depth_attachment_status = self
            .gpu_native_shadow_resources
            .depth_attachment_status_label();
        let native_shadow_depth_attachment_binding_count = self
            .gpu_native_shadow_resources
            .depth_attachment_binding_count();
        let native_shadow_depth_attachment_clear_count = self
            .gpu_native_shadow_resources
            .depth_attachment_clear_count();
        let native_shadow_resource_barrier_status = self
            .gpu_native_shadow_resources
            .resource_barrier_status_label();
        let native_shadow_resource_transition_count =
            self.gpu_native_shadow_resources.resource_transition_count();
        let native_shadow_resource_barrier_error_count = self
            .gpu_native_shadow_resources
            .resource_barrier_error_count();
        let native_shadow_framebuffer_status =
            self.gpu_native_shadow_resources.framebuffer_status_label();
        let native_shadow_framebuffer_rid_allocated =
            self.gpu_native_shadow_resources.framebuffer_rid_allocated();
        let native_shadow_framebuffer_attachment_count = self
            .gpu_native_shadow_resources
            .framebuffer_attachment_count();
        let native_shadow_framebuffer_pass_compat_status = self
            .gpu_native_shadow_resources
            .framebuffer_pass_compat_status_label();
        let native_shadow_framebuffer_pass_compat_error_count = self
            .gpu_native_shadow_resources
            .framebuffer_pass_compat_error_count();
        let native_shadow_framebuffer_depth_only_enabled = self
            .gpu_native_shadow_resources
            .framebuffer_depth_only_enabled();
        let native_shadow_framebuffer_color_attachment_count = self
            .gpu_native_shadow_resources
            .framebuffer_color_attachment_count();
        let native_shadow_pass_status = self.gpu_native_shadow_resources.pass_status_label();
        let native_shadow_pass_rid_allocated =
            self.gpu_native_shadow_resources.pass_rid_allocated();
        let native_shadow_pass_submit_status =
            self.gpu_native_shadow_resources.pass_submit_status_label();
        let native_shadow_pass_begin_count = self.gpu_native_shadow_resources.pass_begin_count();
        let native_shadow_pass_end_count = self.gpu_native_shadow_resources.pass_end_count();
        let native_shadow_command_buffer_status = self
            .gpu_native_shadow_resources
            .command_buffer_status_label();
        let native_shadow_command_buffer_submit_count = self
            .gpu_native_shadow_resources
            .command_buffer_submit_count();
        let native_shadow_command_buffer_error_count = self
            .gpu_native_shadow_resources
            .command_buffer_error_count();
        let native_shadow_sampler_filter = self.gpu_native_shadow_resources.sampler_filter_label();
        let native_shadow_sampler_address =
            self.gpu_native_shadow_resources.sampler_address_label();
        let native_shadow_sampler_compare_op =
            self.gpu_native_shadow_resources.sampler_compare_op_label();
        let native_shadow_sampler_compare_enabled =
            self.gpu_native_shadow_resources.sampler_compare_enabled();
        let native_shadow_depth_bias_constant_milli =
            self.gpu_native_shadow_resources.depth_bias_constant_milli();
        let native_shadow_depth_bias_slope_milli =
            self.gpu_native_shadow_resources.depth_bias_slope_milli();
        let native_shadow_depth_bias_clamp_milli =
            self.gpu_native_shadow_resources.depth_bias_clamp_milli();
        let native_shadow_viewport_x_px = self.gpu_native_shadow_resources.viewport_x_px();
        let native_shadow_viewport_y_px = self.gpu_native_shadow_resources.viewport_y_px();
        let native_shadow_viewport_width_px = self.gpu_native_shadow_resources.viewport_width_px();
        let native_shadow_viewport_height_px =
            self.gpu_native_shadow_resources.viewport_height_px();
        let native_shadow_viewport_min_depth_milli =
            self.gpu_native_shadow_resources.viewport_min_depth_milli();
        let native_shadow_viewport_max_depth_milli =
            self.gpu_native_shadow_resources.viewport_max_depth_milli();
        let native_shadow_pipeline_depth_test_enabled = self
            .gpu_native_shadow_resources
            .pipeline_depth_test_enabled();
        let native_shadow_pipeline_depth_write_enabled = self
            .gpu_native_shadow_resources
            .pipeline_depth_write_enabled();
        let native_shadow_pipeline_cull_mode =
            self.gpu_native_shadow_resources.pipeline_cull_mode_label();
        let native_shadow_pipeline_front_face =
            self.gpu_native_shadow_resources.pipeline_front_face_label();
        let native_shadow_draw_source = self.gpu_native_shadow_resources.draw_source_label();
        let native_shadow_draw_primitive = self.gpu_native_shadow_resources.draw_primitive_label();
        let native_shadow_draw_face_stride_bytes =
            self.gpu_native_shadow_resources.draw_face_stride_bytes();
        let native_shadow_draw_command_stride_bytes =
            self.gpu_native_shadow_resources.draw_command_stride_bytes();
        let native_shadow_draw_indirect_enabled =
            self.gpu_native_shadow_resources.draw_indirect_enabled();
        let native_shadow_draw_status = self.gpu_native_shadow_resources.draw_status_label();
        let native_shadow_draw_call_count = self.gpu_native_shadow_resources.draw_call_count();
        let native_shadow_draw_face_count = self.gpu_native_shadow_resources.draw_face_count();
        let native_shadow_uniform_set_index = self.gpu_native_shadow_resources.uniform_set_index();
        let native_shadow_face_buffer_binding =
            self.gpu_native_shadow_resources.face_buffer_binding();
        let native_shadow_push_constant_bytes =
            self.gpu_native_shadow_resources.push_constant_bytes();
        let native_shadow_texture_sampling_enabled =
            self.gpu_native_shadow_resources.texture_sampling_enabled();
        let native_shadow_shader_language =
            self.gpu_native_shadow_resources.shader_language_label();
        let native_shadow_shader_entry = self.gpu_native_shadow_resources.shader_entry_label();
        let native_shadow_shader_depth_output_enabled = self
            .gpu_native_shadow_resources
            .shader_depth_output_enabled();
        let native_shadow_shader_color_output_enabled = self
            .gpu_native_shadow_resources
            .shader_color_output_enabled();
        let native_shadow_shader_source_bytes =
            self.gpu_native_shadow_resources.shader_source_bytes();
        let native_shadow_shader_source_checksum =
            self.gpu_native_shadow_resources.shader_source_checksum();
        let native_shadow_shader_module_status = self
            .gpu_native_shadow_resources
            .shader_module_status_label();
        let native_shadow_shader_module_rid_allocated = self
            .gpu_native_shadow_resources
            .shader_module_rid_allocated();
        let native_shadow_light_source = self.gpu_native_shadow_resources.light_source_label();
        let native_shadow_light_space = self.gpu_native_shadow_resources.light_space_label();
        let native_shadow_cascade_count = self.gpu_native_shadow_resources.cascade_count();
        let native_shadow_light_matrix_bytes =
            self.gpu_native_shadow_resources.light_matrix_bytes();
        let native_shadow_depth_clip_space =
            self.gpu_native_shadow_resources.depth_clip_space_label();
        let native_shadow_depth_range_source =
            self.gpu_native_shadow_resources.depth_range_source_label();
        let native_shadow_depth_near_milli = self.gpu_native_shadow_resources.depth_near_milli();
        let native_shadow_depth_far_chunks = self.gpu_native_shadow_resources.depth_far_chunks();
        let (native_shadow_covered_chunks, native_shadow_covered_subchunks) = self
            .gpu_native_shadow_resources
            .coverage_counts(&self.chunk_non_empty_subchunks);
        let transparent_requested = gpu_terrain_transparent_requested();
        let transparent_active = gpu_terrain_transparent_active();
        let transparent_fallback =
            gpu_terrain_transparent_fallback_decision(transparent_requested, transparent_active);
        let (transparent_blocks, transparent_faces, transparent_draws, transparent_subchunks) =
            gpu_terrain_transparent_workload_counts(transparent_active);
        let transparent_fixture_overlay_requested =
            gpu_terrain_transparent_fixture_overlay_requested();
        let transparent_fixture_overlay_active =
            gpu_terrain_transparent_fixture_overlay_active_decision(
                transparent_fixture_overlay_requested,
                transparent_active,
            );
        let transparent_fixture_overlay_fallback =
            gpu_terrain_transparent_fixture_overlay_fallback_decision(
                transparent_fixture_overlay_requested,
                transparent_fixture_overlay_active,
            );
        let (transparent_fixture_overlay_roles, transparent_fixture_overlay_blocks) =
            gpu_terrain_transparent_fixture_overlay_metadata_counts(
                transparent_fixture_overlay_requested,
            );
        let gpu_terrain_text = self.gpu_terrain_perf_text();
        let dirty_bounds = dirty_bounds_label(self.perf.last_dirty_bounds);
        let dirty_edges = dirty_edge_label(self.perf.last_dirty_edge_mask);
        let text = format!(
            "rust_ext_profile={} queue={} queue_max={} queue_enq={} queue_geom_enq={} queue_proxy_enq={} queue_dup={} queue_geom_dup={} queue_proxy_dup={} queue_drained={} queue_geom_drained={} queue_proxy_drained={} queue_last_drain={} queue_last_geom_drain={} queue_last_proxy_drain={} queue_stale={} queue_last_stale={} queue_missing={} queue_last_missing={} jobs={} cpu_proxy={} mesh_visible={} mesh_shadow_off={} mesh_shadow_double={} mesh_shadow_only={} proxy_coll={} proxy_shadow={} proxy_both={} proxy_shadow_only={} shadow_path={} native_shadow_requested={} native_shadow_active={} native_shadow_fallback={} native_shadow_implemented={} native_shadow_resource_status={} native_shadow_resource_radius={} native_shadow_resource_map={} native_shadow_resource_width={} native_shadow_resource_height={} native_shadow_resource_layers={} native_shadow_resource_bytes_per_texel={} native_shadow_resource_bytes={} native_shadow_resource_format={} native_shadow_resource_usage={} native_shadow_pass_load_op={} native_shadow_pass_store_op={} native_shadow_pass_clear_depth_milli={} native_shadow_depth_attachment_status={} native_shadow_depth_attachment_binding_count={} native_shadow_depth_attachment_clear_count={} native_shadow_resource_barrier_status={} native_shadow_resource_transition_count={} native_shadow_resource_barrier_error_count={} native_shadow_framebuffer_status={} native_shadow_framebuffer_rid_allocated={} native_shadow_framebuffer_attachment_count={} native_shadow_framebuffer_pass_compat_status={} native_shadow_framebuffer_pass_compat_error_count={} native_shadow_framebuffer_depth_only_enabled={} native_shadow_framebuffer_color_attachment_count={} native_shadow_pass_status={} native_shadow_pass_rid_allocated={} native_shadow_pass_submit_status={} native_shadow_pass_begin_count={} native_shadow_pass_end_count={} native_shadow_command_buffer_status={} native_shadow_command_buffer_submit_count={} native_shadow_command_buffer_error_count={} native_shadow_sampler_filter={} native_shadow_sampler_address={} native_shadow_sampler_compare_op={} native_shadow_sampler_compare_enabled={} native_shadow_depth_bias_constant_milli={} native_shadow_depth_bias_slope_milli={} native_shadow_depth_bias_clamp_milli={} native_shadow_viewport_x_px={} native_shadow_viewport_y_px={} native_shadow_viewport_width_px={} native_shadow_viewport_height_px={} native_shadow_viewport_min_depth_milli={} native_shadow_viewport_max_depth_milli={} native_shadow_pipeline_depth_test_enabled={} native_shadow_pipeline_depth_write_enabled={} native_shadow_pipeline_cull_mode={} native_shadow_pipeline_front_face={} native_shadow_draw_source={} native_shadow_draw_primitive={} native_shadow_draw_face_stride_bytes={} native_shadow_draw_command_stride_bytes={} native_shadow_draw_indirect_enabled={} native_shadow_draw_status={} native_shadow_draw_call_count={} native_shadow_draw_face_count={} native_shadow_uniform_set_index={} native_shadow_face_buffer_binding={} native_shadow_push_constant_bytes={} native_shadow_texture_sampling_enabled={} native_shadow_shader_language={} native_shadow_shader_entry={} native_shadow_shader_depth_output_enabled={} native_shadow_shader_color_output_enabled={} native_shadow_shader_source_bytes={} native_shadow_shader_source_checksum={} native_shadow_shader_module_status={} native_shadow_shader_module_rid_allocated={} native_shadow_light_source={} native_shadow_light_space={} native_shadow_cascade_count={} native_shadow_light_matrix_bytes={} native_shadow_depth_clip_space={} native_shadow_depth_range_source={} native_shadow_depth_near_milli={} native_shadow_depth_far_chunks={} native_shadow_resource_creates={} native_shadow_resource_reuses={} native_shadow_resource_replaces={} native_shadow_resource_releases={} native_shadow_covered_chunks={} native_shadow_covered_subchunks={} transparent_requested={} transparent_active={} transparent_fallback={} transparent_blocks={} transparent_faces={} transparent_draws={} transparent_subchunks={} transparent_fixture_overlay_requested={} transparent_fixture_overlay_active={} transparent_fixture_overlay_fallback={} transparent_fixture_overlay_roles={} transparent_fixture_overlay_blocks={} shadow_mode={} shadow_mesh={} compact_shadow_proxy={} compact_shadow_normals_saved={} compact_collision_proxy={} compact_collision_normals_saved={} fast_proxy={} proxy_refresh_reuse={} collision={} collision_refresh={} collision_refresh_empty={} collision_refresh_rebuilt={} collision_refresh_unchanged={} collision_refresh_missing={} collision_refresh_last={} collision_refresh_last_empty={} collision_refresh_last_rebuilt={} collision_refresh_last_unchanged={} collision_refresh_last_missing={} collision_q={} collision_q_max={} collision_q_enq={} collision_q_dup={} collision_q_drained={} collision_q_last_drain={} collision_q_stale={} collision_q_last_stale={} collision_q_missing={} collision_q_last_missing={} chunk_initial={} chunk_replace={} startup_chunk_packet_ms={:.3} startup_packet_read_work_ms={:.3} startup_packet_decode_work_ms={:.3} startup_packet_reader_elapsed_ms={:.3} startup_packet_queue_lag_ms={:.3} startup_chunk_decode_work_ms={:.3} startup_chunk_inserted_ms={:.3} startup_chunk_loaded_ms={:.3} startup_mesh_queued_ms={:.3} startup_mesh_dispatched_ms={:.3} startup_first_mesh_ms={:.3} startup_first_mesh_work_ms={:.3} startup_first_mesh_phase_ms={:.3}/{:.3}/{:.3}/{:.3}/{:.3}/{:.3} startup_first_mesh_collision_work_ms={:.3} startup_collision_ms={:.3} startup_player_spawn_ms={:.3} dirty_chunks={} dirty_blocks={} dirty_changed_subchunks={} dirty_rebuild_subchunks={} dirty_edge_chunks={} dirty_edge_neighbor_chunks={} dirty_edge_neighbor_subchunks={} dirty_last_edge_neighbor_chunks={} dirty_last_edge_neighbor_subchunks={} dirty_partial_chunks={} dirty_partial_subchunks={} dirty_partial_saved_subchunks={} dirty_last_blocks={} dirty_last_changed_subchunks={} dirty_last_rebuild_subchunks={} dirty_last_partial_subchunks={} dirty_last_partial_saved_subchunks={} dirty_last_changed_mask={} dirty_last_rebuild_mask={} dirty_last_bounds={} dirty_last_edges={} terrain_queue_work_frames={} terrain_queue_work_ms={:.3}/{:.3}/{:.3} terrain_queue_work_max_parts={:.3}/{:.3} terrain_queue_gpu_uploads={}/{:.2}/{} terrain_queue_gpu_upload_kb={:.1}/{:.1}/{:.1} mesh {:.2}/{:.2}/{:.2}ms max_mesh_reason={} max_mesh_cpu_proxy={} max_mesh_compact_shadow={} max_mesh_compact_collision={} max_mesh_collision_bodies={} max_mesh_verts={}/{} max_mesh_phase={:.2}/{:.2}/{:.2}/{:.2}/{:.2}/{:.2} max_array_mesh_reason={} max_array_mesh_cpu_proxy={} max_array_mesh_compact_shadow={} max_array_mesh_compact_collision={} max_array_mesh_collision_bodies={} max_array_mesh_verts={}/{} max_array_mesh_phase={:.2}/{:.2}/{:.2}/{:.2}/{:.2}/{:.2} mesh_phase_last={:.2}/{:.2}/{:.2}/{:.2}/{:.2}/{:.2} mesh_phase_avg={:.2}/{:.2}/{:.2}/{:.2}/{:.2}/{:.2} mesh_phase_max={:.2}/{:.2}/{:.2}/{:.2}/{:.2}/{:.2} gpu prep/sub/sync/read/parse {:.2}/{:.2}/{:.2}/{:.2}/{:.2}ms coll {:.2}/{:.2}/{:.2}ms collision_refresh_phase_last={:.2}/{:.2}/{:.2}/{:.2}/{:.2} collision_refresh_phase_max={:.2}/{:.2}/{:.2}/{:.2}/{:.2} verts last={}/{} total={} normals last={} total={} mem={:.1}MB{}",
            rust_ext_build_profile(),
            self.perf.mesh_queue_depth,
            self.perf.max_mesh_queue_depth,
            self.perf.mesh_queue_enqueues,
            self.perf.mesh_queue_geometry_enqueues,
            self.perf.mesh_queue_proxy_refresh_enqueues,
            self.perf.mesh_queue_duplicate_enqueues,
            self.perf.mesh_queue_geometry_duplicate_enqueues,
            self.perf.mesh_queue_proxy_refresh_duplicate_enqueues,
            self.perf.mesh_queue_drained,
            self.perf.mesh_queue_geometry_drained,
            self.perf.mesh_queue_proxy_refresh_drained,
            self.perf.last_mesh_queue_drained,
            self.perf.last_mesh_queue_geometry_drained,
            self.perf.last_mesh_queue_proxy_refresh_drained,
            self.perf.mesh_queue_stale_drops,
            self.perf.last_mesh_queue_stale_drops,
            self.perf.mesh_queue_missing_chunk_drops,
            self.perf.last_mesh_queue_missing_chunk_drops,
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
            native_shadow_requested as u8,
            native_shadow_active as u8,
            native_shadow_fallback as u8,
            native_shadow_implemented as u8,
            native_shadow_resource_status,
            native_shadow_resource_radius,
            native_shadow_resource_map,
            native_shadow_resource_width,
            native_shadow_resource_height,
            native_shadow_resource_layers,
            native_shadow_resource_bytes_per_texel,
            native_shadow_resource_bytes,
            native_shadow_resource_format,
            native_shadow_resource_usage,
            native_shadow_pass_load_op,
            native_shadow_pass_store_op,
            native_shadow_pass_clear_depth_milli,
            native_shadow_depth_attachment_status,
            native_shadow_depth_attachment_binding_count,
            native_shadow_depth_attachment_clear_count,
            native_shadow_resource_barrier_status,
            native_shadow_resource_transition_count,
            native_shadow_resource_barrier_error_count,
            native_shadow_framebuffer_status,
            native_shadow_framebuffer_rid_allocated,
            native_shadow_framebuffer_attachment_count,
            native_shadow_framebuffer_pass_compat_status,
            native_shadow_framebuffer_pass_compat_error_count,
            native_shadow_framebuffer_depth_only_enabled,
            native_shadow_framebuffer_color_attachment_count,
            native_shadow_pass_status,
            native_shadow_pass_rid_allocated,
            native_shadow_pass_submit_status,
            native_shadow_pass_begin_count,
            native_shadow_pass_end_count,
            native_shadow_command_buffer_status,
            native_shadow_command_buffer_submit_count,
            native_shadow_command_buffer_error_count,
            native_shadow_sampler_filter,
            native_shadow_sampler_address,
            native_shadow_sampler_compare_op,
            native_shadow_sampler_compare_enabled,
            native_shadow_depth_bias_constant_milli,
            native_shadow_depth_bias_slope_milli,
            native_shadow_depth_bias_clamp_milli,
            native_shadow_viewport_x_px,
            native_shadow_viewport_y_px,
            native_shadow_viewport_width_px,
            native_shadow_viewport_height_px,
            native_shadow_viewport_min_depth_milli,
            native_shadow_viewport_max_depth_milli,
            native_shadow_pipeline_depth_test_enabled,
            native_shadow_pipeline_depth_write_enabled,
            native_shadow_pipeline_cull_mode,
            native_shadow_pipeline_front_face,
            native_shadow_draw_source,
            native_shadow_draw_primitive,
            native_shadow_draw_face_stride_bytes,
            native_shadow_draw_command_stride_bytes,
            native_shadow_draw_indirect_enabled,
            native_shadow_draw_status,
            native_shadow_draw_call_count,
            native_shadow_draw_face_count,
            native_shadow_uniform_set_index,
            native_shadow_face_buffer_binding,
            native_shadow_push_constant_bytes,
            native_shadow_texture_sampling_enabled,
            native_shadow_shader_language,
            native_shadow_shader_entry,
            native_shadow_shader_depth_output_enabled,
            native_shadow_shader_color_output_enabled,
            native_shadow_shader_source_bytes,
            native_shadow_shader_source_checksum,
            native_shadow_shader_module_status,
            native_shadow_shader_module_rid_allocated,
            native_shadow_light_source,
            native_shadow_light_space,
            native_shadow_cascade_count,
            native_shadow_light_matrix_bytes,
            native_shadow_depth_clip_space,
            native_shadow_depth_range_source,
            native_shadow_depth_near_milli,
            native_shadow_depth_far_chunks,
            self.gpu_native_shadow_resources.creates,
            self.gpu_native_shadow_resources.reuses,
            self.gpu_native_shadow_resources.replaces,
            self.gpu_native_shadow_resources.releases,
            native_shadow_covered_chunks,
            native_shadow_covered_subchunks,
            transparent_requested as u8,
            transparent_active as u8,
            transparent_fallback as u8,
            transparent_blocks,
            transparent_faces,
            transparent_draws,
            transparent_subchunks,
            transparent_fixture_overlay_requested as u8,
            transparent_fixture_overlay_active as u8,
            transparent_fixture_overlay_fallback as u8,
            transparent_fixture_overlay_roles,
            transparent_fixture_overlay_blocks,
            gpu_terrain_shadow_proxy_mode().as_str(),
            gpu_terrain_shadow_proxy_mesh_mode().as_str(),
            self.perf.compact_shadow_proxy_meshes_built,
            self.perf.compact_shadow_proxy_normals_saved,
            self.perf.compact_collision_proxy_meshes_built,
            self.perf.compact_collision_proxy_normals_saved,
            self.perf.cpu_proxy_meshes_built,
            self.perf.cpu_proxy_refreshes_reused,
            self.perf.node_counts.total_collision_bodies,
            self.perf.collision_refresh_checked,
            self.perf.collision_refresh_skipped_empty,
            self.perf.collision_refresh_rebuilt,
            self.perf.collision_refresh_unchanged,
            self.perf.collision_refresh_missing_meshes,
            self.perf.last_collision_refresh_checked,
            self.perf.last_collision_refresh_skipped_empty,
            self.perf.last_collision_refresh_rebuilt,
            self.perf.last_collision_refresh_unchanged,
            self.perf.last_collision_refresh_missing_meshes,
            self.perf.collision_refresh_queue_depth,
            self.perf.max_collision_refresh_queue_depth,
            self.perf.collision_refresh_queue_enqueues,
            self.perf.collision_refresh_queue_duplicate_enqueues,
            self.perf.collision_refresh_queue_drained,
            self.perf.last_collision_refresh_queue_drained,
            self.perf.collision_refresh_queue_stale_drops,
            self.perf.last_collision_refresh_queue_stale_drops,
            self.perf.collision_refresh_queue_missing_chunk_drops,
            self.perf.last_collision_refresh_queue_missing_chunk_drops,
            self.perf.chunk_initial_loads,
            self.perf.chunk_replacement_updates,
            self.perf.startup_chunk_packet_ms,
            self.perf.startup_packet_read_work_ms,
            self.perf.startup_packet_decode_work_ms,
            self.perf.startup_packet_reader_elapsed_ms,
            self.perf.startup_packet_queue_lag_ms,
            self.perf.startup_chunk_decode_work_ms,
            self.perf.startup_chunk_inserted_ms,
            self.perf.startup_chunk_loaded_ms,
            self.perf.startup_mesh_queued_ms,
            self.perf.startup_mesh_dispatched_ms,
            self.perf.startup_first_mesh_ms,
            self.perf.startup_first_mesh_work_ms,
            self.perf.startup_first_mesh_phase.padded_ms,
            self.perf.startup_first_mesh_phase.packed_faces_ms,
            self.perf.startup_first_mesh_phase.gpu_upload_ms,
            self.perf.startup_first_mesh_phase.cpu_mesh_ms,
            self.perf.startup_first_mesh_phase.array_mesh_ms,
            self.perf.startup_first_mesh_phase.node_counts_ms,
            self.perf.startup_first_mesh_collision_work_ms,
            self.perf.startup_collision_ms,
            self.perf.startup_player_spawn_ms,
            self.perf.dirty_chunk_updates,
            self.perf.dirty_block_changes,
            self.perf.dirty_changed_subchunks,
            self.perf.dirty_rebuild_subchunks,
            self.perf.dirty_edge_chunk_updates,
            self.perf.dirty_edge_neighbor_refresh_chunks,
            self.perf.dirty_edge_neighbor_refresh_subchunks,
            self.perf.last_dirty_edge_neighbor_refresh_chunks,
            self.perf.last_dirty_edge_neighbor_refresh_subchunks,
            self.perf.dirty_partial_chunk_updates,
            self.perf.dirty_partial_subchunks,
            self.perf.dirty_partial_saved_subchunks,
            self.perf.last_dirty_block_changes,
            self.perf.last_dirty_changed_subchunks,
            self.perf.last_dirty_rebuild_subchunks,
            self.perf.last_dirty_partial_subchunks,
            self.perf.last_dirty_partial_saved_subchunks,
            self.perf.last_dirty_changed_subchunk_mask,
            self.perf.last_dirty_rebuild_subchunk_mask,
            dirty_bounds,
            dirty_edges,
            self.perf.terrain_queue_work_frames,
            self.perf.last_terrain_queue_work_ms,
            self.perf.avg_terrain_queue_work_ms,
            self.perf.max_terrain_queue_work_ms,
            self.perf.max_terrain_queue_mesh_work_ms,
            self.perf.max_terrain_queue_collision_work_ms,
            self.perf.last_terrain_queue_gpu_uploads,
            self.perf.avg_terrain_queue_gpu_uploads,
            self.perf.max_terrain_queue_gpu_uploads,
            self.perf.last_terrain_queue_gpu_upload_bytes as f64 / 1024.0,
            self.perf.avg_terrain_queue_gpu_upload_bytes / 1024.0,
            self.perf.max_terrain_queue_gpu_upload_bytes as f64 / 1024.0,
            self.perf.last_mesh_ms,
            self.perf.avg_mesh_ms,
            self.perf.max_mesh_ms,
            self.perf
                .max_mesh_reason
                .map_or("none", MeshQueueReason::as_str),
            self.perf.max_mesh_cpu_proxy_mesh as u8,
            self.perf.max_mesh_compact_shadow_proxy_mesh as u8,
            self.perf.max_mesh_compact_collision_proxy_mesh as u8,
            self.perf.max_mesh_collision_bodies,
            self.perf.max_mesh_vertices,
            self.perf.max_mesh_reported_vertices,
            self.perf.max_mesh_job_phase.padded_ms,
            self.perf.max_mesh_job_phase.packed_faces_ms,
            self.perf.max_mesh_job_phase.gpu_upload_ms,
            self.perf.max_mesh_job_phase.cpu_mesh_ms,
            self.perf.max_mesh_job_phase.array_mesh_ms,
            self.perf.max_mesh_job_phase.node_counts_ms,
            self.perf
                .max_array_mesh_reason
                .map_or("none", MeshQueueReason::as_str),
            self.perf.max_array_mesh_cpu_proxy_mesh as u8,
            self.perf.max_array_mesh_compact_shadow_proxy_mesh as u8,
            self.perf.max_array_mesh_compact_collision_proxy_mesh as u8,
            self.perf.max_array_mesh_collision_bodies,
            self.perf.max_array_mesh_vertices,
            self.perf.max_array_mesh_reported_vertices,
            self.perf.max_array_mesh_job_phase.padded_ms,
            self.perf.max_array_mesh_job_phase.packed_faces_ms,
            self.perf.max_array_mesh_job_phase.gpu_upload_ms,
            self.perf.max_array_mesh_job_phase.cpu_mesh_ms,
            self.perf.max_array_mesh_job_phase.array_mesh_ms,
            self.perf.max_array_mesh_job_phase.node_counts_ms,
            self.perf.last_mesh_phase.padded_ms,
            self.perf.last_mesh_phase.packed_faces_ms,
            self.perf.last_mesh_phase.gpu_upload_ms,
            self.perf.last_mesh_phase.cpu_mesh_ms,
            self.perf.last_mesh_phase.array_mesh_ms,
            self.perf.last_mesh_phase.node_counts_ms,
            self.perf.avg_mesh_phase.padded_ms,
            self.perf.avg_mesh_phase.packed_faces_ms,
            self.perf.avg_mesh_phase.gpu_upload_ms,
            self.perf.avg_mesh_phase.cpu_mesh_ms,
            self.perf.avg_mesh_phase.array_mesh_ms,
            self.perf.avg_mesh_phase.node_counts_ms,
            self.perf.max_mesh_phase.padded_ms,
            self.perf.max_mesh_phase.packed_faces_ms,
            self.perf.max_mesh_phase.gpu_upload_ms,
            self.perf.max_mesh_phase.cpu_mesh_ms,
            self.perf.max_mesh_phase.array_mesh_ms,
            self.perf.max_mesh_phase.node_counts_ms,
            self.perf.last_prepare_ms,
            self.perf.last_submit_ms,
            self.perf.last_sync_ms,
            self.perf.last_readback_ms,
            self.perf.last_parse_ms,
            self.perf.last_collision_ms,
            self.perf.avg_collision_ms,
            self.perf.max_collision_ms,
            self.perf.last_collision_refresh_phase.faces_ms,
            self.perf.last_collision_refresh_phase.clear_ms,
            self.perf.last_collision_refresh_phase.create_ms,
            self.perf.last_collision_refresh_phase.count_ms,
            self.perf.last_collision_refresh_phase.node_counts_ms,
            self.perf.max_collision_refresh_phase.faces_ms,
            self.perf.max_collision_refresh_phase.clear_ms,
            self.perf.max_collision_refresh_phase.create_ms,
            self.perf.max_collision_refresh_phase.count_ms,
            self.perf.max_collision_refresh_phase.node_counts_ms,
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
    fn shutdown_for_quit(&mut self) {
        self.emit_debug_log("GameClient runtime shutdown requested");
        self.shutdown_runtime_resources();
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

    fn test_chunk_data(
        blocks: Vec<u8>,
        encoding: crate::api::ChunkEncoding,
        uncompressed_size: u32,
    ) -> crate::api::ChunkData {
        crate::api::ChunkData {
            x: 0,
            z: 0,
            blocks,
            encoding: encoding as i32,
            uncompressed_size,
        }
    }

    fn push_test_uvarint(encoded: &mut Vec<u8>, mut value: u64) {
        while value >= 0x80 {
            encoded.push((value as u8) | 0x80);
            value >>= 7;
        }
        encoded.push(value as u8);
    }

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
    fn cpu_array_mesh_packed_faces_default_can_be_overridden() {
        assert!(cpu_array_mesh_packed_faces_decision(None));
        assert!(cpu_array_mesh_packed_faces_decision(Some(true)));
        assert!(!cpu_array_mesh_packed_faces_decision(Some(false)));
    }

    #[test]
    fn gpu_terrain_render_remains_opt_in_with_explicit_enable() {
        assert!(!gpu_terrain_render_decision(None));
        assert!(gpu_terrain_render_decision(Some(true)));
        assert!(!gpu_terrain_render_decision(Some(false)));
    }

    #[test]
    fn gpu_terrain_partial_dirty_upload_defaults_on_with_rollback_flag() {
        assert!(gpu_terrain_partial_dirty_upload_decision(None));
        assert!(gpu_terrain_partial_dirty_upload_decision(Some(true)));
        assert!(!gpu_terrain_partial_dirty_upload_decision(Some(false)));
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
    fn chunk_unload_grace_keeps_recently_seen_far_chunks() {
        assert!(!should_unload_chunk(
            (3, 0),
            (0, 0),
            4,
            Some(0.0),
            100.0,
            20.0
        ));
        assert!(!should_unload_chunk(
            (5, 0),
            (0, 0),
            4,
            Some(85.0),
            100.0,
            20.0
        ));
        assert!(should_unload_chunk(
            (5, 0),
            (0, 0),
            4,
            Some(79.0),
            100.0,
            20.0
        ));
        assert!(should_unload_chunk((5, 0), (0, 0), 4, None, 100.0, 20.0));
        assert!(should_unload_chunk(
            (5, 0),
            (0, 0),
            4,
            Some(99.0),
            100.0,
            0.0
        ));
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
            terrain_shadow_path_decision(false, GpuTerrainShadowProxyMode::Conservative, 5, true),
            GpuTerrainShadowPath::ArrayMesh
        );
        assert_eq!(
            terrain_shadow_path_decision(true, GpuTerrainShadowProxyMode::Conservative, 5, false),
            GpuTerrainShadowPath::GodotProxy
        );
        assert_eq!(
            terrain_shadow_path_decision(true, GpuTerrainShadowProxyMode::Conservative, 5, true),
            GpuTerrainShadowPath::GpuNativeShadow
        );
        assert_eq!(
            GpuTerrainShadowPath::GpuNativeShadow.as_str(),
            "gpu_native_shadow"
        );
        assert_eq!(
            terrain_shadow_path_decision(true, GpuTerrainShadowProxyMode::Conservative, 0, true),
            GpuTerrainShadowPath::SceneShadowsDisabled
        );
        assert_eq!(
            terrain_shadow_path_decision(true, GpuTerrainShadowProxyMode::CollisionOnly, 5, true),
            GpuTerrainShadowPath::DiagnosticNoShadowProxy
        );
    }

    #[test]
    fn gpu_native_shadow_gate_stays_disabled_until_implemented() {
        assert!(!GPU_TERRAIN_NATIVE_SHADOW_IMPLEMENTED);
        assert!(!gpu_terrain_native_shadow_requested_decision(None));
        assert!(!gpu_terrain_native_shadow_requested_decision(Some(false)));
        assert!(gpu_terrain_native_shadow_requested_decision(Some(true)));
        assert!(!gpu_terrain_native_shadow_active_decision(false, false));
        assert!(!gpu_terrain_native_shadow_active_decision(false, true));
        assert!(!gpu_terrain_native_shadow_active_decision(true, false));
        assert!(gpu_terrain_native_shadow_active_decision(true, true));
        assert!(!gpu_terrain_native_shadow_fallback_decision(false, false));
        assert!(!gpu_terrain_native_shadow_fallback_decision(false, true));
        assert!(gpu_terrain_native_shadow_fallback_decision(true, false));
        assert!(!gpu_terrain_native_shadow_fallback_decision(true, true));
    }

    #[test]
    fn native_shadow_resource_descriptor_requires_active_shadow_casting_path() {
        let mode = GpuTerrainShadowProxyMode::Conservative;

        assert_eq!(
            gpu_native_shadow_resource_descriptor(false, true, mode, 5),
            None
        );
        assert_eq!(
            gpu_native_shadow_resource_descriptor(true, false, mode, 5),
            None
        );
        assert_eq!(
            gpu_native_shadow_resource_descriptor(
                true,
                true,
                GpuTerrainShadowProxyMode::CollisionOnly,
                5,
            ),
            None
        );
        assert_eq!(
            gpu_native_shadow_resource_descriptor(true, true, mode, 0),
            None
        );
        assert_eq!(
            gpu_native_shadow_resource_descriptor(true, true, mode, 5),
            Some(GpuNativeShadowResourceDescriptor {
                map_size_px: GPU_TERRAIN_NATIVE_SHADOW_MAP_SIZE_PX,
                width_px: GPU_TERRAIN_NATIVE_SHADOW_MAP_SIZE_PX,
                height_px: GPU_TERRAIN_NATIVE_SHADOW_MAP_SIZE_PX,
                layers: GPU_TERRAIN_NATIVE_SHADOW_LAYERS,
                shadow_radius_chunks: 5,
                bytes_per_texel: GPU_TERRAIN_NATIVE_SHADOW_BYTES_PER_TEXEL,
                estimated_bytes: u64::from(GPU_TERRAIN_NATIVE_SHADOW_MAP_SIZE_PX)
                    * u64::from(GPU_TERRAIN_NATIVE_SHADOW_MAP_SIZE_PX)
                    * u64::from(GPU_TERRAIN_NATIVE_SHADOW_LAYERS)
                    * u64::from(GPU_TERRAIN_NATIVE_SHADOW_BYTES_PER_TEXEL),
                format: GPU_TERRAIN_NATIVE_SHADOW_FORMAT,
                usage: GPU_TERRAIN_NATIVE_SHADOW_USAGE,
                pass_load_op: GPU_TERRAIN_NATIVE_SHADOW_PASS_LOAD_OP,
                pass_store_op: GPU_TERRAIN_NATIVE_SHADOW_PASS_STORE_OP,
                pass_clear_depth_milli: GPU_TERRAIN_NATIVE_SHADOW_PASS_CLEAR_DEPTH_MILLI,
                depth_attachment_status: GPU_TERRAIN_NATIVE_SHADOW_DEPTH_ATTACHMENT_STATUS,
                depth_attachment_binding_count:
                    GPU_TERRAIN_NATIVE_SHADOW_DEPTH_ATTACHMENT_BINDING_COUNT,
                depth_attachment_clear_count:
                    GPU_TERRAIN_NATIVE_SHADOW_DEPTH_ATTACHMENT_CLEAR_COUNT,
                resource_barrier_status: GPU_TERRAIN_NATIVE_SHADOW_RESOURCE_BARRIER_STATUS,
                resource_transition_count: GPU_TERRAIN_NATIVE_SHADOW_RESOURCE_TRANSITION_COUNT,
                resource_barrier_error_count:
                    GPU_TERRAIN_NATIVE_SHADOW_RESOURCE_BARRIER_ERROR_COUNT,
                framebuffer_status: GPU_TERRAIN_NATIVE_SHADOW_FRAMEBUFFER_STATUS,
                framebuffer_rid_allocated: GPU_TERRAIN_NATIVE_SHADOW_FRAMEBUFFER_RID_ALLOCATED,
                framebuffer_attachment_count:
                    GPU_TERRAIN_NATIVE_SHADOW_FRAMEBUFFER_ATTACHMENT_COUNT,
                framebuffer_pass_compat_status:
                    GPU_TERRAIN_NATIVE_SHADOW_FRAMEBUFFER_PASS_COMPAT_STATUS,
                framebuffer_pass_compat_error_count:
                    GPU_TERRAIN_NATIVE_SHADOW_FRAMEBUFFER_PASS_COMPAT_ERROR_COUNT,
                framebuffer_depth_only_enabled:
                    GPU_TERRAIN_NATIVE_SHADOW_FRAMEBUFFER_DEPTH_ONLY_ENABLED,
                framebuffer_color_attachment_count:
                    GPU_TERRAIN_NATIVE_SHADOW_FRAMEBUFFER_COLOR_ATTACHMENT_COUNT,
                pass_status: GPU_TERRAIN_NATIVE_SHADOW_PASS_STATUS,
                pass_rid_allocated: GPU_TERRAIN_NATIVE_SHADOW_PASS_RID_ALLOCATED,
                pass_submit_status: GPU_TERRAIN_NATIVE_SHADOW_PASS_SUBMIT_STATUS,
                pass_begin_count: GPU_TERRAIN_NATIVE_SHADOW_PASS_BEGIN_COUNT,
                pass_end_count: GPU_TERRAIN_NATIVE_SHADOW_PASS_END_COUNT,
                command_buffer_status: GPU_TERRAIN_NATIVE_SHADOW_COMMAND_BUFFER_STATUS,
                command_buffer_submit_count: GPU_TERRAIN_NATIVE_SHADOW_COMMAND_BUFFER_SUBMIT_COUNT,
                command_buffer_error_count: GPU_TERRAIN_NATIVE_SHADOW_COMMAND_BUFFER_ERROR_COUNT,
                sampler_filter: GPU_TERRAIN_NATIVE_SHADOW_SAMPLER_FILTER,
                sampler_address: GPU_TERRAIN_NATIVE_SHADOW_SAMPLER_ADDRESS,
                sampler_compare_op: GPU_TERRAIN_NATIVE_SHADOW_SAMPLER_COMPARE_OP,
                sampler_compare_enabled: GPU_TERRAIN_NATIVE_SHADOW_SAMPLER_COMPARE_ENABLED,
                depth_bias_constant_milli: GPU_TERRAIN_NATIVE_SHADOW_DEPTH_BIAS_CONSTANT_MILLI,
                depth_bias_slope_milli: GPU_TERRAIN_NATIVE_SHADOW_DEPTH_BIAS_SLOPE_MILLI,
                depth_bias_clamp_milli: GPU_TERRAIN_NATIVE_SHADOW_DEPTH_BIAS_CLAMP_MILLI,
                viewport_x_px: GPU_TERRAIN_NATIVE_SHADOW_VIEWPORT_X_PX,
                viewport_y_px: GPU_TERRAIN_NATIVE_SHADOW_VIEWPORT_Y_PX,
                viewport_width_px: GPU_TERRAIN_NATIVE_SHADOW_MAP_SIZE_PX,
                viewport_height_px: GPU_TERRAIN_NATIVE_SHADOW_MAP_SIZE_PX,
                viewport_min_depth_milli: GPU_TERRAIN_NATIVE_SHADOW_VIEWPORT_MIN_DEPTH_MILLI,
                viewport_max_depth_milli: GPU_TERRAIN_NATIVE_SHADOW_VIEWPORT_MAX_DEPTH_MILLI,
                pipeline_depth_test_enabled: GPU_TERRAIN_NATIVE_SHADOW_PIPELINE_DEPTH_TEST_ENABLED,
                pipeline_depth_write_enabled:
                    GPU_TERRAIN_NATIVE_SHADOW_PIPELINE_DEPTH_WRITE_ENABLED,
                pipeline_cull_mode: GPU_TERRAIN_NATIVE_SHADOW_PIPELINE_CULL_MODE,
                pipeline_front_face: GPU_TERRAIN_NATIVE_SHADOW_PIPELINE_FRONT_FACE,
                draw_source: GPU_TERRAIN_NATIVE_SHADOW_DRAW_SOURCE,
                draw_primitive: GPU_TERRAIN_NATIVE_SHADOW_DRAW_PRIMITIVE,
                draw_face_stride_bytes: GPU_TERRAIN_NATIVE_SHADOW_DRAW_FACE_STRIDE_BYTES,
                draw_command_stride_bytes: GPU_TERRAIN_NATIVE_SHADOW_DRAW_COMMAND_STRIDE_BYTES,
                draw_indirect_enabled: GPU_TERRAIN_NATIVE_SHADOW_DRAW_INDIRECT_ENABLED,
                draw_status: GPU_TERRAIN_NATIVE_SHADOW_DRAW_STATUS,
                draw_call_count: GPU_TERRAIN_NATIVE_SHADOW_DRAW_CALL_COUNT,
                draw_face_count: GPU_TERRAIN_NATIVE_SHADOW_DRAW_FACE_COUNT,
                uniform_set_index: GPU_TERRAIN_NATIVE_SHADOW_UNIFORM_SET_INDEX,
                face_buffer_binding: GPU_TERRAIN_NATIVE_SHADOW_FACE_BUFFER_BINDING,
                push_constant_bytes: GPU_TERRAIN_NATIVE_SHADOW_PUSH_CONSTANT_BYTES,
                texture_sampling_enabled: GPU_TERRAIN_NATIVE_SHADOW_TEXTURE_SAMPLING_ENABLED,
                shader_language: GPU_TERRAIN_NATIVE_SHADOW_SHADER_LANGUAGE,
                shader_entry: GPU_TERRAIN_NATIVE_SHADOW_SHADER_ENTRY,
                shader_depth_output_enabled: GPU_TERRAIN_NATIVE_SHADOW_SHADER_DEPTH_OUTPUT,
                shader_color_output_enabled: GPU_TERRAIN_NATIVE_SHADOW_SHADER_COLOR_OUTPUT,
                shader_source_bytes: GPU_TERRAIN_NATIVE_SHADOW_SHADER_SOURCE_CONTRACT.len() as u32,
                shader_source_checksum: native_shadow_contract_checksum(
                    GPU_TERRAIN_NATIVE_SHADOW_SHADER_SOURCE_CONTRACT,
                ),
                shader_module_status: GPU_TERRAIN_NATIVE_SHADOW_SHADER_MODULE_STATUS,
                shader_module_rid_allocated: GPU_TERRAIN_NATIVE_SHADOW_SHADER_MODULE_RID_ALLOCATED,
                light_source: GPU_TERRAIN_NATIVE_SHADOW_LIGHT_SOURCE,
                light_space: GPU_TERRAIN_NATIVE_SHADOW_LIGHT_SPACE,
                cascade_count: GPU_TERRAIN_NATIVE_SHADOW_CASCADE_COUNT,
                light_matrix_bytes: GPU_TERRAIN_NATIVE_SHADOW_LIGHT_MATRIX_BYTES,
                depth_clip_space: GPU_TERRAIN_NATIVE_SHADOW_DEPTH_CLIP_SPACE,
                depth_range_source: GPU_TERRAIN_NATIVE_SHADOW_DEPTH_RANGE_SOURCE,
                depth_near_milli: GPU_TERRAIN_NATIVE_SHADOW_DEPTH_NEAR_MILLI,
                depth_far_chunks: 5,
            })
        );
    }

    #[test]
    fn native_shadow_resource_lifecycle_tracks_create_reuse_replace_and_release() {
        let mut resources = GpuNativeShadowResources::default();
        let mode = GpuTerrainShadowProxyMode::Conservative;

        assert_eq!(
            resources.sync(false, true, mode, 5),
            GpuNativeShadowResourceAction::Disabled
        );
        assert_eq!(resources.status_label(), "disabled");
        assert_eq!(resources.shadow_radius_chunks(), 0);
        assert_eq!(resources.map_size_px(), 0);
        assert_eq!(resources.width_px(), 0);
        assert_eq!(resources.height_px(), 0);
        assert_eq!(resources.layers(), 0);
        assert_eq!(resources.bytes_per_texel(), 0);
        assert_eq!(resources.estimated_bytes(), 0);
        assert_eq!(resources.format_label(), "none");
        assert_eq!(resources.usage_label(), "none");
        assert_eq!(resources.pass_load_op_label(), "none");
        assert_eq!(resources.pass_store_op_label(), "none");
        assert_eq!(resources.pass_clear_depth_milli(), 0);
        assert_eq!(resources.depth_attachment_status_label(), "none");
        assert_eq!(resources.depth_attachment_binding_count(), 0);
        assert_eq!(resources.depth_attachment_clear_count(), 0);
        assert_eq!(resources.resource_barrier_status_label(), "none");
        assert_eq!(resources.resource_transition_count(), 0);
        assert_eq!(resources.resource_barrier_error_count(), 0);
        assert_eq!(resources.framebuffer_status_label(), "none");
        assert_eq!(resources.framebuffer_rid_allocated(), 0);
        assert_eq!(resources.framebuffer_attachment_count(), 0);
        assert_eq!(resources.framebuffer_pass_compat_status_label(), "none");
        assert_eq!(resources.framebuffer_pass_compat_error_count(), 0);
        assert_eq!(resources.framebuffer_depth_only_enabled(), 0);
        assert_eq!(resources.framebuffer_color_attachment_count(), 0);
        assert_eq!(resources.pass_status_label(), "none");
        assert_eq!(resources.pass_rid_allocated(), 0);
        assert_eq!(resources.pass_submit_status_label(), "none");
        assert_eq!(resources.pass_begin_count(), 0);
        assert_eq!(resources.pass_end_count(), 0);
        assert_eq!(resources.command_buffer_status_label(), "none");
        assert_eq!(resources.command_buffer_submit_count(), 0);
        assert_eq!(resources.command_buffer_error_count(), 0);
        assert_eq!(resources.sampler_filter_label(), "none");
        assert_eq!(resources.sampler_address_label(), "none");
        assert_eq!(resources.sampler_compare_op_label(), "none");
        assert_eq!(resources.sampler_compare_enabled(), 0);
        assert_eq!(resources.depth_bias_constant_milli(), 0);
        assert_eq!(resources.depth_bias_slope_milli(), 0);
        assert_eq!(resources.depth_bias_clamp_milli(), 0);
        assert_eq!(resources.viewport_x_px(), 0);
        assert_eq!(resources.viewport_y_px(), 0);
        assert_eq!(resources.viewport_width_px(), 0);
        assert_eq!(resources.viewport_height_px(), 0);
        assert_eq!(resources.viewport_min_depth_milli(), 0);
        assert_eq!(resources.viewport_max_depth_milli(), 0);
        assert_eq!(resources.pipeline_depth_test_enabled(), 0);
        assert_eq!(resources.pipeline_depth_write_enabled(), 0);
        assert_eq!(resources.pipeline_cull_mode_label(), "none");
        assert_eq!(resources.pipeline_front_face_label(), "none");
        assert_eq!(resources.draw_source_label(), "none");
        assert_eq!(resources.draw_primitive_label(), "none");
        assert_eq!(resources.draw_face_stride_bytes(), 0);
        assert_eq!(resources.draw_command_stride_bytes(), 0);
        assert_eq!(resources.draw_indirect_enabled(), 0);
        assert_eq!(resources.draw_status_label(), "none");
        assert_eq!(resources.draw_call_count(), 0);
        assert_eq!(resources.draw_face_count(), 0);
        assert_eq!(resources.uniform_set_index(), 0);
        assert_eq!(resources.face_buffer_binding(), 0);
        assert_eq!(resources.push_constant_bytes(), 0);
        assert_eq!(resources.texture_sampling_enabled(), 0);
        assert_eq!(resources.shader_language_label(), "none");
        assert_eq!(resources.shader_entry_label(), "none");
        assert_eq!(resources.shader_depth_output_enabled(), 0);
        assert_eq!(resources.shader_color_output_enabled(), 0);
        assert_eq!(resources.shader_source_bytes(), 0);
        assert_eq!(resources.shader_source_checksum(), 0);
        assert_eq!(resources.shader_module_status_label(), "none");
        assert_eq!(resources.shader_module_rid_allocated(), 0);
        assert_eq!(resources.light_source_label(), "none");
        assert_eq!(resources.light_space_label(), "none");
        assert_eq!(resources.cascade_count(), 0);
        assert_eq!(resources.light_matrix_bytes(), 0);
        assert_eq!(resources.depth_clip_space_label(), "none");
        assert_eq!(resources.depth_range_source_label(), "none");
        assert_eq!(resources.depth_near_milli(), 0);
        assert_eq!(resources.depth_far_chunks(), 0);

        assert_eq!(
            resources.sync(true, true, mode, 5),
            GpuNativeShadowResourceAction::Create
        );
        assert_eq!(resources.status_label(), "ready");
        assert_eq!(resources.shadow_radius_chunks(), 5);
        assert_eq!(
            resources.map_size_px(),
            GPU_TERRAIN_NATIVE_SHADOW_MAP_SIZE_PX
        );
        assert_eq!(resources.width_px(), GPU_TERRAIN_NATIVE_SHADOW_MAP_SIZE_PX);
        assert_eq!(resources.height_px(), GPU_TERRAIN_NATIVE_SHADOW_MAP_SIZE_PX);
        assert_eq!(resources.layers(), GPU_TERRAIN_NATIVE_SHADOW_LAYERS);
        assert_eq!(
            resources.bytes_per_texel(),
            GPU_TERRAIN_NATIVE_SHADOW_BYTES_PER_TEXEL
        );
        assert_eq!(resources.estimated_bytes(), 16 * 1024 * 1024);
        assert_eq!(resources.format_label(), GPU_TERRAIN_NATIVE_SHADOW_FORMAT);
        assert_eq!(resources.usage_label(), GPU_TERRAIN_NATIVE_SHADOW_USAGE);
        assert_eq!(
            resources.pass_load_op_label(),
            GPU_TERRAIN_NATIVE_SHADOW_PASS_LOAD_OP
        );
        assert_eq!(
            resources.pass_store_op_label(),
            GPU_TERRAIN_NATIVE_SHADOW_PASS_STORE_OP
        );
        assert_eq!(
            resources.pass_clear_depth_milli(),
            GPU_TERRAIN_NATIVE_SHADOW_PASS_CLEAR_DEPTH_MILLI
        );
        assert_eq!(
            resources.depth_attachment_status_label(),
            GPU_TERRAIN_NATIVE_SHADOW_DEPTH_ATTACHMENT_STATUS
        );
        assert_eq!(
            resources.depth_attachment_binding_count(),
            GPU_TERRAIN_NATIVE_SHADOW_DEPTH_ATTACHMENT_BINDING_COUNT
        );
        assert_eq!(
            resources.depth_attachment_clear_count(),
            GPU_TERRAIN_NATIVE_SHADOW_DEPTH_ATTACHMENT_CLEAR_COUNT
        );
        assert_eq!(
            resources.resource_barrier_status_label(),
            GPU_TERRAIN_NATIVE_SHADOW_RESOURCE_BARRIER_STATUS
        );
        assert_eq!(
            resources.resource_transition_count(),
            GPU_TERRAIN_NATIVE_SHADOW_RESOURCE_TRANSITION_COUNT
        );
        assert_eq!(
            resources.resource_barrier_error_count(),
            GPU_TERRAIN_NATIVE_SHADOW_RESOURCE_BARRIER_ERROR_COUNT
        );
        assert_eq!(
            resources.framebuffer_status_label(),
            GPU_TERRAIN_NATIVE_SHADOW_FRAMEBUFFER_STATUS
        );
        assert_eq!(
            resources.framebuffer_rid_allocated(),
            GPU_TERRAIN_NATIVE_SHADOW_FRAMEBUFFER_RID_ALLOCATED
        );
        assert_eq!(
            resources.framebuffer_attachment_count(),
            GPU_TERRAIN_NATIVE_SHADOW_FRAMEBUFFER_ATTACHMENT_COUNT
        );
        assert_eq!(
            resources.framebuffer_pass_compat_status_label(),
            GPU_TERRAIN_NATIVE_SHADOW_FRAMEBUFFER_PASS_COMPAT_STATUS
        );
        assert_eq!(
            resources.framebuffer_pass_compat_error_count(),
            GPU_TERRAIN_NATIVE_SHADOW_FRAMEBUFFER_PASS_COMPAT_ERROR_COUNT
        );
        assert_eq!(
            resources.framebuffer_depth_only_enabled(),
            GPU_TERRAIN_NATIVE_SHADOW_FRAMEBUFFER_DEPTH_ONLY_ENABLED
        );
        assert_eq!(
            resources.framebuffer_color_attachment_count(),
            GPU_TERRAIN_NATIVE_SHADOW_FRAMEBUFFER_COLOR_ATTACHMENT_COUNT
        );
        assert_eq!(
            resources.pass_status_label(),
            GPU_TERRAIN_NATIVE_SHADOW_PASS_STATUS
        );
        assert_eq!(
            resources.pass_rid_allocated(),
            GPU_TERRAIN_NATIVE_SHADOW_PASS_RID_ALLOCATED
        );
        assert_eq!(
            resources.pass_submit_status_label(),
            GPU_TERRAIN_NATIVE_SHADOW_PASS_SUBMIT_STATUS
        );
        assert_eq!(
            resources.pass_begin_count(),
            GPU_TERRAIN_NATIVE_SHADOW_PASS_BEGIN_COUNT
        );
        assert_eq!(
            resources.pass_end_count(),
            GPU_TERRAIN_NATIVE_SHADOW_PASS_END_COUNT
        );
        assert_eq!(
            resources.command_buffer_status_label(),
            GPU_TERRAIN_NATIVE_SHADOW_COMMAND_BUFFER_STATUS
        );
        assert_eq!(
            resources.command_buffer_submit_count(),
            GPU_TERRAIN_NATIVE_SHADOW_COMMAND_BUFFER_SUBMIT_COUNT
        );
        assert_eq!(
            resources.command_buffer_error_count(),
            GPU_TERRAIN_NATIVE_SHADOW_COMMAND_BUFFER_ERROR_COUNT
        );
        assert_eq!(
            resources.sampler_filter_label(),
            GPU_TERRAIN_NATIVE_SHADOW_SAMPLER_FILTER
        );
        assert_eq!(
            resources.sampler_address_label(),
            GPU_TERRAIN_NATIVE_SHADOW_SAMPLER_ADDRESS
        );
        assert_eq!(
            resources.sampler_compare_op_label(),
            GPU_TERRAIN_NATIVE_SHADOW_SAMPLER_COMPARE_OP
        );
        assert_eq!(
            resources.sampler_compare_enabled(),
            GPU_TERRAIN_NATIVE_SHADOW_SAMPLER_COMPARE_ENABLED
        );
        assert_eq!(
            resources.depth_bias_constant_milli(),
            GPU_TERRAIN_NATIVE_SHADOW_DEPTH_BIAS_CONSTANT_MILLI
        );
        assert_eq!(
            resources.depth_bias_slope_milli(),
            GPU_TERRAIN_NATIVE_SHADOW_DEPTH_BIAS_SLOPE_MILLI
        );
        assert_eq!(
            resources.depth_bias_clamp_milli(),
            GPU_TERRAIN_NATIVE_SHADOW_DEPTH_BIAS_CLAMP_MILLI
        );
        assert_eq!(
            resources.viewport_x_px(),
            GPU_TERRAIN_NATIVE_SHADOW_VIEWPORT_X_PX
        );
        assert_eq!(
            resources.viewport_y_px(),
            GPU_TERRAIN_NATIVE_SHADOW_VIEWPORT_Y_PX
        );
        assert_eq!(
            resources.viewport_width_px(),
            GPU_TERRAIN_NATIVE_SHADOW_MAP_SIZE_PX
        );
        assert_eq!(
            resources.viewport_height_px(),
            GPU_TERRAIN_NATIVE_SHADOW_MAP_SIZE_PX
        );
        assert_eq!(
            resources.viewport_min_depth_milli(),
            GPU_TERRAIN_NATIVE_SHADOW_VIEWPORT_MIN_DEPTH_MILLI
        );
        assert_eq!(
            resources.viewport_max_depth_milli(),
            GPU_TERRAIN_NATIVE_SHADOW_VIEWPORT_MAX_DEPTH_MILLI
        );
        assert_eq!(
            resources.pipeline_depth_test_enabled(),
            GPU_TERRAIN_NATIVE_SHADOW_PIPELINE_DEPTH_TEST_ENABLED
        );
        assert_eq!(
            resources.pipeline_depth_write_enabled(),
            GPU_TERRAIN_NATIVE_SHADOW_PIPELINE_DEPTH_WRITE_ENABLED
        );
        assert_eq!(
            resources.pipeline_cull_mode_label(),
            GPU_TERRAIN_NATIVE_SHADOW_PIPELINE_CULL_MODE
        );
        assert_eq!(
            resources.pipeline_front_face_label(),
            GPU_TERRAIN_NATIVE_SHADOW_PIPELINE_FRONT_FACE
        );
        assert_eq!(
            resources.draw_source_label(),
            GPU_TERRAIN_NATIVE_SHADOW_DRAW_SOURCE
        );
        assert_eq!(
            resources.draw_primitive_label(),
            GPU_TERRAIN_NATIVE_SHADOW_DRAW_PRIMITIVE
        );
        assert_eq!(
            resources.draw_face_stride_bytes(),
            GPU_TERRAIN_NATIVE_SHADOW_DRAW_FACE_STRIDE_BYTES
        );
        assert_eq!(
            resources.draw_command_stride_bytes(),
            GPU_TERRAIN_NATIVE_SHADOW_DRAW_COMMAND_STRIDE_BYTES
        );
        assert_eq!(
            resources.draw_indirect_enabled(),
            GPU_TERRAIN_NATIVE_SHADOW_DRAW_INDIRECT_ENABLED
        );
        assert_eq!(
            resources.draw_status_label(),
            GPU_TERRAIN_NATIVE_SHADOW_DRAW_STATUS
        );
        assert_eq!(
            resources.draw_call_count(),
            GPU_TERRAIN_NATIVE_SHADOW_DRAW_CALL_COUNT
        );
        assert_eq!(
            resources.draw_face_count(),
            GPU_TERRAIN_NATIVE_SHADOW_DRAW_FACE_COUNT
        );
        assert_eq!(
            resources.uniform_set_index(),
            GPU_TERRAIN_NATIVE_SHADOW_UNIFORM_SET_INDEX
        );
        assert_eq!(
            resources.face_buffer_binding(),
            GPU_TERRAIN_NATIVE_SHADOW_FACE_BUFFER_BINDING
        );
        assert_eq!(
            resources.push_constant_bytes(),
            GPU_TERRAIN_NATIVE_SHADOW_PUSH_CONSTANT_BYTES
        );
        assert_eq!(
            resources.texture_sampling_enabled(),
            GPU_TERRAIN_NATIVE_SHADOW_TEXTURE_SAMPLING_ENABLED
        );
        assert_eq!(
            resources.shader_language_label(),
            GPU_TERRAIN_NATIVE_SHADOW_SHADER_LANGUAGE
        );
        assert_eq!(
            resources.shader_entry_label(),
            GPU_TERRAIN_NATIVE_SHADOW_SHADER_ENTRY
        );
        assert_eq!(
            resources.shader_depth_output_enabled(),
            GPU_TERRAIN_NATIVE_SHADOW_SHADER_DEPTH_OUTPUT
        );
        assert_eq!(
            resources.shader_color_output_enabled(),
            GPU_TERRAIN_NATIVE_SHADOW_SHADER_COLOR_OUTPUT
        );
        assert_eq!(
            resources.shader_source_bytes(),
            GPU_TERRAIN_NATIVE_SHADOW_SHADER_SOURCE_CONTRACT.len() as u32
        );
        assert_eq!(
            resources.shader_source_checksum(),
            native_shadow_contract_checksum(GPU_TERRAIN_NATIVE_SHADOW_SHADER_SOURCE_CONTRACT)
        );
        assert_eq!(
            resources.shader_module_status_label(),
            GPU_TERRAIN_NATIVE_SHADOW_SHADER_MODULE_STATUS
        );
        assert_eq!(
            resources.shader_module_rid_allocated(),
            GPU_TERRAIN_NATIVE_SHADOW_SHADER_MODULE_RID_ALLOCATED
        );
        assert_eq!(
            resources.light_source_label(),
            GPU_TERRAIN_NATIVE_SHADOW_LIGHT_SOURCE
        );
        assert_eq!(
            resources.light_space_label(),
            GPU_TERRAIN_NATIVE_SHADOW_LIGHT_SPACE
        );
        assert_eq!(
            resources.cascade_count(),
            GPU_TERRAIN_NATIVE_SHADOW_CASCADE_COUNT
        );
        assert_eq!(
            resources.light_matrix_bytes(),
            GPU_TERRAIN_NATIVE_SHADOW_LIGHT_MATRIX_BYTES
        );
        assert_eq!(
            resources.depth_clip_space_label(),
            GPU_TERRAIN_NATIVE_SHADOW_DEPTH_CLIP_SPACE
        );
        assert_eq!(
            resources.depth_range_source_label(),
            GPU_TERRAIN_NATIVE_SHADOW_DEPTH_RANGE_SOURCE
        );
        assert_eq!(
            resources.depth_near_milli(),
            GPU_TERRAIN_NATIVE_SHADOW_DEPTH_NEAR_MILLI
        );
        assert_eq!(resources.depth_far_chunks(), 5);

        assert_eq!(
            resources.sync(true, true, mode, 5),
            GpuNativeShadowResourceAction::Reuse
        );
        assert_eq!(
            resources.sync(true, true, mode, 3),
            GpuNativeShadowResourceAction::Replace
        );
        assert_eq!(resources.shadow_radius_chunks(), 3);
        assert_eq!(
            resources.sync(true, true, GpuTerrainShadowProxyMode::CollisionOnly, 3),
            GpuNativeShadowResourceAction::Release
        );
        assert_eq!(resources.status_label(), "disabled");
        assert_eq!(resources.creates, 1);
        assert_eq!(resources.reuses, 1);
        assert_eq!(resources.replaces, 1);
        assert_eq!(resources.releases, 1);

        assert_eq!(resources.release(), GpuNativeShadowResourceAction::Disabled);
    }

    #[test]
    fn native_shadow_resource_coverage_counts_loaded_non_empty_subchunks() {
        let mut masks = HashMap::new();
        masks.insert((0, 0), 0b0011);
        masks.insert((1, 0), 0);
        masks.insert((0, 1), 0b1000);

        let mut resources = GpuNativeShadowResources::default();
        assert_eq!(resources.coverage_counts(&masks), (0, 0));

        assert_eq!(
            resources.sync(true, true, GpuTerrainShadowProxyMode::Conservative, 5),
            GpuNativeShadowResourceAction::Create
        );
        assert_eq!(resources.coverage_counts(&masks), (2, 3));

        assert_eq!(resources.release(), GpuNativeShadowResourceAction::Release);
        assert_eq!(resources.coverage_counts(&masks), (0, 0));
    }

    #[test]
    fn gpu_transparent_gate_stays_disabled_until_implemented() {
        assert!(!gpu_terrain_transparent_requested_decision(None));
        assert!(!gpu_terrain_transparent_requested_decision(Some(false)));
        assert!(gpu_terrain_transparent_requested_decision(Some(true)));
        assert!(!gpu_terrain_transparent_active_decision(false, false));
        assert!(!gpu_terrain_transparent_active_decision(false, true));
        assert!(!gpu_terrain_transparent_active_decision(true, false));
        assert!(gpu_terrain_transparent_active_decision(true, true));
        assert!(!gpu_terrain_transparent_fallback_decision(false, false));
        assert!(!gpu_terrain_transparent_fallback_decision(false, true));
        assert!(gpu_terrain_transparent_fallback_decision(true, false));
        assert!(!gpu_terrain_transparent_fallback_decision(true, true));
        assert_eq!(gpu_terrain_transparent_workload_counts(false), (0, 0, 0, 0));
        assert!(!gpu_terrain_transparent_fixture_overlay_requested_decision(
            None
        ));
        assert!(!gpu_terrain_transparent_fixture_overlay_requested_decision(
            Some(false)
        ));
        assert!(gpu_terrain_transparent_fixture_overlay_requested_decision(
            Some(true)
        ));
        assert!(!gpu_terrain_transparent_fixture_overlay_active_decision(
            false, false
        ));
        assert!(!gpu_terrain_transparent_fixture_overlay_active_decision(
            false, true
        ));
        assert!(!gpu_terrain_transparent_fixture_overlay_active_decision(
            true, false
        ));
        assert!(gpu_terrain_transparent_fixture_overlay_active_decision(
            true, true
        ));
        assert!(!gpu_terrain_transparent_fixture_overlay_fallback_decision(
            false, false
        ));
        assert!(!gpu_terrain_transparent_fixture_overlay_fallback_decision(
            false, true
        ));
        assert!(gpu_terrain_transparent_fixture_overlay_fallback_decision(
            true, false
        ));
        assert!(!gpu_terrain_transparent_fixture_overlay_fallback_decision(
            true, true
        ));
        assert_eq!(
            gpu_terrain_transparent_fixture_overlay_metadata_counts(false),
            (0, 0)
        );
        assert_eq!(
            gpu_terrain_transparent_fixture_overlay_metadata_counts(true),
            (5, 5)
        );
    }

    #[test]
    fn transparent_fixture_overlay_metadata_is_client_only_and_fixed() {
        let roles: Vec<&str> = TRANSPARENT_FIXTURE_OVERLAY_ENTRIES
            .iter()
            .map(|entry| entry.role)
            .collect();
        assert_eq!(
            roles,
            vec![
                "front_transparent",
                "behind_wall_transparent",
                "opaque_depth_occluder",
                "adjacent_same_material_pair",
                "collision_probe"
            ]
        );

        let block_offsets: std::collections::BTreeSet<(i32, i32, i32)> =
            TRANSPARENT_FIXTURE_OVERLAY_ENTRIES
                .iter()
                .map(|entry| entry.block_offset)
                .collect();
        assert_eq!(
            block_offsets.len(),
            TRANSPARENT_FIXTURE_OVERLAY_ENTRIES.len()
        );
        assert!(block_offsets.contains(&(0, 2, 0)));
        assert!(block_offsets.contains(&(0, 2, -2)));
        assert!(block_offsets.contains(&(0, 2, -1)));
        assert!(block_offsets.contains(&(1, 2, 0)));
        assert!(block_offsets.contains(&(0, 1, 1)));

        assert_eq!(
            gpu_terrain_transparent_fixture_overlay_metadata_counts(true),
            (
                TRANSPARENT_FIXTURE_OVERLAY_ENTRIES.len() as u32,
                TRANSPARENT_FIXTURE_OVERLAY_ENTRIES.len() as u32
            )
        );
        assert!(!gpu_terrain_transparent_fixture_overlay_active_decision(
            true,
            GPU_TERRAIN_TRANSPARENT_IMPLEMENTED
        ));
    }

    #[test]
    fn native_shadow_active_separates_renderer_path_from_godot_proxy_radius() {
        let scene_shadow_radius = 5;
        let mode = GpuTerrainShadowProxyMode::Conservative;

        assert_eq!(
            terrain_shadow_path_decision(true, mode, scene_shadow_radius, true),
            GpuTerrainShadowPath::GpuNativeShadow
        );
        assert_eq!(
            terrain_godot_shadow_proxy_chunk_distance(mode, scene_shadow_radius, true),
            0
        );
        assert_eq!(
            terrain_godot_shadow_proxy_chunk_distance(mode, scene_shadow_radius, false),
            scene_shadow_radius
        );
        assert_eq!(
            terrain_godot_shadow_proxy_chunk_distance(
                GpuTerrainShadowProxyMode::CollisionOnly,
                scene_shadow_radius,
                false,
            ),
            0
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
    fn initial_player_startup_contract_targets_current_chunk() {
        let spawn_chunk = initial_player_chunk();
        assert_eq!(spawn_chunk, (0, 0));
        assert_eq!(
            chunk_coord_for_position(INITIAL_PLAYER_X, INITIAL_PLAYER_Z),
            spawn_chunk
        );
        assert_eq!(player_chunk_queue_hint(None), Some(spawn_chunk));
        assert_eq!(player_chunk_queue_hint(Some((3, -4))), Some((3, -4)));

        for key in initial_spawn_mesh_subchunks() {
            assert_eq!((key.chunk_x, key.chunk_z), spawn_chunk);
            assert!(subchunk_needs_collision(key, None));
            assert!(subchunk_needs_shadow_proxy(
                key,
                None,
                GpuTerrainShadowProxyMode::Conservative,
                5
            ));
        }
    }

    #[test]
    fn chunk_collision_refresh_tracks_old_or_new_player_radius() {
        assert!(chunk_needs_collision_refresh((0, 0), None, (0, 0)));
        assert!(chunk_needs_collision_refresh((1, 0), None, (0, 0)));
        assert!(!chunk_needs_collision_refresh((2, 0), None, (0, 0)));

        assert!(chunk_needs_collision_refresh((0, 0), Some((0, 0)), (3, 0)));
        assert!(chunk_needs_collision_refresh((3, 0), Some((0, 0)), (3, 0)));
        assert!(!chunk_needs_collision_refresh((6, 0), Some((0, 0)), (3, 0)));
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
            (4, 0),
            Some((0, 0)),
            (1, 0),
            5
        ));
        assert!(chunk_needs_cpu_proxy_refresh(
            (2, 0),
            Some((0, 0)),
            (1, 0),
            5
        ));
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
    fn gpu_attach_refresh_uses_proxy_refresh_jobs_after_visible_confirmation() {
        assert_eq!(mesh_queue_reason_after_gpu_attach(false), None);
        assert_eq!(
            mesh_queue_reason_after_gpu_attach(true),
            Some(MeshQueueReason::ProxyRefresh)
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
    fn compact_shadow_proxy_mesh_applies_to_any_shadow_cpu_proxy() {
        let compact = GpuTerrainShadowProxyMeshMode::Compact;

        assert!(compact.compacts_shadow_proxy_mesh(true, true));
        assert!(!compact.compacts_shadow_proxy_mesh(true, false));
        assert!(!compact.compacts_shadow_proxy_mesh(false, true));
        assert!(!GpuTerrainShadowProxyMeshMode::Full.compacts_shadow_proxy_mesh(true, true));
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
                indexed_shadow_proxy_mesh: true,
            }
        );
        assert!(shadow_only.uses_compact_mesh());
        assert!(shadow_only.uses_indexed_shadow_mesh());

        let collision_and_shadow = terrain_cpu_proxy_mesh_payload(
            GpuTerrainShadowProxyMeshMode::Compact,
            true,
            true,
            true,
        );
        assert_eq!(
            collision_and_shadow,
            TerrainCpuProxyMeshPayload {
                compact_shadow_proxy_mesh: true,
                compact_collision_proxy_mesh: false,
                indexed_shadow_proxy_mesh: false,
            }
        );
        assert!(collision_and_shadow.uses_compact_mesh());
        assert!(!collision_and_shadow.uses_indexed_shadow_mesh());

        let collision_only =
            terrain_cpu_proxy_mesh_payload(GpuTerrainShadowProxyMeshMode::Full, true, true, false);
        assert_eq!(
            collision_only,
            TerrainCpuProxyMeshPayload {
                compact_shadow_proxy_mesh: false,
                compact_collision_proxy_mesh: true,
                indexed_shadow_proxy_mesh: false,
            }
        );
        assert!(collision_only.uses_compact_mesh());
        assert!(!collision_only.uses_indexed_shadow_mesh());
    }

    #[test]
    fn cpu_proxy_mesh_payload_reuse_is_conservative() {
        let full = TerrainCpuProxyMeshPayload::default();
        let shadow_only = TerrainCpuProxyMeshPayload {
            compact_shadow_proxy_mesh: true,
            compact_collision_proxy_mesh: false,
            indexed_shadow_proxy_mesh: true,
        };
        let collision_and_shadow = TerrainCpuProxyMeshPayload {
            compact_shadow_proxy_mesh: true,
            compact_collision_proxy_mesh: false,
            indexed_shadow_proxy_mesh: false,
        };
        let collision_only = TerrainCpuProxyMeshPayload {
            compact_shadow_proxy_mesh: false,
            compact_collision_proxy_mesh: true,
            indexed_shadow_proxy_mesh: false,
        };

        assert!(full.can_satisfy(full));
        assert!(full.can_satisfy(shadow_only));
        assert!(full.can_satisfy(collision_and_shadow));
        assert!(full.can_satisfy(collision_only));
        assert!(shadow_only.can_satisfy(shadow_only));
        assert!(!shadow_only.can_satisfy(full));
        assert!(!shadow_only.can_satisfy(collision_and_shadow));
        assert!(!shadow_only.can_satisfy(collision_only));
        assert!(collision_and_shadow.can_satisfy(shadow_only));
        assert!(collision_and_shadow.can_satisfy(collision_only));
        assert!(collision_only.can_satisfy(collision_only));
        assert!(!collision_only.can_satisfy(full));
        assert!(!collision_only.can_satisfy(shadow_only));
    }

    #[test]
    fn proxy_refresh_queue_action_skips_only_confirmed_gpu_refresh_work() {
        let full = TerrainCpuProxyMeshPayload::default();
        let shadow_only = TerrainCpuProxyMeshPayload {
            compact_shadow_proxy_mesh: true,
            compact_collision_proxy_mesh: false,
            indexed_shadow_proxy_mesh: true,
        };
        let collision_only = TerrainCpuProxyMeshPayload {
            compact_shadow_proxy_mesh: false,
            compact_collision_proxy_mesh: true,
            indexed_shadow_proxy_mesh: false,
        };

        assert_eq!(
            proxy_refresh_queue_action(true, true, false, None, full),
            ProxyRefreshQueueAction::RemoveCpuNode
        );
        assert_eq!(
            proxy_refresh_queue_action(true, true, true, Some(full), shadow_only),
            ProxyRefreshQueueAction::ReuseCpuProxy
        );
        assert_eq!(
            proxy_refresh_queue_action(true, true, true, Some(shadow_only), collision_only),
            ProxyRefreshQueueAction::BuildMesh
        );
        assert_eq!(
            proxy_refresh_queue_action(true, true, true, Some(collision_only), shadow_only),
            ProxyRefreshQueueAction::BuildMesh
        );
        assert_eq!(
            proxy_refresh_queue_action(false, true, false, Some(full), full),
            ProxyRefreshQueueAction::BuildMesh
        );
        assert_eq!(
            proxy_refresh_queue_action(true, false, false, Some(full), full),
            ProxyRefreshQueueAction::BuildMesh
        );
    }

    #[test]
    fn terrain_mesh_render_mode_matches_proxy_role() {
        let fallback = TerrainMeshRenderMode::from_proxy_state(false, false);
        assert_eq!(fallback, TerrainMeshRenderMode::VisibleDoubleSided);
        assert!(fallback.is_visible());
        assert!(fallback.needs_render_surface());
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
        assert!(shadow_proxy.needs_render_surface());
        assert_eq!(
            shadow_proxy.shadow_setting(),
            godot::classes::geometry_instance_3d::ShadowCastingSetting::SHADOWS_ONLY
        );

        let collision_only = TerrainMeshRenderMode::from_proxy_state(true, false);
        assert_eq!(collision_only, TerrainMeshRenderMode::CollisionOnly);
        assert!(!collision_only.is_visible());
        assert!(!collision_only.needs_render_surface());
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
    fn node_perf_counts_adds_and_removes_subchunk_buckets() {
        let visible = NodePerfCounts::from_subchunk_state(
            true,
            true,
            true,
            godot::classes::geometry_instance_3d::ShadowCastingSetting::SHADOWS_ONLY,
            1,
        );
        let hidden = NodePerfCounts::from_subchunk_state(
            true,
            false,
            false,
            godot::classes::geometry_instance_3d::ShadowCastingSetting::OFF,
            0,
        );

        let mut total = NodePerfCounts::default();
        total.add(visible);
        total.add(hidden);

        assert_eq!(total.rendered_submeshes, 2);
        assert_eq!(total.visible_submeshes, 1);
        assert_eq!(total.shadow_off_submeshes, 1);
        assert_eq!(total.shadow_only_submeshes, 1);
        assert_eq!(total.total_collision_bodies, 1);
        assert_eq!(total.cpu_proxy_collision, 2);
        assert_eq!(total.cpu_proxy_shadow, 1);
        assert_eq!(total.cpu_proxy_both, 1);

        total.subtract(visible);

        assert_eq!(total.rendered_submeshes, 1);
        assert_eq!(total.visible_submeshes, 0);
        assert_eq!(total.shadow_off_submeshes, 1);
        assert_eq!(total.shadow_only_submeshes, 0);
        assert_eq!(total.total_collision_bodies, 0);
        assert_eq!(total.cpu_proxy_collision, 1);
        assert_eq!(total.cpu_proxy_shadow, 0);
        assert_eq!(total.cpu_proxy_both, 0);
    }

    #[test]
    fn perf_records_terrain_queue_frame_work() {
        let mut perf = PerfStats::default();

        perf.record_terrain_queue_frame_work(1.5, 0.5, 1, 4096);
        perf.record_terrain_queue_frame_work(4.0, 2.0, 3, 12_288);
        perf.record_terrain_queue_frame_work(0.5, 0.5, 0, 0);

        assert_eq!(perf.terrain_queue_work_frames, 3);
        assert_eq!(perf.last_terrain_queue_work_ms, 1.0);
        assert!((perf.avg_terrain_queue_work_ms - 3.0).abs() < f64::EPSILON);
        assert_eq!(perf.max_terrain_queue_work_ms, 6.0);
        assert_eq!(perf.max_terrain_queue_mesh_work_ms, 4.0);
        assert_eq!(perf.max_terrain_queue_collision_work_ms, 2.0);
        assert_eq!(perf.last_terrain_queue_gpu_uploads, 0);
        assert!((perf.avg_terrain_queue_gpu_uploads - 4.0 / 3.0).abs() < 0.000_001);
        assert_eq!(perf.max_terrain_queue_gpu_uploads, 3);
        assert_eq!(perf.last_terrain_queue_gpu_upload_bytes, 0);
        assert!((perf.avg_terrain_queue_gpu_upload_bytes - (16_384.0 / 3.0)).abs() < 0.000_001);
        assert_eq!(perf.max_terrain_queue_gpu_upload_bytes, 12_288);
    }

    #[test]
    fn perf_records_startup_milestones_once() {
        let mut perf = PerfStats::default();
        let empty_counts = NodePerfCounts::default();
        let collision_counts = NodePerfCounts {
            total_collision_bodies: 2,
            ..NodePerfCounts::default()
        };
        let startup_mesh_record = test_mesh_record(
            4,
            4,
            4,
            MeshQueueReason::GeometryChanged,
            false,
            false,
            false,
            1.75,
            TerrainMeshPhaseTiming {
                padded_ms: 0.10,
                packed_faces_ms: 0.20,
                gpu_upload_ms: 0.30,
                cpu_mesh_ms: 0.40,
                array_mesh_ms: 0.50,
                node_counts_ms: 0.60,
            },
            1,
        );
        let later_mesh_record = test_mesh_record(
            8,
            8,
            8,
            MeshQueueReason::GeometryChanged,
            false,
            false,
            false,
            9.0,
            TerrainMeshPhaseTiming {
                padded_ms: 9.0,
                packed_faces_ms: 9.0,
                gpu_upload_ms: 9.0,
                cpu_mesh_ms: 9.0,
                array_mesh_ms: 9.0,
                node_counts_ms: 9.0,
            },
            1,
        );

        perf.record_startup_chunk_packet(0.100, 1.25, 0.35, 4.50, 16.75);
        perf.record_startup_chunk_packet(0.110, 9.0, 9.0, 9.0, 9.0);
        perf.record_startup_chunk_decoded(0.115, 2.50);
        perf.record_startup_chunk_decoded(0.120, 9.0);
        perf.record_startup_chunk_inserted(0.125);
        perf.record_startup_chunk_inserted(0.150);
        perf.record_startup_chunk_loaded(0.125);
        perf.record_startup_chunk_loaded(0.250);
        perf.record_startup_mesh_queued(0.200);
        perf.record_startup_mesh_queued(0.225);
        perf.record_startup_mesh_dispatched(0.275);
        perf.record_startup_mesh_dispatched(0.290);
        perf.record_startup_first_mesh(0.300, &startup_mesh_record);
        perf.record_startup_first_mesh(0.325, &later_mesh_record);
        perf.record_startup_collision_ready(0.300, empty_counts);
        perf.record_startup_collision_ready(0.375, collision_counts);
        perf.record_startup_collision_ready(0.500, collision_counts);
        perf.record_startup_player_spawn(0.625);
        perf.record_startup_player_spawn(0.750);

        assert_eq!(perf.startup_chunk_packet_ms, 100.0);
        assert_eq!(perf.startup_packet_read_work_ms, 1.25);
        assert_eq!(perf.startup_packet_decode_work_ms, 0.35);
        assert_eq!(perf.startup_packet_reader_elapsed_ms, 4.50);
        assert_eq!(perf.startup_packet_queue_lag_ms, 16.75);
        assert_eq!(perf.startup_chunk_decode_work_ms, 2.50);
        assert_eq!(perf.startup_chunk_inserted_ms, 125.0);
        assert_eq!(perf.startup_chunk_loaded_ms, 125.0);
        assert_eq!(perf.startup_mesh_queued_ms, 200.0);
        assert_eq!(perf.startup_mesh_dispatched_ms, 275.0);
        assert_eq!(perf.startup_first_mesh_ms, 300.0);
        assert_eq!(perf.startup_first_mesh_work_ms, 1.75);
        assert_eq!(perf.startup_first_mesh_phase.padded_ms, 0.10);
        assert_eq!(perf.startup_first_mesh_phase.packed_faces_ms, 0.20);
        assert_eq!(perf.startup_first_mesh_phase.gpu_upload_ms, 0.30);
        assert_eq!(perf.startup_first_mesh_phase.cpu_mesh_ms, 0.40);
        assert_eq!(perf.startup_first_mesh_phase.array_mesh_ms, 0.50);
        assert_eq!(perf.startup_first_mesh_phase.node_counts_ms, 0.60);
        assert_eq!(perf.startup_first_mesh_collision_work_ms, 0.0);
        assert_eq!(perf.startup_collision_ms, 375.0);
        assert_eq!(perf.startup_player_spawn_ms, 625.0);
    }

    #[test]
    fn collision_refresh_phase_timing_records_component_maxima() {
        let mut timing = CollisionRefreshPhaseTiming::default();

        timing.record_max(CollisionRefreshPhaseTiming {
            faces_ms: 1.0,
            clear_ms: 2.0,
            create_ms: 3.0,
            count_ms: 4.0,
            node_counts_ms: 5.0,
        });
        timing.record_max(CollisionRefreshPhaseTiming {
            faces_ms: 2.0,
            clear_ms: 1.0,
            create_ms: 4.0,
            count_ms: 3.0,
            node_counts_ms: 6.0,
        });

        assert_eq!(timing.faces_ms, 2.0);
        assert_eq!(timing.clear_ms, 2.0);
        assert_eq!(timing.create_ms, 4.0);
        assert_eq!(timing.count_ms, 4.0);
        assert_eq!(timing.node_counts_ms, 6.0);
    }

    #[test]
    fn mesh_queue_reason_merges_geometry_changes_over_proxy_refreshes() {
        assert_eq!(
            MeshQueueReason::ProxyRefresh.merged_with(MeshQueueReason::ProxyRefresh),
            MeshQueueReason::ProxyRefresh
        );
        assert_eq!(
            MeshQueueReason::ProxyRefresh.merged_with(MeshQueueReason::GeometryChanged),
            MeshQueueReason::GeometryChanged
        );
        assert_eq!(
            MeshQueueReason::GeometryChanged.merged_with(MeshQueueReason::ProxyRefresh),
            MeshQueueReason::GeometryChanged
        );
    }

    #[test]
    fn gpu_upload_policy_skips_existing_proxy_refresh_slots_only() {
        assert!(should_upload_gpu_subchunk_for_queue_reason(
            MeshQueueReason::GeometryChanged,
            true
        ));
        assert!(should_upload_gpu_subchunk_for_queue_reason(
            MeshQueueReason::GeometryChanged,
            false
        ));
        assert!(should_upload_gpu_subchunk_for_queue_reason(
            MeshQueueReason::ProxyRefresh,
            false
        ));
        assert!(!should_upload_gpu_subchunk_for_queue_reason(
            MeshQueueReason::ProxyRefresh,
            true
        ));
    }

    #[test]
    fn mesh_queue_pop_prioritizes_player_chunk_with_fifo_ties() {
        let far = SubchunkKey {
            chunk_x: 5,
            sub_y: 0,
            chunk_z: 0,
        };
        let tie_a = SubchunkKey {
            chunk_x: 1,
            sub_y: 0,
            chunk_z: 0,
        };
        let tie_b = SubchunkKey {
            chunk_x: 0,
            sub_y: 0,
            chunk_z: 1,
        };
        let current = SubchunkKey {
            chunk_x: 0,
            sub_y: 0,
            chunk_z: 0,
        };
        let mut queue = VecDeque::new();
        queue.push_back(far);
        queue.push_back(tie_a);
        queue.push_back(tie_b);
        queue.push_back(current);

        assert!(
            pop_next_mesh_queue_key(&mut queue, Some((0, 0))).is_some_and(|key| key == current)
        );
        assert!(pop_next_mesh_queue_key(&mut queue, Some((0, 0))).is_some_and(|key| key == tie_a));
        assert!(pop_next_mesh_queue_key(&mut queue, None).is_some_and(|key| key == far));
        assert!(pop_next_mesh_queue_key(&mut queue, Some((0, 0))).is_some_and(|key| key == tie_b));
        assert!(pop_next_mesh_queue_key(&mut queue, Some((0, 0))).is_none());
    }

    #[test]
    fn mesh_queue_uses_initial_chunk_hint_before_player_chunk_updates() {
        let (chunk_x, chunk_z) = initial_player_chunk();
        let current = SubchunkKey {
            chunk_x,
            sub_y: 0,
            chunk_z,
        };
        let far = SubchunkKey {
            chunk_x: chunk_x + 5,
            sub_y: 0,
            chunk_z,
        };
        let mut queue = VecDeque::new();
        queue.push_back(far);
        queue.push_back(current);

        assert!(
            pop_next_mesh_queue_key(&mut queue, player_chunk_queue_hint(None))
                .is_some_and(|key| key == current)
        );
        assert!(pop_next_mesh_queue_key(&mut queue, None).is_some_and(|key| key == far));
    }

    #[test]
    fn mesh_queue_waits_when_collision_refresh_rebuilt_this_frame() {
        assert!(should_process_mesh_queue_after_collision_refresh(0));
        assert!(!should_process_mesh_queue_after_collision_refresh(1));
        assert!(!should_process_mesh_queue_after_collision_refresh(2));
    }

    #[test]
    fn decode_chunk_blocks_accepts_raw_full_chunk() {
        let mut blocks = vec![0u8; SERIALIZED_CHUNK_BYTES];
        let idx = chunk_byte_index(3, 4, 5);
        blocks[idx..idx + BLOCK_BYTES].copy_from_slice(&7u16.to_le_bytes());
        let chunk = test_chunk_data(blocks.clone(), crate::api::ChunkEncoding::Raw, 0);

        assert_eq!(
            decode_chunk_blocks(&chunk).expect("raw chunk decodes"),
            blocks
        );
    }

    #[test]
    fn decode_chunk_blocks_rejects_short_raw_chunk() {
        let chunk = test_chunk_data(vec![0; 8], crate::api::ChunkEncoding::Raw, 0);

        let err = decode_chunk_blocks(&chunk).expect_err("short raw chunk must fail");

        assert!(err.contains("raw chunk has 8 bytes"));
    }

    #[test]
    fn decode_chunk_blocks_accepts_rle_full_chunk() {
        let mut encoded = 9u16.to_le_bytes().to_vec();
        push_test_uvarint(&mut encoded, (SERIALIZED_CHUNK_BYTES / BLOCK_BYTES) as u64);
        let chunk = test_chunk_data(
            encoded,
            crate::api::ChunkEncoding::Rle,
            SERIALIZED_CHUNK_BYTES as u32,
        );

        let decoded = decode_chunk_blocks(&chunk).expect("RLE chunk decodes");

        assert_eq!(decoded.len(), SERIALIZED_CHUNK_BYTES);
        assert!(
            decoded
                .chunks_exact(BLOCK_BYTES)
                .all(|bytes| { u16::from_le_bytes([bytes[0], bytes[1]]) == 9 })
        );
    }

    #[test]
    fn decode_chunk_blocks_rejects_rle_wrong_uncompressed_size() {
        let chunk = test_chunk_data(vec![], crate::api::ChunkEncoding::Rle, 12);

        let err = decode_chunk_blocks(&chunk).expect_err("bad RLE size must fail");

        assert!(err.contains("uncompressed_size=12"));
    }

    #[test]
    fn decode_serialized_chunk_rle_rejects_malformed_runs() {
        assert!(decode_serialized_chunk_rle(&[1], SERIALIZED_CHUNK_BYTES).is_err());

        let mut zero_run = 1u16.to_le_bytes().to_vec();
        zero_run.push(0);
        assert!(decode_serialized_chunk_rle(&zero_run, SERIALIZED_CHUNK_BYTES).is_err());

        let truncated_varint = vec![1, 0, 0x80];
        assert!(decode_serialized_chunk_rle(&truncated_varint, SERIALIZED_CHUNK_BYTES).is_err());
    }

    #[test]
    fn decode_chunk_blocks_rejects_unknown_encoding() {
        let chunk = crate::api::ChunkData {
            x: 0,
            z: 0,
            blocks: vec![0; SERIALIZED_CHUNK_BYTES],
            encoding: 99,
            uncompressed_size: 0,
        };

        let err = decode_chunk_blocks(&chunk).expect_err("unknown encoding must fail");

        assert!(err.contains("unsupported chunk encoding 99"));
    }

    #[test]
    fn chunk_non_empty_subchunk_mask_tracks_solid_subchunks() {
        let mut blocks = vec![0u8; CHUNK_W * CHUNK_H * CHUNK_D * BLOCK_BYTES];
        let lower_idx = chunk_byte_index(1, 7, 2);
        let upper_idx = chunk_byte_index(3, SUBCHUNK_H * 4 + 5, 4);
        blocks[lower_idx..lower_idx + BLOCK_BYTES].copy_from_slice(&1u16.to_le_bytes());
        blocks[upper_idx..upper_idx + BLOCK_BYTES].copy_from_slice(&2u16.to_le_bytes());

        let mask = compute_chunk_non_empty_subchunks(&blocks);

        assert!(subchunk_mask_has_blocks(mask, 0));
        assert!(subchunk_mask_has_blocks(mask, 4));
        assert!(!subchunk_mask_has_blocks(mask, 1));
        assert!(!subchunk_mask_has_blocks(mask, -1));
        assert!(!subchunk_mask_has_blocks(mask, SUBCHUNKS_PER_CHUNK));
        assert!(chunk_subchunk_has_blocks(&blocks, 0));
        assert!(chunk_subchunk_has_blocks(&blocks, 4));
        assert!(!chunk_subchunk_has_blocks(&blocks, 1));
        assert_eq!(compute_chunk_non_empty_subchunks(&[]), 0);
    }

    #[test]
    fn rust_ext_build_profile_tracks_debug_assertions() {
        let expected = if cfg!(debug_assertions) {
            "debug"
        } else {
            "release"
        };

        assert_eq!(rust_ext_build_profile(), expected);
    }

    #[test]
    fn copy_chunk_region_copies_rows_without_partial_blocks() {
        let mut source = vec![0u8; CHUNK_W * CHUNK_H * CHUNK_D * BLOCK_BYTES];
        let mut padded = vec![0u8; PADDED_W * PADDED_H * PADDED_D * BLOCK_BYTES];
        for (offset, block_id) in [11u16, 12, 13].into_iter().enumerate() {
            let idx = chunk_byte_index(2 + offset, 7, 3);
            source[idx..idx + BLOCK_BYTES].copy_from_slice(&block_id.to_le_bytes());
        }

        copy_chunk_region(
            &source,
            &mut padded,
            ChunkRegion::new(2..5, 7..8, 3..4),
            (4, 6, 5),
        );

        for (offset, expected) in [11u16, 12, 13].into_iter().enumerate() {
            let idx = padded_byte_index(4 + offset, 6, 5);
            assert_eq!(u16::from_le_bytes([padded[idx], padded[idx + 1]]), expected);
        }
        assert_eq!(bounded_block_copy_bytes(6, 5, 6), 4);
        assert_eq!(bounded_block_copy_bytes(6, 6, 1), 0);
    }

    #[test]
    fn neighbor_geometry_refresh_mask_tracks_added_and_removed_subchunks() {
        let lower = 1u32 << 0;
        let upper = 1u32 << 7;
        let out_of_range = 1u32 << SUBCHUNKS_PER_CHUNK;

        assert_eq!(
            neighbor_geometry_refresh_mask(0, lower | upper),
            lower | upper
        );
        assert_eq!(neighbor_geometry_refresh_mask(lower, upper), lower | upper);
        assert_eq!(neighbor_geometry_refresh_mask(out_of_range, lower), lower);
    }

    #[test]
    fn dirty_partial_subchunk_counts_track_skipped_full_rebuild_work() {
        let previous = (1u32 << 0) | (1u32 << 1);
        let current = previous | (1u32 << 2);
        let rebuild = (1u32 << 1) | (1u32 << 2);

        assert_eq!(dirty_partial_subchunk_count(previous, current, rebuild), 2);
        assert_eq!(dirty_partial_saved_subchunks(previous, current, rebuild), 1);
        assert_eq!(
            dirty_partial_saved_subchunks(previous, current, 1u32 << SUBCHUNKS_PER_CHUNK),
            3
        );
    }

    #[test]
    fn dirty_edge_neighbors_only_include_touched_edges() {
        assert_eq!(
            dirty_edge_neighbors(4, 5, DIRTY_EDGE_NEG_X | DIRTY_EDGE_POS_Z),
            vec![(3, 5), (4, 6)]
        );
        assert!(dirty_edge_neighbors(4, 5, 0).is_empty());
    }

    #[test]
    fn identical_chunk_update_skips_geometry_refresh() {
        assert!(chunk_update_needs_geometry_refresh(None));
        assert!(!chunk_update_needs_geometry_refresh(Some(
            ChunkDirtyUpdate::default()
        )));
        assert!(chunk_update_needs_geometry_refresh(Some(
            ChunkDirtyUpdate {
                changed_blocks: 1,
                ..ChunkDirtyUpdate::default()
            }
        )));
    }

    #[test]
    fn chunk_dirty_update_tracks_bounds_masks_and_edges() {
        let mut previous = vec![0u8; CHUNK_W * CHUNK_H * CHUNK_D * BLOCK_BYTES];
        let mut current = previous.clone();

        let middle_idx = chunk_byte_index(4, 35, 5);
        current[middle_idx..middle_idx + BLOCK_BYTES].copy_from_slice(&3u16.to_le_bytes());
        let subchunk_edge_idx = chunk_byte_index(10, SUBCHUNK_H - 1, 12);
        current[subchunk_edge_idx..subchunk_edge_idx + BLOCK_BYTES]
            .copy_from_slice(&4u16.to_le_bytes());
        let chunk_edge_idx = chunk_byte_index(0, 64, CHUNK_D - 1);
        current[chunk_edge_idx..chunk_edge_idx + BLOCK_BYTES].copy_from_slice(&5u16.to_le_bytes());
        previous[chunk_byte_index(8, 90, 8)..chunk_byte_index(8, 90, 8) + BLOCK_BYTES]
            .copy_from_slice(&6u16.to_le_bytes());

        let update = chunk_dirty_update(&previous, &current);

        assert_eq!(update.changed_blocks, 4);
        assert_eq!(
            update.changed_subchunk_mask,
            (1u32 << 0) | (1u32 << 1) | (1u32 << 2)
        );
        assert_eq!(
            update.rebuild_subchunk_mask,
            (1u32 << 0) | (1u32 << 1) | (1u32 << 2)
        );
        assert_eq!(update.edge_mask, DIRTY_EDGE_NEG_X | DIRTY_EDGE_POS_Z);
        assert_eq!(
            update.bounds,
            Some(ChunkDirtyBounds {
                min_x: 0,
                min_y: SUBCHUNK_H - 1,
                min_z: 5,
                max_x: 10,
                max_y: 90,
                max_z: CHUNK_D - 1,
            })
        );

        let mut perf = PerfStats::default();
        perf.record_chunk_update(None);
        perf.record_chunk_update(Some(update));
        assert_eq!(perf.chunk_initial_loads, 1);
        assert_eq!(perf.chunk_replacement_updates, 1);
        assert_eq!(perf.dirty_chunk_updates, 1);
        assert_eq!(perf.dirty_block_changes, 4);
        assert_eq!(perf.dirty_changed_subchunks, 3);
        assert_eq!(perf.dirty_rebuild_subchunks, 3);
        assert_eq!(perf.dirty_edge_chunk_updates, 1);
        assert_eq!(perf.last_dirty_block_changes, 4);
        assert_eq!(perf.last_dirty_rebuild_subchunks, 3);
    }

    #[test]
    fn perf_records_dirty_edge_neighbor_refresh_work() {
        let mut perf = PerfStats::default();

        perf.record_dirty_edge_neighbor_refresh(2, 4);
        assert_eq!(perf.dirty_edge_neighbor_refresh_chunks, 2);
        assert_eq!(perf.dirty_edge_neighbor_refresh_subchunks, 4);
        assert_eq!(perf.last_dirty_edge_neighbor_refresh_chunks, 2);
        assert_eq!(perf.last_dirty_edge_neighbor_refresh_subchunks, 4);

        perf.record_dirty_edge_neighbor_refresh(0, 0);
        assert_eq!(perf.dirty_edge_neighbor_refresh_chunks, 2);
        assert_eq!(perf.dirty_edge_neighbor_refresh_subchunks, 4);
        assert_eq!(perf.last_dirty_edge_neighbor_refresh_chunks, 0);
        assert_eq!(perf.last_dirty_edge_neighbor_refresh_subchunks, 0);
    }

    #[test]
    fn perf_records_mesh_queue_churn() {
        let mut perf = PerfStats::default();

        perf.record_mesh_queue_enqueue(3, MeshQueueReason::GeometryChanged, true);
        perf.record_mesh_queue_enqueue(3, MeshQueueReason::ProxyRefresh, false);
        perf.record_mesh_queue_frame(1, 2, 1, 1, 1, 1);
        perf.record_mesh_queue_enqueue(5, MeshQueueReason::ProxyRefresh, true);

        assert_eq!(perf.mesh_queue_depth, 5);
        assert_eq!(perf.max_mesh_queue_depth, 5);
        assert_eq!(perf.mesh_queue_enqueues, 2);
        assert_eq!(perf.mesh_queue_geometry_enqueues, 1);
        assert_eq!(perf.mesh_queue_proxy_refresh_enqueues, 1);
        assert_eq!(perf.mesh_queue_duplicate_enqueues, 1);
        assert_eq!(perf.mesh_queue_geometry_duplicate_enqueues, 0);
        assert_eq!(perf.mesh_queue_proxy_refresh_duplicate_enqueues, 1);
        assert_eq!(perf.mesh_queue_drained, 2);
        assert_eq!(perf.mesh_queue_geometry_drained, 1);
        assert_eq!(perf.mesh_queue_proxy_refresh_drained, 1);
        assert_eq!(perf.mesh_queue_stale_drops, 1);
        assert_eq!(perf.mesh_queue_missing_chunk_drops, 1);
        assert_eq!(perf.last_mesh_queue_drained, 2);
        assert_eq!(perf.last_mesh_queue_geometry_drained, 1);
        assert_eq!(perf.last_mesh_queue_proxy_refresh_drained, 1);
        assert_eq!(perf.last_mesh_queue_stale_drops, 1);
        assert_eq!(perf.last_mesh_queue_missing_chunk_drops, 1);
    }

    #[test]
    fn perf_records_collision_refresh_churn() {
        let mut first = CollisionRefreshBatch::default();
        first.record(CollisionRefreshResult::MissingMesh);
        first.record(CollisionRefreshResult::SkippedEmpty);
        first.record(CollisionRefreshResult::Unchanged);

        let mut second = CollisionRefreshBatch::default();
        second.record(CollisionRefreshResult::Rebuilt);

        assert_eq!(first.checked, 3);
        assert_eq!(first.skipped_empty, 1);
        assert_eq!(first.missing_meshes, 1);
        assert_eq!(first.unchanged, 1);
        assert_eq!(first.rebuilt, 0);

        let mut perf = PerfStats::default();
        perf.record_collision_refresh(first);
        perf.record_collision_refresh(second);

        assert_eq!(perf.collision_refresh_checked, 4);
        assert_eq!(perf.collision_refresh_skipped_empty, 1);
        assert_eq!(perf.collision_refresh_missing_meshes, 1);
        assert_eq!(perf.collision_refresh_unchanged, 1);
        assert_eq!(perf.collision_refresh_rebuilt, 1);
        assert_eq!(perf.last_collision_refresh_checked, 1);
        assert_eq!(perf.last_collision_refresh_skipped_empty, 0);
        assert_eq!(perf.last_collision_refresh_missing_meshes, 0);
        assert_eq!(perf.last_collision_refresh_unchanged, 0);
        assert_eq!(perf.last_collision_refresh_rebuilt, 1);

        perf.record_collision_refresh_queue_enqueue(2, true);
        perf.record_collision_refresh_queue_enqueue(2, false);
        perf.record_collision_refresh_queue_frame(1, 3, 1, 1);

        assert_eq!(perf.collision_refresh_queue_depth, 1);
        assert_eq!(perf.max_collision_refresh_queue_depth, 2);
        assert_eq!(perf.collision_refresh_queue_enqueues, 1);
        assert_eq!(perf.collision_refresh_queue_duplicate_enqueues, 1);
        assert_eq!(perf.collision_refresh_queue_drained, 3);
        assert_eq!(perf.collision_refresh_queue_stale_drops, 1);
        assert_eq!(perf.collision_refresh_queue_missing_chunk_drops, 1);
        assert_eq!(perf.last_collision_refresh_queue_drained, 3);
        assert_eq!(perf.last_collision_refresh_queue_stale_drops, 1);
        assert_eq!(perf.last_collision_refresh_queue_missing_chunk_drops, 1);
    }

    #[test]
    fn perf_records_mesh_phase_timings() {
        let mut perf = PerfStats::default();
        let first = TerrainMeshPhaseTiming {
            padded_ms: 2.0,
            packed_faces_ms: 4.0,
            gpu_upload_ms: 6.0,
            cpu_mesh_ms: 8.0,
            array_mesh_ms: 10.0,
            node_counts_ms: 12.0,
        };
        let second = TerrainMeshPhaseTiming {
            padded_ms: 4.0,
            packed_faces_ms: 2.0,
            gpu_upload_ms: 8.0,
            cpu_mesh_ms: 6.0,
            array_mesh_ms: 14.0,
            node_counts_ms: 10.0,
        };

        perf.record_mesh(test_mesh_record(
            1,
            0,
            1,
            MeshQueueReason::GeometryChanged,
            false,
            false,
            false,
            1.0,
            first,
            0,
        ));
        perf.record_mesh(test_mesh_record(
            1,
            0,
            1,
            MeshQueueReason::ProxyRefresh,
            false,
            false,
            false,
            1.0,
            second,
            0,
        ));

        assert_eq!(perf.last_mesh_phase.cpu_mesh_ms, 6.0);
        assert_eq!(perf.avg_mesh_phase.padded_ms, 3.0);
        assert_eq!(perf.avg_mesh_phase.array_mesh_ms, 12.0);
        assert_eq!(perf.max_mesh_phase.gpu_upload_ms, 8.0);
        assert_eq!(perf.max_mesh_phase.node_counts_ms, 12.0);
        assert_eq!(perf.max_mesh_reason, Some(MeshQueueReason::ProxyRefresh));
        assert_eq!(perf.max_mesh_job_phase.cpu_mesh_ms, 6.0);
        assert_eq!(perf.max_mesh_vertices, 1);
    }

    #[test]
    fn perf_records_max_array_mesh_context_independently() {
        let mut perf = PerfStats::default();
        let slow_mesh_phase = TerrainMeshPhaseTiming {
            padded_ms: 1.0,
            packed_faces_ms: 2.0,
            gpu_upload_ms: 3.0,
            cpu_mesh_ms: 4.0,
            array_mesh_ms: 1.0,
            node_counts_ms: 0.0,
        };
        let slow_array_mesh_phase = TerrainMeshPhaseTiming {
            padded_ms: 0.5,
            packed_faces_ms: 0.4,
            gpu_upload_ms: 0.3,
            cpu_mesh_ms: 0.2,
            array_mesh_ms: 12.0,
            node_counts_ms: 0.1,
        };

        perf.record_mesh(test_mesh_record(
            30,
            30,
            30,
            MeshQueueReason::GeometryChanged,
            false,
            false,
            false,
            5.0,
            slow_mesh_phase,
            1,
        ));
        perf.record_mesh(test_mesh_record(
            4,
            0,
            6,
            MeshQueueReason::ProxyRefresh,
            true,
            true,
            false,
            1.0,
            slow_array_mesh_phase,
            0,
        ));

        assert_eq!(perf.max_mesh_reason, Some(MeshQueueReason::GeometryChanged));
        assert_eq!(
            perf.max_array_mesh_reason,
            Some(MeshQueueReason::ProxyRefresh)
        );
        assert!(perf.max_array_mesh_cpu_proxy_mesh);
        assert!(perf.max_array_mesh_compact_shadow_proxy_mesh);
        assert!(!perf.max_array_mesh_compact_collision_proxy_mesh);
        assert_eq!(perf.max_array_mesh_collision_bodies, 0);
        assert_eq!(perf.max_array_mesh_vertices, 4);
        assert_eq!(perf.max_array_mesh_reported_vertices, 6);
        assert_eq!(perf.max_array_mesh_job_phase.array_mesh_ms, 12.0);
    }

    #[test]
    fn perf_records_compact_shadow_proxy_normal_savings() {
        let mut perf = PerfStats::default();

        perf.record_mesh(test_mesh_record(
            24,
            0,
            24,
            MeshQueueReason::GeometryChanged,
            true,
            true,
            false,
            1.0,
            TerrainMeshPhaseTiming::default(),
            0,
        ));

        assert_eq!(perf.last_normals, 0);
        assert_eq!(perf.total_normals, 0);
        assert_eq!(perf.compact_shadow_proxy_normals_saved, 24);

        perf.record_mesh(test_mesh_record(
            12,
            12,
            12,
            MeshQueueReason::GeometryChanged,
            true,
            false,
            false,
            1.0,
            TerrainMeshPhaseTiming::default(),
            0,
        ));

        assert_eq!(perf.last_normals, 12);
        assert_eq!(perf.total_normals, 12);
        assert_eq!(perf.compact_shadow_proxy_normals_saved, 24);

        perf.record_mesh(test_mesh_record(
            18,
            0,
            18,
            MeshQueueReason::GeometryChanged,
            true,
            false,
            true,
            1.0,
            TerrainMeshPhaseTiming::default(),
            0,
        ));

        assert_eq!(perf.compact_collision_proxy_meshes_built, 1);
        assert_eq!(perf.compact_collision_proxy_normals_saved, 18);
        assert_eq!(perf.compact_shadow_proxy_normals_saved, 24);
    }
}
