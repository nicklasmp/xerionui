local _, ns = ...
local hooksecurefunc, C_Timer = ns.Probe('BloodIsLife', hooksecurefunc, C_Timer)
local _G = _G

local CreateFrame = CreateFrame
local UIParent = UIParent
local GetTime = GetTime
local GetPhysicalScreenSize = GetPhysicalScreenSize
local pcall = pcall
local tonumber = tonumber
local C_Timer = C_Timer
local mceil = math.ceil
local mmax, mmin = math.max, math.min
local format = string.format

ns.hasBloodIsLife = true

local Round = ns.Round
local secret = ns.IsSecret

-- TWO SPECS, TWO TRIGGERS
-- The talent is San'layn, which Blood and Unholy share: Dancing Rune Weapon
-- summons the Blood Beast for Blood, Dark Transformation for Unholy, 10 s
-- either way. Each spec answers to its own spell only; an unreadable spec
-- makes both IsSpec checks say yes, so both spells then count.
-- Dark Transformation's 12.x cast is 1233448; 63560 is the pre-Midnight ID,
-- kept because it costs nothing (the Blightfall chain takes both). With only
-- the old one listed, Unholy never started the icon (user, 2026-09-26).
local DRW      = 49028
local DT       = { [1233448] = true, [63560] = true }
local BIL_ICON = 2032221
local DURATION = 10

local function IsBlood() return ns.IsSpec('DEATHKNIGHT', 1) end
local function IsUnholy() return ns.IsSpec('DEATHKNIGHT', 3) end
local function IsSanlaynSpec() return IsBlood() or IsUnholy() end

local DEFAULTS = {
	enable = false,
	lock = true,
	width = 44,
	height = 44,
	x = 0,
	y = -210,
	strata = 'MEDIUM',
	border = { 0.77, 0.12, 0.23, 1 },
	showSwipe = true,

	durText = false,
	durSize = 0,
	textColor = { 1, 1, 1, 1 },

	glowColor = { 1, 0.16, 0.16, 1 },
	-- Screen pixels, not UI units: the old fixed 2 units drew twice as thick
	-- as the 1 px icon border (user, 2026-09-26). GlowUnits converts.
	glowThickness = 1,

	euiAnchor = false,
	euiBarKey = '',
	euiPlace = 'CENTER',
	euiOffsetX = 0,
	euiOffsetY = 0,
}

local TextFont = ns.GothamNarrowBlackFont

local function GetCfg() return ns.ModuleCfg('bloodIsLife', DEFAULTS) end
ns.BILGetCfg = GetCfg

local ResolveGroup  = ns.CDMResolveGroup
local AnchorToGroup = ns.CDMAnchorTo


local function BaseOf(id)
	if id == nil or secret(id) then return id end
	local CS = _G.C_Spell
	if CS and CS.GetBaseSpell then
		local ok, base = pcall(CS.GetBaseSpell, id)
		if ok and base and not secret(base) then return base end
	end
	local CSB = _G.C_SpellBook
	if CSB and CSB.FindBaseSpellByID then
		local ok, base = pcall(CSB.FindBaseSpellByID, id)
		if ok and base and not secret(base) then return base end
	end
	return id
end

local function IsDRW(id)
	if id == nil or secret(id) then return false end
	if id == DRW then return true end
	return BaseOf(id) == DRW
end

-- Exact IDs only, no BaseOf: once Dark Transformation is pressed, Blightfall
-- (1271967) takes over its button, and the client then names Dark
-- Transformation as Blightfall's base spell - so the lookup made every
-- Blightfall press start a second timer with no Blood Beast behind it
-- (user, 2026-09-26).
local function IsDT(id)
	if id == nil or secret(id) then return false end
	return DT[id] == true
end

local function IsTrigger(id)
	if IsBlood() and IsDRW(id) then return true end
	return IsUnholy() and IsDT(id)
end
ns.BILIsTrigger = IsTrigger

local frame, btn, glowHost
local expiresAt = 0
local preview = false
local hideTimer
local upTicker

local function Active() return expiresAt > 0 and expiresAt > GetTime() end

local function EnsureFrame()
	if frame then return end
	frame = CreateFrame('Frame', 'XerionUIBloodIsLife', UIParent)
	frame:SetFrameStrata('MEDIUM')
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(false)
	frame:RegisterForDrag('RightButton')

	local dragCX, dragCY
	frame:SetScript('OnDragStart', function(self)
		if GetCfg().lock then return end
		dragCX, dragCY = self:GetCenter()
		self:StartMoving()
	end)
	frame:SetScript('OnDragStop', function(self)
		self:StopMovingOrSizing()
		local cfg = GetCfg()
		local cx, cy = self:GetCenter()
		if cfg.euiAnchor then
			if cx and dragCX then
				cfg.euiOffsetX = (cfg.euiOffsetX or 0) + Round(cx - dragCX)
				cfg.euiOffsetY = (cfg.euiOffsetY or 0) + Round(cy - dragCY)
			end
		elseif cx then
			local ux, uy = UIParent:GetCenter()
			if ux then
				cfg.x = Round(cx - ux)
				cfg.y = Round(cy - uy)
			end
		end
		dragCX, dragCY = nil, nil
		if ns.BILApply then ns.BILApply() end
	end)
	ns.DragAnywhere(frame)

	btn = CreateFrame('Frame', nil, frame)
	btn.border = btn:CreateTexture(nil, 'BACKGROUND')
	btn.border:SetAllPoints()

	btn.Icon = btn:CreateTexture(nil, 'ARTWORK')
	btn.Icon:SetPoint('TOPLEFT', 1, -1)
	btn.Icon:SetPoint('BOTTOMRIGHT', -1, 1)
	btn.Icon:SetTexture(BIL_ICON)

	btn.Cooldown = CreateFrame('Cooldown', nil, btn, 'CooldownFrameTemplate')
	btn.Cooldown:SetAllPoints()
	btn.Cooldown:SetDrawEdge(false)
	btn.Cooldown:SetDrawBling(false)
	btn.Cooldown:SetReverse(true)
	if btn.Cooldown.SetHideCountdownNumbers then btn.Cooldown:SetHideCountdownNumbers(true) end
	btn.Cooldown.noCooldownCount = true

	btn.Text = btn.Cooldown:CreateFontString(nil, 'OVERLAY')
	btn.Text:SetPoint('CENTER')

	glowHost = CreateFrame('Frame', nil, frame)
	glowHost:SetPoint('CENTER', frame, 'CENTER', 0, 0)
	glowHost:EnableMouse(false)

	frame:Hide()
end

local CROP = 0.07
local function IconCoords(w, h) return ns.IconCoords(w, h, CROP) end

local glowingNow, glowW, glowH, glowTh = false, 0, 0, 0
local glowProxy = {}

-- cfg.glowThickness screen pixels in the glow host's units. One pixel is
-- under a unit whenever the UI scale is above pixel-perfect, which is why the
-- glow engine accepts fractions. Falls back to units if the client cannot say.
local function GlowUnits(cfg)
	local px = tonumber(cfg.glowThickness) or DEFAULTS.glowThickness
	if px < 1 then px = 1 end
	local _, ph = GetPhysicalScreenSize()
	local s = glowHost:GetEffectiveScale()
	if not ph or ph <= 0 or not s or s <= 0 then return px end
	return px * 768 / ph / s
end

local function StopGlow()
	if not glowHost then return end
	pcall(ns.GlowStop, glowHost)
	glowingNow = false
end

local function StartGlow(w, h)
	if not glowHost then return end
	local cfg = GetCfg()
	local th = GlowUnits(cfg)
	if glowingNow and w == glowW and h == glowH and th == glowTh then return end
	if glowingNow then StopGlow() end
	glowProxy.glow = true
	glowProxy.glowType = 'pixel'
	glowProxy.glowColor = cfg.glowColor or DEFAULTS.glowColor
	glowProxy.glowThickness = th
	ns.GlowStart(glowHost, w, h, glowProxy)
	glowingNow, glowW, glowH, glowTh = true, w, h, th
end

local function ApplySettings()
	EnsureFrame()
	local cfg = GetCfg()

	local w = cfg.width or 44
	local h = cfg.height or 44

	local grp
	if cfg.euiAnchor then grp = ResolveGroup(cfg) end

	if not (grp and AnchorToGroup(frame, cfg)) then
		frame:ClearAllPoints()
		frame:SetPoint('CENTER', UIParent, 'CENTER', cfg.x or 0, cfg.y or -210)
	end
	frame:SetSize(w, h)
	frame:SetFrameStrata(cfg.strata or 'MEDIUM')

	if grp then
		local okL, lvl = pcall(grp.GetFrameLevel, grp)
		if okL and lvl then pcall(frame.SetFrameLevel, frame, lvl + 10) end
	end

	btn:SetSize(w, h)
	btn:ClearAllPoints()
	btn:SetPoint('CENTER', frame, 'CENTER', 0, 0)
	btn.Icon:SetTexture(BIL_ICON)
	btn.Icon:SetTexCoord(IconCoords(w, h))
	btn:Show()

	local c = cfg.border or DEFAULTS.border
	btn.border:SetColorTexture(c[1] or 1, c[2] or 0, c[3] or 0, c[4] or 1)

	local tc = cfg.textColor or DEFAULTS.textColor
	local ds = cfg.durSize or 0
	if ds <= 0 then ds = mmax(10, Round(mmin(w, h) * 0.36)) end
	btn.Text:SetFont(TextFont(), ds, 'OUTLINE')
	btn.Text:SetTextColor(tc[1] or 1, tc[2] or 1, tc[3] or 1, tc[4] or 1)
	btn.Text:SetShown(cfg.durText and true or false)

	glowHost:SetSize(w, h)
	local ok, lvl = pcall(frame.GetFrameLevel, frame)
	if ok and lvl then pcall(glowHost.SetFrameLevel, glowHost, lvl + 5) end

	if glowingNow then StartGlow(w, h) end
end

local function Render()
	if not frame then return end
	local cfg = GetCfg()

	if not (preview or (cfg.enable and Active())) then
		StopGlow()
		frame:Hide()
		return
	end

	if cfg.euiAnchor and (cfg.euiPlace or 'CENTER') ~= 'CENTER' then
		AnchorToGroup(frame, cfg)
	end

	StartGlow(frame:GetWidth(), frame:GetHeight())
	frame:Show()
end

local function StopHideTimer()
	if hideTimer then hideTimer:Cancel() hideTimer = nil end
end

local function StopUpTicker()
	if upTicker then upTicker:Cancel() upTicker = nil end
end

local function TailAnchored(cfg)
	return cfg.euiAnchor and (cfg.euiPlace or 'CENTER') ~= 'CENTER'
end

-- The whole second the text shows now, so the 0.1 s tick sets it once a
-- second instead of ten times. A plain number from GetTime, never a secret;
-- forgotten by Clear, which is the only other writer of the text.
local paintedSecs

local function PaintText()
	if not btn or not btn.Text then return end
	local left = expiresAt - GetTime()
	if left < 0 then left = 0 end
	local secs = mceil(left)
	if secs == paintedSecs then return end
	paintedSecs = secs
	btn.Text:SetText(format('%d', secs))
end

-- TAIL RE-ANCHOR, RATIONED
-- A tail-anchored icon used to be re-anchored ten times a second, and every
-- time that walks the EllesmereUI group list to find the bar and resets the
-- points. The points are relative to the bar's edge, so the icon already
-- follows the bar as it grows, shrinks or moves; the one live input that
-- changes WHICH point is used is the bar going empty or filling up again
-- (_acLiveW, read by CDMAnchor the same way). So each tick only reads that
-- one field off the bar found last time and re-anchors at once when it
-- flipped; a full re-anchor, which also catches a different bar or changed
-- group layout, runs at most every ANCHOR_EVERY seconds. Should the width
-- ever read secret, the tick re-anchors every time, as before.
local ANCHOR_EVERY = 0.5
local anchorBar, anchorEmpty
local anchorAt = 0

local function BarEmpty(bar)
	local w = bar._acLiveW
	if secret(w) then return nil end
	if w == nil then return false end
	return w <= 0.5
end

local function ForgetAnchor() anchorBar, anchorEmpty, anchorAt = nil, nil, 0 end

local function Tick()
	local cfg = GetCfg()
	if cfg.durText then PaintText() end
	if frame and TailAnchored(cfg) then
		local now = GetTime()
		local stale = (now - anchorAt) >= ANCHOR_EVERY
		if not stale and anchorBar then
			local empty = BarEmpty(anchorBar)
			stale = empty == nil or empty ~= anchorEmpty
		end
		if stale then
			AnchorToGroup(frame, cfg)
			anchorBar = ResolveGroup(cfg)
			anchorEmpty = anchorBar and BarEmpty(anchorBar)
			anchorAt = now
		end
	end
end

local function SyncUpTicker()
	local cfg = GetCfg()
	local up = Active()
	local want = up and (cfg.durText or TailAnchored(cfg)) and true or false
	if want and not upTicker then
		Tick()
		upTicker = C_Timer.NewTicker(0.1, Tick)
	elseif not want and upTicker then
		StopUpTicker()
	end
end

local function Clear()
	StopHideTimer()
	StopUpTicker()
	expiresAt = 0
	StopGlow()
	paintedSecs = nil
	ForgetAnchor()
	if btn then
		if btn.Cooldown then btn.Cooldown:Clear() end
		if btn.Text then btn.Text:SetText('') end
	end
	if frame then frame:Hide() end
end

local ArmHide, Start
ArmHide = function()
	StopHideTimer()
	local left = expiresAt - GetTime()
	if left <= 0 then Clear() Render() return end
	hideTimer = C_Timer.NewTimer(left + 0.05, function()
		hideTimer = nil
		if preview then Start() return end
		if Active() then ArmHide() return end
		Clear()
		Render()
	end)
end

Start = function()
	EnsureFrame()
	local cfg = GetCfg()
	expiresAt = GetTime() + DURATION
	ApplySettings()
	if btn.Cooldown then
		if cfg.showSwipe ~= false then
			btn.Cooldown:SetCooldown(GetTime(), DURATION)
			btn.Cooldown:Show()
		else
			btn.Cooldown:Clear()
			btn.Cooldown:Hide()
		end
	end
	StopUpTicker()
	ForgetAnchor()
	SyncUpTicker()
	ArmHide()
	Render()
end

ns.BILApply = function()
	local cfg = GetCfg()
	if not preview and (not cfg.enable or not IsSanlaynSpec()) then
		Clear()
		return
	end
	EnsureFrame()
	StopGlow()
	ApplySettings()
	-- The settings may point at another group now; the next tick re-anchors
	-- in full rather than watching the old bar.
	ForgetAnchor()
	SyncUpTicker()
	Render()
end

-- No spec gate here: the page is open on every character, and a gated button
-- did nothing at all outside Blood and Unholy. BILApply already keeps a
-- running preview up on any spec.
ns.BILIsPreview = function() return preview and true or false end
ns.BILSetPreview = function(state)
	preview = state and true or false
	EnsureFrame()
	StopGlow()
	ApplySettings()
	frame:EnableMouse(preview)
	if preview then
		Start()
	else
		Clear()
		Render()
	end
end

local evt = CreateFrame('Frame')
evt:RegisterEvent('PLAYER_ENTERING_WORLD')
evt:RegisterUnitEvent('UNIT_SPELLCAST_SUCCEEDED', 'player')
evt:RegisterUnitEvent('PLAYER_SPECIALIZATION_CHANGED', 'player')
evt:SetScript('OnEvent', function(_, event, _, _, arg3)
	if preview then return end

	if event == 'UNIT_SPELLCAST_SUCCEEDED' then
		if not GetCfg().enable then return end
		-- Spec first: it is one cached class check for anyone not a Death
		-- Knight, where IsTrigger would ask for the base spell of every cast.
		if not IsSanlaynSpec() then return end
		if not IsTrigger(arg3) then return end
		Start()
		return
	end

	if event == 'PLAYER_SPECIALIZATION_CHANGED' then
		Clear()
		if ns.BILApply then ns.BILApply() end
		return
	end

	Clear()
	if ns.BILApply then ns.BILApply() end

	if C_Timer and C_Timer.After then
		C_Timer.After(3, function()
			local cfg = GetCfg()
			if cfg.enable and cfg.euiAnchor and not preview and ns.BILApply then ns.BILApply() end
		end)
	end
end)
