local _, ns = ...
local hooksecurefunc, C_Timer = ns.Probe('Blightfall', hooksecurefunc, C_Timer)
local _G = _G

local CreateFrame = CreateFrame
local UIParent = UIParent
local GetTime = GetTime
local PlaySound = PlaySound
local pcall, type, tonumber, tostring = pcall, type, tonumber, tostring
local format = string.format
local mmax, mabs, msin, mceil = math.max, math.abs, math.sin, math.ceil

-- WHY THIS FILE EXISTS
-- Unholy's single-target opener is a chain: Dark Transformation (45 s), then
-- Soul Reaper a few seconds later, then Blightfall a few seconds after that,
-- so both land inside the window they are meant to amplify. Pressing them too
-- early wastes the window, pressing them too late wastes the cooldown. Each
-- press arms a countdown for the NEXT press.
--
-- WHAT IT DOES
--   Dark Transformation cast -> counts down to Soul Reaper (delaySR seconds),
--                               but only when Soul Reaper is talented.
--   Soul Reaper cast         -> while that countdown is armed, counts down to
--                               Blightfall (delayBF seconds from THIS cast,
--                               not from Dark Transformation). Without the
--                               Blightfall talent the chain ends here.
--   Blightfall cast          -> chain done.
-- A countdown that reaches 0 stays on "NOW" until the press, for at most
-- GRACE seconds, and leaving combat clears everything. The timings are the
-- player's own: 7 s / 7 s is the single-target default, AoE players tune it.
--
-- The look is a still icon that glows and can grow as 0 nears. Its countdown
-- colour runs red -> yellow -> green over the last three seconds, and an
-- optional text-to-speech voice says "Soul Reaper in", 3, 2, 1, "Now". The
-- original addon's other look, a lane where the icon travels to a hit line,
-- was dropped at the user's request (2026-09-26), as was the two-decimal
-- countdown.
--
-- SECRET VALUES
-- The player's own UNIT_SPELLCAST_SUCCEEDED spell ID is readable (every
-- class module here keys off it); it is still tested before the compare.
-- Everything else is our own clock. The talent reads go through
-- ns.SpellKnown, which answers "known" when the client will not say - a gate
-- that fails closed would hide the countdown from exactly the Unholy player.

ns.hasBlightfall = true

local secret = ns.IsSecret
local Round = ns.Round

-- Dark Transformation's 12.x cast is 1233448; 63560 is the pre-Midnight ID,
-- kept because accepting it costs nothing if the client never sends it.
local DARK_TRANSFORMATION = { [1233448] = true, [63560] = true }
local SOUL_REAPER         = 343294
local BLIGHTFALL          = 1271967
-- The talent is known under a different ID than the button it grants; the
-- original addon found this one with a spellbook walk. The cast ID is asked
-- as well, in case a later build files the talent under the button.
local BLIGHTFALL_TALENT   = 1271974

local LABELS = { [SOUL_REAPER] = 'Soul Reaper', [BLIGHTFALL] = 'Blightfall' }
local ICON_FALLBACK = { [SOUL_REAPER] = 636333, [BLIGHTFALL] = 5976940 }

local GRACE     = 20
local RAMP      = 3
local GREEN_AT  = 1
local NOW_AT    = 0.05
local SAY_LABEL = 5
local SAY_COUNT = 3
local ACCENT = { 0.72, 0.4, 1 }

local RED    = { 1, 0.15, 0.15 }
local YELLOW = { 1, 0.85, 0.1 }
local GREEN  = { 0.3, 1, 0.3 }

local DEFAULTS = {
	enable = false,
	lock = true,
	delaySR = 7,
	delayBF = 7,
	decimals = 1,
	textSize = 0,
	voice = true,
	voiceVolume = 100,
	sound = 'None',
	strata = 'MEDIUM',
	x = 0,
	y = -220,
	iconSize = 64,
	textPos = 'BELOW',
	-- Nudges the countdown from the place textPos picks.
	textX = 0,
	textY = 0,
	growPulse = false,
	growStart = 3,
	growMax = 2,
}

-- The lane look and the two-decimal countdown went on 2026-09-26: their
-- settings are dropped, and a saved 2 decimals becomes 1.
local function Migrate(cfg)
	cfg.mode, cfg.orientation = nil, nil
	cfg.laneIconSize, cfg.laneLength, cfg.laneSeconds, cfg.laneAlpha = nil, nil, nil, nil
	if cfg.decimals ~= 0 then cfg.decimals = 1 end
end

local function GetCfg() return ns.ModuleCfg('blightfall', DEFAULTS, Migrate) end
ns.BLFGetCfg = GetCfg

local function IsUnholy() return ns.IsSpec('DEATHKNIGHT', 3) end

local function BlightfallTalented()
	return ns.SpellKnown(BLIGHTFALL_TALENT) or ns.SpellKnown(BLIGHTFALL)
end

local function SpellIcon(id)
	local get = _G.C_Spell and _G.C_Spell.GetSpellTexture
	if get then
		local ok, tex = pcall(get, id)
		if ok and tex and not secret(tex) then return tex end
	end
	return ICON_FALLBACK[id]
end

-- THE CHAIN
-- step is the spell the countdown is aiming at (SOUL_REAPER or BLIGHTFALL),
-- nil when idle. armedAt/armedDelay are plain GetTime() numbers of our own.
local step, armedAt, armedDelay = nil, 0, 0
local preview, previewStart = false, 0

-- The last few spell IDs the player cast, for /xerionblight: if a talent or a
-- build ever sends a different ID for one of the three buttons, this is where
-- it shows.
local RECENT_MAX = 8
local recentIDs, recentAt, recentN = {}, {}, 0

local function Remember(id)
	recentN = recentN % RECENT_MAX + 1
	recentIDs[recentN], recentAt[recentN] = id, GetTime()
end

-- Returns the spell being counted down to and the seconds left (never below
-- 0), or nil. Preview loops Soul Reaper -> Blightfall with nothing cast.
local function Active()
	if preview then
		local cfg = GetCfg()
		local a, b = cfg.delaySR or 7, cfg.delayBF or 7
		local total = a + b
		if total <= 0 then return SOUL_REAPER, 0 end
		local e = (GetTime() - previewStart) % total
		if e < a then return SOUL_REAPER, a - e end
		return BLIGHTFALL, total - e
	end
	if not step then return nil end
	local left = armedDelay - (GetTime() - armedAt)
	if left < -GRACE then
		step = nil
		return nil
	end
	return step, mmax(0, left)
end

local function Lerp(a, b, t)
	return a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t
end

local function CountdownColor(eta)
	if eta <= GREEN_AT then return GREEN[1], GREEN[2], GREEN[3] end
	if eta >= RAMP then return RED[1], RED[2], RED[3] end
	local mid = (RAMP + GREEN_AT) / 2
	if eta > mid then return Lerp(RED, YELLOW, (RAMP - eta) / (RAMP - mid)) end
	return Lerp(YELLOW, GREEN, (mid - eta) / (mid - GREEN_AT))
end

local function FormatEta(eta, decimals)
	if eta <= NOW_AT then return 'NOW' end
	if decimals == 0 then return tostring(mceil(eta)) end
	return format('%.1f', eta)
end

-- VOICE
-- The player's own text-to-speech voice and rate from the game's settings,
-- the first installed voice otherwise. Whatever is being said is stopped
-- first so "2" is not queued behind "3"; the new line is deferred one frame
-- because the original addon found Stop + Speak in the same frame silently
-- drops the Speak on Windows. No voice at all falls back to two stock sounds.
local function VoiceID()
	local S = _G.C_TTSSettings
	if S and S.GetVoiceOptionID then
		local ok, id = pcall(S.GetVoiceOptionID, 0)
		if ok and type(id) == 'number' then return id end
	end
	local V = _G.C_VoiceChat
	local voices = V and V.GetTtsVoices and V.GetTtsVoices()
	return voices and voices[1] and voices[1].voiceID
end

local function Beep(isNow)
	local kit = _G.SOUNDKIT
	if not kit then return end
	PlaySound(isNow and kit.READY_CHECK or kit.IG_MAINMENU_OPTION_CHECKBOX_ON, 'Master')
end

local function Speak(text, isNow)
	local V = _G.C_VoiceChat
	local id = V and V.SpeakText and VoiceID()
	if type(id) ~= 'number' then Beep(isNow) return end
	if V.StopSpeakingText then pcall(V.StopSpeakingText) end
	C_Timer.After(0, function()
		local S = _G.C_TTSSettings
		local rate = S and S.GetSpeechRate and S.GetSpeechRate() or 0
		local ok = pcall(V.SpeakText, id, text, rate, GetCfg().voiceVolume or 100, true)
		if not ok then Beep(isNow) end
	end)
end

-- Called every frame with the live countdown; speaks once per whole second
-- that has a line. A preview only talks while the settings window is open,
-- so a preview left running does not keep counting out loud.
local function CountdownVoice(label, eta, last)
	local second = (eta <= NOW_AT) and 0 or mceil(eta)
	if second == last then return last end
	if preview then
		local win = _G.KiraPluginConfig
		if not (win and win:IsShown()) then return second end
	end
	local cfg = GetCfg()
	if second == 0 then
		if cfg.voice then Speak('Now', true) end
		ns.PlaySoundByName(cfg.sound)
	elseif cfg.voice then
		if second == SAY_LABEL then
			Speak(label .. ' in')
		elseif second <= SAY_COUNT then
			Speak(tostring(second))
		end
	end
	return second
end

-- DISPLAY
local root, ic, text
local shownID, shownText, lastSecond

local function GrowScale(eta, cfg)
	local start = cfg.growStart or 3
	local most = cfg.growMax or 2
	if eta >= start then return 1 end
	if start <= 0 then return most end
	return 1 + (most - 1) * (1 - eta / start)
end

local function HideNow()
	shownID, shownText, lastSecond = nil, nil, nil
	if root then root:Hide() end
end

-- Edit mode drives the same preview, but an icon that loops, flickers and
-- grows is hard to line up, and with the settings window open the voice
-- would count along while the player drags. There the preview holds still
-- on the first frame of the Soul Reaper countdown: its icon, number and
-- colour, no glow, no grow, no voice.
local function Render()
	local still = preview and ns.EditModeActive and ns.EditModeActive()
	local id, eta
	if still then
		id, eta = SOUL_REAPER, mmax(0, tonumber(GetCfg().delaySR) or 7)
	else
		id, eta = Active()
	end
	if not id then HideNow() return end
	local cfg = GetCfg()
	if id ~= shownID then
		shownID = id
		lastSecond = nil
		ic.tex:SetTexture(SpellIcon(id))
	end

	local r, g, b = CountdownColor(eta)
	local s = FormatEta(eta, cfg.decimals)
	if s ~= shownText then
		shownText = s
		text:SetText(s)
	end
	text:SetTextColor(r, g, b)

	if eta <= RAMP and not still then
		-- 0 far away -> 1 at NOW, so the glow and the grow build towards the
		-- same moment; the flicker is our own sine, not an engine animation.
		local t = 1 - eta / RAMP
		local flicker = 0.5 + 0.5 * mabs(msin(GetTime() * 10))
		ic.border:SetColorTexture(r, g, b, 0.4 + 0.6 * t * flicker)
		ic.halo:SetColorTexture(r, g, b, 0.15 + 0.35 * t * flicker)
		ic:SetScale(cfg.growPulse and GrowScale(eta, cfg) or 1)
	else
		ic.border:SetColorTexture(r, g, b, 0.4)
		ic.halo:SetColorTexture(r, g, b, 0)
		ic:SetScale(1)
	end

	if not still then lastSecond = CountdownVoice(LABELS[id], eta, lastSecond) end
end

local function Clamp(v, lo, hi, fallback)
	v = tonumber(v) or fallback
	if v < lo then return lo elseif v > hi then return hi end
	return v
end

local function Layout()
	local cfg = GetCfg()
	root:ClearAllPoints()
	root:SetPoint('CENTER', UIParent, 'CENTER', cfg.x or 0, cfg.y or DEFAULTS.y)
	root:SetFrameStrata(cfg.strata or 'MEDIUM')

	local size = Clamp(cfg.iconSize, 16, 160, 64)
	root:SetSize(size, size)
	ic:SetSize(size, size)
	ic:SetScale(1)
	ic:ClearAllPoints()
	ic:SetPoint('CENTER', root, 'CENTER', 0, 0)

	-- Border and halo grow with the icon: 4 px / 10 px on the 64 px icon, the
	-- original addon's sizes.
	local pad = mmax(1, Round(size / 16))
	ic.border:ClearAllPoints()
	ic.border:SetPoint('TOPLEFT', -pad, pad)
	ic.border:SetPoint('BOTTOMRIGHT', pad, -pad)
	local halo = Round(size * 0.16)
	ic.halo:ClearAllPoints()
	ic.halo:SetPoint('TOPLEFT', -halo, halo)
	ic.halo:SetPoint('BOTTOMRIGHT', halo, -halo)

	text:ClearAllPoints()
	local pos = cfg.textPos
	local tx, ty = tonumber(cfg.textX) or 0, tonumber(cfg.textY) or 0
	if pos == 'ABOVE' then
		text:SetPoint('BOTTOM', ic, 'TOP', tx, pad + 2 + ty)
	elseif pos == 'CENTER' then
		text:SetPoint('CENTER', ic, 'CENTER', tx, ty)
	else
		text:SetPoint('TOP', ic, 'BOTTOM', tx, -(pad + 2) + ty)
	end

	local ts = tonumber(cfg.textSize) or 0
	if ts <= 0 then ts = Round(size * 0.34) end
	if ts < 6 then ts = 6 end
	-- A plain outline. THICKOUTLINE, the original addon's, read as bold with
	-- a smear round every digit (user, 2026-09-26).
	local ok, valid = pcall(text.SetFont, text, ns.GothamNarrowBlackFont(), ts, 'OUTLINE')
	if not ok or valid == false then
		pcall(text.SetFont, text, _G.STANDARD_TEXT_FONT, ts, 'OUTLINE')
	end
	shownText = nil
end

local function EnsureFrame()
	if root then return end
	root = CreateFrame('Frame', 'XerionUIBlightfall', UIParent)
	root:SetClampedToScreen(true)
	root:SetMovable(true)
	root:EnableMouse(false)
	root:RegisterForDrag('RightButton')
	ns.MakeDraggable(root, GetCfg, 'x', 'y', function() if ns.BLFApply then ns.BLFApply() end end)

	ic = CreateFrame('Frame', nil, root)
	ic:SetFrameLevel(root:GetFrameLevel() + 2)
	ic.halo = ic:CreateTexture(nil, 'BACKGROUND', nil, -8)
	ic.halo:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0)
	ic.border = ic:CreateTexture(nil, 'BORDER')
	ic.border:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0)
	ic.tex = ic:CreateTexture(nil, 'ARTWORK')
	ic.tex:SetAllPoints()
	ic.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	-- The number sits on its own frame above the icon, so a grown icon never
	-- draws over it.
	local holder = CreateFrame('Frame', nil, root)
	holder:SetAllPoints()
	holder:SetFrameLevel(ic:GetFrameLevel() + 4)
	text = holder:CreateFontString(nil, 'OVERLAY')
	text:SetShadowOffset(0, 0)

	root:Hide()
	root:SetScript('OnUpdate', Render)
	Layout()
end

local function Clear()
	step = nil
	if not preview then HideNow() end
end

local function Arm(id, delay)
	step, armedAt, armedDelay = id, GetTime(), tonumber(delay) or 7
	if preview then return end
	EnsureFrame()
	root:Show()
	Render()
end

local function OnCast(spellID)
	if spellID == nil or secret(spellID) then return end
	Remember(spellID)
	if DARK_TRANSFORMATION[spellID] then
		if not ns.SpellKnown(SOUL_REAPER) then return end
		Arm(SOUL_REAPER, GetCfg().delaySR)
	elseif spellID == SOUL_REAPER then
		if step ~= SOUL_REAPER then return end
		if BlightfallTalented() then
			Arm(BLIGHTFALL, GetCfg().delayBF)
		else
			Clear()
		end
	elseif spellID == BLIGHTFALL then
		if step == BLIGHTFALL then Clear() end
	end
end

local evt = CreateFrame('Frame')
local listening = false

-- The cast event is only registered for an enabled Unholy Death Knight, so
-- every other character pays nothing per cast.
local function Listen(on)
	if on == listening then return end
	listening = on
	if on then
		evt:RegisterUnitEvent('UNIT_SPELLCAST_SUCCEEDED', 'player')
	else
		evt:UnregisterEvent('UNIT_SPELLCAST_SUCCEEDED')
	end
end

ns.BLFApply = function()
	local on = GetCfg().enable and IsUnholy() and true or false
	Listen(on)
	if not on then step = nil end
	if not root and not preview and not on then return end
	EnsureFrame()
	Layout()
	if preview or (on and step) then
		root:Show()
		Render()
	else
		HideNow()
	end
end

ns.BLFIsPreview = function() return preview end
ns.BLFSetPreview = function(state)
	preview = state and true or false
	EnsureFrame()
	root:EnableMouse(preview)
	shownID, shownText, lastSecond = nil, nil, nil
	if preview then
		previewStart = GetTime()
		Layout()
		root:Show()
		Render()
	else
		HideNow()
		ns.BLFApply()
	end
end

evt:RegisterEvent('PLAYER_ENTERING_WORLD')
evt:RegisterEvent('PLAYER_REGEN_ENABLED')
evt:RegisterUnitEvent('PLAYER_SPECIALIZATION_CHANGED', 'player')
evt:SetScript('OnEvent', function(_, event, _, _, spellID)
	if event == 'UNIT_SPELLCAST_SUCCEEDED' then
		OnCast(spellID)
	elseif event == 'PLAYER_REGEN_ENABLED' then
		-- Out of combat: whatever was armed can no longer matter.
		if step then Clear() end
	elseif event == 'PLAYER_ENTERING_WORLD' then
		step = nil
		ns.BLFApply()
	else
		ns.BLFApply()
	end
end)

_G.SLASH_XERIONBLIGHT1 = '/xerionblight'
_G.SlashCmdList.XERIONBLIGHT = function(msg)
	msg = type(msg) == 'string' and msg:lower() or ''
	if msg:find('opt') or msg:find('config') or msg:find('setting') then
		if ns.ShowConfig then ns.ShowConfig('class_dk') end
		C_Timer.After(0.2, function()
			if ns.ShowConfigSubTab then ns.ShowConfigSubTab('class_dk', 'Blightfall chain') end
		end)
		return
	end
	local cfg = GetCfg()
	local function yn(v) return v and 'yes' or 'no' end
	ns.Msg(format('Blightfall chain: enabled %s, Unholy %s, listening %s, preview %s, delays %.1f / %.1f s',
		yn(cfg.enable), yn(IsUnholy()), yn(listening), yn(preview), cfg.delaySR or 0, cfg.delayBF or 0))
	ns.Msg(format('talents: Soul Reaper %s, Blightfall %s (talent id %s, cast id %s)',
		yn(ns.SpellKnown(SOUL_REAPER)), yn(BlightfallTalented()),
		yn(ns.SpellKnown(BLIGHTFALL_TALENT)), yn(ns.SpellKnown(BLIGHTFALL))))
	if step then
		ns.Msg(format('armed: %s, %.2f s left', LABELS[step] or tostring(step), armedDelay - (GetTime() - armedAt)))
	else
		ns.Msg('armed: nothing')
	end
	local V = _G.C_VoiceChat
	ns.Msg(format('voice: %s, voice id %s', yn(cfg.voice), tostring(V and V.SpeakText and VoiceID() or 'none (sound cues instead)')))
	local parts, now = {}, GetTime()
	for i = 0, RECENT_MAX - 1 do
		local k = (recentN - i - 1) % RECENT_MAX + 1
		local id = recentIDs[k]
		if id then parts[#parts + 1] = format('%d (%.0fs ago)', id, now - recentAt[k]) end
	end
	ns.Msg('last casts seen: ' .. (#parts > 0 and table.concat(parts, ', ') or 'none yet'
		.. (listening and '' or ' - not listening, see enabled/Unholy above')))
	ns.Msg(format('expected: Dark Transformation 1233448, Soul Reaper %d, Blightfall %d', SOUL_REAPER, BLIGHTFALL))
end
