local ADDON, ns = ...

ns.name = "Forever Loot"
ns.ICON = "Interface\\Icons\\INV_Box_01"
ns.WOWHEAD = "https://www.wowhead.com/forever/"
ns.WOWHEAD_CLASSIC = "https://www.wowhead.com/classic/"

-- The game's own text colors, so the window reads like the rest of the interface
-- (NORMAL_FONT_COLOR, HIGHLIGHT_FONT_COLOR and friends)
local function rgb(hex)
	return {
		tonumber(hex:sub(1, 2), 16) / 255,
		tonumber(hex:sub(3, 4), 16) / 255,
		tonumber(hex:sub(5, 6), 16) / 255,
		hex = hex,
	}
end

ns.COLORS = {
	gold   = rgb("FFD100"), -- headings and labels
	white  = rgb("FFFFFF"), -- body text
	silver = rgb("C0C0C0"), -- secondary text
	grey   = rgb("808080"), -- disabled, Classic-only
	green  = rgb("19FF19"), -- new in Forever
	red    = rgb("FF1919"), -- warnings
	blue   = rgb("88AAFF"), -- owned, recorded by you
	black  = rgb("000000"),
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
	DEFAULT_CHAT_FRAME:AddMessage(ns.Colorize(ns.COLORS.gold, ns.name) .. ": " .. msg)
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

----------------------------------------------------------------------
-- Quests: where each one stands for you, the quests before it, and where they start.
-- ns.QuestInfo (Data.lua) has each quest's earlier quests, from cMaNGOS's vanilla quest data
-- and Wowhead's Forever pages, and who starts it. The rules follow cMaNGOS's Player::CanTakeQuest.
----------------------------------------------------------------------
-- Answers last for one frame (GetTime() is the frame's time): a page asks about the same quests
-- many times while it draws, and nothing about them changes until the next frame
local cache = { time = nil, status = {}, chain = {}, me = nil, extra = {} }
local function Fresh()
	local now = GetTime and GetTime() or 0
	if now ~= cache.time then
		cache.time, cache.me = now, nil
		wipe(cache.status)
		wipe(cache.chain)
		wipe(cache.extra)   -- the Quests tab's own lists
	end
	return cache
end
ns.QuestCache = Fresh

local function Done(id)
	return C_QuestLog ~= nil and C_QuestLog.IsQuestFlaggedCompleted ~= nil and C_QuestLog.IsQuestFlaggedCompleted(id) == true
end

local function InLog(id)
	return C_QuestLog ~= nil and C_QuestLog.IsOnQuest ~= nil and C_QuestLog.IsOnQuest(id) == true
end

-- Data.lua's race and class masks: bit (id - 1) for each one (Lua 5.1 has no bit operators)
local function HasBit(mask, id)
	return math.floor(mask / 2 ^ (id - 1)) % 2 == 1
end

local function Plain(v)
	if v ~= nil and issecretvalue and issecretvalue(v) then return nil end
	return v
end

-- Your faction (1 Alliance, 2 Horde), race id and class id; nil where the game doesn't say
local function Me()
	local c = Fresh()
	if not c.me then
		local faction = UnitFactionGroup and Plain(UnitFactionGroup("player"))
		local race = UnitRace and Plain(select(3, UnitRace("player")))
		local class = UnitClass and Plain(select(3, UnitClass("player")))
		c.me = { faction == "Alliance" and 1 or (faction == "Horde" and 2 or nil), race, class }
	end
	return c.me[1], c.me[2], c.me[3]
end

-- Whether your faction, race and class can take it
local function ForMe(info)
	if not info then return true end
	local side, race, class = Me()
	if (info.side == 1 or info.side == 2) and side and info.side ~= side then return false end
	if info.races and race and not HasBit(info.races, race) then return false end
	if info.classes and class and not HasBit(info.classes, class) then return false end
	return true
end
ns.QuestForMe = function(id) return ForMe(ns.QuestInfo and ns.QuestInfo[id]) end

-- Your reputation with a faction (absolute: 0 is the start of Neutral), or nil if you've never met it
function ns.Reputation(factionID)
	local d = C_Reputation and C_Reputation.GetFactionDataByID and C_Reputation.GetFactionDataByID(factionID)
	return d and Plain(d.currentStanding)
end

-- Your rank in a skill line (Blacksmithing is 164), or 0
function ns.SkillRank(skillID)
	local s = C_SkillInfo and C_SkillInfo.GetSkillLineInfoByID and C_SkillInfo.GetSkillLineInfoByID(skillID)
	return (s and Plain(s.rank)) or 0
end

-- An earlier-quest choice is met when its quest is done (all of them, for a list), or, for a
-- negative id, when that quest is in your log
local function Met(alt)
	if type(alt) == "table" then
		for _, id in ipairs(alt) do
			if not Done(id) then return false end
		end
		return true
	end
	if alt < 0 then return InLog(-alt) end
	return Done(alt)
end

local function PrevMet(info)
	if not (info and info.prev) or #info.prev == 0 then return true end
	for _, alt in ipairs(info.prev) do
		if Met(alt) then return true end
	end
	return false
end

-- A quest that has to be in your log for this one, turned in without it: this one is gone
local function Missed(info)
	for _, alt in ipairs(info.prev) do
		if type(alt) ~= "number" or alt > 0 or not Done(-alt) then return false end
	end
	return true
end

-- The quest of a group you took, which rules this one out
local function TakenInstead(info)
	for _, other in ipairs(info and info.group or {}) do
		if Done(other) or InLog(other) then return other end
	end
end

-- How a quest stands for you, and a detail:
--   "done"    turned in                     "active"  in your log (detail: ready to turn in)
--   "ready"   you can pick it up now        "level"   you're too low
--   "locked"  earlier quests come first     "closed"  gone for you (detail: the quest you took instead)
--   "rep"     needs more reputation (detail: { factionID, reputation })
--   "skill"   needs a profession skill (detail: { skillLineID, rank })
--   "special" needs something more the addon can't check (a buff, an item)
--   "other"   not for your faction, race or class
-- `q` is the dungeon's quest entry (its level is Forever's). A quest without an id (one only
-- wowtbc.gg lists) has no status.
local Status
function ns.QuestStatus(id, q)
	if not id then return nil end
	local c = Fresh()
	local known = c.status[id]
	if known and (q == nil or known.q == q) then return known[1], known[2] end
	local status, detail = Status(id, q)
	c.status[id] = { status, detail, q = q }
	return status, detail
end

Status = function(id, q)
	local info = ns.QuestInfo and ns.QuestInfo[id]
	if Done(id) then return "done" end
	if InLog(id) then
		return "active", C_QuestLog.IsComplete ~= nil and C_QuestLog.IsComplete(id) == true
	end
	if q and not ns.QuestForPlayer(q) then return "other" end
	if not ForMe(info) then return "other" end
	local other = TakenInstead(info)
	if other then return "closed", other end
	if info and info.crumb then
		-- a lead-in only while the quest it leads to is still to take
		local target = ns.QuestStatus(info.crumb)
		if target == "done" or target == "active" or target == "closed" or target == "other" then return "closed", info.crumb end
		if target == "locked" then return "locked" end
	end
	if not PrevMet(info) then
		if Missed(info) then return "closed" end
		return "locked"
	end
	for _, lead in ipairs(info and info.lead or {}) do
		-- with one of its lead-ins in your log, turn that in first
		if InLog(lead) then return "locked", lead end
	end
	local req = (q and q.req) or (info and info.req)
	if req and (UnitLevel("player") or 1) < req then return "level" end
	if info and info.rep then
		local rep = ns.Reputation(info.rep[1])
		if (rep or 0) < info.rep[2] then return "rep", info.rep end
	end
	if info and info.repMax then
		local rep = ns.Reputation(info.repMax[1])
		if rep and rep >= info.repMax[2] then return "closed" end
	end
	if info and info.skill and ns.SkillRank(info.skill[1]) < info.skill[2] then return "skill", info.skill end
	if info and info.special then return "special" end
	return "ready"
end

local function Ids(alt)
	if type(alt) == "table" then return alt end
	return { math.abs(alt) }
end

-- Which of several earlier quests (any one will do) a chain follows: the one you did, the one in
-- your log, one you can take now, one you could take later, and only then the first listed
local PICK = { ready = 1, active = 1, level = 2, rep = 2, skill = 2, special = 2, locked = 3 }
local function PickPrev(info)
	local best, bestRank
	for _, alt in ipairs(info.prev) do
		if Met(alt) then return Ids(alt) end
		local rank = 0
		for _, id in ipairs(Ids(alt)) do
			local status = ns.QuestStatus(id)
			if status == "active" then rank = math.max(rank, 0)
			elseif status == "done" then rank = math.max(rank, 0)
			else rank = math.max(rank, PICK[status] or 4) end
		end
		if not bestRank or rank < bestRank then best, bestRank = alt, rank end
	end
	return Ids(best or info.prev[1])
end

-- The quests that come before one, earliest first, each once
function ns.QuestChain(id)
	local c = Fresh()
	if c.chain[id] then return c.chain[id] end
	local out, seen = {}, { [id] = true }
	local function Walk(qid, depth)
		local info = ns.QuestInfo and ns.QuestInfo[qid]
		if not (info and info.prev) or #info.prev == 0 or depth > 40 then return end
		for _, need in ipairs(PickPrev(info)) do
			if not seen[need] then
				seen[need] = true
				Walk(need, depth + 1)
				out[#out + 1] = need
			end
		end
	end
	Walk(id, 0)
	c.chain[id] = out
	return out
end

-- What you can do now toward a quest: the earliest quests of its chain (or the quest itself) you
-- can pick up or have in your log, as { id, status } pairs
function ns.QuestNextSteps(id, q)
	local steps = {}
	for i, step in ipairs(ns.QuestChain(id)) do steps[i] = step end
	steps[#steps + 1] = id
	local out = {}
	for i, step in ipairs(steps) do
		local status, complete = ns.QuestStatus(step, i == #steps and q or nil)
		if status == "ready" or status == "active" then
			out[#out + 1] = { id = step, status = status, complete = complete }
		end
	end
	return out
end

-- Map, x and y of a quest giver ({ kind, name, uiMapID, x, y } in Data.lua), when known
local function Spot(giver)
	if giver and giver[3] and giver[4] and giver[5] then return giver[3], giver[4], giver[5] end
end
ns.QuestGiverSpot = Spot

-- Zone names from the client, so they're in your language
function ns.MapName(mapID)
	local info = mapID and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
	return info and info.name ~= "" and info.name or nil
end

-- "Gryan Stoutmantle, Westfall"; an item's name
function ns.QuestGiverText(giver)
	if not giver then return nil end
	local zone = giver[1] ~= "item" and ns.MapName(giver[3])
	return zone and (giver[2] .. ", " .. zone) or giver[2]
end

-- Puts the game's map pin (and its arrow in the world) on a quest giver, and TomTom's too
-- when it's installed. Returns false when it can't (no spot known, or a map that takes no pins).
function ns.PinQuestGiver(giver, questName)
	local mapID, x, y = Spot(giver)
	if not mapID then return false end
	local placed = false
	if C_Map and C_Map.CanSetUserWaypointOnMap and C_Map.CanSetUserWaypointOnMap(mapID) and UiMapPoint then
		C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapID, x / 100, y / 100))
		if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
		placed = true
	end
	if TomTom and TomTom.AddWaypoint then
		TomTom:AddWaypoint(mapID, x / 100, y / 100, { title = giver[2], from = ns.name })
		placed = true
	end
	local where = (ns.MapName(mapID) or "") .. (" %.1f, %.1f"):format(x, y)
	if placed then
		if PlaySound and SOUNDKIT and SOUNDKIT.UI_MAP_WAYPOINT_CLICK_TO_PLACE then PlaySound(SOUNDKIT.UI_MAP_WAYPOINT_CLICK_TO_PLACE) end
		ns:Print("map pin on " .. giver[2] .. ", " .. where .. (questName and (" (" .. questName .. ")") or "") .. ".")
	else
		ns:Print(giver[2] .. " is at " .. where .. ". This map doesn't take pins.")
	end
	return placed
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
		GameTooltip:SetText(ns.name, C.white[1], C.white[2], C.white[3])
		GameTooltip:AddLine("Left-click: open dungeon and raid loot, sets and professions", C.gold[1], C.gold[2], C.gold[3])
		local wanted = ns.Wishlist.Count()
		GameTooltip:AddLine("Wishlist: " .. wanted .. (wanted == 1 and " item" or " items"), C.gold[1], C.gold[2], C.gold[3])
		GameTooltip:AddLine("Right-click: commands", C.gold[1], C.gold[2], C.gold[3])
		GameTooltip:AddLine("Drag: move this button", C.gold[1], C.gold[2], C.gold[3])
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
	DEFAULT_CHAT_FRAME:AddMessage("  " .. ns.Colorize(C.white, "/fl") .. "  open or close the loot window")
	DEFAULT_CHAT_FRAME:AddMessage("  " .. ns.Colorize(C.white, "/fl dungeons") .. ", " .. ns.Colorize(C.white, "/fl raids") .. ", " .. ns.Colorize(C.white, "/fl quests") .. ", " .. ns.Colorize(C.white, "/fl sets") .. ", " .. ns.Colorize(C.white, "/fl professions") .. " or " .. ns.Colorize(C.white, "/fl wishlist") .. "  open that tab")
	DEFAULT_CHAT_FRAME:AddMessage("  " .. ns.Colorize(C.white, "/fl gloves") .. "  search the open tab for an item, slot, type, stat or material")
	DEFAULT_CHAT_FRAME:AddMessage("  " .. ns.Colorize(C.white, "/fl tooltip") .. "  turn the \"drops from\" lines on item tooltips on or off")
	DEFAULT_CHAT_FRAME:AddMessage("  " .. ns.Colorize(C.white, "/fl minimap") .. "  show or hide the minimap button")
	DEFAULT_CHAT_FRAME:AddMessage("  " .. ns.Colorize(C.white, "/fl reset") .. "  reset window and button positions")
	DEFAULT_CHAT_FRAME:AddMessage("  " .. ns.Colorize(C.white, "/fl forget") .. "  clear drops recorded from your own loot")
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
	elseif msg == "quests" or msg == "quest" then
		ns.UI:ShowMode("quests")
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
