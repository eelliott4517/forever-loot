"""Build tools/raw/boss_models.json: the creature model (display ID) of each boss that has no
Encounter Journal portrait, so the game can draw one from the model itself.

    python3 tools/boss_models.py <ClassicDB .sql.gz>

The models come from cMaNGOS's Classic database (creature_template's ModelId1, from
https://github.com/cmangos/classic-db, Full_DB), by the boss's NPC id in Data.lua or, for a boss
without one, by its name. tools/raw/wowhead_npc_models.json holds models read from Wowhead's
Forever NPC pages; they win where both have one (they agreed on all 41 checked in November 2026).
Forever's own bosses aren't in either yet, so they keep the journal's silhouette.

build_art.py reads the result into Art.lua's ns.BossModel.
"""
import gzip
import json
import os
import re
import sys

TOOLS = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(TOOLS, "raw", "boss_models.json")
WOWHEAD = os.path.join(TOOLS, "raw", "wowhead_npc_models.json")
sys.path.insert(0, TOOLS)
from build_art import instances  # noqa: E402


def tuples(s):
    """The value lists of an INSERT ... VALUES (..),(..); statement."""
    i, n = 0, len(s)
    while i < n:
        if s[i] != "(":
            i += 1
            continue
        vals, cur, i, quoted = [], "", i + 1, False
        while i < n:
            c = s[i]
            if quoted:
                if c == "\\":
                    cur += s[i + 1]
                    i += 2
                    continue
                if c == "'":
                    quoted = False
                else:
                    cur += c
            elif c == "'":
                quoted = True
            elif c == ",":
                vals.append(cur)
                cur = ""
            elif c == ")":
                vals.append(cur)
                i += 1
                break
            else:
                cur += c
            i += 1
        yield vals


def creature_models(dump):
    """{entry: (name, first model)} from the dump's creature_template"""
    cols, out = [], {}
    with gzip.open(dump, "rt", encoding="utf-8", errors="replace") as f:
        in_create = False
        for line in f:
            if line.startswith("CREATE TABLE `creature_template`"):
                in_create = True
                continue
            if in_create:
                m = re.match(r"\s+`(\w+)`", line)
                if m:
                    cols.append(m.group(1))
                elif line.startswith(")"):
                    in_create = False
                continue
            if line.startswith("INSERT INTO `creature_template`"):
                for v in tuples(line[line.index("VALUES") + 6:]):
                    r = dict(zip(cols, v))
                    models = [int(r[c]) for c in ("ModelId1", "ModelId2", "ModelId3", "ModelId4") if int(r[c] or 0)]
                    if models:
                        out[int(r["Entry"])] = (r["Name"], models[0])
    return out


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    creatures = creature_models(sys.argv[1])
    by_name = {}
    for entry, (name, model) in sorted(creatures.items()):
        by_name.setdefault(name, model)
    wowhead = {int(k): v for k, v in json.load(open(WOWHEAD)).items()}
    models, missing = {}, []
    for key, _, bosses in instances(with_npcs=True):
        for name, trash, npcs, new in bosses:
            if trash or name == "Boss not confirmed":
                continue
            model = next((wowhead.get(n) or (creatures.get(n) or (None, None))[1] for n in npcs
                          if wowhead.get(n) or n in creatures), None)
            # a Classic boss without an NPC id, by its name (a Forever dungeon's boss may only share
            # a Classic creature's name)
            if model is None and not npcs and not new:
                model = by_name.get(name)
            if model:
                models[name] = model
            else:
                missing.append(f"{name} ({key})")
    with open(OUT, "w") as f:
        json.dump(dict(sorted(models.items())), f, indent=0)
    print(f"wrote {OUT}: {len(models)} bosses with a model; {len(missing)} without:")
    print("  " + ", ".join(missing))


if __name__ == "__main__":
    main()
