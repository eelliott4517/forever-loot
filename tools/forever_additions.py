"""Forever drops documented outside the structured Wowhead and wowtbc.gg data.

ADDITIONS: confirmed boss drops (checked 2026-09-23)
  HOT    Wowhead guide "The Hall of Thanes Dungeon Overview Guide" (loot tabs), matching
         the boss/loot table comment by Sammyx3 on wowhead.com zone=16919
  ROL    Boss/loot table comment by Sammyx3 on wowhead.com zone=16611 (2026-09-22)
  DM     Wowhead news "WoW: Forever Introduces New Item Sets" (First Mate Band, Mr. Smite)
  RFC    Mobalytics "Rage Fire Chasm - Bosses, Loot & Quests" (Satyrskin Cloak, Bazzalan)
  STOCKS Mobalytics "The Stockade Dungeon Guide" (Nightskulker Ring, Targorr; Repurposed Rack, Hamhock)

UNCONFIRMED: new Forever items that no site has tied to a boss yet. Wowhead's Forever
database has them (datamined from the client), and Blizzard created each dungeon's new
items as a block of consecutive ids next to the confirmed drops. Items are grouped by
those blocks; the optional hint is a boss the item's name points at.
"""

WOWHEAD, MOBA = "Wowhead", "Mobalytics"

ADDITIONS = {
    "HOT": [
        dict(boss="Faldrim Anvilmar", items=[271097, 270227, 271096], source=WOWHEAD),
        dict(boss="Magmatus", items=[270230, 270231, 271095], source=WOWHEAD),
        dict(boss="Plunder", items=[270228, 271098, 270229], source=WOWHEAD),
        dict(boss="Durgen Dirgehammer", items=[270256, 270260, 270261], source=WOWHEAD),
    ],
    "ROL": [
        dict(boss="Witherfang", items=[271201, 271202, 271203], source=WOWHEAD),
        dict(boss="The Baron", items=[271204, 271205, 271206], source=WOWHEAD),
        dict(boss="Viktor the Vile", items=[271211, 271212, 271218], source=WOWHEAD),
        dict(boss="The Abandoned", items=[271207, 271208, 271216], source=WOWHEAD),
        dict(boss="Bjork", items=[271209, 271210, 271217], source=WOWHEAD),
        dict(boss="Rath'mael", items=[271213, 271214, 271215], source=WOWHEAD),
        dict(boss="Lordaeron Captain", items=[6641, 6642], source=WOWHEAD),
    ],
    "DM": [
        dict(boss="Mr. Smite", items=[284715], source=WOWHEAD),
    ],
    "RFC": [
        dict(boss="Bazzalan", items=[273005], source=MOBA),
    ],
    # Mobalytics "The Stockade Dungeon Guide" (2026-09-29): two of the datamined Stockade items
    "STOCKS": [
        dict(boss="Targorr the Dread", items=[273820], source=MOBA),   # Nightskulker Ring
        dict(boss="Hamhock", items=[273811], source=MOBA),             # Repurposed Rack
    ],
}

# dungeon key -> [(item id, boss the name points at or None)]
UNCONFIRMED = {
    # (wowtbc.gg confirmed RFK's 274149, 274155 and 274161 and SM's 274290, 274291 and 274293 by 2026-10-04,
    # and Gnomeregan's 274042 and 274043 (Grubbis) and SM's 274292 (Houndmaster Loksey) by 2026-10-08)
    "SM": [(274295, None)],
    "RFD": [(274380, None), (274381, "Amnennar the Coldbringer")],
    "ZF": [(274638, None), (274639, None), (274641, "Theka the Martyr"), (274642, None), (274643, None),
           (274644, None), (274645, None), (274647, None), (274648, None), (274651, None),
           (274652, "Hydromancer Velratha"), (274653, None), (274655, None), (274657, "Gahz'rilla"),
           (274658, None)],
}

# Quests Wowhead files under an instance that no one can get in Forever, which the build can't tell
# by itself: Season of Discovery quests left in Forever's data with their giver, objectives and
# rewards stripped. Wowhead marks them "updated" rather than "unconfirmed", and their pages still
# name where they were turned in.
LEFTOVER_QUESTS = {
    78916: "The Heart of the Void",   # Season of Discovery's Blackfathom Deeps raid quest (Alliance)
    78917: "The Heart of the Void",   # and its Horde copy
}

# Raids. The Barrow Deeps shards are unique, bind-on-pickup and named after its bosses;
# Wowhead has them datamined (ids 277172-277179), with no source yet.
UNCONFIRMED["BARROW"] = [(277172, None), (277174, "Khalith the Dreadspinner"), (277175, "Elder Tangleclaw"),
                         (277178, "Well of Sorrow"), (277179, "Amethrax")]

RAID_DEC9 = "Unlocks Dec 9, 2026. Boss names are datamined; Blizzard hasn't shown any loot yet."
CLASSIC_RAID = "Classic raid. Forever hasn't announced it yet (as of Sep 2026), so this is its Classic loot from Wowhead Classic."

FROM_SITES = "Loot from wowtbc.gg and Wowhead. Anything else you loot gets added here."
AT_LAUNCH_BOSSES = ("Open since launch (Nov 4). Its boss names come from wowtbc.gg; no site has its loot yet. "
                    "Kill its bosses and loot them to record drops here.")
AT_LAUNCH = ("Open since launch (Nov 4). No site has its bosses or loot yet. "
             "Kill its bosses and loot them to record drops here.")

NOTES = {
    "HOT": "Loot from Wowhead's Hall of Thanes guide and wowtbc.gg. Anything else you loot gets added here.",
    "ROL": "Loot from Wowhead community reports and wowtbc.gg. Anything else you loot gets added here.",
    "EXC": FROM_SITES,
    "DAL": FROM_SITES,
    "DROWN": AT_LAUNCH_BOSSES,
    "KROL": AT_LAUNCH,
    "ALCAZ": AT_LAUNCH,
    "BMH": AT_LAUNCH,
    "SHAPER": AT_LAUNCH,
    "BARROW": RAID_DEC9 + " The shards below are datamined and named after its bosses.",
    "HYJAL": RAID_DEC9,
    "ONY": "In Forever as a 40-player raid, unlocking Dec 9, 2026. Until its Forever loot is known, this is Onyxia's Classic loot.",
    "MC": CLASSIC_RAID, "BWL": CLASSIC_RAID, "ZG": CLASSIC_RAID, "AQ20": CLASSIC_RAID, "AQ40": CLASSIC_RAID,
    "NAXX": CLASSIC_RAID,
}
