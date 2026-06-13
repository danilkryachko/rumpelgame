# World Streaming

This document tracks the chunk-loading path and planned optimizations for faster world startup and movement streaming.

## Current Baseline

- Server chunks are `32 x 32 x 512`.
- `world.Chunk.Serialize()` emits a full little-endian `u16` block array.
- A full raw chunk payload is `1,048,576` bytes before protobuf and TCP framing.
- `server/pkg/network` sends RLE `ChunkData.blocks` by default after the Rust client decodes them back to the same raw block bytes.
- `RUMPELMC_SERVER_CHUNK_ENCODING=raw` switches chunk payloads back to the raw full chunk rollback path.
- The default server stream sends up to `64` chunks per update, ordered nearest-first by chunk distance.
- `RUMPELMC_SERVER_CHUNKS_PER_UPDATE=6` restores the previous conservative stream batch.
- The default first post-connect stream uses bootstrap radius `0`, sending only the current chunk first; normal position updates then continue with the full view distance.
- `RUMPELMC_SERVER_BOOTSTRAP_RADIUS=1` restores the previous default startup stream; `RUMPELMC_SERVER_BOOTSTRAP_RADIUS=2` restores the earlier wider startup stream; `RUMPELMC_SERVER_BOOTSTRAP_RADIUS=full` restores full view-distance startup streaming.

## First Optimization Path

Use a compatible staged rollout:

1. Keep the existing raw chunk format as an explicit rollback path.
2. Add a deterministic block-run RLE codec over the existing serialized chunk bytes.
3. Benchmark raw serialize, RLE encode, and RLE decode on representative chunks.
4. Use the new compatible `ChunkData.encoding` and `ChunkData.uncompressed_size` fields for encoded chunks.
5. Make encoded chunk streaming the default only after visual smoke and movement streaming evidence pass, while preserving `RUMPELMC_SERVER_CHUNK_ENCODING=raw` rollback.

## Current RLE Evidence

The first server-side codec slice added `EncodeSerializedChunkRLE` and `DecodeSerializedChunkRLE` without changing storage behavior. The follow-up protocol slice added an opt-in RLE path, and the validated default-on slice makes RLE the server default while keeping `RUMPELMC_SERVER_CHUNK_ENCODING=raw` as rollback.

On the current flat generated chunk, the raw payload is `1,048,576` bytes and the RLE payload is below `64` bytes because the chunk contains long vertical strata and air runs.

Local benchmark command:

```sh
cd server
go test ./pkg/world -bench 'Benchmark(ChunkSerializeFlat|EncodeSerializedChunkRLEFlat|DecodeSerializedChunkRLEFlat)' -benchtime=100ms -run '^$'
```

Latest local result on Apple M4:

- `BenchmarkChunkSerializeFlat`: about `431597 ns/op`, `1,052,144 B/op`.
- `BenchmarkEncodeSerializedChunkRLEFlat`: about `421359 ns/op`, `7,662 B/op`.
- `BenchmarkDecodeSerializedChunkRLEFlat`: about `268477 ns/op`, `1,053,090 B/op`.

Latest protocol-level batch guard for three generated flat chunks:

```sh
cd server
go test ./pkg/network -run 'TestRLEChunkBatchShrinksPayloadAndWireBytes|TestSendChunkCanUseRLEPayload' -v
```

- RAW payload bytes: `3,145,728`.
- RLE payload bytes: `54`.
- RAW framed wire bytes: `3,145,786`.
- RLE framed wire bytes: `118`.
- RLE stayed below `1%` of RAW for both payload and framed wire bytes in this guard.

The 2026-06-13 handshake fix makes the Rust client send an initial `ClientPosition` packet immediately after connecting. The server waits briefly for that packet before starting the initial stream, treats a closed probe as a closed probe instead of sending initial chunks into it, and keeps the old `(0,0)` initial stream fallback when no packet arrives before the timeout.

Latest visual movement smoke evidence from 2026-06-13 used the release Rust extension profile and direct Godot launch because earlier wrapper attempts were invalid when the profile shim was not active in the same shell:

- RAW movement log: `logs/world_streaming_raw_visual_20260613/movement.godot.log`.
- RLE movement marker: `logs/world_streaming_rle_visual_20260613/movement.godot.log`.
- RLE server metrics for that movement run: `logs/world_streaming_rle_visual_20260613/godot.log`.
- Both runs passed `smoke_err=0`, `motion_steps=4`, `motion_chunks=4`, `current_chunk_loaded=1`, `current_chunk_collision=2`, `ground_hits=9`, and ended at `current_chunk="3,2"`.
- The RLE client decoded streamed chunks back to `blocks=1048576` before the normal terrain path consumed them.
- RAW movement totals: `132` chunks, raw bytes `138,412,032`, payload bytes `138,412,032`, framed wire bytes `138,414,760`.
- RLE movement totals: `132` chunks, raw bytes `138,412,032`, payload bytes `2,646`, framed wire bytes `5,640`.
- In this generated-world movement smoke, RLE framed wire bytes were about `0.0041%` of RAW framed wire bytes.

The reproducible wrapper gate for the same path is:

```sh
RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE=1 RUMPELMC_GODOT_RUST_EXT_PROFILE=release scripts/world_streaming_rle_movement_smoke.sh logs/world_streaming_rle_wrapper_20260613
```

It rebuilds `server/server`, requires port `25565` to be free, starts the normal movement stress with `RUMPELMC_SERVER_CHUNK_ENCODING=rle` and `RUMPELMC_SERVER_CHUNK_STREAM_METRICS=1`, validates the movement marker, validates that the client decoded RLE chunks to `blocks=1048576`, requires RLE payload and framed wire bytes to stay below `1%` of raw bytes, writes `world-streaming-rle-summary.txt`, and cleans up the local server.

Fresh wrapper result:

- Summary: `logs/world_streaming_rle_wrapper_20260613/world-streaming-rle-summary.txt`.
- Status: `pass`.
- Batches/chunks: `22` / `132`.
- Raw/payload/wire bytes: `138,412,032` / `2,646` / `5,640`.
- Payload/wire percent of raw: `0.001912%` / `0.004075%`.

Fresh default-on result with `RUMPELMC_SERVER_CHUNK_ENCODING` unset:

- Summary: `logs/world_streaming_default_rle_20260613/world-streaming-default-rle-summary.txt`.
- Status: `pass`.
- Batches/chunks: `22` / `132`.
- Raw/payload/wire bytes: `138,412,032` / `2,646` / `5,640`.
- Payload/wire percent of raw: `0.001912%` / `0.004075%`.

The RAW-vs-RLE comparison gate is:

```sh
RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE=1 RUMPELMC_GODOT_RUST_EXT_PROFILE=release scripts/world_streaming_chunk_encoding_compare.sh logs/world_streaming_encoding_compare_20260613
```

It runs the same movement stress twice, first with `RUMPELMC_SERVER_CHUNK_ENCODING=raw` and then with `rle`, compares normalized payload and wire bytes per raw streamed byte, and writes `world-streaming-encoding-compare-summary.txt`. The RLE run may legitimately stream more chunks in the same smoke window when the transport is faster, so this gate does not require identical chunk counts.

Fresh default-on comparison result:

- Summary: `logs/world_streaming_encoding_compare_default_final2_20260613/world-streaming-encoding-compare-summary.txt`.
- Status: `pass`.
- RAW chunks/raw bytes: `138` / `144,703,488`.
- RLE chunks/raw bytes: `138` / `144,703,488`.
- RAW payload/wire bytes: `144,703,488` / `144,706,330`.
- RLE payload/wire bytes: `2,754` / `5,874`.
- RAW payload/wire percent of raw: `100.000000%` / `100.001964%`.
- RLE payload/wire percent of raw: `0.001903%` / `0.004059%`.

The RLE batch-size comparison gate is:

```sh
RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE=1 RUMPELMC_GODOT_RUST_EXT_PROFILE=release /bin/sh scripts/world_streaming_batch_compare.sh logs/world_streaming_batch_compare_20260613_retry
```

It runs the same movement stress twice with the default RLE encoding, first with rollback batch `RUMPELMC_SERVER_CHUNKS_PER_UPDATE=6` and then with candidate/default batch `64`, validates movement/collision/ground/upload markers, records chunk stream metrics, and writes `world-streaming-batch-compare-summary.txt`.

Fresh batch comparison result:

- Summary: `logs/world_streaming_batch_compare_20260613_retry/world-streaming-batch-compare-summary.txt`.
- Status: `pass`.
- Batch `6`: `22` stream batches, `132` chunks, payload/wire percent of raw `0.001912%` / `0.004075%`, `terrain_queue_max_ms=2.065`, `process_wall_p95_ms=0.035`, `gpu_compositor_submit_max_ms=0.109`.
- Batch `64`: `8` stream batches, `394` chunks, payload/wire percent of raw `0.001782%` / `0.004168%`, `terrain_queue_max_ms=1.560`, `process_wall_p95_ms=0.036`, `gpu_compositor_submit_max_ms=0.109`.

Fresh default batch `64` result with `RUMPELMC_SERVER_CHUNKS_PER_UPDATE` unset:

- Summary: `logs/world_streaming_default_batch64_20260613/world-streaming-default-batch64-summary.txt`.
- Status: `pass`.
- Batches/chunks: `8` / `394`.
- Raw/payload/wire bytes: `413,138,944` / `7,362` / `17,219`.
- Payload/wire percent of raw: `0.001782%` / `0.004168%`.
- Client markers: `current_chunk_loaded=1`, `current_chunk_collision=2`, `ground_hits=9`, `gpu_upload_fail=0`, and `chunk_initial=394`.

Fresh post-default batch comparison result:

- Summary: `logs/world_streaming_batch_default64_compare_20260613/world-streaming-batch-compare-summary.txt`.
- Status: `pass`.
- Rollback batch `6`: `22` stream batches, `132` chunks, `terrain_queue_max_ms=1.648`, `process_wall_p95_ms=0.038`, `gpu_compositor_submit_max_ms=0.138`.
- Default batch `64`: `8` stream batches, `394` chunks, `terrain_queue_max_ms=1.903`, `process_wall_p95_ms=0.038`, `gpu_compositor_submit_max_ms=0.159`.

## Bootstrap Radius

The server sends a smaller first stream around the initial client position before normal `RUMPELMC_SERVER_VIEW_DISTANCE` updates take over. Leaving `RUMPELMC_SERVER_BOOTSTRAP_RADIUS` unset uses the default radius `0`; set it to `1` to restore the previous default startup stream, `2` to restore the earlier wider startup stream, or `full` to restore full-radius startup streaming.

Use it to tune faster time-to-current-chunk without changing chunk encoding, batch size, protocol, storage, world generation, or client decode behavior:

```sh
RUMPELMC_SERVER_BOOTSTRAP_RADIUS=0 RUMPELMC_SERVER_CHUNK_STREAM_METRICS=1
```

The bootstrap-radius comparison gate is:

```sh
/bin/sh scripts/world_streaming_bootstrap_compare.sh logs/world_streaming_bootstrap_compare_20260613
```

It runs the same movement stress twice with default RLE encoding and batch `64`: first with rollback full-radius startup, then with candidate/default bootstrap radius `0`. It validates movement/collision/ground/upload markers, requires the candidate first stream to be smaller than the full startup stream, and writes `world-streaming-bootstrap-compare-summary.txt`.

Fresh opt-in bootstrap radius result:

- Summary: `logs/world_streaming_bootstrap_radius2_20260613/world-streaming-bootstrap-radius-summary.txt`.
- Status: `pass`.
- First stream: `radius=2`, `13` chunks, raw/payload/wire bytes `13,631,488` / `413` / `701`, elapsed `39.793ms`.
- Full run: `9` stream batches, `394` chunks, raw/payload/wire bytes `413,138,944` / `7,362` / `17,219`.
- Client markers: `current_chunk_loaded=1`, `current_chunk_collision=2`, `ground_hits=9`, `gpu_upload_fail=0`, and `chunk_initial=394`.

Fresh bootstrap comparison result:

- Summary: `logs/world_streaming_bootstrap_compare_20260613/world-streaming-bootstrap-compare-summary.txt`.
- Status: `pass`.
- Full startup: first stream `radius=10`, `64` chunks, total `394` chunks over `8` batches, `terrain_queue_max_ms=1.183`, `process_wall_p95_ms=0.037`, `gpu_compositor_submit_max_ms=0.126`.
- Bootstrap radius `2`: first stream `radius=2`, `13` chunks, total `394` chunks over `9` batches, `terrain_queue_max_ms=1.577`, `process_wall_p95_ms=0.034`, `gpu_compositor_submit_max_ms=0.105`.

Fresh post-default bootstrap comparison result:

- Summary: `logs/world_streaming_bootstrap_default2_compare_20260613/world-streaming-bootstrap-compare-summary.txt`.
- Status: `pass`.
- Rollback full startup: first stream `radius=10`, `64` chunks, total `394` chunks over `8` batches, `terrain_queue_max_ms=1.436`, `process_wall_p95_ms=0.038`, `gpu_compositor_submit_max_ms=0.291`.
- Default bootstrap radius `2`: first stream `radius=2`, `13` chunks, total `394` chunks over `9` batches, `terrain_queue_max_ms=1.426`, `process_wall_p95_ms=0.037`, `gpu_compositor_submit_max_ms=0.139`.

Fresh next-candidate bootstrap comparison result:

- Summary: `logs/world_streaming_bootstrap_radius1_compare_20260613/world-streaming-bootstrap-compare-summary.txt`.
- Status: `pass`.
- Rollback full startup: first stream `radius=10`, `64` chunks, total `394` chunks over `8` batches, `terrain_queue_max_ms=1.995`, `process_wall_p95_ms=0.039`, `gpu_compositor_submit_max_ms=0.251`.
- Candidate bootstrap radius `1`: first stream `radius=1`, `5` chunks, total `394` chunks over `9` batches, `terrain_queue_max_ms=1.758`, `process_wall_p95_ms=0.045`, `gpu_compositor_submit_max_ms=0.109`.

Fresh post-default radius `1` comparison result:

- Summary: `logs/world_streaming_bootstrap_default1_compare_20260613/world-streaming-bootstrap-compare-summary.txt`.
- Status: `pass`.
- Rollback full startup: first stream `radius=10`, `64` chunks, total `394` chunks over `8` batches, `terrain_queue_max_ms=1.276`, `process_wall_p95_ms=0.036`, `gpu_compositor_submit_max_ms=0.162`.
- Default bootstrap radius `1`: first stream `radius=1`, `5` chunks, total `394` chunks over `9` batches, `terrain_queue_max_ms=1.508`, `process_wall_p95_ms=0.039`, `gpu_compositor_submit_max_ms=0.129`.

Fresh current-chunk bootstrap candidate result:

- Summary: `logs/world_streaming_bootstrap_radius0_compare_20260613/world-streaming-bootstrap-compare-summary.txt`.
- Status: `pass`.
- Rollback full startup: first stream `radius=10`, `64` chunks, total `394` chunks over `8` batches, `terrain_queue_max_ms=2.367`, `process_wall_p95_ms=0.050`, `gpu_compositor_submit_max_ms=0.128`.
- Candidate bootstrap radius `0`: first stream `radius=0`, `1` chunk, total `394` chunks over `9` batches, `terrain_queue_max_ms=2.107`, `process_wall_p95_ms=0.053`, `gpu_compositor_submit_max_ms=0.155`.

Fresh post-default radius `0` comparison result:

- Summary: `logs/world_streaming_bootstrap_default0_compare_20260613/world-streaming-bootstrap-compare-summary.txt`.
- Status: `pass`.
- Rollback full startup: first stream `radius=10`, `64` chunks, total `394` chunks over `8` batches, `terrain_queue_max_ms=1.989`, `process_wall_p95_ms=0.033`, `gpu_compositor_submit_max_ms=0.224`.
- Default bootstrap radius `0`: first stream `radius=0`, `1` chunk, total `394` chunks over `9` batches, `terrain_queue_max_ms=1.728`, `process_wall_p95_ms=0.044`, `gpu_compositor_submit_max_ms=0.102`.

Fresh initial player startup contract result:

- Summary: `logs/world_streaming_initial_contract_default0_20260613/world-streaming-bootstrap-compare-summary.txt`.
- Status: `pass`.
- The Rust client now derives the initial position packet, spawn position, and pre-spawn mesh subchunks from one startup contract.
- Rollback full startup: first stream `radius=10`, `64` chunks, total `394` chunks over `8` batches, `terrain_queue_max_ms=1.008`, `process_wall_p95_ms=0.022`, `gpu_compositor_submit_max_ms=0.339`.
- Default bootstrap radius `0`: first stream `radius=0`, `1` chunk, total `394` chunks over `9` batches, `terrain_queue_max_ms=1.340`, `process_wall_p95_ms=0.020`, `gpu_compositor_submit_max_ms=0.195`.

Fresh pre-spawn startup queue hint result:

- Summary: `logs/world_streaming_startup_queue_hint_default0_20260613/world-streaming-bootstrap-compare-summary.txt`.
- Status: `pass`.
- The Rust client now uses the startup chunk contract as the mesh/collision queue hint until `current_player_chunk` is available, while collision and shadow fallback still target only the startup chunk before player spawn.
- Rollback full startup: first stream `radius=10`, `64` chunks, total `394` chunks over `8` batches, `terrain_queue_max_ms=0.915`, `process_wall_p95_ms=0.019`, `gpu_compositor_submit_max_ms=0.124`.
- Default bootstrap radius `0`: first stream `radius=0`, `1` chunk, total `394` chunks over `9` batches, `terrain_queue_max_ms=1.487`, `process_wall_p95_ms=0.022`, `gpu_compositor_submit_max_ms=0.158`.

## Stream Metrics

Set `RUMPELMC_SERVER_CHUNK_STREAM_METRICS=1` on the server to log each non-empty chunk stream batch:

```text
Chunk stream batch center=0,0 radius=10 chunks=64 raw_bytes=67108864 payload_bytes=... wire_bytes=... elapsed_ms=... chunks_per_sec=...
```

The metric is off by default and does not change packet payloads. Use it with the default RLE stream and with `RUMPELMC_SERVER_CHUNK_ENCODING=raw` rollback to compare payload shrinkage and batch throughput with the same log shape.

## RLE Protocol Path

RLE is now the default server chunk encoding. Leave `RUMPELMC_SERVER_CHUNK_ENCODING` unset or set it to `rle` to send RLE chunk payloads:

```sh
RUMPELMC_SERVER_CHUNK_STREAM_METRICS=1
```

The server encodes `ChunkData.blocks` as block runs, sets `ChunkData.encoding=CHUNK_ENCODING_RLE`, and sets `ChunkData.uncompressed_size` to `1,048,576`. The Rust client validates the encoded size, decodes RLE back into the full raw block array, and then uses the existing dirty-update, meshing, collision, and GPU upload paths.

Set `RUMPELMC_SERVER_CHUNK_ENCODING=raw` for the rollback path.

## Guardrails

- Keep raw chunk streaming available as an explicit rollback path.
- Do not hand-edit generated protocol files.
- Protocol changes must preserve raw chunk compatibility until the client and server both support the encoded path.
- Storage still persists the exact output of `world.Chunk.Serialize()` unless a separate migration is explicitly planned.
- Add round-trip tests for every encoded chunk format before enabling it in networking.
