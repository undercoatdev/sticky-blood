#!/usr/bin/env python3
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_GAME = Path(
    "/mnt/107f9d85-72c8-43db-ba8d-4a351f120385/"
    "SteamLibrary/steamapps/common/GarrysMod"
)
GAME = Path(os.environ.get("STICKY_BLOOD_GAME", DEFAULT_GAME))


def digest(data):
    return hashlib.sha256(data).hexdigest()


class ReleaseTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.manifest = json.loads((ROOT / "patches/v1.0.0.json").read_text())
        for spec in cls.manifest["files"]:
            source = GAME / spec["path"]
            backup = source.with_name(source.name + ".bak")
            if not backup.is_file():
                raise unittest.SkipTest(f"Missing local pristine fixture: {backup}")
        subprocess.run([sys.executable, ROOT / "tools/build_release.py"], check=True)

    def make_game(self, base):
        game = base / "GarrysMod"
        (game / "garrysmod").mkdir(parents=True)
        (game / "garrysmod/gameinfo.txt").write_text('"GameInfo" {}\\n')
        for spec in self.manifest["files"]:
            target = game / spec["path"]
            target.parent.mkdir(parents=True, exist_ok=True)
            source = GAME / spec["path"]
            shutil.copy2(source.with_name(source.name + ".bak"), target)
        return game

    def assert_hashes(self, game, key):
        for spec in self.manifest["files"]:
            self.assertEqual(
                digest((game / spec["path"]).read_bytes()),
                spec[key],
            )

    def test_manifest_recreates_v1_exactly(self):
        for spec in self.manifest["files"]:
            source = GAME / spec["path"]
            data = bytearray(source.with_name(source.name + ".bak").read_bytes())
            for patch in spec["patches"]:
                offset = int(patch["offset"], 0)
                before = bytes.fromhex(patch["before"])
                after = bytes.fromhex(patch["after"])
                self.assertEqual(data[offset:offset + len(before)], before)
                data[offset:offset + len(after)] = after
            self.assertEqual(digest(data), spec["patched_sha256"])
            self.assertEqual(data, source.read_bytes())

    def test_install_reinstall_and_uninstall(self):
        with tempfile.TemporaryDirectory() as temp:
            game = self.make_game(Path(temp))
            command = [
                sys.executable,
                ROOT / "tools/sticky_blood.py",
                "install",
                "--game",
                str(game),
                "--skip-running-check",
            ]
            subprocess.run(command, check=True)
            self.assert_hashes(game, "patched_sha256")
            self.assertTrue((game / "garrysmod/addons/sticky_blood/addon.json").is_file())
            subprocess.run(command, check=True)
            self.assert_hashes(game, "patched_sha256")
            subprocess.run(
                [
                    sys.executable,
                    ROOT / "tools/sticky_blood.py",
                    "uninstall",
                    "--game",
                    str(game),
                    "--skip-running-check",
                ],
                check=True,
            )
            self.assert_hashes(game, "pristine_sha256")
            self.assertFalse((game / "garrysmod/addons/sticky_blood").exists())

    def test_unknown_version_is_rejected_without_backup(self):
        with tempfile.TemporaryDirectory() as temp:
            game = self.make_game(Path(temp))
            spec = self.manifest["files"][0]
            target = game / spec["path"]
            data = bytearray(target.read_bytes())
            data[0x100] ^= 0xFF
            target.write_bytes(data)
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
                text=True,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Unsupported or modified file", result.stderr)
            self.assertFalse(target.with_name(spec["backup"]).exists())

    def test_release_zip_is_allowlisted_and_installs(self):
        archive_path = ROOT / "dist/sticky-blood-v1.0.0.zip"
        with tempfile.TemporaryDirectory() as temp:
            temp = Path(temp)
            with zipfile.ZipFile(archive_path) as archive:
                names = [name.lower() for name in archive.namelist()]
                self.assertFalse(any(name.endswith((".dll", ".bak")) for name in names))
                self.assertFalse(any(".cursor/" in name or "agents.md" in name for name in names))
                archive.extractall(temp / "release")
            release = temp / "release/sticky-blood-v1.0.0"
            game = self.make_game(temp / "fixture")
            subprocess.run(
                [
                    sys.executable,
                    release / "tools/sticky_blood.py",
                    "install",
                    "--game",
                    str(game),
                    "--skip-running-check",
                ],
                check=True,
            )
            self.assert_hashes(game, "patched_sha256")


if __name__ == "__main__":
    unittest.main()
