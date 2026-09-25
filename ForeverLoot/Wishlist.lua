local ADDON, ns = ...
local UI, K = ns.UI, ns.UIKit
local C = ns.COLORS
if not (UI and K) then return end

-- The Wishlist tab: the gear this character wants, grouped by where to get it, with a
-- chat alert when any of it drops or comes up for a roll. Items go on the list with a
-- right-click on the Dungeons, Raids and Professions tabs (Core.lua keeps the list).

local ITEM_H, RECIPE_H = K.ITEM_H, K.RECIPE_H
local NOTE_H, SECTION_GAP = K.NOTE_H, K.SECTION_GAP
local Count = K.Count

-- The list's first row, and the group for wanted items no dungeon or recipe lists
local EVERYTHING = { name = "Everything" }
local ELSEWHERE = { name = "No known source", key = "elsewhere" }

local function BossSource(d, boss)
	local where = d.name .. (boss.wing and (" (" .. boss.wing .. ")") or "")
	if boss.trash then return "Trash mobs", "Drops from trash in " .. where .. "." end
	if boss.unconfirmed then return "Boss unconfirmed", "Found in " .. where .. "." end
	return boss.name, "Drops from " .. boss.name .. " in " .. where .. "."
end

-- Every wanted item, grouped by where to get it: dungeons in level order, then raids,
-- then the professions that make it, then anything none of them lists. An item that drops and can be
-- made shows up in both. `filter` is a search, or nil for the whole list.
local function Gather(filter)
	local wanted = ns.Wishlist.Items()
	local terms = filter and K.ParseQuery(filter.text)
	local function Keep(itemID)
		return not filter or K.Matches(K.SearchInfo(itemID), terms, filter, " wanted wishlist ")
	end
	local groups, total, placed = {}, 0, {}
	local function Group(entry, rows)
		if #rows > 0 then
			groups[#groups + 1] = { entry = entry, rows = rows }
			total = total + #rows
		end
	end

	local instances = K.SortedDungeons()
	for _, r in ipairs(K.SortedRaids()) do instances[#instances + 1] = r end
	for _, d in ipairs(instances) do
		local rows, here = {}, {}
		for _, boss in ipairs(d.bosses) do
			for _, itemID in ipairs(boss.loot) do
				if wanted[itemID] then
					placed[itemID], here[itemID] = true, true
					if Keep(itemID) then
						local source, from = BossSource(d, boss)
						rows[#rows + 1] = { itemID = itemID, source = source, from = from,
							pct = boss.pct and boss.pct[itemID], hint = boss.hints and boss.hints[itemID],
							owned = ns.Wishlist.IsOwned(itemID) }
					end
				end
			end
		end
		-- Drops you recorded yourself that the bundled tables don't list
		for _, bucket in pairs(ns.db.learned[d.key] or {}) do
			for itemID, count in pairs(bucket.items) do
				if wanted[itemID] and not here[itemID] then
					placed[itemID], here[itemID] = true, true
					if Keep(itemID) then
						rows[#rows + 1] = { itemID = itemID, source = bucket.name, learnedCount = count,
							from = "You looted it from " .. (bucket.name or "a boss") .. " in " .. d.name .. ".",
							owned = ns.Wishlist.IsOwned(itemID) }
					end
				end
			end
		end
		Group(d, rows)
	end

	local skills = K.PlayerSkills and K.PlayerSkills() or {}
	for _, p in ipairs(ns.Professions or {}) do
		local rows = {}
		for _, rec in ipairs(p.recipes) do
			if rec.item and wanted[rec.item] then
				placed[rec.item] = true
				if Keep(rec.item) then
					rows[#rows + 1] = { recipe = rec, prof = p, mine = skills[p.name], owned = ns.Wishlist.IsOwned(rec.item) }
				end
			end
		end
		Group(p, rows)
	end

	local rest = {}
	for itemID in pairs(wanted) do
		if not placed[itemID] and Keep(itemID) then
			rest[#rest + 1] = { itemID = itemID, owned = ns.Wishlist.IsOwned(itemID) }
		end
	end
	table.sort(rest, function(a, b) return (ns.ItemDisplay(a.itemID)) < (ns.ItemDisplay(b.itemID)) end)
	Group(ELSEWHERE, rest)
	return groups, total
end

-- One collapsible section per source, open by default: it's your own short list
local function AddGroup(ui, g)
	local e = g.entry
	if ui.contentY > 0 then ui:AddGap(SECTION_GAP) end
	local right = Count(#g.rows, "item")
	if e.minLevel then right = K.LevelText(e) .. "   ·   " .. right end
	local kind = e.minLevel and "d:" or (e.recipes and "p:" or "")
	local id = (ui:IsSearching() and "s:w:" or "w:") .. kind .. e.key
	if ui:AddSection(id, e.name:upper(), right, true) then return end
	for _, row in ipairs(g.rows) do
		if row.recipe then
			ui:AddEntry("recipe", RECIPE_H, row)
		else
			ui:AddEntry("item", ITEM_H, row)
		end
	end
end

----------------------------------------------------------------------
-- The tab
----------------------------------------------------------------------
local Wishlist = {
	key = "wishlist",
	tab = "Wishlist",
	listTitle = "WHERE TO GET IT",
	listRight = "ITEMS",
	allLabel = "Everything",
	unit = "item",
	groupUnit = "source",
	searchHint = "Search your wishlist",
	searchAbout = "The search looks at the names, slots, types and stats of what's on your wishlist.",
	noMatch = {
		"Nothing on your wishlist matches that.",
		"Clear the search to see the whole list.",
	},
	footer = "Right-click: take it off    Shift-click: link in chat    Ctrl-click: preview    " ..
		ns.Colorize(C.blue, "OWNED") .. ": in your bags, bank or worn",
}

function Wishlist.dataDate()
	return ns.PROFESSION_DATE or ns.DATA_DATE
end

-- Counts for the list's right column, worked out with its entries
local counts = {}

function Wishlist.Entries()
	local groups = Gather()
	wipe(counts)
	counts[EVERYTHING] = ns.Wishlist.Count()
	local list = { EVERYTHING }
	for _, g in ipairs(groups) do
		list[#list + 1] = g.entry
		counts[g.entry] = #g.rows
	end
	return list
end

-- The red bar marks dungeons for your level and professions you know, like the other tabs
function Wishlist.RowInfo(entry)
	local marker = false
	if entry.minLevel then
		local level = UnitLevel("player") or 0
		marker = level >= entry.minLevel and level <= entry.maxLevel
	elseif entry.recipes then
		marker = K.PlayerSkills ~= nil and K.PlayerSkills()[entry.name] ~= nil
	end
	return entry.name, counts[entry] or 0, "", marker
end

function Wishlist.Default()
	return EVERYTHING
end

function Wishlist.Remember()
end

function Wishlist.WowheadLink(entry)
	-- A new raid or dungeon Wowhead has no zone page for yet gets no link
	if entry and entry.minLevel then
		if entry.zone and entry.zone ~= 0 then return entry.name .. " on Wowhead", ns.WOWHEAD .. "zone=" .. entry.zone end
		return entry.name .. " on Wowhead", nil
	end
	if entry and entry.recipes then return entry.name .. " on Wowhead", ns.WOWHEAD .. "skill=" .. entry.skill end
end

function Wishlist.ShowHeader(ui, h, entry)
	local groups = Gather()
	if entry == EVERYTHING then
		h.name:SetText("Wishlist")
		local total, have = ns.Wishlist.Count(), 0
		for itemID in pairs(ns.Wishlist.Items()) do
			if ns.Wishlist.IsOwned(itemID) then have = have + 1 end
		end
		h.meta:SetText(total == 0 and "Nothing on it yet" or
			(Count(total, "item") .. "   ·   " .. have .. " owned   ·   from " .. Count(#groups, "source")))
	else
		h.name:SetText(entry.name)
		local rows = 0
		for _, g in ipairs(groups) do
			if g.entry == entry then rows = #g.rows end
		end
		local parts = { Count(rows, "wanted item") }
		if entry.minLevel then table.insert(parts, 1, K.LevelText(entry)) end
		h.meta:SetText(table.concat(parts, "   ·   "))
	end
	h.note:SetText("Right-click an item on the Dungeons or Raids tab, or a recipe on the Professions tab, to add it; " ..
		"right-click it here to take it off. You get a chat alert when one drops or comes up for a roll. " ..
		ns.Colorize(C.blue, "OWNED") .. " = in your bags, bank or worn.")
end

function Wishlist.Render(ui, entry)
	local shown = 0
	for _, g in ipairs(Gather()) do
		if entry == EVERYTHING or g.entry == entry then
			AddGroup(ui, g)
			shown = shown + 1
		end
	end
	if shown > 0 then return end
	if ns.Wishlist.Count() == 0 then
		ui:AddEntry("note", NOTE_H, { text = "Your wishlist is empty." })
		ui:AddEntry("note", NOTE_H, { text = "Right-click any item on the Dungeons or Raids tab, or any recipe on the Professions tab, to add it." })
	else
		ui:AddEntry("note", NOTE_H, { text = "Nothing from here is on your wishlist anymore." })
	end
end

function Wishlist.Find(filter)
	return Gather(filter)
end

Wishlist.AddResults = AddGroup

UI:RegisterMode(Wishlist)

----------------------------------------------------------------------
-- Alerts, and keeping OWNED up to date
----------------------------------------------------------------------
local alerted = {}

-- A chat line and a sound when something on the wishlist shows up
local function Alert(link, what)
	if not link or (issecretvalue and issecretvalue(link)) then return end
	local itemID = tonumber(link:match("item:(%d+)"))
	if not (itemID and ns.Wishlist.IsWanted(itemID)) then return end
	-- Opening the same corpse again shouldn't repeat it
	local now = GetTime()
	if alerted[link] and now - alerted[link] < 60 then return end
	alerted[link] = now
	ns:Print(link .. " from your wishlist " .. what .. "!")
	if SOUNDKIT and SOUNDKIT.RAID_WARNING then PlaySound(SOUNDKIT.RAID_WARNING) end
end

local pending = false
local events = CreateFrame("Frame")
events:RegisterEvent("LOOT_OPENED")
for _, event in ipairs({ "START_LOOT_ROLL", "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED" }) do
	pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function(_, event, arg1)
	if event == "LOOT_OPENED" then
		for slot = 1, GetNumLootItems() do Alert(GetLootSlotLink(slot), "is in the loot") end
	elseif event == "START_LOOT_ROLL" then
		Alert(GetLootRollItemLink and GetLootRollItemLink(arg1), "is up for a roll")
	elseif UI.mode == "wishlist" and UI.frame and UI.frame:IsShown() and not pending then
		-- Bags or gear changed: repaint OWNED once things settle
		pending = true
		C_Timer.After(0.5, function()
			pending = false
			if UI.mode == "wishlist" and UI.frame:IsShown() then
				UI:Refresh()
				if not UI:IsSearching() and UI.current then Wishlist.ShowHeader(UI, UI.header, UI.current) end
			end
		end)
	end
end)
