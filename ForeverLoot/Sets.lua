local ADDON, ns = ...
local UI, K = ns.UI, ns.UIKit
local C = ns.COLORS
if not (UI and K and ns.Sets) then return end

-- The Sets tab: every item set with a piece in the dungeon or raid loot or the quest
-- rewards, with its set bonuses and where each piece comes from.

local ITEM_H, NOTE_H, SECTION_GAP, WING_H = K.ITEM_H, K.NOTE_H, K.SECTION_GAP, K.WING_H
local Count = K.Count
local CHARS_PER_LINE, LINE_H = 88, 15

-- A wrapped line of text; the renderer sizes it by its length
local function CreateTextRow(parent, width)
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(width, NOTE_H)
	f.text = K.Text(f, K.Font("set_text", GameFontHighlightSmall, C.light, 11))
	f.text:SetPoint("TOPLEFT", 14, -3)
	f.text:SetPoint("RIGHT", -10, 0)
	f.text:SetWordWrap(true)
	return f
end

K.RegisterKind("text", CreateTextRow, function(f, d)
	f:SetHeight(d.height)
	f.text:SetText(d.text)
	K.SetTextColor(f.text, d.color or C.light)
end)

local function AddText(ui, text, color)
	local lines = math.max(1, math.ceil(#text / CHARS_PER_LINE))
	ui:AddEntry("text", lines * LINE_H + 7, { text = text, color = color, height = lines * LINE_H + 7 })
end

----------------------------------------------------------------------
-- Set facts
----------------------------------------------------------------------
local function Flag(st)
	local new, classic = false, true
	for _, id in ipairs(st.pieces) do
		local e = ns.Items[id]
		local flag = e and e[4]
		if flag == 1 or flag == 3 then new = true end
		if flag ~= 2 then classic = false end
	end
	return new, classic
end

local function ForClass(st, class)
	for _, id in ipairs(st.pieces) do
		if not K.UsableBy(id, class) then return false end
	end
	return true
end

local function ForMe(st)
	local class = K.PlayerClass()
	return class ~= nil and ForClass(st, class)
end

-- The classes its pieces are made for, from their "Classes:" line
local CLASS_NAMES = { [1] = "Warrior", [2] = "Paladin", [3] = "Hunter", [4] = "Rogue", [5] = "Priest",
	[7] = "Shaman", [8] = "Mage", [9] = "Warlock", [11] = "Druid" }
local function ClassText(st)
	local e = ns.Items[st.pieces[1]]
	local ids = e and e[8]
	if not ids then return nil end
	local names = {}
	for _, id in ipairs(ids) do names[#names + 1] = CLASS_NAMES[id] or ("class " .. id) end
	return table.concat(names, ", ")
end

-- "Plate" when the pieces share an armor type
local function ArmorText(st)
	local kind
	for _, id in ipairs(st.pieces) do
		local k = K.SearchInfo(id).kind
		if k == "cloth" or k == "leather" or k == "mail" or k == "plate" then
			if kind and kind ~= k then return nil end
			kind = k
		end
	end
	return kind and (kind:sub(1, 1):upper() .. kind:sub(2))
end

local function Pct(p)
	return (("%.1f"):format(p):gsub("%.0$", "")) .. "%"
end

-- One source as a sentence, and as a short name for the row
local function Describe(s)
	local d = s.instance
	local where = d and (d.name .. (s.boss and s.boss.wing and (" (" .. s.boss.wing .. ")") or "")) or ""
	if s.kind == "boss" then
		return s.boss.name, "Drops from " .. s.boss.name .. " in " .. where .. (s.pct and (", " .. Pct(s.pct)) or "") .. "."
	elseif s.kind == "trash" then
		return "Trash mobs", "Drops from trash in " .. where .. "."
	elseif s.kind == "unconfirmed" then
		return "Boss unconfirmed", "Datamined for " .. where .. "; no site has confirmed the boss yet."
	elseif s.kind == "quest" then
		return "Quest reward", "Reward from the quest " .. s.quest.name .. " (" .. where .. ")."
	end
	local skill = s.recipe.skill and (" (" .. s.recipe.skill .. ")") or ""
	return s.profession.name, "Made by " .. s.profession.name .. skill .. "."
end

local KIND_ORDER = { boss = 1, quest = 2, trash = 3, unconfirmed = 4, craft = 5 }

-- Where a piece comes from: the best source's short name, and every source for its tooltip
local function PieceSource(itemID)
	local sources = {}
	for i, s in ipairs(ns.SourcesOf(itemID)) do sources[i] = s end
	if #sources == 0 then return "No known source", "No dungeon, raid, quest or recipe here lists this piece." end
	table.sort(sources, function(a, b)
		if a.kind ~= b.kind then return KIND_ORDER[a.kind] < KIND_ORDER[b.kind] end
		return (a.pct or 0) > (b.pct or 0)
	end)
	local first, sentences, seen = nil, {}, {}
	for _, s in ipairs(sources) do
		local short, sentence = Describe(s)
		first = first or short
		if not seen[sentence] then
			seen[sentence] = true
			sentences[#sentences + 1] = sentence
		end
	end
	if #sentences > 1 then first = first .. " +" .. (#sentences - 1) end
	return first, table.concat(sentences, " ")
end

local function Visible(st)
	local f = K.Filters()
	if f.myClass and not ForMe(st) then return false end
	if f.hideClassic then
		local _, classic = Flag(st)
		if classic then return false end
	end
	return true
end

----------------------------------------------------------------------
-- The tab
----------------------------------------------------------------------
local Sets = {
	key = "sets",
	tab = "Sets",
	listTitle = "ITEM SETS",
	listRight = "LEVEL",
	allLabel = "All sets",
	unit = "piece",
	groupUnit = "set",
	searchHint = "Search every set, e.g. valor",
	searchAbout = "The search looks at set names and each piece's name, slot, type and stats.",
	noMatch = {
		"No set piece matches that.",
		"Try a set name like valor, a slot like gloves, or a stat like agility.",
	},
	footer = "Click: Wowhead link    Shift-click: link in chat    Ctrl-click: preview    Right-click: wishlist    " ..
		ns.Colorize(C.red, "Red bar") .. ": for your class",
	filters = true,
}

function Sets.dataDate()
	return ns.DATA_DATE
end

function Sets.Entries()
	local list = {}
	for _, st in ipairs(ns.Sets) do
		if Visible(st) then list[#list + 1] = st end
	end
	return list
end

-- NEW when Forever added a piece; CLASSIC when Forever's data has none of them
function Sets.RowInfo(st)
	local new, classic = Flag(st)
	local tag, color = "", nil
	if new then
		tag = "NEW"
	elseif classic then
		tag, color = "CLASSIC", C.mist
	end
	return st.name, st.level and tostring(st.level) or "", tag, ForMe(st), color
end

function Sets.Default()
	local byID = {}
	for _, st in ipairs(ns.Sets) do byID[st.id] = st end
	local last = ns.db.lastSet and byID[ns.db.lastSet]
	if last then return last end
	local entries = Sets.Entries()
	for _, st in ipairs(entries) do
		if ForMe(st) then return st end
	end
	return entries[1] or ns.Sets[1]
end

function Sets.Remember(st)
	ns.db.lastSet = st.id
end

function Sets.WowheadLink(st)
	local new, classic = Flag(st)
	if classic then return st.name .. " on Wowhead Classic", ns.WOWHEAD_CLASSIC .. "item-set=" .. st.id end
	return st.name .. " on Wowhead", ns.WOWHEAD .. "item-set=" .. st.id
end

function Sets.ShowHeader(ui, h, st)
	local new, classic = Flag(st)
	h.name:SetText(st.name)
	h.badge.text:SetText("NEW IN FOREVER")
	h.badge:SetWidth(h.badge.text:GetStringWidth() + 12)
	h.badge:SetShown(new)
	local parts = { Count(#st.pieces, "piece") }
	if st.level then
		parts[#parts + 1] = "Level " .. st.level
	elseif st.ilvl then
		parts[#parts + 1] = "Item level " .. st.ilvl
	end
	parts[#parts + 1] = ArmorText(st)
	local classes = ClassText(st)
	if classes then parts[#parts + 1] = classes end
	h.meta:SetText(table.concat(parts, "   ·   "))
	if classic then
		h.note:SetText("Classic set: Wowhead's Forever database has none of these pieces, so Forever may have replaced it. " ..
			"Bonuses and sources are Classic's.")
	else
		h.note:SetText("Where each piece comes from, from the dungeon, raid and quest tables. Set bonuses are " ..
			"Forever's where Wowhead's Forever database has the set (" .. (ns.DATA_DATE or "") .. ").")
	end
end

function Sets.Render(ui, st)
	local bonuses = #st.bonuses == 1 and "1 bonus" or (#st.bonuses .. " bonuses")
	ui:AddEntry("wing", WING_H, { text = "SET BONUSES", right = bonuses })
	ui:AddGap(4)
	for _, b in ipairs(st.bonuses) do
		AddText(ui, "(" .. b[1] .. ") " .. b[2], C.light)
	end
	if #st.bonuses == 0 then ui:AddEntry("note", NOTE_H, { text = "Wowhead lists no bonuses for this set." }) end
	ui:AddGap(SECTION_GAP)
	ui:AddEntry("wing", WING_H, { text = "PIECES", right = Count(#st.pieces, "piece") })
	ui:AddGap(4)
	for _, id in ipairs(st.pieces) do
		local source, from = PieceSource(id)
		ui:AddEntry("item", ITEM_H, { itemID = id, source = source, from = from })
	end
end

function Sets.Find(filter)
	local terms = K.ParseQuery(filter.text)
	local groups, total = {}, 0
	for _, st in ipairs(Sets.Entries()) do
		local extra = K.Simplify(st.name)
		local rows = {}
		for _, id in ipairs(st.pieces) do
			if K.Matches(K.SearchInfo(id), terms, filter, extra) then
				local source, from = PieceSource(id)
				rows[#rows + 1] = { itemID = id, source = source, from = from }
			end
		end
		if #rows > 0 then
			groups[#groups + 1] = { entry = st, rows = rows }
			total = total + #rows
		end
	end
	return groups, total
end

function Sets.AddResults(ui, g)
	if ui.contentY > 0 then ui:AddGap(SECTION_GAP) end
	local st = g.entry
	if ui:AddSection("s:set:" .. st.id, st.name:upper(), st.level and ("Level " .. st.level) or "", true) then
		return
	end
	for _, r in ipairs(g.rows) do ui:AddEntry("item", ITEM_H, r) end
end

UI:RegisterMode(Sets)
