"""Quest chains for the dungeon and raid quests: the quests you need before each one, and where every
one of them starts, with map pins. build_data.py calls Chains(...).Build(quest_ids).

Inputs
  raw/cmangos_quests.json   the vanilla quest graph from cMaNGOS: prerequisites (PrevQuestId,
                            NextQuestId, ExclusiveGroup, breadcrumbs), races, classes, levels and who
                            starts each quest. Rebuild it from the classic world database dump:
                              curl -L -o /tmp/classicdb.sql.gz \\
                                https://raw.githubusercontent.com/cmangos/classic-db/master/Full_DB/ClassicDB_1_12_1_z2815.sql.gz
                              python3 tools/quest_chains.py /tmp/classicdb.sql.gz
  raw/wowhead.json          the refresh's Wowhead scrape; its quest_<id> pages cover Forever's own quests
                            (and any quest cMaNGOS lacks): start, end, level, side and series. Its
                            item_starts_<id> pages are the items Forever added that start a quest.
  raw/db2/UiMap.csv, UiMapAssignment.csv
                            Forever's map tables (wago.tools), to turn a Wowhead zone into a map for pins
  cache/places_forever.json where quest givers stand in Forever, from Wowhead's tooltips (fetched once,
                            then reused)

Why both: cMaNGOS is a vanilla 1.12 database, right for the Classic quests Forever kept; Forever's new
quests are only on Wowhead. Wowhead's "Series" box follows NextQuestInChain only, so it can miss earlier
steps; cMaNGOS's PrevQuestId links give the whole chain (The Defias Brotherhood is 7 quests, not 2).

Prerequisites follow cMaNGOS (Player::SatisfyQuestPreviousQuest): a quest opens when any one of its
earlier quests is done; an earlier quest in an exclusive group below zero needs its whole group done.
"""
import csv
import gzip
import json
import os
import re
import sys
import time
import urllib.request
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
RAW = os.environ.get("FL_RAW", os.path.join(HERE, "raw"))
CMANGOS = os.path.join(RAW, "cmangos_quests.json")
PLACES = os.path.join(HERE, "cache", "places_forever.json")
TOOLTIP = "https://nether.wowhead.com/forever/tooltip/{kind}/{id}"

ALLIANCE_RACES, HORDE_RACES = 1 | 4 | 8 | 64, 2 | 16 | 32 | 128
MAX_DEPTH = 40


# ------------------------------------------------------------------ the cMaNGOS extract
def rows_of(s):
    """Split the VALUES part of an INSERT into rows of string fields (from Rep Planner's extractor)."""
    out, field, fields = [], [], []
    depth, quoted, esc = 0, False, False
    for c in s:
        if quoted:
            if esc:
                field.append(c)
                esc = False
            elif c == "\\":
                esc = True
            elif c == "'":
                quoted = False
            else:
                field.append(c)
        elif c == "'":
            quoted = True
        elif c == "(":
            depth += 1
            if depth == 1:
                fields, field = [], []
            else:
                field.append(c)
        elif c == ")":
            depth -= 1
            if depth == 0:
                fields.append("".join(field))
                out.append(fields)
            else:
                field.append(c)
        elif c == "," and depth == 1:
            fields.append("".join(field))
            field = []
        elif depth >= 1:
            field.append(c)
    return out


def extract_cmangos(dump):
    want = {"quest_template", "creature_questrelation", "gameobject_questrelation", "creature_involvedrelation",
            "gameobject_involvedrelation", "item_template", "creature_template", "gameobject_template", "conditions"}
    cols, data, table = {}, defaultdict(list), None
    with gzip.open(dump, "rt", encoding="utf-8", errors="replace") as f:
        for line in f:
            m = re.match(r"CREATE TABLE `(\w+)`", line)
            if m:
                table = m.group(1)
                if table in want:
                    cols[table] = []
                continue
            if table in want and line.startswith("  `"):
                cols[table].append(re.match(r"  `(\w+)`", line).group(1))
                continue
            m = re.match(r"INSERT INTO `(\w+)` VALUES (.*);\s*$", line)
            if m and m.group(1) in want:
                data[m.group(1)].extend(rows_of(m.group(2)))
    db = {t: [dict(zip(cols[t], r)) for r in rows] for t, rows in data.items()}

    # [Title, QuestLevel, MinLevel, PrevQuestId, NextQuestId, ExclusiveGroup, BreadcrumbForQuestId, RequiredRaces,
    #  RequiredClasses, RequiredSkill, RequiredSkillValue, RequiredMinRepFaction, RequiredMinRepValue,
    #  RequiredMaxRepFaction, RequiredMaxRepValue, RequiredCondition]
    quests = {}
    for r in db["quest_template"]:
        quests[int(r["entry"])] = [r["Title"]] + [int(r[c]) for c in (
            "QuestLevel", "MinLevel", "PrevQuestId", "NextQuestId", "ExclusiveGroup", "BreadcrumbForQuestId",
            "RequiredRaces", "RequiredClasses", "RequiredSkill", "RequiredSkillValue", "RequiredMinRepFaction",
            "RequiredMinRepValue", "RequiredMaxRepFaction", "RequiredMaxRepValue", "RequiredCondition")]
    # the conditions quests require, with the ones they're built from: [type, value1, value2, flags]
    all_conds = {int(r["condition_entry"]): [int(r["type"]), int(r["value1"]), int(r["value2"]), int(r["flags"])]
                 for r in db["conditions"]}
    conds, todo = {}, [q[15] for q in quests.values() if q[15]]
    while todo:
        c = todo.pop()
        if c in conds or c not in all_conds:
            continue
        conds[c] = all_conds[c]
        if conds[c][0] in (-1, -2):
            todo += conds[c][1:3]
        elif conds[c][0] == -3:
            todo.append(conds[c][1])
    starts, ends = defaultdict(list), defaultdict(list)
    for table, kind, out in (("creature_questrelation", "npc", starts), ("gameobject_questrelation", "object", starts),
                             ("creature_involvedrelation", "npc", ends), ("gameobject_involvedrelation", "object", ends)):
        for r in db[table]:
            out[int(r["quest"])].append([kind, int(r["id"])])
    for r in db["item_template"]:
        q = int(r.get("startquest") or 0)
        if q:
            starts[q].append(["item", int(r["entry"])])
    used = defaultdict(set)
    for lst in list(starts.values()) + list(ends.values()):
        for kind, oid in lst:
            used[kind].add(oid)
    names = {
        "npc": {int(r["Entry"]): r["Name"] for r in db["creature_template"] if int(r["Entry"]) in used["npc"]},
        "object": {int(r["entry"]): r["name"] for r in db["gameobject_template"] if int(r["entry"]) in used["object"]},
        "item": {int(r["entry"]): r["name"] for r in db["item_template"] if int(r["entry"]) in used["item"]},
    }
    out = {"quests": quests, "starts": starts, "ends": ends, "names": names, "conditions": conds}
    with open(CMANGOS, "w") as f:
        json.dump(out, f, separators=(",", ":"), sort_keys=True)
    print("wrote", CMANGOS, {k: len(v) for k, v in out.items()})


# ------------------------------------------------------------------ places: Wowhead zone + coordinates
def _get_json(url):
    for attempt in range(4):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "ForeverLoot-databuilder/1.7"})
            with urllib.request.urlopen(req, timeout=30) as r:
                return json.loads(r.read().decode("utf-8"))
        except Exception:
            time.sleep(2 + attempt * 3)
    return None


def fetch_places(refs, max_age_days=30):
    """{"npc:123": [name, areaID, x, y]} for each (kind, id), from Wowhead's Forever tooltips, cached."""
    cache = {}
    if os.path.exists(PLACES):
        with open(PLACES) as f:
            cache = json.load(f)
    now = time.time()
    todo = [r for r in refs if f"{r[0]}:{r[1]}" not in cache or now - cache[f"{r[0]}:{r[1]}"].get("t", 0) > max_age_days * 86400]

    def one(ref):
        kind, oid = ref
        d = _get_json(TOOLTIP.format(kind=kind, id=oid))
        if d is None:
            return ref, None   # the network failed: ask again next build
        if "error" in d:
            return ref, {"t": now, "missing": True}
        m = d.get("map") or {}
        coords = m.get("coords") or {}
        first = next(iter(coords.values()), [])
        x, y = (first[0] if first else (None, None))
        if not x and not y:   # 0, 0: somewhere in the zone (inside an instance, say)
            x = y = None
        return ref, {"t": now, "name": d.get("name"), "zone": m.get("zone"), "x": x, "y": y}

    if todo:
        print(f"  places: fetching {len(todo)} from Wowhead's tooltips")
        with ThreadPoolExecutor(6) as pool:
            for ref, place in pool.map(one, todo):
                if place is not None:
                    cache[f"{ref[0]}:{ref[1]}"] = place
        os.makedirs(os.path.dirname(PLACES), exist_ok=True)
        with open(PLACES, "w") as f:
            json.dump(cache, f, indent=0, sort_keys=True)
    return cache


def zone_maps():
    """{areaID: uiMapID} for zone maps, and {uiMapID: name}, from Forever's UiMap tables."""
    maps, names = {}, {}
    with open(os.path.join(RAW, "db2", "UiMap.csv"), newline="") as f:
        for r in csv.DictReader(f):
            maps[int(r["ID"])] = int(r["Type"])
            names[int(r["ID"])] = r["Name_lang"]
    area = {}
    with open(os.path.join(RAW, "db2", "UiMapAssignment.csv"), newline="") as f:
        for r in csv.DictReader(f):
            ui, a = int(r["UiMapID"]), int(r["AreaID"])
            # a zone (3) or a city or dungeon level map that is the area itself (4, 5)
            if a and maps.get(ui) in (3, 4, 5) and (a not in area or maps[area[a]] != 3):
                area[a] = ui
    return area, names


# ------------------------------------------------------------------ the graph
class Chains:
    def __init__(self, wowhead_pages):
        with open(CMANGOS) as f:
            cm = json.load(f)
        self.q = {int(k): v for k, v in cm["quests"].items()}
        self.starts = {int(k): v for k, v in cm["starts"].items()}
        self.ends = {int(k): v for k, v in cm["ends"].items()}
        self.names = {kind: {int(k): v for k, v in d.items()} for kind, d in cm["names"].items()}
        self.conds = {int(k): v for k, v in cm.get("conditions", {}).items()}
        # earlier quests: own PrevQuestId, plus every quest whose NextQuestId points here
        self.prev = defaultdict(list)
        self.groups = defaultdict(list)
        self.leads = defaultdict(list)
        for qid, r in self.q.items():
            prev, nxt, excl, crumb = r[3], r[4], r[5], r[6]
            if prev:
                self.prev[qid].append(prev)
            if nxt:
                self.prev[abs(nxt)].append(-qid if nxt < 0 else qid)
            if excl:
                self.groups[excl].append(qid)
            if crumb:
                self.leads[crumb].append(qid)
        # Forever's own quests (and any cMaNGOS lacks), from their Wowhead pages
        self.wh = {}
        self.missing = set()
        # Items Forever added that start a quest: {questID: ["item", itemID, name]}
        self.item_pages = {}
        for key, page in (wowhead_pages or {}).items():
            m = re.match(r"item_starts_(\d+)$", key)
            if m:
                for qid in page.get("quests") or []:
                    self.item_pages.setdefault(qid, ["item", int(m.group(1)), page.get("name")])
                continue
            m = re.match(r"quest_(\d+)$", key)
            if not m:
                continue
            qid = int(m.group(1))
            if page.get("missing"):
                self.missing.add(qid)
                continue
            self.wh[qid] = page
        # Wowhead's Series box lists a chain in order. It follows NextQuestInChain, which the game
        # doesn't require, so a step before counts as an earlier quest only when its turn-in NPC
        # starts this one, or its level doesn't put it after this one.
        for qid, page in self.wh.items():
            series = [x[0] for x in page.get("series") or []]
            if qid in self.q or qid not in series or series.index(qid) == 0:
                continue
            before = series[series.index(qid) - 1]
            if before not in self.prev[qid] and self.series_link(before, qid):
                self.prev[qid].append(before)
        # Starts build_data.py knows from elsewhere (an item filed under the dungeon with the quest's name)
        self.item_starts = {}

    def series_link(self, before, qid):
        a, b = self.wh.get(before) or {}, self.wh.get(qid) or {}
        end, start = a.get("end"), b.get("start")
        if end and start and end[:2] == start[:2]:
            return True
        req_a = a.get("req") or (self.q[before][2] if before in self.q else None)
        req_b = b.get("req")
        return not (req_a and req_b and int(req_a) > int(req_b))

    def unobtainable(self, qid, new=False):
        """True for a quest no one can pick up in Forever: Wowhead has no quest page for the id (it's an
        item that starts a quest), or the quest isn't in the vanilla database and its Forever page names no
        quest giver and no turn-in (a Classic leftover like Waking Naralex, or an old copy of a quest whose
        live version is listed too). Forever's new quests are kept: Wowhead's data on them is still filling in."""
        if qid in self.missing:
            return True
        if qid in self.q or new:
            return False
        page = self.wh.get(qid)
        return bool(page) and not page.get("start") and not page.get("end")

    def alternatives(self, qid):
        """Earlier quests as alternatives (any one will do); an alternative that's a list needs all of
        them. A negative id must be in your log. Follows Player::SatisfyQuestPreviousQuest in cMaNGOS."""
        r0 = self.q.get(qid)
        own_prev = r0[3] if r0 else 0
        out = []
        for p in self.prev.get(qid, []):
            r = self.q.get(abs(p))
            # An earlier quest in an each-from-all group (below zero) needs its whole group, unless this
            # quest branches off it: it has a PrevQuestId of its own that isn't where the earlier quest
            # leads (Wildeyes alone opens the Dreadsteed reagents)
            if r and r[5] < 0 and p > 0 and not (own_prev and r[4] != own_prev):
                alt = sorted(self.groups[r[5]])
            else:
                alt = p
            if alt not in out:
                out.append(alt)
        out = self.merge_ancestors(out)
        # RequiredCondition: one built only from quests done joins the earlier quests
        cond = self.condition_alternatives(r0[15]) if r0 and r0[15] else None
        if cond:
            out = self.combine(out, cond)
        return out

    def ancestors(self, qid, depth=0, seen=None):
        seen = set() if seen is None else seen
        for p in self.prev.get(qid, []):
            p = abs(p)
            if p not in seen and depth < MAX_DEPTH:
                seen.add(p)
                self.ancestors(p, depth + 1, seen)
        return seen

    def merge_ancestors(self, alts):
        """cMaNGOS lets any one earlier quest do. When one of them comes before another in its own chain
        (Components of Importance, then I See Alcaz Island, before More Components of Importance), the
        data only makes sense as both: the variant picks which, the later one is the step before."""
        singles = [a for a in alts if isinstance(a, int) and a > 0]
        merged = list(alts)
        for x in singles:
            for y in singles:
                if x != y and x in merged and y in merged and x in self.ancestors(y):
                    merged.remove(x)
                    merged[merged.index(y)] = [x, y]
                    break
        return merged

    def condition_alternatives(self, c, depth=0):
        """A condition made only of quests done, as alternatives (lists need all); None otherwise"""
        e = self.conds.get(c)
        if not e or depth > 10 or e[3] & 1:
            return None
        t, v1, v2 = e[0], e[1], e[2]
        if t == 8:
            return [[v1]]
        if t in (-1, -2):
            a, b = self.condition_alternatives(v1, depth + 1), self.condition_alternatives(v2, depth + 1)
            if a is None or b is None:
                return None
            if t == -2:
                return a + [x for x in b if x not in a]
            return [sorted(set(x) | set(y)) for x in a for y in b]
        return None

    @staticmethod
    def combine(alts, cond):
        """Both: one of `alts` and one of `cond` (cond's alternatives are lists of quest ids)"""
        def ids(a):
            return a if isinstance(a, list) else [a]
        if not alts:
            out = [c for c in cond]
        elif any(isinstance(a, int) and a < 0 for a in alts):
            out = list(alts) + [c for c in cond if c not in alts]
        else:
            out = []
            for a in alts:
                for c in cond:
                    both = sorted(set(ids(a)) | set(c))
                    if both not in out:
                        out.append(both)
        return [o[0] if isinstance(o, list) and len(o) == 1 else o for o in out]

    def info(self, qid):
        r, page = self.q.get(qid), self.wh.get(qid)
        races = 0
        extra = {}
        if r:
            name, level, req, races, classes = r[0], r[1], r[2], r[7] & 255, r[8]
            side = 1 if races and not races & HORDE_RACES else (2 if races and not races & ALLIANCE_RACES else None)
            # races only when they're fewer than the side's (a Night Elf quest)
            if not side or races in (ALLIANCE_RACES, HORDE_RACES):
                races = 0
            if r[9] and r[10] > 0:
                extra["skill"] = [r[9], r[10]]
            if r[11]:
                extra["rep"] = [r[11], r[12]]
            if r[13]:
                extra["repMax"] = [r[13], r[14]]
            if r[15] and self.condition_alternatives(r[15]) is None:
                extra["special"] = True   # a buff, an item or the dungeon's own state: can't be checked here
            if r[6]:
                extra["crumb"] = r[6]
        elif page:
            name, level, req, classes = page.get("title"), page.get("level"), page.get("req"), 0
            side = {"alliance": 1, "horde": 2}.get((page.get("side") or "").lower())
            level, req = int(level) if level else None, int(req) if req else None
        else:
            return None
        group = []
        if r and r[5] > 0:
            group = sorted(q for q in self.groups[r[5]] if q != qid)
        out = {"name": name, "level": level if level and level > 0 else None, "req": req or None, "side": side,
               "races": races or None, "classes": classes or None, "prev": self.alternatives(qid),
               "group": group, "lead": sorted(self.leads.get(qid, [])),
               "from": self.giver(qid, page, self.starts, "start"), "to": self.giver(qid, page, self.ends, "end")}
        out.update(extra)
        return out

    def giver(self, qid, page, table, key):
        """[kind, id, name] of who starts (or takes in) a quest: Wowhead's Forever page first, then cMaNGOS"""
        if page and page.get(key):
            kind, oid, name = page[key]
            return [kind, oid, name]
        if table.get(qid):
            kind, oid = table[qid][0]
            return [kind, oid, self.names.get(kind, {}).get(oid)]
        if key == "start":
            for found in (self.item_pages, self.item_starts):
                if qid in found:
                    return list(found[qid])
        return None

    def Build(self, quest_ids):
        """{questID: info} for the quests, every quest before them and their optional lead-ins"""
        out, todo = {}, [(q, 0) for q in quest_ids]
        while todo:
            qid, d = todo.pop()
            qid = abs(qid)
            if qid in out or d > MAX_DEPTH:
                continue
            info = self.info(qid)
            if not info:
                continue
            out[qid] = info
            for alt in info["prev"]:
                for p in (alt if isinstance(alt, list) else [alt]):
                    todo.append((p, d + 1))
            for p in info["lead"]:
                todo.append((p, d + 1))
        return out

    def Places(self, infos):
        """Adds where each giver is: [kind, id, name, uiMapID, x, y] (x and y when Wowhead has them), and
        the name Forever uses"""
        givers = [g for i in infos.values() for g in (i["from"], i["to"]) if g and g[0] in ("npc", "object")]
        places = fetch_places(sorted({(g[0], g[1]) for g in givers}))
        area, _ = zone_maps()
        for g in givers:
            p = places.get(f"{g[0]}:{g[1]}") or {}
            if p.get("name"):
                g[2] = p["name"]
            ui = area.get(p.get("zone"))
            if ui and len(g) == 3:
                g.append(ui)
                if p.get("x") and p.get("y"):
                    g.extend([p["x"], p["y"]])


if __name__ == "__main__":
    extract_cmangos(sys.argv[1])
