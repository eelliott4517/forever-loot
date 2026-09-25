local ADDON, ns = ...

ns.name = "Forever Loot"
ns.ICON = "Interface\\Icons\\INV_Box_01"
ns.WOWHEAD = "https://www.wowhead.com/forever/"
ns.WOWHEAD_CLASSIC = "https://www.wowhead.com/classic/"

-- Standley's brand palette
local function rgb(hex)
	return {
		tonumber(hex:sub(1, 2), 16) / 255,
		tonumber(hex:sub(3, 4), 16) / 255,
		tonumber(hex:sub(5, 6), 16) / 255,
		hex = hex,
	}
end

ns.COLORS = {
	black    = rgb("000000"),
	light    = rgb("DFE3E2"),
	mist     = rgb("BAC5C3"),
	slate    = rgb("545354"),
	graphite = rgb("444445"),
	night    = rgb("24282A"),
	blue     = rgb("2564AF"),
	steel    = rgb("264886"),
	navy     = rgb("22356A"),
	red      = rgb("EF3942"),
	crimson  = rgb("DF2236"),
	garnet   = rgb("B61F36"),
}

-- Standard in-game item quality colors, so rarity reads the same as everywhere else in WoW
ns.QUALITY_HEX = {
	[0] = "9d9d9d", [1] = "ffffff", [2] = "1eff00", [3] = "0070dd",
	[4] = "a335ee", [5] = "ff8000", [6] = "e6cc80", [7] = "00ccff",
}

function ns.Colorize(c, text)
	return "|cff" .. c.hex .. text .. "|r"
end

function ns:Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage(ns.Colorize(ns.COLORS.blue, ns.name) .. ": " .. msg)
end

-- API shims: prefer the C_Item namespace, fall back to the classic globals
local C_Item = C_Item
ns.GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
ns.GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
ns.GetItemIcon = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
ns.RequestItem = (C_Item and C_Item.RequestLoadItemDataByID) or function() end
ns.GetItemCount = (C_Item and C_Item.GetItemCount) or GetItemCount
ns.IsEquippedItem = (C_Item and C_Item.IsEquippedItem) or IsEquippedItem

function ns.Normalize(s)
	s = (s or ""):lower():gsub("^the%s+", ""):gsub("[^%w]", "")
	return s
end

----------------------------------------------------------------------
-- Lookup tables built from Data.lua
----------------------------------------------------------------------
ns.DungeonByKey, ns.DungeonByMap, ns.DungeonByName, ns.BossByNPC = {}, {}, {}, {}
ns.ProfessionByKey = {}

local function IndexInstance(d)
	ns.DungeonByKey[d.key] = d
	if d.mapID then ns.DungeonByMap[d.mapID] = d end
	ns.DungeonByName[ns.Normalize(d.name)] = d
	for _, alias in ipairs(d.aliases or {}) do
		ns.DungeonByName[ns.Normalize(alias)] = d
	end
	for _, b in ipairs(d.bosses) do
		b.dungeon = d
		for _, npcID in ipairs(b.npc or {}) do
			ns.BossByNPC[npcID] = b
		end
	end
end

-- Raids share the dungeon lookups, so your own loot and "open where you are" work in both
local function BuildIndexes()
	for _, d in ipairs(ns.Dungeons) do IndexInstance(d) end
	for _, r in ipairs(ns.Raids or {}) do
		r.isRaid = true
		IndexInstance(r)
	end
	for _, p in ipairs(ns.Professions or {}) do
		ns.ProfessionByKey[p.key] = p
	end
end

-- Everywhere an item comes from: boss drops, trash, datamined drops, quest rewards and
-- crafts. Each source is { kind = "boss" | "trash" | "unconfirmed" | "quest" | "craft",
-- instance, boss, pct, quest, profession, recipe }. Built the first time it's asked for.
local sourcesByItem
local NO_SOURCES = {}

local function BuildSources()
	sourcesByItem = {}
	local function Add(itemID, source)
		local list = sourcesByItem[itemID]
		if not list then
			list = {}
			sourcesByItem[itemID] = list
		end
		list[#list + 1] = source
	end
	for _, list in ipairs({ ns.Dungeons, ns.Raids or {} }) do
		for _, d in ipairs(list) do
			for _, b in ipairs(d.bosses) do
				local kind = (b.trash and "trash") or (b.unconfirmed and "unconfirmed") or "boss"
				for _, itemID in ipairs(b.loot) do
					Add(itemID, { kind = kind, instance = d, boss = b, pct = b.pct and b.pct[itemID] })
				end
			end
			for _, q in ipairs(d.quests or {}) do
				for _, itemID in ipairs(q.choices or {}) do Add(itemID, { kind = "quest", instance = d, quest = q }) end
				for _, itemID in ipairs(q.rewards or {}) do Add(itemID, { kind = "quest", instance = d, quest = q }) end
			end
		end
	end
	for _, p in ipairs(ns.Professions or {}) do
		for _, rec in ipairs(p.recipes) do
			if rec.item then Add(rec.item, { kind = "craft", profession = p, recipe = rec }) end
		end
	end
end

function ns.SourcesOf(itemID)
	if not sourcesByItem then BuildSources() end
	return sourcesByItem[itemID] or NO_SOURCES
end

-- Quest sides in Data.lua: 1 Alliance, 2 Horde, 3 both
ns.QUEST_SIDES = { [1] = "Alliance", [2] = "Horde" }

-- Whether the player's faction can take a quest (unknown factions see them all)
function ns.QuestForPlayer(q)
	local faction = UnitFactionGroup and UnitFactionGroup("player")
	local side = ns.QUEST_SIDES[q.side]
	return not side or not faction or (faction ~= "Alliance" and faction ~= "Horde") or side == faction
end

-- Returns the dungeon or raid the player is standing in, if it is one we know
function ns.CurrentDungeon()
	local name, instanceType, _, _, _, _, _, instanceID = GetInstanceInfo()
	if instanceType ~= "party" and instanceType ~= "raid" then return end
	return ns.DungeonByMap[instanceID] or ns.DungeonByName[ns.Normalize(name)]
end

----------------------------------------------------------------------
-- Saved variables
----------------------------------------------------------------------
local defaults = {
	minimap = { angle = 215, hide = false },
	learned = {},
	tooltip = true, -- "Drops from" lines on item tooltips
}

-- Per character (SavedVariablesPerCharacter), since each character chases its own gear
local charDefaults = {
	wishlist = {}, -- [itemID] = { added = time() }
	-- The loot view filters: only gear this class can use, and no Classic-only loot
	filters = { myClass = false, hideClassic = false },
}

local function ApplyDefaults(db, def)
	for k, v in pairs(def) do
		if type(v) == "table" then
			if type(db[k]) ~= "table" then db[k] = {} end
			ApplyDefaults(db[k], v)
		elseif db[k] == nil then
			db[k] = v
		end
	end
end

----------------------------------------------------------------------
-- Wishlist: gear this character wants, added by right-clicking any item or recipe
----------------------------------------------------------------------
local Wishlist = {}
ns.Wishlist = Wishlist

function Wishlist.Items()
	return ns.char and ns.char.wishlist or {}
end

function Wishlist.IsWanted(itemID)
	return itemID ~= nil and Wishlist.Items()[itemID] ~= nil
end

-- Adds or removes an item; returns true when it's now on the list
function Wishlist.Toggle(itemID)
	local items = Wishlist.Items()
	if items[itemID] then
		items[itemID] = nil
		return false
	end
	items[itemID] = { added = time() }
	return true
end

function Wishlist.Count()
	local n = 0
	for _ in pairs(Wishlist.Items()) do n = n + 1 end
	return n
end

-- In your bags, your bank (once you've opened it this session) or worn
function Wishlist.IsOwned(itemID)
	if ns.GetItemCount and (ns.GetItemCount(itemID, true) or 0) > 0 then return true end
	return ns.IsEquippedItem and ns.IsEquippedItem(itemID) and true or false
end

----------------------------------------------------------------------
-- Minimap button
----------------------------------------------------------------------
local function UpdateMinimapPosition()
	local b = ns.minimapButton
	if not b then return end
	local angle = math.rad(ns.db.minimap.angle or 215)
	local radius = (Minimap:GetWidth() / 2) + 5
	b:ClearAllPoints()
	b:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function OnMinimapDragUpdate()
	local mx, my = Minimap:GetCenter()
	local px, py = GetCursorPosition()
	local scale = Minimap:GetEffectiveScale()
	px, py = px / scale, py / scale
	ns.db.minimap.angle = math.deg(math.atan2(py - my, px - mx)) % 360
	UpdateMinimapPosition()
end

local function CreateMinimapButton()
	if ns.minimapButton then return end
	local C = ns.COLORS
	local b = CreateFrame("Button", "ForeverLootMinimapButton", Minimap)
	b:SetSize(31, 31)
	b:SetFrameStrata("MEDIUM")
	b:SetFrameLevel(8)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b:RegisterForDrag("LeftButton")
	b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	local overlay = b:CreateTexture(nil, "OVERLAY")
	overlay:SetSize(53, 53)
	overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	overlay:SetPoint("TOPLEFT")

	local background = b:CreateTexture(nil, "BACKGROUND")
	background:SetSize(20, 20)
	background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	background:SetPoint("TOPLEFT", 7, -5)

	local icon = b:CreateTexture(nil, "ARTWORK")
	icon:SetSize(17, 17)
	icon:SetTexture(ns.ICON)
	icon:SetTexCoord(0.06, 0.94, 0.06, 0.94)
	icon:SetPoint("TOPLEFT", 7, -6)

	b:SetScript("OnClick", function(self, button)
		if button == "RightButton" then
			ns:PrintHelp()
		else
			ns.UI:Toggle()
		end
	end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine(ns.name, C.light[1], C.light[2], C.light[3])
		GameTooltip:AddLine("Left-click: open dungeon and raid loot, sets and professions", C.mist[1], C.mist[2], C.mist[3])
		local wanted = ns.Wishlist.Count()
		GameTooltip:AddLine("Wishlist: " .. wanted .. (wanted == 1 and " item" or " items"), C.mist[1], C.mist[2], C.mist[3])
		GameTooltip:AddLine("Right-click: commands", C.mist[1], C.mist[2], C.mist[3])
		GameTooltip:AddLine("Drag: move this button", C.mist[1], C.mist[2], C.mist[3])
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	b:SetScript("OnDragStart", function(self)
		self:LockHighlight()
		self:SetScript("OnUpdate", OnMinimapDragUpdate)
	end)
	b:SetScript("OnDragStop", function(self)
		self:UnlockHighlight()
		self:SetScript("OnUpdate", nil)
	end)

	ns.minimapButton = b
	UpdateMinimapPosition()
	if ns.db.minimap.hide then b:Hide() end
end

----------------------------------------------------------------------
-- Slash commands
----------------------------------------------------------------------
function ns:PrintHelp()
	local C = ns.COLORS
	self:Print("commands")
	DEFAULT_CHAT_FRAME:AddMessage("  " .. ns.Colorize(C.light, "/fl") .. "  open or close the loot window")
	DEFAULT_CHAT_FRAME:AddMessage("  " .. ns.Colorize(C.light, "/fl dungeons") .. ", " .. ns.Colorize(C.light, "/fl raids") .. ", " .. ns.Colorize(C.light, "/fl sets") .. ", " .. ns.Colorize(C.light, "/fl professions") .. " or " .. ns.Colorize(C.light, "/fl wishlist") .. "  open that tab")
	DEFAULT_CHAT_FRAME:AddMessage("  " .. ns.Colorize(C.light, "/fl gloves") .. "  search the open tab for an item, slot, type, stat or material")
	DEFAULT_CHAT_FRAME:AddMessage("  " .. ns.Colorize(C.light, "/fl tooltip") .. "  turn the \"drops from\" lines on item tooltips on or off")
	DEFAULT_CHAT_FRAME:AddMessage("  " .. ns.Colorize(C.light, "/fl minimap") .. "  show or hide the minimap button")
	DEFAULT_CHAT_FRAME:AddMessage("  " .. ns.Colorize(C.light, "/fl reset") .. "  reset window and button positions")
	DEFAULT_CHAT_FRAME:AddMessage("  " .. ns.Colorize(C.light, "/fl forget") .. "  clear drops recorded from your own loot")
end

SLASH_FOREVERLOOT1 = "/fl"
SLASH_FOREVERLOOT2 = "/foreverloot"
SlashCmdList.FOREVERLOOT = function(msg)
	msg = strtrim((msg or ""):lower())
	if msg == "" or msg == "show" or msg == "toggle" then
		ns.UI:Toggle()
	elseif msg == "minimap" then
		ns.db.minimap.hide = not ns.db.minimap.hide
		if ns.db.minimap.hide then
			ns.minimapButton:Hide()
			ns:Print("minimap button hidden. Type /fl minimap to bring it back.")
		else
			ns.minimapButton:Show()
		end
	elseif msg == "reset" then
		ns.db.window = nil
		ns.db.minimap.angle = defaults.minimap.angle
		UpdateMinimapPosition()
		ns.UI:ResetPosition()
		ns:Print("positions reset.")
	elseif msg == "forget" then
		wipe(ns.db.learned)
		ns.UI:Refresh()
		ns:Print("recorded drops cleared.")
	elseif msg == "dungeons" or msg == "dungeon" then
		ns.UI:ShowMode("dungeons")
	elseif msg == "raids" or msg == "raid" then
		ns.UI:ShowMode("raids")
	elseif msg == "sets" or msg == "set" then
		ns.UI:ShowMode("sets")
	elseif msg == "tooltip" or msg == "tooltips" then
		ns.db.tooltip = not ns.db.tooltip
		ns:Print(ns.db.tooltip and "item tooltips show where each item comes from." or
			"item tooltips no longer show where items come from. Type /fl tooltip to turn it back on.")
	elseif msg == "professions" or msg == "profession" or msg == "prof" or msg == "crafting" then
		ns.UI:ShowMode("professions")
	elseif msg == "wishlist" or msg == "wish" or msg == "list" then
		ns.UI:ShowMode("wishlist")
	elseif msg == "help" or msg == "?" then
		ns:PrintHelp()
	else
		ns.UI:Search(msg)
	end
end

----------------------------------------------------------------------
-- Boot
----------------------------------------------------------------------
local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" and arg1 == ADDON then
		ForeverLootDB = ForeverLootDB or {}
		ApplyDefaults(ForeverLootDB, defaults)
		ns.db = ForeverLootDB
		ForeverLootCharDB = ForeverLootCharDB or {}
		ApplyDefaults(ForeverLootCharDB, charDefaults)
		ns.char = ForeverLootCharDB
		BuildIndexes()
		self:UnregisterEvent("ADDON_LOADED")
	elseif event == "PLAYER_LOGIN" then
		CreateMinimapButton()
		ns.Learn:Init()
	end
end)
