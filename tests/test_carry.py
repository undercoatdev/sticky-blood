#!/usr/bin/env python3
import shutil
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = Path(__file__).resolve().parent / "lua" / "test_carry.lua"
HELPER = ROOT / "lua" / "autorun" / "sh_sticky_blood_carry.lua"


class CarryHelperTests(unittest.TestCase):
    def test_lua_helpers(self):
        names = ("lua5.1", "luajit")
        interpreters = []
        for name in names:
            path = shutil.which(name)
            if path and path not in interpreters:
                interpreters.append(path)
        if not interpreters:
            fallback = shutil.which("lua")
            if fallback:
                interpreters.append(fallback)
        if not interpreters:
            self.skipTest("lua interpreter not available")

        for lua in interpreters:
            result = subprocess.run(
                [lua, str(SCRIPT), str(HELPER)],
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(
                result.returncode,
                0,
                lua + "\n" + result.stdout + result.stderr,
            )
            self.assertIn("ok", result.stdout)
