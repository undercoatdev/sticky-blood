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

## Before installing

Sticky Blood patches your local `bin/win64/studiorender.dll` and `engine.dll`. Use it only for single-player or local/private games. Do not use modified game binaries on VAC-secured or integrity-checked multiplayer servers.

The installer finds the code it changes by searching for it, so it keeps working when a Garry's Mod update only moves that code around. If an update really changes that code, the installer stops without touching anything. In that case, run a dry run (see below) and [open an issue](https://github.com/undercoatdev/sticky-blood/issues) with the output. The download does not include any Valve files.

Requirements:

- **The 64-bit (x86-64) branch of Garry's Mod.** In Steam, right-click Garry's Mod, choose **Properties > Betas**, and pick **x86-64 - Chromium + 64-bit binaries**. Let Steam finish updating before you install. On the default branch the installer stops with a "Missing game file" message.
- **Windows**, or **Linux through Proton**. Native Linux builds of Garry's Mod are not supported.
- On Linux, Python 3.

## Windows installation

1. Fully quit Garry's Mod.
2. Extract the release ZIP.
3. Double-click `install.bat`.
4. Start the game with **Play Garry's Mod**.

To check that your game version is supported without changing any files, open Command Prompt in the extracted folder and run `install.bat -DryRun`.

If Steam is not detected, right-click Garry's Mod in Steam and choose **Manage > Browse local files** to find the `GarrysMod` folder. Then open Command Prompt in the extracted Sticky Blood folder and replace the example path below with that folder:

```bat
install.bat -GamePath "C:\Program Files (x86)\Steam\steamapps\common\GarrysMod"
```

## Linux/Proton installation

Fully quit Garry's Mod, extract the release, then run:

```bash
chmod +x install.sh uninstall.sh
./install.sh
```

To check that your game version is supported without changing any files:

```bash
./install.sh --dry-run
```

If Steam is not detected:

```bash
./install.sh --game "/path/to/SteamLibrary/steamapps/common/GarrysMod"
```

## Optional features

### Animated wounds

Galaxy/Zippy's animated blood mod was tested with Sticky Blood and worked as intended. Enable multicore rendering first:

```text
gmod_mcore_test 1
```

### Debug Reviver

The **Debug Reviver** appears in the Weapons tab. Aim it at a dead NPC or a ragdoll created from one, then use primary fire to bring the NPC back without wiping away the blood already on it.

Sticky Blood turns on `ai_serverragdolls 1`, but your existing `g_ragdoll_maxcount` limit still applies.

## Uninstall and recovery

Fully quit the game, then run `uninstall.bat` on Windows or `./uninstall.sh` on Linux. The uninstaller restores the original DLLs from its verified backups and removes `garrysmod/addons/sticky_blood`.

If the uninstaller cannot use its backups, remove `garrysmod/addons/sticky_blood` by hand, then use Steam's **Verify integrity of game files** to restore the official DLLs.

- **After Steam Verify:** Verify puts the original game files back, so run the installer again to re-apply Sticky Blood.
- **After a game update:** If the update replaced the patched files, blood starts disappearing again. Quit the game and run `install.bat` or `./install.sh` again. If it says the build isn't supported, run the dry run (`install.bat -DryRun` or `./install.sh --dry-run`) and open an issue with the output.
- **Backups:** Original DLLs are stored beside the game files as `.stickyblood.bak` with a `.stickyblood.json` sidecar. Backups from 1.0.0 (`.stickyblood-v1.bak`, or a `.bak` whose hash matches that release) are still accepted.

## Workshop limitation

The Workshop can only install the Lua part of Sticky Blood. That gives you blood that stays on NPCs when they become ragdolls and the Debug Reviver, but blood decals still disappear at the normal game limits, because a Workshop addon can't patch the two game DLLs.

For the full mod, use the [latest release](https://github.com/undercoatdev/sticky-blood/releases/latest) and its installer. The installer already includes the Lua part, so unsubscribe from the Workshop version after installing to avoid running two copies.
