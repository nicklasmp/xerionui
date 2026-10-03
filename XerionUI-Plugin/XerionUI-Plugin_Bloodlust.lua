local _, ns = ...
local hooksecurefunc, C_Timer = ns.Probe('Bloodlust', hooksecurefunc, C_Timer)
local _G = _G

local CreateFrame = CreateFrame
local C_Timer = C_Timer
local C_UnitAuras = C_UnitAuras
local GetTime = GetTime
local mceil = math.ceil

local GPA = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
ns.hasBloodlust = GPA and true or false
if not ns.hasBloodlust then return end

if not ns.ReadyAlertSuppressed then
	local GetTime = GetTime
	local suppressUntil = 0
	function ns.ReadyAlertSuppressed() return GetTime() < suppressUntil end
	local function Bump(secs)
		local t = GetTime() + (secs or 6)
		if t > suppressUntil then suppressUntil = t end
	end
	local rs = CreateFrame('Frame')
	rs:RegisterEvent('PLAYER_ENTERING_WORLD')
	rs:RegisterEvent('CHALLENGE_MODE_START')
	rs:RegisterEvent('CHALLENGE_MODE_RESET')
	rs:RegisterEvent('START_TIMER')
	rs:SetScript('OnEvent', function(_, event, arg1, arg2)
		if event == 'START_TIMER' then
			local secs = tonumber(arg2) or 10
			if secs > 30 then secs = 30 end
			Bump(secs + 5)
		else
			Bump(6)
		end
	end)
end

local secret = ns.IsSecret

local SATED = ns.SATED_IDS
local BLOODLUST_ICON = 136012
local WOW_READY_SOUND = 'WoW: Raid Warning'
local LEGACY_DEFAULT_SOUND = '|cFF00FF00Kira - Bloodlust|r'
local DEFAULT_SOUND = WOW_READY_SOUND

local DEFAULTS = {
	enable = false,
	lock = false,
	iconSize = 48,
	textSize = 22,
	threshold = 5,
	x = 0,
	y = 150,
	soundEnabled = true,
	sound = DEFAULT_SOUND,
	ttsEnabled = false,
	ttsText = 'Bloodlust ready',
	ttsVolume = 100,
	ttsVoiceName = '',
	glow = true,
	glowType = 'pixel',
	glowColor = { 242 / 255, 242 / 255, 82 / 255, 1 },
	glowThickness = 2,
}

local function Migrate(cfg)
	if cfg.sound == 'Bloodlust' or cfg.sound == LEGACY_DEFAULT_SOUND then cfg.sound = DEFAULT_SOUND end
	ns.GlowMigrate(cfg, { 242 / 255, 242 / 255, 82 / 255, 1 })
end

local function GetCfg() return ns.ModuleCfg('bloodlust', DEFAULTS, Migrate) end
ns.BLGetCfg = GetCfg
-- The ready countdown icon is removed; the sound and optional speech alert remain.
GetCfg().enable = false

local function PlayReadySound(name)
	if name == WOW_READY_SOUND then
		local kit = _G.SOUNDKIT and _G.SOUNDKIT.RAID_WARNING
		if kit and _G.PlaySound then return _G.PlaySound(kit, 'Master') end
		return
	end
	return ns.PlaySoundByName(name)
end
ns.BLPlayReadySound = PlayReadySound

local function ReadyVoiceID()
	local V = _G.C_VoiceChat
	local voices = V and V.GetTtsVoices and V.GetTtsVoices()
	local wanted = tostring(GetCfg().ttsVoiceName or ''):lower()
	if wanted ~= '' and voices then
		for _, voice in ipairs(voices) do
			if voice.name and voice.name:lower() == wanted then return voice.voiceID end
		end
	end
	local S = _G.C_TTSSettings
	if S and S.GetVoiceOptionID then
		local ok, id = pcall(S.GetVoiceOptionID, 0)
		if ok and type(id) == 'number' then return id end
	end
	return voices and voices[1] and voices[1].voiceID
end

local function SpeakReady(force)
	local cfg = GetCfg()
	if not force and not cfg.ttsEnabled then return end
	local V = _G.C_VoiceChat
	local id = V and V.SpeakText and ReadyVoiceID()
	if type(id) ~= 'number' then return end
	local text = tostring(cfg.ttsText or '')
	if not text:find('%S') then text = 'Bloodlust ready' end
	if V.StopSpeakingText then pcall(V.StopSpeakingText) end
	C_Timer.After(0, function()
		local S = _G.C_TTSSettings
		local rate = S and S.GetSpeechRate and S.GetSpeechRate() or 0
		pcall(V.SpeakText, id, text, rate, cfg.ttsVolume or 100, true)
	end)
end
ns.BLTestTTS = function() SpeakReady(true) end

local function StopGlow(b)
	ns.GlowStop(b)
end

local function StartGlow(b)
	local cfg = GetCfg()
	local sz = cfg.iconSize or 48
	ns.GlowStart(b, sz, sz, cfg)
end

local frame, btn
local previewActive = false

local function ApplyPosition()
	if not frame then return end
	local cfg = GetCfg()
	frame:ClearAllPoints()
	frame:SetPoint('CENTER', _G.UIParent, 'CENTER', cfg.x or 0, cfg.y or 150)
end

local function EnsureFrame()
	if frame then return end
	frame = CreateFrame('Frame', 'XerionUIBloodlust', _G.UIParent)
	frame:SetFrameStrata('MEDIUM')
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(false)
	frame:RegisterForDrag('RightButton')
	ns.MakeDraggable(frame, GetCfg, 'x', 'y', function() ApplyPosition() end)
	btn = CreateFrame('Frame', nil, frame)
	btn.border = btn:CreateTexture(nil, 'BACKGROUND')
	btn.border:SetColorTexture(0, 0, 0, 1)
	btn.border:SetAllPoints()
	btn.Icon = btn:CreateTexture(nil, 'ARTWORK')
	btn.Icon:SetPoint('TOPLEFT', 1, -1)
	btn.Icon:SetPoint('BOTTOMRIGHT', -1, 1)
	btn.Icon:SetTexture(BLOODLUST_ICON)
	btn.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	btn.Cooldown = CreateFrame('Cooldown', nil, btn, 'CooldownFrameTemplate')
	btn.Cooldown:SetAllPoints()
	btn.Cooldown:SetDrawEdge(false)
	btn.Cooldown:SetDrawBling(false)
	btn.Cooldown:SetReverse(true)
	if btn.Cooldown.SetHideCountdownNumbers then btn.Cooldown:SetHideCountdownNumbers(true) end
	btn.Text = btn.Cooldown:CreateFontString(nil, 'OVERLAY')
	btn.Text:SetPoint('CENTER')
	frame:Hide()
end

local function ApplyVisual()
	if not frame then return end
	local cfg = GetCfg()
	local sz = cfg.iconSize or 48
	frame:SetSize(sz, sz)
	btn:SetSize(sz, sz)
	btn:ClearAllPoints()
	btn:SetPoint('CENTER', frame, 'CENTER', 0, 0)
	btn.Text:SetFont(ns.GetFont(), cfg.textSize or 22, 'OUTLINE')
	ApplyPosition()
end

-- Whether the countdown icon is up (ShowIcon) or was put away (HideIcon), so
-- the tick can skip a HideIcon that has nothing to hide. The preview draws
-- the same frame without setting it, and turning the preview off hides the
-- frame itself, so the flag can be stale only on the "shown" side - which
-- costs one redundant HideIcon, never a missed one.
local iconShown = false

local function HideIcon()
	iconShown = false
	if btn then
		StopGlow(btn)
		btn.__cdExp = nil
		btn.__textSec = nil -- see ShowIcon
		if btn.Cooldown then
			if btn.Cooldown.Clear then btn.Cooldown:Clear() else btn.Cooldown:SetCooldown(0, 0) end
		end
	end
	if frame and not previewActive then frame:Hide() end
end

-- The tick asks ten times a second and the number moves once a second, so the
-- text is only written when the whole second changes. Every other writer of
-- btn.Text (the preview) and HideIcon clear btn.__textSec, so the first second
-- after either is always written.
local function ShowIcon(rem, expTime)
	EnsureFrame()
	iconShown = true
	local sec = mceil(rem)
	if sec ~= btn.__textSec then
		btn.__textSec = sec
		btn.Text:SetText(tostring(sec))
	end
	if expTime then
		local thr = GetCfg().threshold or 5
		if btn.__cdExp ~= expTime then
			btn.__cdExp = expTime
			btn.Cooldown:SetCooldown(expTime - thr, thr)
		end
		btn.Cooldown:Show()
	end
	frame:Show()
	btn:Show()
	if not btn.__glow then StartGlow(btn) end
end

local satedActive = false
local satedExp = nil

-- The lockout that was found last is asked first: while it sits on the player
-- that is one lookup instead of a walk down the list.
local lastSated
local function CurrentSated()
	if lastSated then
		local a = GPA(SATED[lastSated])
		if a then return a end
	end
	for i = 1, #SATED do
		if i ~= lastSated then
			local a = GPA(SATED[i])
			if a then
				lastSated = i
				return a
			end
		end
	end
	return nil
end

local SyncTicker, ArmEndCheck

local function OnAura()
	local cfg = GetCfg()
	local a = CurrentSated()
	if a then
		satedActive = true
		local exp = a.expirationTime
		satedExp = (not secret(exp)) and exp or nil
	elseif satedActive then
		satedActive = false
		satedExp = nil
		HideIcon()
		if not previewActive and not (ns.ReadyAlertSuppressed and ns.ReadyAlertSuppressed()) then
			-- The sound follows its own switch only, not Enable: Enable is the
			-- countdown icon, and a player may want the ready sound without the
			-- icon. Gating it on Enable (2026-09-25) silenced exactly that setup.
			-- The Combat Text line has its own switch too.
			if cfg.soundEnabled then PlayReadySound(cfg.sound) end
			if cfg.ttsEnabled then SpeakReady() end
			if ns.CTAnnounce then ns.CTAnnounce('bloodlust') end
		end
	end
	ArmEndCheck()
	SyncTicker()
end

local function Tick()
	if previewActive then return end
	local cfg = GetCfg()
	if not cfg.enable or not satedActive or not satedExp then
		if iconShown then HideIcon() end
		return
	end
	local rem = satedExp - GetTime()
	if rem > 0 and rem <= (cfg.threshold or 5) then
		ShowIcon(rem, satedExp)
	elseif iconShown then
		HideIcon()
	end
end

-- SLEEP THROUGH SATED, WAKE FOR THE LAST SECONDS
-- Sated lasts ten minutes and the icon only matters in the last `threshold`
-- seconds, so instead of a 0.1 s ticker for the whole debuff this arms one
-- timer for the moment the window opens (the Potion module's pattern) and
-- runs the fast ticker only inside it. satedExp is the readable expiration
-- (OnAura drops a secret one to nil, and nil wants nothing, as before). Every
-- UNIT_AURA comes through here, so the wake timer is only re-armed when the
-- expiration or the threshold it was armed for actually changed. The 0.05 s
-- slack keeps a timer that fires a hair early from arming a second one; the
-- ticker starting that little ahead just hides nothing until the window
-- opens. Starting the ticker runs one tick at once, so the icon appears at
-- the threshold rather than up to 0.1 s after it.
local tickTicker, wakeTimer, wakeFor, wakeThr

local function StopTimers()
	local was = (tickTicker or wakeTimer) and true or false
	if tickTicker then tickTicker:Cancel() tickTicker = nil end
	if wakeTimer then wakeTimer:Cancel() wakeTimer = nil end
	wakeFor, wakeThr = nil, nil
	return was
end

local function Wake()
	wakeTimer, wakeFor, wakeThr = nil, nil, nil
	SyncTicker()
end

SyncTicker = function()
	local cfg = GetCfg()
	local want = (not previewActive) and satedActive and satedExp ~= nil
		and cfg.enable and true or false
	if not want then
		if StopTimers() then Tick() end
		return
	end
	local thr = cfg.threshold or 5
	local rem = satedExp - GetTime()
	if rem > thr + 0.05 then
		if tickTicker then
			tickTicker:Cancel()
			tickTicker = nil
			Tick()
		end
		if not (wakeTimer and wakeFor == satedExp and wakeThr == thr) then
			if wakeTimer then wakeTimer:Cancel() end
			wakeFor, wakeThr = satedExp, thr
			wakeTimer = C_Timer.NewTimer(rem - thr, Wake)
		end
	elseif not tickTicker then
		if wakeTimer then wakeTimer:Cancel() end
		wakeTimer, wakeFor, wakeThr = nil, nil, nil
		tickTicker = C_Timer.NewTicker(0.1, Tick)
		Tick()
	end
end

-- SLEEP THROUGH SATED, LOOK AGAIN WHEN IT RUNS OUT
-- Sated cannot be put on again while it is up, and it cannot be clicked off
-- or dispelled, so once it is found with a readable expiration the answer
-- cannot change before that moment. The event handler ignores every UNIT_AURA
-- until then, and this timer looks once just after it - the removal's own
-- UNIT_AURA usually gets there first, and a look that finds Sated gone a second
-- time plays nothing (OnAura only sounds on the active -> gone edge). A secret
-- expiration arms nothing and keeps the look on every event, as before. The
-- cost of the rule: if something ever did take Sated off early, the ready
-- sound would come at the time Sated was due to end.
local endTimer, endFor

local function EndCheck()
	endTimer, endFor = nil, nil
	OnAura()
end

ArmEndCheck = function()
	if satedActive and satedExp then
		if endTimer and endFor == satedExp then return end
		if endTimer then endTimer:Cancel() end
		endFor = satedExp
		local rem = satedExp - GetTime()
		endTimer = C_Timer.NewTimer((rem > 0 and rem or 0) + 0.1, EndCheck)
	elseif endTimer then
		endTimer:Cancel()
		endTimer, endFor = nil, nil
	end
end

local function ShowPreview()
	EnsureFrame()
	ApplyVisual()
	local thr = GetCfg().threshold or 5
	btn.Text:SetText(tostring(thr))
	btn.__textSec = nil -- see ShowIcon
	btn.__cdExp = nil
	btn.Cooldown:SetCooldown(GetTime(), thr)
	btn.Cooldown:Show()
	frame:Show()
	btn:Show()
	StartGlow(btn)
end

local function Apply()
	EnsureFrame()
	ApplyVisual()
	frame:EnableMouse(previewActive and not GetCfg().lock or false)
	if previewActive then ShowPreview() else HideIcon() end
	SyncTicker()
end
ns.BLApply = ns.Coalesce(function() Apply() end)

ns.BLIsPreview = function() return previewActive end
ns.BLSetPreview = function(state)
	previewActive = state and true or false
	EnsureFrame()
	frame:EnableMouse(previewActive and not GetCfg().lock or false)
	if previewActive then
		ShowPreview()
	else
		StopGlow(btn)
		frame:Hide()
	end
	SyncTicker()
end

local evt = CreateFrame('Frame')
evt:RegisterUnitEvent('UNIT_AURA', 'player')
evt:RegisterEvent('PLAYER_ENTERING_WORLD')
-- UPDATE-ONLY AURA EVENTS
-- Every lookup above hands back a fresh aura table, and the player's UNIT_AURA
-- fires several times a second in combat: in a +20 on 2026-09-28 this handler made
-- 16.7 MB of garbage, about 1.8 KB per event. A payload that only refreshed or
-- restacked auras cannot put Sated on or take it off, so it is skipped when the
-- answer cannot move: Sated absent, or present with its expiration already read.
-- Sated present with a secret expiration still looks every time, so the moment
-- the expiration turns readable is caught as before. AuraPayloadChurns counts a
-- secret or unreadable payload as a change, so in restricted content nothing is
-- skipped that was looked at before.
-- That left keys untouched: there the payload is secret, and two keys on
-- 2026-09-28 still made 16-18 MB each here (6.4 events a second, 1.6-1.7 KB
-- each - the aura table of a Sated that is up most of a key). So while a Sated
-- with a readable expiration is up, the handler returns before any of this and
-- the end-time timer above does the one look that matters.
evt:SetScript('OnEvent', function(_, event, _, info)
	if event == 'PLAYER_ENTERING_WORLD' then
		local a = CurrentSated()
		satedActive = a and true or false
		if a then
			local exp = a.expirationTime
			satedExp = (not secret(exp)) and exp or nil
		else
			satedExp = nil
		end
		C_Timer.After(0.5, Apply)
		ArmEndCheck()
		SyncTicker()
		return
	end
	if satedActive and satedExp and GetTime() < satedExp then return end
	if (not satedActive or satedExp) and not ns.AuraPayloadChurns(info) then return end
	OnAura()
end)

SLASH_XERIONLUST1 = '/xerionlust'
SlashCmdList.XERIONLUST = function()
	local a = CurrentSated()
	if not a then print('|cffff7d0aKiraLust|r: no Sated/Exhaustion debuff on you right now.') return end
	local exp = a.expirationTime
	if secret(exp) then
		print('|cffff7d0aKiraLust|r Sated present. remaining = SECRET.')
		print('|cffff2020=> the early-warning icon cannot time it; the ready sound still works.|r')
	elseif exp == nil then
		print('|cffff7d0aKiraLust|r Sated present, but no expirationTime.')
	else
		print(('|cffff7d0aKiraLust|r Sated present. remaining = %.1f sec (readable).'):format(exp - GetTime()))
		print('|cff20ff20=> the early-warning icon will work.|r')
	end
end
