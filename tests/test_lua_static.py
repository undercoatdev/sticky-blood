#!/usr/bin/env python3
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LUA = ROOT / "lua"


def source(rel):
    return (LUA / rel).read_text()


class LuaStaticTests(unittest.TestCase):
    def test_debug_convar_not_archived(self):
        line = next(l for l in source("autorun/sh_sticky_blood_carry.lua").splitlines()
                    if 'CreateConVar("sticky_blood_debug"' in l)
        self.assertNotIn("ARCHIVE", line)
        self.assertNotIn("flags", line)

    def test_revive_code_removed(self):
        for path in LUA.rglob("*.lua"):
            text = path.read_text()
            for name in ("StickyBlood_Revived", "ReviveDeadNPC", "RequestSnatch"):
                self.assertNotIn(name, text, f"{name} in {path}")

    def test_serverragdolls_restored(self):
        sv = source("autorun/server/sv_sticky_blood.lua")
        self.assertIn('hook.Add("ShutDown", "StickyBlood_ServerRagdolls"', sv)
        self.assertIn('GetConVar("sticky_blood_force_serverragdolls")', sv)
        self.assertRegex(source("autorun/sh_sticky_blood_carry.lua"),
                         r'CreateConVar\("sticky_blood_force_serverragdolls", "1", FCVAR_ARCHIVE')


if __name__ == "__main__":
    unittest.main()
