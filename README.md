# Forever Loot

A WoW: Forever addon with dungeon and raid loot tables, profession recipes, a search across all of them, and a wishlist of gear to chase.

- Click the minimap button (or type `/fl`) to open it. The tabs across the top are Dungeons, Raids, Professions and Wishlist.
- **Dungeons** are sorted by level. A red bar marks dungeons at your level, and NEW marks dungeons added in Forever.
- **Raids** has Forever's new raids (The Barrow Deeps and Hyjal Summit), Onyxia's Lair, and the Classic raids: Molten Core, Blackwing Lair, Zul'Gurub, Ruins and Temple of Ahn'Qiraj, and Naxxramas. The list shows each raid's size. NEW marks Forever's new raids, and CLASSIC marks Classic raids Forever hasn't announced.
- Click a dungeon or raid to see its bosses, with each boss's drops underneath.
- Hover an item for its tooltip. Shift-click links it in chat, Ctrl-click previews it, right-click puts it on your wishlist, and a plain click gives you a copyable Wowhead link. The boss bars and the Wowhead button do the same for bosses and dungeons.

## Where the data comes from

WoW addons can't go online, so the loot data is bundled in `ForeverLoot/Data.lua` (pulled 2026-09-23) from three sites:

1. **Wowhead**: Forever and Classic drop tables, Forever level ranges, the Hall of Thanes guide, a Ruins of Lordaeron boss/loot comment, and the First Mate Band news post.
2. **wowtbc.gg**: Forever loot tables for every original dungeon. These have the Classic Era boss tables, the new Forever drops players have found so far, and Classic drop chances. The wing level ranges (Scarlet Monastery, Dire Maul, Blackrock Spire) also come from here.
3. **Mobalytics**: one extra Ragefire Chasm drop (Satyrskin Cloak, Bazzalan).

Every item is checked against Wowhead's Forever database, and the item rows are tagged to match:

- **NEW**: added in Forever. Items in the "New in Forever, boss not confirmed" section are datamined on Wowhead but no site has tied them to a boss yet. They're grouped by the block of item IDs Blizzard used for that dungeon, and the tooltip names a boss when the item's name points to one.
- **CLASSIC**: Classic loot that isn't in Forever's game data, so Forever may have replaced it. These use the bundled Classic icon and stats, and link to Wowhead Classic.
- **SEEN**: recorded from your own loot (see below).
- No tag: Classic loot that's still in Forever. The percentage is its Classic drop chance.

Every item's stats are bundled from Wowhead too (Forever stats where Wowhead has them, Classic stats otherwise). The beta server doesn't send data for many dungeon items, so the addon shows the bundled stats until the game provides its own, then switches to the game's tooltip.

### Raids (pulled 2026-09-25)

- **The Barrow Deeps** (10 players), **Hyjal Summit** (20) and **Onyxia's Lair** (40) unlock on December 9, 2026. The two new raids' boss names are datamined (Blizzard Watch, matching wowclassicforever.info), and nobody has published their loot yet. The Barrow Deeps lists five datamined shards named after its bosses.
- **Onyxia's Lair** shows Onyxia's Classic loot until her Forever loot is known.
- **The Classic raids** use Wowhead Classic's drop tables plus each boss's page, which gives drop chances from recorded kills. Chest loot is credited to its boss (Majordomo Executus and the Four Horsemen). The random world blues that Onyxia, Ragnaros and Nefarian also roll are left out.
- Items Forever's game data doesn't have are tagged CLASSIC, as with dungeons. A few say Wowhead only has Season of Discovery's version of their stats.

Only the dungeons reachable at the beta's level cap have confirmed new drops so far. The ones that open later (Excavation Site, Dalaran, and everything past level 30) have no loot data on any site yet.

To fill gaps, the addon records any rare-or-better item you loot from a dungeon or raid boss and shows it under that boss with a SEEN badge. Bosses it doesn't know yet are picked up from the boss-kill event and listed under "Recorded by you". `/fl forget` clears this.

## Commands

| Command | What it does |
| --- | --- |
| `/fl` | Open or close the window |
| `/fl dungeons`, `/fl raids`, `/fl professions`, `/fl wishlist` | Open that tab |
| `/fl gloves` | Search the open tab for an item, slot, type, stat or material |
| `/fl minimap` | Show or hide the minimap button |
| `/fl reset` | Reset the window and minimap button positions |
| `/fl forget` | Clear drops recorded from your own loot |

## Development

```
ForeverLoot/        the addon (Data.lua is generated)
tools/dungeons.py   curated dungeon + boss list
tools/raids.py      curated raid + boss list (sizes, Forever status, chests credited to bosses)
tools/forever_additions.py  Forever drops documented on Wowhead and Mobalytics, plus datamined new items
tools/build_data.py builds Data.lua from tools/raw/ and verifies items with Wowhead's Forever tooltip API
tools/scrape_console.js  refreshes tools/raw/scrape.json from your browser (Wowhead blocks scripted clients)
tools/raw/raid_zones.json, raid_npcs.json  Wowhead raid zone pages and boss/chest pages (scraped in a browser)
tools/raw/wowtbc/   wowtbc.gg page data (https://wowtbc.gg/page-data/warcraftforever/loot-tables/dungeons/<slug>/page-data.json)
tools/package.py    builds dist/ForeverLoot-<version>.zip (CurseForge: only the addon folder at the top level)
                    and dist/ForeverLoot-<version>-Windows-installer.zip (addon + double-click installer)
tools/test/         Lua 5.1 lint and a smoke test that runs the addon against a strict WoW API mock
ForeverLoot/ProfessionData.lua  generated by 1.4.0's tools/build_professions.py, which isn't in this folder
tools/install.sh    copies the addon into the Forever beta's AddOns folder
```

Rebuild and install:

```
python3 tools/build_data.py && sh tools/install.sh
```

Tests need `luaparse` and `fengari` from npm:

```
node tools/test/lint.js ForeverLoot && node tools/test/run.js ForeverLoot
```
