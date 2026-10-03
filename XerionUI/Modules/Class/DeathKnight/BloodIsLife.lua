--------------------------------------------------------------------------------
-- The Blood is Life (San'layn: Blood and Unholy)
-- A 10 second icon after Dancing Rune Weapon (Blood) or Dark Transformation
-- (Unholy): the window the Vampiric Strike beast is out. Counted on our own
-- clock from the cast; the cast spell ID of your own spells is readable.
--------------------------------------------------------------------------------
local XUI = select(2, ...).XUI
local T = XUI.Templates
local Kit = XUI.ClassKit

local ICON, DURATION = 2032221, 10

local M = XUI:NewModule("BloodIsLife", {
	name = "The Blood is Life",
	desc = "An icon for the 10 seconds after Dancing Rune Weapon or Dark Transformation.",
	category = "class",
	icon = ICON,
	order = 40,
	classes = { "DEATHKNIGHT" },
	specs = { 250, 252 },
	untested = true,
	defaults = {
		icon = T.Icon(44),
		border = T.Border({ useGlobal = false, style = "SOLID", size = 1, color = { 0.77, 0.12, 0.23, 1 } }),
		glow = T.Glow(true, { useGlobal = false, type = "PIXEL", color = { 1, 0.16, 0.16, 1 }, thickness = 1 }),
		timerText = T.Font(16, { enabled = false }),
		showSwipe = true,
		position = T.Position(0, -210),
	},
})

Kit.TimedIcon(M, { frame = "XUI_BloodIsLife", icon = ICON, duration = DURATION, previewSeconds = 6 })

function M:OnEnable()
	self:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player", function(self, _, _, _, spellID)
		if Kit.IsSanlaynTrigger(spellID) then self:Start(DURATION) end
	end)
	self:RegisterEvent("PLAYER_ENTERING_WORLD", "Clear")
end
