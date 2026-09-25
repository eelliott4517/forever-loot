local ADDON, ns = ...
local UI, K = ns.UI, ns.UIKit
local C = ns.COLORS
if not (UI and K and ns.Professions) then return end

-- The Professions tab: every recipe in Forever with its materials, grouped by what it
-- makes, in the same list, search and filters as the Dungeons tab.

local RECIPE_H = 40
K.RECIPE_H = RECIPE_H
local NOTE_H, SECTION_GAP = K.NOTE_H, K.SECTION_GAP
local Tex, Font, Text, Count, SetTextColor = K.Tex, K.Font, K.Text, K.Count, K.SetTextColor

-- A profession's recipes are grouped by what they make: gear by slot in character-sheet
-- order, each enchant right after the slot it goes on, then everything else by kind.
local GROUP_ORDER = {
	{ "head", "Head" }, { "neck", "Neck" }, { "shoulder", "Shoulders" }, { "back", "Cloaks" },
	{ "chest", "Chest" }, { "shirt", "Shirts" }, { "tabard", "Tabards" }, { "wrist", "Bracers" },
	{ "hands", "Gloves" }, { "waist", "Belts" }, { "legs", "Legs" }, { "feet", "Boots" },
	{ "finger", "Rings" }, { "trinket", "Trinkets" },
	{ "onehand", "One-Hand Weapons" }, { "twohand", "Two-Hand Weapons" }, { "ranged", "Ranged Weapons" },
	{ "offhand", "Off-hand Items" }, { "shield", "Shields" }, { "relic", "Relics" },
	{ "potion", "Potions" }, { "elixir", "Elixirs" }, { "flask", "Flasks" }, { "food", "Food & Drink" },
	{ "bandage", "Bandages" }, { "scroll", "Scrolls" }, { "enhancement", "Item Enhancements" },
	{ "consumable", "Consumables" }, { "explosives", "Explosives" }, { "devices", "Devices" }, { "parts", "Parts" },
	{ "metal", "Metal & Stone" }, { "cloth", "Cloth" }, { "leather", "Leather" }, { "elemental", "Elemental" },
	{ "enchanting", "Enchanting Materials" }, { "reagent", "Reagents" }, { "herb", "Herbs" }, { "meat", "Meat" },
	{ "tradegoods", "Trade Goods" },
	{ "bag", "Bags" }, { "quiver", "Quivers & Ammo Pouches" }, { "ammo", "Ammo" },
	{ "pet", "Pets" }, { "mount", "Mounts" }, { "holiday", "Fireworks & Holiday" }, { "quest", "Quest Items" },
	{ "recipe", "Recipes" }, { "key", "Keys" }, { "misc", "Miscellaneous" },
	{ "other", "Other" },
}
local GEAR_SLOTS = {
	head = true, neck = true, shoulder = true, back = true, chest = true, wrist = true, hands = true,
	waist = true, legs = true, feet = true, finger = true, trinket = true, onehand = true, twohand = true,
	ranged = true, offhand = true, shield = true, relic = true,
}
-- Group for everything that isn't gear, by the item's type
local GROUP_OF_TYPE = {
	Potion = "potion", Elixir = "elixir", Flask = "flask", ["Food & Drink"] = "food", Bandage = "bandage",
	Scroll = "scroll", ["Item Enhancement"] = "enhancement", Consumable = "consumable",
	Explosives = "explosives", Devices = "devices", Parts = "parts", ["Metal & Stone"] = "metal",
	Cloth = "cloth", Leather = "leather", Elemental = "elemental", Enchanting = "enchanting",
	Reagent = "reagent", Herb = "herb", Meat = "meat", ["Trade Goods"] = "tradegoods",
	Bag = "bag", ["Soul Bag"] = "bag", ["Herb Bag"] = "bag", ["Enchanting Bag"] = "bag", ["Engineering Bag"] = "bag",
	Quiver = "quiver", ["Ammo Pouch"] = "quiver", ["Ammo Arrow"] = "ammo", ["Ammo Bullet"] = "ammo",
	Shirt = "shirt", Tabard = "tabard", Pet = "pet", Mount = "mount", Holiday = "holiday", Quest = "quest",
	Recipe = "recipe", Key = "key", Miscellaneous = "misc", Junk = "misc",
}
local ENCHANT_GROUPS = {
	head = "Head Enchants", neck = "Neck Enchants", shoulder = "Shoulder Enchants", back = "Cloak Enchants",
	chest = "Chest Enchants", wrist = "Bracer Enchants", hands = "Glove Enchants", waist = "Belt Enchants",
	legs = "Leg Enchants", feet = "Boot Enchants", finger = "Ring Enchants", onehand = "Weapon Enchants",
	twohand = "Two-Hand Weapon Enchants", offhand = "Off-hand Enchants", shield = "Shield Enchants",
}

local GROUPS = {}
for rank, g in ipairs(GROUP_ORDER) do GROUPS[g[1]] = { key = g[1], label = g[2], rank = rank } end
for slot, label in pairs(ENCHANT_GROUPS) do
	GROUPS["enchant:" .. slot] = { key = "enchant:" .. slot, label = label, rank = GROUPS[slot].rank + 0.5 }
end

local groupOf = {}
local function GroupOf(rec)
	local group = groupOf[rec]
	if group then return group end
	local key
	if rec.item then
		local slot = K.SearchInfo(rec.item).slot
		local entry = ns.Items[rec.item]
		local typeText = entry and entry[3] or ""
		if GEAR_SLOTS[slot] then
			key = slot
		elseif GROUP_OF_TYPE[typeText] then
			key = GROUP_OF_TYPE[typeText]
		elseif typeText ~= "" then
			-- A type this list doesn't know yet gets a group of its own, just before Other
			key = "type:" .. typeText
			GROUPS[key] = GROUPS[key] or { key = key, label = typeText, rank = GROUPS.misc.rank + 0.5 }
		else
			key = "other"
		end
	elseif rec.slot then
		key = "enchant:" .. rec.slot
	else
		key = "other"
	end
	group = GROUPS[key] or GROUPS.other
	groupOf[rec] = group
	return group
end

-- How likely a skill-up is at your skill, in the colors the game uses
local SKILLUP = {
	red = C.red,
	orange = { 1, 0.5, 0.25 },
	yellow = { 1, 1, 0 },
	green = { 0.25, 0.75, 0.25 },
	grey = { 0.5, 0.5, 0.5 },
}

local function Tint(color, text)
	return ("|cff%02x%02x%02x%s|r"):format(color[1] * 255, color[2] * 255, color[3] * 255, text)
end

local CHANGED = { "CHANGED", C.steel }

-- Your rank in each profession, from the skills list. A collapsed Professions header
-- in the skills panel hides them; the skill colors just don't show then.
local skills
local function PlayerSkills()
	if skills then return skills end
	skills = {}
	if GetNumSkillLines and GetSkillLineInfo then
		for i = 1, GetNumSkillLines() do
			local name, header, _, rank, _, _, maxRank = GetSkillLineInfo(i)
			if name and not header then skills[name] = { rank = rank, max = maxRank } end
		end
	end
	return skills
end
K.PlayerSkills = PlayerSkills

local function SkillColor(rec, mine)
	if not (mine and rec.skill) then return nil end
	local rank, c = mine.rank, rec.colors
	if rank < rec.skill then return SKILLUP.red end
	if not c then return nil end
	if rank < c[2] then return SKILLUP.orange end
	if rank < c[3] then return SKILLUP.yellow end
	if rank < c[4] then return SKILLUP.green end
	return SKILLUP.grey
end

-- Where a recipe is learned, for the tooltip
local SOURCE_TEXT = {
	Vendor = "Learned from a recipe sold by vendors.",
	Drop = "Learned from a recipe that drops.",
	["World drop"] = "Learned from a recipe that's a world drop.",
	Quest = "Learned from a quest reward.",
	Fishing = "Learned from a recipe you can fish up.",
	Pickpocket = "Learned from a recipe you can pickpocket.",
	Crafted = "Learned from a recipe another profession makes.",
	Starter = "Wowhead lists no source. Recipes like this come with the profession.",
	Unknown = "No site has confirmed how it's learned yet.",
}

local function HowToLearn(rec, prof)
	local text
	if rec.train then
		text = "Taught by " .. prof.name .. " trainers" .. (rec.train > 0 and (" for " .. K.Money(rec.train)) or "") .. "."
	end
	local pattern = rec.pattern and ns.RecipeItems[rec.pattern]
	if pattern then
		local from = pattern[1] .. (pattern[3] ~= "" and (", " .. pattern[3]) or "") .. "."
		if pattern[3] == "" then from = from .. " Where it comes from isn't known yet." end
		text = text and (text .. " Also learned from " .. from) or ("Learned from " .. from)
	end
	text = text or SOURCE_TEXT[rec.src] or (rec.src .. ".")
	if rec.classic then text = text .. " (From Classic's data.)" end
	return text
end

local function MaterialsText(rec)
	local parts = {}
	for i = 1, #rec.mats, 2 do
		parts[#parts + 1] = ns.Colorize(C.light, rec.mats[i + 1]) .. " " .. ns.ItemDisplay(rec.mats[i])
	end
	return table.concat(parts, ", ")
end

----------------------------------------------------------------------
-- Recipe rows: what it makes, the skill it needs, where it's learned, and the materials
----------------------------------------------------------------------
local function CreateRecipe(parent, width)
	local r = CreateFrame("Button", nil, parent)
	r:SetSize(width, RECIPE_H)
	r.isForeverLootRow = true
	r.isForeverLootItem = true
	r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	r.hover = Tex(r, "BACKGROUND", C.blue, 0.22)
	r.hover:SetAllPoints()
	r.hover:Hide()
	-- Red bar on the left: what it makes is on your wishlist
	r.wanted = Tex(r, "ARTWORK", C.red, 1)
	r.wanted:SetPoint("TOPLEFT")
	r.wanted:SetPoint("BOTTOMLEFT")
	r.wanted:SetWidth(3)
	r.wanted:Hide()
	local iconFrame = CreateFrame("Frame", nil, r)
	iconFrame:SetSize(30, 30)
	iconFrame:SetPoint("LEFT", 8, 0)
	Tex(iconFrame, "BACKGROUND", C.black, 1):SetAllPoints()
	r.icon = iconFrame:CreateTexture(nil, "ARTWORK")
	r.icon:SetPoint("TOPLEFT", 1, -1)
	r.icon:SetPoint("BOTTOMRIGHT", -1, 1)
	r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	r.src = Text(r, Font("recipe_src", GameFontHighlightSmall, C.mist, 10), "RIGHT")
	r.src:SetPoint("RIGHT", r, "TOPRIGHT", -8, -13)
	r.src:SetWidth(64)
	r.skill = Text(r, Font("recipe_skill", GameFontHighlight, C.light, 12), "RIGHT")
	r.skill:SetPoint("RIGHT", r.src, "LEFT", -8, 0)
	r.skill:SetWidth(30)
	r.type = Text(r, Font("item_type", GameFontHighlightSmall, C.mist, 11), "RIGHT")
	r.type:SetPoint("RIGHT", r.skill, "LEFT", -10, 0)
	r.badge = CreateFrame("Frame", nil, r)
	r.badge:SetSize(40, 14)
	r.badge:SetPoint("RIGHT", r.type, "LEFT", -8, 0)
	r.badge.bg = Tex(r.badge, "BACKGROUND", C.red, 1)
	r.badge.bg:SetAllPoints()
	r.badge.text = Text(r.badge, Font("badge", GameFontHighlightSmall, C.light, 9), "CENTER")
	r.badge.text:SetPoint("CENTER")
	r.name = Text(r, Font("item_name", GameFontHighlight, C.light, 12))
	r.mats = Text(r, Font("recipe_mats", GameFontHighlightSmall, C.mist, 10))
	r.mats:SetPoint("LEFT", r, "TOPLEFT", 46, -28)
	r.mats:SetPoint("RIGHT", r, "TOPRIGHT", -8, -28)

	r:SetScript("OnEnter", function(self)
		self.hover:Show()
		local d = self.entry
		if not d then return end
		local rec, prof = d.recipe, d.prof
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		local bundled
		if rec.item then
			bundled = K.ItemTooltip(rec.item)
		else
			GameTooltip:AddLine(rec.name, C.light[1], C.light[2], C.light[3])
			if rec.desc then
				GameTooltip:AddLine(rec.desc, 1, 1, 1, true)
			elseif not rec.slot then
				GameTooltip:AddLine("Wowhead doesn't list the item this makes yet.", C.mist[1], C.mist[2], C.mist[3], true)
			end
		end

		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("Materials", C.light[1], C.light[2], C.light[3])
		for i = 1, #rec.mats, 2 do
			local id, n = rec.mats[i], rec.mats[i + 1]
			local name, quality = ns.ItemDisplay(id)
			local have = ns.GetItemCount and ns.GetItemCount(id) or 0
			local qr, qg, qb = K.HexToRGB(ns.QUALITY_HEX[quality] or "ffffff")
			GameTooltip:AddDoubleLine(n .. " x " .. name, have > 0 and ("you have " .. have) or " ",
				qr, qg, qb, C.mist[1], C.mist[2], C.mist[3])
		end

		local notes = {}
		if rec.item and ns.ItemDisplay(rec.item) ~= rec.name then
			notes[#notes + 1] = { "Recipe: " .. rec.name, C.light }
		end
		if rec.makes then notes[#notes + 1] = { "Makes " .. rec.makes .. " at a time.", C.mist } end
		if rec.skill then
			local line = prof.name .. " " .. rec.skill .. " to learn."
			local c = rec.colors
			if c then
				line = line .. " " .. Tint(SKILLUP.yellow, "Yellow") .. " at " .. c[2] .. ", " ..
					Tint(SKILLUP.green, "green") .. " at " .. c[3] .. ", " .. Tint(SKILLUP.grey, "grey") .. " at " .. c[4] .. "."
			end
			if d.mine then line = line .. " You're at " .. d.mine.rank .. "." end
			notes[#notes + 1] = { line, C.mist }
		else
			notes[#notes + 1] = { "The skill it needs isn't known yet.", C.mist }
		end
		notes[#notes + 1] = { HowToLearn(rec, prof), C.mist }
		if rec.status == "new" then
			notes[#notes + 1] = { "New in Forever.", C.red }
		elseif rec.status == "changed" then
			notes[#notes + 1] = { "Changed in Forever" .. (rec.changes and (": " .. table.concat(rec.changes, "; ")) or "") .. ".", C.mist }
		end
		if bundled then
			notes[#notes + 1] = { "The beta server isn't sending this item's data, so these stats come from Wowhead.", C.mist }
		end
		if d.owned then notes[#notes + 1] = { "You have it: it's in your bags, bank or worn.", C.light } end
		if rec.item then notes[#notes + 1] = K.WishlistNote(rec.item) end
		K.AddNotes(notes)
		GameTooltip:Show()
	end)
	r:SetScript("OnLeave", function(self)
		self.hover:Hide()
		GameTooltip:Hide()
	end)
	r:SetScript("OnClick", function(self, button)
		local rec = self.entry and self.entry.recipe
		if not rec then return end
		if button == "RightButton" and not IsModifierKeyDown() then
			if rec.item then
				UI:ToggleWanted(rec.item)
			else
				ns:Print(rec.name .. " doesn't make an item, so it can't go on the wishlist.")
			end
			return
		end
		if IsModifierKeyDown() then
			if rec.item then
				K.ItemModifiedClick(rec.item)
				return
			end
			-- Recipes that make no item (enchants) can still be linked as a spell
			local link = GetSpellLink and GetSpellLink(rec.id)
			if not (link and IsShiftKeyDown() and ChatEdit_InsertLink and ChatEdit_InsertLink(link)) then
				ns:Print(rec.name .. " doesn't make an item to link.")
			end
			return
		end
		UI:ShowURL(rec.name .. " on Wowhead", ns.WOWHEAD .. "spell=" .. rec.id)
	end)
	return r
end

-- data: recipe, prof (its profession), mine (your skill in it, if you have it), owned (Wishlist tab)
local function FillRecipe(r, d)
	local rec = d.recipe
	r.itemID = rec.item
	local name, quality, typeText, icon
	if rec.item then
		name, quality, typeText, icon = ns.ItemDisplay(rec.item)
		r.name:SetTextColor(K.HexToRGB(ns.QUALITY_HEX[quality] or "ffffff"))
	else
		name, typeText = rec.name, rec.slot and "Enchant" or ""
		icon = rec.icon or "Interface\\Icons\\INV_Misc_QuestionMark"
		SetTextColor(r.name, C.light)
	end
	if rec.makes then name = name .. ns.Colorize(C.mist, "  x" .. rec.makes) end
	r.name:SetText(name)
	r.icon:SetTexture(icon)
	r.type:SetText(typeText or "")
	r.skill:SetText(rec.skill or "?")
	SetTextColor(r.skill, SkillColor(rec, d.mine) or C.light)
	r.src:SetText(rec.src)

	r.wanted:SetShown(rec.item ~= nil and ns.Wishlist.IsWanted(rec.item))
	local badge = (d.owned and K.BADGES.owned) or (rec.status == "new" and K.BADGES.new) or (rec.status == "changed" and CHANGED) or nil
	r.name:ClearAllPoints()
	r.name:SetPoint("LEFT", r, "TOPLEFT", 46, -13)
	if badge then
		r.badge.text:SetText(badge[1])
		r.badge.bg:SetColorTexture(badge[2][1], badge[2][2], badge[2][3], 1)
		r.badge:SetWidth(r.badge.text:GetStringWidth() + 10)
		r.badge:Show()
		r.name:SetPoint("RIGHT", r.badge, "LEFT", -6, 0)
	else
		r.badge:Hide()
		r.name:SetPoint("RIGHT", r.type, "LEFT", -8, 0)
	end
	r.mats:SetText(MaterialsText(rec))
end

K.RegisterKind("recipe", CreateRecipe, FillRecipe, true)

----------------------------------------------------------------------
-- Search: a recipe is found by what it makes (name, slot, type, stats), its own name,
-- its materials, its profession and where it's learned
----------------------------------------------------------------------
local recipeInfo = {}
local function RecipeInfo(rec, prof)
	local info = recipeInfo[rec]
	if info then return info end
	local words = { rec.name, prof.name, rec.src, rec.status }
	local slot, kind
	if rec.item then
		local base = K.SearchInfo(rec.item)
		slot, kind = base.slot, base.kind
		words[#words + 1] = base.words
	else
		slot = rec.slot or "other"
		words[#words + 1] = K.SlotWords(slot)
	end
	for i = 1, #rec.mats, 2 do
		local entry = ns.Items[rec.mats[i]]
		words[#words + 1] = entry and entry[1]
	end
	info = { slot = slot, kind = kind, words = K.Simplify(table.concat(words, " ")) }
	recipeInfo[rec] = info
	return info
end

----------------------------------------------------------------------
-- The tab
----------------------------------------------------------------------
local professions = ns.Professions

local Professions = {
	key = "professions",
	tab = "Professions",
	listTitle = "PROFESSIONS",
	listRight = "RECIPES",
	allLabel = "All professions",
	unit = "recipe",
	groupUnit = "profession",
	searchHint = "Search every recipe, e.g. copper bar",
	searchAbout = "The search looks at recipe and item names, materials, slots, types and stats.",
	noMatch = {
		"No recipe in any profession matches that.",
		"Try a material like copper bar, a slot like gloves, a type like leather, or a stat like agility.",
	},
	footer = "Click: Wowhead link    Shift-click: link in chat    Right-click: wishlist    " .. ns.Colorize(C.red, "Red bar") ..
		": your professions    Skill color: skill-up chance",
}

function Professions.dataDate()
	return ns.PROFESSION_DATE
end

function Professions.Entries()
	return professions
end

function Professions.RowInfo(p)
	return p.name, #p.recipes, "", PlayerSkills()[p.name] ~= nil
end

-- Crafting professions come before Cooking and First Aid, and those before gathering,
-- which has only a handful of recipes
local PRIORITY = { COOK = 2, FA = 2, MINE = 3, HERB = 3, SKIN = 3 }

-- The profession you looked at last, else your best crafting one, else the first
function Professions.Default()
	local last = ns.db.lastProfession and ns.ProfessionByKey[ns.db.lastProfession]
	if last then return last end
	local best, bestKey
	for _, p in ipairs(professions) do
		local mine = PlayerSkills()[p.name]
		if mine then
			local key = { PRIORITY[p.key] or 1, -mine.rank }
			if not bestKey or key[1] < bestKey[1] or (key[1] == bestKey[1] and key[2] < bestKey[2]) then
				best, bestKey = p, key
			end
		end
	end
	return best or professions[1]
end

function Professions.Remember(p)
	ns.db.lastProfession = p.key
end

function Professions.WowheadLink(p)
	return p.name .. " on Wowhead", ns.WOWHEAD .. "skill=" .. p.skill
end

function Professions.ShowHeader(ui, h, p)
	h.name:SetText(p.name)
	local trained = 0
	for _, rec in ipairs(p.recipes) do
		if rec.train then trained = trained + 1 end
	end
	local parts = { Count(#p.recipes, "recipe"), trained .. " from trainers" }
	local mine = PlayerSkills()[p.name]
	if mine then parts[#parts + 1] = "Your skill " .. mine.rank .. "/" .. mine.max end
	h.meta:SetText(table.concat(parts, "   ·   "))
	h.note:SetText("Forever's recipes, materials and sources from Wowhead (" .. (ns.PROFESSION_DATE or "") .. "). " ..
		ns.Colorize(C.red, "NEW") .. " = added in Forever. " .. ns.Colorize(C.light, "CHANGED") ..
		" = different from Classic. " ..
		(mine and "Skill numbers are colored by your chance of a skill-up." or "Numbers are the skill each recipe needs."))
end

-- One collapsible section per group, collapsed until opened (a profession with a single
-- group shows it open); recipes keep their skill order inside it
function Professions.Render(ui, p)
	local mine = PlayerSkills()[p.name]
	local sections, byGroup = {}, {}
	for _, rec in ipairs(p.recipes) do
		local group = GroupOf(rec)
		local section = byGroup[group]
		if not section then
			section = { group = group, recipes = {} }
			byGroup[group] = section
			sections[#sections + 1] = section
		end
		section.recipes[#section.recipes + 1] = rec
	end
	table.sort(sections, function(a, b)
		if a.group.rank ~= b.group.rank then return a.group.rank < b.group.rank end
		return a.group.label < b.group.label
	end)
	for _, section in ipairs(sections) do
		if ui.contentY > 0 then ui:AddGap(SECTION_GAP) end
		local collapsed = ui:AddSection("p:" .. p.key .. ":" .. section.group.key, section.group.label:upper(),
			Count(#section.recipes, "recipe"), #sections == 1)
		if not collapsed then
			for _, rec in ipairs(section.recipes) do
				ui:AddEntry("recipe", RECIPE_H, { recipe = rec, prof = p, mine = mine })
			end
		end
	end
	if #p.recipes == 0 then
		ui:AddEntry("note", NOTE_H, { text = "Wowhead lists no recipes for this profession yet." })
	end
end

function Professions.Find(filter)
	local terms = K.ParseQuery(filter.text)
	local groups, total = {}, 0
	for _, p in ipairs(professions) do
		local rows, mine = {}, PlayerSkills()[p.name]
		for _, rec in ipairs(p.recipes) do
			local extra = rec.item and ns.Wishlist.IsWanted(rec.item) and " wanted wishlist "
			if K.Matches(RecipeInfo(rec, p), terms, filter, extra) then
				rows[#rows + 1] = { recipe = rec, prof = p, mine = mine }
			end
		end
		if #rows > 0 then
			groups[#groups + 1] = { entry = p, rows = rows }
			total = total + #rows
		end
	end
	return groups, total
end

function Professions.AddResults(ui, g)
	if ui.contentY > 0 then ui:AddGap(SECTION_GAP) end
	if ui:AddSection("s:p:" .. g.entry.key, g.entry.name:upper(), Count(#g.rows, "recipe"), true) then return end
	for _, row in ipairs(g.rows) do ui:AddEntry("recipe", RECIPE_H, row) end
end

UI:RegisterMode(Professions)

-- Skill-ups and new professions change the colors and the red bars
local events = CreateFrame("Frame")
pcall(events.RegisterEvent, events, "SKILL_LINES_CHANGED")
events:SetScript("OnEvent", function()
	skills = nil
	if UI.mode == "professions" and UI.frame and UI.frame:IsShown() then
		UI:Refresh()
		if not UI:IsSearching() and UI.current then
			Professions.ShowHeader(UI, UI.header, UI.current)
			UI:BuildList()
		end
	end
end)
