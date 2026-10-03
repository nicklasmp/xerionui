local _, ns = ...
local hooksecurefunc, C_Timer = ns.Probe('EUIPartyHealth', hooksecurefunc, C_Timer)
local _G = _G

local CreateFrame = CreateFrame
local C_Timer = C_Timer
local hooksecurefunc = hooksecurefunc
local ipairs, pairs, pcall, type, tostring = ipairs, pairs, pcall, type, tostring
local setmetatable = setmetatable
local sort = table.sort
local UnitExists = UnitExists
local UnitHealth = UnitHealth
local UnitHealthMax = UnitHealthMax
local UnitGetTotalAbsorbs = UnitGetTotalAbsorbs
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitIsConnected = UnitIsConnected
local secret = ns.IsSecret


local DEFAULTS = {
	enable = false,
	anchor = 'RIGHT',
	offX   = -4,
	offY   = 0,
	size   = 12,
	color  = { 1, 1, 1, 1 },
	byValue = true,
	t1 = 35, t2 = 70, t3 = 100,
	c1 = { 1, 0.25, 0.25, 1 },
	c2 = { 1, 0.82, 0.2, 1 },
	c3 = { 1, 1, 1, 1 },
	c4 = { 0.35, 1, 0.35, 1 },
	debuffStackPlacement = 'BOTTOMRIGHT',
	debuffStackOffsetX = 0,
	debuffStackOffsetY = 0,
}

local function GetCfg() return ns.ModuleCfg('euiPartyHealth', DEFAULTS) end
ns.EPHGetCfg = GetCfg

ns.hasEUIPartyHealth = false

-- One unit of sensor width per percent.
local SPAN = 100
-- Colour sensors: K units per percent, so at a step the digits show two
-- colours for about half a percent (text width / K).
local K = 40
local FAR = K * 300
local BANDS = 4
local WHITE = 'Interface\\Buttons\\WHITE8X8'

local JUSTIFY = { LEFT = 'LEFT', RIGHT = 'RIGHT', CENTER = 'CENTER', TOP = 'CENTER', BOTTOM = 'CENTER' }

local RF
-- Party Interrupts uses EllesmereUI's live unit map to anchor its icon-only
-- variant beside each member's health bar.
ns.EPHGetHealthBar = function(unit)
	local btn = RF and RF._partyUnitToButton and RF._partyUnitToButton[unit]
	-- The unit map is rebuilt by EllesmereUI as the secure header changes. If
	-- this addon runs between that rebuild and the next refresh, resolve the
	-- token directly from the current buttons instead of falling back to screen
	-- coordinates.
	if not btn and RF and RF._partyAllButtons then
		for _, candidate in ipairs(RF._partyAllButtons) do
			local ok, token = pcall(candidate.GetAttribute, candidate, 'unit')
			if ok and token == unit then btn = candidate break end
		end
	end
	if not btn or not RF or type(RF.GetFFD) ~= 'function' then return nil end
	local ok, d = pcall(RF.GetFFD, btn)
	if ok and d and d.health then return d.health end
	return nil
end

-- button -> widget, weak so a discarded button takes its widget with it.
local widgets = setmetatable({}, { __mode = 'k' })
-- Bumped by Apply; a widget lays itself out again when its stamp is behind.
local gen = 0

local function Sensor(parent, width, height)
	local bar = CreateFrame('StatusBar', nil, parent)
	bar:SetStatusBarTexture(WHITE)
	bar:SetStatusBarColor(1, 1, 1, 0) -- geometry only, never drawn
	bar:SetOrientation('HORIZONTAL')
	bar:SetReverseFill(false)
	bar:SetSize(width, height)
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(0)
	return bar
end

-- COLOUR BY VALUE
-- Lua cannot compare the secret total, so the colour is picked by clipping.
-- A second, wider sensor pair starts at the centre of the number, so the end
-- of its absorb fill sits K units right of the number's centre per percent of
-- health + shield. Each step T puts an edge K * T units left of that end: the
-- edge passes the number's centre exactly when the total reaches T. The four
-- clip frames split the plane at those edges and each holds one copy of the
-- number in its colour, so only the copy whose band the total is in shows.
-- `ref` is an unclipped, invisible copy the sensor pair anchors to: the
-- number's centre, without a clip frame anchored to its own child.
local function Build(btn)
	local w = widgets[btn]
	if w then return w end
	local d = RF and RF.GetFFD and RF.GetFFD(btn)
	if not (d and d.health) then return nil end
	-- EllesmereUI's text carrier (name and health text, above every border) when
	-- there is one, so the number sits in the same band as the name.
	local carrier = (d.nameText and d.nameText:GetParent()) or btn
	w = { d = d, clip = {}, text = {} }
	w.host = CreateFrame('Frame', nil, carrier)
	w.host:SetAllPoints(d.health)

	w.hp = Sensor(w.host, SPAN, 1)
	w.hp:SetPoint('TOPLEFT', w.host, 'TOPLEFT', 0, 0)
	w.abs = Sensor(w.host, SPAN, 1)
	w.abs:SetPoint('TOPLEFT', w.hp:GetStatusBarTexture(), 'TOPRIGHT', 0, 0)
	w.span = CreateFrame('Frame', nil, w.host)
	w.span:SetPoint('TOPLEFT', w.hp, 'TOPLEFT', 0, 0)
	w.span:SetPoint('BOTTOMRIGHT', w.abs:GetStatusBarTexture(), 'BOTTOMRIGHT', 0, 0)

	w.ref = w.host:CreateFontString(nil, 'OVERLAY')
	w.ref:SetAlpha(0)
	w.chp = Sensor(w.host, K * SPAN, 200)
	w.chp:SetPoint('LEFT', w.ref, 'CENTER', 0, 0)
	w.cabs = Sensor(w.host, K * SPAN, 200)
	w.cabs:SetPoint('TOPLEFT', w.chp:GetStatusBarTexture(), 'TOPRIGHT', 0, 0)

	for i = 1, BANDS do
		local clip = CreateFrame('Frame', nil, w.host)
		w.clip[i] = clip
		w.text[i] = clip:CreateFontString(nil, 'OVERLAY')
	end
	widgets[btn] = w
	return w
end

local function Tint(fs, c)
	c = c or DEFAULTS.color
	fs:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1, 1)
end

-- The edge for step T, as an offset from the end of the colour fill. Half a
-- percent early, so the colour changes where the rounded number does.
local function Edge(t) return -K * (t - 0.5) end

local function LayoutBands(w, cfg)
	local t = { cfg.t1 or DEFAULTS.t1, cfg.t2 or DEFAULTS.t2, cfg.t3 or DEFAULTS.t3 }
	sort(t)
	local fill = w.cabs:GetStatusBarTexture()
	local c = w.clip
	for i = 1, BANDS do
		c[i]:ClearAllPoints()
		c[i]:SetClipsChildren(true)
		c[i]:Show()
		Tint(w.text[i], cfg['c' .. i])
	end
	c[1]:SetPoint('TOPLEFT', fill, 'TOPRIGHT', Edge(t[1]), 0)
	c[1]:SetPoint('BOTTOMRIGHT', w.chp, 'BOTTOMLEFT', FAR, 0)
	for i = 2, BANDS - 1 do
		c[i]:SetPoint('TOPLEFT', fill, 'TOPRIGHT', Edge(t[i]), 0)
		c[i]:SetPoint('BOTTOMRIGHT', fill, 'BOTTOMRIGHT', Edge(t[i - 1]), 0)
	end
	c[BANDS]:SetPoint('TOPLEFT', w.chp, 'TOPLEFT', -FAR, 0)
	c[BANDS]:SetPoint('BOTTOMRIGHT', fill, 'BOTTOMRIGHT', Edge(t[BANDS - 1]), 0)
end

-- EllesmereUI's name font, outline and shadow, so the number looks like part
-- of the frame; the plugin font when the name text is not there to copy.
local function Layout(w, cfg)
	local nameFS = w.d.nameText
	local path, flags
	if nameFS then
		local ok, p, _, f = pcall(nameFS.GetFont, nameFS)
		if ok and type(p) == 'string' then path, flags = p, f end
	end
	local size = cfg.size or DEFAULTS.size
	local sx, sy, sr, sg, sb, sa = 0, 0, 0, 0, 0, 0
	if nameFS then
		local ok, x, y = pcall(nameFS.GetShadowOffset, nameFS)
		if ok and type(x) == 'number' and type(y) == 'number' then sx, sy = x, y end
		local okC, r, g, b, a = pcall(nameFS.GetShadowColor, nameFS)
		if okC and type(r) == 'number' then sr, sg, sb, sa = r, g or 0, b or 0, a or 1 end
	end
	local a = JUSTIFY[cfg.anchor] and cfg.anchor or DEFAULTS.anchor
	local all = { w.ref, w.text[1], w.text[2], w.text[3], w.text[4] }
	for _, fs in ipairs(all) do
		if not (path and fs:SetFont(path, size, flags or '')) then
			fs:SetFont(ns.GetFont(), size, 'OUTLINE')
		end
		fs:SetShadowOffset(sx, sy)
		fs:SetShadowColor(sr, sg, sb, sa)
		fs:ClearAllPoints()
		fs:SetPoint(a, w.host, a, cfg.offX or 0, cfg.offY or 0)
		fs:SetJustifyH(JUSTIFY[a])
	end

	w.byValue = cfg.byValue and true or false
	if w.byValue then
		LayoutBands(w, cfg)
	else
		local clip = w.clip[1]
		clip:ClearAllPoints()
		clip:SetAllPoints(w.host)
		clip:SetClipsChildren(false)
		clip:Show()
		for i = 2, BANDS do w.clip[i]:Hide() end
		Tint(w.text[1], cfg.color)
		w.ref:SetText('')
	end
end

-- Clean booleans for group units per EllesmereUI; unreadable counts as alive
-- and online, as everywhere else in the plugin.
local function Gone(unit)
	local dead = UnitIsDeadOrGhost(unit)
	if secret(dead) then dead = false end
	local online = UnitIsConnected(unit)
	if secret(online) then online = true end
	return dead or not online
end

local function Feed(w, unit)
	local maxHP, hp, abs = UnitHealthMax(unit), UnitHealth(unit), UnitGetTotalAbsorbs(unit)
	w.hp:SetMinMaxValues(0, maxHP)
	w.hp:SetValue(hp)
	w.abs:SetMinMaxValues(0, maxHP)
	w.abs:SetValue(abs)
	if w.byValue then
		w.chp:SetMinMaxValues(0, maxHP)
		w.chp:SetValue(hp)
		w.cabs:SetMinMaxValues(0, maxHP)
		w.cabs:SetValue(abs)
	end
end

local function Blank(w)
	w.live = false
	w.ref:SetText('')
	for i = 1, BANDS do w.text[i]:SetText('') end
end

local function Read(w)
	if not w.live then return end
	local ok, width = pcall(w.span.GetWidth, w.span)
	if not ok then return end
	local n = 1
	if w.byValue then
		n = BANDS
		pcall(w.ref.SetFormattedText, w.ref, '%.0f', width)
	end
	for i = 1, n do
		pcall(w.text[i].SetFormattedText, w.text[i], '%.0f', width)
	end
end

-- The fill textures may only settle on the next layout pass, so a read made
-- right after Feed can see the old width. Every paint therefore reads the span
-- once, one frame later; a burst of paints in one frame shares that one read.
local dirty = {}
local QueueFlush = ns.Coalesce(function()
	for w in pairs(dirty) do
		dirty[w] = nil
		Read(w)
	end
end)

local function Paint(btn)
	local w = Build(btn)
	if not w then return end
	if w.gen ~= gen then
		w.gen = gen
		Layout(w, GetCfg())
	end
	w.host:Show()
	local unit = btn:GetAttribute('unit')
	if not (unit and UnitExists(unit)) or Gone(unit) or not pcall(Feed, w, unit) then
		Blank(w)
		return
	end
	w.live = true
	dirty[w] = true
	QueueFlush()
end

local watching = false

local function PaintAll()
	local list = watching and RF and RF._partyAllButtons
	if not list then return end
	for _, btn in ipairs(list) do
		if btn:IsVisible() then Paint(btn) end
	end
end

local function HideAll()
	for _, w in pairs(widgets) do
		w.live = false
		w.host:Hide()
	end
end

-- The secure header moves units between buttons on roster changes; EllesmereUI
-- repaints on a zero timer, so this looks twice: next frame and a moment later.
local refreshPending = false
local function DoRefresh()
	refreshPending = false
	PaintAll()
end
local function ScheduleRefresh()
	if refreshPending then return end
	refreshPending = true
	C_Timer.After(0, DoRefresh)
	C_Timer.After(0.5, PaintAll)
end

-- One frame per unit token: five small registrations instead of every
-- nameplate's health and absorb traffic arriving at one handler.
local function OnUnitEvent(_, _, unit)
	local map = RF and RF._partyUnitToButton
	local btn = map and map[unit]
	if btn then Paint(btn) end
end

local UNITS = { 'player', 'party1', 'party2', 'party3', 'party4' }
local UNIT_EVENTS = { 'UNIT_HEALTH', 'UNIT_MAXHEALTH', 'UNIT_ABSORB_AMOUNT_CHANGED', 'UNIT_CONNECTION' }
local watchers = {}
for i = 1, #UNITS do
	local f = CreateFrame('Frame')
	f:SetScript('OnEvent', OnUnitEvent)
	watchers[i] = f
end

local roster = CreateFrame('Frame')
roster:SetScript('OnEvent', ScheduleRefresh)

local function SyncWatch(want)
	if want == watching then return end
	watching = want
	if want then
		for i, f in ipairs(watchers) do
			for _, ev in ipairs(UNIT_EVENTS) do f:RegisterUnitEvent(ev, UNITS[i]) end
		end
		roster:RegisterEvent('GROUP_ROSTER_UPDATE')
		roster:RegisterEvent('PLAYER_ENTERING_WORLD')
	else
		for _, f in ipairs(watchers) do f:UnregisterAllEvents() end
		roster:UnregisterAllEvents()
	end
end

local function Apply()
	gen = gen + 1
	local on = (RF and GetCfg().enable) and true or false
	SyncWatch(on)
	if on then PaintAll() else HideAll() end
end
ns.EPHApply = Apply

-- EllesmereUI's raid-frame aura style currently anchors party debuff stacks
-- at BOTTOMRIGHT. Wrap only the party debuff style callbacks so this addon can
-- offer a placement choice without changing raid frames or Ellesmere settings.
local stackPreview
local function InstallPartyStackStyle(key)
	local eui = _G.EllesmereUI
	local ak = eui and eui.AuraKit
	local style = ak and ak.styles and ak.styles[key]
	if not (style and type(style.applyExtra) == 'function') or style.__xerionPartyStackHook then return false end
	local applyExtra = style.applyExtra
	style.applyExtra = function(button, data, currentStyle)
		applyExtra(button, data, currentStyle)
		local point = GetCfg().debuffStackPlacement or 'BOTTOMRIGHT'
		if point ~= 'BOTTOMRIGHT' and point ~= 'TOPLEFT' and point ~= 'TOP' and point ~= 'TOPRIGHT' then
			point = 'BOTTOMRIGHT'
		end
		if data and data.stack then
			-- Top is an explicit XerionUI override: place the count just above
			-- the debuff icon and ignore EllesmereUI's stack offsets.
			local anchorPoint, relativePoint = point, point
			local cfg = GetCfg()
			local x = (currentStyle.stackOffX or 0) + (cfg.debuffStackOffsetX or 0)
			local y = (currentStyle.stackOffY or 0) + (cfg.debuffStackOffsetY or 0)
			if point == 'TOP' then
				anchorPoint, relativePoint = 'BOTTOM', 'TOP'
				x, y = cfg.debuffStackOffsetX or 0, cfg.debuffStackOffsetY or 0
			end
			-- Reapply after every Ellesmere style pass; it may reset the anchor
			-- even when our saved placement has not changed.
			data.stack:ClearAllPoints()
			data.stack:SetPoint(anchorPoint, button, relativePoint, x, y)
		end
	end
	style.__xerionPartyStackHook = true
	return true
end

local function InstallPartyStackStyles()
	InstallPartyStackStyle('rf:debuff:party')
	InstallPartyStackStyle('rf:debuffcc:party')
end

local function ApplyPartyStackPlacement()
	InstallPartyStackStyles()
	local eui = _G.EllesmereUI
	local ak = eui and eui.AuraKit
	if ak and type(ak.RestyleSoon) == 'function' then
		ak.RestyleSoon('rf:debuff:party')
		ak.RestyleSoon('rf:debuffcc:party')
	end
	if stackPreview then stackPreview:Update() end
end
ns.EPHApplyDebuffStackPlacement = ApplyPartyStackPlacement

-- A small sample debuff anchored over the first visible party frame lets the
-- user judge stack placement even when no real party debuff is active.
local function EnsureStackPreview()
	if stackPreview then return stackPreview end
	local icon = CreateFrame('Frame', nil, UIParent, 'BackdropTemplate')
	icon:SetSize(24, 24)
	icon:SetFrameStrata('HIGH')
	icon:SetFrameLevel(100)
	icon:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
	icon:SetBackdropColor(0.04, 0.04, 0.04, 1)
	icon:SetBackdropBorderColor(0, 0, 0, 1)
	local texture = icon:CreateTexture(nil, 'ARTWORK')
	texture:SetPoint('TOPLEFT', 1, -1)
	texture:SetPoint('BOTTOMRIGHT', -1, 1)
	texture:SetTexture('Interface\\Icons\\Spell_Frost_FrostBolt02')
	local count = icon:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
	count:SetText('5')
	count:SetTextColor(1, 1, 1, 1)
	count:SetShadowColor(0, 0, 0, 1)
	count:SetShadowOffset(1, -1)
	stackPreview = { icon = icon, count = count }
	function stackPreview:Update()
		if not self.active then return end
		local buttons = RF and RF._partyAllButtons
		local target
		if buttons then
			for _, button in ipairs(buttons) do
				if button and button.IsVisible and button:IsVisible() then target = button break end
			end
		end
		if not target then icon:Hide() return end
		icon:ClearAllPoints()
		icon:SetPoint('TOPLEFT', target, 'TOPLEFT', 8, -8)
		local cfg = GetCfg()
		local point = cfg.debuffStackPlacement or 'BOTTOMRIGHT'
		local anchorPoint, relativePoint = point, point
		local x, y = cfg.debuffStackOffsetX or 0, cfg.debuffStackOffsetY or 0
		if point == 'TOP' then anchorPoint, relativePoint = 'BOTTOM', 'TOP' end
		count:ClearAllPoints()
		count:SetPoint(anchorPoint, icon, relativePoint, x, y)
		icon:Show()
	end
	return stackPreview
end

ns.EPHStackPreviewIsOn = function() return stackPreview and stackPreview.active or false end
ns.EPHStackPreviewSet = function(on)
	local preview = EnsureStackPreview()
	preview.active = on and true or false
	if preview.active then
		preview:Update()
		if C_Timer and C_Timer.NewTicker and not preview.ticker then
			preview.ticker = C_Timer.NewTicker(0.5, function() preview:Update() end)
		end
	else
		if preview.ticker then preview.ticker:Cancel() preview.ticker = nil end
		preview.icon:Hide()
	end
end

_G.SLASH_XERIONPARTY1 = '/xerionparty'
_G.SlashCmdList.XERIONPARTY = function()
	local Msg = ns.Msg
	if not RF then
		Msg('Party Health + Shield: NOT active - EllesmereUI Raid Frames namespace not found.')
		return
	end
	local cfg = GetCfg()
	local list = RF._partyAllButtons or {}
	local shown, built = 0, 0
	for _, btn in ipairs(list) do
		if btn:IsVisible() then shown = shown + 1 end
		if widgets[btn] then built = built + 1 end
	end
	Msg(('Party Health + Shield: %s, watching %s | party buttons %d, visible %d, widgets %d | EllesmereUI party frames %s'):format(
		cfg.enable and 'on' or 'off', watching and 'yes' or 'no', #list, shown, built,
		RF._partyFramesVisible and 'shown' or 'hidden'))
	Msg(('colour by value: %s (steps %s / %s / %s)'):format(
		cfg.byValue and 'on' or 'off', tostring(cfg.t1), tostring(cfg.t2), tostring(cfg.t3)))
	local function show(v)
		if secret(v) then return 'secret' end
		return type(v) == 'number' and ('%.1f'):format(v) or tostring(v)
	end
	for _, btn in ipairs(list) do
		local w = widgets[btn]
		if btn:IsVisible() and w then
			local unit = btn:GetAttribute('unit')
			local okW, width = pcall(w.span.GetWidth, w.span)
			local fillTex = w.cabs:GetStatusBarTexture()
			local okF, fillW = pcall(fillTex.GetWidth, fillTex)
			local okH, hp = pcall(UnitHealth, unit)
			local okM, maxHP = pcall(UnitHealthMax, unit)
			local okA, abs = pcall(UnitGetTotalAbsorbs, unit)
			Msg(('  %s: span %s | colour shield fill %s | health %s / %s, absorb %s | text %s'):format(tostring(unit),
				okW and show(width) or 'read failed', okF and show(fillW) or 'read failed',
				okH and show(hp) or '?', okM and show(maxHP) or '?',
				okA and show(abs) or '?', w.live and 'live' or 'blank'))
		end
	end
end

local function Activate()
	if RF then return true end
	local eui = _G.EllesmereUI
	local rf = eui and eui._ModuleNS and eui._ModuleNS.EllesmereUIRaidFrames
	if not (rf and type(rf.GetFFD) == 'function') then return false end
	RF = rf
	ns.hasEUIPartyHealth = true
	InstallPartyStackStyles()
	if type(rf.RFC_SetupButton) == 'function' and not rf._xerionPartyStackSetupHook then
		rf._xerionPartyStackSetupHook = true
		hooksecurefunc(rf, 'RFC_SetupButton', InstallPartyStackStyles)
	end
	if type(rf.RFC_ReloadAll) == 'function' and not rf._xerionPartyStackReloadHook then
		rf._xerionPartyStackReloadHook = true
		hooksecurefunc(rf, 'RFC_ReloadAll', InstallPartyStackStyles)
	end
	if type(rf._RebuildPartyUnitMap) == 'function' then
		hooksecurefunc(rf, '_RebuildPartyUnitMap', function()
			if watching then ScheduleRefresh() end
			if ns.IKApply then C_Timer.After(0, ns.IKApply) end
		end)
	end
	Apply()
	if ns.IKApply then C_Timer.After(0, ns.IKApply) end
	return true
end

local loader = CreateFrame('Frame')
loader:SetScript('OnEvent', function(self, event, arg1)
	if event == 'ADDON_LOADED' and arg1 ~= 'EllesmereUI' and arg1 ~= 'EllesmereUIRaidFrames' then return end
	if Activate() then
		self:UnregisterEvent('ADDON_LOADED')
		if event == 'PLAYER_LOGIN' then Apply() end
	end
end)
loader:RegisterEvent('ADDON_LOADED')
loader:RegisterEvent('PLAYER_LOGIN')

if Activate() then loader:UnregisterEvent('ADDON_LOADED') end
