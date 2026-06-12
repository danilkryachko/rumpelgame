# Protocol

## Sources

- Packet schema lives in `api/schema/packets.proto`.
- Generated Go protocol code lives under `server/pkg/api`.
- Rust client protocol handling lives under `client/rust_ext/src`.
- Go server framing lives in `server/pkg/network`.
- Rust generated protocol code is produced at Cargo build time from `api/schema/packets.proto`.

## Rules

- Do not hand-edit generated protocol files.
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

## Packet Payloads

- `Packet.chunk = 1`: server-to-client `ChunkData`.
- `Packet.position = 2`: client-to-server `ClientPosition`.
- `Packet.block_action = 3`: client-to-server `BlockAction`.

## Chunk Data

- `ChunkData.x` and `ChunkData.z` are chunk coordinates, not block coordinates.
- `ChunkData.blocks` is a full serialized chunk for the current implementation.
- Chunk dimensions are `32 x 32 x 512`, defined by the server world package as width, depth, and height.
- Block IDs are serialized as unsigned 16-bit little-endian values.
- Block index order is `x + y * width * depth + z * width`.
- A full chunk payload currently contains `32 * 32 * 512 * 2` block bytes.

## Block Actions

- `DESTROY = 0` removes a block; `block_id` is ignored.
- `PLACE = 1` sets the block to `block_id`.
- Action coordinates are block coordinates in the active server chunk implementation.

## Sensitive Behavior

- Client/server startup and connection flow.
- Chunk data packet shape and coordinate semantics.
- Block IDs, chunk dimensions, and serialization assumptions.
- Error handling for malformed, partial, or unknown packets.
