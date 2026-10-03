--------------------------------------------------------------------------------
-- Control Undead
-- The charm lasts five minutes: an icon with the time left (m:ss), red in the
-- last 30 seconds, gone when the minion is.
--------------------------------------------------------------------------------
local XUI = select(2, ...).XUI
local T = XUI.Templates
local Kit = XUI.ClassKit

local SPELL, FALLBACK, DURATION = 111673, 237511, 300

local M = XUI:NewModule("ControlUndead", {
	name = "Control Undead",
	desc = "The time left on your Control Undead minion.",
	category = "class",
	icon = FALLBACK,
	order = 60,
	classes = { "DEATHKNIGHT" },
	untested = true,
	defaults = {
		icon = T.Icon(44),
		border = T.Border(),
		timerText = T.Font(18, { enabled = true, color = { 1, 1, 1, 1 } }),
		showSwipe = true,
		hideOnPetLost = true,
		warnAt = 30,
		warnColor = { 1, 0.3, 0.3, 1 },
		position = T.Position(0, -160),
	},
})

local petGUID, castAt = nil, 0

Kit.TimedIcon(M, {
	frame = "XUI_ControlUndead",
	icon = function() return XUI.GetSpellIcon(SPELL, FALLBACK) end,
	duration = DURATION,
	previewSeconds = 137,
})

function M:OnTick(left, display)
	local db = self.db
	local c = (left <= (db.warnAt or 30)) and db.warnColor or XUI.Style:Resolve("font", db.timerText).color
	display.timer:SetTextColor(XUI.UnpackColor(c))
end

local function MinionLost()
	local exists = XUI.Ask(UnitExists, "pet")
	if exists == nil then return false end
	if not exists then return true end
	if petGUID then
		local ok, guid = pcall(UnitGUID, "pet")
		if ok and guid and not XUI.IsSecret(guid) then return guid ~= petGUID end
	end
	return false
end

function M:OnEnable()
	self:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player", function(self, _, _, _, spellID)
		if XUI.IsSecret(spellID) or spellID ~= SPELL then return end
		castAt, petGUID = GetTime(), nil
		self:Start(DURATION)
		self:After(0.4, function()
			local ok, guid = pcall(UnitGUID, "pet")
			petGUID = (ok and guid and not XUI.IsSecret(guid)) and guid or nil
		end)
	end)
	self:RegisterUnitEvent("UNIT_PET", "player", function(self)
		if self.db.hideOnPetLost and self:IsActive() and GetTime() - castAt > 0.5 and MinionLost() then self:Clear() end
	end)
	self:RegisterEvent("PLAYER_ENTERING_WORLD", "Clear")
end
