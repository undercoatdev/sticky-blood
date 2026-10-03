# Sticky Blood

[![Release](https://img.shields.io/github/v/release/undercoatdev/sticky-blood?display_name=tag&sort=semver)](https://github.com/undercoatdev/sticky-blood/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/undercoatdev/sticky-blood/total)](https://github.com/undercoatdev/sticky-blood/releases)
[![License](https://img.shields.io/github/license/undercoatdev/sticky-blood)](LICENSE)
[![Garry's Mod](https://img.shields.io/badge/Garry's%20Mod-64--bit-1b9cff)](https://store.steampowered.com/app/4000/Garrys_Mod/)

Sticky Blood keeps blood decals from disappearing in Garry's Mod.

[Watch Sticky Blood in action.](https://github.com/user-attachments/assets/b8fdd3f4-1789-4b1f-9723-999c23507da5)

## Features

- Blood stays on the map and on character models.
- New splatters do not replace older ones.
- Blood already on an NPC stays visible when it dies and becomes a ragdoll.
- Supported animated effects leave behind a final stain instead of vanishing.

## Before installing

Sticky Blood patches your local `bin/win64/studiorender.dll` and `engine.dll`. Use it only for single-player or local/private games. Do not use modified game binaries on VAC-secured or integrity-checked multiplayer servers.

The installer checks that both DLLs match a supported game version, backs up the originals, and stops if either file is unknown or already modified. The download does not include any Valve binaries.

Version 1.0.0 is made for Steam's standard 64-bit **Play Garry's Mod** launch option. It works on Windows and on Linux through Proton.

If a Garry's Mod update changes either DLL, the installer will stop rather than risk patching the wrong version. Wait for a compatible Sticky Blood release before trying again.

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

Python 3 is required to run the Linux installer.

## Optional features

### Animated wounds

Animated blood normally disappears when its animation ends. Sticky Blood lets the animation play, then turns its last frame into a static blood stain when the effect is removed.

This has been tested with Galaxy/Zippy animated wounds, but compatibility is not guaranteed for every version or blood pack. Enable multicore rendering first:

```text
gmod_mcore_test 1
```

Sticky Blood only recognizes effects whose materials are under `animated_blood/` or `decals/flesh/animated/`. Effects stored elsewhere will continue to disappear normally.

### Debug Reviver

The **Debug Reviver** appears in the Weapons tab. Aim it at a dead NPC or a ragdoll created from one, then use primary fire to bring the NPC back without wiping away the blood already on it.

Sticky Blood turns on `ai_serverragdolls 1`, but your existing `g_ragdoll_maxcount` limit still applies.

## Uninstall and recovery

Fully quit the game, then run `uninstall.bat` on Windows or `./uninstall.sh` on Linux. The uninstaller restores the original DLLs from its verified backups and removes `garrysmod/addons/sticky_blood`.

If the uninstaller cannot use its backups, remove `garrysmod/addons/sticky_blood` by hand, then use Steam's **Verify integrity of game files** to restore the official DLLs.

- **After Steam Verify:** Run the Sticky Blood installer again if you still want to use the mod.
- **After a game update:** If the installer rejects the new DLLs, wait for a compatible Sticky Blood release instead of forcing the patch.
- **Backups:** Original DLLs are stored beside the game files with the suffix `.stickyblood-v1.bak`.

## Workshop limitation

Sticky Blood cannot be installed through the Workshop alone because Workshop addons cannot replace the two game DLLs it needs. Use the release download and installer instead.
