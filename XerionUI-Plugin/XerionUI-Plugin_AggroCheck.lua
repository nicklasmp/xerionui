local _, ns = ...
local hooksecurefunc, C_Timer = ns.Probe('AggroCheck', hooksecurefunc, C_Timer)
local _G = _G

local CreateFrame = CreateFrame
local UIParent = UIParent
local UnitThreatSituation = UnitThreatSituation
local UnitAffectingCombat = UnitAffectingCombat
local GetTime = GetTime
local pcall, type, tostring, format, ipairs = pcall, type, tostring, string.format, ipairs
local mmax = math.max

local secret = ns.IsSecret
local Msg = ns.Msg

-- WHY THIS FILE EXISTS
-- A dps or healer who pulls aggro in a key usually finds out from their own
-- health bar dropping. The nameplate colour and the raid frame border do say
-- it, but they are small and off to the side of where the eyes are during a
-- pull. This module puts one big red word in the middle of the screen for the
-- one fact that matters at that moment: the mob is on you, not the tank.
--
-- WHAT IT DOES
-- Listens to UNIT_THREAT_SITUATION_UPDATE for the player and asks
-- UnitThreatSituation('player') - the one-token form, which reports the
-- player against everything on their threat table at once. 2 and 3 mean the
-- player is tanking something (insecurely or securely); 0 and 1 mean the mob
-- is on somebody else. The text shows for 2 and 3 and hides otherwise, when
-- the fight ends, when the player's spec is a tank, and outside a Mythic+ key
-- unless the key-only toggle is off.
--
-- SECRETS
-- UnitThreatSituation is SecretWhenUnitThreatStateRestricted, but Blizzard's
-- note on that predicate says queries with only one unit token "are generally
-- not secret", and CompactUnitFrame_UpdateAggroHighlight relies on exactly
-- that to colour the raid frames. Should the client hand back a secret anyway,
-- the module cannot know whether the player has aggro, so it hides the text
-- and counts the read for /xerionaggro. That is the opposite of the class/spec
-- gate rule (unreadable means allow): a gate that fails closed hides a feature
-- from the player it is for, but a signal that fails open would shout AGGRO at
-- a player who has none.
--
-- ROLE
-- The role comes from the spec, the same way Co-Tank decides it: the role you
-- listed a group under sticks server-side through a respec, so
-- UnitGroupRolesAssigned('player') can say TANK for a dps. An unreadable spec
-- means the text is allowed.
--
-- The text frame never takes the mouse outside preview: it sits in the middle
-- of the screen during combat and must stay click-through.
--
-- SOUND
-- One sound when the text comes up for real aggro, never for the preview (the
-- sound dropdown already plays its pick). Threat can bounce between the player
-- and the tank several times a second while the tank catches up, so a sound
-- inside SOUND_GAP of the last one is dropped instead of stacking.
--
-- PREFIX
-- The exports are AGC, not AG: Auto Gossip already owns ns.AGGetCfg and loads
-- later in the TOC, so a shared name hands the settings page Auto Gossip's
-- table. That happened until 2026-09-23 and Migrate below still cleans up
-- after it.

ns.hasAggroCheck = true

local DEFAULT_SOUND = '|cFF00FF00Kira - On You|r'
local SOUND_GAP = 2

local DEFAULTS = {
	enable = false,
	text = 'AGGRO',
	color = { 1, 0.15, 0.15, 1 },
	fontSize = 32,
	pulse = true,
	keyOnly = true,
	lock = false,
	x = 0,
	y = 180,
	soundEnabled = true,
	sound = DEFAULT_SOUND,
}

-- Keys the Aggro Check page wrote into db.autoGossip while the two modules
-- shared ns.AGGetCfg. Auto Gossip has none of them, so anything found there
-- came from this page and is what the player last set. enable is not on the
-- list: both pages wrote the same autoGossip.enable, and it cannot say which
-- of the two it was meant for.
local STRAYED = { 'text', 'color', 'fontSize', 'pulse', 'keyOnly', 'lock', 'x', 'y' }

local function Migrate(cfg)
	local db = _G.XerionUIChangesDB
	local gossip = db and db.autoGossip
	if type(gossip) == 'table' then
		for _, k in ipairs(STRAYED) do
			if gossip[k] ~= nil then
				cfg[k] = gossip[k]
				gossip[k] = nil
			end
		end
	end
	if type(cfg.color) ~= 'table' then cfg.color = { 1, 0.15, 0.15, 1 } end
	if type(cfg.text) ~= 'string' or cfg.text == '' then cfg.text = 'AGGRO' end
end

local function GetCfg() return ns.ModuleCfg('aggroCheck', DEFAULTS, Migrate) end
ns.AGCGetCfg = GetCfg

local frame, text, pulse
local previewActive = false
local inCombat = false
local lastStatus = nil
local secretReads = 0
local lastSound = 0

local function ReadCombat()
	local ok, v = pcall(UnitAffectingCombat, 'player')
	inCombat = ok and not secret(v) and v and true or false
end

-- EVENTS ONLY WHILE ON
-- Threat changes several times a second in a pull, so these listen only while
-- the enable box is ticked. The preview needs none of them: it shows whatever
-- the gates say. PLAYER_ENTERING_WORLD stays registered for good (bottom of
-- the file), it is the re-apply after a loading screen.
local LIVE_EVENTS = {
	'PLAYER_REGEN_DISABLED', 'PLAYER_REGEN_ENABLED', 'PLAYER_SPECIALIZATION_CHANGED',
	'CHALLENGE_MODE_START', 'CHALLENGE_MODE_COMPLETED', 'CHALLENGE_MODE_RESET',
}
local evt = CreateFrame('Frame')
local live = false

local function SetLive(on)
	on = on and true or false
	if on == live then return end
	live = on
	if on then
		-- Combat went unwatched while off.
		ReadCombat()
		evt:RegisterUnitEvent('UNIT_THREAT_SITUATION_UPDATE', 'player')
		for _, e in ipairs(LIVE_EVENTS) do evt:RegisterEvent(e) end
	else
		evt:UnregisterEvent('UNIT_THREAT_SITUATION_UPDATE')
		for _, e in ipairs(LIVE_EVENTS) do evt:UnregisterEvent(e) end
	end
end

local function PlayerIsTank()
	local spec, unreadable = ns.PlayerSpec()
	if unreadable then return false end
	if not spec then return false end
	local get = (_G.C_SpecializationInfo and _G.C_SpecializationInfo.GetSpecializationRole) or _G.GetSpecializationRole
	if not get then return false end
	local ok, role = pcall(get, spec)
	if not ok or secret(role) then return false end
	return role == 'TANK'
end

local function KeyActive()
	local CM = _G.C_ChallengeMode
	if not CM then return false end
	if CM.IsChallengeModeActive then
		local ok, v = pcall(CM.IsChallengeModeActive)
		if ok and not secret(v) and v then return true end
	end
	if CM.GetActiveChallengeMapID then
		local ok, id = pcall(CM.GetActiveChallengeMapID)
		if ok and not secret(id) and id then return true end
	end
	return false
end

-- true only when the client says, in the clear, that a mob is on the player.
local function HasAggro()
	if not UnitThreatSituation then return false end
	local ok, status = pcall(UnitThreatSituation, 'player')
	if not ok then lastStatus = 'error' return false end
	if secret(status) then
		secretReads = secretReads + 1
		lastStatus = 'secret'
		return false
	end
	lastStatus = status
	return type(status) == 'number' and status >= 2
end

-- Preview wins over every gate, the enable box and the tank check included:
-- it exists so the text can be placed, and a tank placing it for their alts
-- (or before a respec) is exactly who presses it.
local function ShouldShow()
	if previewActive then return true end
	local cfg = GetCfg()
	if not cfg.enable then return false end
	if not inCombat then return false end
	if cfg.keyOnly and not KeyActive() then return false end
	if PlayerIsTank() then return false end
	return HasAggro()
end

local function EnsureFrame()
	if frame then return end
	frame = CreateFrame('Frame', 'XerionUIAggroCheck', UIParent)
	frame:SetFrameStrata('HIGH')
	frame:SetSize(120, 40)
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(false)
	frame:RegisterForDrag('RightButton')
	ns.MakeDraggable(frame, GetCfg, 'x', 'y')

	text = frame:CreateFontString(nil, 'OVERLAY')
	text:SetPoint('CENTER')
	text:SetJustifyH('CENTER')

	-- C-side animation, so it keeps breathing on engine-driven frames and costs
	-- nothing per frame in Lua.
	pulse = frame:CreateAnimationGroup()
	pulse:SetLooping('BOUNCE')
	local a = pulse:CreateAnimation('Alpha')
	a:SetFromAlpha(1)
	a:SetToAlpha(0.35)
	a:SetDuration(0.45)
	a:SetSmoothing('IN_OUT')

	frame:Hide()
end

local function PlayAggroSound(cfg)
	if previewActive or not cfg.soundEnabled then return end
	local now = GetTime()
	if now - lastSound < SOUND_GAP then return end
	lastSound = now
	ns.PlaySoundByName(cfg.sound)
end

local function Refresh()
	if not frame then return end
	local want = ShouldShow()
	local cfg = GetCfg()
	if want then
		if not frame:IsShown() then
			frame:Show()
			PlayAggroSound(cfg)
		end
		if cfg.pulse then
			if not pulse:IsPlaying() then pulse:Play() end
		else
			if pulse:IsPlaying() then pulse:Stop() end
			frame:SetAlpha(1)
		end
	else
		if pulse:IsPlaying() then pulse:Stop() end
		frame:SetAlpha(1)
		frame:Hide()
	end
end

local function Apply()
	local cfg = GetCfg()
	SetLive(cfg.enable)
	-- Nothing is built while the module is off and not previewing. A frame
	-- built earlier is only hidden (Refresh does nothing without one); the next
	-- Apply with the box ticked styles it again.
	if not (cfg.enable or previewActive) then
		Refresh()
		return
	end
	EnsureFrame()
	local c = cfg.color or DEFAULTS.color
	local size = cfg.fontSize or DEFAULTS.fontSize

	text:SetFont(ns.GothamNarrowBlackFont(), size, 'OUTLINE')
	text:SetText(cfg.text or DEFAULTS.text)
	text:SetTextColor(c[1] or 1, c[2] or 0.15, c[3] or 0.15, c[4] or 1)

	local w, h = text:GetStringWidth(), text:GetStringHeight()
	if secret(w) then w = 0 end
	if secret(h) then h = 0 end
	frame:SetSize(mmax(60, (w or 0) + 16), mmax(24, (h or 0) + 8))

	frame:ClearAllPoints()
	frame:SetPoint('CENTER', UIParent, 'CENTER', cfg.x or 0, cfg.y or 0)
	frame:EnableMouse(previewActive and not cfg.lock or false)

	Refresh()
end
ns.AGCApply = ns.Coalesce(function() Apply() end)

ns.AGCIsPreview = function() return previewActive end
ns.AGCSetPreview = function(state)
	previewActive = state and true or false
	Apply()
end

-- The rest of the events come and go with the enable box (SetLive, called by
-- Apply: ApplyAllSettings after login and on a profile switch, the settings
-- page, and this handler).
evt:RegisterEvent('PLAYER_ENTERING_WORLD')
evt:SetScript('OnEvent', function(_, event)
	if event == 'PLAYER_ENTERING_WORLD' then
		ReadCombat()
		Apply()
		return
	elseif event == 'PLAYER_REGEN_DISABLED' then
		inCombat = true
	elseif event == 'PLAYER_REGEN_ENABLED' then
		inCombat = false
	end
	Refresh()
end)

-- /xerionaggro         - state dump
-- /xerionaggro test    - toggle the preview so the text can be placed
_G.SLASH_XERIONAGGRO1 = '/xerionaggro'
_G.SlashCmdList.XERIONAGGRO = function(arg)
	arg = ns.Trim(arg or ''):lower()
	if arg == 'test' or arg == 'preview' then
		ns.AGCSetPreview(not previewActive)
		Msg('Aggro Check preview ' .. (previewActive and 'ON' or 'OFF'))
		return
	end
	local cfg = GetCfg()
	local status = HasAggro()
	Msg(format('Aggro Check: enabled=%s shown=%s preview=%s listening=%s built=%s', tostring(cfg.enable),
		tostring(frame and frame:IsShown() or false), tostring(previewActive), tostring(live), tostring(frame ~= nil)))
	Msg(format('  in combat=%s key active=%s key only=%s tank spec=%s', tostring(inCombat),
		tostring(KeyActive()), tostring(cfg.keyOnly), tostring(PlayerIsTank())))
	Msg(format('  threat status now=%s (2 or 3 = you have aggro) has aggro=%s secret reads so far=%d',
		tostring(lastStatus), tostring(status), secretReads))
	Msg(format('  position x=%s y=%s  sound=%s %s (file %s)', tostring(cfg.x), tostring(cfg.y),
		cfg.soundEnabled and 'on' or 'off', tostring(cfg.sound), tostring(ns.SoundPath(cfg.sound) or 'not found')))
	local CS = _G.C_Secrets
	if CS and CS.ShouldUnitThreatStateBeSecret then
		local ok, v = pcall(CS.ShouldUnitThreatStateBeSecret, 'player')
		Msg('  client says player threat state would be secret: ' .. tostring(ok and v))
	end
end
