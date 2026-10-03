--------------------------------------------------------------------------------
-- Melee Indicator
-- A melee spec in combat with an attackable target out of melee range sees a
-- marker. Checked twice a second, and only while in combat.
-- Ported from ItruliaQoL (MIT, (c) Itrulia).
--
-- Midnight: the range answer can be secret. Then the marker is shown with
-- its alpha driven by the secret boolean (SetAlphaFromBoolean), so the client
-- decides and Lua never reads it.
--------------------------------------------------------------------------------
local XUI = select(2, ...).XUI
local T = XUI.Templates

-- A melee ability per spec, used as the range probe.
local MELEE_SPELLS = {
	DEATHKNIGHT = { [250] = 49998, [251] = 49998, [252] = 49998 },  -- Death Strike
	DEMONHUNTER = { [577] = 162794, [581] = 344859 },               -- Chaos Strike, Demon's Bite
	DRUID = { [103] = 5221, [104] = 33917 },                        -- Shred, Mangle
	HUNTER = { [255] = 186270 },                                    -- Raptor Strike
	MONK = { [268] = 205523, [269] = 205523, [270] = 205523 },      -- Blackout Kick
	PALADIN = { [66] = 96231, [70] = 96231 },                       -- Rebuke
	ROGUE = { [259] = 1752, [260] = 1752, [261] = 1752 },           -- Sinister Strike
	SHAMAN = { [263] = 73899 },                                     -- Primal Strike
	WARRIOR = { [71] = 1715, [72] = 1715, [73] = 1715 },            -- Hamstring
}

local M = XUI:NewModule("MeleeIndicator", {
	name = "Melee Indicator",
	desc = "Shows a marker in combat when your target is out of melee range.",
	category = "combat",
	icon = [[Interface\Icons\Ability_Warrior_Charge]],
	order = 20,
	defaults = {
		text = "+",
		color = { 1, 0, 0, 1 },
		interval = 0.25,
		alert = T.Alert("NONE", { text = "Out of range" }),
		repeatEvery = 0,
		pulse = false,
		pulseSpeed = 0.45,
		font = T.Font(28),
		position = T.Position(0, -40),
	},
})

local IsSecret = XUI.IsSecret
local display, ticker
local spellID
local last = "not checked yet" -- what the last check saw, for /xui debug

local function Display()
	if display then return display end
	display = XUI.Widgets:CreateText("XUI_MeleeIndicator")
	display:Hide()
	-- the pulse is on the text, not the frame: the frame's alpha is the range
	-- answer (possibly secret) and must stay out of the animation's way
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

local function ResolveSpell()
	local entry = MELEE_SPELLS[XUI.playerClass]
	local spec = XUI.GetSpecID()
	local id = entry and spec and entry[spec]
	if id and C_Spell.GetSpellInfo(id) then spellID = id else spellID = nil end
end

function M:CanLoad()
	ResolveSpell()
	if not spellID then return false, "Only for melee specializations." end
	return true
end

-- Druids only count in cat or bear form: the probe is usable there.
local function FormReady()
	if XUI.playerClass ~= "DRUID" then return true end
	local usable, noMana = C_Spell.IsSpellUsable(spellID)
	if IsSecret(usable) then return true end
	return (usable or noMana) and true or false
end

-- The sound or voice: when you step out of range, and again every
-- `repeatEvery` seconds while you stay out (0 = once). It needs the answer in
-- the clear: where range is secret the client decides, and Lua cannot tell.
local wasOut, lastAlertAt = false, 0
local function Alert(out)
	if not out then wasOut = false return end
	local now = GetTime()
	local every = M.db.repeatEvery
	if not wasOut or (every > 0 and now - lastAlertAt >= every) then
		wasOut, lastAlertAt = true, now
		XUI.Audio:Play(M.db.alert, M.db.text ~= "" and "Out of range" or nil, true)
	end
end

local function Check()
	local d = display
	if not d then return end
	if not spellID or not UnitExists("target") or XUI.Ask(UnitCanAttack, "player", "target") == false or not FormReady() then
		last = "no attackable target (or wrong form)"
		d:Hide()
		Alert(false)
		return
	end
	local inRange = C_Spell.IsSpellInRange(spellID, "target")
	if IsSecret(inRange) then
		last = "secret answer: alpha follows it"
		d:Show()
		d:SetAlphaFromBoolean(inRange, 0, 1)
		return
	end
	last = "answer " .. tostring(inRange)
	d:SetAlpha(1)
	-- nil means the client could not tell (no valid target for the spell)
	d:SetShown(inRange == false)
	Alert(inRange == false)
end

function M:StartChecking()
	self:CancelTicker(ticker)
	ticker = self:NewTicker(self.db.interval, Check)
	Check()
end

function M:StopChecking()
	wasOut = false
	self:CancelTicker(ticker)
	ticker = nil
	if display and not self:IsPreview() then display:Hide() end
end

function M:OnEnable()
	Display()
	ResolveSpell()
	self:RegisterEvent("PLAYER_REGEN_DISABLED", "StartChecking")
	self:RegisterEvent("PLAYER_REGEN_ENABLED", "StopChecking")
	self:RegisterEvent("PLAYER_TARGET_CHANGED", function() if ticker then Check() end end)
	self:RegisterEvent("UPDATE_SHAPESHIFT_FORM", function() if ticker then Check() end end)
	if InCombatLockdown() then self:StartChecking() end
end

function M:OnDisable()
	ticker = nil
end

function M:OnRefresh()
	if not (display or self:IsPreview()) then return end
	local d, db = Display(), self.db
	XUI.Movers:Apply(d)
	d:ApplyStyle(db.font)
	d:SetText(db.text)
	d:SetTextColor(XUI.UnpackColor(db.color))
	if db.pulse then
		d.pulseAnim:SetDuration(math.max(0.1, db.pulseSpeed))
		if not d.pulse:IsPlaying() then d.pulse:Play() end
	else
		d.pulse:Stop()
		d.text:SetAlpha(1)
	end
	if self:IsPreview() then
		d:SetAlpha(1)
		d:Show()
	elseif ticker and self:IsRunning() then
		self:StartChecking() -- the interval may have changed
	else
		d:Hide()
	end
end

-- the marker for three seconds, whatever the target
function M:Test()
	if not self:RequireRunning() then return end
	local d = Display()
	self:Refresh()
	d:SetAlpha(1)
	d:Show()
	XUI.Audio:Play(self.db.alert, "Out of range", true)
	self:After(3, function() if not ticker and not self:IsPreview() then d:Hide() end end)
end

function M:DebugInfo()
	local d = display
	return {
		("probe spell: %s (%s)"):format(tostring(spellID), spellID and (C_Spell.GetSpellName(spellID) or "?") or "none for this spec"),
		("in combat: %s, checking: %s"):format(tostring(InCombatLockdown()), tostring(ticker ~= nil)),
		("last check: %s"):format(last),
		("marker: shown %s, alpha %s"):format(tostring(d and d:IsShown()), d and tostring(d:GetAlpha()) or "-"),
	}
end
