

https://github.com/user-attachments/assets/b8fdd3f4-1789-4b1f-9723-999c23507da5





# Sticky Blood

[![Release](https://img.shields.io/github/v/release/undercoatdev/sticky-blood?display_name=tag&sort=semver)](https://github.com/undercoatdev/sticky-blood/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/undercoatdev/sticky-blood/total)](https://github.com/undercoatdev/sticky-blood/releases)
[![License](https://img.shields.io/github/license/undercoatdev/sticky-blood)](LICENSE)
[![Garry's Mod](https://img.shields.io/badge/Garry's%20Mod-64--bit-1b9cff)](https://store.steampowered.com/app/4000/Garrys_Mod/)

Sticky Blood removes Garry's Mod's normal model- and world-decal recycling, keeps wounds through NPC ragdolling and revival, and preserves the last frame of compatible animated blood wounds.

This release supports the default 64-bit **Play Garry's Mod** launch on native Windows and Linux through Proton. It is version-locked to the game DLLs listed in `patches/v1.0.0.json`.

## Features

- Effectively persistent world and model decals without recycling older blood.
- Independent decal meshes so many wounds can overlap on the same body.
- Animated Galaxy/Zippy wounds freeze into permanent final-frame stains.
- Wounds survive NPC death, server ragdolls, and Debug Reviver transitions.
- Verified installers, automatic backups, safe uninstall, and update detection.
- No redistributed Valve binaries.

## Preview

Gameplay GIFs are coming soon. The repository has a [`media`](media) folder ready for:

- `infinite-decals.gif`
- `animated-wound-bake.gif`
- `ragdoll-revival.gif`

## Safety

Sticky Blood modifies two local Garry's Mod DLLs. Use it for single-player or local/private games. Do not use modified game binaries on VAC-secured or integrity-checked multiplayer servers.

The release does not contain or redistribute Valve DLLs. The installer verifies and patches your own files. If Garry's Mod updates, the installer will refuse unknown files instead of guessing.

## Windows installation

1. Fully quit Garry's Mod.
2. Extract the release ZIP.
3. Double-click `install.bat`.
4. Start the game with **Play Garry's Mod**.

If Steam is not detected, open Command Prompt in the extracted folder and run:

```bat
install.bat -GamePath "D:\SteamLibrary\steamapps\common\GarrysMod"
```

## Linux/Proton installation

Fully quit Garry's Mod, extract the release, then run:

```bash
chmod +x install.sh uninstall.sh
./install.sh
```

If Steam is not detected:

```bash
./install.sh --game "/path/to/SteamLibrary/steamapps/common/GarrysMod"
```

Python 3 is required on Linux for safe hash verification and patching.

## Animated wounds

Compatible Galaxy/Zippy animated wounds require:

```text
gmod_mcore_test 1
```

The animation plate plays normally. When it is removed, Sticky Blood stamps its final texture frame onto the NPC or ragdoll as another permanent decal layer.

## Debug Reviver

The **Debug Reviver** appears in the Weapons tab. Primary-fire a supported dead NPC or ragdoll to recreate it standing while retaining its model-instance wounds.

Sticky Blood enables `ai_serverragdolls 1`. It does not override `g_ragdoll_maxcount`.

## Uninstall

Fully quit the game, then run `uninstall.bat` on Windows or `./uninstall.sh` on Linux. The uninstaller restores only verified v1 backups and removes `garrysmod/addons/sticky_blood`.

If a backup is missing or a DLL is from another game version, the uninstaller refuses to overwrite it. Use Steam's **Verify integrity of game files** to restore official DLLs.

## Updates and recovery

- Steam Verify restores the original DLLs and disables the binary part of Sticky Blood. Run the installer again afterward.
- A Garry's Mod update may change the DLL hashes. Wait for a compatible Sticky Blood manifest rather than forcing the patch.
- The installer is idempotent: running it again on a verified v1 installation is safe.
- Backups are created beside the game DLLs with the suffix `.stickyblood-v1.bak`.

## Workshop

The complete mod cannot be distributed as a normal Workshop addon because Workshop content cannot replace the game-loaded `bin/win64/studiorender.dll` and `engine.dll`. A Lua-only Workshop upload would not provide infinite decals.

## Distribution contents

The release ZIP is built from an explicit allowlist. It contains the addon, installers, patch manifest, and user documentation only. It excludes Valve DLLs, backups, obsolete experiments, plans, transcripts, `.cursor`, `cursor.md`, `AGENTS.md`, and other agentic metadata.
