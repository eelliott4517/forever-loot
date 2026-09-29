-- Loads Forever Loot in TOC order against the mock and exercises every tab.
local DIR = ...
local passed, failed = 0, 0
local function check(cond, what, detail)
	if cond then
		passed = passed + 1
		print("PASS  " .. what)
	else
		failed = failed + 1
		print("FAIL  " .. what .. (detail ~= nil and ("  ->  " .. tostring(detail)) or ""))
	end
end

dofile(DIR .. "/wowmock.lua")
dofile(DIR .. "/../test/templates.lua")
-- Leatherworking is matched by name, Skinning by its skill line id, Tailoring (under a collapsed
-- header) only by id
MOCK.skills = { { "Professions", true }, { "Leatherworking", false, 125, 150 }, { "Skinning", false, 140, 150, 393 } }
MOCK.hiddenSkills = { { "Tailoring", false, 50, 75, 197 } }

local before = {}
for k in pairs(_G) do before[k] = true end

local ns = {}
-- The repo's ForeverLoot folder; FL_ADDON_DIR points the tests at another copy (the installed one, say)
local ADDON_DIR = os.getenv("FL_ADDON_DIR") or (DIR .. "/../../ForeverLoot/")
local toc = {}
for line in io.lines(ADDON_DIR .. "ForeverLoot.toc") do
	if line:match("%.lua$") then toc[#toc + 1] = line end
end
for _, file in ipairs(toc) do
	local fh = assert(io.open(ADDON_DIR .. file, "rb"))
	local src = fh:read("*a")
	fh:close()
	local chunk = assert(loadstring(src, "@" .. file))
	chunk("ForeverLoot", ns)
end
print("loaded " .. table.concat(toc, ", "))

MOCK.Fire("ADDON_LOADED", "ForeverLoot")
MOCK.Fire("PLAYER_LOGIN")
local UI = ns.UI
check(ns.db and ns.minimapButton, "boots and makes the minimap button")
check(table.concat(UI.modeOrder, ",") == "dungeons,raids,sets,professions,wishlist", "all five tabs registered in order", table.concat(UI.modeOrder, ","))
local function tab(key)
	for _, t in ipairs(UI.tabs or {}) do if t.key == key then return t end end
end

---------------------------------------------------------------- helpers
-- Every row the Dungeons (or Raids) search can list: boss drops, then the quest rewards
-- your faction can get
local function rowsWhere(pred, list)
	local n = 0
	for _, d in ipairs(list or ns.Dungeons) do
		for _, b in ipairs(d.bosses) do
			for _, id in ipairs(b.loot) do
				if pred(ns.Items[id], id, b, d) then n = n + 1 end
			end
		end
		for _, q in ipairs(d.quests or {}) do
			if ns.QuestForPlayer(q) then
				for _, id in ipairs(q.choices or {}) do if pred(ns.Items[id], id, nil, d) then n = n + 1 end end
				for _, id in ipairs(q.rewards or {}) do if pred(ns.Items[id], id, nil, d) then n = n + 1 end end
			end
		end
	end
	return n
end
local function recipesWhere(pred)
	local n = 0
	for _, p in ipairs(ns.Professions) do
		for _, rec in ipairs(p.recipes) do
			if pred(rec, p) then n = n + 1 end
		end
	end
	return n
end
local function entries(kind)
	local out = {}
	for _, e in ipairs(UI.entries or {}) do if e.kind == kind then out[#out + 1] = e end end
	return out
end
local function painted(kind)
	local out = {}
	for i = 1, UI.used[kind] or 0 do out[#out + 1] = UI.pools[kind][i] end
	return out
end
local function listRows()
	local out = {}
	for _, r in ipairs(UI.listRows) do if r:IsShown() then out[#out + 1] = r end end
	return out
end
local function search(text)
	UI.searchBox:Type(text)
	return #entries(UI.mode == "professions" and "recipe" or "item")
end

local gloves = rowsWhere(function(e) return e[3]:match(" Hands$") or e[1]:find("Gloves") end)
local hands = rowsWhere(function(e) return e[3]:match(" Hands$") end)
local leatherHands = rowsWhere(function(e) return e[3] == "Leather Hands" end)
local fingers = rowsWhere(function(e) return e[3] == "Finger" end)
local twoHandSwords = rowsWhere(function(e) return e[3] == "Two-Hand Sword" end)
local newItems = rowsWhere(function(e) return e[4] == 1 or e[4] == 3 or e[1]:find("%f[%a]New%f[%A]") end)

---------------------------------------------------------------- open (dungeons)
SlashCmdList.FOREVERLOOT("")
UI.loot._h = 422
check(UI.frame:IsShown() and UI.mode == "dungeons", "/fl opens the Dungeons tab")
check(UI.current and UI.current.key == "RFC", "opens on a dungeon for your level", UI.current and UI.current.key)
check(#listRows() == #ns.Dungeons, "list shows every dungeon", #listRows())
check(UI.header.wowhead:IsShown() and not UI.header.clear:IsShown(), "dungeon view shows the Wowhead button")
check(#entries("item") == 12 and #painted("item") == 12, "RFC renders its 12 drops", #entries("item"))
check(tab("dungeons").checked and not tab("raids").checked, "Dungeons tab is highlighted")
check(UI.listLabel:GetText() == "Dungeons" and UI.listRight:GetText() == "Levels", "list labels for dungeons")

---------------------------------------------------------------- dungeon search
local n = search("gloves")
check(UI:IsSearching() and UI.listKey == "dungeons:search", "typing switches to search mode")
check(n == gloves and UI.searchTotal == gloves, "\"gloves\" finds every Hands drop plus glove patterns", n .. " vs " .. gloves)
local allRow = listRows()[1]
check(allRow.entry == nil and allRow.name:GetText() == "All dungeons" and allRow.count:GetText() == tostring(gloves),
	"list starts with All dungeons and the total")
local sum = 0
for i, r in ipairs(listRows()) do if i > 1 then sum = sum + tonumber(r.count:GetText()) end end
check(sum == gloves, "per-dungeon counts add up", sum)
check(UI.header.clear:IsShown() and not UI.header.wowhead:IsShown(), "Clear search replaces the Wowhead button")
local itemsPainted = painted("item")
check(#itemsPainted > 0 and #itemsPainted < 30, "only the rows in view get widgets", #itemsPainted)
for _, row in ipairs(itemsPainted) do
	assert(row.sourceText and row.source:IsShown() and not row.pct:IsShown(), "rows show the boss column")
end
check(search("glove") == gloves and search("GLOVES") == gloves and search("hands") == hands, "singular and caps agree; \"hands\" is the slot only")

search("gloves")
UI:SetFilter("kind", "leather")
check(#entries("item") == leatherHands, "Type: Leather narrows gloves to leather", #entries("item") .. " vs " .. leatherHands)
check(search("leather gloves") == leatherHands, "\"leather gloves\" text matches too")
local slotMenu = UI.filterButtons.slot
local shownOptions, titles = 0, 0
for _, o in ipairs(slotMenu:MockOptions()) do
	if o.kind == "radio" then shownOptions = shownOptions + 1 elseif o.kind == "title" then titles = titles + 1 end
end
check(slotMenu:IsMenuOpen() and shownOptions == 21 and titles == 3, "dungeon slot menu has 21 choices under 3 titles", shownOptions)
slotMenu:MockPick("finger")
check(not slotMenu:IsMenuOpen() and UI.filter.slot == "finger" and UI.header.meta:GetText() == "No matches", "picking Finger with leather gloves finds nothing")
check(slotMenu.Text:GetText() == "Slot: Finger", "the dropdown shows what's picked", slotMenu.Text:GetText())
check(#entries("note") == 2, "no-match notes shown")
UI.filterButtons.kind:MockPick("All types")
check(UI.filterButtons.kind.Text:GetText() == "All types", "All types clears the Type filter")
UI.searchBox:Type("")
check(UI:IsSearching() and #entries("item") == fingers, "Slot: Finger alone lists every ring", #entries("item") .. " vs " .. fingers)
UI:SetFilter("slot", nil)

search("gloves")
local second = listRows()[2]
second:Click()
local focus = second.entry
local expect
for _, g in ipairs(UI.searchGroups) do if g.entry == focus then expect = #g.rows end end
check(UI.filter.focus == focus and #entries("item") == expect, "clicking a dungeon narrows results to it")
search("gloves")
listRows()[2]:Click()
UI.header.clear:Click()
check(not UI:IsSearching() and UI.listKey == "dungeons:entries" and UI.current == focus, "Clear search opens the dungeon you narrowed to")
check(UI.searchBox:GetText() == "" and UI.searchBox.Instructions:IsShown(), "search box reset with its hint back")

local a, b, c = search("two hand sword"), search("two-handed sword"), search("2h sword")
check(a == twoHandSwords and b == a and c == a, "two hand / two-handed / 2h sword agree", a .. " " .. b .. " " .. c)
check(search("rings") == fingers, "\"rings\" is exactly the Finger slot")
check(search("new") == newItems, "\"new\" lists everything new in Forever", UI.searchTotal .. " vs " .. newItems)

-- No more 300-row cap: everything is listed, but only what's in view is drawn
local wide = search("st")
check(wide > 300 and wide == UI.searchTotal, "broad searches list every match", wide)
local firstPainted = painted("item")[1].entry.itemID
UI.loot:ScrollTo(UI.loot:GetVerticalScrollRange())
local lastEntry = entries("item")[#entries("item")]
local seenLast = false
for _, row in ipairs(painted("item")) do if row.entry == lastEntry.data then seenLast = true end end
check(seenLast and painted("item")[1].entry.itemID ~= firstPainted and #painted("item") < 30, "scrolling to the bottom draws the last rows")

-- Recorded loot still shows up
MOCK.itemInstant[900001] = { 900001, "Armor", "Leather", "INVTYPE_HAND", 133, 4, 2 }
MOCK.itemInfo[900001] = { "Test Recorded Handwraps", "|cff0070dd|Hitem:900001|h[Test]|h|r", 3 }
ns.db.learned.DM = { ["npc:646"] = { name = "Mr. Smite", items = { [900001] = 2, [5196] = 1 } } }
check(search("gloves") == gloves + 1, "recorded gloves add one row")
check(search("seen") == 1, "\"seen\" lists what you recorded")
wipe(ns.db.learned)

-- Tooltips and live item data
search("gloves")
local first = painted("item")[1]
first:GetScript("OnEnter")(first)
check(table.concat(GameTooltip.lines, "\n"):find("Drops from ", 1, true), "item tooltip says which boss drops it")
first:GetScript("OnLeave")(first)
MOCK.Fire("GET_ITEM_INFO_RECEIVED", first.itemID, true)
MOCK.RunTimers()
check(true, "item-data refresh runs over painted rows")
UI:ClearSearch()
local function sectionWidget(text)
	for _, w in ipairs(painted("wing")) do if w.text:GetText() == text then return w end end
end
UI:Select(ns.DungeonByKey.SM)
check(#entries("boss") == 0 and #entries("wing") >= 5, "Scarlet Monastery's wings start collapsed", #entries("boss"))
sectionWidget("Graveyard"):Click()
local graveyard = 0
for _, b in ipairs(ns.DungeonByKey.SM.bosses) do if b.wing == "Graveyard" then graveyard = graveyard + 1 end end
check(#entries("boss") == graveyard, "clicking Graveyard shows its bosses", #entries("boss") .. " vs " .. graveyard)
for _, d in ipairs(ns.Dungeons) do UI:Select(d) end
check(true, "every dungeon view renders")

---------------------------------------------------------------- professions tab
tab("professions"):MockClick()
check(UI.mode == "professions" and tab("professions").checked and not tab("dungeons").checked, "Professions tab switches and highlights")
check(#listRows() == #ns.Professions and #ns.Professions == 11, "list shows the 11 professions", #listRows())
check(UI.listLabel:GetText() == "Professions" and UI.listRight:GetText() == "Recipes", "list labels for professions")
check(UI.current and UI.current.name == "Leatherworking", "opens on your best crafting profession, not Skinning", UI.current and UI.current.name)
local lwRow
for _, r in ipairs(listRows()) do if r.entry and r.entry.name == "Leatherworking" then lwRow = r end end
check(lwRow and lwRow.isMarked and lwRow.levels:GetText() == tostring(#lwRow.entry.recipes), "known professions are marked (a gold name) with a recipe count")
lwRow:Click()
local lw = ns.ProfessionByKey.LW
check(UI.current == lw and UI.header.name:GetText() == "Leatherworking", "clicking a profession opens it")
print("  meta: " .. UI.header.meta:GetText())
check(UI.header.meta:GetText():find("Your skill 125/150", 1, true), "header shows your skill")
check(#entries("recipe") == 0 and #entries("wing") > 10, "groups start collapsed: only the headers show", #entries("recipe"))
local glovesHeader = sectionWidget("Gloves")
check(glovesHeader and glovesHeader.collapsed and glovesHeader.icon:GetAtlas() == "common-button-list-plus", "collapsed headers show a plus")
glovesHeader:GetScript("OnEnter")(glovesHeader)
check(GameTooltip.lines[2] and GameTooltip.lines[2]:find("Click to expand", 1, true), "header hint says what a click does")
glovesHeader:GetScript("OnLeave")(glovesHeader)
glovesHeader:Click()
local lwGloves = 0
for _, r in ipairs(lw.recipes) do
	local e = r.item and ns.Items[r.item]
	if e and e[3]:match("Hands$") then lwGloves = lwGloves + 1 end
end
check(#entries("recipe") == lwGloves, "clicking Gloves opens just that group", #entries("recipe") .. " vs " .. lwGloves)
glovesHeader = sectionWidget("Gloves")
check(not glovesHeader.collapsed and glovesHeader.icon:GetAtlas() == "common-button-list-minus", "open headers show a minus")
UI:Select(ns.ProfessionByKey.TAIL)
check(#entries("recipe") == 0, "another profession starts collapsed")
UI:Select(lw)
check(#entries("recipe") == lwGloves, "coming back keeps Gloves open")
MOCK.shift = true
sectionWidget("Head"):Click()
check(#entries("recipe") == 0, "shift-click collapses every group when any is open")
sectionWidget("Head"):Click()
MOCK.shift = false
check(#entries("recipe") == #lw.recipes and #lw.recipes > 500, "shift-click again opens them all", #entries("recipe"))
local function groupNames()
	local names, has = {}, {}
	for _, e in ipairs(entries("wing")) do
		names[#names + 1] = e.data.text
		has[e.data.text] = true
	end
	return names, has
end
local groups, has = groupNames()
print("  groups: " .. table.concat(groups, ", "))
check(groups[1] == "Head" and has.Chest and has.Legs and has.Gloves and not has.Apprentice, "grouped by type: Head first, with Chest, Legs, Gloves")
local counted, ordered, pure, current, last = 0, true, true, nil, nil
for _, e in ipairs(UI.entries) do
	if e.kind == "wing" then
		current, last = e.data.text, nil
	elseif e.kind == "recipe" then
		counted = counted + 1
		local sk = e.data.recipe.skill or 9999
		if last and sk < last then ordered = false end
		last = sk
		if current == "Gloves" then
			local it = ns.Items[e.data.recipe.item or 0]
			if not (it and it[3]:match("Hands$")) then pure = false end
		end
	end
end
check(counted == #lw.recipes, "every recipe appears exactly once", counted)
check(ordered, "recipes stay in skill order inside each group")
check(pure, "the Gloves group holds only hand items")
check(#painted("recipe") > 0 and #painted("recipe") < 20, "only visible recipe rows get widgets", #painted("recipe"))

-- A row: name, skill color, source, materials
local row = painted("recipe")[1]
local rec = row.entry.recipe
print(("  first row: %s | skill %s | %s | %s"):format(row.name:GetText(), row.skill:GetText(), row.src:GetText(), row.mats:GetText()))
check(row.mats:GetText():find(ns.Items[rec.mats[1]][1], 1, true), "materials line names the reagents")
check(row.skill:GetText() == tostring(rec.skill), "skill number shown")
-- skill colors at 125: a recipe above that is out of reach (red)
local far
for _, e in ipairs(entries("recipe")) do if e.data.recipe.skill and e.data.recipe.skill > 125 then far = e break end end
UI.loot:ScrollTo(far.y)
local farRow
for _, r in ipairs(painted("recipe")) do if r.entry == far.data then farRow = r end end
check(farRow and farRow.skill._textColor[1] == ns.COLORS.red[1] and farRow.skill._textColor[2] == ns.COLORS.red[2], "recipes above your skill show red")
local grey
for _, e in ipairs(entries("recipe")) do
	local cl = e.data.recipe.colors
	if cl and cl[4] <= 125 and e.data.recipe.skill and e.data.recipe.skill <= 125 then grey = e break end
end
UI.loot:ScrollTo(grey.y)
local greyOk = false
for _, r in ipairs(painted("recipe")) do
	if r.entry == grey.data and r.skill._textColor[1] == 0.5 then greyOk = true end
end
check(greyOk, "recipes you've outgrown show grey")

-- Tooltip
UI.loot:ScrollTo(0)
row = painted("recipe")[2]
MOCK.bags[row.entry.recipe.mats[1]] = 7
row:GetScript("OnEnter")(row)
local tip = table.concat(GameTooltip.lines, "\n")
print("  tooltip:\n    " .. tip:gsub("\n", "\n    "))
check(tip:find("Materials", 1, true) and tip:find("you have 7", 1, true), "tooltip lists materials and what you carry")
check(tip:find("to learn", 1, true), "tooltip says the skill it needs")
row:GetScript("OnLeave")(row)

-- Clicks
row:Click()
check(MOCK.popup and MOCK.popup.which == "FOREVERLOOT_WOWHEAD_LINK" and MOCK.popup.data.url:find("spell=" .. row.entry.recipe.id, 1, true)
	and MOCK.popup:GetEditBox():GetText() == MOCK.popup.data.url, "click gives the recipe's Wowhead link in the game's popup")
MOCK.popup = nil

-- Enchants make no item
UI:Select(ns.ProfessionByKey.ALCH)
local alchGroups, alchHas = groupNames()
print("  alchemy: " .. table.concat(alchGroups, ", "))
check(alchHas.Potions and alchHas.Elixirs and alchHas.Flasks, "Alchemy groups potions, elixirs and flasks")
local ench = ns.ProfessionByKey.ENCH
UI:Select(ench)
local enchGroups, enchHas = groupNames()
print("  enchanting: " .. table.concat(enchGroups, ", "))
local bracerAt, chestAt
for i, g in ipairs(enchGroups) do
	if g == "Bracer Enchants" then bracerAt = i elseif g == "Chest Enchants" then chestAt = i end
end
check(bracerAt and chestAt and chestAt < bracerAt, "enchants group by the slot they go on, in sheet order")
MOCK.shift = true
painted("wing")[1]:Click()
MOCK.shift = false
local enchantEntry
for _, e in ipairs(entries("recipe")) do if not e.data.recipe.item and e.data.recipe.slot then enchantEntry = e break end end
UI.loot:ScrollTo(enchantEntry.y)
local enchantRow
for _, r in ipairs(painted("recipe")) do if r.entry == enchantEntry.data then enchantRow = r end end
check(enchantRow and enchantRow.type:GetText() == "Enchant" and enchantRow.name:GetText() == enchantEntry.data.recipe.name, "enchants show their own name and Enchant")
MOCK.links = {}
MOCK.shift = true
enchantRow:Click()
MOCK.shift = false
check(MOCK.links[1] and MOCK.links[1]:find("Hspell:" .. enchantEntry.data.recipe.id, 1, true), "shift-click links an enchant as a spell")
enchantRow:GetScript("OnEnter")(enchantRow)
check(table.concat(GameTooltip.lines, "\n"):find(enchantEntry.data.recipe.desc or enchantEntry.data.recipe.name, 1, true), "enchant tooltip shows what it does")
enchantRow:GetScript("OnLeave")(enchantRow)

---------------------------------------------------------------- profession search
local function madeName(r) return r.item and ns.Items[r.item] and ns.Items[r.item][1] or "" end
local function usesMat(r, name)
	for i = 1, #r.mats, 2 do
		local e = ns.Items[r.mats[i]]
		if e and e[1] == name then return true end
	end
end
local copperBar = search("copper bar")
local usesCopper = recipesWhere(function(r) return usesMat(r, "Copper Bar") or madeName(r) == "Copper Bar" end)
print(("  \"copper bar\": %d results, %d use or make Copper Bar"):format(copperBar, usesCopper))
check(copperBar >= usesCopper and usesCopper > 10, "\"copper bar\" finds every recipe that uses or makes it")
local smelt = false
for _, g in ipairs(UI.searchGroups) do
	for _, r in ipairs(g.rows) do if r.recipe.name == "Smelt Copper" then smelt = true end end
end
check(smelt, "including Smelt Copper in Mining")
check(listRows()[1].name:GetText() == "All professions", "search list starts with All professions")
local openCount = #entries("recipe")
check(openCount == UI.searchTotal, "search results start open")
local hiddenRows = #UI.searchGroups[1].rows
painted("wing")[1]:Click()
check(#entries("recipe") == openCount - hiddenRows, "a search section collapses too")
search("copper")
search("copper bar")
check(#entries("recipe") == openCount, "a new search opens every section again")

UI.searchBox:Type("")
UI:SetFilter("slot", "hands")
local craftHands = recipesWhere(function(r)
	if r.item then local e = ns.Items[r.item]; return e and e[3]:match(" Hands$") and true end
	return r.slot == "hands"
end)
check(UI.searchTotal == craftHands and craftHands > 50, "Slot: Hands lists craftable gloves and glove enchants", UI.searchTotal .. " vs " .. craftHands)
UI:SetFilter("kind", "leather")
local leatherCraft = recipesWhere(function(r) local e = r.item and ns.Items[r.item]; return e and e[3] == "Leather Hands" end)
check(UI.searchTotal == leatherCraft, "plus Type: Leather lists leather gloves", UI.searchTotal .. " vs " .. leatherCraft)
UI:SetFilter("kind", nil)
UI:SetFilter("slot", nil)
local profOptions, consumableOption = 0, nil
for _, o in ipairs(UI.filterButtons.slot:MockOptions()) do
	if o.kind == "radio" then
		profOptions = profOptions + 1
		if o.data == "consumable" then consumableOption = o end
	end
end
check(consumableOption and profOptions == 23, "profession slot menu offers Consumable, Trade Goods and Bag", profOptions)
UI.filterButtons.slot:MockPick("consumable")
local consumables = recipesWhere(function(r)
	local e = r.item and ns.Items[r.item]
	return e and ({ Potion = 1, Elixir = 1, Flask = 1, Scroll = 1, ["Food & Drink"] = 1, Bandage = 1, Consumable = 1, ["Item Enhancement"] = 1 })[e[3]] and true
end)
check(UI.searchTotal == consumables and consumables > 100, "Slot: Consumable lists potions, food and bandages", UI.searchTotal .. " vs " .. consumables)

-- Switching tabs keeps the search words but drops a filter the other tab lacks
search("gloves")
tab("dungeons"):MockClick()
check(UI.mode == "dungeons" and UI.filter.slot == nil and UI.searchBox:GetText() == "gloves" and #entries("item") == gloves,
	"back on Dungeons the Consumable filter drops and gloves still search")
tab("professions"):MockClick()
local craftGloves = #entries("recipe")
check(UI.mode == "professions" and craftGloves > 0, "and on Professions \"gloves\" lists craftable gloves", craftGloves)
local agiGloves = search("agility gloves")
check(agiGloves > 0 and agiGloves < craftGloves, "\"agility gloves\" narrows crafted gloves", agiGloves)
check(search("trainer") == recipesWhere(function(r) return r.src == "Trainer" end), "\"trainer\" lists trainer recipes")
check(search("new leatherworking") == recipesWhere(function(r, p) return p.key == "LW" and r.status == "new" end), "\"new leatherworking\" lists Forever's new patterns")

-- Narrow to one profession, then clear back into it
search("bracers")
local profRow = listRows()[2]
profRow:Click()
check(UI.filter.focus == profRow.entry, "clicking a profession narrows the results")
UI.header.clear:Click()
check(not UI:IsSearching() and UI.current == profRow.entry, "Clear search opens that profession")

-- Skill changes repaint
UI:Select(lw)
MOCK.skills[2][3] = 140
MOCK.Fire("SKILL_LINES_CHANGED")
check(UI.header.meta:GetText():find("Your skill 140/150", 1, true), "skill changes show up", UI.header.meta:GetText())

-- Live item data refresh over recipe rows
MOCK.Fire("GET_ITEM_INFO_RECEIVED", (painted("recipe")[1] or {}).itemID or 2318, true)
MOCK.RunTimers()
check(true, "item-data refresh runs over recipe rows")

-- A profession with a single group shows it open
UI:Select(ns.ProfessionByKey.SKIN)
check(#entries("wing") == 1 and #entries("recipe") == #ns.ProfessionByKey.SKIN.recipes, "a profession with one group opens it")

-- Every profession renders
for _, p in ipairs(ns.Professions) do UI:Select(p) end
check(true, "every profession view renders")

---------------------------------------------------------------- wishlist
local function openAll()
	for _, id in ipairs(UI.sectionIds) do UI:SectionState()[id] = true end
	UI:Refresh()
end
local function chatHas(text) return (MOCK.chat[#MOCK.chat] or ""):find(text, 1, true) ~= nil end
check(#UI.tabs == 5 and tab("wishlist").tooltipText == "Wishlist", "there's a Wishlist tab")

-- Right-click a dungeon drop
tab("dungeons"):MockClick()
UI:ClearSearch()
UI:Select(ns.DungeonByKey.DM)
local dmRow = painted("item")[1]
local wantedID = dmRow.itemID
dmRow:GetScript("OnEnter")(dmRow)
check(table.concat(GameTooltip.lines, "\n"):find("Right-click to add it to your wishlist", 1, true), "item tooltips say how to add it")
dmRow:GetScript("OnLeave")(dmRow)
dmRow:Click("RightButton")
check(ns.Wishlist.IsWanted(wantedID) and chatHas("is on your wishlist"), "right-click puts a drop on the wishlist")
local marked
for _, r in ipairs(painted("item")) do if r.itemID == wantedID then marked = r end end
check(marked and marked.wanted:IsShown() and marked.wanted:GetAtlas() == "auctionhouse-icon-favorite", "wanted rows get the favorite star")
check(ForeverLootCharDB.wishlist[wantedID] ~= nil, "the list is saved per character")
marked:GetScript("OnEnter")(marked)
check(table.concat(GameTooltip.lines, "\n"):find("On your wishlist", 1, true), "and their tooltip says so")
marked:GetScript("OnLeave")(marked)

-- Right-click a recipe: its item goes on the list
tab("professions"):MockClick()
UI:Select(lw)
openAll()
local recipeRow
for _, r in ipairs(painted("recipe")) do if r.entry.recipe.item then recipeRow = r break end end
local craftedID = recipeRow.entry.recipe.item
recipeRow:Click("RightButton")
local recipeMarked
for _, r in ipairs(painted("recipe")) do if r.entry.recipe.item == craftedID then recipeMarked = r end end
check(ns.Wishlist.IsWanted(craftedID) and recipeMarked.wanted:IsShown(), "right-click puts a recipe's item on it too")
UI:Select(ns.ProfessionByKey.ENCH)
openAll()
local enchantOnly
for _, r in ipairs(painted("recipe")) do if not r.entry.recipe.item then enchantOnly = r break end end
enchantOnly:Click("RightButton")
check(ns.Wishlist.Count() == 2 and chatHas("can't go on the wishlist"), "enchants make no item, so they can't be added")

-- The Wishlist tab
tab("wishlist"):MockClick()
check(UI.mode == "wishlist" and UI.current and UI.current.name == "Everything", "the Wishlist tab opens on everything")
print("  meta: " .. UI.header.meta:GetText())
check(UI.header.name:GetText() == "Wishlist" and UI.header.meta:GetText():find("2 items", 1, true), "header counts the list")
check(not UI.header.wowhead:IsShown(), "no Wowhead button for the whole list")
local wrows = listRows()
check(wrows[1].name:GetText() == "Everything" and wrows[1].levels:GetText() == "2", "list starts with Everything")
check(wrows[2].entry == ns.DungeonByKey.DM and wrows[3].entry == lw and #wrows == 3, "then each source, dungeons first")
check(#entries("item") == 1 and #entries("recipe") == 1, "one drop row and one recipe row")
local wishItem = painted("item")[1]
check(wishItem.sourceText and wishItem.source:IsShown(), "drops show which boss has them")
check(painted("recipe")[1].mats:GetText() ~= "", "recipes show their materials")

MOCK.bags[wantedID] = 1
MOCK.Fire("BAG_UPDATE_DELAYED")
MOCK.RunTimers()
wishItem = painted("item")[1]
check(wishItem.badge:IsShown() and wishItem.badge:GetText() == "Owned", "items you carry show Owned")
check(UI.header.meta:GetText():find("1 owned", 1, true), "and the header counts them")
MOCK.bags[wantedID] = nil
MOCK.equipped[craftedID] = true
UI:Refresh()
check(painted("recipe")[1].badge:GetText() == "Owned", "so do items you're wearing")
MOCK.equipped[craftedID] = nil

listRows()[2]:Click()
check(UI.current == ns.DungeonByKey.DM and #entries("item") == 1 and #entries("recipe") == 0 and UI.header.wowhead:IsShown(),
	"clicking a source shows just its items")
UI.searchBox:Type(ns.Items[craftedID][1])
check(UI.searchTotal == 1 and #entries("recipe") == 1, "the search box searches the wishlist")
UI:ClearSearch()

-- "wanted" finds wishlist items on the other tabs
tab("dungeons"):MockClick()
check(search("wanted") == 1, "\"wanted\" finds your wishlist drops on the Dungeons tab")
UI.searchBox:Type("")

-- Alerts
local lootLink = "|cff0070dd|Hitem:" .. wantedID .. "::::::::|h[Wanted]|h|r"
MOCK.loot = { "|cffffffff|Hitem:2589::::::::|h[Linen Cloth]|h|r", lootLink }
MOCK.sounds = {}
MOCK.Fire("LOOT_OPENED")
check(chatHas("is in the loot") and MOCK.sounds[1] == 8959, "a wanted drop in the loot window gets an alert and a sound")
local chats = #MOCK.chat
MOCK.Fire("LOOT_OPENED")
check(#MOCK.chat == chats, "reopening the same loot doesn't repeat it")
MOCK.rolls[7] = "|cff0070dd|Hitem:" .. craftedID .. "::::::::|h[Crafted]|h|r"
MOCK.Fire("START_LOOT_ROLL", 7)
check(chatHas("is up for a roll"), "and so does a roll")
MOCK.loot = { MOCK.Secret() }
check(pcall(MOCK.Fire, "LOOT_OPENED"), "a secret loot link is skipped, not an error")
MOCK.loot = {}

-- Take things off from the Wishlist tab
tab("wishlist"):MockClick()
UI:Select(listRows()[1].entry)
painted("item")[1]:Click("RightButton")
check(not ns.Wishlist.IsWanted(wantedID) and #entries("item") == 0 and chatHas("is off your wishlist"), "right-click in the list takes it off")
check(UI.header.meta:GetText():find("1 item", 1, true) and listRows()[1].levels:GetText() == "1", "the counts follow")
ns.Wishlist.Toggle(987654)
UI:Refresh()
UI:BuildList()
local elsewhere = false
for _, e in ipairs(entries("wing")) do if e.data.text == "No known source" then elsewhere = true end end
check(elsewhere, "an item nothing lists goes under No known source")
wipe(ns.char.wishlist)
UI:Select(listRows()[1].entry)
check(#entries("note") == 2 and UI.header.meta:GetText() == "Nothing on it yet", "an empty wishlist says how to add things")
ns.minimapButton:GetScript("OnEnter")(ns.minimapButton)
check(table.concat(GameTooltip.lines, "\n"):find("Wishlist: 0 items", 1, true), "the minimap tooltip counts the wishlist")
SlashCmdList.FOREVERLOOT("dungeons")
SlashCmdList.FOREVERLOOT("wishlist")
check(UI.mode == "wishlist", "/fl wishlist opens the tab")

---------------------------------------------------------------- slash commands and show/hide
SlashCmdList.FOREVERLOOT("dungeons")
check(UI.mode == "dungeons", "/fl dungeons")
SlashCmdList.FOREVERLOOT("professions")
check(UI.mode == "professions", "/fl professions")
SlashCmdList.FOREVERLOOT("copper")
check(UI.searchBox:GetText() == "copper" and UI.mode == "professions" and UI.searchTotal > 0, "/fl copper searches the open tab")
UI.frame:Hide()
UI:Show()
check(UI.mode == "professions" and UI.searchBox:GetText() == "copper", "reopening keeps the tab and the search")
MOCK.instance = { "The Deadmines", "party", 1, "", 5, 0, false, 36 }
UI.frame:Hide()
UI:Show()
check(UI.mode == "dungeons" and UI.current.key == "DM" and not UI:IsSearching(), "walking into a dungeon jumps to it")
MOCK.instance = { "Elwynn Forest", "none", 0, "", 0, 0, false, 0 }
check(ns.db.mode == "dungeons", "the tab is remembered")
SlashCmdList.FOREVERLOOT("help")
check(MOCK.chat[#MOCK.chat]:find("forget", 1, true), "/fl help prints help")
UI.filterButtons.kind:OpenMenu()
UI.frame:Hide()
check(not UI.filterButtons.kind:IsMenuOpen(), "closing the window closes an open menu")

---------------------------------------------------------------- 1.6.0: raids
local function wipeFilters() ns.char.filters.myClass, ns.char.filters.hideClassic = false, false end
wipeFilters()
SlashCmdList.FOREVERLOOT("raids")
check(UI.frame:IsShown() and UI.mode == "raids" and tab("raids").checked, "/fl raids opens the Raids tab")
check(#listRows() == #ns.Raids and UI.listLabel:GetText() == "Raids" and UI.listRight:GetText() == "Players",
	"the list shows every raid, with a players column", #listRows())
check(listRows()[1].levels:GetText() == tostring(ns.Raids[1].size), "raid rows show the raid size", listRows()[1].levels:GetText())
local classicRow
for _, r in ipairs(listRows()) do if r.entry.status == "classic" then classicRow = r break end end
check(classicRow and classicRow.tag:GetText() == "Classic" and classicRow.tagColor == nil and classicRow.tag._textColor[1] == ns.COLORS.grey[1], "Classic raids are tagged Classic in grey")
check(UI.current == ns.Raids[1], "below 60 it opens on the first raid", UI.current and UI.current.key)
check(UI.toggles.myClass:IsShown() and UI.toggles.hideClassic:IsShown(), "the loot filters show on the Raids tab")
local naxx = ns.DungeonByKey.NAXX
UI:Select(naxx)
check(#entries("boss") == 0 and #entries("wing") >= 6, "Naxxramas's quarters start collapsed", #entries("wing"))
check(not UI.header.wowhead:IsShown() == (naxx.zone == 0), "the Wowhead button follows the zone id")
local mc = ns.DungeonByKey.MC
UI:Select(mc)
check(#entries("boss") == #mc.bosses, "a raid without wings lists every boss", #entries("boss") .. " vs " .. #mc.bosses)
UI:Select(ns.DungeonByKey.HYJAL)
check(UI.header.meta:GetText():find("20 players", 1, true) and not UI.header.wowhead:IsShown(), "a new raid without a zone page shows its size and no link",
	UI.header.meta:GetText())
UI.searchBox:Type("")
UI:SetFilter("slot", "trinket")
local raidTrinkets = rowsWhere(function(e) return e[3] == "Trinket" end, ns.Raids)
check(UI.searchTotal == raidTrinkets and raidTrinkets > 20, "Slot: Trinket lists every raid trinket", UI.searchTotal .. " vs " .. raidTrinkets)
UI:SetFilter("slot", nil)
for _, r in ipairs(ns.Raids) do UI:Select(r) end
check(true, "every raid view renders")

---------------------------------------------------------------- 1.6.0: dungeon quests and your faction
local qd, sideCount
for _, d in ipairs(ns.Dungeons) do
	local n = { 0, 0, 0 }
	for _, q in ipairs(d.quests or {}) do n[q.side] = n[q.side] + 1 end
	if n[1] > 0 and n[2] > 0 then qd, sideCount = d, n break end
end
tab("dungeons"):MockClick()
UI:ClearSearch()
MOCK.faction = "Alliance"
UI:Select(qd)
local questSection = "d:" .. qd.key .. ":quests"
check(UI:IsCollapsed(questSection) and #entries("quest") == 0, "a dungeon's quests start collapsed under QUESTS")
UI:ToggleSection(questSection)
check(#entries("quest") == sideCount[1] + sideCount[3], "an Alliance character sees Alliance and shared quests",
	#entries("quest") .. " vs " .. (sideCount[1] + sideCount[3]))
local hordeNote = false
for _, e in ipairs(entries("note")) do
	if e.data.text == (sideCount[2] == 1 and "1 quest for the Horde isn't shown." or (sideCount[2] .. " quests for the Horde aren't shown.")) then hordeNote = true end
end
check(hordeNote, "and a note counts the Horde quests left out")
local qEntry = entries("quest")[1]
UI.loot:ScrollTo(qEntry.y)
local qRow
for _, w in ipairs(painted("quest")) do if w.entry == qEntry.data then qRow = w end end
qRow:GetScript("OnEnter")(qRow)
local qTip = MOCK.TooltipText()
check(qTip:find(qEntry.data.quest.name, 1, true) and (qTip:find("Alliance only", 1, true) or qTip:find("Alliance and Horde", 1, true)),
	"a quest's tooltip names it and its side")
qRow:GetScript("OnLeave")(qRow)
qRow:Click()
check(MOCK.popup and MOCK.popup.data.url == ns.WOWHEAD .. "quest=" .. qEntry.data.quest.id, "clicking a quest gives its Wowhead link")
MOCK.popup = nil
MOCK.faction = "Horde"
UI:Refresh()
check(#entries("quest") == sideCount[2] + sideCount[3], "a Horde character sees the Horde ones instead")
MOCK.faction = "Alliance"
UI:Refresh()

---------------------------------------------------------------- 1.6.0: My class and Hide Classic
-- Independent of the addon's own rules: a rogue can't wear cloth, mail or plate, or use a shield
local BODY = { Head = true, Shoulder = true, Chest = true, Wrist = true, Hands = true, Waist = true, Legs = true, Feet = true }
local function rogueCant(e)
	if not e then return false end
	local material, slot = e[3]:match("^(%a+) (%a+)$")
	return (BODY[slot] and (material == "Cloth" or material == "Mail" or material == "Plate")) or e[3] == "Shield"
end
local dm = ns.DungeonByKey.DM
UI:Select(dm)
local allItems = #entries("item")
MOCK.classFile = "ROGUE"
UI.toggles.myClass:Click()
check(ns.char.filters.myClass and UI.toggles.myClass:GetChecked(), "My class turns on, and is saved per character")
local afterClass, bad = #entries("item"), 0
for _, e in ipairs(entries("item")) do
	local it = ns.Items[e.data.itemID]
	if rogueCant(it) and not (it and it[8]) then bad = bad + 1 end
end
check(afterClass < allItems and bad == 0, "My class hides the cloth, mail and plate a rogue can't wear", allItems .. " -> " .. afterClass)
-- A boss whose drops a rogue can use none of gets a note instead
local blocked
for _, d in ipairs(ns.Dungeons) do
	for _, b in ipairs(d.bosses) do
		if not d.bosses[1].wing and #b.loot > 0 and not b.trash then
			local all = true
			for _, id in ipairs(b.loot) do
				local it = ns.Items[id]
				if not rogueCant(it) or (it and it[8]) then all = false end
			end
			if all then blocked = blocked or { d = d, b = b } end
		end
	end
end
if blocked then
	UI:Select(blocked.d)
	local noted = false
	for _, e in ipairs(entries("note")) do
		if e.data.text:find("hidden by the My class / Hide Classic filters", 1, true) then noted = true end
	end
	check(noted, "a boss with nothing for your class says the filter hid its " .. #blocked.b.loot .. " drops")
end
UI:Select(dm)
UI.toggles.hideClassic:Click()
local classicLeft = 0
for _, e in ipairs(entries("item")) do
	local it = ns.Items[e.data.itemID]
	if it and it[4] == 2 then classicLeft = classicLeft + 1 end
end
check(ns.char.filters.hideClassic and classicLeft == 0, "Hide Classic takes out the Classic-only loot")
search("gloves")
local cantGloves = 0
for _, e in ipairs(entries("item")) do if rogueCant(ns.Items[e.data.itemID]) and not ns.Items[e.data.itemID][8] then cantGloves = cantGloves + 1 end end
check(UI.searchTotal < gloves and cantGloves == 0, "searches follow the filters too", UI.searchTotal .. " of " .. gloves)
UI:ClearSearch()
tab("professions"):MockClick()
check(not UI.toggles.myClass:IsShown(), "the Professions tab has no loot filters")
tab("dungeons"):MockClick()
UI.toggles.myClass:Click()
UI.toggles.hideClassic:Click()
check(not ns.char.filters.myClass and not ns.char.filters.hideClassic and #entries("item") == allItems, "turning both off brings everything back")

---------------------------------------------------------------- 1.6.0: sets
SlashCmdList.FOREVERLOOT("sets")
check(UI.mode == "sets" and #listRows() == #ns.Sets and UI.listLabel:GetText() == "Item sets", "/fl sets lists every set", #listRows())
local defias = ns.Sets[1]
check(UI.current == defias and UI.header.name:GetText() == defias.name, "a rogue opens on the first set it can wear", UI.current and UI.current.name)
local meta = UI.header.meta:GetText()
check(meta:find(#defias.pieces .. " pieces", 1, true) and meta:find("Level " .. defias.level, 1, true) and meta:find("Leather", 1, true),
	"the header gives pieces, level and armor", meta)
check(#entries("text") == #defias.bonuses and #entries("item") == #defias.pieces, "set bonuses, then one row per piece")
local sourced = 0
for _, e in ipairs(entries("item")) do if e.data.source and e.data.source ~= "No known source" then sourced = sourced + 1 end end
check(sourced == #defias.pieces, "every Defias piece says where it drops", sourced)
local piece = painted("item")[1]
piece:GetScript("OnEnter")(piece)
check(MOCK.TooltipText():find("Drops from ", 1, true), "a piece's tooltip names the boss")
piece:GetScript("OnLeave")(piece)
piece:Click("RightButton")
check(ns.Wishlist.IsWanted(piece.itemID), "right-click puts a set piece on the wishlist")
piece:Click("RightButton")
check(search("defias") >= #defias.pieces and UI.searchGroups[1].entry == defias, "searching a set's name finds its pieces")
UI:ClearSearch()
local classicSet
for _, st in ipairs(ns.Sets) do
	local all = true
	for _, id in ipairs(st.pieces) do if not (ns.Items[id] and ns.Items[id][4] == 2) then all = false end end
	if all then classicSet = st break end
end
if classicSet then
	local tagged = false
	for _, r in ipairs(listRows()) do if r.entry == classicSet and r.tag:GetText() == "Classic" then tagged = true end end
	check(tagged, "a set Forever has none of is tagged CLASSIC")
	UI.toggles.hideClassic:Click()
	local listed = false
	for _, r in ipairs(listRows()) do if r.entry == classicSet then listed = true end end
	check(not listed, "and Hide Classic takes it off the list")
	UI.toggles.hideClassic:Click()
end
UI.toggles.myClass:Click()
local rogueSets = #listRows()
check(rogueSets < #ns.Sets and rogueSets > 0, "My class keeps only the sets a rogue can wear", rogueSets .. " of " .. #ns.Sets)
UI.toggles.myClass:Click()
for _, st in ipairs(ns.Sets) do UI:Select(st) end
check(true, "every set view renders")

---------------------------------------------------------------- 1.6.0: where-it-comes-from lines on item tooltips
local bossDrop = dm.bosses[1].loot[1]
local lines, namesBoss = ns.TooltipLines(bossDrop), false
for _, l in ipairs(lines or {}) do if l[1] == dm.bosses[1].name and l[2]:find(dm.name, 1, true) then namesBoss = true end end
check(namesBoss, "an item's lines name the boss and dungeon it drops in")
local busiest, busiestN = nil, 0
for id in pairs(ns.Items) do
	local l = ns.TooltipLines(id)
	local last = l and l[#l][1]
	if last and last:match("^and %d+ more places$") then
		local n = tonumber(last:match("%d+"))
		if n > busiestN then busiest, busiestN = id, n end
	end
end
check(busiest and #ns.TooltipLines(busiest) == 4, "an item from many places gets three lines and \"and N more places\"", busiestN)
local bagSlot = CreateFrame("Frame")
GameTooltip:SetOwner(bagSlot)
GameTooltip:SetItemByID(bossDrop)
local function countLine(text)
	local n = 0
	for _, l in ipairs(GameTooltip.lines) do if l == text then n = n + 1 end end
	return n
end
check(countLine("Forever Loot") == 1 and MOCK.TooltipText():find(dm.bosses[1].name, 1, true), "a bag item's tooltip says where it drops")
GameTooltip:SetItemByID(bossDrop)
check(countLine("Forever Loot") == 1, "a tooltip that reports the item twice gets the lines once")
GameTooltip:SetOwner(bagSlot)
GameTooltip:SetItemByID(bossDrop)
check(countLine("Forever Loot") == 1, "and after it's cleared, once again")
ItemRefTooltip:SetOwner(UIParent)
ItemRefTooltip:SetItemByID(bossDrop)
check(MOCK.TooltipText(ItemRefTooltip):find("Forever Loot", 1, true), "chat link tooltips get them too")
local crafted
for _, rec in ipairs(ns.ProfessionByKey.LW.recipes) do
	if rec.item and rec.skill and #ns.SourcesOf(rec.item) == 1 then crafted = rec break end
end
GameTooltip:SetOwner(bagSlot)
GameTooltip:SetItemByID(crafted.item)
check(MOCK.TooltipText():find("Made by Leatherworking (" .. crafted.skill .. ")", 1, true), "crafted items say which profession makes them")
local questItem = qd.quests[1].choices and qd.quests[1].choices[1] or qd.quests[1].rewards and qd.quests[1].rewards[1]
if questItem then
	GameTooltip:SetOwner(bagSlot)
	GameTooltip:SetItemByID(questItem)
	check(MOCK.TooltipText():find("Quest: ", 1, true), "quest rewards name the quest")
end
GameTooltip:SetOwner(bagSlot)
check(pcall(GameTooltip.SetItemByID, GameTooltip, bossDrop, MOCK.Secret()) and countLine("Forever Loot") == 0, "a secret item id is skipped, not an error")
GameTooltip:SetOwner(bagSlot)
GameTooltip:SetItemByID(987654)
check(countLine("Forever Loot") == 0, "items with no known source get nothing")
SlashCmdList.FOREVERLOOT("tooltip")
GameTooltip:SetOwner(bagSlot)
GameTooltip:SetItemByID(bossDrop)
check(not ns.db.tooltip and countLine("Forever Loot") == 0, "/fl tooltip turns the lines off")
SlashCmdList.FOREVERLOOT("tooltip")
check(ns.db.tooltip, "and back on")
SlashCmdList.FOREVERLOOT("dungeons")
UI:Select(dm)
local ownRow = painted("item")[1]
GameTooltip:SetOwner(ownRow)
GameTooltip:SetItemByID(ownRow.itemID)
check(countLine("Forever Loot") == 0, "the addon's own rows don't get the lines twice")

---------------------------------------------------------------- 1.6.0: wishlist with raid drops and quest rewards
wipe(ns.char.wishlist)
local raidDrop = mc.bosses[1].loot[1]
local rewardQuest
for _, q in ipairs(qd.quests) do if ns.QuestForPlayer(q) and q.choices and q.choices[1] then rewardQuest = q break end end
ns.Wishlist.Toggle(raidDrop)
if rewardQuest then ns.Wishlist.Toggle(rewardQuest.choices[1]) end
SlashCmdList.FOREVERLOOT("wishlist")
UI:Select(listRows()[1].entry)
local sources, rewardRow = {}, nil
for _, r in ipairs(listRows()) do if r.entry then sources[r.entry] = true end end
for _, e in ipairs(entries("item")) do if e.data.source == "Quest reward" then rewardRow = e end end
check(sources[mc], "a raid drop shows under its raid")
check(not rewardQuest or (sources[qd] and rewardRow), "a quest reward shows under its dungeon as a quest reward")
wipe(ns.char.wishlist)

---------------------------------------------------------------- 1.6.0: every tab, every entry, every filter, a few searches
local errors = {}
local tries = 0
local function try(what, fn, ...)
	tries = tries + 1
	local ok, err = pcall(fn, ...)
	if not ok then errors[#errors + 1] = what .. ": " .. tostring(err) end
end
for _, key in ipairs(UI.modeOrder) do
	try("tab " .. key, UI.SetMode, UI, key)
	for _, combo in ipairs({ { false, false }, { true, false }, { false, true }, { true, true } }) do
		ns.char.filters.myClass, ns.char.filters.hideClassic = combo[1], combo[2]
		for _, class in ipairs({ "ROGUE", "PRIEST", "WARRIOR", "DRUID", "PALADIN" }) do
			MOCK.classFile = class
			UI:ClearSearch()
			try(key .. " list", UI.BuildList, UI)
			for _, entry in ipairs(UI:Mode().Entries()) do try(key .. " " .. tostring(entry.name), UI.Select, UI, entry) end
			for _, q in ipairs({ "gloves", "new", "classic", "agility", "a", "zzzz", "leather", "2h sword" }) do
				try(key .. " search " .. q, function() UI.searchBox:Type(q) end)
			end
			try(key .. " slot filter", UI.SetFilter, UI, "slot", "finger")
			try(key .. " kind filter", UI.SetFilter, UI, "kind", "leather")
			UI:SetFilter("slot", nil)
			UI:SetFilter("kind", nil)
			UI.searchBox:Type("")
		end
	end
end
wipeFilters()
MOCK.classFile = "ROGUE"
check(#errors == 0 and tries > 2500, "every tab, entry, filter and search renders for five classes (" .. tries .. " tries)", errors[1])

---------------------------------------------------------------- 1.6.0: other commands
SlashCmdList.FOREVERLOOT("minimap")
check(ns.db.minimap.hide and not ns.minimapButton:IsShown(), "/fl minimap hides the button")
SlashCmdList.FOREVERLOOT("minimap")
check(not ns.db.minimap.hide and ns.minimapButton:IsShown(), "and shows it again")
ns.db.window = { "TOPLEFT", "TOPLEFT", 10, -10 }
SlashCmdList.FOREVERLOOT("reset")
check(ns.db.window == nil and select(1, UI.frame:GetPoint(1)) == "CENTER", "/fl reset recenters the window")
ns.db.learned.DM = { ["npc:646"] = { name = "Mr. Smite", items = { [900001] = 1 } } }
SlashCmdList.FOREVERLOOT("forget")
check(next(ns.db.learned) == nil, "/fl forget clears recorded drops")

---------------------------------------------------------------- 1.6.1 fixes
-- Skills come from C_SkillInfo: by name, by skill line id, and by id under a collapsed header
SlashCmdList.FOREVERLOOT("professions")
UI:ClearSearch()
local marked = {}
for _, r in ipairs(listRows()) do if r.entry and r.isMarked then marked[r.entry.key] = true end end
check(marked.LW and marked.SKIN and marked.TAIL, "your professions come from C_SkillInfo, even under a collapsed header")
UI:Select(ns.ProfessionByKey.TAIL)
check(UI.header.meta:GetText():find("Your skill 50/75", 1, true), "and a collapsed one still shows your skill", UI.header.meta:GetText())
MOCK.skills[3][1] = "Kürschnerei"
MOCK.Fire("SKILL_LINES_CHANGED")
UI:Select(ns.ProfessionByKey.SKIN)
check(UI.header.meta:GetText():find("Your skill 140/150", 1, true), "a profession is found by its id, so other client languages work too")
MOCK.skills[3][1] = "Skinning"
MOCK.Fire("SKILL_LINES_CHANGED")

-- Enchant links go through C_Spell.GetSpellLink and ChatFrameUtil.InsertLink
UI:Select(ns.ProfessionByKey.ENCH)
openAll()
local enchantE
for _, e in ipairs(entries("recipe")) do if not e.data.recipe.item and e.data.recipe.slot then enchantE = e break end end
UI.loot:ScrollTo(enchantE.y)
local enchantW
for _, r in ipairs(painted("recipe")) do if r.entry == enchantE.data then enchantW = r end end
MOCK.links = {}
MOCK.shift = true
enchantW:Click()
check(MOCK.links[1] and MOCK.links[1]:find("Hspell:" .. enchantE.data.recipe.id, 1, true), "shift-clicking an enchant links it through ChatFrameUtil")
MOCK.chatOpen = false
enchantW:Click()
MOCK.shift = false
MOCK.chatOpen = true
check(MOCK.chat[#MOCK.chat]:find("open the chat box first", 1, true), "with the chat box closed it says to open it", MOCK.chat[#MOCK.chat])

-- Unknown loot after a boss kill counts only when it came off one of the encounter's own bosses
MOCK.instance = { "The Deadmines", "party", 1, "", 5, 0, false, 36 }
MOCK.Fire("ENCOUNTER_END", 9001, "Captain Nobody", 1, 5, 1, { { creatureID = 999001, creatureName = "Captain Nobody", remainingHealthPercent = 0 } })
MOCK.loot = { "|cff0070dd|Hitem:900111::::::::|h[Trash Blue]|h|r" }
MOCK.lootSources = { { "Creature-0-0-0-0-1726-0000000001", 1 } }
MOCK.Fire("LOOT_OPENED")
local enc = ns.db.learned.DM and ns.db.learned.DM["enc:captainnobody"]
check(not (enc and enc.items[900111]), "a blue from trash after a boss kill isn't credited to the boss")
MOCK.loot = { "|cff0070dd|Hitem:900112::::::::|h[Boss Blue]|h|r" }
MOCK.lootSources = { { "Creature-0-0-0-0-999001-0000000002", 1 } }
MOCK.Fire("LOOT_OPENED")
enc = ns.db.learned.DM and ns.db.learned.DM["enc:captainnobody"]
check(enc and enc.items[900112] == 1, "one off the encounter's own boss is")
wipe(ns.db.learned)
MOCK.loot, MOCK.lootSources = {}, {}
MOCK.instance = { "Elwynn Forest", "none", 0, "", 0, 0, false, 0 }

-- A wanted item several bosses drop is one row, with the others on its line
local multi, multiIn, multiBosses
for _, list in ipairs({ ns.Dungeons, ns.Raids }) do
	for _, d in ipairs(list) do
		local count = {}
		for _, b in ipairs(d.bosses) do
			if not (b.trash or b.unconfirmed) then
				for _, id in ipairs(b.loot) do count[id] = (count[id] or 0) + 1 end
			end
		end
		for id, c in pairs(count) do
			if c >= 2 and not multi then multi, multiIn, multiBosses = id, d, c end
		end
	end
end
wipe(ns.char.wishlist)
ns.Wishlist.Toggle(multi)
SlashCmdList.FOREVERLOOT("wishlist")
UI:Select(listRows()[1].entry)
local wrow
for _, r in ipairs(listRows()) do if r.entry == multiIn then wrow = r end end
check(#entries("item") == 1 and wrow and wrow.levels:GetText() == "1", "an item " .. multiBosses .. " bosses drop is one wishlist row, counted once")
check(entries("item")[1] and entries("item")[1].data.source:find(" +" .. (multiBosses - 1), 1, true),
	"and its line names the others: " .. tostring(entries("item")[1] and entries("item")[1].data.source))
wipe(ns.char.wishlist)

-- Quest rewards only count as a source for the faction that can take the quest
local allianceOnly
for _, d in ipairs(ns.Dungeons) do
	for _, q in ipairs(d.quests or {}) do
		if q.side == 1 then
			for _, id in ipairs(q.choices or {}) do
				local only = true
				for _, s in ipairs(ns.SourcesOf(id)) do if not (s.kind == "quest" and s.quest.side == 1) then only = false end end
				if only and not allianceOnly then allianceOnly = id end
			end
		end
	end
end
MOCK.faction = "Horde"
check(allianceOnly and ns.TooltipLines(allianceOnly) == nil, "a Horde character's tooltip doesn't list an Alliance quest's reward")
MOCK.faction = "Alliance"
check(ns.TooltipLines(allianceOnly) ~= nil, "an Alliance one's does")

-- The Sets tab doesn't reopen a set the filters now hide
local plateSet
for _, st in ipairs(ns.Sets) do
	local first = st.pieces[1] and ns.Items[st.pieces[1]]
	if not plateSet and first and first[3]:match("^Plate ") and not first[8] then plateSet = st end
end
MOCK.classFile = "MAGE"
ns.char.filters.myClass = true
ns.db.lastSet = plateSet.id
local pick = UI.modes.sets.Default()
check(pick ~= plateSet, "a mage with My class on doesn't reopen " .. plateSet.name)
ns.char.filters.myClass = false
MOCK.classFile = "ROGUE"

---------------------------------------------------------------- 1.6.3: crafted sets, quest chains
-- Forever's tier sets are partly crafted: the recipes' versions of the pieces are listed too
local glory
for _, st in ipairs(ns.Sets) do if st.name == "Battlegear of Glory" then glory = st end end
check(glory, "a Forever tier set with crafted pieces is on the Sets tab")
if glory then
	SlashCmdList.FOREVERLOOT("sets")
	UI:Select(glory)
	local made = 0
	for _, e in ipairs(entries("item")) do if (e.data.from or ""):find("Made by ", 1, true) then made = made + 1 end end
	check(made > 0, "and its crafted pieces say which profession makes them", made)
end
-- wowtbc.gg's "Abominable Creatures/Unending Torment" is one quest per faction; Unending Torment's
-- four steps share its name and are listed once
local rol, torment = nil, {}
for _, d in ipairs(ns.Dungeons) do if d.key == "ROL" then rol = d end end
for _, q in ipairs(rol and rol.quests or {}) do if q.name == "Unending Torment" then torment[#torment + 1] = q end end
check(#torment == 1 and torment[1].choices and #torment[1].choices > 0, "a chain whose steps share a name is one quest, with its rewards", #torment)
MOCK.faction = "Horde"
local hordeLines = torment[1] and torment[1].choices and ns.TooltipLines(torment[1].choices[1])
MOCK.faction = "Alliance"
check(hordeLines ~= nil, "and a Horde character's tooltip lists that reward")
check(ns.Items[6340] and ns.Items[6340][4] == 0, "an original item Forever reworked (Fenrus' Hide) isn't marked new")

-- The window shares Blizzard's panels' layer, so the dressing room opens in front of it
check(UI.frame:GetFrameStrata() == "MEDIUM", "the window is on Blizzard's panel layer")

---------------------------------------------------------------- globals
local allowed = { ForeverLootDB = true, ForeverLootCharDB = true, SLASH_FOREVERLOOT1 = true, SLASH_FOREVERLOOT2 = true }
local leaks = {}
for k in pairs(_G) do
	if not before[k] and not allowed[k] and not tostring(k):match("^ForeverLoot") then leaks[#leaks + 1] = tostring(k) end
end
check(#leaks == 0, "no stray globals", table.concat(leaks, ", "))

print(("\n%d passed, %d failed"):format(passed, failed))
return failed
