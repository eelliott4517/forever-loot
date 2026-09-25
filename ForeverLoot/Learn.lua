local ADDON, ns = ...

-- Wowhead's Forever data is still filling in during the beta. When you loot a
-- boss, any rare-or-better item it drops is remembered under that boss so the
-- loot tables fill in as you play. Stored per account in ForeverLootDB.learned.

local Learn = {}
ns.Learn = Learn

local MIN_QUALITY = 3          -- rare (blue) and up; skips random greens and trade goods
local ENCOUNTER_WINDOW = 180   -- seconds after a boss kill that unknown loot is credited to it

local QUALITY_BY_HEX = {}
for q, hex in pairs(ns.QUALITY_HEX) do QUALITY_BY_HEX[hex] = q end

local seen = {}

local function NPCFromGUID(guid)
	-- Forever can hand out secret GUIDs, which can't be read; skip those
	if type(guid) ~= "string" or (issecretvalue and issecretvalue(guid)) then return end
	local unitType, _, _, _, _, npcID = strsplit("-", guid)
	if unitType == "Creature" or unitType == "Vehicle" then
		return tonumber(npcID)
	end
end

local function QualityOf(link)
	local quality = select(3, ns.GetItemInfo(link))
	if quality then return quality end
	local hex = link:match("|c%x%x(%x%x%x%x%x%x)")
	return hex and QUALITY_BY_HEX[hex:lower()]
end

-- Bucket keys: "npc:<id>" for a boss we know, "enc:<name>" for one we only know from the encounter
function Learn.KeysForBoss(boss)
	local keys = { "enc:" .. ns.Normalize(boss.name) }
	for _, npcID in ipairs(boss.npc or {}) do
		keys[#keys + 1] = "npc:" .. npcID
	end
	return keys
end

local function Record(dungeon, key, bossName, itemID)
	local byDungeon = ns.db.learned[dungeon.key]
	if not byDungeon then
		byDungeon = {}
		ns.db.learned[dungeon.key] = byDungeon
	end
	local bucket = byDungeon[key]
	if not bucket then
		bucket = { name = bossName, items = {} }
		byDungeon[key] = bucket
	end
	bucket.items[itemID] = (bucket.items[itemID] or 0) + 1
end

local function BossByName(dungeon, name)
	local wanted = ns.Normalize(name)
	for _, b in ipairs(dungeon.bosses) do
		if not b.trash and ns.Normalize(b.name) == wanted then return b end
	end
end

function Learn:OnEncounterEnd(_, encounterName, _, _, success)
	if success ~= 1 and success ~= true then return end
	local dungeon = ns.CurrentDungeon()
	if dungeon and encounterName then
		self.last = { name = encounterName, dungeon = dungeon, time = GetTime() }
	end
end

function Learn:OnLootOpened()
	local dungeon = ns.CurrentDungeon()
	if not dungeon then return end
	local changed = false

	for slot = 1, GetNumLootItems() do
		local link = GetLootSlotLink(slot)
		if link and issecretvalue and issecretvalue(link) then link = nil end
		local itemID = link and tonumber(link:match("item:(%d+)"))
		if itemID and (QualityOf(link) or 0) >= MIN_QUALITY then
			local sources = GetLootSourceInfo and { GetLootSourceInfo(slot) } or {}
			if #sources == 0 then sources = { UnitGUID("target"), 1 } end
			for i = 1, #sources, 2 do
				local guid = sources[i]
				local npcID = NPCFromGUID(guid)
				local dedupe = npcID and (guid .. ":" .. itemID)
				if npcID and not seen[dedupe] then
					seen[dedupe] = true
					local boss = ns.BossByNPC[npcID]
					if boss and boss.dungeon == dungeon then
						Record(dungeon, "npc:" .. npcID, boss.name, itemID)
						changed = true
					elseif self.last and self.last.dungeon == dungeon and GetTime() - self.last.time <= ENCOUNTER_WINDOW then
						local named = BossByName(dungeon, self.last.name)
						Record(dungeon, "enc:" .. ns.Normalize(self.last.name), named and named.name or self.last.name, itemID)
						changed = true
					end
				end
			end
		end
	end

	if changed then ns.UI:Refresh() end
end

function Learn:Init()
	local f = CreateFrame("Frame")
	f:RegisterEvent("LOOT_OPENED")
	-- Registering an event the client doesn't know throws, so don't let this one break login
	pcall(f.RegisterEvent, f, "ENCOUNTER_END")
	f:SetScript("OnEvent", function(_, event, ...)
		if event == "LOOT_OPENED" then
			Learn:OnLootOpened()
		else
			Learn:OnEncounterEnd(...)
		end
	end)
end
