local _, ns = ...
local hooksecurefunc, C_Timer = ns.Probe('EUIFocusKick', hooksecurefunc, C_Timer)
local _G = _G

-- WHAT IT DOES
-- One alert added to EllesmereUI's FocusKick (the Cooldown Manager's kick bar
-- on the focus nameplate): it plays when BOTH are true - the FocusKick
-- interrupt is off cooldown AND the FocusKick unit is casting something that
-- can be interrupted. Either can come second, so it rings at two moments:
--   * the unit starts a cast or channel while the kick is ready, or
--   * the kick comes off cooldown while that cast is still going.
-- A cast that loses its "cannot be interrupted" shield midway, with the kick
-- ready, rings too. The user asked for exactly one sound on 2026-09-29 (an
-- earlier build of the same day had separate kick-ready and cast alerts).
-- Both halves follow FocusKick's own setup: the interrupt is the one picked in
-- its options, else the first spell on its bar this spec can cast (the same id
-- EllesmereUI's own Focus Cast Sound checks), and the unit is "focus", or
-- "target" when its Show on Target switch is on. With an empty FocusKick bar
-- the plugin's own interrupt list (Nameplate Interrupt) stands in.
--
-- WHY IT IS TTS AND NEVER A SOUND FILE
-- Whether a cast can be interrupted is the notInterruptible return of
-- UnitCastingInfo / UnitChannelInfo, SecretWhenUnitSpellCastRestricted: a
-- secret boolean for any unit that is not the player or their pet, unless
-- Blizzard flags that spell never-secret. It is the same flag EllesmereUI's
-- Targeted Spell Bars colour interruptible casts by (e._kickProtected, painted
-- with SetAlphaFromBoolean / EvaluateColorValueFromBoolean) - drawing calls
-- take secrets, so the colour works without Lua ever knowing the answer. Lua
-- cannot branch on it, and PlaySoundFile / PlaySound refuse secret arguments
-- from addon code, so a sound FILE can follow every cast (what EllesmereUI's
-- own Focus Cast Sound does - its comment says so) or none, never only the
-- interruptible ones. On 2026-09-29 the build went voice-only, then got an
-- Audio choice back, then TTS first; once the user saw Audio could not stay
-- silent on protected casts in keys they asked for it to be removed. TTS only,
-- with the user's text, volume and voice - do not add a sound-file choice.
-- C_VoiceChat.SpeakText is the one sound call that takes a secret from addon
-- code (text is ConditionalSecret, AllowedWhenTainted), so the engine makes
-- the choice and Lua never sees it:
--   C_CurveUtil.EvaluateColorValueFromBoolean(notInterruptible, 0, 1)
--                                             secret 0 (protected) or 1
--   C_StringUtil.TruncateWhenZero(n)          secret '' or '1'
--   C_StringUtil.WrapString(s, '<silence msec="', '"/>Kick')
--                                             '' or '<silence msec="1"/>Kick'
-- All three are AllowedWhenTainted. The '1' disappears into a 1 ms silence
-- tag (SpeakText's doc: XML TTS tags work on Windows; the Mac client gets its
-- own [[slnc 1]] command), so an interruptible cast says the words and a
-- protected one says nothing. Where the flag is readable it is used directly.
-- The Test button runs the same gated path with a plain "interruptible", so a
-- client that reads the tag out loud instead of obeying it shows up outside a
-- key.
-- UNIT_SPELLCAST_INTERRUPTIBLE carries only the unit, never a secret: it is a
-- plain "this cast just lost its shield", so it rings outright in both modes.
--
-- The kick half needs nothing secret: C_Spell.GetSpellCooldown's isActive is
-- readable for the player's own spells (ns.SpellDurationRunning), and a
-- Cooldown frame fed the duration object calls OnCooldownDone the moment it
-- runs out - SPELL_UPDATE_COOLDOWN does not reliably fire when a cooldown
-- ends. The same trick the core's cooldown pulse uses.
--
-- Built 2026-09-29, untested in-game. /xerionfk prints what it sees.

local function CDM()
	local E = _G.EllesmereUI
	local reg = E and E._ModuleNS
	return reg and reg.EllesmereUICooldownManager
end

ns.hasEUIFocusKick = (CDM() ~= nil)
if not ns.hasEUIFocusKick then return end

local CreateFrame = CreateFrame
local GetTime = GetTime
local ipairs, pcall, type, tostring = ipairs, pcall, type, tostring
local format = string.format
local UnitExists, UnitCanAttack = UnitExists, UnitCanAttack
local UnitCastingInfo, UnitChannelInfo = UnitCastingInfo, UnitChannelInfo
local IsPlayerSpell = IsPlayerSpell
local C_Spell = C_Spell
local secret = ns.IsSecret

local EvalBool = _G.C_CurveUtil and _G.C_CurveUtil.EvaluateColorValueFromBoolean
local StrUtil = _G.C_StringUtil
local TruncateWhenZero = StrUtil and StrUtil.TruncateWhenZero
local WrapString = StrUtil and StrUtil.WrapString
local CAN_GATE = (EvalBool and TruncateWhenZero and WrapString) and true or false
local IS_MAC = (_G.IsMacClient and _G.IsMacClient()) and true or false

local FK_KEY = 'focuskick'
-- A second "kick is back" inside this window is the same cooldown seen twice
-- (the frame's end and a late read). No interrupt is shorter than about 9 s.
local READY_GAP = 1
-- UNIT_SPELLCAST_INTERRUPTIBLE this soon after the cast began belongs to the
-- start, which has already made its choice.
local SHIELD_AFTER_START = 0.3

local DEFAULTS = {
	enable = false,
	text = 'Kick',
	voiceVolume = 100,
	voiceName = 'Zira',
}

-- Earlier builds of 2026-09-29: the first had a kick-ready alert and a cast
-- alert (on here if either was, the cast alert's words kept); later ones had
-- an Audio/TTS choice (`mode`, then `alert`) and a sound file (`sound`).
local OLD_KEYS = {
	'readyEnable', 'readyFocusOnly', 'readyMode', 'readyText', 'readySound',
	'castEnable', 'castReadyOnly', 'castMode', 'castText', 'castSound',
	'mode', 'alert', 'sound',
}
local function Migrate(cfg)
	if cfg.castEnable ~= nil or cfg.readyEnable ~= nil then
		cfg.enable = (cfg.castEnable or cfg.readyEnable) and true or false
		if type(cfg.castText) == 'string' then cfg.text = cfg.castText end
	end
	for _, k in ipairs(OLD_KEYS) do cfg[k] = nil end
end

local function GetCfg() return ns.ModuleCfg('euiFocusKick', DEFAULTS, Migrate) end
ns.EFKGetCfg = GetCfg

local stats = { rang = 0, onStart = 0, onKick = 0, shield = 0, plainSkip = 0, hidden = 0, busy = 0 }
local lastDecision = 'none yet'

-- FOCUSKICK'S SETUP
local function FKBar()
	local m = CDM()
	local byKey = m and m.barDataByKey
	return byKey and byKey[m.FOCUSKICK_BAR_KEY or FK_KEY], m
end

-- EllesmereUI's GetFocusKickUnit: 'target' with Show on Target, else 'focus'.
local function WatchUnit()
	local m = CDM()
	local f = m and m.GetFocusKickUnit
	if f then
		local ok, u = pcall(f)
		if ok and (u == 'focus' or u == 'target') then return u end
	end
	return 'focus'
end

function ns.EFKEUISoundOn()
	local bd = FKBar()
	local k = bd and bd.focusCastSoundKey
	return type(k) == 'string' and k ~= 'none'
end

-- The interrupt, found the way EllesmereUI's cast sound finds it, then the
-- plugin's list. Returns id (false for none) and where it came from.
local function ResolveKick()
	local bd, m = FKBar()
	local resolve = m and m.ResolveCastableInterrupt
	if bd and resolve then
		local pick = bd.focusKickInterruptSpellID
		if type(pick) == 'number' and pick > 0 then
			local ok, id = pcall(resolve, pick)
			if ok and id then return id, 'FocusKick pick' end
		end
		local ok, sd = pcall(m.GetBarSpellData, m.FOCUSKICK_BAR_KEY or FK_KEY)
		local spells = ok and type(sd) == 'table' and sd.assignedSpells
		if type(spells) == 'table' then
			for _, sid in ipairs(spells) do
				if type(sid) == 'number' and sid > 0 then
					local ok2, id = pcall(resolve, sid)
					if ok2 and id then return id, 'FocusKick bar' end
				end
			end
		end
	end
	local scan = ns.EUIIntScanKick
	local id = scan and scan()
	if id then return id, 'plugin list' end
	return false, 'none'
end

-- VOICE
-- Blightfall / Combat Text pattern: a voice whose name holds cfg.voiceName,
-- else the game's own TTS voice, else the first installed one. The voice list
-- is only asked again when the name setting changes (GetTtsVoices is slow).
local voiceFor, voiceByName, firstVoice
local function LookupVoice(want)
	local V = _G.C_VoiceChat
	local voices = V and V.GetTtsVoices and V.GetTtsVoices()
	if type(voices) ~= 'table' or not voices[1] then
		voiceFor, voiceByName, firstVoice = nil, nil, nil
		return
	end
	voiceFor, voiceByName, firstVoice = want, nil, voices[1].voiceID
	if want == '' then return end
	for _, v in ipairs(voices) do
		if v.name and v.name:lower():find(want, 1, true) then voiceByName = v.voiceID break end
	end
end

local function VoiceID()
	local want = tostring(GetCfg().voiceName or ''):lower()
	if want ~= voiceFor then LookupVoice(want) end
	if type(voiceByName) == 'number' then return voiceByName end
	local S = _G.C_TTSSettings
	if S and S.GetVoiceOptionID then
		local ok, id = pcall(S.GetVoiceOptionID, 0)
		if ok and type(id) == 'number' then return id end
	end
	return firstVoice
end

-- text may be a secret string; SpeakText takes it as it is.
local function Say(text)
	local V = _G.C_VoiceChat
	if not (V and V.SpeakText) then return end
	local id = VoiceID()
	if type(id) ~= 'number' then return end
	local S = _G.C_TTSSettings
	local rate = S and S.GetSpeechRate and S.GetSpeechRate() or 0
	pcall(V.SpeakText, id, text, rate, GetCfg().voiceVolume or 100, true)
end

local function XmlEscape(s)
	return (s:gsub('&', '&amp;'):gsub('<', '&lt;'):gsub('>', '&gt;'))
end

-- notInt may be secret. The words when the cast can be interrupted, '' when
-- it cannot - chosen inside the engine (see the top of the file).
local function GatedWords(words, notInt)
	local digit = TruncateWhenZero(EvalBool(notInt, 0, 1))
	if IS_MAC then return WrapString(digit, '[[slnc ', ']]' .. words) end
	return WrapString(digit, '<silence msec="', '"/>' .. XmlEscape(words))
end

local function Words()
	local w = GetCfg().text
	if type(w) ~= 'string' or not w:find('%S') then return DEFAULTS.text end
	return w
end

-- The alert, its answer already known in Lua.
local function Play()
	stats.rang = stats.rang + 1
	Say(Words())
end

-- THE CAST HALF
local function Hostile(unit)
	local ok, v = pcall(UnitCanAttack, 'player', unit)
	if not ok or secret(v) then return true end
	return v and true or false
end

-- name (nil = not casting) and notInterruptible, either possibly secret.
local function CastState(unit, channel)
	if channel then
		local name, _, _, _, _, _, notInt = UnitChannelInfo(unit)
		return name, notInt
	end
	local name, _, _, _, _, _, _, notInt = UnitCastingInfo(unit)
	return name, notInt
end

-- The unit's current cast: channel nil = look at both. Rings when it can be
-- interrupted (or, hidden, lets the engine decide). Returns casting (false
-- when the unit is not casting at all) and played (a gated voice counts: the
-- engine may still say nothing).
local function RingForCast(unit, channel, why)
	local ok, name, notInt
	if channel == nil then
		ok, name, notInt = pcall(CastState, unit, false)
		if not ok or type(name) == 'nil' then ok, name, notInt = pcall(CastState, unit, true) end
	else
		ok, name, notInt = pcall(CastState, unit, channel)
	end
	if not ok or type(name) == 'nil' then return false end
	if not secret(notInt) then
		if notInt then
			stats.plainSkip = stats.plainSkip + 1
			lastDecision = why .. ': readable, cannot be interrupted - silent'
			return true, false
		end
		lastDecision = why .. ': readable, interruptible - rang'
		Play()
		return true, true
	end
	stats.hidden = stats.hidden + 1
	if not CAN_GATE then
		lastDecision = why .. ': hidden, this client lacks the voice gate - silent'
		return true, false
	end
	local okText, text = pcall(GatedWords, Words(), notInt)
	if okText and type(text) == 'string' then
		lastDecision = why .. ': hidden - voice gated by the engine'
		stats.rang = stats.rang + 1
		Say(text)
		return true, true
	end
	lastDecision = why .. ': hidden, voice gate failed (' .. tostring(text) .. ')'
	return true, false
end

-- THE KICK HALF
local kickID, kickPet, kickFrom -- kickID nil = look again, false = none
local tracker, armed, lastReadyAt = nil, false, -READY_GAP
local ReadKick

local function Kick()
	if kickID == nil then
		kickID, kickFrom = ResolveKick()
		kickPet = (kickID and not IsPlayerSpell(kickID)) and true or false
	end
	return kickID or nil
end

-- running, duration object (nil for a spell the duration API does not know,
-- which leaves the polling below to catch its end).
local function KickState(id)
	local dur, charges = ns.SpellFetchDuration(id)
	if dur then return ns.SpellDurationRunning(id, dur, charges), dur end
	local info = C_Spell.GetSpellCooldown(id)
	return (info and info.isActive and not info.isOnGCD) and true or false, nil
end

-- true = on cooldown, false = ready, nil = no interrupt (or an unreadable one).
local function KickBusy()
	local id = Kick()
	if not id then return nil end
	local ok, running = pcall(KickState, id)
	if not ok then return nil end
	return running
end

-- The kick just came back: ring if the unit is mid-cast right now.
local function KickBack()
	local now = GetTime()
	if now - lastReadyAt < READY_GAP then return end
	lastReadyAt = now
	if not GetCfg().enable then return end
	local unit = WatchUnit()
	if not UnitExists(unit) or not Hostile(unit) then return end
	local _, played = RingForCast(unit, nil, 'kick back mid-cast')
	if played then stats.onKick = stats.onKick + 1 end
end

local function OnDone()
	if not armed then return end
	armed = false
	KickBack()
end

local function EnsureTracker()
	if tracker then return tracker end
	local bucket = CreateFrame('Frame', nil, _G.UIParent)
	bucket:SetSize(1, 1)
	bucket:SetPoint('BOTTOMLEFT', _G.UIParent, 'BOTTOMLEFT', -10000, -10000)
	bucket:Show()
	tracker = CreateFrame('Cooldown', nil, bucket, 'CooldownFrameTemplate')
	tracker:SetAllPoints(bucket)
	tracker:SetDrawSwipe(false)
	tracker:SetDrawEdge(false)
	tracker:SetDrawBling(false)
	tracker:SetHideCountdownNumbers(true)
	tracker.noCooldownCount = true
	tracker:SetScript('OnCooldownDone', OnDone)
	return tracker
end

local rereadQueued = false
local function QueueReread(delay)
	if rereadQueued then return end
	rereadQueued = true
	C_Timer.After(delay, function()
		rereadQueued = false
		ReadKick()
	end)
end

ReadKick = function()
	local id = Kick()
	if not id then armed = false return end
	local ok, running, dur = pcall(KickState, id)
	if not ok then return end
	if running then
		-- Right after the kick came back a read can still say "running" for
		-- the cooldown that just ended; arming on it would ring twice. Look
		-- again once the window has passed, so a kick pressed at once is still
		-- caught.
		local since = GetTime() - lastReadyAt
		if since < READY_GAP then QueueReread(READY_GAP - since + 0.05) return end
		armed = true
		if dur then
			local t = EnsureTracker()
			pcall(t.SetCooldownFromDurationObject, t, dur)
		else
			QueueReread(0.25)
		end
	elseif armed then
		-- Ended early: a reset or a refund that finished it outright.
		armed = false
		if tracker then tracker:Clear() end
		KickBack()
	end
end

-- A different interrupt (talents, spec, pet, the FocusKick pick) starts clean,
-- so the old spell's cooldown never rings for the new one.
local function RefreshKick()
	local oldID = kickID
	kickID = nil
	local id = Kick()
	if id ~= oldID then
		armed = false
		if tracker then tracker:Clear() end
	end
	return id
end

-- CAST EVENTS
local lastStartAt = 0

local function OnCast(event, unit)
	if unit ~= WatchUnit() then return end
	if not GetCfg().enable then return end
	local shield = (event == 'UNIT_SPELLCAST_INTERRUPTIBLE')
	local now = GetTime()
	if shield then
		if now - lastStartAt < SHIELD_AFTER_START then return end
	else
		lastStartAt = now
	end
	if not Hostile(unit) then return end
	if KickBusy() ~= false then
		-- On cooldown (or no interrupt): the kick half rings later if this
		-- cast is still going when the kick comes back.
		stats.busy = stats.busy + 1
		lastDecision = 'cast started, kick on cooldown - waiting for the kick'
		return
	end

	if shield then
		local ok, name = pcall(CastState, unit, false)
		if not ok or type(name) == 'nil' then
			ok, name = pcall(CastState, unit, true)
		end
		if not ok or type(name) == 'nil' then return end
		stats.shield = stats.shield + 1
		lastDecision = 'shield dropped mid-cast - rang'
		Play()
		return
	end

	local _, played = RingForCast(unit, event == 'UNIT_SPELLCAST_CHANNEL_START', 'cast started, kick ready')
	if played then stats.onStart = stats.onStart + 1 end
end

-- DRIVERS
local pendingRead = false
local function RunRead()
	pendingRead = false
	ReadKick()
end
local function QueueRead()
	if pendingRead then return end
	pendingRead = true
	C_Timer.After(0, RunRead)
end

-- SPELL_UPDATE_COOLDOWN fires many times a second in combat; one naming a
-- readable spell that is not the interrupt cannot move it and is dropped. A
-- pet's interrupt keeps every event (its cooldown is the pet's, see
-- EUIInterrupt), as does anything before the interrupt is known.
local function OtherSpell(id, base)
	if id == nil or secret(id) then return false end
	if not kickID or kickPet then return false end
	if id == kickID then return false end
	if base ~= nil and not secret(base) and base == kickID then return false end
	return true
end

local f = CreateFrame('Frame')
f:SetScript('OnEvent', function(_, event, a1, a2)
	if event == 'SPELL_UPDATE_COOLDOWN' then
		if OtherSpell(a1, a2) then return end
		QueueRead()
	elseif event == 'SPELL_UPDATE_CHARGES' or event == 'PET_BAR_UPDATE_COOLDOWN' then
		QueueRead()
	elseif event == 'UNIT_SPELLCAST_START' or event == 'UNIT_SPELLCAST_CHANNEL_START'
		or event == 'UNIT_SPELLCAST_INTERRUPTIBLE' then
		OnCast(event, a1)
	else
		-- Spells, spec, pet, combat start: whatever may change the interrupt
		-- or the FocusKick pick behind it.
		RefreshKick()
		QueueRead()
	end
end)

local driversOn = false
local function SyncDrivers()
	local want = GetCfg().enable and true or false
	f:UnregisterAllEvents()
	driversOn = want
	if not want then
		armed = false
		if tracker then tracker:Clear() end
		return
	end
	f:RegisterEvent('SPELLS_CHANGED')
	f:RegisterEvent('PLAYER_REGEN_DISABLED')
	f:RegisterUnitEvent('PLAYER_SPECIALIZATION_CHANGED', 'player')
	f:RegisterUnitEvent('UNIT_PET', 'player')
	f:RegisterEvent('SPELL_UPDATE_COOLDOWN')
	f:RegisterEvent('SPELL_UPDATE_CHARGES')
	f:RegisterEvent('PET_BAR_UPDATE_COOLDOWN')
	-- Both tokens: FocusKick's Show on Target can switch between them at any
	-- time, and OnCast drops the one it is not following.
	f:RegisterUnitEvent('UNIT_SPELLCAST_START', 'focus', 'target')
	f:RegisterUnitEvent('UNIT_SPELLCAST_CHANNEL_START', 'focus', 'target')
	f:RegisterUnitEvent('UNIT_SPELLCAST_INTERRUPTIBLE', 'focus', 'target')
end

ns.EFKApply = function()
	SyncDrivers()
	if driversOn then
		RefreshKick()
		ReadKick()
	end
end

ns.EFKTest = function()
	if CAN_GATE then
		-- The gated path with a plain "interruptible": what a key does.
		local ok, text = pcall(GatedWords, Words(), false)
		if ok and type(text) == 'string' then Say(text) return end
	end
	Play()
end

_G.SLASH_XERIONFOCUSKICK1 = '/xerionfk'
_G.SlashCmdList.XERIONFOCUSKICK = function()
	local cfg = GetCfg()
	local id = RefreshKick()
	local name = id and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
	local busy = KickBusy()
	local unit = WatchUnit()
	ns.Msg(format('FocusKick Sound: kick %s %s (%s), %s; watching %s (%s).',
		tostring(id or 'none'), tostring(name or ''), tostring(kickFrom),
		busy == nil and 'cooldown unknown' or (busy and 'on cooldown' or 'ready'),
		unit, UnitExists(unit) and 'exists' or 'none'))
	ns.Msg(format('Alert %s: %d rang - %d at cast start, %d when the kick came back mid-cast, %d shield drops; %d casts while the kick was on cooldown, %d readable protected, %d hidden.',
		cfg.enable and 'on' or 'off', stats.rang, stats.onStart, stats.onKick, stats.shield,
		stats.busy, stats.plainSkip, stats.hidden))
	ns.Msg('Last: ' .. lastDecision .. '.')
	ns.Msg(format('Voice id %s, engine gate %s%s. EllesmereUI\'s own Focus Cast Sound: %s.',
		tostring(VoiceID()), CAN_GATE and 'available' or 'missing', IS_MAC and ' (Mac)' or '',
		ns.EFKEUISoundOn() and 'ON (plays on every cast too)' or 'off'))
end
