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
- `src/galois/data/wearables/{head,hair,hair_with_hat,face,ears,hat,neck,top,bottoms,outerwear,hands,feet,robot}/*.vox` -> `wearables/.../*.vox`
- `src/galois/data/animations/character-animations.gltf` -> `animations/character-animations.gltf`
- `thumbnails/.../*.png` are local UI thumbnails generated from the copied
  `wearables/.../*.vox` files by skipping reference mannequin layers and
  rendering the item-only wearable voxels.

Local integration notes:

- `client/rust_ext/src/biomes_avatar.rs` adapts the Biomes character skeleton,
  joint ordering, wearable slot names, animation-name catalog, full
  skin/eye/hair palette IDs, and source wearable/accessory slot catalogs.
- The runtime remains Rust/Godot-native and does not import Biomes Galois,
  Three.js, Next.js asset APIs, GLB generation, ECS, networking, or server code.
- The player skeleton and idle/run/jump poses are applied to local `Node3D`
  pivots so this stays client presentation only.
