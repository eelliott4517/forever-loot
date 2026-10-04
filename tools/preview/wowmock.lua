-- Strict mock of the WoW: Forever (1.60.1) API surface Forever Loot touches, for preview.py. It
-- started as Forever Messenger's preview mock (itself Rep Planner's and Trainer Locator's) and keeps
-- only what this addon uses. Widgets keep their anchors, sizes, layers, art and text, so layout.lua
-- can place them the way the game does and preview.py can draw them. Methods that aren't defined
-- here raise "attempt to call" errors, so an API typo can't pass; templates.lua adds the Blizzard
-- templates the addon builds its window from.
local DIR = ...

local function class(parent)
	local c = {}
	c.__index = c
	if parent then setmetatable(c, { __index = parent }) end
	return c
end

MOCK = {
	events = {}, timers = {}, chat = {}, secrets = {}, sounds = {}, requested = {}, popups = {},
	now = 1000, epoch = 1790000000,
	-- the character (preview.py's scenarios set these)
	side = "Alliance", classFile = "ROGUE", raceID = 1, level = 20,
	-- the quest log: done[id] once turned in; log[id] = true while in the log, "complete" when it's ready to turn in
	done = {}, log = {},
	instance = nil,        -- { name, kind, instanceID } while inside an instance
	mapNames = {},         -- [uiMapID] = name, what C_Map.GetMapInfo knows
	noPins = {},           -- [uiMapID] = true for maps that take no user waypoint
	mouseOver = nil,       -- the frame under the mouse
	frames = {},
}

-- The atlases WoW: Forever has that the addon and the templates use, at the size the game gives each
-- (atlases.txt, checked against the client's own table by preview.py). Names are matched exactly.
MOCK.ATLASES = {}
for line in io.lines(DIR .. "/preview/atlases.txt") do
	local name, w, h = line:match("^(%S+)%s+([%d.]+)%s+([%d.]+)$")
	if name and not line:find("^#") then MOCK.ATLASES[name] = { tonumber(w), tonumber(h) } end
end

-- Every event the client knows: registering any other one throws, as in the game
local KNOWN_EVENTS = {}
for line in io.lines(DIR .. "/preview/events.txt") do KNOWN_EVENTS[line] = true end

local function finite(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge end
local function isRegion(v) return type(v) == "table" and v._kind ~= nil end

---------------------------------------------------------------- secrets
function MOCK.Secret()
	local p = newproxy(true)
	local mt = getmetatable(p)
	local function boom() error("attempt to use a secret value") end
	mt.__index, mt.__concat, mt.__tostring, mt.__lt, mt.__le = boom, boom, boom, boom, boom
	mt.__add, mt.__sub, mt.__mul, mt.__div, mt.__unm = boom, boom, boom, boom, boom
	MOCK.secrets[p] = true
	return p
end
function issecretvalue(v) return MOCK.secrets[v] == true end

---------------------------------------------------------------- regions
local Region = class()
local POINTS = { TOPLEFT = 1, TOPRIGHT = 1, BOTTOMLEFT = 1, BOTTOMRIGHT = 1, TOP = 1, BOTTOM = 1, LEFT = 1, RIGHT = 1, CENTER = 1 }
-- SetPoint(point [, relativeTo [, relativePoint]] [, x, y]); relativeTo defaults to the parent
function Region:SetPoint(point, a, b, c, d)
	assert(POINTS[point], "bad anchor point " .. tostring(point))
	local rel, relPoint, x, y
	if isRegion(a) then
		rel, relPoint, x, y = a, b, c, d
		if type(relPoint) == "number" then rel, relPoint, x, y = a, point, b, c end
	elseif type(a) == "number" then
		rel, relPoint, x, y = self._parent, point, a, b
	else
		assert(a == nil or type(a) == "string", "SetPoint: bad relative frame " .. tostring(a))
		rel, relPoint, x, y = self._parent, a or point, b, c
	end
	relPoint = relPoint or point
	x, y = x or 0, y or 0
	assert(isRegion(rel), "SetPoint needs a region to anchor to")
	assert(rel ~= self, "a region can't anchor to itself")
	assert(POINTS[relPoint], "bad relative point " .. tostring(relPoint))
	assert(finite(x) and finite(y), "SetPoint offset isn't a finite number")
	self._points = self._points or {}
	for i = #self._points, 1, -1 do
		if self._points[i][1] == point then table.remove(self._points, i) end
	end
	table.insert(self._points, { point, rel, relPoint, x, y })
end
function Region:GetPoint(i)
	local p = self._points and self._points[i or 1]
	if p then return p[1], p[2], p[3], p[4], p[5] end
end
function Region:GetNumPoints() return #(self._points or {}) end
function Region:SetAllPoints(rel)
	assert(rel == nil or isRegion(rel), "SetAllPoints needs a region")
	rel = rel or self._parent
	self._points = { { "TOPLEFT", rel, "TOPLEFT", 0, 0 }, { "BOTTOMRIGHT", rel, "BOTTOMRIGHT", 0, 0 } }
end
function Region:ClearAllPoints() self._points = {} end
function Region:SetWidth(w)
	assert(finite(w) and w >= 0, "bad width " .. tostring(w))
	local changed = w ~= self._w
	self._w = w
	if changed and self._Fire then self:_Fire("OnSizeChanged", self._w, self._h or 0) end
end
function Region:SetHeight(h)
	assert(finite(h) and h >= 0, "bad height " .. tostring(h))
	local changed = h ~= self._h
	self._h = h
	if changed and self._Fire then self:_Fire("OnSizeChanged", self._w or 0, self._h) end
end
function Region:SetSize(w, h) self:SetWidth(w); self:SetHeight(h) end
-- As in the game, a size comes from the anchors when they set it (layout.lua works it out)
function Region:GetWidth() return MOCK.layout.Width(self) end
function Region:GetHeight() return MOCK.layout.Height(self) end
function Region:GetSize() return self:GetWidth(), self:GetHeight() end
function Region:Show()
	local was = self._shown
	self._shown = true
	if not was and self._Fire then self:_Fire("OnShow") end
end
function Region:Hide()
	local was = self._shown
	self._shown = false
	if was and self._Fire then self:_Fire("OnHide") end
end
function Region:SetShown(v) if v then self:Show() else self:Hide() end end
function Region:IsShown() return self._shown == true end
function Region:IsVisible()
	local r = self
	while r do
		if not r._shown then return false end
		r = r._parent
	end
	return true
end
function Region:GetParent() return self._parent end
function Region:SetAlpha(a) assert(finite(a) and a >= 0 and a <= 1, "bad alpha"); self._alpha = a end
function Region:GetAlpha() return self._alpha or 1 end
function Region:GetObjectType() return self._kind end

local LAYERS = { BACKGROUND = 1, BORDER = 1, ARTWORK = 1, OVERLAY = 1, HIGHLIGHT = 1 }

-- Textures. An atlas's crop stays on a texture through a later SetTexture until SetTexCoord resets
-- it, and tex coords set before SetAtlas apply inside the atlas (unless resetTexCoords), as in the
-- client; preview.py draws both, so a reused texture that keeps an old crop shows up.
local Texture = class(Region)
function Texture:SetTexture(file)
	assert(file == nil or type(file) == "string" or type(file) == "number", "SetTexture wants a file path or id")
	if self._atlas then self._atlasCrop = self._atlas end
	self._file, self._atlas, self._color = file, nil, nil
	return true
end
function Texture:GetTexture() return self._file or self._atlas end
function Texture:SetAtlas(atlas, useAtlasSize, filterMode, resetTexCoords)
	local size = MOCK.ATLASES[atlas]
	assert(size, "no atlas called " .. tostring(atlas) .. " (tools/preview/atlases.txt)")
	assert(useAtlasSize == nil or type(useAtlasSize) == "boolean", "SetAtlas: useAtlasSize is a boolean")
	self._atlas, self._file, self._color, self._atlasCrop = atlas, nil, nil, nil
	if resetTexCoords then self._coords = nil end
	if useAtlasSize then self:SetSize(size[1], size[2]) end
	return true
end
function Texture:GetAtlas() return self._atlas end
function Texture:SetTexCoord(...)
	local n = select("#", ...)
	assert(n == 4 or n == 8, "SetTexCoord takes 4 or 8 numbers")
	for i = 1, n do assert(finite((select(i, ...))), "SetTexCoord wants numbers") end
	self._coords = { ... }
	self._atlasCrop = nil
end
function Texture:SetBlendMode(mode)
	assert(({ DISABLE = 1, BLEND = 1, ALPHAKEY = 1, ADD = 1, MOD = 1 })[mode], "bad blend mode " .. tostring(mode))
	self._blend = mode
end
function Texture:SetDesaturated(v) assert(type(v) == "boolean", "SetDesaturated wants a boolean"); self._desaturated = v end
function Texture:IsDesaturated() return self._desaturated == true end
function Texture:SetHorizTile(v) self._htile = v and true or false end
function Texture:SetVertTile(v) self._vtile = v and true or false end
function Texture:SetColorTexture(r, g, b, a)
	for _, v in ipairs({ r, g, b, a or 1 }) do assert(finite(v) and v >= 0 and v <= 1, "SetColorTexture out of range: " .. tostring(v)) end
	self._color, self._file, self._atlas = { r, g, b, a or 1 }, nil, nil
end
function Texture:SetVertexColor(r, g, b, a)
	for _, v in ipairs({ r, g, b, a or 1 }) do assert(finite(v) and v >= 0 and v <= 1, "SetVertexColor out of range: " .. tostring(v)) end
	self._vcolor = { r, g, b, a or 1 }
end
function Texture:SetDrawLayer(layer, sublevel)
	assert(LAYERS[layer], "bad layer " .. tostring(layer))
	assert(sublevel == nil or (finite(sublevel) and sublevel >= -8 and sublevel <= 7), "sublevels run -8 to 7")
	self._layer, self._sublevel = layer, sublevel or 0
end
function Texture:GetDrawLayer() return self._layer, self._sublevel or 0 end
function Texture:AddMaskTexture(mask)
	assert(type(mask) == "table" and mask._kind == "MaskTexture", "AddMaskTexture wants a mask texture")
	self._masks = self._masks or {}
	table.insert(self._masks, mask)
end

-- Mask textures: their art's alpha cuts the textures they're added to (outside the mask is cut too)
local MaskTexture = class(Region)
function MaskTexture:SetTexture(file) assert(type(file) == "string" or type(file) == "number"); self._file, self._atlas = file, nil end
function MaskTexture:SetAtlas(atlas, useAtlasSize)
	local size = MOCK.ATLASES[atlas]
	assert(size, "no atlas called " .. tostring(atlas) .. " (tools/preview/atlases.txt)")
	self._atlas, self._file = atlas, nil
	if useAtlasSize then self:SetSize(size[1], size[2]) end
end

---------------------------------------------------------------- fonts
-- The game's font objects the addon and the templates use. Their size, color and shadow are in
-- preview.py (FONTS), from Blizzard_Fonts_Shared.
local FontObject = class()
MOCK.FONTS = {}
for _, name in ipairs({ "GameFontNormal", "GameFontNormalLeft", "GameFontNormalSmall", "GameFontNormalLarge", "GameFontNormalHuge",
	"GameFontHighlight", "GameFontHighlightSmall", "GameFontDisable", "GameFontDisableSmall", "GameFontGreenSmall",
	"ChatFontNormal", "GameTooltipHeaderText", "GameTooltipText", "GameTooltipTextSmall" }) do
	MOCK.FONTS[name] = true
	_G[name] = setmetatable({ _fontName = name }, FontObject)
end
local function FontName(font)
	if type(font) == "string" then
		assert(MOCK.FONTS[font], "unknown font object " .. font)
		return font
	end
	assert(type(font) == "table" and font._fontName, "not a font object: " .. tostring(font))
	return font._fontName
end
MOCK.FontName = FontName

local FontString = class(Region)
function FontString:SetFontObject(font) self._font = FontName(font); self._color = nil end
function FontString:GetFontObject() return self._font and _G[self._font] end
function FontString:SetText(t)
	assert(self._font, "FontString:SetText(): Font not set")
	assert(t == nil or type(t) == "string" or type(t) == "number", "SetText needs a string, got " .. type(t))
	self._text = t and tostring(t) or ""
end
function FontString:GetText() return self._text end
function FontString:SetTextColor(r, g, b, a)
	for _, v in ipairs({ r, g, b, a or 1 }) do assert(finite(v) and v >= 0 and v <= 1, "SetTextColor out of range: " .. tostring(v)) end
	self._color = { r, g, b }
end
function FontString:SetJustifyH(j) assert(j == "LEFT" or j == "RIGHT" or j == "CENTER", "bad JustifyH " .. tostring(j)); self._justify = j end
function FontString:SetJustifyV(j) assert(j == "TOP" or j == "MIDDLE" or j == "BOTTOM", "bad JustifyV " .. tostring(j)); self._justifyV = j end
function FontString:SetWordWrap(v) assert(type(v) == "boolean", "SetWordWrap wants a boolean"); self._wrap = v end
function FontString:SetSpacing(n) assert(finite(n)); self._spacing = n end
function FontString:SetDrawLayer(layer) assert(LAYERS[layer], "bad layer " .. tostring(layer)); self._layer = layer end
-- Plain text without color codes, for the checks
function MOCK.Plain(s)
	s = s or ""
	return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end
-- Measured with the game's font by preview.py (MOCK.Measure); a rough guess without it
function FontString:GetStringWidth()
	if MOCK.Measure then return (MOCK.Measure(self._font, self._text or "", 0, 0)) end
	return #MOCK.Plain(self._text) * 6
end
-- The height at the width the anchors give it, wrapped when the string wraps there
function FontString:GetStringHeight()
	local width = MOCK.layout.WrapWidth(self)
	if MOCK.Measure then return (select(2, MOCK.Measure(self._font, self._text or "", width, self._spacing or 0))) end
	return (self._text or "") == "" and 0 or 12
end

---------------------------------------------------------------- frames
local SCRIPTS = {
	OnEvent = 1, OnShow = 1, OnHide = 1, OnEnter = 1, OnLeave = 1, OnSizeChanged = 1, OnUpdate = 1, OnClick = 1,
	OnMouseUp = 1, OnMouseDown = 1, OnDragStart = 1, OnDragStop = 1, OnMouseWheel = 1, OnVerticalScroll = 1,
	OnScrollRangeChanged = 1, OnValueChanged = 1, OnHyperlinkClick = 1, OnLoad = 1,
	OnTextChanged = 1, OnEditFocusGained = 1, OnEditFocusLost = 1, OnEscapePressed = 1, OnEnterPressed = 1,
}
local Frame = class(Region)
function Frame:SetScript(name, fn)
	assert(SCRIPTS[name], "no script " .. tostring(name))
	assert(fn == nil or type(fn) == "function", "SetScript wants a function")
	if name == "OnClick" then assert(self._kind == "Button" or self._kind == "CheckButton" or self._kind == "DropdownButton", "only buttons have OnClick") end
	if name:find("^OnText") or name:find("Focus") or name:find("Pressed$") then assert(self._kind == "EditBox", name .. " is an edit box script") end
	if name == "OnVerticalScroll" or name == "OnScrollRangeChanged" then assert(self._kind == "ScrollFrame", name .. " is a scroll frame script") end
	self._scripts = self._scripts or {}
	self._scripts[name] = fn
	self._hooks = self._hooks or {}
	self._hooks[name] = nil   -- a new script drops the hooks on the old one, as in the game
end
function Frame:GetScript(name) return self._scripts and self._scripts[name] end
function Frame:HasScript(name) return SCRIPTS[name] ~= nil end
function Frame:HookScript(name, fn)
	assert(SCRIPTS[name], "no script " .. tostring(name))
	assert(type(fn) == "function", "HookScript needs a function")
	self._hooks = self._hooks or {}
	self._hooks[name] = self._hooks[name] or {}
	table.insert(self._hooks[name], fn)
end
function Frame:_Fire(name, ...)
	local handler = self._scripts and self._scripts[name]
	if handler then handler(self, ...) end
	for _, fn in ipairs(self._hooks and self._hooks[name] or {}) do fn(self, ...) end
end
function Frame:RegisterEvent(e)
	if not KNOWN_EVENTS[e] then error('Frame:RegisterEvent(): Attempt to register unknown event "' .. tostring(e) .. '"') end
	MOCK.events[e] = MOCK.events[e] or {}
	MOCK.events[e][self] = true
end
function Frame:UnregisterEvent(e) if MOCK.events[e] then MOCK.events[e][self] = nil end end
function Frame:IsEventRegistered(e) return MOCK.events[e] ~= nil and MOCK.events[e][self] == true end
function Frame:CreateTexture(name, layer, template, sublevel)
	assert(name == nil, "named textures aren't mocked")
	assert(template == nil, "texture templates aren't mocked")
	layer = layer or "ARTWORK"
	assert(LAYERS[layer], "bad layer " .. tostring(layer))
	assert(sublevel == nil or (finite(sublevel) and sublevel >= -8 and sublevel <= 7), "sublevels run -8 to 7")
	local t = setmetatable({ _parent = self, _shown = true, _kind = "Texture", _layer = layer, _sublevel = sublevel or 0 }, Texture)
	self._textures = self._textures or {}
	table.insert(self._textures, t)
	return t
end
function Frame:CreateMaskTexture()
	local m = setmetatable({ _parent = self, _shown = true, _kind = "MaskTexture" }, MaskTexture)
	return m
end
function Frame:CreateFontString(name, layer, template)
	assert(name == nil, "named font strings aren't mocked")
	layer = layer or "ARTWORK"
	assert(LAYERS[layer], "bad layer " .. tostring(layer))
	local fs = setmetatable({ _parent = self, _shown = true, _kind = "FontString", _text = "", _layer = layer,
		_font = template and FontName(template) or nil }, FontString)
	self._fontstrings = self._fontstrings or {}
	table.insert(self._fontstrings, fs)
	return fs
end
local STRATA = { BACKGROUND = 1, LOW = 1, MEDIUM = 1, HIGH = 1, DIALOG = 1, FULLSCREEN = 1, FULLSCREEN_DIALOG = 1, TOOLTIP = 1 }
function Frame:SetToplevel(on) assert(type(on) == "boolean"); self._toplevel = on end
function Frame:SetFrameStrata(s) assert(STRATA[s], "bad strata " .. tostring(s)); self._strata = s end
function Frame:GetFrameStrata() return MOCK.layout.Strata(self) end
function Frame:SetFrameLevel(l) assert(finite(l) and l >= 0, "bad frame level"); self._level = l end
function Frame:GetFrameLevel() return MOCK.layout.Level(self) end
function Frame:SetClampedToScreen(v) assert(type(v) == "boolean") end
function Frame:SetMovable(v) assert(type(v) == "boolean"); self._movable = v end
function Frame:EnableMouse(v) assert(type(v) == "boolean", "EnableMouse wants a boolean"); self._mouse = v end
function Frame:IsMouseEnabled() return self._mouse == true end
function Frame:EnableMouseWheel(v) assert(type(v) == "boolean") end
function Frame:RegisterForDrag(...) for _, b in ipairs({ ... }) do assert(type(b) == "string") end end
function Frame:StartMoving() assert(self._movable, "StartMoving on a frame that isn't movable") end
function Frame:StopMovingOrSizing() end
function Frame:IsMouseOver() return MOCK.mouseOver == self end
function Frame:GetName() return self._name end
function Frame:GetEffectiveScale() return 1 end
function Frame:GetCenter()
	local b = MOCK.layout.Box(self)
	return (b[1] + b[3]) / 2, MOCK.layout.SCREEN_H - (b[2] + b[4]) / 2
end
function Frame:IsProtected() return false, false end
-- Disabled steppers and the like grey out their whole hierarchy
function Frame:DesaturateHierarchy(amount)
	for _, t in ipairs(self._textures or {}) do t._desaturated = amount > 0 end
end

local Button = class(Frame)
function Button:RegisterForClicks(...) for _, b in ipairs({ ... }) do assert(type(b) == "string") end end
-- A button's state textures are its own regions, filling it unless anchored otherwise
local function StateTexture(self, key, layer, art, blend)
	assert(type(art) == "string" or type(art) == "number", "state textures want a file or an atlas")
	local t = self[key]
	if not t then
		t = self:CreateTexture(nil, layer)
		t:SetAllPoints()
		self[key] = t
	end
	if type(art) == "string" and MOCK.ATLASES[art] then t:SetAtlas(art) else t:SetTexture(art) end
	if blend then t:SetBlendMode(blend) end
	return t
end
MOCK.StateTexture = StateTexture
function Button:SetNormalTexture(art) StateTexture(self, "_normalTexture", "ARTWORK", art) end
function Button:SetPushedTexture(art) StateTexture(self, "_pushedTexture", "ARTWORK", art):Hide() end
function Button:SetDisabledTexture(art) StateTexture(self, "_disabledTexture", "ARTWORK", art):Hide() end
function Button:SetHighlightTexture(art, blend) StateTexture(self, "_highlightTexture", "HIGHLIGHT", art, blend or "ADD") end
function Button:GetNormalTexture() return self._normalTexture end
function Button:GetHighlightTexture() return self._highlightTexture end
function Button:Click(button) self:_Fire("OnClick", button or "LeftButton", false) end
-- The button's text: its template's ButtonText, else one made on demand in its normal font, centered
function Button:SetText(text)
	assert(text == nil or type(text) == "string" or type(text) == "number", "Button:SetText wants a string")
	if not self._fontString then
		self._fontString = self:CreateFontString(nil, "OVERLAY", self._normalFont or "GameFontNormal")
		self._fontString:SetPoint("CENTER")
	end
	self._fontString:SetText(text)
end
function Button:GetText() return self._fontString and self._fontString:GetText() end
function Button:GetFontString() return self._fontString end
function Button:GetTextWidth() return self._fontString and self._fontString:GetStringWidth() or 0 end
function Button:SetNormalFontObject(font)
	self._normalFont = FontName(font)
	if self._fontString and self._enabled ~= false then self._fontString._font, self._fontString._color = self._normalFont, nil end
end
function Button:SetHighlightFontObject(font) self._highlightFont = FontName(font) end
function Button:SetDisabledFontObject(font) self._disabledFont = FontName(font) end
function Button:LockHighlight() self._highlightLocked = true end
function Button:UnlockHighlight() self._highlightLocked = false end
function Button:IsEnabled() return self._enabled ~= false end
function Button:SetEnabled(on)
	local was = self:IsEnabled()
	self._enabled = on and true or false
	if self._fontString then
		local font = on and self._normalFont or self._disabledFont
		if font then self._fontString._font, self._fontString._color = font, nil end
	end
	if self._disabledTexture then self._disabledTexture:SetShown(not on) end
	if self._normalTexture and self._disabledTexture then self._normalTexture:SetShown(on and true or false) end
	if was ~= self:IsEnabled() then self:_Fire(on and "OnEnable" or "OnDisable") end
end
function Button:Enable() self:SetEnabled(true) end
function Button:Disable() self:SetEnabled(false) end
SCRIPTS.OnEnable, SCRIPTS.OnDisable = 1, 1

local CheckButton = class(Button)
function CheckButton:SetChecked(v)
	assert(v == nil or type(v) == "boolean", "SetChecked wants a boolean")
	self._checked = v and true or false
	if self._checkedTexture then self._checkedTexture:SetShown(self._checked) end
end
function CheckButton:GetChecked() return self._checked == true end
function CheckButton:SetCheckedTexture(art) self._checkedTexture = StateTexture(self, "_checkedTexture", "OVERLAY", art); self._checkedTexture:SetShown(self._checked == true) end
-- a click flips it before OnClick runs, as in the game
function CheckButton:Click(button)
	self:SetChecked(not self._checked)
	self:_Fire("OnClick", button or "LeftButton", false)
end

local ScrollFrame = class(Frame)
function ScrollFrame:SetScrollChild(f)
	assert(isRegion(f) and f._parent == self, "the scroll child is a child of its scroll frame")
	self._child = f
end
function ScrollFrame:GetScrollChild() return self._child end
function ScrollFrame:UpdateScrollChildRect() end
function ScrollFrame:GetVerticalScrollRange()
	return math.max(0, (self._child and self._child:GetHeight() or 0) - self:GetHeight())
end
function ScrollFrame:GetVerticalScroll() return self._scroll or 0 end
function ScrollFrame:SetVerticalScroll(v)
	assert(finite(v) and v >= 0, "bad scroll offset")
	self._scroll = v
	self:_Fire("OnVerticalScroll", v)
end

-- EditBox: its text, focus, and the scripts a typed character runs
local EditBox = class(Frame)
function EditBox:SetText(t)
	assert(type(t) == "string" or type(t) == "number", "EditBox:SetText wants a string")
	self._text = tostring(t)
	self:_Fire("OnTextChanged", false)
end
function EditBox:GetText() return self._text or "" end
function EditBox:SetAutoFocus(v) assert(type(v) == "boolean") end
function EditBox:HasFocus() return self._focus == true end
function EditBox:SetFocus() self._focus = true; self:_Fire("OnEditFocusGained") end
function EditBox:ClearFocus()
	if self._focus then
		self._focus = false
		self:_Fire("OnEditFocusLost")
	end
end
function EditBox:SetTextInsets(l, r, t, b) self._insets = { l or 0, r or 0, t or 0, b or 0 } end
function EditBox:SetMaxLetters(n) assert(finite(n)) end
function EditBox:SetFontObject(font) self._textFont = FontName(font) end
function EditBox:SetTextColor(r, g, b) self._textColor = { r, g, b } end
function EditBox:HighlightText() end
-- what typing does: the text changes as the player's input
function EditBox:MockType(t) self._text = t; self:_Fire("OnTextChanged", true) end

local KINDS = { Frame = Frame, Button = Button, CheckButton = CheckButton, ScrollFrame = ScrollFrame, EditBox = EditBox,
	DropdownButton = class(Button), EventFrame = class(Frame), EventButton = class(Button) }
MOCK.KINDS, MOCK.class, MOCK.Texture, MOCK.FontString = KINDS, class, Texture, FontString
-- Blizzard templates, from templates.lua: [name] = { kinds = { Frame = true, ... }, build = function(frame, name) }
MOCK.TEMPLATES = {}
function CreateFrame(kind, name, parent, template)
	local mt = KINDS[kind]
	assert(mt, "CreateFrame kind " .. tostring(kind))
	assert(parent == nil or isRegion(parent), "CreateFrame parent isn't a frame")
	assert(name == nil or type(name) == "string", "CreateFrame name isn't a string")
	if type(name) == "string" and name:find("^%$parent") then name = (parent and parent._name or "") .. name:sub(8) end
	local f = setmetatable({ _parent = parent, _shown = true, _name = name, _kind = kind }, mt)
	if name then _G[name] = f end
	table.insert(MOCK.frames, f)
	if template then
		f._templates = {}
		for t in template:gmatch("[^,%s]+") do
			local spec = MOCK.TEMPLATES[t]
			assert(spec, "template " .. t .. " isn't mocked (or doesn't exist)")
			assert(not spec.kinds or spec.kinds[kind], t .. " isn't a template for a " .. kind)
			f._templates[t] = true
			if spec.build then spec.build(f, name) end
		end
	end
	return f
end

UIParent = CreateFrame("Frame", "UIParent")
UIParent:SetSize(1920, 1080)
Minimap = CreateFrame("Frame", "Minimap", UIParent)
Minimap:SetSize(198, 198)
Minimap:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -20, -30)

---------------------------------------------------------------- tooltip
-- GameTooltip keeps its lines for preview.py, which lays them out the way the game's tooltip does
local Tooltip = class(Region)
GameTooltip = setmetatable({ _kind = "GameTooltip", _name = "GameTooltip", _shown = false, _rows = {} }, Tooltip)
local ANCHORS = { ANCHOR_RIGHT = 1, ANCHOR_LEFT = 1, ANCHOR_TOP = 1, ANCHOR_BOTTOM = 1, ANCHOR_TOPLEFT = 1, ANCHOR_TOPRIGHT = 1,
	ANCHOR_BOTTOMLEFT = 1, ANCHOR_BOTTOMRIGHT = 1, ANCHOR_CURSOR = 1, ANCHOR_NONE = 1, ANCHOR_PRESERVE = 1 }
function Tooltip:SetOwner(owner, anchor, x, y)
	assert(isRegion(owner), "SetOwner needs a frame")
	anchor = anchor or "ANCHOR_LEFT"
	assert(ANCHORS[anchor], "bad anchor " .. tostring(anchor))
	self._owner, self._anchor, self._offset, self._rows, self._shown = owner, anchor, { x or 0, y or 0 }, {}, false
end
function Tooltip:GetOwner() return self._owner end
function Tooltip:ClearLines() self._rows = {} end
local function colorOK(...) for _, v in ipairs({ ... }) do assert(finite(v) and v >= 0 and v <= 1, "tooltip colour out of range: " .. tostring(v)) end end
function Tooltip:SetText(text, r, g, b, a, wrap)
	assert(type(text) == "string", "SetText needs a string")
	colorOK(r or 1, g or 1, b or 1, a or 1)
	assert(wrap == nil or type(wrap) == "boolean")
	self._rows = { { left = text, lc = { r or 1, g or 1, b or 1 }, wrap = wrap } }
end
function Tooltip:AddLine(text, r, g, b, wrap)
	assert(type(text) == "string", "AddLine needs a string, got " .. type(text))
	colorOK(r or 1, g or 1, b or 1)
	assert(wrap == nil or type(wrap) == "boolean", "AddLine's wrap is a boolean")
	table.insert(self._rows, { left = text, lc = { r or 1, g or 1, b or 1 }, wrap = wrap })
end
function Tooltip:AddDoubleLine(l, r, lr, lg, lb, rr, rg, rb)
	assert(type(l) == "string" and type(r) == "string", "AddDoubleLine needs two strings")
	colorOK(lr or 1, lg or 1, lb or 1, rr or 1, rg or 1, rb or 1)
	table.insert(self._rows, { left = l, right = r, lc = { lr or 1, lg or 1, lb or 1 }, rc = { rr or 1, rg or 1, rb or 1 } })
end
function Tooltip:NumLines() return #self._rows end
function MOCK.TooltipText()
	local out = {}
	for _, r in ipairs(GameTooltip._rows) do out[#out + 1] = MOCK.Plain(r.left .. (r.right and (" | " .. r.right) or "")) end
	return table.concat(out, "\n")
end
Enum = { TooltipDataType = { Item = 0, Spell = 1, Unit = 2 } }
MOCK.postCalls = {}
TooltipDataProcessor = { AddTooltipPostCall = function(kind, fn)
	assert(type(fn) == "function")
	MOCK.postCalls[kind] = MOCK.postCalls[kind] or {}
	table.insert(MOCK.postCalls[kind], fn)
end }

---------------------------------------------------------------- Blizzard globals
UISpecialFrames = {}
tinsert, tremove = table.insert, table.remove
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function strsplit(sep, s)
	local out = {}
	for part in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do out[#out + 1] = part end
	return unpack(out)
end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function hooksecurefunc(obj, name, fn)
	if type(obj) == "string" then obj, name, fn = _G, obj, name end
	local orig = obj[name]
	assert(type(orig) == "function", "hooksecurefunc: " .. tostring(name) .. " isn't a function")
	obj[name] = function(...)
		local r = { orig(...) }
		fn(...)
		return unpack(r)
	end
end
function GetTime() return MOCK.now end
function time() return MOCK.epoch + MOCK.now end
function InCombatLockdown() return false end
function GetCursorPosition() return 0, 0 end
function IsModifierKeyDown() return MOCK.shift == true or MOCK.ctrl == true end
function IsShiftKeyDown() return MOCK.shift == true end
function IsControlKeyDown() return MOCK.ctrl == true end
CLOSE = "Close"
SEARCH = "Search"
SOUNDKIT = { IG_CHARACTER_INFO_OPEN = 839, IG_CHARACTER_INFO_CLOSE = 840, IG_CHARACTER_INFO_TAB = 841,
	IG_MAINMENU_OPTION_CHECKBOX_ON = 856, IG_MAINMENU_OPTION_CHECKBOX_OFF = 857, UI_MAP_WAYPOINT_CLICK_TO_PLACE = 167092,
	RAID_WARNING = 8959, SCROLLBAR_STEP = 1115, U_CHAT_SCROLL_BUTTON = 1115 }
function PlaySound(id)
	local known = false
	for _, v in pairs(SOUNDKIT) do if v == id then known = true end end
	assert(known, "PlaySound wants a SOUNDKIT id")
	table.insert(MOCK.sounds, id)
end
C_Timer = { After = function(seconds, fn)
	assert(finite(seconds) and type(fn) == "function", "C_Timer.After(seconds, fn)")
	table.insert(MOCK.timers, fn)
end }
function MOCK.RunTimers() local t = MOCK.timers; MOCK.timers = {}; for _, fn in ipairs(t) do fn() end end

-- Blizzard_FrameXMLBase/Constants.lua
QuestDifficultyColors = {
	impossible = { r = 1.00, g = 0.10, b = 0.10 }, verydifficult = { r = 1.00, g = 0.50, b = 0.25 },
	difficult = { r = 1.00, g = 0.82, b = 0.00 }, standard = { r = 0.25, g = 0.75, b = 0.25 },
	trivial = { r = 0.50, g = 0.50, b = 0.50 }, header = { r = 0.70, g = 0.70, b = 0.70 },
	disabled = { r = 0.498, g = 0.498, b = 0.498 },
}
-- (Forever has no GetQuestGreenRange: the addon falls back to its own rule)

-- The game's popups: StaticPopup_Show formats the text and runs OnShow
StaticPopupDialogs = {}
function StaticPopup_Show(which, a1, a2, data)
	local info = assert(StaticPopupDialogs[which], "no StaticPopupDialogs entry " .. tostring(which))
	table.insert(MOCK.popups, { which = which, text = info.text:format(a1 or "", a2 or ""), data = data })
end

SlashCmdList = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) assert(type(msg) == "string"); table.insert(MOCK.chat, MOCK.Plain(msg)) end }
function MOCK.Fire(event, ...)
	for f in pairs(MOCK.events[event] or {}) do f:GetScript("OnEvent")(f, event, ...) end
end
-- The mouse moves onto a frame: its highlight shows and its OnEnter runs
function MOCK.Hover(frame)
	MOCK.mouseOver = frame
	frame:_Fire("OnEnter", false)
end

---------------------------------------------------------------- the character, quests, maps, items
local CLASSES = { WARRIOR = { "Warrior", 1 }, PALADIN = { "Paladin", 2 }, HUNTER = { "Hunter", 3 }, ROGUE = { "Rogue", 4 },
	PRIEST = { "Priest", 5 }, SHAMAN = { "Shaman", 7 }, MAGE = { "Mage", 8 }, WARLOCK = { "Warlock", 9 }, DRUID = { "Druid", 11 } }
local RACES = { [1] = { "Human", "Human" }, [2] = { "Orc", "Orc" }, [3] = { "Dwarf", "Dwarf" }, [4] = { "Night Elf", "NightElf" },
	[5] = { "Undead", "Scourge" }, [6] = { "Tauren", "Tauren" }, [7] = { "Gnome", "Gnome" }, [8] = { "Troll", "Troll" } }
function UnitFactionGroup(u) assert(u == "player", "UnitFactionGroup(" .. tostring(u) .. ")"); return MOCK.side, MOCK.side end
function UnitClass(u)
	assert(u == "player", "UnitClass(" .. tostring(u) .. ")")
	local c = CLASSES[MOCK.classFile]
	return c[1], MOCK.classFile, c[2]
end
function UnitRace(u)
	assert(u == "player", "UnitRace(" .. tostring(u) .. ")")
	local r = RACES[MOCK.raceID]
	return r[1], r[2], MOCK.raceID
end
function UnitLevel(u) assert(u == "player", "UnitLevel(" .. tostring(u) .. ")"); return MOCK.level end
function UnitGUID() return nil end
function GetInstanceInfo()
	local i = MOCK.instance
	if i then return i.name, i.kind, 1, "Normal", 5, 0, false, i.instanceID end
	return "Elwynn Forest", "none", 0, "", 0, 0, false, 0
end
function IsInInstance()
	if MOCK.instance then return true, MOCK.instance.kind end
	return false, "none"
end

-- Forever has the quest log only as C_QuestLog (no IsQuestFlaggedCompleted global)
C_QuestLog = {
	IsQuestFlaggedCompleted = function(id) assert(type(id) == "number", "IsQuestFlaggedCompleted needs a quest id"); return MOCK.done[id] == true end,
	IsOnQuest = function(id) assert(type(id) == "number", "IsOnQuest needs a quest id"); return MOCK.log[id] ~= nil end,
	IsComplete = function(id) assert(type(id) == "number", "IsComplete needs a quest id"); return MOCK.log[id] == "complete" end,
}

-- Zone names come from the client (UiMap); a map the client doesn't have has no info
C_Map = {
	GetMapInfo = function(id)
		assert(type(id) == "number", "GetMapInfo needs a map id")
		local name = MOCK.mapNames[id]
		if name then return { mapID = id, name = name, mapType = 3, parentMapID = 0 } end
	end,
	CanSetUserWaypointOnMap = function(id) assert(type(id) == "number"); return MOCK.mapNames[id] ~= nil and not MOCK.noPins[id] end,
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

-- The item cache starts empty, as after a fresh login: GetItemInfo has nothing until the server
-- answers, so the addon shows its bundled names, icons and tooltips (what it does in game too)
MOCK.bags, MOCK.equipped = {}, {}
C_Item = {
	GetItemInfo = function(id) assert(id ~= nil, "GetItemInfo needs an item"); return nil end,
	GetItemInfoInstant = function(id) assert(id ~= nil, "GetItemInfoInstant needs an item"); return nil end,
	GetItemIconByID = function(id) assert(type(id) == "number", "GetItemIconByID needs an item id"); return nil end,
	RequestLoadItemDataByID = function(id) MOCK.requested[id] = true end,
	GetItemCount = function(id) assert(type(id) == "number"); return MOCK.bags[id] or 0 end,
	IsEquippedItem = function(id) return MOCK.equipped[id] == true end,
}
C_Spell = { GetSpellLink = function(id) return "|cff71d5ff|Hspell:" .. id .. "|h[Spell " .. id .. "]|h|r" end }
C_SkillInfo = {
	GetNumSkillLines = function() return 0 end,
	GetSkillLineInfo = function() return nil end,
	GetSkillLineInfoByID = function() return nil end,
}
ChatFrameUtil = { InsertLink = function() return false end }

MOCK.layout = assert(loadfile(DIR .. "/preview/layout.lua"))()
assert(loadfile(DIR .. "/preview/templates.lua"))(DIR)
