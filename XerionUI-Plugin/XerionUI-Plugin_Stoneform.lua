local _, ns = ...
local _G = _G

local CreateFrame = CreateFrame
local UIParent = UIParent
local C_Timer = C_Timer
local pcall = pcall
local ipairs = ipairs
local max = math.max
local min = math.min
local floor = math.floor
local secret = ns.IsSecret

ns.hasStoneform = true

local STONEFORM = 20594
local STONEFORM_ICON = 132275
local AURA_API = _G.C_UnitAuras

local DEFAULTS = {
	enable = true,
	lock = false,
	iconSize = 48,
	x = 0,
	y = 160,
	borderSize = 1,
	borderColor = { 0, 0, 0, 1 },
	glow = false,
	glowType = 'pixel',
	glowColor = { 1, 0.49, 0.04, 1 },
	glowThickness = 2,
	alertMode = 'tts',
	ttsText = 'Bleed detected',
	ttsVolume = 100,
	ttsVoiceName = '',
	sound = 'None',
}

local function GetCfg() return ns.ModuleCfg('stoneform', DEFAULTS) end
ns.SFMGetCfg = GetCfg
ns.SFMUnavailable = not (AURA_API and AURA_API.GetAuraDataByIndex and _G.C_Spell and _G.C_Spell.GetSpellCooldown)

local frame, icon, border, autoCastOverlay, activeAutoCastGlows
local preview = false
local alertVisible = false

local function VoiceID()
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

local function PlayAlert(force)
	local cfg = GetCfg()
	if cfg.alertMode == 'sound' then
		if ns.PlaySoundByName then ns.PlaySoundByName(cfg.sound) end
		return
	end
	local V = _G.C_VoiceChat
	local id = V and V.SpeakText and VoiceID()
	if type(id) ~= 'number' then return end
	local text = tostring(cfg.ttsText or '')
	if not text:find('%S') then text = 'Bleed detected' end
	if V.StopSpeakingText then pcall(V.StopSpeakingText) end
	C_Timer.After(0, function()
		local S = _G.C_TTSSettings
		local rate = S and S.GetSpeechRate and S.GetSpeechRate() or 0
		pcall(V.SpeakText, id, text, rate, cfg.ttsVolume or 100, true)
	end)
end
ns.SFMTestAlert = function() PlayAlert(true) end

local function HasBleed()
	if not (AURA_API and AURA_API.GetAuraDataByIndex) then return false end
	for i = 1, 40 do
		local ok, aura = pcall(AURA_API.GetAuraDataByIndex, 'player', i, 'HARMFUL')
		if not ok or secret(aura) then break end
		if aura == nil then break end
		local okType, dispelType = pcall(function() return aura.dispelName end)
		if okType and not secret(dispelType) and dispelType == 'Bleed' then
			return true
		end
	end
	return false
end

local function StoneformReady()
	local CS = _G.C_Spell
	if not (CS and CS.GetSpellCooldown) then return false end
	local ok, info = pcall(CS.GetSpellCooldown, STONEFORM)
	if not ok or secret(info) or info == nil then return false end
	local active, onGCD
	local okA, a = pcall(function() return info.isActive end)
	local okG, g = pcall(function() return info.isOnGCD end)
	if okA and not secret(a) then active = a end
	if okG and not secret(g) then onGCD = g end
	if active == nil then return false end
	return not (active and not onGCD)
end

local function HasStoneform()
	if not _G.IsPlayerSpell then return false end
	local ok, known = pcall(_G.IsPlayerSpell, STONEFORM)
	return ok and not secret(known) and known and true or false
end

local function StopAutoCastShine()
	if activeAutoCastGlows and activeAutoCastGlows.StopAutoCastShine and frame then
		pcall(activeAutoCastGlows.StopAutoCastShine, frame)
		activeAutoCastGlows = nil
	end
	if autoCastOverlay then
		if autoCastOverlay.ShowAutoCastEnabled then
			pcall(autoCastOverlay.ShowAutoCastEnabled, autoCastOverlay, false)
		end
		autoCastOverlay:Hide()
	end
end

local function StopGlow()
	StopAutoCastShine()
	if frame then ns.GlowStop(frame) end
end

local function StartGlow()
	local cfg = GetCfg()
	if not cfg.glow then StopGlow() return end
	local size = cfg.iconSize or DEFAULTS.iconSize
	if cfg.glowType == 'autoshine' then
		StopAutoCastShine()
		ns.GlowStop(frame)
		local eui = _G.EllesmereUI
		local glows = eui and eui.Glows
		if glows and glows.StartAutoCastShine and glows.StopAutoCastShine then
			local c = cfg.glowColor or DEFAULTS.glowColor
			local ok = pcall(glows.StartAutoCastShine, frame, size,
				c[1] or 1, c[2] or 1, c[3] or 1, 1, size)
			if ok then activeAutoCastGlows = glows return end
		end
		if ns.HasTemplate and ns.HasTemplate('AutoCastOverlayTemplate') then
			if not autoCastOverlay then
				autoCastOverlay = CreateFrame('Frame', nil, frame, 'AutoCastOverlayTemplate')
				autoCastOverlay:SetAllPoints(frame)
				autoCastOverlay:SetFrameLevel(frame:GetFrameLevel() + 5)
				pcall(autoCastOverlay.SetMouseMotionEnabled, autoCastOverlay, false)
				pcall(autoCastOverlay.SetMouseClickEnabled, autoCastOverlay, false)
			end
			autoCastOverlay:Show()
			if autoCastOverlay.ShowAutoCastEnabled then
				pcall(autoCastOverlay.ShowAutoCastEnabled, autoCastOverlay, true)
			end
			return
		end
	end
	StopAutoCastShine()
	ns.GlowStart(frame, size, size, cfg)
end

local function EnsureFrame()
	if frame then return end
	frame = CreateFrame('Frame', 'XerionUIStoneform', UIParent)
	frame:SetFrameStrata('HIGH')
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(false)
	frame:RegisterForDrag('RightButton')
	border = frame:CreateTexture(nil, 'BACKGROUND')
	border:SetAllPoints()
	icon = frame:CreateTexture(nil, 'ARTWORK')
	local texture = STONEFORM_ICON
	local CS = _G.C_Spell
	if CS and CS.GetSpellTexture then
		local ok, tex = pcall(CS.GetSpellTexture, STONEFORM)
		if ok and type(tex) == 'number' and not secret(tex) then texture = tex end
	end
	icon:SetTexture(texture)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	frame:Hide()
	ns.MakeDraggable(frame, GetCfg, 'x', 'y', function() ns.SFMApply() end)
end

local function Refresh(fromAura)
	if not frame then return end
	local cfg = GetCfg()
	local actualShow = cfg.enable and not ns.SFMUnavailable and HasStoneform() and HasBleed() and StoneformReady()
	if fromAura and actualShow and not alertVisible and not preview then PlayAlert() end
	alertVisible = actualShow and true or false
	local show = preview or actualShow
	if show then
		StartGlow()
	else
		StopGlow()
	end
	frame:SetShown(show)
end
local RefreshSoon = ns.Coalesce(Refresh)

local function Apply()
	local cfg = GetCfg()
	local enabled = cfg.enable and not ns.SFMUnavailable and HasStoneform()
	if not (enabled or preview) then
		if frame then StopGlow() frame:Hide() end
		return
	end
	EnsureFrame()
	local size = max(16, min(120, floor((cfg.iconSize or DEFAULTS.iconSize) + 0.5)))
	frame:SetSize(size, size)
	frame:ClearAllPoints()
	frame:SetPoint('CENTER', UIParent, 'CENTER', cfg.x or 0, cfg.y or 160)
	border:SetColorTexture((cfg.borderColor or DEFAULTS.borderColor)[1] or 0,
		(cfg.borderColor or DEFAULTS.borderColor)[2] or 0,
		(cfg.borderColor or DEFAULTS.borderColor)[3] or 0,
		(cfg.borderColor or DEFAULTS.borderColor)[4] or 1)
	local inset = max(0, min(8, floor((cfg.borderSize or 1) + 0.5)))
	icon:ClearAllPoints()
	if inset > 0 then
		icon:SetPoint('TOPLEFT', inset, -inset)
		icon:SetPoint('BOTTOMRIGHT', -inset, inset)
	else
		icon:SetAllPoints()
	end
	frame:EnableMouse(preview and not cfg.lock or false)
	Refresh()
end

ns.SFMIsPreview = function() return preview end
ns.SFMSetPreview = function(on)
	preview = on and true or false
	Apply()
end

local events = {
	'PLAYER_ENTERING_WORLD', 'PLAYER_SPECIALIZATION_CHANGED', 'PLAYER_TALENT_UPDATE',
	'UNIT_AURA', 'SPELL_UPDATE_COOLDOWN', 'SPELL_UPDATE_CHARGES',
}
local evt = CreateFrame('Frame')
evt:SetScript('OnEvent', function(_, event, unit)
	if event == 'PLAYER_LOGIN' then
		ns.SFMApply()
	elseif event ~= 'UNIT_AURA' or unit == 'player' then
		if event == 'UNIT_AURA' and unit == 'player' then Refresh(true) else RefreshSoon() end
	end
end)
evt:RegisterEvent('PLAYER_LOGIN')
local function SyncEvents()
	local cfg = GetCfg()
	local on = cfg.enable and not ns.SFMUnavailable and HasStoneform()
	for _, event in ipairs(events) do
		if on then evt:RegisterEvent(event) else evt:UnregisterEvent(event) end
	end
end

ns.SFMApply = ns.Coalesce(function()
	SyncEvents()
	Apply()
end)

