"""Build ForeverLoot/Art.lua: a picture for each dungeon and raid, and a portrait for each boss,
from WoW: Forever's own files.

    python3 tools/build_art.py

Dungeons and raids use the Encounter Journal's button art (interface/encounterjournal/
ui-ej-dungeonbutton-*), and the dungeons Forever added use its own loading screens (interface/
glues/loadingscreens/...). Bosses use the Encounter Journal's portraits (ui-ej-boss-*); a boss
without one gets its creature model (tools/raw/boss_models.json, from boss_models.py), which the game
draws as a round portrait, or else the journal's own "unknown boss" silhouette. Pictures are file IDs
from the live client's file list on wago.tools (cached in tools/cache), so the game loads each
picture by its ID.
"""
import json
import os
import re
import sys
import urllib.parse
import urllib.request

import lupa.lua51 as lua51

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "preview"))
import art  # noqa: E402  (the preview's file fetcher and BLP reader)

BUILD = "1.60.1.70790"
TOOLS = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(TOOLS)
CACHE = os.path.join(TOOLS, "cache")
OUT = os.path.join(ROOT, "ForeverLoot", "Art.lua")

# The Encounter Journal's button art is the top left 175 x 95 of its 256 x 128 file
EJ_BUTTON = (0, 0.68359375, 0, 0.7421875, 175 / 95)
# A loading screen fills its file; its shape comes from the file itself
LOADSCREEN = (0, 1, 0, 1)

# Each instance's picture: an Encounter Journal button by its name, or a loading screen ("ls:")
INSTANCES = {
    "HOT": "ls:loadscreen_camelot_oldironforge", "ROL": "ls:loadscreen_camelot_ruinsoflordaeron",
    "EXC": "ls:loadscreen_camelot_excavation", "DAL": "ls:loadscreen_camelot_dalaran",
    "DROWN": "ls:loadscreen_thedrownedcity_7963741", "KROL": "ls:loadscreen_kroldokstronghold_7963780",
    "ALCAZ": "ls:loadscreen_alcazprison_7963734", "BMH": "ls:loadscreen_blackmawhold_7963784",
    "SHAPER": "ls:loadscreen_theshapersterrace_7963783",
    "RFC": "ragefirechasm", "DM": "deadmines", "WC": "wailingcaverns", "SFK": "shadowfangkeep",
    "BFD": "blackfathomdeeps", "STOCKS": "thestockade", "GNOMER": "gnomeregan", "SM": "scarletmonastery",
    "RFK": "razorfenkraul", "RFD": "razorfendowns", "ULDA": "uldaman", "MARA": "maraudon", "ZF": "zulfarrak",
    "DIRE": "diremaul", "STRAT": "stratholme", "ST": "sunkentemple", "BRD": "blackrockdepths",
    "BRS": "blackrockspire", "SCHOLO": "scholomance",
    # the two raids in Mount Hyjal: Forever's Kalimdor screen and the Mount Hyjal one
    # (the Mount Hyjal one is the old framed kind: only the band between its frame and logo)
    "BARROW": "ls:loadscreen_camelot_kalimdor", "HYJAL": ("ls:loadscreenhyjal", (0, 1, 0.3, 0.78)),
    "ONY": "onyxia", "MC": "moltencore", "BWL": "blackwinglair", "ZG": "zulgurub",
    "AQ20": "ruinsofahnqiraj", "AQ40": "templeofahnqiraj", "NAXX": "naxxramas",
}
# The rest of the list's entries: the Quests tab's "Quests you can do" and the wishlist's groups
# that aren't an instance use Forever's Eastern Kingdoms screen
OTHER = "ls:loadscreen_camelot_easternkingdom"

# Bosses whose journal portrait has another name (most were renamed when Cataclysm remade them)
BOSS_FILES = {
    "Cannon Master Willey": "willey hopebreaker", "Archivist Galford": "instructor galford",
    "Baron Rivendare": "lord aurius rivendare", "Malor the Zealous": "commander malor",
    "Emperor Dagran Thaurissan": "emperor thaurissan", "Jin'do the Hexxer": "jindo the godbreaker",
    "Hakkar": "avatar of hakkar", "The Four Horsemen": "four horseman",
}
UNKNOWN_BOSS = "default"


def search(query):
    os.makedirs(CACHE, exist_ok=True)
    path = os.path.join(CACHE, "art-" + re.sub(r"[^a-z0-9]+", "-", query.lower()).strip("-") + ".json")
    if not os.path.exists(path):
        url = f"https://wago.tools/api/files?search={urllib.parse.quote(query)}&version={BUILD}"
        req = urllib.request.Request(url, headers={"User-Agent": "forever-loot-build"})
        with urllib.request.urlopen(req, timeout=120) as r:
            data = json.loads(r.read() or b"{}")
        with open(path, "w") as f:
            json.dump(data, f)
    with open(path) as f:
        return {v: int(k) for k, v in json.load(f).items()}


def norm(s):
    return re.sub(r"[^a-z0-9]", "", s.lower())


def instances(with_npcs=False):
    rt = lua51.LuaRuntime(unpack_returned_tuples=True)
    ns = rt.eval("{}")
    rt.eval('function(f, ns) return assert(loadfile(f))("ForeverLoot", ns) end')(os.path.join(ROOT, "ForeverLoot", "Data.lua"), ns)
    out = []
    for kind in ("Dungeons", "Raids"):
        t = ns[kind]
        for i in range(1, len(t) + 1):
            d = t[i]
            bosses = []
            for j in range(1, len(d["bosses"] or {}) + 1):
                b = d["bosses"][j]
                if with_npcs:
                    npcs = [b["npc"][k] for k in range(1, len(b["npc"]) + 1)] if b["npc"] else []
                    bosses.append((b["name"], bool(b["trash"]), npcs, bool(d["isNew"])))
                else:
                    bosses.append((b["name"], bool(b["trash"])))
            out.append((d["key"], d["name"], bosses))
    return out


def lua_string(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def main():
    buttons = {path.rsplit("/", 1)[1][len("ui-ej-dungeonbutton-"):-4]: fid
               for path, fid in search("ui-ej-dungeonbutton-").items()}
    screens = {path.rsplit("/", 1)[1][:-4]: fid for path, fid in search("glues/loadingscreens").items()}
    portraits = {path.rsplit("/", 1)[1][len("ui-ej-boss-"):-4]: fid for path, fid in search("ui-ej-boss-").items()}
    by_norm = {norm(name): fid for name, fid in portraits.items()}

    art.BUILD = BUILD

    def picture(spec):
        spec, region = spec if isinstance(spec, tuple) else (spec, None)
        if spec.startswith("ls:"):
            fid = screens[spec[3:]]
            img = art.by_fdid(fid)
            # the old square ones are drawn on a 4:3 screen
            aspect = 4 / 3 if img.width == img.height else img.width / img.height
            l, r, t, b = region or LOADSCREEN
            return (fid, l, r, t, b, aspect * (r - l) / (b - t))
        return (buttons[spec],) + EJ_BUTTON

    lines = [
        "-- Generated by tools/build_art.py from WoW: Forever " + BUILD + "'s own files; don't edit it by hand.",
        "local ADDON, ns = ...",
        "",
        "-- A picture for each dungeon and raid: { file ID, left, right, top, bottom, width / height }, the",
        "-- part of the file that's the picture. The Encounter Journal's button art, or for the dungeons",
        "-- Forever added, its loading screen.",
        "ns.InstanceArt = {",
    ]
    insts = instances()
    missing = [key for key, _, _ in insts if key not in INSTANCES]
    if missing:
        sys.exit("no picture for " + ", ".join(missing) + ": add them to INSTANCES")
    for key, name, _ in insts:
        fid, l, r, t, b, aspect = picture(INSTANCES[key])
        lines.append(f"\t{key} = {{ {fid}, {l:g}, {r:g}, {t:g}, {b:g}, {aspect:.4f} }}, -- {name}")
    lines.append("}")
    fid, l, r, t, b, aspect = picture(OTHER)
    lines.append(f"ns.OtherArt = {{ {fid}, {l:g}, {r:g}, {t:g}, {b:g}, {aspect:.4f} }}")
    lines += [
        "",
        "-- Each boss's portrait in the Encounter Journal (128 x 64), by its name in Data.lua; a boss",
        "-- that isn't here gets ns.UnknownBossArt, the journal's own silhouette",
        "ns.BossArt = {",
    ]
    found, without = 0, []
    seen = set()
    for key, _, bosses in insts:
        for name, trash in bosses:
            if trash or name == "Boss not confirmed" or name in seen:
                continue
            seen.add(name)
            fid = portraits.get(BOSS_FILES[name]) if name in BOSS_FILES else by_norm.get(norm(name))
            if fid:
                found += 1
                lines.append(f"\t[{lua_string(name)}] = {fid},")
            else:
                without.append(f"{name} ({key})")
    lines.append("}")
    lines.append(f"ns.UnknownBossArt = {portraits[UNKNOWN_BOSS]}")
    # the rest: the game draws a portrait from the boss's model
    models_file = os.path.join(TOOLS, "raw", "boss_models.json")
    models = json.load(open(models_file)) if os.path.exists(models_file) else {}
    lines += [
        "",
        "-- A boss with no journal portrait: its creature model, which the game draws as a portrait",
        "ns.BossModel = {",
    ]
    drawn = 0
    still = []
    for item in without:
        name = item.rsplit(" (", 1)[0]
        if name in models:
            drawn += 1
            lines.append(f"\t[{lua_string(name)}] = {models[name]},")
        else:
            still.append(item)
    lines.append("}")
    with open(OUT, "w") as f:
        f.write("\n".join(lines) + "\n")
    print(f"wrote {OUT}: {len(insts)} instances, {found} boss portraits, {drawn} drawn from models; "
          f"{len(still)} bosses with neither:")
    print("  " + ", ".join(still))


if __name__ == "__main__":
    main()
