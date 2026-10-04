Forever Loot {VERSION}
Dungeon and raid loot tables, quests, item sets, profession recipes and a wishlist for WoW: Forever,
built from Wowhead's data.

INSTALL
1. Extract this whole zip somewhere (right-click it, then "Extract All").
2. Double-click Install-ForeverLoot.bat. It finds your WoW folder and copies the addon into
   _classic_beta_\Interface\AddOns. If Windows warns about the file, click "More info",
   then "Run anyway". If it can't find WoW, it asks you to paste the folder path.

Or install it by hand: copy the ForeverLoot folder into
   C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns\
(use your own WoW folder if it's somewhere else, and create Interface\AddOns if it's missing).

Then restart WoW. A /reload won't pick up a new addon. If the AddOns list marks it as
out of date, tick "Load out of date AddOns".

USING IT
- Click the minimap button, or type /fl. The tabs down the right edge are Dungeons, Raids,
  Quests, Sets, Professions and Wishlist.
- Everything starts collapsed: click a header to open it, shift-click to open or close them all.
- Click a dungeon or raid on the left to see its bosses, then click a boss for its drops
  (right-click it for its Wowhead link). Its quests are in the Quests section at the bottom.
- The Quests tab shows every dungeon and raid quest: where it starts, the quests you need to do
  first, and a map pin button for each quest giver. Its first page lists what you can do now.
- Tick "My class" under the search box to see only gear your class can use, and
  "Hide Classic" to hide Classic loot that isn't in Forever.
- Every item tooltip in the game shows where the item drops, which quest gives it and which
  profession makes it. /fl tooltip turns that off.
- Hover an item for its tooltip. Shift-click links it in chat, Ctrl-click previews it,
  right-click puts it on your wishlist, and a plain click gives you a Wowhead link to copy.
- Commands: /fl raids (or dungeons, quests, sets, professions, wishlist), /fl gloves (search),
  /fl minimap (show or hide the button), /fl reset (reset positions),
  /fl forget (clear drops recorded from your own loot).

ABOUT THE DATA
WoW addons can't go online, so the loot data is bundled (pulled {DATE}) from Wowhead,
wowtbc.gg and Mobalytics. Item tags:
  New      added in Forever (a "boss not confirmed" section lists datamined ones)
  Classic  Classic loot that isn't in Forever's game data, so it may have been replaced
  Seen     recorded from your own loot: the addon remembers any blue-or-better item
           you loot from a dungeon or raid boss
