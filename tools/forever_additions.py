"""Forever drops documented outside the structured Wowhead and wowtbc.gg data.

ADDITIONS: confirmed boss drops (checked 2026-09-23)
  HOT    Wowhead guide "The Hall of Thanes Dungeon Overview Guide" (loot tabs), matching
         the boss/loot table comment by Sammyx3 on wowhead.com zone=16919
  ROL    Boss/loot table comment by Sammyx3 on wowhead.com zone=16611 (2026-09-22)
  DM     Wowhead news "WoW: Forever Introduces New Item Sets" (First Mate Band, Mr. Smite)
  RFC    Mobalytics "Rage Fire Chasm - Bosses, Loot & Quests" (Satyrskin Cloak, Bazzalan)

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
}

# dungeon key -> [(item id, boss the name points at or None)]
UNCONFIRMED = {
    "DM": [(273102, "Cookie")],                                   # Blueprint: Cookie's Feast
    "STOCKS": [(273807, None), (273811, None), (273817, None), (273819, None), (273820, None)],
    "BFD": [(273839, "Ghamoo-ra"), (273840, "Gelihast"), (273841, "Twilight Lord Kelris"),
            (273842, None), (273843, None)],
    "GNOMER": [(274042, None), (274043, None)],
    "RFK": [(274149, None), (274152, "Roogug"), (274155, None), (274158, None), (274161, None)],
    "SM": [(274290, None), (274291, None), (274292, "Houndmaster Loksey"), (274293, None), (274295, None)],
    "RFD": [(274380, None), (274381, "Amnennar the Coldbringer")],
    "ZF": [(274638, None), (274639, None), (274641, "Theka the Martyr"), (274642, None), (274643, None),
           (274644, None), (274645, None), (274647, None), (274648, None), (274651, None),
           (274652, "Hydromancer Velratha"), (274653, None), (274655, None), (274657, "Gahz'rilla"),
           (274658, None)],
}

# Raids. The Barrow Deeps shards are unique, bind-on-pickup and named after its bosses;
# Wowhead has them datamined (ids 277172-277179), with no source yet.
UNCONFIRMED["BARROW"] = [(277172, None), (277174, "Khalith the Dreadspinner"), (277175, "Elder Tangleclaw"),
                         (277178, "Well of Sorrow"), (277179, "Amethrax")]

RAID_DEC9 = "Unlocks Dec 9, 2026. Boss names are datamined; Blizzard hasn't shown any loot yet."
CLASSIC_RAID = "Classic raid. Forever hasn't announced it yet (as of Sep 2026), so this is its Classic loot from Wowhead Classic."

LATER_BETA = "Opens in the level 30 beta phase. No site has boss or loot data yet."
AT_LAUNCH = "Opens at launch (Nov 4). No site has boss or loot data yet."

NOTES = {
    "HOT": "Loot from Wowhead's Hall of Thanes guide and wowtbc.gg. Anything else you loot gets added here.",
    "ROL": "Loot from Wowhead community reports and wowtbc.gg. Anything else you loot gets added here.",
    "EXC": LATER_BETA,
    "DAL": LATER_BETA,
    "DROWN": AT_LAUNCH,
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
