# Chunk Compression Decision

Date: 2026-06-15

Decision: keep RLE as the default server chunk encoding and keep `RUMPELMC_SERVER_CHUNK_ENCODING=raw` as the explicit rollback path. Do not add another chunk compression format until non-flat worldgen, edits, caves, structures, liquids, or biome variety create evidence that RLE is no longer adequate.

## Current Contract

- Stored chunks remain the raw serialized `32 x 32 x 512` little-endian `u16` block array.
- Server `ChunkData.blocks` is RLE by default and raw when `RUMPELMC_SERVER_CHUNK_ENCODING=raw`.
- RLE payloads must decode to exactly the raw serialized bytes before client chunk insert, dirty update, meshing, collision, and GPU upload.
- `ChunkData.encoding` and `ChunkData.uncompressed_size` remain the compatibility markers for encoded payloads.
- `RUMPELMC_SERVER_CHUNK_ENCODING=raw` must stay available for rollback and protocol diagnostics.

## Decision Gate

Run the full gate with:

```sh
RUMPELMC_GODOT_RUST_EXT_BUILD_RELEASE=1 RUMPELMC_GODOT_RUST_EXT_PROFILE=release ./scripts/world_streaming_compression_decision.sh logs/world_streaming_compression_decision
```

The gate runs:

- Go compatibility tests for API, world codec, and network encoding behavior.
- CPU benchmarks for raw serialize, RLE encode, and RLE decode.
- RAW-vs-RLE movement runtime comparison through `scripts/world_streaming_chunk_encoding_compare.sh`.

Use `RUMPELMC_COMPRESSION_DECISION_RUNTIME=0` for a fast tests-plus-benchmark pass without Godot.

## Fresh Evidence

Fresh full result:

- Summary: `logs/world_streaming_compression_decision_full_check/chunk-compression-decision-summary.txt`.
- Status: `pass`.
- Benchmarks on the flat generated chunk:
  - `BenchmarkChunkSerializeFlat`: `258530 ns/op`, `1050891 B/op`, `1 allocs/op`.
  - `BenchmarkEncodeSerializedChunkRLEFlat`: `261109 ns/op`, `4603 B/op`, `1 allocs/op`.
  - `BenchmarkDecodeSerializedChunkRLEFlat`: `179847 ns/op`, `1051659 B/op`, `1 allocs/op`.
- Runtime RAW/RLE compare streamed `394` chunks in both runs.
- RAW payload/wire: `413,138,944` / `413,148,011` bytes.
- RLE payload/wire: `7,362` / `17,219` bytes.
- RLE payload/wire percent of raw: `0.001782%` / `0.004168%`.
- RAW/RLE startup player spawn both reported `8.333ms`.

## Future Revisit Triggers

Reopen the compression decision when any of these become true:

- Worldgen entropy changes materially: caves, ores, structures, biome layers, liquids, or large edit histories.
- RLE payload or wire bytes exceed an accepted budget on representative non-flat terrain.
- RLE encode/decode work becomes a meaningful startup or movement latency component.
- A new protocol shape is already planned for another reason and can carry a format negotiation path safely.
- Long-run exploration shows decode spikes, packet queue growth, or backpressure symptoms tied to compression.

Until those triggers exist, compression work should focus on keeping current RLE/raw compatibility tests and runtime comparisons fresh rather than adding formats.
