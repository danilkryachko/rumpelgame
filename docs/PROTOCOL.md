# Protocol

## Sources

- Packet schema lives in `api/schema/packets.proto`.
- Generated Go protocol code lives under `server/pkg/api`.
- Rust client protocol handling lives under `client/rust_ext/src`.
- Go server framing lives in `server/pkg/network`.
- Rust generated protocol code is produced at Cargo build time from `api/schema/packets.proto`.
- Streaming protocol evolution planning lives in `docs/STREAMING_PROTOCOL_EVOLUTION_PLAN.md`.
- Chunk payload and schema compatibility guards live in `docs/CHUNK_SERIALIZATION_COMPATIBILITY.md`.
- Packet boundary robustness guards live in `docs/NETWORKING_ROBUSTNESS_PROGRAM.md`.

## Rules

- Do not hand-edit generated protocol files.
- Use `scripts/protocol_generated_drift_gate.sh` before finishing protocol/schema work; it guards generated-code headers, schema identity tokens, and partial proto/generated diffs.
- Protocol changes must account for both client and server behavior.
- Preserve wire compatibility unless the task explicitly changes it.
- Do not reuse or repurpose existing packet fields without documenting the compatibility impact.
- Add or update encode/decode, round-trip, or integration tests when changing protocol behavior.
- Add new `Packet.payload` variants with new field numbers; never reuse field numbers `1`, `2`, or `3`.
- Add new fields to existing messages with new field numbers; do not change the type, meaning, or encoding of existing fields.

## Wire Format

- Transport is TCP.
- Each packet is framed as:
  - 4-byte unsigned little-endian payload length.
  - `Packet` protobuf payload bytes of exactly that length.
- Length values describe only the protobuf payload, not the 4-byte prefix.
- Readers must consume exactly the advertised payload length before decoding.
- A zero-length protobuf payload decodes as a `Packet` with no active payload and follows the same ignore policy as other unsupported empty packet shapes.

## Packet Payloads

- `Packet.chunk = 1`: server-to-client `ChunkData`.
- `Packet.position = 2`: client-to-server `ClientPosition`.
- `Packet.block_action = 3`: client-to-server `BlockAction`.
- Packets with no active payload, nil `ClientPosition`/`BlockAction` bodies, or an unsupported payload shape are ignored by current handlers and must not emit chunk updates.

## Chunk Data

- `ChunkData.x` and `ChunkData.z` are chunk coordinates, not block coordinates.
- `ChunkData.blocks` is the chunk block payload. With `CHUNK_ENCODING_RAW`, it is the full serialized chunk. With `CHUNK_ENCODING_RLE`, it is a block-run payload over the same serialized chunk bytes.
- `ChunkData.encoding` uses tag `4`. Omitted or `CHUNK_ENCODING_RAW = 0` means raw full chunk bytes for compatibility with older packets.
- `ChunkData.uncompressed_size` uses tag `5`. It is set for `CHUNK_ENCODING_RLE` and must match the full serialized chunk byte size.
- Chunk dimensions are `32 x 32 x 512`, defined by the server world package as width, depth, and height.
- Block IDs are serialized as unsigned 16-bit little-endian values.
- Block index order is `x + y * width * depth + z * width`.
- A full chunk payload currently contains `32 * 32 * 512 * 2` block bytes.
- RLE chunk payloads are a sequence of runs. Each run is a 2-byte little-endian block ID followed by an unsigned protobuf-style varint run length in blocks.
- RLE chunk payloads are the server default. `RUMPELMC_SERVER_CHUNK_ENCODING=raw` enables the raw full-chunk rollback path.
- Compatibility tests guard raw default fields, exact packet frame boundaries, zero-length empty-packet frames, RLE run-vector stability, representative RLE run patterns, schema field numbers, enum wire values, and unknown `ChunkData` fields.
- Block material metadata is registry-derived behavior. Do not add render, collision, liquid, emissive, or material flags into `ChunkData.blocks`; if metadata ever needs to cross the wire, add new protobuf fields with new field numbers and compatibility tests.

## Block Actions

- `DESTROY = 0` removes a block; `block_id` is ignored.
- `PLACE = 1` sets the block to `block_id`.
- Action coordinates are block coordinates in the active server chunk implementation.
- Current server handling validates `PLACE` through the server block registry and the session inventory before applying `World.SetBlockGlobal`.
- A `Packet_BlockAction` wrapper with no `BlockAction` body is treated as an ignored unsupported packet shape and must not emit chunk updates.

## Sensitive Behavior

- Client/server startup and connection flow.
- Chunk data packet shape and coordinate semantics.
- Block IDs, chunk dimensions, and serialization assumptions.
- Block material metadata compatibility; `block_id` remains the only current wire/storage identity for voxel contents.
- Error handling for malformed, partial, or unknown packets.
- Reconnect, slow-client timeout, overload, and backpressure behavior are policy work; do not change packet framing or schema for them without an explicit protocol task.

## Generated Drift Guard

Run:

```sh
sh scripts/protocol_generated_drift_gate.sh logs/protocol_generated_drift_current
```

The expected current result is `status=pass`, `schema_diff=0`, `generated_diff=0`, `generated_header=guarded`, `schema_identity=guarded`, and `partial_generated_drift=guarded`.
