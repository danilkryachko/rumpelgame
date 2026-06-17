# Biomes-Derived Character Assets

These assets and character-system constants are adapted from the Biomes project
for the local third-person character visual.

Source:

- Project: Biomes
- Repository: https://github.com/ill-inc/biomes-game
- Source commit: `669da235acbc5ec19720b047889c4aaa1c013ce2`
- License: MIT
- License copy: `licenses/BIOMES-MIT-LICENSE.txt`

Copied files:

- `src/galois/data/wearables/base_model.vox` -> `wearables/base_model.vox`
- `src/galois/data/animations/character-animations.gltf` -> `animations/character-animations.gltf`

Local integration notes:

- `client/rust_ext/src/biomes_avatar.rs` adapts the Biomes character skeleton,
  joint ordering, wearable slot names, animation-name catalog, and reserved
  appearance palette ranges.
- The runtime remains Rust/Godot-native and does not import Biomes Galois,
  Three.js, Next.js asset APIs, GLB generation, ECS, networking, or server code.
- The player skeleton and idle/run/jump poses are applied to local `Node3D`
  pivots so this stays client presentation only.
