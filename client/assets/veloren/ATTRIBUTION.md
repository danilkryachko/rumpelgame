# Veloren-Derived Character Assets

These voxel assets are copied from the Veloren project for the local third-person
character prototype.

Source:

- Project: Veloren
- Repository: https://gitlab.com/veloren/veloren
- Source commit: `39f63fc1919fedd0782bca48fdbff0c23a9a6ae5`
- License: GNU General Public License v3.0 or later
- License copy: `licenses/VELoren-GPL-3.0-or-later-LICENSE.txt`

Copied files:

- `figure/body/chest_male.vox`
- `figure/body/belt_male.vox`
- `figure/body/pants_male.vox`
- `figure/body/hand.vox`
- `figure/body/foot.vox`
- `figure/head/human/male.vox`
- `figure/eyes/general/male_default-0.vox`
- `figure/hair/human/male-16.vox`
- `figure/beard/human/human-4.vox`

Local integration notes:

- Files are loaded directly as MagicaVoxel `.vox` assets by the Rust GDExtension.
- The player skeleton and idle/run/jump motion remain local procedural code.
- No Veloren networking, ECS, gameplay, or renderer code is copied.
