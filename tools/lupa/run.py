"""The Lua 5.1 tests: the addon run in real Lua 5.1 (lupa) against a strict mock of WoW: Forever's API,
through every tab, entry, filter and search. Exits non-zero on any failure.

    python3 -m pip install lupa
    python3 tools/lupa/run.py                       the repo's ForeverLoot folder
    FL_ADDON_DIR=<folder>/ python3 tools/lupa/run.py   another copy, like the installed one
"""
import os
import sys

import lupa.lua51 as lua51

HERE = os.path.dirname(os.path.abspath(__file__))
rt = lua51.LuaRuntime(unpack_returned_tuples=True)
failed = rt.eval('function(dir) return assert(loadfile(dir .. "/run.lua"))(dir) end')(HERE)
sys.exit(1 if failed else 0)
