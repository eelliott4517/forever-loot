"""Build ForeverLoot/Data.lua (dungeons and raids) from the scraped loot data.

Inputs (see README; tools/refresh.py fetches them):
  raw/wowhead.json                      Wowhead scrape (scrape_template.js): Forever + Classic zone pages
                                        (drops by NPC, quests), raid boss and loot chest pages (drop
                                        chances), quest lookups, new Forever items
  raw/zone_<id>.json, raw/scrape.json,  older scrapes, used for any page wowhead.json doesn't have
  raw/raid_zones.json, raw/raid_npcs.json
  raw/wowtbc/<slug>.json                wowtbc.gg Forever dungeon loot tables and quests (new drops,
                                        drop chances)
  dungeons.py, raids.py                 curated instance + boss lists
  forever_additions.py                  Forever drops from Wowhead guides/comments/news and Mobalytics,
                                        plus datamined new items not tied to a boss yet

Quests come from each instance's Wowhead zone page plus the dungeon quests wowtbc.gg
lists (looked up on Wowhead by name). Item sets come from the item tooltips: every set
with a piece in the loot or quest rewards is listed with all its pieces.

Each item is then looked up in Wowhead's Forever database. Items Forever still has
use their Forever name, type and tooltip text. Items it doesn't have (Forever
replaced a lot of Classic loot) are kept as Classic loot with their Classic tooltip
text. Every item's icon and tooltip text is bundled, because the beta server
doesn't send data for many items.

Item flags written to Data.lua: 0 in Forever, 1 new in Forever, 2 Classic only, 3 new, boss unconfirmed.
"""
import json
import os
import re
import sys
from collections import defaultdict

from dungeons import DUNGEONS
from raids import RAIDS
from forever_additions import ADDITIONS, NOTES, UNCONFIRMED
import item_info

HERE = os.path.dirname(os.path.abspath(__file__))
RAW = os.environ.get("FL_RAW", os.path.join(HERE, "raw"))
OUT = os.path.join(HERE, "..", "ForeverLoot", "Data.lua")
DATA_DATE = os.environ.get("FL_DATE", "2026-09-25")

SOD_RANGE = range(200000, 260000)  # Season of Discovery item ids; not part of Forever's loot
SOD_NPCS = range(200000, 250000)   # Season of Discovery NPC ids (Forever's own NPCs start around 250000)
FOREVER_IDS = 260000               # items at or above this id were added in Forever
MIN_BOSS_QUALITY = 2
MIN_TRASH_QUALITY = 3              # Wowhead trash lists; wowtbc.gg trash lists keep their greens
QUEST_LEVELS_BELOW, QUEST_LEVELS_ABOVE = 15, 5   # a zone's quests outside this band aren't its own
MIN_PAGE_PCT = 3.0                 # a boss-page drop not on the zone's table needs this chance to count
SHARED_PCT = 15.0                  # ...and a rare that several bosses share (random world blues) needs this
SOD_MARK = re.compile(r"SoD Phase|Season of Discovery", re.I)
SOD_NOTE = "|cff9d9d9dWowhead shows Season of Discovery's version of this item.|r"

WH, WHC, TBC, DATAMINED = "Wowhead", "Wowhead Classic", "wowtbc.gg", "Wowhead (datamined)"
SOURCE_ORDER = [WH, DATAMINED, "Mobalytics", TBC, WHC]


def norm(s):
    s = s.lower()
    s = re.sub(r"^the\s+", "", s)
    return re.sub(r"[^a-z0-9]", "", s)


def slim_drop(x):
    return dict(id=x["id"], name=x.get("name", ""), q=x.get("q", x.get("quality", 1)), sm=list(x.get("sm") or []))


def load_json(name):
    path = os.path.join(RAW, name)
    if not os.path.exists(path):
        return {}
    with open(path) as f:
        return json.load(f)


def load_pages():
    """Zone pages, boss/chest pages and quest lookups by key (forever_zone_1581, classic_npc_11502, ...).
    raw/wowhead.json wins; the older scrape files fill in any page it doesn't have."""
    pages, boss_pages = {}, {}
    for fn in sorted(os.listdir(RAW)):
        m = re.match(r"zone_(\d+)\.json$", fn)
        if m:
            with open(os.path.join(RAW, fn)) as f:
                d = json.load(f)
            lv = re.search(r"Level: (\d+) - (\d+)", d.get("infobox", ""))
            pages[f"forever_zone_{m.group(1)}"] = dict(
                drops=[slim_drop(x) for x in d["drops"]], npcs=d["npcs"], objects=[], quests=[],
                level=[int(lv.group(1)), int(lv.group(2))] if lv else None)
    for name in ("scrape.json", "raid_zones.json"):
        for k, v in load_json(name).items():
            pages[k] = dict(drops=[slim_drop(x) for x in v["drops"]], npcs=v["npcs"],
                            objects=v.get("objects", []), level=v.get("level"), quests=[])
    boss_pages.update(load_json("raid_npcs.json"))
    searches = {}
    scrape = load_json("wowhead.json")
    for k, v in (scrape.get("pages") or {}).items():
        if "_zone_" in k:
            pages[k] = dict(drops=[slim_drop(x) for x in v["drops"]], npcs=v["npcs"], objects=v.get("objects", []),
                            level=v.get("level"), quests=v.get("quests", []))
        elif re.match(r"(classic|forever)_(npc|object)_\d+$", k):
            boss_pages[k] = v
        elif k.startswith("quest_search_"):
            searches[k[len("quest_search_"):]] = v["quests"]
    new_items = [x for k, v in (scrape.get("pages") or {}).items() if k.startswith("new_items_") for x in v["items"]]
    return pages, boss_pages, searches, new_items


def load_tbc(slug):
    with open(os.path.join(RAW, "wowtbc", f"{slug}.json")) as f:
        ctx = json.load(f)["result"]["pageContext"]
    loot = (ctx.get("loot") or [{}])[0]
    return loot, {g["id"]: g for g in ctx.get("gearData") or []}


SIDES = {"Alliance": 1, "Horde": 2}   # Wowhead quest sides: 1 Alliance, 2 Horde, 3 both


def pick_quest(candidates, side, zones):
    """The Wowhead quest a name lookup means: same faction, filed under the instance if it can be."""
    fits = [q for q in candidates if not side or q.get("side") in (side, 3)] or candidates
    fits.sort(key=lambda q: (q.get("cat") not in zones, q["id"]))
    return fits[0] if fits else None


def page_pct(x):
    """Drop chance from a boss or chest page entry, from its kill counts."""
    modes = x.get("modes") or {}
    total = modes.get("0") if isinstance(modes, dict) else None
    count, outof = (total or {}).get("count", x.get("count")), (total or {}).get("outof", x.get("outof"))
    if count and outof:
        return round(100.0 * count / outof, 1)
    return None


def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


class Loot:
    """Ordered item list with where each item was reported and its drop chance."""

    def __init__(self):
        self.items = []
        self.sources = defaultdict(set)
        self.pct = {}

    def add(self, iid, source, pct=None):
        if iid not in self.items:
            self.items.append(iid)
        self.sources[iid].add(source)
        if pct and iid not in self.pct:
            self.pct[iid] = pct


class Build:
    def __init__(self):
        self.pages, self.boss_pages, self.quest_searches, self.new_items = load_pages()
        self.report = []
        self.quest_ids = set()        # quest reward items
        self.new_ids = set()          # confirmed new in Forever
        self.unconfirmed_ids = set()
        self.era_listed = set()       # ids known to be original Classic loot (not Season of Discovery)
        self.sources = defaultdict(set)
        # Rares on more than one boss page: the random world blues that end bosses also roll
        pages_with = defaultdict(set)
        for key, page in self.boss_pages.items():
            for x in page["lists"].get("drops", []):
                if x.get("q") == 3 and (page_pct(x) or 0) < SHARED_PCT:
                    pages_with[x["id"]].add(key.split("_", 1)[1])
        self.shared = {iid for iid, keys in pages_with.items() if len(keys) > 1}

    def collect(self, d, raid=False):
        forever = [p for p in (self.pages.get(f"forever_zone_{z}") for z in d["zones"]) if p]
        classic = [p for p in (self.pages.get(f"classic_zone_{z}") for z in d["zones"]) if p]

        ids_by_name = defaultdict(set)
        objects_by_name = defaultdict(set)
        for p in forever + classic:
            for n in p["npcs"]:
                ids_by_name[norm(n["name"])].add(n["id"])
            for o in p.get("objects", []):
                objects_by_name[norm(o["name"])].add(o["id"])
            for x in p["drops"]:
                for m in x["sm"]:
                    if m.get("t") == 1 and m.get("n"):
                        ids_by_name[norm(m["n"])].add(m["ti"])

        bosses, by_name, boss_of_npc, boss_of_object = [], {}, {}, {}

        def add_boss(b):
            b = dict(name=b) if isinstance(b, str) else dict(b)
            npc = list(b.get("npc", []))
            for nm in [b["name"]] + b.get("aliases", []):
                for i in sorted(ids_by_name.get(norm(nm), [])):
                    if i not in npc and i not in SOD_NPCS:
                        npc.append(i)
                by_name[norm(nm)] = b
            b["npc"] = npc
            b["objects_ids"] = sorted({i for o in b.get("objects", []) for i in objects_by_name.get(norm(o), [])})
            b["loot"] = Loot()
            for i in npc:
                boss_of_npc[i] = b
            for o in b.get("objects", []):
                boss_of_object[norm(o)] = b
            bosses.append(b)
            return b

        for b in d["bosses"]:
            add_boss(b)
        trash = Loot()
        unassigned = defaultdict(list)

        # 1) Wowhead zone drops, Forever first
        for label, plist in ((WH, forever), (WHC, classic)):
            for p in plist:
                for x in p["drops"]:
                    iid = x["id"]
                    if iid in SOD_RANGE:
                        continue
                    npc_srcs = [m for m in x["sm"] if m.get("t") == 1]
                    era_srcs = [m for m in npc_srcs if m["ti"] not in SOD_NPCS]
                    if npc_srcs and not era_srcs:
                        continue          # only Season of Discovery's versions of the bosses drop it
                    owners = [boss_of_npc[m["ti"]] for m in era_srcs if m["ti"] in boss_of_npc]
                    owners += [boss_of_object[norm(m["n"])] for m in x["sm"]
                               if m.get("t") == 2 and m.get("n") and norm(m["n"]) in boss_of_object]
                    if owners:
                        if x["q"] >= MIN_BOSS_QUALITY:
                            for b in owners:
                                b["loot"].add(iid, label)
                            if raid and label == WHC:
                                self.era_listed.add(iid)
                    elif x["q"] >= MIN_TRASH_QUALITY:
                        trash.add(iid, label)
                        for m in era_srcs:
                            unassigned[(m["ti"], m.get("n"))].append(x["name"])

        # 2) Boss and chest pages: drop chances, and drops the zone table doesn't attribute
        for b in bosses:
            keys = [(f"classic_npc_{i}", WHC) for i in b["npc"]] + [(f"forever_npc_{i}", WH) for i in b["npc"]]
            keys += [(f"classic_object_{i}", WHC) for i in b["objects_ids"]]
            for key, label in keys:
                page = self.boss_pages.get(key)
                if not page:
                    continue
                for list_name, rows in page["lists"].items():
                    if list_name not in ("drops", "contains"):
                        continue
                    for x in rows:
                        iid, pct = x["id"], page_pct(x)
                        if iid in SOD_RANGE or (x.get("q") or 0) < 3:
                            continue
                        if iid in b["loot"].items:
                            if pct and iid not in b["loot"].pct:
                                b["loot"].pct[iid] = pct
                        elif pct and pct >= MIN_PAGE_PCT and not (iid in self.shared and pct < SHARED_PCT):
                            b["loot"].add(iid, label, pct)
                            if label == WHC:
                                self.era_listed.add(iid)

        # 3) wowtbc.gg boss tables (dungeons)
        for slug, wing in (d.get("tbc") or {}).items():
            loot, gear = load_tbc(slug)
            for tb in loot.get("bosses", []):
                news = set(tb.get("new", []))
                if tb["name"] == "Trash":
                    target = None
                else:
                    target = by_name.get(norm(tb["name"]))
                    if target is None:
                        target = add_boss(dict(name=tb["name"], wing=wing))
                        self.report.append(f"   {d['name']}: added boss from wowtbc.gg: {tb['name']}")
                for iid in tb["items"]:
                    if iid in SOD_RANGE:
                        continue
                    g = gear.get(iid, {})
                    chance = g.get("drop_chance")
                    pct = round(chance * 100, 1) if chance and g.get("source") == tb["name"] else None
                    if target is None:
                        trash.add(iid, TBC)
                    else:
                        target["loot"].add(iid, TBC, pct)
                    if iid in news:
                        self.new_ids.add(iid)
                    elif not d.get("new"):
                        self.era_listed.add(iid)

        for (npc_id, npc_name), names in sorted(unassigned.items(), key=lambda kv: -len(kv[1])):
            self.report.append(f"   {d['name']}: trash source {npc_name} ({npc_id}): {', '.join(names[:3])}")

        # 4) Forever drops documented on guides, comments, news
        for add in ADDITIONS.get(d["key"], []):
            target = by_name.get(norm(add["boss"])) or add_boss(dict(name=add["boss"]))
            for iid in add["items"]:
                target["loot"].add(iid, add["source"])
                if iid >= FOREVER_IDS:
                    self.new_ids.add(iid)

        # 4b) New Forever items Wowhead credits to one of the bosses (its zone tables can miss them)
        zones = set(d["zones"])
        for x in self.new_items:
            for m in x["sm"]:
                target = by_name.get(norm(m.get("n") or "")) if m.get("t") == 1 and m.get("z") in zones else None
                if target and x["id"] not in SOD_RANGE:
                    target["loot"].add(x["id"], WH)
                    self.new_ids.add(x["id"])

        # 5) Datamined new items without a confirmed boss (until a table above places one)
        extra = Loot()
        hints = {}
        placed = {i for b in bosses for i in b["loot"].items}
        for iid, hint in UNCONFIRMED.get(d["key"], []):
            if iid in placed:
                boss = next(b["name"] for b in bosses if iid in b["loot"].items)
                self.report.append(f"   {d['name']}: {iid} is confirmed now ({boss}); drop it from UNCONFIRMED")
                self.sources[iid].add(DATAMINED)
                continue
            extra.add(iid, DATAMINED)
            self.unconfirmed_ids.add(iid)
            if hint:
                hints[iid] = hint

        # an item on a boss's table doesn't also belong in trash
        on_bosses = {i for b in bosses for i in b["loot"].items}
        trash.items = [i for i in trash.items if i not in on_bosses]

        if "levels" not in d:
            found = [p["level"] for p in forever if p.get("level")]
            if not found:
                raise SystemExit(f"no Wowhead level range for {d['name']}")
            d["levels"] = tuple(found[0])
        for b in bosses:
            for i, s in b["loot"].sources.items():
                self.sources[i] |= s
        for acc in (trash, extra):
            for i, s in acc.sources.items():
                self.sources[i] |= s
        quests = self.quests(d)
        for q in quests:
            for iid in q["choices"] + q["rewards"]:
                self.quest_ids.add(iid)
                self.sources[iid].add(WH if q.get("id") else TBC)
        return (d, bosses, trash, extra, hints, quests)

    def quests(self, d):
        """The instance's quests: those Wowhead files under its zones, plus the ones wowtbc.gg
        lists for it (found on Wowhead by name, or kept as wowtbc.gg has them)."""
        zones = set(d["zones"])
        lo, hi = d["levels"][0] - QUEST_LEVELS_BELOW, d["levels"][1] + QUEST_LEVELS_ABOVE
        found, by_name = {}, defaultdict(list)
        for z in d["zones"]:
            for q in (self.pages.get(f"forever_zone_{z}") or {}).get("quests", []):
                if q["id"] in found or (q.get("env") or {}).get("status") == "removed":
                    continue
                # Placeholders ("<UNUSED>", "<TXT> ..."), and holiday quests Wowhead files under the zone
                if q["name"].startswith("<") or not lo <= (q.get("level") or lo) <= hi:
                    continue
                found[q["id"]] = q
                by_name[norm(q["name"])].append(q)
        extra = []
        for slug in (d.get("tbc") or {}):
            loot, _ = load_tbc(slug)
            for tq in loot.get("quests") or []:
                n, side = norm(tq["name"]), SIDES.get(tq.get("faction"))
                self.new_ids.update(i for i in tq.get("new", []) if i not in SOD_RANGE)
                q = pick_quest(by_name.get(n, []), side, zones)
                if not q:
                    q = pick_quest([x for x in self.quest_searches.get(n, []) if norm(x["name"]) == n], side, zones)
                    if q and q["id"] not in found:
                        found[q["id"]] = q
                        by_name[n].append(q)
                if not q:
                    extra.append(dict(id=None, name=tq["name"], side=side or 3, level=None, req=None,
                                      choices=[[i, 1] for i in tq["items"]], rewards=[]))
                    by_name[n].append(extra[-1])
                    self.report.append(f"   {d['name']}: quest only on wowtbc.gg: {tq['name']}")
        out = []
        for q in list(found.values()) + extra:
            choices = [(i, c) for i, c in q.get("choices", []) if i not in SOD_RANGE]
            rewards = [(i, c) for i, c in q.get("rewards", []) if i not in SOD_RANGE]
            env = q.get("env") or {}
            out.append(dict(id=q["id"], name=q["name"], level=q.get("level") if (q.get("level") or 0) > 0 else None,
                            req=q.get("req") if (q.get("req") or 0) > 0 else None, side=q.get("side") or 3,
                            choices=[i for i, _ in choices], rewards=[i for i, _ in rewards],
                            counts={i: c for i, c in choices + rewards if c and c > 1},
                            new=env.get("status") == "new",
                            # what Forever changed; its new rewards are tagged NEW on their rows anyway
                            changes=[l for l in env.get("lines", [])
                                     if not l.startswith("Rewards:") and not l.endswith("reworded")]))
        out.sort(key=lambda q: (q["level"] or 99, q["name"]))
        return out


def resolve(build, ids, meta, report, keep_sod=False):
    """Looks items up (Forever first, then Classic) and adds them to meta with their flag."""
    ids = [i for i in ids if i not in meta]
    if not ids:
        return
    print(f"checking {len(ids)} items against Wowhead's Forever database...", file=sys.stderr)
    forever_info = item_info.fetch(ids, "forever")
    classic_ids = [i for i in ids if forever_info.get(i, {}).get("missing")]
    print(f"{len(classic_ids)} of them aren't in Forever; fetching their Classic tooltips...", file=sys.stderr)
    classic_info = item_info.fetch(classic_ids, "classic")
    dropped_sod, dropped_missing = [], []
    for iid in ids:
        f = forever_info.get(iid)
        if f and not f.get("missing"):
            flag = 3 if iid in build.unconfirmed_ids else (1 if (iid in build.new_ids or iid >= FOREVER_IDS) else 0)
            meta[iid] = dict(f, flag=flag)
            continue
        c = classic_info.get(iid)
        if not c or c.get("missing"):
            dropped_missing.append(iid)
            continue
        lines = c.get("lines", [])
        if any(SOD_MARK.search(l) for l in lines):
            if iid not in build.era_listed and not keep_sod:
                dropped_sod.append(iid)       # a Season of Discovery addition, not original Classic loot
                continue
            lines = [l for l in lines if not SOD_MARK.search(l)] + [SOD_NOTE]
        meta[iid] = dict(c, lines=lines, flag=2)
    if dropped_sod:
        report.append(f"-- dropped {len(dropped_sod)} Season of Discovery items found in Wowhead Classic data")
    if dropped_missing:
        report.append(f"-- dropped {len(dropped_missing)} ids missing from both databases: {sorted(dropped_missing)[:20]}")


def class_list(e):
    return sorted(set(e.get("classes") or []))


def main():
    build = Build()
    dungeon_plan = [build.collect(d) for d in DUNGEONS]
    raid_plan = [build.collect(r, raid=True) for r in RAIDS]
    report, sources = build.report, build.sources

    meta = {}
    resolve(build, set(sources), meta, report)

    # Item sets with a piece in the loot or quest rewards, with every piece
    sets = {}
    for iid in sorted(meta):
        st = meta[iid].get("set")
        if st and st["id"] not in sets and st["pieces"]:
            sets[st["id"]] = st
    pieces = {p for st in sets.values() for p in st["pieces"]}
    resolve(build, pieces - set(meta), meta, report, keep_sod=True)
    for p in pieces:
        if p in meta and p not in sources:
            sources[p] = {WH}

    group = {1: 0, 3: 0, 0: 1, 2: 2}   # new first, then current Forever loot, then Classic-only

    def sort_items(ids):
        return sorted((i for i in ids if i in meta),
                      key=lambda i: (group[meta[i]["flag"]], -meta[i]["quality"], meta[i]["type"], meta[i]["name"]))

    def source_text(iid):
        s = sources.get(iid) or {DATAMINED}
        return ", ".join(sorted(s, key=lambda x: SOURCE_ORDER.index(x) if x in SOURCE_ORDER else 99))

    def id_list(ids):
        return "{ " + ", ".join(str(i) for i in ids) + " }"

    used = set()
    L = []

    def emit_quests(quests):
        quests = [q for q in quests if q["id"] or any(i in meta for i in q["choices"] + q["rewards"])]
        if not quests:
            return
        L.append("\t\tquests = {")
        for q in quests:
            choices = [i for i in q["choices"] if i in meta]
            rewards = [i for i in q["rewards"] if i in meta]
            used.update(choices + rewards)
            parts = [f"id = {q['id']}" if q["id"] else None, f"name = {lua_str(q['name'])}"]
            if q["level"]:
                parts.append(f"level = {q['level']}")
            if q["req"]:
                parts.append(f"req = {q['req']}")
            parts.append(f"side = {q['side']}")
            if q["new"]:
                parts.append("new = true")
            if choices:
                parts.append("choices = " + id_list(choices))
            if rewards:
                parts.append("rewards = " + id_list(rewards))
            counts = {i: c for i, c in q["counts"].items() if i in choices + rewards}
            if counts:
                parts.append("counts = { " + ", ".join(f"[{i}] = {c}" for i, c in sorted(counts.items())) + " }")
            if q["changes"]:
                parts.append("changes = { " + ", ".join(lua_str(c) for c in q["changes"]) + " }")
            L.append("\t\t\t{ " + ", ".join(p for p in parts if p) + " },")
        L.append("\t\t},")

    def emit(var, plan, raid):
        L.append(f"{var} = {{")
        for d, bosses, trash, extra, hints, quests in plan:
            L.append("\t{")
            L.append(f"\t\tkey = {lua_str(d['key'])}, name = {lua_str(d['name'])},")
            zone = d["zones"][0] if d["zones"] else 0
            L.append(f"\t\tzone = {zone}, minLevel = {d['levels'][0]}, maxLevel = {d['levels'][1]},")
            extras = []
            if d.get("new") or d.get("status") == "new":
                extras.append("isNew = true")
            if raid:
                extras.append(f"size = {d['size']}")
                extras.append(f"status = {lua_str(d['status'])}")
            if d.get("map"):
                extras.append(f"mapID = {d['map']}")
            if d.get("location"):
                extras.append(f"location = {lua_str(d['location'])}")
            if d.get("territory"):
                extras.append(f"territory = {lua_str(d['territory'])}")
            if extras:
                L.append("\t\t" + ", ".join(extras) + ",")
            if d.get("aliases"):
                L.append("\t\taliases = { " + ", ".join(lua_str(a) for a in d["aliases"]) + " },")
            if d.get("wings"):
                L.append("\t\twings = { " + ", ".join(f"[{lua_str(k)}] = {{ {v[0]}, {v[1]} }}"
                                                      for k, v in d["wings"].items()) + " },")
            if NOTES.get(d["key"]):
                L.append(f"\t\tnote = {lua_str(NOTES[d['key']])},")
            L.append("\t\tbosses = {")
            for b in bosses:
                loot = sort_items(b["loot"].items)
                used.update(loot)
                parts = [f"name = {lua_str(b['name'])}"]
                if b.get("npc"):
                    parts.append("npc = " + id_list(b["npc"]))
                if b.get("wing"):
                    parts.append(f"wing = {lua_str(b['wing'])}")
                if b.get("tag"):
                    parts.append(f"tag = {lua_str(b['tag'])}")
                parts.append("loot = " + id_list(loot))
                pct = {i: p for i, p in b["loot"].pct.items() if i in loot}
                if pct:
                    parts.append("pct = { " + ", ".join(f"[{i}] = {p:g}" for i, p in sorted(pct.items())) + " }")
                L.append("\t\t\t{ " + ", ".join(parts) + " },")
            tl = sort_items(trash.items)
            if tl:
                used.update(tl)
                where = "raid" if raid else "dungeon"
                L.append(f'\t\t\t{{ name = "Trash & zone drops", trash = true, tag = "Any mob in the {where}", loot = '
                         + id_list(tl) + " },")
            el = sort_items(extra.items)
            if el:
                used.update(el)
                hint_lua = ", ".join(f"[{i}] = {lua_str(hints[i])}" for i in el if i in hints)
                L.append('\t\t\t{ name = "New in Forever, boss not confirmed", unconfirmed = true, '
                         'tag = "Datamined on Wowhead", loot = ' + id_list(el)
                         + (f", hints = {{ {hint_lua} }}" if hint_lua else "") + " },")
            L.append("\t\t},")
            emit_quests(quests)
            L.append("\t},")
        L.append("}")
        L.append("")

    L.append("-- Generated by tools/build_data.py from Wowhead, wowtbc.gg and Mobalytics. Do not edit by hand.")
    L.append("local ADDON, ns = ...")
    L.append("")
    L.append(f"ns.DATA_DATE = {lua_str(DATA_DATE)}")
    L.append("")
    L.append("-- Instance quests: id (Wowhead), side (1 Alliance, 2 Horde, 3 both), choices (pick one),")
    L.append("-- rewards (always given), counts (stack sizes over 1), changes (what Forever changed)")
    emit("ns.Dungeons", dungeon_plan, raid=False)
    L.append("-- Raids in Data.lua order: Forever's (new, then Onyxia), then the Classic ones by release.")
    L.append("-- status: \"new\" in Forever, \"forever\" a Classic raid that's in Forever, \"classic\" not announced")
    emit("ns.Raids", raid_plan, raid=True)

    # Sets, easiest first: by the level their pieces need, then name
    kept = []
    for st in sets.values():
        ids = [p for p in st["pieces"] if p in meta]
        if not any(p in used for p in ids):
            continue
        level = max(meta[p]["req"] for p in ids)
        ilvl = max(meta[p]["ilvl"] for p in ids)
        # Some sets list no required level (Forever's tier 0.5); sort those by item level
        kept.append((level or min(60, ilvl), st["name"], st, ids, level, ilvl))
    kept.sort(key=lambda k: (k[0], k[1]))
    L.append("-- Item sets with a piece in the loot or quest rewards above: id (Wowhead item-set), level")
    L.append("-- (required, when the pieces list one), ilvl (highest), pieces, bonuses { pieces worn, effect }")
    L.append("ns.Sets = {")
    for _, name, st, ids, level, ilvl in kept:
        used.update(ids)
        bonuses = ", ".join(f"{{ {n}, {lua_str(t)} }}" for n, t in st["bonuses"])
        L.append(f"\t{{ id = {st['id']}, name = {lua_str(name)}, " + (f"level = {level}, " if level else "")
                 + f"ilvl = {ilvl}, pieces = {id_list(ids)}, bonuses = {{ {bonuses} }} }},")
    L.append("}")
    L.append("")

    L.append("-- [itemID] = { name, quality, type, flag, sources, icon, tooltip lines, classes (Wowhead class ids) }")
    L.append("-- flag: 0 in Forever, 1 new in Forever, 2 Classic only (not in Forever's data), 3 new, boss unconfirmed")
    L.append("ns.Items = {")
    for iid in sorted(used):
        e = meta[iid]
        fields = [lua_str(e["name"]), str(e["quality"]), lua_str(e["type"]), str(e["flag"]), lua_str(source_text(iid))]
        # Icon and tooltip text for every item: the beta server doesn't send data for many items
        lines = [l for l in e.get("lines", []) if not SOD_MARK.search(l) or l == SOD_NOTE]
        fields.append(lua_str("Interface\\Icons\\" + (e.get("icon") or "inv_misc_questionmark")))
        fields.append("{ " + ", ".join(lua_str(l) for l in lines) + " }")
        if class_list(e):
            fields.append(id_list(class_list(e)))
        L.append(f"\t[{iid}] = {{ {', '.join(fields)} }},")
    L.append("}")
    L.append("")

    with open(OUT, "w") as f:
        f.write("\n".join(L))

    counts = defaultdict(int)
    for i in used:
        counts[meta[i]["flag"]] += 1
    for label, plan in (("dungeons", dungeon_plan), ("raids", raid_plan)):
        empty = [(d["key"], b["name"]) for d, bs, _, _, _, _ in plan for b in bs if not sort_items(b["loot"].items)]
        n_items = len({i for d, bs, t, e, _, _ in plan for x in list(bs) + [t, e] for i in sort_items(
            (x["loot"] if isinstance(x, dict) else x).items)})
        n_quests = sum(len(q) for *_, q in plan)
        print(f"{label}: {len(plan)}, {n_items} items, {n_quests} quests, {len(empty)} bosses without loot",
              file=sys.stderr)
        if empty and label == "raids":
            print("   raid bosses without loot: " + ", ".join(f"{k}:{n}" for k, n in empty), file=sys.stderr)
    print(f"sets: {len(kept)}", file=sys.stderr)
    print(f"wrote {OUT}: {len(used)} items (in Forever {counts[0]}, new {counts[1]}, Classic only {counts[2]}, "
          f"unconfirmed new {counts[3]})", file=sys.stderr)

    # New Forever gear that Wowhead says drops from an NPC but no table here lists: candidates
    # for forever_additions.py (or a boss missing from dungeons.py / raids.py)
    unplaced = {}
    for x in build.new_items:
        drops = [m for m in x["sm"] if m.get("t") == 1 and m.get("n")]
        if x["id"] >= FOREVER_IDS and x["id"] not in used and drops:
            unplaced[x["id"]] = f"{x['name']} ({x['id']}) from {drops[0]['n']}"
    if unplaced:
        report.append(f"-- {len(unplaced)} new rare/epic Forever drops aren't in any table: "
                      + "; ".join(v for _, v in sorted(unplaced.items())[:25]))
    for line in report:
        print(line, file=sys.stderr)


if __name__ == "__main__":
    main()
