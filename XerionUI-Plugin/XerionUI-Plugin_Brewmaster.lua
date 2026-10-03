local _, ns = ...
local hooksecurefunc, C_Timer = ns.Probe('Brewmaster', hooksecurefunc, C_Timer)
local _G = _G

local CreateFrame = CreateFrame
local GetTime = GetTime
local UIParent = UIParent
local pcall, tostring = pcall, tostring
local mmax = math.max
local secret = ns.IsSecret

ns.hasBrewmaster = true

local DEFAULTS = {
	orbEnable = false,
	orbSize = 12,
	orbRadius = 25,
	orbSpread = 120,
	orbColor = { 0, 1, 0.588, 1 },
	orbLock = false,
	orbX = 0,
	orbY = -4,
	dodgeEnable = false,
	dodgeCombatOnly = true,
	dodgeSize = 18,
	dodgeColor = { 0, 1, 0.588, 1 },
	dodgeLock = false,
	dodgeX = 0,
	dodgeY = -120,
	elixEnable = false,
	elixReady = false,
	elixSize = 40,
	elixSwipe = true,
	elixText = true,
	elixTextSize = 0,
	elixLock = false,
	elixX = 0,
	elixY = -170,
}

local function Migrate(cfg)
	if cfg.orbY == -260 then cfg.orbY = -4 end
	if cfg.orbSize == 30 then cfg.orbSize = 12 end
end

local function GetCfg() return ns.ModuleCfg('elixirICD', DEFAULTS, Migrate) end
ns.BMGetCfg = GetCfg

local EXPEL_HARM = 322101
local ORBS = 5
local GetCastCount = (_G.C_Spell and _G.C_Spell.GetSpellCastCount) or _G.GetSpellCount

local orbFrame, orbs
local orbPreview = false
local ApplyOrbs, RenderOrbs

local function IsBrew() return ns.IsSpec('MONK', 1) end

-- The orbs, the dodge text and the Elixir icon share one kind of holder:
-- hidden until its Apply shows it, right-dragged while unlocked.
local function MakeHolder(name, xKey, yKey, lockKey, onMoved)
	local f = CreateFrame('Frame', name, UIParent)
	f:SetFrameStrata('MEDIUM')
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(false)
	f:RegisterForDrag('RightButton')
	f:Hide()
	ns.MakeDraggable(f, GetCfg, xKey, yKey, onMoved, function(cfg) return not cfg[lockKey] end)
	return f
end

local function MakeOrbBar(parent, level)
	local b = CreateFrame('StatusBar', nil, parent)
	b:SetFrameLevel(parent:GetFrameLevel() + level)
	b:SetStatusBarTexture('Interface\\Buttons\\WHITE8x8')
	local m = b:CreateMaskTexture()
	m:SetTexture('Interface\\Masks\\CircleMaskScalable',
		'CLAMPTOBLACKADDITIVE', 'CLAMPTOBLACKADDITIVE')
	m:SetAllPoints(b)
	b:GetStatusBarTexture():AddMaskTexture(m)
	return b
end

local function EnsureOrbs()
	if orbFrame then return end
	orbFrame = MakeHolder('XerionUIExpelHarmOrbs', 'orbX', 'orbY', 'orbLock', ApplyOrbs)
	orbs = {}
	for i = 1, ORBS do
		local ring = MakeOrbBar(orbFrame, 1)
		ring:SetStatusBarColor(0, 0, 0, 1)
		ring:SetMinMaxValues(i - 1, i)
		local fill = MakeOrbBar(orbFrame, 2)
		fill:SetMinMaxValues(i - 1, i)
		orbs[i] = { ring = ring, fill = fill }
	end
end

local mcos, msin, mrad = math.cos, math.sin, math.rad

ApplyOrbs = function()
	local cfg = GetCfg()
	-- Nothing is built until the orbs are wanted: BMApply runs for every class.
	if not (orbFrame or cfg.orbEnable or orbPreview) then return end
	EnsureOrbs()
	orbFrame:EnableMouse(orbPreview and not cfg.orbLock)
	local sz = cfg.orbSize or 12
	local r = cfg.orbRadius or 25
	local span = cfg.orbSpread or 120
	local c = cfg.orbColor or { 0, 1, 0.588, 1 }
	local ymin = r * msin(mrad(90 - span / 2))
	local midY = (r + ymin) / 2
	orbFrame:SetSize(2 * r + sz + 2, (r - ymin) + sz + 2)
	orbFrame:ClearAllPoints()
	orbFrame:SetPoint('CENTER', UIParent, 'CENTER', cfg.orbX or 0, cfg.orbY or -4)
	local step = span / (ORBS - 1)
	for i = 1, ORBS do
		local a = mrad(90 + span / 2 - (i - 1) * step)
		local o = orbs[i]
		o.ring:SetSize(sz + 2, sz + 2)
		o.ring:ClearAllPoints()
		o.ring:SetPoint('CENTER', orbFrame, 'CENTER', r * mcos(a), r * msin(a) - midY)
		o.fill:SetSize(sz, sz)
		o.fill:ClearAllPoints()
		o.fill:SetPoint('CENTER', o.ring, 'CENTER', 0, 0)
		o.fill:SetStatusBarColor(c[1] or 0, c[2] or 1, c[3] or 0.588, c[4] or 1)
		o.ring:Show()
		o.fill:Show()
	end
end

local orbTicker
local function StopOrbTicker()
	if orbTicker then orbTicker:Cancel() orbTicker = nil end
end
local function StartOrbTicker()
	if orbTicker then return end
	orbTicker = C_Timer.NewTicker(0.2, RenderOrbs)
end

RenderOrbs = function()
	if not orbFrame then return end
	local cfg = GetCfg()
	if not cfg.orbEnable or (not orbPreview and not IsBrew()) then
		orbFrame:Hide()
		StopOrbTicker()
		return
	end
	StartOrbTicker()
	local n
	if orbPreview then
		n = ORBS
	else
		n = GetCastCount and GetCastCount(EXPEL_HARM)
		if not secret(n) then
			n = n or 0
		end
	end
	for i = 1, ORBS do
		orbs[i].ring:SetValue(n)
		orbs[i].fill:SetValue(n)
	end
	orbFrame:Show()
end

local orbEvt = CreateFrame('Frame')
orbEvt:RegisterUnitEvent('PLAYER_SPECIALIZATION_CHANGED', 'player')
orbEvt:RegisterEvent('PLAYER_ENTERING_WORLD')

-- The charge and aura events fire on every cast, so only a Brewmaster with
-- the orbs on (or the preview) listens to them; spec changes re-decide.
local function SyncOrbEvents()
	local cfg = GetCfg()
	if cfg.orbEnable and (orbPreview or IsBrew()) then
		orbEvt:RegisterEvent('SPELL_UPDATE_USES')
		orbEvt:RegisterEvent('SPELL_UPDATE_USABLE')
		orbEvt:RegisterEvent('SPELL_UPDATE_COOLDOWN')
		orbEvt:RegisterUnitEvent('UNIT_AURA', 'player')
	else
		orbEvt:UnregisterEvent('SPELL_UPDATE_USES')
		orbEvt:UnregisterEvent('SPELL_UPDATE_USABLE')
		orbEvt:UnregisterEvent('SPELL_UPDATE_COOLDOWN')
		orbEvt:UnregisterEvent('UNIT_AURA')
	end
end

local function RefreshOrbs()
	ApplyOrbs()
	SyncOrbEvents()
	RenderOrbs()
end

-- USES, USABLE, COOLDOWN and the player's UNIT_AURA land two to four at a time
-- per cast; one render on the next frame answers the whole burst.
local QueueRenderOrbs = ns.Coalesce(function() RenderOrbs() end)
orbEvt:SetScript('OnEvent', function(_, event)
	if event == 'PLAYER_ENTERING_WORLD' or event == 'PLAYER_SPECIALIZATION_CHANGED' then
		RefreshOrbs()
	else
		QueueRenderOrbs()
	end
end)

local dodgeFrame
local dodgePreview = false
local ApplyDodge, RenderDodge

local function EnsureDodge()
	if dodgeFrame then return end
	dodgeFrame = MakeHolder('XerionUIBrewDodge', 'dodgeX', 'dodgeY', 'dodgeLock', ApplyDodge)
	dodgeFrame:SetSize(120, 32)
	dodgeFrame.text = dodgeFrame:CreateFontString(nil, 'OVERLAY')
	dodgeFrame.text:SetPoint('CENTER')
end

ApplyDodge = function()
	local cfg = GetCfg()
	if not (dodgeFrame or cfg.dodgeEnable or dodgePreview) then return end
	EnsureDodge()
	local c = cfg.dodgeColor or { 0, 1, 0.588, 1 }
	dodgeFrame.text:SetFont(ns.GetFont(), cfg.dodgeSize or 18, 'OUTLINE')
	dodgeFrame.text:SetTextColor(c[1] or 0, c[2] or 1, c[3] or 0.588, c[4] or 1)
	dodgeFrame:ClearAllPoints()
	dodgeFrame:SetPoint('CENTER', UIParent, 'CENTER', cfg.dodgeX or 0, cfg.dodgeY or -120)
	dodgeFrame:EnableMouse(dodgePreview and not cfg.dodgeLock)
end

local dodgeInCombat = false

local dodgeTicker
local function StopDodgeTicker()
	if dodgeTicker then dodgeTicker:Cancel() dodgeTicker = nil end
end
local function StartDodgeTicker()
	if dodgeTicker then return end
	dodgeTicker = C_Timer.NewTicker(0.2, RenderDodge)
end

RenderDodge = function()
	if not dodgeFrame then return end
	local cfg = GetCfg()
	local show = cfg.dodgeEnable and (dodgePreview or IsBrew())
	if show and not dodgePreview and cfg.dodgeCombatOnly
		and not (dodgeInCombat or _G.InCombatLockdown()) then
		show = false
	end
	if not show then
		dodgeFrame:Hide()
		StopDodgeTicker()
		return
	end
	local okRead, v = pcall(_G.GetDodgeChance)
	if okRead then
		if not secret(v) then v = v or 0 end
		pcall(dodgeFrame.text.SetFormattedText, dodgeFrame.text, '%.0f%%', v)
	end
	dodgeFrame:Show()
	StartDodgeTicker()
end

-- Only a Monk can be a Brewmaster, and the class never changes in a session.
-- Anyone else sees the dodge text only in the preview, which the settings
-- window drives itself (BMDodgeSetPreview), so they need none of these.
local dodgeEvt = CreateFrame('Frame')
if ns.IsClass('MONK') then
	dodgeEvt:RegisterEvent('PLAYER_REGEN_DISABLED')
	dodgeEvt:RegisterEvent('PLAYER_REGEN_ENABLED')
	dodgeEvt:RegisterUnitEvent('PLAYER_SPECIALIZATION_CHANGED', 'player')
	dodgeEvt:RegisterEvent('PLAYER_ENTERING_WORLD')
	pcall(dodgeEvt.RegisterEvent, dodgeEvt, 'PLAYER_IN_COMBAT_CHANGED')
end
dodgeEvt:SetScript('OnEvent', function(_, event, arg1)
	if event == 'PLAYER_REGEN_DISABLED' then
		dodgeInCombat = true
	elseif event == 'PLAYER_REGEN_ENABLED' then
		dodgeInCombat = false
	elseif event == 'PLAYER_IN_COMBAT_CHANGED' then
		if not secret(arg1) then
			dodgeInCombat = arg1 and true or false
		end
	else
		dodgeInCombat = _G.InCombatLockdown() and true or false
		ApplyDodge()
	end
	RenderDodge()
end)

-- Elixir of Determination. The talent (455139) has no cooldown to read, and
-- the absorb it gives (455179) is secret in combat and often eaten within a
-- second, so neither can say when the next proc may come. The proc also casts
-- a hidden 15 s lockout spell on the player (455180), and a spell of the
-- player's own is announced in SPELL_UPDATE_COOLDOWN by its spell ID, whether
-- it has a cooldown or not. That payload carries no secret flag, so the event
-- starts a plain 15 s clock of ours: the icon counts from the proc itself,
-- however fast the shield goes. The ID is still tested for a secret before it
-- is compared - should a patch ever hide it, the icon goes quiet instead of
-- raising an error on every global cooldown.
local ELIXIR_ICON = 455179
local ELIXIR_TALENT = 455139
local ELIXIR_LOCKOUT = 455180
local ELIXIR_ICD, ELIXIR_LEFT = 15, 9

local elixHolder, elixIdle, elixRun, elixSample
local elixPreview, elixOn = false, false
local elixEnds, elixTimer = 0, nil
local elixStyleSig
local elixStats = { procs = 0, secret = 0 }
local ApplyElixir

local function ElixirWanted(cfg)
	return cfg.elixEnable and IsBrew()
end

-- Decides the bright "ready" icon and whether the event is listened to at
-- all; an unreadable answer counts as talented.
local function ElixirTalented() return ns.Ask(_G.IsPlayerSpell, ELIXIR_TALENT) ~= false end

local function ElixirSize(cfg) return mmax(12, cfg.elixSize or 40) end

local function MakeElixirFace(parent)
	local p = {}
	p.face = CreateFrame('Frame', nil, parent)
	p.face:SetPoint('CENTER', parent, 'CENTER', 0, 0)
	p.face:SetSize(40, 40)
	p.icon = ns.PixelBorderIcon(p.face)
	p.cd = CreateFrame('Cooldown', nil, p.face, 'CooldownFrameTemplate')
	p.cd:SetAllPoints(p.icon)
	p.cd:SetDrawEdge(false)
	p.cd:SetDrawBling(false)
	p.cd:SetReverse(false)
	p.cd.noCooldownCount = true
	return p
end

local function StyleElixirFace(p, cfg)
	local s = ElixirSize(cfg)
	p.face:SetSize(s, s)
	p.icon:SetTexture(ns.CdSpellTexture(ELIXIR_ICON))
	p.icon:SetTexCoord(ns.IconCoords(s, s, 0.08))
	p.icon:SetDesaturated(not p.bright)
	p.cd:SetDrawSwipe(cfg.elixSwipe ~= false)
	p.cd:SetHideCountdownNumbers(cfg.elixText == false)
	if p.cd.SetCountdownMillisecondsThreshold then pcall(p.cd.SetCountdownMillisecondsThreshold, p.cd, 0) end
	local ts = cfg.elixTextSize or 0
	if ts <= 0 then ts = mmax(10, ns.Round(s * 0.4)) end
	local ok, fs = pcall(p.cd.GetCountdownFontString, p.cd)
	if ok and fs then fs:SetFont(ns.GothamNarrowBlackFont(), ts, 'OUTLINE') end
end

local function ElixirHost(level)
	local f = CreateFrame('Frame', nil, elixHolder)
	f:SetAllPoints(elixHolder)
	f:SetFrameLevel(elixHolder:GetFrameLevel() + level)
	return f
end

local function EnsureElixirHolder()
	if elixHolder then return end
	elixHolder = MakeHolder('XerionUIElixirICD', 'elixX', 'elixY', 'elixLock', ApplyElixir)
	elixHolder:SetSize(40, 40)
	-- The bright icon sits under the grey one, which covers it for the 15 s.
	local idle = ElixirHost(1)
	elixIdle = { host = idle, p = MakeElixirFace(idle) }
	elixIdle.p.bright = true
	local run = ElixirHost(10)
	run:Hide()
	elixRun = { host = run, p = MakeElixirFace(run) }
end

local function EndElixirRun()
	elixTimer = nil
	elixEnds = 0
	elixRun.p.cd:Clear()
	elixRun.host:Hide()
end

-- The lockout itself means no second proc can land inside the 15 s, so a
-- repeat of the same cast's event changes nothing. A proc right at the end
-- can beat the old timer by a frame; that timer is cancelled so it cannot
-- end the new run.
local function StartElixirRun()
	local now = GetTime()
	if now < elixEnds then return end
	if elixTimer then elixTimer:Cancel() end
	elixEnds = now + ELIXIR_ICD
	elixStats.procs = elixStats.procs + 1
	elixStats.last = now
	elixRun.p.cd:SetCooldown(now, ELIXIR_ICD)
	elixRun.host:Show()
	elixTimer = C_Timer.NewTimer(ELIXIR_ICD, EndElixirRun)
end

local elixCdEvt = CreateFrame('Frame')
elixCdEvt:SetScript('OnEvent', function(_, _, spellID)
	if secret(spellID) then
		elixStats.secret = elixStats.secret + 1
	elseif spellID == ELIXIR_LOCKOUT then
		StartElixirRun()
	end
end)

-- Switching off only stops listening: a lockout already counting is real and
-- runs out on its own clock.
local function SetElixirLive(live)
	if live == elixOn then return end
	elixOn = live
	if live then
		elixCdEvt:RegisterEvent('SPELL_UPDATE_COOLDOWN')
	else
		elixCdEvt:UnregisterEvent('SPELL_UPDATE_COOLDOWN')
	end
end

-- The preview: frozen at 9 of 15 seconds. Built the first time it is shown;
-- restyled with the other faces after that.
local function ShowElixirSample(cfg)
	if not elixSample then
		if not elixPreview then return end
		local host = ElixirHost(30)
		elixSample = { host = host, p = MakeElixirFace(host) }
		StyleElixirFace(elixSample.p, cfg)
	end
	elixSample.host:SetShown(elixPreview)
	if elixPreview then
		local cd = elixSample.p.cd
		cd:SetCooldown(GetTime() - (ELIXIR_ICD - ELIXIR_LEFT), ELIXIR_ICD)
		if cd.Pause then pcall(cd.Pause, cd) end
	end
end

ApplyElixir = function()
	local cfg = GetCfg()
	local wanted = ElixirWanted(cfg)
	if not (wanted or elixPreview) then
		SetElixirLive(false)
		if elixHolder then elixHolder:Hide() end
		return
	end
	EnsureElixirHolder()
	local s = ElixirSize(cfg)
	elixHolder:SetSize(s, s)
	elixHolder:ClearAllPoints()
	elixHolder:SetPoint('CENTER', UIParent, 'CENTER', cfg.elixX or 0, cfg.elixY or -170)
	local live = wanted and not elixPreview and ElixirTalented()
	-- SPELLS_CHANGED lands here mid-fight too; the faces are only restyled
	-- when a look setting (or the font) really moved.
	local sig = s .. '|' .. tostring(cfg.elixSwipe) .. '|' .. tostring(cfg.elixText) .. '|'
		.. tostring(cfg.elixTextSize) .. '|' .. tostring(ns.GothamNarrowBlackFont())
	if sig ~= elixStyleSig then
		elixStyleSig = sig
		StyleElixirFace(elixIdle.p, cfg)
		StyleElixirFace(elixRun.p, cfg)
		if elixSample then StyleElixirFace(elixSample.p, cfg) end
	end
	elixIdle.host:SetShown(live and cfg.elixReady or false)
	ShowElixirSample(cfg)
	elixHolder:Show()
	SetElixirLive(live)
	elixHolder:EnableMouse(elixPreview and not cfg.elixLock)
end

-- SPELLS_CHANGED and TRAIT_CONFIG_UPDATED come in bursts; one pass a frame.
-- Monks only, as with the dodge events: for anyone else the icon is the
-- preview alone, and BMElixirSetPreview applies that itself.
local elixEvt = CreateFrame('Frame')
if ns.IsClass('MONK') then
	elixEvt:RegisterEvent('PLAYER_ENTERING_WORLD')
	elixEvt:RegisterUnitEvent('PLAYER_SPECIALIZATION_CHANGED', 'player')
	elixEvt:RegisterEvent('SPELLS_CHANGED')
	pcall(elixEvt.RegisterEvent, elixEvt, 'TRAIT_CONFIG_UPDATED')
end
elixEvt:SetScript('OnEvent', ns.Coalesce(ApplyElixir))

_G.SLASH_XERIONELIXIR1 = '/xerionelixir'
_G.SlashCmdList.XERIONELIXIR = function()
	local function p(...) print('|cffff7d0aXerionUI-Elixir|r', ...) end
	local cfg = GetCfg()
	local stats = elixStats
	p('enable =', cfg.elixEnable and 'on' or 'off', '| preview =', elixPreview and 'ON' or 'off',
		'| brewmaster =', IsBrew() and 'yes' or 'no',
		'| talented =', ElixirTalented() and 'yes' or '|cffff5555no|r')
	p('listening =', elixOn and 'yes' or 'no', '| procs seen =', stats.procs,
		'| secret payloads =', stats.secret > 0 and ('|cffff5555' .. stats.secret .. '|r') or 0)
	local now = GetTime()
	if now < elixEnds then
		p(('lockout: %.1f s left'):format(elixEnds - now))
	elseif stats.last then
		p(('last proc: %.0f s ago'):format(now - stats.last))
	end
end

-- A dragged slider asks on every step; one pass on the next frame answers all.
ns.BMApply = ns.Coalesce(function()
	RefreshOrbs()
	ApplyDodge()
	RenderDodge()
	ApplyElixir()
end)
ns.BMOrbIsPreview = function() return orbPreview end
ns.BMOrbSetPreview = function(state)
	orbPreview = state and true or false
	RefreshOrbs()
end
ns.BMDodgeIsPreview = function() return dodgePreview end
ns.BMDodgeSetPreview = function(state)
	dodgePreview = state and true or false
	ApplyDodge()
	RenderDodge()
end
ns.BMElixirIsPreview = function() return elixPreview end
ns.BMElixirSetPreview = function(state)
	elixPreview = state and true or false
	ApplyElixir()
end
