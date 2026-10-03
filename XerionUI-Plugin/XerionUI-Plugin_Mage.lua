local _, ns = ...
local hooksecurefunc, C_Timer = ns.Probe('Mage', hooksecurefunc, C_Timer)
local _G = _G

local _, playerClass = _G.UnitClass('player')
local isMage = (playerClass == 'MAGE')
ns.hasMage = true

local CreateFrame = CreateFrame
local C_Timer = C_Timer
local GetTime = GetTime
local UnitHealth, UnitHealthMax = UnitHealth, UnitHealthMax
local issecretvalue = issecretvalue
local pcall = pcall
local AuraPayloadChurns = ns.AuraPayloadChurns

local ALTER_TIME_CAST   = 342245
local ALTER_TIME_BUFF   = 342246
local ALTER_TIME_BUFF_2 = 444754
local ALTER_TIME_RETURN = 342247
local MAX_WINDOW = 10.2

local DEFAULTS = {
	enable = false,
	lock = false,
	size = 24,
	x = 0,
	y = -180,
	anchorCDM = true,
	anchorX = 0,
	anchorY = 0,
}

local function GetCfg() return ns.ModuleCfg('mageAlterTime', DEFAULTS) end
ns.MageGetCfg = GetCfg

local frame, preview
local activeUntil
local armedAt = 0
local capToken
local ApplySettings
local TryAnchor

local function EnsureFrame()
	if frame then return end
	frame = CreateFrame('Frame', 'XerionUIAlterTimeHP', _G.UIParent)
	frame:SetSize(120, 40)
	frame:SetFrameStrata('MEDIUM')
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(false)
	frame:RegisterForDrag('RightButton')
	frame:Hide()
	frame.text = frame:CreateFontString(nil, 'OVERLAY')
	frame.text:SetPoint('CENTER')
	ns.MakeDraggable(frame, GetCfg, 'x', 'y', function() ApplySettings() end)
end

ApplySettings = function()
	EnsureFrame()
	local cfg = GetCfg()
	frame.text:SetFont(ns.GetFont(), cfg.size or 24, 'OUTLINE')
	frame.text:SetTextColor(0.25, 0.78, 0.92, 1)
	frame:SetFrameStrata('MEDIUM')
	frame:ClearAllPoints()
	frame:SetPoint('CENTER', _G.UIParent, 'CENTER', cfg.x or 0, cfg.y or -180)
	frame:EnableMouse((preview and not cfg.lock) and true or false)
	if not cfg.enable and not preview then
		activeUntil = nil
		frame:Hide()
	end
	if activeUntil and TryAnchor then TryAnchor() end
end
ns.MageApply = ApplySettings

TryAnchor = function()
	if not activeUntil then return false end
	local cfg = GetCfg()
	if not cfg.anchorCDM or not ns.CDSFindBuffFrame then return false end
	local icon = ns.CDSFindBuffFrame(ALTER_TIME_BUFF)
		or ns.CDSFindBuffFrame(ALTER_TIME_BUFF_2)
		or ns.CDSFindBuffFrame(ALTER_TIME_CAST)
	if not icon then return false end
	frame:SetParent(icon)
	frame:SetFrameLevel(icon:GetFrameLevel() + 30)
	frame:ClearAllPoints()
	frame:SetPoint('CENTER', icon, 'CENTER', cfg.anchorX or 0, cfg.anchorY or 0)
	return true
end

local function Detach()
	if not frame then return end
	frame:SetParent(_G.UIParent)
	ApplySettings()
end

local function HideSnapshot()
	activeUntil = nil
	if frame then
		if not preview then frame:Hide() end
		Detach()
	end
end

local pctCurve
local function GetPctCurve()
	if pctCurve ~= nil then return pctCurve or nil end
	pctCurve = false
	if _G.CurveConstants and _G.CurveConstants.ScaleTo100 then
		pctCurve = _G.CurveConstants.ScaleTo100
		return pctCurve
	end
	local CU = _G.C_CurveUtil
	if CU and CU.CreateCurve then
		local ok, c = pcall(function()
			local c = CU.CreateCurve()
			if c.SetType and _G.Enum and _G.Enum.LuaCurveType then
				c:SetType(_G.Enum.LuaCurveType.Linear)
			end
			c:AddPoint(0, 0)
			c:AddPoint(1, 100)
			return c
		end)
		if ok and c then pctCurve = c end
	end
	return pctCurve or nil
end

local function StartSnapshot()
	local cfg = GetCfg()
	if not cfg.enable or preview then return end
	ApplySettings()
	local shown = false
	local UHP = _G.UnitHealthPercent
	local curve = UHP and GetPctCurve()
	if UHP and curve then
		shown = pcall(function()
			frame.text:SetFormattedText('%.0f%%', UHP('player', false, curve))
		end)
	end
	if not shown then
		shown = pcall(function()
			frame.text:SetFormattedText('%.0f%%',
				UnitHealth('player') / UnitHealthMax('player') * 100)
		end)
	end
	if not shown then frame.text:SetText('?') end
	armedAt = GetTime()
	activeUntil = armedAt + MAX_WINDOW
	frame:Show()
	if not TryAnchor() then
		C_Timer.After(0.3, TryAnchor)
	end
	local token = {}
	capToken = token
	C_Timer.After(MAX_WINDOW, function()
		if capToken == token then HideSnapshot() end
	end)
end

local function ScanForAlterTimeBuff()
	local AU = _G.AuraUtil
	if not (AU and AU.ForEachAura) then return nil end
	local found
	pcall(AU.ForEachAura, 'player', 'HELPFUL', nil, function(a)
		if a and type(a.name) == 'string' and a.name:lower():find('alter time') then
			found = a.spellId
			return true
		end
	end, true)
	return found
end

local TARGET_BUFFS = { [ALTER_TIME_BUFF] = true, [ALTER_TIME_BUFF_2] = true }

-- The visitor lives at file level so a scan does not build a fresh closure
-- per UNIT_AURA; the two flags it reports through are reset by every scan
-- before it runs.
local bpSawAny, bpFound = false, false
local function BuffPresentVisit(a)
	if not a then return end
	bpSawAny = true
	local id = a.spellId
	if id ~= nil and not (issecretvalue and issecretvalue(id)) and TARGET_BUFFS[id] then
		bpFound = true
		return true
	end
	local nm = a.name
	if type(nm) == 'string' and nm:lower():find('alter time') then
		bpFound = true
		return true
	end
end

local function BuffPresent()
	local AU = _G.AuraUtil
	if not (AU and AU.ForEachAura) then return nil end
	bpSawAny, bpFound = false, false
	local ok = pcall(AU.ForEachAura, 'player', 'HELPFUL', nil, BuffPresentVisit, true)
	if not ok then return nil end
	if bpFound then return true end
	if bpSawAny then return false end
	return nil
end

-- ONE SCAN PER CHANGE, NOT PER EVENT
-- Every player UNIT_AURA used to walk all helpful auras. A readable payload
-- that only refreshed or restacked auras already there cannot have added or
-- dropped Alter Time, so the last scan's answer still stands and is reused.
-- The time checks below still run on every event exactly as before - only
-- the walk is skipped. The remembered answer is thrown away whenever an
-- event goes unscanned (module off, preview, a loading screen, death), so a
-- reuse always follows an unbroken run of scanned or update-only events; an
-- unknown answer (nil) is never reused. An unreadable payload counts as a
-- change (AuraPayloadChurns), so restricted content scans as it always did.
local lastPresent

local function OnAuraUpdate(info)
	local cfg = GetCfg()
	if not cfg.enable or preview then lastPresent = nil return end
	local present
	if lastPresent ~= nil and not AuraPayloadChurns(info) then
		present = lastPresent
	else
		present = BuffPresent()
		lastPresent = present
	end
	if not activeUntil then
		if present == true then StartSnapshot() end
		return
	end
	local now = GetTime()
	if now >= activeUntil then HideSnapshot() return end
	if now - armedAt < 0.5 then return end
	if present == false then HideSnapshot() end
end

ns.MageIsPreview = function() return preview and true or false end
ns.MageSetPreview = function(v)
	preview = v and true or false
	EnsureFrame()
	ApplySettings()
	if preview then
		frame.text:SetText('87%')
		frame:Show()
	elseif not activeUntil then
		frame:Hide()
	end
end

if isMage then
local evt = CreateFrame('Frame')
evt:RegisterUnitEvent('UNIT_SPELLCAST_SUCCEEDED', 'player')
evt:RegisterUnitEvent('UNIT_AURA', 'player')
evt:RegisterEvent('PLAYER_ENTERING_WORLD')
evt:RegisterEvent('PLAYER_DEAD')
evt:SetScript('OnEvent', function(_, event, _, arg2, arg3)
	if event == 'UNIT_SPELLCAST_SUCCEEDED' then
		local sid = arg3
		if issecretvalue and issecretvalue(sid) then return end
		if sid == ALTER_TIME_CAST then
			StartSnapshot()
		elseif sid == ALTER_TIME_RETURN then
			HideSnapshot()
		end
	elseif event == 'UNIT_AURA' then
		-- UNIT_AURA's payload is its second argument (unit, updateInfo).
		OnAuraUpdate(arg2)
	else
		lastPresent = nil
		HideSnapshot()
	end
end)
end

local watchUntil = 0
local watchLastDump = 0
local watchFrame
local function DumpHelpfulIds(tag)
	local AU = _G.AuraUtil
	if not (AU and AU.ForEachAura) then
		print('|cff33ccffKiraMage|r ['..tag..'] AuraUtil.ForEachAura unavailable')
		return
	end
	local ids, secretNames = {}, 0
	pcall(AU.ForEachAura, 'player', 'HELPFUL', nil, function(a)
		if a then
			if a.spellId ~= nil then ids[#ids + 1] = tostring(a.spellId) end
			if type(a.name) ~= 'string' then secretNames = secretNames + 1 end
		end
	end, true)
	print('|cff33ccffKiraMage|r ['..tag..'] helpful ids:',
		(#ids > 0 and table.concat(ids, ', ') or '(none/secret)'),
		'| unreadable names:', secretNames)
end
local function MageWatchArm()
	watchUntil = GetTime() + 12
	if not watchFrame then
		watchFrame = CreateFrame('Frame')
		watchFrame:RegisterUnitEvent('UNIT_SPELLCAST_SUCCEEDED', 'player')
		watchFrame:RegisterUnitEvent('UNIT_AURA', 'player')
		watchFrame:SetScript('OnEvent', function(_, ev, _, _, sid)
			if GetTime() > watchUntil then return end
			if ev == 'UNIT_SPELLCAST_SUCCEEDED' then
				local isSecret = issecretvalue and issecretvalue(sid)
				print('|cff33ccffKiraMage|r CAST success | secret:', isSecret and 'YES' or 'no',
					'| id:', isSecret and '<secret>' or tostring(sid))
				DumpHelpfulIds('post-cast')
			else
				local now = GetTime()
				if now - watchLastDump >= 0.3 then
					watchLastDump = now
					DumpHelpfulIds('aura-change')
				end
			end
		end)
	end
	DumpHelpfulIds('before-cast')
end

SLASH_XERIONMAGE1 = '/xerionmage'
SlashCmdList.XERIONMAGE = function()
	local function p(...) print('|cff33ccffKiraMage|r', ...) end
	local cfg = GetCfg()
	p('enable:', tostring(cfg.enable), '| preview:', tostring(preview),
		'| anchorCDM:', tostring(cfg.anchorCDM), '| showing now:', activeUntil and 'YES' or 'no')

	local present = BuffPresent()
	p('buff id', ALTER_TIME_BUFF, 'present:',
		present == true and 'YES' or (present == false and 'no' or 'unknown (secret/no API)'))
	local disc = ScanForAlterTimeBuff()
	if disc then
		p('name scan found active "Alter Time" buff -> real id:', disc,
			disc ~= ALTER_TIME_BUFF and '|cffff6600(differs from '..ALTER_TIME_BUFF..'!)|r' or '(matches)')
	else
		p('name scan: no active "Alter Time" buff found (cast it first, stay unrestricted)')
	end

	local UHP = _G.UnitHealthPercent
	local curve = UHP and GetPctCurve()
	p('UnitHealthPercent api:', UHP and 'yes' or 'NO', '| scale curve:', curve and 'yes' or 'NO')
	local ok, val = pcall(function() return UHP and curve and UHP('player', false, curve) end)
	local secret = (issecretvalue and val ~= nil and issecretvalue(val)) and 'yes' or 'no'
	p('health read ok:', tostring(ok), '| value secret:', secret)

	local icon = ns.CDSFindBuffFrame and (ns.CDSFindBuffFrame(ALTER_TIME_BUFF)
		or (disc and ns.CDSFindBuffFrame(disc)) or ns.CDSFindBuffFrame(ALTER_TIME_CAST))
	p('CDM buff icon found:', icon and 'YES' or 'no (will use free screen position)')

	p('=> forcing a 5s TEST display at the free position (x='..(cfg.x or 0)..', y='..(cfg.y or -180)..')')
	EnsureFrame()
	frame:SetParent(_G.UIParent)
	frame.text:SetFont(ns.GetFont(), cfg.size or 24, 'OUTLINE')
	frame.text:SetTextColor(0.25, 0.78, 0.92, 1)
	if ok and val ~= nil then
		frame.text:SetFormattedText('%.0f%%', val)
	else
		frame.text:SetText('TEST')
	end
	frame:ClearAllPoints()
	frame:SetPoint('CENTER', _G.UIParent, 'CENTER', cfg.x or 0, cfg.y or -180)
	frame:SetFrameStrata('FULLSCREEN_DIALOG')
	frame:Show()
	local tok = {}
	capToken = tok
	C_Timer.After(5, function()
		if capToken == tok and not activeUntil then
			frame:SetFrameStrata('MEDIUM')
			if not preview then frame:Hide() end
			ApplySettings()
		end
	end)
	p('=> if you see a number/TEST in the screen centre, the display works and the issue is the trigger/anchor above')

	MageWatchArm()
	p('=> WATCHING 12s: cast Alter Time NOW - I will log the cast id and your buff ids so we find the real one')
end
