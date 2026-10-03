local _, ns = ...
local hooksecurefunc, C_Timer = ns.Probe('ShiningLight', hooksecurefunc, C_Timer)
local _G = _G

local CreateFrame = CreateFrame
local UIParent = UIParent
local GetTime = GetTime
local issecretvalue = issecretvalue
local pcall = pcall

local GetPlayerAuraBySpellID = _G.C_UnitAuras and _G.C_UnitAuras.GetPlayerAuraBySpellID

local BigBuffIconFrame

local hasSL = GetPlayerAuraBySpellID and true or false
ns.hasShiningLight = hasSL
if not hasSL then return end

local IS_121 = ns.IS_121
ns.SLDisabled = not IS_121

local function IsProt() return ns.IsSpec('PALADIN', 2) end

local FREE_ID   = 327510
local BASE_FREE_ID = 321136
local SEGMENTS  = 8
local FREE_VAL  = 3

local Round = ns.Round

local DEFAULTS = {
	enable = false,
	alwaysShow = true,
	lock = true,
	barEnable = false,
	width = 348,
	height = 8,
	barX = 0,
	barY = -220,
	attachFrame = '',
	matchWidth = true,
	barStrata = 'MEDIUM',
	bgAlpha = 1,
	freeColor = { 0.23, 0.78, 0.88, 1 },
	chargeColor = { 1, 0.9333, 0.4627, 1 },
	bgColor = { 0.2, 0.2, 0.2, 1 },
	textSize = 12,
	showTimers = true,
}

local function Migrate(cfg)
	if cfg.iconEnable ~= nil then
		if cfg.iconEnable and cfg.barEnable == false then cfg.barEnable = true end
		cfg.iconEnable, cfg.iconW, cfg.iconH = nil, nil, nil
		cfg.iconAttachFrame, cfg.iconAttachSide, cfg.iconAttachFallback = nil, nil, nil
		cfg.stackSize, cfg.stackX, cfg.stackY, cfg.durSize = nil, nil, nil, nil
		cfg.simpleIcon, cfg.iconSize = nil, nil
	end
	if not cfg.alwaysShowFlipped then
		cfg.alwaysShowFlipped = true
		cfg.alwaysShow = true
	end
end

local function GetCfg() return ns.ModuleCfg('shiningLight', DEFAULTS, Migrate) end
ns.SLGetCfg = GetCfg

local BarFont = ns.GothamNarrowBlackFont

local function PlainSeconds(txt)
	if issecretvalue and issecretvalue(txt) then return txt end
	if not txt then return '' end
	return txt:match('%d+') or txt
end

local charge, freeN = 0, 0
local chargeExpire = 0
local preview
local SyncTicker

local frame, segs, textFree, textCharge
local ApplySettings

local function EnsureFrame()
	if frame then return end
	frame = CreateFrame('Frame', 'XerionUIShiningLight', UIParent)
	frame:SetFrameStrata('MEDIUM')
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(false)
	frame:RegisterForDrag('RightButton')
	frame:Hide()

	local function edge()
		local t = frame:CreateTexture(nil, 'BACKGROUND')
		t:SetColorTexture(0, 0, 0, 1)
		return t
	end
	frame.edgeT, frame.edgeB, frame.edgeL, frame.edgeR = edge(), edge(), edge(), edge()
	frame.edgeT:SetPoint('BOTTOMLEFT', frame, 'TOPLEFT', -1, 0)
	frame.edgeT:SetPoint('BOTTOMRIGHT', frame, 'TOPRIGHT', 1, 0)
	frame.edgeT:SetHeight(1)
	frame.edgeB:SetPoint('TOPLEFT', frame, 'BOTTOMLEFT', -1, 0)
	frame.edgeB:SetPoint('TOPRIGHT', frame, 'BOTTOMRIGHT', 1, 0)
	frame.edgeB:SetHeight(1)
	frame.edgeL:SetPoint('TOPRIGHT', frame, 'TOPLEFT', 0, 1)
	frame.edgeL:SetPoint('BOTTOMRIGHT', frame, 'BOTTOMLEFT', 0, -1)
	frame.edgeL:SetWidth(1)
	frame.edgeR:SetPoint('TOPLEFT', frame, 'TOPRIGHT', 0, 1)
	frame.edgeR:SetPoint('BOTTOMLEFT', frame, 'BOTTOMRIGHT', 0, -1)
	frame.edgeR:SetWidth(1)

	frame.ticks = {}
	for i = 1, SEGMENTS - 1 do
		frame.ticks[i] = frame:CreateTexture(nil, 'BACKGROUND')
	end

	segs = {}
	for i = 1, SEGMENTS do
		segs[i] = frame:CreateTexture(nil, 'ARTWORK')
	end

	textFree = frame:CreateFontString(nil, 'OVERLAY')
	textFree:SetDrawLayer("BACKGROUND")
	textFree:SetPoint('LEFT', frame, 'LEFT', 4, 0)
	textFree:SetJustifyH('LEFT')
	textCharge = frame:CreateFontString(nil, 'OVERLAY')
	textCharge:SetDrawLayer("BACKGROUND")
	textCharge:SetPoint('RIGHT', frame, 'RIGHT', -4, 0)
	textCharge:SetJustifyH('RIGHT')

	ns.MakeDraggable(frame, GetCfg, 'barX', 'barY', function() ApplySettings() end,
		function(cfg) return not cfg.lock and (cfg.attachFrame or '') == '' end)
	local acc = 0
	frame:SetScript('OnUpdate', function(_, elapsed)
		acc = acc + elapsed
		if acc < 0.1 then return end
		if chargeExpire > 0 then
			chargeExpire = chargeExpire - acc
		end
		if chargeExpire < 0 then
			charge = 0
			chargeExpire = 0
		end
		acc = 0
		if preview then return end
		local cfg = GetCfg()
		if cfg.showTimers then
			local freeTxt = ''
			if freeN > 0 and BigBuffIconFrame and BigBuffIconFrame.Cooldown then
				local okT, fsCd = pcall(BigBuffIconFrame.Cooldown.GetCountdownFontString, BigBuffIconFrame.Cooldown)
				if okT and fsCd then freeTxt = fsCd:GetText() or '' end
			end
			textFree:SetText(freeTxt)
			textCharge:SetText(chargeExpire > 0 and PlainSeconds(tostring(chargeExpire)) or "")
		else
			if textFree:GetText() then textFree:SetText('') end
			if textCharge:GetText() then textCharge:SetText('') end
		end
	end)
end

ApplySettings = function()
	EnsureFrame()
	local cfg = GetCfg()
	local w, h = cfg.width or 348, cfg.height or 8

	local target
	if (cfg.attachFrame or '') ~= '' then
		local t = _G[cfg.attachFrame]
		if type(t) == 'table' and t.GetObjectType and t.GetWidth then target = t end
	end
	frame:ClearAllPoints()
	if target then
		frame:SetPoint('BOTTOM', target, 'TOP', cfg.barX or 0, cfg.barY or 2)
		if cfg.matchWidth then
			local tw = Round(target:GetWidth() or 0)
			if tw >= 50 then w = tw end
		end
	else
		frame:SetPoint('CENTER', UIParent, 'CENTER', cfg.barX or 0, cfg.barY or -220)
	end
	frame:SetSize(w, h)
	frame:SetFrameStrata(cfg.barStrata or 'MEDIUM')

	local ba = cfg.bgAlpha or 1
	frame.edgeT:SetColorTexture(0, 0, 0, ba)
	frame.edgeB:SetColorTexture(0, 0, 0, ba)
	frame.edgeL:SetColorTexture(0, 0, 0, ba)
	frame.edgeR:SetColorTexture(0, 0, 0, ba)

	local gap = 1
	local segW = (w - gap * (SEGMENTS - 1)) / SEGMENTS
	for i = 1, SEGMENTS do
		local s = segs[i]
		s:ClearAllPoints()
		s:SetSize(segW, h)
		s:SetDrawLayer("BACKGROUND")
		s:SetPoint('LEFT', frame, 'LEFT', (i - 1) * (segW + gap), 0)
	end
	for i = 1, SEGMENTS - 1 do
		local t = frame.ticks[i]
		t:SetColorTexture(0, 0, 0, ba)
		t:ClearAllPoints()
		t:SetSize(gap, h)
		t:SetPoint('LEFT', frame, 'LEFT', i * segW + (i - 1) * gap, 0)
	end

	local font = BarFont()
	textFree:SetFont(font, cfg.textSize or 12, 'OUTLINE')
	textCharge:SetFont(font, cfg.textSize or 12, 'OUTLINE')
	textFree:SetTextColor(1, 1, 1)
	textCharge:SetTextColor(1, 1, 1)
end

-- What the segments were last painted from. The poll below repaints only
-- when one of these moved; every other caller (settings, preview, spec
-- change) paints unconditionally. Both are plain numbers this file sets
-- itself - nothing drawn here comes from a secret. nil means "paint next
-- time", which is what a hidden bar leaves behind.
local drawnFree, drawnCharge

local function RenderBar()
	if not frame then return end
	local cfg = GetCfg()
	if not cfg.barEnable or not cfg.enable or not (preview or IsProt()) then
		drawnFree, drawnCharge = nil, nil
		frame:Hide()
		return
	end
	local fc = cfg.freeColor or { 0.23, 0.78, 0.88, 1 }
	local cc = cfg.chargeColor or { 1, 0.9333, 0.4627, 1 }
	local bgc = cfg.bgColor or { 0.2, 0.2, 0.2, 1 }
	local filledFree = freeN * FREE_VAL
	for i = 1, SEGMENTS do
		local s = segs[i]
		if i <= filledFree then
			s:SetColorTexture(fc[1] or 0, fc[2] or 0.8, fc[3] or 1, fc[4] or 1)
		elseif i <= filledFree + charge then
			s:SetColorTexture(cc[1] or 1, cc[2] or 0.9, cc[3] or 0.4, cc[4] or 1)
		else
			s:SetColorTexture(bgc[1] or 0.2, bgc[2] or 0.2, bgc[3] or 0.2, cfg.bgAlpha or 1)
		end
		s:Show()
	end
	if preview or (filledFree + charge) > 0 or cfg.alwaysShow then
		frame:Show()
	else
		frame:Hide()
	end
	drawnFree, drawnCharge = freeN, charge
end

ns.SLApply = function()
	if ns.SLDisabled then
		if frame then frame:Hide() end
		SyncTicker()
		return
	end
	ApplySettings()
	if preview then RenderBar() SyncTicker() return end
	if GetCfg().enable then
		RenderBar()
	else
		charge, freeN, chargeExpire = 0, 0, 0
		if frame then frame:Hide() end
	end
	SyncTicker()
end

ns.SLIsPreview = function() return preview and true or false end
ns.SLSetPreview = function(state)
	if ns.SLDisabled then return end
	preview = state and true or false
	EnsureFrame()
	ApplySettings()
	frame:EnableMouse(preview)
	if preview then
		charge, freeN = 2, 1
		chargeExpire = GetTime() + (29)
		RenderBar()
		textFree:SetText('12')
		textCharge:SetText('26')
	else
		charge, freeN, chargeExpire = 0, 0, 0
		textFree:SetText('')
		textCharge:SetText('')
		RenderBar()
	end
	SyncTicker()
end

-- WHY THE FOUND ICON IS RE-CHECKED
-- The Cooldown Manager's icons are pooled: after a relayout, a spec change or
-- an edit of the tracked list, the frame we found can be released and handed
-- to another buff, and its stack text would then be read as Shining Light's
-- free charges. The cooldown ID the viewer gave the frame is plain layout
-- data it clears on release, so it is taken when the frame is found and a
-- frame whose ID changed is dropped and searched for again. An ID that reads
-- secret or cannot be read keeps the frame, which is what happened before.
local bigBuffCdID

local function CdIDOf(iframe)
	if type(iframe.GetCooldownID) ~= 'function' then return nil end
	local ok, id = pcall(iframe.GetCooldownID, iframe)
	if not ok or (issecretvalue and issecretvalue(id)) then return nil end
	return id
end

local function StillOurs(iframe)
	if bigBuffCdID == nil or type(iframe.GetCooldownID) ~= 'function' then return true end
	local ok, id = pcall(iframe.GetCooldownID, iframe)
	if not ok or (issecretvalue and issecretvalue(id)) then return true end
	return id == bigBuffCdID
end

local evt = CreateFrame('Frame')
evt:RegisterEvent('PLAYER_ENTERING_WORLD')
evt:RegisterUnitEvent('UNIT_SPELLCAST_SUCCEEDED', 'player')
evt:RegisterUnitEvent('PLAYER_SPECIALIZATION_CHANGED', 'player')
evt:SetScript('OnEvent', function(_, event, unit, _, spellID)
	if preview or ns.SLDisabled then return end
	local cfg = GetCfg()
	if not cfg.enable then return end
	if event == 'PLAYER_SPECIALIZATION_CHANGED' then
		charge, freeN, chargeExpire = 0, 0, 0
		RenderBar()
		SyncTicker()
	elseif event == 'UNIT_SPELLCAST_SUCCEEDED' then
		-- a secret spell ID cannot be compared; Shield of the Righteous is not
		-- one, so a secret payload is never ours
		if issecretvalue and issecretvalue(spellID) then return end
		if spellID == 53600 then
			if charge + 1 > 2 then
				charge = 0
				chargeExpire = 0
			elseif charge == 1 then
				charge = 2
				chargeExpire = 29.5
			else
				charge = 1
				chargeExpire = 29.5
			end
		end
	else
		ApplySettings()
		SyncTicker()
		C_Timer.After(2, function()
			ApplySettings()
			local viewer = _G.BuffIconCooldownViewer
			if viewer and viewer.GetChildren then
				for _, iframe in ipairs({ viewer:GetChildren() }) do
					local spellID = (type(iframe.GetSpellID) == "function") and iframe:GetSpellID() or nil
					if spellID and not (issecretvalue and issecretvalue(spellID))
						and (spellID == FREE_ID or spellID == BASE_FREE_ID) then
						BigBuffIconFrame = iframe
						bigBuffCdID = CdIDOf(iframe)
					end
				end
			end
			SyncTicker()
		end)
	end
end)

local function ShiningLightTick()
	-- Anything that should have stopped the poll and did not (a setting
	-- flipped by a path that skipped SLApply) stops it here instead.
	if preview or ns.SLDisabled then SyncTicker() return end
	local cfg = GetCfg()
	if not cfg.enable then SyncTicker() return end
	local viewer = _G.BuffIconCooldownViewer
	if BigBuffIconFrame and not StillOurs(BigBuffIconFrame) then
		BigBuffIconFrame, bigBuffCdID = nil, nil
		freeN = 0
	end
	if not BigBuffIconFrame and viewer and viewer.GetChildren then
		for _, iframe in ipairs({ viewer:GetChildren() }) do
			local spellID = (type(iframe.GetSpellID) == "function") and iframe:GetSpellID() or nil
			if spellID and not (issecretvalue and issecretvalue(spellID))
				and (spellID == FREE_ID or spellID == BASE_FREE_ID) then
				BigBuffIconFrame = iframe
				bigBuffCdID = CdIDOf(iframe)
			end
		end
	elseif BigBuffIconFrame and BigBuffIconFrame.Applications and BigBuffIconFrame.Applications.Applications then
		if BigBuffIconFrame:IsVisible() then
			if BigBuffIconFrame.Applications.Applications:GetText() then
				freeN = 2
			else
				freeN = 1
			end
		else
			freeN = 0
		end
	end
	if freeN ~= drawnFree or charge ~= drawnCharge then RenderBar() end
end

-- WHO GETS THE POLL
-- The poll used to be a file-level ticker that ran four times a second for
-- every character once the module was on - settings are account-wide, so
-- that was every class, walking the buff viewer's children forever looking
-- for a Shining Light icon only a Protection paladin can have. It now runs
-- only while it can draw something: module on, bar on, Protection, no
-- preview (preview paints its own fixed picture and the poll returned at
-- once in it anyway). Everything the poll fed is invisible outside that
-- state - the bar is hidden by RenderBar the moment any of those is false -
-- so stopping it changes nothing on screen. It is re-asked from SLApply
-- (settings, profile switch, login), the preview toggle, a spec change and
-- a loading screen. Starting it takes one pass at once, so a bar switched
-- on is painted from fresh counts rather than whatever was left from before.
local slTicker
SyncTicker = function()
	local cfg = GetCfg()
	local want = not preview and not ns.SLDisabled and cfg.enable and cfg.barEnable and IsProt()
	if want and not slTicker then
		slTicker = C_Timer.NewTicker(0.25, ShiningLightTick)
		ShiningLightTick()
	elseif not want and slTicker then
		slTicker:Cancel()
		slTicker = nil
	end
end
