local ADDON, ns = ...
local C = ns.COLORS

-- Where an item comes from, on every item tooltip in the game: bags, chat links, the
-- auction house, loot windows. Which bosses drop it, which quest gives it, which
-- profession makes it. /fl tooltip turns it off. The addon's own item rows are skipped:
-- they already say where their item comes from.

local MAX_LINES = 4
local KIND_ORDER = { boss = 1, quest = 2, trash = 3, unconfirmed = 4, craft = 5 }

local function Pct(p)
	return (("%.1f"):format(p):gsub("%.0$", "")) .. "%"
end

-- { left, right } for one source
local function Describe(s)
	local d = s.instance
	local where = d and (d.name .. (s.boss and s.boss.wing and (": " .. s.boss.wing) or "")) or ""
	if s.kind == "boss" then
		return s.boss.name, where .. (s.pct and ("  " .. Pct(s.pct)) or "")
	elseif s.kind == "trash" then
		return "Trash mobs", where
	elseif s.kind == "unconfirmed" then
		return "Boss not confirmed", where
	elseif s.kind == "quest" then
		return "Quest: " .. s.quest.name, where
	elseif s.kind == "craft" then
		local skill = s.recipe.skill and (" (" .. s.recipe.skill .. ")") or ""
		return "Made by " .. s.profession.name .. skill, ""
	end
end

-- The lines to add for an item, best sources first
function ns.TooltipLines(itemID)
	local sources = ns.SourcesOf(itemID)
	if #sources == 0 then return nil end
	local sorted = {}
	for i, s in ipairs(sources) do sorted[i] = s end
	table.sort(sorted, function(a, b)
		if a.kind ~= b.kind then return KIND_ORDER[a.kind] < KIND_ORDER[b.kind] end
		if (a.pct or 0) ~= (b.pct or 0) then return (a.pct or 0) > (b.pct or 0) end
		local la, lb = a.instance and a.instance.minLevel or 0, b.instance and b.instance.minLevel or 0
		return la < lb
	end)
	local lines, seen = {}, {}
	for _, s in ipairs(sorted) do
		local left, right = Describe(s)
		local key = left .. "\0" .. right
		if not seen[key] then
			seen[key] = true
			lines[#lines + 1] = { left, right }
		end
	end
	if #lines > MAX_LINES then
		local more = #lines - (MAX_LINES - 1)
		for i = #lines, MAX_LINES, -1 do lines[i] = nil end
		lines[MAX_LINES] = { "and " .. more .. " more places", "" }
	end
	return lines
end

local function IsSecret(v)
	return issecretvalue ~= nil and issecretvalue(v)
end

local function AddSources(tooltip, itemID)
	if not (ns.db and ns.db.tooltip) or not itemID or IsSecret(itemID) then return false end
	local owner = tooltip.GetOwner and tooltip:GetOwner()
	if owner and owner.isForeverLootItem then return false end
	-- Some tooltips report the same item twice; add the lines once
	if tooltip.foreverLootItem == itemID then return false end
	local lines = ns.TooltipLines(itemID)
	if not lines then return false end
	tooltip.foreverLootItem = itemID
	tooltip:AddLine(ns.name, C.red[1], C.red[2], C.red[3])
	for _, l in ipairs(lines) do
		if l[2] ~= "" then
			tooltip:AddDoubleLine(l[1], l[2], C.light[1], C.light[2], C.light[3], C.mist[1], C.mist[2], C.mist[3])
		else
			tooltip:AddLine(l[1], C.light[1], C.light[2], C.light[3])
		end
	end
	return true
end

local function ItemIDFromLink(link)
	if not link or IsSecret(link) then return nil end
	return tonumber(link:match("item:(%d+)"))
end

local function Hook(tooltip)
	if not tooltip or tooltip.foreverLootHooked or not tooltip.HookScript then return end
	tooltip.foreverLootHooked = true
	pcall(tooltip.HookScript, tooltip, "OnTooltipCleared", function(self) self.foreverLootItem = nil end)
	-- Clients without TooltipDataProcessor tell us about items this way
	if not (TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall) then
		pcall(tooltip.HookScript, tooltip, "OnTooltipSetItem", function(self)
			local _, link = self:GetItem()
			if AddSources(self, ItemIDFromLink(link)) then self:Show() end
		end)
	end
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function()
	Hook(GameTooltip)
	Hook(ItemRefTooltip)
	if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
			if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
			local itemID = data and data.id
			if IsSecret(itemID) then return end
			if not itemID and tooltip.GetItem then
				itemID = ItemIDFromLink(select(2, tooltip:GetItem()))
			end
			AddSources(tooltip, itemID)
		end)
	end
end)
