--------------------------------------------------------------------------------
-- Combat Timer
-- How long the current fight has lasted. Ticks four times a second, and only
-- while you are in combat.
-- Ported from ItruliaQoL (MIT, (c) Itrulia).
--------------------------------------------------------------------------------
local XUI = select(2, ...).XUI
local T = XUI.Templates

local M = XUI:NewModule("CombatTimer", {
	name = "Combat Timer",
	desc = "Shows how long you have been in combat.",
	category = "general",
	icon = 134376, -- INV_Misc_PocketWatch_01
	order = 20,
	defaults = {
		format = "CLOCK",
		linger = 0,
		text = T.Font(16, { color = { 1, 1, 1, 1 } }),
		position = T.Position(0, -220),
	},
})

M.FORMATS = {
	{ value = "SECONDS", text = "83" },
	{ value = "SECONDS_BRACKET", text = "[83]" },
	{ value = "CLOCK", text = "01:23" },
	{ value = "CLOCK_BRACKET", text = "[01:23]" },
}

local floor = math.floor

local function Format(fmt, seconds)
	seconds = floor(seconds)
	if fmt == "SECONDS" then
		return tostring(seconds)
	elseif fmt == "SECONDS_BRACKET" then
		return ("[%d]"):format(seconds)
	end
	local clock = ("%02d:%02d"):format(floor(seconds / 60), seconds % 60)
	if fmt == "CLOCK_BRACKET" then return "[" .. clock .. "]" end
	return clock
end

local display, ticker, startTime, lastShown

local function Display()
	if display then return display end
	display = XUI.Widgets:CreateText("XUI_CombatTimer")
	display:Hide()
	XUI.Movers:Register(display, M, "position")
	return display
end

local function Tick()
	if not startTime then return end
	local s = floor(GetTime() - startTime)
	if s ~= lastShown then
		lastShown = s
		display:SetText(Format(M.db.format, s))
	end
end

function M:Start()
	startTime, lastShown = GetTime(), nil
	local d = Display()
	d:ApplyStyle(self.db.text)
	d:Show()
	Tick()
	self:CancelTicker(ticker)
	ticker = self:NewTicker(0.25, Tick)
end

function M:Stop()
	self:CancelTicker(ticker)
	ticker = nil
	Tick()
	startTime = nil
	if self:IsPreview() then return end
	if self.db.linger > 0 then
		self:After(self.db.linger, function()
			if not startTime and not self:IsPreview() and display then display:Hide() end
		end)
	elseif display then
		display:Hide()
	end
end

function M:OnEnable()
	Display()
	self:RegisterEvent("PLAYER_REGEN_DISABLED", "Start")
	self:RegisterEvent("PLAYER_REGEN_ENABLED", "Stop")
	if InCombatLockdown() then self:Start() end
end

function M:OnDisable()
	ticker, startTime = nil, nil
end

function M:OnRefresh()
	if not (display or self:IsPreview()) then return end
	local d = Display()
	XUI.Movers:Apply(d)
	d:ApplyStyle(self.db.text)
	if startTime and self:IsRunning() then
		lastShown = nil
		Tick()
		d:Show()
	elseif self:IsPreview() then
		d:SetText(Format(self.db.format, 83))
		d:Show()
	else
		d:Hide()
	end
end
