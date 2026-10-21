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

Sticky Blood changes two game files on your computer: `bin/win64/studiorender.dll` and `engine.dll`. It is made for **single-player and private games with friends only**.

> **Important:** Before you join any online server, run the uninstaller (see [Uninstall and recovery](#uninstall-and-recovery)). Read [Can I join servers?](#can-i-join-servers) to find out why.

The installer finds the code it changes by searching for it, so it keeps working when a Garry's Mod update only moves that code around. If an update really changes that code, the installer stops without touching anything. In that case, run a dry run (see below) and [open an issue](https://github.com/undercoatdev/sticky-blood/issues) with the output. The download does not include any Valve files.

Requirements:

- **The 64-bit (x86-64) branch of Garry's Mod.** In Steam, right-click Garry's Mod, choose **Properties > Betas**, and pick **x86-64 - Chromium + 64-bit binaries**. Let Steam finish updating before you install. On the default branch the installer stops with a "Missing game file" message.
- **Windows**, or **Linux through Proton**. Native Linux builds of Garry's Mod are not supported.
- On Linux, Python 3.

## Windows installation

1. Fully quit Garry's Mod.
2. Download `sticky-blood-v1.1.0.zip` from the [latest release](https://github.com/undercoatdev/sticky-blood/releases/latest), right-click it and choose **Extract All**.
3. Open the extracted `sticky-blood-v1.1.0` folder and double-click `install.bat` (Windows may put it inside a second folder with the same name). A window opens briefly. If it closes on its own, the install worked. If something goes wrong, it stays open and shows the error.
4. Start the game from Steam as usual.

To check that your game version is supported without changing anything, click the address bar of the extracted folder in File Explorer, type `cmd` and press Enter, then run:

```bat
install.bat -DryRun
```

**Only if step 3 says it can't find Garry's Mod:** right-click Garry's Mod in Steam and choose **Manage > Browse local files** to find the `GarrysMod` folder. Then open Command Prompt in the extracted folder the same way and run this, with the example path replaced by your own:

```bat
install.bat -GamePath "C:\Program Files (x86)\Steam\steamapps\common\GarrysMod"
```

## Linux/Proton installation

1. Fully quit Garry's Mod.
2. Download `sticky-blood-v1.1.0.zip` from the [latest release](https://github.com/undercoatdev/sticky-blood/releases/latest) and extract it, for example into your `Downloads` folder.
3. Open a terminal **in the extracted `sticky-blood-v1.1.0` folder**. In most file managers you can right-click inside the folder and choose **Open in Terminal**, or open any terminal and go there with `cd`, for example:

   ```bash
   cd ~/Downloads/sticky-blood-v1.1.0
   ```

4. Check that your game version is supported. This changes nothing:

   ```bash
   bash install.sh --dry-run
   ```

   It should list the patches it would make. If it says the build isn't supported, stop and [open an issue](https://github.com/undercoatdev/sticky-blood/issues) with the output.

5. Install:

   ```bash
   bash install.sh
   ```

6. Start the game from Steam as usual.

Type these commands into a normal terminal, not into the Garry's Mod console or a game server console.

**Only if step 5 can't find Garry's Mod:** you can tell the installer where the game is. You do not need this if step 5 worked. In Steam, right-click Garry's Mod and choose **Manage > Browse local files** to find the `GarrysMod` folder, then run this, with the example path replaced by your own:

```bash
bash install.sh --game "/path/to/SteamLibrary/steamapps/common/GarrysMod"
```

## Can I join servers?

**No, not while Sticky Blood is installed.** Uninstall it first, play online, then install it again when you are back in single-player.

Why:

- **VAC (Valve Anti-Cheat).** Garry's Mod has used VAC since it launched, and servers with the "secure" shield run it. Valve's own VAC FAQ says that third-party changes to a game's core `.exe` and `.dll` files can count as cheating, and VAC bans are permanent. Sticky Blood is not a cheat and we know of no ban caused by it, but it does change two core DLLs, so we can't promise VAC will never flag it. Don't risk your account.
- **Server anti-cheats and admins.** Many community servers run their own anti-cheat addons, and admins can ban anyone for any reason. Some may treat a modified game as suspicious.
- **sv_pure.** This server setting checks content files such as models, materials and sounds. As far as we know it does not check the patched DLLs, so it is not a safety guarantee either way.
- **Crashes.** The patched code has only been tested in single-player and on private local games. On a busy server with lots of blood, it may use more memory or crash.

Single-player and private local games (for example, a game hosted by you for friends) are what Sticky Blood is made for.

To go online: quit the game, run `uninstall.bat` (Windows) or `bash uninstall.sh` (Linux), then start the game. If you are unsure, use Steam's **Verify integrity of game files** after uninstalling.

## Optional features

### Animated wounds

Galaxy/Zippy's animated blood mod was tested with Sticky Blood and worked as intended. Enable multicore rendering first:

```text
gmod_mcore_test 1
```

### Death wounds

Bullet hits from the kill, including a full shotgun volley, are painted back onto the ragdoll. Pellets that land in the same server tick as the death are kept, and so are pellets that hit the ragdoll just after it appears. In the Garry's Mod console:

```text
sticky_blood_carry 1
sticky_blood_carry_ticks 1
sticky_blood_carry_window 0.3
sticky_blood_carry_max 32
sticky_blood_debug 0
```

`sticky_blood_carry` turns this on (`1`) or off (`0`). `sticky_blood_carry_ticks` is how many server ticks before the death still count. `sticky_blood_carry_window` is how many seconds of bullet hits on the new ragdoll are kept. `sticky_blood_carry_max` is the most hits kept on one body. `sticky_blood_debug 1` prints one line each time hits are carried.

Sticky Blood turns on `ai_serverragdolls 1`, but your existing `g_ragdoll_maxcount` limit still applies.

## Uninstall and recovery

Always uninstall before playing on online servers.

Fully quit the game, then double-click `uninstall.bat` in the extracted folder on Windows, or run `bash uninstall.sh` from a terminal in that folder on Linux. The uninstaller restores the original DLLs from its verified backups and removes `garrysmod/addons/sticky_blood`.

If the uninstaller cannot use its backups, remove `garrysmod/addons/sticky_blood` by hand, then use Steam's **Verify integrity of game files** to restore the official DLLs.

- **After Steam Verify:** Verify puts the original game files back, so run the installer again to re-apply Sticky Blood.
- **After a game update:** If the update replaced the patched files, blood starts disappearing again. Quit the game and run `install.bat` or `bash install.sh` again. If it says the build isn't supported, run the dry run (`install.bat -DryRun` or `bash install.sh --dry-run`) and open an issue with the output.
- **Backups:** Original DLLs are stored beside the game files as `.stickyblood.bak` with a `.stickyblood.json` sidecar. Backups from 1.0.0 (`.stickyblood-v1.bak`, or a `.bak` whose hash matches that release) are still accepted.

## Workshop item

The Steam Workshop item ([Infinite Blood Decals](https://steamcommunity.com/sharedfiles/filedetails/?id=3823903039)) is empty on purpose. Subscribing to it installs nothing. To get the mod, use the [latest release](https://github.com/undercoatdev/sticky-blood/releases/latest) and its installer.
