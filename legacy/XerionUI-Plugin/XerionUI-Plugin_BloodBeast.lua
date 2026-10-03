local _, ns = ...
local hooksecurefunc, C_Timer = ns.Probe('BloodBeast', hooksecurefunc, C_Timer)
local _G = _G

local CreateFrame = CreateFrame
local UIParent = UIParent
local GetTime = GetTime
local UnitGUID = UnitGUID
local InCombatLockdown = InCombatLockdown
local C_Timer = C_Timer
local pcall = pcall
local type = type
local tonumber = tonumber
local tostring = tostring
local format = string.format
local gsub = string.gsub
local mmax, mmin = math.max, math.min

ns.hasBloodBeast = true

local secret = ns.IsSecret
local Round = ns.Round

local DRW        = 49028
-- Dark Transformation: 1233448 on 12.x, 63560 before (see BloodIsLife.lua).
local DT         = { [1233448] = true, [63560] = true }
local BEAST      = 434237
local LABEL      = 'Bloodbeast:'
local SHOW_FOR   = 10
local SETTLE     = 12
local RETRY_GAP  = 0.5
local RETRY_MAX  = 12
local PREVIEW_VALUE = 12500000

local DEFAULTS = {
	enable = false,
	lock = true,
	x = 0,
	y = -160,
	size = 22,
	strata = 'MEDIUM',
	labelColor = { 0.9, 0.12, 0.12, 1 },
	valueColor = { 1, 1, 1, 1 },
}

-- Always a plain outline, like every other XerionUI text; the outline picker
-- was removed (user, 2026-09-26) and a saved choice is dropped here.
local FONT_FLAGS = 'OUTLINE'

local function Migrate(cfg) cfg.outline = nil end

local function GetCfg() return ns.ModuleCfg('bloodBeast', DEFAULTS, Migrate) end
ns.BBGetCfg = GetCfg

-- San'layn: DRW summons the beast for Blood, Dark Transformation for Unholy.
local function IsSanlaynSpec() return ns.IsSpec('DEATHKNIGHT', 1) or ns.IsSpec('DEATHKNIGHT', 3) end

local function IsTrigger(id)
	if ns.BILIsTrigger then return ns.BILIsTrigger(id) end
	if id == nil or secret(id) then return false end
	if ns.IsSpec('DEATHKNIGHT', 1) and id == DRW then return true end
	return ns.IsSpec('DEATHKNIGHT', 3) and DT[id] == true
end

local UNITS = { { 1e9, 'B' }, { 1e6, 'M' }, { 1e3, 'K' } }

local function FormatShort(n)
	n = tonumber(n) or 0
	local neg = n < 0
	if neg then n = -n end
	local out
	for i = 1, #UNITS do
		local div, suffix = UNITS[i][1], UNITS[i][2]
		if n >= div - div / 2000 then
			local s = format('%.1f', n / div)
			s = gsub(s, '%.0$', '')
			out = s .. suffix
			break
		end
	end
	if not out then out = format('%d', Round(n)) end
	if neg then out = '-' .. out end
	return out
end

local function Hex(c, fallback)
	if type(c) ~= 'table' then c = fallback end
	local function ch(v) return mmax(0, mmin(255, Round((tonumber(v) or 1) * 255))) end
	return format('%02x%02x%02x', ch(c[1]), ch(c[2]), ch(c[3]))
end

local function ReadTotal()
	local DM = _G.C_DamageMeter
	local E = _G.Enum
	if not (DM and DM.GetCombatSessionSourceFromType and E and E.DamageMeterSessionType and E.DamageMeterType) then
		return nil
	end
	local guid = UnitGUID('player')
	if not guid or secret(guid) then return nil end
	local ok, src = pcall(DM.GetCombatSessionSourceFromType,
		E.DamageMeterSessionType.Overall, E.DamageMeterType.DamageDone, guid, nil)
	if not ok then return nil end
	if src == nil then return 0 end
	if type(src) ~= 'table' then return nil end
	local spells = src.combatSpells
	if type(spells) ~= 'table' then return 0 end
	local total = 0
	for i = 1, #spells do
		local sp = spells[i]
		if type(sp) == 'table' then
			local id = sp.spellID
			if secret(id) then return nil end
			if id == BEAST then
				local amt = sp.totalAmount
				if secret(amt) then return nil end
				if type(amt) == 'number' then total = total + amt end
			end
		end
	end
	return total
end

local frame, text
local preview = false
local hideTimer, resolveTimer
local pending = false
local castAt = 0
local baseline = 0
local lastPlain
local retries = 0
local shownValue

local function StopTimer(t) if t then t:Cancel() end end

local function EnsureFrame()
	if frame then return end
	frame = CreateFrame('Frame', 'XerionUIBloodBeast', UIParent)
	frame:SetSize(120, 30)
	frame:SetFrameStrata('MEDIUM')
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(false)
	frame:RegisterForDrag('RightButton')
	ns.MakeDraggable(frame, GetCfg, 'x', 'y', function() if ns.BBApply then ns.BBApply() end end)

	text = frame:CreateFontString(nil, 'OVERLAY')
	text:SetFontObject('GameFontNormalLarge')
	text:SetPoint('CENTER')
	text:SetJustifyH('CENTER')
	frame:Hide()
end

local function ApplySettings()
	EnsureFrame()
	local cfg = GetCfg()
	frame:ClearAllPoints()
	frame:SetPoint('CENTER', UIParent, 'CENTER', cfg.x or 0, cfg.y or DEFAULTS.y)
	frame:SetFrameStrata(cfg.strata or 'MEDIUM')
	local size = tonumber(cfg.size) or DEFAULTS.size
	if size < 6 then size = 6 end
	local ok, valid = pcall(text.SetFont, text, ns.GothamNarrowBlackFont(), size, FONT_FLAGS)
	if not ok or valid == false then
		pcall(text.SetFont, text, _G.STANDARD_TEXT_FONT, size, FONT_FLAGS)
	end
	text:SetShadowOffset(0, 0)
	text:SetShadowColor(0, 0, 0, 0)
end

local function Paint(value)
	local cfg = GetCfg()
	text:SetText(format('|cff%s%s|r |cff%s%s|r',
		Hex(cfg.labelColor, DEFAULTS.labelColor), LABEL,
		Hex(cfg.valueColor, DEFAULTS.valueColor), FormatShort(value)))
	local w, h = text:GetStringWidth(), text:GetStringHeight()
	frame:SetSize(mmax(40, (w or 0) + 8), mmax(16, (h or 0) + 4))
end

local function Hide()
	StopTimer(hideTimer)
	hideTimer = nil
	shownValue = nil
	if frame then frame:Hide() end
end

local function Show(value)
	EnsureFrame()
	ApplySettings()
	shownValue = value
	Paint(value)
	frame:Show()
	StopTimer(hideTimer)
	hideTimer = C_Timer.NewTimer(SHOW_FOR, function()
		hideTimer = nil
		if preview then return end
		Hide()
	end)
end

local ScheduleResolve

local function Resolve()
	resolveTimer = nil
	if not pending then return end
	local left = castAt + SETTLE - GetTime()
	if left > 0 then ScheduleResolve(left) return end
	local total = ReadTotal()
	if total == nil then
		if not InCombatLockdown() and retries < RETRY_MAX then
			retries = retries + 1
			ScheduleResolve(RETRY_GAP)
		end
		return
	end
	pending = false
	retries = 0
	local dmg = total - baseline
	if dmg < 0 then dmg = total end
	lastPlain = total
	if dmg > 0 and not preview then Show(dmg) end
end

ScheduleResolve = function(delay)
	StopTimer(resolveTimer)
	resolveTimer = C_Timer.NewTimer(delay, Resolve)
end

local function Nudge()
	if not pending then return end
	retries = 0
	ScheduleResolve(RETRY_GAP)
end

local function OnCast()
	local total = ReadTotal()
	if total ~= nil then lastPlain = total end
	if not pending then
		baseline = lastPlain or 0
		pending = true
	end
	castAt = GetTime()
	retries = 0
	ScheduleResolve(SETTLE)
end

local function Cancel()
	pending = false
	retries = 0
	StopTimer(resolveTimer)
	resolveTimer = nil
end

ns.BBApply = function()
	local cfg = GetCfg()
	if not preview and (not cfg.enable or not IsSanlaynSpec()) then
		Hide()
		Cancel()
		return
	end
	EnsureFrame()
	ApplySettings()
	if preview then
		Paint(PREVIEW_VALUE)
		frame:Show()
	elseif shownValue then
		Paint(shownValue)
	end
end

ns.BBIsPreview = function() return preview and true or false end
-- No spec gate, same as The Blood is Life above it on the page.
ns.BBSetPreview = function(state)
	preview = state and true or false
	EnsureFrame()
	frame:EnableMouse(preview)
	if preview then
		Hide()
		ApplySettings()
		Paint(PREVIEW_VALUE)
		frame:Show()
	else
		frame:Hide()
		if ns.BBApply then ns.BBApply() end
	end
end

local evt = CreateFrame('Frame')
evt:RegisterEvent('PLAYER_ENTERING_WORLD')
evt:RegisterEvent('PLAYER_REGEN_ENABLED')
evt:RegisterUnitEvent('UNIT_SPELLCAST_SUCCEEDED', 'player')
evt:RegisterUnitEvent('PLAYER_SPECIALIZATION_CHANGED', 'player')
pcall(evt.RegisterEvent, evt, 'DAMAGE_METER_RESET')
pcall(evt.RegisterEvent, evt, 'ADDON_RESTRICTION_STATE_CHANGED')

evt:SetScript('OnEvent', function(_, event, arg1, arg2, arg3)
	if event == 'UNIT_SPELLCAST_SUCCEEDED' then
		if preview then return end
		if not GetCfg().enable then return end
		-- Spec first: anyone who is not a Death Knight is turned away without a
		-- spell API read. Both are plain reads, so the order changes nothing
		-- but the cost.
		if not IsSanlaynSpec() then return end
		if not IsTrigger(arg3) then return end
		OnCast()
		return
	end

	if event == 'ADDON_RESTRICTION_STATE_CHANGED' then
		if not pending then return end
		local E = _G.Enum
		local T = E and E.AddOnRestrictionType
		local S = E and E.AddOnRestrictionState
		if secret(arg1) or secret(arg2) or not (T and S) then Nudge() return end
		if arg1 == T.Combat and arg2 == S.Inactive then Nudge() end
		return
	end

	if event == 'PLAYER_REGEN_ENABLED' then
		Nudge()
		return
	end

	if event == 'DAMAGE_METER_RESET' then
		lastPlain = 0
		baseline = 0
		return
	end

	if event == 'PLAYER_SPECIALIZATION_CHANGED' then
		if ns.BBApply then ns.BBApply() end
		return
	end

	Cancel()
	if ns.BBApply then ns.BBApply() end
	if C_Timer and C_Timer.After then
		C_Timer.After(2, function()
			if pending then return end
			local total = ReadTotal()
			if total ~= nil then lastPlain = total end
		end)
	end
end)

_G.SLASH_XERIONBLOODBEAST1 = '/xerionbloodbeast'
_G.SLASH_XERIONBLOODBEAST2 = '/xerionbb'
_G.SlashCmdList.XERIONBLOODBEAST = function(msg)
	msg = type(msg) == 'string' and msg:lower() or ''
	if msg:find('test') then
		Show(PREVIEW_VALUE)
		return
	end
	if msg:find('opt') or msg:find('config') or msg:find('setting') then
		if ns.ShowConfig then ns.ShowConfig('class_dk') end
		C_Timer.After(0.2, function()
			if ns.ShowConfigSubTab then
				ns.ShowConfigSubTab('class_dk', 'The Blood is Life')
			else
				ns.Msg('the settings window is built from an OLD options file (it has no Bloodbeast page). Reload the UI; if this message stays, the XerionUI-Plugin_Options folder in AddOns is out of date.')
			end
		end)
		return
	end
	local cfg = GetCfg()
	local total = ReadTotal()
	ns.Msg(format('Bloodbeast: enabled %s, blood or unholy %s, pending %s, baseline %s, last plain read %s, meter now %s',
		tostring(cfg.enable), tostring(IsSanlaynSpec()), tostring(pending),
		FormatShort(baseline),
		lastPlain and FormatShort(lastPlain) or 'never',
		total and FormatShort(total) or 'unreadable (secret here, or no meter)'))
	local CA = _G.C_AddOns
	local optLoaded = CA and CA.IsAddOnLoaded and CA.IsAddOnLoaded('XerionUI-Plugin_Options')
	local tocBuild = CA and CA.GetAddOnMetadata and CA.GetAddOnMetadata('XerionUI-Plugin_Options', 'X-Build')
	ns.Msg(format('options addon: loaded %s, toc build %s, lua build %s, bloodbeast page known %s',
		tostring(optLoaded), tostring(tocBuild or 'none (old toc)'),
		tostring(ns.OptionsBuild or (optLoaded and 'none (old lua)' or 'window not opened yet')),
		tostring(ns.ShowConfigSubTab ~= nil)))
end
