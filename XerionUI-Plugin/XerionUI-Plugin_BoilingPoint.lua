local _, ns = ...
local hooksecurefunc, C_Timer = ns.Probe('BoilingPoint', hooksecurefunc, C_Timer)
local _G = _G

local CreateFrame = CreateFrame
local UIParent = UIParent
local GetTime = GetTime
local pcall = pcall
local mceil = math.ceil
local mmax, mmin = math.max, math.min
local format = string.format

ns.hasBoilingPoint = true

local BP_SPELL   = 50842
local USE_ECHO   = 1265982

local DURATION   = 3
local GLOW_GRACE = 1.0
local MAX_QUEUE  = 3

local Round = ns.Round
local secret = ns.IsSecret

local IsSpellOverlayed = _G.C_SpellActivationOverlay
	and _G.C_SpellActivationOverlay.IsSpellOverlayed
	or _G.IsSpellOverlayed

local function IsBlood() return ns.IsSpec('DEATHKNIGHT', 1) end

local PROC_SECONDS = 15
local GLOW_TYPE = 'pixel'

local DEFAULTS = {
	enable = false,
	lock = true,
	x = 0,
	y = -160,
	strata = 'MEDIUM',
	durSize = 0,
	textColor = { 1, 1, 1, 1 },

	barLength = 160,
	barThickness = 16,
	barColor = { 0.77, 0.12, 0.23, 1 },
	barBg = { 0, 0, 0, 0.55 },
	barText = true,

	procBar = false,
	procColor = { 0.20, 0.60, 1, 1 },

	procGlow = false,
	procGlowColor = { 1, 0.82, 0, 1 },
	procGlowThickness = 2,
}

local function Migrate(cfg)
	cfg.requireGlow, cfg.strictGlow, cfg.chain = nil, nil, nil
	cfg.display, cfg.barVertical, cfg.barSmooth = nil, nil, nil
	cfg.procSeconds, cfg.procGlowType, cfg.euiMatchSize = nil, nil, nil
	cfg.euiAnchor, cfg.euiBarKey, cfg.euiPlace = nil, nil, nil
	cfg.euiOffsetX, cfg.euiOffsetY = nil, nil
	cfg.iconSize, cfg.sizeSplit, cfg.width, cfg.height = nil, nil, nil, nil
	cfg.border, cfg.showSwipe = nil, nil
end

local function GetCfg() return ns.ModuleCfg('boilingPoint', DEFAULTS, Migrate) end
ns.BPGetCfg = GetCfg

local Apply

local BarTexture = ns.BarTexture

local BarFont = ns.GothamNarrowBlackFont

local function BaseOf(id)
	if type(id) ~= 'number' then return nil end
	local CS = _G.C_Spell
	if CS and CS.GetBaseSpell then
		local ok, v = pcall(CS.GetBaseSpell, id)
		if ok and type(v) == 'number' and not secret(v) then return v end
	end
	local SB = _G.C_SpellBook
	local find = (SB and SB.FindBaseSpellByID) or _G.FindBaseSpellByID
	if find then
		local ok, v = pcall(find, id)
		if ok and type(v) == 'number' and not secret(v) then return v end
	end
	return nil
end

local function LiveID()
	local CS = _G.C_Spell
	if CS and CS.GetOverrideSpell then
		local ok, v = pcall(CS.GetOverrideSpell, BP_SPELL)
		if ok and type(v) == 'number' and not secret(v) then return v end
	end
	local SB = _G.C_SpellBook
	local find = (SB and SB.FindSpellOverrideByID) or _G.FindSpellOverrideByID
	if find then
		local ok, v = pcall(find, BP_SPELL)
		if ok and type(v) == 'number' and not secret(v) then return v end
	end
	return BP_SPELL
end

local function IsBloodBoil(id)
	if id == BP_SPELL then return true end
	if type(id) ~= 'number' then return false end
	if BaseOf(id) == BP_SPELL then return true end
	return LiveID() == id
end

local glowOn   = false
local glowSeen = 0
local glowEver = false

local procSpent = false
local spentAt = 0

local glowLog, glowLogN = {}, 0
local castLog, castLogN = {}, 0
local function Log(t, n)
	n = n + 1
	local slot = (n - 1) % 12 + 1
	local e = t[slot]
	if not e then e = {} t[slot] = e end
	return n, e
end

local function Overlayed(id)
	local ok, v = pcall(IsSpellOverlayed, id)
	if ok and not secret(v) then return v and true or false end
	return nil
end

local function GlowLive()
	if not IsSpellOverlayed then return nil end
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
		if procSpent and (now - spentAt) <= GLOW_GRACE then return false end
		procSpent = false
		return true
	end
	if live == false then glowOn = false end
	if procSpent then return false end
	if glowOn then return true end
	if (now - glowSeen) <= GLOW_GRACE then return true end
	return false
end

local expiresAt = 0
local procUntil = 0
local queued = 0
local preview
local frame, bar, glowHost
local ticker

-- End and length of the window the bar is drawing. 0 while the preview or
-- nothing is up, so the per-frame update leaves the bar alone.
local shownEnd, shownTotal, shownSec = 0, 1, nil

local function Active() return expiresAt > 0 and expiresAt > GetTime() end

local function ProcActive()
	if not GetCfg().procBar then return false end
	return procUntil > 0 and procUntil > GetTime()
end

local ApplySettings
local Tick

-- Runs only while the bar is shown. The fill drains every frame instead of
-- easing after a 0.1 s step, and the window's end is handled on the frame it
-- passes instead of on the next tick; together those drew the bar up to a
-- fifth of a second behind the real time left.
local function OnUpdate()
	if shownEnd == 0 then return end
	local left = shownEnd - GetTime()
	if left <= 0 then Tick() return end
	bar:SetValue(left / shownTotal)
	local sec = mceil(left)
	if sec ~= shownSec then
		shownSec = sec
		bar.Text:SetText(format('%d', sec))
	end
end

local function EnsureFrame()
	if frame then return end
	frame = CreateFrame('Frame', 'XerionUIBoilingPoint', UIParent)
	frame:SetFrameStrata('MEDIUM')
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(false)
	frame:RegisterForDrag('RightButton')
	ns.MakeDraggable(frame, GetCfg, 'x', 'y', function() Apply() end)
	frame:SetScript('OnUpdate', OnUpdate)

	bar = CreateFrame('StatusBar', nil, frame)
	bar:SetAllPoints(frame)
	bar:SetOrientation('HORIZONTAL')
	bar:SetStatusBarTexture(BarTexture())
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(1)
	bar.bg = bar:CreateTexture(nil, 'BACKGROUND')
	bar.bg:SetAllPoints()
	bar.border = bar:CreateTexture(nil, 'BACKGROUND', nil, -1)
	bar.border:SetPoint('TOPLEFT', -1, 1)
	bar.border:SetPoint('BOTTOMRIGHT', 1, -1)
	bar.border:SetColorTexture(0, 0, 0, 1)
	bar.Text = bar:CreateFontString(nil, 'OVERLAY')
	bar.Text:SetPoint('CENTER')

	glowHost = CreateFrame('Frame', nil, frame)
	glowHost:SetAllPoints(frame)
	glowHost:EnableMouse(false)

	frame:Hide()
end

local glowingNow = false
local glowW, glowH
local glowProxy = {}

local function StopProcGlow()
	if not glowingNow then return end
	glowingNow = false
	if glowHost and ns.GlowStop then ns.GlowStop(glowHost) end
end

local function SetProcGlow(on, w, h)
	if not glowHost or not ns.GlowStart then return end
	if not on then StopProcGlow() return end
	if glowingNow then
		if w == glowW and h == glowH then return end
		StopProcGlow()
	end
	local cfg = GetCfg()
	glowProxy.glow = true
	glowProxy.glowType = GLOW_TYPE
	glowProxy.glowColor = cfg.procGlowColor or DEFAULTS.procGlowColor
	glowProxy.glowThickness = cfg.procGlowThickness or 2
	ns.GlowStart(glowHost, w, h, glowProxy)
	glowingNow, glowW, glowH = true, w, h
end

local function ProcUp()
	if procSpent then return false end
	local live = GlowLive()
	if live ~= nil then return live end
	return glowOn
end

local applied = false

ApplySettings = function()
	EnsureFrame()
	local cfg = GetCfg()

	local w = cfg.barLength or 160
	local h = cfg.barThickness or 16

	frame:ClearAllPoints()
	frame:SetPoint('CENTER', UIParent, 'CENTER', cfg.x or 0, cfg.y or -160)
	frame:SetSize(w, h)
	frame:SetFrameStrata(cfg.strata or 'MEDIUM')

	local tc = cfg.textColor or DEFAULTS.textColor
	local ds = cfg.durSize or 0
	if ds <= 0 then ds = mmax(10, Round(mmin(w, h) * 0.36)) end

	bar:SetStatusBarTexture(BarTexture())
	local bc = cfg.barColor or DEFAULTS.barColor
	bar:SetStatusBarColor(bc[1] or 1, bc[2] or 0, bc[3] or 0, bc[4] or 1)
	local bg = cfg.barBg or DEFAULTS.barBg
	bar.bg:SetColorTexture(bg[1] or 0, bg[2] or 0, bg[3] or 0, bg[4] or 0.55)
	bar.Text:SetFont(BarFont(), ds, 'OUTLINE')
	bar.Text:SetTextColor(tc[1] or 1, tc[2] or 1, tc[3] or 1, tc[4] or 1)
	bar.Text:SetShown(cfg.barText ~= false)

	local ok, lvl = pcall(frame.GetFrameLevel, frame)
	if ok and lvl then pcall(glowHost.SetFrameLevel, glowHost, lvl + 5) end
	applied = true
end

local function EnsureApplied()
	if not applied then ApplySettings() end
end

local function Render()
	if not frame then return end
	local cfg = GetCfg()

	local left, total, isProc, endAt
	if preview then
		left, total, isProc, endAt = 2, DURATION, false, 0
	elseif not cfg.enable then
		left = nil
	elseif Active() then
		left, total, isProc, endAt = expiresAt - GetTime(), DURATION, false, expiresAt
	elseif ProcActive() then
		left, total, isProc, endAt = procUntil - GetTime(), PROC_SECONDS, true, procUntil
	end

	if not left or left <= 0 then
		shownEnd = 0
		StopProcGlow()
		frame:Hide()
		return
	end
	shownEnd, shownTotal = endAt, total

	local c = isProc and (cfg.procColor or DEFAULTS.procColor)
		or (cfg.barColor or DEFAULTS.barColor)
	bar:SetStatusBarColor(c[1] or 1, c[2] or 0, c[3] or 0, c[4] or 1)

	local sec = mceil(left)
	if sec ~= shownSec then
		shownSec = sec
		bar.Text:SetText(format('%d', sec))
	end
	bar:SetValue(left / total)

	SetProcGlow(cfg.procGlow and not isProc and (preview or ProcUp()),
		frame:GetWidth(), frame:GetHeight())

	frame:Show()
end

local function StopTicker()
	if ticker then ticker:Cancel() ticker = nil end
end

local function Clear()
	expiresAt = 0
	procUntil = 0
	queued = 0
	StopTicker()
	StopProcGlow()
	if frame and not preview then frame:Hide() end
end

local function EnsureTicker()
	if ticker then return end
	ticker = C_Timer.NewTicker(0.1, function() Tick() end)
end

Tick = function()
	if preview then return end
	if Active() then Render() return end

	if queued > 0 then
		-- The echo landing is a Blood Boil and spends the proc that glowed
		-- mid-window, so that proc is gone now. Left unspent, the gate's grace
		-- let the next plain Blood Boil restart the chained bar.
		queued = queued - 1
		procSpent, spentAt = true, GetTime()
		local from = expiresAt
		if (GetTime() - expiresAt) > DURATION then from = GetTime() end
		expiresAt = from + DURATION
		Render()
		return
	end

	expiresAt = 0
	if ProcActive() then Render() return end
	Clear()
end

local function Begin()
	EnsureApplied()
	expiresAt = GetTime() + DURATION
	EnsureTicker()
	Render()
end

local function BeginProc()
	if not GetCfg().procBar then return end
	EnsureApplied()
	procUntil = GetTime() + PROC_SECONDS
	EnsureTicker()
	Render()
end

local function EndProc()
	procUntil = 0
	if not Active() and not preview then
		if ticker then Tick() end
	end
end

local function Start()
	queued = 0
	procSpent, spentAt = true, GetTime()
	Begin()
end

-- The server casts a hidden 3 s spell on the player when a Boiling Point proc
-- is USED, and SPELL_UPDATE_COOLDOWN names it. The glow gate cannot tell a
-- used proc from a plain Blood Boil that grants a fresh one: the client already
-- reports the new glow at that cast's event, so the gate passed it and the bar
-- restarted with no glow on screen. Once this has been read, it alone starts
-- the bar. The event fires on every GCD, so it is only listened to while the
-- bar can run.
local evt = CreateFrame('Frame')
local echoProven = false

local function SyncEcho(on)
	if on then
		evt:RegisterEvent('SPELL_UPDATE_COOLDOWN')
	else
		evt:UnregisterEvent('SPELL_UPDATE_COOLDOWN')
	end
end

-- A running preview is drawn whatever the switch or the spec says, so every
-- setting changed while it is up redraws it, the way the other previews do.
Apply = function()
	StopProcGlow()
	local live = GetCfg().enable and IsBlood()
	SyncEcho(live)
	if not preview and not live then
		Clear()
		return
	end
	ApplySettings()
	Render()
end
ns.BPApply = Apply

-- No spec gate here: the page is open on every character, and a gated button
-- did nothing at all anywhere but Blood. The preview is only a drawing; the
-- real bar still waits for a Blood Boil on Blood.
ns.BPIsPreview = function() return preview and true or false end
ns.BPSetPreview = function(state)
	preview = state and true or false
	ApplySettings()
	frame:EnableMouse(preview)
	if preview then
		Render()
	else
		Clear()
		Render()
	end
end

evt:RegisterEvent('PLAYER_ENTERING_WORLD')
evt:RegisterEvent('SPELL_ACTIVATION_OVERLAY_GLOW_SHOW')
evt:RegisterEvent('SPELL_ACTIVATION_OVERLAY_GLOW_HIDE')
evt:RegisterUnitEvent('UNIT_SPELLCAST_SUCCEEDED', 'player')
evt:RegisterUnitEvent('PLAYER_SPECIALIZATION_CHANGED', 'player')
evt:SetScript('OnEvent', function(_, event, arg1, arg2, arg3)

	if event == 'SPELL_UPDATE_COOLDOWN' then
		if arg1 == nil then return end
		-- A secret payload means the echo cannot be read here: hand the start
		-- back to the glow gate rather than never starting at all.
		if secret(arg1) then echoProven = false return end
		if arg1 ~= USE_ECHO and (arg2 == nil or secret(arg2) or arg2 ~= USE_ECHO) then return end
		echoProven = true
		local entry
		castLogN, entry = Log(castLog, castLogN)
		entry.id, entry.pass, entry.proven, entry.t = USE_ECHO, true, true, GetTime()
		entry.spent = 'server echo: proc used'
		if preview or not GetCfg().enable or not IsBlood() then return end
		Start()
		return
	end

	if event == 'SPELL_ACTIVATION_OVERLAY_GLOW_SHOW'
		or event == 'SPELL_ACTIVATION_OVERLAY_GLOW_HIDE' then
		local spellID = arg1
		if spellID == nil or secret(spellID) then return end
		local mine = IsBloodBoil(spellID)
		local entry
		glowLogN, entry = Log(glowLog, glowLogN)
		entry.id, entry.t = spellID, GetTime()
		entry.show = (event == 'SPELL_ACTIVATION_OVERLAY_GLOW_SHOW')
		entry.mine = mine
		if not mine then return end
		if event == 'SPELL_ACTIVATION_OVERLAY_GLOW_SHOW' then
			local rising = not glowOn
				or (procSpent and (GetTime() - spentAt) > GLOW_GRACE)
			if rising then procSpent = false end
			if rising and not preview
				and expiresAt > 0 and expiresAt > GetTime() then
				if queued < MAX_QUEUE then queued = queued + 1 end
			end
			glowOn, glowEver, glowSeen = true, true, GetTime()
			if rising and not preview and GetCfg().enable and IsBlood() then BeginProc() end
		else
			glowOn = false
			glowSeen = GetTime()
			if not preview then EndProc() end
		end
		return
	end

	if preview then return end
	local cfg = GetCfg()

	if event == 'UNIT_SPELLCAST_SUCCEEDED' then
		if echoProven or not cfg.enable then return end
		local spellID = arg3
		if spellID == nil or secret(spellID) then return end
		-- Spec first: one read, where the Blood Boil match asks the spell API
		-- twice for every other cast. Both are plain reads, so the order
		-- changes nothing but the cost.
		if not IsBlood() then return end
		if not IsBloodBoil(spellID) then return end
		local pass = GlowGate()
		local entry
		castLogN, entry = Log(castLog, castLogN)
		entry.id, entry.pass, entry.proven, entry.t = spellID, pass, glowEver, GetTime()
		entry.spent = pass and 'spent' or (procSpent and 'already spent' or 'unspent')
		if not pass then return end
		Start()
		return
	end

	if event == 'PLAYER_SPECIALIZATION_CHANGED' then
		procSpent = false
		Clear()
		Apply()
		return
	end

	glowOn = GlowLive() and true or false
	procSpent = false
	Clear()
	Apply()
	if glowOn and GetCfg().enable and IsBlood() then BeginProc() end
end)

local function SpellName(id)
	local CS = _G.C_Spell
	if CS and CS.GetSpellName then
		local ok, n = pcall(CS.GetSpellName, id)
		if ok and type(n) == 'string' then return n end
	end
	local ok, n = pcall(_G.GetSpellInfo, id)
	if ok and type(n) == 'string' then return n end
	return '?'
end

local function DumpRing(t, n, fmt, p, emptyMsg)
	if n == 0 then p(emptyMsg) return end
	local count = n < 12 and n or 12
	local first = n < 12 and 1 or (n % 12) + 1
	for i = 0, count - 1 do
		local e = t[(first + i - 1) % 12 + 1]
		if e then p('   ' .. fmt(e)) end
	end
end

ns.BPTest = function()
	local function p(...) print('|cffff7d0aXerionUI-BoilingPoint|r', ...) end
	local cfg = GetCfg()
	local live = LiveID()

	p('enable:', tostring(cfg.enable), '| Blood:', tostring(IsBlood()))
	p('start signal:', echoProven
		and ('|cff00ff00server echo %d|r (proc used) - a plain Blood Boil can never start the bar'):format(USE_ECHO)
		or ('glow gate on Blood Boil casts - server echo %d not read yet this session'):format(USE_ECHO))
	p('Blood Boil base id:', BP_SPELL, '(' .. SpellName(BP_SPELL) .. ')',
		'| live id right now:', live, live ~= BP_SPELL and '|cffff6600(OVERRIDDEN)|r' or '(no override)')
	p('proc bar:', cfg.procBar and ('on, %ds'):format(PROC_SECONDS) or 'off',
		'| running:', ProcActive() and ('%.1fs left'):format(procUntil - GetTime()) or 'no')
	p('proc glow:', cfg.procGlow and 'on' or 'off',
		'| Blood Boil glowing now:', tostring(ProcUp()),
		'| drawn:', glowingNow and 'yes' or 'no')
	p('chaining: on', '| windows queued right now:', queued,
		'| echo bar up:', Active() and 'yes' or 'no')
	p('proc spent:', procSpent and ('yes, %.1fs ago - next Blood Boil is a filler'):format(GetTime() - spentAt)
		or 'no - next Blood Boil counts if it glows')
	p('overlay api:', IsSpellOverlayed and 'yes' or '|cffff6600MISSING|r',
		'| glowing now:', tostring(GlowLive()),
		'| gate proven:', glowEver and '|cff00ff00YES|r'
			or '|cffff6600NO - nothing will fire until the game glows Blood Boil once|r')
	local cv = _G.GetCVar and _G.GetCVar('displaySpellActivationOverlays')
	p('spell alerts cvar:', tostring(cv), cv == '0' and '|cffff6600(alerts off in Interface options)|r' or '')

	p('glows seen this session (newest last):')
	DumpRing(glowLog, glowLogN, function(e)
		return ('%s  %d  %s  %s'):format(e.show and 'SHOW' or 'hide', e.id, SpellName(e.id),
			e.mine and '|cff00ff00<- matched as Blood Boil|r' or '|cff999999(not ours)|r')
	end, p, '   |cffff6600none at all - the game has not glowed ANY spell since login|r')

	p('Blood Boil casts (newest last):')
	DumpRing(castLog, castLogN, function(e)
		return ('id %d  gate %s  %s %s'):format(e.id,
			e.pass and '|cff00ff00PASS|r' or '|cff999999blocked|r',
			e.spent or '',
			e.proven and '' or '(gate unproven at the time)')
	end, p, '   none yet')

	if not glowEver and glowLogN > 0 then
		p('|cffff6600=> the game IS glowing spells, but never one this module reads as Blood Boil.|r')
		p('   Nothing will fire until that is fixed. The correct id is in the list above.')
	elseif glowLogN == 0 then
		p('=> no glow data yet. Get a Boiling Point proc, then run /xerionboil again.')
	else
		p('=> gate is calibrated; only glowing Blood Boils start the countdown.')
	end
end

SLASH_XERIONBOIL1 = '/xerionboil'
SlashCmdList.XERIONBOIL = function() ns.BPTest() end
