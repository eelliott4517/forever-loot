"""Fetch item facts from Wowhead's tooltip API.

Forever (dataEnv 16) is checked first: it tells us whether an item exists in the
WoW: Forever database and gives Forever-accurate names, types and tooltip lines.
Items that Forever doesn't have are looked up in Wowhead's Classic database
(dataEnv 4). Every item's icon and tooltip lines are bundled, because the beta
server doesn't send data for many dungeon items.
Results are cached in cache/items_<env>.json so reruns only fetch new ids.
"""
import html
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
URL = "https://nether.wowhead.com/tooltip/item/{id}?dataEnv={env}&locale=0"
ENVS = {"forever": 16, "classic": 4}
DELAY = 0.3  # seconds between requests; be polite


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
    with open(cache_path(name), "w") as f:
        json.dump({str(k): v for k, v in sorted(cache.items())}, f, indent=0)


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


def tooltip_lines(tip):
    """Wowhead tooltip HTML -> plain lines for an in-game tooltip ('left\\tright' for two columns)."""
    t = re.sub(r"<!--nstart-->.*?<!--nend-->", "", tip, count=1, flags=re.S)
    t = re.sub(r'<div class="whtt-sellprice">.*?</div>', "", t, flags=re.S)
    t = re.sub(r"<table width=\"100%\"><tr><td>(.*?)</td><th>(.*?)</th></tr></table>",
               lambda m: "\n" + strip_tags(m.group(1)) + "\t" + strip_tags(m.group(2)) + "\n", t, flags=re.S)
    t = re.sub(r"<table width=\"100%\"><tr><td>(.*?)</td></tr></table>",
               lambda m: "\n" + strip_tags(m.group(1)) + "\n", t, flags=re.S)
    t = re.sub(r"<br\s*/?>|</tr>|</table>", "\n", t)
    lines = []
    for raw in t.split("\n"):
        parts = [html.unescape(re.sub(r"<[^>]+>", "", p)) for p in raw.split("\t")]
        parts = [re.sub(r"\s+", " ", p).strip() for p in parts]
        if not any(parts):
            continue
        line = "\t".join(p for p in parts if p) if len(parts) > 1 else parts[0]
        line = line.replace("|", "||")
        if line.startswith(GREEN):
            line = "|cff1eff00" + line + "|r"
        lines.append(line)
    return lines


def parse(data, keep_lines):
    if "error" in data:
        return {"missing": True}
    tip = data.get("tooltip", "")
    ilvl = re.search(r"Item Level <!--ilvl-->(\d+)", tip)
    req = re.search(r"Requires Level <!--rlvl-->(\d+)", tip) or re.search(r"Requires Level (\d+)", tip)
    out = {
        "name": data["name"],
        "quality": data.get("quality", 1),
        "icon": data.get("icon"),
        "ilvl": int(ilvl.group(1)) if ilvl else 0,
        "req": int(req.group(1)) if req else 0,
        "type": type_text(data["name"], tip),
        "bop": "Binds when picked up" in tip,
    }
    if keep_lines:
        out["lines"] = tooltip_lines(tip)
    return out


def fetch(ids, env="forever", refresh=False):
    cache = load_cache(env)
    todo = [i for i in sorted(set(ids)) if refresh or i not in cache or ("lines" not in cache[i] and not cache[i].get("missing"))]
    for n, item_id in enumerate(todo, 1):
        req = urllib.request.Request(URL.format(id=item_id, env=ENVS[env]),
                                     headers={"User-Agent": "ForeverLoot-databuilder/1.1"})
        for attempt in range(3):
            try:
                with urllib.request.urlopen(req, timeout=20) as r:
                    data = json.loads(r.read().decode("utf-8"))
                break
            except urllib.error.HTTPError as e:
                if e.code == 404:
                    data = {"error": "not found"}
                    break
                time.sleep(2 + attempt * 3)
            except Exception:
                time.sleep(2 + attempt * 3)
        else:
            print(f"  giving up on {item_id}", file=sys.stderr)
            continue
        cache[item_id] = parse(data, keep_lines=True)
        if n % 50 == 0:
            save_cache(env, cache)
            print(f"  {env}: {n}/{len(todo)} items", file=sys.stderr)
        time.sleep(DELAY)
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
            print(k, json.dumps(v)[:600])
