local ADDON, ns = ...
local UI, K = ns.UI, ns.UIKit
local C = ns.COLORS
if not (UI and K and K.QuestStartLine and ns.QuestInfo) then return end

-- The Quests tab: every dungeon and raid quest with where it stands for you, where it starts,
-- and the quests that come before it, each with a map pin button for its quest giver. Its first
-- page lists what you can do now across every instance.

local ITEM_H, NOTE_H, SECTION_GAP, QLINE_H = K.ITEM_H, K.NOTE_H, K.SECTION_GAP, K.QLINE_H
local Count = K.Count

-- The first page of the list
local TODO = { key = "todo", name = "Quests you can do", isTodo = true }

local function Instances()
	local list = { TODO }
	for _, d in ipairs(K.SortedDungeons()) do list[#list + 1] = d end
	for _, r in ipairs(K.SortedRaids()) do list[#list + 1] = r end
	return list
end

local function SectionID(d, q)
	return "q:" .. d.key .. ":" .. (q.id or q.name)
end

-- A quest the quest log would show grey: too easy to be worth much
local function Trivial(q)
	if not q.level then return false end
	local player = UnitLevel("player") or 1
	return K.DifficultyKey(q.level) == "trivial" and q.level < player
end

-- Order on a page: what you can do first, then what's coming, then what's behind you
local ORDER = { active = 1, ready = 2, locked = 3, level = 4, done = 5, closed = 6 }

-- An instance's quests for your faction, race and class, with each one's status
local function QuestsOf(d)
	local out, other = {}, 0
	for _, q in ipairs(d.quests or {}) do
		local status, complete = ns.QuestStatus(q.id, q)
		if status == "other" then
			other = other + 1
		else
			out[#out + 1] = { q = q, status = status, complete = complete }
		end
	end
	table.sort(out, function(a, b)
		local oa, ob = ORDER[a.status] or 2, ORDER[b.status] or 2
		if oa ~= ob then return oa < ob end
		if (a.q.level or 0) ~= (b.q.level or 0) then return (a.q.level or 0) < (b.q.level or 0) end
		return a.q.name < b.q.name
	end)
	return out, other
end

-- What you can work on now: the quest itself (to pick up or in your log), or the quests before it
-- you can pick up now. Grey quests are left out, and counted. Worked out once a frame.
local function TodoOf(d)
	local c = ns.QuestCache().extra
	local key = "todo:" .. d.key
	if c[key] then return c[key][1], c[key][2] end
	local out, easy = {}, 0
	for _, e in ipairs((QuestsOf(d))) do
		local steps = (e.status == "ready" or e.status == "active" or e.status == "locked") and e.q.id
			and ns.QuestNextSteps(e.q.id, e.q) or {}
		if #steps > 0 then
			if Trivial(e.q) and e.status ~= "active" then
				easy = easy + 1
			else
				out[#out + 1] = { q = e.q, status = e.status, complete = e.complete, steps = steps }
			end
		end
	end
	c[key] = { out, easy }
	return out, easy
end

-- The "can do" page's lists: a quest two instances list (The Challenge, in Dire Maul and
-- Blackrock Depths) shows under the first one only
local function AllTodo()
	local c = ns.QuestCache().extra
	if c.allTodo then return c.allTodo end
	local all = { byInstance = {}, total = 0, places = 0, easy = 0 }
	local seen = {}
	for _, d in ipairs(Instances()) do
		if not d.isTodo then
			local list, easy = TodoOf(d)
			local kept = {}
			for _, e in ipairs(list) do
				local key = e.q.id or (d.key .. ":" .. e.q.name)
				if not seen[key] then
					seen[key] = true
					kept[#kept + 1] = e
				end
			end
			all.byInstance[d] = kept
			all.total, all.easy = all.total + #kept, all.easy + easy
			if #kept > 0 then all.places = all.places + 1 end
		end
	end
	c.allTodo = all
	return all
end

local function Counts(d)
	local todo, done, total = #(TodoOf(d)), 0, 0
	for _, e in ipairs((QuestsOf(d))) do
		total = total + 1
		if e.status == "done" then done = done + 1 end
	end
	return todo, done, total
end

----------------------------------------------------------------------
-- Rows
----------------------------------------------------------------------
-- A quest's header: its status mark, its name in the quest log's colors, and its status. Click
-- to open it (shift-click opens or closes them all).
local function CreateQuestHeader(parent, width)
	local w = K.kinds.wing.create(parent, width)
	w.status = w:CreateTexture(nil, "ARTWORK")
	w.status:SetSize(16, 16)
	w.status:SetPoint("LEFT", 8, 0)
	w.text:ClearAllPoints()
	w.text:SetPoint("LEFT", w.status, "RIGHT", 6, 0)
	w.text:SetPoint("RIGHT", w.levels, "LEFT", -10, 0)
	w:SetScript("OnEnter", function(self)
		local q = self.quest
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(q.name, C.white[1], C.white[2], C.white[3])
		local level = {}
		if q.level then level[#level + 1] = "Level " .. q.level end
		if q.req then level[#level + 1] = "requires level " .. q.req end
		if #level > 0 then GameTooltip:AddLine(table.concat(level, ", "), C.gold[1], C.gold[2], C.gold[3]) end
		K.AddQuestHowTo(q.id, q)
		GameTooltip:AddLine((UI:IsCollapsed(self.sectionId) and "Click to see how to get it." or "Click to close it.") ..
			" Shift-click opens or closes every quest.", C.silver[1], C.silver[2], C.silver[3], true)
		GameTooltip:Show()
	end)
	w:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return w
end

K.RegisterKind("qhead", CreateQuestHeader, function(w, d)
	K.kinds.wing.fill(w, d)
	w.quest = d.quest
	K.SetQuestIcon(w.status, d.status or "ready", d.complete)
	K.SetTextColor(w.text, d.quest.level and K.DifficultyColor(d.quest.level) or C.gold)
	K.SetTextColor(w.levels, d.rightColor or C.silver)
end)

-- Where to go for a quest: who starts it when you can pick it up, who takes it in when it's in
-- your log. Text for the line's right side, its color, and the giver for the pin button.
local function GoTo(q, status, complete)
	local info = q.id and ns.QuestInfo[q.id]
	if status == "active" then
		local to = info and (info.to or info.from)
		if to and to[1] == "item" then to = nil end
		if complete and to then return "Turn in: " .. ns.QuestGiverText(to), C.green, to end
		local text, color = K.QuestStatusText(status, complete, q.id, q)
		return text, color, to
	end
	local from = info and info.from
	if status == "ready" and from then
		return from[1] == "item" and ("from an item: " .. from[2]) or ns.QuestGiverText(from), C.silver, from
	end
	local text, color = K.QuestStatusText(status, complete, q.id, q)
	return text, color, status ~= "locked" and from or nil
end

-- A quest's own line on the "can do" page and in search results: opens it on its instance's page
local function QuestLine(d, q, status, complete, indent)
	local right, rightColor, giver = GoTo(q, status, complete)
	return { text = q.name, color = q.level and K.DifficultyColor(q.level) or C.gold, status = status or "ready",
		complete = complete, indent = indent, right = right, rightColor = rightColor, giver = giver, name = q.name,
		questID = q.id, click = function() UI:OpenQuest(d, q.id or q.name) end,
		hint = "Click to see it on " .. d.name .. "'s page." }
end

-- One of the quests before it: its status, name, and who starts it (who takes it in, once it's
-- in your log)
local function StepLine(id, indent, label)
	local info = ns.QuestInfo[id]
	local status, complete = ns.QuestStatus(id)
	local giver, right, rightColor = info and info.from, nil, nil
	if status == "active" then
		giver = info and (info.to or info.from)
		if giver and giver[1] == "item" then giver = nil end
		right = giver and ("Turn in: " .. ns.QuestGiverText(giver)) or "In your log"
		rightColor = complete and C.green or C.blue
	elseif giver then
		right = giver[1] == "item" and ("from an item: " .. giver[2]) or ns.QuestGiverText(giver)
	end
	local name = info and info.name or ("Quest " .. id)
	return { text = (label or "") .. name, color = info and info.level and K.DifficultyColor(info.level) or C.gold,
		status = status or "ready", complete = complete, indent = indent, right = right, rightColor = rightColor,
		giver = giver, name = name, questID = id, hint = "Click for its Wowhead link." }
end

----------------------------------------------------------------------
-- The tab
----------------------------------------------------------------------
local Quests = {
	key = "quests",
	tab = "Quests",
	icon = "Interface\\Icons\\INV_Misc_Book_08",
	listTitle = "Dungeons and raids",
	listRight = "Levels",
	allLabel = "All instances",
	unit = "quest",
	groupUnit = "instance",
	searchHint = "Search quests, e.g. defias",
	searchAbout = "The search looks at quest names, quest givers, zones and rewards.",
	noMatch = {
		"No quest matches that.",
		"Try a quest name like defias, a quest giver like Gryan, a zone like Westfall, or a reward like gloves.",
	},
	footer = "Click a quest: how to get it    Pin button: map pin on the quest giver    Click a step: Wowhead link",
	filters = true,
}

function Quests.dataDate()
	return ns.DATA_DATE
end

function Quests.Entries()
	return Instances()
end

-- A yellow "!" and how many quests you can work on now (narrow, so long names still fit); gold
-- names at your level
local TODO_MARK = "|TInterface\\GossipFrame\\AvailableQuestIcon:0|t"
function Quests.RowInfo(d)
	if d.isTodo then
		local n = AllTodo().total
		return d.name, "", n > 0 and (TODO_MARK .. n) or "", true, C.gold
	end
	local level = UnitLevel("player") or 0
	local todo = #(TodoOf(d))
	local levels = d.minLevel == d.maxLevel and tostring(d.minLevel) or (d.minLevel .. "-" .. d.maxLevel)
	return d.name, levels, todo > 0 and (TODO_MARK .. todo) or "",
		level >= d.minLevel and level <= d.maxLevel, C.gold, K.DifficultyColor(math.floor((d.minLevel + d.maxLevel) / 2))
end

function Quests.Default()
	local here = ns.CurrentDungeon()
	if here then return here end
	local last = ns.db.lastQuests
	if last == TODO.key then return TODO end
	if last and ns.DungeonByKey[last] then return ns.DungeonByKey[last] end
	return TODO
end

function Quests.Remember(d)
	ns.db.lastQuests = d.key
end

function Quests.WowheadLink(d)
	if d.isTodo or not (d.zone and d.zone ~= 0) then return d.name, nil end
	return d.name .. " on Wowhead", ns.WOWHEAD .. "zone=" .. d.zone
end

local LEGEND = "|TInterface\\GossipFrame\\AvailableQuestIcon:0|t you can take it   " ..
	"|TInterface\\GossipFrame\\IncompleteQuestIcon:0|t in your log   |A:common-icon-checkmark:0:0|a done. "

function Quests.ShowHeader(ui, h, d)
	h.name:SetText(d.name)
	h.badge.text:SetText("New in Forever")
	h.badge:SetWidth(h.badge.text:GetStringWidth() + 12)
	h.badge:SetShown(d.isNew and true or false)
	if d.isTodo then
		local all = AllTodo()
		local n, places, easy = all.total, all.places, all.easy
		h.meta:SetText(n > 0 and (Count(n, "quest") .. " in " .. Count(places, "instance")) or "Nothing to do right now")
		h.note:SetText("Dungeon and raid quests you can pick up, have in your log, or can work toward now: the next " ..
			"quest to pick up is under each. " .. (easy > 0 and (Count(easy, "grey quest") .. " too easy to bother with " ..
			(easy == 1 and "isn't" or "aren't") .. " listed. ") or "") .. "Data from cMaNGOS and Wowhead (" .. (ns.DATA_DATE or "") .. ").")
		return
	end
	local todo, done, total = Counts(d)
	local parts = { K.LevelText(d), Count(total, "quest") }
	if todo > 0 then parts[#parts + 1] = todo .. " to do" end
	if done > 0 then parts[#parts + 1] = done .. " done" end
	h.meta:SetText(table.concat(parts, "   ·   "))
	h.note:SetText(LEGEND .. "Open a quest for where it starts and the quests before it; the pin button puts a map pin on the quest giver.")
end

-- How to get one quest: where it starts and ends, any lead-in, the quests before it, its rewards
local function AddQuestDetails(ui, d, e)
	local q, info = e.q, e.q.id and ns.QuestInfo[e.q.id]
	ui:AddGap(2)
	local start = K.QuestStartLine(q)
	if start then
		start.right, start.indent = nil, 8
		ui:AddEntry("qline", QLINE_H, start)
	else
		ui:AddEntry("qline", QLINE_H, { text = "Where it starts isn't on Wowhead yet.", color = C.grey, indent = 8 })
	end
	if info and info.to then
		ui:AddEntry("qline", QLINE_H, { text = "Turn in: " .. ns.QuestGiverText(info.to), color = C.white, indent = 8,
			giver = info.to, name = q.name, tipTitle = q.name })
	end
	if e.status ~= "done" then
		for _, lead in ipairs(info and info.lead or {}) do
			local status = ns.QuestStatus(lead)
			if status ~= "done" and status ~= "other" then
				ui:AddEntry("qline", QLINE_H, StepLine(lead, 8, "Lead-in (optional): "))
			end
		end
	end
	local chain = q.id and ns.QuestChain(q.id) or {}
	if #chain > 0 then
		local done = 0
		for _, id in ipairs(chain) do
			if ns.QuestStatus(id) == "done" then done = done + 1 end
		end
		ui:AddEntry("qline", QLINE_H, { text = "Before it, in order: " .. Count(#chain, "quest") ..
			(done > 0 and (", " .. done .. " done") or ""), color = C.gold, indent = 8 })
		for _, id in ipairs(chain) do ui:AddEntry("qline", QLINE_H, StepLine(id, 18)) end
	end
	local choices = K.VisibleItems(q.choices or {})
	local rewards = K.VisibleItems(q.rewards or {})
	if #choices + #rewards > 0 then
		ui:AddEntry("qline", QLINE_H, { text = #choices > 1 and ("Rewards: choose 1 of " .. #choices ..
			(#rewards > 0 and (", plus " .. #rewards) or "")) or "Rewards", color = C.gold, indent = 8 })
		for _, itemID in ipairs(choices) do ui:AddEntry("item", ITEM_H, { itemID = itemID }) end
		for _, itemID in ipairs(rewards) do ui:AddEntry("item", ITEM_H, { itemID = itemID }) end
	end
	ui:AddGap(SECTION_GAP)
end

local function RenderTodo(ui)
	local any = false
	local all = AllTodo()
	for _, d in ipairs(Instances()) do
		local todo = all.byInstance[d] or {}
		if #todo > 0 then
			any = true
			if ui.contentY > 0 then ui:AddGap(SECTION_GAP) end
			if not ui:AddSection("t:" .. d.key, d.name, Count(#todo, "quest") .. "   ·   " .. K.LevelText(d)) then
				ui:AddGap(2)
				for _, e in ipairs(todo) do
					ui:AddEntry("qline", QLINE_H, QuestLine(d, e.q, e.status, e.complete, 0))
					-- the quest itself is the step when you can take it or have it
					if not (e.status == "ready" or e.status == "active") then
						for _, step in ipairs(e.steps) do
							ui:AddEntry("qline", QLINE_H, StepLine(step.id, 18, "Next: "))
						end
					end
				end
			end
		end
	end
	if not any then
		ui:AddEntry("note", NOTE_H, { text = "No dungeon or raid quest to pick up or work toward right now." })
		ui:AddEntry("note", NOTE_H, { text = "Pick a dungeon or raid on the left to see all its quests and how to get them." })
	end
end

function Quests.Render(ui, d)
	if d.isTodo then return RenderTodo(ui) end
	local list, other = QuestsOf(d)
	for _, e in ipairs(list) do
		local text, color = K.QuestStatusText(e.status, e.complete, e.q.id, e.q)
		if not ui:AddSection(SectionID(d, e.q), e.q.name, text or "", "qhead",
			{ quest = e.q, status = e.status, complete = e.complete, rightColor = color }) then
			AddQuestDetails(ui, d, e)
		end
	end
	if #list == 0 then
		ui:AddEntry("note", NOTE_H, { text = "No quests here for your character." })
	end
	if other > 0 then
		ui:AddEntry("note", NOTE_H, { text = Count(other, "quest") .. " for another faction, race or class " ..
			(other == 1 and "isn't" or "aren't") .. " shown." })
	end
end

-- What a quest's search looks at: its name, who starts and ends it, their zones
local function QuestWords(q)
	local info = q.id and ns.QuestInfo[q.id]
	local words = { q.name }
	for _, giver in ipairs({ info and info.from, info and info.to }) do
		if giver then words[#words + 1] = ns.QuestGiverText(giver) end
	end
	return K.Simplify(table.concat(words, " "))
end

function Quests.Find(filter)
	local terms = K.ParseQuery(filter.text)
	local byItem = filter.slot or filter.kind
	local groups, total = {}, 0
	for _, d in ipairs(Instances()) do
		local rows = {}
		for _, e in ipairs(not d.isTodo and (QuestsOf(d)) or {}) do
			local q, hit = e.q, false
			local words = QuestWords(q)
			if not byItem then
				hit = true
				for _, t in ipairs(terms) do
					if not words:find(t, 1, true) then hit = false end
				end
			end
			if not hit then
				for _, list in ipairs({ q.choices or {}, q.rewards or {} }) do
					for _, itemID in ipairs(list) do
						if K.Visible(itemID) and K.Matches(K.SearchInfo(itemID), terms, filter, words) then hit = true end
					end
				end
			end
			if hit then rows[#rows + 1] = QuestLine(d, q, e.status, e.complete, 0) end
		end
		if #rows > 0 then
			groups[#groups + 1] = { entry = d, rows = rows }
			total = total + #rows
		end
	end
	return groups, total
end

function Quests.AddResults(ui, g)
	if ui.contentY > 0 then ui:AddGap(SECTION_GAP) end
	local d = g.entry
	if ui:AddSection("s:q:" .. d.key, d.name, Count(#g.rows, "quest") .. "   ·   " .. K.LevelText(d)) then return end
	for _, r in ipairs(g.rows) do ui:AddEntry("qline", QLINE_H, r) end
end

UI:RegisterMode(Quests)

-- Opens a quest on its instance's page in this tab, its section open and at the top
function UI:OpenQuest(d, key)
	if not (self.frame and self.frame:IsShown()) then self:Show() end
	if self:IsSearching() then self:ResetFilter() end
	local id = "q:" .. d.key .. ":" .. key
	self.sections[id] = true
	self:SetMode("quests", true)
	self:Select(d)
	for _, e in ipairs(self.entries or {}) do
		if e.data and e.data.id == id then
			self.loot:ScrollTo(e.y)
			self:Paint()
			break
		end
	end
end

-- Quest progress changes what each quest's status is: redraw the open page (once, when the burst
-- of quest log events settles)
local pending = false
local events = CreateFrame("Frame")
for _, event in ipairs({ "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_REMOVED", "PLAYER_LEVEL_UP" }) do
	events:RegisterEvent(event)
end
events:SetScript("OnEvent", function()
	if pending or not (UI.frame and UI.frame:IsShown()) then return end
	local mode = UI.mode
	if mode ~= "quests" and mode ~= "dungeons" and mode ~= "raids" then return end
	pending = true
	C_Timer.After(0.5, function()
		pending = false
		if not (UI.frame and UI.frame:IsShown()) then return end
		UI:Refresh()
		if not UI:IsSearching() and UI.current then UI:Mode().ShowHeader(UI, UI.header, UI.current) end
		UI:BuildList()
	end)
end)
