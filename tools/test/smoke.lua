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
check(table.concat(UI.modeOrder, ",") == "dungeons,raids,sets,professions,wishlist", "tabs: " .. table.concat(UI.modeOrder, ","))
local tabLabels = {}
for _, t in ipairs(UI.tabs) do tabLabels[#tabLabels + 1] = t.label.text end
check(table.concat(tabLabels, ",") == "DUNGEONS,RAIDS,SETS,PROFESSIONS,WISHLIST", "tab labels " .. table.concat(tabLabels, ","))

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
	-- Raids without wings: every boss and its loot shows (the Quests section starts collapsed)
	local wings = 0
	for _, e in ipairs(UI.entries) do
		if e.kind == "wing" and e.data.id ~= "d:" .. r.key .. ":quests" then wings = wings + 1 end
	end
	if wings == 0 then
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
-- 1.6: quests, sets, filters, tooltips
----------------------------------------------------------------------
local function Entries(kind)
	local out = {}
	for _, e in ipairs(UI.entries) do if e.kind == kind then out[#out + 1] = e end end
	return out
end
local function Section(id)
	for _, e in ipairs(UI.entries) do if e.kind == "wing" and e.data.id == id then return e end end
end

-- Quests in the data
local defias
for _, q in ipairs(R.DM.quests or {}) do if q.id == 166 then defias = q end end
check(defias and defias.name == "The Defias Brotherhood" and defias.side == 1, "Deadmines has The Defias Brotherhood")
check(defias and Has(defias.choices or {}, 6087), "with its reward choices")
local questCount, rewardItems = 0, 0
for _, list in ipairs({ ns.Dungeons, ns.Raids }) do
	for _, d in ipairs(list) do
		for _, q in ipairs(d.quests or {}) do
			questCount = questCount + 1
			check(type(q.name) == "string" and (q.side == 1 or q.side == 2 or q.side == 3), "quest fields " .. tostring(q.name))
			for _, id in ipairs(q.choices or {}) do
				rewardItems = rewardItems + 1
				check(ns.Items[id] ~= nil, "quest reward bundled " .. id)
			end
			for _, id in ipairs(q.rewards or {}) do
				rewardItems = rewardItems + 1
				check(ns.Items[id] ~= nil, "quest reward bundled " .. id)
			end
		end
	end
end
check(questCount > 100 and rewardItems > 200, ("quests %d, reward items %d"):format(questCount, rewardItems))

-- The Quests section: collapsed at first, then a bar per quest with its rewards
MOCK.faction = "Alliance"
UI:SetMode("dungeons")
UI:Select(R.DM)
local qs = Section("d:DM:quests")
check(qs ~= nil and #Entries("quest") == 0, "Deadmines has a Quests section, collapsed")
UI:ToggleSection("d:DM:quests")
local bars = Entries("quest")
check(#bars > 3, "opening it lists the quests (" .. #bars .. ")")
local sawDefias = false
for _, e in ipairs(bars) do if e.data.quest == defias then sawDefias = true end end
check(sawDefias, "The Defias Brotherhood is listed")
local rewardRow = false
for _, e in ipairs(UI.entries) do
	if e.kind == "item" and e.data.itemID == 6087 then rewardRow = true end
end
check(rewardRow, "its reward is an item row")
check(K.QuestTag(defias):find("Alliance", 1, true) and K.QuestTag(defias):find("choose 1 of", 1, true), "quest tag: " .. K.QuestTag(defias))
UI.loot.bar:SetValue(bars[1].y) -- scroll the quests into view
local bar
for i = 1, (UI.used.quest or 0) do if UI.pools.quest[i]:IsShown() then bar = UI.pools.quest[i] break end end
check(bar ~= nil, "a quest bar is painted")
if bar then
	bar.scripts.OnEnter(bar)
	check(GameTooltip.lines[1] == bar.quest.name, "quest bar tooltip")
	bar.scripts.OnLeave(bar)
	bar.scripts.OnClick(bar)
	check(UI.urlPopup and UI.urlPopup.url:find("quest=" .. bar.quest.id, 1, true), "quest bar gives its Wowhead link")
	UI.urlPopup:Hide()
end
-- The other faction's quests are left out
MOCK.faction = "Horde"
UI:Refresh()
local hordeBars = #Entries("quest")
check(hordeBars < #bars, "a Horde character sees fewer Deadmines quests (" .. hordeBars .. ")")
MOCK.faction = "Alliance"
UI:Refresh()

-- Quest rewards are searchable
UI:Search("tunic of westfall")
local questHit = false
for _, g in ipairs(UI.searchGroups or {}) do
	for _, r in ipairs(g.rows) do if r.itemID == 2041 and r.wing == "Quests" then questHit = true end end
end
check(questHit, "search finds a quest reward under Quests")
UI:ClearSearch()

-- My class: a Mage doesn't see plate, a Warrior does
local plate, cloth
for id, e in pairs(ns.Items) do
	if e[3] == "Plate Chest" and not e[8] then plate = plate or id end
	if e[3] == "Cloth Chest" and not e[8] then cloth = cloth or id end
end
check(K.UsableBy(plate, "WARRIOR") and not K.UsableBy(plate, "MAGE"), "plate is for Warriors, not Mages")
check(K.UsableBy(cloth, "MAGE") and not K.UsableBy(cloth, "WARRIOR"), "cloth is for Mages (the filter hides it for Warriors)")
local wand, shield
for id, e in pairs(ns.Items) do
	if e[3] == "Wand" and not e[8] then wand = wand or id end
	if e[3] == "Shield" and not e[8] then shield = shield or id end
end
check(K.UsableBy(wand, "PRIEST") and not K.UsableBy(wand, "ROGUE"), "wands for casters only")
check(K.UsableBy(shield, "SHAMAN") and not K.UsableBy(shield, "DRUID"), "shields for Shamans, not Druids")
local restricted
for id, e in pairs(ns.Items) do
	if e[8] and #e[8] == 1 and e[8][1] == 8 then restricted = id break end
end
check(restricted and K.UsableBy(restricted, "MAGE") and not K.UsableBy(restricted, "PRIEST"), "Classes: Mage items are Mage-only")
check(K.UsableBy(ns.DungeonByKey.DM.bosses[1].loot[1], "WARRIOR") ~= nil, "UsableBy answers for any drop")

MOCK.class = { "Mage", "MAGE", 8 }
UI:SetMode("raids")
UI:Select(R.MC)
local before = #Entries("item")
UI:ToggleFilter("myClass")
check(ns.char.filters.myClass == true and UI.toggles.myClass.check:IsShown(), "My class turns on")
local after = #Entries("item")
check(after < before, ("My class hides gear a Mage can't use in Molten Core (%d -> %d)"):format(before, after))
for _, e in ipairs(Entries("item")) do
	check(K.UsableBy(e.data.itemID, "MAGE"), "only Mage gear left: " .. e.data.itemID)
end
local tagged = false
for _, e in ipairs(Entries("boss")) do if e.data.tag and e.data.tag:find(" of ", 1, true) then tagged = true end end
check(tagged, "boss bars say how many items the filter left")
UI:Search("chest")
for _, g in ipairs(UI.searchGroups or {}) do
	for _, r in ipairs(g.rows) do check(K.UsableBy(r.itemID, "MAGE"), "search respects My class: " .. r.itemID) end
end
UI:ClearSearch()
UI:ToggleFilter("myClass")
check(#Entries("item") == before, "turning it off brings them back")

-- Hide Classic
UI:Select(R.MC)
UI:ToggleFilter("hideClassic")
for _, e in ipairs(Entries("item")) do
	check(ns.Items[e.data.itemID][4] ~= 2, "Hide Classic leaves no Classic-only item: " .. e.data.itemID)
end
local notes = Entries("note")
check(#notes > 0, "bosses left empty by the filter say so")
UI:ToggleFilter("hideClassic")
MOCK.class = { "Warrior", "WARRIOR", 1 }

-- The toggles only show on tabs with loot
UI:SetMode("professions")
check(not UI.toggles.myClass:IsShown(), "no loot filters on Professions")
UI:SetMode("dungeons")
check(UI.toggles.myClass:IsShown() and UI.toggles.hideClassic:IsShown(), "loot filters on Dungeons")

-- Sets
check(#ns.Sets > 20, "item sets (" .. #ns.Sets .. ")")
local valor
for _, st in ipairs(ns.Sets) do
	for _, id in ipairs(st.pieces) do check(ns.Items[id] ~= nil, "set piece bundled " .. id .. " (" .. st.name .. ")") end
	if st.id == 189 then valor = st end
end
check(valor and valor.name == "Battlegear of Valor" and #valor.pieces == 8 and #valor.bonuses > 0, "Battlegear of Valor")
UI:SetMode("sets")
check(UI.mode == "sets" and UI.listLabel.text == "ITEM SETS", "Sets tab")
check(#ShownRows() == #ns.Sets, "one row per set (" .. #ShownRows() .. ")")
UI:Select(valor)
check(UI.header.name.text == "Battlegear of Valor" and UI.header.meta.text:find("8 pieces", 1, true), "set header: " .. UI.header.meta.text)
check(#Entries("text") == #valor.bonuses and #Entries("item") == 8, "set bonuses and pieces")
local sourced = 0
for _, e in ipairs(Entries("item")) do
	if e.data.source and e.data.source ~= "No known source" then sourced = sourced + 1 end
end
check(sourced >= 6, "most Valor pieces say where they drop (" .. sourced .. ")")
check(select(2, UI:Mode().WowheadLink(valor)):find("item-set=189", 1, true), "set Wowhead link")
local valorRow = RowFor(valor)
check(valorRow and valorRow.marker.shown, "red bar: a Warrior can wear Valor")
MOCK.class = { "Mage", "MAGE", 8 }
UI:BuildList()
check(valorRow and not RowFor(valor).marker.shown, "but not a Mage")
UI:ToggleFilter("myClass")
check(RowFor(valor) == nil and #ShownRows() < #ns.Sets, "My class hides sets a Mage can't wear")
UI:ToggleFilter("myClass")
MOCK.class = { "Warrior", "WARRIOR", 1 }
UI:Search("valor")
check((UI.searchTotal or 0) >= 8, "set search finds the Valor pieces by set name (" .. tostring(UI.searchTotal) .. ")")
UI:ClearSearch()
SlashCmdList.FOREVERLOOT("sets")
check(UI.mode == "sets", "/fl sets")

-- "Drops from" lines on the game's item tooltips
local barb = 5191 -- Cruel Barb, Edwin VanCleef
local sources = ns.SourcesOf(barb)
check(#sources > 0 and sources[1].instance == R.DM, "Cruel Barb's sources")
GameTooltip:SetOwner(UIParent, "ANCHOR_CURSOR")
GameTooltip:SetItemByID(barb)
local joined = table.concat(GameTooltip.lines, "\n")
check(joined:find("Forever Loot", 1, true) and joined:find("Edwin VanCleef", 1, true), "item tooltip says who drops it")
local before = #GameTooltip.lines
GameTooltip:SetItemByID(barb)
check(#GameTooltip.lines == before, "the lines aren't added twice")
GameTooltip:SetOwner(UIParent, "ANCHOR_CURSOR")
GameTooltip:SetItemByID(2041)
check(table.concat(GameTooltip.lines, "\n"):find("Quest: ", 1, true), "quest rewards say which quest")
ItemRefTooltip:SetOwner(UIParent, "ANCHOR_CURSOR")
ItemRefTooltip:SetHyperlink("item:" .. barb)
check(table.concat(ItemRefTooltip.lines, "\n"):find("Edwin VanCleef", 1, true), "chat link tooltips too")
SlashCmdList.FOREVERLOOT("tooltip")
check(ns.db.tooltip == false, "/fl tooltip turns it off")
GameTooltip:SetOwner(UIParent, "ANCHOR_CURSOR")
GameTooltip:SetItemByID(barb)
check(not table.concat(GameTooltip.lines, "\n"):find("Forever Loot", 1, true), "and the lines are gone")
SlashCmdList.FOREVERLOOT("tooltip")
check(ns.db.tooltip == true, "/fl tooltip turns it back on")
-- The addon's own rows don't get the extra lines
UI:SetMode("dungeons")
UI:Select(R.DM)
UI:Paint()
local own
for i = 1, (UI.used.item or 0) do
	local r = UI.pools.item[i]
	if r:IsShown() and MOCK.cached[r.itemID] then own = r break end
end
if own then
	own.scripts.OnEnter(own)
	check(not table.concat(GameTooltip.lines, "\n"):find("Forever Loot", 1, true), "own item rows skip the source lines")
	own.scripts.OnLeave(own)
end

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
