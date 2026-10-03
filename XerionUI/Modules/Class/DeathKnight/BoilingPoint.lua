--------------------------------------------------------------------------------
-- Boiling Point (Blood)
-- A 3-second bar after a Boiling Point proc is spent (the window its echo
-- lands in), optionally a bar for the proc itself and a glow while Blood Boil
-- is lit.
--
-- WHEN DOES THE WINDOW START
-- The server casts a hidden spell (1265982) on you when the proc is USED,
-- and SPELL_UPDATE_COOLDOWN names it: once seen, that alone starts the bar.
-- Until then (or when it is secret) a Blood Boil cast starts it only if Blood
-- Boil was glowing - the game already reports the NEW proc's glow at the cast
-- that spends the old one, so a short grace window and a "spent" flag keep a
-- plain Blood Boil from restarting the bar. A proc that lights up mid-window
-- queues another window after it.
--------------------------------------------------------------------------------
local XUI = select(2, ...).XUI
local T = XUI.Templates
local Style = XUI.Style

local BP_SPELL, USE_ECHO = 50842, 1265982
local DURATION, PROC_SECONDS, GLOW_GRACE, MAX_QUEUE = 3, 15, 1.0, 3

local M = XUI:NewModule("BoilingPoint", {
	name = "Boiling Point",
	desc = "A countdown bar for the Boiling Point window after Blood Boil.",
	category = "class",
	icon = [[Interface\Icons\Spell_DeathKnight_BloodBoil]],
	order = 30,
	classes = { "DEATHKNIGHT" },
	specs = { 250 },
	defaults = {
		bar = T.Bar(160, 16, { color = { 0.77, 0.12, 0.23, 1 } }),
		border = T.Border(),
		timerText = T.Font(12, { enabled = true }),
		procBar = false,
		procColor = { 0.20, 0.60, 1, 1 },
		procGlow = T.Glow(false, { useGlobal = false, type = "PIXEL", color = { 1, 0.82, 0, 1 } }),
		position = T.Position(0, -160),
	},
})

local IsSecret = XUI.IsSecret
local IsSpellOverlayed = (C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed) or _G.IsSpellOverlayed

local function BaseOf(id)
	local v = C_Spell and C_Spell.GetBaseSpell and XUI.Probe(C_Spell.GetBaseSpell, id)
	if type(v) == "number" then return v end
	local find = (C_SpellBook and C_SpellBook.FindBaseSpellByID) or _G.FindBaseSpellByID
	v = find and XUI.Probe(find, id)
	return type(v) == "number" and v or nil
end

local function LiveID()
	local v = C_Spell and C_Spell.GetOverrideSpell and XUI.Probe(C_Spell.GetOverrideSpell, BP_SPELL)
	if type(v) == "number" then return v end
	local find = (C_SpellBook and C_SpellBook.FindSpellOverrideByID) or _G.FindSpellOverrideByID
	v = find and XUI.Probe(find, BP_SPELL)
	return type(v) == "number" and v or BP_SPELL
end

local function IsBloodBoil(id)
	if id == BP_SPELL then return true end
	if type(id) ~= "number" then return false end
	return BaseOf(id) == BP_SPELL or LiveID() == id
end

-- the glow gate
local glowOn, glowSeen, glowEver = false, 0, false
local procSpent, spentAt = false, 0
local echoProven = false

local function Overlayed(id)
	if not IsSpellOverlayed then return nil end
	local v = XUI.Probe(IsSpellOverlayed, id)
	if v == nil then return nil end
	return v and true or false
end

local function GlowLive()
	local base = Overlayed(BP_SPELL)
	if base then return true end
	local live, over = LiveID(), nil
	if live ~= BP_SPELL then
		over = Overlayed(live)
		if over then return true end
	end
	if base == nil and over == nil then return nil end
	return false
end

local function GlowGate()
	local now = GetTime()
	local live = GlowLive()
	if live then
		glowEver, glowOn, glowSeen = true, true, now
		if procSpent and now - spentAt <= GLOW_GRACE then return false end
		procSpent = false
		return true
	end
	if live == false then glowOn = false end
	if procSpent then return false end
	if glowOn then return true end
	return now - glowSeen <= GLOW_GRACE
end

local function ProcUp()
	if procSpent then return false end
	local live = GlowLive()
	if live ~= nil then return live end
	return glowOn
end

--------------------------------------------------------------------------------
-- The bar
--------------------------------------------------------------------------------
local frame, glowHost
local expiresAt, procUntil, queued = 0, 0, 0
local shownEnd, shownTotal, shownSec = 0, 1, nil
local ticker

local function Active() return expiresAt > 0 and expiresAt > GetTime() end
local function ProcActive() return M.db.procBar and procUntil > GetTime() end

local Tick

-- the fill drains every frame while the bar is shown
local function OnUpdate()
	if shownEnd == 0 then return end
	local left = shownEnd - GetTime()
	if left <= 0 then Tick() return end
	frame.bar:SetValue(left / shownTotal)
	local sec = math.ceil(left)
	if sec ~= shownSec then
		shownSec = sec
		frame.time:SetText(tostring(sec))
	end
end

local function Frame()
	if frame then return frame end
	frame = XUI.Widgets:CreateBar("XUI_BoilingPoint")
	frame:Hide()
	frame:SetScript("OnUpdate", OnUpdate)
	glowHost = CreateFrame("Frame", nil, frame)
	glowHost:SetAllPoints(frame)
	XUI.Movers:Register(frame, M, "position")
	return frame
end

local function ApplyLook()
	local f, db = Frame(), M.db
	XUI.Movers:Apply(f)
	f:ApplyLayout(db.bar, db.border, "NONE")
	f.name:Hide()
	Style:ApplyFont(f.time, db.timerText)
	f.time:ClearAllPoints()
	f.time:SetPoint("CENTER", f.bar, "CENTER")
	f.time:SetShown(db.timerText.enabled ~= false)
	shownSec = nil
end

local function Render()
	if not frame then return end
	local db = M.db
	local left, total, isProc, endAt
	if M:IsPreview() then
		left, total, isProc, endAt = 2, DURATION, false, 0
	elseif not M.running then
		left = nil
	elseif Active() then
		left, total, isProc, endAt = expiresAt - GetTime(), DURATION, false, expiresAt
	elseif ProcActive() then
		left, total, isProc, endAt = procUntil - GetTime(), PROC_SECONDS, true, procUntil
	end
	if not left or left <= 0 then
		shownEnd = 0
		Style:HideGlow(glowHost)
		frame:Hide()
		return
	end
	shownEnd, shownTotal = endAt, total
	local c = isProc and db.procColor or Style:Resolve("bar", db.bar).color
	frame:SetColor(XUI.UnpackColor(c))
	local sec = math.ceil(left)
	if sec ~= shownSec then
		shownSec = sec
		frame.time:SetText(tostring(sec))
	end
	frame.bar:SetValue(left / total)
	glowHost:SetFrameLevel(frame:GetFrameLevel() + 5)
	Style:SetGlow(glowHost, db.procGlow, db.procGlow.enabled ~= false and not isProc and (M:IsPreview() or ProcUp()))
	frame:Show()
end

local function StopTicker()
	if ticker then M:CancelTicker(ticker) ticker = nil end
end

local function Clear()
	expiresAt, procUntil, queued = 0, 0, 0
	StopTicker()
	if glowHost then Style:HideGlow(glowHost) end
	if frame and not M:IsPreview() then frame:Hide() end
end

Tick = function()
	if M:IsPreview() then return end
	if Active() then Render() return end
	if queued > 0 then
		-- the echo landing is a Blood Boil and spends the proc that lit up
		-- mid-window
		queued = queued - 1
		procSpent, spentAt = true, GetTime()
		local from = expiresAt
		if GetTime() - expiresAt > DURATION then from = GetTime() end
		expiresAt = from + DURATION
		Render()
		return
	end
	expiresAt = 0
	if ProcActive() then Render() return end
	Clear()
end

local function EnsureTicker()
	if not ticker then ticker = M:NewTicker(0.1, Tick) end
end

local function Start()
	queued = 0
	procSpent, spentAt = true, GetTime()
	Frame()
	expiresAt = GetTime() + DURATION
	EnsureTicker()
	Render()
end

local function BeginProc()
	if not M.db.procBar then return end
	Frame()
	procUntil = GetTime() + PROC_SECONDS
	EnsureTicker()
	Render()
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------
function M:OnEnable()
	Frame()
	-- fires on every GCD, so it only listens while the module runs
	self:RegisterEvent("SPELL_UPDATE_COOLDOWN", function(_, _, id, base)
		if id == nil then return end
		if IsSecret(id) then echoProven = false return end
		if id ~= USE_ECHO and (base == nil or IsSecret(base) or base ~= USE_ECHO) then return end
		echoProven = true
		if not M:IsPreview() then Start() end
	end)
	local function glowEvent(_, event, spellID)
		if spellID == nil or IsSecret(spellID) or not IsBloodBoil(spellID) then return end
		if event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" then
			local rising = not glowOn or (procSpent and GetTime() - spentAt > GLOW_GRACE)
			if rising then procSpent = false end
			if rising and not M:IsPreview() and Active() and queued < MAX_QUEUE then queued = queued + 1 end
			glowOn, glowEver, glowSeen = true, true, GetTime()
			if rising and not M:IsPreview() then BeginProc() end
		else
			glowOn, glowSeen = false, GetTime()
			if not M:IsPreview() then
				procUntil = 0
				if not Active() and ticker then Tick() end
			end
		end
	end
	self:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", glowEvent)
	self:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", glowEvent)
	self:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player", function(_, _, _, _, spellID)
		if echoProven or M:IsPreview() or spellID == nil or IsSecret(spellID) or not IsBloodBoil(spellID) then return end
		if GlowGate() then Start() end
	end)
	self:RegisterEvent("PLAYER_ENTERING_WORLD", function()
		glowOn = GlowLive() and true or false
		procSpent = false
		Clear()
		ApplyLook()
		if glowOn then BeginProc() end
	end)
end

function M:OnDisable()
	ticker = nil
	procSpent = false
	Clear()
end

function M:OnRefresh()
	if not (frame or self:IsPreview()) then return end
	ApplyLook()
	if glowHost then Style:HideGlow(glowHost) end
	Render()
end
