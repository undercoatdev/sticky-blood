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

The installer looks for the exact code it changes. If a Garry's Mod update changes that code, it stops without touching anything. Run `install --dry-run` and open an issue with the output. The download does not include any Valve binaries.

Sticky Blood supports the x86-64 branch only. Native Linux is not supported (Proton only). Use Steam's standard 64-bit **Play Garry's Mod** launch option on Windows or Linux through Proton.

## Windows installation

1. Fully quit Garry's Mod.
2. Extract the release ZIP.
3. Double-click `install.bat`.
4. Start the game with **Play Garry's Mod**.

To see the planned edits without changing any files, run `install.bat -DryRun`.

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

To see the planned edits without changing any files:

```bash
./install.sh --dry-run
```

If Steam is not detected:

```bash
./install.sh --game "/path/to/SteamLibrary/steamapps/common/GarrysMod"
```

Python 3 is required to run the Linux installer.

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

- **After Steam Verify:** Install Sticky Blood again. The installer looks for the exact code it changes. If a Garry's Mod update changes that code, it stops without touching anything. Run `install --dry-run` and open an issue with the output.
- **After a game update:** Run `install --dry-run`. When the signatures still match, install as usual.
- **Backups:** Original DLLs are stored beside the game files as `.stickyblood.bak` with a `.stickyblood.json` sidecar. Backups from 1.0.0 (`.stickyblood-v1.bak`, or a `.bak` whose hash matches that release) are still accepted.

## Workshop limitation

Sticky Blood cannot be installed through the Workshop alone because Workshop addons cannot replace the two game DLLs it needs. Use the release download and installer instead.
