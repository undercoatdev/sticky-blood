#!/usr/bin/env python3
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile

ROOT = Path(__file__).resolve().parent.parent
MANIFEST = ROOT / "patches" / "v1.0.0.json"


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def normalize_game(path):
    path = Path(path).expanduser().resolve()
    if (path / "gameinfo.txt").is_file():
        path = path.parent
    if (path / "garrysmod" / "gameinfo.txt").is_file():
        return path
    raise RuntimeError(f"Not a Garry's Mod folder: {path}")


def steam_libraries(steam):
    yield steam
    vdf = steam / "steamapps" / "libraryfolders.vdf"
    if not vdf.is_file():
        return
    for line in vdf.read_text(encoding="utf-8", errors="ignore").splitlines():
        fields = line.split('"')
        if len(fields) >= 4 and fields[1].strip().lower() == "path":
            yield Path(fields[3].replace("\\\\", "\\"))


def find_game(requested):
    if requested:
        return normalize_game(requested)
    steam_roots = [
        Path.home() / ".local/share/Steam",
        Path.home() / ".steam/steam",
    ]
    steam_roots.extend(Path("/mnt").glob("*/SteamLibrary"))
    seen = set()
    for steam in steam_roots:
        for library in steam_libraries(steam):
            candidate = library / "steamapps/common/GarrysMod"
            key = str(candidate)
            if key not in seen and (candidate / "garrysmod/gameinfo.txt").is_file():
                return candidate.resolve()
            seen.add(key)
    raise RuntimeError("Could not find Garry's Mod. Pass --game /path/to/GarrysMod.")


def ensure_game_closed(skip):
    if skip or os.name == "nt":
        return
    proc = Path("/proc")
    if not proc.is_dir():
        return
    for entry in proc.iterdir():
        if not entry.name.isdigit():
            continue
        try:
            cmd = (entry / "cmdline").read_bytes().replace(b"\0", b" ").lower()
        except (OSError, PermissionError):
            continue
        if b"garrysmod/bin/win64/gmod.exe" in cmd or b"/gmod.exe" in cmd:
            raise RuntimeError("Garry's Mod is running. Fully quit it before installing.")


def load_manifest():
    with MANIFEST.open(encoding="utf-8") as handle:
        return json.load(handle)


def hex_bytes(value):
    return bytes.fromhex(value)


def preflight(game, manifest, uninstall):
    result = []
    for spec in manifest["files"]:
        target = game / spec["path"]
        if not target.is_file():
            raise RuntimeError(f"Missing game file: {target}")
        current = sha256(target)
        pristine = spec["pristine_sha256"]
        patched = spec["patched_sha256"]
        if current not in (pristine, patched):
            raise RuntimeError(
                f"Unsupported or modified file: {target}\n"
                f"Expected {pristine} or {patched}\nFound    {current}\n"
                "Run Steam Verify, then try again."
            )
        backup = target.with_name(spec["backup"])
        if uninstall and current == patched:
            if not backup.is_file() or sha256(backup) != pristine:
                raise RuntimeError(f"Verified v1 backup is missing or invalid: {backup}")
        result.append((spec, target, backup, current))
    return result


def atomic_write(target, data, expected_hash):
    temp_name = None
    try:
        with tempfile.NamedTemporaryFile(dir=target.parent, delete=False) as handle:
            temp_name = handle.name
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
        temp = Path(temp_name)
        if sha256(temp) != expected_hash:
            raise RuntimeError(f"Generated file failed verification: {target.name}")
        os.replace(temp, target)
    finally:
        if temp_name:
            Path(temp_name).unlink(missing_ok=True)


def patch_file(spec, target, backup, current):
    if current == spec["patched_sha256"]:
        if not backup.exists():
            legacy = target.with_name(target.name + ".bak")
            if legacy.is_file() and sha256(legacy) == spec["pristine_sha256"]:
                shutil.copy2(legacy, backup)
                print(f"Adopted verified backup: {backup}")
        print(f"Already patched: {target.name}")
        return
    if backup.exists():
        if sha256(backup) != spec["pristine_sha256"]:
            raise RuntimeError(f"Refusing to overwrite invalid backup: {backup}")
    else:
        shutil.copy2(target, backup)
    data = bytearray(target.read_bytes())
    for patch in spec["patches"]:
        offset = int(patch["offset"], 0)
        before = hex_bytes(patch["before"])
        after = hex_bytes(patch["after"])
        if len(before) != len(after):
            raise RuntimeError(f"Invalid manifest patch at {patch['offset']}")
        if data[offset:offset + len(before)] != before:
            raise RuntimeError(f"Unexpected bytes in {target.name} at {patch['offset']}")
        data[offset:offset + len(after)] = after
    atomic_write(target, data, spec["patched_sha256"])
    print(f"Patched: {target}")


def install_addon(game):
    destination = game / "garrysmod/addons/sticky_blood"
    if destination.exists():
        shutil.rmtree(destination)
    destination.mkdir(parents=True)
    shutil.copy2(ROOT / "addon.json", destination / "addon.json")
    shutil.copytree(ROOT / "lua", destination / "lua")
    print(f"Installed addon: {destination}")


def remove_addon(game):
    destination = game / "garrysmod/addons/sticky_blood"
    if destination.exists():
        shutil.rmtree(destination)
        print(f"Removed addon: {destination}")


def install(game, manifest):
    entries = preflight(game, manifest, False)
    for spec, target, backup, current in entries:
        patch_file(spec, target, backup, current)
    install_addon(game)


def uninstall(game, manifest):
    entries = preflight(game, manifest, True)
    for spec, target, backup, current in entries:
        if current == spec["pristine_sha256"]:
            print(f"Already restored: {target.name}")
            continue
        atomic_write(target, backup.read_bytes(), spec["pristine_sha256"])
        backup.unlink()
        print(f"Restored: {target}")
    remove_addon(game)


def main():
    parser = argparse.ArgumentParser(description="Install or remove Sticky Blood v1.0")
    parser.add_argument("action", choices=("install", "uninstall"))
    parser.add_argument("--game", help="Path to GarrysMod or its garrysmod folder")
    parser.add_argument("--skip-running-check", action="store_true", help=argparse.SUPPRESS)
    args = parser.parse_args()
    try:
        game = find_game(args.game)
        ensure_game_closed(args.skip_running_check)
        manifest = load_manifest()
        print(f"Game: {game}")
        if args.action == "install":
            install(game, manifest)
        else:
            uninstall(game, manifest)
    except Exception as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1
    print("Done. Fully restart Garry's Mod.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
