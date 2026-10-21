#!/usr/bin/env python3
import importlib.util
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def load_sig_tests():
    spec = importlib.util.spec_from_file_location("test_sig_engine", ROOT / "tests" / "test_sig_engine.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class ReleaseTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        subprocess.run([sys.executable, ROOT / "tools/build_release.py"], check=True)
        cls.archive_path = ROOT / "dist/sticky-blood-v1.1.0.zip"
        cls.sig = load_sig_tests()

    def test_release_zip_is_allowlisted_and_installs(self):
        self.assertTrue(self.archive_path.is_file())
        with tempfile.TemporaryDirectory() as temp:
            temp = Path(temp)
            with zipfile.ZipFile(self.archive_path) as archive:
                names = [name for name in archive.namelist()]
                lowered = [name.lower() for name in names]
                self.assertFalse(any(name.endswith((".dll", ".bak")) for name in lowered))
                self.assertFalse(any(".cursor/" in name or "agents.md" in name for name in lowered))
                self.assertTrue(any(name.endswith("patches/v2.json") for name in names))
                self.assertTrue(any(name.endswith("patches/v1.0.0.json") for name in names))
                archive.extractall(temp / "release")
            release = temp / "release/sticky-blood-v1.1.0"
            files = self.sig.synthesize(self.sig.SB.load_manifest(), seed=4)
            game = self.sig.make_game(temp / "fixture", files)
            subprocess.run(
                [
                    sys.executable,
                    release / "tools/sticky_blood.py",
                    "install",
                    "--dry-run",
                    "--game",
                    str(game),
                    "--skip-running-check",
                ],
                check=True,
            )
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
            subprocess.run(
                [
                    sys.executable,
                    release / "tools/sticky_blood.py",
                    "uninstall",
                    "--game",
                    str(game),
                    "--skip-running-check",
                ],
                check=True,
            )
            for relative, blob in files.items():
                self.assertEqual((game / relative).read_bytes(), blob)


if __name__ == "__main__":
    unittest.main()
