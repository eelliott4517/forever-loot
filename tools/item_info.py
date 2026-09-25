"""Fetch item facts from Wowhead's tooltip API.

Forever (dataEnv 16) is checked first: it tells us whether an item exists in the
WoW: Forever database and gives Forever-accurate names, types and tooltip lines.
Items that Forever doesn't have are looked up in Wowhead's Classic database
(dataEnv 4). Every item's icon and tooltip lines are bundled, because the beta
server doesn't send data for many dungeon items.

Results are cached in cache/items_<env>.json with the raw tooltip HTML, so a parser
change re-reads the cache instead of fetching again. Entries older than FL_ITEM_AGE
days (default: never) are fetched again.
"""
import html
import json
import os
import re
import sys
import threading
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
URL = "https://nether.wowhead.com/tooltip/item/{id}?dataEnv={env}&locale=0"
ENVS = {"forever": 16, "classic": 4}
PARSER = 3          # bump when parse() changes; cached HTML gets parsed again
WORKERS = 8
MIN_INTERVAL = 0.2  # seconds between requests across all workers; be polite


def cache_path(name):
    return os.path.join(HERE, "cache", f"items_{name}.json")


def load_cache(name):
    p = cache_path(name)
    if os.path.exists(p):
        with open(p) as f:
            return {int(k): v for k, v in json.load(f).items()}
    return {}


def save_cache(name, cache):
    os.makedirs(os.path.dirname(cache_path(name)), exist_ok=True)
    tmp = cache_path(name) + ".tmp"
    with open(tmp, "w") as f:
        json.dump({str(k): v for k, v in sorted(cache.items())}, f, indent=0)
    os.replace(tmp, cache_path(name))


def strip_tags(s):
    return html.unescape(re.sub(r"<[^>]+>", "", s)).strip()


RECIPE_PREFIXES = ("Recipe:", "Pattern:", "Plans:", "Schematic:", "Formula:", "Manual:", "Design:", "Blueprint:")


def type_text(name, tip):
    """Short slot/type label, e.g. 'Cloth Chest', 'One-Hand Sword', 'Back', 'Shield'."""
    if name.startswith(RECIPE_PREFIXES):
        return "Recipe"
    m = re.search(r'<table width="100%"><tr><td>(.*?)</td>(?:<th>(.*?)</th>)?</tr></table>', tip)
    if m:
        slot = strip_tags(m.group(1))
        kind = strip_tags(m.group(2) or "")
        if kind == "Shield":
            return "Shield"
        if kind in ("Cloth", "Leather", "Mail", "Plate"):
            return f"{kind} {slot}"
        if kind:
            if slot in ("Ranged", "Thrown", "Projectile"):
                return kind
            return f"{slot} {kind}"
        return slot
    if "Quest Item" in tip:
        return "Quest Item"
    m = re.search(r"<br>(\d+) Slot ([A-Za-z ]*Bag)", tip)
    if m:
        return f"{m.group(1)} Slot Bag"
    return ""


GREEN = ("Equip:", "Use:", "Chance on hit:")
GOLD, GREY = "|cffffd100", "|cff9d9d9d"
SET_HEADER = re.compile(r'<span class="q"><a href="/[a-z]+/item-set=(\d+)[^"]*"[^>]*>(.*?)</a>\s*\((\d+)/(\d+)\)</span>', re.S)
SET_PIECES = re.compile(r'<div class="q0 indent">(.*?)</div>', re.S)
SET_BONUS = re.compile(r"^\((\d+)\) Set ?: ?(.*)$")
CLASSES = re.compile(r'<div class="wowhead-tooltip-item-classes">(.*?)</div>', re.S)


def tooltip_lines(tip):
    """Wowhead tooltip HTML -> plain lines for an in-game tooltip ('left\\tright' for two columns).
    Set names are gold and the pieces and bonuses grey, as in game when you wear none of it."""
    t = re.sub(r"<!--nstart-->.*?<!--nend-->", "", tip, count=1, flags=re.S)
    t = re.sub(r'<div class="whtt-sellprice">.*?</div>', "", t, flags=re.S)
    t = SET_HEADER.sub(lambda m: f"\n\x01{strip_tags(m.group(2))} (0/{m.group(4)})\n", t)
    t = SET_PIECES.sub(lambda m: "".join(f"\n\x02{strip_tags(p)}\n" for p in re.findall(r"<span>(.*?)</span>", m.group(1), re.S)), t)
    t = re.sub(r"<table width=\"100%\"><tr><td>(.*?)</td><th>(.*?)</th></tr></table>",
               lambda m: "\n" + strip_tags(m.group(1)) + "\t" + strip_tags(m.group(2)) + "\n", t, flags=re.S)
    t = re.sub(r"<table width=\"100%\"><tr><td>(.*?)</td></tr></table>",
               lambda m: "\n" + strip_tags(m.group(1)) + "\n", t, flags=re.S)
    t = re.sub(r"<br\s*/?>|</tr>|</table>|<div[^>]*>|</div>", "\n", t)
    lines = []
    for raw in t.split("\n"):
        parts = [html.unescape(re.sub(r"<[^>]+>", "", p)) for p in raw.split("\t")]
        parts = [re.sub(r"\s+", " ", p).strip() for p in parts]
        if not any(parts):
            continue
        line = "\t".join(p for p in parts if p) if len(parts) > 1 else parts[0]
        line = line.replace("|", "||")
        if line.startswith("\x01"):
            line = GOLD + line[1:] + "|r"
        elif line.startswith("\x02"):
            line = GREY + "  " + line[1:] + "|r"
        elif SET_BONUS.match(line):
            m = SET_BONUS.match(line)
            line = f"{GREY}({m.group(1)}) Set: {m.group(2)}|r"
        elif line.startswith(GREEN):
            line = "|cff1eff00" + line + "|r"
        lines.append(line)
    return lines


def item_set(tip):
    """The item set the tooltip lists: id, name, piece ids, bonuses [(pieces, text)]."""
    m = SET_HEADER.search(tip)
    if not m:
        return None
    pieces = []
    block = SET_PIECES.search(tip, m.end())
    for ids in re.findall(r"<!--si([\d:]+)-->", block.group(1) if block else ""):
        pieces.append(int(ids.split(":")[0]))
    bonuses = []
    for n, text in re.findall(r"\((\d+)\) Set ?: ?(.*?)</span>", tip[m.end():], re.S):
        bonuses.append([int(n), re.sub(r"\s+", " ", strip_tags(text))])
    return {"id": int(m.group(1)), "name": strip_tags(m.group(2)), "pieces": pieces, "bonuses": bonuses}


def parse(data):
    if "error" in data:
        return {"missing": True}
    tip = data.get("tooltip", "")
    ilvl = re.search(r"Item Level <!--ilvl-->(\d+)", tip)
    req = re.search(r"Requires Level <!--rlvl-->(\d+)", tip) or re.search(r"Requires Level (\d+)", tip)
    classes = CLASSES.search(tip)
    out = {
        "name": data["name"],
        "quality": data.get("quality", 1),
        "icon": data.get("icon"),
        "ilvl": int(ilvl.group(1)) if ilvl else 0,
        "req": int(req.group(1)) if req else 0,
        "type": type_text(data["name"], tip),
        "bop": "Binds when picked up" in tip,
        "lines": tooltip_lines(tip),
    }
    if classes:
        out["classes"] = [int(c) for c in re.findall(r"/class=(\d+)", classes.group(1))]
    s = item_set(tip)
    if s:
        out["set"] = s
    return out


def entry(data, fetched):
    """A cache entry: the parsed fields plus what they came from."""
    e = parse(data)
    e.update(v=PARSER, t=int(fetched), raw={k: data[k] for k in ("name", "quality", "icon", "tooltip", "error") if k in data})
    return e


def reparse(e):
    if e.get("v") == PARSER or "raw" not in e:
        return e
    return entry(e["raw"], e.get("t", 0))


_lock = threading.Lock()
_last = [0.0]


def _get(item_id, env):
    req = urllib.request.Request(URL.format(id=item_id, env=ENVS[env]),
                                 headers={"User-Agent": "ForeverLoot-databuilder/1.6"})
    for attempt in range(4):
        with _lock:
            wait = _last[0] + MIN_INTERVAL - time.time()
            if wait > 0:
                time.sleep(wait)
            _last[0] = time.time()
        try:
            with urllib.request.urlopen(req, timeout=20) as r:
                return json.loads(r.read().decode("utf-8"))
        except urllib.error.HTTPError as e:
            if e.code == 404:
                return {"error": "not found"}
            time.sleep(2 + attempt * 3)
        except Exception:
            time.sleep(2 + attempt * 3)
    return None


def fetch(ids, env="forever", max_age_days=None):
    if max_age_days is None:
        age = os.environ.get("FL_ITEM_AGE")
        max_age_days = int(age) if age else None
    cache = {k: reparse(v) for k, v in load_cache(env).items()}
    oldest = time.time() - max_age_days * 86400 if max_age_days else None

    def stale(i):
        e = cache.get(i)
        return e is None or "raw" not in e or (oldest is not None and e.get("t", 0) < oldest)

    todo = [i for i in sorted(set(ids)) if stale(i)]
    if todo:
        print(f"  {env}: fetching {len(todo)} tooltips", file=sys.stderr)
    done = 0
    with ThreadPoolExecutor(WORKERS) as pool:
        for item_id, data in zip(todo, pool.map(lambda i: _get(i, env), todo)):
            if data is None:
                print(f"  giving up on {item_id}", file=sys.stderr)
                continue
            cache[item_id] = entry(data, time.time())
            done += 1
            if done % 200 == 0:
                save_cache(env, cache)
                print(f"  {env}: {done}/{len(todo)}", file=sys.stderr)
    save_cache(env, cache)
    return cache


if __name__ == "__main__":
    env = "forever"
    args = sys.argv[1:]
    if args and args[0] in ENVS:
        env = args.pop(0)
    ids = [int(x) for x in args]
    for k, v in fetch(ids, env).items():
        if k in ids:
            print(k, json.dumps({x: y for x, y in v.items() if x != "raw"})[:1500])
