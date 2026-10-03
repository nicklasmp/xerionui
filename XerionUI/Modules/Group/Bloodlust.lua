--------------------------------------------------------------------------------
-- Bloodlust Ready
-- A sound or spoken alert the moment Sated (or its class twin) runs out, so
-- you know lust can be used again.
--
-- Cheap on purpose: Sated cannot be refreshed, clicked off or dispelled, so
-- once it is found with a readable expiration nothing can change before that
-- moment - aura events are ignored until then and one timer looks again just
-- after it. A secret expiration keeps looking on every aura event that could
-- have added or removed an aura.
--------------------------------------------------------------------------------
local XUI = select(2, ...).XUI
local T = XUI.Templates

local M = XUI:NewModule("Bloodlust", {
	name = "Bloodlust Ready",
	desc = "Plays an alert when your Sated debuff runs out.",
	category = "group",
	icon = [[Interface\Icons\Spell_Nature_BloodLust]],
	order = 80,
	defaults = {
		alert = T.Alert("SOUND", { sound = "WoW: Raid Warning", text = "Bloodlust ready" }),
	},
})

local GPA = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
local SATED = XUI.SATED_IDS
local IsSecret = XUI.IsSecret

function M:CanLoad()
	if not GPA then return false, "Not supported by this client." end
	return true
end

-- Loading screens and a key's countdown remove and re-add auras; an alert
-- right after one would be a false "ready".
local suppressUntil = 0
local function Suppress(secs)
	local t = GetTime() + (secs or 6)
	if t > suppressUntil then suppressUntil = t end
end

local active, expires = false, nil
local lastIndex
local endTimer

local function CurrentSated()
	if lastIndex then
		local a = GPA(SATED[lastIndex])
		if a then return a end
	end
	for i = 1, #SATED do
		if i ~= lastIndex then
			local a = GPA(SATED[i])
			if a then
				lastIndex = i
				return a
			end
		end
	end
	return nil
end

local function Read()
	local a = CurrentSated()
	if a then
		local exp = a.expirationTime
		return true, (not IsSecret(exp)) and exp or nil
	end
	return false, nil
end

function M:Check()
	local now, exp = Read()
	if now then
		active, expires = true, exp
	elseif active then
		active, expires = false, nil
		if GetTime() >= suppressUntil then XUI.Audio:Play(self.db.alert, "Bloodlust ready") end
	end
	self:ArmEnd()
end

-- one look just after a readable expiration
function M:ArmEnd()
	if endTimer then self:CancelTicker(endTimer) endTimer = nil end
	if active and expires then
		local rem = math.max(0, expires - GetTime()) + 0.1
		endTimer = self:NewTicker(rem, function(self)
			endTimer = nil
			self:Check()
		end, 1)
	end
end

function M:OnEnable()
	active, expires = Read()
	self:ArmEnd()
	self:RegisterUnitEvent("UNIT_AURA", "player", function(self, _, _, info)
		if active and expires and GetTime() < expires then return end
		if (not active or expires) and not XUI.AuraPayloadChurns(info) then return end
		self:Check()
	end)
	self:RegisterEvent("PLAYER_ENTERING_WORLD", function(self)
		Suppress(6)
		active, expires = Read()
		self:ArmEnd()
	end)
	self:RegisterEvent("CHALLENGE_MODE_START", function() Suppress(6) end)
	self:RegisterEvent("CHALLENGE_MODE_RESET", function() Suppress(6) end)
	self:RegisterEvent("START_TIMER", function(_, _, _, secs)
		Suppress(math.min(30, tonumber(secs) or 10) + 5)
	end)
end

function M:OnDisable()
	endTimer = nil
end

function M:TestAlert()
	XUI.Audio:Play(self.db.alert, "Bloodlust ready", true)
end
