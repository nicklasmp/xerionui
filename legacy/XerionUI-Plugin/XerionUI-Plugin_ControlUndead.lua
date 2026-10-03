local _, ns = ...
local hooksecurefunc, C_Timer = ns.Probe('ControlUndead', hooksecurefunc, C_Timer)
local _G = _G

local CreateFrame = CreateFrame
local UIParent = UIParent
local GetTime = GetTime
local pcall = pcall
local mfloor, mceil = math.floor, math.ceil
local format = string.format

ns.hasControlUndead = true

local CU_SPELL = 111673
local CU_ICON_FALLBACK = 237511

local Round = ns.Round
local secret = ns.IsSecret

local function IsDeathKnight() return ns.IsClass('DEATHKNIGHT') end

local DURATION = 300

local DEFAULTS = {
	enable = false,
	lock = true,
	iconSize = 44,
	textSize = 0,
	x = 0,
	y = -160,
	strata = 'MEDIUM',
	hideOnPetLost = true,
	showSwipe = true,
	warnAt = 30,
	textColor = { 1, 1, 1, 1 },
	warnColor = { 1, 0.3, 0.3, 1 },
}

local function GetCfg() return ns.ModuleCfg('controlUndead', DEFAULTS) end
ns.CUGetCfg = GetCfg

local function IconTexture()
	local get = _G.C_Spell and _G.C_Spell.GetSpellTexture
	if get then
		local ok, tex = pcall(get, CU_SPELL)
		if ok and tex and not secret(tex) then return tex end
	end
	return CU_ICON_FALLBACK
end

local castAt, expiresAt = 0, 0
local petGUID
local preview
local frame, btn
local ticker

local function Active() return expiresAt > 0 and expiresAt > GetTime() end

local ApplySettings

local function EnsureFrame()
	if frame then return end
	frame = CreateFrame('Frame', 'XerionUIControlUndead', UIParent)
	frame:SetFrameStrata('MEDIUM')
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(false)
	frame:RegisterForDrag('RightButton')
	ns.MakeDraggable(frame, GetCfg, 'x', 'y', function() ApplySettings() end)

	btn = CreateFrame('Frame', nil, frame)
	btn.border = btn:CreateTexture(nil, 'BACKGROUND')
	btn.border:SetColorTexture(0, 0, 0, 1)
	btn.border:SetAllPoints()

	btn.Icon = btn:CreateTexture(nil, 'ARTWORK')
	btn.Icon:SetPoint('TOPLEFT', 1, -1)
	btn.Icon:SetPoint('BOTTOMRIGHT', -1, 1)
	btn.Icon:SetTexture(IconTexture())
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

local function FormatTime(rem)
	if rem >= 60 then
		local m = mfloor(rem / 60)
		local s = mfloor(rem % 60)
		return format('%d:%02d', m, s)
	end
	return format('%d', mceil(rem))
end

-- WHAT THE TEXT SHOWS NOW
-- The charm lasts five minutes and the ticker runs four times a second, so
-- the same "3:12" used to be formatted and set four times over. shownKey is
-- the whole second FormatTime would print (floored above a minute, ceiled
-- below it, negative below so the two ranges cannot collide - FormatTime
-- itself only looks at that one number), shownColor the colour table last
-- applied. Both are plain numbers and tables of our own, never secrets. They
-- are forgotten whenever the text is restyled or the icon hidden, so the
-- next Render sets both again.
local shownKey, shownColor
local function ForgetShown() shownKey, shownColor = nil, nil end

ApplySettings = function()
	EnsureFrame()
	ForgetShown()
	local cfg = GetCfg()
	local sz = cfg.iconSize or 44

	frame:ClearAllPoints()
	frame:SetPoint('CENTER', UIParent, 'CENTER', cfg.x or 0, cfg.y or -160)
	frame:SetSize(sz, sz)
	frame:SetFrameStrata(cfg.strata or 'MEDIUM')

	btn:SetSize(sz, sz)
	btn:ClearAllPoints()
	btn:SetPoint('CENTER', frame, 'CENTER', 0, 0)
	btn.Icon:SetTexture(IconTexture())

	local ts = cfg.textSize or 0
	if ts <= 0 then ts = Round(sz * 0.42) end
	btn.Text:SetFont(ns.GetFont(), ts, 'OUTLINE')
end

local function Render()
	if not frame then return end
	local cfg = GetCfg()
	local rem = preview and 137 or (expiresAt - GetTime())

	if not preview and (not cfg.enable or rem <= 0) then
		ForgetShown()
		frame:Hide()
		return
	end

	local key = (rem >= 60) and mfloor(rem) or -mceil(rem)
	if key ~= shownKey then
		shownKey = key
		btn.Text:SetText(FormatTime(rem))
	end
	local c = (rem <= (cfg.warnAt or 30)) and (cfg.warnColor or DEFAULTS.warnColor)
		or (cfg.textColor or DEFAULTS.textColor)
	if c ~= shownColor then
		shownColor = c
		btn.Text:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
	end

	frame:Show()
	btn:Show()
end

local function StopTicker()
	if ticker then ticker:Cancel() ticker = nil end
end

local function Clear()
	expiresAt, castAt = 0, 0
	petGUID = nil
	StopTicker()
	if btn and btn.Cooldown then
		if btn.Cooldown.Clear then btn.Cooldown:Clear() else btn.Cooldown:SetCooldown(0, 0) end
	end
	if frame and not preview then ForgetShown() frame:Hide() end
end

local function Start()
	EnsureFrame()
	ApplySettings()

	local cfg = GetCfg()

	castAt = GetTime()
	expiresAt = castAt + DURATION
	petGUID = nil

	if cfg.showSwipe and btn.Cooldown then
		btn.Cooldown:SetCooldown(castAt, DURATION)
		btn.Cooldown:Show()
	elseif btn.Cooldown then
		btn.Cooldown:Hide()
	end

	C_Timer.After(0.4, function()
		if not Active() then return end
		local ok, guid = pcall(_G.UnitGUID, 'pet')
		if ok and guid and not secret(guid) then
			petGUID = guid
		else
			petGUID = nil
		end
	end)

	StopTicker()
	ticker = C_Timer.NewTicker(0.25, function()
		if preview then return end
		if not Active() then Clear() return end
		Render()
	end)
	Render()
end

local function MinionLost()
	local okE, exists = pcall(_G.UnitExists, 'pet')
	if not okE then return false end
	if secret(exists) then return false end
	if not exists then return true end

	if petGUID then
		local okG, guid = pcall(_G.UnitGUID, 'pet')
		if okG and guid and not secret(guid) then
			return guid ~= petGUID
		end
	end
	return false
end

ns.CUApply = function()
	if not GetCfg().enable then
		if not preview then Clear() end
		return
	end
	EnsureFrame()
	ApplySettings()
	Render()
end

ns.CUIsPreview = function() return preview and true or false end
ns.CUSetPreview = function(state)
	preview = state and true or false
	EnsureFrame()
	ApplySettings()
	frame:EnableMouse(preview)
	if preview then
		if btn.Cooldown then
			if GetCfg().showSwipe then
				btn.Cooldown:SetCooldown(GetTime() - 163, 300)
				btn.Cooldown:Show()
			else
				btn.Cooldown:Hide()
			end
		end
		Render()
	else
		Clear()
		Render()
	end
end

local evt = CreateFrame('Frame')
evt:RegisterEvent('PLAYER_ENTERING_WORLD')
evt:RegisterUnitEvent('UNIT_SPELLCAST_SUCCEEDED', 'player')
evt:RegisterUnitEvent('UNIT_PET', 'player')
evt:SetScript('OnEvent', function(_, event, unit, _, spellID)
	if preview then return end
	local cfg = GetCfg()
	if not cfg.enable then return end

	if event == 'UNIT_SPELLCAST_SUCCEEDED' then
		if spellID and not secret(spellID) and spellID == CU_SPELL then
			if not IsDeathKnight() then return end
			Start()
		end

	elseif event == 'UNIT_PET' then
		if cfg.hideOnPetLost and Active() then
			if GetTime() - castAt > 0.5 and MinionLost() then Clear() end
		end

	else
		Clear()
		ApplySettings()
	end
end)
