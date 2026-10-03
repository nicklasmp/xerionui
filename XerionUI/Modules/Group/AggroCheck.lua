--------------------------------------------------------------------------------
-- Aggro Check
-- One big word in the middle of the screen when a mob is on you and you are
-- not the tank: a dps or healer usually finds out from their health bar.
--
-- UnitThreatSituation("player") - the one-token form - is "generally not
-- secret" (Blizzard's raid frames rely on it). Should it come back secret
-- anyway the text stays hidden: a signal that fails open would shout AGGRO at
-- someone who has none. The role comes from the spec, not the group role.
--------------------------------------------------------------------------------
local XUI = select(2, ...).XUI
local T = XUI.Templates

local M = XUI:NewModule("AggroCheck", {
	name = "Aggro Check",
	desc = "Warns you when a mob is attacking you and you are not the tank.",
	category = "group",
	icon = [[Interface\Icons\Ability_Warrior_Challange]],
	order = 70,
	defaults = {
		text = "AGGRO",
		color = { 1, 0.15, 0.15, 1 },
		pulse = true,
		keyOnly = true,
		font = T.Font(32),
		alert = T.Alert("SOUND", { sound = "WoW: Raid Warning" }),
		position = T.Position(0, 180, "HIGH"),
	},
})

local display
local inCombat = false

local function Display()
	if display then return display end
	display = XUI.Widgets:CreateText("XUI_AggroCheck")
	display:Hide()
	-- C-side animation: no Lua per frame
	local pulse = display:CreateAnimationGroup()
	pulse:SetLooping("BOUNCE")
	local a = pulse:CreateAnimation("Alpha")
	a:SetFromAlpha(1)
	a:SetToAlpha(0.35)
	a:SetDuration(0.45)
	a:SetSmoothing("IN_OUT")
	display.pulse = pulse
	XUI.Movers:Register(display, M, "position")
	return display
end

local function HasAggro()
	if not UnitThreatSituation then return false end
	local ok, status = pcall(UnitThreatSituation, "player")
	if not ok or XUI.IsSecret(status) then return false end
	return type(status) == "number" and status >= 2
end

local function ShouldShow()
	if not (M.running and inCombat) then return false end
	if M.db.keyOnly and not XUI.KeyActive() then return false end
	if XUI.PlayerIsTank(false) then return false end
	return HasAggro()
end

function M:Update()
	if not display then return end
	local show = self:IsPreview() or ShouldShow()
	if show then
		if not display:IsShown() then
			display:Show()
			if not self:IsPreview() then XUI.Audio:Play(self.db.alert, self.db.text) end
		end
		if self.db.pulse then
			if not display.pulse:IsPlaying() then display.pulse:Play() end
		else
			display.pulse:Stop()
			display:SetAlpha(1)
		end
	else
		display.pulse:Stop()
		display:SetAlpha(1)
		display:Hide()
	end
end

-- the warning and its alert for three seconds
function M:Test()
	if not self:RequireRunning() then return end
	local d = Display()
	self:Refresh()
	d:Show()
	XUI.Audio:Play(self.db.alert, self.db.text, true)
	if self.db.pulse then d.pulse:Play() end
	self:After(3, function() if not self:IsPreview() then self:Update() end end)
end

function M:OnEnable()
	Display()
	inCombat = XUI.Ask(UnitAffectingCombat, "player") == true
	self:RegisterUnitEvent("UNIT_THREAT_SITUATION_UPDATE", "player", "Update")
	self:RegisterEvent("PLAYER_REGEN_DISABLED", function(self) inCombat = true self:Update() end)
	self:RegisterEvent("PLAYER_REGEN_ENABLED", function(self) inCombat = false self:Update() end)
	self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", "Update")
	self:RegisterEvent("CHALLENGE_MODE_START", "Update")
	self:RegisterEvent("CHALLENGE_MODE_COMPLETED", "Update")
	self:RegisterEvent("CHALLENGE_MODE_RESET", "Update")
end

function M:OnRefresh()
	if not (display or self:IsPreview()) then return end
	local d, db = Display(), self.db
	XUI.Movers:Apply(d)
	d:ApplyStyle(db.font)
	d:SetText(db.text)
	d:SetTextColor(XUI.UnpackColor(db.color))
	self:Update()
end
