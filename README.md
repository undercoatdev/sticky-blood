# Sticky Blood

[![Release](https://img.shields.io/github/v/release/undercoatdev/sticky-blood?display_name=tag&sort=semver)](https://github.com/undercoatdev/sticky-blood/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/undercoatdev/sticky-blood/total)](https://github.com/undercoatdev/sticky-blood/releases)
[![License](https://img.shields.io/github/license/undercoatdev/sticky-blood)](LICENSE)
[![Garry's Mod](https://img.shields.io/badge/Garry's%20Mod-64--bit-1b9cff)](https://store.steampowered.com/app/4000/Garrys_Mod/)

Sticky Blood makes blood decals in Garry's Mod stick around. Wounds can pile up on NPCs and the world, remain on bodies when NPCs become ragdolls, and preserve the last frame of supported animated blood effects.

[Watch Sticky Blood in action.](https://github.com/user-attachments/assets/b8fdd3f4-1789-4b1f-9723-999c23507da5)

## Features

- Persistent blood on map surfaces, NPCs, and ragdolls.
- Overlapping wounds without older decals being recycled.
- Wounds that carry over when an NPC becomes a ragdoll.
- Optional support for preserving compatible animated wounds.

## Before installing

Sticky Blood patches your local `bin/win64/studiorender.dll` and `engine.dll`. Use it only for single-player or local/private games. Do not use modified game binaries on VAC-secured or integrity-checked multiplayer servers.

The installer checks both DLLs against the supported version, backs up the originals, and refuses to patch unknown or modified files. The release does not contain or redistribute Valve binaries.

Version 1.0.0 supports the default 64-bit **Play Garry's Mod** launch on:

- Windows
- Linux through Proton

Compatibility is tied to the exact DLL hashes in `patches/v1.0.0.json`. A Garry's Mod update may require a new Sticky Blood release.

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

## Optional features

### Animated wounds

Compatible Galaxy/Zippy animated wounds can leave their final frame behind as a persistent decal. Enable multicore rendering first:

```text
gmod_mcore_test 1
```

The effect must use a material under `animated_blood/` or `decals/flesh/animated/`. Other animated wound materials are ignored.

### Debug Reviver

The **Debug Reviver** appears in the Weapons tab. Primary-fire a supported dead NPC or ragdoll to recreate it standing with its wounds intact.

Sticky Blood enables `ai_serverragdolls 1`. It does not override `g_ragdoll_maxcount`.

## Uninstall and recovery

Fully quit the game, then run `uninstall.bat` on Windows or `./uninstall.sh` on Linux. The uninstaller restores only verified v1 backups and removes `garrysmod/addons/sticky_blood`.

If a backup is missing or a DLL is from another game version, the uninstaller refuses to overwrite it. Use Steam's **Verify integrity of game files** to restore official DLLs.

- **After Steam Verify:** Run the Sticky Blood installer again; verification restores the original DLLs.
- **After a game update:** If the installer rejects the new DLLs, wait for a compatible Sticky Blood release instead of forcing the patch.
- **To reinstall:** Running the installer again on a verified v1 installation is safe.
- **Backups:** Original DLLs are stored beside the game files with the suffix `.stickyblood-v1.bak`.

## Workshop limitation

Sticky Blood cannot work as a normal Workshop-only addon because Workshop content cannot replace the two game-loaded DLLs it patches. The Lua addon alone does not provide persistent decals.
