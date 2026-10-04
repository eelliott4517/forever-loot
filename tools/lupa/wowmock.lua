-- Strict mock of the WoW API surface Forever Loot touches. Methods that aren't
-- defined here raise "attempt to call method" errors, so an API typo can't pass.

local function class(parent)
	local c = {}
	c.__index = c
	if parent then setmetatable(c, { __index = parent }) end
	return c
end

MOCK = { events = {}, timers = {}, chat = {}, requested = {}, itemInfo = {}, itemInstant = {} }

---------------------------------------------------------------- regions
local Region = class()
function Region:SetSize(w, h) self._w, self._h = w, h end
function Region:SetWidth(w) self._w = w end
function Region:SetHeight(h) self._h = h end
function Region:GetWidth() return self._w or 0 end
function Region:GetHeight() return self._h or 0 end
function Region:SetPoint(...) self._points = self._points or {}; table.insert(self._points, { ... }) end
function Region:ClearAllPoints() self._points = {} end
function Region:SetAllPoints(rel) self._points = { { "ALL", rel } } end
function Region:GetPoint(i) local p = (self._points or {})[i or 1]; if p then return p[1], p[2], p[3], p[4], p[5] end end
function Region:Show()
	local was = self._shown
	self._shown = true
	if not was and self._scripts and self._scripts.OnShow then self._scripts.OnShow(self) end
end
function Region:Hide()
	local was = self._shown
	self._shown = false
	if was and self._scripts and self._scripts.OnHide then self._scripts.OnHide(self) end
end
function Region:IsShown() return self._shown == true end
function Region:SetShown(on) if on then self:Show() else self:Hide() end end
function Region:IsVisible()
	local r = self
	while r do
		if not r._shown then return false end
		r = r._parent
	end
	return true
end
function Region:SetAlpha(a) self._alpha = a end
function Region:GetParent() return self._parent end

local Texture = class(Region)
function Texture:SetColorTexture(r, g, b, a) self._color = { r, g, b, a } end
function Texture:SetTexture(path) self._texture = path; self._atlas = nil end
-- An atlas crops the texture, and the crop stays through a later SetTexture (as in the client)
-- until SetTexCoord resets it
function Texture:SetTexCoord(l, r, t, b)
	if l == 0 and r == 1 and t == 0 and b == 1 then self._crop = nil else self._crop = { l, r, t, b } end
end
function Texture:SetVertexColor(r, g, b) self._vertex = { r, g, b } end
function Texture:SetAtlas(atlas) assert(type(atlas) == "string", "SetAtlas needs an atlas name"); self._atlas = atlas; self._texture = nil; self._crop = atlas; return true end
function Texture:SetDesaturated(on) assert(type(on) == "boolean", "SetDesaturated needs a boolean"); self._desaturated = on end
function Texture:GetAlpha() return self._alpha or 1 end
function Texture:GetAtlas() return self._atlas end
function Texture:SetBlendMode(mode) self._blend = mode end

local FontString = class(Region)
function FontString:SetFontObject(f) assert(type(f) == "table", "SetFontObject needs a font object"); self._font = f end
function FontString:SetJustifyH(j) self._justify = j end
function FontString:SetWordWrap(on) self._wrap = on end
function FontString:SetText(t)
	assert(t == nil or type(t) == "string" or type(t) == "number", "FontString:SetText got " .. type(t))
	self._text = t ~= nil and tostring(t) or nil
end
function FontString:GetText() return self._text end
function FontString:SetTextColor(r, g, b) self._textColor = { r, g, b } end
function FontString:GetStringWidth() return #(self._text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") * 6 end

---------------------------------------------------------------- frames
local Frame = class(Region)
function Frame:SetScript(name, fn) self._scripts = self._scripts or {}; self._scripts[name] = fn end
function Frame:GetScript(name) return self._scripts and self._scripts[name] end
function Frame:HookScript(name, fn) local old = self:GetScript(name); self:SetScript(name, function(...) if old then old(...) end fn(...) end) end
function Frame:RegisterEvent(e) MOCK.events[e] = MOCK.events[e] or {}; MOCK.events[e][self] = true end
function Frame:UnregisterEvent(e) if MOCK.events[e] then MOCK.events[e][self] = nil end end
function Frame:EnableMouse(on) self._mouse = on end
function Frame:EnableMouseWheel(on) self._wheel = on end
function Frame:SetMovable(on) end
function Frame:StartMoving() end
function Frame:StopMovingOrSizing() end
function Frame:RegisterForDrag() end
function Frame:SetFrameStrata(s) assert(({ BACKGROUND = 1, LOW = 1, MEDIUM = 1, HIGH = 1, DIALOG = 1, FULLSCREEN = 1, FULLSCREEN_DIALOG = 1, TOOLTIP = 1 })[s], "bad strata " .. tostring(s)); self._strata = s end
function Frame:GetFrameStrata() return self._strata or (self._parent and self._parent:GetFrameStrata()) or "MEDIUM" end
function Frame:SetFrameLevel(l) self._level = l end
function Frame:GetFrameLevel() return self._level or ((self._parent and self._parent.GetFrameLevel and self._parent:GetFrameLevel() or 0) + 1) end
function Frame:SetToplevel() end
function Frame:SetClampedToScreen() end
function Frame:CreateTexture(name, layer) local t = setmetatable({ _parent = self, _shown = true, _layer = layer }, Texture); return t end
function Frame:CreateFontString(name, layer) local t = setmetatable({ _parent = self, _shown = true, _layer = layer }, FontString); return t end
function Frame:GetCenter() return 0, 0 end
function Frame:GetEffectiveScale() return 1 end
function Frame:GetName() return self._name end
function Frame:IsMouseOver() return MOCK.mouseOver == self end

local Button = class(Frame)
function Button:RegisterForClicks(...) end
function Button:SetHighlightTexture() end
function Button:LockHighlight() end
function Button:UnlockHighlight() end
function Button:Click(button) local fn = self:GetScript("OnClick"); if fn then fn(self, button or "LeftButton") end end

local EditBox = class(Frame)
function EditBox:SetAutoFocus(on) self._autoFocus = on end
function EditBox:SetFontObject(f) assert(type(f) == "table"); self._font = f end
function EditBox:SetTextInsets() end
function EditBox:SetMaxLetters(n) self._maxLetters = n end
function EditBox:SetText(t)
	assert(self._font, "EditBox font not set")
	assert(type(t) == "string", "EditBox:SetText needs a string, got " .. type(t))
	self._text = t
	local fn = self:GetScript("OnTextChanged")
	if fn then fn(self, false) end
end
function EditBox:GetText() return self._text or "" end
function EditBox:HighlightText() end
function EditBox:SetFocus()
	if MOCK.focus and MOCK.focus ~= self then MOCK.focus:ClearFocus() end
	MOCK.focus = self
	local fn = self:GetScript("OnEditFocusGained"); if fn then fn(self) end
end
function EditBox:ClearFocus()
	if MOCK.focus == self then
		MOCK.focus = nil
		local fn = self:GetScript("OnEditFocusLost"); if fn then fn(self) end
	end
end
function EditBox:HasFocus() return MOCK.focus == self end
-- Test helper: the player typing text (fires OnTextChanged with userInput = true)
function EditBox:Type(t)
	self._text = t
	self:GetScript("OnTextChanged")(self, true)
end

local ScrollFrame = class(Frame)
function ScrollFrame:SetScrollChild(c) self._child = c end
-- Like the game, a scroll change runs OnVerticalScroll
function ScrollFrame:SetVerticalScroll(v)
	self._scroll = v
	local fn = self:GetScript("OnVerticalScroll"); if fn then fn(self, v) end
end
function ScrollFrame:GetVerticalScroll() return self._scroll or 0 end
function ScrollFrame:GetVerticalScrollRange() return math.max(0, (self._child and self._child:GetHeight() or 0) - self:GetHeight()) end
function ScrollFrame:UpdateScrollChildRect() end

local Slider = class(Frame)
function Slider:SetOrientation() end
function Slider:SetThumbTexture(t) end
function Slider:SetMinMaxValues(lo, hi) self._min, self._max = lo, hi end
function Slider:GetMinMaxValues() return self._min or 0, self._max or 0 end
function Slider:SetValueStep() end
function Slider:SetValue(v)
	v = math.max(self._min or 0, math.min(self._max or 0, v))
	self._value = v
	local fn = self:GetScript("OnValueChanged"); if fn then fn(self, v) end
end
function Slider:GetValue() return self._value or 0 end

local CheckButton = class(Button)
local DropdownButton = class(Button)
local CLASSES = { Frame = Frame, Button = Button, EditBox = EditBox, ScrollFrame = ScrollFrame, Slider = Slider,
	CheckButton = CheckButton, DropdownButton = DropdownButton }
-- Extension mocks add widget types and methods through these
MOCK.classes = CLASSES
MOCK.class = class
MOCK.frames = {}
function CreateFrame(kind, name, parent, template)
	local cls = assert(CLASSES[kind], "CreateFrame kind " .. tostring(kind))
	local f = setmetatable({ _parent = parent, _shown = true, _name = name, _kind = kind }, cls)
	if name then _G[name] = f end
	table.insert(MOCK.frames, f)
	-- Templates come from tools/test/templates.lua, loaded after this file
	if template then assert(MOCK.ApplyTemplate, "templates.lua isn't loaded")(f, template) end
	return f
end

UIParent = CreateFrame("Frame", "UIParent")
Minimap = CreateFrame("Frame", "Minimap")
Minimap:SetSize(140, 140)
WorldFrame = CreateFrame("Frame", "WorldFrame")

---------------------------------------------------------------- fonts
local FontObject = class()
function FontObject:CopyFontObject(other) self._file, self._size, self._flags = other._file, other._size, other._flags end
function FontObject:GetFont() return self._file, self._size, self._flags end
function FontObject:SetFont(file, size, flags) self._file, self._size, self._flags = file, size, flags end
function FontObject:SetTextColor() end
function CreateFont(name) local f = setmetatable({ _name = name }, FontObject); _G[name] = f; return f end
for _, n in ipairs({ "GameFontNormal", "GameFontNormalSmall", "GameFontNormalLarge", "GameFontNormalHuge",
	"GameFontHighlight", "GameFontHighlightSmall", "ChatFontNormal" }) do
	local f = CreateFont(n)
	f:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
end

---------------------------------------------------------------- tooltip
-- Retail-style tooltips: SetOwner clears (firing OnTooltipCleared), and showing an item
-- runs every TooltipDataProcessor post-call registered for items
MOCK.postCalls = {}
Enum = { TooltipDataType = { Item = 0, Spell = 1, Unit = 2 } }
TooltipDataProcessor = {
	AddTooltipPostCall = function(kind, fn)
		MOCK.postCalls[kind] = MOCK.postCalls[kind] or {}
		table.insert(MOCK.postCalls[kind], fn)
	end,
}
local function MakeTooltip(name)
	local t = CreateFrame("Frame", name)
	t._shown = false
	t.lines = {}
	function t:ClearLines()
		self.lines, self._item = {}, nil
		local fn = self:GetScript("OnTooltipCleared")
		if fn then fn(self) end
	end
	function t:SetOwner(owner) self._owner = owner; self:ClearLines() end
	function t:GetOwner() return self._owner end
	function t:SetText(text) self.lines = { text } end
	function t:AddLine(text) table.insert(self.lines, text) end
	function t:AddDoubleLine(l, r) table.insert(self.lines, l .. " | " .. r) end
	function t:GetItem()
		if self._item then return "Item " .. self._item, "|cffffffff|Hitem:" .. self._item .. "::::::::|h[Item]|h|r", self._item end
	end
	-- data.id is the item id, or whatever a test passes (a secret, say)
	function t:SetItemByID(id, dataID)
		self._item = id
		table.insert(self.lines, "<game tooltip for " .. tostring(id) .. ">")
		for _, fn in ipairs(MOCK.postCalls[Enum.TooltipDataType.Item] or {}) do
			fn(self, { type = Enum.TooltipDataType.Item, id = dataID == nil and id or dataID })
		end
	end
	function t:SetHyperlink(l) table.insert(self.lines, "<hyperlink " .. l .. ">") end
	return t
end
GameTooltip = MakeTooltip("GameTooltip")
ItemRefTooltip = MakeTooltip("ItemRefTooltip")
function MOCK.TooltipText(t) return table.concat((t or GameTooltip).lines, "\n") end

---------------------------------------------------------------- class and faction
MOCK.classFile, MOCK.faction = "ROGUE", "Alliance"
local CLASS_INFO = { WARRIOR = { "Warrior", 1 }, PALADIN = { "Paladin", 2 }, HUNTER = { "Hunter", 3 }, ROGUE = { "Rogue", 4 },
	PRIEST = { "Priest", 5 }, SHAMAN = { "Shaman", 7 }, MAGE = { "Mage", 8 }, WARLOCK = { "Warlock", 9 }, DRUID = { "Druid", 11 } }
function UnitClass(unit)
	assert(unit == "player", "UnitClass(" .. tostring(unit) .. ")")
	local info = CLASS_INFO[MOCK.classFile]
	return info[1], MOCK.classFile, info[2]
end
function UnitFactionGroup(unit)
	assert(unit == "player", "UnitFactionGroup(" .. tostring(unit) .. ")")
	return MOCK.faction, MOCK.faction
end

---------------------------------------------------------------- globals
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function strsplit(sep, s)
	local out = {}
	for part in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do out[#out + 1] = part end
	return unpack(out)
end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
tinsert = table.insert
UISpecialFrames = {}
SlashCmdList = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) table.insert(MOCK.chat, msg) end }
SOUNDKIT = { IG_CHARACTER_INFO_OPEN = 1, IG_CHARACTER_INFO_CLOSE = 2 }
function PlaySound(id) table.insert(MOCK.sounds or {}, id) end
MOCK.level = 25
function UnitLevel() return MOCK.level end
MOCK.instance = { "Elwynn Forest", "none", 0, "", 0, 0, false, 0 }
function GetInstanceInfo() return unpack(MOCK.instance) end
-- Each call is a new frame, unless a test freezes the clock (MOCK.frozen) to see what the
-- addon does within one frame (it caches answers for a frame)
MOCK.clock = 1000
function GetTime()
	if not MOCK.frozen then MOCK.clock = MOCK.clock + 0.001 end
	return MOCK.clock
end
function UnitGUID() return nil end
-- Loot window and rolls: MOCK.loot = { link, ... }, MOCK.rolls[rollID] = link
MOCK.loot, MOCK.rolls = {}, {}
function GetNumLootItems() return #MOCK.loot end
function GetLootSlotLink(i) return MOCK.loot[i] end
function GetLootRollItemLink(id) return MOCK.rolls[id] end
time = os.time
-- Secret values: MOCK.Secret() makes one; any string use of it errors like the real thing
local secretMeta
function MOCK.Secret()
	local p = newproxy(true)
	local mt = getmetatable(p)
	mt.__index = function() error("attempt to index a secret value") end
	mt.__concat = function() error("attempt to concatenate a secret value") end
	mt.__tostring = function() error("attempt to convert a secret value") end
	MOCK.secrets = MOCK.secrets or {}
	MOCK.secrets[p] = true
	return p
end
function issecretvalue(v) return MOCK.secrets ~= nil and MOCK.secrets[v] == true end
MOCK.equipped = {}
function IsEquippedItem(id) return MOCK.equipped[id] == true end
SOUNDKIT.RAID_WARNING = 8959
MOCK.sounds = {}
MOCK.links = {}
function IsModifierKeyDown() return MOCK.shift or MOCK.ctrl or false end
function IsShiftKeyDown() return MOCK.shift or false end
function HandleModifiedItemClick(link) table.insert(MOCK.links, link) return true end
-- Forever has no GetSpellLink, GetNumSkillLines or GetSkillLineInfo globals, and
-- ChatEdit_InsertLink only with the deprecation fallbacks on. So only the C_ versions exist here.
MOCK.chatOpen = true   -- ChatFrameUtil.InsertLink only inserts into an open chat box
ChatFrameUtil = {
	InsertLink = function(link)
		if not MOCK.chatOpen then return false end
		table.insert(MOCK.links, link)
		return true
	end,
}
C_Spell = { GetSpellLink = function(id) return "|cff71d5ff|Hspell:" .. id .. "|h[Spell " .. id .. "]|h|r" end }
-- Skills panel: MOCK.skills = { { "Professions", true }, { "Leatherworking", false, 125, 150, 165 }, ... }
-- (name, header, rank, max, skill line id). MOCK.hiddenSkills are under a collapsed header: not
-- in the list, but C_SkillInfo.GetSkillLineInfoByID still finds them.
MOCK.skills, MOCK.hiddenSkills = {}, {}
local function SkillInfo(s)
	return { name = s[1], isHeader = s[2] == true, isCollapsed = false, rank = s[3] or 0, tempPoints = 0, modifier = 0,
		maxRank = s[4] or 0, skillID = s[5] or 0, isAbandonable = false }
end
C_SkillInfo = {
	GetNumSkillLines = function() return #MOCK.skills end,
	GetSkillLineInfo = function(i) local s = MOCK.skills[i]; return s and SkillInfo(s) end,
	GetSkillLineInfoByID = function(id)
		for _, list in ipairs({ MOCK.skills, MOCK.hiddenSkills }) do
			for _, s in ipairs(list) do if s[5] == id then return SkillInfo(s) end end
		end
	end,
}
-- Loot sources: MOCK.lootSources[slot] = { guid, count, ... }
MOCK.lootSources = {}
function GetLootSourceInfo(slot) local s = MOCK.lootSources[slot]; if s then return unpack(s) end end
MOCK.bags = {}
function GetItemCount(id) return MOCK.bags[id] or 0 end
function GetCursorPosition() return 0, 0 end
function InCombatLockdown() return false end
INVTYPE_HAND = "Hands"
INVTYPE_FINGER = "Finger"

C_Timer = { After = function(_, fn) table.insert(MOCK.timers, fn) end }
function MOCK.RunTimers() local t = MOCK.timers; MOCK.timers = {}; for _, fn in ipairs(t) do fn() end end

C_Item = {
	GetItemInfo = function(id) local i = MOCK.itemInfo[id]; if i then return unpack(i) end end,
	GetItemInfoInstant = function(id) local i = MOCK.itemInstant[id]; if i then return unpack(i) end end,
	GetItemIconByID = function() return nil end,
	RequestLoadItemDataByID = function(id) MOCK.requested[id] = true end,
	GetItemCount = function(id) return MOCK.bags[id] or 0 end,
	IsEquippedItem = function(id) return MOCK.equipped[id] == true end,
}

-- Quests and maps, as Forever has them (C_QuestLog, C_Map, C_SuperTrack; no global
-- IsQuestFlaggedCompleted). MOCK.questsDone[id] = true once turned in; MOCK.questLog[id] = true
-- in the log, "complete" when it's ready to turn in.
MOCK.questsDone, MOCK.questLog = {}, {}
MOCK.questCalls = 0
C_QuestLog = {
	IsQuestFlaggedCompleted = function(id)
		assert(type(id) == "number", "IsQuestFlaggedCompleted needs a quest id")
		MOCK.questCalls = MOCK.questCalls + 1
		return MOCK.questsDone[id] == true
	end,
	IsOnQuest = function(id) assert(type(id) == "number", "IsOnQuest needs a quest id"); return MOCK.questLog[id] ~= nil end,
	IsComplete = function(id) assert(type(id) == "number", "IsComplete needs a quest id"); return MOCK.questLog[id] == "complete" end,
}
MOCK.race = { "Human", "Human", 1 }
function UnitRace(unit) assert(unit == "player", "UnitRace(" .. tostring(unit) .. ")"); return unpack(MOCK.race) end
-- Every map has a name; MOCK.noPins[id] marks maps that take no user waypoint (instances)
MOCK.mapNames, MOCK.noPins = { [1436] = "Westfall", [1453] = "Stormwind City", [1433] = "Redridge Mountains" }, {}
C_Map = {
	GetMapInfo = function(id)
		assert(type(id) == "number", "GetMapInfo needs a map id")
		return { mapID = id, name = MOCK.mapNames[id] or ("Map " .. id), mapType = 3, parentMapID = 0 }
	end,
	CanSetUserWaypointOnMap = function(id) assert(type(id) == "number"); return not MOCK.noPins[id] end,
	SetUserWaypoint = function(point)
		assert(type(point) == "table" and point.uiMapID and point.position, "SetUserWaypoint needs a UiMapPoint")
		MOCK.waypoint = point
	end,
}
UiMapPoint = { CreateFromCoordinates = function(mapID, x, y)
	assert(type(mapID) == "number" and x >= 0 and x <= 1 and y >= 0 and y <= 1, "UiMapPoint coordinates run 0 to 1")
	return { uiMapID = mapID, position = { x = x, y = y } }
end }
C_SuperTrack = { SetSuperTrackedUserWaypoint = function(on) assert(type(on) == "boolean"); MOCK.superTracked = on end }
SOUNDKIT.UI_MAP_WAYPOINT_CLICK_TO_PLACE = 167092
-- Reputation: MOCK.rep[factionID] = absolute reputation (0 is the start of Neutral); factions you
-- haven't met return nothing
MOCK.rep = {}
local FACTION_NAMES = { [529] = "Argent Dawn", [270] = "Zandalar Tribe", [59] = "Thorium Brotherhood", [910] = "Brood of Nozdormu" }
C_Reputation = { GetFactionDataByID = function(id)
	assert(type(id) == "number", "GetFactionDataByID needs a faction id")
	local rep = MOCK.rep[id]
	if rep == nil then return nil end
	return { factionID = id, name = FACTION_NAMES[id] or ("Faction " .. id), reaction = 4, currentStanding = rep,
		currentReactionThreshold = 0, nextReactionThreshold = 3000, isHeader = false }
end }

function MOCK.Fire(event, ...)
	for f in pairs(MOCK.events[event] or {}) do f:GetScript("OnEvent")(f, event, ...) end
end
