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

Visual movement smoke still needs a stable local harness pass before making RLE default. The 2026-06-13 local attempt timed out before producing a marker file; the controlled server log showed an early connect/probe followed by `Failed to send initial chunks: ... broken pipe`, so it is not valid visual evidence.

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
