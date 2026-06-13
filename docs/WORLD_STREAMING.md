# World Streaming

This document tracks the chunk-loading path and planned optimizations for faster world startup and movement streaming.

## Current Baseline

- Server chunks are `32 x 32 x 512`.
- `world.Chunk.Serialize()` emits a full little-endian `u16` block array.
- A full raw chunk payload is `1,048,576` bytes before protobuf and TCP framing.
- `server/pkg/network` sends raw `ChunkData.blocks` by default.
- `RUMPELMC_SERVER_CHUNK_ENCODING=rle` switches chunk payloads to a compatible RLE protocol path after the Rust client decodes them back to the same raw block bytes.
- The default server stream sends up to `6` chunks per update, ordered nearest-first by chunk distance.

## First Optimization Path

Use a compatible staged rollout:

1. Keep the existing raw chunk format as the default and rollback path.
2. Add a deterministic block-run RLE codec over the existing serialized chunk bytes.
3. Benchmark raw serialize, RLE encode, and RLE decode on representative chunks.
4. Use the new compatible `ChunkData.encoding` and `ChunkData.uncompressed_size` fields for encoded chunks.
5. Gate encoded chunk streaming behind `RUMPELMC_SERVER_CHUNK_ENCODING=rle` until visual smoke and movement streaming evidence pass.

## Current RLE Evidence

The first server-side codec slice adds `EncodeSerializedChunkRLE` and `DecodeSerializedChunkRLE` without changing storage behavior. The follow-up protocol slice keeps raw packets as the default and adds an opt-in RLE path.

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

## Stream Metrics

Set `RUMPELMC_SERVER_CHUNK_STREAM_METRICS=1` on the server to log each non-empty chunk stream batch:

```text
Chunk stream batch center=0,0 chunks=6 raw_bytes=6291456 payload_bytes=... wire_bytes=... elapsed_ms=... chunks_per_sec=...
```

The metric is off by default and does not change packet payloads. Use it with the default raw stream and with `RUMPELMC_SERVER_CHUNK_ENCODING=rle` to compare payload shrinkage and batch throughput with the same log shape.

## Opt-in RLE Protocol Path

Set `RUMPELMC_SERVER_CHUNK_ENCODING=rle` on the server to send RLE chunk payloads:

```sh
RUMPELMC_SERVER_CHUNK_ENCODING=rle RUMPELMC_SERVER_CHUNK_STREAM_METRICS=1
```

The server encodes `ChunkData.blocks` as block runs, sets `ChunkData.encoding=CHUNK_ENCODING_RLE`, and sets `ChunkData.uncompressed_size` to `1,048,576`. The Rust client validates the encoded size, decodes RLE back into the full raw block array, and then uses the existing dirty-update, meshing, collision, and GPU upload paths.

Leave `RUMPELMC_SERVER_CHUNK_ENCODING` unset or set it to `raw` for the rollback/default path.

## Guardrails

- Keep raw chunk streaming as the default rollback path.
- Do not hand-edit generated protocol files.
- Protocol changes must preserve raw chunk compatibility until the client and server both support the encoded path.
- Storage still persists the exact output of `world.Chunk.Serialize()` unless a separate migration is explicitly planned.
- Add round-trip tests for every encoded chunk format before enabling it in networking.
