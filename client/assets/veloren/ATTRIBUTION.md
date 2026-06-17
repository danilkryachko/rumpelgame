# Veloren-Derived Character Assets

These voxel assets are copied from the Veloren project for the local third-person
character prototype and the local Human/Male voxygen composer checkpoint.

Source:

- Project: Veloren
- Repository: https://github.com/veloren/veloren
- Source commit: `bd7d694ec1353b8b5be5be389f0c3f08b1bae28a`
- License: GNU General Public License v3.0 or later
- License copy: `licenses/VELoren-GPL-3.0-or-later-LICENSE.txt`

Copied files:

- `voxygen/voxel/humanoid_head_manifest.ron`
- `voxygen/voxel/humanoid_color_manifest.ron`
- `voxygen/voxel/humanoid_armor_chest_manifest.ron`
- `voxygen/voxel/humanoid_armor_belt_manifest.ron`
- `voxygen/voxel/humanoid_armor_pants_manifest.ron`
- `voxygen/voxel/humanoid_armor_hand_manifest.ron`
- `voxygen/voxel/humanoid_armor_foot_manifest.ron`
- `voxygen/voxel/figure/head/human/male.vox`
- `voxygen/voxel/figure/eyes/general/male_default-0.vox`
- `voxygen/voxel/figure/hair/human/male-16.vox`
- `voxygen/voxel/figure/beard/human/human-4.vox`
- `voxygen/voxel/armor/empty.vox`
- `voxygen/voxel/armor/misc/chest/none.vox`
- `voxygen/voxel/armor/misc/belt/none.vox`
- `voxygen/voxel/armor/misc/pants/none.vox`
- `voxygen/voxel/armor/misc/hand/none.vox`
- `voxygen/voxel/armor/misc/foot/none.vox`

Local integration notes:

- The current Rust GDExtension path parses local voxygen RON manifests and composes the selected Human/Male head, eyes, hair, beard, palette colors, and default armor parts from local MagicaVoxel `.vox` files.
- The local manifest parser covers this checked-in runtime subset and does not add `serde` or `ron` runtime dependencies.
- The player skeleton and idle/run/jump motion remain local procedural code.
- No Veloren networking, ECS, gameplay, or renderer code is copied.
