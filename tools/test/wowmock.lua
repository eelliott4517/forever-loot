-- Strict mock of the parts of the WoW client API ForeverLoot uses.
-- Calling a widget method that isn't implemented here raises an error, so the
-- method list below doubles as an allowlist of real Classic-client API calls.

unpack = unpack or table.unpack
math.atan2 = math.atan2 or function(y, x) return math.atan(y, x) end

MOCK = { events = {}, frames = {}, printed = {}, named = {}, sounds = 0, timers = {} }

local function strict(kind, methods)
	return {
		__index = function(obj, key)
			local m = methods[key]
			if m ~= nil then return m end
			-- API methods are CamelCase; lowercase keys are the addon's (or the mock's) own fields
			if type(key) == "string" and key:match("^%u") then
				error("mock: " .. kind .. " has no method '" .. key .. "'", 2)
			end
			return nil
		end,
	}
end

----------------------------------------------------------------------
-- Regions (shared by frames, textures, font strings)
----------------------------------------------------------------------
local Region = {}
function Region:SetPoint(point, rel, relPoint, x, y)
	if type(point) ~= "string" then error("SetPoint: bad point", 2) end
	self.points = self.points or {}
	table.insert(self.points, { point, rel, relPoint, x, y })
end
function Region:ClearAllPoints() self.points = {} end
function Region:SetAllPoints() self.allPoints = true end
function Region:SetSize(w, h) self.w, self.h = w, h end
function Region:SetWidth(w) self.w = w end
function Region:SetHeight(h) self.h = h end
function Region:GetWidth() return self.w or 100 end
function Region:GetHeight() return self.h or 100 end
function Region:Show() self.shown = true end
function Region:Hide() self.shown = false end
function Region:SetShown(v) self.shown = not not v end
function Region:IsShown() return self.shown end
function Region:SetAlpha(a) assert(type(a) == "number"); self.alpha = a end
function Region:IsMouseOver() return false end
function Region:GetPoint(i)
	local p = (self.points or {})[i or 1]
	if p then return p[1], p[2], p[3], p[4] or 0, p[5] or 0 end
end

local function inherit(base, extra)
	local t = {}
	for k, v in pairs(base) do t[k] = v end
	for k, v in pairs(extra) do t[k] = v end
	return t
end

local Texture = inherit(Region, {
	SetColorTexture = function(self, r, g, b, a)
		assert(type(r) == "number" and type(g) == "number" and type(b) == "number", "SetColorTexture needs numbers")
		self.color = { r, g, b, a }
	end,
	SetTexture = function(self, t) self.texture = t end,
	SetTexCoord = function(self, ...) self.texCoord = { ... } end,
	SetVertexColor = function(self, r, g, b, a) assert(type(r) == "number"); self.vertex = { r, g, b, a } end,
})
local TextureMT = strict("Texture", Texture)

local FontString = inherit(Region, {
	SetFontObject = function(self, f) assert(f and f.__isFont, "SetFontObject needs a font object"); self.font = f end,
	SetJustifyH = function(self, j) assert(j == "LEFT" or j == "RIGHT" or j == "CENTER", "bad justify " .. tostring(j)) end,
	SetWordWrap = function() end,
	SetText = function(self, t)
		if t ~= nil and type(t) ~= "string" and type(t) ~= "number" then error("SetText needs a string", 2) end
		self.text = t and tostring(t) or ""
	end,
	GetText = function(self) return self.text end,
	SetTextColor = function(self, r, g, b) assert(type(r) == "number", "SetTextColor needs numbers"); self.tc = { r, g, b } end,
	GetStringWidth = function(self) return #(self.text or "") * 6 end,
})
local FontStringMT = strict("FontString", FontString)

----------------------------------------------------------------------
-- Frames
----------------------------------------------------------------------
local Frame = inherit(Region, {
	CreateTexture = function(self, name, layer)
		local t = setmetatable({ parent = self, layer = layer, shown = true }, TextureMT)
		return t
	end,
	CreateFontString = function(self, name, layer)
		return setmetatable({ parent = self, layer = layer, shown = true }, FontStringMT)
	end,
	SetScript = function(self, name, fn)
		assert(type(name) == "string" and name:sub(1, 2) == "On", "bad script name " .. tostring(name))
		self.scripts[name] = fn
	end,
	GetScript = function(self, name) return self.scripts[name] end,
	HookScript = function(self, name, fn) self.scripts[name] = fn end,
	RegisterEvent = function(self, e) MOCK.events[e] = MOCK.events[e] or {}; MOCK.events[e][self] = true end,
	UnregisterEvent = function(self, e) if MOCK.events[e] then MOCK.events[e][self] = nil end end,
	SetFrameStrata = function() end,
	SetFrameLevel = function(self, n) self.level = n end,
	GetFrameLevel = function(self) return self.level or 1 end,
	SetToplevel = function() end,
	SetClampedToScreen = function() end,
	SetMovable = function() end,
	EnableMouse = function() end,
	EnableMouseWheel = function() end,
	RegisterForDrag = function() end,
	StartMoving = function() end,
	StopMovingOrSizing = function() end,
	GetCenter = function() return 500, 400 end,
	GetEffectiveScale = function() return 1 end,
	Show = function(self)
		local was = self.shown
		self.shown = true
		if not was and self.scripts.OnShow then self.scripts.OnShow(self) end
	end,
	Hide = function(self)
		local was = self.shown
		self.shown = false
		if was and self.scripts.OnHide then self.scripts.OnHide(self) end
	end,
	IsShown = function(self) return self.shown end,
	GetName = function(self) return self.name end,
})

local Button = inherit(Frame, {
	RegisterForClicks = function() end,
	SetHighlightTexture = function() end,
	LockHighlight = function() end,
	UnlockHighlight = function() end,
	Click = function(self, button) if self.scripts.OnClick then self.scripts.OnClick(self, button or "LeftButton") end end,
})

local ScrollFrame = inherit(Frame, {
	SetScrollChild = function(self, c) self.child = c end,
	SetVerticalScroll = function(self, v) assert(type(v) == "number"); self.scroll = v end,
	GetVerticalScroll = function(self) return self.scroll or 0 end,
})

local Slider = inherit(Frame, {
	SetOrientation = function() end,
	SetThumbTexture = function(self, t) self.thumb = t end,
	SetMinMaxValues = function(self, lo, hi) assert(lo <= hi, "min > max"); self.lo, self.hi = lo, hi end,
	GetMinMaxValues = function(self) return self.lo or 0, self.hi or 0 end,
	SetValueStep = function() end,
	SetValue = function(self, v)
		v = math.max(self.lo or 0, math.min(self.hi or 0, v))
		local changed = v ~= self.value
		self.value = v
		if changed and self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, v) end
	end,
	GetValue = function(self) return self.value or 0 end,
})

local EditBox = inherit(Frame, {
	SetAutoFocus = function() end,
	SetMaxLetters = function(self, n) assert(type(n) == "number") end,
	SetFontObject = function(self, f) assert(f and f.__isFont) end,
	SetTextInsets = function() end,
	SetText = function(self, t) self.text = t end,
	GetText = function(self) return self.text end,
	HighlightText = function() end,
	SetFocus = function(self) self.focus = true end,
	ClearFocus = function(self) self.focus = false end,
})

local kinds = {
	Frame = strict("Frame", Frame), Button = strict("Button", Button),
	ScrollFrame = strict("ScrollFrame", ScrollFrame), Slider = strict("Slider", Slider),
	EditBox = strict("EditBox", EditBox),
}

function CreateFrame(kind, name, parent, template)
	local mt = kinds[kind]
	if not mt then error("mock: unsupported frame type " .. tostring(kind), 2) end
	if template then error("mock: templates not expected: " .. tostring(template), 2) end
	local f = setmetatable({ kind = kind, name = name, parent = parent, scripts = {}, shown = true, children = {} }, mt)
	if parent and parent.children then table.insert(parent.children, f) end
	if name then _G[name] = f; MOCK.named[name] = f end
	table.insert(MOCK.frames, f)
	return f
end

function MOCK.Fire(event, ...)
	local list = {}
	for f in pairs(MOCK.events[event] or {}) do list[#list + 1] = f end
	for _, f in ipairs(list) do
		if f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
	end
end

function MOCK.RunTimers()
	local t = MOCK.timers
	MOCK.timers = {}
	for _, fn in ipairs(t) do fn() end
end

----------------------------------------------------------------------
-- Fonts
----------------------------------------------------------------------
local FontObject = {
	CopyFontObject = function(self, other) assert(other and other.__isFont, "CopyFontObject needs a font"); self.file = other.file; self.size = other.size end,
	SetFont = function(self, file, size, flags) assert(type(file) == "string" and type(size) == "number"); self.file, self.size = file, size end,
	GetFont = function(self) return self.file, self.size, "" end,
	SetTextColor = function(self, r, g, b) assert(type(r) == "number") end,
}
local FontMT = strict("Font", FontObject)
local function newFont(size) return setmetatable({ __isFont = true, file = "Fonts\\FRIZQT__.TTF", size = size }, FontMT) end
function CreateFont(name) local f = newFont(12); _G[name] = f; return f end
GameFontNormal, GameFontNormalSmall, GameFontNormalLarge, GameFontNormalHuge = newFont(12), newFont(10), newFont(16), newFont(20)
GameFontHighlight, GameFontHighlightSmall, ChatFontNormal = newFont(12), newFont(10), newFont(14)

----------------------------------------------------------------------
-- Globals
----------------------------------------------------------------------
UIParent = CreateFrame("Frame", "UIParent")
Minimap = CreateFrame("Frame", "Minimap", UIParent)
Minimap:SetSize(140, 140)
UISpecialFrames = {}
SlashCmdList = {}
SOUNDKIT = { IG_CHARACTER_INFO_OPEN = 839, IG_CHARACTER_INFO_CLOSE = 840 }
function PlaySound(id) assert(type(id) == "number", "PlaySound needs a sound kit id"); MOCK.sounds = MOCK.sounds + 1 end

DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) table.insert(MOCK.printed, msg) end }

-- Tooltip data post-calls (TooltipDataProcessor), run when a tooltip is set to an item
MOCK.postCalls = {}
Enum = { TooltipDataType = { Item = 0 } }
TooltipDataProcessor = { AddTooltipPostCall = function(kind, fn)
	assert(kind == Enum.TooltipDataType.Item and type(fn) == "function")
	table.insert(MOCK.postCalls, fn)
end }

local function newTooltip(name)
	local tip = setmetatable({ lines = {}, hooks = {}, name = name }, strict(name, {
		SetOwner = function(self, owner, anchor)
			assert(owner, "SetOwner needs owner")
			self.lines = {}; self.item = nil; self.owner = owner
			for _, fn in ipairs(self.hooks.OnTooltipCleared or {}) do fn(self) end
		end,
		GetOwner = function(self) return self.owner end,
		IsShown = function(self) return self.visible end,
		SetItemByID = function(self, id)
			assert(type(id) == "number", "SetItemByID needs a number")
			self.item = id
			for _, fn in ipairs(MOCK.postCalls) do fn(self, { id = id, type = 0 }) end
		end,
		SetHyperlink = function(self, link)
			self.link = link
			local id = tonumber(tostring(link):match("item:(%d+)"))
			if id then self.item = id; for _, fn in ipairs(MOCK.postCalls) do fn(self, { id = id, type = 0 }) end end
		end,
		GetItem = function(self) if self.item then return "item", "|Hitem:" .. self.item .. "|h" end end,
		HookScript = function(self, script, fn)
			assert(script == "OnTooltipCleared" or script == "OnTooltipSetItem", "unexpected tooltip script " .. tostring(script))
			self.hooks[script] = self.hooks[script] or {}
			table.insert(self.hooks[script], fn)
		end,
		AddLine = function(self, text) assert(type(text) == "string"); table.insert(self.lines, text) end,
		AddDoubleLine = function(self, left, right) assert(type(left) == "string" and type(right) == "string"); table.insert(self.lines, left .. " | " .. right) end,
		Show = function(self) self.visible = true end,
		Hide = function(self) self.visible = false end,
	}))
	return tip
end
GameTooltip = newTooltip("GameTooltip")
ItemRefTooltip = newTooltip("ItemRefTooltip")

function strsplit(sep, s)
	local out, start = {}, 1
	while true do
		local i = s:find(sep, start, true)
		if not i then out[#out + 1] = s:sub(start); break end
		out[#out + 1] = s:sub(start, i - 1)
		start = i + #sep
	end
	return unpack(out)
end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
tinsert = table.insert

MOCK.level = 16
MOCK.class = { "Warrior", "WARRIOR", 1 }
MOCK.faction = "Alliance"
function UnitClass(unit) assert(unit == "player"); return unpack(MOCK.class) end
function UnitFactionGroup(unit) assert(unit == "player"); return MOCK.faction end
MOCK.instance = { "World", "none", 0, "", 5, 0, false, 0 }
MOCK.time = 1000
MOCK.cached = {}      -- itemID -> true when the "server" has sent item data
MOCK.modifier = false
MOCK.clicked = {}

function UnitGUID(unit) return MOCK.targetGUID end
function UnitLevel(unit) assert(unit == "player"); return MOCK.level end
function GetInstanceInfo() return unpack(MOCK.instance) end
function GetTime() return MOCK.time end
function GetCursorPosition() return 600, 450 end
function IsModifierKeyDown() return MOCK.modifier end
function HandleModifiedItemClick(link) assert(type(link) == "string"); table.insert(MOCK.clicked, link); return true end

local function itemRecord(id)
	local e = MOCK.itemsDB[id]
	if not e then return end
	return e
end

function GetItemInfo(id)
	if type(id) == "string" then id = tonumber(id:match("item:(%d+)")) end
	MOCK.infoCalls[id] = (MOCK.infoCalls[id] or 0) + 1
	local e = itemRecord(id)
	if not e or not MOCK.cached[id] or MOCK.notInClient[id] or MOCK.serverMissing[id] then return nil end
	local link = "|cff" .. ({ [0] = "9d9d9d", [1] = "ffffff", [2] = "1eff00", [3] = "0070dd", [4] = "a335ee", [5] = "ff8000", [6] = "e6cc80" })[e[2]] .. "|Hitem:" .. id .. "::::::::::::|h[" .. e[1] .. "]|h|r"
	return e[1], link, e[2], 20, 15, "Armor", "Cloth", 1, "INVTYPE_CHEST", 132000 + id, 100
end
MOCK.notInClient = {}    -- the client has never heard of the item id
MOCK.serverMissing = {}  -- the client knows the id, but the server never sends its data
MOCK.infoCalls = {}
MOCK.failed = {}
function GetItemInfoInstant(id)
	local e = itemRecord(id)
	if not e or MOCK.notInClient[id] then return nil end
	return id, "Armor", "Cloth", "INVTYPE_CHEST", 132000 + id, 4, 1
end
function GetItemIcon(id) local e = itemRecord(id); return (e and not MOCK.notInClient[id]) and (132000 + id) or nil end
INVTYPE_CHEST = "Chest"

C_Item = { RequestLoadItemDataByID = function(id)
	assert(type(id) == "number")
	MOCK.requested = (MOCK.requested or 0) + 1
	if MOCK.serverMissing[id] or MOCK.notInClient[id] then MOCK.failed[id] = true end
end }
-- The server replies "no such item" to requests it can't serve
function MOCK.FlushItemRequests()
	local ids = {}
	for id in pairs(MOCK.failed) do ids[#ids + 1] = id end
	MOCK.failed = {}
	for _, id in ipairs(ids) do MOCK.Fire("GET_ITEM_INFO_RECEIVED", id, false) end
end
C_Timer = { After = function(sec, fn) assert(type(fn) == "function"); table.insert(MOCK.timers, fn) end }

MOCK.loot = {}
function GetNumLootItems() return #MOCK.loot end
function GetLootSlotLink(slot) return MOCK.loot[slot] and MOCK.loot[slot].link end
function GetLootSourceInfo(slot) local s = MOCK.loot[slot]; return s.guid, 1 end

-- Globals the Wishlist and Professions tabs use
time = time or os.time
function GetItemCount(item, includeBank) return MOCK.owned and MOCK.owned[item] or 0 end
function IsEquippedItem(item) return false end
function IsShiftKeyDown() return MOCK.shift == true end
function GetNumSkillLines() return 0 end
function GetSkillLineInfo(i) return nil end
function GetSpellLink(id) return nil end
function ChatEdit_InsertLink(link) return false end
function GetLootRollItemLink(rollID) return nil end
