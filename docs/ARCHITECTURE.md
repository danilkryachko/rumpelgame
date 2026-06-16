# Architecture

## Stack

- **Godot client**: owns the scene tree, window setup, HUD, local server lifecycle helper, lighting, visual smoke harness, and user input surface.
- **Rust GDExtension client logic**: owns TCP networking, packet decode, chunk residency, dirty-update detection, meshing queues, collision refresh queues, GPU terrain upload/render orchestration, local player gameplay glue, debug overlay getters, and perf telemetry.
- **Go server**: owns authoritative world state, chunk generation/loading, block edits, chunk streaming, packet framing, and storage integration.
- **Storage**: RocksDB is the implemented chunk persistence backend. PostgreSQL is approved but has no current implemented role.
- **Protocol**: protobuf packets over TCP with a 4-byte little-endian payload length prefix.

## Current Runtime Flow

1. `client/main.gd` starts or reuses a local Go server, then adds `GameClient` and the HUD.
2. `server/cmd/server/main.go` opens RocksDB, creates `world.World`, creates `network.Server`, and starts the TCP listener.
3. `GameClient` connects to the server and sends `ClientPosition`.
4. The server streams chunks around the client. The first startup stream uses the configured bootstrap radius, then normal updates stream nearest chunks around the player.
5. Chunk packets are framed protobuf `Packet` values. `ChunkData` is RLE by default with a raw rollback path.
6. The Rust client decodes chunk bytes into the full serialized chunk buffer, records dirty-update counters for replacements, and updates chunk residency.
7. Geometry, GPU upload, CPU proxy, and collision work are queued from chunk/subchunk state.
8. Player spawn remains collision-gated on startup readiness.

## Server World And Storage

- `world.World` is the authoritative in-memory world owner.
- `World.ChunksAround` selects chunk coordinates, loads or generates chunks, and returns serialized snapshots for networking.
- `World.SetBlockGlobal` applies block edits and persists dirty chunks through the configured `ChunkStore`.
- RocksDB chunk keys use the stable `c` prefix plus sortable signed big-endian chunk coordinates.
- Persisted chunk payloads are the exact output of `world.Chunk.Serialize()`.
- Current generation uses an explicit `GeneratorConfig` with `seed`, `dimension_id`, and generator `version`; server startup validates `RUMPELMC_WORLD_SEED`, `RUMPELMC_WORLD_DIMENSION_ID`, and `RUMPELMC_WORLD_GENERATOR_VERSION` before creating `World`. The default `flat_v1` path still produces the deterministic flat terrain byte contract. `height_v1` is opt-in and provides deterministic integer-hashed terrain surface height without changing protocol, storage, chunk dimensions, or default generation. `biome_v1`, `cave_v1`, and `resource_v1` are deterministic server-side metadata samplers/catalogs owned by the world package; `biome_height_v1` is an opt-in generator that uses the biome sampler for surface/subsurface block selection, `cave_height_v1` carves `cave_v1` openings below the preserved `height_v1` surface, and `biome_cave_height_v1` combines biome surface/subsurface selection with cave carving. Resource-to-block, structure, broader biome runtime, and default-world quality layers are documented but not active runtime behavior.

## Protocol Contract

- Current packet payload variants are `ChunkData`, `ClientPosition`, and `BlockAction`.
- `ChunkData.blocks` carries either raw serialized chunk bytes or RLE runs over the same serialized bytes.
- `ChunkData.encoding` and `ChunkData.uncompressed_size` are compatibility fields for encoded chunks.
- Block IDs remain the only current wire/storage identity for voxel contents.
- Server and client block material metadata exists as registry-derived behavior for the existing block IDs only. Block IDs remain the only wire/storage identity; transparent material behavior, liquid/emissive runtime traits, and future protocol deltas remain separate work unless new protobuf fields and compatibility tests are added explicitly.

## Client Rust GDExtension

- The client lifecycle model tracks connecting, waiting_chunks, spawning, active, reconnecting, and shutdown.
- The packet reader feeds the main-thread packet queue; packet queue metrics are observational and do not implement backpressure or dropping.
- Chunk replacements run through dirty-update detection. Partial dirty GPU upload is default-on; `RUMPELMC_GPU_TERRAIN_PARTIAL_DIRTY_UPLOAD=0` is the full-rebuild rollback path.
- Local creative hotbar state is client-side gameplay foundation. Server authority for block edits still flows through `BlockAction` and `World.SetBlockGlobal`.
- Reconnect execution, slow-client policy, block-edit broadcast fanout, and opt-in max-client admission with bounded live rejection evidence are guarded; adaptive overload/backpressure behavior remains deferred policy work.

## GPU Terrain Contract

- The visible terrain path uses GPU terrain buffers and RenderingDevice submission through the Rust extension.
- CPU proxy meshes remain responsible for collision and current Godot shadow participation where required.
- Compact proxy and partial dirty paths reduce work while preserving current visible quality.
- Native terrain shadows are scaffolded but inactive while `GPU_TERRAIN_NATIVE_SHADOW_IMPLEMENTED=false`.
- Transparent terrain is scaffolded/planned but inactive while `GPU_TERRAIN_TRANSPARENT_IMPLEMENTED=false`.
- Existing lighting, texture atlas, draw distance, shadows, collision coverage, and texture quality must not be reduced for performance gates unless explicitly requested.

## Observability And Handoff

- `GameClient.get_perf_text()` remains the full machine-readable perf stream for scripts.
- `GameClient.get_debug_overlay_text()` is the compact in-client dev overlay summary.
- HUD perf logs include `run_id=`, `overlay=`, and preserved `perf=` fields.
- Current summary artifacts are indexed by `scripts/observability_logs_cleanup_gate.sh`.
- `scripts/handoff.sh` prints required handoff inputs, current git state, and the current observability artifact index.

## Guardrails

- Do not hand-edit generated protocol files.
- Do not introduce storage engines beyond RocksDB/PostgreSQL without explicit approval.
- Do not change chunk serialization, world generation determinism, packet field meanings, or RocksDB key format without a focused task and tests.
- Do not reformat Godot scene/resource/import files casually.
- Run the narrowest relevant checks for small changes, `./scripts/check.sh fast` for normal code changes, and full/diff guard for broad or sensitive changes.
