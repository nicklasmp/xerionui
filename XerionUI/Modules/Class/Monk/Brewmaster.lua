--------------------------------------------------------------------------------
-- Brewmaster (Monk): three small modules
--
--   Expel Harm orbs    five orbs for the healing orbs Expel Harm can use (its
--                      cast count), as an arc over the character
--   Dodge chance       your dodge chance as a number, in combat or always
--   Elixir of          the icon counts the 15 second lockout between Elixir of
--   Determination      Determination procs
--
-- Elixir: the talent (455139) has no cooldown to read, and the absorb it gives
-- (455179) is secret in combat and often gone within a second, so neither can
-- say when the next proc may come. The proc also casts a hidden 15 s lockout
-- spell on the player (455180), and a spell of the player's own is announced in
-- SPELL_UPDATE_COOLDOWN by its spell ID whether or not it has a cooldown. That
-- payload carries no secret flag, so the event starts a plain 15 s clock of
-- ours: the icon counts from the proc itself, however fast the shield goes.
-- The ID is tested for a secret before it is compared.
--------------------------------------------------------------------------------
local XUI = select(2, ...).XUI
local T = XUI.Templates
local Style = XUI.Style

local IsSecret = XUI.IsSecret
local BREWMASTER = 268

--------------------------------------------------------------------------------
-- Expel Harm orbs
--------------------------------------------------------------------------------
local EXPEL_HARM, ORBS = 322101, 5

local Orbs = XUI:NewModule("ExpelHarmOrbs", {
	name = "Expel Harm Orbs",
	desc = "Five orbs showing how many healing orbs Expel Harm can use.",
	category = "class",
	icon = [[Interface\Icons\Ability_Monk_ExpelHarm]],
	order = 30,
	classes = { "MONK" },
	specs = { BREWMASTER },
	untested = true,
	defaults = {
		orbSize = 12,
		orbRadius = 25,
		orbSpread = 120,
		orbColor = { 0, 1, 0.588, 1 },
		position = T.Position(0, -4),
	},
})

local GetCastCount = (C_Spell and C_Spell.GetSpellCastCount) or _G.GetSpellCount
local orbFrame, orbs

local function MakeOrbBar(parent, level)
	local b = CreateFrame("StatusBar", nil, parent)
	b:SetFrameLevel(parent:GetFrameLevel() + level)
	b:SetStatusBarTexture([[Interface\Buttons\WHITE8x8]])
	local m = b:CreateMaskTexture()
	m:SetTexture([[Interface\Masks\CircleMaskScalable]], "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	m:SetAllPoints(b)
	b:GetStatusBarTexture():AddMaskTexture(m)
	return b
end

local function OrbFrame()
	if orbFrame then return orbFrame end
	orbFrame = CreateFrame("Frame", "XUI_ExpelHarmOrbs", UIParent)
	orbFrame:Hide()
	orbs = {}
	for i = 1, ORBS do
		local ring = MakeOrbBar(orbFrame, 1)
		ring:SetStatusBarColor(0, 0, 0, 1)
		ring:SetMinMaxValues(i - 1, i)
		local fill = MakeOrbBar(orbFrame, 2)
		fill:SetMinMaxValues(i - 1, i)
		orbs[i] = { ring = ring, fill = fill }
	end
	XUI.Movers:Register(orbFrame, Orbs, "position")
	return orbFrame
end

local function PaintOrbs()
	if not orbFrame then return end
	local n
	if Orbs:IsPreview() then
		n = ORBS
	else
		n = GetCastCount and GetCastCount(EXPEL_HARM)
		if not IsSecret(n) then n = n or 0 end
	end
	for i = 1, ORBS do
		orbs[i].ring:SetValue(n)
		orbs[i].fill:SetValue(n)
	end
end

-- these events land two to four at a time per cast; one paint answers the burst
local PaintSoon = XUI.Coalesce(PaintOrbs)

function Orbs:OnEnable()
	OrbFrame()
	for _, e in ipairs({ "SPELL_UPDATE_USES", "SPELL_UPDATE_USABLE", "SPELL_UPDATE_COOLDOWN" }) do
		self:RegisterEvent(e, PaintSoon)
	end
	self:RegisterUnitEvent("UNIT_AURA", "player", PaintSoon)
end

function Orbs:OnRefresh()
	if not (orbFrame or self:IsPreview()) then return end
	local f, db = OrbFrame(), self.db
	XUI.Movers:Apply(f)
	local sz, r, span = db.orbSize, db.orbRadius, db.orbSpread
	local ymin = r * math.sin(math.rad(90 - span / 2))
	local midY = (r + ymin) / 2
	f:SetSize(2 * r + sz + 2, (r - ymin) + sz + 2)
	local step = span / (ORBS - 1)
	for i = 1, ORBS do
		local a = math.rad(90 + span / 2 - (i - 1) * step)
		local o = orbs[i]
		o.ring:SetSize(sz + 2, sz + 2)
		o.ring:ClearAllPoints()
		o.ring:SetPoint("CENTER", f, "CENTER", r * math.cos(a), r * math.sin(a) - midY)
		o.fill:SetSize(sz, sz)
		o.fill:ClearAllPoints()
		o.fill:SetPoint("CENTER", o.ring, "CENTER", 0, 0)
		o.fill:SetStatusBarColor(XUI.UnpackColor(db.orbColor))
	end
	f:SetShown(self:IsPreview() or self.running)
	PaintOrbs()
end

function Orbs:OnDisable()
	if orbFrame and not self:IsPreview() then orbFrame:Hide() end
end

--------------------------------------------------------------------------------
-- Dodge chance
--------------------------------------------------------------------------------
local Dodge = XUI:NewModule("BrewDodge", {
	name = "Dodge Chance",
	desc = "Your dodge chance as a number.",
	category = "class",
	icon = [[Interface\Icons\Ability_Rogue_Feint]],
	order = 31,
	classes = { "MONK" },
	specs = { BREWMASTER },
	untested = true,
	defaults = {
		combatOnly = true,
		font = T.Font(18, { color = { 0, 1, 0.588, 1 } }),
		position = T.Position(0, -120),
	},
})

local dodgeText
local dodgeInCombat = false
local dodgeTicker

local function DodgeDisplay()
	if dodgeText then return dodgeText end
	dodgeText = XUI.Widgets:CreateText("XUI_BrewDodge")
	dodgeText:Hide()
	XUI.Movers:Register(dodgeText, Dodge, "position")
	return dodgeText
end

local function RenderDodge()
	local d = dodgeText
	if not d then return end
	local show = Dodge:IsPreview() or (Dodge.running and (not Dodge.db.combatOnly or dodgeInCombat or InCombatLockdown()))
	if not show then d:Hide() return end
	local ok, v = pcall(GetDodgeChance)
	if ok then
		if not IsSecret(v) then v = v or 0 end
		pcall(d.text.SetFormattedText, d.text, "%.0f%%", v)
	end
	d:Show()
end

function Dodge:OnEnable()
	DodgeDisplay()
	dodgeInCombat = InCombatLockdown() and true or false
	self:RegisterEvent("PLAYER_REGEN_DISABLED", function(self) dodgeInCombat = true self:Refresh() end)
	self:RegisterEvent("PLAYER_REGEN_ENABLED", function(self) dodgeInCombat = false self:Refresh() end)
	-- dodge changes with gear and auras; a slow tick is enough while it shows
	dodgeTicker = self:NewTicker(0.5, RenderDodge)
end

function Dodge:OnDisable()
	dodgeTicker = nil
	if dodgeText and not self:IsPreview() then dodgeText:Hide() end
end

function Dodge:OnRefresh()
	if not (dodgeText or self:IsPreview()) then return end
	local d, db = DodgeDisplay(), self.db
	XUI.Movers:Apply(d)
	d:ApplyStyle(db.font)
	d:SetTextColor(XUI.UnpackColor(Style:Resolve("font", db.font).color))
	RenderDodge()
	d:Fit()
end

--------------------------------------------------------------------------------
-- Elixir of Determination lockout
--------------------------------------------------------------------------------
local ELIXIR_ICON, ELIXIR_TALENT, ELIXIR_LOCKOUT = 455179, 455139, 455180
local ELIXIR_ICD, ELIXIR_LEFT = 15, 9

local Elixir = XUI:NewModule("ElixirProc", {
	name = "Elixir of Determination",
	desc = "Counts the 15 second lockout between Elixir of Determination procs.",
	category = "class",
	icon = 6034820,
	order = 32,
	classes = { "MONK" },
	specs = { BREWMASTER },
	untested = true,
	defaults = {
		showReady = false,
		icon = T.Icon(40),
		border = T.Border(),
		showSwipe = true,
		timerText = T.Font(16, { enabled = true }),
		position = T.Position(0, -170),
	},
})

local elixIcon, elixEnds, elixTimer = nil, 0, nil

function Elixir:CanLoad()
	-- an unreadable answer counts as talented
	if XUI.Ask(IsPlayerSpell, ELIXIR_TALENT) == false then return false, "Requires the Elixir of Determination talent." end
	return true
end

local function ElixirIcon()
	if elixIcon then return elixIcon end
	elixIcon = XUI.Widgets:CreateIcon("XUI_ElixirProc")
	elixIcon:Hide()
	XUI.Movers:Register(elixIcon, Elixir, "position")
	return elixIcon
end

local function ElixirRun()
	local d = elixIcon
	if not d then return end
	local running = GetTime() < elixEnds
	local show = Elixir:IsPreview() or running or (Elixir.running and Elixir.db.showReady)
	d:SetShown(show)
	-- bright while ready, grey while the lockout runs
	d:SetDesaturated(running or Elixir:IsPreview())
	local cd = d:GetCooldown()
	if Elixir:IsPreview() then
		cd:SetCooldown(GetTime() - (ELIXIR_ICD - ELIXIR_LEFT), ELIXIR_ICD)
	elseif running then
		cd:SetCooldown(elixEnds - ELIXIR_ICD, ELIXIR_ICD)
	else
		cd:Clear()
	end
end

function Elixir:OnEnable()
	ElixirIcon()
	self:RegisterEvent("SPELL_UPDATE_COOLDOWN", function(self, _, spellID)
		if IsSecret(spellID) or spellID ~= ELIXIR_LOCKOUT then return end
		local now = GetTime()
		if now < elixEnds then return end -- no second proc can land inside the lockout
		if elixTimer then elixTimer:Cancel() end
		elixEnds = now + ELIXIR_ICD
		elixTimer = C_Timer.NewTimer(ELIXIR_ICD, function() elixTimer = nil elixEnds = 0 self:Refresh() end)
		self:Refresh()
	end)
	for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "SPELLS_CHANGED" }) do
		self:RegisterEvent(e, function(self) self:RefreshSoon() end)
	end
	pcall(self.RegisterEvent, self, "TRAIT_CONFIG_UPDATED", function(self) self:RefreshSoon() end)
end

-- switching off only stops listening: a lockout already counting is real and
-- runs out on its own clock
function Elixir:OnDisable()
	if elixIcon and not self:IsPreview() and GetTime() >= elixEnds then elixIcon:Hide() end
end

function Elixir:OnRefresh()
	if not (elixIcon or self:IsPreview()) then return end
	local d, db = ElixirIcon(), self.db
	XUI.Movers:Apply(d)
	d:ApplyLayout(db.icon, db.border)
	d:SetIcon(XUI.GetSpellIcon(ELIXIR_ICON, 6034820))
	d:StyleCooldownText(db.timerText)
	d:GetCooldown():SetDrawSwipe(db.showSwipe ~= false)
	ElixirRun()
end
