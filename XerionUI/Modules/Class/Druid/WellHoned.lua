--------------------------------------------------------------------------------
-- Well-Honed Instincts (Druid, every spec)
-- The cheat death casts Frenzied Regeneration for you and leaves a debuff
-- (382912) while it cannot do that again. A sound the moment that debuff lands
-- and, if one is picked, another when it falls off.
--
-- The game's own C_UnitAuras.AddAuraSound on "player", one registration per
-- sound: the engine plays the file when the aura comes or goes, so Lua never
-- reads the aura and it works in keys and raids where the aura is secret. The
-- client refuses NEW registrations during a boss encounter and in combat
-- inside a key, so they are made at login and on a settings change and kept;
-- one that had to wait is made when the fight or the encounter ends.
--------------------------------------------------------------------------------
local XUI = select(2, ...).XUI

local SPELL = 382912

local M = XUI:NewModule("WellHoned", {
	name = "Well-Honed Instincts",
	desc = "A sound when the Well-Honed Instincts lockout lands or ends.",
	category = "class",
	icon = [[Interface\Icons\Spell_Nature_Regeneration]],
	order = 30,
	classes = { "DRUID" },
	untested = true,
	defaults = {
		sound = "Xerion: External",
		endSound = "None",
		channel = "Master",
	},
})

local TRIGGERS = { { key = "sound", enum = "Added" }, { key = "endSound", enum = "Removed" } }
local reg, pending = {}, false

local function API()
	local api = C_UnitAuras
	if not (api and api.AddAuraSound and api.RemoveAuraSound) then return nil end
	if not (Enum and Enum.UnitAuraSoundTrigger) then return nil end
	return api
end

local function Wanted(db)
	local out = {}
	if not M.running then return out end
	for _, t in ipairs(TRIGGERS) do
		local path = XUI.Audio:SoundFile(db[t.key])
		local trigger = Enum.UnitAuraSoundTrigger[t.enum]
		if path and trigger then out[t.key] = { trigger = trigger, path = path, channel = db.channel } end
	end
	return out
end

local function Sync()
	local api = API()
	if not api then return end
	local want = Wanted(M.db)
	for k, live in pairs(reg) do
		local w = want[k]
		if not w or w.path ~= live.path or w.channel ~= live.channel then
			pcall(api.RemoveAuraSound, live.id)
			reg[k] = nil
		end
	end
	pending = false
	local blocked = XUI.AuraSoundsBlocked()
	for k, w in pairs(want) do
		if not reg[k] then
			if blocked then
				pending = true
			else
				local ok, id = pcall(api.AddAuraSound, w.trigger, {
					unitToken = "player", spellID = SPELL, soundFileName = w.path, outputChannel = w.channel,
				})
				if ok and id then reg[k] = { id = id, path = w.path, channel = w.channel } else pending = true end
			end
		end
	end
	if pending then
		pcall(M.RegisterEvent, M, "PLAYER_REGEN_ENABLED", "Sync")
		pcall(M.RegisterEvent, M, "ADDON_RESTRICTION_STATE_CHANGED", "Sync")
	end
end

-- the restriction still reads its old answer while its own event is handed out
local SyncSoon = XUI.Coalesce(Sync)
function M:Sync() SyncSoon() end

function M:OnEnable() SyncSoon() end

function M:OnDisable()
	local api = API()
	if api then
		for k, live in pairs(reg) do
			pcall(api.RemoveAuraSound, live.id)
			reg[k] = nil
		end
	end
end

function M:OnRefresh() if self.running then SyncSoon() end end

function M:Test(key)
	XUI.Audio:PlaySound(self.db[key or "sound"], self.db.channel)
end

function M:DebugInfo()
	local lines = { ("engine sounds available: %s, waiting: %s"):format(tostring(API() ~= nil), tostring(pending)) }
	for _, t in ipairs(TRIGGERS) do
		lines[#lines + 1] = ("%s: %s, %s"):format(t.enum, tostring(self.db[t.key]), reg[t.key] and "registered" or "not registered")
	end
	return lines
end
