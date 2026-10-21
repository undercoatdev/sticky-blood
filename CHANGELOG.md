# Changelog

## Unreleased

- `sticky_blood_debug` is no longer saved between sessions.
- `ai_serverragdolls` is restored to its previous value on shutdown. New `sticky_blood_force_serverragdolls` (default 1) turns the forcing off.
- Removed leftover revive code and the unused `StickyBlood_Revived` network message.

## 1.1.1

- Fixed engine crash when the decal pool filled up.

## 1.1.0

- Shotgun volleys that kill an NPC now keep all their wounds on the ragdoll (pellet carry), including pellets that hit the ragdoll just after it appears.
- Carried pellet hits use the small flesh bullet-hole decal, one per pellet.
- Locate patch sites by byte signatures, so a Garry's Mod update can still install when that code has only moved.
- Stop without modifying files when a signature is missing, ambiguous, or the original bytes differ.
- Add `install --dry-run` so an unsupported build can be reported from the plan output.
- Keep 1.0.0 backups usable when their hash matches that release.
- Require the x86-64 branch. Native Linux is not supported (Proton only).
- Removed the Debug Reviver weapon. The Steam Workshop item is now an empty placeholder.

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
