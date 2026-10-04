-- The Blizzard templates Forever Loot builds its window from, made the way WoW: Forever 1.60.1 (build
-- 70205) defines them: the same children, art, sizes, anchors, layers and frame levels, read from
-- Gethe/wow-ui-source's forever branch (Blizzard_SharedXML's Mainline, Shared and Camelot files and
-- Blizzard_Menu's Mainline templates), so preview.py can draw them. Script handlers are cut to what
-- changes the look. Loaded by wowmock.lua; CreateFrame refuses any template that isn't here.
local T = MOCK.TEMPLATES

local function Kinds(...)
	local k = {}
	for _, v in ipairs({ ... }) do k[v] = true end
	return k
end

local function Atlas(parent, layer, atlas, useAtlasSize, sublevel)
	local t = parent:CreateTexture(nil, layer, nil, sublevel)
	t:SetAtlas(atlas, useAtlasSize)
	return t
end

local function File(parent, layer, file, sublevel)
	local t = parent:CreateTexture(nil, layer, nil, sublevel)
	t:SetTexture(file)
	return t
end

-- NineSlicePanelTemplate: frame level 500 unless useParentLevel, filling its parent, drawing the
-- layout its parent's layoutType names (NineSlicePanelMixin:OnLoad). layout.lua lists it and
-- preview.py draws its pieces.
local function NineSlice(parent, layoutType, useParentLevel)
	local n = CreateFrame("Frame", nil, parent)
	n:SetAllPoints(parent)
	if useParentLevel then n._useParentLevel = true else n:SetFrameLevel(500) end
	n._nineSlice = layoutType
	return n
end

---------------------------------------------------------------- the window
-- UIPanelCloseButtonNoScripts / UIPanelCloseButton (Mainline/SharedUIPanelTemplates.xml): 24 x 24
-- at frame level 510, the red X; its click runs the window's onCloseCallback, then hides it
local function CloseButton(b)
	b:SetSize(24, 24)
	b:SetFrameLevel(510)
	b:SetDisabledTexture("RedButton-Exit-Disabled")
	b:SetNormalTexture("RedButton-Exit")
	b:SetPushedTexture("RedButton-exit-pressed")
	b:SetHighlightTexture("RedButton-Highlight", "ADD")
	b:SetScript("OnClick", function(self)
		local window = self:GetParent()
		if window.onCloseCallback and not window.onCloseCallback(self) then return end
		window:Hide()
	end)
end
T.UIPanelCloseButton = { kinds = Kinds("Button"), build = CloseButton }
-- Camelot's UIPanelCloseButtonDefaultAnchorsMixin:OnLoad (Camelot/SharedUIPanelTemplates.lua): TOPRIGHT -2, 1
T.UIPanelCloseButtonDefaultAnchors = { kinds = Kinds("Button"), build = function(b)
	CloseButton(b)
	b:SetPoint("TOPRIGHT", -2, 1)
end }

-- PortraitFrameTemplate = PortraitFrameBaseTemplate + PortraitFrameTexturedBaseTemplate + a close
-- button (Mainline/SharedUIPanelTemplates.xml): the metal border (NineSlice "PortraitFrameTemplate",
-- with Camelot's offset overrides), the rock background and the streaks under the title bar, the
-- round portrait (masked by TempPortraitAlphaMask) and the title
T.PortraitFrameTemplate = { kinds = Kinds("Frame"), build = function(f, name)
	f:SetSize(338, 424)
	f.layoutType = "PortraitFrameTemplate"
	f.NineSlice = NineSlice(f, "PortraitFrameTemplate")
	local pc = CreateFrame("Frame", nil, f)
	pc:SetSize(1, 1)
	pc:SetPoint("TOPLEFT")
	pc:SetFrameLevel(400)
	local portrait = pc:CreateTexture(nil, "OVERLAY")
	portrait:SetSize(62, 62)
	portrait:SetPoint("TOPLEFT", -5, 7)
	local mask = pc:CreateMaskTexture()
	mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
	mask:SetPoint("TOPLEFT", portrait, "TOPLEFT", 2, 0)
	mask:SetPoint("BOTTOMRIGHT", portrait, "BOTTOMRIGHT", -2, 4)
	portrait:AddMaskTexture(mask)
	pc.portrait, pc.CircleMask = portrait, mask
	f.PortraitContainer = pc
	local tc = CreateFrame("Frame", nil, f)
	tc:SetHeight(20)
	tc:SetPoint("TOPLEFT", 58, -1)
	tc:SetPoint("TOPRIGHT", -24, -1)
	tc:SetFrameLevel(510)
	local title = tc:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOP", 0, -5)
	title:SetPoint("LEFT")
	title:SetPoint("RIGHT")
	title:SetWordWrap(false)
	title:SetText("")
	tc.TitleText = title
	f.TitleContainer = tc
	f.Bg = File(f, "BACKGROUND", "Interface\\FrameGeneral\\UI-Background-Rock", -6)
	f.Bg:SetHorizTile(true)
	f.Bg:SetVertTile(true)
	f.Bg:SetPoint("TOPLEFT", 2, -21)
	f.Bg:SetPoint("BOTTOMRIGHT", -2, 2)
	-- the texture template _UI-Frame-TopTileStreaks: its atlas, 256 x 43, tiled across
	f.TopTileStreaks = Atlas(f, "BORDER", "_UI-Frame-TopTileStreaks")
	f.TopTileStreaks:SetSize(256, 43)
	f.TopTileStreaks:SetHorizTile(true)
	f.TopTileStreaks:SetPoint("TOPLEFT", 6, -21)
	f.TopTileStreaks:SetPoint("TOPRIGHT", -2, -21)
	f.CloseButton = CreateFrame("Button", name and "$parentCloseButton" or nil, f, "UIPanelCloseButtonDefaultAnchors")
	-- PortraitFrameMixin / TitledPanelMixin
	function f:GetTitleText() return self.TitleContainer.TitleText end
	function f:SetTitle(text) self.TitleContainer.TitleText:SetText(text) end
	function f:GetPortrait() return self.PortraitContainer.portrait end
	function f:SetPortraitToAsset(texture) self:GetPortrait():SetTexture(texture) end
	function f:SetPortraitTextureRaw(texture) self:GetPortrait():SetTexture(texture) end
	function f:SetPortraitTexCoord(...) self:GetPortrait():SetTexCoord(...) end
	function f:SetPortraitShown(shown) self:GetPortrait():SetShown(shown) end
end }

-- InsetFrameTemplate: useParentLevel; the marble background (BACKGROUND -5, tiled) and the inner
-- border (NineSlice "InsetFrameTemplate", also useParentLevel; its pieces are BORDER -5)
T.InsetFrameTemplate = { kinds = Kinds("Frame"), build = function(f)
	f._useParentLevel = true
	f.layoutType = "InsetFrameTemplate"
	f.Bg = File(f, "BACKGROUND", "Interface\\FrameGeneral\\UI-Background-Marble", -5)
	f.Bg:SetHorizTile(true)
	f.Bg:SetVertTile(true)
	f.Bg:SetAllPoints()
	f.NineSlice = NineSlice(f, "InsetFrameTemplate", true)
end }

-- LargeSideTabButtonTemplate (a Frame, mixin SidePanelTabButtonMixin): the tab art, the icon under
-- the tab's mask, the gold frame when it's the open tab and the hover glow. OnLoad sizes it from
-- the common-sidetab art (its height less 5) and puts the icon at CENTER -4, 0 (Camelot's offset).
T.LargeSideTabButtonTemplate = { kinds = Kinds("Frame"), build = function(t)
	t.Background = Atlas(t, "BACKGROUND", "common-sidetab", true)
	t.Background:SetPoint("CENTER")
	t.Icon = t:CreateTexture(nil, "ARTWORK")
	t.Mask = t:CreateMaskTexture()
	t.Mask:SetAtlas("common-sidetab-mask", true)
	t.Mask:SetPoint("CENTER")
	t.Icon:AddMaskTexture(t.Mask)
	t.SelectedTexture = Atlas(t, "OVERLAY", "common-sidetab-selected", true)
	t.SelectedTexture:SetPoint("CENTER")
	t.TabGlow = Atlas(t, "OVERLAY", "common-sidetab-selected", true)
	t.TabGlow:SetPoint("CENTER")
	t.TabGlow:SetAlpha(0)
	t.TabGlow:SetBlendMode("ADD")
	t.HighlightTexture = Atlas(t, "HIGHLIGHT", "common-sidetab-hover", true)
	t.HighlightTexture:SetPoint("CENTER")
	local art = MOCK.ATLASES["common-sidetab"]
	t:SetSize(art[1], art[2] - 5)
	t.Icon:SetPoint("CENTER", -4, 0)
	function t:SetCustomOnMouseUpHandler(handler) self.customMouseUpHandler = handler end
	function t:UpdateIconInterior()
		if self.fillToInterior then
			local extent = self.interiorExtent or 50
			self.Icon:SetTexCoord(0.03125, 0.96875, 0.03125, 0.96875)
			self.Icon:SetSize(extent, extent)
		end
	end
	function t:SetFillToInterior(fill, extent)
		self.fillToInterior, self.interiorExtent = fill, extent
		self:UpdateIconInterior()
	end
	function t:SetChecked(checked)
		self.SelectedTexture:SetShown(checked)
		self:UpdateIconInterior()
	end
	t:SetScript("OnMouseDown", function(self, button)
		if button == "LeftButton" then self.Icon:SetPoint("CENTER", -3, -1) end
	end)
	t:SetScript("OnMouseUp", function(self, button, upInside)
		if button == "LeftButton" then
			self.Icon:SetPoint("CENTER", -4, 0)
			PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
		end
		if self.customMouseUpHandler then self.customMouseUpHandler(self, button, upInside) end
	end)
	t:SetScript("OnEnter", function(self)
		if not self.tooltipText then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT", -4, -4)
		GameTooltip:SetText(self.tooltipText)
		GameTooltip:Show()
	end)
	t:SetScript("OnLeave", function() GameTooltip:Hide() end)
	-- a left click on the tab, as the player makes it
	function t:MockClick()
		self:_Fire("OnMouseDown", "LeftButton")
		self:_Fire("OnMouseUp", "LeftButton", true)
	end
end }

---------------------------------------------------------------- scrolling
-- MinimalScrollBar (Shared/Scroll/MinimalScrollBar.xml, an EventFrame): the arrows top and bottom,
-- the track 19 in from each end, and the thumb (minThumbExtent 23, anchored TOP). MockUpdate does
-- what ScrollBarMixin:Update does after the scroll frame scrolls or its content changes.
T.MinimalScrollBar = { kinds = Kinds("EventFrame"), build = function(bar)
	bar:SetSize(8, 560)
	bar.minThumbExtent = 23
	local track = CreateFrame("Frame", nil, bar)
	track:SetWidth(8)
	track:SetPoint("TOP", 0, -19)
	track:SetPoint("BOTTOM", 0, 19)
	track.Begin = Atlas(track, "ARTWORK", "minimal-scrollbar-track-top", true)
	track.Begin:SetPoint("TOPLEFT")
	track.End = Atlas(track, "ARTWORK", "minimal-scrollbar-track-bottom", true)
	track.End:SetPoint("BOTTOMLEFT")
	track.Middle = Atlas(track, "ARTWORK", "!minimal-scrollbar-track-middle", true)
	track.Middle:SetPoint("TOPLEFT", track.Begin, "BOTTOMLEFT")
	track.Middle:SetPoint("BOTTOMRIGHT", track.End, "TOPRIGHT")
	local thumb = CreateFrame("EventButton", nil, track)
	thumb:SetWidth(8)
	thumb.Begin = Atlas(thumb, "ARTWORK", "minimal-scrollbar-small-thumb-top", true)
	thumb.Begin:SetPoint("TOPLEFT")
	thumb.End = Atlas(thumb, "ARTWORK", "minimal-scrollbar-small-thumb-bottom", true)
	thumb.End:SetPoint("BOTTOMLEFT")
	thumb.Middle = Atlas(thumb, "ARTWORK", "minimal-scrollbar-small-thumb-middle", true)
	thumb.Middle:SetPoint("TOPLEFT", thumb.Begin, "BOTTOMLEFT")
	thumb.Middle:SetPoint("BOTTOMRIGHT", thumb.End, "TOPRIGHT")
	track.Thumb = thumb
	bar.Track = track
	-- the steppers: a texture filling each (it has no anchors), set to its normal atlas on load
	local function Stepper(atlas, point)
		local b = CreateFrame("EventButton", nil, bar)
		b:SetSize(17, 11)
		b:SetPoint(point)
		b.Texture = Atlas(b, "BACKGROUND", atlas, true)
		b.Texture:SetAllPoints()
		return b
	end
	bar.Back = Stepper("minimal-scrollbar-arrow-top", "TOP")
	bar.Forward = Stepper("minimal-scrollbar-arrow-bottom", "BOTTOM")
	function bar:SetHideIfUnscrollable(hide) self.hideIfUnscrollable = hide end
	function bar:SetHideTrackIfThumbExceedsTrack(hide) self.hideTrackIfThumbExceedsTrack = hide end
	function bar:MockUpdate()
		local sf = self._scrollFrame
		if not sf then return end
		local eps = 0.000001
		local viewH, range = sf:GetHeight(), sf:GetVerticalScrollRange()
		local visible = viewH > 0 and viewH / (range + viewH) or 0
		local trackExtent = self.Track:GetHeight()
		local thumbExtent = math.max(self.minThumbExtent, trackExtent * visible)
		local clamped = thumbExtent > trackExtent
		if clamped then thumbExtent = trackExtent end
		local th = self.Track.Thumb
		th:SetHeight(thumbExtent)
		-- MinimalScrollBarThumbScriptsMixin:OnSizeChanged: the middle shows as much of its art as the thumb is tall
		th.Middle:SetTexCoord(0, 1, 0, math.min(thumbExtent / MOCK.ATLASES["minimal-scrollbar-small-thumb-middle"][2], 1))
		local percent = range > 0 and sf:GetVerticalScroll() / range or 0
		th:ClearAllPoints()
		th:SetPoint("TOP", self.Track, "TOP", 0, -(trackExtent - thumbExtent) * percent)
		local scrollable = visible > eps and visible < 1 - eps
		th:SetShown(scrollable and not clamped)
		self.Track:SetShown(not self.hideTrack and not (clamped and self.hideTrackIfThumbExceedsTrack))
		-- a stepper that can't scroll further is disabled, and greys out (DesaturateIfDisabled)
		self.Back:DesaturateHierarchy((scrollable and percent > eps) and 0 or 1)
		self.Forward:DesaturateHierarchy((scrollable and percent < 1 - eps) and 0 or 1)
		if self.hideIfUnscrollable then self:SetShown(scrollable) end
	end
end }

-- ScrollFrameTemplate: ScrollFrame_OnLoad adds a SCROLL_FRAME_SCROLL_BAR_TEMPLATE (MinimalScrollBar
-- in Mainline/ScrollDefine.lua) 6 right of the frame, 2 above its top and 5 above its bottom, and
-- ScrollUtil.InitScrollFrameWithScrollBar sets OnVerticalScroll and the mouse wheel (30 a notch)
T.ScrollFrameTemplate = { kinds = Kinds("ScrollFrame"), build = function(sf)
	local bar = CreateFrame("EventFrame", nil, sf, "MinimalScrollBar")
	bar:SetHideIfUnscrollable(sf.scrollBarHideIfUnscrollable)
	bar:SetHideTrackIfThumbExceedsTrack(sf.scrollBarHideTrackIfThumbExceedsTrack)
	bar:SetPoint("TOPLEFT", sf, "TOPRIGHT", 6, 2)
	bar:SetPoint("BOTTOMLEFT", sf, "BOTTOMRIGHT", 6, 5)
	bar:Show()
	bar._scrollFrame = sf
	sf.ScrollBar = bar
	sf:SetScript("OnVerticalScroll", function() bar:MockUpdate() end)
	sf:SetScript("OnScrollRangeChanged", function() bar:MockUpdate() end)
	sf:SetScript("OnMouseWheel", function(self, delta)
		self:SetVerticalScroll(math.max(0, math.min(self:GetVerticalScrollRange(), self:GetVerticalScroll() - delta * 30)))
	end)
end }

---------------------------------------------------------------- controls
-- SearchBoxTemplate = InputBoxVisualTemplate (the search border's three pieces) +
-- InputBoxInstructionsTemplate (the grey instructions, GameFontHighlightSmall text) + the magnifying
-- glass and the clear button (Shared/InputBox/InputBoxTemplates.xml and .lua)
T.SearchBoxTemplate = { kinds = Kinds("EditBox"), build = function(e)
	e.Left = Atlas(e, "BACKGROUND", "common-search-border-left")
	e.Left:SetSize(8, 20)
	e.Left:SetPoint("LEFT", -5, 0)
	e.Right = Atlas(e, "BACKGROUND", "common-search-border-right")
	e.Right:SetSize(8, 20)
	e.Right:SetPoint("RIGHT", 0, 0)
	e.Middle = Atlas(e, "BACKGROUND", "common-search-border-middle")
	e.Middle:SetSize(10, 20)
	e.Middle:SetPoint("LEFT", e.Left, "RIGHT")
	e.Middle:SetPoint("RIGHT", e.Right, "LEFT")
	e.Instructions = e:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	e.Instructions:SetJustifyH("LEFT")
	e.Instructions:SetJustifyV("MIDDLE")
	e.Instructions:SetPoint("TOPLEFT", 16, 0)
	e.Instructions:SetPoint("BOTTOMRIGHT", -20, 0)
	e.Instructions:SetTextColor(0.35, 0.35, 0.35)
	e:SetFontObject("GameFontHighlightSmall")
	e.searchIcon = Atlas(e, "OVERLAY", "common-search-magnifyingglass")
	e.searchIcon:SetSize(10, 10)
	e.searchIcon:SetPoint("LEFT", 1, -1)
	local clear = CreateFrame("Button", e._name and (e._name .. "ClearButton") or nil, e)
	clear:SetSize(17, 17)
	clear:SetPoint("RIGHT", -3, 0)
	clear.Icon = Atlas(clear, "ARTWORK", "common-search-clearbutton")
	clear.Icon:SetSize(10, 10)
	clear.Icon:SetPoint("TOPLEFT", 3, -3)
	clear.Icon:SetAlpha(0.5)
	clear:Hide()
	clear:SetScript("OnClick", function() e:SetText(""); e:ClearFocus() end)
	e.clearButton = clear
	e:SetTextInsets(16, 20, 0, 0)
	e:SetAutoFocus(false)
	-- SearchBoxTemplate_OnLoad
	e.searchIcon:SetVertexColor(0.6, 0.6, 0.6)
	e.Instructions:SetText(SEARCH)
	-- SearchBoxTemplate_OnTextChanged (with InputBoxInstructions_OnTextChanged)
	e:SetScript("OnTextChanged", function(self)
		if not self:HasFocus() and self:GetText() == "" then
			self.searchIcon:SetVertexColor(0.6, 0.6, 0.6)
			self.clearButton:Hide()
		else
			self.searchIcon:SetVertexColor(1, 1, 1)
			self.clearButton:Show()
		end
		self.Instructions:SetShown(self:GetText() == "")
	end)
	e:SetScript("OnEditFocusGained", function(self)
		self.searchIcon:SetVertexColor(1, 1, 1)
		self.clearButton:Show()
	end)
	e:SetScript("OnEditFocusLost", function(self)
		if self:GetText() == "" then
			self.searchIcon:SetVertexColor(0.6, 0.6, 0.6)
			self.clearButton:Hide()
		end
	end)
	e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
end }

-- UICheckButtonTemplate (Shared/Button/CheckButtonTemplates.xml): 32 x 32, the UI-CheckBox art and
-- its label in GameFontNormalSmall just right of the box
T.UICheckButtonTemplate = { kinds = Kinds("CheckButton"), build = function(b)
	b:SetSize(32, 32)
	b:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
	b:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
	b:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
	b:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
	b.Text = b:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	b.Text:SetPoint("LEFT", b, "RIGHT", -2, 0)
	b.text = b.Text
end }

-- UIPanelButtonTemplate (UIPanelButtonNoTooltipTemplate in SecureUIPanelTemplates.xml): 40 x 22, the
-- red button in three pieces of UI-Panel-Button-Up, GameFontNormal text (GameFontHighlight hovered)
T.UIPanelButtonTemplate = { kinds = Kinds("Button"), build = function(b)
	b:SetSize(40, 22)
	local function Piece(l, r)
		local t = File(b, "BACKGROUND", "Interface\\Buttons\\UI-Panel-Button-Up")
		t:SetTexCoord(l, r, 0, 0.6875)
		return t
	end
	b.Left = Piece(0, 0.09375)
	b.Left:SetSize(12, 22)
	b.Left:SetPoint("TOPLEFT")
	b.Left:SetPoint("BOTTOMLEFT")
	b.Right = Piece(0.53125, 0.625)
	b.Right:SetSize(12, 22)
	b.Right:SetPoint("TOPRIGHT")
	b.Right:SetPoint("BOTTOMRIGHT")
	b.Middle = Piece(0.09375, 0.53125)
	b.Middle:SetSize(12, 22)
	b.Middle:SetPoint("TOPLEFT", b.Left, "TOPRIGHT")
	b.Middle:SetPoint("BOTTOMRIGHT", b.Right, "BOTTOMLEFT")
	b.Text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	b.Text:SetPoint("CENTER")
	b._fontString = b.Text
	b:SetNormalFontObject("GameFontNormal")
	b:SetHighlightFontObject("GameFontHighlight")
	b:SetDisabledFontObject("GameFontDisable")
	-- UIPanelButtonHighlightTexture
	local h = File(b, "HIGHLIGHT", "Interface\\Buttons\\UI-Panel-Button-Highlight")
	h:SetTexCoord(0, 0.625, 0, 0.6875)
	h:SetBlendMode("ADD")
	h:SetAllPoints()
	b._highlightTexture = h
	local function Art(file) b.Left:SetTexture(file); b.Middle:SetTexture(file); b.Right:SetTexture(file) end
	b:SetScript("OnDisable", function() Art("Interface\\Buttons\\UI-Panel-Button-Disabled") end)
	b:SetScript("OnEnable", function() Art("Interface\\Buttons\\UI-Panel-Button-Up") end)
end }

---------------------------------------------------------------- Blizzard_Menu dropdowns
-- A menu description: what the generator adds, and what picking an entry does
local function NewMenuDescription()
	local root = { elements = {} }
	local function Add(e)
		table.insert(root.elements, e)
		return e
	end
	function root:CreateRadio(text, isSelected, setSelected, data)
		assert(type(text) == "string" and type(isSelected) == "function" and type(setSelected) == "function", "CreateRadio(text, isSelected, setSelected, data)")
		return Add({ kind = "radio", text = text, isSelected = isSelected, setSelected = setSelected, data = data })
	end
	function root:CreateCheckbox(text, isSelected, setSelected, data)
		return Add({ kind = "checkbox", text = text, isSelected = isSelected, setSelected = setSelected, data = data })
	end
	function root:CreateButton(text, onClick, data) return Add({ kind = "button", text = text, onClick = onClick, data = data }) end
	function root:CreateTitle(text) return Add({ kind = "title", text = text }) end
	function root:CreateDivider() return Add({ kind = "divider" }) end
	function root:SetScrollMode(extent) self.scrollExtent = extent end
	return root
end
MOCK.NewMenuDescription = NewMenuDescription

-- WowStyle1DropdownTemplate (Blizzard_Menu/Mainline/MenuTemplates.xml): 120 x 25, the text holder
-- stretched 8 past each side, the gold arrow at the right, and the selection as its text in white
-- (WowStyle1DropdownMixin:OnButtonStateChanged sets HIGHLIGHT_FONT_COLOR)
T.WowStyle1DropdownTemplate = { kinds = Kinds("DropdownButton"), build = function(d)
	d:SetSize(120, 25)
	d.Background = Atlas(d, "BACKGROUND", "common-dropdown-textholder", true)
	d.Background:SetPoint("TOPLEFT", -8, 7)
	d.Background:SetPoint("BOTTOMRIGHT", 8, -9)
	d.Arrow = Atlas(d, "OVERLAY", "common-dropdown-a-button", true)
	d.Arrow:SetPoint("RIGHT", d, "RIGHT", 1, -3)
	d.Text = d:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	d.Text:SetWordWrap(false)
	d.Text:SetJustifyH("LEFT")
	d.Text:SetHeight(10)
	d.Text:SetPoint("TOPRIGHT", d.Arrow, "LEFT")
	d.Text:SetPoint("TOPLEFT", 8, -8)
	d.Text:SetTextColor(1, 1, 1)
	function d:SetDefaultText(text) self.defaultText = text; self:GenerateMenu() end
	function d:SetSelectionTranslator(translator) self.translator = translator end
	function d:SetupMenu(generator)
		assert(type(generator) == "function", "SetupMenu wants a function")
		self.generator = generator
		self:GenerateMenu()
	end
	-- DropdownSelectionTextMixin: the selected radios' text, or the default text
	function d:GenerateMenu()
		if not self.generator then return end
		local root = NewMenuDescription()
		self.generator(self, root)
		self.menuDescription = root
		local texts = {}
		for _, e in ipairs(root.elements) do
			if (e.kind == "radio" or e.kind == "checkbox") and e.isSelected(e.data) then
				texts[#texts + 1] = self.translator and self.translator(e) or e.text
			end
		end
		self.Text:SetText(#texts > 0 and table.concat(texts, ", ") or (self.defaultText or ""))
	end
	function d:OpenMenu() self:GenerateMenu(); self.menuOpen = true end
	function d:CloseMenu() self.menuOpen = false end
	function d:IsMenuOpen() return self.menuOpen == true end
	-- Picks the radio with this text or data, as a click does (the menu closes, the text updates)
	function d:MockPick(textOrData)
		self:OpenMenu()
		for _, e in ipairs(self.menuDescription.elements) do
			if e.kind == "radio" and (MOCK.Plain(e.text) == textOrData or (e.data ~= nil and e.data == textOrData)) then
				e.setSelected(e.data)
				self.menuOpen = false
				self:GenerateMenu()
				return true
			end
		end
		error("no menu option " .. tostring(textOrData))
	end
end }
