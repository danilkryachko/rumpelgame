# Chunk Serialization Compatibility

Date: 2026-06-15

This note records the compatibility guard for chunk payload bytes and the protobuf packet schema.

## Current Contract

- Raw chunk payloads remain backward-compatible: omitted `ChunkData.encoding` defaults to `CHUNK_ENCODING_RAW`, and omitted `ChunkData.uncompressed_size` defaults to `0`.
- RLE payloads remain a stable sequence of `little-endian u16 block_id` plus protobuf-style unsigned varint run length in blocks.
- `ChunkData` field numbers remain stable: `x=1`, `z=2`, `blocks=3`, `encoding=4`, `uncompressed_size=5`.
- `Packet.payload` oneof field numbers remain stable: `chunk=1`, `position=2`, `block_action=3`.
- `ChunkEncoding` wire values remain stable: `CHUNK_ENCODING_RAW=0`, `CHUNK_ENCODING_RLE=1`.
- Go protobuf round-trips preserve unknown `ChunkData` fields, so future chunk metadata can be added without breaking current Go-side decode/remarshal paths.

## Guard

Run the focused guard with:

```sh
cd server
go test ./pkg/api ./pkg/world ./pkg/network
```

Fresh check:

- `go test ./pkg/api ./pkg/world ./pkg/network` passed on 2026-06-15 after adding schema field-number tests, raw default compatibility coverage, unknown-field round-trip coverage, a stable RLE wire-vector test, and direct chunk serialize/deserialize coordinate/block round-trip coverage.
