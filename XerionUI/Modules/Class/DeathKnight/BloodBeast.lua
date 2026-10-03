--------------------------------------------------------------------------------
-- Bloodbeast damage (San'layn: Blood and Unholy)
-- "Bloodbeast: 12.5M" for the damage the beast did after Dancing Rune Weapon
-- (Blood) or Dark Transformation (Unholy), from Blizzard's damage meter: your
-- Overall damage done for the beast's spell, compared with the reading before
-- the cast. The meter is secret in combat, so after a fight it is read and the
-- number shows for 10 seconds.
--------------------------------------------------------------------------------
local XUI = select(2, ...).XUI
local T = XUI.Templates
local Kit = XUI.ClassKit

local BEAST = 434237

local M = XUI:NewModule("BloodBeast", {
	name = "Bloodbeast Damage",
	desc = "The damage your Bloodbeast did, from the damage meter.",
	category = "class",
	icon = 1392565,
	order = 50,
	classes = { "DEATHKNIGHT" },
	specs = { 250, 252 },
	untested = true,
	defaults = {
		font = T.Font(22),
		labelColor = { 0.9, 0.12, 0.12, 1 },
		valueColor = { 1, 1, 1, 1 },
		position = T.Position(0, -160),
	},
})

Kit.Meter(M, {
	frame = "XUI_BloodBeast",
	label = "Bloodbeast:",
	settle = 12,
	showFor = 10,
	count = function(id) return id == BEAST end,
	isTrigger = Kit.IsSanlaynTrigger,
})

function M:OnEnable() self:StartMeterEvents() end
