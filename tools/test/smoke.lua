-- Smoke test: load ForeverLoot into the WoW mock and drive it like a player would.
dofile(arg_test_dir .. "/wowmock.lua")

local passed, failed = 0, 0
local function check(cond, msg)
	if cond then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. msg) end
end

-- Load files in TOC order, like the client does
local ns = {}
for file in arg_files:gmatch("[^,]+") do
	local chunk, err = loadfile(arg_addon_dir .. "/" .. file)
	assert(chunk, err)
	chunk("ForeverLoot", ns)
end

-- Like the Forever beta: the client knows most removed Classic item ids but the server never
-- sends their data, a few ids it has never heard of, and other items arrive from the server late
MOCK.itemsDB = ns.Items
local n = 0
for id, e in pairs(ns.Items) do
	n = n + 1
	if e[4] == 2 then
		MOCK.serverMissing[id] = true
		if n % 5 == 0 then MOCK.notInClient[id] = true end
	elseif n % 2 == 0 then
		MOCK.cached[id] = true
	end
end

MOCK.Fire("ADDON_LOADED", "SomeOtherAddon")
check(ns.db == nil, "ignores other addons' ADDON_LOADED")
MOCK.Fire("ADDON_LOADED", "ForeverLoot")
check(ns.db == ForeverLootDB and ns.char == ForeverLootCharDB, "saved variables initialised")
MOCK.Fire("PLAYER_LOGIN")
check(_G.ForeverLootMinimapButton ~= nil, "minimap button created")

----------------------------------------------------------------------
-- Data
----------------------------------------------------------------------
local keys = {}
local function CheckInstance(d)
	check(not keys[d.key], "unique key " .. d.key)
	keys[d.key] = true
	check(d.minLevel > 0 and d.maxLevel >= d.minLevel, "level range " .. d.name)
	for _, b in ipairs(d.bosses) do
		for _, id in ipairs(b.loot) do
			local e = ns.Items[id]
			check(e ~= nil and type(e[6]) == "string" and type(e[7]) == "table",
				"bundled item " .. id .. " (" .. d.name .. ": " .. b.name .. ")")
		end
	end
end
for _, d in ipairs(ns.Dungeons) do CheckInstance(d) end
for _, r in ipairs(ns.Raids) do CheckInstance(r) end

local R = ns.DungeonByKey
check(#ns.Raids == 9, "9 raids (" .. #ns.Raids .. ")")
check(R.BARROW and R.BARROW.isNew and R.BARROW.size == 10 and #R.BARROW.bosses >= 8, "The Barrow Deeps")
check(R.HYJAL and R.HYJAL.isNew and R.HYJAL.size == 20 and #R.HYJAL.bosses == 13, "Hyjal Summit")
check(R.ONY and R.ONY.status == "forever" and R.ONY.size == 40 and not R.ONY.isNew, "Onyxia's Lair is in Forever")
for _, k in ipairs({ "MC", "BWL", "ZG", "AQ20", "AQ40", "NAXX" }) do
	check(R[k] and R[k].status == "classic" and R[k].isRaid, "Classic raid " .. k)
end
check(not R.DM.isRaid, "dungeons aren't raids")

local function BossOf(d, name)
	for _, b in ipairs(d.bosses) do if b.name == name then return b end end
end
local function Has(list, id)
	for _, x in ipairs(list) do if x == id then return true end end
end
local rag = BossOf(R.MC, "Ragnaros")
check(rag and Has(rag.loot, 17204), "Eye of Sulfuras drops from Ragnaros")
check(rag and rag.pct and (rag.pct[16901] or 0) > 10, "Ragnaros has drop chances")
local domo = BossOf(R.MC, "Majordomo Executus")
check(domo and Has(domo.loot, 18703), "Majordomo's chest loot (Ancient Petrified Leaf)")
local horse = BossOf(R.NAXX, "The Four Horsemen")
check(horse and Has(horse.loot, 22691), "Four Horsemen chest (Corrupted Ashbringer)")
local ony = BossOf(R.ONY, "Onyxia")
check(ony and Has(ony.loot, 17068), "Onyxia drops Deathbringer")
check(ns.BossByNPC[11502] == rag and rag.dungeon == R.MC, "raid bosses indexed for recorded loot")
local total = 0
for _, r in ipairs(ns.Raids) do
	for _, b in ipairs(r.bosses) do total = total + #b.loot end
end
check(total > 800, "raid loot entries (" .. total .. ")")

----------------------------------------------------------------------
-- The Raids tab
----------------------------------------------------------------------
local UI, K, C = ns.UI, ns.UIKit, ns.COLORS
UI:Toggle()
check(UI.frame:IsShown(), "window opens")
check(table.concat(UI.modeOrder, ",") == "dungeons,raids,professions,wishlist", "tabs: " .. table.concat(UI.modeOrder, ","))
local tabLabels = {}
for _, t in ipairs(UI.tabs) do tabLabels[#tabLabels + 1] = t.label.text end
check(table.concat(tabLabels, ",") == "DUNGEONS,RAIDS,PROFESSIONS,WISHLIST", "tab labels " .. table.concat(tabLabels, ","))

local function Count(kind)
	local c = 0
	for _, e in ipairs(UI.entries) do if e.kind == kind then c = c + 1 end end
	return c
end
local function ShownRows()
	local rows = {}
	for _, row in ipairs(UI.listRows) do if row:IsShown() then rows[#rows + 1] = row end end
	return rows
end
local function RowFor(entry)
	for _, row in ipairs(ShownRows()) do if row.entry == entry then return row end end
end

UI:SetMode("raids")
check(UI.mode == "raids", "Raids tab opens")
check(UI.listLabel.text == "RAIDS" and UI.listRight.text == "PLAYERS", "raid list headings")
local rows = ShownRows()
check(#rows == 9, "one row per raid (" .. #rows .. ")")
check(rows[1] and rows[1].entry == R.BARROW and rows[1].tag.text == "NEW", "Barrow Deeps first, tagged NEW")
check(rows[1] and rows[1].levels.text == "10", "raid size in the list")
local mcRow, onyRow = RowFor(R.MC), RowFor(R.ONY)
check(mcRow and mcRow.tag.text == "CLASSIC", "Classic raids tagged CLASSIC")
check(mcRow and mcRow.tag.tc and math.abs(mcRow.tag.tc[1] - C.mist[1]) < 0.01, "CLASSIC tag is muted, not red")
local hyjalRow = RowFor(R.HYJAL)
check(hyjalRow and not hyjalRow.isSelected and hyjalRow.tag.tc and math.abs(hyjalRow.tag.tc[1] - C.red[1]) < 0.01,
	"NEW tag stays red on a row that isn't selected")
check(onyRow and onyRow.tag.text == "", "Onyxia has no tag (it's in Forever)")
check(mcRow and not mcRow.marker.shown, "no red bar for a level 16 character")

for _, r in ipairs(ns.Raids) do
	UI:Select(r)
	check(UI.current == r and UI.header.name.text == r.name, "select " .. r.name)
	local meta = UI.header.meta.text
	check(meta:find("Level 60", 1, true) and meta:find(r.size .. " players", 1, true), "raid header " .. r.name .. ": " .. meta)
	check(UI.header.note.text ~= "" and UI.header.note.text ~= nil, "raid note " .. r.name)
	if Count("wing") == 0 then
		check(Count("boss") == #r.bosses, ("boss rows %s: %d vs %d"):format(r.name, Count("boss"), #r.bosses))
		local items = 0
		for _, b in ipairs(r.bosses) do items = items + #b.loot end
		check(Count("item") == items, ("item rows %s: %d vs %d"):format(r.name, Count("item"), items))
	end
end

UI:Select(R.NAXX)
check(Count("wing") >= 5 and Count("boss") == 0, "Naxxramas quarters start collapsed")
UI:ToggleSection("d:NAXX:Arachnid Quarter")
check(Count("boss") == 3, "opening a quarter shows its 3 bosses (" .. Count("boss") .. ")")

UI:Select(R.HYJAL)
check(not UI.header.wowhead:IsShown(), "no Wowhead link for a raid Wowhead has no page for")
check(UI.header.badge:IsShown(), "NEW IN FOREVER badge on Hyjal Summit")
check(Count("note") == 13, "each Hyjal boss says it has no drops yet (" .. Count("note") .. ")")
UI:Select(R.MC)
check(UI.header.wowhead:IsShown() and not UI.header.badge:IsShown(), "Molten Core: Wowhead link, no NEW badge")

UI:Select(R.BARROW)
local shard
for _, e in ipairs(UI.entries) do
	if e.kind == "item" and e.data.itemID == 277174 then shard = e.data end
end
check(shard and shard.hint == "Khalith the Dreadspinner", "Barrow Deeps shard points at its boss")

-- A painted Classic-only raid item shows its bundled stats
UI:Select(R.MC)
local row
for i = 1, (UI.used.item or 0) do
	local r = UI.pools.item[i]
	if r:IsShown() and ns.Items[r.itemID][4] == 2 then row = r break end
end
check(row ~= nil, "a Classic-only item painted in Molten Core")
if row then
	GameTooltip.item = nil
	row.scripts.OnEnter(row)
	check(GameTooltip.item == nil and GameTooltip.lines[1] == ns.Items[row.itemID][1], "bundled tooltip for a Classic raid item")
	check(#GameTooltip.lines >= #ns.Items[row.itemID][7] + 1, "with its stat lines")
	row.scripts.OnLeave(row)
end

-- Search the raids
UI:Search("sulfuras")
check(UI:IsSearching() and (UI.searchTotal or 0) > 0, "raid search finds Sulfuras (" .. tostring(UI.searchTotal) .. ")")
local inMC = false
for _, g in ipairs(UI.searchGroups or {}) do if g.entry == R.MC then inMC = true end end
check(inMC, "results grouped under Molten Core")
UI:ClearSearch()
check(not UI:IsSearching(), "search cleared")

-- Wishlist: a raid drop is listed under its raid
UI:ToggleWanted(17204)
check(ns.Wishlist.IsWanted(17204), "raid item goes on the wishlist")
UI:SetMode("wishlist")
check(RowFor(R.MC) ~= nil, "wishlist lists Molten Core as where to get it")
UI:ToggleWanted(17204)

----------------------------------------------------------------------
-- Recording your own loot in raids
----------------------------------------------------------------------
UI:Hide()
MOCK.instance = { "Molten Core", "raid", 9, "40 Player", 40, 0, false, 409 }
MOCK.itemsDB[299002] = { "Test Epic", 4, "Plate Chest" }
MOCK.cached[299002] = true
MOCK.loot = { { link = "|cffa335ee|Hitem:299002::::::::::::|h[Test Epic]|h|r", guid = "Creature-0-1-409-1-11502-00001" } }
MOCK.Fire("LOOT_OPENED")
local bucket = ns.db.learned.MC and ns.db.learned.MC["npc:11502"]
check(bucket and bucket.items[299002] == 1, "loot recorded under Ragnaros")
UI:SetMode("dungeons")
UI:Toggle()
check(UI.mode == "raids" and UI.current == R.MC, "opening inside Molten Core jumps to its raid page")
local seen = false
for _, e in ipairs(UI.entries) do
	if e.kind == "item" and e.data.itemID == 299002 and e.data.learnedCount == 1 then seen = true end
end
check(seen, "recorded raid drop listed under its boss")

MOCK.instance = { "Hyjal Summit", "raid", 9, "20 Player", 20, 0, false, 9100 }
MOCK.Fire("ENCOUNTER_END", 4001, "Bandalar", 9, 20, 1)
MOCK.time = MOCK.time + 10
MOCK.itemsDB[299003] = { "Test Cloak", 4, "Back" }
MOCK.cached[299003] = true
MOCK.loot = { { link = "|cffa335ee|Hitem:299003::::::::::::|h[Test Cloak]|h|r", guid = "Creature-0-1-9100-1-299999-00002" } }
MOCK.Fire("LOOT_OPENED")
local hb = ns.db.learned.HYJAL and ns.db.learned.HYJAL["enc:bandalar"]
check(hb and hb.items[299003] == 1, "Hyjal loot recorded by encounter name")
UI:Select(R.HYJAL)
local under = false
for _, e in ipairs(UI.entries) do
	if e.kind == "item" and e.data.itemID == 299003 then under = true end
end
check(under, "recorded Hyjal drop shows under Bandalar")

----------------------------------------------------------------------
-- The other tabs still work
----------------------------------------------------------------------
UI:SetMode("dungeons")
check(#ShownRows() == #ns.Dungeons, "Dungeons tab lists every dungeon")
for _, d in ipairs(ns.Dungeons) do
	UI:Select(d)
	check(UI.current == d and UI.header.name.text == d.name, "select dungeon " .. d.name)
	check(UI.header.meta.text:find(K.LevelText(d), 1, true) ~= nil, "dungeon levels " .. d.name)
	check(UI.header.wowhead:IsShown() == (d.zone ~= 0), "Wowhead link only with a zone page: " .. d.name)
end
UI:Search("gloves")
check((UI.searchTotal or 0) > 0, "dungeon search still works")
UI:ClearSearch()

UI:SetMode("professions")
check(UI.mode == "professions" and #ShownRows() > 0 and #UI.entries > 0, "Professions tab")
UI:SetMode("wishlist")
check(UI.mode == "wishlist", "Wishlist tab")

SlashCmdList.FOREVERLOOT("raids")
check(UI.mode == "raids", "/fl raids")
SlashCmdList.FOREVERLOOT("dungeons")
check(UI.mode == "dungeons", "/fl dungeons")
SlashCmdList.FOREVERLOOT("help")
local helped = false
for _, m in ipairs(MOCK.printed) do if m:find("/fl raids", 1, true) then helped = true end end
check(helped, "help mentions /fl raids")
SlashCmdList.FOREVERLOOT("forget")
check(next(ns.db.learned) == nil, "/fl forget")

print(("smoke: %d passed, %d failed"):format(passed, failed))
if failed > 0 then error("smoke test failed") end
