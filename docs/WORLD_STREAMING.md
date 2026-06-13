# World Streaming

This document tracks the chunk-loading path and planned optimizations for faster world startup and movement streaming.

## Current Baseline

- Server chunks are `32 x 32 x 512`.
- `world.Chunk.Serialize()` emits a full little-endian `u16` block array.
- A full raw chunk payload is `1,048,576` bytes before protobuf and TCP framing.
- `server/pkg/network` currently sends `ChunkData.blocks` as that full raw payload.
- The default server stream sends up to `6` chunks per update, ordered nearest-first by chunk distance.

## First Optimization Path

Use a compatible staged rollout:

1. Keep the existing raw chunk format as the default and rollback path.
2. Add a deterministic block-run RLE codec over the existing serialized chunk bytes.
3. Benchmark raw serialize, RLE encode, and RLE decode on representative chunks.
4. Add a new protocol field or packet variant for encoded chunks only after client/server tests cover both raw and encoded paths.
5. Gate encoded chunk streaming behind an explicit env flag until visual smoke and movement streaming evidence pass.

## Current RLE Evidence

The first server-side codec slice adds `EncodeSerializedChunkRLE` and `DecodeSerializedChunkRLE` without changing storage or wire behavior.

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

## Stream Metrics

Set `RUMPELMC_SERVER_CHUNK_STREAM_METRICS=1` on the server to log each non-empty chunk stream batch:

```text
Chunk stream batch center=0,0 chunks=6 raw_bytes=6291456 wire_bytes=6291534 elapsed_ms=... chunks_per_sec=...
```

The metric is off by default and does not change packet payloads. It exists to compare raw and future encoded chunk streaming with the same log shape.

## Guardrails

- Do not change `ChunkData.blocks` semantics in place.
- Do not hand-edit generated protocol files.
- Protocol changes must preserve raw chunk compatibility until the client and server both support the encoded path.
- Storage still persists the exact output of `world.Chunk.Serialize()` unless a separate migration is explicitly planned.
- Add round-trip tests for every encoded chunk format before enabling it in networking.
