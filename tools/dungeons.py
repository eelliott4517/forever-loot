"""Curated dungeon list for WoW: Forever.

Boss names must match Wowhead NPC names exactly; build_data.py resolves them to
NPC ids and loot from the scraped Wowhead zone data. A boss entry is either a
name string or a dict with optional keys: tag (shown on the boss bar), wing
(section header), npc (explicit ids), aliases (other Wowhead names to merge).

Level ranges come from Wowhead's Forever zone database, except the new Forever
dungeons, which Wowhead's database lists as 0-0, so those use Wowhead's
"Dungeons Overview for Forever" guide. Wing ranges (and Dire Maul, which Wowhead
lists as 44-54) come from wowtbc.gg's Forever loot tables.

tbc maps a dungeon to its wowtbc.gg loot-table page(s): {slug: wing or None}. The new dungeons'
pages are empty until players find their loot; refresh.py fetches them anyway, and any bosses
and drops wowtbc.gg adds show up on the next build.
"""

RARE = "Rare spawn"
SUMMON = "Summoned"
SCOURGE = "Scourge Invasion event"


def w(wing, *bosses):
    out = []
    for b in bosses:
        b = dict(name=b) if isinstance(b, str) else dict(b)
        b["wing"] = wing
        out.append(b)
    return out


DUNGEONS = [
    # ---------------------------------------------------------------- new in Forever
    dict(key="HOT", name="The Hall of Thanes", zones=[16919], new=True, levels=(13, 18),
         location="Ironforge", territory="Alliance", aliases=["Hall of Thanes"],
         tbc={"hall-of-thanes": None},
         bosses=[
             dict(name="Faldrim Anvilmar", npc=[261306]),
             dict(name="Magmatus", npc=[261316]),
             dict(name="Plunder", npc=[261311]),
             dict(name="Durgen Dirgehammer", npc=[261319]),
         ]),
    dict(key="ROL", name="Ruins of Lordaeron", zones=[16611], new=True, levels=(15, 20),
         location="Tirisfal Glades", territory="Horde", aliases=["Lordaeron"],
         tbc={"ruins-of-lordaeron": None},
         bosses=[
             dict(name="Witherfang", npc=[250483]),
             dict(name="The Baron", npc=[250660]),
             dict(name="Viktor the Vile", npc=[256035], tag="Event boss"),
             dict(name="The Abandoned", npc=[250631], tag="Event boss"),
             dict(name="Bjork", npc=[256097]),
             dict(name="Rath'mael", npc=[250657]),
             dict(name="Lordaeron Captain", npc=[255699], tag=RARE),
         ]),
    dict(key="EXC", name="Excavation Site: Wetlands", zones=[16732], new=True, levels=(24, 29), tbc={"excavation-site-wetlands": None},
         location="Wetlands", territory="Contested", aliases=["Excavation Site", "Whelgar's Excavation Site"],
         bosses=[]),
    dict(key="DAL", name="City of Dalaran", zones=[16544, 16560], new=True, levels=(28, 33), tbc={"city-of-dalaran": None},
         location="Alterac Mountains", territory="Contested", aliases=["Dalaran"], bosses=[]),
    dict(key="DROWN", name="The Drowned City", zones=[], new=True, levels=(35, 40), tbc={"the-drowned-city": None},
         location="Stranglethorn Vale coast", territory="Contested", bosses=[]),
    dict(key="KROL", name="Krol'dok Stronghold", zones=[], new=True, levels=(40, 45), tbc={"krol-dok-stronghold": None},
         location="Riverglades", territory="Contested", bosses=[]),
    dict(key="ALCAZ", name="Alcaz Prison", zones=[], new=True, levels=(48, 53), tbc={"alcaz-prison": None},
         location="Alcaz Island, Dustwallow Marsh", territory="Contested", bosses=[]),
    dict(key="BMH", name="Blackmaw Hold", zones=[], new=True, levels=(55, 60), tbc={"blackmaw-hold": None},
         location="Northern Azshara", territory="Contested", bosses=[]),
    dict(key="SHAPER", name="Shaper's Terrace", zones=[], new=True, levels=(58, 60), tbc={"shaper-s-terrace": None},
         location="Un'Goro Crater", territory="Contested", aliases=["The Shapers Terrace", "Shapers Terrace"],
         bosses=[]),

    # ---------------------------------------------------------------- original dungeons
    dict(key="RFC", name="Ragefire Chasm", zones=[2437], map=389, tbc={"ragefire-chasm": None}, location="Orgrimmar", territory="Horde",
         bosses=["Oggleflint", "Taragaman the Hungerer", "Jergosh the Invoker", "Bazzalan"]),
    dict(key="DM", name="The Deadmines", zones=[1581], map=36, tbc={"the-deadmines": None}, location="Westfall", territory="Alliance",
         aliases=["Deadmines"],
         bosses=["Rhahk'Zor", dict(name="Miner Johnson", tag=RARE), "Sneed's Shredder", "Sneed", "Gilnid",
                 "Mr. Smite", "Captain Greenskin", "Edwin VanCleef", "Cookie"]),
    dict(key="WC", name="Wailing Caverns", zones=[718], map=43, tbc={"wailing-caverns": None}, location="The Barrens", territory="Horde",
         bosses=["Lady Anacondra", "Lord Cobrahn", "Kresh", "Lord Pythas", "Skum", "Lord Serpentis",
                 "Verdan the Everliving", "Mutanus the Devourer", dict(name="Deviate Faerie Dragon", tag=RARE)]),
    dict(key="SFK", name="Shadowfang Keep", zones=[209], map=33, tbc={"shadowfang-keep": None}, location="Silverpine Forest", territory="Horde",
         bosses=["Rethilgore", "Razorclaw the Butcher", "Baron Silverlaine", "Commander Springvale",
                 "Odo the Blindwatcher", dict(name="Deathsworn Captain", tag=RARE), "Fenrus the Devourer",
                 "Wolf Master Nandos", "Archmage Arugal", dict(name="Sever", tag=SCOURGE)]),
    dict(key="BFD", name="Blackfathom Deeps", zones=[719], map=48, tbc={"blackfathom-deeps": None}, location="Ashenvale", territory="Contested",
         bosses=["Ghamoo-ra", "Lady Sarevess", "Gelihast", "Lorgus Jett", "Baron Aquanis",
                 "Twilight Lord Kelris", "Old Serra'kis", "Aku'mai"]),
    dict(key="STOCKS", name="The Stockade", zones=[717], map=34, tbc={"the-stockade": None}, location="Stormwind City", territory="Alliance",
         aliases=["Stormwind Stockade", "Stockade"],
         bosses=["Targorr the Dread", "Kam Deepfury", "Hamhock", "Bazil Thredd", "Dextren Ward",
                 dict(name="Bruegal Ironknuckle", tag=RARE)]),
    dict(key="GNOMER", name="Gnomeregan", zones=[721], map=90, tbc={"gnomeregan": None}, location="Dun Morogh", territory="Alliance",
         bosses=["Grubbis", "Viscous Fallout", "Electrocutioner 6000", "Crowd Pummeler 9-60",
                 dict(name="Dark Iron Ambassador", tag=RARE), "Mekgineer Thermaplugg"]),
    dict(key="SM", name="Scarlet Monastery", zones=[796], map=189,
         tbc={"scarlet-monastery-graveyard": "Graveyard", "scarlet-monastery-library": "Library",
              "scarlet-monastery-armory": "Armory", "scarlet-monastery-cathedral": "Cathedral"},
         wings={"Graveyard": (26, 36), "Library": (29, 39), "Armory": (32, 42), "Cathedral": (35, 45)}, location="Tirisfal Glades", territory="Horde",
         bosses=w("Graveyard", "Interrogator Vishas", "Bloodmage Thalnos",
                  dict(name="Azshir the Sleepless", tag=RARE), dict(name="Fallen Champion", tag=RARE),
                  dict(name="Ironspine", tag=RARE))
                + w("Library", "Houndmaster Loksey", "Arcanist Doan")
                + w("Armory", "Herod")
                + w("Cathedral", "High Inquisitor Fairbanks", "Scarlet Commander Mograine",
                    "High Inquisitor Whitemane")
                + [dict(name="Scorn", tag=SCOURGE, wing="Event bosses")]),
    dict(key="RFK", name="Razorfen Kraul", zones=[491], map=47, tbc={"razorfen-kraul": None}, location="The Barrens", territory="Horde",
         bosses=["Roogug", "Aggem Thorncurse", "Death Speaker Jargba", "Overlord Ramtusk",
                 "Agathelos the Raging", dict(name="Blind Hunter", tag=RARE), "Charlga Razorflank",
                 dict(name="Earthcaller Halmgar", tag=RARE)]),
    dict(key="RFD", name="Razorfen Downs", zones=[722], map=129, tbc={"razorfen-downs": None}, location="The Barrens", territory="Horde",
         bosses=["Tuten'kash", "Plaguemaw the Rotting", "Mordresh Fire Eye", "Glutton",
                 dict(name="Ragglesnout", tag=RARE), "Amnennar the Coldbringer",
                 dict(name="Lady Falther'ess", tag=SCOURGE)]),
    dict(key="ULDA", name="Uldaman", zones=[1337], map=70, tbc={"uldaman": None}, location="Badlands", territory="Contested",
         bosses=["Revelosh", "Baelog", "Olaf", 'Eric "The Swift"', "Ironaya", "Obsidian Sentinel",
                 "Ancient Stone Keeper", "Galgann Firehammer", "Grimlok", "Archaedas"]),
    dict(key="MARA", name="Maraudon", zones=[2100], map=349, tbc={"maraudon": None}, location="Desolace", territory="Contested",
         bosses=["Noxxion", "Razorlash", "Lord Vyletongue", dict(name="Meshlok the Harvester", tag=RARE),
                 "Celebras the Cursed", "Landslide", "Tinkerer Gizlock", "Rotgrip", "Princess Theradras"]),
    dict(key="ZF", name="Zul'Farrak", zones=[1176], map=209, tbc={"zul-farrak": None}, location="Tanaris", territory="Contested",
         bosses=["Antu'sul", "Theka the Martyr", "Witch Doctor Zum'rah", "Nekrum Gutchewer",
                 "Shadowpriest Sezz'ziz", "Sergeant Bly", "Hydromancer Velratha", "Gahz'rilla",
                 "Chief Ukorz Sandscalp", "Ruuzlu", dict(name="Zerillis", tag=RARE),
                 dict(name="Dustwraith", tag=RARE), dict(name="Sandarr Dunereaver", tag=RARE)]),
    dict(key="DIRE", name="Dire Maul", zones=[2557], map=429, levels=(55, 60),
         tbc={"dire-maul-east": "East", "dire-maul-west": "West", "dire-maul-north": "North"},
         wings={"East": (55, 60), "West": (56, 60), "North": (57, 60)}, location="Feralas", territory="Contested",
         bosses=w("East", "Pusillin", "Zevrim Thornhoof", "Hydrospawn", "Lethtendris", "Alzzin the Wildshaper",
                  dict(name="Isalien", tag=SUMMON))
                + w("West", "Tendris Warpwood", "Illyanna Ravenoak", "Magister Kalendris",
                    dict(name="Tsu'zee", tag=RARE), "Immol'thar", dict(name="Lord Hel'nurath", tag=SUMMON),
                    "Prince Tortheldrin")
                + w("North", "Guard Mol'dar", "Stomper Kreeg", "Guard Fengus", "Guard Slip'kik",
                    "Captain Kromcrush", "Cho'Rush the Observer", "King Gordok",
                    dict(name="Mizzle the Crafty", tag="Tribute chest"))
                + [dict(name="Revanchion", tag=SCOURGE, wing="Event bosses")]),
    dict(key="STRAT", name="Stratholme", zones=[2017], map=329, tbc={"stratholme": None}, location="Eastern Plaguelands", territory="Contested",
         bosses=w("Main Gate", dict(name="Skul", tag=RARE), "Stratholme Courier", "Fras Siabi",
                  dict(name="Hearthsinger Forresten", tag=RARE), "The Unforgiven", "Timmy the Cruel",
                  "Malor the Zealous", "Crimson Hammersmith", "Cannon Master Willey", "Archivist Galford",
                  dict(name="Balnazzar", aliases=["Grand Crusader Dathrohan"]), dict(name="Sothos", tag=SUMMON, aliases=["Jarien"]), "Postmaster Malown")
                + w("Service Entrance", "Magistrate Barthilas", dict(name="Stonespine", tag=RARE),
                    "Baroness Anastari", "Black Guard Swordsmith", "Nerub'enkan", "Maleki the Pallid",
                    "Ramstein the Gorger", "Baron Rivendare")
                + [dict(name="Balzaphon", tag=SCOURGE, wing="Event bosses")]),
    dict(key="ST", name="The Temple of Atal'Hakkar", zones=[1477, 1417], map=109, tbc={"the-temple-of-atal-hakkar": None}, location="Swamp of Sorrows",
         territory="Contested", aliases=["Sunken Temple", "Temple of Atal'Hakkar"],
         bosses=["Atal'alarion", "Spawn of Hakkar",
                 dict(name="Atal'ai Troll Guardians", aliases=["Gasher", "Loro", "Hukku", "Zolo", "Mijan", "Zul'Lor"]),
                 "Dreamscythe", "Weaver", "Jammal'an the Prophet", "Ogom the Wretched", "Morphaz", "Hazzas",
                 dict(name="Avatar of Hakkar", aliases=["Shade of Hakkar"]), "Shade of Eranikus"]),
    dict(key="BRD", name="Blackrock Depths", zones=[1584, 17803], map=230, tbc={"blackrock-depths": None}, location="Blackrock Mountain",
         territory="Contested",
         bosses=["Lord Roccor", "High Interrogator Gerstahn", "Houndmaster Grebmar",
                 dict(name="Ring of Law", aliases=["Anub'shiah", "Eviscerator", "Gorosh the Dervish", "Grizzle",
                                                   "Hedrum the Creeper", "Ok'thor the Breaker"]),
                 "Pyromancer Loregrain", "Warder Stilgiss", "Verek", "Fineous Darkvire", "Lord Incendius",
                 "Bael'Gar", "General Angerforge", "Golem Lord Argelmach", "Hurley Blackbreath",
                 "Ribbly Screwspigot", "Plugger Spazzring", "Phalanx", "Ambassador Flamelash",
                 dict(name="The Seven", aliases=["Doom'rel", "Anger'rel", "Seeth'rel", "Dope'rel", "Gloom'rel",
                                                 "Vile'rel", "Hate'rel"]),
                 "Magmus", "Princess Moira Bronzebeard", "Emperor Dagran Thaurissan",
                 dict(name="Panzor the Invincible", tag=RARE), "Watchman Doomgrip"]),
    dict(key="BRS", name="Blackrock Spire", zones=[1583, 17804], map=229,
         tbc={"blackrock-spire-lower": "Lower Spire", "blackrock-spire-upper": "Upper Spire"},
         wings={"Lower Spire": (55, 60), "Upper Spire": (58, 60)}, location="Blackrock Mountain",
         territory="Contested", aliases=["Lower Blackrock Spire", "Upper Blackrock Spire"],
         bosses=w("Lower Spire", "Highlord Omokk", "Shadow Hunter Vosh'gajin", "War Master Voone",
                  "Mother Smolderweb", "Urok Doomhowl", "Quartermaster Zigris", "Halycon", "Gizrul the Slavener",
                  "Overlord Wyrmthalak", dict(name="Mor Grayhoof", tag=SUMMON), dict(name="Spirestone Butcher", tag=RARE),
                  dict(name="Spirestone Battle Lord", tag=RARE), dict(name="Spirestone Lord Magus", tag=RARE),
                  dict(name="Bannok Grimaxe", tag=RARE), dict(name="Crystal Fang", tag=RARE),
                  dict(name="Ghok Bashguud", tag=RARE), dict(name="Burning Felguard", tag=RARE))
                + w("Upper Spire", "Pyroguard Emberseer", "Solakar Flamewreath",
                    dict(name="Jed Runewatcher", tag=RARE), "Goraluk Anvilcrack", "Warchief Rend Blackhand",
                    "Gyth", "The Beast", dict(name="Lord Valthalak", tag=SUMMON), "General Drakkisath")),
    dict(key="SCHOLO", name="Scholomance", zones=[2057], map=289, tbc={"scholomance": None}, location="Western Plaguelands",
         territory="Contested",
         bosses=["Kirtonos the Herald", "Jandice Barov", "Rattlegore", "Marduk Blackpool", "Vectus",
                 "Ras Frostwhisper", "Instructor Malicia", "Doctor Theolen Krastinov", "Lorekeeper Polkelt",
                 "The Ravenian", "Lord Alexei Barov", "Lady Illucia Barov", "Darkmaster Gandling",
                 dict(name="Death Knight Darkreaver", tag=SUMMON), dict(name="Kormok", tag=SUMMON),
                 dict(name="Lord Blackwood", tag=SCOURGE)]),
]
