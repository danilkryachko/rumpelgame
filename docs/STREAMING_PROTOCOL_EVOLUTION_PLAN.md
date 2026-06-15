# Streaming Protocol Evolution Plan

Date: 2026-06-15

Decision: no protocol change is needed for the current streaming work. RLE already uses compatible `ChunkData.encoding = 4` and `ChunkData.uncompressed_size = 5`, and Block 6 evidence does not justify another compression packet shape.

## Current Wire Contract

- TCP frame: 4-byte little-endian protobuf payload length, followed by exactly that many `Packet` bytes.
- `Packet.chunk = 1`: server-to-client `ChunkData`.
- `Packet.position = 2`: client-to-server `ClientPosition`.
- `Packet.block_action = 3`: client-to-server `BlockAction`.
- `ChunkData.x = 1`, `ChunkData.z = 2`, `ChunkData.blocks = 3`, `ChunkData.encoding = 4`, `ChunkData.uncompressed_size = 5`.
- `CHUNK_ENCODING_RAW = 0` remains compatibility default.
- `CHUNK_ENCODING_RLE = 1` remains current default server encoding.

## Non-Negotiable Rules

- Never reuse existing field numbers or change their meaning.
- Do not hand-edit generated Go or Rust protocol files.
- Any new `Packet.payload` variant must use a new oneof tag greater than `3`.
- Any new field on an existing message must use a new field number greater than the current highest field for that message.
- Old clients must continue to handle omitted new fields through default values.
- Rollback must be explicit and documented before a protocol change becomes default.

## Change Triggers

Consider a protocol change only when at least one trigger has fresh evidence:

- Compression: RLE fails representative non-flat terrain size or latency budgets.
- Backpressure: client packet queue metrics show sustained drain bursts or queue lag that cannot be handled server-side without client telemetry.
- Streaming priority: pop-in metrics prove the server needs client-visible/interest signals beyond position.
- Multi-client scaling: server fairness requires per-client capability or budget negotiation.
- Persistence/gameplay: block edit or chunk delta semantics need a distinct packet shape.

## Safe Evolution Path

1. Write a short design note with compatibility impact, rollback behavior, and exact field/tag allocation.
2. Add or update `api/schema/packets.proto` only after the design has a concrete evidence trigger.
3. Regenerate Go/Rust bindings through the approved build path; never edit generated files manually.
4. Add wire compatibility tests that lock old tags and new tags.
5. Add server encode tests and Rust client decode tests before runtime use.
6. Keep old behavior as default until RAW/RLE, startup, packet queue, and movement smoke gates pass with both old and new behavior.
7. Update `docs/PROTOCOL.md`, `docs/AGENT_MEMORY.md`, and handoff notes in the same change.

## Candidate Future Shapes

These are reserved as planning concepts, not active schema:

- Client capability packet: client declares supported chunk encodings, optional telemetry support, and protocol feature bits.
- Server capability packet: server declares selected encoding, stream policy, and fallback rules.
- Client stream telemetry packet: client reports packet queue drain bursts, queue lag, decode work, terrain queue pressure, and resident pressure for adaptive batching.
- Chunk delta packet: server sends block/subchunk deltas separately from full chunk snapshots when edit persistence requires it.

Do not add any of these until the relevant trigger has runtime evidence and a rollback path.

## Current Next Step

Protocol work should stay planning-only. The next runtime work should use Block 5 packet queue metrics and Block 10 pop-in metrics to decide whether adaptive server batching can stay server-side or needs explicit client telemetry.
