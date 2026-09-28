-- Mocks of the Blizzard templates and UI globals Forever Loot builds its window from, shared
-- by both test suites. Load it after a mock (tools/test/wowmock.lua or tools/lupa/wowmock.lua);
-- the mock's CreateFrame calls MOCK.ApplyTemplate for any template it's given, and an unknown
-- template is an error. Each template gets the children and methods the real one has (from
-- WoW: Forever's Blizzard_SharedXML and Blizzard_Menu), plus Mock* helpers for the tests.

local function FontStringOf(parent, font)
	local fs = parent:CreateFontString(nil, "OVERLAY")
	fs:SetFontObject(font)
	return fs
end

for _, name in ipairs({ "GameFontNormal", "GameFontNormalSmall", "GameFontNormalLarge", "GameFontNormalHuge",
	"GameFontHighlight", "GameFontHighlightSmall", "GameFontDisable", "GameFontDisableSmall", "GameFontGreenSmall",
	"ChatFontNormal" }) do
	if not _G[name] then CreateFont(name) end
end

CLOSE = "Close"
SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON = 856
SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF = 857
SOUNDKIT.IG_CHARACTER_INFO_TAB = 841

QuestDifficultyColors = {
	impossible = { r = 1.00, g = 0.10, b = 0.10 }, verydifficult = { r = 1.00, g = 0.50, b = 0.25 },
	difficult = { r = 1.00, g = 0.82, b = 0.00 }, standard = { r = 0.25, g = 0.75, b = 0.25 },
	trivial = { r = 0.50, g = 0.50, b = 0.50 }, header = { r = 0.70, g = 0.70, b = 0.70 },
}

-- Blizzard_Menu's descriptions: radios, titles and dividers, with what picking does
local function NewMenuDescription()
	local root = { elements = {} }
	local function Add(e)
		table.insert(root.elements, e)
		return e
	end
	function root:CreateRadio(text, isSelected, setSelected, data)
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

local T = {}

T.PortraitFrameTemplate = function(f)
	f.TitleContainer = CreateFrame("Frame", nil, f)
	f.TitleContainer.TitleText = FontStringOf(f.TitleContainer, GameFontNormal)
	f.PortraitContainer = CreateFrame("Frame", nil, f)
	f.PortraitContainer.portrait = f.PortraitContainer:CreateTexture(nil, "OVERLAY")
	f.NineSlice = CreateFrame("Frame", nil, f)
	f.Bg = f:CreateTexture(nil, "BACKGROUND")
	-- UIPanelCloseButton: onCloseCallback, then HideUIPanel (a plain Hide for an unmanaged frame)
	local close = CreateFrame("Button", nil, f)
	close:SetScript("OnClick", function(self)
		local continueHide = true
		if f.onCloseCallback then continueHide = f.onCloseCallback(self) end
		if continueHide then f:Hide() end
	end)
	f.CloseButton = close
	function f:SetTitle(text) self.TitleContainer.TitleText:SetText(text) end
	function f:GetTitleText() return self.TitleContainer.TitleText end
	function f:SetPortraitToAsset(texture) self.PortraitContainer.portrait:SetTexture(texture) end
	function f:GetPortrait() return self.PortraitContainer.portrait end
end

T.InsetFrameTemplate = function(f)
	f.Bg = f:CreateTexture(nil, "BACKGROUND")
	f.NineSlice = CreateFrame("Frame", nil, f)
end

-- A side tab (a Frame): clicks come through the custom mouse-up handler
T.LargeSideTabButtonTemplate = function(f)
	f.Background = f:CreateTexture(nil, "BACKGROUND")
	f.Icon = f:CreateTexture(nil, "ARTWORK")
	f.SelectedTexture = f:CreateTexture(nil, "OVERLAY")
	f.SelectedTexture:Hide()
	function f:SetChecked(checked)
		self.checked = checked and true or false
		self.SelectedTexture:SetShown(self.checked)
	end
	function f:SetFillToInterior(fill, extent) self.fillToInterior, self.interiorExtent = fill, extent end
	function f:SetCustomOnMouseUpHandler(handler) self.customMouseUpHandler = handler end
	function f:MockClick()
		if self.customMouseUpHandler then self.customMouseUpHandler(self, "LeftButton", true) end
	end
end

-- The search box: instructions, magnifier and a clear button that empties it
T.SearchBoxTemplate = function(eb)
	eb:SetFontObject(ChatFontNormal)
	eb.Instructions = FontStringOf(eb, GameFontDisableSmall)
	eb.searchIcon = eb:CreateTexture(nil, "OVERLAY")
	local clear = CreateFrame("Button", nil, eb)
	clear:SetScript("OnClick", function()
		eb:SetText("")
		eb:ClearFocus()
	end)
	eb.clearButton = clear
	eb:SetScript("OnTextChanged", function(self)
		self.Instructions:SetShown(self:GetText() == "")
	end)
end

-- A dropdown: the menu is rebuilt from the generator, and the button shows the selections
T.WowStyle1DropdownTemplate = function(d)
	d.Text = FontStringOf(d, GameFontHighlightSmall)
	d.Arrow = d:CreateTexture(nil, "OVERLAY")
	function d:SetDefaultText(text) self.defaultText = text end
	function d:SetSelectionTranslator(translator) self.translator = translator end
	function d:SetupMenu(generator)
		self.generator = generator
		self:GenerateMenu()
	end
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
	function d:OpenMenu()
		self:GenerateMenu()
		self.menuOpen = true
	end
	function d:CloseMenu() self.menuOpen = false end
	function d:IsMenuOpen() return self.menuOpen == true end
	-- The menu's elements, as they'd show when opened
	function d:MockOptions()
		self:OpenMenu()
		return self.menuDescription.elements
	end
	-- Picks the radio with this text (or data), closing the menu as a click does
	function d:MockPick(textOrData)
		for _, e in ipairs(self:MockOptions()) do
			if e.kind == "radio" and (e.text == textOrData or (e.data ~= nil and e.data == textOrData)) then
				e.setSelected(e.data)
				self.menuOpen = false
				self:GenerateMenu()
				return true
			end
		end
		error("no menu option " .. tostring(textOrData))
	end
end

-- A checkbox: clicking flips the check before OnClick runs, as in the game
T.UICheckButtonTemplate = function(b)
	b.Text = FontStringOf(b, GameFontNormalSmall)
	function b:SetChecked(checked) self.checked = checked and true or false end
	function b:GetChecked() return self.checked == true end
	function b:Click(button)
		self.checked = not self.checked
		local fn = self:GetScript("OnClick")
		if fn then fn(self, button or "LeftButton") end
	end
end

T.UIPanelButtonTemplate = function(b)
	b.Text = FontStringOf(b, GameFontNormal)
	function b:SetText(text) self.Text:SetText(text) end
	function b:GetText() return self.Text:GetText() end
end

-- ScrollFrameTemplate: a minimal scroll bar, and the mouse wheel scrolls
T.ScrollFrameTemplate = function(sf)
	local bar = CreateFrame("Frame", nil, sf)
	function bar:SetHideIfUnscrollable(hide) self.hideIfUnscrollable = hide end
	sf.ScrollBar = bar
	sf:SetScript("OnMouseWheel", function(self, delta)
		self:SetVerticalScroll(math.max(0, math.min(self:GetVerticalScrollRange(), self:GetVerticalScroll() - delta * 30)))
	end)
end

function MOCK.ApplyTemplate(frame, template)
	local build = T[template]
	if not build then error("mock: unknown template " .. tostring(template), 3) end
	build(frame)
end

-- The game's popups: StaticPopup_Show formats the text and runs OnShow with the edit box
StaticPopupDialogs = {}
function StaticPopup_Show(which, textArg1, textArg2, data)
	local info = assert(StaticPopupDialogs[which], "no StaticPopupDialogs entry " .. tostring(which))
	local dialog = CreateFrame("Frame", nil, UIParent)
	local box = CreateFrame("EditBox", nil, dialog)
	box:SetFontObject(ChatFontNormal)
	function dialog:GetEditBox() return box end
	dialog.which, dialog.data = which, data
	dialog.text = info.text:format(textArg1 or "", textArg2 or "")
	MOCK.popup = dialog
	if info.OnShow then info.OnShow(dialog, data) end
	return dialog
end
