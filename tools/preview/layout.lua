-- Resolves the mock's anchors into screen rectangles the way the game does, and lists everything
-- preview.py draws in the game's order: strata, then frame level, then draw layer and sublevel, then
-- creation order. Rectangles are { left, top, right, bottom } in UI units with y going down.
local L = {}

local SCREEN_W, SCREEN_H = 1920, 1080
L.SCREEN_H = SCREEN_H
local STRATA = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5, FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }
local LAYERS = { BACKGROUND = 1, BORDER = 2, ARTWORK = 3, OVERLAY = 4, HIGHLIGHT = 5 }
-- The draw layer and sublevel of each NineSlice layout's pieces (Mainline/NineSliceLayouts.lua)
local NINESLICE_LAYERS = { PortraitFrameTemplate = { "OVERLAY", 0 }, InsetFrameTemplate = { "BORDER", -5 } }

-- Horizontal and vertical extents are worked out apart, as a font string's height depends on the
-- width its anchors give it. Each top-level question starts with empty caches.
local hc, vc, depth = {}, {}, 0
local function Enter()
	if depth == 0 then hc, vc = {}, {} end
	depth = depth + 1
end
local function Leave() depth = depth - 1 end

local function HPart(point) return point:find("LEFT") and "L" or (point:find("RIGHT") and "R" or "C") end
local function VPart(point) return point:find("TOP") and "T" or (point:find("BOTTOM") and "B" or "C") end

-- A scroll child with no anchors sits at its scroll frame's top left, moved up by the scroll
local function ScrollFrameOf(r)
	local p = r._parent
	if p and p._kind == "ScrollFrame" and p._child == r and #(r._points or {}) == 0 then return p end
end

local function BothSides(r)
	local left, right = false, false
	for _, p in ipairs(r._points or {}) do
		local h = HPart(p[1])
		if h == "L" then left = true elseif h == "R" then right = true end
	end
	return left and right
end

local H, V
function H(r) -- left, right
	if r == UIParent then return 0, SCREEN_W end
	local c = hc[r]
	if c then return c[1], c[2] end
	hc[r] = { 0, 0 } -- guards cycles
	local left, right, center
	local sf = ScrollFrameOf(r)
	if sf then left = (H(sf)) end
	for _, p in ipairs(r._points or {}) do
		local point, rel, relPoint, x = p[1], p[2], p[3], p[4]
		local rl, rr = H(rel)
		local h = HPart(relPoint)
		local at = (h == "L" and rl or (h == "R" and rr or (rl + rr) / 2)) + x
		local mine = HPart(point)
		if mine == "L" then left = at elseif mine == "R" then right = at else center = at end
	end
	local w
	if left and right then
		w = right - left
	else
		w = r._w
		if (not w or w == 0) and r._kind == "FontString" then w = r:GetStringWidth() end
		w = w or 0
	end
	if not left then left = right and (right - w) or (center and (center - w / 2)) or 0 end
	if not right then right = left + w end
	hc[r] = { left, right }
	return left, right
end

function V(r) -- bottom, top (y up)
	if r == UIParent then return 0, SCREEN_H end
	local c = vc[r]
	if c then return c[1], c[2] end
	vc[r] = { 0, 0 }
	local bottom, top, center
	local sf = ScrollFrameOf(r)
	if sf then
		local _, t = V(sf)
		top = t + (sf._scroll or 0)
	end
	for _, p in ipairs(r._points or {}) do
		local point, rel, relPoint, y = p[1], p[2], p[3], p[5]
		local rb, rt = V(rel)
		local v = VPart(relPoint)
		local at = (v == "B" and rb or (v == "T" and rt or (rb + rt) / 2)) + y
		local mine = VPart(point)
		if mine == "B" then bottom = at elseif mine == "T" then top = at else center = at end
	end
	local h
	if top and bottom then
		h = top - bottom
	else
		h = r._h
		if (not h or h == 0) and r._kind == "FontString" then h = r:GetStringHeight() end
		h = h or 0
	end
	if not bottom then bottom = top and (top - h) or (center and (center - h / 2)) or 0 end
	if not top then top = bottom + h end
	vc[r] = { bottom, top }
	return bottom, top
end

function L.Width(r) Enter(); local l, rr = H(r); Leave(); return rr - l end
function L.Height(r) Enter(); local b, t = V(r); Leave(); return t - b end
-- The width a font string wraps at: what its width or its anchors give it, when it wraps at all
function L.WrapWidth(fs)
	if fs._wrap == false then return 0 end
	if not ((fs._w and fs._w > 0) or BothSides(fs)) then return 0 end
	Enter()
	local l, r = H(fs)
	Leave()
	return r - l
end

local function Box(r)
	local l, rr = H(r)
	local b, t = V(r)
	return { l, SCREEN_H - t, rr, SCREEN_H - b }
end
function L.Box(r) Enter(); local b = Box(r); Leave(); return b end

---------------------------------------------------------------- levels, strata, visibility
function L.Level(f)
	if f._level then return f._level end
	local p = f._parent
	if not p then return 0 end
	if f._useParentLevel then return L.Level(p) end
	return L.Level(p) + 1
end
function L.Strata(f)
	if f._strata then return f._strata end
	local p = f._parent
	if p and p ~= UIParent then return L.Strata(p) end
	return "MEDIUM"
end
local function Visible(r)
	while r do
		if r._shown == false then return false end
		r = r._parent
	end
	return true
end
local function Under(r, root)
	while r do
		if r == root then return true end
		r = r._parent
	end
	return false
end
local function Alpha(r)
	local a = 1
	while r do
		a = a * (r._alpha or 1)
		r = r._parent
	end
	return a
end
local function Intersect(a, b)
	return { math.max(a[1], b[1]), math.max(a[2], b[2]), math.min(a[3], b[3]), math.min(a[4], b[4]) }
end
-- A scroll frame cuts its scroll child and everything in it to its own rectangle
local function ClipOf(r)
	local clip
	while r and r._parent do
		local p = r._parent
		if p._kind == "ScrollFrame" and p._child == r then
			local b = Box(p)
			clip = clip and Intersect(clip, b) or b
		end
		r = p
	end
	return clip
end

-- What ScrollBarMixin:Update would have done by the time the frame is drawn
function L.UpdateScrollBars()
	for _, f in ipairs(MOCK.frames) do
		if f.MockUpdate and f._scrollFrame then f:MockUpdate() end
	end
end

-- For the layout checks: the field a region is kept in (a row's "text", "right"...), and the kind
-- of row it's in (a scenario tags the rows with _rowKind)
local function KeyOf(region)
	local p = region._parent
	for _, holder in ipairs({ p, p and p._parent }) do
		for k, v in pairs(holder or {}) do
			if v == region and type(k) == "string" and not k:find("^_") then return k end
		end
	end
end
local function RowOf(f)
	while f do
		if f._rowKind then return f._rowKind end
		f = f._parent
	end
end
-- A height that doesn't come from the text: set, or given by a top and a bottom anchor
local function FixedHeight(r)
	if r._h and r._h > 0 then return true end
	local top, bottom = false, false
	for _, p in ipairs(r._points or {}) do
		local v = VPart(p[1])
		if v == "T" then top = true elseif v == "B" then bottom = true end
	end
	return top and bottom
end

-- Everything visible under the roots, as drawable items. `hovered` is the frame under the mouse:
-- its HIGHLIGHT layer shows.
function L.Dump(roots, hovered)
	Enter()
	local out, order, buttons = {}, 0, {}
	local index = {}
	for i, f in ipairs(MOCK.frames) do index[f] = i end
	local function Chain(f)
		local ids = {}
		while f do
			if index[f] then ids[#ids + 1] = index[f] end
			f = f._parent
		end
		return ids
	end
	local function Mine(f)
		for _, root in ipairs(roots) do if Under(f, root) then return true end end
	end
	local function Add(item, f, layer, sublevel, region)
		order = order + 1
		item.strata, item.level, item.layer, item.sublevel, item.order = STRATA[L.Strata(f)], L.Level(f), LAYERS[layer] or 3, sublevel or 0, order
		item.clip = ClipOf(region or f)
		out[#out + 1] = item
	end
	for _, f in ipairs(MOCK.frames) do
		if Mine(f) and Visible(f) then
			local alpha = Alpha(f)
			if f._nineSlice then
				local layer = NINESLICE_LAYERS[f._nineSlice] or { "BORDER", 0 }
				Add({ kind = "nineslice", layout = f._nineSlice, box = Box(f), alpha = alpha }, f, layer[1], layer[2])
			end
			local lit = hovered == f or f._highlightLocked
			for _, t in ipairs(f._textures or {}) do
				if t._shown and (t._layer ~= "HIGHLIGHT" or lit) and (t._atlas or t._file or t._color) then
					local masks
					for _, m in ipairs(t._masks or {}) do
						masks = masks or {}
						masks[#masks + 1] = { atlas = m._atlas, file = m._file, box = Box(m) }
					end
					Add({ kind = "texture", box = Box(t), atlas = t._atlas, file = t._file, color = t._color, vcolor = t._vcolor,
						alpha = alpha * (t._alpha or 1), blend = t._blend, desaturated = t._desaturated, coords = t._coords,
						staleCrop = t._atlasCrop, htile = t._htile, vtile = t._vtile, masks = masks }, f, t._layer, t._sublevel, t)
				end
			end
			for _, fs in ipairs(f._fontstrings or {}) do
				if fs._shown and fs._text and fs._text ~= "" then
					Add({ kind = "text", box = Box(fs), text = fs._text, font = fs._font, color = fs._color, justify = fs._justify,
						justifyV = fs._justifyV, wrap = L.WrapWidth(fs) > 0, spacing = fs._spacing or 0,
						fixedHeight = FixedHeight(fs), alpha = alpha * (fs._alpha or 1),
						key = KeyOf(fs), row = RowOf(f), chain = Chain(f) }, f, fs._layer, 0, fs)
				end
			end
			-- a button with art of its own (not just a highlight): text from elsewhere shouldn't run under it
			if f._kind ~= "Frame" and f._kind ~= "ScrollFrame" and f._kind ~= "EditBox" and f._kind ~= "EventFrame" then
				for _, t in ipairs(f._textures or {}) do
					if t._shown and t._layer ~= "HIGHLIGHT" and (t._atlas or t._file or t._color) and (t._alpha or 1) > 0 then
						buttons[#buttons + 1] = { box = Box(f), id = index[f], row = RowOf(f), key = KeyOf(f), clip = ClipOf(f) }
						break
					end
				end
			end
			-- an edit box draws what's typed in it inside its text insets
			if f._kind == "EditBox" and (f._text or "") ~= "" then
				local b, ins = Box(f), f._insets or { 0, 0, 0, 0 }
				Add({ kind = "text", box = { b[1] + ins[1], b[2] + ins[3], b[3] - ins[2], b[4] - ins[4] }, text = f._text,
					font = f._textFont or "ChatFontNormal", color = f._textColor, justify = "LEFT", wrap = false, spacing = 0,
					alpha = alpha }, f, "OVERLAY", 0)
			end
		end
	end
	Leave()
	return out, buttons
end

return L
