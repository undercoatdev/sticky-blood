#!/usr/bin/env python3
"""Sticky Blood installer.

Patches are found by wildcard byte signatures (manifest format 2). Every site
must match exactly once. Files are left untouched when a signature is missing,
ambiguous, or the original bytes differ. The PowerShell installer implements
the same plan.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import struct
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parent.parent
MANIFEST = ROOT / "patches" / "v2.json"
V1_MANIFEST = ROOT / "patches" / "v1.0.0.json"

UNSUPPORTED = "This Garry's Mod build isn't supported (signature {0} not found or ambiguous)"
BRANCH_REQUIRED = "64-bit (x86-64 branch) required"
STEAM_VERIFY = (
    "The installed files do not match the Sticky Blood backup. "
    "Run Steam Verify, then try again."
)


class PatchError(Exception):
    def __init__(self, signature, detail):
        self.signature = signature
        super().__init__(detail)


def unsupported_message(signature):
    name = signature or "unknown"
    return UNSUPPORTED.format(name)


def sha256_bytes(data):
    return hashlib.sha256(data).hexdigest()


def sha256_file(path):
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def parse_sig(text):
    """'aa ?? [bb cc] dd' -> (pattern of int|None, site index, site length)."""
    tokens = text.replace("[", " [ ").replace("]", " ] ").split()
    pattern = []
    site = None
    end = None
    for token in tokens:
        if token == "[":
            site = len(pattern)
        elif token == "]":
            end = len(pattern)
        elif token == "??":
            pattern.append(None)
        else:
            pattern.append(int(token, 16))
    if site is None:
        site = 0
        end = len(pattern)
    return pattern, site, end - site


def find_all(data, pattern):
    best = (0, 0)
    index = 0
    while index < len(pattern):
        if pattern[index] is None:
            index += 1
            continue
        end = index
        while end < len(pattern) and pattern[end] is not None:
            end += 1
        if end - index > best[1] - best[0]:
            best = (index, end)
        index = end
    start, end = best
    if end - start < 4:
        raise PatchError(None, "signature needs >=4 consecutive literal bytes")
    key = bytes(pattern[start:end])
    hits = []
    found = data.find(key)
    while found != -1:
        origin = found - start
        if origin >= 0 and origin + len(pattern) <= len(data):
            if all(
                byte is None or data[origin + offset] == byte
                for offset, byte in enumerate(pattern)
            ):
                hits.append(origin)
        found = data.find(key, found + 1)
    return hits


def find_unique(data, signature, name):
    try:
        pattern, site, _ = parse_sig(signature)
        hits = find_all(data, pattern)
    except PatchError as exc:
        raise PatchError(name, str(exc)) from exc
    if len(hits) != 1:
        raise PatchError(name, f"{name}: signature matched {len(hits)} times (need exactly 1)")
    return hits[0] + site, pattern


def resolve_replace(text, at, original, labels):
    output = []
    for token in re.findall(r"\{[^}]+\}|\S+", text):
        if token.startswith("{rel32:"):
            name = token[7:-1]
            if name == "@jcc32":
                target = at + 6 + struct.unpack("<i", bytes(original[2:6]))[0]
            else:
                match = re.fullmatch(r"([\w]+)([+-]\d+)?", name)
                if not match or match.group(1) not in labels:
                    raise PatchError(name, f"unknown label {name}")
                target = labels[match.group(1)] + int(match.group(2) or 0)
            relative = target - (at + len(output) + 4)
            try:
                output.extend(struct.pack("<i", relative))
            except struct.error as exc:
                raise PatchError(name, "rel32 out of range") from exc
        elif token == "{keep}":
            output.append(original[len(output)])
        else:
            output.append(int(token, 16))
    return bytes(output)


def text_range(data):
    """File-offset span of .text. rel32 is computed on file offsets."""
    try:
        if len(data) < 0x40:
            raise PatchError(None, "no .text section")
        pe = struct.unpack_from("<I", data, 0x3C)[0]
        sections = struct.unpack_from("<H", data, pe + 6)[0]
        optional = struct.unpack_from("<H", data, pe + 20)[0]
        header = pe + 24 + optional
        for index in range(sections):
            name, _virtual_size, _virtual, raw_size, raw = struct.unpack_from(
                "<8sIIII", data, header + 40 * index
            )
            if name.rstrip(b"\0") == b".text":
                return raw, raw + raw_size
    except (struct.error, IndexError) as exc:
        raise PatchError(None, "no .text section") from exc
    raise PatchError(None, "no .text section")


def replace_pattern(text):
    output = []
    for token in re.findall(r"\{[^}]+\}|\S+", text):
        if token.startswith("{rel32:"):
            output.extend([None, None, None, None])
        elif token == "{keep}":
            output.append(None)
        else:
            output.append(int(token, 16))
    return output


def _literals_match(window, expect):
    if len(window) != len(expect):
        return False
    found = 0
    for have, want in zip(window, expect):
        if want is None:
            continue
        if have is None or have != want:
            return False
        found += 1
    return found >= 4


def _edge_match(window, expect):
    if not window or len(window) != len(expect):
        return False
    for have, want in zip(window, expect):
        if want is None or have is None or have != want:
            return False
    return True


def patched_pattern(patch, patches):
    """Signature with [expect] swapped for [replace].

    Context bytes that another patch in the same file overwrites are wildcarded.
    Neighbouring sites share signature context (the studio limit check and its
    following NOP, and one padding byte between the two caves).
    """
    pattern, site, length = parse_sig(patch["sig"])
    replacement = replace_pattern(patch["replace"])
    if len(replacement) != length:
        raise PatchError(patch["id"], "replace length")
    pattern = pattern[:site] + replacement + pattern[site + length:]
    for other in patches:
        if other["id"] == patch["id"]:
            continue
        expect, _, _ = parse_sig(other["expect"])
        for index in range(0, len(pattern) - len(expect) + 1):
            if index + len(expect) <= site or index >= site + length:
                if _literals_match(pattern[index:index + len(expect)], expect):
                    for offset in range(len(expect)):
                        pattern[index + offset] = None
        limit = len(pattern) - (site + length)
        best = 0
        for size in range(1, min(limit, len(expect)) + 1):
            if _edge_match(pattern[-size:], expect[:size]):
                best = size
        for offset in range(best):
            pattern[-1 - offset] = None
        best = 0
        for size in range(1, min(site, len(expect)) + 1):
            if _edge_match(pattern[:size], expect[-size:]):
                best = size
        for offset in range(best):
            pattern[offset] = None
    return pattern, site


def plan_file(data, spec):
    low, high = text_range(data)
    labels = {}
    for anchor in spec.get("anchors") or []:
        labels[anchor["id"]], _ = find_unique(data, anchor["sig"], anchor["id"])
    sites = []
    for patch in spec["patches"]:
        at, _pattern = find_unique(data, patch["sig"], patch["id"])
        labels[patch["id"]] = at
        sites.append((patch, at))
    for name, offset in labels.items():
        if not low <= offset < high:
            raise PatchError(name, f"{name} outside .text")
    edits = []
    for patch, at in sites:
        expect, _, _ = parse_sig(patch["expect"])
        _, _, bracket_len = parse_sig(patch["sig"])
        if len(expect) != bracket_len:
            raise PatchError(patch["id"], "expect length")
        original = bytes(data[at:at + len(expect)])
        if any(byte is not None and byte != original[index] for index, byte in enumerate(expect)):
            raise PatchError(patch["id"], f"{patch['id']}: original bytes differ")
        replacement = resolve_replace(patch["replace"], at, original, labels)
        if len(replacement) != len(expect):
            raise PatchError(
                patch["id"],
                f"{patch['id']}: replace length {len(replacement)} != expect {len(expect)}",
            )
        required = patch.get("require_before")
        if required:
            prologue, _, _ = parse_sig(required["sig"])
            start = at - required["distance"]
            if start < 0 or start + len(prologue) > len(data) or any(
                byte is not None and data[start + index] != byte
                for index, byte in enumerate(prologue)
            ):
                raise PatchError(
                    patch["id"],
                    f"{patch['id']}: required function prologue not found at site-{required['distance']}",
                )
        edits.append((patch["id"], at, original, replacement))
    edits.sort(key=lambda item: (item[1], item[0]))
    for (left_id, left_at, left_old, _), (right_id, right_at, _, _) in zip(edits, edits[1:]):
        if left_at + len(left_old) > right_at:
            raise PatchError(left_id, f"overlap {left_id}/{right_id}")
    return edits, labels


def matches_patched(data, spec):
    low, high = text_range(data)
    for anchor in spec.get("anchors") or []:
        at, _ = find_unique(data, anchor["sig"], anchor["id"])
        if not low <= at < high:
            raise PatchError(anchor["id"], f"{anchor['id']} outside .text")
    patches = spec["patches"]
    for patch in patches:
        try:
            pattern, site = patched_pattern(patch, patches)
            hits = find_all(data, pattern)
        except PatchError as exc:
            raise PatchError(patch["id"], str(exc)) from exc
        if len(hits) != 1:
            raise PatchError(patch["id"], f"{patch['id']}: signature matched {len(hits)} times")
        at = hits[0] + site
        if not low <= at < high:
            raise PatchError(patch["id"], f"{patch['id']} outside .text")
        required = patch.get("require_before")
        if required:
            prologue, _, _ = parse_sig(required["sig"])
            start = at - required["distance"]
            if start < 0 or start + len(prologue) > len(data) or any(
                byte is not None and data[start + index] != byte
                for index, byte in enumerate(prologue)
            ):
                raise PatchError(patch["id"], "prologue")
    return True


def classify_bytes(data, spec):
    try:
        edits, labels = plan_file(data, spec)
        return "pristine", edits, labels
    except PatchError as first:
        try:
            matches_patched(data, spec)
        except PatchError:
            raise PatchError(first.signature, unsupported_message(first.signature)) from first
        return "patched", None, None


def apply_edits(data, edits):
    output = bytearray(data)
    for _name, at, original, replacement in edits:
        if output[at:at + len(original)] != original:
            raise PatchError(None, "edit slipped")
        output[at:at + len(replacement)] = replacement
    return bytes(output)


def sites_match(original, patched, edits):
    if len(original) != len(patched):
        return False
    restored = bytearray(patched)
    for _name, at, original_bytes, replacement in edits:
        if patched[at:at + len(replacement)] != replacement:
            return False
        restored[at:at + len(replacement)] = original_bytes
    return bytes(restored) == original


def describe(filename, digest, spec, state, edits):
    lines = [f"FILE {filename}"]
    if state == "patched":
        lines.append("patched")
        return lines
    known = digest in set(spec.get("known_pristine_sha256") or [])
    lines.append("known build" if known else "unknown build, signatures OK")
    for name, at, original, replacement in edits:
        lines.append(f"{name} {format(at, '#x')} {original.hex()} -> {replacement.hex()}")
    return lines


def load_json(path):
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def load_manifest():
    manifest = load_json(MANIFEST)
    if manifest.get("format") != 2:
        raise RuntimeError("Unsupported patch manifest format")
    return manifest


def load_v1_index():
    if not V1_MANIFEST.is_file():
        return {}
    manifest = load_json(V1_MANIFEST)
    index = {}
    for spec in manifest["files"]:
        index[Path(spec["path"]).name] = spec
    return index


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
            command = (entry / "cmdline").read_bytes().replace(b"\0", b" ").lower()
        except (OSError, PermissionError):
            continue
        if b"garrysmod/bin/win64/gmod.exe" in command or b"/gmod.exe" in command:
            raise RuntimeError("Garry's Mod is running. Fully quit it before installing.")


def target_for(game, spec):
    return game / spec["path"]


def require_binaries(game, manifest):
    win64 = game / "bin" / "win64"
    if not win64.is_dir():
        raise RuntimeError(BRANCH_REQUIRED)
    for spec in manifest["files"]:
        if not target_for(game, spec).is_file():
            raise RuntimeError(BRANCH_REQUIRED)


def atomic_commit(target, data, original=None, edits=None):
    temp_name = None
    try:
        with tempfile.NamedTemporaryFile(dir=target.parent, delete=False) as handle:
            temp_name = handle.name
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
        temp = Path(temp_name)
        readback = temp.read_bytes()
        if readback != data:
            raise RuntimeError(f"Generated file failed verification: {target.name}")
        if edits is not None and not sites_match(original, readback, edits):
            raise RuntimeError(f"Generated file failed verification: {target.name}")
        os.replace(temp, target)
        temp_name = None
    finally:
        if temp_name:
            Path(temp_name).unlink(missing_ok=True)


def copy_atomic(source, destination):
    temp_name = None
    try:
        with tempfile.NamedTemporaryFile(dir=destination.parent, delete=False) as handle:
            temp_name = handle.name
        temp = Path(temp_name)
        shutil.copy2(source, temp)
        os.replace(temp, destination)
        temp_name = None
    finally:
        if temp_name:
            Path(temp_name).unlink(missing_ok=True)


def v1_backup_candidates(target, v1_spec):
    candidates = []
    if v1_spec:
        candidates.append(target.with_name(v1_spec["backup"]))
    legacy = target.with_name(target.name + ".bak")
    if legacy not in candidates:
        candidates.append(legacy)
    return candidates


def matching_v1_backup(target, v1_spec, expected_hash):
    if not v1_spec or expected_hash != v1_spec["pristine_sha256"]:
        return None
    for candidate in v1_backup_candidates(target, v1_spec):
        if candidate.is_file() and sha256_file(candidate) == v1_spec["pristine_sha256"]:
            return candidate
    return None


def backup_path(target, spec):
    return target.with_name(spec["backup"])


def sidecar_path(target):
    return target.with_name(target.name + ".stickyblood.json")


def ensure_backup(target, spec, current_hash, v1_spec):
    backup = backup_path(target, spec)
    if backup.exists():
        if sha256_file(backup) != current_hash:
            stamp = time.strftime("%Y%m%d%H%M%S", time.gmtime())
            stamped = target.with_name(f"{target.name}.stickyblood.{stamp}.bak")
            counter = 1
            while stamped.exists():
                stamped = target.with_name(f"{target.name}.stickyblood.{stamp}-{counter}.bak")
                counter += 1
            backup.rename(stamped)
            copy_atomic(target, backup)
    else:
        adopted = None
        if v1_spec and current_hash == v1_spec["pristine_sha256"]:
            adopted = matching_v1_backup(target, v1_spec, v1_spec["pristine_sha256"])
        if adopted:
            copy_atomic(adopted, backup)
        else:
            copy_atomic(target, backup)
    if sha256_file(backup) != current_hash:
        raise RuntimeError(f"Backup does not match the game file: {backup}")
    return backup


def write_sidecar(target, pristine_hash, patched_hash, version, labels):
    payload = {
        "offsets": {name: hex(offset) for name, offset in sorted(labels.items())},
        "patched_sha256": patched_hash,
        "pristine_sha256": pristine_hash,
        "version": version,
    }
    data = (json.dumps(payload, indent=2, sort_keys=True) + "\n").encode("utf-8")
    atomic_commit(sidecar_path(target), data)


def read_sidecar(target):
    path = sidecar_path(target)
    if not path.is_file():
        return None
    return load_json(path)


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


def prepare(game, manifest, strict=True):
    require_binaries(game, manifest)
    prepared = []
    for spec in manifest["files"]:
        target = target_for(game, spec)
        data = target.read_bytes()
        error = None
        try:
            state, edits, labels = classify_bytes(data, spec)
        except PatchError as exc:
            if strict:
                raise RuntimeError(str(exc)) from exc
            state, edits, labels = "unsupported", None, None
            error = str(exc)
        prepared.append(
            {
                "spec": spec,
                "target": target,
                "data": data,
                "digest": sha256_bytes(data),
                "state": state,
                "edits": edits,
                "labels": labels,
                "error": error,
            }
        )
    return prepared


def render_plan(game, prepared):
    lines = [f"Game: {game}"]
    for item in prepared:
        lines.extend(
            describe(
                item["target"].name,
                item["digest"],
                item["spec"],
                item["state"],
                item["edits"],
            )
        )
    return lines


def install_game(game, manifest, v1_index, dry_run=False):
    prepared = prepare(game, manifest)
    if dry_run:
        for line in render_plan(game, prepared):
            print(line)
        return 0
    for item in prepared:
        print_status(item)
        if item["state"] == "patched":
            print(f"Already patched: {item['target'].name}")
            continue
        if item["state"] != "pristine":
            raise RuntimeError(unsupported_message("unknown"))
        v1_spec = v1_index.get(item["target"].name)
        ensure_backup(item["target"], item["spec"], item["digest"], v1_spec)
        patched = apply_edits(item["data"], item["edits"])
        if not sites_match(item["data"], patched, item["edits"]):
            raise RuntimeError(f"Generated file failed verification: {item['target'].name}")
        patched_hash = sha256_bytes(patched)
        # Sidecar first: a crash before the DLL rename leaves the original file,
        # which uninstall reports as already restored.
        write_sidecar(
            item["target"],
            item["digest"],
            patched_hash,
            manifest["version"],
            item["labels"],
        )
        try:
            atomic_commit(item["target"], patched, item["data"], item["edits"])
        except Exception:
            sidecar_path(item["target"]).unlink(missing_ok=True)
            raise
        print(f"Patched: {item['target']}")
    install_addon(game)
    return 0


def print_status(item):
    for line in describe(
        item["target"].name,
        item["digest"],
        item["spec"],
        item["state"],
        item["edits"],
    ):
        print(line)


def decide_uninstall(item, v1_spec):
    target = item["target"]
    current = item["digest"]
    sidecar = read_sidecar(target)
    backup = backup_path(target, item["spec"])
    if sidecar and current == sidecar.get("pristine_sha256"):
        return {"action": "restored", "target": target}
    if (
        sidecar
        and current == sidecar.get("patched_sha256")
        and backup.is_file()
        and sha256_file(backup) == sidecar.get("pristine_sha256")
    ):
        return {
            "action": "restore",
            "target": target,
            "source": backup,
            "expected": sidecar["pristine_sha256"],
            "delete": [backup, sidecar_path(target)],
        }
    if v1_spec and current == v1_spec["patched_sha256"]:
        source = matching_v1_backup(target, v1_spec, v1_spec["pristine_sha256"])
        if source:
            delete = []
            if source.name.endswith(".stickyblood-v1.bak"):
                delete.append(source)
            if sidecar_path(target).exists():
                delete.append(sidecar_path(target))
            return {
                "action": "restore",
                "target": target,
                "source": source,
                "expected": v1_spec["pristine_sha256"],
                "delete": delete,
            }
    if item["state"] == "pristine" and sidecar:
        delete = [sidecar_path(target)]
        if backup.exists():
            delete.append(backup)
        return {"action": "stale", "target": target, "delete": delete}
    if item["state"] == "pristine" and not sidecar:
        return {"action": "restored", "target": target}
    raise RuntimeError(STEAM_VERIFY)


def uninstall_game(game, manifest, v1_index, dry_run=False):
    prepared = prepare(game, manifest, strict=False)
    if dry_run:
        failed = next((item for item in prepared if item["state"] == "unsupported"), None)
        if failed:
            raise RuntimeError(failed["error"])
        for line in render_plan(game, prepared):
            print(line)
        return 0
    decisions = []
    for item in prepared:
        v1_spec = v1_index.get(item["target"].name)
        decisions.append(decide_uninstall(item, v1_spec))
    for decision in decisions:
        action = decision["action"]
        target = decision["target"]
        if action == "restored":
            print(f"Already restored: {target.name}")
            continue
        if action == "stale":
            for path in decision["delete"]:
                if path.exists():
                    path.unlink()
                    print(f"Removed stale backup: {path.name}")
            continue
        data = decision["source"].read_bytes()
        atomic_commit(target, data)
        if sha256_file(target) != decision["expected"]:
            raise RuntimeError(f"Generated file failed verification: {target.name}")
        for path in decision["delete"]:
            if path.exists() and path != target:
                path.unlink()
        print(f"Restored: {target}")
    remove_addon(game)
    return 0


def main():
    parser = argparse.ArgumentParser(description="Install or remove Sticky Blood v1.1.0")
    parser.add_argument("action", choices=("install", "uninstall"))
    parser.add_argument("--game", help="Path to GarrysMod or its garrysmod folder")
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print the patch plan and do not modify the game",
    )
    parser.add_argument("--skip-running-check", action="store_true", help=argparse.SUPPRESS)
    args = parser.parse_args()
    try:
        game = find_game(args.game)
        ensure_game_closed(args.skip_running_check)
        manifest = load_manifest()
        v1_index = load_v1_index()
        if not args.dry_run:
            print(f"Game: {game}")
        if args.action == "install":
            install_game(game, manifest, v1_index, dry_run=args.dry_run)
        else:
            uninstall_game(game, manifest, v1_index, dry_run=args.dry_run)
    except (RuntimeError, PatchError, OSError) as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1
    if not args.dry_run:
        print("Done. Fully restart Garry's Mod.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
