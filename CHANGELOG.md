# Changelog

## 1.0.0

- Prevented global and per-model decal retirement.
- Raised studio decal mesh and single-stamp limits to 61440 vertices.
- Preserved existing wounds when a decal mesh reaches its limit.
- Allocated independent meshes for stacked splats while reusing the empty mesh within one stamp.
- Prevented the world decal pool from recycling older decals.
- Preserved model-instance wounds across NPC death, ragdolling, and debug revival.
- Added the Debug Reviver weapon.
- Added final-frame stamping for compatible Galaxy/Zippy animated wounds.
- Added verified Windows and Linux/Proton installers, backups, uninstallers, and version checks.
