--------------------------------------------------------------------------------
-- Combat Alert
-- A short text when you enter and leave combat, with an optional sound or
-- spoken alert for each.
-- Ported from ItruliaQoL (MIT, (c) Itrulia).
--------------------------------------------------------------------------------
local XUI = select(2, ...).XUI
local T = XUI.Templates

local M = XUI:NewModule("CombatAlert", {
	name = "Combat Alert",
	desc = "Shows a short text when you enter and leave combat.",
	category = "general",
	icon = 132147, -- Ability_DualWield
	order = 10,
	defaults = {
		enterText = "+ Combat",
		enterColor = { 0.98, 1, 0, 1 },
		leaveText = "- Combat",
		leaveColor = { 0.53, 1, 0, 1 },
		hold = 1.5,
		fade = 1,
		text = T.Font(22),
		enterAlert = T.Alert(),
		leaveAlert = T.Alert(),
		position = T.Position(0, 220),
	},
})

local display

local function Display()
	if display then return display end
	display = XUI.Widgets:CreateText("XUI_CombatAlert")
	display:Hide()
	local anim = display:CreateAnimationGroup()
	display.fadeOut = anim:CreateAnimation("Alpha")
	display.fadeOut:SetFromAlpha(1)
	display.fadeOut:SetToAlpha(0)
	anim:SetScript("OnFinished", function() display:Hide() end)
	display.anim = anim
	XUI.Movers:Register(display, M, "position")
	return display
end

-- Shows the enter or leave text; `hold` keeps it up (preview).
function M:ShowText(entering, hold)
	local d, db = Display(), self.db
	d.anim:Stop()
	d:ApplyStyle(db.text)
	d:SetText(entering and db.enterText or db.leaveText)
	d:SetTextColor(XUI.UnpackColor(entering and db.enterColor or db.leaveColor))
	d:SetAlpha(1)
	d:Show()
	if not hold then
		d.fadeOut:SetStartDelay(db.hold)
		d.fadeOut:SetDuration(math.max(0.05, db.fade))
		d.anim:Play()
	end
end

function M:OnEnable()
	Display() -- so the mover exists before the first pull
	self:RegisterEvent("PLAYER_REGEN_DISABLED", function(self)
		self:ShowText(true, self:IsPreview())
		XUI.Audio:Play(self.db.enterAlert, self.db.enterText)
	end)
	self:RegisterEvent("PLAYER_REGEN_ENABLED", function(self)
		self:ShowText(false, self:IsPreview())
		XUI.Audio:Play(self.db.leaveAlert, self.db.leaveText)
	end)
end

function M:OnRefresh()
	if self:IsPreview() then
		self:ShowText(true, true)
		XUI.Movers:Apply(display)
		return
	end
	if not display then return end
	XUI.Movers:Apply(display)
	if self:IsRunning() and display.anim:IsPlaying() then
		display:ApplyStyle(self.db.text)
	else
		display.anim:Stop()
		display:Hide()
	end
end
