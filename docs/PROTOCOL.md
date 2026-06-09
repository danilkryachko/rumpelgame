# Protocol

## Sources

- Packet schema lives in `api/schema/packets.proto`.
- Generated Go protocol code lives under `server/pkg/api`.
- Rust client protocol handling lives under `client/rust_ext/src`.

## Rules

- Do not hand-edit generated protocol files.
- Protocol changes must account for both client and server behavior.
- Preserve wire compatibility unless the task explicitly changes it.
- Do not reuse or repurpose existing packet fields without documenting the compatibility impact.
- Add or update encode/decode, round-trip, or integration tests when changing protocol behavior.

## Sensitive Behavior

- Client/server startup and connection flow.
- Chunk data packet shape and coordinate semantics.
- Block IDs, chunk dimensions, and serialization assumptions.
- Error handling for malformed, partial, or unknown packets.
