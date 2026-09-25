"""Curated raid list for WoW: Forever.

Same shape as dungeons.py, plus:
  size      players
  status    "new" (new in Forever), "forever" (a Classic raid that is in Forever) or
            "classic" (a Classic raid Forever hasn't announced)
  map       instance map id (for recording your own loot)
  objects   on a boss: loot containers credited to it (e.g. Majordomo's chest)

Sources (checked 2026-09-25):
  Forever raids: Wowhead "Forever Raids Overview" guide (raids, sizes, Dec 9 unlock) and
  Blizzard Watch "Who are the raid bosses of World of Warcraft: Forever?" (datamined boss
  names, matched by wowclassicforever.info). No loot is announced for the new raids yet.
  Classic raids: boss lists and loot from Wowhead Classic; Forever still has these zones.
"""

from dungeons import w

SUMMON = "Summoned"

RAIDS = [
    # ---------------------------------------------------------------- Forever (unlock Dec 9, 2026)
    dict(key="BARROW", name="The Barrow Deeps", zones=[], size=10, status="new", levels=(60, 60),
         location="Mount Hyjal, plus two other entrances", aliases=["Barrow Deeps"],
         bosses=["Deepscar Matriarch", "Elder Tangleclaw", "Khalith the Dreadspinner", "Well of Sorrow", "Amethrax",
                 "Del'lynar Songwood", "Ravus and Darlissa", "Sonya Darkhallow"]),
    dict(key="HYJAL", name="Hyjal Summit", zones=[], size=20, status="new", levels=(60, 60),
         location="Mount Hyjal",
         bosses=["Bandalar", "Ancient of Decay", "Time-Lost Battalion", "Sylvestris Dusksong", "Old Gloomlurker",
                 "Gharalis the Abyssal", "Kathris the Haunted", "Anara Chillwind", "Elder Minderel",
                 "Tracker Stillwind", "Council of Thorns", "Nythus the Dreadmbound", "The Wild King"]),
    dict(key="ONY", name="Onyxia's Lair", zones=[2159], map=249, size=40, status="forever", levels=(60, 60),
         location="Dustwallow Marsh",
         bosses=[dict(name="Onyxia", npc=[10184, 268401], aliases=["Onyxia Prime"])]),

    # ---------------------------------------------------------------- Classic raids
    dict(key="MC", name="Molten Core", zones=[2717], map=409, size=40, status="classic", levels=(60, 60),
         location="Blackrock Mountain",
         bosses=["Lucifron", "Magmadar", "Gehennas", "Garr", "Shazzrah", "Baron Geddon", "Golemagg the Incinerator",
                 "Sulfuron Harbinger", dict(name="Majordomo Executus", objects=["Cache of the Firelord"]),
                 "Ragnaros"]),
    dict(key="BWL", name="Blackwing Lair", zones=[2677], map=469, size=40, status="classic", levels=(60, 60),
         location="Blackrock Mountain",
         bosses=["Razorgore the Untamed", "Vaelastrasz the Corrupt", "Broodlord Lashlayer", "Firemaw", "Ebonroc",
                 "Flamegor", "Chromaggus", "Nefarian"]),
    dict(key="ZG", name="Zul'Gurub", zones=[1977], map=309, size=20, status="classic", levels=(60, 60),
         location="Stranglethorn Vale",
         bosses=["High Priestess Jeklik", "High Priest Venoxis", "High Priestess Mar'li", "Bloodlord Mandokir",
                 dict(name="Edge of Madness", tag="One of four", aliases=["Gri'lek", "Hazza'rah", "Renataki", "Wushoolay"]),
                 dict(name="Gahz'ranka", tag=SUMMON), "High Priest Thekal", "High Priestess Arlokk",
                 "Jin'do the Hexxer", "Hakkar"]),
    dict(key="AQ20", name="Ruins of Ahn'Qiraj", zones=[3429], map=509, size=20, status="classic", levels=(60, 60),
         location="Silithus",
         bosses=["Kurinnaxx", "General Rajaxx", "Moam", "Buru the Gorger", "Ayamiss the Hunter",
                 "Ossirian the Unscarred"]),
    dict(key="AQ40", name="Temple of Ahn'Qiraj", zones=[3428], map=531, size=40, status="classic", levels=(60, 60),
         location="Silithus", aliases=["Ahn'Qiraj"],
         bosses=["The Prophet Skeram",
                 dict(name="Silithid Royalty", aliases=["Lord Kri", "Princess Yauj", "Vem"]),
                 "Battleguard Sartura", "Fankriss the Unyielding", "Viscidus", "Princess Huhuran",
                 dict(name="Twin Emperors", aliases=["Emperor Vek'lor", "Emperor Vek'nilash"]),
                 "Ouro", "C'Thun"]),
    dict(key="NAXX", name="Naxxramas", zones=[3456], map=533, size=40, status="classic", levels=(60, 60),
         location="Eastern Plaguelands",
         bosses=w("Arachnid Quarter", "Anub'Rekhan", "Grand Widow Faerlina", "Maexxna")
                + w("Plague Quarter", "Noth the Plaguebringer", "Heigan the Unclean", "Loatheb")
                + w("Military Quarter", "Instructor Razuvious", "Gothik the Harvester",
                    dict(name="The Four Horsemen", objects=["Four Horsemen Chest"],
                         aliases=["Thane Korth'azz", "Lady Blaumeux", "Highlord Mograine", "Sir Zeliek"]))
                + w("Construct Quarter", "Patchwerk", "Grobbulus", "Gluth", "Thaddius")
                + w("Frostwyrm Lair", "Sapphiron", "Kel'Thuzad")),
]
