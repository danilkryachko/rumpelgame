# Architecture

## Stack
- **Client**: Godot Engine (UI, Rendering, Scene management).
- **Client Logic**: Rust via GDExtension (`godot-rust`). Handles network communication with the server and orchestrates GPU compute shaders for meshing.
- **Server**: Go. Headless server handling world generation, block updates, and networking.

## Data Flow
- Client starts -> Godot launches Server binary -> Godot connects to localhost TCP/UDP.
- Server generates terrain -> sends Chunk Data (32x32x512) to Client.
- Rust receives Chunk Data -> passes it to Godot `RenderingDevice` -> Compute Shader meshes the chunk.
