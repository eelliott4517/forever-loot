local ADDON, ns = ...
local C = ns.COLORS

local UI = {}
ns.UI = UI

-- Building blocks the tab files share (Professions.lua uses them)
local K = {}
ns.UIKit = K

-- Each tab in the title bar is a mode with its own list, detail view and search.
-- The Dungeons and Raids tabs are at the bottom of this file; Sets.lua, Professions.lua and
-- Wishlist.lua add the others.
UI.modes, UI.modeOrder = {}, {}
function UI:RegisterMode(mode)
	self.modes[mode.key] = mode
	self.modeOrder[#self.modeOrder + 1] = mode.key
end

-- What the search box and the Slot / Type filters ask for. Both tabs share it;
-- `focus` narrows the results to one entry of the list (a dungeon or a profession).
UI.filter = { text = "" }
-- The entry each tab last had open
UI.selected = {}
-- Sections the player opened or closed (id -> true open, false closed). Every section starts
-- collapsed (bosses, quests, wings, groups, search results) and opens on click. What's open lasts
-- the session; search results forget it with each new search.
UI.sections, UI.searchSections = {}, {}

-- The window is built from the game's own templates (portrait frame, insets, side tabs,
-- search box, dropdowns, checkboxes, scroll bars), so it takes on WoW: Forever's own art
local WIDTH, HEIGHT = 880, 600
local TOP_H, FOOTER_H = 60, 26
local LIST_W = 272
local LIST_ROW_H = 22
local HEADER_H = 96
local WING_H = 26
local BOSS_H = 28
local ITEM_H = 28
local NOTE_H = 22
local SECTION_GAP = 10
local SEARCH_H = 20
local QUEST_H = 26
local SOURCE_W = 140
local PAINT_PAD = 60
local SCROLLBAR_W = 18
K.WING_H, K.ITEM_H, K.NOTE_H, K.SECTION_GAP = WING_H, ITEM_H, NOTE_H, SECTION_GAP

----------------------------------------------------------------------
-- Small widget helpers
----------------------------------------------------------------------
local function Tex(parent, layer, color, alpha)
	local t = parent:CreateTexture(nil, layer or "BACKGROUND")
	t:SetColorTexture(color[1], color[2], color[3], alpha or 1)
	return t
end

-- A texture from the game's atlases: the same pieces Blizzard's lists and headers use
local function Atlas(parent, layer, atlas, alpha)
	local t = parent:CreateTexture(nil, layer or "ARTWORK")
	t:SetAtlas(atlas)
	if alpha then t:SetAlpha(alpha) end
	return t
end

-- The game's font objects by name, so text matches the rest of the interface
local function Font(name)
	return _G[name] or GameFontHighlight
end

local function Text(parent, font, justify)
	local fs = parent:CreateFontString(nil, "OVERLAY")
	fs:SetFontObject(type(font) == "string" and Font(font) or font)
	fs:SetJustifyH(justify or "LEFT")
	fs:SetWordWrap(false)
	return fs
end

local function SetTextColor(fs, color)
	fs:SetTextColor(color[1], color[2], color[3])
end

local function HexToRGB(hex)
	return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
end

local function Count(n, word)
	return n .. " " .. word .. (n == 1 and "" or "s")
end

local function Money(copper)
	local parts = {}
	local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
	if g > 0 then parts[#parts + 1] = g .. "g" end
	if s > 0 then parts[#parts + 1] = s .. "s" end
	if c > 0 or #parts == 0 then parts[#parts + 1] = c .. "c" end
	return table.concat(parts, " ")
end

-- The standard red panel button
local function PanelButton(parent, label, width)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width, 22)
	b:SetText(label)
	return b
end

-- A tooltip in the game's style: a white title, gold text under it
local function ShowHint(owner, title, line)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:SetText(title, C.white[1], C.white[2], C.white[3])
	if line then GameTooltip:AddLine(line, C.gold[1], C.gold[2], C.gold[3], true) end
	GameTooltip:Show()
end

-- The hover and selection art of Blizzard's own lists (the Professions recipe list)
local function RowHighlight(row, alpha)
	local h = Atlas(row, "HIGHLIGHT", "Professions_Recipe_Hover", alpha or 0.5)
	h:SetAllPoints()
	return h
end

-- Difficulty colors for a level, as the quest log colors quests (and falls back to its
-- rules where the client doesn't expose them)
local DIFFICULTY = {
	impossible = { 1.00, 0.10, 0.10 }, verydifficult = { 1.00, 0.50, 0.25 }, difficult = { 1.00, 0.82, 0.00 },
	standard = { 0.25, 0.75, 0.25 }, trivial = { 0.50, 0.50, 0.50 },
}
local function GreenRange(level)
	if GetQuestGreenRange then return GetQuestGreenRange() end
	if level <= 5 then return 5 elseif level <= 39 then return math.floor(level / 10) + 5 end
	return math.floor(level / 5) + 1
end
local function DifficultyKey(level)
	local player = UnitLevel("player") or 1
	local diff = level - player
	if diff >= 5 then return "impossible"
	elseif diff >= 3 then return "verydifficult"
	elseif diff >= -2 then return "difficult"
	elseif -diff <= GreenRange(player) then return "standard" end
	return "trivial"
end
local function DifficultyColor(level)
	local key = DifficultyKey(level)
	local c = QuestDifficultyColors and QuestDifficultyColors[key]
	if c then return { c.r, c.g, c.b } end
	return DIFFICULTY[key]
end

K.Tex, K.Atlas, K.Font, K.Text, K.SetTextColor, K.HexToRGB = Tex, Atlas, Font, Text, SetTextColor, HexToRGB
K.Count, K.Money, K.ShowHint, K.PanelButton, K.RowHighlight = Count, Money, ShowHint, PanelButton, RowHighlight
K.DifficultyColor, K.DifficultyKey = DifficultyColor, DifficultyKey

-- A ScrollFrame with the game's minimal scroll bar (ScrollFrameTemplate wires the bar and the
-- mouse wheel); the bar sits just right of it
local function CreateScrollArea(parent, contentWidth)
	local sf = CreateFrame("ScrollFrame", nil, parent, "ScrollFrameTemplate")
	if sf.ScrollBar and sf.ScrollBar.SetHideIfUnscrollable then sf.ScrollBar:SetHideIfUnscrollable(true) end
	local content = CreateFrame("Frame", nil, sf)
	content:SetSize(contentWidth, 1)
	sf:SetScrollChild(content)
	sf.content = content

	function sf:SetContentHeight(h)
		content:SetHeight(math.max(h, 1))
		self:UpdateScrollChildRect()
		local range = self:GetVerticalScrollRange()
		if self:GetVerticalScroll() > range then self:SetVerticalScroll(range) end
	end

	-- Scrolls to an offset, kept inside the content
	function sf:ScrollTo(offset)
		self:SetVerticalScroll(math.max(0, math.min(offset, self:GetVerticalScrollRange())))
	end

	function sf:ScrollToTop()
		self:SetVerticalScroll(0)
	end

	sf:HookScript("OnVerticalScroll", function(self)
		if self.onScrolled then self:onScrolled() end
	end)
	return sf
end

----------------------------------------------------------------------
-- Item helpers
----------------------------------------------------------------------
local WEAPON_TYPES = {
	INVTYPE_WEAPON = "One-Hand", INVTYPE_2HWEAPON = "Two-Hand",
	INVTYPE_WEAPONMAINHAND = "Main Hand", INVTYPE_WEAPONOFFHAND = "Off Hand",
}

local function TypeTextFromClient(itemID)
	local _, itemType, subType, equipLoc = ns.GetItemInfoInstant(itemID)
	if not itemType then return "" end
	local slot = equipLoc and equipLoc ~= "" and _G[equipLoc]
	if WEAPON_TYPES[equipLoc] and subType then
		return subType
	elseif slot and subType and (subType == "Cloth" or subType == "Leather" or subType == "Mail" or subType == "Plate") then
		return subType .. " " .. slot
	end
	return slot or subType or itemType or ""
end

-- Items the server has answered "no data" for (Classic items Forever removed).
-- The client can still know the item id, but the server will never send its stats.
local noServerData = {}

function ns.MarkNoServerData(itemID)
	noServerData[itemID] = true
end

function ns.HasNoServerData(itemID)
	return noServerData[itemID] == true
end

-- Returns display info plus `live`: true when the server has sent real item data.
-- Classic items Forever removed never get live data, so they use the name, icon and
-- tooltip text bundled in Data.lua.
function ns.ItemDisplay(itemID)
	local entry = ns.Items[itemID]
	local classicOnly = entry and entry[4] == 2
	local name, link, quality
	if not noServerData[itemID] then
		name, link, quality = ns.GetItemInfo(itemID)
		if not name then ns.RequestItem(itemID) end
	end
	local live = name ~= nil
	local icon
	if live or not classicOnly then
		icon = (ns.GetItemIcon and ns.GetItemIcon(itemID)) or select(5, ns.GetItemInfoInstant(itemID))
	end
	icon = icon or (entry and entry[6])
	name = name or (entry and entry[1]) or ("Item #" .. itemID)
	quality = quality or (entry and entry[2]) or 1
	local typeText = (entry and entry[3]) or TypeTextFromClient(itemID)
	return name, quality, typeText, icon or "Interface\\Icons\\INV_Misc_QuestionMark", link, live
end

local function FormatPct(p)
	return (("%.1f"):format(p):gsub("%.0$", "")) .. "%"
end

-- Item flags from Data.lua: 1 new in Forever, 2 Classic only, 3 new with no confirmed boss.
-- Shown as a colored word next to the item's name.
local BADGES = {
	owned = { "Owned", C.blue },
	seen = { "Seen", C.blue },
	new = { "New", C.green },
	classic = { "Classic", C.grey },
}
K.BADGES = BADGES

-- The tooltip line under any item that can go on the wishlist
function K.WishlistNote(itemID)
	if ns.Wishlist.IsWanted(itemID) then
		return { "On your wishlist. Right-click to take it off.", C.white }
	end
	return { "Right-click to add it to your wishlist.", C.green }
end

-- The item part of a row's tooltip: the game's own once the server has sent the item,
-- otherwise the lines bundled with the addon (the game's would sit on "Retrieving item
-- information", often forever on the beta). Returns true when it used the bundled lines.
function K.ItemTooltip(itemID)
	local entry = ns.Items[itemID]
	local name, quality, _, _, _, live = ns.ItemDisplay(itemID)
	local bundled = not live and entry ~= nil and entry[7] ~= nil
	if not bundled then
		if GameTooltip.SetItemByID then
			GameTooltip:SetItemByID(itemID)
		else
			GameTooltip:SetHyperlink("item:" .. itemID)
		end
	else
		GameTooltip:AddLine(name, HexToRGB(ns.QUALITY_HEX[quality] or "ffffff"))
		for _, line in ipairs(entry[7]) do
			local left, right = line:match("^(.-)\t(.*)$")
			if left then
				GameTooltip:AddDoubleLine(left, right, 1, 1, 1, 1, 1, 1)
			else
				GameTooltip:AddLine(line, 1, 1, 1, true)
			end
		end
	end
	return bundled
end

-- A spaced block of { text, color } notes under a tooltip
function K.AddNotes(notes)
	if #notes == 0 then return end
	GameTooltip:AddLine(" ")
	for _, n in ipairs(notes) do GameTooltip:AddLine(n[1], n[2][1], n[2][2], n[2][3], true) end
end

-- Shift-click links an item, Ctrl-click previews it. Returns true when a modifier was held.
function K.ItemModifiedClick(itemID)
	if not IsModifierKeyDown() then return false end
	local name, _, _, _, link = ns.ItemDisplay(itemID)
	local entry = ns.Items[itemID]
	if link then
		HandleModifiedItemClick(link)
	elseif entry and entry[4] == 2 then
		ns:Print(name .. " isn't in Forever's game data, so it can't be linked.")
	elseif ns.HasNoServerData(itemID) then
		ns:Print("the beta server has no data for " .. name .. ", so it can't be linked.")
	else
		ns:Print("item data is still loading. Try again in a moment.")
	end
	return true
end

----------------------------------------------------------------------
-- Wowhead link dialog (WoW can't open a browser, so give a copyable URL). It's the
-- game's own popup with an edit box, like the ones for sharing a link or naming a set.
----------------------------------------------------------------------
local URL_DIALOG = "FOREVERLOOT_WOWHEAD_LINK"

local function DialogEditBox(dialog)
	return (dialog.GetEditBox and dialog:GetEditBox()) or dialog.editBox or dialog.EditBox
end

if StaticPopupDialogs then
	StaticPopupDialogs[URL_DIALOG] = {
		text = "%s|n|nPress Ctrl+C (Cmd+C on a Mac) to copy the link, then paste it into your browser.",
		button1 = CLOSE or "Close",
		hasEditBox = 1,
		editBoxWidth = 350,
		OnShow = function(dialog, data)
			local box = DialogEditBox(dialog)
			if box and data then
				box:SetText(data.url)
				box:HighlightText()
				box:SetFocus()
			end
		end,
		-- The link can't be edited away: typing puts it back
		EditBoxOnTextChanged = function(box, data)
			if data and box:GetText() ~= data.url then
				box:SetText(data.url)
				box:HighlightText()
			end
		end,
		EditBoxOnEnterPressed = function(box) box:GetParent():Hide() end,
		EditBoxOnEscapePressed = function(box) box:GetParent():Hide() end,
		timeout = 0,
		whileDead = 1,
		hideOnEscape = 1,
	}
end

function UI:ShowURL(title, url)
	self.lastURL = { title = title, url = url }
	if StaticPopup_Show and StaticPopupDialogs and StaticPopupDialogs[URL_DIALOG] then
		StaticPopup_Show(URL_DIALOG, title, nil, { url = url })
	else
		ns:Print(title .. ": " .. url)
	end
end

----------------------------------------------------------------------
-- Search box and the Slot / Type filter menus
----------------------------------------------------------------------
-- Menu entries. Each key matches what the search index works out for an item.
-- The Other group differs per tab: crafting makes consumables and trade goods.
local FILTER_MENUS = {
	slot = {
		label = "Slot", all = "All slots",
		{ "Armor", { "head", "Head" }, { "neck", "Neck" }, { "shoulder", "Shoulder" }, { "back", "Back" },
			{ "chest", "Chest" }, { "wrist", "Wrist" }, { "hands", "Hands" }, { "waist", "Waist" },
			{ "legs", "Legs" }, { "feet", "Feet" }, { "finger", "Finger" }, { "trinket", "Trinket" } },
		{ "Weapons", { "onehand", "One-Hand" }, { "twohand", "Two-Hand" }, { "ranged", "Ranged" },
			{ "offhand", "Off-hand" }, { "shield", "Shield" }, { "relic", "Relic" } },
		other = {
			dungeons = { "Other", { "recipe", "Recipe" }, { "other", "Other" } },
			quests = { "Other", { "recipe", "Recipe" }, { "other", "Other" } },
			professions = { "Other", { "consumable", "Consumable" }, { "tradegoods", "Trade Goods" },
				{ "bag", "Bag" }, { "other", "Other" } },
		},
	},
	kind = {
		label = "Type", all = "All types",
		{ "Armor", { "cloth", "Cloth" }, { "leather", "Leather" }, { "mail", "Mail" }, { "plate", "Plate" } },
		{ "Weapons", { "axe", "Axe" }, { "bow", "Bow" }, { "crossbow", "Crossbow" }, { "dagger", "Dagger" },
			{ "fist", "Fist Weapon" }, { "gun", "Gun" }, { "mace", "Mace" }, { "polearm", "Polearm" },
			{ "staff", "Staff" }, { "sword", "Sword" }, { "thrown", "Thrown" }, { "wand", "Wand" } },
		other = {},
	},
}

-- The groups a menu shows in one tab
local function MenuGroups(which, modeKey)
	local menu, groups = FILTER_MENUS[which], {}
	for _, group in ipairs(menu) do groups[#groups + 1] = group end
	groups[#groups + 1] = menu.other[modeKey]
	return groups
end

local function MenuOffers(which, modeKey, key)
	for _, group in ipairs(MenuGroups(which, modeKey)) do
		for i = 2, #group do
			if group[i][1] == key then return true end
		end
	end
	return false
end

-- key -> display name, for the button labels and the results header
for _, menu in pairs(FILTER_MENUS) do
	menu.names = {}
	local groups = {}
	for _, group in ipairs(menu) do groups[#groups + 1] = group end
	for _, group in pairs(menu.other) do groups[#groups + 1] = group end
	for _, group in ipairs(groups) do
		for i = 2, #group do menu.names[group[i][1]] = group[i][2] end
	end
end

-- The game's search box: magnifier, grey hint text and the clear button come with it
local function CreateSearchBox(parent)
	local eb = CreateFrame("EditBox", "ForeverLootSearchBox", parent, "SearchBoxTemplate")
	eb:SetHeight(SEARCH_H)
	eb:SetMaxLetters(60)
	-- Typing and the clear button both land here (the clear button sets the text to "")
	eb:HookScript("OnTextChanged", function(self)
		UI:SetSearchText(self:GetText())
	end)
	return eb
end

-- A Slot or Type dropdown on Blizzard's menu system, with its choices grouped under titles
local function CreateDropdown(parent, which, width)
	local spec = FILTER_MENUS[which]
	local d = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
	d:SetWidth(width)
	d.which = which
	d:SetDefaultText(spec.all)
	local function IsSelected(key) return UI.filter[which] == key end
	local function SetSelected(key) UI:SetFilter(which, key, true) end
	d:SetupMenu(function(_, root)
		root:CreateRadio(spec.all, function() return UI.filter[which] == nil end, function() UI:SetFilter(which, nil, true) end)
		for _, group in ipairs(MenuGroups(which, UI.mode)) do
			root:CreateTitle(group[1])
			for i = 2, #group do root:CreateRadio(group[i][2], IsSelected, SetSelected, group[i][1]) end
		end
	end)
	-- "Slot: Hands" on the button once something is picked
	d:SetSelectionTranslator(function(selection)
		if selection.data == nil then return spec.all end
		return spec.label .. ": " .. (spec.names[selection.data] or selection.text or "")
	end)
	return d
end

-- A checkbox for the loot filters (My class, Hide Classic)
local function CreateToggle(parent, key, label)
	local b = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	b:SetSize(24, 24)
	b.key = key
	b.Text:SetText(label)
	b:SetScript("OnEnter", function(self)
		ShowHint(self, label, self.Hint and self.Hint())
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	b:SetScript("OnClick", function(self)
		if SOUNDKIT then
			PlaySound(self:GetChecked() and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
		end
		UI:ClearSearchFocus()
		UI:ToggleFilter(self.key)
	end)
	return b
end

-- Closes a dropdown menu that's open (the menu system closes it anyway when the window hides)
function UI:CloseMenu()
	for _, d in pairs(self.filterButtons or {}) do
		if d.IsMenuOpen and d:IsMenuOpen() then d:CloseMenu() end
	end
end

-- The dropdowns show whatever the filter is now (after a search reset or a tab switch)
function UI:UpdateFilterButtons()
	for _, d in pairs(self.filterButtons or {}) do
		if d.GenerateMenu then d:GenerateMenu() end
	end
end

function UI:UpdateToggles()
	local f = K.Filters()
	for key, t in pairs(self.toggles or {}) do
		t:SetChecked(f[key] and true or false)
	end
end

-- My class / Hide Classic: redraw the open entry (or the search) with the new filter
function UI:ToggleFilter(key)
	local f = K.Filters()
	f[key] = not f[key]
	self:UpdateToggles()
	if not (self.frame and self.frame:IsShown()) then return end
	if self:IsSearching() then
		self:Refresh()
	else
		self:BuildList()
		if self.current then
			self:Mode().ShowHeader(self, self.header, self.current)
			self:Refresh()
		end
	end
end

function UI:ClearSearchFocus()
	if self.searchBox then self.searchBox:ClearFocus() end
end

----------------------------------------------------------------------
-- Main window
----------------------------------------------------------------------
function UI:Mode()
	return self.modes[self.mode]
end

function UI:Create()
	if self.frame then return self.frame end
	self.mode = (ns.db.mode and self.modes[ns.db.mode]) and ns.db.mode or self.modeOrder[1]

	-- A portrait frame like the game's own windows: title, portrait and close button included
	local f = CreateFrame("Frame", "ForeverLootFrame", UIParent, "PortraitFrameTemplate")
	f:SetSize(WIDTH, HEIGHT)
	-- Blizzard's panels' layer, so the dressing room from Ctrl-click (and any other window you
	-- open) comes up in front instead of under it; clicking brings this back to the front
	f:SetFrameStrata("MEDIUM")
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:Hide()
	self.frame = f
	self:ResetPosition(true)
	tinsert(UISpecialFrames, "ForeverLootFrame")
	if f.SetTitle then f:SetTitle(ns.name) end
	if f.SetPortraitToAsset then f:SetPortraitToAsset(ns.ICON) end
	-- The close button goes through UI:Hide, for its sound
	f.onCloseCallback = function()
		UI:Hide()
		return false
	end

	-- Drag the window by its title bar
	local drag = CreateFrame("Frame", nil, f)
	drag:SetPoint("TOPLEFT", 60, 0)
	drag:SetPoint("TOPRIGHT", -28, 0)
	drag:SetHeight(22)
	drag:EnableMouse(true)
	drag:RegisterForDrag("LeftButton")
	drag:SetScript("OnDragStart", function() f:StartMoving() end)
	drag:SetScript("OnDragStop", function() f:StopMovingOrSizing(); UI:SavePosition() end)

	-- A side tab per mode, down the right edge, as on the game's Character and Collections windows
	self.tabs = {}
	local previous
	for _, key in ipairs(self.modeOrder) do
		local mode = self.modes[key]
		local t = CreateFrame("Frame", nil, f, "LargeSideTabButtonTemplate")
		t.key = key
		t.tooltipText = mode.tab
		t.Icon:SetTexture(mode.icon or ns.ICON)
		if t.SetFillToInterior then t:SetFillToInterior(true) end
		t:SetCustomOnMouseUpHandler(function(tab, button, upInside)
			if button == "LeftButton" and upInside then
				UI:ClearSearchFocus()
				UI:SetMode(tab.key)
			end
		end)
		if previous then
			t:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -2)
		else
			t:SetPoint("TOPLEFT", f, "TOPRIGHT", 0, -TOP_H)
		end
		previous = t
		self.tabs[#self.tabs + 1] = t
	end

	-- Top bar: search, the Slot and Type dropdowns, and the loot filters
	local search = CreateSearchBox(f)
	search:SetPoint("TOPLEFT", 68, -31)
	search:SetWidth(LIST_W - 70)
	self.searchBox = search

	local slotFilter = CreateDropdown(f, "slot", 140)
	slotFilter:SetPoint("LEFT", search, "RIGHT", 18, 0)
	local kindFilter = CreateDropdown(f, "kind", 140)
	kindFilter:SetPoint("LEFT", slotFilter, "RIGHT", 10, 0)
	self.filterButtons = { slot = slotFilter, kind = kindFilter }

	local classToggle = CreateToggle(f, "myClass", "My class")
	classToggle:SetPoint("LEFT", kindFilter, "RIGHT", 14, 0)
	classToggle.Hint = function() return K.ClassFilterText() end
	local classicToggle = CreateToggle(f, "hideClassic", "Hide Classic")
	classicToggle:SetPoint("LEFT", classToggle.Text, "RIGHT", 12, 0)
	classicToggle.Hint = function()
		return "Hide Classic loot: items Wowhead's Forever database doesn't have, so Forever may have replaced them."
	end
	self.toggles = { myClass = classToggle, hideClassic = classicToggle }

	-- Left inset: the list
	local left = CreateFrame("Frame", nil, f, "InsetFrameTemplate")
	left:SetPoint("TOPLEFT", 4, -TOP_H)
	left:SetPoint("BOTTOMLEFT", 4, FOOTER_H)
	left:SetWidth(LIST_W)
	self.left = left

	self.listLabel = Text(left, "GameFontNormalSmall")
	self.listLabel:SetPoint("TOPLEFT", 10, -8)
	self.listRight = Text(left, "GameFontNormalSmall", "RIGHT")
	self.listRight:SetPoint("TOPRIGHT", -(SCROLLBAR_W + 8), -8)

	local listWidth = LIST_W - 12 - SCROLLBAR_W - 4
	local list = CreateScrollArea(left, listWidth)
	list:SetPoint("TOPLEFT", 6, -24)
	list:SetPoint("BOTTOMRIGHT", -(SCROLLBAR_W + 6), 6)
	self.list = list

	-- Right inset: the open entry, or search results
	local right = CreateFrame("Frame", nil, f, "InsetFrameTemplate")
	right:SetPoint("TOPLEFT", left, "TOPRIGHT", 4, 0)
	right:SetPoint("BOTTOMRIGHT", -6, FOOTER_H)
	self.right = right

	local header = CreateFrame("Frame", nil, right)
	header:SetPoint("TOPLEFT")
	header:SetPoint("TOPRIGHT")
	header:SetHeight(HEADER_H)
	local divider = Atlas(header, "ARTWORK", "Options_HorizontalDivider")
	divider:SetPoint("BOTTOMLEFT", 10, 0)
	divider:SetPoint("BOTTOMRIGHT", -10, 0)
	divider:SetHeight(2)
	divider:SetVertexColor(C.gold[1], C.gold[2], C.gold[3])

	header.name = Text(header, "GameFontNormalHuge")
	header.name:SetPoint("TOPLEFT", 14, -14)

	-- "New in Forever" after the name
	header.badge = CreateFrame("Frame", nil, header)
	header.badge:SetHeight(16)
	header.badge:SetPoint("LEFT", header.name, "RIGHT", 10, 0)
	header.badge.text = Text(header.badge, "GameFontGreenSmall")
	header.badge.text:SetPoint("LEFT")
	header.badge.text:SetText("New in Forever")
	header.badge:SetWidth(header.badge.text:GetStringWidth() + 4)

	header.meta = Text(header, "GameFontHighlight")
	header.meta:SetPoint("TOPLEFT", header.name, "BOTTOMLEFT", 0, -7)

	header.note = Text(header, "GameFontHighlightSmall")
	header.note:SetPoint("TOPLEFT", header.meta, "BOTTOMLEFT", 0, -7)
	header.note:SetPoint("RIGHT", -14, 0)
	header.note:SetWordWrap(true)
	SetTextColor(header.note, C.silver)

	header.wowhead = PanelButton(header, "Wowhead", 96)
	header.wowhead:SetPoint("TOPRIGHT", -10, -12)
	header.wowhead:SetScript("OnClick", function()
		local title, url = UI:Mode().WowheadLink(UI.current)
		if url then UI:ShowURL(title, url) end
	end)

	-- Takes the place of the Wowhead button while search results are showing
	header.clear = PanelButton(header, "Clear search", 110)
	header.clear:SetPoint("TOPRIGHT", -10, -12)
	header.clear:SetScript("OnClick", function() UI:ClearSearch() end)
	header.clear:Hide()
	self.header = header

	local contentWidth = WIDTH - LIST_W - 4 - 4 - 6 - 10 - SCROLLBAR_W - 8
	local loot = CreateScrollArea(right, contentWidth)
	loot:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 10, -6)
	loot:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT", -(SCROLLBAR_W + 8), 6)
	loot.onScrolled = function() UI:Paint() end
	self.loot = loot
	self.contentWidth = contentWidth

	-- Footer: what the clicks do, and how fresh the data is
	self.footerHelp = Text(f, "GameFontDisableSmall")
	self.footerHelp:SetPoint("BOTTOMLEFT", 14, 8)
	self.footerSource = Text(f, "GameFontDisableSmall", "RIGHT")
	self.footerSource:SetPoint("BOTTOMRIGHT", -14, 8)

	self.listRows = {}
	self.pools, self.used = {}, {}
	self:UpdateChrome()

	f:SetScript("OnShow", function() UI:BuildList(); UI:RegisterItemEvents(true) end)
	f:SetScript("OnHide", function()
		UI:CloseMenu()
		UI:ClearSearchFocus()
		UI:RegisterItemEvents(false)
	end)
	return f
end

-- Tabs, list labels, search hint and footer for the current mode
function UI:UpdateChrome()
	local mode = self:Mode()
	self:UpdateTabs()
	-- The loot filters are only on the tabs that list loot
	for _, t in pairs(self.toggles) do t:SetShown(mode.filters and true or false) end
	self:UpdateToggles()
	self.listLabel:SetText(mode.listTitle)
	self.listRight:SetText(mode.listRight)
	self.searchBox.Instructions:SetText(mode.searchHint)
	self.footerHelp:SetText(mode.footer)
	self.footerSource:SetText("Wowhead data " .. (mode.dataDate() or ""))
	self:UpdateFilterButtons()
end

function UI:UpdateTabs()
	for _, t in ipairs(self.tabs) do t:SetChecked(t.key == self.mode) end
end

function UI:SavePosition()
	local point, _, relPoint, x, y = self.frame:GetPoint(1)
	ns.db.window = { point, relPoint, x, y }
end

function UI:ResetPosition(fromCreate)
	local f = self.frame
	if not f then return end
	f:ClearAllPoints()
	local w = (fromCreate and ns.db and ns.db.window) or nil
	if w then
		f:SetPoint(w[1], UIParent, w[2], w[3], w[4])
	else
		f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
	end
end

----------------------------------------------------------------------
-- The list on the left
----------------------------------------------------------------------
local function CreateListRow(parent, width)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(width, LIST_ROW_H)
	b.selected = Atlas(b, "BACKGROUND", "Professions_Recipe_Active")
	b.selected:SetAllPoints()
	b.selected:Hide()
	RowHighlight(b)
	b.levels = Text(b, "GameFontHighlightSmall", "RIGHT")
	b.levels:SetPoint("RIGHT", -4, 0)
	b.levels:SetWidth(44)
	b.tag = Text(b, "GameFontHighlightSmall", "RIGHT")
	b.tag:SetPoint("RIGHT", b.levels, "LEFT", -4, 0)
	-- Match count, shown while searching
	b.count = Text(b, "GameFontHighlightSmall", "RIGHT")
	b.count:SetPoint("RIGHT", -4, 0)
	b.count:Hide()
	b.name = Text(b, "GameFontHighlight")
	b.name:SetPoint("LEFT", 8, 0)
	b.name:SetPoint("RIGHT", b.tag, "LEFT", -4, 0)
	b:SetScript("OnClick", function(self)
		UI:ClearSearchFocus()
		if UI:IsSearching() then
			UI:FocusEntry(self.entry)
		else
			UI:Select(self.entry)
		end
	end)
	return b
end

-- Normally lists every entry of the tab. While searching it lists "All ..." and then
-- only the entries with matches, each with its match count.
-- RowInfo gives name, right column, tag, marker (the entry is yours: your level range, your
-- profession, your class), tag color and right column color. Marked names are gold, as the
-- game marks what's yours; the rest are white.
function UI:BuildList()
	local mode = self:Mode()
	local searching = self:IsSearching()
	local listKey = self.mode .. (searching and ":search" or ":entries")
	if listKey ~= self.listKey then
		self.listKey = listKey
		self.list:ScrollToTop()
	end
	local entries = {}
	if searching then
		entries[1] = { count = self.searchTotal or 0 }
		for _, g in ipairs(self.searchGroups or {}) do
			entries[#entries + 1] = { entry = g.entry, count = #g.rows }
		end
	else
		for _, e in ipairs(mode.Entries()) do entries[#entries + 1] = { entry = e } end
	end

	local width = self.list.content:GetWidth()
	for i, e in ipairs(entries) do
		local row = self.listRows[i]
		if not row then
			row = CreateListRow(self.list.content, width)
			row:SetPoint("TOPLEFT", 0, -(i - 1) * LIST_ROW_H)
			self.listRows[i] = row
		end
		row.entry = e.entry
		local name, right, tag, marker, tagColor, rightColor = mode.allLabel, "", "", false, nil, nil
		if e.entry then name, right, tag, marker, tagColor, rightColor = mode.RowInfo(e.entry) end
		row.isMarked = marker and true or false
		row.name:SetText(name)
		SetTextColor(row.name, row.isMarked and C.gold or C.white)
		if e.count then
			row.levels:Hide()
			row.tag:Hide()
			row.count:SetText(e.count)
			row.count:Show()
			row.name:SetPoint("RIGHT", row.count, "LEFT", -6, 0)
		else
			row.count:Hide()
			row.levels:SetText(right)
			SetTextColor(row.levels, rightColor or C.silver)
			row.levels:Show()
			row.tag:SetText(tag or "")
			SetTextColor(row.tag, tagColor or C.green)
			row.tag:Show()
			row.name:SetPoint("RIGHT", row.tag, "LEFT", -4, 0)
		end
		row:Show()
	end
	for i = #entries + 1, #self.listRows do self.listRows[i]:Hide() end
	self.list:SetContentHeight(#entries * LIST_ROW_H)
	self:UpdateListSelection()
end

function UI:UpdateListSelection()
	-- While searching, the highlighted row is the entry the results are narrowed to
	-- (none means the "All ..." row)
	local selected
	if self:IsSearching() then selected = self.filter.focus else selected = self.current end
	for _, row in ipairs(self.listRows) do
		local on = row:IsShown() and row.entry == selected
		row.isSelected = on
		row.selected:SetShown(on)
	end
end

----------------------------------------------------------------------
-- The right panel. Renderers add entries (kind, height, data); only the ones in view
-- get a widget, taken from a pool per kind, so long lists stay light.
----------------------------------------------------------------------
K.kinds = {}
-- `live` kinds get refilled when item data arrives from the server
function K.RegisterKind(kind, create, fill, live)
	K.kinds[kind] = { create = create, fill = fill, live = live }
end

function UI:BeginContent()
	self.entries = {}
	self.contentY = 0
	self.sectionIds = {}
end

function UI:AddEntry(kind, height, data)
	self.entries[#self.entries + 1] = { kind = kind, y = self.contentY, h = height, data = data }
	self.contentY = self.contentY + height
end

function UI:AddGap(height)
	self.contentY = self.contentY + height
end

function UI:EndContent()
	self.loot:SetContentHeight(self.contentY)
	self:Paint()
end

----------------------------------------------------------------------
-- Collapsible sections. A renderer adds a header with AddSection and leaves out the
-- section's rows when it comes back collapsed. Sections can hold sections (a wing's bosses).
----------------------------------------------------------------------
function UI:SectionState()
	return self:IsSearching() and self.searchSections or self.sections
end

-- Every section starts collapsed until it's clicked
function UI:IsCollapsed(id)
	return not self:SectionState()[id]
end

-- `kind` and `extra` make the header another row kind with its own data: a boss or quest bar,
-- the Quests tab's quest headers
local SECTION_H = { boss = BOSS_H, quest = QUEST_H }
function UI:AddSection(id, text, right, kind, extra)
	self.sectionIds[#self.sectionIds + 1] = id
	local data = extra or {}
	data.id, data.text, data.right = id, text, right
	self:AddEntry(kind or "wing", SECTION_H[kind] or WING_H, data)
	return self:IsCollapsed(id)
end

function UI:ToggleSection(id)
	self:SectionState()[id] = self:IsCollapsed(id)
	self:Refresh()
end

-- Shift-click: collapse every section if any is open, otherwise open them all, the sections
-- inside them too (those only show up once the one around them is open)
function UI:ToggleAllSections()
	local anyOpen = false
	for _, id in ipairs(self.sectionIds) do
		if not self:IsCollapsed(id) then anyOpen = true end
	end
	local state = self:SectionState()
	for _ = 1, 5 do
		local before = #self.sectionIds
		for _, id in ipairs(self.sectionIds) do state[id] = not anyOpen end
		self:Refresh()
		if anyOpen or #self.sectionIds == before then break end
	end
end

local function Acquire(self, kind)
	local pool = self.pools[kind]
	if not pool then
		pool = {}
		self.pools[kind] = pool
	end
	local n = (self.used[kind] or 0) + 1
	self.used[kind] = n
	local w = pool[n]
	if not w then
		w = K.kinds[kind].create(self.loot.content, self.contentWidth)
		pool[n] = w
	end
	w:ClearAllPoints()
	w:Show()
	return w
end

function UI:Paint()
	local entries = self.entries
	if not entries then return end
	for kind in pairs(self.used) do self.used[kind] = 0 end
	local top = self.loot:GetVerticalScroll()
	local view = self.loot:GetHeight()
	if not view or view < 50 then view = HEIGHT end
	local lo, hi = top - PAINT_PAD, top + view + PAINT_PAD

	-- The first entry that reaches into view (entries are in order of y)
	local a, b = 1, #entries
	while a < b do
		local m = math.floor((a + b) / 2)
		if entries[m].y + entries[m].h < lo then a = m + 1 else b = m end
	end
	for i = a, #entries do
		local e = entries[i]
		if e.y > hi then break end
		local w = Acquire(self, e.kind)
		w:SetPoint("TOPLEFT", 0, -e.y)
		w.entry = e.data
		K.kinds[e.kind].fill(w, e.data)
	end
	for kind, pool in pairs(self.pools) do
		for i = (self.used[kind] or 0) + 1, #pool do pool[i]:Hide() end
	end

	-- A row that scrolled under a still mouse would keep the last row's tooltip
	local owner = GameTooltip:IsShown() and GameTooltip:GetOwner()
	if owner and owner.isForeverLootRow and owner:IsShown() and owner:IsMouseOver() then
		owner:GetScript("OnEnter")(owner)
	end
end

----------------------------------------------------------------------
-- Rows both tabs use: section headers, item rows and notes
----------------------------------------------------------------------
-- Section header, like the categories of the game's recipe list: a bar with a plus or minus.
-- Click to collapse or expand it, shift-click for every section.
local function CreateWing(parent, width)
	local w = CreateFrame("Button", nil, parent)
	w:SetSize(width, WING_H)
	w.isForeverLootRow = true
	w:RegisterForClicks("LeftButtonUp")
	w.bg = Atlas(w, "BACKGROUND", "common-button-list-collapseExpand")
	w.bg:SetPoint("TOPLEFT", 0, -1)
	w.bg:SetPoint("BOTTOMRIGHT", 0, 1)
	w.glow = Atlas(w, "HIGHLIGHT", "common-button-list-collapseExpand", 0.4)
	w.glow:SetBlendMode("ADD")
	w.glow:SetAllPoints(w.bg)
	w.icon = w:CreateTexture(nil, "ARTWORK")
	w.icon:SetPoint("RIGHT", -8, 0)
	w.text = Text(w, "GameFontNormal")
	w.text:SetPoint("LEFT", 10, 0)
	w.levels = Text(w, "GameFontHighlightSmall", "RIGHT")
	w.levels:SetPoint("RIGHT", -32, 0)
	SetTextColor(w.levels, C.silver)
	w:SetScript("OnEnter", function(self)
		if not self.sectionId then return end
		SetTextColor(self.text, C.white)
		ShowHint(self, self.text:GetText(), (UI:IsCollapsed(self.sectionId) and "Click to expand." or "Click to collapse.") ..
			" Shift-click expands or collapses every section.")
	end)
	w:SetScript("OnLeave", function(self)
		SetTextColor(self.text, C.gold)
		GameTooltip:Hide()
	end)
	w:SetScript("OnClick", function(self)
		if not self.sectionId then return end
		if IsShiftKeyDown() then UI:ToggleAllSections() else UI:ToggleSection(self.sectionId) end
	end)
	return w
end

K.RegisterKind("wing", CreateWing, function(w, d)
	w.sectionId = d.id
	w.text:SetText(d.text)
	SetTextColor(w.text, C.gold)
	w.levels:SetText(d.right or "")
	local collapsed = d.id and UI:IsCollapsed(d.id)
	w.collapsed = collapsed and true or false
	if d.id then
		w.icon:SetAtlas(collapsed and "common-button-list-plus" or "common-button-list-minus", true)
		w.icon:Show()
	else
		w.icon:Hide()
	end
	w:EnableMouse(d.id ~= nil)
end)

local QUALITY_BORDER = 2 -- uncommon and up get a colored border, as on the game's item buttons

local function UpdateItemRow(row)
	local name, quality, typeText, icon = ns.ItemDisplay(row.itemID)
	local entry = ns.Items[row.itemID]
	local flag = entry and entry[4]
	row.icon:SetTexture(icon)
	local r, g, b = HexToRGB(ns.QUALITY_HEX[quality] or "ffffff")
	row.name:SetText(name)
	row.name:SetTextColor(r, g, b)
	if quality >= QUALITY_BORDER then
		row.border:SetVertexColor(r, g, b)
		row.border:Show()
	else
		row.border:Hide()
	end
	row.type:SetText(typeText or "")

	-- Search results show which boss drops the item where the drop chance normally goes
	row.type:ClearAllPoints()
	if row.sourceText then
		row.pct:Hide()
		row.source:SetText(row.sourceText)
		row.source:Show()
		row.type:SetPoint("RIGHT", row.source, "LEFT", -10, 0)
	else
		row.source:Hide()
		row.pct:SetText(row.pctValue and FormatPct(row.pctValue) or "")
		row.pct:Show()
		row.type:SetPoint("RIGHT", row.pct, "LEFT", -6, 0)
	end

	row.wanted:SetShown(ns.Wishlist.IsWanted(row.itemID))
	local badge = (row.owned and BADGES.owned) or (row.learnedCount and BADGES.seen) or ((flag == 1 or flag == 3) and BADGES.new)
		or (flag == 2 and BADGES.classic) or nil
	row.name:ClearAllPoints()
	row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
	if badge then
		row.badge:SetText(badge[1])
		SetTextColor(row.badge, badge[2])
		row.badge:Show()
		row.name:SetPoint("RIGHT", row.badge, "LEFT", -6, 0)
	else
		row.badge:Hide()
		row.name:SetPoint("RIGHT", row.type, "LEFT", -8, 0)
	end
end

local function AddLootNotes(row, entry, bundled)
	local flag = entry and entry[4]
	local notes = {}
	if row.sourceNote then notes[#notes + 1] = { row.sourceNote, C.white } end
	if bundled and flag ~= 2 then
		notes[#notes + 1] = { "The beta server isn't sending this item's data, so these stats come from Wowhead.", C.silver }
	end
	if row.pctValue then notes[#notes + 1] = { "Drop chance (Classic data): " .. FormatPct(row.pctValue), C.silver } end
	if flag == 1 then
		notes[#notes + 1] = { "New in Forever.", C.green }
	elseif flag == 3 then
		notes[#notes + 1] = { "New in Forever. No site has confirmed which boss drops it yet.", C.green }
	elseif flag == 2 then
		notes[#notes + 1] = { "Classic loot. Wowhead's Forever database doesn't have this item, so Forever may have replaced it.", C.grey }
	end
	if row.hint then notes[#notes + 1] = { "Its name points to " .. row.hint .. ".", C.silver } end
	if row.learnedCount then
		notes[#notes + 1] = { "Recorded from your loot (" .. row.learnedCount .. "x).", C.blue }
	elseif entry and entry[5] then
		notes[#notes + 1] = { "Listed by " .. entry[5] .. ".", C.silver }
	end
	if row.owned then notes[#notes + 1] = { "You have it: it's in your bags, bank or worn.", C.blue } end
	notes[#notes + 1] = K.WishlistNote(row.itemID)
	K.AddNotes(notes)
end

local function CreateItem(parent, width)
	local r = CreateFrame("Button", nil, parent)
	r:SetSize(width, ITEM_H)
	r.isForeverLootRow = true
	r.isForeverLootItem = true
	r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	RowHighlight(r)
	-- A star, like the auction house's favorites: it's on your wishlist
	r.wanted = Atlas(r, "OVERLAY", "auctionhouse-icon-favorite")
	r.wanted:SetSize(13, 12)
	r.wanted:SetPoint("LEFT", 2, 0)
	r.wanted:Hide()
	-- The icon with the quality border of the game's item buttons
	r.icon = r:CreateTexture(nil, "ARTWORK")
	r.icon:SetSize(24, 24)
	r.icon:SetPoint("LEFT", 18, 0)
	r.border = r:CreateTexture(nil, "OVERLAY")
	r.border:SetTexture("Interface\\Common\\WhiteIconFrame")
	r.border:SetAllPoints(r.icon)
	r.pct = Text(r, "GameFontHighlightSmall", "RIGHT")
	r.pct:SetPoint("RIGHT", -8, 0)
	r.pct:SetWidth(40)
	SetTextColor(r.pct, C.silver)
	r.source = Text(r, "GameFontHighlightSmall", "RIGHT")
	r.source:SetPoint("RIGHT", -8, 0)
	r.source:SetWidth(SOURCE_W)
	SetTextColor(r.source, C.silver)
	r.source:Hide()
	r.type = Text(r, "GameFontHighlightSmall", "RIGHT")
	r.type:SetPoint("RIGHT", r.pct, "LEFT", -6, 0)
	SetTextColor(r.type, C.silver)
	r.badge = Text(r, "GameFontHighlightSmall", "RIGHT")
	r.badge:SetPoint("RIGHT", r.type, "LEFT", -8, 0)
	r.name = Text(r, "GameFontHighlight")

	r:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		local bundled = K.ItemTooltip(self.itemID)
		AddLootNotes(self, ns.Items[self.itemID], bundled)
		GameTooltip:Show()
	end)
	r:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	r:SetScript("OnClick", function(self, button)
		if K.ItemModifiedClick(self.itemID) then return end
		if button == "RightButton" then
			UI:ToggleWanted(self.itemID)
			return
		end
		local name = ns.ItemDisplay(self.itemID)
		local entry = ns.Items[self.itemID]
		if entry and entry[4] == 2 then
			UI:ShowURL(name .. " on Wowhead Classic", ns.WOWHEAD_CLASSIC .. "item=" .. self.itemID)
		else
			UI:ShowURL(name .. " on Wowhead", ns.WOWHEAD .. "item=" .. self.itemID)
		end
	end)
	return r
end

-- data: itemID, learnedCount, pct, hint, owned, and in search results source (the boss) and from (tooltip line)
K.RegisterKind("item", CreateItem, function(r, d)
	r.itemID = d.itemID
	r.owned = d.owned
	r.learnedCount = d.learnedCount
	r.pctValue = d.pct
	r.hint = d.hint
	r.sourceText, r.sourceNote = d.source, d.from
	UpdateItemRow(r)
end, true)

local function CreateNote(parent, width)
	local n = CreateFrame("Frame", nil, parent)
	n:SetSize(width, NOTE_H)
	n.text = Text(n, "GameFontHighlightSmall")
	n.text:SetPoint("LEFT", 14, 0)
	n.text:SetPoint("RIGHT", -10, 0)
	SetTextColor(n.text, C.silver)
	return n
end

K.RegisterKind("note", CreateNote, function(n, d) n.text:SetText(d.text) end)

----------------------------------------------------------------------
-- Search index: every word an item can be found by
----------------------------------------------------------------------
-- Slot and type keys come from each item's type text in the data ("Leather Hands",
-- "Two-Hand Staff", "Finger", "Potion"), or from the client for items only known from your loot.
local SLOT_BY_TYPE = {
	Head = "head", Neck = "neck", Shoulder = "shoulder", Back = "back", Chest = "chest",
	Wrist = "wrist", Hands = "hands", Waist = "waist", Legs = "legs", Feet = "feet",
	Finger = "finger", Trinket = "trinket", Shield = "shield", ["Held In Off-hand"] = "offhand",
	Bow = "ranged", Crossbow = "ranged", Gun = "ranged", Thrown = "ranged", Wand = "ranged",
	Recipe = "recipe",
	Consumable = "consumable", Potion = "consumable", Elixir = "consumable", Flask = "consumable",
	Scroll = "consumable", ["Food & Drink"] = "consumable", ["Item Enhancement"] = "consumable",
	Bandage = "consumable",
	["Trade Goods"] = "tradegoods", Parts = "tradegoods", Explosives = "tradegoods", Devices = "tradegoods",
	Cloth = "tradegoods", Leather = "tradegoods", ["Metal & Stone"] = "tradegoods", Meat = "tradegoods",
	Herb = "tradegoods", Elemental = "tradegoods", Enchanting = "tradegoods", Reagent = "tradegoods",
	Bag = "bag", ["Soul Bag"] = "bag", ["Herb Bag"] = "bag", ["Enchanting Bag"] = "bag",
	["Engineering Bag"] = "bag", Quiver = "bag", ["Ammo Pouch"] = "bag",
}
local HAND_PREFIXES = {
	{ "One-Hand ", "onehand" }, { "Main Hand ", "onehand" }, { "Off Hand ", "onehand" }, { "Two-Hand ", "twohand" },
}
local MATERIALS = { Cloth = "cloth", Leather = "leather", Mail = "mail", Plate = "plate" }
local WEAPON_KINDS = {
	Axe = "axe", Bow = "bow", Crossbow = "crossbow", Dagger = "dagger", ["Fist Weapon"] = "fist",
	Gun = "gun", Mace = "mace", Polearm = "polearm", Staff = "staff", Sword = "sword",
	Thrown = "thrown", Wand = "wand",
}

local function ClassifyTypeText(text)
	local material, slot = text:match("^(%a+) (.+)$")
	if material and MATERIALS[material] then
		return SLOT_BY_TYPE[slot] or "other", MATERIALS[material]
	end
	for _, p in ipairs(HAND_PREFIXES) do
		if text:sub(1, #p[1]) == p[1] then return p[2], WEAPON_KINDS[text:sub(#p[1] + 1)] end
	end
	if text:sub(1, 6) == "Relic " then return "relic" end
	return SLOT_BY_TYPE[text] or "other", WEAPON_KINDS[text]
end

local SLOT_BY_EQUIPLOC = {
	INVTYPE_HEAD = "head", INVTYPE_NECK = "neck", INVTYPE_SHOULDER = "shoulder", INVTYPE_CLOAK = "back",
	INVTYPE_CHEST = "chest", INVTYPE_ROBE = "chest", INVTYPE_WRIST = "wrist", INVTYPE_HAND = "hands",
	INVTYPE_WAIST = "waist", INVTYPE_LEGS = "legs", INVTYPE_FEET = "feet", INVTYPE_FINGER = "finger",
	INVTYPE_TRINKET = "trinket", INVTYPE_WEAPON = "onehand", INVTYPE_WEAPONMAINHAND = "onehand",
	INVTYPE_WEAPONOFFHAND = "onehand", INVTYPE_2HWEAPON = "twohand", INVTYPE_RANGED = "ranged",
	INVTYPE_RANGEDRIGHT = "ranged", INVTYPE_THROWN = "ranged", INVTYPE_HOLDABLE = "offhand",
	INVTYPE_SHIELD = "shield", INVTYPE_RELIC = "relic",
}
-- Subclass ids of item classes 2 (weapons) and 4 (armor)
local KIND_BY_SUBCLASS = {
	[2] = { [0] = "axe", [1] = "axe", [2] = "bow", [3] = "gun", [4] = "mace", [5] = "mace", [6] = "polearm",
		[7] = "sword", [8] = "sword", [10] = "staff", [13] = "fist", [15] = "dagger", [16] = "thrown",
		[18] = "crossbow", [19] = "wand" },
	[4] = { [1] = "cloth", [2] = "leather", [3] = "mail", [4] = "plate" },
}
-- Cloaks count as cloth in the game's data, but only these slots have an armor type here
local ARMOR_SLOTS = { head = true, shoulder = true, chest = true, wrist = true, hands = true, waist = true, legs = true, feet = true }

local function ClassifyFromClient(itemID)
	local _, _, _, equipLoc, _, classID, subclassID = ns.GetItemInfoInstant(itemID)
	if not classID then return "other" end
	local slot = SLOT_BY_EQUIPLOC[equipLoc] or (classID == 9 and "recipe") or "other"
	local kind = KIND_BY_SUBCLASS[classID] and KIND_BY_SUBCLASS[classID][subclassID]
	if classID == 4 and not ARMOR_SLOTS[slot] then kind = nil end
	return slot, kind
end

-- Words each slot and type also answer to, so "gloves" finds every Hands item.
-- Plurals get added below, so "rings" and "daggers" work too.
local SLOT_WORDS = {
	head = "helm helmet hat hood cap cowl crown circlet mask",
	neck = "necklace amulet pendant choker jewelry",
	shoulder = "shoulders pauldrons spaulders mantle shoulderpads epaulets amice",
	back = "cloak cape drape",
	chest = "robe tunic vest breastplate chestpiece jerkin hauberk",
	wrist = "wrists bracers bracelets bindings cuffs wristguards wristbands",
	hands = "gloves gauntlets handguards handwraps grips mitts",
	waist = "belt girdle sash cord cinch",
	legs = "pants leggings legguards legplates trousers kilt breeches",
	feet = "boots shoes sandals slippers treads sabatons footwraps",
	finger = "ring band jewelry",
	onehand = "1h weapon melee",
	twohand = "2h weapon melee",
	ranged = "weapon",
	offhand = "holdable",
	shield = "offhand",
	recipe = "profession",
	consumable = "potion elixir flask scroll food drink bandage",
	tradegoods = "trade goods materials mats",
	bag = "container quiver",
	other = "misc",
}
local KIND_WORDS = {
	cloth = "armor", leather = "armor", mail = "armor chain", plate = "armor",
	staff = "staves", dagger = "knife", crossbow = "xbow",
}

-- Only this fixed vocabulary gets plurals. A general "drop the s" rule would make
-- "hands" also find "Hand of Justice".
local function WithPlurals(words)
	local out = {}
	for w in words:gmatch("%S+") do
		out[#out + 1] = w
		if not w:find("s$") then out[#out + 1] = w:find("[xh]$") and (w .. "es") or (w .. "s") end
	end
	return table.concat(out, " ")
end
for key in pairs(FILTER_MENUS.slot.names) do SLOT_WORDS[key] = WithPlurals(key .. " " .. (SLOT_WORDS[key] or "")) end
for key in pairs(FILTER_MENUS.kind.names) do KIND_WORDS[key] = WithPlurals(key .. " " .. (KIND_WORDS[key] or "")) end
local QUALITY_WORDS = { [2] = "uncommon", [3] = "rare", [4] = "epic", [5] = "legendary" }
local FLAG_WORDS = { [1] = "new", [2] = "classic", [3] = "new" }

function K.SlotWords(slot)
	return SLOT_WORDS[slot]
end

-- Stats from the bundled tooltip, so "agility gloves" or "spell power cloth" work
local STAT_ALIASES = { ["attack power"] = "ap", ["critical strike"] = "crit" }
local EQUIP_STATS = {
	{ "damage and healing done by magical spells", "spell power damage healing" },
	{ "healing done by spells", "healing" },
	{ "attack power", "attack power ap" },
	{ "critical strike", "critical strike crit" },
	{ "chance to hit", "hit" },
	{ "mana per", "mana mp5" },
	{ "health per", "health" },
	{ "defense", "defense" },
	{ "dodge", "dodge" },
	{ "parry", "parry" },
	{ "block", "block" },
}
-- Other things a tooltip line can say an item is
local TOOLTIP_KINDS = {
	{ "%d+ slot bag", "bag" },
	{ "slot quiver", "quiver" },
	{ "ammo pouch", "ammo pouch" },
	{ "^mount", "mount" },
	{ "begins a quest", "quest" },
}

local function TooltipWords(lines, out)
	for _, line in ipairs(lines or {}) do
		line = line:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):lower()
		local equip = line:match("^equip: (.*)")
		local stat = (equip or line):match("^%+%d+ ([%a ]+)")
		if stat then
			out[#out + 1] = stat
			for name, alias in pairs(STAT_ALIASES) do
				if stat:find(name, 1, true) then out[#out + 1] = alias end
			end
		elseif equip then
			for _, s in ipairs(EQUIP_STATS) do
				if equip:find(s[1], 1, true) then out[#out + 1] = s[2] end
			end
			local school = equip:match("damage done by (%a+) spells")
			if school then out[#out + 1] = school .. " spell power damage" end
		end
		for _, k in ipairs(TOOLTIP_KINDS) do
			if line:find(k[1]) then out[#out + 1] = k[2] end
		end
	end
end

-- Lowercases, drops apostrophes and joins "two-hand", "off hand" and the like into one
-- word, so the item side and the query side always split into the same words
local HAND_WORDS = { "two", "one", "main", "off" }
local function Simplify(s)
	s = " " .. (s or ""):lower():gsub("'", ""):gsub("\226\128\153", "") .. " "
	s = s:gsub("handed", "hand")
	for _, w in ipairs(HAND_WORDS) do
		s = s:gsub("(%W)" .. w .. "[%s%-]*hand", "%1" .. w .. "hand")
	end
	return (s:gsub("[^%w]+", " "))
end
K.Simplify = Simplify

local searchInfo = {}

-- An item's slot, type and every word it can be found by
local function SearchInfo(itemID)
	local info = searchInfo[itemID]
	if info then return info end
	local entry = ns.Items[itemID]
	local words, name, typeText, slot, kind = {}
	if entry then
		name, typeText = entry[1], entry[3]
		if typeText ~= "" then slot, kind = ClassifyTypeText(typeText) else slot = "other" end
		words[#words + 1] = QUALITY_WORDS[entry[2]]
		words[#words + 1] = FLAG_WORDS[entry[4]]
		TooltipWords(entry[7], words)
	else
		local link, quality
		name, link, quality = ns.GetItemInfo(itemID)
		typeText = TypeTextFromClient(itemID)
		slot, kind = ClassifyFromClient(itemID)
		words[#words + 1] = quality and QUALITY_WORDS[quality]
	end
	words[#words + 1] = name
	words[#words + 1] = typeText
	words[#words + 1] = SLOT_WORDS[slot]
	words[#words + 1] = kind and KIND_WORDS[kind]
	info = { slot = slot, kind = kind, words = Simplify(table.concat(words, " ")) }
	-- Items only known from your own loot may still be waiting on their name from the server
	if entry or name then searchInfo[itemID] = info end
	return info
end
K.SearchInfo = SearchInfo

-- Each word of the query has to start one of the item's words ("glove" finds "gloves")
function K.ParseQuery(text)
	local terms = {}
	for term in Simplify(text):gmatch("%S+") do terms[#terms + 1] = " " .. term end
	return terms
end

function K.Matches(info, terms, filter, extra)
	if filter.slot and info.slot ~= filter.slot then return false end
	if filter.kind and info.kind ~= filter.kind then return false end
	for _, t in ipairs(terms) do
		if not (info.words:find(t, 1, true) or (extra and extra:find(t, 1, true))) then return false end
	end
	return true
end

----------------------------------------------------------------------
-- What the player's class can use, for the "My class" filter
----------------------------------------------------------------------
-- Class ids, as the game and Wowhead number them
local CLASS_IDS = { WARRIOR = 1, PALADIN = 2, HUNTER = 3, ROGUE = 4, PRIEST = 5, SHAMAN = 7, MAGE = 8, WARLOCK = 9, DRUID = 11 }
-- Each class's own armor, and the type it wears until it learns that one at level 40
local ARMOR = {
	WARRIOR = { plate = true, mail = true }, PALADIN = { plate = true, mail = true },
	HUNTER = { mail = true, leather = true }, SHAMAN = { mail = true, leather = true },
	ROGUE = { leather = true }, DRUID = { leather = true },
	PRIEST = { cloth = true }, MAGE = { cloth = true }, WARLOCK = { cloth = true },
}
-- Weapon skills each class can learn: "1" one-handed, "2" two-handed
local WEAPON_SKILLS = {
	WARRIOR = "axe1 axe2 mace1 mace2 sword1 sword2 dagger fist polearm staff bow crossbow gun thrown",
	PALADIN = "axe1 axe2 mace1 mace2 sword1 sword2 polearm",
	HUNTER = "axe1 axe2 sword1 sword2 dagger fist polearm staff bow crossbow gun thrown",
	ROGUE = "dagger fist mace1 sword1 bow crossbow gun thrown",
	PRIEST = "dagger mace1 staff wand",
	SHAMAN = "axe1 axe2 mace1 mace2 dagger fist staff",
	MAGE = "dagger sword1 staff wand",
	WARLOCK = "dagger sword1 staff wand",
	DRUID = "dagger fist mace1 mace2 staff",
}
local DUAL_WIELD = { WARRIOR = true, ROGUE = true, HUNTER = true }
local SHIELDS = { WARRIOR = true, PALADIN = true, SHAMAN = true }
local RELICS = { PALADIN = "Libram", SHAMAN = "Totem", DRUID = "Idol" }
local HELD_OFFHAND = { PALADIN = true, PRIEST = true, SHAMAN = true, MAGE = true, WARLOCK = true, DRUID = true }
local skillSets = {}
for class, list in pairs(WEAPON_SKILLS) do
	skillSets[class] = {}
	for skill in list:gmatch("%S+") do skillSets[class][skill] = true end
end

function K.PlayerClass()
	local name, file, id = UnitClass("player")
	return file, id or CLASS_IDS[file], name
end

-- Whether a class can equip the item. Anything that isn't armor, a weapon, a shield or a
-- relic (rings, cloaks, trinkets, recipes, bags) counts as usable.
function K.UsableBy(itemID, class)
	local entry = ns.Items[itemID]
	local classes = entry and entry[8]
	if classes then
		local id = CLASS_IDS[class]
		for _, c in ipairs(classes) do
			if c == id then return true end
		end
		return false
	end
	local info = SearchInfo(itemID)
	local slot, kind = info.slot, info.kind
	if ARMOR_SLOTS[slot] and kind then return ARMOR[class][kind] == true end
	if slot == "shield" then return SHIELDS[class] == true end
	if slot == "offhand" then return HELD_OFFHAND[class] == true end
	if slot == "relic" then
		local typeText = entry and entry[3] or ""
		return RELICS[class] ~= nil and typeText:find(RELICS[class], 1, true) ~= nil
	end
	if kind and (slot == "onehand" or slot == "twohand" or slot == "ranged") then
		local skills = skillSets[class]
		if kind == "axe" or kind == "mace" or kind == "sword" then
			if not skills[kind .. (slot == "twohand" and "2" or "1")] then return false end
		elseif not skills[kind] then
			return false
		end
		local typeText = entry and entry[3] or ""
		if typeText:sub(1, 9) == "Off Hand " then return DUAL_WIELD[class] == true end
		return true
	end
	return true
end

function K.Filters()
	return (ns.char and ns.char.filters) or {}
end

-- Whether the filters leave an item in the Dungeons, Raids and Sets tabs
function K.Visible(itemID)
	local f = K.Filters()
	if f.hideClassic then
		local entry = ns.Items[itemID]
		if entry and entry[4] == 2 then return false end
	end
	if f.myClass then
		local class = K.PlayerClass()
		if class and ARMOR[class] and not K.UsableBy(itemID, class) then return false end
	end
	return true
end

-- The items the filters leave, and how many they hid
function K.VisibleItems(itemIDs)
	local f = K.Filters()
	if not (f.myClass or f.hideClassic) then return itemIDs, 0 end
	local out = {}
	for _, itemID in ipairs(itemIDs) do
		if K.Visible(itemID) then out[#out + 1] = itemID end
	end
	return out, #itemIDs - #out
end

-- "Plate, mail, and a Warrior's weapons" for the filter's tooltip
local ARMOR_ORDER = { "plate", "mail", "leather", "cloth" }
function K.ClassFilterText()
	local class, _, name = K.PlayerClass()
	if not (class and ARMOR[class]) then return "Only gear your class can use." end
	local armor = {}
	for _, a in ipairs(ARMOR_ORDER) do
		if ARMOR[class][a] then armor[#armor + 1] = a end
	end
	return "Only gear a " .. (name or class) .. " can use: " .. table.concat(armor, " and ") ..
		" armor, its weapon types" .. (SHIELDS[class] and ", shields" or "") .. (RELICS[class] and (", " .. RELICS[class]:lower() .. "s") or "") ..
		", and items made for the class. Rings, necks, cloaks and trinkets always show."
end

----------------------------------------------------------------------
-- Searching, shared by both tabs
----------------------------------------------------------------------
function UI:IsSearching()
	local f = self.filter
	return f.text ~= "" or f.slot ~= nil or f.kind ~= nil
end

function UI:RenderSearch()
	local mode, filter = self:Mode(), self.filter
	local groups, total = mode.Find(filter)
	self.searchGroups, self.searchTotal = groups, total

	-- Results were narrowed to an entry that no longer has any: show them all again
	local focus = filter.focus
	if focus then
		local found = false
		for _, g in ipairs(groups) do
			if g.entry == focus then found = true end
		end
		if not found then filter.focus, focus = nil, nil end
	end

	local matched = 0
	self:BeginContent()
	for _, g in ipairs(groups) do
		if not focus or g.entry == focus then
			matched = matched + #g.rows
			mode.AddResults(self, g)
		end
	end
	if total == 0 then
		for _, line in ipairs(mode.noMatch) do self:AddEntry("note", NOTE_H, { text = line }) end
	end
	self:EndContent()

	local h = self.header
	h.name:SetText("Search results")
	h.badge:Hide()
	h.wowhead:Hide()
	h.clear:Show()
	local meta
	if total == 0 then
		meta = "No matches"
	elseif focus then
		meta = Count(matched, mode.unit) .. " in " .. focus.name .. "   ·   " .. total .. " in all " .. mode.groupUnit .. "s"
	else
		meta = Count(total, mode.unit) .. " in " .. Count(#groups, mode.groupUnit)
	end
	h.meta:SetText(meta)

	local parts = {}
	if filter.text ~= "" then parts[#parts + 1] = 'Matching "' .. (filter.text:gsub("|", "||")) .. '"' end
	if filter.slot then parts[#parts + 1] = "Slot: " .. FILTER_MENUS.slot.names[filter.slot] end
	if filter.kind then parts[#parts + 1] = "Type: " .. FILTER_MENUS.kind.names[filter.kind] end
	local tip
	if total == 0 then
		tip = mode.searchAbout
	elseif focus then
		tip = 'Click "' .. mode.allLabel .. '" on the left to see every match.'
	else
		tip = "Click a " .. mode.groupUnit .. " on the left to see only its matches."
	end
	h.note:SetText(table.concat(parts, "   ·   ") .. ".   " .. tip)

	self:BuildList()
end

-- Forgets the search text and filters without redrawing anything
function UI:ResetFilter()
	local f = self.filter
	f.text, f.slot, f.kind, f.focus = "", nil, nil, nil
	if self.searchBox then self.searchBox:SetText("") end
	if self.filterButtons then self:UpdateFilterButtons() end
end

function UI:FilterChanged()
	if not self.frame then return end
	if self:IsSearching() then
		-- A new search starts with every section open
		self.searchSections = {}
		self.loot:ScrollToTop()
		self:RenderSearch()
	else
		-- Nothing left to search for: back to the entry the results were narrowed to,
		-- or the one that was open before
		local back = self.filter.focus or self.current
		self.filter.focus = nil
		if back then self:Select(back) else self:BuildList() end
	end
end

function UI:SetSearchText(text)
	text = strtrim(text or "")
	if text == self.filter.text then return end
	self.filter.text = text
	self:FilterChanged()
end

-- `fromMenu`: the choice was picked in the dropdown itself, which updates its own label
function UI:SetFilter(which, value, fromMenu)
	if self.filter[which] == value then return end
	self.filter[which] = value
	if not fromMenu then self:UpdateFilterButtons() end
	self:FilterChanged()
end

function UI:FocusEntry(entry)
	self.filter.focus = entry
	self.loot:ScrollToTop()
	self:RenderSearch()
end

function UI:ClearSearch()
	local back = self.filter.focus or self.current
	self:ResetFilter()
	if back then self:Select(back) end
end

-- /fl <text> opens the window straight onto search results
function UI:Search(text)
	if not (self.frame and self.frame:IsShown()) then self:Show() end
	self.searchBox:SetText(text or "")
	self:SetSearchText(text)
end

----------------------------------------------------------------------
-- Opening an entry, switching tabs
----------------------------------------------------------------------
function UI:Select(entry)
	if not entry then return end
	-- Picking an entry leaves the search results
	if self:IsSearching() then self:ResetFilter() end
	local mode = self:Mode()
	self.current = entry
	mode.Remember(entry)
	local h = self.header
	h.clear:Hide()
	h.wowhead:SetShown(select(2, mode.WowheadLink(entry)) ~= nil)
	h.badge:Hide()
	mode.ShowHeader(self, h, entry)
	if self.listKey ~= self.mode .. ":entries" then self:BuildList() else self:UpdateListSelection() end
	self.loot:ScrollToTop()
	self:BeginContent()
	mode.Render(self, entry)
	self:EndContent()
end

function UI:Refresh()
	if not (self.frame and self.frame:IsShown()) then return end
	local scroll = self.loot:GetVerticalScroll()
	if self:IsSearching() then
		self:RenderSearch()
	elseif self.current then
		self:BeginContent()
		self:Mode().Render(self, self.current)
		self:EndContent()
	else
		return
	end
	self.loot:ScrollTo(scroll)
end

-- `quiet` switches without drawing, for a caller that opens something right after
function UI:SetMode(key, quiet)
	if not self.modes[key] or key == self.mode then return end
	self:CloseMenu()
	self.selected[self.mode] = self.current
	self.mode = key
	ns.db.mode = key
	self.current = self.selected[key]
	local f = self.filter
	f.focus = nil
	-- A filter only the other tab offers (like Consumable) doesn't carry over
	if f.slot and not MenuOffers("slot", key, f.slot) then f.slot = nil end
	if f.kind and not MenuOffers("kind", key, f.kind) then f.kind = nil end
	self:UpdateChrome()
	if quiet then return end
	if self:IsSearching() then
		self.loot:ScrollToTop()
		self:RenderSearch()
	else
		self:Select(self.current or self:Mode().Default())
	end
end

-- Right-click on an item or recipe: put it on the wishlist, or take it off
function UI:ToggleWanted(itemID)
	local name, _, _, _, link = ns.ItemDisplay(itemID)
	local wanted = ns.Wishlist.Toggle(itemID)
	ns:Print((link or name) .. (wanted and " is on your wishlist." or " is off your wishlist."))
	self:Refresh()
	-- The Wishlist tab's list and header count what's on it
	if not self:IsSearching() and self.current then
		self:Mode().ShowHeader(self, self.header, self.current)
		self:BuildList()
	end
end

-- /fl dungeons, /fl professions, /fl wishlist
function UI:ShowMode(key)
	if not (self.frame and self.frame:IsShown()) then self:Show() end
	self:SetMode(key)
end

-- Item names arrive from the server asynchronously; repaint visible rows as they do
function UI:RegisterItemEvents(on)
	if not self.itemEvents then
		self.itemEvents = CreateFrame("Frame")
		self.itemEvents:SetScript("OnEvent", function(_, _, itemID, success)
			-- The server answers "no such item" for Classic items Forever removed; stop asking
			if success == false and itemID then ns.MarkNoServerData(itemID) end
			-- Swap a bundled tooltip for the game's own one when the item's data shows up
			if success and itemID and GameTooltip:IsShown() then
				local owner = GameTooltip:GetOwner()
				if owner and owner.isForeverLootItem and owner.itemID == itemID then
					owner:GetScript("OnEnter")(owner)
				end
			end
			if UI.pendingRefresh then return end
			UI.pendingRefresh = true
			C_Timer.After(0.25, function()
				UI.pendingRefresh = false
				for kind, spec in pairs(K.kinds) do
					local pool = spec.live and UI.pools[kind]
					if pool then
						for i = 1, UI.used[kind] or 0 do spec.fill(pool[i], pool[i].entry) end
					end
				end
			end)
		end)
	end
	if on then
		self.itemEvents:RegisterEvent("GET_ITEM_INFO_RECEIVED")
	else
		self.itemEvents:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
	end
end

----------------------------------------------------------------------
-- Show / hide
----------------------------------------------------------------------
function UI:Show()
	self:Create()
	self.frame:Show()
	-- Jump to the dungeon you're standing in, once per visit, so browsing elsewhere isn't undone
	-- (on the Quests tab, to its quests)
	local here = ns.CurrentDungeon()
	local hereMode = here and (self.mode == "quests" and "quests" or (here.isRaid and "raids" or "dungeons"))
	if here and here ~= self.lastAutoDungeon and self.modes[hereMode] then
		self.lastAutoDungeon = here
		self:SetMode(hereMode, true)
		self:Select(here)
	elseif not self.current then
		self:Select(self:Mode().Default())
	else
		self:Refresh()
	end
	if SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_OPEN then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_OPEN) end
end

function UI:Hide()
	if self.frame and self.frame:IsShown() then
		self.frame:Hide()
		if SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_CLOSE then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_CLOSE) end
	end
end

function UI:Toggle()
	if self.frame and self.frame:IsShown() then
		self:Hide()
	else
		self:Show()
	end
end

----------------------------------------------------------------------
-- The Dungeons and Raids tabs: one view over ns.Dungeons and ns.Raids
----------------------------------------------------------------------
local function SortedDungeons()
	local list = {}
	for _, d in ipairs(ns.Dungeons) do list[#list + 1] = d end
	table.sort(list, function(a, b)
		if a.minLevel ~= b.minLevel then return a.minLevel < b.minLevel end
		if a.maxLevel ~= b.maxLevel then return a.maxLevel < b.maxLevel end
		return a.name < b.name
	end)
	return list
end
K.SortedDungeons = SortedDungeons

-- Raids keep their Data.lua order: Forever's own first, then the Classic ones by release
local function SortedRaids()
	local list = {}
	for _, r in ipairs(ns.Raids or {}) do list[#list + 1] = r end
	return list
end
K.SortedRaids = SortedRaids

-- "Level 60" or "Levels 13-18"
local function LevelText(d)
	if d.minLevel == d.maxLevel then return "Level " .. d.minLevel end
	return "Levels " .. d.minLevel .. "-" .. d.maxLevel
end
K.LevelText = LevelText

-- Items the player has looted that the bundled table doesn't list yet
local function LearnedFor(dungeon, keys, known)
	local byDungeon = ns.db.learned[dungeon.key]
	local items, counts = {}, {}
	if not byDungeon then return items, counts end
	for _, key in ipairs(keys) do
		local bucket = byDungeon[key]
		if bucket then
			for itemID, count in pairs(bucket.items) do
				if not known[itemID] and not counts[itemID] then
					items[#items + 1] = itemID
				end
				if not known[itemID] then counts[itemID] = (counts[itemID] or 0) + count end
			end
		end
	end
	table.sort(items)
	return items, counts
end

-- Boss bar: the name in gold over a gold rule, like the dividers in the game's recipe list
-- A section's plus or minus, at the right end of its header
local function SetSectionIcon(icon, id)
	icon:SetAtlas(UI:IsCollapsed(id) and "common-button-list-plus" or "common-button-list-minus", true)
end

-- What a click on a section header does: open or close it, or with Shift every section;
-- a right-click runs `onRight` (a boss's or quest's Wowhead link)
local function SectionClick(self, button)
	if button == "RightButton" then
		if self.onRight then self.onRight(self) end
	elseif IsShiftKeyDown() then
		UI:ToggleAllSections()
	else
		UI:ToggleSection(self.sectionId)
	end
end
K.SectionClick, K.SetSectionIcon = SectionClick, SetSectionIcon

-- "Click to see its loot." and the rest of a header's hint
local function SectionHint(id, what, right)
	return (UI:IsCollapsed(id) and ("Click to see " .. what .. ".") or "Click to close it.") ..
		" Shift-click opens or closes every section." .. (right and (" Right-click for " .. right .. ".") or "")
end
K.SectionHint = SectionHint

-- Boss bar: a section header over the boss's loot. Click it to see the drops, right-click for
-- the boss's Wowhead link.
local function CreateBoss(parent, width)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(width, BOSS_H)
	b.isForeverLootRow = true
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	RowHighlight(b, 0.3)
	b.rule = Atlas(b, "ARTWORK", "Options_HorizontalDivider")
	b.rule:SetPoint("BOTTOMLEFT", 4, 1)
	b.rule:SetPoint("BOTTOMRIGHT", -4, 1)
	b.rule:SetHeight(2)
	b.rule:SetVertexColor(C.gold[1], C.gold[2], C.gold[3])
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetPoint("RIGHT", -8, 1)
	b.name = Text(b, "GameFontNormalLarge")
	b.name:SetPoint("LEFT", 8, 1)
	b.tag = Text(b, "GameFontHighlightSmall", "RIGHT")
	b.tag:SetPoint("RIGHT", -32, 1)
	SetTextColor(b.tag, C.silver)
	b.onRight = function(self)
		if self.url then UI:ShowURL(self.boss.name .. " on Wowhead", self.url) end
	end
	b:SetScript("OnEnter", function(self)
		ShowHint(self, self.boss.name, SectionHint(self.sectionId, "its loot", self.url and "its Wowhead link"))
	end)
	b:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	b:SetScript("OnClick", SectionClick)
	return b
end

K.RegisterKind("boss", CreateBoss, function(b, d)
	b.sectionId = d.id
	b.boss = { name = d.name }
	b.url = d.url
	b.name:SetText(d.name)
	b.tag:SetText(d.tag or "")
	SetSectionIcon(b.icon, d.id)
end)

----------------------------------------------------------------------
-- Quest rows: a quest's status as the quest log and quest givers show it, and the lines under
-- it (where it starts, the quests before it)
----------------------------------------------------------------------
local QUEST_ICON = "Interface\\GossipFrame\\AvailableQuestIcon"
local QLINE_H = 20

-- A yellow "!" you can pick up, a grey one you can't yet, a "?" in your log (yellow when it's
-- ready to turn in), a check when it's done, a cross when it isn't for you
local function SetQuestIcon(tex, status, complete)
	tex:SetDesaturated(false)
	tex:SetAlpha(1)
	if status == "done" then
		tex:SetAtlas("common-icon-checkmark")
	elseif status == "closed" or status == "other" then
		tex:SetAtlas("common-icon-redx")
		tex:SetAlpha(0.8)
	else
		-- a pooled texture keeps an atlas's crop after SetTexture
		tex:SetTexture(status == "active" and (complete and "Interface\\GossipFrame\\ActiveQuestIcon"
			or "Interface\\GossipFrame\\IncompleteQuestIcon") or QUEST_ICON)
		tex:SetTexCoord(0, 1, 0, 1)
		if status ~= "ready" and status ~= "active" and status ~= nil then
			-- not yet: earlier quests, level, reputation, skill
			tex:SetDesaturated(true)
			tex:SetAlpha(0.75)
		end
	end
end
K.SetQuestIcon = SetQuestIcon

-- The quests before one you haven't done yet
local function StepsLeft(id)
	local left = 0
	for _, step in ipairs(id and ns.QuestChain(id) or {}) do
		if ns.QuestStatus(step) ~= "done" then left = left + 1 end
	end
	return left
end

-- Reputation standings by where they start, and their names in your language
local STANDINGS = { { 42000, 8 }, { 21000, 7 }, { 9000, 6 }, { 3000, 5 }, { 0, 4 }, { -3000, 3 }, { -6000, 2 } }
local STANDING_NAMES = { "Hated", "Hostile", "Unfriendly", "Neutral", "Friendly", "Honored", "Revered", "Exalted" }
local function StandingName(rep)
	local reaction = 1
	for _, s in ipairs(STANDINGS) do
		if rep >= s[1] then reaction = s[2] break end
	end
	return _G["FACTION_STANDING_LABEL" .. reaction] or STANDING_NAMES[reaction]
end

-- The game's name for a faction (in your language), or the bundled one for a faction you haven't met
local function FactionName(factionID)
	local d = C_Reputation and C_Reputation.GetFactionDataByID and C_Reputation.GetFactionDataByID(factionID)
	if d and d.name and d.name ~= "" then return d.name end
	return ns.QuestFactions and ns.QuestFactions[factionID] or ("faction " .. factionID)
end

local function SkillName(skillID)
	local s = C_SkillInfo and C_SkillInfo.GetSkillLineInfoByID and C_SkillInfo.GetSkillLineInfoByID(skillID)
	return s and s.name and s.name ~= "" and s.name or ("skill " .. skillID)
end

-- "Available", "In your log", "3 quests first"... and its color
local function StatusText(status, detail, id, q)
	local info = id and ns.QuestInfo and ns.QuestInfo[id]
	if status == "ready" then return "Available", C.gold end
	if status == "active" then
		if detail then return "Ready to turn in", C.green end
		return "In your log", C.blue
	end
	if status == "done" then return "Done", C.grey end
	if status == "level" then
		return "At level " .. ((q and q.req) or (info and info.req) or "?"), C.red
	end
	if status == "rep" then return StandingName(detail[2]) .. " with " .. FactionName(detail[1]), C.red end
	if status == "skill" then return SkillName(detail[1]) .. " " .. detail[2], C.red end
	if status == "special" then return "Something else first", C.silver end
	if status == "locked" then
		if detail then return "Turn in its lead-in first", C.silver end
		local left = StepsLeft(id)
		return left > 0 and (Count(left, "quest") .. " first") or "Earlier quests first", C.silver
	end
	if status == "closed" then return "Closed", C.grey end
	if status == "other" then return "Not for you", C.grey end
	return nil
end
K.QuestStatusText = StatusText

-- A quest's name, by id
local function QuestName(id)
	local info = id and ns.QuestInfo and ns.QuestInfo[id]
	return info and info.name or ("quest " .. tostring(id))
end

-- Tooltip lines about how to get a quest: its status, where it starts and ends, what comes first
local function AddQuestHowTo(id, q)
	local status, detail = ns.QuestStatus(id, q)
	local text, color = StatusText(status, detail, id, q)
	if text then GameTooltip:AddLine(text, color[1], color[2], color[3]) end
	local info = id and ns.QuestInfo and ns.QuestInfo[id]
	if not info then return end
	local silver = C.silver
	if status == "closed" and detail then
		if info.crumb == detail then
			GameTooltip:AddLine("It leads to " .. QuestName(detail) .. ", which you've taken or can't take.", silver[1], silver[2], silver[3], true)
		else
			GameTooltip:AddLine("You took " .. QuestName(detail) .. " instead.", silver[1], silver[2], silver[3], true)
		end
	elseif status == "closed" then
		GameTooltip:AddLine("You can't take it any more.", silver[1], silver[2], silver[3], true)
	elseif status == "locked" and detail then
		GameTooltip:AddLine("Turn in " .. QuestName(detail) .. " first.", silver[1], silver[2], silver[3], true)
	elseif status == "rep" then
		GameTooltip:AddLine("Needs " .. text .. ".", silver[1], silver[2], silver[3], true)
	elseif status == "skill" then
		GameTooltip:AddLine("Needs " .. text .. ".", silver[1], silver[2], silver[3], true)
	elseif status == "special" then
		GameTooltip:AddLine("It needs something the addon can't check, like a buff or an item. Its Wowhead page says what.",
			silver[1], silver[2], silver[3], true)
	end
	if info.from then
		local line = info.from[1] == "item" and ("Starts from an item: " .. info.from[2]) or ("Starts: " .. ns.QuestGiverText(info.from))
		GameTooltip:AddLine(line, C.white[1], C.white[2], C.white[3], true)
	end
	if info.to then
		GameTooltip:AddLine("Turn in: " .. ns.QuestGiverText(info.to), C.white[1], C.white[2], C.white[3], true)
	end
	if info.crumb and status ~= "done" then
		GameTooltip:AddLine("A lead-in to " .. QuestName(info.crumb) .. ".", silver[1], silver[2], silver[3], true)
	end
	local chain = ns.QuestChain(id)
	if #chain > 0 and status ~= "done" then
		local left = StepsLeft(id)
		GameTooltip:AddLine(Count(#chain, "quest") .. " before it" .. (left < #chain and (", " .. (#chain - left) .. " done") or "") .. ".",
			silver[1], silver[2], silver[3], true)
		local nextStep = ns.QuestNextSteps(id, q)[1]
		if nextStep and nextStep.id ~= id then
			local s = ns.QuestInfo[nextStep.id]
			local line
			if nextStep.status == "active" then
				local to = s and (s.to or s.from)
				line = "In your log: " .. QuestName(nextStep.id) .. (to and to[1] ~= "item" and (", turn in to " .. ns.QuestGiverText(to)) or "")
			else
				local from = s and s.from
				line = "Next: " .. QuestName(nextStep.id) .. (from and (from[1] == "item" and (" (from the item " .. from[2] .. ")")
					or (" from " .. ns.QuestGiverText(from))) or "")
			end
			GameTooltip:AddLine(line, C.gold[1], C.gold[2], C.gold[3], true)
		end
	end
end
K.AddQuestHowTo = AddQuestHowTo

-- "Available  ·  Level 22  ·  choose 1 of 3". It leaves out what the bar shows anyway: the
-- faction (only yours is listed) and the level when the status already gives it.
local function QuestTag(q)
	local parts = {}
	local status, detail = ns.QuestStatus(q.id, q)
	local text, color = StatusText(status, detail, q.id, q)
	if text then parts[#parts + 1] = ns.Colorize(color, text) end
	if q.new then parts[#parts + 1] = ns.Colorize(C.green, "New") end
	if q.level and status ~= "level" then parts[#parts + 1] = "Level " .. q.level end
	local choices, rewards = #(q.choices or {}), #(q.rewards or {})
	if choices > 1 then
		parts[#parts + 1] = "choose 1 of " .. choices .. (rewards > 0 and (", plus " .. rewards) or "")
	end
	return table.concat(parts, "  ·  ")
end
K.QuestTag = QuestTag

-- Quest bar: its status mark, and the name colored by how hard the quest is for you, as in the
-- quest log. A section header: click it for where it starts and its rewards (item rows),
-- right-click for the quest's Wowhead link.
local function CreateQuest(parent, width)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(width, QUEST_H)
	b.isForeverLootRow = true
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	RowHighlight(b)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetSize(16, 16)
	b.icon:SetPoint("LEFT", 6, 0)
	b.icon:SetTexture(QUEST_ICON)
	b.toggle = b:CreateTexture(nil, "ARTWORK")
	b.toggle:SetPoint("RIGHT", -8, 0)
	b.tag = Text(b, "GameFontHighlightSmall", "RIGHT")
	b.tag:SetPoint("RIGHT", -32, 0)
	SetTextColor(b.tag, C.silver)
	b.name = Text(b, "GameFontNormal")
	b.name:SetPoint("LEFT", b.icon, "RIGHT", 6, 0)
	b.name:SetPoint("RIGHT", b.tag, "LEFT", -10, 0)
	b:SetScript("OnEnter", function(self)
		local q = self.quest
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(q.name, C.white[1], C.white[2], C.white[3])
		local level = {}
		if q.level then level[#level + 1] = "Level " .. q.level end
		if q.req then level[#level + 1] = "requires level " .. q.req end
		if #level > 0 then GameTooltip:AddLine(table.concat(level, ", "), C.gold[1], C.gold[2], C.gold[3]) end
		GameTooltip:AddLine(ns.QUEST_SIDES[q.side] and (ns.QUEST_SIDES[q.side] .. " only") or "Alliance and Horde",
			C.gold[1], C.gold[2], C.gold[3])
		local choices = #(q.choices or {})
		if choices > 1 then GameTooltip:AddLine("Choose one of " .. choices .. " rewards.", C.gold[1], C.gold[2], C.gold[3]) end
		if q.new then GameTooltip:AddLine("New in Forever.", C.green[1], C.green[2], C.green[3]) end
		for _, change in ipairs(q.changes or {}) do
			GameTooltip:AddLine("Forever: " .. change, C.green[1], C.green[2], C.green[3], true)
		end
		AddQuestHowTo(q.id, q)
		GameTooltip:AddLine(SectionHint(self.sectionId, "where it starts and its rewards", q.id and "its Wowhead link"),
			C.silver[1], C.silver[2], C.silver[3], true)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	b.onRight = function(self)
		local q = self.quest
		if q.id then UI:ShowURL(q.name .. " on Wowhead", ns.WOWHEAD .. "quest=" .. q.id) end
	end
	b:SetScript("OnClick", SectionClick)
	return b
end

K.RegisterKind("quest", CreateQuest, function(b, d)
	b.sectionId = d.id
	b.quest = d.quest
	b.name:SetText(d.quest.name)
	SetTextColor(b.name, d.quest.level and DifficultyColor(d.quest.level) or C.gold)
	b.tag:SetText(QuestTag(d.quest))
	local status, complete = ns.QuestStatus(d.quest.id, d.quest)
	SetQuestIcon(b.icon, status or "ready", complete)
	SetSectionIcon(b.toggle, d.id)
end)
K.QUEST_H = QUEST_H

-- A line under a quest: where it starts, or one of the quests that come before it. A status
-- mark when it's a quest, and the game's map pin button when the spot is known (click it for a
-- pin on your map). data: text, color, right, rightColor, indent, status, complete, giver,
-- questID and name (for the tooltip and the Wowhead link), click (instead of the link), hint
local function CreateQuestLine(parent, width)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(width, QLINE_H)
	b.isForeverLootRow = true
	RowHighlight(b)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetSize(14, 14)
	b.pin = CreateFrame("Button", nil, b)
	b.pin:SetSize(18, 18)
	b.pin:SetPoint("RIGHT", -6, 0)
	b.pin.art = Atlas(b.pin, "ARTWORK", "Waypoint-MapPin-Untracked")
	b.pin.art:SetAllPoints()
	b.pin.glow = Atlas(b.pin, "HIGHLIGHT", "Waypoint-MapPin-Tracked")
	b.pin.glow:SetAllPoints()
	b.pin:SetScript("OnClick", function(self)
		local d = self:GetParent().data
		ns.PinQuestGiver(d.giver, d.name)
	end)
	b.pin:SetScript("OnEnter", function(self)
		local d = self:GetParent().data
		ShowHint(self, d.giver[2], "Click for a map pin on " .. (ns.QuestGiverText(d.giver) or d.giver[2]) ..
			(" (%.1f, %.1f)."):format(d.giver[4], d.giver[5]))
	end)
	b.pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
	b.right = Text(b, "GameFontHighlightSmall", "RIGHT")
	b.right:SetPoint("RIGHT", b.pin, "LEFT", -6, 0)
	b.text = Text(b, "GameFontHighlightSmall")
	b.text:SetPoint("RIGHT", b.right, "LEFT", -8, 0)
	b:SetScript("OnEnter", function(self)
		local d = self.data
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		if d.questID then
			local info = ns.QuestInfo and ns.QuestInfo[d.questID]
			GameTooltip:SetText(d.name or (info and info.name) or "", C.white[1], C.white[2], C.white[3])
			if info and (info.level or info.req) then
				local level = {}
				if info.level then level[#level + 1] = "Level " .. info.level end
				if info.req then level[#level + 1] = "requires level " .. info.req end
				GameTooltip:AddLine(table.concat(level, ", "), C.gold[1], C.gold[2], C.gold[3])
			end
			AddQuestHowTo(d.questID)
		else
			GameTooltip:SetText(d.tipTitle or self.text:GetText() or "", C.white[1], C.white[2], C.white[3])
		end
		if d.hint then GameTooltip:AddLine(d.hint, C.silver[1], C.silver[2], C.silver[3], true) end
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	b:SetScript("OnClick", function(self)
		local d = self.data
		if d.click then
			d.click()
		elseif d.questID then
			UI:ShowURL((d.name or "Quest") .. " on Wowhead", ns.WOWHEAD .. "quest=" .. d.questID)
		end
	end)
	return b
end

K.RegisterKind("qline", CreateQuestLine, function(b, d)
	b.data = d
	local x = 14 + (d.indent or 0)
	b.icon:ClearAllPoints()
	b.text:ClearAllPoints()
	if d.status then
		b.icon:SetPoint("LEFT", x, 0)
		SetQuestIcon(b.icon, d.status, d.complete)
		b.icon:Show()
		b.text:SetPoint("LEFT", b.icon, "RIGHT", 5, 0)
	else
		b.icon:Hide()
		b.text:SetPoint("LEFT", x, 0)
	end
	b.text:SetPoint("RIGHT", b.right, "LEFT", -8, 0)
	b.text:SetText(d.text)
	SetTextColor(b.text, d.color or C.white)
	b.right:SetText(d.right or "")
	SetTextColor(b.right, d.rightColor or C.silver)
	b.pin:SetShown(ns.QuestGiverSpot(d.giver) ~= nil)
end)
K.QLINE_H = QLINE_H

-- The line under a quest: where it starts, and how many quests come before it. `click` makes
-- the line open the quest in the Quests tab.
function K.QuestStartLine(q, click)
	local info = q.id and ns.QuestInfo and ns.QuestInfo[q.id]
	if not info then return nil end
	local giver, text = info.from, nil
	if giver then
		text = giver[1] == "item" and ("Starts from an item: " .. giver[2]) or ("Starts: " .. ns.QuestGiverText(giver))
	end
	local chain = ns.QuestChain(q.id)
	local right
	if #chain > 0 then
		local left = StepsLeft(q.id)
		right = left == 0 and (Count(#chain, "quest") .. " before it, all done") or
			(Count(#chain, "quest") .. " before it" .. (left < #chain and (", " .. (#chain - left) .. " done") or ""))
	end
	if not (text or right) then return nil end
	return { text = text or "Where it starts isn't on Wowhead yet.", color = text and C.white or C.grey, right = right,
		giver = giver, name = q.name, click = click,
		tipTitle = q.name, hint = click and "Click to see the quests before it, and where each starts, in the Quests tab." }
end

local FOOTER = "Click a boss or quest to open it    Item: click for Wowhead, Shift-click to link, Ctrl-click to preview, right-click for the wishlist"

-- A tab over one list of instances. `cfg` gives the list, the labels, and the row and note text.
local function InstanceMode(cfg)
	local M = {
		key = cfg.key,
		tab = cfg.tab,
		icon = cfg.icon,
		listTitle = cfg.listTitle,
		listRight = cfg.listRight,
		allLabel = cfg.allLabel,
		unit = "item",
		groupUnit = cfg.groupUnit,
		searchHint = cfg.searchHint,
		searchAbout = "The search looks at item names, slots, types and stats.",
		noMatch = cfg.noMatch,
		footer = FOOTER,
		filters = true,
	}
	local Sorted = cfg.sorted

	local function Mine(d)
		return d ~= nil and (d.isRaid or false) == cfg.raids
	end

	function M.dataDate()
		return ns.DATA_DATE
	end

	function M.Entries()
		return Sorted()
	end

	M.RowInfo = cfg.rowInfo

	function M.Default()
		local here = ns.CurrentDungeon()
		if Mine(here) then return here end
		local last = ns.db[cfg.remember] and ns.DungeonByKey[ns.db[cfg.remember]]
		if Mine(last) then return last end
		local level = UnitLevel("player") or 1
		local best
		for _, d in ipairs(Sorted()) do
			if level >= d.minLevel and level <= d.maxLevel then return d end
			best = best or d
		end
		return best
	end

	function M.Remember(d)
		ns.db[cfg.remember] = d.key
	end

	-- A new instance Wowhead has no zone page for yet gets no link
	function M.WowheadLink(d)
		if d.zone and d.zone ~= 0 then
			return d.name .. " on Wowhead", ns.WOWHEAD .. "zone=" .. d.zone
		end
		return d.name .. " on Wowhead", nil
	end

	function M.ShowHeader(ui, h, d)
		h.name:SetText(d.name)
		h.badge.text:SetText("New in Forever")
		h.badge:SetWidth(h.badge.text:GetStringWidth() + 12)
		h.badge:SetShown(d.isNew)
		local bossCount = 0
		for _, b in ipairs(d.bosses) do
			if not (b.trash or b.unconfirmed) then bossCount = bossCount + 1 end
		end
		local parts = { LevelText(d) }
		if d.size then parts[#parts + 1] = d.size .. " players" end
		if d.location then parts[#parts + 1] = d.location end
		if d.territory then parts[#parts + 1] = d.territory end
		if bossCount > 0 then parts[#parts + 1] = bossCount .. (bossCount == 1 and " boss" or " bosses") end
		h.meta:SetText(table.concat(parts, "   ·   "))
		h.note:SetText(d.note or cfg.defaultNote())
	end

	function M.Render(ui, d)
		local lastWing
		local usedKeys = {}

		local function AddItems(itemIDs, learnedCounts, pct, hints)
			for _, itemID in ipairs(itemIDs) do
				ui:AddEntry("item", ITEM_H, { itemID = itemID, learnedCount = learnedCounts and learnedCounts[itemID],
					pct = pct and pct[itemID], hint = hints and hints[itemID] })
			end
		end

		local function AddNote(text)
			ui:AddEntry("note", NOTE_H, { text = text })
		end

		-- A boss bar over its drops (a section of its own: the drops show once it's opened)
		local function AddBoss(key, name, tag, url, loot, learnedKeys, emptyText, pct, hints)
			if ui:AddSection("d:" .. d.key .. ":b:" .. key, name, tag, "boss", { name = name, tag = tag, url = url }) then
				ui:AddGap(2)
				return
			end
			ui:AddGap(2)
			local known = {}
			for _, itemID in ipairs(loot) do known[itemID] = true end
			local learned, counts = LearnedFor(d, learnedKeys, known)
			local shown, hidden = K.VisibleItems(loot)
			local shownLearned, hiddenLearned = K.VisibleItems(learned)
			AddItems(shown, nil, pct, hints)
			AddItems(shownLearned, counts)
			if #shown == 0 and #shownLearned == 0 then
				local filtered = hidden + hiddenLearned
				AddNote(filtered > 0 and (Count(filtered, "item") .. " hidden by the My class / Hide Classic filters.") or emptyText)
			end
			ui:AddGap(SECTION_GAP)
		end

		-- A quest bar, then (once it's opened) where it starts and its rewards: the ones to choose
		-- from, then the ones it always gives
		local function AddQuest(q)
			if ui:AddSection("d:" .. d.key .. ":q:" .. (q.id or q.name), q.name, nil, "quest", { quest = q }) then
				ui:AddGap(2)
				return
			end
			local line = K.QuestStartLine(q, UI.OpenQuest and ns.QuestStatus(q.id, q) ~= "other" and function() UI:OpenQuest(d, q.id) end)
			if line then ui:AddEntry("qline", QLINE_H, line) end
			ui:AddGap(2)
			AddItems((K.VisibleItems(q.choices or {})))
			AddItems((K.VisibleItems(q.rewards or {})))
			ui:AddGap(SECTION_GAP)
		end

		-- Returns true when the wing is collapsed, so its bosses are left out
		local function AddWing(label, levels)
			return ui:AddSection("d:" .. d.key .. ":" .. label, label,
				levels and ("Levels " .. levels[1] .. "-" .. levels[2]) or "")
		end

		local collapsed = false
		for _, boss in ipairs(d.bosses) do
			if boss.wing and boss.wing ~= lastWing then
				collapsed = AddWing(boss.wing, d.wings and d.wings[boss.wing])
				lastWing = boss.wing
			elseif not boss.wing and lastWing and (boss.trash or boss.unconfirmed) then
				-- keep instance-wide sections from looking like part of the last wing
				collapsed = AddWing(cfg.raids and "Whole raid" or "Whole dungeon")
				lastWing = nil
			end
			local keys = ns.Learn.KeysForBoss(boss)
			for _, k in ipairs(keys) do usedKeys[k] = true end
			if not collapsed then
				local url = boss.npc and boss.npc[1] and (ns.WOWHEAD .. "npc=" .. boss.npc[1]) or nil
				-- how many drops, so a closed boss still says what it has
				local count, visible = #boss.loot, #(K.VisibleItems(boss.loot))
				local countText = visible < count and (visible .. " of " .. count .. " items")
					or (count .. (count == 1 and " item" or " items"))
				local tag = (boss.tag and (boss.tag .. "  ·  ") or "") .. countText
				local plain = boss.trash or boss.unconfirmed
				AddBoss((boss.wing and (boss.wing .. ":") or "") .. boss.name, boss.name, tag, url, boss.loot, plain and {} or keys,
					boss.trash and "No trash drops listed." or "No drops listed yet. Kill it and loot to record them here.",
					boss.pct, boss.hints)
			end
		end

		-- Bosses we only know about from your own kills
		local byDungeon = ns.db.learned[d.key]
		if byDungeon then
			local extra = {}
			for key, bucket in pairs(byDungeon) do
				if not usedKeys[key] then extra[#extra + 1] = { key = key, name = bucket.name or key } end
			end
			table.sort(extra, function(a, b) return a.name < b.name end)
			if #extra > 0 and not ui:AddSection("d:" .. d.key .. ":recorded", "Recorded by you") then
				for _, e in ipairs(extra) do
					AddBoss("recorded:" .. e.key, e.name, "from your loot", nil, {}, { e.key }, "")
				end
			end
		end

		if #d.bosses == 0 and not byDungeon then
			AddNote("Wowhead has no boss or loot data for this " .. cfg.groupUnit .. " yet.")
			AddNote("Kill its bosses and loot them: drops will be recorded here automatically.")
		end

		-- Its quests for your faction, in a section of their own. A quest whose rewards the
		-- filters all hide (another class's tier token, say) is left out too.
		local quests, otherSide, otherClass, filtered = {}, 0, 0, 0
		for _, q in ipairs(d.quests or {}) do
			local rewards = #(q.choices or {}) + #(q.rewards or {})
			if not ns.QuestForPlayer(q) then
				otherSide = otherSide + 1
			elseif ns.QuestStatus(q.id, q) == "other" then
				otherClass = otherClass + 1   -- another race's or class's
			elseif rewards > 0 and #(K.VisibleItems(q.choices or {})) + #(K.VisibleItems(q.rewards or {})) == 0 then
				filtered = filtered + 1
			else
				quests[#quests + 1] = q
			end
		end
		if #quests + filtered > 0 then
			if ui.contentY > 0 then ui:AddGap(SECTION_GAP) end
			if not ui:AddSection("d:" .. d.key .. ":quests", "Quests", Count(#quests, "quest")) then
				ui:AddGap(4)
				for _, q in ipairs(quests) do AddQuest(q) end
				if otherSide > 0 then
					local faction = UnitFactionGroup and UnitFactionGroup("player")
					AddNote(Count(otherSide, "quest") .. " for the " .. (faction == "Alliance" and "Horde" or "Alliance") ..
						(otherSide == 1 and " isn't" or " aren't") .. " shown.")
				end
				if otherClass > 0 then
					AddNote(Count(otherClass, "quest") .. " for another race or class " .. (otherClass == 1 and "isn't" or "aren't") .. " shown.")
				end
				if filtered > 0 then
					AddNote(Count(filtered, "quest") .. " with only rewards the My class / Hide Classic filters hide " ..
						(filtered == 1 and "isn't" or "aren't") .. " shown.")
				end
			end
		end
	end

	-- Every matching drop, grouped by instance in list order and by boss order within one.
	-- Mirrors Render, so items you recorded yourself are found too.
	function M.Find(filter)
		local terms = K.ParseQuery(filter.text)
		local groups, total = {}, 0
		for _, d in ipairs(Sorted()) do
			local rows = {}
			local function Add(itemID, source, from, wing, learnedCount, pct, hint)
				local extra = (learnedCount and " seen " or "") .. (ns.Wishlist.IsWanted(itemID) and " wanted wishlist " or "")
				if K.Visible(itemID) and K.Matches(SearchInfo(itemID), terms, filter, extra) then
					rows[#rows + 1] = { itemID = itemID, source = source, from = from, wing = wing,
						learnedCount = learnedCount, pct = pct, hint = hint }
				end
			end

			local usedKeys = {}
			for _, boss in ipairs(d.bosses) do
				local keys = ns.Learn.KeysForBoss(boss)
				for _, k in ipairs(keys) do usedKeys[k] = true end
				local where = d.name .. (boss.wing and (" (" .. boss.wing .. ")") or "")
				local source, from
				if boss.trash then
					source, from = "Trash mobs", "Drops from trash in " .. where .. "."
				elseif boss.unconfirmed then
					source, from = "Boss unconfirmed", "Found in " .. where .. "."
				else
					source, from = boss.name, "Drops from " .. boss.name .. " in " .. where .. "."
				end
				for _, itemID in ipairs(boss.loot) do
					Add(itemID, source, from, boss.wing, nil, boss.pct and boss.pct[itemID], boss.hints and boss.hints[itemID])
				end
				if not (boss.trash or boss.unconfirmed) then
					local known = {}
					for _, itemID in ipairs(boss.loot) do known[itemID] = true end
					local learned, counts = LearnedFor(d, keys, known)
					for _, itemID in ipairs(learned) do Add(itemID, source, from, boss.wing, counts[itemID]) end
				end
			end

			local byDungeon = ns.db.learned[d.key]
			if byDungeon then
				local extra = {}
				for key, bucket in pairs(byDungeon) do
					if not usedKeys[key] then extra[#extra + 1] = { key = key, name = bucket.name or key } end
				end
				table.sort(extra, function(a, b) return a.name < b.name end)
				for _, e in ipairs(extra) do
					local learned, counts = LearnedFor(d, { e.key }, {})
					for _, itemID in ipairs(learned) do
						Add(itemID, e.name, "You looted it from " .. e.name .. " in " .. d.name .. ".", nil, counts[itemID])
					end
				end
			end

			-- Quest rewards, in a Quests section after the bosses
			for _, q in ipairs(d.quests or {}) do
				if ns.QuestForPlayer(q) then
					local from = "Reward from the quest " .. q.name .. " (" .. d.name .. ")."
					for _, itemID in ipairs(q.choices or {}) do Add(itemID, "Quest reward", from, "Quests") end
					for _, itemID in ipairs(q.rewards or {}) do Add(itemID, "Quest reward", from, "Quests") end
				end
			end

			if #rows > 0 then
				groups[#groups + 1] = { entry = d, rows = rows }
				total = total + #rows
			end
		end
		return groups, total
	end

	-- A header per instance, and per wing where it has them, with how many matches it holds
	function M.AddResults(ui, g)
		local d = g.entry
		local runs = {}
		for _, r in ipairs(g.rows) do
			local last = runs[#runs]
			if not last or last.wing ~= r.wing then
				last = { wing = r.wing, rows = {} }
				runs[#runs + 1] = last
			end
			last.rows[#last.rows + 1] = r
		end
		for _, run in ipairs(runs) do
			if ui.contentY > 0 then ui:AddGap(SECTION_GAP) end
			local levels = run.wing and d.wings and d.wings[run.wing]
			local right = Count(#run.rows, "item") .. "   ·   " ..
				(levels and ("Levels " .. levels[1] .. "-" .. levels[2]) or LevelText(d))
			if not ui:AddSection("s:d:" .. d.key .. ":" .. (run.wing or ""), run.wing and (d.name .. ": " .. run.wing) or d.name, right) then
				for _, r in ipairs(run.rows) do ui:AddEntry("item", ITEM_H, r) end
			end
		end
	end

	return M
end

local Dungeons = InstanceMode({
	key = "dungeons",
	tab = "Dungeons",
	icon = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01",
	listTitle = "Dungeons",
	listRight = "Levels",
	allLabel = "All dungeons",
	groupUnit = "dungeon",
	raids = false,
	remember = "lastDungeon",
	searchHint = "Search dungeons, e.g. gloves",
	noMatch = {
		"Nothing in any dungeon matches that.",
		"Try a slot like gloves or ring, a type like dagger or plate, or a stat like agility.",
	},
	sorted = SortedDungeons,
	-- name, levels (colored by how hard the dungeon is for you, as quests are), tag, and
	-- whether it's at your level
	rowInfo = function(d)
		local level = UnitLevel("player") or 0
		return d.name, d.minLevel .. "-" .. d.maxLevel, d.isNew and "New" or "", level >= d.minLevel and level <= d.maxLevel,
			nil, K.DifficultyColor(math.floor((d.minLevel + d.maxLevel) / 2))
	end,
	defaultNote = function()
		return "Classic loot plus Forever's new drops, from Wowhead, wowtbc.gg and Mobalytics (" ..
			(ns.DATA_DATE or "") .. "). " .. ns.Colorize(C.green, "New") .. " = added in Forever. " ..
			ns.Colorize(C.grey, "Classic") .. " = not in Forever's game data, so it may have been replaced."
	end,
})

local Raids = InstanceMode({
	key = "raids",
	tab = "Raids",
	icon = "Interface\\Icons\\INV_Misc_Head_Dragon_01",
	listTitle = "Raids",
	listRight = "Players",
	allLabel = "All raids",
	groupUnit = "raid",
	raids = true,
	remember = "lastRaid",
	searchHint = "Search raids, e.g. trinket",
	noMatch = {
		"Nothing in any raid matches that.",
		"Try a slot like helm or ring, a type like sword or plate, or a stat like spell power.",
	},
	sorted = SortedRaids,
	-- Forever's new raids say New; Classic raids Forever hasn't announced say Classic
	rowInfo = function(r)
		local level = UnitLevel("player") or 0
		local tag, color = "", nil
		if r.isNew then
			tag = "New"
		elseif r.status == "classic" then
			tag, color = "Classic", C.grey
		end
		return r.name, tostring(r.size or ""), tag, level >= r.minLevel and level <= r.maxLevel, color
	end,
	defaultNote = function()
		return "Loot from Wowhead (" .. (ns.DATA_DATE or "") .. "). " .. ns.Colorize(C.green, "New") ..
			" = added in Forever. " .. ns.Colorize(C.grey, "Classic") .. " = not in Forever's game data."
	end,
})

UI:RegisterMode(Dungeons)
UI:RegisterMode(Raids)
