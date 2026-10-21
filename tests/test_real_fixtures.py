#!/usr/bin/env python3
"""Read-only checks against old/ and new/ Garry's Mod DLL fixtures.

Skipped unless STICKYBLOOD_FIXTURES points at a directory. The test never
writes under that directory.
"""
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
FIXTURES = os.environ.get("STICKYBLOOD_FIXTURES")

OLD_OFFSETS = {
    "sr_skip_count_evict": 0x4714,
    "sr_skip_lod_evict": 0x4772,
    "sr_limit_a": 0x489D,
    "sr_jump_past_flush": 0x48A7,
    "sr_limit_b": 0x4984,
    "sr_limit_c": 0x4ACA,
    "sr_find_hook": 0x94BB,
    "sr_cave1": 0x8D47C,
    "sr_cave2": 0x8D49B,
    "sr_flush_exit": 0x4E90,
    "sr_find_continue": 0x9478,
    "en_never_recycle": 0x12DA4E,
    "en_return_null": 0x12DA68,
}
NEW_OFFSETS = dict(OLD_OFFSETS)
NEW_OFFSETS["en_never_recycle"] = 0x12DA5E
NEW_OFFSETS["en_return_null"] = 0x12DA78
OLD_PATCHED = {
    "studiorender.dll": "c98ea283ca15f2004d35d92e1b3754ce33aa3c8a455ec9ed337a0451463ac80d",
    "engine.dll": "c21f5e735f96e6057386c420fbddd8e2fcb7347d9988ab039b4dcf2a71e71961",
}
NEW_PATCHED = {
    "studiorender.dll": "8ab35804f6baca02dd40db3455db7eab5bd2e324a347d7527e265e8589c18ec9",
    "engine.dll": "c3bebbdd1832f0c9125c2346abdb20ecabd33367574f21a59698b3aaae270a5e",
}
OLD_PRISTINE = {
    "studiorender.dll": "01a040d57c4daac1b8a313a773579c89ee04463cc6f1409b3c2419dcefe25e8b",
    "engine.dll": "7c21e827722fa7ac9ba4539dc652d3b79f58e240da49d28e75a1a9a1a88c4173",
}


def load_installer():
    path = ROOT / "tools" / "sticky_blood.py"
    spec = importlib.util.spec_from_file_location("sticky_blood_fixtures", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def fixture_file(kind, name):
    base = Path(FIXTURES) / kind
    for candidate in (base / name, base / "bin" / "win64" / name):
        if candidate.is_file():
            return candidate
    raise FileNotFoundError(f"Missing {kind} fixture {name} under {base}")


@unittest.skipUnless(FIXTURES, "STICKYBLOOD_FIXTURES is not set")
class RealFixtureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sb = load_installer()
        cls.manifest = cls.sb.load_manifest()
        cls.v1 = json.loads((ROOT / "patches/v1.0.0.json").read_text(encoding="utf-8"))

    def read_kind(self, kind):
        blobs = {}
        for spec in self.manifest["files"]:
            name = Path(spec["path"]).name
            blobs[name] = fixture_file(kind, name).read_bytes()
        return blobs

    def test_old_and_new_offsets_and_hashes(self):
        cases = (
            ("old", OLD_OFFSETS, OLD_PATCHED, OLD_PRISTINE),
            ("new", NEW_OFFSETS, NEW_PATCHED, None),
        )
        for kind, offsets, patched_hashes, pristine in cases:
            blobs = self.read_kind(kind)
            for spec in self.manifest["files"]:
                name = Path(spec["path"]).name
                data = blobs[name]
                if pristine:
                    self.assertEqual(self.sb.sha256_bytes(data), pristine[name])
                state, edits, labels = self.sb.classify_bytes(data, spec)
                self.assertEqual(state, "pristine")
                for label, offset in labels.items():
                    self.assertEqual(offset, offsets[label], label)
                patched = self.sb.apply_edits(data, edits)
                self.assertEqual(self.sb.sha256_bytes(patched), patched_hashes[name])
                self.assertEqual(self.sb.classify_bytes(patched, spec)[0], "patched")

    def test_v1_backup_migration_round_trip(self):
        blobs = self.read_kind("old")
        with tempfile.TemporaryDirectory() as temp:
            game = Path(temp) / "GarrysMod"
            (game / "garrysmod").mkdir(parents=True)
            (game / "garrysmod/gameinfo.txt").write_text("x\n", encoding="utf-8")
            for spec in self.manifest["files"]:
                target = game / spec["path"]
                target.parent.mkdir(parents=True, exist_ok=True)
                name = target.name
                target.write_bytes(blobs[name])
                legacy = target.with_name(name + ".stickyblood-v1.bak")
                legacy.write_bytes(blobs[name])
            self.sb.install_game(game, self.manifest, self.sb.load_v1_index(), dry_run=False)
            for spec in self.v1["files"]:
                target = game / spec["path"]
                self.assertEqual(self.sb.sha256_file(target), spec["patched_sha256"])
                backup = target.with_name(spec["path"].split("/")[-1] + ".stickyblood.bak")
                self.assertEqual(self.sb.sha256_file(backup), spec["pristine_sha256"])
                sidecar = target.with_name(target.name + ".stickyblood.json")
                sidecar.unlink()
                backup.unlink()
            self.sb.uninstall_game(game, self.manifest, self.sb.load_v1_index(), dry_run=False)
            for spec in self.v1["files"]:
                target = game / spec["path"]
                self.assertEqual(self.sb.sha256_file(target), spec["pristine_sha256"])
                self.assertFalse(target.with_name(target.name + ".stickyblood-v1.bak").exists())


if __name__ == "__main__":
    unittest.main()
