"""Link Forever's new recipes to the items they make, in ForeverLoot/ProfessionData.lua.

ProfessionData.lua was generated (by 1.4.0's build_professions.py, which isn't in this repo)
before Wowhead knew what many new recipes create, so those recipes have no `item` and a
placeholder icon. This finds each one's item in Wowhead's list of new Forever items (new_items
in raw/wowhead.json): the item Wowhead says the recipe's spell creates, or else the only item
with the recipe's name. It writes the item id in. It also fills in where a new pattern comes
from (who sells it, or which quest gives it) when ProfessionData.lua doesn't say, from
Wowhead's list of new recipe items (new_recipes). refresh.py runs it before build_data.py,
which then bundles the linked items' tooltips.

    python3 tools/link_recipes.py          write the links
    python3 tools/link_recipes.py --check  just report what would change
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PROFESSIONS = os.path.join(HERE, "..", "ForeverLoot", "ProfessionData.lua")
RECIPE = re.compile(r'(\t\t\t\{ id = \d+, name = "((?:[^"\\]|\\.)*)"(.*?) \},\n)')
PLACEHOLDER = ', icon = "Interface\\\\Icons\\\\temp"'
PATTERN = re.compile(r'^(\t\[(\d+)\] = \{ "(?:[^"\\]|\\.)*", \d, )""( \},)$', re.M)   # a pattern with no source
VENDOR, QUEST, DROP = 5, 4, 2        # Wowhead's source types
NPC, QUEST_SOURCE = 1, 5             # ...and its sourcemore entry types


def wowhead_pages():
    path = os.path.join(HERE, "raw", "wowhead.json")
    return json.load(open(path))["pages"] if os.path.exists(path) else {}


def lua_escaped(text):
    return text.replace("\\", "\\\\").replace('"', '\\"')


def where_from(x, zones):
    """A pattern's source as ProfessionData.lua words it (Lua-escaped): "sold by Mishta in Silithus"."""
    def at(m):
        zone = zones.get(m.get("z"))
        return lua_escaped(m["n"] + (f" in {zone}" if zone else ""))
    npcs = [m for m in x.get("sm") or [] if m.get("t") == NPC and m.get("n")]
    quests = [m for m in x.get("sm") or [] if m.get("t") == QUEST_SOURCE and m.get("n")]
    parts = []
    if QUEST in x.get("src", []):
        parts += [f'a reward from the quest \\"{lua_escaped(q["n"])}\\"' for q in quests[:1]] or ["a quest reward"]
    if VENDOR in x.get("src", []):
        parts += [f"sold by {at(m)}" for m in npcs[:1]] or ["sold by a vendor"]
    elif DROP in x.get("src", []):
        parts += [f"dropped by {at(m)}" for m in npcs[:1]] or ["a drop"]
    return ", or ".join(parts)


def pattern_sources(src, pages):
    """ProfessionData.lua with the patterns that have no source given Wowhead's."""
    recipes = {x["id"]: x for key, page in pages.items() if key.startswith("new_recipes_") for x in page["items"]}
    zones = {z["id"]: z["name"] for z in (pages.get("forever_zones") or {}).get("zones", [])}
    filled = []

    def fill(m):
        x = recipes.get(int(m.group(2)))
        text = where_from(x, zones) if x else ""
        if not text:
            return m.group(0)
        filled.append((x["name"], text))
        return f'{m.group(1)}"{text}"{m.group(3)}'

    return PATTERN.sub(fill, src), filled


def new_items(pages):
    """Wowhead's new Forever items by name, and by the recipe spell that creates them."""
    by_name, by_spell = {}, {}
    for key, page in pages.items():
        if key.startswith("new_items_"):
            for x in page["items"]:
                by_name.setdefault(x["name"], {})[x["id"]] = x
                for m in x.get("sm") or []:
                    if m.get("t") == 6 and m.get("ti"):    # created by this spell
                        by_spell.setdefault(m["ti"], set()).add(x["id"])
    return by_name, by_spell


def main():
    check = "--check" in sys.argv
    pages = wowhead_pages()
    by_name, by_spell = new_items(pages)
    src = open(PROFESSIONS, encoding="utf-8").read()
    linked, unmatched, ambiguous = [], [], []

    def link(m):
        whole, name, rest = m.group(1), m.group(2), m.group(3)
        if " item = " in rest or " slot = " in rest or " desc = " in rest:
            return whole                      # makes a known item, or it's an enchant
        # The item Wowhead says this recipe's spell creates; else the one item with its name
        recipe_id = int(re.match(r"\t\t\t\{ id = (\d+)", whole).group(1))
        found = by_spell.get(recipe_id) or set(by_name.get(name.replace('\\"', '"'), {}))
        if len(found) != 1:
            (ambiguous if found else unmatched).append(name)
            return whole
        item_id = next(iter(found))
        linked.append((name, item_id))
        # item goes after colors, as in the other recipes; the item's own icon replaces the placeholder
        new_rest = rest.replace(PLACEHOLDER, "")
        if ", mats = " in new_rest:
            new_rest = new_rest.replace(", mats = ", f", item = {item_id}, mats = ", 1)
        else:
            new_rest = f", item = {item_id}" + new_rest
        return whole.replace(rest, new_rest, 1)

    out = RECIPE.sub(link, src)
    print(f"linked {len(linked)} recipes to their items; {len(unmatched)} have no match on Wowhead yet, "
          f"{len(ambiguous)} match more than one item")
    for name, item_id in linked:
        print(f"   {name} -> {item_id}")
    if unmatched:
        print("   no match: " + ", ".join(unmatched))
    if ambiguous:
        print("   ambiguous: " + ", ".join(ambiguous))
    out, filled = pattern_sources(out, pages)
    print(f"gave {len(filled)} patterns the source Wowhead lists")
    for name, text in filled:
        print(f"   {name}: {text}")
    if not check and (linked or filled):
        with open(PROFESSIONS, "w", encoding="utf-8") as f:
            f.write(out)


if __name__ == "__main__":
    main()
