"""Read Forever's new dungeons and raids from warcraft.wiki.gg into tools/raw/wiki.json.

    python3 tools/wiki.py

For each instance in PAGES it reads the wiki page's Encounters list (the bosses in the order you
meet them, rares marked), its Loot section's boss and trash tables, each boss's level from its
own page (the Npcbox), and each item's id from its page (the Itemtip). Everything comes from the
MediaWiki API, which the wiki offers for scripted use, one request at a time with a pause between
them, and is cached in tools/cache/wiki (delete it to read the pages fresh).

boss_models.py takes the levels of the bosses cMaNGOS doesn't have (Forever's own), and
build_data.py takes the loot as a source next to wowtbc.gg and Wowhead.
"""
import difflib
import json
import os
import re
import sys
import time
import urllib.parse
import urllib.request

TOOLS = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(TOOLS, "raw", "wiki.json")
CACHE = os.path.join(TOOLS, "cache", "wiki")
API = "https://warcraft.wiki.gg/api.php"
UA = "ForeverLoot-databuilder/1.13 (World of Warcraft addon data build)"
PAUSE = 0.5

# dungeon or raid key (dungeons.py, raids.py) -> its page on the wiki
PAGES = {
    "HOT": "Hall of Thanes (instance)",
    "ROL": "Ruins of Lordaeron (instance)",
    "EXC": "Excavation Site: Wetlands",
    "DAL": "City of Dalaran",
    "DROWN": "Drowned City",
    "KROL": "Krol'dok Stronghold",
    "ALCAZ": "Alcaz Prison",
    "BMH": "Blackmaw Hold (instance)",
    "SHAPER": "Shaper's Terrace (instance)",
    "BARROW": "Barrow Deeps (instance)",
    "HYJAL": "Hyjal Summit (instance)",
}


def api(**params):
    params = dict(params, format="json", formatversion=2)
    query = urllib.parse.urlencode(sorted(params.items()))
    os.makedirs(CACHE, exist_ok=True)
    path = os.path.join(CACHE, re.sub(r"[^\w.-]", "_", query)[:180] + ".json")
    if os.path.exists(path):
        with open(path) as f:
            return json.load(f)
    req = urllib.request.Request(API + "?" + query, headers={"User-Agent": UA})
    for attempt in range(4):
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                data = json.loads(r.read().decode("utf-8"))
            break
        except OSError:
            if attempt == 3:
                raise
            time.sleep(3 * (attempt + 1))
    with open(path, "w") as f:
        json.dump(data, f)
    time.sleep(PAUSE)
    return data


def wikitext(title):
    """(text, title) of a page, following redirects; (None, None) if there's no such page"""
    d = api(action="parse", page=title, prop="wikitext", redirects=1)
    p = d.get("parse")
    return (p["wikitext"], p["title"]) if p else (None, None)


def section(text, name):
    """A level-2 section's text, subsections included"""
    m = re.search(r"^==\s*" + re.escape(name) + r"\s*==\s*$", text, re.M)
    if not m:
        return ""
    end = re.search(r"^==[^=].*==\s*$", text[m.end():], re.M)
    return text[m.end(): m.end() + end.start() if end else len(text)]


def subsection(text, name):
    m = re.search(r"^===\s*" + re.escape(name) + r"\s*===\s*$", text, re.M)
    if not m:
        return ""
    end = re.search(r"^===?[^=].*===?\s*$", text[m.end():], re.M)
    return text[m.end(): m.end() + end.start() if end else len(text)]


LINK = re.compile(r"\[\[([^\]|#]+)(?:#[^\]|]*)?(?:\|([^\]]+))?\]\]")


def link(s):
    """(page, shown name) of the first [[link]] in s"""
    m = LINK.search(s)
    if not m:
        return None, None
    page = m.group(1).strip()
    return page, (m.group(2) or page).strip()


def encounters(text):
    out = []
    for line in section(text, "Encounters").splitlines():
        if not line.startswith("*"):
            continue
        page, name = link(line)
        if page:
            note = LINK.sub("", line.lstrip("*")).strip(" -:()").lower()
            out.append(dict(name=name, page=page, rare="rare" in note, note=note))
    return out


def loot_table(text):
    """[(boss name or None, [item pages])] from a darktable: a "! rowspan=N | [[Boss]]" header
    cell starts each boss's rows; "! Shared" rows belong to no boss"""
    rows, boss = [], None
    for line in text.splitlines():
        line = line.strip()
        if line.startswith("!") and "||" not in line:
            cell = line.lstrip("!").split("|")[-1] if "rowspan" in line else line.lstrip("!")
            page, name = link(cell)
            boss = name or cell.strip()
            rows.append([boss, []])
        elif line.startswith("|") and not line.startswith(("|-", "|+", "|}")):
            page, _ = link(line.split("||")[0])
            if page:
                if not rows:
                    rows.append([None, []])
                rows[-1][1].append(page)
    return [(b, items) for b, items in rows if items]


def boss_name(name, bosses):
    """A loot table's boss as the Encounters list names it: without a note like "(rare)", and a
    misspelling ("Durgen Direhammer") matched to the closest name"""
    if not name:
        return name
    name = re.sub(r"\s*\([^)]*\)\s*$", "", name).strip()
    names = [b["name"] for b in bosses]
    if name in names or name.lower() == "shared":
        return name
    close = difflib.get_close_matches(name, names, n=1, cutoff=0.85)
    return close[0] if close else name


def npc_level(page):
    """(level text, type) from a boss's Npcbox"""
    text, _ = wikitext(page)
    if not text:
        return None, None
    box = re.search(r"\{\{Npcbox(.*?)\n\}\}", text, re.S)
    if not box:
        return None, None
    fields = dict(re.findall(r"^\s*\|\s*(\w+)\s*=\s*(.*?)\s*$", box.group(1), re.M))
    return fields.get("level") or None, fields.get("type") or None


def item_id(page):
    text, _ = wikitext(page)
    m = text and re.search(r"\|\s*itemid\s*=\s*(\d+)", text)
    return int(m.group(1)) if m else None


def level_value(text):
    """The level as boss_models.py writes it: a number, "low-high", or -1 for "??" """
    if not text:
        return None
    if "??" in text or "skull" in text.lower() or "boss" in text.lower():
        return -1
    nums = [int(n) for n in re.findall(r"\d+", text)]
    if not nums:
        return None
    low, high = min(nums), max(nums)
    return low if low == high else f"{low}-{high}"


def main():
    out = {"fetched": time.strftime("%Y-%m-%d"), "source": "warcraft.wiki.gg", "instances": {}}
    missing = []
    for key, title in PAGES.items():
        text, found = wikitext(title)
        if not text:
            missing.append(f"{key}: no page {title}")
            continue
        info = re.search(r"\|\s*level\s*=\s*([^\n|]+)", text)
        bosses = []
        for b in encounters(text):
            level, kind = npc_level(b["page"])
            bosses.append(dict(b, level=level_value(level), level_text=level, type=kind))
        loot_text = section(text, "Loot")
        loot = []
        for boss, pages in loot_table(subsection(loot_text, "Boss drops")):
            ids = []
            for p in pages:
                iid = item_id(p)
                if iid:
                    ids.append(iid)
                else:
                    missing.append(f"{key}: no item id on {p}")
            loot.append(dict(boss=boss_name(boss, bosses), items=ids))
        trash = []
        for _, pages in loot_table(subsection(loot_text, "Trash mob drops")):
            for p in pages:
                iid = item_id(p)
                if iid:
                    trash.append(iid)
                else:
                    missing.append(f"{key}: no item id on {p}")
        out["instances"][key] = dict(page=found, levels=info.group(1).strip() if info else None,
                                     bosses=bosses, loot=loot, trash=trash)
        print(f"{key:7} {found}: {len(bosses)} bosses, "
              f"{sum(len(x['items']) for x in loot)} boss drops, {len(trash)} trash drops", flush=True)
    with open(OUT, "w") as f:
        json.dump(out, f, indent=1)
    print(f"wrote {OUT}")
    for m in missing:
        print("  " + m)


if __name__ == "__main__":
    sys.exit(main())
