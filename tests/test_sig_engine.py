#!/usr/bin/env python3
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import random
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
FILL = 0xA5


def load_installer():
    path = ROOT / "tools" / "sticky_blood.py"
    spec = importlib.util.spec_from_file_location("sticky_blood", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


SB = load_installer()


def decode_output(data):
    if data.startswith(b"\xff\xfe") or (len(data) > 3 and data[1] == 0 and data[3] == 0):
        return data.decode("utf-16")
    return data.decode("utf-8")


def wrap_pe(text):
    e_lfanew = 0x80
    dos = bytearray(e_lfanew)
    dos[0:2] = b"MZ"
    struct.pack_into("<I", dos, 0x3C, e_lfanew)
    optional_size = 0xF0
    coff = bytearray(20)
    struct.pack_into("<H", coff, 0, 0x8664)
    struct.pack_into("<H", coff, 2, 1)
    struct.pack_into("<H", coff, 16, optional_size)
    optional = bytearray(optional_size)
    struct.pack_into("<H", optional, 0, 0x20B)
    section = bytearray(40)
    section[0:5] = b".text"
    struct.pack_into("<I", section, 8, len(text))
    struct.pack_into("<I", section, 12, 0x1000)
    struct.pack_into("<I", section, 16, len(text))
    struct.pack_into("<I", section, 20, 0x200)
    headers = dos + b"PE\0\0" + bytes(coff) + bytes(optional) + bytes(section)
    return bytes(headers.ljust(0x200, b"\x00") + text)


def materialize(signature, rng):
    pattern, site, _length = SB.parse_sig(signature)
    raw = bytearray()
    for byte in pattern:
        raw.append(rng.randrange(1, 255) if byte is None else byte)
    return bytes(raw), site


def build_text(spec, rng, shift=0, drop_id=None, duplicate_id=None, flip_prologue=False):
    items = []
    for anchor in spec.get("anchors") or []:
        raw, site = materialize(anchor["sig"], rng)
        items.append({"id": anchor["id"], "raw": raw, "site": site, "require": None})
    for patch in spec["patches"]:
        raw, site = materialize(patch["sig"], rng)
        items.append(
            {
                "id": patch["id"],
                "raw": raw,
                "site": site,
                "require": patch.get("require_before"),
            }
        )
    present = {item["id"] for item in items}
    if drop_id not in present:
        drop_id = None
    if duplicate_id not in present:
        duplicate_id = None
    gap = 800
    cursor = 500 + shift
    placed = []
    for item in items:
        item["start"] = cursor
        cursor += len(item["raw"]) + gap
        placed.append(item)
    if duplicate_id:
        cursor += gap
    text = bytearray([FILL]) * (cursor + 64)
    occupied = []

    def claim(start, blob):
        end = start + len(blob)
        for left, right in occupied:
            if start < right and left < end:
                raise AssertionError(f"synthetic layout overlap at {start:#x}")
        occupied.append((start, end))
        text[start:end] = blob

    for item in placed:
        if item["id"] == drop_id:
            continue
        claim(item["start"], item["raw"])
        required = item["require"]
        if not required:
            continue
        prologue, _, _ = SB.parse_sig(required["sig"])
        blob = bytes(byte if byte is not None else 0x11 for byte in prologue)
        pro_at = item["start"] + item["site"] - required["distance"]
        if flip_prologue and item["id"] == "en_return_null":
            blob = bytes([blob[0] ^ 0xFF]) + blob[1:]
        claim(pro_at, blob)
    if duplicate_id:
        source = next(item for item in placed if item["id"] == duplicate_id)
        claim(cursor - 64, source["raw"])
    return bytes(text)


def synthesize(manifest, seed=1, **kwargs):
    rng = random.Random(seed)
    files = {}
    for spec in manifest["files"]:
        files[spec["path"]] = wrap_pe(build_text(spec, rng, **kwargs))
    return files


def make_game(root, files):
    game = root / "GarrysMod"
    (game / "garrysmod").mkdir(parents=True)
    (game / "garrysmod" / "gameinfo.txt").write_text('"GameInfo" {}\n', encoding="utf-8")
    for relative, data in files.items():
        target = game / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
    return game


def snapshot(game):
    found = {}
    for path in game.rglob("*"):
        if path.is_file():
            found[path.relative_to(game).as_posix()] = hashlib.sha256(path.read_bytes()).hexdigest()
    return found


def rel32_target(buf, at):
    disp = struct.unpack_from("<i", buf, at + 1)[0]
    return at + 5 + disp


class SignatureEngineTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.manifest = SB.load_manifest()

    def plan(self, files):
        planned = {}
        for spec in self.manifest["files"]:
            data = files[spec["path"]]
            state, edits, labels = SB.classify_bytes(data, spec)
            self.assertEqual(state, "pristine")
            patched = SB.apply_edits(data, edits)
            self.assertTrue(SB.sites_match(data, patched, edits))
            planned[spec["path"]] = (data, patched, edits, labels)
        return planned

    def assert_rel32(self, data, patched, edits, labels):
        by_id = {name: (at, original, replacement) for name, at, original, replacement in edits}
        at, original, replacement = by_id["sr_jump_past_flush"]
        self.assertEqual(replacement[0], 0xE9)
        self.assertEqual(rel32_target(patched, at), labels["sr_flush_exit"])
        at, _original, replacement = by_id["sr_find_hook"]
        self.assertEqual(rel32_target(patched, at), labels["sr_cave1"])
        at, original, replacement = by_id["sr_skip_lod_evict"]
        old_disp = struct.unpack_from("<i", original, 2)[0]
        self.assertEqual(at + 6 + old_disp, rel32_target(patched, at))
        at, _original, replacement = by_id["sr_cave1"]
        self.assertEqual(replacement[8], 0xE9)
        self.assertEqual(rel32_target(patched, at + 8), labels["sr_cave2"])
        self.assertEqual(replacement[13], 0xE9)
        self.assertEqual(rel32_target(patched, at + 13), labels["sr_find_continue"])
        self.assertEqual(patched[at + 6], 0x75)
        self.assertEqual(patched[at + 7], 0x05)

    def test_patch_rel32_and_shift(self):
        base = synthesize(self.manifest, seed=3)
        shifted = synthesize(self.manifest, seed=3, shift=80)
        for files in (base, shifted):
            planned = self.plan(files)
            for spec in self.manifest["files"]:
                data, patched, edits, labels = planned[spec["path"]]
                low, high = SB.text_range(data)
                for name, offset in labels.items():
                    self.assertTrue(low <= offset < high)
                again, _, _ = SB.classify_bytes(patched, spec)
                self.assertEqual(again, "patched")
            studio = planned["bin/win64/studiorender.dll"]
            self.assert_rel32(*studio)
        base_offsets = {
            name: at
            for name, at, _old, _new in self.plan(base)["bin/win64/studiorender.dll"][2]
        }
        shift_offsets = {
            name: at
            for name, at, _old, _new in self.plan(shifted)["bin/win64/studiorender.dll"][2]
        }
        for name, offset in base_offsets.items():
            self.assertEqual(shift_offsets[name], offset + 80)

    def test_failures_write_nothing(self):
        cases = (
            {"drop_id": "sr_limit_b", "signature": "sr_limit_b"},
            {"duplicate_id": "sr_skip_count_evict", "signature": "sr_skip_count_evict"},
            {"flip_prologue": True, "signature": "en_return_null"},
        )
        for case in cases:
            kwargs = dict(case)
            signature = kwargs.pop("signature")
            with self.subTest(signature=signature):
                files = synthesize(self.manifest, seed=5, **kwargs)
                with tempfile.TemporaryDirectory() as temp:
                    game = make_game(Path(temp), files)
                    before = snapshot(game)
                    with self.assertRaises(RuntimeError) as caught:
                        SB.install_game(game, self.manifest, {}, dry_run=False)
                    self.assertIn(signature, str(caught.exception))
                    self.assertIn("isn't supported", str(caught.exception))
                    self.assertEqual(before, snapshot(game))

    def test_wrong_expect_writes_nothing(self):
        files = synthesize(self.manifest, seed=7)
        manifest = json.loads(json.dumps(self.manifest))
        patch = next(
            patch
            for spec in manifest["files"]
            if spec["path"].endswith("studiorender.dll")
            for patch in spec["patches"]
            if patch["id"] == "sr_limit_c"
        )
        patch["expect"] = "00 41 00 00"
        with tempfile.TemporaryDirectory() as temp:
            game = make_game(Path(temp), files)
            before = snapshot(game)
            with self.assertRaises(RuntimeError) as caught:
                SB.install_game(game, manifest, {}, dry_run=False)
            self.assertIn("sr_limit_c", str(caught.exception))
            self.assertEqual(before, snapshot(game))

    def test_outside_text_writes_nothing(self):
        files = synthesize(self.manifest, seed=9)
        spec = self.manifest["files"][0]
        data = bytearray(files[spec["path"]])
        low, high = SB.text_range(data)
        self.assertGreater(high - low, 1)
        struct.pack_into("<I", data, 0x188 + 16, 1)
        shrunk = SB.text_range(bytes(data))
        self.assertEqual(shrunk[1] - shrunk[0], 1)
        files[spec["path"]] = bytes(data)
        with tempfile.TemporaryDirectory() as temp:
            game = make_game(Path(temp), files)
            before = snapshot(game)
            with self.assertRaises(RuntimeError) as caught:
                SB.install_game(game, self.manifest, {}, dry_run=False)
            self.assertIn("isn't supported", str(caught.exception))
            self.assertEqual(before, snapshot(game))

    def test_install_uninstall_round_trip_and_repatch(self):
        files = synthesize(self.manifest, seed=11)
        with tempfile.TemporaryDirectory() as temp:
            game = make_game(Path(temp), files)
            originals = {path: blob for path, blob in files.items()}
            SB.install_game(game, self.manifest, {}, dry_run=False)
            patched = {}
            for relative, original in originals.items():
                target = game / relative
                patched[relative] = target.read_bytes()
                self.assertNotEqual(patched[relative], original)
                self.assertTrue((target.with_name(target.name + ".stickyblood.bak")).is_file())
                self.assertTrue((target.with_name(target.name + ".stickyblood.json")).is_file())
                state, _, _ = SB.classify_bytes(patched[relative], next(
                    spec for spec in self.manifest["files"] if spec["path"] == relative
                ))
                self.assertEqual(state, "patched")
            before_second = snapshot(game)
            SB.install_game(game, self.manifest, {}, dry_run=False)
            self.assertEqual(before_second, snapshot(game))
            SB.uninstall_game(game, self.manifest, {}, dry_run=False)
            for relative, original in originals.items():
                self.assertEqual((game / relative).read_bytes(), original)
                target = game / relative
                self.assertFalse((target.with_name(target.name + ".stickyblood.bak")).exists())
                self.assertFalse((target.with_name(target.name + ".stickyblood.json")).exists())
            self.assertFalse((game / "garrysmod/addons/sticky_blood").exists())
            SB.uninstall_game(game, self.manifest, {}, dry_run=False)

    def test_timestamped_backup_and_stale_uninstall(self):
        files = synthesize(self.manifest, seed=13)
        shifted = synthesize(self.manifest, seed=13, shift=40)
        with tempfile.TemporaryDirectory() as temp:
            game = make_game(Path(temp), files)
            spec = self.manifest["files"][0]
            target = game / spec["path"]
            stale = target.with_name(spec["backup"])
            stale.write_bytes(b"not the original dll")
            SB.install_game(game, self.manifest, {}, dry_run=False)
            stamped = list(target.parent.glob(target.name + ".stickyblood.*.bak"))
            self.assertEqual(len(stamped), 1)
            self.assertEqual(stale.read_bytes(), files[spec["path"]])
            shifted_path = spec["path"]
            target.write_bytes(shifted[shifted_path])
            SB.uninstall_game(game, self.manifest, {}, dry_run=False)
            self.assertEqual(target.read_bytes(), shifted[shifted_path])
            self.assertFalse(stale.exists())
            self.assertFalse(target.with_name(target.name + ".stickyblood.json").exists())
            self.assertTrue(stamped[0].is_file())

    def test_corrupt_file_asks_for_steam_verify(self):
        files = synthesize(self.manifest, seed=15)
        with tempfile.TemporaryDirectory() as temp:
            game = make_game(Path(temp), files)
            SB.install_game(game, self.manifest, {}, dry_run=False)
            spec = self.manifest["files"][0]
            target = game / spec["path"]
            data = bytearray(target.read_bytes())
            data[SB.plan_file(files[spec["path"]], spec)[0][0][1]] ^= 0xFF
            target.write_bytes(data)
            backup = target.with_name(spec["backup"])
            sidecar = target.with_name(target.name + ".stickyblood.json")
            with self.assertRaises(RuntimeError) as caught:
                SB.uninstall_game(game, self.manifest, {}, dry_run=False)
            self.assertIn("Steam Verify", str(caught.exception))
            self.assertTrue(backup.is_file())
            self.assertTrue(sidecar.is_file())
            self.assertEqual(target.read_bytes(), bytes(data))

    def test_missing_win64_message(self):
        with tempfile.TemporaryDirectory() as temp:
            game = Path(temp) / "GarrysMod"
            (game / "garrysmod").mkdir(parents=True)
            (game / "garrysmod" / "gameinfo.txt").write_text("x\n", encoding="utf-8")
            result = subprocess.run(
                [
                    sys.executable,
                    ROOT / "tools/sticky_blood.py",
                    "install",
                    "--game",
                    str(game),
                    "--skip-running-check",
                ],
                capture_output=True,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("64-bit (x86-64 branch) required", decode_output(result.stderr))

    def test_powershell_parity(self):
        pwsh = shutil.which("pwsh")
        if not pwsh:
            self.fail("pwsh is required for installer parity")
        shells = [pwsh]
        if os.name == "nt":
            windows = shutil.which("powershell")
            if windows and Path(windows) != Path(pwsh):
                shells.append(windows)
        files = synthesize(self.manifest, seed=21)
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            game = make_game(root / "dry", files)
            python = subprocess.run(
                [
                    sys.executable,
                    ROOT / "tools/sticky_blood.py",
                    "install",
                    "--dry-run",
                    "--game",
                    str(game),
                    "--skip-running-check",
                ],
                capture_output=True,
            )
            self.assertEqual(python.returncode, 0, decode_output(python.stderr))
            python_lines = [line.strip() for line in decode_output(python.stdout).splitlines() if line.strip()]
            self.assertIn("unknown build, signatures OK", python_lines)
            self.assertTrue(any(" -> " in line for line in python_lines))
            for shell in shells:
                with self.subTest(shell=shell):
                    other_game = make_game(root / Path(shell).name, files)
                    result = subprocess.run(
                        [
                            shell,
                            "-NoProfile",
                            "-File",
                            str(ROOT / "tools/sticky_blood.ps1"),
                            "-Action",
                            "install",
                            "-DryRun",
                            "-GamePath",
                            str(other_game),
                            "-SkipRunningCheck",
                        ],
                        capture_output=True,
                    )
                    self.assertEqual(result.returncode, 0, decode_output(result.stderr))
                    other_lines = [line.strip() for line in decode_output(result.stdout).splitlines() if line.strip()]
                    self.assertEqual(other_lines[1:], python_lines[1:])
            py_game = make_game(root / "py-install", files)
            ps_game = make_game(root / "ps-install", files)
            SB.install_game(py_game, self.manifest, SB.load_v1_index(), dry_run=False)
            installed = subprocess.run(
                [
                    pwsh,
                    "-NoProfile",
                    "-File",
                    str(ROOT / "tools/sticky_blood.ps1"),
                    "-Action",
                    "install",
                    "-GamePath",
                    str(ps_game),
                    "-SkipRunningCheck",
                ],
                capture_output=True,
            )
            self.assertEqual(installed.returncode, 0, decode_output(installed.stderr))
            for spec in self.manifest["files"]:
                self.assertEqual((py_game / spec["path"]).read_bytes(), (ps_game / spec["path"]).read_bytes())
                py_side = json.loads((py_game / spec["path"]).with_name(Path(spec["path"]).name + ".stickyblood.json").read_text())
                ps_side = json.loads((ps_game / spec["path"]).with_name(Path(spec["path"]).name + ".stickyblood.json").read_text())
                self.assertEqual(py_side["pristine_sha256"], ps_side["pristine_sha256"])
                self.assertEqual(py_side["patched_sha256"], ps_side["patched_sha256"])
                self.assertEqual(py_side["offsets"], ps_side["offsets"])
                self.assertEqual(py_side["version"], "1.1.0")
            removed = subprocess.run(
                [
                    pwsh,
                    "-NoProfile",
                    "-File",
                    str(ROOT / "tools/sticky_blood.ps1"),
                    "-Action",
                    "uninstall",
                    "-GamePath",
                    str(ps_game),
                    "-SkipRunningCheck",
                ],
                capture_output=True,
            )
            self.assertEqual(removed.returncode, 0, decode_output(removed.stderr))
            for relative, blob in files.items():
                self.assertEqual((ps_game / relative).read_bytes(), blob)


if __name__ == "__main__":
    unittest.main()
