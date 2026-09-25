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
-- Sections the player opened or closed (id -> true open, false closed). Sections in a
-- dungeon or profession start collapsed and this lasts the session; search results
-- start open and forget their state with each new search.
UI.sections, UI.searchSections = {}, {}

local WIDTH, HEIGHT = 870, 590
local TITLE_H, FOOTER_H = 34, 26
local LIST_W = 272
local LIST_ROW_H = 24
local HEADER_H = 90
local WING_H = 26
local BOSS_H = 28
local ITEM_H = 26
local NOTE_H = 22
local SECTION_GAP = 10
local SCROLL_STEP = 48
local SEARCH_H, FILTER_H, TOGGLE_H = 24, 22, 18
local QUEST_H = 26
local SOURCE_W = 140
local PAINT_PAD = 60
local MENU_COLS, MENU_COL_W, MENU_ROW_H, MENU_PAD = 3, 92, 20, 8
K.WING_H, K.ITEM_H, K.NOTE_H, K.SECTION_GAP = WING_H, ITEM_H, NOTE_H, SECTION_GAP

----------------------------------------------------------------------
-- Small widget helpers
----------------------------------------------------------------------
local function Tex(parent, layer, color, alpha)
	local t = parent:CreateTexture(nil, layer or "BACKGROUND")
	t:SetColorTexture(color[1], color[2], color[3], alpha or 1)
	return t
end

local function Border(frame, color, alpha)
	local top = Tex(frame, "BORDER", color, alpha)
	top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT"); top:SetHeight(1)
	local bottom = Tex(frame, "BORDER", color, alpha)
	bottom:SetPoint("BOTTOMLEFT"); bottom:SetPoint("BOTTOMRIGHT"); bottom:SetHeight(1)
	local left = Tex(frame, "BORDER", color, alpha)
	left:SetPoint("TOPLEFT"); left:SetPoint("BOTTOMLEFT"); left:SetWidth(1)
	local right = Tex(frame, "BORDER", color, alpha)
	right:SetPoint("TOPRIGHT"); right:SetPoint("BOTTOMRIGHT"); right:SetWidth(1)
	return { top, bottom, left, right }
end

local function SetBorderColor(edges, color)
	for _, t in ipairs(edges) do t:SetColorTexture(color[1], color[2], color[3], 1) end
end

-- Small arrows drawn from color bars, so they don't depend on texture files
local function DownArrow(parent, color)
	local a = CreateFrame("Frame", nil, parent)
	a:SetSize(7, 4)
	for i, w in ipairs({ 7, 5, 3, 1 }) do
		local line = Tex(a, "ARTWORK", color, 1)
		line:SetSize(w, 1)
		line:SetPoint("TOP", 0, 1 - i)
	end
	return a
end

local function RightArrow(parent, color)
	local a = CreateFrame("Frame", nil, parent)
	a:SetSize(4, 7)
	for i, h in ipairs({ 7, 5, 3, 1 }) do
		local line = Tex(a, "ARTWORK", color, 1)
		line:SetSize(1, h)
		line:SetPoint("LEFT", i - 1, 0)
	end
	return a
end

local fonts = {}
local function Font(key, base, color, size)
	if not fonts[key] then
		base = base or GameFontNormal
		local f = CreateFont("ForeverLootFont_" .. key)
		f:CopyFontObject(base)
		if size then
			local file, _, flags = base:GetFont()
			f:SetFont(file, size, flags or "")
		end
		f:SetTextColor(color[1], color[2], color[3])
		fonts[key] = f
	end
	return fonts[key]
end

local function Text(parent, font, justify)
	local fs = parent:CreateFontString(nil, "OVERLAY")
	fs:SetFontObject(font)
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

local function FlatButton(parent, label, width, height)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(width, height)
	b.bg = Tex(b, "BACKGROUND", C.steel, 1)
	b.bg:SetAllPoints()
	b.label = Text(b, Font("button", GameFontHighlightSmall, C.light, 11), "CENTER")
	b.label:SetPoint("CENTER")
	b.label:SetText(label)
	b:SetScript("OnEnter", function(self) self.bg:SetColorTexture(C.blue[1], C.blue[2], C.blue[3], 1) end)
	b:SetScript("OnLeave", function(self) self.bg:SetColorTexture(C.steel[1], C.steel[2], C.steel[3], 1) end)
	return b
end

local function ShowHint(owner, title, line)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:AddLine(title, C.light[1], C.light[2], C.light[3])
	if line then GameTooltip:AddLine(line, C.mist[1], C.mist[2], C.mist[3], true) end
	GameTooltip:Show()
end

K.Tex, K.Border, K.Font, K.Text, K.SetTextColor, K.HexToRGB = Tex, Border, Font, Text, SetTextColor, HexToRGB
K.Count, K.Money, K.ShowHint = Count, Money, ShowHint

-- ScrollFrame with a slim brand-colored scrollbar and mouse wheel support
local function CreateScrollArea(parent, contentWidth)
	local sf = CreateFrame("ScrollFrame", nil, parent)
	local content = CreateFrame("Frame", nil, sf)
	content:SetSize(contentWidth, 1)
	sf:SetScrollChild(content)
	sf.content = content

	local bar = CreateFrame("Slider", nil, parent)
	bar:SetOrientation("VERTICAL")
	bar:SetWidth(6)
	bar:SetPoint("TOPLEFT", sf, "TOPRIGHT", 4, 0)
	bar:SetPoint("BOTTOMLEFT", sf, "BOTTOMRIGHT", 4, 0)
	local track = Tex(bar, "BACKGROUND", C.graphite, 0.7)
	track:SetAllPoints()
	local thumb = bar:CreateTexture(nil, "OVERLAY")
	thumb:SetColorTexture(C.blue[1], C.blue[2], C.blue[3], 1)
	thumb:SetSize(6, 40)
	bar:SetThumbTexture(thumb)
	bar:SetMinMaxValues(0, 0)
	bar:SetValueStep(1)
	bar:SetValue(0)
	bar:SetScript("OnValueChanged", function(_, value)
		sf:SetVerticalScroll(value)
		if sf.OnScrolled then sf:OnScrolled() end
	end)
	bar.thumb = thumb
	sf.bar = bar

	sf:EnableMouseWheel(true)
	sf:SetScript("OnMouseWheel", function(_, delta)
		local lo, hi = bar:GetMinMaxValues()
		bar:SetValue(math.max(lo, math.min(hi, bar:GetValue() - delta * SCROLL_STEP)))
	end)

	function sf:SetContentHeight(h)
		content:SetHeight(math.max(h, 1))
		local view = self:GetHeight()
		local maxScroll = math.max(0, h - view)
		bar:SetMinMaxValues(0, maxScroll)
		if maxScroll <= 0 then
			bar:Hide()
			bar:SetValue(0)
			self:SetVerticalScroll(0)
		else
			bar:Show()
			thumb:SetHeight(math.max(24, view * view / h))
			if bar:GetValue() > maxScroll then bar:SetValue(maxScroll) end
		end
	end

	function sf:ScrollToTop()
		bar:SetValue(0)
		self:SetVerticalScroll(0)
	end

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

-- Item flags from Data.lua: 1 new in Forever, 2 Classic only, 3 new with no confirmed boss
local BADGES = {
	owned = { "OWNED", C.blue },
	seen = { "SEEN", C.blue },
	new = { "NEW", C.red },
	classic = { "CLASSIC", C.slate },
}
K.BADGES = BADGES

-- The tooltip line under any item that can go on the wishlist
function K.WishlistNote(itemID)
	if ns.Wishlist.IsWanted(itemID) then
		return { "On your wishlist. Right-click to take it off.", C.light }
	end
	return { "Right-click to add it to your wishlist.", C.mist }
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
-- Wowhead link popup (WoW can't open a browser, so give a copyable URL)
----------------------------------------------------------------------
function UI:ShowURL(title, url)
	local p = self.urlPopup
	if not p then
		p = CreateFrame("Frame", "ForeverLootURLPopup", UIParent)
		p:SetSize(460, 104)
		p:SetPoint("CENTER", 0, 160)
		p:SetFrameStrata("DIALOG")
		p:SetToplevel(true)
		p:EnableMouse(true)
		Tex(p, "BACKGROUND", C.night, 0.98):SetAllPoints()
		Border(p, C.blue, 1)

		p.title = Text(p, Font("body", GameFontHighlight, C.light, 12))
		p.title:SetPoint("TOPLEFT", 14, -14)
		p.title:SetPoint("RIGHT", -40, 0)

		local close = CreateFrame("Button", nil, p)
		close:SetSize(24, 24)
		close:SetPoint("TOPRIGHT", -6, -6)
		close.bg = Tex(close, "BACKGROUND", C.graphite, 0)
		close.bg:SetAllPoints()
		local x = Text(close, Font("close", GameFontHighlight, C.light, 13), "CENTER")
		x:SetPoint("CENTER", 0, 1)
		x:SetText("X")
		close:SetScript("OnEnter", function(self) self.bg:SetColorTexture(C.red[1], C.red[2], C.red[3], 1) end)
		close:SetScript("OnLeave", function(self) self.bg:SetColorTexture(C.graphite[1], C.graphite[2], C.graphite[3], 0) end)
		close:SetScript("OnClick", function() p:Hide() end)

		local eb = CreateFrame("EditBox", nil, p)
		eb:SetPoint("TOPLEFT", 14, -40)
		eb:SetPoint("TOPRIGHT", -14, -40)
		eb:SetHeight(26)
		eb:SetAutoFocus(false)
		eb:SetFontObject(Font("url", ChatFontNormal, C.light))
		eb:SetTextInsets(8, 8, 0, 0)
		Tex(eb, "BACKGROUND", C.black, 0.7):SetAllPoints()
		Border(eb, C.graphite, 1)
		eb:SetScript("OnEscapePressed", function() p:Hide() end)
		eb:SetScript("OnEnterPressed", function() p:Hide() end)
		eb:SetScript("OnTextChanged", function(self, userInput)
			if userInput then
				self:SetText(p.url or "")
				self:HighlightText()
			end
		end)
		eb:SetScript("OnMouseUp", function(self) self:HighlightText() end)
		p.editBox = eb

		local hint = Text(p, Font("hint", GameFontHighlightSmall, C.mist, 10))
		hint:SetPoint("BOTTOMLEFT", 14, 12)
		hint:SetText("Press Ctrl+C (Cmd+C on Mac) to copy, then paste it into your browser.")

		tinsert(UISpecialFrames, "ForeverLootURLPopup")
		self.urlPopup = p
	end
	p.url = url
	p.title:SetText(title)
	p.editBox:SetText(url)
	p:Show()
	p.editBox:SetFocus()
	p.editBox:HighlightText()
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

local function CreateSearchBox(parent)
	local eb = CreateFrame("EditBox", "ForeverLootSearchBox", parent)
	eb:SetHeight(SEARCH_H)
	eb:SetAutoFocus(false)
	eb:SetMaxLetters(60)
	eb:EnableMouse(true)
	eb:SetFontObject(Font("search", ChatFontNormal, C.light, 12))
	eb:SetTextInsets(24, 22, 0, 0)
	Tex(eb, "BACKGROUND", C.black, 0.7):SetAllPoints()
	eb.edges = Border(eb, C.graphite, 1)

	local icon = eb:CreateTexture(nil, "ARTWORK")
	icon:SetSize(14, 14)
	icon:SetPoint("LEFT", 6, 0)
	icon:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
	icon:SetVertexColor(C.mist[1], C.mist[2], C.mist[3])

	eb.hint = Text(eb, Font("search_hint", GameFontHighlightSmall, C.mist, 11))
	eb.hint:SetPoint("LEFT", 24, 0)
	eb.hint:SetPoint("RIGHT", -22, 0)
	eb.hint:SetAlpha(0.75)

	local clear = CreateFrame("Button", nil, eb)
	clear:SetSize(18, 18)
	clear:SetPoint("RIGHT", -3, 0)
	clear.bg = Tex(clear, "BACKGROUND", C.red, 0)
	clear.bg:SetAllPoints()
	local x = Text(clear, Font("search_clear", GameFontHighlightSmall, C.light, 11), "CENTER")
	x:SetPoint("CENTER", 0, 0)
	x:SetText("X")
	clear:SetScript("OnEnter", function(self)
		self.bg:SetColorTexture(C.red[1], C.red[2], C.red[3], 1)
		ShowHint(self, "Clear the search")
	end)
	clear:SetScript("OnLeave", function(self)
		self.bg:SetColorTexture(C.red[1], C.red[2], C.red[3], 0)
		GameTooltip:Hide()
	end)
	clear:SetScript("OnClick", function()
		eb:SetText("")
		eb:ClearFocus()
		UI:SetSearchText("")
	end)
	clear:Hide()
	eb.clear = clear

	eb:SetScript("OnTextChanged", function(self, userInput)
		local text = self:GetText()
		self.hint:SetShown(text == "")
		self.clear:SetShown(text ~= "")
		if userInput then UI:SetSearchText(text) end
	end)
	eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	eb:SetScript("OnEditFocusGained", function(self) SetBorderColor(self.edges, C.blue) end)
	eb:SetScript("OnEditFocusLost", function(self) SetBorderColor(self.edges, C.graphite) end)
	return eb
end

local function CreateDropdown(parent, which, width)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(width, FILTER_H)
	b.which = which
	b.bg = Tex(b, "BACKGROUND", C.black, 0.7)
	b.bg:SetAllPoints()
	b.edges = Border(b, C.graphite, 1)
	b.text = Text(b, Font("filter", GameFontHighlightSmall, C.mist, 11))
	b.text:SetPoint("LEFT", 8, 0)
	b.text:SetPoint("RIGHT", -20, 0)
	DownArrow(b, C.mist):SetPoint("RIGHT", -8, 0)
	b:SetScript("OnEnter", function(self) SetBorderColor(self.edges, C.blue) end)
	b:SetScript("OnLeave", function(self) SetBorderColor(self.edges, C.graphite) end)
	b:SetScript("OnClick", function(self)
		UI:ClearSearchFocus()
		UI:OpenMenu(self)
	end)
	return b
end

-- A checkbox for the loot filters (My class, Hide Classic)
local function CreateToggle(parent, key, label, width)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(width, TOGGLE_H)
	b.key = key
	local box = CreateFrame("Frame", nil, b)
	box:SetSize(12, 12)
	box:SetPoint("LEFT", 1, 0)
	Tex(box, "BACKGROUND", C.black, 0.7):SetAllPoints()
	box.edges = Border(box, C.graphite, 1)
	b.box = box
	b.check = Tex(box, "ARTWORK", C.blue, 1)
	b.check:SetPoint("TOPLEFT", 3, -3)
	b.check:SetPoint("BOTTOMRIGHT", -3, 3)
	b.text = Text(b, Font("toggle", GameFontHighlightSmall, C.mist, 11))
	b.text:SetPoint("LEFT", box, "RIGHT", 6, 0)
	b.text:SetText(label)
	b:SetScript("OnEnter", function(self)
		SetBorderColor(self.box.edges, C.blue)
		ShowHint(self, self.text:GetText(), self.Hint and self.Hint())
	end)
	b:SetScript("OnLeave", function(self)
		SetBorderColor(self.box.edges, C.graphite)
		GameTooltip:Hide()
	end)
	b:SetScript("OnClick", function(self)
		UI:ClearSearchFocus()
		UI:ToggleFilter(self.key)
	end)
	return b
end

local function CreateMenuOption(menu)
	local o = CreateFrame("Button", nil, menu)
	o:SetHeight(MENU_ROW_H)
	o.hover = Tex(o, "BACKGROUND", C.steel, 0.55)
	o.hover:SetAllPoints()
	o.hover:Hide()
	o.selected = Tex(o, "BACKGROUND", C.blue, 1)
	o.selected:SetAllPoints()
	o.selected:Hide()
	o.text = Text(o, Font("menu_option", GameFontHighlightSmall, C.light, 11))
	o.text:SetPoint("LEFT", 8, 0)
	o.text:SetPoint("RIGHT", -4, 0)
	o:SetScript("OnEnter", function(self) if not self.selected:IsShown() then self.hover:Show() end end)
	o:SetScript("OnLeave", function(self) self.hover:Hide() end)
	o:SetScript("OnClick", function(self)
		UI:CloseMenu()
		UI:SetFilter(menu.which, self.key)
	end)
	return o
end

function UI:OpenMenu(button)
	local m = self.menu
	if not m then
		-- Invisible layer over the whole screen, under the menu: a click anywhere else closes it
		local catcher = CreateFrame("Button", nil, self.frame)
		catcher:SetFrameStrata("DIALOG")
		catcher:SetAllPoints(UIParent)
		catcher:EnableMouse(true)
		catcher:SetScript("OnMouseDown", function() UI:CloseMenu() end)
		catcher:Hide()
		self.menuCatcher = catcher

		m = CreateFrame("Frame", nil, self.frame)
		m:SetFrameStrata("DIALOG")
		m:SetFrameLevel(catcher:GetFrameLevel() + 10)
		m:EnableMouse(true)
		Tex(m, "BACKGROUND", C.night, 0.98):SetAllPoints()
		Border(m, C.blue, 1)
		m.options, m.labels = {}, {}
		m:Hide()
		self.menu = m
	end

	local spec = FILTER_MENUS[button.which]
	local current = self.filter[button.which]
	m.which = button.which
	for _, o in ipairs(m.options) do o:Hide() end
	for _, l in ipairs(m.labels) do l:Hide() end

	local inner = MENU_COLS * MENU_COL_W
	local y, used = MENU_PAD, 0
	local function AddOption(key, name, x, width)
		used = used + 1
		local o = m.options[used]
		if not o then
			o = CreateMenuOption(m)
			m.options[used] = o
		end
		o:ClearAllPoints()
		o:SetPoint("TOPLEFT", MENU_PAD + x, -y)
		o:SetWidth(width)
		o.key = key
		o.text:SetText(name)
		o.selected:SetShown(key == current)
		o.hover:Hide()
		o:Show()
	end

	AddOption(nil, spec.all, 0, inner)
	y = y + MENU_ROW_H + 4
	for g, group in ipairs(MenuGroups(button.which, self.mode)) do
		local label = m.labels[g]
		if not label then
			label = Text(m, Font("label", GameFontNormalSmall, C.red, 10))
			m.labels[g] = label
		end
		label:ClearAllPoints()
		label:SetPoint("TOPLEFT", MENU_PAD + 8, -(y + 4))
		label:SetText(group[1]:upper())
		label:Show()
		y = y + 20
		for i = 2, #group do
			local col = (i - 2) % MENU_COLS
			AddOption(group[i][1], group[i][2], col * MENU_COL_W, MENU_COL_W)
			if col == MENU_COLS - 1 or i == #group then y = y + MENU_ROW_H end
		end
		y = y + 4
	end
	m:SetSize(inner + MENU_PAD * 2, y + MENU_PAD - 4)
	m:ClearAllPoints()
	m:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -2)
	self.menuCatcher:Show()
	m:Show()
end

function UI:CloseMenu()
	if self.menu then
		self.menu:Hide()
		self.menuCatcher:Hide()
	end
end

function UI:UpdateFilterButtons()
	for which, b in pairs(self.filterButtons) do
		local spec, value = FILTER_MENUS[which], self.filter[which]
		b.text:SetText(spec.label .. ": " .. ns.Colorize(C.light, value and spec.names[value] or "Any"))
		local bg = value and C.steel or C.black
		b.bg:SetColorTexture(bg[1], bg[2], bg[3], value and 1 or 0.7)
	end
end

function UI:UpdateToggles()
	local f = K.Filters()
	for key, t in pairs(self.toggles or {}) do
		local on = f[key] and true or false
		t.check:SetShown(on)
		SetTextColor(t.text, on and C.light or C.mist)
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

	local f = CreateFrame("Frame", "ForeverLootFrame", UIParent)
	f:SetSize(WIDTH, HEIGHT)
	f:SetFrameStrata("HIGH")
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:Hide()
	self.frame = f
	self:ResetPosition(true)
	tinsert(UISpecialFrames, "ForeverLootFrame")

	Tex(f, "BACKGROUND", C.night, 0.97):SetAllPoints()
	Border(f, C.graphite, 1)

	-- Title bar (drag handle)
	local bar = CreateFrame("Frame", nil, f)
	bar:SetPoint("TOPLEFT", 1, -1)
	bar:SetPoint("TOPRIGHT", -1, -1)
	bar:SetHeight(TITLE_H)
	bar:EnableMouse(true)
	bar:RegisterForDrag("LeftButton")
	bar:SetScript("OnDragStart", function() f:StartMoving() end)
	bar:SetScript("OnDragStop", function() f:StopMovingOrSizing(); UI:SavePosition() end)
	Tex(bar, "BACKGROUND", C.navy, 1):SetAllPoints()
	local stripe = Tex(bar, "ARTWORK", C.red, 1)
	stripe:SetPoint("BOTTOMLEFT"); stripe:SetPoint("BOTTOMRIGHT"); stripe:SetHeight(2)

	local icon = bar:CreateTexture(nil, "ARTWORK")
	icon:SetSize(20, 20)
	icon:SetPoint("LEFT", 10, 1)
	icon:SetTexture(ns.ICON)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	local title = Text(bar, Font("title", GameFontNormalLarge, C.light, 15))
	title:SetPoint("LEFT", icon, "RIGHT", 8, 0)
	title:SetText(ns.name)

	-- A tab per mode, right after the title
	self.tabs = {}
	local x = 38 + math.ceil(title:GetStringWidth()) + 18
	for _, key in ipairs(self.modeOrder) do
		local t = CreateFrame("Button", nil, bar)
		t.key = key
		t:SetHeight(TITLE_H - 2)
		t:SetPoint("TOPLEFT", bar, "TOPLEFT", x, 0)
		t.bg = Tex(t, "BACKGROUND", C.blue, 1)
		t.bg:SetAllPoints()
		t.label = Text(t, Font("tab", GameFontNormal, C.light, 11), "CENTER")
		t.label:SetPoint("CENTER", 0, 1)
		t.label:SetText(self.modes[key].tab:upper())
		t:SetWidth(math.ceil(t.label:GetStringWidth()) + 28)
		t:SetScript("OnEnter", function(self)
			if UI.mode ~= self.key then
				self.bg:SetColorTexture(C.steel[1], C.steel[2], C.steel[3], 0.8)
				self.bg:Show()
				SetTextColor(self.label, C.light)
			end
		end)
		t:SetScript("OnLeave", function() UI:UpdateTabs() end)
		t:SetScript("OnClick", function(self)
			UI:ClearSearchFocus()
			UI:SetMode(self.key)
		end)
		self.tabs[#self.tabs + 1] = t
		x = x + t:GetWidth() + 2
	end

	local close = CreateFrame("Button", nil, bar)
	close:SetSize(TITLE_H - 2, TITLE_H - 2)
	close:SetPoint("TOPRIGHT", 0, 0)
	close.bg = Tex(close, "BACKGROUND", C.red, 0)
	close.bg:SetAllPoints()
	local xText = Text(close, Font("close", GameFontHighlight, C.light, 13), "CENTER")
	xText:SetPoint("CENTER", 0, 1)
	xText:SetText("X")
	close:SetScript("OnEnter", function(self) self.bg:SetColorTexture(C.red[1], C.red[2], C.red[3], 1) end)
	close:SetScript("OnLeave", function(self) self.bg:SetColorTexture(C.red[1], C.red[2], C.red[3], 0) end)
	close:SetScript("OnClick", function() UI:Hide() end)

	-- Left: search, filters and the list
	local left = CreateFrame("Frame", nil, f)
	left:SetPoint("TOPLEFT", 1, -(TITLE_H + 1))
	left:SetPoint("BOTTOMLEFT", 1, FOOTER_H + 1)
	left:SetWidth(LIST_W)
	Tex(left, "BACKGROUND", C.black, 0.28):SetAllPoints()
	local divider = Tex(f, "ARTWORK", C.graphite, 1)
	divider:SetPoint("TOPLEFT", left, "TOPRIGHT")
	divider:SetPoint("BOTTOMLEFT", left, "BOTTOMRIGHT")
	divider:SetWidth(1)

	local search = CreateSearchBox(left)
	search:SetPoint("TOPLEFT", 10, -10)
	search:SetPoint("TOPRIGHT", -10, -10)
	self.searchBox = search

	local filterW = (LIST_W - 26) / 2
	local slotFilter = CreateDropdown(left, "slot", filterW)
	slotFilter:SetPoint("TOPLEFT", search, "BOTTOMLEFT", 0, -6)
	local kindFilter = CreateDropdown(left, "kind", filterW)
	kindFilter:SetPoint("TOPRIGHT", search, "BOTTOMRIGHT", 0, -6)
	self.filterButtons = { slot = slotFilter, kind = kindFilter }

	-- Loot filters, on the tabs that list loot
	local classToggle = CreateToggle(left, "myClass", "My class", filterW)
	classToggle:SetPoint("TOPLEFT", slotFilter, "BOTTOMLEFT", 2, -6)
	classToggle.Hint = function() return K.ClassFilterText() end
	local classicToggle = CreateToggle(left, "hideClassic", "Hide Classic", filterW)
	classicToggle:SetPoint("TOPLEFT", kindFilter, "BOTTOMLEFT", 2, -6)
	classicToggle.Hint = function()
		return "Hide Classic loot: items Wowhead's Forever database doesn't have, so Forever may have replaced them."
	end
	self.toggles = { myClass = classToggle, hideClassic = classicToggle }

	self.listLabel = Text(left, Font("label", GameFontNormalSmall, C.red, 10))
	self.listRight = Text(left, Font("small", GameFontHighlightSmall, C.mist, 10), "RIGHT")

	local listWidth = LIST_W - 26
	local list = CreateScrollArea(left, listWidth)
	self.list = list
	self.left = left

	-- Right: the open entry, or search results
	local right = CreateFrame("Frame", nil, f)
	right:SetPoint("TOPLEFT", left, "TOPRIGHT", 1, 0)
	right:SetPoint("BOTTOMRIGHT", -1, FOOTER_H + 1)
	self.right = right

	local header = CreateFrame("Frame", nil, right)
	header:SetPoint("TOPLEFT")
	header:SetPoint("TOPRIGHT")
	header:SetHeight(HEADER_H)
	Tex(header, "BACKGROUND", C.graphite, 0.35):SetAllPoints()
	local headerLine = Tex(header, "ARTWORK", C.graphite, 1)
	headerLine:SetPoint("BOTTOMLEFT"); headerLine:SetPoint("BOTTOMRIGHT"); headerLine:SetHeight(1)

	header.name = Text(header, Font("h1", GameFontNormalHuge or GameFontNormalLarge, C.light, 20))
	header.name:SetPoint("TOPLEFT", 16, -14)

	header.badge = CreateFrame("Frame", nil, header)
	header.badge:SetHeight(16)
	header.badge:SetPoint("LEFT", header.name, "RIGHT", 10, 0)
	Tex(header.badge, "BACKGROUND", C.red, 1):SetAllPoints()
	header.badge.text = Text(header.badge, Font("badge", GameFontHighlightSmall, C.light, 9), "CENTER")
	header.badge.text:SetPoint("CENTER", 0, 0)
	header.badge.text:SetText("NEW IN FOREVER")
	header.badge:SetWidth(header.badge.text:GetStringWidth() + 12)

	header.meta = Text(header, Font("meta", GameFontHighlight, C.mist, 11))
	header.meta:SetPoint("TOPLEFT", header.name, "BOTTOMLEFT", 0, -6)

	header.note = Text(header, Font("small", GameFontHighlightSmall, C.mist, 10))
	header.note:SetPoint("TOPLEFT", header.meta, "BOTTOMLEFT", 0, -6)
	header.note:SetPoint("RIGHT", -16, 0)
	header.note:SetWordWrap(true)

	header.wowhead = FlatButton(header, "Wowhead", 84, 22)
	header.wowhead:SetPoint("TOPRIGHT", -14, -14)
	header.wowhead:SetScript("OnClick", function()
		local title, url = UI:Mode().WowheadLink(UI.current)
		if url then UI:ShowURL(title, url) end
	end)

	-- Takes the place of the Wowhead button while search results are showing
	header.clear = FlatButton(header, "Clear search", 100, 22)
	header.clear:SetPoint("TOPRIGHT", -14, -14)
	header.clear:SetScript("OnClick", function() UI:ClearSearch() end)
	header.clear:Hide()
	self.header = header

	local contentWidth = WIDTH - LIST_W - 3 - 16 - 22
	local loot = CreateScrollArea(right, contentWidth)
	loot:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 14, -10)
	loot:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT", -18, 8)
	loot.OnScrolled = function() UI:Paint() end
	self.loot = loot
	self.contentWidth = contentWidth

	-- Footer
	local footer = CreateFrame("Frame", nil, f)
	footer:SetPoint("BOTTOMLEFT", 1, 1)
	footer:SetPoint("BOTTOMRIGHT", -1, 1)
	footer:SetHeight(FOOTER_H)
	Tex(footer, "BACKGROUND", C.black, 0.45):SetAllPoints()
	local footerLine = Tex(footer, "ARTWORK", C.graphite, 1)
	footerLine:SetPoint("TOPLEFT"); footerLine:SetPoint("TOPRIGHT"); footerLine:SetHeight(1)
	self.footerHelp = Text(footer, Font("small", GameFontHighlightSmall, C.mist, 10))
	self.footerHelp:SetPoint("LEFT", 12, 0)
	self.footerSource = Text(footer, Font("small", GameFontHighlightSmall, C.mist, 10), "RIGHT")
	self.footerSource:SetPoint("RIGHT", -12, 0)

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
	-- The loot filters take a row under the Slot and Type menus on the tabs that have them
	local top = mode.filters and 96 or 74
	for _, t in pairs(self.toggles) do t:SetShown(mode.filters and true or false) end
	self:UpdateToggles()
	self.listLabel:ClearAllPoints()
	self.listLabel:SetPoint("TOPLEFT", 12, -top)
	self.listRight:ClearAllPoints()
	self.listRight:SetPoint("TOPRIGHT", -14, -top)
	self.list:ClearAllPoints()
	self.list:SetPoint("TOPLEFT", 6, -(top + 18))
	self.list:SetPoint("BOTTOMRIGHT", -16, 6)
	self.listLabel:SetText(mode.listTitle)
	self.listRight:SetText(mode.listRight)
	self.searchBox.hint:SetText(mode.searchHint)
	self.footerHelp:SetText(mode.footer)
	self.footerSource:SetText("Wowhead data " .. (mode.dataDate() or ""))
	self:UpdateFilterButtons()
end

function UI:UpdateTabs()
	for _, t in ipairs(self.tabs) do
		local on = t.key == self.mode
		t.bg:SetColorTexture(C.blue[1], C.blue[2], C.blue[3], 1)
		t.bg:SetShown(on)
		SetTextColor(t.label, on and C.light or C.mist)
	end
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
	b.hover = Tex(b, "BACKGROUND", C.steel, 0.55)
	b.hover:SetAllPoints()
	b.hover:Hide()
	b.selected = Tex(b, "BACKGROUND", C.blue, 1)
	b.selected:SetAllPoints()
	b.selected:Hide()
	b.marker = Tex(b, "ARTWORK", C.red, 1)
	b.marker:SetPoint("TOPLEFT")
	b.marker:SetPoint("BOTTOMLEFT")
	b.marker:SetWidth(3)
	b.levels = Text(b, Font("list_levels", GameFontHighlightSmall, C.mist, 11), "RIGHT")
	b.levels:SetPoint("RIGHT", -6, 0)
	b.levels:SetWidth(40)
	b.tag = Text(b, Font("list_tag", GameFontHighlightSmall, C.red, 9), "RIGHT")
	b.tag:SetPoint("RIGHT", b.levels, "LEFT", -4, 0)
	-- Match count, shown while searching
	b.count = CreateFrame("Frame", nil, b)
	b.count:SetHeight(14)
	b.count:SetPoint("RIGHT", b.levels, "LEFT", -6, 0)
	Tex(b.count, "BACKGROUND", C.graphite, 1):SetAllPoints()
	b.count.text = Text(b.count, Font("badge", GameFontHighlightSmall, C.light, 9), "CENTER")
	b.count.text:SetPoint("CENTER")
	b.count:Hide()
	b.name = Text(b, Font("list_name", GameFontHighlight, C.light, 11))
	b.name:SetPoint("LEFT", 10, 0)
	b.name:SetPoint("RIGHT", b.tag, "LEFT", -4, 0)
	b:SetScript("OnEnter", function(self) if not self.isSelected then self.hover:Show() end end)
	b:SetScript("OnLeave", function(self) self.hover:Hide() end)
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
		local name, right, tag, marker, tagColor = mode.allLabel, "", "", false, nil
		if e.entry then name, right, tag, marker, tagColor = mode.RowInfo(e.entry) end
		row.tagColor = tagColor
		row.name:SetText(name)
		row.levels:SetText(right)
		row.marker:SetShown(marker and true or false)
		row.name:ClearAllPoints()
		row.name:SetPoint("LEFT", 10, 0)
		if e.count then
			row.tag:SetText("")
			row.count.text:SetText(e.count)
			row.count:SetWidth(row.count.text:GetStringWidth() + 10)
			row.count:Show()
			row.name:SetPoint("RIGHT", row.count, "LEFT", -6, 0)
		else
			row.tag:SetText(tag or "")
			row.count:Hide()
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
		if on then row.hover:Hide() end
		SetTextColor(row.levels, on and C.light or C.mist)
		SetTextColor(row.tag, on and C.light or (row.tagColor or C.red))
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
	self.sectionIds, self.sectionOpen = {}, {}
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
-- section's rows when it comes back collapsed.
----------------------------------------------------------------------
function UI:SectionState()
	return self:IsSearching() and self.searchSections or self.sections
end

-- `openByDefault` is for search results, and for a view with a single section
function UI:IsCollapsed(id)
	local open = self:SectionState()[id]
	if open == nil then open = self.sectionOpen[id] or false end
	return not open
end

function UI:AddSection(id, text, right, openByDefault)
	self.sectionIds[#self.sectionIds + 1] = id
	self.sectionOpen[id] = openByDefault or false
	self:AddEntry("wing", WING_H, { id = id, text = text, right = right })
	return self:IsCollapsed(id)
end

function UI:ToggleSection(id)
	self:SectionState()[id] = self:IsCollapsed(id)
	self:Refresh()
end

-- Shift-click: collapse every section if any is open, otherwise open them all
function UI:ToggleAllSections()
	local anyOpen = false
	for _, id in ipairs(self.sectionIds) do
		if not self:IsCollapsed(id) then anyOpen = true end
	end
	local state = self:SectionState()
	for _, id in ipairs(self.sectionIds) do state[id] = not anyOpen end
	self:Refresh()
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
		if w.hover then w.hover:Hide() end
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
-- Section header: click to collapse or expand, shift-click for every section
local function CreateWing(parent, width)
	local w = CreateFrame("Button", nil, parent)
	w:SetSize(width, WING_H)
	w.isForeverLootRow = true
	w:RegisterForClicks("LeftButtonUp")
	w.hover = Tex(w, "BACKGROUND", C.steel, 0.35)
	w.hover:SetPoint("TOPLEFT", 0, -6)
	w.hover:SetPoint("BOTTOMRIGHT", 0, 1)
	w.hover:Hide()
	w.text = Text(w, Font("wing", GameFontNormalSmall, C.red, 11))
	w.text:SetPoint("BOTTOMLEFT", 16, 6)
	w.open = DownArrow(w, C.red)
	w.open:SetPoint("RIGHT", w.text, "LEFT", -5, 0)
	w.closed = RightArrow(w, C.red)
	w.closed:SetPoint("RIGHT", w.text, "LEFT", -6, 0)
	w.levels = Text(w, Font("wing_levels", GameFontHighlightSmall, C.mist, 11), "RIGHT")
	w.levels:SetPoint("BOTTOMRIGHT", -2, 6)
	w.line = Tex(w, "ARTWORK", C.garnet, 0.8)
	w.line:SetHeight(1)
	w.line:SetPoint("LEFT", w.text, "RIGHT", 8, 0)
	w.line:SetPoint("RIGHT", w.levels, "LEFT", -8, 0)
	w:SetScript("OnEnter", function(self)
		if not self.sectionId then return end
		self.hover:Show()
		ShowHint(self, self.text:GetText(), (UI:IsCollapsed(self.sectionId) and "Click to expand." or "Click to collapse.") ..
			" Shift-click expands or collapses every section.")
	end)
	w:SetScript("OnLeave", function(self)
		self.hover:Hide()
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
	w.levels:SetText(d.right or "")
	local collapsed = d.id and UI:IsCollapsed(d.id)
	w.open:SetShown(d.id ~= nil and not collapsed)
	w.closed:SetShown(collapsed and true or false)
	w:EnableMouse(d.id ~= nil)
end)

local function UpdateItemRow(row)
	local name, quality, typeText, icon = ns.ItemDisplay(row.itemID)
	local entry = ns.Items[row.itemID]
	local flag = entry and entry[4]
	row.icon:SetTexture(icon)
	row.name:SetText(name)
	row.name:SetTextColor(HexToRGB(ns.QUALITY_HEX[quality] or "ffffff"))
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
	row.name:SetPoint("LEFT", row.iconFrame, "RIGHT", 8, 0)
	if badge then
		row.badge.text:SetText(badge[1])
		row.badge.bg:SetColorTexture(badge[2][1], badge[2][2], badge[2][3], 1)
		row.badge:SetWidth(row.badge.text:GetStringWidth() + 10)
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
	if row.sourceNote then notes[#notes + 1] = { row.sourceNote, C.light } end
	if bundled and flag ~= 2 then
		notes[#notes + 1] = { "The beta server isn't sending this item's data, so these stats come from Wowhead.", C.mist }
	end
	if row.pctValue then notes[#notes + 1] = { "Drop chance (Classic data): " .. FormatPct(row.pctValue), C.mist } end
	if flag == 1 then
		notes[#notes + 1] = { "New in Forever.", C.red }
	elseif flag == 3 then
		notes[#notes + 1] = { "New in Forever. No site has confirmed which boss drops it yet.", C.red }
	elseif flag == 2 then
		notes[#notes + 1] = { "Classic loot. Wowhead's Forever database doesn't have this item, so Forever may have replaced it.", C.mist }
	end
	if row.hint then notes[#notes + 1] = { "Its name points to " .. row.hint .. ".", C.mist } end
	if row.learnedCount then
		notes[#notes + 1] = { "Recorded from your loot (" .. row.learnedCount .. "x).", C.mist }
	elseif entry and entry[5] then
		notes[#notes + 1] = { "Listed by " .. entry[5] .. ".", C.mist }
	end
	if row.owned then notes[#notes + 1] = { "You have it: it's in your bags, bank or worn.", C.light } end
	notes[#notes + 1] = K.WishlistNote(row.itemID)
	K.AddNotes(notes)
end

local function CreateItem(parent, width)
	local r = CreateFrame("Button", nil, parent)
	r:SetSize(width, ITEM_H)
	r.isForeverLootRow = true
	r.isForeverLootItem = true
	r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	r.hover = Tex(r, "BACKGROUND", C.blue, 0.22)
	r.hover:SetAllPoints()
	r.hover:Hide()
	-- Red bar on the left: it's on your wishlist
	r.wanted = Tex(r, "ARTWORK", C.red, 1)
	r.wanted:SetPoint("TOPLEFT")
	r.wanted:SetPoint("BOTTOMLEFT")
	r.wanted:SetWidth(3)
	r.wanted:Hide()
	local iconFrame = CreateFrame("Frame", nil, r)
	iconFrame:SetSize(22, 22)
	iconFrame:SetPoint("LEFT", 12, 0)
	Tex(iconFrame, "BACKGROUND", C.black, 1):SetAllPoints()
	r.icon = iconFrame:CreateTexture(nil, "ARTWORK")
	r.icon:SetPoint("TOPLEFT", 1, -1)
	r.icon:SetPoint("BOTTOMRIGHT", -1, 1)
	r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	r.iconFrame = iconFrame
	r.pct = Text(r, Font("item_pct", GameFontHighlightSmall, C.mist, 11), "RIGHT")
	r.pct:SetPoint("RIGHT", -8, 0)
	r.pct:SetWidth(40)
	r.source = Text(r, Font("item_source", GameFontHighlightSmall, C.mist, 11), "RIGHT")
	r.source:SetPoint("RIGHT", -8, 0)
	r.source:SetWidth(SOURCE_W)
	r.source:Hide()
	r.type = Text(r, Font("item_type", GameFontHighlightSmall, C.mist, 11), "RIGHT")
	r.type:SetPoint("RIGHT", r.pct, "LEFT", -6, 0)
	r.badge = CreateFrame("Frame", nil, r)
	r.badge:SetSize(40, 14)
	r.badge:SetPoint("RIGHT", r.type, "LEFT", -8, 0)
	r.badge.bg = Tex(r.badge, "BACKGROUND", C.blue, 1)
	r.badge.bg:SetAllPoints()
	r.badge.text = Text(r.badge, Font("badge", GameFontHighlightSmall, C.light, 9), "CENTER")
	r.badge.text:SetPoint("CENTER")
	r.name = Text(r, Font("item_name", GameFontHighlight, C.light, 12))

	r:SetScript("OnEnter", function(self)
		self.hover:Show()
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		local bundled = K.ItemTooltip(self.itemID)
		AddLootNotes(self, ns.Items[self.itemID], bundled)
		GameTooltip:Show()
	end)
	r:SetScript("OnLeave", function(self)
		self.hover:Hide()
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
	n.text = Text(n, Font("note", GameFontHighlightSmall, C.mist, 11))
	n.text:SetPoint("LEFT", 14, 0)
	n.text:SetPoint("RIGHT", -10, 0)
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

function UI:SetFilter(which, value)
	if self.filter[which] == value then return end
	self.filter[which] = value
	self:UpdateFilterButtons()
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
	self.loot.bar:SetValue(scroll)
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
	local here = ns.CurrentDungeon()
	local hereMode = here and (here.isRaid and "raids" or "dungeons")
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

local function CreateBoss(parent, width)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(width, BOSS_H)
	b.bg = Tex(b, "BACKGROUND", C.navy, 0.95)
	b.bg:SetAllPoints()
	local accent = Tex(b, "ARTWORK", C.red, 1)
	accent:SetPoint("TOPLEFT"); accent:SetPoint("BOTTOMLEFT"); accent:SetWidth(3)
	b.name = Text(b, Font("boss", GameFontNormal, C.light, 13))
	b.name:SetPoint("LEFT", 12, 0)
	b.tag = Text(b, Font("boss_tag", GameFontHighlightSmall, C.mist, 10), "RIGHT")
	b.tag:SetPoint("RIGHT", -10, 0)
	b:SetScript("OnEnter", function(self)
		self.bg:SetColorTexture(C.steel[1], C.steel[2], C.steel[3], 1)
		if self.url then ShowHint(self, self.boss.name, "Click for this boss's Wowhead link.") end
	end)
	b:SetScript("OnLeave", function(self)
		self.bg:SetColorTexture(C.navy[1], C.navy[2], C.navy[3], 0.95)
		GameTooltip:Hide()
	end)
	b:SetScript("OnClick", function(self)
		if self.url then UI:ShowURL(self.boss.name .. " on Wowhead", self.url) end
	end)
	return b
end

K.RegisterKind("boss", CreateBoss, function(b, d)
	b.bg:SetColorTexture(C.navy[1], C.navy[2], C.navy[3], 0.95)
	b.boss = { name = d.name }
	b.url = d.url
	b.name:SetText(d.name)
	b.tag:SetText(d.tag or "")
end)

-- "Level 22  ·  Alliance  ·  choose 1 of 3"
local function QuestTag(q)
	local parts = {}
	if q.new then parts[#parts + 1] = ns.Colorize(C.red, "NEW") end
	if q.level then parts[#parts + 1] = "Level " .. q.level end
	local side = ns.QUEST_SIDES[q.side]
	if side then parts[#parts + 1] = side end
	local choices, rewards = #(q.choices or {}), #(q.rewards or {})
	if choices > 1 then
		parts[#parts + 1] = "choose 1 of " .. choices .. (rewards > 0 and (", plus " .. rewards) or "")
	elseif choices + rewards == 0 then
		parts[#parts + 1] = "no item reward"
	end
	return table.concat(parts, "  ·  ")
end
K.QuestTag = QuestTag

-- Quest bar: its rewards follow as item rows. Click for the quest's Wowhead link.
local function CreateQuest(parent, width)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(width, QUEST_H)
	b.isForeverLootRow = true
	b.bg = Tex(b, "BACKGROUND", C.graphite, 0.55)
	b.bg:SetAllPoints()
	local accent = Tex(b, "ARTWORK", C.blue, 1)
	accent:SetPoint("TOPLEFT"); accent:SetPoint("BOTTOMLEFT"); accent:SetWidth(3)
	b.tag = Text(b, Font("quest_tag", GameFontHighlightSmall, C.mist, 10), "RIGHT")
	b.tag:SetPoint("RIGHT", -10, 0)
	b.name = Text(b, Font("quest", GameFontNormal, C.light, 12))
	b.name:SetPoint("LEFT", 12, 0)
	b.name:SetPoint("RIGHT", b.tag, "LEFT", -10, 0)
	b:SetScript("OnEnter", function(self)
		self.bg:SetColorTexture(C.steel[1], C.steel[2], C.steel[3], 0.8)
		local q = self.quest
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(q.name, C.light[1], C.light[2], C.light[3])
		local level = {}
		if q.level then level[#level + 1] = "Level " .. q.level end
		if q.req then level[#level + 1] = "requires level " .. q.req end
		if #level > 0 then GameTooltip:AddLine(table.concat(level, ", "), C.mist[1], C.mist[2], C.mist[3]) end
		GameTooltip:AddLine(ns.QUEST_SIDES[q.side] and (ns.QUEST_SIDES[q.side] .. " only") or "Alliance and Horde",
			C.mist[1], C.mist[2], C.mist[3])
		local choices = #(q.choices or {})
		if choices > 1 then GameTooltip:AddLine("Choose one of " .. choices .. " rewards.", C.mist[1], C.mist[2], C.mist[3]) end
		if q.new then GameTooltip:AddLine("New in Forever.", C.red[1], C.red[2], C.red[3]) end
		for _, change in ipairs(q.changes or {}) do
			GameTooltip:AddLine("Forever: " .. change, C.red[1], C.red[2], C.red[3], true)
		end
		if q.id then GameTooltip:AddLine("Click for its Wowhead link.", C.mist[1], C.mist[2], C.mist[3]) end
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function(self)
		self.bg:SetColorTexture(C.graphite[1], C.graphite[2], C.graphite[3], 0.55)
		GameTooltip:Hide()
	end)
	b:SetScript("OnClick", function(self)
		local q = self.quest
		if q.id then UI:ShowURL(q.name .. " on Wowhead", ns.WOWHEAD .. "quest=" .. q.id) end
	end)
	return b
end

K.RegisterKind("quest", CreateQuest, function(b, d)
	b.bg:SetColorTexture(C.graphite[1], C.graphite[2], C.graphite[3], 0.55)
	b.quest = d.quest
	b.name:SetText(d.quest.name)
	b.tag:SetText(QuestTag(d.quest))
end)
K.QUEST_H = QUEST_H

local FOOTER = "Click: Wowhead link    Shift-click: link in chat    Ctrl-click: preview    Right-click: wishlist    " ..
	ns.Colorize(C.red, "Red bar") .. ": your level"

-- A tab over one list of instances. `cfg` gives the list, the labels, and the row and note text.
local function InstanceMode(cfg)
	local M = {
		key = cfg.key,
		tab = cfg.tab,
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
		h.badge.text:SetText("NEW IN FOREVER")
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

		local function AddBoss(name, tag, url, loot, learnedKeys, emptyText, pct, hints)
			ui:AddEntry("boss", BOSS_H, { name = name, tag = tag, url = url })
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

		-- A quest bar, then its rewards: the ones to choose from, then the ones it always gives
		local function AddQuest(q)
			ui:AddEntry("quest", QUEST_H, { quest = q })
			ui:AddGap(2)
			AddItems((K.VisibleItems(q.choices or {})))
			AddItems((K.VisibleItems(q.rewards or {})))
			ui:AddGap(SECTION_GAP)
		end

		-- Returns true when the wing is collapsed, so its bosses are left out
		local function AddWing(label, levels)
			return ui:AddSection("d:" .. d.key .. ":" .. label, label:upper(),
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
				local tag = boss.tag
				if not boss.trash then
					local count, visible = #boss.loot, #(K.VisibleItems(boss.loot))
					local countText = visible < count and (visible .. " of " .. count .. " items")
						or (count .. (count == 1 and " item" or " items"))
					tag = (tag and (tag .. "  ·  ") or "") .. countText
				end
				local plain = boss.trash or boss.unconfirmed
				AddBoss(boss.name, tag, url, boss.loot, plain and {} or keys,
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
			if #extra > 0 and not ui:AddSection("d:" .. d.key .. ":recorded", "RECORDED BY YOU") then
				for _, e in ipairs(extra) do
					AddBoss(e.name, "from your loot", nil, {}, { e.key }, "")
				end
			end
		end

		if #d.bosses == 0 and not byDungeon then
			AddNote("Wowhead has no boss or loot data for this " .. cfg.groupUnit .. " yet.")
			AddNote("Kill its bosses and loot them: drops will be recorded here automatically.")
		end

		-- Its quests for your faction, in a section of their own. A quest whose rewards the
		-- filters all hide (another class's tier token, say) is left out too.
		local quests, otherSide, filtered = {}, 0, 0
		for _, q in ipairs(d.quests or {}) do
			local rewards = #(q.choices or {}) + #(q.rewards or {})
			if not ns.QuestForPlayer(q) then
				otherSide = otherSide + 1
			elseif rewards > 0 and #(K.VisibleItems(q.choices or {})) + #(K.VisibleItems(q.rewards or {})) == 0 then
				filtered = filtered + 1
			else
				quests[#quests + 1] = q
			end
		end
		if #quests + filtered > 0 then
			if ui.contentY > 0 then ui:AddGap(SECTION_GAP) end
			if not ui:AddSection("d:" .. d.key .. ":quests", "QUESTS", Count(#quests, "quest")) then
				ui:AddGap(4)
				for _, q in ipairs(quests) do AddQuest(q) end
				if otherSide > 0 then
					local faction = UnitFactionGroup and UnitFactionGroup("player")
					AddNote(Count(otherSide, "quest") .. " for the " .. (faction == "Alliance" and "Horde" or "Alliance") ..
						(otherSide == 1 and " isn't" or " aren't") .. " shown.")
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

	-- A header per instance, and per wing where it has them
	function M.AddResults(ui, g)
		local d = g.entry
		local section, collapsed = false, false
		for _, r in ipairs(g.rows) do
			if r.wing ~= section then
				if ui.contentY > 0 then ui:AddGap(SECTION_GAP) end
				local levels = r.wing and d.wings and d.wings[r.wing]
				collapsed = ui:AddSection("s:d:" .. d.key .. ":" .. (r.wing or ""),
					(r.wing and (d.name .. ": " .. r.wing) or d.name):upper(),
					levels and ("Levels " .. levels[1] .. "-" .. levels[2]) or LevelText(d), true)
				section = r.wing
			end
			if not collapsed then ui:AddEntry("item", ITEM_H, r) end
		end
	end

	return M
end

local Dungeons = InstanceMode({
	key = "dungeons",
	tab = "Dungeons",
	listTitle = "DUNGEONS",
	listRight = "LEVELS",
	allLabel = "All dungeons",
	groupUnit = "dungeon",
	raids = false,
	remember = "lastDungeon",
	searchHint = "Search every dungeon, e.g. gloves",
	noMatch = {
		"Nothing in any dungeon matches that.",
		"Try a slot like gloves or ring, a type like dagger or plate, or a stat like agility.",
	},
	sorted = SortedDungeons,
	-- name, right column, tag, whether the red bar shows
	rowInfo = function(d)
		local level = UnitLevel("player") or 0
		return d.name, d.minLevel .. "-" .. d.maxLevel, d.isNew and "NEW" or "", level >= d.minLevel and level <= d.maxLevel
	end,
	defaultNote = function()
		return "Classic loot plus Forever's new drops, from Wowhead, wowtbc.gg and Mobalytics (" ..
			(ns.DATA_DATE or "") .. "). " .. ns.Colorize(C.red, "NEW") .. " = added in Forever. " ..
			ns.Colorize(C.light, "CLASSIC") .. " = not in Forever's game data, so it may have been replaced."
	end,
})

local Raids = InstanceMode({
	key = "raids",
	tab = "Raids",
	listTitle = "RAIDS",
	listRight = "PLAYERS",
	allLabel = "All raids",
	groupUnit = "raid",
	raids = true,
	remember = "lastRaid",
	searchHint = "Search every raid, e.g. trinket",
	noMatch = {
		"Nothing in any raid matches that.",
		"Try a slot like helm or ring, a type like sword or plate, or a stat like spell power.",
	},
	sorted = SortedRaids,
	-- Forever's new raids say NEW; Classic raids Forever hasn't announced say CLASSIC
	rowInfo = function(r)
		local level = UnitLevel("player") or 0
		local tag, color = "", nil
		if r.isNew then
			tag = "NEW"
		elseif r.status == "classic" then
			tag, color = "CLASSIC", C.mist
		end
		return r.name, tostring(r.size or ""), tag, level >= r.minLevel and level <= r.maxLevel, color
	end,
	defaultNote = function()
		return "Loot from Wowhead (" .. (ns.DATA_DATE or "") .. "). " .. ns.Colorize(C.red, "NEW") ..
			" = added in Forever. " .. ns.Colorize(C.light, "CLASSIC") .. " = not in Forever's game data."
	end,
})

UI:RegisterMode(Dungeons)
UI:RegisterMode(Raids)
