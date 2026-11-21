"""Build tools/raw/boss_models.json: the creature model (display ID) of each boss that has no
Encounter Journal portrait, so the game can draw one from the model itself. Also builds
tools/raw/boss_levels.json: each boss's level, for the badge on its portrait.

    python3 tools/boss_models.py <ClassicDB .sql.gz>

The models come from cMaNGOS's Classic database (creature_template's ModelId1, from
https://github.com/cmangos/classic-db, Full_DB), by the boss's NPC id in Data.lua or, for a boss
without one, by its name. tools/raw/wowhead_npc_models.json holds models read from Wowhead's
Forever NPC pages; they win where both have one (they agreed on all 41 checked in November 2026).
Forever's own bosses aren't in either yet, so they keep the journal's silhouette.

The levels are creature_template's MinLevel and MaxLevel over the boss's NPCs (Forever kept
Classic's dungeon level ranges, so it kept their bosses' levels too): one number, "low-high" for an
encounter whose creatures differ, or -1 for a boss the game shows as "??" (Rank 3, the raid
bosses). Forever's own bosses aren't in the Classic database; the addon learns theirs in the game.

build_art.py reads both into Art.lua's ns.BossModel and ns.BossLevel.
"""
import gzip
import json
import os
import re
import sys

TOOLS = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(TOOLS, "raw", "boss_models.json")
LEVELS_OUT = os.path.join(TOOLS, "raw", "boss_levels.json")
BOSS_RANK = 3  # creature_template Rank: the game shows its level as "??"
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
    """{entry: (name, first model, min level, max level, rank)} from the dump's creature_template"""
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
                    out[int(r["Entry"])] = (r["Name"], models[0] if models else None,
                                            int(r["MinLevel"]), int(r["MaxLevel"]), int(r["Rank"]))
    return out


def level_of(rows):
    """The level a boss's portrait shows, from its creatures' (min level, max level, rank)"""
    if any(rank == BOSS_RANK for _, _, rank in rows):
        return -1
    low, high = min(r[0] for r in rows), max(r[1] for r in rows)
    return low if low == high else f"{low}-{high}"


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    creatures = creature_models(sys.argv[1])
    by_name = {}
    for with_model in (True, False):
        for entry, row in sorted(creatures.items()):
            if row[1] or not with_model:
                by_name.setdefault(row[0], row)
    wowhead = {int(k): v for k, v in json.load(open(WOWHEAD)).items()}
    models, missing, levels, unleveled = {}, [], {}, []
    for key, _, bosses in instances(with_npcs=True):
        for name, trash, npcs, new in bosses:
            if trash or name == "Boss not confirmed":
                continue
            rows = [creatures[n] for n in npcs if n in creatures]
            # a Classic boss without an NPC id, by its name (a Forever dungeon's boss may only share
            # a Classic creature's name)
            if not rows and not npcs and not new and name in by_name:
                rows = [by_name[name]]
            model = next((wowhead.get(n) or (creatures.get(n) or (None, None))[1] for n in npcs
                          if wowhead.get(n) or (creatures.get(n) or (None, None))[1]), None)
            if model is None and not npcs and rows:
                model = rows[0][1]
            if model:
                models[name] = model
            else:
                missing.append(f"{name} ({key})")
            if rows:
                levels[name] = level_of([r[2:] for r in rows])
            else:
                unleveled.append(f"{name} ({key})")
    with open(OUT, "w") as f:
        json.dump(dict(sorted(models.items())), f, indent=0)
    with open(LEVELS_OUT, "w") as f:
        json.dump(dict(sorted(levels.items())), f, indent=0)
    print(f"wrote {OUT}: {len(models)} bosses with a model; {len(missing)} without:")
    print("  " + ", ".join(missing))
    print(f"wrote {LEVELS_OUT}: {len(levels)} bosses with a level; {len(unleveled)} without:")
    print("  " + ", ".join(unleveled))


if __name__ == "__main__":
    main()
