--------------------------------------------------------------------------------
-- Bear Form reminder (Guardian)
-- One line of text for as long as you are in combat, Guardian and not a bear:
-- a Travel Form hop between packs or a stray form has dropped the armour and
-- the rage that make you the tank. The alert (speech or a sound) plays once
-- each time the warning appears.
--
-- The form is GetShapeshiftFormID() (5 = Bear Form); should it ever come back
-- secret the text stays hidden - a warning that fails open would shout at a
-- player who is a bear.
--------------------------------------------------------------------------------
local XUI = select(2, ...).XUI
local T = XUI.Templates

local BEAR_FORM = 5

local M = XUI:NewModule("BearForm", {
	name = "Bear Form Reminder",
	desc = "Text in combat when a Guardian is not in Bear Form.",
	category = "class",
	icon = [[Interface\Icons\Ability_Racial_BearForm]],
	order = 40,
	classes = { "DRUID" },
	specs = { 104 },
	untested = true,
	defaults = {
		text = "BEAR FORM",
		color = { 1, 0.49, 0.04, 1 },
		pulse = true,
		pulseSpeed = 0.45,
		font = T.Font(32),
		position = T.Position(0, 140, "HIGH"),
		alert = T.Alert("NONE", { text = "Bear form" }),
	},
})

local display
local inCombat = false
local warned = false -- the alert has played for this stretch of the warning

local function Display()
	if display then return display end
	display = XUI.Widgets:CreateText("XUI_BearForm")
	display:Hide()
	-- the pulse is on the text, like the Melee Indicator's, and C-side: no Lua per frame
	local group = display.text:CreateAnimationGroup()
	group:SetLooping("BOUNCE")
	local a = group:CreateAnimation("Alpha")
	a:SetFromAlpha(1)
	a:SetToAlpha(0.2)
	a:SetSmoothing("IN_OUT")
	display.pulse, display.pulseAnim = group, a
	XUI.Movers:Register(display, M, "position")
	return display
end

-- Runs while the warning is up and stops with it; started afresh each time it
-- shows, as a hidden frame does not keep its animation going.
local function SyncPulse(shown)
	local d = display
	if not d then return end
	if shown and M.db.pulse then
		if not d.pulse:IsPlaying() then
			d.pulseAnim:SetDuration(math.max(0.1, M.db.pulseSpeed))
			d.pulse:Play()
		end
	else
		d.pulse:Stop()
		d.text:SetAlpha(1)
	end
end

local function NotBear()
	if not GetShapeshiftFormID then return false end
	local ok, form = pcall(GetShapeshiftFormID)
	if not ok or XUI.IsSecret(form) then return false end
	return form ~= BEAR_FORM
end

function M:Update()
	if not display then return end
	local dead = XUI.Ask(UnitIsDeadOrGhost, "player") == true
	local warn = self.running and inCombat and not dead and NotBear()
	local shown = self:IsPreview() or warn
	display:SetShown(shown)
	SyncPulse(shown)
	if warn and not warned then
		warned = true
		XUI.Audio:Play(self.db.alert, "Bear form")
	elseif not warn then
		warned = false
	end
end

function M:OnEnable()
	Display()
	inCombat = XUI.Ask(UnitAffectingCombat, "player") == true
	self:RegisterEvent("PLAYER_REGEN_DISABLED", function(self) inCombat = true self:Update() end)
	self:RegisterEvent("PLAYER_REGEN_ENABLED", function(self) inCombat = false self:Update() end)
	for _, e in ipairs({ "UPDATE_SHAPESHIFT_FORM", "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST", "PLAYER_ENTERING_WORLD" }) do
		self:RegisterEvent(e, "Update")
	end
end

function M:OnRefresh()
	if not (display or self:IsPreview()) then return end
	local d, db = Display(), self.db
	XUI.Movers:Apply(d)
	d:ApplyStyle(db.font)
	d:SetText(db.text)
	d:SetTextColor(XUI.UnpackColor(db.color))
	-- the speed may have changed under a running pulse
	d.pulseAnim:SetDuration(math.max(0.1, db.pulseSpeed))
	self:Update()
end
